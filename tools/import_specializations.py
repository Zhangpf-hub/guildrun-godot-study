"""Resolve the rank-two picker, class growth and ability text in the Steam build."""
import argparse
import json
from contextlib import ExitStack
from pathlib import Path

from import_scenes import Source


def field(row, key):
    return row[f"<{key}>k__BackingField"]


def index(sheet):
    return {field(row, "Id")["_sequentialId"]: row for row in sheet["Entries"]}


def build(data, game):
    records = json.loads((game / "balancing/sharedassets1.json").read_text(encoding="utf8"))
    tables = {r["type"]: r["fields"] for r in records["records"]}
    classes = {k: {"primary": field(v, "PrimaryStat"), "secondary": field(v, "SecondaryStats")}
               for k, v in index(tables["HeroClassSheetHolder"]).items()}
    specs = index(tables["HeroSpecializationSheetHolder"])
    abilities = {}
    for kind in ("Passive", "Active"):
        table = tables[kind + "AbilitySheetHolder"]
        refs = {r["rid"]: r["data"] for r in table["references"]["RefIds"]}
        abilities[kind] = (index(table), refs)
    choices = {}
    with ExitStack() as stack:
        src = Source(data, stack)
        owner = src.file("sharedassets1.assets")
        for choice in tables["HeroSpecializationChoiceSheetHolder"]["Entries"]:
            options = []
            for spec_id in choice["_specializationIds"]:
                spec = specs[spec_id]
                kind = "Passive" if spec["_passiveAbilityId"] >= 0 else "Active"
                ability_id = spec["_" + kind.lower() + "AbilityId"]
                entries, refs = abilities[kind]
                ability = entries[ability_id]
                description = field(ability, "DescriptionLocaKey")
                variables = {v["name"]: refs[v["variable"]["rid"]]["m_Value"]
                             for v in description["_localizedString"]["m_LocalVariables"]}
                sprite_owner, sprite = src.resolve(owner, field(ability, "Icon"))
                icon = f"sprites/{Path(sprite_owner.name).stem}_{sprite.path_id}.png"
                if not (game / icon).exists():
                    sprite.read().image.save(game / icon)
                options.append({"id": spec_id, "name": field(spec, "NameLocaKey")["_key"],
                                "class": spec["_classId"], "passive": spec["_passiveAbilityId"],
                                "active": spec["_activeAbilityId"], "description": description["_key"],
                                "variables": variables, "icon": "res://" + icon})
            choices[choice["_heroId"]] = options
    stats = ["Health", "ManaRegen", "Defense", "Attack", "Magic", "AttackSpeed", "Crit"]
    growth = {}
    for prefix in ("", "Primary", "Secondary"):
        amounts = {}
        for name in stats:
            suffix = "PercentageIncreasePerRank" if name == "Health" else "FlatIncreasePerRank"
            value = tables["HeroesSingleton"][prefix + name + suffix]
            amounts["MaxHealth" if name == "Health" else name] = value["RawValue"] if isinstance(value, dict) else value
        growth[prefix.lower() or "base"] = amounts
    result = {"choices": choices, "classes": classes, "growth": growth}
    (game / "balancing/hero_ranks.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    build(parser.parse_args().data, Path(__file__).resolve().parents[1] / "game")
