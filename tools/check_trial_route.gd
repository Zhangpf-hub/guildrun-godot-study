extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func verify() -> void:
	for contract in [0, 2, 4]:
		var stage: Node = (load("res://battle/stage.tscn") as PackedScene).instantiate()
		stage.contract_index = contract
		root.add_child(stage)
		var tier := int(stage.contract.stage_index) - 1
		expect(stage._trial_roads.size() == 1, "Exactly one trial road in the Forest")
		expect(stage.trial_road_id() == -1, "Opening has a normal road")
		stage._trial_roads = {3: 34, 6: 35, 9: 36}
		expect(stage.load_board(10301 + tier * 10000), "Fourth board")
		expect(stage.trial_road_id() == 34, "Fourth road")
		expect(stage.trial_map(1032) == 50101 + tier * 3, "Fourth solo board")
		expect(stage.trial_map(1033) == 50201 + tier * 2, "Fourth survival board")
		expect(stage.trial_map(1034) == 50301 + tier * 2, "Fourth turtle board")
		expect(stage.load_board(10701 + tier * 10000), "Seventh board")
		expect(stage.trial_road_id() == 35, "Seventh road")
		expect(stage.trial_map(1032) == 50102 + tier * 3, "Seventh solo board")
		expect(stage.trial_map(1033) == 50202 + tier * 2, "Seventh survival board")
		expect(stage.trial_map(1034) == 50302 + tier * 2, "Seventh turtle board")
		expect(stage.load_board(101001 + tier * 100000), "Tenth board")
		expect(stage.trial_road_id() == 36, "Tenth road")
		expect(stage.trial_map(1032) == 50103 + tier * 3, "Tenth solo board")
		expect(stage.trial_map(1035) == 50401 + tier * 2, "Default Hydra")
		stage.last_miniboss_group = "Hydra"
		expect(stage.trial_map(1035) == 50402 + tier * 2, "Demon after Hydra")
		stage.free()

	for victory in [true, false]:
		var stage: Node = (load("res://battle/stage.tscn") as PackedScene).instantiate()
		root.add_child(stage)
		var fight: GuildrunEncounter = stage.encounter
		fight.select_hero(4)
		if fight.first_shop == null:
			fight._create_party()
		var shop := fight.first_shop
		shop.roster.assign([4])
		shop.hero_ranks = {4: 1}
		shop.reserve_slots.assign([-1, -1])
		var shards := shop.shards
		var reserve := fight.rewind_reserve
		var wins := fight._regular_wins
		expect(stage.load_board(10301), "Ordinary fourth floor")
		var next_floors: Array[int] = stage.next_floor_candidates()
		fight._enter_next_battle({"stage_id": stage.trial_map(1032), "modifier": 5500, "kind": "shards", "value": 20})
		expect(stage.stage_id == 50101 and fight.phase == GuildrunEncounter.Phase.PLACE, "Trial inserted after fourth floor")
		expect(stage.next_floor_candidates() == next_floors, "Trial preserves run floor")
		fight.start_fight()
		for unit in fight._units:
			if unit.is_hero != victory:
				unit.take_damage(unit.max_health * 2)
		fight._step_battle(GuildrunEncounter.BATTLE_STEP_Q16)
		expect(fight.phase == GuildrunEncounter.Phase.RESULT and fight._trial_won == victory, "Trial result for %s (phase %s, outcome %s)" % [victory, fight.phase, fight._trial_won])
		expect(shop.shards == shards, "Reward pending on result panel")
		fight.open_first_shop()
		expect(stage.stage_id in next_floors and fight.phase == GuildrunEncounter.Phase.PLACE, "Trial continues directly to fifth floor")
		expect(fight.trial.is_empty() and fight.rewind_reserve == reserve and fight._regular_wins == wins, "Trial cleanup and regular run counters")
		expect(shop.shards == shards + (20 if victory else 0), "Trial reward settles once")
		stage.free()
	print("TRIAL_ROUTE three tiers, one guaranteed road, opposite boss, victory and loss continuation")
	quit(1 if failed else 0)




