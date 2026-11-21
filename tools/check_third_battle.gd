extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failed = true


func resolve(fight: GuildrunEncounter) -> void:
	fight.start_fight()
	for frame in 5400:
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			return
		fight._physics_process(1.0 / 30.0)
	check(false, "Fight timed out")


func verify() -> void:
	var seen := {}
	for event: int in [503, 504, 505, 1001, 1014, 1023, 1024, 1025]:
		var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
		root.add_child(stage)
		var fight: GuildrunEncounter = stage.encounter
		fight._rng.seed = event
		fight.select_hero(4)
		resolve(fight)
		fight.open_first_shop()
		var shop := fight.first_shop
		check(shop.buy(0) and shop.buy(1), "First shop recruits")
		shop.leave()
		fight.crossroads.select_path(0)
		fight.crossroads.claim()
		fight.crossroads.departed.emit()
		resolve(fight)
		fight.open_first_shop()
		check(shop.buy(0) and shop.choose_specialization(1), "Second shop specialization")
		shop._close_rank_picker()
		shop.leave()
		var road := fight.crossroads
		check(road._data.id == 33 and road.offers.size() == 2 and road.offers[0] != road.offers[1], "Wrong crossroads draw")
		road.offers[0] = event
		road._rng.seed = event
		road.select_path(0)
		check(not road.choices.is_empty(), "Event has no choices")
		var index := 0
		if event == 1001:
			index = road.choices.size() - 1
		var chosen: Dictionary = road.choices[index]
		road.choose_reward(index)
		if chosen.kind in ["rank", "retrain"]:
			var target := shop.roster[1] if event == 1024 else 4
			road._choose_hero(target)
			var specification: Dictionary = preload("res://battle/hero_rank.gd").choices(target)[0]
			if event == 1024:
				shop._rank_picker.chosen.emit(0)
				shop._rank_picker.dismissed.emit()
			else:
				road._choose_specialization(specification)
			check(shop.hero_ranks[target] == 2 and shop.specializations[target].id == specification.id, "Event specialization")
		check(road.claimed, "Unclaimed curated reward")
		var counts := [shop.items.size(), shop.relics.size(), shop.delayed_rewards.size()]
		road.choose_reward(index)
		check(counts == [shop.items.size(), shop.relics.size(), shop.delayed_rewards.size()], "Paid twice")
		if event == 1025:
			check(shop.delayed_rewards.size() == 1 and not shop.relics.has(int(chosen.value)), "Delayed reward paid early")
		seed(event)
		road.get_node("Body/Event/Content/Continue").pressed.emit()
		seen[stage.stage_id] = true
		check(stage.stage_id in [10201, 10202] and fight.phase == GuildrunEncounter.Phase.PLACE, "Third room")
		check(fight._units.size() == 6 and fight._hero.rank == 2, "Lost formation or specialization")
		for unit in fight._units:
			if not unit.is_hero:
				check(not unit.ability_kind.is_empty(), "Missing third-room action")
		resolve(fight)
		check(fight.phase == GuildrunEncounter.Phase.RESULT, "No third result")
		var survivors := fight._units.filter(func(u): return u.is_hero and not u.defeated).size()
		if survivors:
			check(shop.battle_reward == 20 and shop.survival_reward == 2 * survivors, "Wrong third victory payout")
			if event == 1025:
				check(shop.relics.has(int(chosen.value)) and shop.delayed_rewards.is_empty(), "Delayed reward missing")
			var wallet := shop.shards
			fight._continue.pressed.emit()
			check(shop.visit == 3 and shop.stock.size() == 6 and shop.shards == wallet + 20 + 2 * survivors, "Third shop payout")
			var first_stock := shop.stock.duplicate()
			wallet = shop.shards
			check(shop.reroll() and shop.reroll_cost == 2 and shop.shards == wallet - 1 and shop.stock != first_stock, "Third shop reroll")
			check(shop.sale_index in range(6), "Missing sale")
			var cost := shop.price_at(3)
			var item := int(shop._data.catalog[shop.stock[3]].id)
			wallet = shop.shards
			check(shop.buy(3) and shop.shards == wallet - cost and shop.items.back() == item and not shop.buy(3), "Restocked item sale")
		print("event=", event, " choices=", road.choices.size(), " third stage=", stage.stage_id, " survivors=", survivors)
		stage.free()
	check(seen.size() == 2, "Missing third-room variant")
	quit(1 if failed else 0)
