extends SceneTree

const Stats = preload("res://battle/battle_statistics.gd")

class BattleDamageLog extends GuildrunBattleStatistics:
	var step: int
	var character_ids: Dictionary[int, int] = {}
	var hits: Array[Array] = []

	func attach(fight: GuildrunEncounter) -> void:
		units.assign(fight.battle_statistics.units)
		fight.battle_statistics = self
		for unit: GuildrunBoardUnit in fight._units:
			character_ids[unit.get_instance_id()] = int(unit.stat("Id")._sequentialId)
			unit.battle_statistics = self

	func damage(source: int, target: int, origin: Origin, amount: int, shield: int, mitigated: int, relic := 0) -> void:
		super.damage(source, target, origin, amount, shield, mitigated, relic)
		hits.append([step, character_ids.get(source, 0), character_ids.get(target, 0), origin, amount])

var failed := false


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var stats := Stats.new()
	stats.register(101, "A", "", true)
	stats.register(102, "B", "", true)
	stats.register(201, "Enemy", "", false)
	stats.damage(101, 201, Stats.Origin.ATTACK, 12, 6, 2)
	stats.damage(101, 201, Stats.Origin.ABILITY, 19, 0, 2)
	stats.damage(102, 201, Stats.Origin.ITEM, 4, 0, 0)
	stats.damage(101, 201, Stats.Origin.STATUS, 2, 1, 0)
	stats.damage(0, 201, Stats.Origin.OTHER, 5, 0, 0)
	stats.damage(101, 201, Stats.Origin.OTHER, 8, 0, 0, 701)
	stats.support(102, 16, 18)
	stats.support(0, 3, 0, 701)
	expect(Stats.total(stats.units[101], Stats.Mode.DEALT) == 33, "Attack, ability and status credited to A")
	expect(Stats.total(stats.units[102], Stats.Mode.DEALT) == 4, "Item damage credited to B")
	expect(Stats.total(stats.units[201], Stats.Mode.TAKEN) == 61, "Target records damage, shield and mitigation separately")
	expect(Stats.total(stats.units[102], Stats.Mode.SUPPORT) == 34, "Support sums healing and shields")
	expect(stats.relics[701].damage == 8 and stats.relics[701].healing == 3, "Relic receives separate attribution")
	var saved := stats.snapshot(2 << 16, true)
	stats.damage(101, 201, Stats.Origin.ABILITY, 1, 0, 0)
	expect(saved.victory and saved.elapsed_q16 == 131072 and saved.units[101].ability == 19,
			"Previous result is independent of ongoing fight")
	verify_overkill()
	verify_projectile_crit()
	verify_first_fight()
	verify_source_replay()
	verify_second_battle_source_replay()
	verify_second_battle_source_replay(true)
	print("BATTLE_STATISTICS Damage sources, defense segments, support, relics and three native encounter replays")
	quit(1 if failed else 0)


func verify_overkill() -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	fight.start_fight()
	var turtle: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
	var hero := fight._hero
	turtle.health = 7
	turtle.gain_shield(12, 1 << 16)
	fight._land(turtle, 37, hero)
	var stats := fight.battle_statistics
	var dealt := stats.units[hero.get_instance_id()]
	var taken := stats.units[turtle.get_instance_id()]
	expect(turtle.defeated and turtle.health == 0, "A fatal hit clamps actual health to zero")
	expect(dealt.ability == 25 and taken.health_damage == 25 and taken.shield_damage == 12,
			"The damage log uses the full unshielded portion of the hit, including overkill")
	stage.free()


func verify_source_replay() -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.run_seed = 262144
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	var turtle: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
	fight.select_hero(4)
	var hero := fight._hero
	fight.start_fight()
	expect(fight.combat_seed == 500813409, "Native tutorial seed")
	var log := BattleDamageLog.new()
	log.attach(fight)
	var cast_steps: Array[int] = []
	hero.skill_attack_started.connect(func(): cast_steps.append(log.step))
	const ATTACK := Stats.Origin.ATTACK
	const ABILITY := Stats.Origin.ABILITY
	var enemy := int(turtle.get_meta("enemy_id"))
	# Steam build 26551710, unaided Yuna at (3, 0) with 15 shards.
	var native_hits: Array[Array] = [
		[40, enemy, 4, ATTACK, 3], [45, 4, enemy, ATTACK, 40], [100, enemy, 4, ATTACK, 3],
		[111, 4, enemy, ATTACK, 40], [160, enemy, 4, ATTACK, 3], [178, 4, enemy, ATTACK, 40],
		[220, enemy, 4, ATTACK, 3], [245, 4, enemy, ATTACK, 80], [280, enemy, 4, ATTACK, 3],
		[340, enemy, 4, ATTACK, 3], [374, 4, enemy, ABILITY, 150], [374, 4, enemy, ABILITY, 150],
		[400, enemy, 4, ATTACK, 3], [409, 4, enemy, ATTACK, 80],
	]
	for step in range(1, 410):
		log.step = step
		fight._step_battle(fight.BATTLE_STEP_Q16, true)
		match step:
			1:
				expect(hero.moving and hero.grid_cell == Vector2i(3, 0) and hero.move_destination == Vector2i(2, 1)
						and turtle.moving and turtle.grid_cell == Vector2i(3, 4) and turtle.move_destination == Vector2i(3, 3),
						"First movement starts immediately and keeps the occupied cell until crossing")
			9:
				expect(hero.grid_cell == Vector2i(2, 1) and turtle.grid_cell == Vector2i(3, 3),
						"Occupied cells change at the first hex boundary")
			27:
				expect(hero.grid_cell == Vector2i(3, 2) and turtle.attack_cooldown_q16 > 0,
						"Turtle starts its attack when Yuna enters range")
			374:
				expect(turtle.health == 0 and turtle.targetable(), "Turtle stays in combat at exactly zero HP")
			401:
				expect(hero.grid_cell == Vector2i(4, 4) and not hero.is_casting(), "Native Shadow Strike landing")
	expect(cast_steps == [301] and log.hits == native_hits, "Complete native first-fight hit order: %s" % [log.hits])
	expect(turtle.defeated and hero.health == 779 and fight.battle_time_q16 == 893256
			and fight._pending_battle_result.is_valid(), "Native battle resolves at step 409")
	stage.free()


func verify_second_battle_source_replay(logan_first := false) -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.run_seed = 262144
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	fight.start_fight()
	for step in 409:
		fight._step_battle(fight.BATTLE_STEP_Q16)
	var total_time: Label = fight._result_view.get_node(
			fight._result_view.STATS + "/TitlePanel/TotalDurationText/UnityText")
	expect(not total_time.is_visible_in_tree() and fight.last_battle_statistics.run_elapsed_q16 == 893256,
			"The first result tracks run time with the native total label hidden")
	fight._continue.pressed.emit()
	expect(fight.phase == GuildrunEncounter.Phase.SHOP and fight.first_shop.shards == 30, "Original first shop opening balance")
	var purchased_first := fight.first_shop.buy(1 if logan_first else 0)
	var purchased_second := fight.first_shop.buy(0 if logan_first else 1)
	expect(purchased_first and purchased_second, "Recruit Dragomir and Logan from the first shop")
	fight.first_shop.leave()
	var road := fight.crossroads
	road.select_path(0)
	road.claim()
	seed(2) # Choose the same map as the native recording.
	road.get_node("Body/Event/Content/Continue").pressed.emit()
	expect(stage.stage_id == 10101 and fight.first_shop.shards == 5, "Native second room after shard mining")
	if stage.stage_id != 10101:
		stage.free()
		return

	if logan_first:
		verify_contested_moves(fight)
		stage.free()
		return

	var yuna: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 0)]
	var dragomir: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 0)]
	var logan: GuildrunBoardUnit = stage.grid.occupants[Vector2i(5, 0)]
	var tank: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 4)]
	var archer: GuildrunBoardUnit = stage.grid.occupants[Vector2i(0, 7)]
	fight.start_fight()
	expect(fight.combat_seed == 491578230, "Native 10101 seed, with the same run seed and gold")
	var log := BattleDamageLog.new()
	log.attach(fight)
	const ATTACK := Stats.Origin.ATTACK
	const ABILITY := Stats.Origin.ABILITY
	# Steam build 26551710. Index zero in the native log is simulation step one.
	var native_hits: Array[Array] = [
		[48, 102001, 13, ATTACK, 15], [50, 24, 102001, ATTACK, 70],
		[52, 13, 102001, ATTACK, 62], [55, 101901, 4, ATTACK, 9],
		[63, 4, 102001, ATTACK, 40], [100, 101901, 4, ATTACK, 9],
		[114, 102001, 13, ATTACK, 15], [116, 24, 102001, ATTACK, 70],
		[127, 13, 102001, ATTACK, 62], [129, 4, 102001, ATTACK, 40],
		[146, 101901, 4, ATTACK, 9], [180, 102001, 13, ATTACK, 15],
		[183, 24, 102001, ATTACK, 35], [192, 101901, 4, ATTACK, 9],
		[196, 4, 102001, ATTACK, 80], [202, 13, 102001, ATTACK, 62],
		[238, 101901, 4, ATTACK, 9], [247, 102001, 13, ATTACK, 15],
		[250, 24, 102001, ATTACK, 70], [263, 4, 102001, ATTACK, 40],
		[277, 13, 102001, ATTACK, 124], [284, 101901, 4, ATTACK, 9],
		[313, 102001, 13, ATTACK, 15], [316, 24, 102001, ABILITY, 395],
		[327, 101901, 4, ATTACK, 9], [365, 101901, 4, ATTACK, 9],
		[407, 101901, 4, ATTACK, 9], [438, 24, 101901, ATTACK, 35],
		[440, 13, 101901, ATTACK, 62], [452, 101901, 4, ATTACK, 9],
		[453, 13, 101901, ABILITY, 200], [463, 4, 101901, ABILITY, 300],
		[463, 4, 101901, ABILITY, 300],
	]
	# Native occupied cells sampled before each action. Reuse a row until the next crossing.
	var native_cells := {
		0: [Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(4, 4), Vector2i(0, 7)],
		9: [Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1), Vector2i(4, 3), Vector2i(1, 6)],
		27: [Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2), Vector2i(5, 3), Vector2i(1, 6)],
		45: [Vector2i(4, 3), Vector2i(5, 2), Vector2i(6, 2), Vector2i(5, 3), Vector2i(1, 6)],
		325: [Vector2i(4, 4), Vector2i(4, 2), Vector2i(5, 3), Vector2i(5, 3), Vector2i(1, 6)],
		343: [Vector2i(3, 4), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(1, 6)],
		361: [Vector2i(2, 5), Vector2i(2, 3), Vector2i(4, 4), Vector2i(5, 3), Vector2i(1, 6)],
		379: [Vector2i(1, 5), Vector2i(1, 3), Vector2i(3, 5), Vector2i(5, 3), Vector2i(1, 6)],
		397: [Vector2i(1, 5), Vector2i(1, 4), Vector2i(2, 5), Vector2i(5, 3), Vector2i(1, 6)],
		415: [Vector2i(1, 5), Vector2i(0, 5), Vector2i(2, 6), Vector2i(5, 3), Vector2i(1, 6)],
	}
	var expected_cells: Array = []
	var first_path_difference := -1
	for step in range(1, 464):
		expected_cells = native_cells.get(step - 1, expected_cells)
		var cells := [yuna.grid_cell, dragomir.grid_cell, logan.grid_cell, tank.grid_cell, archer.grid_cell]
		if first_path_difference < 0 and cells != expected_cells:
			first_path_difference = step
		log.step = step
		fight._step_battle(fight.BATTLE_STEP_Q16)
		match step:
			1:
				expect(tank.current_target == logan and archer.current_target == yuna, "Native monster targeting order")
			316:
				expect(tank.defeated and dragomir.stat("OmniVamp") == 6 and fight.first_shop.shards == 7,
						"Devour's unshielded hit, post-hit vamp and kill reward")
			317:
				expect(yuna.moving and not yuna.is_casting() and yuna.mana == 75, "Yuna resumes pursuit after the cast loses its target")
			394:
				expect(dragomir.mana == 0, "Devour's mana lock extends the paused regeneration countdown")
			438, 452:
				expect(dragomir.mana == 5, "Dragomir gains only attack mana before the next native regen tick")
			453:
				expect(dragomir.mana == 9, "Dragomir's first post-cast natural regeneration matches the native tick")
	expect(first_path_difference < 0, "Native 10101 occupied-cell sequence diverged at step %d" % first_path_difference)
	expect(log.hits == native_hits, "Complete native second-battle hit order: %s" % [log.hits])
	expect(fight.battle_time_q16 == 1011192 and fight.phase == GuildrunEncounter.Phase.RESULT
			and archer.defeated and yuna.health == 710 and logan.health == 750 and dragomir.health == 800,
			"Native 10101 battle duration and surviving health")
	expect(total_time.is_visible_in_tree() and "29.1" in total_time.text
			and fight.last_battle_statistics.run_elapsed_q16 == 1904448
			and fight.last_battle_statistics.battle_count == 2, "Native cumulative time after the second battle")
	fight._continue.pressed.emit()
	expect(fight.phase == GuildrunEncounter.Phase.SHOP and fight.first_shop.shards == 48,
			"Second shop includes the native 35 battle and 6 survivor shards")
	stage.free()


func verify_contested_moves(fight: GuildrunEncounter) -> void:
	var yuna := fight.board_hero(4)
	var logan := fight.board_hero(13)
	var dragomir := fight.board_hero(24)
	var tank: GuildrunBoardUnit = fight._stage.grid.occupants[Vector2i(4, 4)]
	expect(yuna.grid_cell == Vector2i(3, 0) and logan.grid_cell == Vector2i(4, 0)
			and dragomir.grid_cell == Vector2i(5, 0), "Original alternate recruitment order")
	fight.start_fight()
	expect(fight.combat_seed == 491578230, "Alternate lineup has the same 10101 seed")
	var log := BattleDamageLog.new()
	log.attach(fight)
	var deaths: Array[int] = []
	const ATTACK := Stats.Origin.ATTACK
	const ABILITY := Stats.Origin.ABILITY
	# Index zero in the native log is simulation step one here.
	var native_hits: Array[Array] = [
		[35, 4, 102001, ATTACK, 40], [42, 13, 102001, ATTACK, 62],
		[48, 102001, 4, ATTACK, 15], [50, 24, 102001, ATTACK, 35],
		[57, 101901, 13, ATTACK, 9], [94, 101901, 4, ATTACK, 9],
		[101, 4, 102001, ATTACK, 80], [114, 102001, 4, ATTACK, 15],
		[116, 24, 102001, ATTACK, 35], [139, 101901, 4, ATTACK, 9],
		[168, 4, 102001, ATTACK, 80], [180, 102001, 4, ATTACK, 15],
		[183, 24, 102001, ATTACK, 35], [185, 101901, 4, ATTACK, 9],
		[231, 101901, 4, ATTACK, 9], [235, 4, 102001, ATTACK, 80],
		[247, 102001, 4, ATTACK, 15], [250, 24, 102001, ATTACK, 35],
		[277, 101901, 4, ATTACK, 9], [313, 102001, 4, ATTACK, 15],
		[316, 24, 102001, ABILITY, 395], [323, 101901, 4, ATTACK, 9],
		[354, 24, 102001, ATTACK, 70], [369, 101901, 4, ATTACK, 9],
		[374, 4, 102001, ABILITY, 300], [374, 4, 101901, ABILITY, 300],
		[408, 101901, 4, ATTACK, 9], [445, 101901, 4, ATTACK, 9],
		[455, 4, 101901, ATTACK, 40], [460, 24, 101901, ATTACK, 70],
		[518, 101901, 4, ABILITY, 110], [521, 4, 101901, ATTACK, 80],
		[526, 24, 101901, ATTACK, 35], [537, 101901, 4, ATTACK, 9],
		[582, 101901, 4, ATTACK, 9], [588, 4, 101901, ATTACK, 40],
		[593, 24, 101901, ATTACK, 70],
	]
	for step in range(1, 594):
		log.step = step
		var logan_was_alive := not logan.defeated
		var tank_was_alive := not tank.defeated
		fight._step_battle(fight.BATTLE_STEP_Q16, true)
		match step:
			1:
				expect(yuna.move_destination == Vector2i(3, 1) and tank.move_destination == Vector2i(3, 3)
						and not logan.moving, "Stone monster approaches a reachable target")
				# Native fixture lowers Logan's health after the first pathfinding pass.
				logan.health = 1
				logan.set_meta("health", 1)
			2:
				expect(yuna.move_destination == Vector2i(2, 1) and logan.move_destination == Vector2i(3, 1),
						"Logan can claim the cell Yuna has not entered")
		if logan_was_alive and logan.defeated:
			deaths.append(step)
			expect(logan.grid_cell == Vector2i(3, 1), "Logan falls in the original cell")
		if tank_was_alive and tank.defeated:
			deaths.append(step)
	expect(deaths == [57, 374] and fight._pending_battle_result.is_valid()
			and fight.battle_time_q16 == 1295112, "Original death and victory timing")
	expect(log.hits == native_hits, "Complete alternate-lineup hit order: %s" % [log.hits])


func verify_projectile_crit() -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(14)
	fight.start_fight()
	var turtle: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
	var hero := fight._hero
	hero.combat_stats.Crit = 0
	var base_crit := int(hero.stat("Crit"))
	hero.combat_stats.Crit = -base_crit
	var state: int = fight._combat_rng.state
	var hp := turtle.health
	var attack := hero.effective_attack_damage()
	fight._on_attack_action(turtle, hero)
	expect(fight._shots.size() == 1 and fight._combat_rng.state == state and turtle.health == hp,
			"A ranged attack does not consume a damage roll at launch")
	hero.combat_stats.Crit = 100 - base_crit
	fight._advance_projectiles(4 << 16)
	expect(fight._shots.is_empty() and fight._combat_rng.state != state and
			turtle.health == hp - turtle.damage_after_defense(attack * 2),
			"Projectile contact rolls against the attacker's current critical chance")
	stage.free()


func verify_first_fight() -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	var turtle: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
	fight.select_hero(26)
	var hero: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 0)]
	var tracker: Control = fight._ui.get_node("BattleTracker")
	tracker.refresh()
	var main: Control = tracker.get_node(tracker.PANEL)
	var first_row: Control = main.get_node("TrackerViewHolder/HeroTrackerView")
	expect(tracker.visible and first_row.get_node("DamageNumber/UnityText").text == "0",
			"Original statistics panel shows the selected hero before battle")
	expect(first_row.get_node(tracker.PORTRAIT).texture == stage.hero_portrait(26),
			"Translated portrait is bound to the actual hero")
	turtle.combat_stats.Defense = 15
	hero.combat_stats.HPPerSecond = 6
	fight.start_fight()
	var live := fight.battle_statistics
	var hero_id := hero.get_instance_id()
	var enemy_id := turtle.get_instance_id()
	expect(live.units.has(hero_id) and live.units.has(enemy_id), "Start registers both combatants")
	for tick in 7200:
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			break
		fight._physics_process(1.0 / Engine.physics_ticks_per_second)
		if tick == 180:
			for mode in 3:
				var button: Button = main.get_node("ButtonsHolder/" + tracker.MODES[mode] + "/SelectMode")
				button.pressed.emit()
				var value: int = live.total(live.units[hero_id], mode)
				expect(tracker.mode == mode and first_row.get_node("DamageNumber/UnityText").text == str(value),
						"Clicking the native mode tab shows the live ledger total")
	tracker.refresh()
	var result := fight.last_battle_statistics
	expect(fight.phase == GuildrunEncounter.Phase.RESULT and not result.is_empty(), "Combat publishes result snapshot")
	if not result.is_empty():
		expect(tracker.visible and first_row.get_node("DamageNumber/UnityText").text ==
				str(live.total(result.units[hero_id], tracker.mode)), "Result sidebar displays the final statistics")
		expect(result.victory and result.elapsed_q16 == fight.battle_time_q16, "Victory and actual elapsed time are recorded")
		expect(result.units[hero_id].attack > 0 and result.units[hero_id].ability > 0, "Natural attacks and abilities are credited")
		expect(result.units[hero_id].shielding >= 400 and result.units[hero_id].shield_damage > 0, "Cast shield and absorbed damage are both credited")
		expect(result.units[hero_id].healing > 0, "Health regeneration credits actual restoration")
		expect(result.units[enemy_id].mitigated > 0 and result.units[enemy_id].health_damage >= turtle.max_health,
				"Mitigation is measured separately from unshielded damage")
	stage.free()
