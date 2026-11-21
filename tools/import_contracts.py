"""Resolve normal contracts, their localization and menu icons from the demo."""
import argparse
import json
import re
from contextlib import ExitStack
from pathlib import Path

from import_first_battle import save_sprite
from import_scenes import Source
from import_translations import tables


def extract(data, game):
    records = json.loads((game / "balancing/sharedassets1.json").read_text(encoding="utf8"))["records"]
    by_id = {r["id"]: r for r in records}
    settings = next(r["fields"] for r in records if r["type"] == "DifficultiesSingleton")
    shared = next((data / "StreamingAssets").rglob("localization-assets-shared*.bundle"))
    ui = next(t for t in tables(shared) if t.get("m_TableCollectionName") == "UI")
    keys = {int(e["m_Id"]): e["m_Key"] for e in ui["m_Entries"]}
    canvas = (game / "UI/MainMenu.tscn").read_text(encoding="utf8")
    resources = {ident: path for path, ident in re.findall(r'path="([^"]+)" id="([^"]+)"', canvas)}
    def selected_icon(item):
        path = "Canvas/Root/DifficultyPanel/Content/TopGroup/DifficultiesList/" + item + "/SelectedBorderImg/Icon"
        block = re.search(r'\[node name="UnityImage" [^\n]*parent="' + re.escape(path) + r'"\][^\[]+', canvas)[0]
        return resources[re.search(r'texture = ExtResource\("([^"]+)"\)', block)[1]]

    contracts = []
    for index, row in enumerate(settings["_difficulties"]):
        # DifficultyUIController._difficulties in level2 has six direct children, then the SSS/Red Rift group.
        item = "Group_Mode/DifficultyItem" if index == 6 else "DifficultyItem" + (f"_{index}" if index else "")
        icon = selected_icon(item)
        modifiers = {}
        for pointer in row["_modifiers"]:
            record = by_id[pointer["m_PathID"]]
            modifiers[record["type"]] = {k: v for k, v in record["fields"].items()
                                         if k not in ("Id", "Title", "DisabledInGame", "references")}
        def label(name):
            return keys[int(row[f"<{name}>k__BackingField"]["m_TableEntryReference"]["m_KeyId"])]
        contracts.append({"name": label("DisplayName"), "description": label("DisplayDescription"),
                          "stage_index": row["<StageDifficultyIndex>k__BackingField"], "icon": icon, "modifiers": modifiers})
    audio = next(r["fields"] for r in records if r["type"] == "AudioSingleton")
    menu = next(row for row in audio["_scopeBgmMappings"] if row["Scope"] == "MainMenu")
    rift = {key: value for key, value in settings.items() if key.startswith("Challenge") or key == "_anchorItemId"}
    rift["icon"] = selected_icon("Group_Mode/DifficultyItem_RR")
    item_sheet = next(r["fields"] for r in records if r["type"] == "ItemSheetHolder")
    anchor = next(row for row in item_sheet["Entries"] if row["<Id>k__BackingField"]["_sequentialId"] == rift["_anchorItemId"])
    with ExitStack() as stack:
        source = Source(data, stack)
        rift["anchor_icon"] = save_sprite(source, source.file("sharedassets1.assets"), anchor["<Icon>k__BackingField"], game)
    output = {"score_per_difficulty": settings["LeaderboardScorePerDifficulty"], "contracts": contracts, "red_rift": rift,
              "menu_audio": [event["Path"] for event in menu["FmodEvents"]]}
    (game / "balancing/contracts.json").write_text(json.dumps(output, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    extract(parser.parse_args().data, Path(__file__).resolve().parents[1] / "game")
