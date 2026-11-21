"""Export clock definitions from initialized RankModifierEntry records of build 26551710."""

import argparse
import json
import struct
from pathlib import Path


def rush_action(effect):
    action, = effect["0x128_children"]
    fields = bytes.fromhex(action["fields_0x10_to_0x30"])
    kind = action["type"]
    if kind == "ModifyStatPercentAction":
        return {"kind": "percent", "stat": struct.unpack_from("<i", fields)[0],
                "value_q16": struct.unpack_from("<q", fields, 8)[0]}
    if kind == "ApplyShieldFromDamageDealtAction":
        ratio, duration = struct.unpack_from("<qq", fields)
        return {"kind": "damage_shield", "ratio_q16": ratio, "duration_q16": duration}
    if kind == "ModifyStatFromShardsAction":
        stat, scale, interval = struct.unpack_from("<i4xqq", fields)
        return {"kind": "wallet_stat", "stat": stat, "value_q16": scale, "interval_q16": interval}
    raise ValueError(f"Unmapped Rush action {kind}")


def convert(rows):
    durations = {}
    clocks = {}
    for rank_id, effects in rows.items():
        for index, effect in enumerate(effects):
            reserve = effect["class"] == "ReserveOnlyModularEffect"
            keyword = effect["keyword"]
            if keyword in (1, 2):
                duration = effect["rush_q16"] if keyword == 1 else effect["stall_q16"]
                clock = {
                    "effect": index, "keyword": keyword, "duration_q16": duration,
                    "reserve": reserve, "trigger": effect["trigger"],
                }
                if keyword == 1:
                    clock.update(target=effect["target"], target_class=effect["class_id"], action=rush_action(effect))
                clocks.setdefault(rank_id, []).append(clock)
            for action in effect.get("0x128_children", []):
                name = action["type"]
                if name not in ("IncreasePlayerRushDurationAction", "ReducePlayerStallDurationAction"):
                    continue
                if (effect["trigger"], effect["attachment"], effect["target"], effect["0x120"]) != (1, 0, 1000, "NoCondition"):
                    raise ValueError(f"Unexpected duration provider for {rank_id}")
                fields = bytes.fromhex(action["fields_0x10_to_0x30"])
                shift = struct.unpack_from("<i", fields)[0] << 16 if name.startswith("Increase") else -struct.unpack_from("<q", fields)[0]
                durations.setdefault(rank_id, []).append({
                    "keyword": 1 if name.startswith("Increase") else 2, "shift_q16": shift, "reserve": reserve,
                })
    return {"duration_modifiers": durations, "clocks": clocks}


def ordinary_sources(generated, authored):
    origins = {
        "ActiveAbilityEffectsProvider": "ability", "PassiveAbilityEffectsProvider": "passive",
        "ItemEffectsProvider": "item", "RelicEffectsProvider": "relic",
    }
    sources = {name: {} for name in origins.values()}
    for effect in generated:
        provider, method = effect["provider"].split(".", 1)
        if provider not in origins or method in ("PopulateEnemy", "PopulateActBoss"):
            continue
        entry = str(effect["entry"])
        sources[origins[provider]].setdefault(entry, []).append({
            "keyword": 1 if effect["keyword"] == "rush" else 2,
            "duration_q16": effect["seconds_q16"], "reserve": effect["reserve_only"],
        })
    generated_items = set(sources["item"])
    for effect in authored:
        if effect["sheet"] != "ItemSheetHolder" or effect["classification"] != "matching_keyword_definition":
            continue
        entry = str(effect["entry"])
        if entry in generated_items or not effect["path"].startswith("_specialEffects/"):
            continue
        sources["item"].setdefault(entry, []).append({
            "keyword": 1 if effect["keyword"] == "rush" else 2,
            "duration_q16": effect["seconds_q16"], "reserve": False,
        })
    return sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("initialized_rows", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--generated", type=Path, required=True)
    parser.add_argument("--authored", type=Path, required=True)
    args = parser.parse_args()
    rows = json.loads(args.initialized_rows.read_text(encoding="utf-8-sig"))
    data = convert(rows)
    generated = [json.loads(line) for line in args.generated.read_text(encoding="utf-8-sig").splitlines()]
    authored = [json.loads(line) for line in args.authored.read_text(encoding="utf-8-sig").splitlines()]
    data["sources"] = ordinary_sources(generated, authored)
    args.output.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
