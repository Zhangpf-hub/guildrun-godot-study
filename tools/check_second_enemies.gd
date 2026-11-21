extends SceneTree


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	for stage_id: int in [10101, 10102]:
		var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
		stage.stage_id = stage_id
		root.add_child(stage)
		var fight := GuildrunEncounter.new()
		stage.add_child(fight)
		fight.setup(stage)
		var melee_cell := Vector2i(4, 4) if stage_id == 10101 else Vector2i(3, 4)
		var melee: GuildrunBoardUnit = stage.grid.occupants[melee_cell]
		var archer: GuildrunBoardUnit = stage.grid.occupants[Vector2i(0, 7) if stage_id == 10101 else Vector2i(6, 7)]
		var target: GuildrunBoardUnit = stage.deploy_hero(26, melee_cell + Vector2i(0, -1))
		var distant: GuildrunBoardUnit = stage.deploy_hero(4, Vector2i(0, 0))
		fight._register(target)
		fight._register(distant)
		# Isolate damage from random critical strikes.
		melee.base_stats = melee.base_stats.duplicate()
		melee.base_stats["<Crit>k__BackingField"] = 0
		melee.begin_active_ability()
		if stage_id == 10101:
			fight._tick_cast(melee, 25099)
			if target.health != target.max_health:
				push_error("Smash hit before its action timestamp")
				quit(1)
				return
			fight._tick_cast(melee, 1)
			if target.health != target.max_health - target.damage_after_defense(69) or target.stun_remaining_q16 != 131072 or distant.stun_remaining_q16 != 0:
				push_error("Smash adjacency, stun or damage mismatch")
				quit(1)
				return
		else:
			melee.burn_stacks = 18
			fight._tick_cast(melee, 32767)
			if melee.burn_stacks != 18 or target.health != target.max_health:
				push_error("Slime cleansed too early")
				quit(1)
				return
			fight._tick_cast(melee, 1)
			fight._tick_cast(melee, 1)
			if melee.burn_stacks != 13 or target.health != target.max_health - target.damage_after_defense(127):
				push_error("Slime attack did not scale from attack and max HP")
				quit(1)
				return
		archer.begin_active_ability()
		fight._tick_cast(archer, 77331)
		if not fight._shots.is_empty():
			push_error("Snipe fired early")
			quit(1)
			return
		fight._tick_cast(archer, 1)
		if fight._shots.size() != 1 or fight._shots[0].speed != 24 * 65536 or fight._shots[0].damage != (153 if stage_id == 10101 else 177):
			push_error("Snipe scaling, speed or release mismatch")
			quit(1)
			return
		var victim: GuildrunBoardUnit = fight._shots[0].target
		var raw_damage: int = fight._shots[0].damage
		var initial := victim.health
		fight._advance_projectiles(5 * 65536)
		if victim.health != initial - victim.damage_after_defense(raw_damage):
			push_error("Snipe projectile did not resolve on contact")
			quit(1)
			return
		print("stage=", stage_id, " melee=", melee.ability_kind, " snipe=", raw_damage)
		stage.free()
	quit(0)
