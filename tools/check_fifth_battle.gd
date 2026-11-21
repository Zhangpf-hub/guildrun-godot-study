extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failed = true


func resolve(fight: GuildrunEncounter) -> void:
	fight.start_fight()
	for i in 7200:
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			return
		fight._physics_process(1.0 / 30.0)
	check(false, "Unresolved fifth battle")


func next_room(stage: Node, id: int) -> void:
	var candidates: Array = stage.next_floor_candidates()
	for key in 1000:
		seed(key)
		if candidates.pick_random() == id:
			seed(key)
			return
	check(false, "Missing stage %d" % id)


func stock_up(shop: GuildrunFirstShop, stage: Node) -> void:
	for roll in 5:
		for i in 3:
			var id := int(shop._data.catalog[shop.stock[i]].id)
			if not shop.roster.has(id) or int(shop.hero_ranks[id]) >= 4 or not shop.buy(i):
				continue
			if shop.pending_hero >= 0:
				shop.choose_specialization(0)
				shop._close_rank_picker()
			elif shop.has_pending_rank_modifier():
				var picker: Control = stage.encounter._ui.get_node("RankModifierPicker")
				picker.find_child("RankChoice0", true, false).pressed.emit()
				picker._movement.custom_step(1.0)
				picker.find_child("RankContinue", true, false).pressed.emit()
		if roll == 0:
			shop.buy(3)
			shop.buy(4)
		if roll >= 4 or shop.shards < 18 or not shop.reroll():
			break
	for i in shop.items.size():
		if not shop.equipped_to.has(i):
			for hero in shop.roster:
				if shop.assign_item(i, hero, stage.base_equipment_limit):
					break


func verify() -> void:
	var wins := 0
	for variant in 6:
		if run_variant(variant):
			wins += 1
	check(wins > 0, "Fifth shop was never reached")
	quit(1 if failed else 0)


func run_variant(variant: int) -> bool:
	seed(1940)
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	stage._trial_roads.clear()
	var fight: GuildrunEncounter = stage.encounter
	fight._rng.seed = 1940
	fight.select_hero(4)
	# Keep this route's historical formation after the starter's automatic placement changed.
	check(fight.transfer_hero(fight._hero.grid_cell, Vector2i(3, 1)), "Set up the route's starting formation")
	resolve(fight)
	fight.open_first_shop()
	var shop := fight.first_shop
	shop._rng.seed = 301
	shop._rank_rng.seed = 301
	check(shop.buy(0) and shop.buy(1), "Recruit tutorial team")
	shop.leave()
	fight.crossroads._rng.seed = 301
	fight.crossroads.select_path(0)
	fight.crossroads.claim()
	next_room(stage, 10101)
	fight.crossroads.departed.emit()
	resolve(fight)
	fight.open_first_shop()
	check(shop.buy(0) and shop.choose_specialization(1), "Specialize starter")
	shop._close_rank_picker()
	shop.buy(3)
	shop.buy(4)
	for i in shop.items.size():
		shop.assign_item(i, 4, stage.base_equipment_limit)
	shop.leave()
	fight.crossroads.offers[0] = 503
	fight.crossroads._rng.seed = 301
	fight.crossroads.select_path(0)
	fight.crossroads.choose_reward(0)
	fight.crossroads.departed.emit()
	resolve(fight)
	fight.open_first_shop()
	stock_up(shop, stage)
	shop.leave()
	next_room(stage, 10301)
	fight.crossroads.select_path(0)
	resolve(fight)
	fight.open_first_shop()
	if shop.visit != 4:
		check(false, "Fourth shop missing")
		stage.free()
		return false
	stock_up(shop, stage)
	shop.toggle_freeze()
	var stock := shop.stock.duplicate()
	shop._leave.pressed.emit()
	var road := fight.crossroads
	check(road._data.id == 30 and road.offers.size() == 1 and road._data.paths[0].size() == 11, "Fourth shop road pool")
	road.offers[0] = [1026, 1018, 1025, 1027, 1028, 1030][variant]
	road._rng.seed = 301
	road.select_path(0)
	match variant:
		0, 1:
			road.choose_reward(0 if variant == 1 else 1)
			road.choose_reward(0)
		2: road.choose_reward(0)
		3, 4: road.choose_reward(1)
		5:
			road.choose_reward(0)
			road.choose_reward(0)
			road.choose_reward(1)
	check(road.claimed, "Event must resolve before travel")
	var expected := 10401 + variant
	next_room(stage, expected)
	road.get_node("Body/Event/Content/Continue").pressed.emit()
	var team := fight._units.filter(func(u: GuildrunBoardUnit): return u.is_hero)
	check(stage.stage_id == expected and team.size() == 3 and fight.phase == GuildrunEncounter.Phase.PLACE, "Fifth deployment")
	fight.start_fight()
	if variant == 0:
		check(team[0].health == team[0].max_health - roundi(team[0].max_health * 0.15), "Rift Puppy opening damage")
	if variant == 4:
		check(team[0].poison_stacks == roundi(team[0].max_health * 0.01), "Fairy Ring starting poison")
	resolve(fight)
	check(fight.phase == GuildrunEncounter.Phase.RESULT, "Fifth battle result")
	var event_id := road.selected_event
	var continued := fight._continue.visible
	if continued:
		var wallet := shop.shards
		fight.open_first_shop()
		check(shop.visit == 5 and fight.phase == GuildrunEncounter.Phase.SHOP and shop.stock == stock and not shop.frozen, "Fifth shop carryover")
		check(shop.shards == wallet + shop.battle_reward + shop.survival_reward, "Fifth victory payout")
		if variant < 2:
			verify_sixth(stage, variant)
	else:
		check(shop.visit == 4, "Lost battle paid rewards")
	print("fifth stage=", expected, " event=", event_id, " shop=", shop.visit)
	stage.free()
	return continued


func verify_sixth(stage: Node, variant: int) -> void:
	var fight: GuildrunEncounter = stage.encounter
	var shop := fight.first_shop
	check(fight.rewind_available and fight.rewind_reserve == 60, "Five wins should charge 60 shards")
	stock_up(shop, stage)
	shop.toggle_freeze()
	shop._leave.pressed.emit()
	var road := fight.crossroads
	check(road.offers == [600], "Direct campfire after fifth shop")
	road._rng.seed = 301
	road.get_node("Body/Paths").get_child(0).pressed.emit()
	var actions := road.get_node("Body/Event/Content/Actions")
	check(actions.get_child_count() == 4 and actions.get_child(2).disabled, "Campfire availability in a fresh normal run")
	road.choose_reward(2)
	check(not road.claimed and road._pending_choice < 0, "Spent recharge on an active rewind")
	var boss_room := 10601 + variant
	next_room(stage, boss_room)
	if variant == 0:
		actions.get_child(3).pressed.emit()
		check(shop.event_durations.get(5106) == 1, "Rest missing")
	else:
		actions.get_child(1).pressed.emit()
		var hero: int = shop.specializations.keys()[0]
		var old_spec: int = shop.specializations[hero].id
		for button: Button in actions.get_children():
			if button.text == tr("Heroes.Hero_%d.Name" % hero):
				button.pressed.emit()
				break
		actions.get_child(0).pressed.emit()
		check(int(shop.specializations[hero].id) != old_spec, "Study should change the chosen hero's specialization")
	check(road.claimed, "Unresolved campfire")
	road.get_node("Body/Event/Content/Continue").pressed.emit()
	check(stage.stage_id == boss_room and fight.phase == GuildrunEncounter.Phase.PLACE, "Missing elite deployment")
	resolve(fight)
	var survivors := fight._units.filter(func(u): return u.is_hero and not u.defeated).size()
	check(survivors > 0 or not fight.rewind_available, "Unexpected sixth fight result")
	var wallet := shop.shards
	fight.open_first_shop()
	check(shop.visit == 6 and fight.phase == GuildrunEncounter.Phase.SHOP, "Missing sixth shop")
	if survivors > 0:
		check(shop.super_shop and shop.reroll_cost == 7 and shop.super_sales.size() == 3, "Elite victory shop rules")
		check(shop.stock.size() == 10 and shop._buttons.size() == 10, "Elite shop catalog layout")
		for slot: int in shop._buttons:
			check(shop._buttons[slot].is_visible_in_tree(), "Elite offer hidden by its panel")
		check(shop.shards == wallet + shop.battle_reward + 2 * survivors and shop.battle_reward == 75, "Elite victory payout")
		check(shop.reroll() and shop.reroll_cost == 8 and shop._buttons.size() == 10, "Elite reroll")
	else:
		check(not shop.super_shop and shop.shards == wallet + 60 and shop.battle_reward == 0, "Elite loss payout")
	check(not shop.event_durations.has(5106), "One-combat rest leaked into another room")
	print("sixth stage=", boss_room, " survivors=", survivors, " super_shop=", shop.super_shop, " offers=", shop.stock.size())
