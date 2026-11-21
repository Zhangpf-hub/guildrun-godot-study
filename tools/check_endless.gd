extends "check_forest_challenges.gd"


func verify() -> void:
	verify_growth()
	for room in 3:
		verify_full_health_fight(room)
	var stage := late_party()
	current_scene = stage
	var fight: GuildrunEncounter = stage.encounter
	var shop := fight.first_shop
	stage.stage = stage._stages[101301]
	shop.visit = 11
	shop.prepare_third(0, 3, true)
	shop.claim_and_open()
	var wallet := shop.shards
	var inventory := shop.items.duplicate()
	shop._leave.pressed.emit()
	check(stage.endless_maps == [101, 102, 103], "Endless map schedule")
	var rooms := [[104, 104, 101, 102, 103], [105, 105, 108, 108], [109, 109, 109]]
	var initial_health := 0
	for i in 4:
		check(fight.phase == GuildrunEncounter.Phase.PLACE and stage.stage_id == 101 + i % 3 and stage.endless_floor == i,
				"Wrong next floor %d" % i)
		if failed:
			quit(1)
			return
		var enemies := fight._units.filter(func(unit): return not unit.is_hero)
		var ids := enemies.map(func(unit): return int(unit.stat("Id")._sequentialId))
		check(ids == rooms[i % 3], "Enemy composition %s" % str(ids))
		if i == 0:
			initial_health = enemies[0].max_health
		if i == 3:
			check(enemies[0].max_health > initial_health and stage.endless_cycle() == 1, "Second cycle health")
			break
		# Control the last hit to test routing independently of balance and shopping choices.
		for enemy: GuildrunBoardUnit in enemies:
			enemy.health = 1
		resolve(fight)
		check(fight._endless_won and fight.phase == GuildrunEncounter.Phase.RESULT, "Endless victory")
		fight._continue.pressed.emit()
		if i == 2:
			var road := fight.crossroads
			check(fight.phase == GuildrunEncounter.Phase.CROSSROADS and road.offers.size() == 3 and road._data.id == 123, "Third-floor crossroads")
			road.offers[0] = 2005
			road.select_path(0)
			road.choose_reward(0)
			road.choose_reward(0)
			road.get_node("Body/Event/Content/Continue").pressed.emit()
	check(shop.visit == 12 and shop.shards == wallet and shop.items == inventory, "Extra shop or gold")
	for id in range(2001, 2015):
		test_event(shop, id)
	test_recruitment_limits(shop)
	for unit in fight._units:
		if unit.is_hero:
			unit.take_damage(unit.max_health)
	resolve(fight)
	check(not fight._endless_won and fight._continue.visible, "Endless loss")
	fight._continue.pressed.emit()
	var screen := fight._ui.get_node("EndScreen")
	var scores := str(screen.get_node("Center/Summary/Scores").text)
	check(fight.phase == GuildrunEncounter.Phase.END_SCREEN and scores.ends_with("3"), "Loss score")
	print("Endless: 101/102/103, second cycle, 14 events, floor 4 loss and score 3")
	screen.get_node("Center/Summary/NewRun").pressed.emit()
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.endless_floor == -1 and current_scene.encounter.phase == GuildrunEncounter.Phase.PICK,
			"New run should reset to tutorial recruit")
	quit(1 if failed else 0)


func verify_growth() -> void:
	# Reference values from the Steam build's EnemyData.Power and embedded Photon tables.
	var samples := {
		98304: [500, 614, 804, 1669, 8025], 104858: [500, 635, 868, 2023, 12484],
		108134: [500, 645, 900, 2216, 15410], 114688: [500, 664, 964, 2641, 23057],
		121242: [500, 683, 1029, 3115, 33732], 131072: [500, 711, 1128, 3928, 57522],
	}
	var cycles := [0, 1, 2, 4, 7]
	var scaling = load("res://battle/endless_scaling.gd")
	for factor: int in samples:
		for i in cycles.size():
			check(scaling.scaled_stat(500, factor, cycles[i]) == samples[factor][i],
					"Native growth mismatch at factor %d, cycle %d" % [factor, cycles[i]])


func verify_full_health_fight(room: int) -> void:
	var stage := late_party()
	var fight: GuildrunEncounter = stage.encounter
	stage.stage = stage._stages[101301]
	stage.endless_floor = room - 1
	fight._enter_next_battle()
	var health := 0
	for unit in fight._units:
		check(unit.health == unit.max_health, "Full-health spawn")
		if not unit.is_hero:
			health += unit.health
	resolve(fight)
	check(fight.phase == GuildrunEncounter.Phase.RESULT and fight._frame > 1, "Full-health battle did not finish")
	print("Full-health endless map ", stage.stage_id, " enemy HP ", health, " steps ", fight._frame, " victory ", fight._endless_won)
	if not fight._endless_won:
		fight._continue.pressed.emit()
		var scores := fight._ui.get_node("EndScreen/Center/Summary/Scores") as Label
		check(scores.text.ends_with(str(room)), "Floor-one loss starts at zero completed floors")
	stage.free()


func test_event(shop: GuildrunFirstShop, id: int) -> void:
	var road: GuildrunFirstCrossroads = load("res://UI/first_crossroads.tscn").instantiate()
	root.add_child(road)
	road.setup(shop.roster, shop)
	road.offers[0] = id
	road.select_path(0)
	var first := road.choices[0]
	if id == 2004:
		road.choose_reward(0)
		var buttons := road.get_node("Body/Event/Content/Actions")
		buttons.get_child(0).pressed.emit()
		buttons.get_child(0).pressed.emit()
	elif id == 2012:
		check(first.has("children"), "S-rank class options")
		var classes := 0
		for option: Dictionary in road.choices:
			if not option.has("children"):
				continue
			classes += 1
			var offer: Dictionary = option.children[0]
			check(not shop.roster.has(int(offer.hero)), "Already owned heroes are excluded from class offers")
			check(offer.rank_modifiers.size() == 2 and offer.rank_modifiers[3] != offer.rank_modifiers[4],
				"Both distinct rank modifiers are generated with the class offer")
		check(classes == 3, "Three eligible class choices precede Leave")
		var quote: Dictionary = first.children[0].duplicate(true)
		var size_before := shop.roster.size()
		var shards_before := shop.shards
		road.choose_reward(0)
		var hero := int(road.choices[0].hero)
		check(road.choices[0] == quote and not shop.roster.has(hero), "Preview preserves the generated S offer")
		road.choose_reward(0)
		check(shop.hero_ranks.get(hero) == 4 and shop.specializations.get(hero) == quote.spec
			and shop.rank_modifiers_for(hero) == quote.rank_modifiers and not shop.has_pending_rank_modifier(),
			"Confirm grants the exact S offer without a rank picker")
		shop.take_curated_reward(quote)
		check(shop.roster.size() == size_before + 1 and shop.shards == shards_before,
			"A duplicate confirmation cannot grant another hero or shard payout")
	elif id <= 2003:
		var owned: Array = shop.items if id == 2001 else shop.relics
		var count := owned.size()
		check(road.choices.size() == (1 if id == 2003 else 3), "Rolled reward count")
		road.choose_reward(0)
		road.choose_reward(0)
		check(owned.size() == count + 1 and owned.back() == first.value, "Reward grant count")
	else:
		var modifier := int(road._data.events[str(id)].modifier)
		var hero := shop.roster[0]
		var before := (shop.hero_modifiers.get(hero, []) as Array).count(modifier)
		road.choose_reward(0)
		road.get_node("Body/Event/Content/Actions").get_child(-1).pressed.emit()
		check(road.choices[0] == first and not road.claimed, "Stat choice Back")
		road.choose_reward(0)
		road.choose_reward(0)
		check((shop.hero_modifiers[hero] as Array).count(modifier) == before + 1, "Permanent stat reward")
	check(road.claimed, "Unclaimed event %d" % id)
	road.free()


func test_recruitment_limits(shop: GuildrunFirstShop) -> void:
	var saved_capacity := int(shop.battle_stage.max_total_heroes)
	shop.battle_stage.max_total_heroes = shop.roster.size()
	var road: GuildrunFirstCrossroads = load("res://UI/first_crossroads.tscn").instantiate()
	root.add_child(road)
	road.setup(shop.roster, shop)
	check(not road.offers.has(2012), "Full parties do not draw the S-rank recruitment event")
	var pool: Array = road._data.pools.hero["1"]
	var candidate := -1
	for pair: Array in pool:
		if not shop.roster.has(int(pair[0])):
			candidate = int(pair[0])
			break
	var owned := shop.roster.duplicate()
	var shards := shop.shards
	shop.take_curated_reward({"kind": "hero", "value": candidate})
	check(candidate >= 0 and shop.roster == owned and shop.shards == shards,
		"A capacity change before confirmation cannot grant an extra hero or convert it to shards")
	road.offers[0] = 2012
	road.select_path(0)
	check(road.choices.size() == 1 and road.choices[0].kind == "leave", "A stale full-party route offers only Leave")
	shop.battle_stage.max_total_heroes = saved_capacity
	road.free()
