extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, detail: String) -> void:
	if not ok:
		push_error(detail)
		failed = true


func resolve(fight: GuildrunEncounter) -> void:
	fight.start_fight()
	for frame in 6000:
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			return
		fight._physics_process(1.0 / 30.0)
	check(false, "Fourth floor simulation timed out")


func verify() -> void:
	var victories := 0
	for index in 6:
		seed(1940)
		var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
		root.add_child(stage)
		stage._trial_roads.clear()
		var fight: GuildrunEncounter = stage.encounter
		fight._rng.seed = 1940 + index
		fight.select_hero(4)
		resolve(fight)
		fight.open_first_shop()
		var shop := fight.first_shop
		shop._rng.seed = 301
		check(shop.buy(0) and shop.buy(1), "Failed to recruit")
		shop.leave()
		fight.crossroads._rng.seed = 301
		fight.crossroads.select_path(0)
		fight.crossroads.claim()
		var second_rooms: Array = stage.next_floor_candidates()
		for key in 1000:
			seed(key)
			if second_rooms.pick_random() == 10101:
				seed(key)
				break
		fight.crossroads.departed.emit()
		resolve(fight)
		fight.open_first_shop()
		check(shop.buy(0) and shop.choose_specialization(1), "Could not select specialization")
		shop._close_rank_picker()
		if index in [0, 1]:
			for offer in [3, 4]:
				shop.buy(offer)
			for item in shop.items.size():
				shop.assign_item(item, 4, stage.base_equipment_limit)
		shop.leave()
		fight.crossroads.offers[0] = 503
		fight.crossroads._rng.seed = 301
		fight.crossroads.select_path(0)
		fight.crossroads.choose_reward(0)
		fight.crossroads.departed.emit()
		resolve(fight)
		fight.open_first_shop()
		check(shop.visit == 3 and shop._leave.visible, "Third shop exit missing")
		var frozen_stock := shop.stock.duplicate()
		var sale := shop.sale_index
		if index == 1:
			check(shop.buy(3), "Cannot buy before freeze")
			shop.toggle_freeze()
		shop.leave()
		var road := fight.crossroads
		check(road.offers[0] == 0 and road.offers[1] in range(5000, 5005), "Wrong challenge options")
		var expected := 10301 + index
		var candidates: Array = stage.next_floor_candidates()
		for i in 1000:
			seed(i)
			if candidates.pick_random() == expected:
				seed(i)
				break
		var modifier := 0 if index == 0 else 4999 + index
		if modifier:
			road.offers[1] = modifier
		road.select_path(0 if index == 0 else 1)
		var rewards: Array = road.get("rewards")
		check(stage.stage_id == expected and fight.phase == GuildrunEncounter.Phase.PLACE, "Wrong fourth encounter")
		check(fight.challenge_modifier == modifier, "Stale battle modifier")
		check(rewards.size() == (3 if modifier else 0), "Incorrect challenge reward count")
		var taken := shop.relics.duplicate()
		for id: int in rewards:
			check(not taken.has(id), "Duplicate or prematurely obtained reward")
			taken.append(id)
		for unit in fight._units:
			if not unit.is_hero:
				check(not unit.ability_kind.is_empty(), "Missing enemy ability %s" % unit.name)
		resolve(fight)
		var survivors := fight._units.filter(func(u): return u.is_hero and not u.defeated).size()
		print("stage=", stage.stage_id, " modifier=", modifier, " survivors=", survivors)
		if survivors == 0:
			check(fight._continue.visible and shop.visit == 4 and not fight.rewind_available and shop.rewind_payout == 40, "First defeat must release the rewind reserve")
			check(shop.battle_reward == 0 and shop.survival_reward == 0, "Defeat used the victory table")
			fight.open_first_shop()
			check(fight.phase == GuildrunEncounter.Phase.SHOP and not road.visible, "Lost challenge granted a relic choice")
		else:
			victories += 1
			var wallet := shop.shards
			fight.open_first_shop()
			if modifier:
				check(fight.phase == GuildrunEncounter.Phase.RELIC_REWARD and road.visible, "Missing relic choice after victory")
				var picked := -1 if index == 2 else int(rewards[0])
				var before := shop.relics.size()
				road.call("take_relic", picked)
				road.call("take_relic", picked)
				check(shop.relics.size() == before + (0 if picked == -1 else 1), "Duplicate reward or skip failed")
			check(shop.visit == 4 and fight.phase == GuildrunEncounter.Phase.SHOP, "Fourth shop missing")
			if index == 1:
				check(not shop.frozen and shop.stock == frozen_stock and shop.sale_index == sale and shop.purchased.has(3) and not shop._buttons[3].visible, "Frozen stock, discount or sold slot lost")
			check(shop.shards == wallet + 20 + 2 * survivors, "Wrong fourth-floor payout")
		stage.free()
	check(victories >= 2, "Insufficient coverage of post-victory shop and reward")
	quit(1 if failed else 0)
