extends SceneTree

signal picked(index: int)

var failed := false
var requests: Array[Dictionary] = []


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, detail: String) -> void:
	if not ok:
		failed = true
		push_error(detail)


func verify() -> void:
	root.size = Vector2i(1280, 720)
	var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	fight.start_fight()
	for frame in 3600:
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			break
		fight._physics_process(1.0 / 60.0)
	fight._continue.pressed.emit()
	fight.open_first_shop()
	var shop := fight.first_shop
	# This driver checks shop transactions independently of the picker lifecycle.
	var presentation := Callable(fight, "_show_rank_modifier_picker")
	if shop.rank_modifier_choice_requested.is_connected(presentation):
		shop.rank_modifier_choice_requested.disconnect(presentation)
	shop.rank_modifier_choice_requested.connect(_on_request)
	picked.connect(shop.choose_rank_modifier)
	var choices: Array = load("res://battle/hero_rank.gd").choices(4)
	shop.specializations[4] = choices[0]
	shop.hero_ranks[4] = 2
	stage.contract.slots_by_rank = true
	shop._rank_rng.seed = 10000
	prime(shop, "Hero_4")
	await process_frame
	var initial_balance := shop.shards
	var price := shop.price_at(0)
	var capacity := shop.equipment_limit(4)
	check(capacity == mini(2, stage.max_item_slots), "Contract capacity before B→A")
	click((shop._buttons[0] as Button).get_global_rect().get_center())
	check(requests.size() == 1 and requests[0].rank == 3, "Physical shop click opens A choice")
	check(shop.shards == initial_balance - price and shop.purchased.has(0), "Successful purchase charges the quote once")
	check(shop.hero_ranks[4] == 2 and shop.equipment_limit(4) == capacity, "Rank and slots remain unchanged while pending")
	check(shop.rank_modifiers_for(4).is_empty(), "Nothing granted before the selection")
	check(not shop.buy(0) and not shop.sell("Hero", 4) and not shop.reroll(), "Pending prevents shop re-entry")
	shop.leave()
	check(not shop._departed, "Pending prevents leaving")
	picked.emit(99)
	check(shop.has_pending_rank_modifier(), "Invalid pick preserves pending")
	picked.emit(1)
	var earned: Dictionary = shop.rank_modifiers_for(4)
	check(shop.hero_ranks[4] == 3 and shop.equipment_limit(4) == mini(3, stage.max_item_slots), "Valid pick advances rank and capacity")
	check(earned.size() == 1 and earned.get(3) == requests[0].offers[1], "A choice belongs to rank 3")
	picked.emit(0)
	check(shop.rank_modifiers_for(4) == earned and shop.shards == initial_balance - price, "Second selection is inert")
	# Simulate a restored original DTO which explicitly carries its rank-3 modifier.
	shop.rank_modifiers_by_hero.erase(4)
	shop.rank_modifiers_by_hero["4"] = {"3": float(earned.get(3, 1))}
	shop.apply_event_reward("training", 1, 4)
	check(requests.size() == 1 and shop.hero_ranks[4] == 3, "Ordinary stat training does not rank up")
	var training_balance := shop.shards
	check(shop.return_from_training(4), "Actual returned-hero API requests S")
	check(requests.size() == 2 and requests[1].rank == 4 and not requests[1].offers.has(earned.get(3)),
		"Training return uses S pool and excludes explicit A modifier")
	check(shop.hero_ranks[4] == 3 and shop.equipment_limit(4) == mini(3, stage.max_item_slots), "Training return waits at A")
	picked.emit(0)
	check(shop.hero_ranks[4] == 4 and shop.shards == training_balance, "Training upgrade does not charge a shop price")
	check(shop.rank_modifiers_for(4).size() == 2 and shop.hero_modifiers[4] == [1], "Old explicit A and training stats survive")
	check(not shop.return_from_training(4), "A maxed hero cannot request another choice")
	shop.prepare_third(0, 0, true)
	shop._data.super_odds.Hero = {"4": 1}
	shop._roll_stock()
	var fresh_offer := -1
	for index: int in shop.offer_rank_modifiers:
		if not shop.roster.has(int(shop._data.catalog[shop.stock[index]].id)):
			fresh_offer = index
			break
	if fresh_offer < 0:
		push_error("Real super-shop stock must include a new S hero")
		quit(1)
		return
	var fresh_id := int(shop._data.catalog[shop.stock[fresh_offer]].id)
	var quote: Dictionary = shop.offer_rank_modifiers[fresh_offer].duplicate()
	var quoted_spec: Dictionary = shop.offer_specs[fresh_offer].duplicate()
	shop.shards = 500
	shop.claim_and_open()
	await process_frame
	var new_cost := shop.price_at(fresh_offer)
	var new_balance := shop.shards
	click((shop._buttons[fresh_offer] as Button).get_global_rect().get_center())
	check(shop.roster.has(fresh_id) and shop.hero_ranks[fresh_id] == 4 and shop.rank_modifiers_for(fresh_id) == quote
		and quote.size() == 2 and quote[3] != quote[4] and shop.specializations[fresh_id] == quoted_spec,
		"New pre-ranked hero receives exact stock-time specialization and ranks")
	check(shop.shards == new_balance - new_cost and requests.size() == 2, "New pre-ranked hero charges once without pending")
	prime(shop, "Hero_%d" % fresh_id)
	await process_frame
	var max_rank_balance := shop.shards
	click((shop._buttons[0] as Button).get_global_rect().get_center())
	check(shop.shards == max_rank_balance and not shop.purchased.has(0), "Max-rank duplicate remains unpurchased")
	prime(shop, "Hero_%d" % (26 if fresh_id != 26 else 14))
	shop.shards = 0
	shop._refresh()
	await process_frame
	click((shop._buttons[0] as Button).get_global_rect().get_center())
	check(not shop.roster.has(26 if fresh_id != 26 else 14) and not shop.purchased.has(0) and not shop.buy(0), "Failed transaction preserves inventory and purchase state")
	if not failed:
		print("rank modifier shop click, training return, pre-ranked stock and legacy data passed")
	quit(int(failed))


func prime(shop: GuildrunFirstShop, key: String, rank := 1) -> void:
	shop.prepare_third(0, 0, rank > 1)
	shop.stock.assign([key])
	shop.offer_ranks.clear()
	shop.offer_specs.clear()
	shop.offer_rank_modifiers.clear()
	shop.super_sales.clear()
	shop.sale_index = -1
	if rank > 1:
		var id := int(shop._data.catalog[key].id)
		shop.offer_ranks[0] = rank
		shop.offer_specs[0] = load("res://battle/hero_rank.gd").choices(id)[0]
		shop.offer_rank_modifiers[0] = shop._roll_pre_ranked(id, rank)
	shop.shards = 500
	shop.claim_and_open()


func _on_request(hero: int, rank: int, offers: Array[int]) -> void:
	requests.append({"hero": hero, "rank": rank, "offers": offers})


func click(point: Vector2) -> void:
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = point
	mouse.global_position = point
	mouse.pressed = true
	root.push_input(mouse, true)
	mouse.pressed = false
	root.push_input(mouse, true)

