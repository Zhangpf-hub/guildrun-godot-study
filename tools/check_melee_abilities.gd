extends SceneTree

func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var scene: PackedScene = load("res://battle/stage.tscn")
	var stage = scene.instantiate()
	root.add_child(stage)
	if not check_kai(stage):
		push_error("Kai shield, timing, or damage mismatch")
		quit(1)
		return
	stage.free()
	stage = scene.instantiate()
	root.add_child(stage)
	if not check_yuuna(stage):
		push_error("Yuuna cast, retargeting, or landing mismatch")
		quit(1)
		return
	stage.free()
	print("Verified Kai shield absorption, expiry and area damage. Verified Yuuna volley, retargeting and board occupancy.")
	quit()


func check_kai(stage: Node3D) -> bool:
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(26)
	var kai := fight._hero
	var turtle: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
	kai.base_stats = kai.base_stats.duplicate(true)
	kai.base_stats["<Crit>k__BackingField"] = 0
	fight._claim_cell(kai, Vector2i(3, 3))
	kai.position = GuildrunBattleGrid.center(kai.grid_cell)
	var distant: GuildrunBoardUnit = stage.spawn_unit(turtle.base_stats, Vector2i(0, 7), 0, false)
	fight._register(distant)
	var initial_hp := turtle.health
	var distant_hp := distant.health
	kai.mana = int(kai.stat("MaxMana"))
	kai.begin_active_ability()
	if kai.total_shield() != 400:
		return false
	var kai_hp := kai.health
	kai.take_damage(75)
	fight._tick_cast(kai, 171485)
	if kai.health != kai_hp or kai.total_shield() != 325 or not fight._strike_areas.is_empty():
		return false
	fight._tick_cast(kai, 1)
	fight._advance_strike_areas(32112)
	if turtle.health != initial_hp or kai.mana != 0:
		return false
	fight._advance_strike_areas(1)
	var damage := turtle.damage_after_defense(137) + turtle.damage_after_defense(325)
	fight._advance_strike_areas(65536)
	if turtle.health != initial_hp - damage or distant.health != distant_hp or not fight._strike_areas.is_empty():
		return false
	kai.shields.append({"amount": 20, "remaining": 2})
	kai.take_damage(15)
	kai.tick_shields(2)
	if kai.total_shield() != 325:
		return false
	kai.tick_shields(10 * 65536 - 3)
	if kai.total_shield() != 325:
		return false
	kai.tick_shields(1)
	kai.take_damage(2)
	return kai.total_shield() == 0 and kai.health == kai_hp - 2


func check_yuuna(stage: Node3D) -> bool:
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	var yuuna := fight._hero
	var turtle: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
	var weak: GuildrunBoardUnit = stage.spawn_unit(turtle.base_stats, Vector2i(0, 7), 0, false)
	fight._register(weak)
	# The first two rolls for this seed are both above Yuuna's 50% crit chance.
	fight._combat_rng.reseed(1940)
	weak.health = 1
	var initial_hp := turtle.health
	var start := yuuna.grid_cell
	yuuna.mana = int(yuuna.stat("MaxMana"))
	yuuna.begin_active_ability()
	fight._tick_cast(yuuna, 80609)
	fight._tick_cast(yuuna, 80608)
	if weak.defeated or turtle.health != initial_hp:
		return false
	fight._tick_cast(yuuna, 1)
	if not weak.defeated or initial_hp - turtle.health != turtle.damage_after_defense(150) or yuuna.mana != 0:
		return false
	fight._tick_cast(yuuna, 1092)
	fight._tick_cast(yuuna, 26214)
	if yuuna.grid_cell != start or yuuna.visual_offset.is_zero_approx() or yuuna.shadow_step != 4:
		return false
	var landing := yuuna.shadow_landing
	fight._tick_cast(yuuna, 28180)
	return (not yuuna.is_casting() and yuuna.visual_offset.is_zero_approx() and landing != start
			and stage.grid.occupants.get(landing) == yuuna and not stage.grid.occupants.has(start)
			and yuuna.position.is_equal_approx(GuildrunBattleGrid.center(landing)))
