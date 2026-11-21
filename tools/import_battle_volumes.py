"""Translate the active battle-camera and environment Volume color overrides."""
import argparse
from contextlib import ExitStack
from hashlib import sha256
from math import log10
from pathlib import Path
from struct import pack, unpack

from PIL import Image
from import_balancing import BuildLayouts, read_fields
from import_scenes import Source, quote, vector


LUT_SIZE = 32  # PC_RenderPipelineAsset, globalgamemanagers.assets:6665.
CURVE_SIZE = 128
CURVE_MAX = (CURVE_SIZE - 1) / CURVE_SIZE
LUMA = (0.2126729, 0.7151522, 0.0721750)


def linear(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def white_balance(temperature, tint):
    temperature /= 65
    x = 0.31271 - temperature * (0.1 if temperature < 0 else 0.05)
    y = 2.87 * x - 3 * x * x - 0.27509507 + tint / 65 * 0.05
    xx, zz = x / y, (1 - x - y) / y
    return (0.949237 / (0.7328 * xx + 0.4296 - 0.1624 * zz),
            1.03542 / (-0.7036 * xx + 1.6975 + 0.0061 * zz),
            1.08728 / (0.003 * xx + 0.0136 + 0.9834 * zz))


def active_volumes(source, scene, names):
    objects = scene.objects
    for obj in objects.values():
        if obj.type.name != "MonoBehaviour":
            continue
        head = obj.parse_monobehaviour_head()
        owner = objects.get(head.m_GameObject.m_PathID)
        if owner is None:
            continue
        go = owner.read_typetree()
        if not go["m_IsActive"] or go["m_Name"] not in names or head.m_Script.deref_parse_as_object().m_ClassName != "Volume":
            continue
        fields = read_fields(obj, source.env.typetree_generator)
        if not fields["m_Enabled"] or not fields["m_IsGlobal"] or fields["weight"] != 1:
            continue
        profile_file, profile, overrides = volume_profile(source, scene, fields)
        yield fields["priority"], overrides, f"{scene.name}:{obj.path_id}/{profile_file.name}:{profile.path_id}"


def volume_profile(source, scene, fields):
    layouts = source.env.typetree_generator
    profile_file, profile = source.resolve(scene, fields["sharedProfile"])
    overrides = {}
    for pointer in read_fields(profile, layouts)["components"]:
        _, component = source.resolve(profile_file, pointer)
        data = read_fields(component, layouts)
        if data["active"]:
            kind = component.parse_monobehaviour_head().m_Script.deref_parse_as_object().m_ClassName
            overrides[kind] = {key: v["m_Value"] for key, v in data.items()
                               if isinstance(v, dict) and v.get("m_OverrideState")}
    return profile_file, profile, overrides


def saturate(value):
    return max(0.0, min(1.0, value))


def smoothstep(low, high, value):
    t = saturate((value - low) / (high - low))
    return t * t * (3.0 - 2.0 * t)


def master_samples(master):
    # URP stores TextureCurve in R16_SFloat, sampling Unity's unweighted keys at i/128.
    keys = master["m_Curve"]["m_Curve"]
    if len(keys) < 2 or master["m_Loop"] or any(key["weightedMode"] for key in keys):
        raise ValueError("Unsupported master curve")
    values = []
    span = 0
    for index in range(CURVE_SIZE):
        time = index / CURVE_SIZE
        while span < len(keys) - 2 and time > keys[span + 1]["time"]:
            span += 1
        a, b = keys[span:span + 2]
        width = b["time"] - a["time"]
        t = saturate((time - a["time"]) / width)
        value = ((2 * t - 3) * t * t + 1) * a["value"] + ((t - 2) * t + 1) * t * width * a["outSlope"]
        value += (3 - 2 * t) * t * t * b["value"] + (t - 1) * t * t * width * b["inSlope"]
        values.append(unpack("<e", pack("<e", value))[0])
    return values


def sample_master(samples, value):
    # LutBuilderLdr places i/128 at the center of texel i for both the master
    # curve and the default identity channel curves. The last texel is 127/128.
    index = saturate(value) * CURVE_SIZE
    low = min(int(index), CURVE_SIZE - 1)
    high = min(low + 1, CURVE_SIZE - 1)
    weight = index - low
    return min(saturate(samples[low] + (samples[high] - samples[low]) * weight), CURVE_MAX)


def bake_lut(destination, balance, contrast, saturation, limits, tones, master, defeat_saturation, cache):
    # Stack four 1024x32 strips: field, panel, defeat, and panel with defeat.
    samples = master_samples(master)
    key = (balance, contrast, saturation, limits, tones, tuple(samples), defeat_saturation)
    if key in cache:
        return cache[key]
    strip_bytes = LUT_SIZE ** 3 * 3
    pixels = bytearray(strip_bytes * 4)
    grid = [i / (LUT_SIZE - 1) for i in range(LUT_SIZE)]
    cursor = 0
    for g in grid:
        for b in grid:
            for r in grid:
                l = (0.390405 * r + 0.549941 * g + 0.00892632 * b) * balance[0]
                m = (0.0708416 * r + 0.963172 * g + 0.00135775 * b) * balance[1]
                s = (0.0231082 * r + 0.128021 * g + 0.936245 * b) * balance[2]
                rgb = (2.85847 * l - 1.62879 * m - 0.024891 * s,
                       -0.210182 * l + 1.15820 * m + 0.000324281 * s,
                       -0.041812 * l - 0.118169 * m + 1.06867 * s)
                graded = []
                for value in rgb:
                    # URP uses its fast LogC transform for contrast in the LDR LUT.
                    log_c = 0.244161 * log10(max(1e-20, 5.555556 * value + 0.047996)) + 0.386036
                    log_c = (log_c - 0.4135884) * contrast + 0.4135884
                    graded.append(max(0.0, (10 ** ((log_c - 0.386036) / 0.244161) - 0.047996) / 5.555556))
                luma = sum(value * weight for value, weight in zip(graded, LUMA))
                low = 1.0 - smoothstep(*limits[:2], luma)
                high = smoothstep(*limits[2:], luma)
                rgb = [value * (shadow * low + mid * (1.0 - low - high) + highlight * high)
                       for value, (shadow, mid, highlight) in zip(graded, zip(*tones))]
                luma = sum(value * weight for value, weight in zip(rgb, LUMA))
                for channel, value in enumerate(rgb):
                    normal = luma + (value - luma) * saturation
                    defeat = luma + (value - luma) * defeat_saturation
                    pixels[cursor + channel] = round(saturate(min(normal, CURVE_MAX)) * 255)
                    pixels[cursor + channel + strip_bytes] = round(sample_master(samples, normal) * 255)
                    pixels[cursor + channel + 2 * strip_bytes] = round(saturate(min(defeat, CURVE_MAX)) * 255)
                    pixels[cursor + channel + 3 * strip_bytes] = round(sample_master(samples, defeat) * 255)
                cursor += 3
    name = "grade_" + sha256(pixels).hexdigest()[:12] + ".png"
    folder = destination.parent / "grade_luts"
    folder.mkdir(exist_ok=True)
    path = folder / name
    Image.frombytes("RGB", (LUT_SIZE ** 2, LUT_SIZE * 4), bytes(pixels)).save(path)
    cache[key] = name
    return name


def write_grade(destination, ordered, ssao, master, defeat_saturation, lut_cache):
    parameters = {}
    sources = []
    for _, overrides, binding in sorted(ordered, key=lambda row: row[0]):
        sources.append(binding)
        for kind, fields in overrides.items():
            parameters.setdefault(kind, {}).update(fields)
    tone_mode = parameters.get("Tonemapping", {}).get("mode", 0)
    if tone_mode not in (0, 1):
        raise ValueError("Untranslated tonemapping mode in " + destination.stem)
    adjust = parameters.get("ColorAdjustments", {})
    bloom = parameters.get("Bloom", {})
    white = parameters.get("WhiteBalance", {})
    tone = parameters.get("ShadowsMidtonesHighlights", {})
    vignette = parameters.get("Vignette", {})
    center = vignette.get("center", {"x": 0.5, "y": 0.5})
    color = vignette.get("color", dict.fromkeys("rgb", 0))
    balance = white_balance(white.get("temperature", 0), white.get("tint", 0))
    contrast = 1 + adjust.get("contrast", 0) / 100
    saturation = 1 + adjust.get("saturation", 0) / 100
    limits = (tone.get("shadowsStart", 0), tone.get("shadowsEnd", 0.3),
              tone.get("highlightsStart", 0.55), tone.get("highlightsEnd", 1))
    values = {
        "neutral_tonemap": str(tone_mode == 1).lower(),
        "exposure": 2 ** adjust.get("postExposure", 0),
        "vignette_center": vector("Vector2", center["x"], center["y"]),
        "vignette_color": vector("Vector3", *(color[k] for k in "rgb")),
        "vignette_intensity": 3 * vignette.get("intensity", 0),
        "vignette_smoothness": 5 * vignette.get("smoothness", 0.2),
        "vignette_rounded": str(bool(vignette.get("rounded", False))).lower(),
    }
    tones = []
    for key in ("shadows", "midtones", "highlights"):
        ball = tone.get(key, {"x": 1, "y": 1, "z": 1, "w": 0})
        weight = ball["w"] * (4 if ball["w"] >= 0 else 1)
        tones.append(tuple(max(0, linear(ball[k]) + weight) for k in "xyz"))
    lut = bake_lut(destination, balance, contrast, saturation, limits, tuple(tones), master,
                   defeat_saturation, lut_cache)
    lines = ['[gd_scene format=3]', '',
             '[ext_resource type="Shader" path="res://materials/battle_volume.gdshader" id="1"]',
             f'[ext_resource type="Texture2D" path="res://materials/volumes/grade_luts/{lut}" id="2"]', '',
              '[sub_resource type="Environment" id="WorldEffects"]',
              "ambient_light_source = 1",
              "ssao_enabled = " + str(ssao is not None).lower()]
    if ssao is not None:
        lines.extend([f'ssao_radius = {ssao["Radius"]:.9g}',
                      f'ssao_intensity = {ssao["Intensity"]:.9g}',
                      f'ssao_light_affect = {ssao["DirectLightingStrength"]:.9g}'])
    if bloom.get("intensity", 0) > 0:
        lines.extend(["glow_enabled = true",
                      f'glow_intensity = {bloom["intensity"]:.9g}',
                      # Compatibility filters the sRGB scene buffer.
                      f'glow_hdr_threshold = {bloom.get("threshold", 0.9):.9g}',
                      "glow_hdr_scale = 1.0"])
    lines.extend(['', '[sub_resource type="ShaderMaterial" id="Grade"]',
                  'resource_local_to_scene = true', 'shader = ExtResource("1")',
                  'shader_parameter/grade_lookup = ExtResource("2")'])
    lines.extend(f"shader_parameter/{key} = {value}" for key, value in values.items())
    lines.extend(['', '[node name="BattleVolume" type="CanvasLayer"]', "layer = -1",
                  "metadata/unity_profiles = " + quote(" + ".join(sources))])
    if ssao is not None and uses_environment_ambient_occlusion(ssao):
        ao_settings = vector("Vector4", ssao["Radius"], ssao["Intensity"], ssao["Falloff"],
                             ssao["DirectLightingStrength"])
        lines.append(f"metadata/ambient_occlusion = {ao_settings}")
    if bloom.get("intensity", 0) > 0:
        # Unity 6 URP prepares these parameters before running the HDR passes.
        threshold = linear(bloom.get("threshold", 0.9))
        bloom_filter = vector("Vector4", 0.05 + bloom.get("scatter", 0.7) * 0.9,
                              bloom.get("clamp", 65472), threshold, threshold * 0.5)
        tint = bloom.get("tint", dict.fromkeys("rgb", 1))
        tint_linear = [linear(tint[channel]) for channel in "rgb"]
        luma = sum(value * coefficient for value, coefficient in zip(tint_linear, LUMA))
        tint_normalized = [value / luma for value in tint_linear] if luma > 0 else [1, 1, 1]
        bloom_strength = vector("Vector4", *tint_normalized, bloom["intensity"])
        bloom_quality = vector("Vector3i", int(bloom.get("highQualityFiltering", 0)),
                               1 + bloom.get("downscale", 0), bloom.get("maxIterations", 6))
        lines.extend([f"metadata/bloom_filter = {bloom_filter}", f"metadata/bloom_strength = {bloom_strength}",
                      f"metadata/bloom_quality = {bloom_quality}"])
    lines.extend(['',
                  '[node name="WorldEffects" type="WorldEnvironment" parent="."]',
                  'environment = SubResource("WorldEffects")', '',
                  '[node name="ColorGrade" type="ColorRect" parent="."]', 'material = SubResource("Grade")',
                  'anchor_right = 1.0', 'anchor_bottom = 1.0', 'mouse_filter = 2', ''])
    destination.write_text("\n".join(lines), encoding="utf-8")


def uses_environment_ambient_occlusion(settings):
    # PC uses the full-resolution, eight-tap blue-noise pass with a normals prepass.
    keys = ("AfterOpaque", "Downsample", "Source", "Samples", "BlurQuality", "AOMethod")
    return tuple(settings[key] for key in keys) == (0, 0, 1, 1, 0, 0)


def export_ambient_noise(renderer_file, destination):
    tiles = {}
    for reader in renderer_file.objects.values():
        if reader.type.name != "Texture2D":
            continue
        name = reader.peek_name()
        prefix = "LDR_LLL1_"
        if not name.startswith(prefix) or not name[len(prefix):].isdigit():
            continue
        texture = reader.read()
        if (texture.m_Width, texture.m_Height) == (256, 256):
            tiles[int(name[len(prefix):])] = texture.image.convert("RGBA").getchannel("A")
    if not tiles:
        raise ValueError("The PC AO profile requires serialized 256px blue-noise textures.")
    atlas = Image.new("L", (256, 256 * len(tiles)))
    for row, index in enumerate(sorted(tiles)):
        atlas.paste(tiles[index], (0, 256 * row))
    atlas.save(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    args = parser.parse_args()
    dest = Path(__file__).resolve().parents[1] / "game/materials/volumes"
    dest.mkdir(exist_ok=True)
    with ExitStack() as stack:
        src = Source(args.data, stack)
        for asset in args.data.glob("*.assets"):
            src.file(asset.name)
        build = next(o.read_typetree() for o in src.file("globalgamemanagers").objects.values()
                     if o.type.name == "BuildSettings")
        layouts = BuildLayouts(build["m_Version"])
        layouts.load_local_game(str(args.data.parent))
        src.env.typetree_generator = layouts
        scenes = {Path(p).stem: src.file(f"level{i}") for i, p in enumerate(build["scenes"])}
        base = list(active_volumes(src, scenes["Battle"], {"Global Volume"}))
        # PC_Renderer / ScreenSpaceAmbientOcclusion in Steam build 26551710.
        renderer_file = src.file("globalgamemanagers.assets")
        renderer = read_fields(renderer_file.objects[6668], layouts)
        ssao = None
        for pointer in renderer["m_RendererFeatures"]:
            _, feature = src.resolve(renderer_file, pointer)
            if feature.peek_name() == "ScreenSpaceAmbientOcclusion":
                fields = read_fields(feature, layouts)
                if fields["m_Active"]:
                    ssao = fields["m_Settings"]
        if ssao is not None and uses_environment_ambient_occlusion(ssao):
            export_ambient_noise(renderer_file, dest.parent / "battle_ambient_noise.png")
        # The defeat background enables Volume 32861 only while the result is visible.
        battle = scenes["Battle"]
        _, _, defeat = volume_profile(src, battle, read_fields(battle.objects[32861], layouts))
        _, _, panel = volume_profile(src, battle, read_fields(battle.objects[33369], layouts))
        defeat_saturation = 1 + defeat["ColorAdjustments"]["saturation"] / 100
        master = panel["ColorCurves"]["master"]
        lut_cache = {}
        for name, scene in scenes.items():
            if name.startswith("Environment_"):
                local = list(active_volumes(src, scene, {"LocalVolume", "PostProcessing"}))
                write_grade(dest / (name + ".tscn"), base + local, ssao, master, defeat_saturation, lut_cache)
                print(name, [v[2] for v in base + local])


if __name__ == "__main__":
    main()
