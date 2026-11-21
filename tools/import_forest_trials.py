"""Import Act 1 forest trial crossroads, reward pools and event art from the Steam data."""
import argparse
import json
from contextlib import ExitStack
from pathlib import Path

from import_first_battle import field, save_sprite
from import_scenes import Source


def extract(data, game):
    records = json.loads((game / "balancing/sharedassets1.json").read_text(encoding="utf8"))["records"]
    tables = {row["type"]: row["fields"] for row in records}

    def index(name):
        return {field(row, "Id")["_sequentialId"]: row for row in tables[name + "SheetHolder"]["Entries"]}

    event_pools = index("EventPool")
    events = index("Event")
    locked_catalog = json.loads((game / "balancing/regular_shop.json").read_text(encoding="utf8"))["locked_catalog"]
    roads = {}
    for road_id in (34, 35, 36):
        roads[road_id] = [
            [[row["_eventID"], field(row, "Weight")]
             for row in field(event_pools[path["_eventPoolId"]], "WeightedEvents")
             if field(row, "Weight") > 0 and not field(events[row["_eventID"]], "DisabledInGame")]
            for path in field(index("Crossroads")[road_id], "Paths")
        ]

    info = {}
    pools = {}
    with ExitStack() as stack:
        source = Source(data, stack)
        owner = source.file("sharedassets1.assets")
        # CrossroadsController._fallbackEventIcon on level3 PathID 1.
        fallback_icon = save_sprite(source, source.file("level3"), {"m_FileID": 2, "m_PathID": 495}, game)
        for event_id in sorted({i for paths in roads.values() for path in paths for i, _ in path}):
            row = events[event_id]
            info[event_id] = {"kind": "forest_trial"}
            for key, prop in (("icon", "EventIcon"), ("art", "EventArtwork")):
                pointer = field(row, prop)
                info[event_id][key] = save_sprite(source, owner, pointer, game) if pointer["m_PathID"] else ""

        for kind, pool_id, weights, id_key in (
            ("Relic", 102, "WeightedRelics", "_relicId"),
            ("Item", 1, "WeightedRewards", "_elementId"),
        ):
            entries = index(kind)
            rows = field(index(kind + "Pool")[pool_id], weights)
            pools[kind.lower()] = [
                [row[id_key], field(row, "Weight"), locked_catalog.get(f"{kind}_{row[id_key]}", {}).get("xp", 0)]
                for row in rows if field(row, "Weight") > 0 and not field(entries[row[id_key]], "DisabledInGame")
            ]

    payload = {"roads": roads, "events": info, "pools": pools, "fallback_icon": fallback_icon}
    (game / "balancing/forest_trials.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    extract(parser.parse_args().data, Path(__file__).resolve().parents[1] / "game")
