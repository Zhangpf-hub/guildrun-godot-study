"""Join Unity Localization's 64-bit string IDs to keys before writing translations."""
import argparse
import csv
from pathlib import Path

import UnityPy


def tables(bundle):
    env = UnityPy.load(str(bundle))
    return [o.read_typetree() for o in env.objects if o.type.name == "MonoBehaviour"]


def extract(data, dest):
    bundles = data / "StreamingAssets" / "aa"
    keys = {}
    for table in tables(next(bundles.rglob("localization-assets-shared*.bundle"))):
        if "m_Entries" in table:
            keys[table["m_TableCollectionName"]] = {e["m_Id"]: e["m_Key"] for e in table["m_Entries"]}
    columns = {}
    for bundle in sorted(bundles.rglob("localization-string-tables-*.bundle")):
        for table in tables(bundle):
            if "m_TableData" not in table:
                continue
            collection, locale = table["m_Name"].rsplit("_", 1)
            translation = columns.setdefault(locale.replace("-", "_"), {})
            for entry in table["m_TableData"]:
                key = keys[collection].get(entry["m_Id"], f'{collection}/{entry["m_Id"]}')
                translation[key] = entry["m_Localized"]
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["keys", *columns])
        for key in sorted(set().union(*columns.values())):
            writer.writerow([key, *(strings.get(key, "") for strings in columns.values())])
    print({locale: len(strings) for locale, strings in columns.items()})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    extract(parser.parse_args().data, Path(__file__).resolve().parents[1] / "game/locale/guildrun.csv")
