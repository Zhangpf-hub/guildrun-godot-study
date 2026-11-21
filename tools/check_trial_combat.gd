extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func verify() -> void:
	var maps: Array[int] = [50101, 50102, 50103, 50201, 50201, 50201, 50301, 50301, 50301, 50401, 50401, 50401]
	var seconds: Array[int] = [0, 0, 0, 30, 40, 50, 20, 20, 20, 0, 20, 0]
	for index in maps.size():
		var modifier := 5500 + index
		var stage: Node = (load("res://battle/stage.tscn") as PackedScene).instantiate()
		root.add_child(stage)
		var fight: GuildrunEncounter = stage.encounter
		if fight.first_shop == null:
			fight._create_party()
		var shop := fight.first_shop
		shop.roster.assign([4, 8, 20])
		shop.hero_ranks = {4: 1, 8: 1, 20: 1}
		shop.reserve_slots.assign([20, -1])
		fight._formation = {4: Vector2i(1, 1), 8: Vector2i(2, 1)}
		var original_size: int = stage.max_deployed
		var original_reserves := shop.reserve_slots.duplicate()
		var original_positions := fight._formation.duplicate()
		fight._enter_next_battle({"stage_id": maps[index], "modifier": modifier, "kind": "shards", "value": 20})
		expect(fight.phase == GuildrunEncounter.Phase.PLACE, "Missing deployment for %d" % modifier)
		var solo := modifier in [5500, 5501, 5502, 5509]
		if solo:
			expect(shop.deployed_ids().size() == 1, "Solo deployment for %d" % modifier)
			var cell: Vector2i = fight._hero.grid_cell
			expect(fight.transfer_hero(Vector2i(-1, 0), cell) and fight.board_hero(20) != null, "Reserve swap for %d" % modifier)
		var enemy: GuildrunBoardUnit
		for unit in fight._units:
			if not unit.is_hero:
				enemy = unit
				break
		var starting_hp := enemy.max_health
		fight.start_fight()
		expect(fight.phase == GuildrunEncounter.Phase.FIGHT, "Trial did not start for %d" % modifier)
		expect(fight._trial_time_limit_q16() == seconds[index] << 16, "Wrong time limit for %d" % modifier)
		match modifier:
			5503, 5504, 5505:
				var hp := enemy.health
				enemy.take_damage(hp * 2)
				expect(fight._land(enemy, hp * 2, fight._hero) == 0 and enemy.health == hp, "Survival damage immunity for %d" % modifier)
			5507, 5508:
				expect(enemy.max_health == starting_hp * (1 + modifier - 5506) and enemy.health == enemy.max_health, "Turtle max HP for %d" % modifier)
			5509, 5511:
				var reduction := -10 if modifier == 5509 else -50
				for unit in fight._units:
					if unit.is_hero:
						expect(unit.basic_stat_percent == reduction, "Hero reduction for %d" % modifier)
		if seconds[index] > 0:
			for unit in fight._units:
				unit.stun_remaining_q16 = 60 << 16
			while fight.phase == GuildrunEncounter.Phase.FIGHT and fight.battle_time_q16 <= seconds[index] << 16:
				fight._step_battle(GuildrunEncounter.BATTLE_STEP_Q16)
			expect(fight.phase == GuildrunEncounter.Phase.RESULT and fight.battle_time_q16 >= seconds[index] << 16, "Trial timer for %d" % modifier)
			expect(fight._trial_won == fight._trial_survival(), "Timed trial outcome for %d" % modifier)
		else:
			for unit in fight._units:
				if not unit.is_hero:
					unit.take_damage(unit.max_health * 2)
			fight._step_battle(GuildrunEncounter.BATTLE_STEP_Q16)
			expect(fight.phase == GuildrunEncounter.Phase.RESULT and fight._trial_won, "Elimination result for %d" % modifier)
		if solo:
			expect(stage.max_deployed == original_size and shop.reserve_slots == original_reserves and fight._formation == original_positions, "Formation restoration for %d" % modifier)
		stage.free()
	print("TRIAL_COMBAT 12 modifiers, one-on-one reserve swaps, survival immunity, timer outcomes, stat effects")
	quit(1 if failed else 0)
