"""Import the combat popups referenced by the shipped HealthBarView."""
import argparse
from contextlib import ExitStack
import json
from pathlib import Path

from PIL import Image

from import_balancing import BuildLayouts, read_fields
from import_scenes import Source, quote


def export_font(source, owner, label, layouts, folder):
    font_owner, font = source.resolve(owner, label["m_fontAsset"])
    material_owner, material = source.resolve(owner, label["m_sharedMaterial"])
    data = read_fields(font, layouts)
    props = material.read_typetree()["m_SavedProperties"]
    values = dict(props["m_Floats"])
    face = data["m_FaceInfo"]
    _, texture = source.resolve(font_owner, data["m_AtlasTextures"][0])
    distance = texture.read().image.getchannel("A")
    weight = (values["_WeightBold"] / 4 + values["_FaceDilate"]) * values["_ScaleRatioA"] / 2
    face_edge = 0.5 - weight
    outline_edge = face_edge - values["_OutlineWidth"] * values["_ScaleRatioA"] / 2

    def coverage(value, edge):
        return max(0.0, min(1.0, (value / 255 - edge) * values["_GradientScale"] + 0.5))

    outer = [coverage(i, outline_edge) for i in range(256)]
    ink = distance.point([round(255 * coverage(i, face_edge) / alpha) if alpha else 0
                          for i, alpha in enumerate(outer)])
    page = "battle_damage_text.png"
    Image.merge("RGBA", (ink, ink, ink, distance.point([round(255 * a) for a in outer]))).save(folder / page)
    ascent = round(face["m_AscentLine"])
    characters = "0123456789+"
    glyphs = {g["m_Index"]: g for g in data["m_GlyphTable"]}
    char_map = {c["m_Unicode"]: c for c in data["m_CharacterTable"]}
    padding = min(6, data["m_AtlasPadding"])
    lines = [f'info face={quote(face["m_FamilyName"])} size={round(face["m_PointSize"])} bold=1 italic=0 unicode=1 stretchH=100 aa=1 spacing=0,0',
             f'common lineHeight={round(face["m_LineHeight"])} base={ascent} scaleW={distance.width} scaleH={distance.height} pages=1 packed=0',
             f'page id=0 file="{page}"', f'chars count={len(characters)}']
    for symbol in characters:
        char = char_map[ord(symbol)]
        glyph = glyphs[char["m_GlyphIndex"]]
        rect, metrics = glyph["m_GlyphRect"], glyph["m_Metrics"]
        width, height = rect["m_Width"], rect["m_Height"]
        x, y = rect["m_X"] - padding, distance.height - rect["m_Y"] - height - padding
        ox = round(metrics["m_HorizontalBearingX"]) - padding
        oy = ascent - round(metrics["m_HorizontalBearingY"]) - padding
        advance = round(metrics["m_HorizontalAdvance"] * char["m_Scale"] * glyph["m_Scale"])
        lines.append(f'char id={ord(symbol)} x={x} y={y} width={width + 2 * padding} height={height + 2 * padding} '
                     f'xoffset={ox} yoffset={oy} xadvance={advance} page=0 chnl=15')
    (folder / "battle_damage_text.fnt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return {"font": [font_owner.name, font.path_id], "material": [material_owner.name, material.path_id],
            "point_size": round(face["m_PointSize"]), "cap_height": face["m_CapLine"]}


def extract(data, game):
    with ExitStack() as stack:
        source = Source(data, stack)
        for name in ("globalgamemanagers.assets", "sharedassets0.assets", "sharedassets1.assets", "sharedassets3.assets", "resources.assets"):
            source.file(name)
        build = next(row.read_typetree() for row in source.file("globalgamemanagers").objects.values()
                     if row.type.name == "BuildSettings")
        layouts = BuildLayouts(build["m_Version"])
        layouts.load_local_game(str(data.parent))
        source.env.typetree_generator = layouts
        battle = source.file("level3")
        controller = read_fields(battle.objects[26860], layouts)
        owner, view = source.resolve(battle, controller["_healthBarPrefab"])
        owner, popup = source.resolve(owner, read_fields(view, layouts)["_damageTextPrefab"])
        settings = read_fields(popup, layouts)
        text_owner, text = source.resolve(owner, settings["_damageText"])
        fonts = game / "fonts"
        fonts.mkdir(exist_ok=True)
        payload = export_font(source, text_owner, read_fields(text, layouts), layouts, fonts)
        payload["prefab"] = [owner.name, popup.path_id]
        fields = ("minFontSize", "maxFontSize", "playerMinDamage", "playerMaxDamage", "enemyMinDamage", "enemyMaxDamage",
                  "positionVariation", "jumpPower", "popInDuration", "movementDuration", "fadeOutDuration")
        payload.update({name: settings["_" + name] for name in fields})
        payload["colors"] = {name[1:]: list(value.values()) for name, value in settings.items() if name.endswith("Color")}
        feedback_owner = source.file("sharedassets1.assets")
        feedback = read_fields(feedback_owner.objects[60884], layouts)
        icons = {"crit": settings["_critIconText"]}
        icons.update({{1: "burn", 2: "frost", 3: "poison"}[row["_statusType"]]: row["IconText"]
                      for row in feedback["_statusVisualSettings"] if row["_statusType"] in (1, 2, 3)})
        resources = source.file("resources.assets")
        sprites = {item.peek_name(): item for item in resources.objects.values() if item.type.name == "Sprite"}
        for key, tag in icons.items():
            sprite = sprites[tag.removeprefix("<sprite name=").removesuffix(">")]
            sprite.read().image.save(fonts / f"battle_damage_{key}.png")
        folder = game / "balancing"
        folder.mkdir(exist_ok=True)
        (folder / "battle_damage_text.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    args = parser.parse_args()
    extract(args.data, Path(__file__).resolve().parents[1] / "game")
