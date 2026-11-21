"""Extract A/S pool inputs from the existing audited balancing snapshot."""
import argparse
import json
from pathlib import Path

def field(row, key):
    return row[f"<{key}>k__BackingField"]

def identifier(row):
    return field(row, "Id")["_sequentialId"]

def export(source):
    tables = {r["type"]: r for r in json.loads(source.read_text(encoding="utf-8"))["records"]}
    mods = tables["RankModifierSheetHolder"]
    enabled = {identifier(row): field(row, "NameLocaKey")["_key"]
               for row in mods["fields"]["Entries"] if not field(row, "DisabledInGame")}
    pools = tables["RankModifierPoolSheetHolder"]
    selections = {}
    for row in pools["fields"]["Entries"]:
        rank = field(row, "TargetRank")
        if rank not in (3, 4) or field(row, "DisabledInGame"):
            continue
        weights = [[w["_elementId"], field(w, "Weight")] for w in field(row, "WeightedRankModifiers")
                   if w["_elementId"] in enabled and field(w, "Weight") > 0]
        key = f"{row['_targetClassID']}:{rank}"
        if key in selections:
            raise ValueError(f"Duplicate pool for {key}")
        selections[key] = {"id": identifier(row), "weights": weights}
    return {"pool_holder": pools["id"], "modifier_holder": mods["id"],
            "enabled": enabled, "pools": selections}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    args.out.write_text(json.dumps(export(args.snapshot), indent=2) + "\n", encoding="utf-8")
