"""Export the original RagdollAnimator2 colliders and constraints for battle visuals."""
import argparse
from contextlib import ExitStack
import json
from pathlib import Path

from import_balancing import BuildLayouts, read_fields
from import_scenes import Source


GAME = Path(__file__).resolve().parents[1] / "game"


def vector(value, signs=(1, 1, 1)):
    return [round(float(value[axis]) * sign, 7) for axis, sign in zip("xyz", signs)]


def components(source, file, parent):
    for ptr in parent.read_typetree()["m_Component"]:
        owner, component = source.resolve(file, ptr["component"])
        yield owner, component
        if component.type.name == "Transform":
            for child in component.read_typetree()["m_Children"]:
                child_file, transform = source.resolve(owner, child)
                go_file, go = source.resolve(child_file, transform.read_typetree()["m_GameObject"])
                yield from components(source, go_file, go)


def collision_shape(collider, handler, chain):
    length_scale = handler["RagdollSizeMultiplier"] * chain["ChainScaleMultiplier"] * collider["ColliderSizeMultiply"]
    radius = collider["ColliderRadius"] * length_scale * handler["RagdollThicknessMultiplier"] * chain["ChainThicknessMultiplier"]
    kind = collider["ColliderType"]
    if kind not in (0, 2):
        raise ValueError(f"Unsupported ragdoll collider type {kind}")
    shape = {"center": vector(collider["ColliderCenter"], (-1, 1, 1)), "radius": round(radius, 7)}
    if kind == 0:
        shape["height"] = round(collider["ColliderLength"] * length_scale, 7)
        shape["axis"] = collider["CapsuleDirection"]
    correction = vector(collider["RotationCorrection"], (1, -1, -1))
    if any(correction):
        shape["rotation"] = correction
    return shape


def export_ragdoll(source, file, component, layouts):
    handler = read_fields(component, layouts)["handler"]
    bodies = []
    for chain in handler["chains"]:
        for index, bone in enumerate(chain["BoneSetups"]):
            owner, transform = source.resolve(file, bone["SourceBone"])
            transform_data = transform.read_typetree()
            _, node = source.resolve(owner, transform_data["m_GameObject"])
            body = {
                "name": node.read_typetree()["m_Name"],
                "mass": round(handler["ReferenceMass"] * chain["MassMultiplier"] * bone["MassMultiplier"] *
                              handler["MassMultiplyOnFalling"], 6),
                "shapes": [collision_shape(shape, handler, chain) for shape in bone["colliders"]],
            }
            # Selkhera's FBX omits this unweighted leaf, but it still has a source collider.
            if body["name"] == "tail_069" and not transform_data["m_Children"]:
                parent_file, parent = source.resolve(owner, transform_data["m_Father"])
                _, parent_node = source.resolve(parent_file, parent.read_typetree()["m_GameObject"])
                rotation = transform_data["m_LocalRotation"]
                body["rest"] = {
                    "parent": parent_node.read_typetree()["m_Name"],
                    "position": vector(transform_data["m_LocalPosition"], (-1, 1, 1)),
                    "rotation": vector(rotation, (1, -1, -1)) + [round(rotation["w"], 7)],
                }
            if chain["ChainType"] != 2 or index != 0:
                # FBX export reflects the source X axis. Joint axes are axial vectors.
                twist_sign = -1 if bone["InverseMainAxis"] else 1
                swing_sign = -1 if bone["InverseSecondaryAxis"] else 1
                body["joint"] = {
                    "twist": vector(bone["TargetMainAxis"], (twist_sign, -twist_sign, -twist_sign)),
                    "swing": vector(bone["TargetSecondaryAxis"], (swing_sign, -swing_sign, -swing_sign)),
                }
                if not chain["UnlimitedRotations"]:
                    scale = chain["AxisLimitRange"]
                    lower = (bone["MainAxisLowLimit"], -bone["SecondaryAxisAngleLimit"], -bone["ThirdAxisAngleLimit"])
                    upper = (bone["MainAxisHighLimit"], bone["SecondaryAxisAngleLimit"], bone["ThirdAxisAngleLimit"])
                    body["joint"]["lower"] = [round(value * scale, 5) for value in lower]
                    body["joint"]["upper"] = [round(value * scale, 5) for value in upper]
            bodies.append(body)
    return {
        "linear_damping": round(handler["RigidbodyDragValue"], 6),
        "angular_damping": round(handler["RigidbodyAngularDragValue"], 6),
        "bodies": bodies,
    }


def export(source, layouts):
    assets = source.file("sharedassets1.assets")
    records = json.loads((GAME / "balancing/sharedassets1.json").read_text(encoding="utf-8"))["records"]
    rigs = {}
    for record in records:
        if record["type"] != "CharacterVisualConfig":
            continue
        source_file, prefab = source.resolve(assets, record["fields"]["Prefab"])
        for owner, component in components(source, source_file, prefab):
            if component.type.name != "MonoBehaviour":
                continue
            script = component.parse_monobehaviour_head().m_Script.deref_parse_as_object()
            if script.m_ClassName != "RagdollAnimator2":
                continue
            identifier = str(record["id"])
            if identifier in rigs:
                raise ValueError(f"Multiple ragdoll skeletons in {record['name']}")
            rigs[identifier] = export_ragdoll(source, owner, component, layouts)

    settings = read_fields(assets.objects[60793], layouts)
    output = {
        "impulse": {
            "min_damage": settings["<RagdollMinDamage>k__BackingField"],
            "max_damage": settings["<RagdollMaxDamage>k__BackingField"],
            "min_force": settings["<RagdollMinImpactForce>k__BackingField"],
            "max_force": settings["<RagdollMaxImpactForce>k__BackingField"],
        },
        "rigs": rigs,
    }
    destination = GAME / "Characters/ragdolls.json"
    destination.write_text(json.dumps(output, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{len(rigs)} ragdoll configurations, {sum(len(rig['bodies']) for rig in rigs.values())} physical bones")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    args = parser.parse_args()
    with ExitStack() as stack:
        source = Source(args.data, stack)
        manager = source.file("globalgamemanagers")
        for label in ("globalgamemanagers.assets", "resources.assets", "sharedassets1.assets",
                      "sharedassets2.assets", "sharedassets3.assets"):
            source.file(label)
        build = next(obj.read_typetree() for obj in manager.objects.values() if obj.type.name == "BuildSettings")
        layouts = BuildLayouts(build["m_Version"])
        layouts.load_local_game(str(args.data.parent))
        source.env.typetree_generator = layouts
        export(source, layouts)
