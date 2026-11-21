"""Import the demo's victory and Stabilizer particle prefabs from VisualFeedbackSingleton."""
import argparse
from contextlib import ExitStack
import math
from pathlib import Path

from import_balancing import BuildLayouts, read_fields
from import_scenes import Source, material_texture, mesh_asset, particle_range, quote, texture_transform, vector


STEPS = 64


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


def add_material(src, owner, reader, trail, game, resource, lines):
    material = reader.read_typetree()
    props = material["m_SavedProperties"]
    floats, maps = dict(props["m_Floats"]), dict(props["m_TexEnvs"])
    colors = dict(props["m_Colors"])
    _, shader = src.resolve(owner, material["m_Shader"])
    if shader.path_id not in (707, 711, 2989, 2996):
        raise ValueError(f"Unhandled revival shader {shader.path_id}")
    name = f"Material{reader.path_id}"
    lines.extend([f'[sub_resource type="ShaderMaterial" id="{name}"]',
                  'shader = ' + resource("Shader", "materials/revival_particle.gdshader"),
                  f'shader_parameter/intensity = {floats.get("_ColorIntensity", floats.get("_Emission", 1.0)):.9g}',
                  f'shader_parameter/additive = {str(floats.get("_DstBlend") == 1).lower()}'])
    if "_DEPTHFADE" in material["m_ValidKeywords"]:
        lines.append(f'shader_parameter/fade_distance = {floats["_FadeDistance"]:.9g}')
    image = "_MainTex" if "_MainTex" in maps else "_Mask"
    use_rgb = shader.path_id == 2989 or bool(floats.get("_UseTexColor"))
    lines.append(f"shader_parameter/use_rgb = {str(use_rgb).lower()}")
    bindings = {"image": image, "mask": "_MaskTex"}
    if shader.path_id == 2989:
        bindings.update(mask="_Mask", noise="_Noise", flow="_Flow")
        speed = colors["_SpeedMainTexUVNoiseZW"]
        flow = colors["_DistortionSpeedXYPowerZ"]
        lines.extend(["shader_parameter/flow_graph = true",
                      "shader_parameter/image_scroll = " + vector("Vector2", speed["r"], -speed["g"]),
                      "shader_parameter/noise_scroll = " + vector("Vector2", speed["b"], -speed["a"]),
                      "shader_parameter/flow_scroll = " + vector("Vector2", flow["r"], -flow["g"]),
                      f'shader_parameter/flow_strength = {flow["b"]:.9g}'])
        if floats["_Usedepth"]:
            lines.append(f'shader_parameter/fade_distance = {floats["_Depthpower"]:.9g}')
    if floats.get("_Dissolve"):
        bindings["noise"] = "_DissolveTex"
        lines.extend([f'shader_parameter/dissolve_amount = {floats["_DissolveAmount"]:.9g}',
                      f'shader_parameter/dissolve_softness = {floats.get("_DissolveSmoothness", 0.1):.9g}',
                      "shader_parameter/noise_scroll = " + vector("Vector2", floats.get("_Dissolve_X_Spd", 0),
                                                                 -floats.get("_Dissolve_Y_Spd", 0))])
    if trail:
        lines.append("shader_parameter/vertex_tint = true")
    for uniform, field in bindings.items():
        slot = maps.get(field)
        if not slot or not slot["m_Texture"]["m_PathID"]:
            continue
        path, texture = material_texture(src, owner, slot["m_Texture"], game)
        lines.extend([f"shader_parameter/{uniform}_texture = " + resource("Texture2D", path),
                      f"shader_parameter/{uniform}_uv = " + texture_transform(slot)])
        if uniform == "image" and texture.read().m_ColorSpace == 1:
            lines.append("shader_parameter/image_is_srgb = true")
    lines.append("")
    return f'SubResource("{name}")'


def particle_profile(data, renderer, mesh, material):
    initial, shape = data["InitialModule"], data["ShapeModule"]
    size, color = data["SizeModule"], data["ColorModule"]
    velocity, trail = data["VelocityModule"], data["TrailModule"]
    emission = data["EmissionModule"]
    burst, = emission["m_Bursts"][:emission["m_BurstCount"]]
    assert burst["cycleCount"] > 0 and burst["probability"] == 1.0 and data["simulationSpeed"] == 1.0
    count = sorted(particle_range(burst["countCurve"]))
    profile = {
        "mesh": mesh, "material": material,
        "count": vector("Vector2i", *(int(v) for v in count)),
        "delay": data["startDelay"]["scalar"] + burst["time"],
        "repeat_count": burst["cycleCount"], "repeat_interval": burst["repeatInterval"],
        "seed": -1 if data["autoRandomSeed"] else data["randomSeed"],
        "mode": renderer["m_RenderMode"], "alignment": renderer["m_RenderAlignment"],
        "sorting_offset": renderer["m_SortingFudge"],
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
    ranges = {"lifetime": "startLifetime", "speed": "startSpeed", "width": "startSize",
              "height": "startSizeY", "depth": "startSizeZ", "pitch": "startRotationX",
              "yaw": "startRotationY", "roll": "startRotation"}
    for field, native in ranges.items():
        limits = particle_range(initial[native])
        if field in ("pitch", "yaw", "roll"):
            limits = [-v if field in ("pitch", "yaw") else v for v in limits]
            if field != "roll" and not initial["rotation3D"]:
                limits = [0.0, 0.0]
        profile[field] = vector("Vector2", *sorted(limits))
    tint = initial["startColor"]
    for suffix, key in (("min", "minColor" if tint["minMaxState"] == 2 else "maxColor"), ("max", "maxColor")):
        profile[f"tint_{suffix}"] = vector("Color", *(tint[key][channel] for channel in "rgba"))
    x = size["curve"] if size["enabled"] else None
    values = {"size_x_min": samples(x, minimum=True), "size_x": samples(x),
              "size_y": samples(size["y"] if size["separateAxes"] else x),
              "size_z": samples(size["z"] if size["separateAxes"] else x),
              "opacity": opacity(color, "gradient") if color["enabled"] else [1.0],
              "speed_distance": integrated(velocity["speedModifier"] if velocity["enabled"] else None, 1.0),
              "radial_distance": integrated(velocity["radial"] if velocity["enabled"] else None, 0.0)}
    if trail["enabled"]:
        profile.update(ribbon_lifetime=trail["lifetime"]["scalar"], ribbon_spacing=trail["minVertexDistance"],
                       ribbon_radial_speed=velocity["radial"]["scalar"])
        values.update(ribbon_width=samples(trail["widthOverTrail"]),
                      ribbon_opacity=opacity(trail, "colorOverTrail"))
    profile.update({key: vector("PackedFloat32Array", *curve) for key, curve in values.items()})
    serialized = (str(v).lower() if isinstance(v, bool) else format(v, ".9g") if isinstance(v, (float, int)) else v
                  for v in profile.values())
    return "{\n" + ",\n".join(f'{quote(key)}: {value}' for key, value in zip(profile, serialized)) + "\n}"


def export_prefab(src, owner, reader, layouts, game, name):
    prefab = read_fields(reader, layouts)
    effect = owner.objects[prefab["m_GameObject"]["m_PathID"]].read()
    external, materials = {}, {}
    subresources = ['[sub_resource type="QuadMesh" id="Quad"]', 'size = Vector2(1, 1)', ""]
    nodes = []

    def resource(kind, path):
        key = external.setdefault((kind, path), str(len(external) + 1))
        return f'ExtResource("{key}")'

    nodes.extend([f'[node name="{effect.m_Name}" type="Node3D"]',
                  'script = ' + resource("Script", "battle/revival_effect.gd"),
                  f'lead_in = {prefab["_delay"]:.9g}', f'duration = {prefab["_duration"]:.9g}',
                  f'metadata/unity_prefab = {reader.path_id}', ""])

    def emit(go, parent):
        components = {pointer.type.name: pointer for component in go.m_Component
                      if component.component and (pointer := component.component.deref())}
        transform = components["Transform"].read_typetree()
        assert transform["m_LocalScale"] == {"x": 1.0, "y": 1.0, "z": 1.0}
        if "ParticleSystem" in components:
            ps = components["ParticleSystem"].read_typetree()
            renderer = components["ParticleSystemRenderer"].read_typetree()
            if renderer["m_Enabled"] and ps["EmissionModule"]["m_BurstCount"]:
                mode = renderer["m_RenderMode"]
                assert mode in (0, 1, 4, 5)
                mat_owner, mat = src.resolve(owner, renderer["m_Materials"][-1 if mode == 5 else 0])
                key = (mat_owner.name, mat.path_id)
                if key not in materials:
                    materials[key] = add_material(src, mat_owner, mat, mode == 5, game, resource, subresources)
                mesh = resource("ArrayMesh", mesh_asset(src, owner, renderer["m_Mesh"], game)) if mode == 4 else 'SubResource("Quad")'
                q = transform["m_LocalRotation"]
                nodes.extend([f'[node name="{go.m_Name}" type="Node3D" parent="{parent}"]',
                              "position = " + xyz(transform["m_LocalPosition"]),
                              "quaternion = " + vector("Quaternion", -q["x"], -q["y"], q["z"], q["w"]),
                              f'metadata/unity_particle = {components["ParticleSystem"].path_id}',
                              'metadata/particle = ' + particle_profile(ps, renderer, mesh, materials[key]), ""])
        for child in transform["m_Children"]:
            emit(src.resolve(owner, child)[1].read().m_GameObject.read(), parent)

    emit(effect, ".")
    header = ["[gd_scene format=3]", ""]
    header += [f'[ext_resource type="{kind}" path="res://{path}" id="{key}"]'
               for (kind, path), key in external.items()]
    destination = game / "battle" / f"revival_{name}.tscn"
    destination.write_text("\n".join(header + [""] + subresources + nodes), encoding="utf-8")
    print(f"{destination.name}: {owner.name}:{reader.path_id} {effect.m_Name}")


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
                  f'shader_parameter/antialias_strength = {floats["_AAStrength"]:.9g}',
                  f'metadata/revive_delay = {revive["Delay"]:.9g}',
                  f'metadata/revive_duration = {revive["Duration"]:.9g}',
                  f'metadata/unity_material = "{mat_owner.name}:{material.path_id}"', ""])
    path = game / "materials" / "character_revive.tres"
    path.write_text("\n".join(lines), encoding="utf-8")
    print(f"{path.name}: {mat_owner.name}:{material.path_id}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    args = parser.parse_args()
    game = Path(__file__).resolve().parents[1] / "game"
    with ExitStack() as stack:
        src = Source(args.data, stack)
        src.file("globalgamemanagers.assets")
        build = next(o.read_typetree() for o in src.file("globalgamemanagers").objects.values()
                     if o.type.name == "BuildSettings")
        layouts = BuildLayouts(build["m_Version"])
        layouts.load_local_game(str(args.data.parent))
        src.env.typetree_generator = layouts
        owner = src.file("sharedassets1.assets")
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
