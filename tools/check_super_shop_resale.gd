extends "check_shop_sales.gd"

const HERO_PRICES := {1: 9, 2: 16, 3: 23, 4: 29}
const ITEM_PRICES := {1: 3, 2: 9, 3: 16, 4: 3}


func verify() -> void:
	root.size = Vector2i(1280, 720)
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	for room: int in [10601, 101301]:
		stage.stage = stage._stages[room]
		var expected_chunk := 0 if room == 10601 else 1
		check(int(stage.floor_rules().get("chunk", -1)) == expected_chunk, "Fixture uses the actual elite room's chapter")
		for category: String in ["heroRank", "itemRarity"]:
			var expected := HERO_PRICES if category == "heroRank" else ITEM_PRICES
			for tier: int in expected:
				check(stage.resale_price_for(category, tier, false) == expected[tier], "Ordinary authored resale")
				check(stage.resale_price_for(category, tier, true) == expected[tier], "Current super shop authored resale")

	var balance_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/sharedassets1.json"))
	var source: Dictionary = balance_data.records.filter(func(row: Dictionary): return row.type == "ShopSingleton")[0].fields.duplicate(true)
	source._superShopHeroRankResaleMultipliers = [
		resale_row(0, 2, 65536),
		resale_row(0, 3, 49152),
		resale_row(1, 2, 32768),
	]
	source._superShopItemRarityResaleMultipliers = [resale_row(0, 2, 32768)]
	stage._load_resale_prices(source)
	check(stage.resale_price_for("heroRank", 2, true) == 12, "Chapter 1 B rank uses its own Q16 multiplier, truncating 12.5")
	check(stage.resale_price_for("heroRank", 3, true) == 26, "Missing chapter 1 rank uses chapter 0")
	check(stage.resale_price_for("heroRank", 4, true) == 29, "Missing rank in both chapters uses ordinary rank")
	check(stage.resale_price_for("itemRarity", 2, true) == 7, "Items use authored rarity tables and chapter 0 fallback")
	check(stage.resale_price_for("itemRarity", 4, true) == 3, "Missing rarity uses the global Q16 fallback")
	check(stage.resale_price_for("heroRank", 2, false) == 16 and stage.resale_price_for("itemRarity", 2, false) == 9,
			"Changing only super data leaves ordinary prices intact")
	stage.stage = stage._stages[10601]
	check(stage.resale_price_for("heroRank", 2, true) == 25, "Same rank resolves differently in chapter 0")
	stage.stage = stage._stages[101301]

	var fight: GuildrunEncounter = stage.encounter
	fight._choices.hide()
	fight._create_party()
	fight.phase = GuildrunEncounter.Phase.SHOP
	var shop := fight.first_shop
	shop.roster.assign([4, 26, 14])
	shop.hero_ranks = {4: 2, 26: 1, 14: 1}
	for id: int in stage.items:
		if int(stage.field(stage.items[id], "Rarity")) == 2:
			shop.items.append(id)
			break
	shop.visit = 11
	shop.prepare_third(0, 0, true)
	check(shop.super_shop and not shop.sell("Hero", 4), "Unclaimed super shop cannot sell")
	shop.claim_and_open()
	check(is_instance_valid(shop._selling) and shop._selling.target.visible, "Claimed super shop exposes a sale drop target")
	var wallet := shop.shards
	shop._rank_picker = Control.new()
	check(not shop.sell("Hero", 4) and shop.shards == wallet, "Pending rank selection blocks selling")
	shop._rank_picker.free()
	shop._rank_picker = null
	for frame in 4:
		await process_frame
	check(shop.resale_price("Hero", 4) == 12, "The drop preview uses the chapter- and rank-specific value")
	await drag_to_sale(shop, shop._selling.row.get_child(0))
	check(shop.shards == wallet + 12 and not shop.roster.has(4), "Actual UI drop pays the same value and removes the hero")
	check(shop.sell("Item", 0) and shop.shards == wallet + 19, "Item payout uses the same preview calculation")
	check(shop.sell("Hero", 26) and not shop.sell("Hero", 14), "Last-owned hero cannot be sold")
	shop.leave()
	check(not shop.sell("Hero", 14), "Departed super shop does not sell")
	stage.free()
	print("SUPER_SHOP_RESALE real chapters, Q16 rounding and fallbacks, unchanged ordinary values, native-mode drag payout")
	quit(1 if failed else 0)


func resale_row(chunk: int, tier: int, multiplier: int) -> Dictionary:
	return {"<ChunkIndex>k__BackingField": chunk, "<Element>k__BackingField": tier,
			"<Multiplier>k__BackingField": {"RawValue": multiplier}}
