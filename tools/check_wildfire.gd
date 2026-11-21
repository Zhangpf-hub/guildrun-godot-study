extends SceneTree
func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var stage = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(14)
	var hero: GuildrunBoardUnit = fight._hero
	var turtle: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
	var extra = stage.spawn_unit(turtle.base_stats, Vector2i(3, 3), 0, false)
	var distant = stage.spawn_unit(turtle.base_stats, Vector2i(0, 7), 0, false)
	fight._register(extra)
	fight._register(distant)
	hero.mana = hero.stat("MaxMana")
	hero.begin_active_ability()
	fight._tick_cast(hero, 106167)
	if not fight._shots.is_empty() or hero.mana != 85:
		push_error("Early release")
		quit(1)
		return
	fight._tick_cast(hero, 1)
	if fight._shots.size() != 2 or hero.mana != 0 or distant.burn_stacks != 0:
		push_error("Incorrect release or range")
		quit(1)
		return
	for shot: Dictionary in fight._shots:
		if shot.damage != 225 or shot.target.burn_stacks != 18:
			push_error("Incorrect damage or stacks")
			quit(1)
			return
	var initial_hp := turtle.health
	fight._tick_burn(turtle, 65535)
	if turtle.health != initial_hp:
		push_error("Early burn")
		quit(1)
		return
	fight._tick_burn(turtle, 1)
	fight._tick_burn(turtle, 65536)
	if turtle.burn_stacks != 16 or turtle.health != initial_hp - 35:
		push_error("Incorrect burn ticks")
		quit(1)
		return
	fight._shots.clear()
	hero.position = Vector3.ZERO
	turtle.position = Vector3(6, 0, 0)
	var before_flight := turtle.health
	fight._queue_shot(hero, turtle, 10, 65536)
	fight._advance_projectiles(65536)
	if fight._shots.size() != 1 or not (fight._shots[0].position as Vector3).is_equal_approx(Vector3(3, 0, 0)):
		push_error("Projectile speed scaling mismatch")
		quit(1)
		return
	turtle.position = Vector3(3, 0, -6)
	fight._advance_projectiles(65536)
	if fight._shots.size() != 1 or not (fight._shots[0].position as Vector3).is_equal_approx(Vector3(3, 0, -3)):
		push_error("Projectile failed to track moving target")
		quit(1)
		return
	fight._advance_projectiles(32768)
	if turtle.health != before_flight:
		push_error("Projectile hit outside collider")
		quit(1)
		return
	fight._advance_projectiles(21845)
	if not fight._shots.is_empty() or turtle.health != before_flight - turtle.damage_after_defense(10):
		push_error("Projectile missed collider entry")
		quit(1)
		return
	print("Verified two fireballs, 18 burn stacks, retargeted flight direction and contact before the target center.")
	stage.free()
	quit()
