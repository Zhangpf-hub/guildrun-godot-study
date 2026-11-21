"""Extract the tutorial's first hero choices and the matching first-shop offers."""
import argparse
import json
from contextlib import ExitStack
from pathlib import Path

from import_balancing import BuildLayouts, read_fields
from import_scenes import Source


def field(row, key):
    return row[f"<{key}>k__BackingField"]


def save_sprite(source, owner_file, pointer, game):
    owner, sprite = source.resolve(owner_file, pointer)
    path = f"sprites/{Path(owner.name).stem}_{sprite.path_id}.png"
    dest = game / path
    if not dest.exists():
        dest.parent.mkdir(exist_ok=True)
        sprite.read().image.save(dest)
    return "res://" + path


def extract_shop(records, step, layouts, source, file, game, filename):
    tables = {r["type"]: r["fields"] for r in records}
    visuals = {r["id"]: r["fields"] for r in records if r["type"] == "CharacterVisualConfig"}
    prices = tables["ShopSingleton"]
    catalog = {}
    stock = {}
    fallbacks = {}
    refs = read_fields(step, layouts)["references"]["RefIds"]
    override = next(r["data"] for r in refs if r["type"]["class"] == "ShopOverrideStepData")
    for shop in override["_heroToShopContents"]:
        slots = []
        for kind, ids, cost_table in (
                ("Hero", field(shop, "ShopHeroIds"), "_heroRankCosts"),
                ("Item", field(shop, "ShopItemIds"), "_itemRarityCosts"),
                ("Relic", [field(shop, "ShopRelicId")], "_relicRarityCosts"),
                ("Fallback", field(shop, "ShopHeroFallbackIds"), "_heroRankCosts")):
            is_fallback = kind == "Fallback"
            kind = "Hero" if is_fallback else kind
            for entry_id in ids:
                key = f"{kind}_{entry_id}"
                if is_fallback:
                    fallbacks.setdefault(str(field(shop, "HeroId")), []).append(key)
                else:
                    slots.append(key)
                if key in catalog:
                    continue
                row = next(r for r in tables[kind + "SheetHolder"]["Entries"]
                           if field(r, "Id")["_sequentialId"] == entry_id)
                if kind == "Hero":
                    visual = visuals[field(row, "VisualConfig")["m_PathID"]]
                    icon = visual["PortraitSpritesPerRank"][0]
                    tier = 1
                else:
                    icon = field(row, "Icon")
                    tier = field(row, "Rarity")
                price = next(field(r, "Value") for r in prices[cost_table] if field(r, "Element") == tier)
                catalog[key] = dict(kind=kind, id=entry_id, price=price,
                                    icon=save_sprite(source, file, icon, game))
        stock[str(field(shop, "HeroId"))] = slots
    result = dict(starting_shards=tables["PlayerSingleton"]["StartingShards"],
                  surviving_hero_shards=tables["RewardSelectionSingleton"]["ShardRewardPerSurvivingHero"],
                  stock=stock, catalog=catalog, fallbacks=fallbacks)
    (game / "balancing" / filename).write_text(json.dumps(result, indent=2), encoding="utf8")


def extract_crossroads(records, step, layouts, source, file, game):
    sheets = {r["type"]: r["fields"] for r in records}

    def index(sheet):
        return {field(row, "Id")["_sequentialId"]: row for row in sheets[sheet]["Entries"]}

    events = index("EventSheetHolder")
    pools = index("EventPoolSheetHolder")
    item_pools = index("ItemPoolSheetHolder")
    item_rows = index("ItemSheetHolder")
    stat_pools = index("StatModPoolSheetHolder")
    stats = index("StatModSheetHolder")
    refs = {str(r["rid"]): r for r in sheets["EventSheetHolder"]["references"]["RefIds"]}
    steps = read_fields(step, layouts)["references"]["RefIds"]
    crossroads_id = next(r["data"]["_crossroadsId"] for r in steps
                         if r["type"]["class"] == "CrossroadsOverrideStepData")
    crossroads = index("CrossroadsSheetHolder")[crossroads_id]
    paths = []
    catalog = {}
    for path in field(crossroads, "Paths"):
        entries = ([[path["_eventId"], 1]] if path["_eventId"] >= 0 else
                   [[r["_eventID"], field(r, "Weight")] for r in field(pools[path["_eventPoolId"]], "WeightedEvents")])
        paths.append(entries)
        for event_id, _ in entries:
            row = events[event_id]
            choice, = field(row, "EventChoices")
            reward_ref, = field(choice, "Rewards")
            reward = refs[str(reward_ref["rid"])]
            data = reward["data"]
            kind = reward["type"]["class"]
            offer = {"icon": save_sprite(source, file, field(row, "EventIcon"), game),
                     "art": save_sprite(source, file, field(row, "EventArtwork"), game)}
            if kind == "RangeEventChoiceReward":
                amount = field(data, "Amount")["RawValue"]
                assert amount == field(data, "UpperAmount")["RawValue"] and amount % 65536 == 0
                offer.update(kind="shards", amount=amount // 65536)
            elif kind == "EquipmentPoolEventChoiceReward":
                choices = field(item_pools[data["_entryId"]], "WeightedRewards")
                offer.update(kind="item", choices=[[r["_elementId"], field(r, "Weight")] for r in choices])
                for entry in choices:
                    save_sprite(source, file, field(item_rows[entry["_elementId"]], "Icon"), game)
            elif kind == "StatModEventChoiceReward":
                only_stat, = field(stat_pools[data["_entryId"]], "WeightedStatMods")
                stat = stats[only_stat["_elementId"]]
                offer.update(kind="training", modifier=only_stat["_elementId"], target_stat=field(stat, "TargetStat"),
                             amount_q16=field(stat, "Value")["RawValue"])
            else:
                raise ValueError(kind)
            catalog[event_id] = offer
    (game / "balancing/first_crossroads.json").write_text(
        json.dumps(dict(id=crossroads_id, paths=paths, events=catalog), indent=2), encoding="utf8")


def extract(data, game):
    records = json.loads((game / "balancing/sharedassets1.json").read_text())["records"]
    heroes = next(r["fields"]["Entries"] for r in records if r["type"] == "HeroSheetHolder")
    with ExitStack() as stack:
        source = Source(data, stack)
        settings = next(o.read_typetree() for o in source.file("globalgamemanagers").objects.values()
                        if o.type.name == "BuildSettings")
        layouts = BuildLayouts(settings["m_Version"])
        layouts.load_local_game(str(data.parent))
        source.env.typetree_generator = layouts
        for f in data.glob("*.assets"):
            source.file(f.name)
        file = source.file("sharedassets1.assets")
        step = next(o for o in file.objects.values() if o.type.name == "MonoBehaviour"
                    and o.parse_monobehaviour_head().m_Name == "Ftue_1_HeroSelectionTutorialStepEntry")
        refs = read_fields(step, layouts)["references"]["RefIds"]
        choices = next(r["data"]["_heroIds"] for r in refs if r["type"]["class"] == "HeroListStepData")
        vitality = next(r["data"]["_heroHealthPairs"] for r in refs
                        if r["type"]["class"] == "TurtleHealthOverrideStepData")
        result = []
        for hero_id in choices:
            row = next(h for h in heroes if h["<Id>k__BackingField"]["_sequentialId"] == hero_id)
            visual = next(r for r in records if r["id"] == row["<VisualConfig>k__BackingField"]["m_PathID"])
            portrait = save_sprite(source, file, visual["fields"]["SquarePortraitSprite"], game)
            result.append(dict(id=hero_id, portrait=portrait,
                               turtle_hp=next(p["HealthOverride"] for p in vitality if p["HeroId"] == hero_id)))
        (game / "balancing/first_battle.json").write_text(json.dumps(result, indent=2))
        print(result)
        shop_step = next(o for o in file.objects.values() if o.type.name == "MonoBehaviour"
                         and o.parse_monobehaviour_head().m_Name == "Ftue_6_FirstShop_TutorialStepEntry")
        extract_shop(records, shop_step, layouts, source, file, game, "first_shop.json")
        second_shop = next(o for o in file.objects.values() if o.type.name == "MonoBehaviour"
                           and o.parse_monobehaviour_head().m_Name == "Ftue_9_SecondShop_TutorialStepEntry")
        extract_shop(records, second_shop, layouts, source, file, game, "second_shop.json")
        crossroads_step = next(o for o in file.objects.values() if o.type.name == "MonoBehaviour"
                               and o.parse_monobehaviour_head().m_Name == "Ftue_7_FirstCrossroads_TutorialStepEntry")
        extract_crossroads(records, crossroads_step, layouts, source, file, game)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    extract(parser.parse_args().data, Path(__file__).resolve().parents[1] / "game")
