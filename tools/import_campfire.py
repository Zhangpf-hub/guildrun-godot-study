"""Read direct forest events, their artwork and authored rewards."""
import argparse
import json
from contextlib import ExitStack
from pathlib import Path

from import_first_battle import field, save_sprite
from import_scenes import Source


def extract(data, game, chunk_index=0, floor_index=4):
    records = json.loads((game / "balancing/sharedassets1.json").read_text(encoding="utf8"))["records"]
    tables = {row["type"]: row["fields"] for row in records}

    def entry(sheet, entry_id):
        return next(row for row in tables[sheet + "SheetHolder"]["Entries"]
                    if field(row, "Id")["_sequentialId"] == entry_id)

    act = next(row["fields"] for row in records if row["type"] == "ActEntry"
               and row["fields"]["Title"] == "Act1Entry")
    floor = field(act["ActChunks"][chunk_index], "FloorNodes")[floor_index]
    road_id = floor["_crossroadsId"]
    path, = field(entry("Crossroads", road_id), "Paths")
    event_id = path["_eventId"]
    event = entry("Event", event_id)
    with ExitStack() as stack:
        source = Source(data, stack)
        owner = source.file("sharedassets1.assets")
        art = {}
        for key, prop in [("icon", "EventIcon"), ("art", "EventArtwork")]:
            ptr = field(event, prop)
            art[key] = save_sprite(source, owner, ptr, game) if ptr["m_PathID"] else ""
        settings = tables["EventsSingleton"]
        if event_id == 1013:
            filename = "guild_banner"
            pools = {"reward_count": settings["RelicsToShowOnClassEvent"], "banners": {}}
            locked = {i for row in tables["ProgressionUnlocksSingleton"]["_unlocks"] for i in row["_relicIds"]}
            for profession in settings["ClassEventSettings"]:
                rewards = []
                for design in field(profession, "Inputs"):
                    for flag in field(design, "Outputs"):
                        relic = flag["_relicId"]
                        row = entry("Relic", relic)
                        if relic not in locked and not field(row, "DisabledInGame"):
                            rewards.append(relic)
                            save_sprite(source, owner, field(row, "Icon"), game)
                pools["banners"][profession["_classId"]] = rewards
        else:
            filename = "first_campfire" if event_id == 600 else "second_campfire"
            rest, = field(entry("RelicPool", 83), "WeightedRelics")
            rank = next(row["MaxRank"] for row in settings["_maxRankUpPerChunk"] if row["Chunk"] == chunk_index)
            pools = dict(max_rank=rank, rested=rest["_relicId"])
    result = dict(id=road_id, paths=[[[event_id, 1]]], events={event_id: dict(kind="choice", **art)},
                  pools=pools)
    (game / "balancing" / (filename + ".json")).write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    parser.add_argument("--chunk-index", type=int, choices=[0, 1], default=0)
    parser.add_argument("--floor-index", type=int, choices=[2, 4], default=4)
    args = parser.parse_args()
    extract(args.data, Path(__file__).resolve().parents[1] / "game", args.chunk_index, args.floor_index)
