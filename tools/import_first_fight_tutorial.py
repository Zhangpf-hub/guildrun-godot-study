"""Read first-fight tutorial configuration from the installed Unity build."""
import argparse
from contextlib import ExitStack
import json
from pathlib import Path
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("data", type=Path)
parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "game/balancing/first_fight_tutorial.json")
args = parser.parse_args()
sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_balancing import BuildLayouts, read_fields
from import_scenes import Source
from import_translations import tables

with ExitStack() as stack:
    source = Source(args.data, stack)
    settings = next(o.read_typetree() for o in source.file("globalgamemanagers").objects.values()
                    if o.type.name == "BuildSettings")
    layouts = BuildLayouts(settings["m_Version"])
    layouts.load_local_game(str(args.data.parent))
    source.env.typetree_generator = layouts
    for path in args.data.glob("*.assets"):
        source.file(path.name)
    shared = source.file("sharedassets3.assets")
    steps = source.file("sharedassets1.assets")
    bundle = next((args.data / "StreamingAssets" / "aa").rglob("localization-assets-shared*.bundle"))
    entries = next(t["m_Entries"] for t in tables(bundle) if t.get("m_TableCollectionName") == "Tutorial")
    keys = {int(e["m_Id"]): e["m_Key"] for e in entries}

    def fields(reader):
        return read_fields(reader, layouts)

    def mono_class(reader, owner=shared):
        h = reader.parse_monobehaviour_head()
        if not h.m_Script.m_PathID:
            return ""
        _, script = source.resolve(owner, {"m_FileID": h.m_Script.m_FileID, "m_PathID": h.m_Script.m_PathID})
        return script.read().m_ClassName

    def rect_data(owner, reader):
        d = reader.read_typetree()
        return {"asset": owner.name, "path_id": reader.path_id,
                "game_object": d["m_GameObject"]["m_PathID"], "parent_path_id": d["m_Father"]["m_PathID"],
                "anchor_min": d["m_AnchorMin"], "anchor_max": d["m_AnchorMax"],
                "anchored_position": d["m_AnchoredPosition"], "size_delta": d["m_SizeDelta"],
                "pivot": d["m_Pivot"], "local_scale": d["m_LocalScale"]}

    def rect_from_pointer(owner, pointer):
        target_owner, target = source.resolve(owner, pointer)
        return rect_data(target_owner, target)

    def positioners(element, display):
        head = element.parse_monobehaviour_head()
        game_object = shared.objects[head.m_GameObject.m_PathID].read_typetree()
        container_id = fields(shared.objects[display])["_container"]["m_PathID"]
        result = []
        for component in game_object["m_Component"]:
            reader = shared.objects[component["component"]["m_PathID"]]
            if reader.type.name != "MonoBehaviour":
                continue
            kind = mono_class(reader)
            if kind not in ("ReferenceElementPositioner", "TargetedElementPositioner"):
                continue
            d = fields(reader)
            element_rect = rect_from_pointer(shared, d["_elementToReposition"])
            if element_rect["game_object"] != container_id:
                continue
            row = {"source_id": reader.path_id, "kind": kind, "element_rect": element_rect,
                   "alignment": d["_alignment"], "padding": d["_positionPadding"],
                   "fallback_to_auto_mode_when_missing_space": bool(d["_fallbackToAutoModeWhenMissingSpace"])}
            if "_positionTarget" in d:
                row["target_rect"] = rect_from_pointer(shared, d["_positionTarget"])
            else:
                resolver_id = d["_referenceResolver"]["m_PathID"]
                row["resolver_source_id"] = resolver_id
                row["target_reference"] = fields(shared.objects[resolver_id])["_elementReference"]
            result.append(row)
        return result

    output = {}
    combat_tracker = None
    for flow_id in (77433, 75529, 75756, 76709, 77296, 75206, 68067):
        flow = fields(shared.objects[flow_id])
        step = fields(steps.objects[flow["_targetStep"]["m_PathID"]])
        text_ids = {r["rid"]: r["data"]["<LocalizedText>k__BackingField"]["m_TableEntryReference"]["m_KeyId"]
                    for r in step["references"]["RefIds"] if r["type"]["class"] == "TextTutorialStepData"}
        text = {r["<Key>k__BackingField"]: keys[int(text_ids[r["<Data>k__BackingField"]["rid"]])]
                for r in step["_stepData"] if r["<Data>k__BackingField"]["rid"] in text_ids}
        trigger = str(step["<TriggerEvent>k__BackingField"])
        actions = []
        for pointer in flow["_flowElements"]:
            eid = pointer["m_PathID"]
            element = shared.objects[eid]
            kind = mono_class(element)
            d = fields(element)
            if trigger == "5" and eid != 70861:
                break
            entry = {"kind": kind, "source_id": eid, "lock": bool(d["<LockInput>k__BackingField"])}
            if "_textDisplay" in d:
                entry.update(text=text[d["_textDataKey"]], display=d["_textDisplay"]["m_PathID"],
                             hide=bool(d["_hideTextOnComplete"]))
                positioning = positioners(element, entry["display"])
                if positioning:
                    entry["positioning"] = positioning[0]
                    if len(positioning) > 1:
                        entry["positioning_alternatives"] = positioning[1:]
            for name in ("_waitDuration", "_skippable", "_anyMouseButton", "_specificButton", "_delaySeconds",
                         "_setPaused", "_visible", "_setActive", "_state", "_targetParentReference", "_reparentAll"):
                if name in d:
                    entry[name.lstrip("_")] = d[name]
            if "_referenceResolver" in d:
                resolver = fields(shared.objects[d["_referenceResolver"]["m_PathID"]])
                entry["reference"] = resolver["_elementReference"]
            if "_gameObjects" in d:
                entry["objects"] = [p["m_PathID"] for p in d["_gameObjects"]]
            actions.append(entry)
        definition = {"flow_id": flow_id, "step_id": flow["_targetStep"]["m_PathID"], "actions": actions}
        if flow_id == 68067:
            combat_tracker = definition
        else:
            output[trigger] = definition

    positioned = []
    for step in (*output.values(), combat_tracker):
        for action in step["actions"]:
            if "positioning" in action:
                positioned.extend(row for row in [action["positioning"], *action.get("positioning_alternatives", [])]
                                  if "target_reference" in row)
    targets = {row["target_reference"]: [] for row in positioned}
    for owner in (shared, source.file("level3")):
        for reader in owner.objects.values():
            if reader.type.name != "MonoBehaviour" or mono_class(reader, owner) != "TutorialViewReference":
                continue
            d = fields(reader)
            reference = d["<ReferenceType>k__BackingField"]
            if reference not in targets:
                continue
            go = owner.objects[d["m_GameObject"]["m_PathID"]].read_typetree()
            for component in go["m_Component"]:
                ptr = component["component"]
                if owner.objects[ptr["m_PathID"]].type.name == "RectTransform":
                    targets[reference].append(rect_from_pointer(owner, ptr))
    for row in positioned:
        candidates = targets[row["target_reference"]]
        if len(candidates) == 1:
            row["target_rect"] = candidates[0]
        elif candidates:
            row["target_candidates"] = candidates

    layouts_data = {}
    for cid, rid, image_id, layout_id in ((65348, 63903, 76757, 74042), (77122, 61758, 70525, 75240)):
        display = fields(shared.objects[cid])
        rect = shared.objects[rid].read_typetree()
        image = fields(shared.objects[image_id])
        layout = fields(shared.objects[layout_id])
        layouts_data[str(cid)] = {"container": display["_container"]["m_PathID"],
                                  "text_component": display["_textComponent"]["m_PathID"],
                                  "anchor": rect["m_AnchorMin"], "position": rect["m_AnchoredPosition"],
                                  "size": rect["m_SizeDelta"], "pivot": rect["m_Pivot"],
                                  "background_sprite": image["m_Sprite"]["m_PathID"],
                                  "pixels_per_unit_multiplier": image["m_PixelsPerUnitMultiplier"],
                                  "padding": layout["m_Padding"], "spacing": layout["m_Spacing"]}
    dest = args.output
    scaler = fields(shared.objects[72833])
    canvas = shared.objects[53899].read_typetree()
    adjuster = fields(shared.objects[75545])
    canvas_layout = {"render_mode": canvas["m_RenderMode"], "sorting_order": canvas["m_SortingOrder"],
                     "reference_resolution": scaler["m_ReferenceResolution"],
                     "match_width_or_height": scaler["m_MatchWidthOrHeight"],
                     "aspect_ratio_threshold": adjuster["_aspectRatioThreshold"]}
    dest.write_text(json.dumps({"steps": output, "combat_tracker": combat_tracker,
                                "canvas": canvas_layout, "display_layouts": layouts_data},
                               indent=2), encoding="utf-8")


