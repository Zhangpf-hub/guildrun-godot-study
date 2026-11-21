"""Resolve the bottom roster's four skill slots and sprite source references."""
import argparse
from contextlib import ExitStack
import json
from pathlib import Path

from import_scenes import Source
from import_first_battle import save_sprite
from import_balancing import BuildLayouts, read_fields
from import_specializations import field, index


ICON_FIELD = "<Icon>k__BackingField"
ABILITY_SHEETS = {
    "active": "ActiveAbility",
    "passive": "PassiveAbility",
    "rank_modifier": "RankModifier",
}
VIEW_IDS = {
    "deployed": (11399, 75114, 74286),
    "reserve": (9576, 74584, 75392),
}


def view_sources(source, data, game):
    settings = next(obj.read_typetree() for obj in source.file("globalgamemanagers").objects.values()
                    if obj.type.name == "BuildSettings")
    layouts = BuildLayouts(settings["m_Version"])
    layouts.load_local_game(str(data.parent))
    source.env.typetree_generator = layouts
    for asset in sorted(data.glob("*.assets")):
        source.file(asset.name)
    owner = source.file("sharedassets3.assets")

    def reference(asset, pointer):
        target_file, target = source.resolve(asset, pointer)
        result = {"asset_file": target_file.name, "path_id": target.path_id}
        if target.type.name == "Sprite":
            result["texture"] = save_sprite(source, asset, pointer, game)
        return result

    def image(pointer):
        target_file, target = source.resolve(owner, pointer)
        fields = read_fields(target, layouts)
        return {**reference(owner, pointer), "game_object": fields["m_GameObject"]["m_PathID"],
                "authored_sprite": reference(target_file, fields["m_Sprite"])}

    views = {}
    for group, (panel, card, container) in VIEW_IDS.items():
        fields = read_fields(owner.objects[container], layouts)
        rendered_slots = []
        for pointer in fields["_abilities"]:
            slot = read_fields(owner.objects[pointer["m_PathID"]], layouts)
            rendered_slots.append({
                "ability_view": reference(owner, pointer),
                "frame_target": image(slot["_frameImage"]),
                "icon_target": image(slot["_abilityIcon"]),
                "frames": {
                    "empty": reference(owner, slot["_emptyFrame"]),
                    "active": reference(owner, slot["_activeAbilityFrame"]),
                    "passive": reference(owner, slot["_abilityFrame"]),
                    "rank_modifier": reference(owner, slot["_abilityFrame"]),
                },
            })
        card_fields = read_fields(owner.objects[card], layouts)
        views[group] = {"show_abilities": bool(card_fields["_showAbilitiesPanel"]),
                        "asset_file": owner.name, "panel_game_object": panel, "bottom_hero_view": card,
                        "abilities_view": container,
                        "ability_views": [slot["ability_view"]["path_id"] for slot in rendered_slots],
                        "slot_render": rendered_slots}
    return views


def icon_source(source, table_file, holder_id, entry_id, entry, game):
    pointer = entry[ICON_FIELD]
    reference = {
        "owner_file": table_file.name,
        "holder_path_id": holder_id,
        "entry_id": entry_id,
        "field": ICON_FIELD,
        "file_id": pointer["m_FileID"],
        "path_id": pointer["m_PathID"],
    }
    if not pointer["m_PathID"]:
        return {"ref": reference, "icon": ""}
    asset, sprite = source.resolve(table_file, pointer)
    if sprite.type.name != "Sprite":
        raise ValueError(f"{asset.name}:{sprite.path_id} is {sprite.type.name}, expected Sprite")
    reference["asset_file"] = asset.name
    reference["asset_path_id"] = sprite.path_id
    return {"ref": reference, "icon": save_sprite(source, table_file, pointer, game)}


def export(data, game, output):
    records = json.loads((game / "balancing/sharedassets1.json").read_text(encoding="utf-8"))["records"]
    tables = {row["type"]: row for row in records}
    choices = {row["_heroId"]: row["_specializationIds"]
               for row in tables["HeroSpecializationChoiceSheetHolder"]["fields"]["Entries"]}
    heroes = {}
    specializations = {}
    wanted = {"active": set(), "passive": set()}
    for hero_id, hero in sorted(index(tables["HeroSheetHolder"]["fields"]).items()):
        kind = "active" if field(hero, "StartWithActiveAbility") else "passive"
        ability = hero[f"_{kind}AbilityID"]
        if ability >= 0:
            wanted[kind].add(ability)
        heroes[hero_id] = {"starting": {"kind": kind, "id": ability},
                          "specialization_ids": choices.get(hero_id, [])}
    for spec_id, spec in sorted(index(tables["HeroSpecializationSheetHolder"]["fields"]).items()):
        known = {kind: spec[f"_{kind}AbilityId"] for kind in ("active", "passive")}
        for kind, ability in known.items():
            if ability >= 0:
                wanted[kind].add(ability)
        # InitializeAbilityViews sets the active first and then the passive in the same slot.
        display_kind = "passive" if known["passive"] >= 0 else "active"
        display = {"kind": display_kind, "id": known[display_kind]} if known[display_kind] >= 0 else None
        specializations[spec_id] = {"display": display, **known}

    ability_icons = {}
    with ExitStack() as stack:
        source = Source(data, stack)
        table_file = source.file("sharedassets1.assets")
        for kind, table_name in ABILITY_SHEETS.items():
            holder = tables[table_name + "SheetHolder"]
            entries = index(holder["fields"])
            ids = wanted.get(kind, entries.keys())
            ability_icons[kind] = {
                entry_id: icon_source(source, table_file, holder["id"], entry_id, entries[entry_id], game)
                for entry_id in sorted(ids)
            }
        views = view_sources(source, data, game)
    result = {
        "slots": {"count": 4, "starting": 0, "specialization": 1, "rank_modifier_index_offset": -1},
        "views": views,
        "heroes": heroes,
        "specializations": specializations,
        "icons": ability_icons,
    }
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    game = Path(__file__).resolve().parents[1] / "game"
    parser.add_argument("--output", type=Path, default=game / "balancing/bottom_roster_abilities.json")
    args = parser.parse_args()
    export(args.data, game, args.output)
