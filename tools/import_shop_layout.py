"""Build the interactive first-shop layout from the imported Battle canvas."""
import re
from pathlib import Path

GAME = Path(__file__).resolve().parents[1] / "game"
BASE = "Canvas/Root/ShopUIController/Panel"
CENTER = "CenterPanel"
HEROES = CENTER + "/HeroesPanel/HeroHolderPanel"
SIDE = CENTER + "/ItemRelicPanel/"
ITEMS = SIDE + "ItemsToBuyPanel_VerticalLayout/ItemHolderPanel"
RELICS = SIDE + "RelicsToBuyPanel_VerticalLayout/ItemHolderPanel"
SELL = "ButtonsPanel/Panel_CSF/SellingPanel"
KEY = "ButtonsPanel/ProceedButton/BuyKeyFragmentButton"


def build(super_shop=False):
    canvas = (GAME / "UI/Battle.tscn").read_text(encoding="utf8")
    head, *blocks = re.split(r"(?=^\[node )", canvas, flags=re.M)
    slots = {}
    for i in range(3):
        slots[f"{HEROES}/HeroCardShopItem" + (f"_{i}" if i else "")] = i
    sections = [(ITEMS, "ShopItemView_Descriptions", 2, 3), (RELICS, "ShopRelicView_Descriptions", 1, 5)]
    if super_shop:
        sections = [(ITEMS.replace("_VerticalLayout", ""), "ShopItemView", 4, 3),
                    (RELICS.replace("_VerticalLayout", ""), "ShopRelicView", 2, 7)]
    for path, prefix, count, first in sections:
        available = [re.search(r'name="([^"]+)"', block).group(1) for block in blocks
                     if f'parent="{BASE}/{path}"]' in block.splitlines()[0]]
        for i, name in enumerate([n for n in available if n.startswith(prefix)][:count]):
            slots[f"{path}/{name}"] = first + i
    assert sorted(slots.values()) == list(range(9 if super_shop else 6))
    leaves = set(slots) | {"Background/UnityImage"}
    for suffix in ("UnityImage", "Button/UnityImage", "Icon/UnityImage", "Text (TMP)/UnityText",
                   "ShopLeftPanel/UnityImage", "ShopLeftPanel/Text (TMP)/UnityText"):
        leaves.add(f"{KEY}/{suffix}")
    for suffix in (
        "InactiveFill/BottomLayer/UnityImage", "InactiveFill/InactiveText/UnityText",
        "OpenFill/BottomLayer/UnityImage", "OpenFill/BottomLayer/Hover/UnityImage",
        "OpenFill/ActiveFill/BottomLayer/UnityImage", "OpenFill/ActiveFill/BottomLayer/Hover/UnityImage",
        "OpenFill/ActiveText/UnityText", "TopLayer/UnityImage",
        "Frame/UnityImage", "Frame/CartImage/UnityImage",
    ):
        leaves.add(f"{SELL}/{suffix}")
    for path, slot in slots.items():
        if slot < 3:
            leaves.add(path + "/Background/UnityImage")
    retained = set()
    for path in leaves:
        while path:
            retained.add(path)
            path = path.rpartition("/")[0]

    nodes = ['[node name="ShopPanel" type="Control"]\nlayout_mode = 0\noffset_right = 1340.0\n'
             'offset_bottom = 678.0\nmouse_filter = 2\n']
    resources = set()
    for block in blocks:
        header, _, body = block.partition("\n")
        if f'parent="{BASE}' not in header:
            continue
        match = re.search(r'name="([^"]+)" type="[^"]+" parent="([^"]+)"', header)
        parent = match[2].removeprefix(BASE).lstrip("/")
        path = "/".join(filter(None, (parent, match[1])))
        if path not in retained:
            continue
        if super_shop and path in (SIDE + "ItemsToBuyPanel", SIDE + "RelicsToBuyPanel"):
            body = body.replace("visible = false\n", "")
        header = header.replace(f'parent="{match[2]}"', f'parent="{parent or "."}"')
        if path in slots:
            body = body.rstrip() + f'\nmetadata/offer_slot = {slots[path]}\n'
        if path == SELL:
            # The original HorizontalLayoutGroup applies LayoutElement.minWidth = 280.
            body = body.replace("offset_left = 668", "offset_left = 528").replace("offset_right = 668", "offset_right = 808")
            body = body.rstrip() + "\nvisible = false\n"
        if path == KEY:
            body = body.rstrip() + "\nvisible = false\n"
        resources.update(re.findall(r'ExtResource\("([^"]+)"\)', body))
        if super_shop and slots.get(path) in (7, 8):
            # Center the runtime row of three relics using the authored 100-unit cell width.
            body = re.sub(r"(offset_(?:left|right) = )(-?\d+)", lambda m: m[1] + str(int(m[2]) - 50), body)
        nodes.append(header + "\n" + body.rstrip() + "\n")
        if super_shop and slots.get(path) == 8:
            third = re.sub(r"(offset_(?:left|right) = )(-?\d+)", lambda m: m[1] + str(int(m[2]) + 100), body)
            third = re.sub(r"^metadata/unity_id = .*\n", "", third, flags=re.M)
            nodes.append(header.replace('name="ShopRelicView_1"', 'name="ShopRelicView_2"') + "\n" +
                         third.replace("metadata/offer_slot = 8", "metadata/offer_slot = 9").rstrip() + "\n")
    ext = [l for l in head.splitlines() if l.startswith("[ext_resource") and re.search(r'id="([^"]+)"', l)[1] in resources]
    filename = "super_shop" if super_shop else "first_shop"
    (GAME / f"UI/{filename}.tscn").write_text("[gd_scene format=3]\n\n" + "\n".join(ext) +
                                              "\n\n" + "\n".join(nodes), encoding="utf8")


if __name__ == "__main__":
    build()
    build(True)
