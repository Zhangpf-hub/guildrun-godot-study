"""Extract the normal opening draft and progression thresholds from the installed demo."""
import argparse
import json
from contextlib import ExitStack
from pathlib import Path

from import_first_battle import field, save_sprite
from import_scenes import Source


def extract(data, game):
    records = json.loads((game / "balancing/sharedassets1.json").read_text(encoding="utf8"))["records"]
    tables = {record["type"]: record["fields"] for record in records}
    visuals = {record["id"]: record["fields"] for record in records if record["type"] == "CharacterVisualConfig"}
    selection = tables["RewardSelectionSingleton"]
    unlocks = tables["ProgressionUnlocksSingleton"]
    xp = {key: unlocks[key] for key in ("StageCompletionXpReward", "VictoryXpReward",
          "RegularEncounterWonXpReward", "EndlessCycleXpReward")}
    gates = {kind: {} for kind in ("hero", "relic", "item")}
    token_slots = []
    for entry in unlocks["_unlocks"]:
        threshold = field(entry, "XpThreshold")
        for kind, mapping in gates.items():
            mapping.update({key: threshold for key in entry["_" + kind + "Ids"]})
        if field(entry, "BonusTokenSlots"):
            token_slots.append([threshold, field(entry, "BonusTokenSlots")])
    pools = {}
    reward_pools = {}
    bonus_text = {}
    quests = {}
    # StarterKitEvent..cctor initializes these arrays from its assembly's FieldRVA data.
    kit = dict(shards=[720, 723, 724], items=[list(range(725, 732)), [734], [771]],
               stats=[list(range(736, 743)), list(range(757, 764)), [764, *range(777, 783)]],
               stat_types=[6, 1, 4, 11, 9, 12, 7])
    kit_ids = {*kit["shards"], *(key for group in kit["items"] + kit["stats"] for key in group)}
    with ExitStack() as stack:
        source = Source(data, stack)
        file = source.file("sharedassets1.assets")
        for kind, pool_id in (("Hero", selection["_initialSelectionHeroPoolID"]),
                              ("Relic", selection["_basicInitialSelectionRelicPoolID"])):
            rows = {field(row, "Id")["_sequentialId"]: row for row in tables[kind + "SheetHolder"]["Entries"]}
            pool = next(row for row in tables[kind + "PoolSheetHolder"]["Entries"]
                        if field(row, "Id")["_sequentialId"] == pool_id)
            entries = []
            for member in field(pool, "WeightedRewards" if kind == "Hero" else "WeightedRelics"):
                key = member["_elementId" if kind == "Hero" else "_relicId"]
                row = rows[key]
                if field(row, "DisabledInGame") or field(member, "Weight") <= 0:
                    continue
                sprite = (visuals[field(row, "VisualConfig")["m_PathID"]]["SquarePortraitSprite"]
                          if kind == "Hero" else field(row, "Icon"))
                entries.append(dict(id=key, weight=field(member, "Weight"), xp=gates[kind.lower()].get(key, 0),
                                    icon=save_sprite(source, file, sprite, game)))
            pools[kind.lower()] = entries
        ability_pools = [row["_itemPoolId"] for row in tables["HeroesSingleton"]["FionaItemPoolPerRank"]]
        for kind, pool_ids in (("Item", [*ability_pools, 4, 6, 8, 10, 12, 14, 16, 18, *range(20, 27), *range(31, 38)]),
                               ("Relic", [101, 102])):
            rows = {field(row, "Id")["_sequentialId"]: row for row in tables[kind + "SheetHolder"]["Entries"]}
            for pool in tables[kind + "PoolSheetHolder"]["Entries"]:
                pool_id = field(pool, "Id")["_sequentialId"]
                if pool_id not in pool_ids:
                    continue
                entries = []
                for member in field(pool, "WeightedRewards" if kind == "Item" else "WeightedRelics"):
                    key = member["_elementId" if kind == "Item" else "_relicId"]
                    if field(rows[key], "DisabledInGame") or field(member, "Weight") <= 0:
                        continue
                    save_sprite(source, file, field(rows[key], "Icon"), game)
                    entries.append([key, field(member, "Weight"), gates[kind.lower()].get(key, 0)])
                reward_pools[f"{kind}_{pool_id}"] = entries
        relics = tables["RelicSheetHolder"]
        refs = {str(v["rid"]): v for v in relics["references"]["RefIds"]}
        for entry in relics["Entries"]:
            key = field(entry, "Id")["_sequentialId"]
            if key not in kit_ids and not any(row["id"] == key for row in pools["relic"]):
                continue
            texts = {}
            for label in ("Description", "QuestDescription", "QuestRewardDescription"):
                localization = field(entry, label + "LocaKey")["_localizedString"]
                if localization["m_TableEntryReference"]["m_Key"]:
                    texts[label] = {v["name"]: str(refs[str(v["variable"]["rid"])]["data"]["m_Value"])
                                    for v in localization["m_LocalVariables"]}
            bonus_text[key] = texts
            quest = refs[str(field(entry, "QuestEffect")["rid"])]
            if quest["type"]["class"] == "QuestEffect":
                row = quest["data"]
                condition = refs[str(row["_condition"]["rid"])]
                reward = refs[str(field(row, "Rewards")[0]["rid"])]["data"]
                effect = refs[str(field(reward, "RewardEffects")[0]["rid"])]["data"]
                actions = [refs[str(pointer["rid"])] for pointer in effect["_actions"]]
                quests[key] = dict(trigger=field(row, "Trigger"), target=row["_requiredProgress"],
                                   condition=condition["type"]["class"], params=condition["data"],
                                   actions=[dict(kind=a["type"]["class"], values=a["data"]) for a in actions])
        kit_event = next(row for row in tables["EventSheetHolder"]["Entries"] if field(row, "Id")["_sequentialId"] == 506)
        art = {}
        for name, label in (("icon", "EventIcon"), ("art", "EventArtwork")):
            pointer = field(kit_event, label)
            art[name] = save_sprite(source, file, pointer, game) if pointer["m_PathID"] else ""
        kit["road"] = dict(id=23, paths=[[[506, 1]]], events={"506": dict(kind="starter_kit", **art)})
    result = dict(pools=pools, choices=selection["InitialSelectionSize"], starting_shards=tables["PlayerSingleton"]["StartingShards"],
                  max_tokens=selection["MaxBonusTokens"], locked_slots=unlocks["TotalUnlockableBonusTokenSlots"],
                  token_slots=token_slots, xp=xp, rewards=reward_pools, descriptions=bonus_text, quests=quests, kit=kit)
    (game / "balancing/opening.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    extract(parser.parse_args().data, Path(__file__).resolve().parents[1] / "game")
