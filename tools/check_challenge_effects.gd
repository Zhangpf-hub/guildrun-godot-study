extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, detail: String) -> void:
	if not ok:
		failed = true
		push_error(detail)


func fixture(id: int) -> GuildrunEncounter:
	var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.stage_id = id
	root.add_child(stage)
	var fight := GuildrunEncounter.new()
	stage.add_child(fight)
	fight.setup(stage)
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(3, 2)]:
		fight._register(stage.deploy_hero(26, cell))
	fight.phase = GuildrunEncounter.Phase.PLACE
	return fight


func verify() -> void:
	for modifier: int in range(5000, 5005) + range(5011, 5016):
		var fight := fixture(10301)
		var enemy := fight._units[0]
		var hero := fight._units.back() as GuildrunBoardUnit
		var enemy_hp := enemy.max_health
		var hero_hp := hero.max_health
		fight.challenge_modifier = modifier
		fight.start_fight()
		for unit in fight._units:
			unit.stun_remaining_q16 = 100 << 16
		match modifier:
			5000, 5011:
				var bonus := 150 if modifier == 5000 else 66
				var duration := 8 if modifier == 5000 else 10
				check(enemy.max_health == int(enemy_hp * (100 + bonus) / 100.0), "Rush opening bonus")
				fight._step_battle((duration << 16) - 1)
				check(enemy.basic_stat_percent == bonus, "Rush ended early")
				fight._step_battle(1)
				check(enemy.max_health == enemy_hp, "Rush did not expire")
			5001, 5012:
				fight._step_battle((15 << 16) - 1)
				check(enemy.max_health == enemy_hp, "Stall triggered early")
				fight._step_battle(1)
				check(enemy.max_health == int(enemy_hp * (140 if modifier == 5001 else 155) / 100.0), "Stall percentage")
			5002, 5013:
				fight._step_battle(65535)
				check(hero.health == hero_hp, "Pain ticked early")
				fight._step_battle(1)
				var factor := 1638 if modifier == 5002 else 4588
				check(hero.health == hero_hp - hero.damage_after_defense((hero_hp * factor) >> 16), "Pain damage")
			5003, 5014:
				enemy.take_damage(200)
				fight._step_battle(65535)
				check(enemy.health == enemy_hp - 200, "Regeneration ticked early")
				fight._step_battle(1)
				check(enemy.health == mini(enemy_hp, enemy_hp - 200 + ((enemy_hp * (1966 if modifier == 5003 else 3277)) >> 16)), "Enemy regeneration")
			5004, 5015:
				check(hero.max_health == int(hero_hp * (80 if modifier == 5004 else 85) / 100.0) and enemy.max_health == enemy_hp, "Decay affected wrong team")
		fight._stage.free()
	for id in [10301, 10302, 10305, 10306]:
		var fight := fixture(id)
		var far := fight._units[-2]
		var near := fight._units[-1]
		for unit in fight._units:
			if unit.is_hero:
				continue
			match unit.ability_kind:
				"AreaOfEffectAction", "SnakeAction":
					unit.begin_active_ability(near)
					fight._tick_cast(unit, 32767)
					check(fight._strike_areas.is_empty(), "Enemy area cast released early")
					fight._tick_cast(unit, 1)
					check(fight._strike_areas.size() == 1, "Enemy area missing")
					var target := near if unit.ability_kind == "AreaOfEffectAction" else far
					if unit.ability_kind == "SnakeAction":
						target.position = unit.position
					var hp := target.health
					fight._advance_strike_areas(65535)
					check(target.health == hp, "Enemy area ticked early")
					fight._advance_strike_areas(1)
					check(target.health < hp, "Enemy area not at its configured center")
					match id:
						10301: check(target.burn_stacks > 0, "Missing burn")
						10302: check(target.frost_stacks > 0, "Missing frost")
						10305: check(target.poison_stacks > 0, "Missing snake poison")
					fight._strike_areas.clear()
					break
				"hook_strike":
					var victim := fight._farthest_enemy(unit)
					var old_position := victim.position
					unit.begin_active_ability(near)
					fight._tick_cast(unit, 655)
					check(fight._drags.size() == 1 and victim.position == old_position and victim.stun_remaining_q16 > 0, "Hook did not begin a timed drag")
					fight._advance_drags(victim.stun_remaining_q16)
					check(victim.position != old_position and victim.position == GuildrunBattleGrid.center(victim.grid_cell), "Hook did not reach reserved cell")
				"SpiderEnsnareAction":
					var victim := fight._farthest_enemy(unit)
					unit.begin_active_ability(near)
					fight._tick_cast(unit, 32768)
					check(victim.stun_remaining_q16 >= 131072 and victim.poison_stacks > 0, "Web did not stun and poison farthest target")
		fight._stage.free()
	quit(1 if failed else 0)
