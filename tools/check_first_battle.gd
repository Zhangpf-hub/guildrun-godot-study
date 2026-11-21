extends SceneTree

func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	for id: int in [4, 26, 14]:
		var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
		root.add_child(stage)
		var fight: GuildrunEncounter = stage.encounter
		var turtle: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
		fight.select_hero(id)
		var hero := fight._hero
		if not is_instance_valid(hero) or hero.grid_cell != Vector2i(3, 0):
			push_error("First selection must automatically use the first free cell (3,0)")
			quit(1)
			return
		fight.start_fight()
		var health_before := turtle.health
		var starting_mana := hero.mana
		var interval: int = stage.mana_regen_interval_q16
		hero.tick_mana(interval - 1, interval)
		if hero.mana != starting_mana or hero.mana_regen_remaining_q16 != 1:
			push_error("Early mana regen")
			quit(1)
			return
		hero.tick_mana(1, interval)
		if hero.mana != starting_mana + 4 or hero.mana_regen_remaining_q16 != interval:
			push_error("Mana regen boundary mismatch")
			quit(1)
			return
		hero.mana = starting_mana
		var first_mana_tick := 0
		var fire_tick := 0
		var shield_tick := 0
		var shuriken_tick := 0
		var first_hit := 0
		var tick := 0
		while fight.phase == GuildrunEncounter.Phase.FIGHT and tick < 7200:
			fight._physics_process(1.0 / Engine.physics_ticks_per_second)
			tick += 1
			if id == 4 and shuriken_tick == 0 and hero.shadow_step == 2 and hero.mana == 0:
				shuriken_tick = tick
			if first_mana_tick == 0 and hero.mana != starting_mana:
				if hero.mana != starting_mana + 5 or tick >= Engine.physics_ticks_per_second * 2:
					push_error("Expected attack mana before natural regen")
					quit(1)
					return
				first_mana_tick = tick
			if turtle.health < health_before and first_hit == 0:
				first_hit = tick
			if fire_tick == 0 and turtle.burn_stacks > 0:
				if id != 14 or hero.mana != 0 or turtle.burn_stacks != 18:
					push_error("Wildfire mana or burn mismatch")
					quit(1)
					return
				fire_tick = tick
			if shield_tick == 0 and hero.total_shield() > 0:
				if id != 26 or hero.total_shield() != 400:
					push_error("Unexpected shield at start of cast")
					quit(1)
					return
				shield_tick = tick
		if first_hit == 0 or fight.phase != GuildrunEncounter.Phase.RESULT or turtle.health != 0 or hero.defeated:
			push_error("Encounter did not resolve for hero %d" % id)
			quit(1)
			return
		if first_mana_tick == 0 or first_mana_tick > first_hit or turtle.mana != 0:
			push_error("Attack mana or cap mismatch")
			quit(1)
			return
		if (id == 14 and fire_tick == 0) or (id == 26 and shield_tick == 0) or (id == 4 and shuriken_tick == 0):
			push_error("Missing cast or incorrect mana cap")
			quit(1)
			return
		print("hero=%d hp=%d turtle=%d/%d first_hit_tick=%d first_mana_tick=%d fire_tick=%d mana=%d result_tick=%d" %
				[id, hero.health, turtle.health, health_before, first_hit, first_mana_tick, fire_tick, hero.mana, tick])
		stage.free()
	quit()
