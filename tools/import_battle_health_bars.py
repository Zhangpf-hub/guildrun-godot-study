"""Translate BattleUIController's overhead health bar prefab, data and model sockets."""
import argparse
import json
from contextlib import ExitStack
from pathlib import Path

from import_balancing import BuildLayouts, read_fields
from import_canvas import export, game_object_id, item_slot_binding
from import_scenes import Source


def extract(data, game):
    records = json.loads((game / "balancing/sharedassets1.json").read_text(encoding="utf8"))["records"]
    with ExitStack() as stack:
        source = Source(data, stack)
        for asset in data.glob("*.assets"):
            source.file(asset.name)
        settings = next(row.read_typetree() for row in source.file("globalgamemanagers").objects.values()
                        if row.type.name == "BuildSettings")
        layouts = BuildLayouts(settings["m_Version"])
        layouts.load_local_game(str(data.parent))
        source.env.typetree_generator = layouts
        battle = source.file("level3")
        source_controller = read_fields(battle.objects[26860], layouts)
        owner, view = source.resolve(battle, source_controller["_healthBarPrefab"])
        settings = read_fields(view, layouts)
        root_id = settings["m_GameObject"]["m_PathID"]
        export(source, owner, "battle_health_bar", game, prefab_root=root_id)
        scaler = next(
            read_fields(obj, layouts) for entry in battle.objects[40].read_typetree()["m_Component"]
            if (obj := battle.objects[entry["component"]["m_PathID"]]).type.name == "MonoBehaviour"
            and obj.parse_monobehaviour_head().m_Script.deref_parse_as_object().m_ClassName == "CanvasScaler")
        health_image = read_fields(owner.objects[settings["_healthBarImage"]["m_PathID"]], layouts)
        equipment_parent = game_object_id(source, owner, settings["_equipmentSlotsParent"])
        equipment_slots = []
        for pointer in settings["_itemSlotViews"]:
            slot_owner, slot = source.resolve(owner, pointer)
            equipment_slots.append(item_slot_binding(source, slot_owner, slot, layouts))
        material_owner, material = source.resolve(owner, health_image["m_Material"])
        properties = material.read_typetree()["m_SavedProperties"]
        color_properties, float_properties = dict(properties["m_Colors"]), dict(properties["m_Floats"])
        colors = {name.removeprefix("_"): list(value.values()) for name, value in settings.items() if name.endswith("Color")}
        colors["background"] = list(color_properties["_BackgroundHealthColor"].values())
        colors["separator"] = list(color_properties["_SeparatorColor"].values())
        sockets = {}
        character_owner = source.file("sharedassets1.assets")
        for row in records:
            if row["type"] != "CharacterVisualConfig" or not row["fields"]["Prefab"]["m_PathID"]:
                continue
            file, obj = source.resolve(character_owner, row["fields"]["Prefab"])
            for entry in obj.read_typetree()["m_Component"]:
                component = file.objects[entry["component"]["m_PathID"]]
                if component.type.name != "MonoBehaviour":
                    continue
                script = component.parse_monobehaviour_head().m_Script
                if not script.m_PathID or script.deref_parse_as_object().m_ClassName != "EntityView":
                    continue
                mapping = read_fields(component, layouts)["_attachmentSlotMappings"]
                slot = next((entry["SlotTransform"] for entry in mapping if entry["SlotType"] == 1), None)
                if not slot or not slot["m_PathID"]:
                    continue
                slot_file, transform = source.resolve(file, slot)
                node = transform.read_typetree()
                parent = slot_file.objects[node["m_Father"]["m_PathID"]].read_typetree()
                if parent["m_GameObject"]["m_PathID"] != obj.path_id:
                    raise ValueError(f"Overhead slot {transform.path_id} requires parent transform composition")
                position = node["m_LocalPosition"]
                sockets[str(row["id"])] = {"source": [slot_file.name, transform.path_id],
                                           "position": [position["x"], position["y"], -position["z"]]}
        payload = {
            "source": {"controller": [battle.name, 26860], "prefab": [owner.name, root_id, view.path_id],
                       "material": [material_owner.name, material.path_id]},
            "reference": list(scaler["m_ReferenceResolution"].values()),
            "scale_match": scaler["m_MatchWidthOrHeight"],
            "offset": source_controller["_healthBarVerticalOffset"],
            "death_delay": source_controller["_healthBarDisappearDelay"],
            "health_value_current_only": bool(settings["_onlyShowCurrentHealth"]),
            "damage_duration": 0.30000001192092896,
            "health_per_divider": settings["_healthPerDivider"],
            "minor_dividers_per_major": settings["_minorDividersPerMajor"],
            "minor_thickness": float_properties["_MinorSeparatorThickness"],
            "major_thickness": float_properties["_MajorSeparatorThickness"],
            "colors": colors, "sockets": sockets,
            "equipment_parent": equipment_parent, "equipment_slots": equipment_slots,
        }
        (game / "balancing/battle_health_bars.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    args = parser.parse_args()
    extract(args.data, Path(__file__).resolve().parents[1] / "game")
