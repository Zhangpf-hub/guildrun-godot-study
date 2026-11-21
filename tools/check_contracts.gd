extends "check_fifth_battle.gd"

var rules = load("res://battle/difficulty_rules.gd")


func verify() -> void:
	var progress := "user://contract-test-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	var tiers := [1, 1, 2, 2, 2, 3, 3]
	for i in 7:
		var stage = load("res://battle/stage.tscn").instantiate()
		stage.contract_index = i
		root.add_child(stage)
		var contract = stage.contract
		check(contract.stage_index == tiers[i] and contract.score_bonus == i * 2, "Stage tier and score")
		check(contract.start_health_q16 == (65536 if i == 0 else 58982), "Cumulative health penalty")
		check(contract.survivor_delta == (-1 if i >= 3 else 0) and contract.slots_by_rank == (i >= 4), "Cumulative rewards and slots")
		var candidates: Array = stage.next_floor_candidates()
		check(not candidates.is_empty() and candidates.all(func(id): return int(stage.field(stage._stages[id], "DifficultyIndex")) == tiers[i]), "Shared first room to contract schedule")
		verify_schedule(stage, i, tiers[i])
		var fight: GuildrunEncounter = stage.encounter
		fight.select_hero(26)
		var hero := fight._hero
		fight.start_fight()
		check(hero.health == ((hero.max_health * int(contract.start_health_q16) + 32768) >> 16), "Start health")
		var shop := GuildrunFirstShop.new()
		stage.add_child(shop)
		shop.battle_stage = stage
		shop.prepare(26, stage.stage, 1)
		check(shop.survival_reward == 0, "No survivor reward on the first floor")
		shop.prepare_second(35, 1)
		check(shop.survival_reward == (1 if i >= 3 else 2), "Shop survivor reward")
		shop.items.assign([701, 703, 702, 704])
		for rank in range(1, 5):
			shop.equipped_to.clear()
			shop.hero_ranks[26] = rank
			var limit := rank if i >= 4 else (4 if rank == 4 else 3)
			for slot in range(4):
				check(shop.assign_item(slot, 26, stage.base_equipment_limit) == (slot < limit), "Equipment slots at contract %d rank %d" % [i, rank])
		if i in [2, 5]:
			resolve(fight)
			fight.open_first_shop()
			fight.first_shop.leave()
			fight.crossroads.select_path(0)
			fight.crossroads.claim()
			fight.crossroads.get_node("Body/Event/Content/Continue").pressed.emit()
			check(fight.phase == GuildrunEncounter.Phase.PLACE and int(stage.field(stage.stage, "DifficultyIndex")) == tiers[i],
					"Turtle, shop and crossroads should lead to the selected tier")
			resolve(fight)
			check(fight.phase == GuildrunEncounter.Phase.RESULT, "Full-health encounter at the new tier")
		if i == 6:
			check(contract.planned_bosses[0] in [30601, 30602] and contract.planned_bosses[1] in [301301, 301302, 301303], "Boss identity follows selected stage")
			check(contract.active_boss_relic in [7000, 7001], "First chapter penalty")
			stage.load_board(30401)
			check(stage.next_floor_candidates() == [contract.planned_bosses[0]], "Planned elite selection")
			stage.load_board(contract.planned_bosses[0])
			check(contract.active_boss_relic == 0, "Relic removed on reaching elite")
			stage.load_board(30701)
			check(contract.active_boss_relic in [7002, 7003, 7004], "Second chapter penalty")
			var rule: Array = contract.DRAGON_STACKS[contract.active_boss_relic]
			check(contract.dragon_stacks == rule[1], "Starting dragon stacks")
			contract.won_battle()
			check(contract.dragon_stacks == rule[1] + rule[2], "Victory increments stacks")
			stage.load_board(contract.planned_bosses[1])
			check(contract.active_boss_relic == 0, "Relic removed on reaching dragon")
			stage.endless_floor = 3
			var summary = load("res://UI/end_screen.tscn").instantiate()
			stage.add_child(summary)
			summary.setup(stage, shop)
			check(summary.get_node("Center/Summary/Scores").text.ends_with("15"), "Fourth endless floor at SSS scores 3 + 12")
		stage.free()
	for relic in range(7000, 7005):
		verify_boss_relic(relic)
	check(rules.unlocked_through(rules.read_progress(progress)) == 0, "Fresh progress")
	var menu = load("res://UI/contracts.tscn").instantiate()
	menu.progress_path = progress
	menu.selecting = true
	root.add_child(menu)
	current_scene = menu
	menu.get_node("Panel/Options").get_child(1).pressed.emit()
	check(menu.get_node("Panel/Actions/Play").disabled, "Locked contract")
	menu._start_game()
	check(current_scene == menu, "Locked start guard")
	menu.get_node("Panel/Options").get_child(0).pressed.emit()
	menu.get_node("Panel/Actions/Play").pressed.emit()
	await process_frame
	await process_frame
	var actual = current_scene
	check(actual != null and actual.stage_id == 10000 and actual.track_contract_progress, "Menu starts a tracked run")
	# Use a controlled final hit to verify that the real victory handler records exactly one win.
	var fight: GuildrunEncounter = actual.encounter
	var skip_comic := InputEventKey.new()
	skip_comic.keycode = KEY_ESCAPE
	skip_comic.pressed = true
	root.push_input(skip_comic, true)
	if is_instance_valid(fight._founding_comic):
		await fight._founding_comic.completed
	fight.select_hero(26)
	actual.stage = actual._stages[101301]
	fight.start_fight()
	for unit in fight._units:
		if not unit.is_hero:
			unit.take_damage(unit.health + unit.total_shield() + 1)
	fight._step_battle(2184)
	var saved: ConfigFile = rules.read_progress(progress)
	check(rules.unlocked_through(saved) == 1 and saved.get_value("forest", "wins_0") == 1, "Boss unlock survives disk reload")
	fight._show_end_screen()
	fight._ui.get_node("EndScreen/Center/Summary/NewRun").pressed.emit()
	await process_frame
	await process_frame
	var next_menu = current_scene
	check(next_menu.selecting and next_menu.selected == 1 and not next_menu.get_node("Panel/Actions/Play").disabled, "New run opens newly unlocked contract")
	next_menu.get_node("Panel/Actions/Play").pressed.emit()
	await process_frame
	await process_frame
	check(current_scene.contract.selected == 1 and current_scene.contract.start_health_q16 == 58982, "Selected second run")
	if FileAccess.file_exists(progress):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(progress))
	print("Contracts: 7 selections, 3 schedules, start health, survivor shards, 28 slot limits, SSS bosses, menu start and unlock")
	quit(1 if failed else 0)


func verify_schedule(stage: Node, index: int, tier: int) -> void:
	var visited := {10000: true}
	var pending := [10000]
	while not pending.is_empty():
		var id := int(pending.pop_back())
		stage.stage_id = id
		stage.stage = stage._stages[id]
		var floor_index := int(stage.field(stage.stage, "FloorNumber"))
		var next: Array = stage.next_floor_candidates()
		check(next.is_empty() == (floor_index == 11), "Each route must reach the final boss")
		for room: int in next:
			var row: Dictionary = stage._stages[room]
			check(int(stage.field(row, "DifficultyIndex")) == tier and int(stage.field(row, "FloorNumber")) == floor_index + 1,
					"Contract crossed tiers or skipped a floor")
			if not visited.has(room):
				visited[room] = true
				pending.append(room)
	check(visited.size() == (69 if index == 6 else 72), "Reachable maps in contract %d: %d" % [index, visited.size()])
	stage.stage_id = 10000
	stage.stage = stage._stages[10000]


func verify_boss_relic(relic: int) -> void:
	var stage = load("res://battle/stage.tscn").instantiate()
	stage.contract_index = 6
	root.add_child(stage)
	var contract = stage.contract
	var chunk := 0 if relic <= 7001 else 1
	for room: int in contract.boss_map:
		if int(contract.boss_map[room]) == relic:
			contract.planned_bosses[chunk] = room
	contract._chunk = -1
	contract.enter_floor(chunk, false, false)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(26)
	var turtle: GuildrunBoardUnit = fight._units[0]
	var original_speed := int(turtle.stat("AttackSpeed"))
	var original_regen := int(turtle.stat("HPPerSecond"))
	fight.start_fight()
	match relic:
		7000:
			turtle.take_damage(turtle.health - floori(turtle.max_health * 0.5))
			check(turtle.fury_used and int(turtle.stat("AttackSpeed")) == original_speed + 20 and turtle.total_shield() == ((turtle.max_health * 6554) >> 16), "Demon fury at half HP")
			turtle.take_damage(1)
			check(int(turtle.stat("AttackSpeed")) == original_speed + 20, "Demon fury triggered twice")
		7001:
			check(int(turtle.stat("HPPerSecond")) == original_regen + floori(turtle.max_health / 150.0), "Hydra regeneration")
		7002:
			check(fight._hero.burn_stacks == 18, "Fire dragon opener")
		7003:
			check(fight._hero.frost_stacks == 8, "Frost dragon opener")
		7004:
			check(fight._hero.poison_stacks == 12, "Poison dragon opener")
	stage.free()
