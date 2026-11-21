"""Export enemy modifiers and reward pools from the act's challenge crossroads."""
import argparse
import json
from contextlib import ExitStack
from pathlib import Path

from import_first_battle import field, save_sprite
from import_scenes import Source


def extract(data, game):
    records = json.loads((game / "balancing/sharedassets1.json").read_text(encoding="utf8"))["records"]
    tables = {r["type"]: r["fields"] for r in records}
    act = next(r["fields"] for r in records if r["type"] == "ActEntry" and r["fields"]["Title"] == "Act1Entry")
    pools = {field(r, "Id")["_sequentialId"]: r for r in tables["RelicPoolSheetHolder"]["Entries"]}
    relics = {field(r, "Id")["_sequentialId"]: r for r in tables["RelicSheetHolder"]["Entries"]}
    locked = {i for row in tables["ProgressionUnlocksSingleton"]["_unlocks"] for i in row["_relicIds"]}
    floors, weighted, catalog = {}, {}, {}
    with ExitStack() as stack:
        src = Source(data, stack)
        owner = src.file("sharedassets1.assets")
        for chunk_no, chunk in enumerate(act["ActChunks"]):
            for floor_no, floor in enumerate(field(chunk, "FloorNodes")):
                if field(floor, "EventOverrideType") != 3:
                    continue
                choices = field(field(floor, "StageModifierCrossroadsData"), "ModifierChoices")
                floors[f"{chunk_no}/{floor_no}"] = choices
                for choice in choices:
                    for pool in [choice["_enemyRelicPoolId"], *choice["_rewardRelicPoolIds"]]:
                        if pool in weighted:
                            continue
                        weighted[pool] = []
                        for entry in field(pools[pool], "WeightedRelics"):
                            i = entry["_relicId"]
                            weight = field(entry, "Weight")
                            if not weight or i in locked or field(relics[i], "DisabledInGame"):
                                continue
                            weighted[pool].append([i, weight])
                            if i not in catalog:
                                icon = field(relics[i], "Icon")
                                catalog[i] = dict(icon=save_sprite(src, owner, icon, game) if icon["m_PathID"] else "",
                                                  rarity=field(relics[i], "Rarity"))
    (game / "balancing/challenge_roads.json").write_text(
        json.dumps(dict(floors=floors, pools=weighted, relics=catalog), indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    extract(parser.parse_args().data, Path(__file__).resolve().parents[1] / "game")
