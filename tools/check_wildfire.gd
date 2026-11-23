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
	var charge: Node3D = hero._funke_cast_effects[0]
	var release: Node3D = hero._funke_cast_effects[1]
	var hand := hero._funke_hand_mount
	if hand.get_skeleton().get_bone_name(hand.bone_idx) != &"hand_R" \
			or charge.get_parent() != hand or release.get_parent() != hand \
			or not charge.position.is_equal_approx(Vector3(0, -0.24, -0.33)) \
			or not is_equal_approx(charge._activation_time, 0.467) or not is_equal_approx(release._activation_time, 1.62):
		push_error("Incorrect Fireball cast attachment or event timing")
		quit(1)
		return
	hero.set_death_appearance_speed(0.0)
	charge._process(1.0)
	if not is_zero_approx(charge._elapsed):
		push_error("Fireball cast effect advanced while paused")
		quit(1)
		return
	hero.set_death_appearance_speed(2.0)
	charge._process(0.25)
	if not is_equal_approx(charge._elapsed, 0.5):
		push_error("Fireball cast effect missed the battle speed setting")
		quit(1)
		return
	hero.set_death_appearance_speed(1.0)
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
		if shot.damage != 225 or shot.target.burn_stacks != 18 \
				or shot.effect.get_meta("unity_prefab") != 7148 or shot.effect.position != shot.position:
			push_error("Incorrect damage, stacks, or fireball position")
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
	for shot: Dictionary in fight._shots:
		shot.effect.free()
	fight._shots.clear()
	hero.position = Vector3.ZERO
	turtle.position = Vector3(6, 0, 0)
	var before_flight := turtle.health
	fight._queue_shot(hero, turtle, 10, 65536)
	var flight: Node3D = fight._shots[0].effect
	fight._advance_projectiles(65536)
	if fight._shots.size() != 1 or not (fight._shots[0].position as Vector3).is_equal_approx(Vector3(3, 0, 0)):
		push_error("Projectile speed scaling mismatch")
		quit(1)
		return
	turtle.position = Vector3(3, 0, -6)
	fight._advance_projectiles(65536)
	if fight._shots.size() != 1 or not (fight._shots[0].position as Vector3).is_equal_approx(Vector3(3, 0, -3)) \
			or not flight.position.is_equal_approx(Vector3(3, 0, -3)) or not flight.basis.z.is_equal_approx(Vector3.BACK):
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
	var impact := fight._projectile_effects.get_node("VFX_Funke_SkillHit") as Node3D
	if not flight.is_queued_for_deletion() or impact.get_meta("unity_prefab") != 63109 \
			or not impact.position.is_equal_approx(flight.position + Vector3.UP):
		push_error("Fireball impact failed to replace flight at contact")
		quit(1)
		return
	hero.cast_effect_fired = false
	fight._finish_cast(hero)
	if not charge.is_queued_for_deletion() or not release.is_queued_for_deletion():
		push_error("Canceled Fireball still has scheduled cast effects")
		quit(1)
		return
	print("Verified right-hand cast events, pause and speed, two fireballs, burn ticks, retargeting, and impact cleanup.")
	stage.free()
	quit()
