"""Export the source opening comic prefabs, reveal tracks and localized captions."""
import argparse
from contextlib import ExitStack
import json
from pathlib import Path

from import_balancing import BuildLayouts, read_fields
from import_canvas import export, prefab_objects
from import_scenes import Source
from import_translations import tables


ANIMATED_PROPERTIES = {76: "group_alpha", 77: "image_alpha", 61: "scale",
                       79: "position", 84: "position_x", 112: "size"}
SEQUENCES = {"intro_comic": "comics/comicintro", "founding_comic": "comics/comicguildfounding"}


def tracks(file, components, component_id, time=0.0):
    sequence = components[component_id]["animation"]["animations"]
    end = time
    previous = time
    output = []
    for item in sequence:
        operation = item["operation"]
        start = end if operation == 0 else previous if operation == 1 else time + item["startTime"]
        duration = item["duration"]
        for target in item["targets"]:
            component = target["m_PathID"]
            if not component or target["m_FileID"] != 0:
                continue
            if item["tweenType"] == 72 and component in components:
                nested, nested_end = tracks(file, components, component, start)
                output.extend(nested)
                end = max(end, nested_end)
            elif item["tweenType"] in ANIMATED_PROPERTIES:
                fields = file.objects[component].read_typetree(check_read=False)
                output.append({
                    "node": fields["m_GameObject"]["m_PathID"],
                    "property": ANIMATED_PROPERTIES[item["tweenType"]],
                    "start": start, "duration": duration, "ease": item["ease"],
                    "from": [item["startValue"][axis] for axis in ("x", "y")],
                    "to": [item["endValue"][axis] for axis in ("x", "y")],
                })
        end = max(end, start + duration)
        previous = start
    return output, end


def export_sequence(source, file, prefab, name, game, keys, layouts):
    export(source, file, name + "_content", game, prefab_root=prefab.path_id)
    components = {}
    captions = {}
    layout_elements = {}
    layout_groups = {}
    panel = {}
    for obj in prefab_objects(file, prefab.path_id):
        if obj.type.name != "MonoBehaviour":
            continue
        head = obj.parse_monobehaviour_head()
        kind = head.m_Script.deref_parse_as_object().m_ClassName
        if kind == "TweenAnimationComponent":
            components[obj.path_id] = read_fields(obj, layouts)
        elif kind == "ComicPanelView":
            panel = read_fields(obj, layouts)
        elif kind == "LayoutElement":
            layout_elements[head.m_GameObject.m_PathID] = read_fields(obj, layouts)
        elif kind == "VerticalLayoutGroup":
            layout_groups[head.m_GameObject.m_PathID] = read_fields(obj, layouts)
        elif kind == "AutoLocalizeTMP":
            fields = read_fields(obj, layouts)
            key = fields["_stringReference"]["m_TableEntryReference"]["m_KeyId"]
            captions[head.m_GameObject.m_PathID] = keys[int(key)]
    tweens, duration = tracks(file, components, panel["_introAnimationComponent"]["m_PathID"])
    caption_layouts = {}
    for object_id, key in captions.items():
        obj = file.objects[object_id].read_typetree()
        rect = next(file.objects[ref["component"]["m_PathID"]] for ref in obj["m_Component"]
                    if file.objects[ref["component"]["m_PathID"]].type.name == "RectTransform")
        parent_rect = file.objects[rect.read_typetree()["m_Father"]["m_PathID"]].read_typetree()
        parent_id = parent_rect["m_GameObject"]["m_PathID"]
        caption = {"key": key}
        if parent_id in layout_groups and object_id in layout_elements:
            padding = layout_groups[parent_id]["m_Padding"]
            caption.update(width=layout_elements[object_id]["m_PreferredWidth"],
                           padding=[padding[f"m_{edge}"] for edge in ("Left", "Top", "Right", "Bottom")],
                           spacing=float(layout_groups[parent_id]["m_Spacing"]))
        caption_layouts[object_id] = caption
    result = {"duration": duration, "tracks": sorted(tweens, key=lambda row: row["start"]),
              "captions": caption_layouts, "sound": panel["_sfx"]["Path"]}
    (game / f"balancing/{name}.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    parser.add_argument("--sequence", choices=SEQUENCES, action="append")
    args = parser.parse_args()
    game = Path(__file__).resolve().parents[1] / "game"
    bundle = next((args.data / "StreamingAssets" / "aa").rglob("localization-assets-shared*.bundle"))
    shared = next(t for t in tables(bundle) if t.get("m_TableCollectionName") == "Comics")
    keys = {int(row["m_Id"]): row["m_Key"] for row in shared["m_Entries"]}
    with ExitStack() as stack:
        source = Source(args.data, stack)
        for asset in args.data.glob("*.assets"):
            source.file(asset.name)
        for resource in ("unity_builtin_extra", "unity default resources"):
            source.file(resource)
        manager = source.file("globalgamemanagers")
        layouts = BuildLayouts(next(obj.read_typetree()["m_Version"] for obj in manager.objects.values()
                                    if obj.type.name == "BuildSettings"))
        layouts.load_local_game(str(args.data.parent))
        source.env.typetree_generator = layouts
        resources = next(obj.read_typetree()["m_Container"] for obj in manager.objects.values()
                         if obj.type.name == "ResourceManager")
        for name in args.sequence or SEQUENCES:
            file, prefab = source.resolve(manager, dict(resources)[SEQUENCES[name]])
            export_sequence(source, file, prefab, name, game, keys, layouts)


if __name__ == "__main__":
    main()
