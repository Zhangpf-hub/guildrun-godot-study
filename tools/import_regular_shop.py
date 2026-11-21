"""Build the Act 1 shop catalog for a fresh tutorial run from the installed demo."""
import argparse
import json
from contextlib import ExitStack
from pathlib import Path

from import_first_battle import field, save_sprite
from import_scenes import Source


def extract(data, game):
    records = json.loads((game / "balancing/sharedassets1.json").read_text(encoding="utf8"))["records"]
    tables = {r["type"]: r["fields"] for r in records}
    visuals = {r["id"]: r["fields"] for r in records if r["type"] == "CharacterVisualConfig"}
    shop = tables["ShopSingleton"]
    unlocks = tables["ProgressionUnlocksSingleton"]["_unlocks"]
    catalog = {}
    locked_catalog = {}
    odds = {}
    super_odds = {}
    later_odds = {}
    with ExitStack() as stack:
        src = Source(data, stack)
        owner = src.file("sharedassets1.assets")
        for hero in tables["HeroSheetHolder"]["Entries"]:
            visual = visuals.get(field(hero, "VisualConfig")["m_PathID"], {})
            small = visual.get("SmallPortraitSprite", {})
            if small.get("m_PathID"):
                save_sprite(src, owner, small, game)
        for kind, table in (("Hero", "heroRank"), ("Item", "itemRarity"), ("Relic", "relicRarity")):
            locked = {i: field(u, "XpThreshold") for u in unlocks for i in u["_" + kind.lower() + "Ids"]}
            costs = {field(v, "Element"): field(v, "Value") for v in shop["_" + table + "Costs"]}
            odds[kind] = {field(v, "Element"): field(v, "Chance")["RawValue"]
                          for v in shop["_" + table + "Chances"] if field(v, "ChunkIndex") == 0}
            later_odds[kind] = {field(v, "Element"): field(v, "Chance")["RawValue"]
                                for v in shop["_" + table + "Chances"] if field(v, "ChunkIndex") == 1}
            super_odds[kind] = {field(v, "Element"): field(v, "Chance")["RawValue"]
                                for v in shop["_superShop" + table[0].upper() + table[1:] + "Chances"]
                                if field(v, "ChunkIndex") == 0}
            for row in tables[kind + "SheetHolder"]["Entries"]:
                i = field(row, "Id")["_sequentialId"]
                tier = 1 if kind == "Hero" else field(row, "Rarity")
                if field(row, "DisabledInGame") or tier not in odds[kind]:
                    continue
                icon = (visuals[field(row, "VisualConfig")["m_PathID"]]["PortraitSpritesPerRank"][0]
                        if kind == "Hero" else field(row, "Icon"))
                offer = dict(kind=kind, id=i, tier=tier, price=costs[tier],
                             icon=save_sprite(src, owner, icon, game))
                if i in locked:
                    locked_catalog[f"{kind}_{i}"] = dict(offer, xp=locked[i])
                else:
                    catalog[f"{kind}_{i}"] = offer
        panel_owner = src.file("sharedassets3.assets")
        for sprite_id in (402, 589, 521, 359):
            save_sprite(src, panel_owner, {"m_FileID": 0, "m_PathID": sprite_id}, game)
    result = dict(catalog=catalog, locked_catalog=locked_catalog, odds=odds, counts={k: shop[k + "ChoicesPerShop"] for k in odds},
                  second_chunk_odds=later_odds, super_odds=super_odds,
                  super_counts={k: shop[k + "ChoicesPerSuperShop"] for k in odds},
                  super_reroll=shop["SuperShopBaseRerollCost"],
                  rank_prices={field(v, "Element"): field(v, "Value") for v in shop["_heroRankCosts"]},
                  discount=shop["RandomSaleDiscount"]["RawValue"], reroll=shop["BaseRerollCost"],
                  reroll_increment=shop["RerollCostIncrement"],
                  surviving_hero_shards=tables["RewardSelectionSingleton"]["ShardRewardPerSurvivingHero"])
    (game / "balancing/regular_shop.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    extract(parser.parse_args().data, Path(__file__).resolve().parents[1] / "game")
