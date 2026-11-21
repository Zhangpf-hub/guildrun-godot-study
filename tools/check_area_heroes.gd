extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


@warning_ignore("integer_division")
func exercise(id: int, stalled: bool) -> void:
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	var enemy: GuildrunBoardUnit = fight._units[0]
	var source: GuildrunBoardUnit = stage.deploy_hero(id, enemy.grid_cell - Vector2i(0, 1))
	var ally: GuildrunBoardUnit = stage.deploy_hero(4, enemy.grid_cell + Vector2i(0, 1))
	var outside: GuildrunBoardUnit = stage.deploy_hero(4, Vector2i(0, 0))
	fight._register(source)
	fight._register(ally)
	fight._register(outside)
	fight._hero = source
	fight.phase = GuildrunEncounter.Phase.PLACE
	outside.position = Vector3(80, 0, -80)
	for unit in [enemy, ally, outside]:
		unit.stun_remaining_q16 = 90 << 16
	source.combat_stats.Crit = -10000
	source.mana = int(source.stat("MaxMana"))
	ally.health -= 80
	enemy.health = 10000
	enemy.max_health = enemy.health
	fight.start_fight()
	if stalled:
		fight.battle_time_q16 = 15 << 16
	var tick := GuildrunEncounter.BATTLE_STEP_Q16
	for frame in 95:
		fight._step_battle(tick)
		if not fight._strike_areas.is_empty():
			break
	expect(not fight._strike_areas.is_empty(), "No normal active area for hero %d" % id)
	if fight._strike_areas.is_empty():
		stage.free()
		return
	var area: Dictionary = fight._strike_areas[0]
	var source_hp_per_second := int(source.stat("HPPerSecond"))
	var ally_before := ally.health
	var enemy_before := enemy.health
	source.stun_remaining_q16 = 99 << 16
	expect(int(area.until_hit) == 65536, "Area must tick every authored second")
	expect(ally.total_shield() == 0 and enemy.poison_stacks == 0 and enemy.frost_stacks == 0,
			"Area effects must wait for their pulse")
	var center: Vector3 = area.transform.affine_inverse().origin
	if id == 22:
		expect(center.is_equal_approx(source.position), "Pimenta must cast at their own position")
	else:
		expect(center.distance_to(outside.position) > 20 and center.distance_to(enemy.position) <= 6.1
				and center.distance_to(ally.position) <= 6.1, "Weighted target cluster missed")
	for frame in 29:
		fight._step_battle(tick)
	expect(ally.total_shield() == 0 and enemy.poison_stacks == 0 and enemy.frost_stacks == 0,
			"Area pulse released early")
	for frame in ceili(65536.0 / tick) - 29:
		fight._step_battle(tick)
	var spell_power := int(source.stat("Magic"))
	var mana_regen := int(source.stat("ManaRegen"))
	match id:
		8:
			expect(enemy.poison_stacks == 1 + mana_regen / 5 and ally.total_shield() == 10 + spell_power,
					"Flower field poison or shield formula differs")
			expect(ally.health == ally_before + (10 + spell_power / 2 if stalled else 0), "Flower field Stall heal differs")
		16:
			expect(enemy.frost_stacks == 2 + mana_regen / 8 and ally.total_shield() == 10 + spell_power * 3 / 4,
					"Blizzard frost or shield formula differs")
			expect(enemy.health == enemy_before - enemy.damage_after_defense(15 + spell_power / 2), "Blizzard damage differs")
		22:
			var defense := int(source.stat("Defense"))
			expect(enemy.poison_stacks == 2 + defense / 20 and ally.total_shield() == 0,
					"Poison cloud poison or target side differs")
			expect(enemy.health == enemy_before - enemy.damage_after_defense(5 + spell_power * 3 / 4 + defense / 2),
					"Poison cloud damage differs")
			expect(int(source.stat("HPPerSecond")) == source_hp_per_second + (4 if stalled else 0), "Poison cloud Stall regen differs")
	expect(outside.total_shield() == 0 and outside.poison_stacks == 0 and outside.frost_stacks == 0,
			"Area touched an outside target")
	stage.free()


func verify() -> void:
	for id: int in [8, 16, 22]:
		exercise(id, false)
	exercise(8, true)
	exercise(22, true)
	print("AREA_HEROES normal active pulse, weighted cluster, poison, frost, shields, Stall heal and regen")
	quit(1 if failed else 0)
