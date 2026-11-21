"""Resolve Act 1's endless crossroads and its event reward references from the Steam build."""
import argparse
import json
from contextlib import ExitStack
from pathlib import Path

from import_first_battle import field, save_sprite
from import_scenes import Source


def extract(data, game):
    records = json.loads((game / "balancing/sharedassets1.json").read_text(encoding="utf8"))["records"]
    tables = {r["type"]: r["fields"] for r in records}

    def index(sheet):
        return {field(r, "Id")["_sequentialId"]: r for r in tables[sheet + "SheetHolder"]["Entries"]}

    act = next(r["fields"] for r in records if r["type"] == "ActEntry" and r["fields"]["Title"] == "Act1Entry")
    road_id = act["_endlessCrossroadsId"]
    event_pools, event_rows = index("EventPool"), index("Event")
    paths = []
    for path in field(index("Crossroads")[road_id], "Paths"):
        paths.append([[e["_eventID"], field(e, "Weight")]
                      for e in field(event_pools[path["_eventPoolId"]], "WeightedEvents") if field(e, "Weight")])
    refs = {r["rid"]: r["data"] for r in tables["EventSheetHolder"]["references"]["RefIds"]}
    mods, mod_pools = index("StatMod"), index("StatModPool")
    events, pools = {}, {"item": {}, "relic": {}, "hero": {}}
    catalog = json.loads((game / "balancing/regular_shop.json").read_text(encoding="utf8"))["catalog"]
    with ExitStack() as stack:
        src = Source(data, stack)
        owner = src.file("sharedassets1.assets")
        for event_id in sorted({i for path in paths for i, _ in path}):
            row = event_rows[event_id]
            reward = refs[field(field(row, "EventChoices")[0], "Rewards")[0]["rid"]]
            info = {"kind": "choice"}
            for key, prop in [("icon", "EventIcon"), ("art", "EventArtwork")]:
                pointer = field(row, prop)
                info[key] = save_sprite(src, owner, pointer, game) if pointer["m_PathID"] else ""
            if field(reward, "RewardType") == 105:
                modifier, = field(mod_pools[reward["_entryId"]], "WeightedStatMods")
                mod_id = modifier["_elementId"]
                info.update(modifier=mod_id, target_stat=field(mods[mod_id], "TargetStat"),
                            amount_q16=field(mods[mod_id], "Value")["RawValue"])
            elif event_id in (2001, 2002, 2003, 2012):
                kind = {2001: "Item", 2002: "Relic", 2003: "Relic", 2012: "Hero"}[event_id]
                pool_id = reward["_entryId"]
                info["pool"] = pool_id
                entries = field(index(kind + "Pool")[pool_id], "WeightedRelics" if kind == "Relic" else "WeightedRewards")
                key = "_relicId" if kind == "Relic" else "_elementId"
                pools[kind.lower()][pool_id] = [[v[key], field(v, "Weight")] for v in entries
                                                 if field(v, "Weight") and f"{kind}_{v[key]}" in catalog]
            events[event_id] = info
    output = {"id": road_id, "paths": paths, "events": events, "pools": pools}
    (game / "balancing/endless_crossroads.json").write_text(json.dumps(output, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    extract(parser.parse_args().data, Path(__file__).resolve().parents[1] / "game")
