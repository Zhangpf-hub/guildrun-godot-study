"""Translate screen-space Unity RectTransforms into anchored Godot Controls."""
import argparse
import json
import math
import re
import struct
import zlib
from collections import defaultdict
from contextlib import ExitStack
from pathlib import Path

from PIL import Image

from import_balancing import BuildLayouts, read_fields
from import_scenes import Source, quote, vector
from import_first_battle import save_sprite


def prefab_objects(file, root_id):
    pending = [root_id]
    while pending:
        game_object = file.objects[pending.pop()]
        yield game_object
        for entry in game_object.read_typetree()["m_Component"]:
            component = file.objects[entry["component"]["m_PathID"]]
            yield component
            if component.type.name == "RectTransform":
                for child in component.read_typetree()["m_Children"]:
                    transform = file.objects[child["m_PathID"]]
                    if transform.type.name == "RectTransform":
                        pending.append(transform.read_typetree()["m_GameObject"]["m_PathID"])


def game_object_id(src, file, pointer):
    if not pointer["m_PathID"]:
        return 0
    _, reader = src.resolve(file, pointer)
    if reader.type.name == "GameObject":
        return reader.path_id
    if reader.type.name == "MonoBehaviour":
        return reader.parse_monobehaviour_head().m_GameObject.m_PathID
    return reader.read_typetree()["m_GameObject"]["m_PathID"]


def item_slot_binding(src, file, reader, layouts):
    fields = read_fields(reader, layouts)
    return {"id": reader.path_id, "root": reader.parse_monobehaviour_head().m_GameObject.m_PathID,
            **{k: game_object_id(src, file, fields[k]) for k in (
                "_emptySlotParent", "_activeSlotParent", "_hoveringSlotParent",
                "_activeSlotImage", "_hoveringSlotImage", "_activeNameText", "_frameImage")}}


def export_party_bindings(src, file, game, layouts):
    def object_id(pointer):
        return game_object_id(src, file, pointer)

    def slot_binding(reader):
        return item_slot_binding(src, file, reader, layouts)

    controller = read_fields(file.objects[77014], layouts)
    roster = {"divider": object_id(controller["_dividerObject"])}
    for section, field in [("active", "_activeHeroPanel"), ("reserve", "_reserveHeroPanel")]:
        _, panel = src.resolve(file, controller[field])
        cards = []
        for pointer in read_fields(panel, layouts)["_bottomHeroViews"]:
            _, view = src.resolve(file, pointer)
            record = read_fields(view, layouts)
            card = {"id": view.path_id, "root": object_id(pointer)}
            for key in ("_heroIcon", "_frameImage", "_backupIconContainer", "_portraitActiveContainer",
                        "_itemRowsContainer", "_damageIndicatorView", "_abilitiesViewContainer"):
                card[key] = object_id(record[key])
            card["rank_frames"] = [save_sprite(src, file, ptr, game) for ptr in record["_frameSpritesPerRank"]]
            card["equipment_slots"] = [slot_binding(src.resolve(file, ptr)[1]) for ptr in record["_itemSlotViews"]]
            cards.append(card)
        roster[section] = {"root": object_id(controller[field]), "cards": cards}
    inventory = read_fields(file.objects[70425], layouts)
    result = {"source": file.name, "roster": roster, "inventory": {
        "sidebar": object_id(inventory["_sideBarGameObject"]),
        "holder": object_id(inventory["_slotHolderTransform"]),
        "column": object_id(inventory["_equipmentColumnPrefab"]),
        "slot": slot_binding(src.resolve(file, inventory["_placeholderSlotViewPrefab"])[1])}}
    directory = game / "balancing"
    directory.mkdir(exist_ok=True)
    (directory / "battle_party_ui.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


def rank_hero_open_pose(file):
    # HeroCardView.Show(true, false) samples HeroCard_Hover at normalized time 1.
    clip = file.objects[348].read_typetree()
    bindings = clip["m_ClipBindingConstant"]["genericBindings"]
    values = clip["m_MuscleClip"]["m_Clip"]["data"]
    words = values["m_StreamedClip"]["data"]
    stream = values["m_StreamedClip"]["curveCount"]
    ends = {}
    offset = 0
    while offset < len(words):
        count = words[offset + 1]
        offset += 2
        for _ in range(count):
            ends[words[offset]] = struct.unpack("<f", struct.pack("<I", words[offset + 4]))[0]
            offset += 5
    ends.update(enumerate(values["m_ConstantClip"]["data"], start=stream))
    paths = {}
    def visit(game_object, path):
        paths[zlib.crc32(path.encode())] = path
        for ref in file.objects[game_object].read_typetree()["m_Component"]:
            component = file.objects[ref["component"]["m_PathID"]]
            if component.type.name == "RectTransform":
                for child in component.read_typetree()["m_Children"]:
                    gid = file.objects[child["m_PathID"]].read_typetree()["m_GameObject"]["m_PathID"]
                    name = file.objects[gid].read_typetree()["m_Name"]
                    visit(gid, f"{path}/{name}" if path else name)
                break
    visit(10140, "")
    properties = {zlib.crc32(x.encode()): x for x in ("m_AnchoredPosition.x", "m_AnchoredPosition.y", "m_Alpha")}
    return [{"path": paths[b["path"]], "property": properties[b["attribute"]], "value": ends[i]}
            for i, b in enumerate(bindings)]


def export_rank_modifier_display(src, file, layouts, game):
    owner = src.file("sharedassets1.assets")
    table = read_fields(owner.objects[60845], layouts)
    refs = {ref["rid"]: ref["data"] for ref in table["references"]["RefIds"]}
    entries = {}
    for row in table["<Entries>k__BackingField"]:
        if row["<DisabledInGame>k__BackingField"]:
            continue
        desc = row["<DescriptionLocaKey>k__BackingField"]
        entries[row["<Id>k__BackingField"]["_sequentialId"]] = {
            "name": row["<NameLocaKey>k__BackingField"]["_key"],
            "description": desc["_key"],
            "variables": {v["name"]: refs[v["variable"]["rid"]]["m_Value"]
                          for v in desc["_localizedString"]["m_LocalVariables"]},
            "icon": save_sprite(src, owner, row["<Icon>k__BackingField"], game),
        }
    choice = read_fields(file.objects[78327], layouts)
    picker = read_fields(file.objects[69114], layouts)
    frames = {key: [save_sprite(src, file, ptr, game) if ptr["m_PathID"] else ""
                    for ptr in choice[key]]
              for key in ("_rarityInnerFrameSprites", "_rarityOuterFrameSprites", "_rarityiconFrame")}
    hero = read_fields(file.objects[68583], layouts)
    feedback = read_fields(owner.objects[60884], layouts)
    behaviors = {ref["rid"]: ref for ref in feedback["references"]["RefIds"]}
    colors = {}
    for item in feedback["_keywordBehaviors"]:
        for pointer in item["<Behaviors>k__BackingField"]:
            behavior = behaviors[pointer["rid"]]
            if behavior["type"]["class"] == "ColorCodeKeywordBehavior":
                color = behavior["data"]["_color"]
                colors[item["<Keyword>k__BackingField"]] = "#" + "".join(
                    f"{round(color[channel] * 255):02x}" for channel in "rgba")
    heroes = read_fields(owner.objects[60838], layouts)["<Entries>k__BackingField"]
    portraits = {}
    for row in heroes:
        if row["<DisabledInGame>k__BackingField"]:
            continue
        config_file, config_reader = src.resolve(owner, row["<VisualConfig>k__BackingField"])
        config = read_fields(config_reader, layouts)
        hero_id = row["<Id>k__BackingField"]["_sequentialId"]
        portraits[hero_id] = {
            field: [save_sprite(src, config_file, ptr, game) if ptr["m_PathID"] else "" for ptr in
                    config[f"<{field}>k__BackingField"]]
            for field in ("PortraitSpritesPerRank", "BreakoutPortraitSpritesPerRank")}
        fallback = config["<PortraitSprite>k__BackingField"]
        portraits[hero_id]["fallback"] = (
            save_sprite(src, config_file, fallback, game) if fallback["m_PathID"] else "")
    hero_frames = {}
    for image, sprites in [("_rankImage", "_rankNameSprites"), ("_backFrame", "_backFramesPerRank"),
                           ("_frontFrame", "_frontFramesPerRank")]:
        component = file.objects[hero[image]["m_PathID"]].parse_monobehaviour_head()
        hero_frames[image] = {"node": component.m_GameObject.m_PathID,
                              "textures": [save_sprite(src, file, ptr, game) if ptr["m_PathID"] else ""
                                           for ptr in hero[sprites]]}
    data = {"entries": entries, "frames": frames, "hero_frames": hero_frames, "portraits": portraits,
            "keyword_colors": colors,
            "hero_open_pose": rank_hero_open_pose(file),
            "spacing": picker["_spacingBetweenChoices"], "hero_gap": picker["_spacingAfterHeroCard"],
            "movement": picker["_movementAnimationSettings"]}
    folder = game / "balancing"
    folder.mkdir(exist_ok=True)
    (folder / "rank_modifier_display.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf8")


def export_tutorial_caption_font(src, shared, layouts, game):
    timed = read_fields(shared.objects[77122], layouts)
    owner, label = src.resolve(shared, timed["_textComponent"])
    owner, font = src.resolve(owner, read_fields(label, layouts)["m_fontAsset"])
    data = read_fields(font, layouts)
    face = data["m_FaceInfo"]
    glyphs = {g["m_Index"]: g for g in data["m_GlyphTable"]}
    _, atlas = src.resolve(owner, data["m_AtlasTextures"][0])
    distance = atlas.read().image.getchannel("A")
    # Convert the original alpha SDF into coverage for Godot's BMFont importer.
    # Keep the original atlas coordinates and 91-unit advances for fractional scaling.
    alpha = distance.point(lambda value: max(0, min(255, round((value - 116) * 255 / 24))))
    output = game / "fonts"
    output.mkdir(exist_ok=True)
    page_name = "tutorial_serif.png"
    coverage = Image.new("RGBA", alpha.size, (255, 255, 255, 255))
    coverage.putalpha(alpha)
    coverage.save(output / page_name)
    ascent = round(face["m_AscentLine"])
    lines = [f'info face={quote(face["m_FamilyName"])} size={round(face["m_PointSize"])} bold=0 italic=0 unicode=1 stretchH=100 aa=1 padding=2,2,2,2 spacing=0,0 outline=0',
             f'common lineHeight={round(face["m_LineHeight"])} base={ascent} scaleW={alpha.width} scaleH={alpha.height} pages=1 packed=0 alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4',
             f'page id=0 file="{page_name}"', f'chars count={len(data["m_CharacterTable"])}']
    for char in data["m_CharacterTable"]:
        glyph = glyphs[char["m_GlyphIndex"]]
        rect, metrics = glyph["m_GlyphRect"], glyph["m_Metrics"]
        width, height = rect["m_Width"], rect["m_Height"]
        padding = 2 if width and height else 0
        x = rect["m_X"] - padding
        y = alpha.height - rect["m_Y"] - height - padding if height else 0
        offset_x = round(metrics["m_HorizontalBearingX"]) - padding
        offset_y = ascent - round(metrics["m_HorizontalBearingY"]) - padding
        advance = round(metrics["m_HorizontalAdvance"] * char["m_Scale"] * glyph["m_Scale"])
        lines.append(f'char id={char["m_Unicode"]} x={x} y={y} width={width + 2 * padding} height={height + 2 * padding} '
                     f'xoffset={offset_x} yoffset={offset_y} xadvance={advance} page=0 chnl=8')
    (output / "tutorial_serif.fnt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def export(src, file, name, game, prefab_root=None, selected_root=None):
    battle_controls = name in ("battle_start_button", "battle_speed", "tutorial_prompt", "tutorial_timed", "tutorial_modal")
    party_controls = name in ("battle_roster", "battle_inventory", "battle_item_column", "battle_item_slot")
    rank_controls = name in ("rank_modifier_picker", "rank_modifier_choice")
    layout_metadata = name.startswith(("forest_trial", "battle_tracker", "battle_top")) or battle_controls or party_controls or rank_controls
    component_kinds = {"Image", "TextMeshPro", "TextMeshProUGUI", "Text", "RectMask2D", "Mask",
                       "CanvasScaler", "HorizontalLayoutGroup", "VerticalLayoutGroup"}
    if layout_metadata:
        component_kinds.add("CanvasScalingAdjuster")
    if name.startswith("battle_top") or battle_controls or party_controls or rank_controls:
        component_kinds.add("LayoutElement")
    if rank_controls:
        component_kinds.add("ContentSizeFitter")
    objects, transforms, canvases = {}, {}, {}
    controls = defaultdict(dict)
    for obj in (prefab_objects(file, prefab_root) if prefab_root is not None else file.objects.values()):
        kind = obj.type.name
        if kind == "GameObject":
            objects[obj.path_id] = obj.read_typetree()
        elif kind == "RectTransform":
            transforms[obj.path_id] = obj.read_typetree()
        elif kind == "Canvas":
            data = obj.read_typetree()
            canvases[data["m_GameObject"]["m_PathID"]] = data
        elif kind == "CanvasGroup":
            data = obj.read_typetree()
            controls[data["m_GameObject"]["m_PathID"]][kind] = data
        elif kind == "MonoBehaviour":
            head = obj.parse_monobehaviour_head()
            ptr = head.m_Script
            if not ptr.m_PathID or not ptr.m_FileID:
                continue
            path = Path(file.externals[ptr.m_FileID - 1].path).name
            if not (src.data / path).is_file():
                continue
            src.file(path)
            script = ptr.deref_parse_as_object().m_ClassName
            if script in component_kinds:
                controls[head.m_GameObject.m_PathID][script] = obj

    nodes = [f'[node name={quote(name + "UI")} type="Control"]',
             "anchors_preset = 15", "anchor_right = 1.0", "anchor_bottom = 1.0", "mouse_filter = 2"]
    if selected_root is not None:
        retained = set()
        tid = next(tid for tid, rect in transforms.items() if rect["m_GameObject"]["m_PathID"] == selected_root)
        while tid in transforms:
            retained.add(tid)
            tid = transforms[tid]["m_Father"]["m_PathID"]
    textures = {}

    has_sliced_images = False

    def emit(tid, parent, siblings, canvas_root=False, reference_ppu=100.0):
        nonlocal has_sliced_images
        rect = transforms[tid]
        gid = rect["m_GameObject"]["m_PathID"]
        obj = objects[gid]
        label = re.sub(r'[\x00-\x1f.:@/"%\\]', "_", obj["m_Name"]).strip() or "Control"
        if label in siblings:
            label += f"_{gid}"
        siblings.add(label)
        path = label if parent == "." else parent + "/" + label
        nodes.extend([f'\n[node name={quote(label)} type="Control" parent={quote(parent)}]',
                      "mouse_filter = 2", f"metadata/unity_id = {gid}"])
        if canvas_root:
            nodes.extend(["anchor_right = 1.0", "anchor_bottom = 1.0"])
        else:
            amin, amax, pivot, pos, size = (rect[k] for k in
                ("m_AnchorMin", "m_AnchorMax", "m_Pivot", "m_AnchoredPosition", "m_SizeDelta"))
            left = pos["x"] - pivot["x"] * size["x"]
            top = -pos["y"] - (1 - pivot["y"]) * size["y"]
            settings = dict(anchor_left=amin["x"], anchor_right=amax["x"], anchor_top=1-amax["y"],
                            anchor_bottom=1-amin["y"], offset_left=left, offset_right=left+size["x"],
                            offset_top=top, offset_bottom=top+size["y"])
            nodes.extend(f"{k} = {v:.9g}" for k, v in settings.items())
            rotation = rect["m_LocalRotation"]
            nodes.append(f'rotation = {-2 * math.atan2(rotation["z"], rotation["w"]):.9g}')
            scale = rect["m_LocalScale"]
            nodes.append("scale = " + vector("Vector2", scale["x"], scale["y"]))
            nodes.append("pivot_offset_ratio = " + vector("Vector2", pivot["x"], 1-pivot["y"]))
        if not obj["m_IsActive"]:
            nodes.append("visible = false")
        comps = controls[gid]
        if "CanvasScaler" in comps:
            scaler = read_fields(comps["CanvasScaler"], src.env.typetree_generator)
            reference_ppu = scaler["m_ReferencePixelsPerUnit"]
            if layout_metadata:
                resolution = scaler["m_ReferenceResolution"]
                nodes.append("metadata/reference_resolution = " + vector("Vector2", resolution["x"], resolution["y"]))
                nodes.append(f'metadata/match_width_or_height = {scaler["m_MatchWidthOrHeight"]}')
                if "CanvasScalingAdjuster" in comps:
                    adjuster = read_fields(comps["CanvasScalingAdjuster"], src.env.typetree_generator)
                    nodes.append(f'metadata/aspect_ratio_threshold = {adjuster["_aspectRatioThreshold"]}')
        if layout_metadata:
            nodes.append("metadata/unity_file = " + quote(Path(file.name).name))
            if "ContentSizeFitter" in comps:
                fitter = read_fields(comps["ContentSizeFitter"], src.env.typetree_generator)
                nodes.append(f'metadata/fit_axes = Vector2i({fitter["m_HorizontalFit"]}, {fitter["m_VerticalFit"]})')
            if "LayoutElement" in comps:
                element = read_fields(comps["LayoutElement"], src.env.typetree_generator)
                nodes.append(f'metadata/min_width = {element["m_MinWidth"]}')
                nodes.append(f'metadata/preferred_width = {element["m_PreferredWidth"]}')
                if party_controls or rank_controls:
                    nodes.append(f'metadata/ignore_layout = {str(bool(element["m_IgnoreLayout"])).lower()}')
                    nodes.append(f'metadata/preferred_height = {element["m_PreferredHeight"]}')
            for layout in ("HorizontalLayoutGroup", "VerticalLayoutGroup"):
                if layout in comps:
                    settings = read_fields(comps[layout], src.env.typetree_generator)
                    nodes.append(f'metadata/layout_spacing = {settings["m_Spacing"]}')
                    padding = settings["m_Padding"]
                    nodes.append("metadata/layout_padding = " + vector(
                        "Vector4", *(padding[f"m_{edge}"] for edge in ("Left", "Top", "Right", "Bottom"))))
                    if party_controls or rank_controls:
                        nodes.append(f'metadata/child_alignment = {settings["m_ChildAlignment"]}')
        if "CanvasGroup" in comps:
            nodes.append(f'modulate = Color(1, 1, 1, {comps["CanvasGroup"]["m_Alpha"]})')
        if "Mask" in comps or "RectMask2D" in comps:
            nodes.append("clip_contents = true")
        child_names = set()
        fill = ["anchor_right = 1.0", "anchor_bottom = 1.0", "mouse_filter = 2"]
        show_mask_graphic = ("Mask" not in comps
                             or read_fields(comps["Mask"], src.env.typetree_generator)["m_ShowMaskGraphic"])
        if "Image" in comps and show_mask_graphic:
            d = read_fields(comps["Image"], src.env.typetree_generator)
            if d["m_Enabled"]:
                p = d["m_Sprite"]
                typ = "TextureRect" if p["m_PathID"] else "ColorRect"
                if p["m_PathID"]:
                    owner, reader = src.resolve(file, p)
                    sprite = reader.read()
                    border = sprite.m_Border
                    sliced = d["m_Type"] == 1 and any((border.x, border.y, border.z, border.w))
                    if sliced:
                        typ = "Control"
                nodes.append(f'\n[node name="UnityImage" type="{typ}" parent={quote(path)}]')
                child_names.add("UnityImage")
                nodes.extend(fill)
                color = vector("Color", *(d["m_Color"][k] for k in "rgba"))
                if p["m_PathID"]:
                    dest = f"sprites/{Path(owner.name).stem}_{reader.path_id}.png"
                    if not (game / dest).exists():
                        sprite.image.save(game / dest)
                    key = textures.setdefault(dest, str(len(textures)+1))
                    if sliced:
                        has_sliced_images = True
                        ppu = sprite.m_PixelsToUnits * d["m_PixelsPerUnitMultiplier"] / reference_ppu
                        nodes.extend(['script = ExtResource("SlicedImage")',
                                      f'texture = ExtResource("{key}")',
                                      "border = " + vector("Vector4", border.x, border.w, border.z, border.y),
                                      f'pixels_per_unit = {ppu:.9g}',
                                      f'draw_center = {str(bool(d["m_FillCenter"])).lower()}'])
                    else:
                        nodes.extend([f'texture = ExtResource("{key}")', "expand_mode = 1",
                                      f'stretch_mode = {5 if d.get("m_PreserveAspect") else 0}'])
                    nodes.append("self_modulate = " + color)
                else:
                    nodes.append("color = " + color)
        for kind in ("TextMeshPro", "TextMeshProUGUI", "Text"):
            if kind not in comps:
                continue
            d = read_fields(comps[kind], src.env.typetree_generator)
            if not d["m_Enabled"]:
                continue
            child_names.add("UnityText")
            nodes.append(f'\n[node name="UnityText" type="Label" parent={quote(path)}]')
            nodes.extend(fill)
            text = d.get("m_text", d.get("m_Text", ""))
            color = d["m_fontColor"] if "m_fontColor" in d else d["m_Color"]
            font_size = d.get("m_fontSize", d.get("m_FontData", {}).get("m_FontSize", 14))
            nodes.extend([f"text = {quote(text)}", f'theme_override_font_sizes/font_size = {max(1, round(font_size))}',
                          "theme_override_colors/font_color = " + vector("Color", *(color[k] for k in "rgba")),
                          f'horizontal_alignment = {{h}}'.format(h={1:0,2:1,4:2}.get(d.get("m_HorizontalAlignment"),0)),
                          f'vertical_alignment = {{v}}'.format(v={256:0,512:1,1024:2}.get(d.get("m_VerticalAlignment"),1))])
            if rank_controls and kind.startswith("TextMeshPro"):
                wrapping = d.get("m_TextWrappingMode", d.get("m_enableWordWrapping", 0))
                nodes.append(f'metadata/unity_wrap = {int(wrapping)}')
                if wrapping == 1:
                    nodes.append("autowrap_mode = 3")
                nodes.append(f'metadata/unity_font_style = {d.get("m_fontStyle", 0)}')
                nodes.append(f'metadata/unity_character_spacing = {d.get("m_characterSpacing", 0.0)}')
        for child in rect["m_Children"]:
            child_id = child["m_PathID"]
            if child_id in transforms and (selected_root is None or gid == selected_root
                                           or tid not in retained or child_id in retained):
                emit(child_id, path, child_names, reference_ppu=reference_ppu)

    roots = set()
    for tid, rect in transforms.items():
        canvas = canvases.get(rect["m_GameObject"]["m_PathID"])
        if prefab_root is not None and rect["m_GameObject"]["m_PathID"] == prefab_root:
            emit(tid, ".", roots, canvas_root=selected_root is not None and prefab_root in canvases)
        elif prefab_root is None and canvas and canvas["m_RenderMode"] in (0,1) and (
                selected_root is None or tid in retained):
            emit(tid, ".", roots, True)
    header = ["[gd_scene format=3]", ""]
    if has_sliced_images:
        header.append('[ext_resource type="Script" path="res://UI/sliced_image.gd" id="SlicedImage"]')
    header.extend(f'[ext_resource type="Texture2D" path="res://{p}" id="{k}"]' for p,k in textures.items())
    dest = game / "UI" / (name + ".tscn")
    dest.parent.mkdir(exist_ok=True)
    dest.write_text("\n".join(header + [""] + nodes) + "\n", encoding="utf-8")
    print(name, "canvases", len(roots), "textures", len(textures), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    parser.add_argument("--scene", type=int, nargs="+", default=[2,3,4,5])
    parser.add_argument("--rank-picker", action="store_true", help="Export the specialization picker and its choice card prefabs")
    parser.add_argument("--rank-modifier-picker", action="store_true", help="Export the A/S rank modifier picker and its choice prefab")
    parser.add_argument("--forest-trials", action="store_true", help="Export the forest trial crossroads and event canvases")
    parser.add_argument("--battle-tracker", action="store_true", help="Export the original battle statistics sidebar with its canvas ancestors")
    parser.add_argument("--battle-result", action="store_true", help="Export the original result panel and its shard reward row")
    parser.add_argument("--battle-top", action="store_true", help="Export the run progress, wallet, stabilizer and timer with their canvas ancestors")
    parser.add_argument("--battle-controls", action="store_true", help="Export the placement button, speed controls and both tutorial text display prefabs")
    parser.add_argument("--battle-party", action="store_true", help="Export the bottom roster, item reserve and its column and slot templates")
    parser.add_argument("--output", type=Path, help="Destination Godot project directory")
    args = parser.parse_args()
    with ExitStack() as stack:
        src = Source(args.data, stack)
        for asset in args.data.glob("*.assets"):
            src.file(asset.name)
        for resource in ("unity_builtin_extra", "unity default resources"):
            src.file(resource)
        settings = next(o.read_typetree() for o in src.file("globalgamemanagers").objects.values()
                        if o.type.name == "BuildSettings")
        layouts = BuildLayouts(settings["m_Version"])
        layouts.load_local_game(str(args.data.parent))
        src.env.typetree_generator = layouts
        game = args.output or Path(__file__).resolve().parents[1] / "game"
        game.mkdir(parents=True, exist_ok=True)
        (game / "sprites").mkdir(exist_ok=True)
        if args.rank_picker:
            for name, root in [("specialization_picker", 13512), ("specialization_choice", 9441)]:
                export(src, src.file("sharedassets3.assets"), name, game, root)
        elif args.rank_modifier_picker:
            file = src.file("sharedassets3.assets")
            export(src, file, "rank_modifier_picker", game, prefab_root=11559, selected_root=17349)
            export(src, file, "rank_modifier_choice", game, prefab_root=4597)
            export_rank_modifier_display(src, file, layouts, game)
        elif args.battle_party:
            file = src.file("sharedassets3.assets")
            for name, root, selection in [
                    ("battle_roster", 11559, 9741), ("battle_inventory", 11559, 14633),
                    ("battle_item_column", 725, None), ("battle_item_slot", 9506, None)]:
                export(src, file, name, game, prefab_root=root, selected_root=selection)
            export_party_bindings(src, file, game, layouts)
        elif args.battle_controls:
            for file, name, canvas, selected in [
                    ("level3", "battle_start_button", 40, 45),
                    ("sharedassets3.assets", "battle_speed", 11559, 13748),
                    ("sharedassets3.assets", "tutorial_modal", 11559, 3431),
                    ("sharedassets3.assets", "tutorial_prompt", 16827, 9992),
                    ("sharedassets3.assets", "tutorial_timed", 16827, 13588)]:
                export(src, src.file(file), name, game, prefab_root=canvas, selected_root=selected)
            export_tutorial_caption_font(src, src.file("sharedassets3.assets"), layouts, game)
        elif args.battle_top:
            file = src.file("sharedassets3.assets")
            export(src, file, "battle_top", game, prefab_root=11559, selected_root=8353)
            hud = read_fields(file.objects[70037], layouts)
            data = {"icons": {}, "colors": {}, "templates": {}}
            for kind in ("fight", "actBoss", "miniBoss", "event", "fightEvent", "mining", "campfire"):
                data["icons"][kind] = save_sprite(src, file, hud["_" + kind + "Icon"], game)
            for kind in ("past", "current", "next", "future", "bossNext", "bossFuture", "other"):
                color = hud["_" + kind + "Color"]
                data["colors"][kind] = "".join(f'{round(255 * color[k]):02x}' for k in "rgba")
            for kind in ("fight", "large", "boss", "connector", "dots"):
                component = file.objects[hud["_" + kind + "NodePrefab"]["m_PathID"]]
                root = component.parse_monobehaviour_head().m_GameObject.m_PathID
                name = "battle_top_" + kind
                export(src, file, name, game, prefab_root=root)
                data["templates"][kind] = "res://UI/" + name + ".tscn"
            (game / "balancing/battle_top.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        elif args.battle_tracker:
            export(src, src.file("sharedassets3.assets"), "battle_tracker", game,
                   prefab_root=11559, selected_root=11243)
        elif args.battle_result:
            from import_result_layout import build, export_entrance, export_portrait_states

            file = src.file("level3")
            view = read_fields(file.objects[31436], layouts)
            owner, prefab = src.resolve(file, view["_textRewardViewPrefab"])
            export(src, owner, "battle_text_reward", game,
                   prefab_root=prefab.parse_monobehaviour_head().m_GameObject.m_PathID)
            build(game)
            export_entrance(src, file, view, layouts, game)
            export_portrait_states(src, file, layouts, game)
        elif args.forest_trials:
            scenes = {Path(path).stem: index for index, path in enumerate(settings["scenes"])}
            export(src, src.file(f'level{scenes["Battle"]}'), "forest_trial_roads", game, selected_root=1)
            export(src, src.file(f'level{scenes["Event"]}'), "forest_trial_event", game)
            gates = src.file(f'level{scenes["Environment_Default_3Gates_Morning"]}')
            export(src, gates, "forest_trial_gate_title", game, prefab_root=4)
            export(src, gates, "forest_trial_gate_tooltip", game, prefab_root=66)
        else:
            for index in args.scene:
                export(src, src.file(f"level{index}"), Path(settings["scenes"][index]).stem, game)
