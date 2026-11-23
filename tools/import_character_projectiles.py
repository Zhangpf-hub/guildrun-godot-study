"""Extract authored flight and impact VFX referenced by CharacterVisualConfig."""

import argparse
import json
from contextlib import ExitStack
from pathlib import Path

from import_balancing import BuildLayouts, read_fields
from import_battle_revival import STEPS, add_material, export_prefab, gradient_at, keyframe_value, profile_literal, xyz
from import_scenes import Source, vector

GROUP = "projectiles"


def script_name(component):
    return str(component.parse_monobehaviour_head().m_Script.deref_parse_as_object().m_ClassName)


def scripts(src, owner, obj, class_name):
    for entry in obj.read_typetree()["m_Component"]:
        file, component = src.resolve(owner, entry["component"])
        if component.type.name == "MonoBehaviour" and script_name(component) == class_name:
            yield file, component


def components(src, owner, obj):
    return {reader.type.name: reader
            for entry in obj.read_typetree()["m_Component"]
            for _, reader in [src.resolve(owner, entry["component"])]
            if reader.type.name != "MonoBehaviour"}


def children(src, owner, obj, include_inactive_root=False):
    if not include_inactive_root and not obj.read().m_IsActive:
        return
    parts = components(src, owner, obj)
    yield obj, parts
    for item in parts["Transform"].read_typetree()["m_Children"]:
        file, transform = src.resolve(owner, item)
        child_owner, child = src.resolve(file, transform.read_typetree()["m_GameObject"])
        yield from children(src, child_owner, child)


def particle_ids(src, owner, obj, activation_managed):
    ids = set()
    for _, parts in children(src, owner, obj, activation_managed):
        if "ParticleSystem" not in parts or "ParticleSystemRenderer" not in parts:
            continue
        particle = parts["ParticleSystem"]
        renderer = parts["ParticleSystemRenderer"].read_typetree()
        emission = particle.read_typetree()["EmissionModule"]
        if renderer["m_Enabled"] and emission["enabled"] and (
                emission["m_BurstCount"] or emission["rateOverTime"]["scalar"] > 0
                or emission["rateOverDistance"]["scalar"] > 0):
            ids.add(particle.path_id)
    return ids


def root_local_position(src, owner, root, obj):
    """Return the source trail point in prefab coordinates, independent of root placement."""
    position = (0.0, 0.0, 0.0)
    while obj.path_id != root.path_id:
        transform = components(src, owner, obj)["Transform"].read_typetree()
        scale, rotation, offset = (transform[key] for key in
                                   ("m_LocalScale", "m_LocalRotation", "m_LocalPosition"))
        point = tuple(position[i] * scale[axis] for i, axis in enumerate("xyz"))
        x, y, z = (rotation[axis] for axis in "xyz")
        w = rotation["w"]
        cx, cy, cz = (y * point[2] - z * point[1], z * point[0] - x * point[2], x * point[1] - y * point[0])
        rotated = (point[0] + 2 * (w * cx + y * cz - z * cy),
                   point[1] + 2 * (w * cy + z * cx - x * cz),
                   point[2] + 2 * (w * cz + x * cy - y * cx))
        position = tuple(rotated[i] + offset[axis] for i, axis in enumerate("xyz"))
        owner, parent = src.resolve(owner, transform["m_Father"])
        owner, obj = src.resolve(owner, parent.read_typetree()["m_GameObject"])
    return dict(zip("xyz", position))


def attach_ara_trails(src, owner, root, layouts, game, path, references, errors):
    external, materials, nodes = {}, [], []

    def resource(kind, target):
        key = external.setdefault((kind, target), f"ara_{len(external) + 1}")
        return f'ExtResource("{key}")'

    for reference in references:
        file, reader = src.resolve(owner, reference)
        fields = read_fields(reader, layouts)
        if not (fields["m_Enabled"] and fields["emit"]):
            continue
        try:
            assert not fields["enablePhysics"] and not fields["section"]["m_PathID"]
            assert fields["space"] == fields["alignment"] == fields["textureMode"] == fields["sorting"] == 0
            assert fields["uvFactor"] == fields["uvWidthFactor"] == 1.0 and len(fields["materials"]) == 1
            obj_owner, trail = src.resolve(file, fields["m_GameObject"])
            anchor = root_local_position(src, obj_owner, root, trail)
            material_owner, material = src.resolve(file, fields["materials"][0])
            trail_materials = []
            material_ref, _, _ = add_material(src, material_owner, material, True, game, resource, trail_materials, skill=True)
            unique = f"AraMaterial{reader.path_id}"
            material_ref = material_ref.replace(f"Material{material.path_id}", unique)
            materials.extend(line.replace(f'id="Material{material.path_id}"', f'id="{unique}"') for line in trail_materials)
            width = fields["thickness"] * fields["initialThickness"] * 2
            widths, colors = [], []
            # Existing camera-facing ribbons sample by normalized path length. Constant-speed
            # trail motion makes length a useful proxy for age once the ribbon is fully extended.
            for step in range(STEPS + 1):
                progress = step / STEPS
                over_length = keyframe_value(fields["thicknessOverLength"]["m_Curve"], progress)
                over_time = keyframe_value(fields["thicknessOverTime"]["m_Curve"], 1 - progress)
                widths.append(width * over_length * over_time)
                length_color = gradient_at(fields["colorOverLength"], progress)
                age_color = gradient_at(fields["colorOverTime"], 1 - progress)
                colors.extend(fields["initialColor"][channel] * left * right
                              for channel, left, right in zip("rgba", length_color, age_color))
            profile = dict(lifetime=fields["time"], spacing=fields["minDistance"], width_multiplier=width,
                           width=vector("PackedFloat32Array", *widths), color=vector("PackedColorArray", *colors))
            mesh = f"AraMesh{reader.path_id}"
            name = f"AraTrail{reader.path_id}"
            materials.extend([f'[sub_resource type="ImmediateMesh" id="{mesh}"]',
                              "resource_local_to_scene = true", ""])
            nodes.extend([f'[node name="{name}" type="Node3D" parent="."]',
                          "position = " + xyz(anchor), f"metadata/unity_ara_trail = {reader.path_id}",
                          "metadata/motion_trail = " + profile_literal(profile), "",
                          f'[node name="Ribbon" type="MeshInstance3D" parent="{name}"]',
                          "top_level = true", "cast_shadow = 0",
                          f'mesh = SubResource("{mesh}")', "material_override = " + material_ref, ""])
        except (AssertionError, AttributeError, KeyError, ValueError, ZeroDivisionError) as error:
            errors[reader.path_id] = str(error) or "Unsupported AraTrail settings"

    content = path.read_text(encoding="utf-8")
    ext = "\n".join(f'[ext_resource type="{kind}" path="res://{target}" id="{key}"]'
                    for (kind, target), key in external.items())
    header, separator, tail = content.partition("[sub_resource")
    path.write_text(header + ext + "\n\n" + "\n".join(materials) + separator + tail
                    + "\n" + "\n".join(nodes), encoding="utf-8")


def scene_has_layers(path):
    content = path.read_text(encoding="utf-8")
    return "metadata/unity_particle = " in content or "metadata/motion_trail = " in content


def local_vec(value):
    return [value["x"], value["y"], -value["z"]]


def target_bindings(src, owner, layouts, visuals):
    offsets, bones = {}, {}
    for visual in visuals:
        pid = visual["id"]
        root_file, root = src.resolve(owner, visual["fields"]["Prefab"])
        root_transform = components(src, root_file, root)["Transform"].read_typetree()
        scale = root_transform["m_LocalScale"]
        rotation = root_transform["m_LocalRotation"]
        assert all(rotation[axis] == 0.0 for axis in "xyz")
        for obj, _ in children(src, root_file, root, include_inactive_root=True):
            for file, entity in scripts(src, root_file, obj, "EntityView"):
                for slot in read_fields(entity, layouts).get("_attachmentSlotMappings", []):
                    if slot["SlotType"] != 2 or not slot["SlotTransform"]["m_PathID"]:
                        continue
                    slot_file, transform = src.resolve(file, slot["SlotTransform"])
                    slot_owner, bone = src.resolve(slot_file, transform.read_typetree()["m_GameObject"])
                    local_position = root_local_position(src, slot_owner, root, bone)
                    offsets[pid] = [round(value, 8) for value in local_vec(
                        {axis: local_position[axis] * scale[axis] for axis in "xyz"})]
                    bones[pid] = bone.peek_name()
                    break
            if pid in bones:
                break
    return offsets, bones


def export_projectile(src, owner, prefab, layouts, game):
    _, controller = next(scripts(src, owner, prefab, "ProjectileViewController"))
    fields = read_fields(controller, layouts)
    pid = prefab.path_id
    report = {"prefab": prefab.peek_name(), "controller": controller.path_id}
    binding = {"launch_offset": local_vec(fields["_customPositionOffset"]),
               "forward": local_vec(fields["_projectileForwardAxis"]),
               "up": local_vec(fields["_projectileUpAxis"]),
               "pitch_degrees": -fields["_customRotationOffset"]["x"],
               "match_source_scale": bool(fields["_matchScaleWithSource"])}
    report.update(source_offset_type=fields["_sourceOffsetType"], use_arc=bool(fields["_useArc"]))
    if fields["_useArc"]:
        report["arc_keys"] = fields["_distanceToArcHeightMultiplier"]["m_Curve"]
        start, end = report["arc_keys"]
        assert start["time"] == start["value"] == end["inSlope"] == 0.0
        assert start["weightedMode"] == end["weightedMode"] == 0
        binding["arc"] = {"distance": end["time"], "height": end["value"],
                          "initial_tangent": start["outSlope"]}

    flight_errors = {}
    particles = particle_ids(src, owner, prefab, False)
    flight = export_prefab(src, owner, prefab, layouts, game, f"{pid}_flight", particles=particles,
                           projectile=True, layer_errors=flight_errors, output_group=GROUP)
    attach_ara_trails(src, owner, prefab, layouts, game, flight, fields["_projectileAraTrails"], flight_errors)
    if scene_has_layers(flight):
        binding["flight"] = f"res://battle/{GROUP}/{flight.name}"
    else:
        flight.unlink()
    if fields["_projectileTrails"]:
        for trail in fields["_projectileTrails"]:
            flight_errors[trail["m_PathID"]] = "Source TrailRenderer still requires dedicated transfer"
    if flight_errors:
        report["flight_pending"] = flight_errors

    hit_errors = {}
    if fields["_onHitVfxPrefab"]["m_PathID"]:
        file, hit_ref = src.resolve(owner, fields["_onHitVfxPrefab"])
        hit_fields = read_fields(hit_ref, layouts)
        hit_owner, hit_root = src.resolve(file, hit_fields["m_GameObject"])
        particles = particle_ids(src, hit_owner, hit_root, True)
        hit = export_prefab(src, file, hit_ref, layouts, game, f"{pid}_impact", particles=particles,
                            layer_errors=hit_errors, output_group=GROUP)
        if scene_has_layers(hit):
            binding["impact"] = f"res://battle/{GROUP}/{hit.name}"
        else:
            hit.unlink()
    if hit_errors:
        report["impact_pending"] = hit_errors
    return binding, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path, help="Guildrun_Data from the source build")
    parser.add_argument("--output", type=Path, required=True, help="Staging Godot project directory")
    parser.add_argument("--balancing", type=Path, default=Path("game/balancing/sharedassets1.json"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for folder in ("meshes", "textures"):
        (args.output / folder).mkdir(exist_ok=True)
    records = json.loads(args.balancing.read_text(encoding="utf-8"))["records"]
    visuals = [record for record in records if record["type"] == "CharacterVisualConfig"]
    grouped = {}
    for visual in visuals:
        pid = visual["fields"]["ProjectilePrefab"]["m_PathID"]
        if pid:
            grouped.setdefault(pid, []).append(visual["id"])
    report = {}
    with ExitStack() as stack:
        src = Source(args.data, stack)
        for file in args.data.glob("*.assets"):
            src.file(file.name)
        manager = src.file("globalgamemanagers")
        version = next(obj.read_typetree()["m_Version"] for obj in manager.objects.values() if obj.type.name == "BuildSettings")
        layouts = BuildLayouts(version)
        layouts.load_local_game(str(args.data.parent))
        src.env.typetree_generator = layouts
        owner = src.file("sharedassets1.assets")
        output = args.output / "battle" / GROUP
        for pid, visual_ids in sorted(grouped.items()):
            binding, evidence = export_projectile(src, owner, owner.objects[pid], layouts, args.output)
            evidence["visuals"] = visual_ids
            report[pid] = evidence
            if "flight" in binding or "impact" in binding:
                (output / f"{pid}.json").write_text(json.dumps(binding, indent=2) + "\n", encoding="utf-8")
        offsets, bones = target_bindings(src, owner, layouts, visuals)
        for name, data in (("target_offsets", offsets), ("target_bones", bones)):
            (output / f"{name}.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    (args.output / "projectile_audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
