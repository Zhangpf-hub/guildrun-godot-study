extends SceneTree


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(26)
	fight.start_fight()
	var hero := fight._hero
	var enemy: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
	var hero_hp := hero.health
	var enemy_hp := enemy.health
	var hero_damage := hero.damage_after_defense(5)
	var enemy_damage := enemy.damage_after_defense(5)
	hero.gain_shield(20, 10 << 16)
	fight._tick_riftstorm((50 << 16) - 1)
	var pending := fight._storm_damage == 0
	fight._tick_riftstorm(1)
	var started := fight._storm_damage == 5 and enemy.health == enemy_hp
	fight._tick_riftstorm(65535)
	var no_early_hit := hero.total_shield() == 20 and enemy.health == enemy_hp
	fight._tick_riftstorm(1)
	var first_hit := hero.health == hero_hp and hero.total_shield() == 20 - hero_damage \
			and enemy.health == enemy_hp - enemy_damage and fight._storm_damage == 10

	# Cross the exponential threshold without killing the targets before the checkpoint.
	hero.health = 100000
	enemy.health = 100000
	for tick in range(2, 15):
		fight._tick_riftstorm(65536)
	var last_linear_damage := fight._storm_damage == 75
	fight._tick_riftstorm(65536)
	var rounded_multiplier := fight._storm_damage == 112

	# Put both sides one hit from death and let the regular fixed-step path resolve the round.
	hero.health = 1
	hero.shields.clear()
	hero.stun_remaining_q16 = 2 << 16
	enemy.health = 1
	enemy.stun_remaining_q16 = 2 << 16
	fight._storm_damage_timer_q16 = GuildrunEncounter.BATTLE_STEP_Q16
	fight._advance_battle_tick(0.0)
	fight._physics_process(1.0)
	var simultaneous_loss := hero.defeated and enemy.defeated and fight.phase == GuildrunEncounter.Phase.RESULT
	var success := pending and started and no_early_hit and first_hit and last_linear_damage \
			and rounded_multiplier and simultaneous_loss
	if success:
		print("Riftstorm: 50s start, first hit after one interval, defense and shields, 75 -> 112 escalation, double KO")
	else:
		push_error("Riftstorm checks failed: %s" % [[pending, started, no_early_hit, first_hit,
				last_linear_damage, rounded_multiplier, simultaneous_loss]])
	stage.free()
	quit(0 if success else 1)
