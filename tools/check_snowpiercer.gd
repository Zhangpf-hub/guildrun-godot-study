extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func test_target_order(source: GuildrunBoardUnit) -> void:
	var helper: GDScript = load("res://battle/javryn_action.gd")
	var nearer := GuildrunBoardUnit.new()
	var farther := GuildrunBoardUnit.new()
	var outside := GuildrunBoardUnit.new()
	nearer.grid_cell = source.grid_cell + Vector2i(1, 0)
	farther.grid_cell = source.grid_cell + Vector2i(2, 0)
	outside.grid_cell = source.grid_cell + Vector2i(int(source.stat("AttackRange")) + 1, 0)
	source.combat_stats.AttackSpeed = 450
	var units: Array[GuildrunBoardUnit] = [source, farther, outside, nearer]
	var targets: Array[GuildrunBoardUnit] = helper.allocate(source, units)
	expect(targets.size() == 14, "Snowpiercer shot count must cap at 14")
	for index in targets.size():
		expect(targets[index] == (nearer if index % 2 == 0 else farther),
				"Snowpiercer must rotate through distance-ordered enemies inside range")
	nearer.free()
	farther.free()
	outside.free()


func verify() -> void:
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	var enemy: GuildrunBoardUnit = fight._units[0]
	var source: GuildrunBoardUnit = stage.deploy_hero(20, enemy.grid_cell - Vector2i(0, 1))
	fight._register(source)
	fight._hero = source
	fight.phase = GuildrunEncounter.Phase.PLACE
	expect(source.ability_kind == "JavrynAction", "Karsu must resolve Snowpiercer via standard deployment")
	if source.ability_kind != "JavrynAction":
		quit(1)
		return
	test_target_order(source)
	source.combat_stats.Crit = -10000
	source.mana = int(source.stat("MaxMana"))
	enemy.health = 10000
	enemy.max_health = enemy.health
	var original_health := enemy.health
	enemy.stun_remaining_q16 = 99 << 16
	fight.start_fight()
	var tick := GuildrunEncounter.BATTLE_STEP_Q16
	fight._step_battle(tick)
	expect(source.is_casting() and source.javryn_targets.size() == 14, "Normal mana-driven cast did not allocate shots")
	source.stun_remaining_q16 = 98 << 16
	var release_delay := source.cast_release_q16
	expect(release_delay == 87163, "Snowpiercer windup differs from the authored first hit")
	var frames_to_first := ceili(float(release_delay) / tick)
	for frame in frames_to_first - 1:
		fight._step_battle(tick)
	expect(source.cast_hit_index == 0 and enemy.frost_stacks == 0, "Snowpiercer hit before its first delay")
	fight._step_battle(tick)
	expect(source.cast_hit_index == 1 and source.stun_remaining_q16 == 0, "First shot or native cast stun immunity failed")
	var previous_release := fight.battle_time_q16
	for frame in 12:
		if enemy.frost_stacks > 0:
			break
		fight._step_battle(tick)
	var damage := 25 + int(source.stat("Attack")) + int(source.stat("Magic"))
	expect(enemy.health == original_health - enemy.damage_after_defense(damage) and enemy.frost_stacks == 5,
			"First arrow must apply scaled damage and 3 + 2 × rank frost on contact")
	for frame in 240:
		if not source.is_casting():
			break
		var previous_index := source.cast_hit_index
		fight._step_battle(tick)
		if source.cast_hit_index != previous_index:
			expect(fight.battle_time_q16 - previous_release == ceili(13107.0 / tick) * tick,
					"Follow-up arrows must reset to the authored delay, including extra arrows")
			previous_release = fight.battle_time_q16
	expect(source.cast_hit_index == 14 and not source.is_casting(), "Extra arrows must repeat the final attack table row")
	stage.free()
	print("SNOWPIERCER normal deployment, range allocation, cast delay, projectile hit, frost, and 14-shot cap")
	quit(1 if failed else 0)
