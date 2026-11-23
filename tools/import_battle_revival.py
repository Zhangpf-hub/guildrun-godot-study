"""Import the demo's revival prefabs or supported layers of Yuna's action effects."""
import argparse
from contextlib import ExitStack
import math
import traceback
from pathlib import Path

from import_balancing import BuildLayouts, read_fields
from import_scenes import Source, material_texture, mesh_asset, particle_range, quote, source_mip_texture, texture_transform, vector


STEPS = 64

# Emission time, age at emission, and Custom1.x from Wave_01 with Unity seed 6457.
YUNA_FLIGHT_WAVE_BIRTHS = (
    (0.0, 0.60, 21.281950),
    (0.0, 0.40, 63.763450),
    (0.0, 0.20, 74.239500),
    (0.0, 0.0, 0.733895),
    (0.0, 0.0, 24.176120),
    (0.20, 0.0, 56.917670),
)

# Cone offsets for Glow_01 at seed 6457. The first three are present at activation.
YUNA_FLIGHT_GLOW_OFFSETS = (
    (0.07925109, 0.23075590),
    (0.23951730, 0.15720500),
    (-0.13826470, 0.16634300),
    (0.14369510, -0.05710463),
    (0.16132870, -0.10111850),
    (0.18601410, 0.12206310),
    (0.23367090, 0.16966900),
    (0.12952330, 0.23450650),
    (0.12129930, 0.14213990),
    (-0.13144390, -0.18355080),
    (-0.27470340, 0.07025955),
    (0.13159680, -0.20246110),
    (0.10307640, -0.06615592),
    (0.02067764, 0.03164482),
    (-0.02070851, 0.10039270),
    (-0.12683930, -0.24914100),
)

# Local position, velocity, size, lifetime and roll from Unity seed 3964.
YUNA_IMPACT_SMOKE_BIRTHS = (
    (
        ((-0.1418939, 0.0, 0.4568362), (-0.0336070, 0.2539590, 0.1081998), 1.0391630, 1.9660990, 356.9663),
        ((-0.4465384, 0.0, 0.0701880), (-0.5738385, 1.3779340, 0.0901974), 2.7247460, 1.9268440, 178.5430),
        ((0.0209422, 0.0, 0.0114587), (0.0215879, 1.1053160, 0.0118121), 2.8851600, 1.6005120, 294.9198),
        ((0.0643547, 0.0, -0.1066389), (0.0862366, 1.4368420, -0.1428983), 2.4591570, 1.6244460, 213.0840),
        ((0.0483610, 0.0, -0.0039756), (0.0629862, 1.3965210, -0.0051778), 3.3108750, 1.8728560, 331.6636),
    ),
    (
        ((0.1020786, 0.0, 0.4299753), (0.0648705, 0.6814122, 0.2732473), 3.4771520, 1.6882570, 343.9323),
        ((-0.2922704, 0.0, 0.3086982), (-0.1765523, 0.6477182, 0.1864759), 3.2243010, 1.6045380, 358.2908),
        ((-0.0992735, 0.0, -0.2185507), (-0.1215149, 1.3124830, -0.2675152), 2.1730330, 1.9859220, 216.5896),
        ((-0.3282863, 0.0, -0.0095944), (-0.4004100, 1.3078250, -0.0117022), 1.1889780, 1.8550690, 260.7342),
        ((-0.3000292, 0.0, -0.0865027), (-0.4432132, 1.5839690, -0.1277845), 2.7708760, 1.9610500, 324.7446),
    ),
)


def keyframe_value(keys, time):
    for left, right in zip(keys, keys[1:]):
        if time <= right["time"]:
            span = right["time"] - left["time"]
            t = max(0.0, (time - left["time"]) / span)
            t2, t3 = t * t, t * t * t
            return ((2 * t3 - 3 * t2 + 1) * left["value"] + (t3 - 2 * t2 + t) * span * left["outSlope"]
                    + (-2 * t3 + 3 * t2) * right["value"] + (t3 - t2) * span * right["inSlope"])
    return keys[-1]["value"]


def samples(curve, minimum=False):
    if curve is None:
        return [1.0]
    state = curve["minMaxState"]
    if state in (0, 3):
        return [curve["minScalar"] if state == 3 and minimum else curve["scalar"]]
    side = "minCurve" if state == 2 and minimum else "maxCurve"
    keys = curve[side]["m_Curve"]
    return [keyframe_value(keys, step / STEPS) * curve["scalar"] for step in range(STEPS + 1)]


def integrated(curve, default):
    values = samples(curve) if curve is not None else [default]
    if len(values) == 1:
        return [0.0, values[0]]
    totals = [0.0]
    for left, right in zip(values, values[1:]):
        totals.append(totals[-1] + (left + right) / (2 * STEPS))
    return totals


def opacity(module, field):
    gradient = module[field]["maxGradient"]
    keys = [(gradient[f"atime{i}"] / 65535, gradient[f"key{i}"]["a"])
            for i in range(gradient["m_NumAlphaKeys"])]
    if not keys:
        return [1.0]
    values = []
    for step in range(STEPS + 1):
        time = step / STEPS
        for (start, left), (end, right) in zip(keys, keys[1:]):
            if time <= end and end > start:
                values.append(left + (right - left) * max(0.0, (time - start) / (end - start)))
                break
        else:
            values.append(keys[-1][1])
    return values


def xyz(point, signs=(1, 1, -1)):
    return vector("Vector3", *(point[k] * sign for k, sign in zip("xyz", signs)))


def uniform_hierarchy_scale(src, owner, transform):
    scale = 1.0
    while True:
        local = transform["m_LocalScale"]
        assert all(math.isclose(local["x"], local[axis], rel_tol=1e-6) for axis in "yz")
        scale *= local["x"]
        parent = transform["m_Father"]
        if not parent["m_PathID"]:
            return scale
        owner, reader = src.resolve(owner, parent)
        transform = reader.read_typetree()


def profile_literal(profile):
    values = (str(v).lower() if isinstance(v, bool) else format(v, ".9g") if isinstance(v, (float, int)) else v
              for v in profile.values())
    return "{\n" + ",\n".join(f'{quote(key)}: {value}' for key, value in zip(profile, values)) + "\n}"


def gradient_at(gradient, progress):
    def channel_value(channel, count, prefix):
        keys = [(gradient[f"{prefix}time{i}"] / 65535, gradient[f"key{i}"][channel]) for i in range(count)]
        for (start, left), (end, right) in zip(keys, keys[1:]):
            if progress <= end and end > start:
                return left + (right - left) * max(0.0, (progress - start) / (end - start))
        return keys[-1][1]

    assert gradient["m_Mode"] == 0
    return (*(channel_value(channel, gradient["m_NumColorKeys"], "c") for channel in "rgb"),
            channel_value("a", gradient["m_NumAlphaKeys"], "a"))


def sampled_gradient(module, field):
    gradient = module[field]["maxGradient"]
    return vector("PackedColorArray", *(v for step in range(STEPS + 1) for v in gradient_at(gradient, step / STEPS)))


def burst_profile(data, burst):
    assert burst["cycleCount"] > 0 and burst["probability"] == 1.0
    count = sorted(particle_range(burst["countCurve"]))
    return {"count": vector("Vector2i", *(int(v) for v in count)),
            "delay": data["startDelay"]["scalar"] + burst["time"],
            "repeat_count": burst["cycleCount"], "repeat_interval": burst["repeatInterval"]}


def impact_smoke_birth_profiles(birth, scale):
    assert birth["count"] == "Vector2i(5, 5)" and birth["repeat_count"] == len(YUNA_IMPACT_SMOKE_BIRTHS)
    for cycle, samples in enumerate(YUNA_IMPACT_SMOKE_BIRTHS):
        delay = birth["delay"] + cycle * birth["repeat_interval"]
        for origin, velocity, width, lifetime, roll in samples:
            angle = math.radians(roll)
            yield {"count": "Vector2i(1, 1)", "repeat_count": 1, "delay": delay,
                   "width": vector("Vector2", width, width), "lifetime": vector("Vector2", lifetime, lifetime),
                   "roll": vector("Vector2", angle, angle),
                   "initial_position": vector("Vector3", origin[0] * scale, origin[1] * scale, -origin[2] * scale),
                   "initial_velocity": vector("Vector3", velocity[0] * scale, velocity[1] * scale, -velocity[2] * scale)}


def linear_material_channel(value):
    # Unity's non-HDR Color upload uses a power of 2.2 above the sRGB display range.
    if value > 1.0:
        return value ** 2.2
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def slash_atlas(src, owner, pointer, game):
    texture_owner, reader = src.resolve(owner, pointer)
    texture = reader.read()
    size = texture.m_Width
    levels = texture.m_MipCount
    assert texture.m_TextureFormat == 10 and texture.m_ColorSpace == 1  # Unity DXT1 and sRGB.
    assert size == texture.m_Height and size & (size - 1) == 0 and levels == size.bit_length()
    return source_mip_texture(texture_owner, reader.path_id, texture, game)


def add_material(src, owner, reader, trail, game, resource, lines, skill=False, linearize_vertex_tint=False):
    # Keep scalar uniforms as float literals, including whole-number values.
    material = reader.read_typetree()
    props = material["m_SavedProperties"]
    floats, maps = dict(props["m_Floats"]), dict(props["m_TexEnvs"])
    colors = dict(props["m_Colors"])
    _, shader = src.resolve(owner, material["m_Shader"])
    atlas_shader = shader.path_id == 3022
    custom_dissolve = False
    mixed_dissolve = False
    name = f"Material{reader.path_id}"
    if shader.path_id in (723, 743, 748, 762):
        # Approximate the Sine VFX surface using the shipped noise, mask and color ramp.
        image, ramp = {723: ("_MainTex", "_RampFire"), 743: ("_Mask", "_Ramp"),
                       748: ("_NoiseTest", "_Ramp"), 762: ("_MainTex", "_RampSmoke")}[shader.path_id]
        lines.extend([f'[sub_resource type="ShaderMaterial" id="{name}"]',
                      'shader = ' + resource("Shader", "materials/revival_particle.gdshader"),
                      'shader_parameter/use_ramp = true',
                      'shader_parameter/use_rgb = true',
                      f'shader_parameter/intensity = {float(floats.get("_FinalPower", floats.get("_FirePower", 1.0)))}'])
        for uniform, field in (("image", image), ("ramp", ramp)):
            path, _ = material_texture(src, owner, maps[field]["m_Texture"], game)
            lines.append(f"shader_parameter/{uniform}_texture = " + resource("Texture2D", path))
        if shader.path_id in (723, 762):
            lines.extend(["shader_parameter/opacity_from_red = true",
                          "shader_parameter/age_sheet_rows = 4.0",
                          f'shader_parameter/opacity_gain = {float(floats["_OpacityBoost"])}'])
        if shader.path_id == 748:
            lines.append(f'shader_parameter/edge_power = {float(floats["_OpacityPower"])}')
        if shader.path_id == 743:
            lines.append("shader_parameter/rim_power = 2.0")
        lines.append("")
        return f'SubResource("{name}")', atlas_shader, custom_dissolve
    if shader.path_id in (3008, 3034):
        path = slash_atlas(src, owner, maps["Main_tex"]["m_Texture"], game)
        additive = shader.path_id == 3034
        depth_toggle = "Boolean_7846239A" if additive else "Boolean_BE6D81B9"
        lines.extend([f'[sub_resource type="ShaderMaterial" id="{name}"]',
                      'shader = ' + resource("Shader", "materials/yuna_basic_slash.gdshader"),
                      'shader_parameter/image_texture = ' + resource("Texture2D", path),
                      f'shader_parameter/additive = {str(additive).lower()}',
                      f'shader_parameter/depth_fade = {str(bool(floats[depth_toggle])).lower()}'])
        if additive:
            intensity = floats["Vector1_ba2f839299ad461eb6b76fbb90d387aa"]
            lines.append(f"shader_parameter/intensity = {float(intensity)}")
        lines.append("")
        return f'SubResource("{name}")', atlas_shader, custom_dissolve
    if shader.path_id == 3048:
        assert material["m_ValidKeywords"] == ["_SURFACE_TYPE_TRANSPARENT"]
        assert floats["_SrcBlend"] == 5 and floats["_DstBlend"] == 1
        lines.extend([f'[sub_resource type="ShaderMaterial" id="{name}"]',
                      'shader = ' + resource("Shader", "materials/yuna_distorted_aura.gdshader")])
        srgb = []
        for uniform, field in (("image", "_MainTex"), ("mask", "_Mask"), ("warp", "_DistortionTexture"),
                               ("noise", "_DissolveTexture")):
            pointer = maps[field]["m_Texture"]
            if not pointer["m_PathID"]:
                srgb.append(0.0)
                continue
            path, texture = material_texture(src, owner, pointer, game)
            lines.append(f"shader_parameter/{uniform}_texture = " + resource("Texture2D", path))
            srgb.append(float(texture.read().m_ColorSpace == 1))
        lines.append("shader_parameter/texture_srgb = " + vector("Vector4", *srgb))
        for prefix, native in (("image", "_MainTex"), ("warp", "_Distortion"), ("noise", "_Dissolve")):
            for field in ("Speed", "Tiling"):
                value = colors[f"{native}{field}"]
                lines.append(f"shader_parameter/{prefix}_{field.lower()} = " + vector("Vector2", value["r"], value["g"]))
        for field, native in (("warp_amount", "_DistortionAmount"), ("noise_exponent", "_DissolveAmount"),
                              ("soft_depth", "_SoftParticles"), ("intersection_depth", "_IntersectionDepth")):
            lines.append(f"shader_parameter/{field} = {float(floats[native])}")
        for field, native in (("aura_tint", "_Color"), ("intersection_tint", "_IntersectionColor")):
            lines.append(f"shader_parameter/{field} = " + vector("Vector4", *(colors[native][key] for key in "rgba")))
        lines.append("")
        return f'SubResource("{name}")', atlas_shader, custom_dissolve
    if shader.path_id == 3045:
        # The unnamed unlit pass blends the front-facing Fresnel rim over the mesh fill.
        assert reader.path_id == 335 and not material["m_ValidKeywords"]
        assert all(not maps[field]["m_Texture"]["m_PathID"] for field in ("_MainTex", "_Noise", "_Flow", "_Mask"))
        assert floats["_Addnoise"] == floats["_Useonlycolor"] == 0 and floats["_Texturesopacity"] == 1
        tint = colors["_Color"]
        linear_tint = vector("Vector4", *(linear_material_channel(tint[channel]) for channel in "rgb"), tint["a"])
        lines.extend([f'[sub_resource type="ShaderMaterial" id="{name}"]',
                      'shader = ' + resource("Shader", "materials/yuna_shuriken_fresnel.gdshader"),
                      "shader_parameter/tint = " + linear_tint,
                      f'shader_parameter/emission_strength = {float(floats["_Emission"])}',
                      f'shader_parameter/fresnel_scale = {float(floats["_Fresnelscale"])}',
                      f'shader_parameter/fresnel_power = {float(floats["_Fresnelpower"])}', ""])
        return f'SubResource("{name}")', atlas_shader, custom_dissolve
    if shader.path_id == 712:
        assert reader.path_id == 331
        assert set(material["m_ValidKeywords"]) == {
            "_DISSOLVETEXTURERADIAL_ON", "_DISTORTIONENABLED_ON", "_NOISE01RADIAL_ON",
            "_RAMPENABLED_ON", "_SOFTPARTICLESENABLED_ON"}
        assert all(not maps[field]["m_Texture"]["m_PathID"] for field in
                   ("_SecondMask", "_SecondMaskProfile", "_CustomColorMask"))
        assert floats["_DissolveGlowAmount"] == 0 and floats["_DissolveMaskSteepness"] >= 0
        lines.extend([f'[sub_resource type="ShaderMaterial" id="{name}"]',
                      'shader = ' + resource("Shader", "materials/yuna_charge_flare.gdshader")])
        for uniform, field in (("main_mask", "_MainMask"), ("radial_noise", "_Noise01"),
                               ("distortion", "_Distortion"), ("distortion_mask", "_DistortionMask"),
                               ("color_ramp", "_Ramp")):
            slot = maps[field]
            assert texture_transform(slot) == "Vector4(1, 1, 0, 0)"
            path, texture = material_texture(src, owner, slot["m_Texture"], game)
            assert texture.read().m_ColorSpace == 1
            lines.append(f"shader_parameter/{uniform} = " + resource("Texture2D", path))
        for uniform, field in (("distortion_power", "_DistortionPower"), ("noise_bias", "_Noise01Negate"),
                               ("opacity_power", "_FinalOpacityPower"), ("opacity_exponent", "_FinalOpacityExp"),
                               ("color_power", "_FinalPower"), ("ramp_bias", "_RampAdd"),
                               ("ramp_dynamics", "_RampAffectedByDynamics"), ("custom_mask_mix", "_CustomColorMaskSwitch"),
                               ("fade_distance", "_SoftParticlesDistance")):
            lines.append(f"shader_parameter/{uniform} = {float(floats[field])}")
        for uniform, field in (("distortion_scroll", "_DistortionScrollSpeed"), ("noise_scroll", "_Noise01ScrollSpeed")):
            lines.append(f"shader_parameter/{uniform} = " + vector("Vector2", floats[field + "U"], floats[field + "V"]))
        lines.extend(["shader_parameter/ramp_tint = " + vector("Color", *(colors["_RampColorTint"][k] for k in "rgba")), ""])
        return f'SubResource("{name}")', atlas_shader, custom_dissolve
    if shader.path_id == 3027:
        assert reader.path_id == 361 and material["m_ValidKeywords"] == ["_RAMPENABLED_ON"]
        assert all(floats[field] == 1 for field in ("_Emission_VS_Enabled", "_Time_VS_Enabled",
                   "_Random_Time_Offset", "_Dissolve_Mask_Enabled", "_Dissolve_Mask_Simple",
                   "_DISSOLVETEXTUREFLIP", "_FinalOpacityPower"))
        assert all(floats[field] == 0 for field in ("_Dissolve_Use_Flow_Texture", "_Dissolve_Mask_Flip",
                   "_Dissolve_Simple_Enabled", "_Dissolve_Scroll_Speed", "_Distortion_Mask_Enabled", "_Global_Mask_Enabled",
                   "_Horizontal_Mask_Enabled", "_Flip_UV_Direction"))
        assert colors["_Distortion_Scroll_Speed"]["r"] == colors["_Distortion_Scroll_Speed"]["g"] == 0
        lines.extend([f'[sub_resource type="ShaderMaterial" id="{name}"]',
                      'shader = ' + resource("Shader", "materials/yuna_flight_wave.gdshader")])
        for uniform, field in (("main_texture", "_MainTex"), ("flow_texture", "_Flow_Texture_2"),
                               ("dissolve_texture", "_DissolveTexture"),
                               ("distortion_normal", "_Distortion_Normal")):
            slot = maps[field]
            assert texture_transform(slot) == "Vector4(1, 1, 0, 0)"
            path, texture = material_texture(src, owner, slot["m_Texture"], game)
            assert texture.read().m_ColorSpace == int(uniform != "distortion_normal")
            lines.append(f"shader_parameter/{uniform} = " + resource("Texture2D", path))
        for uniform, field in (("uv_turns", "_Final_UV_Rotation"), ("final_uv_scale", "_Final_UV_U_Scale"),
                               ("main_scale", "_Flow_Scale_U"),
                               ("main_scroll", "_Flow_Scroll_Speed"), ("flow_scale", "_Flow_Texture_2_Scale_U"),
                               ("flow_scroll", "_Flow_Texture_2_Scroll_Speed"), ("flow_exponent", "_Flow_Curve_Exp"),
                               ("flow_bias", "_Flow_Texture_2_Negate"), ("distortion_amount", "_Distortion_Amount"),
                               ("dissolve_distortion", "_Distortion_Dissolve_Amount"),
                               ("dissolve_steepness", "_Dissolve_Mask_Steepness"),
                               ("dissolve_softness", "_Dissolve_Smooth_Steepness"),
                               ("opacity_exponent", "_Final_Opacity_Exp_Reversed")):
            lines.append(f"shader_parameter/{uniform} = {float(floats[field])}")
        scale = colors["_Distortion_UV_Scale"]
        dissolve_scale = colors["_Dissolve_Texture_Scale"]
        lines.extend(["shader_parameter/distortion_scale = " + vector("Vector2", scale["r"], scale["g"]),
                      "shader_parameter/dissolve_scale = " + vector("Vector2", dissolve_scale["r"], dissolve_scale["g"]),
                      "shader_parameter/flow_fade_in = " + vector("Vector2", floats["_Flow_Mask_SS11"], floats["_Flow_Mask_SS12"]),
                      "shader_parameter/flow_fade_out = " + vector("Vector2", floats["_Flow_Mask_SS21"], floats["_Flow_Mask_SS22"]), ""])
        return f'SubResource("{name}")', atlas_shader, custom_dissolve
    ab_shader = shader.path_id == 3031
    # Funke's aura uses the same texture inputs but a different distortion graph.
    if shader.path_id not in (707, 711, 2989, 2996, 3007, 3022, 3031):
        raise ValueError(f"Unhandled particle shader {shader.path_id}")
    intensity = 1 + floats["_AddIntensity"] if atlas_shader else floats.get("_ColorIntensity", floats.get("_Emission", 1.0))
    lines.extend([f'[sub_resource type="ShaderMaterial" id="{name}"]',
                  'shader = ' + resource("Shader", "materials/revival_particle.gdshader"),
                  f'shader_parameter/intensity = {float(intensity)}',
                  f'shader_parameter/additive = {str(floats.get("_DstBlend") == 1).lower()}'])
    if ab_shader:
        # GAP_SG/AB_Unlit uses the transparent forward pass and unconverted particle vertex colors.
        assert material["m_ValidKeywords"] == ["_SURFACE_TYPE_TRANSPARENT"]
        assert (floats["_SrcBlend"], floats["_DstBlend"], floats["_ZWrite"]) == (5, 10, 0)
        assert floats.get("_ColorMode", 0) == floats["_AlphaClip"] == 0
        if colors["_Color"] != dict.fromkeys("rgba", 1.0):
            lines.append("shader_parameter/material_tint = " + vector("Vector4", *(colors["_Color"][k] for k in "rgba")))
        # The forward fragment program multiplies the depth gap by _SoftParticle.
        # The serialized _SoftParticleFadeParams belongs to a different shader.
        assert floats["_SoftParticle"] > 0
        lines.append(f'shader_parameter/fade_distance = {1 / floats["_SoftParticle"]}')
    elif "_DEPTHFADE" in material["m_ValidKeywords"]:
        if atlas_shader:
            scale = floats["_DepthFadeDistance"] / floats["_DepthFadeMax"]
            lines.append(f"shader_parameter/raw_depth_fade = {float(scale)}")
        else:
            lines.append(f'shader_parameter/fade_distance = {float(floats["_FadeDistance"])}')
    image = "_BaseTexture" if atlas_shader else "_MainTex" if "_MainTex" in maps else "_Mask"
    use_rgb = atlas_shader or shader.path_id in (2989, 3007, 3031) or bool(floats.get("_UseTexColor"))
    lines.append(f"shader_parameter/use_rgb = {str(use_rgb).lower()}")
    bindings = {"image": image, "mask": "_MaskTex"}
    if skill and not floats.get("_MaskMainTex"):
        bindings.pop("mask")
    if atlas_shader:
        assert set(material["m_ValidKeywords"]) <= {
            "_SURFACE_TYPE_TRANSPARENT", "_BUILTIN_SURFACE_TYPE_TRANSPARENT", "_DEPTHFADE",
            "_EDGEFADE", "_LUT", "_USEMASK"}
        if "_USEMASK" in material["m_ValidKeywords"]:
            bindings["mask"] = "_MaskTexture"
        if "_LUT" in material["m_ValidKeywords"]:
            bindings["ramp"] = "_RampTexture"
    if shader.path_id == 2989:
        bindings.update(mask="_Mask", noise="_Noise", flow="_Flow")
        speed = colors["_SpeedMainTexUVNoiseZW"]
        flow = colors["_DistortionSpeedXYPowerZ"]
        lines.extend(["shader_parameter/flow_graph = true",
                      "shader_parameter/image_scroll = " + vector("Vector2", speed["r"], -speed["g"]),
                      "shader_parameter/noise_scroll = " + vector("Vector2", speed["b"], -speed["a"]),
                      "shader_parameter/flow_scroll = " + vector("Vector2", flow["r"], -flow["g"]),
                      f'shader_parameter/flow_strength = {float(flow["b"])}'])
        if floats["_Usedepth"]:
            lines.append(f'shader_parameter/fade_distance = {float(floats["_Depthpower"])}')
    lifetime_dissolve = owner.name == "sharedassets1.assets" and reader.path_id in (498, 499)
    if skill and floats.get("_Dissolve") and not lifetime_dissolve:
        white_default_dissolve = owner.name == "sharedassets1.assets" and reader.path_id in (334, 354)
        if maps["_DissolveTex"]["m_Texture"]["m_PathID"] or white_default_dissolve:
            custom_dissolve = True
            bindings["noise"] = "_DissolveTex"
            lines.append("shader_parameter/custom_dissolve = true")
            if floats.get("_MixDissolve"):
                mixed_dissolve = True
                bindings["dissolve_mask"] = "_Dissolve2Tex"
                lines.append(f'shader_parameter/dissolve_mix = {float(floats["_MixAmount"])}')
            if floats.get("_DissolveSmoothness"):
                lines.append(f'shader_parameter/custom_dissolve_softness = {float(floats["_DissolveSmoothness"])}')
        else:
            # The other untextured dissolve materials still use the existing approximation.
            assert not maps["_Dissolve2Tex"]["m_Texture"]["m_PathID"] and floats["_DissolveSmoothness"] == 0
    elif floats.get("_Dissolve"):
        bindings["noise"] = "_DissolveTex"
        lines.extend([f'shader_parameter/dissolve_amount = {float(floats.get("_DissolveAmount", 1.0))}',
                      f'shader_parameter/dissolve_softness = {float(floats.get("_DissolveSmoothness", 0.1))}',
                      "shader_parameter/noise_scroll = " + vector("Vector2", floats.get("_Dissolve_X_Spd", 0),
                                                                 -floats.get("_Dissolve_Y_Spd", 0))])
    if trail:
        lines.append("shader_parameter/vertex_tint = true")
        if linearize_vertex_tint:
            lines.append("shader_parameter/linearize_vertex_tint = true")
    for uniform, field in bindings.items():
        slot = maps.get(field)
        if not slot or not slot["m_Texture"]["m_PathID"]:
            continue
        impact_mips = (skill and uniform == "image" and owner.name == "sharedassets1.assets"
                       and reader.path_id in (334, 356))
        if impact_mips:
            texture_owner, texture = src.resolve(owner, slot["m_Texture"])
            image = texture.read()
            sampler = image.m_TextureSettings
            assert sampler.m_FilterMode == 1 and sampler.m_WrapU == sampler.m_WrapV == 0
            assert sampler.m_Aniso == 1 and sampler.m_MipBias == 0
            assert image.m_MipCount == max(image.m_Width, image.m_Height).bit_length()
            path = source_mip_texture(texture_owner, texture.path_id, image, game)
            lines.extend(["shader_parameter/source_mip_image = " + resource("Texture2D", path),
                          "shader_parameter/image_uv = " + texture_transform(slot),
                          "shader_parameter/use_source_mip_image = true"])
            continue
        path, texture = material_texture(src, owner, slot["m_Texture"], game)
        uv = texture_transform(slot)
        sampler = uniform + "_texture"
        if uniform == "dissolve_mask":
            sampler_settings = texture.read().m_TextureSettings
            if sampler_settings.m_WrapU == sampler_settings.m_WrapV == 0:
                sampler = "repeating_dissolve_mask_texture"
                lines.append("shader_parameter/repeat_dissolve_mask = true")
            else:
                assert sampler_settings.m_WrapU == sampler_settings.m_WrapV == 1
        if uniform == "ramp":
            lines.append("shader_parameter/use_ramp = true")
        if atlas_shader and uniform == "image":
            assert uv == "Vector4(1, 1, 0, 0)"
            tiling, offset, scroll = (colors[k] for k in ("_Tiling", "_InitOffset", "_ScrollSpeed"))
            assert trail or all(colors["_Offset"][axis] == 0 for axis in "rg")
            uv = vector("Vector4", tiling["r"], tiling["g"], offset["r"], 1 - tiling["g"] - offset["g"])
            if scroll["r"] or scroll["g"]:
                settings = texture.read().m_TextureSettings
                assert settings.m_WrapU == settings.m_WrapV == 0
                sampler = "repeating_image_texture"
                lines.extend(["shader_parameter/scroll_atlas = true",
                              "shader_parameter/atlas_scroll = " + vector("Vector2", scroll["r"], -scroll["g"])])
        lines.extend([f"shader_parameter/{sampler} = " + resource("Texture2D", path),
                      f"shader_parameter/{uniform}_uv = {uv}"])
        if uniform == "image" and texture.read().m_ColorSpace == 1:
            lines.append("shader_parameter/image_is_srgb = true")
        if uniform == "noise" and custom_dissolve and texture.read().m_ColorSpace == 1:
            lines.append("shader_parameter/dissolve_is_srgb = true")
        if mixed_dissolve and uniform in ("mask", "dissolve_mask") and texture.read().m_ColorSpace == 1:
            lines.append(f"shader_parameter/{uniform}_is_srgb = true")
    if mixed_dissolve:
        lines.append("shader_parameter/atlas_mask_uv = true")
    lines.append("")
    return f'SubResource("{name}")', atlas_shader, custom_dissolve


def particle_profile(data, renderer, mesh, material, atlas_shader, custom_dissolve, skill, scale, effect_duration,
                     ribbon_only=False, scale_with_action=False, emit_on_enable=False, flare_scale=None, flow_wave=False,
                     effect_delay=0.0, projectile_contact_time=None, baked_view_billboard=None, presentation_offset=0.0,
                     baked_smoke_scale=None, baked_flight_glow=False, unity_layer=0, hit_dark_blend=False,
                     projectile=False, presentation_scale=1.0):
    initial, shape = data["InitialModule"], data["ShapeModule"]
    size, color = data["SizeModule"], data["ColorModule"]
    velocity, trail = data["VelocityModule"], data["TrailModule"]
    rotation = data["RotationModule"]
    emission = data["EmissionModule"]
    distance_rate = emission["rateOverDistance"]["scalar"]
    bursts = emission["m_Bursts"][:emission["m_BurstCount"]]
    tracked_ribbon = ribbon_only and data["moveWithTransform"] == 0
    simulation_speed = data["simulationSpeed"]
    assert simulation_speed > 0
    births = [burst_profile(data, burst) for burst in bursts]
    rate = emission["rateOverTime"]["scalar"]
    starts_active = skill and emit_on_enable and data["looping"] and rate > 0 and effect_delay > 0
    if skill and rate > 0:
        assert emission["rateOverTime"]["minMaxState"] in (0, 1) and data["startDelay"]["minMaxState"] == 0
        start = data["startDelay"]["scalar"]
        length = effect_duration * simulation_speed - start
        if starts_active:
            # Play restarts the burst cycle, while the continuous emission clock keeps running.
            assert start == 0 and not scale_with_action
            playback = effect_delay * simulation_speed
            length += playback
            period = data["lengthInSec"]
            for birth in births.copy():
                assert birth["delay"] == 0 and birth["repeat_count"] == 1
                birth.update(repeat_count=math.ceil(playback / period), repeat_interval=period)
                births.append({**birth, "delay": playback,
                               "repeat_count": math.ceil(effect_duration * simulation_speed / period)})
            if data["prewarm"]:
                assert not bursts and initial["startLifetime"]["minMaxState"] == 0
                warm_particles = math.ceil(initial["startLifetime"]["scalar"] * rate - 1e-6)
                start -= warm_particles / rate
                length -= start
        if not data["looping"]:
            length = min(length, data["lengthInSec"])
        if emission["rateOverTime"]["minMaxState"] == 0:
            pulse_count = math.ceil(length * rate - 1e-6) - 1
            if pulse_count > 0:
                births.append({"count": "Vector2i(1, 1)", "delay": start + 1 / rate,
                               "repeat_count": pulse_count, "repeat_interval": 1 / rate})
        else:
            curve = emission["rateOverTime"]["maxCurve"]["m_Curve"]
            accumulated = 0.0
            steps = math.ceil(length * 240)
            for step in range(steps):
                before = accumulated
                dt = length / steps
                progress = (step + 0.5) * dt / data["lengthInSec"]
                accumulated += rate * max(0, keyframe_value(curve, progress)) * dt
                for pulse in range(math.floor(before) + 1, math.floor(accumulated) + 1):
                    time = (step + (pulse - before) / (accumulated - before)) * dt
                    births.append({"count": "Vector2i(1, 1)", "delay": start + time,
                                   "repeat_count": 1, "repeat_interval": 0.0})
    for birth in births:
        birth["delay"] += presentation_offset * simulation_speed
    profile = {
        "mesh": mesh, "material": material,
        **(births[0] if births else {}),
        "seed": -1 if data["autoRandomSeed"] else (data["randomSeed"] & 0xffffffff if skill else data["randomSeed"]),
        "mode": 5 if ribbon_only else renderer["m_RenderMode"], "alignment": renderer["m_RenderAlignment"],
        "sorting_offset": renderer["m_SortingFudge"] * (-1 if skill else 1),
        "pivot": xyz(renderer["m_Pivot"]),
        "length_scale": renderer["m_LengthScale"], "velocity_scale": renderer["m_VelocityScale"],
        "size_3d": initial["size3D"],
        "shape": shape["type"] if shape["enabled"] else -1,
        "shape_position": xyz(shape["m_Position"]) if shape["enabled"] else "Vector3(0, 0, 0)",
        "shape_rotation": vector("Vector3", *[math.radians(shape["m_Rotation"][axis]) * sign
                                               for axis, sign in zip("xyz", (-1, -1, 1))]),
        "shape_scale": xyz(shape["m_Scale"], (1, 1, 1)),
        "radius": shape["radius"]["value"],
        "radius_thickness": shape["radiusThickness"],
        "shape_length": shape["length"], "cone_angle": math.radians(shape["angle"]),
        "orbit": vector("Vector2", *sorted(-v for v in particle_range(velocity["orbitalY"]))) if velocity["enabled"] else "Vector2(0, 0)",
    }
    if simulation_speed != 1.0:
        profile["simulation_speed"] = simulation_speed
    if presentation_scale != 1.0:
        profile["presentation_scale"] = presentation_scale
    if scale_with_action:
        profile["scale_with_action"] = True
    if starts_active:
        profile["start_on_enable"] = True
        if renderer["m_RenderMode"] == 0 and data["scalingMode"] == 1:
            profile["local_billboard_scale"] = True
    if skill and renderer["m_SortingOrder"]:
        assert renderer["m_SortingLayerID"] == 0
        profile["render_priority"] = renderer["m_SortingOrder"]
    # PC_Renderer/VFXRender (6689) repeats layer 8 after the character surface pass.
    if unity_layer == 8:
        profile["vfx_redraw"] = True
    # PC_Renderer/onHitVFX Render (6683) redraws transparent renderers on layer 14.
    if skill and unity_layer == 14:
        profile["on_hit_vfx_redraw"] = True
        if hit_dark_blend:
            profile["compensate_dark_blend"] = True
    if skill and not renderer["m_ApplyActiveColorSpace"]:
        profile["raw_particle_tint"] = True
    if flare_scale is not None:
        stream = data["CustomDataModule"]
        assert data["scalingMode"] == data["moveWithTransform"] == 0 and all(value == 1.0 for value in scale.values())
        assert stream["enabled"] and stream["vector0_0"]["minMaxState"] == 3
        assert all(stream[f"vector0_{i}"]["minMaxState"] == 0 for i in (1, 2, 3))
        assert stream["vector0_2"]["scalar"] == 0 and renderer["m_ApplyActiveColorSpace"]
        assert all(stream[f"vector1_{i}"]["minMaxState"] == 0 and stream[f"vector1_{i}"]["scalar"] == 0 for i in range(4))
        profile["flare_offset"] = vector("Vector2", *sorted(particle_range(stream["vector0_0"])))
        profile["flare_warp_emission"] = vector("Vector2", stream["vector0_1"]["scalar"], stream["vector0_3"]["scalar"])
        profile["size_scale"] = vector("Vector3", flare_scale, flare_scale, flare_scale)
    if distance_rate > 0:
        assert skill and emit_on_enable
        assert emission["rateOverDistance"]["minMaxState"] == 0
        assert data["moveWithTransform"] == data["scalingMode"] == 1 and data["looping"]
        if renderer["m_RenderMode"] == 0:
            profile["local_billboard_scale"] = True
        else:
            assert renderer["m_RenderMode"] == 1 and renderer["m_CameraVelocityScale"] == 0
            assert initial["startSpeed"]["minMaxState"] == 0 and initial["startSpeed"]["scalar"] == 0
        profile["distance_rate"] = distance_rate
    infinite_projectile = projectile and math.isinf(initial["startLifetime"]["scalar"])
    if skill and data["moveWithTransform"] == 0 and not infinite_projectile:
        profile["world_space"] = True
    if skill and renderer["m_RenderMode"] == 4:
        if data["scalingMode"] == 1:
            profile["mesh_local_scale"] = True
    linear_curves = None
    if skill and velocity["enabled"] and any(velocity[axis]["scalar"] != 0 for axis in "xyz"):
        states = {velocity[axis]["minMaxState"] for axis in "xyz"}
        if velocity["inWorldSpace"]:
            if not profile.get("world_space") or profile.get("local_billboard_scale") or not states <= {0, 3}:
                raise ValueError("World velocity requires fixed world simulation and constant axis ranges")
            profile["world_linear_velocity"] = True
        if states == {0}:
            profile["linear_velocity"] = xyz({axis: velocity[axis]["scalar"] for axis in "xyz"})
        elif states <= {0, 3}:
            profile["linear_velocity_ranges"] = "[" + ", ".join(
                vector("Vector2", *sorted(sign * value for value in particle_range(velocity[axis])))
                for axis, sign in zip("xyz", (1, 1, -1))) + "]"
        elif states <= {0, 1}:
            assert velocity["speedModifier"]["minMaxState"] in (0, 1)
            linear_curves = {axis: velocity[axis] for axis in "xyz"}
        else:
            raise ValueError(f"Unsupported velocity curve modes {sorted(states)}")
    if (skill and shape["enabled"] and shape["type"] == 0 and shape["alignToDirection"]
            and (renderer["m_RenderMode"] == 4 or renderer["m_RenderAlignment"] == 2)):
        profile["align_to_direction"] = True
    if skill and shape["enabled"] and shape["type"] == 0 and shape["radius"]["value"] > 0:
        profile["sphere_volume"] = True
    if skill and shape["enabled"] and shape["type"] == 17:
        profile["donut_radius"] = shape["donutRadius"]
    if skill and rotation["enabled"] and not rotation["separateAxes"] and rotation["curve"]["minMaxState"] in (0, 3):
        profile["spin"] = vector("Vector2", *sorted(particle_range(rotation["curve"])))
    if skill and color["enabled"]:
        gradient = color["gradient"]["maxGradient"]
        if any(gradient[f"key{i}"][channel] != 1.0 for i in range(gradient["m_NumColorKeys"]) for channel in "rgb"):
            profile["color_gradient"] = sampled_gradient(color, "gradient")
    if any(value != 1.0 for value in scale.values()):
        assert data["scalingMode"] in (0, 1) and renderer["m_RenderMode"] in (0, 2, 3)
        profile["size_scale"] = xyz(scale, (1, 1, 1))
    ranges = {"lifetime": "startLifetime", "speed": "startSpeed", "width": "startSize",
              "height": "startSizeY", "depth": "startSizeZ", "pitch": "startRotationX",
              "yaw": "startRotationY", "roll": "startRotation"}
    for field, native in ranges.items():
        limits = particle_range(initial[native])
        if field == "lifetime" and infinite_projectile:
            limits = [effect_duration * simulation_speed] * 2
        elif field == "lifetime" and all(math.isinf(value) for value in limits):
            # Use the first ground-contact pose in the Godot replay for the anchored projectile mesh.
            assert emit_on_enable and not data["looping"] and len(births) == len(bursts) == 1
            assert renderer["m_RenderMode"] == 4 and not size["enabled"] and not color["enabled"]
            assert data["moveWithTransform"] == 0 and data["scalingMode"] == 1 and not shape["enabled"]
            assert data["startDelay"]["minMaxState"] == 0 and math.isclose(profile["delay"] / simulation_speed, effect_delay)
            assert projectile_contact_time is not None and projectile_contact_time >= effect_delay
            profile["delay"] = (projectile_contact_time - effect_delay) * simulation_speed
            profile["world_mesh_rotation"] = True
            limits = [effect_duration * simulation_speed] * 2
        if skill and field == "lifetime" and initial[native]["minMaxState"] == 1 and len(births) == len(bursts) == 1:
            curve = initial[native]
            lifetime = curve["scalar"] * keyframe_value(curve["maxCurve"]["m_Curve"], bursts[0]["time"] / data["lengthInSec"])
            limits = [lifetime, lifetime]
        if field in ("pitch", "yaw", "roll"):
            limits = [-v if field in ("pitch", "yaw") else v for v in limits]
            if field != "roll" and not initial["rotation3D"]:
                limits = [0.0, 0.0]
        profile[field] = vector("Vector2", *sorted(limits))
    if baked_view_billboard is not None:
        # Match the deterministic first burst measured with Unity BakeMesh.
        roll, hierarchy_scale = baked_view_billboard
        assert renderer["m_RenderMode"] == renderer["m_RenderAlignment"] == data["scalingMode"] == 0
        assert not data["autoRandomSeed"] and not data["looping"] and data["randomSeed"] == 3964
        assert len(bursts) == 1 and bursts[0]["cycleCount"] == 1 and profile["count"] == "Vector2i(1, 1)"
        assert initial["startRotation"]["minMaxState"] == 3 and not initial["rotation3D"]
        profile["roll"] = vector("Vector2", roll, roll)
        profile["size_scale"] = vector("Vector3", hierarchy_scale, hierarchy_scale, hierarchy_scale)
    tint = initial["startColor"]
    for suffix, key in (("min", "minColor" if tint["minMaxState"] == 2 else "maxColor"), ("max", "maxColor")):
        profile[f"tint_{suffix}"] = vector("Color", *(tint[key][channel] for channel in "rgba"))
    if starts_active and len(births) > 1:
        profile["bursts"] = "[" + ", ".join(profile_literal(birth) for birth in births) + "]"
    elif len(bursts) > 1:
        assert emission["rateOverTime"]["scalar"] == 0 and data["startDelay"]["minMaxState"] == 0
        if initial["startSize"]["minMaxState"] == 1 and not initial["size3D"] and tint["minMaxState"] == 1:
            for birth, burst in zip(births, bursts):
                assert burst["cycleCount"] == 1
                progress = burst["time"] / data["lengthInSec"]
                size_curve = initial["startSize"]
                width = keyframe_value(size_curve["maxCurve"]["m_Curve"], progress) * size_curve["scalar"]
                color_at_birth = vector("Color", *gradient_at(tint["maxGradient"], progress))
                birth.update(width=vector("Vector2", width, width), tint_min=color_at_birth, tint_max=color_at_birth)
        else:
            size_fields = ("startSize", "startSizeY", "startSizeZ") if initial["size3D"] else ("startSize",)
            assert all(initial[field]["minMaxState"] in (0, 3) for field in size_fields)
            assert tint["minMaxState"] in (0, 2)
    if len(births) > 1:
        profile["bursts"] = "[" + ", ".join(profile_literal(birth) for birth in births) + "]"
    if baked_flight_glow:
        assert starts_active and data["prewarm"] and not data["autoRandomSeed"] and data["randomSeed"] == 6457
        assert data["scalingMode"] == 1 and data["moveWithTransform"] == 0 and rate == 5.0
        assert len(births) == 1 and births[0]["repeat_count"] == len(YUNA_FLIGHT_GLOW_OFFSETS)
        assert shape["type"] == 4 and math.isclose(shape["radius"]["value"], 0.3, rel_tol=1e-6)
        assert initial["startSpeed"]["scalar"] == 0 and not velocity["enabled"]
        glow_births = (dict(delay=(i + 1 - warm_particles) / rate, repeat_count=1,
                            initial_position=vector("Vector3", x, y, 0), initial_velocity="Vector3(0, 0, 0)")
                       for i, (x, y) in enumerate(YUNA_FLIGHT_GLOW_OFFSETS))
        profile["bursts"] = "[" + ", ".join(profile_literal(birth) for birth in glow_births) + "]"
        profile["interpolate_birth_position"] = True
    if baked_smoke_scale is not None:
        assert len(births) == 1 and data["scalingMode"] == 0 and data["moveWithTransform"] == 1
        assert not data["looping"] and not data["autoRandomSeed"] and data["randomSeed"] == 3964
        assert shape["type"] == 4 and shape["m_Rotation"] == {"x": -90.0, "y": 0.0, "z": 0.0}
        profile["size_scale"] = vector("Vector3", baked_smoke_scale, baked_smoke_scale, baked_smoke_scale)
        smoke_births = impact_smoke_birth_profiles(births[0], baked_smoke_scale)
        profile["bursts"] = "[" + ", ".join(profile_literal(sample) for sample in smoke_births) + "]"
    x = size["curve"] if size["enabled"] else None
    radial = velocity["radial"] if velocity["enabled"] else None
    if skill and not tracked_ribbon and radial is not None and radial["minMaxState"] in (0, 3):
        radial_range = sorted(particle_range(radial))
        if any(radial_range):
            profile["radial_speed"] = vector("Vector2", *radial_range)
            radial = None
    values = {"size_x_min": samples(x, minimum=True), "size_x": samples(x),
              "size_y": samples(size["y"] if size["separateAxes"] else x),
              "size_z": samples(size["z"] if size["separateAxes"] else x),
              "opacity": opacity(color, "gradient") if color["enabled"] else [1.0],
              "speed_distance": integrated(velocity["speedModifier"] if velocity["enabled"] else None, 1.0),
              "radial_distance": integrated(radial, 0.0)}
    noise = data["NoiseModule"]
    if skill and noise["enabled"]:
        assert noise["damping"] and noise["octaves"] == 1 and not noise["separateAxes"] and not noise["remapEnabled"]
        assert noise["scrollSpeed"]["minMaxState"] == noise["positionAmount"]["minMaxState"] == 0
        assert noise["rotationAmount"]["scalar"] == noise["sizeAmount"]["scalar"] == 0
        profile["noise_frequency"] = noise["frequency"]
        profile["noise_scroll"] = noise["scrollSpeed"]["scalar"]
        displacement = noise["positionAmount"]["scalar"] / noise["frequency"]
        if distance_rate > 0 and renderer["m_RenderMode"] == 1:
            values["noise_distance"] = [value * displacement for value in integrated(noise["strength"], 0.0)]
        else:
            profile["noise_strength"] = vector("Vector2", *(value * displacement for value in
                                                           sorted(particle_range(noise["strength"]))))
    uv = data["UVModule"]
    if skill and uv["enabled"]:
        assert uv["mode"] == uv["timeMode"] == uv["animationType"] == uv["flipU"] == uv["flipV"] == 0
        assert uv["startFrame"]["minMaxState"] == 0 and uv["frameOverTime"]["minMaxState"] in (0, 1, 3)
        profile.update(atlas_grid=vector("Vector2i", uv["tilesX"], uv["tilesY"]),
                       atlas_cycles=uv["cycles"], atlas_start=uv["startFrame"]["scalar"])
        values["atlas_frames"] = samples(uv["frameOverTime"])
        if uv["frameOverTime"]["minMaxState"] == 3:
            values["atlas_frames_min"] = samples(uv["frameOverTime"], minimum=True)
    if atlas_shader:
        custom = data["CustomDataModule"]
        if custom["enabled"] and custom["mode0"] == 1:
            intensity = custom["vector0_0"]
            constant = intensity["minMaxState"] == 0 or (
                intensity["minMaxState"] == 1 and intensity["scalar"] == 0.0)
            if constant:
                profile["intensity_offset"] = intensity["scalar"]
            elif intensity["minMaxState"] == 1:
                values["intensity_curve"] = samples(intensity)
    if custom_dissolve:
        assert renderer["m_UseCustomVertexStreams"]
        custom = data["CustomDataModule"]
        assert custom["enabled"]
        if renderer["m_VertexStreams"] == [0, 1, 3, 4, 31]:
            # D3D11 aliases missing TEXCOORD1 to TEXCOORD0 for the white core mesh.
            assert custom["mode0"] == 1 and custom["vector0_0"]["minMaxState"] == 0
            values.update(dissolve_value=[custom["vector0_0"]["scalar"]], dissolve_scroll_x=[0.0])
        else:
            assert renderer["m_VertexStreams"] == [0, 1, 3, 4, 34, 38]
            assert custom["mode1"] == 1 and custom["vector1_2"]["minMaxState"] in (0, 1, 3)
            values.update(dissolve_value=samples(custom["vector1_0"]), dissolve_scroll_x=samples(custom["vector1_1"]))
            if custom["vector1_2"]["minMaxState"] == 1:
                values["dissolve_scroll_y"] = samples(custom["vector1_2"])
            else:
                profile["dissolve_shift_y"] = vector("Vector2", *sorted(particle_range(custom["vector1_2"])))
    if flow_wave:
        assert renderer["m_UseCustomVertexStreams"] and renderer["m_VertexStreams"] == [0, 1, 3, 4, 34, 38, 19]
        stream = data["CustomDataModule"]
        assert stream["enabled"] and stream["vector0_0"]["minMaxState"] == 3
        assert all(stream[f"vector1_{i}"]["minMaxState"] == 0 and stream[f"vector1_{i}"]["scalar"] == 0 for i in (0, 2, 3))
        assert data["prewarm"] and data["looping"] and not data["playOnAwake"] and not data["autoRandomSeed"]
        assert simulation_speed == 1.0 and data["randomSeed"] == 6457 and data["lengthInSec"] == 1.0
        assert initial["startLifetime"]["minMaxState"] == 0 and math.isclose(initial["startLifetime"]["scalar"], 0.8, rel_tol=1e-6)
        assert [birth["delay"] for birth in births] == [0.0, 0.20]
        warm_births = (dict(delay=delay, initial_age=age, wave_offset=vector("Vector2", offset, offset))
                       for delay, age, offset in YUNA_FLIGHT_WAVE_BIRTHS)
        profile["bursts"] = "[" + ", ".join(profile_literal(birth) for birth in warm_births) + "]"
        values.update(wave_far=samples(stream["vector0_1"]), wave_near=samples(stream["vector0_2"]),
                      wave_phase=samples(stream["vector1_1"]))
    if renderer["m_UseCustomVertexStreams"] and renderer["m_VertexStreams"] == [0, 1, 3, 4, 5, 34]:
        custom = data["CustomDataModule"]
        assert custom["enabled"] and custom["mode0"] == 1
        values.update({f"slash_{axis}": samples(custom[f"vector0_{index}"])
                       for index, axis in enumerate("xyzw")})
    if skill and rotation["enabled"] and rotation["separateAxes"]:
        for axis, field, sign in (("x", "x", -1), ("y", "y", -1), ("z", "curve", 1)):
            values[f"spin_{axis}_distance"] = [v * sign for v in integrated(rotation[field], 0.0)]
    if linear_curves is not None:
        multiplier = samples(velocity["speedModifier"])
        for axis, sign in zip("xyz", (1, 1, -1)):
            speed = samples(linear_curves[axis])
            seconds = [sign * speed[min(i, len(speed) - 1)] * multiplier[min(i, len(multiplier) - 1)]
                       for i in range(STEPS + 1)]
            displacement = [0.0]
            for left, right in zip(seconds, seconds[1:]):
                displacement.append(displacement[-1] + (left + right) / (2 * STEPS))
            values[f"velocity_{axis}_distance"] = displacement
    if ribbon_only:
        assert trail["mode"] == 0 and trail["ratio"] == 1 and trail["textureMode"] == 0
        assert not (trail["sizeAffectsWidth"] or trail["sizeAffectsLifetime"] or trail["inheritParticleColor"])
        profile.update(ribbon_die_with_particle=trail["dieWithParticles"],
                       ribbon_life_factor=vector("Vector2", *sorted(particle_range(trail["lifetime"]))),
                       ribbon_color=sampled_gradient(trail, "colorOverTrail"),
                       ribbon_life_color=sampled_gradient(trail, "colorOverLifetime"))
        values["ribbon_width"] = samples(trail["widthOverTrail"])
        if trail["widthOverTrail"]["minMaxState"] in (2, 3):
            values["ribbon_width_min"] = samples(trail["widthOverTrail"], minimum=True)
        if tracked_ribbon:
            assert not velocity["inWorldSpace"] and velocity["radial"]["minMaxState"] == 3
            profile.update(tracked_ribbon=True,
                           ribbon_radial_range=vector("Vector2", *sorted(particle_range(velocity["radial"]))))
    elif trail["enabled"]:
        profile.update(ribbon_lifetime=trail["lifetime"]["scalar"], ribbon_spacing=trail["minVertexDistance"],
                       ribbon_radial_speed=velocity["radial"]["scalar"])
        values.update(ribbon_width=samples(trail["widthOverTrail"]),
                      ribbon_opacity=opacity(trail, "colorOverTrail"))
    profile.update({key: vector("PackedFloat32Array", *curve) for key, curve in values.items()})
    return profile_literal(profile)


def export_prefab(src, owner, reader, layouts, game, name, particles=None, hold_on_emit=False, emitter_root=None,
                  motion_trails=(), finish_particles=False, presentation_offset=0.0, projectile=False,
                  presentation_scales=None, flat_emitters=None, layer_errors=None, output_group=None):
    prefab = ({"m_GameObject": {"m_PathID": reader.path_id}, "_delay": 0.0, "_duration": 5.0,
               "_disableOnRelease": True} if projectile else read_fields(reader, layouts))
    effect = owner.objects[prefab["m_GameObject"]["m_PathID"]].read()
    external, materials = {}, {}
    subresources = ['[sub_resource type="QuadMesh" id="Quad"]', 'size = Vector2(1, 1)', ""]
    nodes = []
    used_node_names = set()
    presentation_scales = presentation_scales or {}

    def resource(kind, path):
        key = external.setdefault((kind, path), str(len(external) + 1))
        return f'ExtResource("{key}")'

    def emitter_name(name, path_id):
        if name in used_node_names:
            name = f"{name}_{path_id}"
        used_node_names.add(name)
        return name

    nodes.extend([f'[node name="{effect.m_Name}" type="Node3D"]',
                  'script = ' + resource("Script", "battle/revival_effect.gd"),
                  f'lead_in = {float(prefab["_delay"])}', f'duration = {float(prefab["_duration"])}'])
    if hold_on_emit:
        nodes.append("hold_world_position_on_emit = true")
    if finish_particles:
        assert not prefab["_disableOnRelease"] and not motion_trails
        nodes.append("finish_particles = true")
    if particles is not None and not projectile and flat_emitters is None:
        root_transform = next(c.component.deref().read_typetree() for c in effect.m_Component
                              if c.component.deref().type.name == "Transform")
        if emitter_root is not None:
            assert all(root_transform["m_LocalPosition"][axis] == root_transform["m_LocalRotation"][axis] == 0
                       for axis in "xyz")
            root_transform = owner.objects[emitter_root].read_typetree()
        position, rotation = root_transform["m_LocalPosition"], root_transform["m_LocalRotation"]
        if any(position[axis] != 0 for axis in "xyz"):
            nodes.append("position = " + xyz(position))
        if any(abs(rotation[axis]) > 1e-7 for axis in "xyz"):
            nodes.append("quaternion = " + vector("Quaternion", -rotation["x"], -rotation["y"], rotation["z"], rotation["w"]))
    nodes.extend([f'metadata/unity_prefab = {reader.path_id}', ""])

    def emit(go, offset, is_root=False):
        if projectile and not go.m_IsActive:
            return
        components = {pointer.type.name: pointer for component in go.m_Component
                      if component.component and (pointer := component.component.deref())}
        transform = components["Transform"].read_typetree()
        scale = transform["m_LocalScale"]
        if flat_emitters is None and (transform["m_Children"] or particles is None):
            assert scale == {"x": 1.0, "y": 1.0, "z": 1.0}
        position = transform["m_LocalPosition"]
        if particles is not None and not is_root:
            position = {axis: offset[axis] + position[axis] for axis in "xyz"}
        elif particles is not None:
            position = offset
        trail = components.get("TrailRenderer")
        if trail and trail.path_id in motion_trails:
            renderer = trail.read_typetree()
            params = renderer["m_Parameters"]
            assert prefab["_disableOnRelease"] and go.m_IsActive and renderer["m_Enabled"] and renderer["m_Emitting"]
            assert params["alignment"] == params["textureMode"] == params["numCornerVertices"] == params["numCapVertices"] == 0
            assert params["textureScale"] == {"x": 1.0, "y": 1.0}
            assert renderer["m_SortingLayerID"] == 0
            mat_owner, mat = src.resolve(owner, renderer["m_Materials"][0])
            material, _, _ = add_material(src, mat_owner, mat, True, game, resource, subresources, skill=True,
                                          linearize_vertex_tint=bool(renderer["m_ApplyActiveColorSpace"]))
            width = params["widthCurve"]["m_Curve"]
            gradient = params["colorGradient"]
            profile = dict(lifetime=renderer["m_Time"], spacing=renderer["m_MinVertexDistance"],
                           render_priority=renderer["m_SortingOrder"],
                           width_multiplier=params["widthMultiplier"],
                           width=vector("PackedFloat32Array", *(params["widthMultiplier"] * keyframe_value(width, step / STEPS)
                                                                for step in range(STEPS + 1))),
                           color=vector("PackedColorArray", *(channel for step in range(STEPS + 1)
                                                             for channel in gradient_at(gradient, step / STEPS))))
            mesh = f"MotionTrail{trail.path_id}"
            subresources.extend([f'[sub_resource type="ImmediateMesh" id="{mesh}"]',
                                 'resource_local_to_scene = true', ""])
            trail_name = emitter_name(go.m_Name, trail.path_id)
            nodes.extend([f'[node name="{trail_name}" type="Node3D" parent="."]',
                          "position = " + xyz(position),
                          f'metadata/unity_trail_renderer = {trail.path_id}',
                          'metadata/motion_trail = ' + profile_literal(profile), "",
                          f'[node name="Ribbon" type="MeshInstance3D" parent="{trail_name}"]',
                          "top_level = true", "cast_shadow = 0",
                          f'mesh = SubResource("{mesh}")', "material_override = " + material, ""])
        particle = components.get("ParticleSystem")
        if particle and (particles is None or particle.path_id in particles):
            if layer_errors is None:
                emit_particle(particle, components, go, transform, scale, position)
            else:
                # A failed layer can allocate resources before its profile rejects a Unity feature.
                subresource_length, node_length = len(subresources), len(nodes)
                ext_before, materials_before = external.copy(), materials.copy()
                try:
                    emit_particle(particle, components, go, transform, scale, position)
                except (AssertionError, KeyError, ValueError, NotImplementedError) as error:
                    line = traceback.extract_tb(error.__traceback__)[-1]
                    layer_errors[particle.path_id] = (f"{type(error).__name__}: {error}" if str(error) else
                                                       f"{line.name}: {line.line or 'unsupported source fields'}")
                    del subresources[subresource_length:]
                    del nodes[node_length:]
                    external.clear()
                    external.update(ext_before)
                    materials.clear()
                    materials.update(materials_before)
        for child in transform["m_Children"]:
            emit(src.resolve(owner, child)[1].read().m_GameObject.read(), position)

    def emit_particle(particle, components, go, transform, scale, position):
        ps = particle.read_typetree()
        renderer = components["ParticleSystemRenderer"].read_typetree()
        emission = ps["EmissionModule"]
        emits = emission["m_BurstCount"] or (particles is not None and
                (emission["rateOverTime"]["scalar"] > 0 or emission["rateOverDistance"]["scalar"] > 0))
        if renderer["m_Enabled"] and emits:
            mode = renderer["m_RenderMode"]
            assert mode in ((0, 1, 2, 3, 4, 5) if flat_emitters is not None else (0, 1, 4, 5))
            ribbon_only = particles is not None and mode == 0 and ps["TrailModule"]["enabled"]
            trail_only = mode == 5 or ribbon_only
            mat_owner, mat = src.resolve(owner, renderer["m_Materials"][-1 if trail_only else 0])
            if mat.path_id == 328 and mat_owner.name == "sharedassets1.assets":
                assert not renderer["m_ApplyActiveColorSpace"]
            key = (mat_owner.name, mat.path_id)
            if key not in materials:
                materials[key] = add_material(src, mat_owner, mat, trail_only, game, resource, subresources,
                                              skill=particles is not None)
            material, atlas_shader, custom_dissolve = materials[key]
            mesh = resource("ArrayMesh", mesh_asset(src, owner, renderer["m_Mesh"], game)) if mode == 4 else 'SubResource("Quad")'
            q = transform["m_LocalRotation"]
            if flat_emitters is not None:
                position, q, scale = flat_emitters[particle.path_id]
            flare_scale = None
            if mat.path_id == 331 and mat_owner.name == "sharedassets1.assets":
                flare_scale = uniform_hierarchy_scale(src, owner, transform)
            baked_view_billboard = None
            if particles is not None and particle.path_id in (52380, 54056):
                roll_degrees = 204.8808 if particle.path_id == 52380 else 356.9663
                baked_view_billboard = (math.radians(roll_degrees), uniform_hierarchy_scale(src, owner, transform))
            baked_smoke_scale = None
            if particles is not None and particle.path_id == 54276:
                baked_smoke_scale = uniform_hierarchy_scale(src, owner, transform)
            # Match the frame the animated weapon first reaches the ground in Godot.
            projectile_contact_time = 2.47 if particle.path_id in (54552, 55301) else None
            # The dark plume grows from the authored hit event while the flash is delayed.
            birth_offset = presentation_offset if baked_smoke_scale is None else 0.0
            profile = particle_profile(ps, renderer, mesh, material, atlas_shader, custom_dissolve,
                                       skill=particles is not None, scale=scale,
                                       effect_duration=prefab["_duration"], ribbon_only=ribbon_only,
                                       scale_with_action=(emitter_root is not None or flat_emitters is not None) and
                                       particle.path_id in scaled_particles,
                                       emit_on_enable=ps["playOnAwake"] and bool(prefab.get("_disableOnRelease")),
                                       flare_scale=flare_scale,
                                       flow_wave=mat.path_id == 361 and mat_owner.name == "sharedassets1.assets",
                                       effect_delay=prefab["_delay"], projectile_contact_time=projectile_contact_time,
                                       baked_view_billboard=baked_view_billboard,
                                       presentation_offset=birth_offset, baked_smoke_scale=baked_smoke_scale,
                                       baked_flight_glow=owner.name == "sharedassets1.assets" and particle.path_id == 53628,
                                       unity_layer=go.m_Layer,
                                       hit_dark_blend=mat_owner.name == "sharedassets1.assets" and mat.path_id in (337, 354),
                                       projectile=projectile,
                                       presentation_scale=presentation_scales.get(particle.path_id, 1.0))
            node_scale = 1.0 if baked_smoke_scale is None else baked_smoke_scale
            nodes.extend([f'[node name="{emitter_name(go.m_Name, particle.path_id)}" type="Node3D" parent="."]',
                          "position = " + xyz(position, (node_scale, node_scale, -node_scale)),
                          "quaternion = " + vector("Quaternion", -q["x"], -q["y"], q["z"], q["w"]),
                          f'metadata/unity_particle = {components["ParticleSystem"].path_id}',
                          'metadata/particle = ' + profile, ""])
    scaled_particles = {p["m_PathID"] for p in prefab.get("_particleSystemsToApplySpeedTo", [])}
    emission_root = effect if emitter_root is None else owner.objects[emitter_root].read().m_GameObject.read()
    emit(emission_root, dict.fromkeys("xyz", 0.0), is_root=True)
    header = ["[gd_scene format=3]", ""]
    header += [f'[ext_resource type="{kind}" path="res://{path}" id="{key}"]'
               for (kind, path), key in external.items()]
    scene_name = f"revival_{name}" if particles is None else name
    folder = game / "battle" if output_group is None else game / "battle" / output_group
    folder.mkdir(parents=True, exist_ok=True)
    destination = folder / f"{scene_name}.tscn"
    destination.write_text("\n".join(header + [""] + subresources + nodes), encoding="utf-8")
    print(f"{destination.name}: {owner.name}:{reader.path_id} {effect.m_Name}")
    return destination


def export_flash(src, owner, layouts, game):
    settings = read_fields(owner.objects[60894], layouts)
    states = [{key.split(">")[0].removeprefix("<"): value for key, value in state.items()}
              for state in settings["_states"]]
    revive, = (state for state in states if state["StateSource"] == 2 and state["Action"] == 1)
    mat_owner, material = src.resolve(owner, revive["Material"])
    props = material.read_typetree()["m_SavedProperties"]
    floats, colors = dict(props["m_Floats"]), dict(props["m_Colors"])
    assert floats["_UseShadow"] == 0 and floats["_RimBlendMode"] == 1 and floats["_UseRim"] == 1
    lines = ['[gd_resource type="ShaderMaterial" format=3]', "",
             '[ext_resource type="Shader" path="res://materials/character_revive.gdshader" id="1"]', "",
             '[resource]', 'shader = ExtResource("1")']
    for parameter, prop in (("tint", "_Color"), ("rim_tint", "_RimColor")):
        lines.append(f"shader_parameter/{parameter} = " + vector("Color", *(colors[prop][k] for k in "rgba")))
    lines.extend(["shader_parameter/rim_profile = " + vector("Vector3", *(floats[k] for k in
                  ("_RimFresnelPower", "_RimBorder", "_RimBlur"))),
                  "shader_parameter/light_limits = " + vector("Vector2", floats["_LightMinLimit"], floats["_LightMaxLimit"]),
                  f'shader_parameter/antialias_strength = {float(floats["_AAStrength"])}',
                  f'metadata/revive_delay = {revive["Delay"]:.9g}',
                  f'metadata/revive_duration = {revive["Duration"]:.9g}',
                  f'metadata/unity_material = "{mat_owner.name}:{material.path_id}"', ""])
    path = game / "materials" / "character_revive.tres"
    path.write_text("\n".join(lines), encoding="utf-8")
    print(f"{path.name}: {mat_owner.name}:{material.path_id}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    parser.add_argument("--output", type=Path, help="Godot project or staging directory")
    effects = parser.add_mutually_exclusive_group()
    effects.add_argument("--yuna-skill", action="store_true")
    effects.add_argument("--yuna-basic", action="store_true")
    effects.add_argument("--funke-skill", action="store_true")
    args = parser.parse_args()
    game = args.output or Path(__file__).resolve().parents[1] / "game"
    for folder in ("battle", "materials", "meshes", "textures"):
        (game / folder).mkdir(parents=True, exist_ok=True)
    with ExitStack() as stack:
        src = Source(args.data, stack)
        src.file("globalgamemanagers.assets")
        build = next(o.read_typetree() for o in src.file("globalgamemanagers").objects.values()
                     if o.type.name == "BuildSettings")
        layouts = BuildLayouts(build["m_Version"])
        layouts.load_local_game(str(args.data.parent))
        src.env.typetree_generator = layouts
        owner = src.file("sharedassets1.assets")
        if args.funke_skill:
            export_prefab(src, owner, owner.objects[63105], layouts, game, "funke_skill_charge",
                          {51926, 54363, 52226, 54668, 54871, 50862, 53288})
            export_prefab(src, owner, owner.objects[63387], layouts, game, "funke_skill_release",
                          {51661, 52296, 53122, 54702, 52384, 51470, 54554, 54694, 54255, 51571})
            export_prefab(src, owner, owner.objects[7148], layouts, game, "funke_skill_projectile",
                          {51124, 52309, 52356, 52718, 51514, 53056, 52909, 54510}, projectile=True)
            export_prefab(src, owner, owner.objects[63109], layouts, game, "funke_skill_hit",
                          {54575, 51328, 55474, 54194, 51527, 54318, 51246, 52590, 53726, 52818, 54327, 55316,
                           52655, 53295, 53411, 55302},
                          # The approximate shaders cover more pixels than the native passes.
                          presentation_scales={51246: 0.75, 52655: 0.65, 54194: 0.6, 51527: 0.65,
                                               53295: 0.7, 53411: 0.65, 55302: 0.7, 55474: 0.75})
            return
        if args.yuna_basic:
            export_prefab(src, owner, owner.objects[61495], layouts, game, "yuna_basic_slash",
                          {52764, 52927, 55087}, emitter_root=29141)
            return
        if args.yuna_skill:
            export_prefab(src, owner, owner.objects[63281], layouts, game, "yuna_skill_wind", {52194, 54405})
            export_prefab(src, owner, owner.objects[61017], layouts, game, "yuna_skill_charge",
                          {54326, 51603, 55554, 51547, 50802, 53010, 55433, 53412, 53965},
                          finish_particles=True)
            export_prefab(src, owner, owner.objects[62365], layouts, game, "yuna_skill_release",
                          {53342, 54920, 51506, 52648, 51360, 53505, 53773, 53216, 55213, 51186})
            export_prefab(src, owner, owner.objects[61696], layouts, game, "yuna_skill_flight",
                          {53229, 55583, 55253, 53628, 54005, 54552, 55301},
                          motion_trails={50124})
            export_prefab(src, owner, owner.objects[63162], layouts, game, "yuna_skill_landing", {52154})
            # Capture the authored anchor first, then match the burst phase observed in the replay.
            export_prefab(src, owner, owner.objects[62694], layouts, game, "yuna_skill_hit",
                          {52380, 54056, 51953, 52598, 54788, 54773, 53683, 55536, 53506, 53953, 54276},
                          hold_on_emit=True, presentation_offset=0.20)
            return
        feedback = read_fields(owner.objects[60884], layouts)
        victory, = feedback["<PostCombatVictoryResurrectVfxBlock>k__BackingField"]["<Mappings>k__BackingField"]
        wings, common = feedback["<PostCombatStabilizerResurrectVfxBlock>k__BackingField"]["<Mappings>k__BackingField"]
        assert victory == common
        for name, mapping in (("victory", common), ("stabilizer", wings)):
            mat_owner, reader = src.resolve(owner, mapping["<VfxPrefab>k__BackingField"])
            export_prefab(src, mat_owner, reader, layouts, game, name)
        export_flash(src, owner, layouts, game)


if __name__ == "__main__":
    main()
