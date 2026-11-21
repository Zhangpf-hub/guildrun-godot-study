"""Read the regular tutorial crossroads and their event reward pools."""
import argparse
import json
from contextlib import ExitStack
from pathlib import Path

from import_first_battle import field, save_sprite
from import_scenes import Source


def extract(data, game, floor_index=1, chunk_index=0):
    records = json.loads((game / "balancing/sharedassets1.json").read_text(encoding="utf8"))["records"]
    tables = {r["type"]: r["fields"] for r in records}

    def index(name):
        return {field(r, "Id")["_sequentialId"]: r for r in tables[name + "SheetHolder"]["Entries"]}

    # ActEntry comes once per act in the serialized asset.
    act = next(r["fields"] for r in records if r["type"] == "ActEntry" and r["fields"]["Title"] == "Act1Entry")
    floors = field(act["ActChunks"][chunk_index], "FloorNodes")
    floor = floors[floor_index]
    filename = {(0, 1): "second_crossroads.json", (0, 3): "fourth_crossroads.json",
                (1, 0): "seventh_crossroads.json", (1, 3): "tenth_crossroads.json"}[chunk_index, floor_index]
    use_unlocks = chunk_index > 0 or floor_index == 3
    pool = index("CrossroadsPool")[floor["_crossroadsId"]]
    road_entry, = field(pool, "WeightedCrossroads")
    road_id = road_entry["_elementId"]
    paths = []
    for path in field(index("Crossroads")[road_id], "Paths"):
        paths.append([[r["_eventID"], field(r, "Weight")] for r in
                      field(index("EventPool")[path["_eventPoolId"]], "WeightedEvents")])

    item_pools = index("ItemPool")
    relic_pools = index("RelicPool")
    pools = {"item": {}, "relic": {}}
    for kind, table, key, entry_key, ids in (
        ("item", item_pools, "WeightedRewards", "_elementId",
         [1, 2, 3, 30, 110, 112] if use_unlocks else [1, 2, 39, 40, 41, 110, 112]),
        ("relic", relic_pools, "WeightedRelics", "_relicId",
         [101, 102, 103, 111, 112, 113] if use_unlocks else [61, 62, 63, 101, 102, 111, 112, 113]),
    ):
        for pool_id in ids:
            pools[kind][pool_id] = [[r[entry_key], field(r, "Weight")] for r in field(table[pool_id], key)]
            if use_unlocks:
                entries = index(kind.capitalize())
                locked = {i for unlock in tables["ProgressionUnlocksSingleton"]["_unlocks"]
                          for i in unlock["_" + kind + "Ids"]}
                pools[kind][pool_id] = [[i, w] for i, w in pools[kind][pool_id]
                                        if w > 0 and i not in locked and not field(entries[i], "DisabledInGame")]

    events = {}
    with ExitStack() as stack:
        src = Source(data, stack)
        file = src.file("sharedassets1.assets")
        for event_id, _ in paths[0]:
            row = index("Event")[event_id]
            events[event_id] = {"kind": "choice"}
            for key, attr in (("art", "EventArtwork"), ("icon", "EventIcon")):
                ptr = field(row, attr)
                events[event_id][key] = save_sprite(src, file, ptr, game) if ptr["m_PathID"] else ""
        for kind in pools:
            entries = index(kind.capitalize())
            all_ids = {i for pool in pools[kind].values() for i, _ in pool}
            if kind == "item":
                all_ids.update(range(301, 308))
            if chunk_index == 1:
                rewards = range(308, 322) if kind == "item" else range(621, 635)
                locked = {i for unlock in tables["ProgressionUnlocksSingleton"]["_unlocks"]
                          for i in unlock["_" + kind + "Ids"]}
                available = [i for i in rewards if i not in locked and not field(entries[i], "DisabledInGame")]
                pools[kind]["class_rewards"] = available
                all_ids.update(available)
            for i in all_ids:
                save_sprite(src, file, field(entries[i], "Icon"), game)
    if use_unlocks:
        pools["stat"] = {i: [[r["_elementId"], field(r, "Weight")]
                             for r in field(index("StatModPool")[i], "WeightedStatMods")] for i in [4, 5]}
    road_data = dict(id=road_id, paths=paths, events=events, pools=pools)
    if use_unlocks:
        road_data["remaining_victories"] = len(floors) - floor_index - 1
        pools["max_rank"] = next(r["MaxRank"] for r in tables["EventsSingleton"]["_maxRankUpPerChunk"]
                                 if r["Chunk"] == chunk_index)
    (game / "balancing" / filename).write_text(json.dumps(road_data, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    parser.add_argument("--floor-index", type=int, choices=[0, 1, 3], default=1)
    parser.add_argument("--chunk-index", type=int, choices=[0, 1], default=0)
    args = parser.parse_args()
    extract(args.data, Path(__file__).resolve().parents[1] / "game", args.floor_index, args.chunk_index)
