extends SceneTree

var _stage: Node3D


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var args := OS.get_cmdline_user_args()
	var capture_path := "" if args.is_empty() else args[0]
	root.size = Vector2i(819, 616)
	_stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	_stage.run_seed = 262144
	root.add_child(_stage)
	var fight: GuildrunEncounter = _stage.encounter
	fight.set_physics_process(false)
	fight.simulation_speed._settings_path = ""
	fight.simulation_speed.select_manual(0)
	fight.select_hero(4)
	var cell := Vector2i(3, 1)
	var logan: GuildrunBoardUnit = _stage.deploy_hero(13, cell)
	var healer: GuildrunBoardUnit = _stage.deploy_hero(27, Vector2i(4, 1))
	fight._register(logan)
	fight._register(healer)
	fight.start_fight()
	_stage.battle_camera.advance(4.0)
	var attacker: GuildrunBoardUnit = _stage.grid.occupants.get(Vector2i(3, 4))
	var position_before := logan.global_position
	var outlines := get_outlines(logan)
	if not require(_stage._has_ragdoll_floor and outlines.size() == 2 and attacker != null,
			"10101 loads Logan, his outlined meshes, the attacker and the authored floor"):
		return
	for frame in 6:
		await physics_frame
	await snapshot(capture_path, "standing")

	var original_clip: StringName = logan._motion_players[0].current_animation
	fight._land(logan, 100000, attacker)
	if not require(logan.defeated and not _stage.grid.occupants.has(cell)
			and logan._ragdoll == null and logan._motion_players[0].current_animation == original_clip,
			"Fatal damage releases the cell while preserving the current pose until the physics delay"):
		return
	for frame in 4:
		await physics_frame
		if not require(logan._ragdoll == null, "The ragdoll must wait for the source's 80 ms physics delay"):
			return
	for frame in 2:
		await physics_frame
	var ragdoll := logan._ragdoll
	if not require(is_instance_valid(ragdoll) and ragdoll.get_child_count() == 17
			and ragdoll.is_simulating_physics(), "The physics delay activates the imported ragdoll"):
		return
	var head := ragdoll.get_node(^"head") as PhysicalBone3D
	var starting_height := head.global_position.y
	for frame in 12:
		await physics_frame
	var height_before_pause := head.global_position.y
	logan.set_death_appearance_speed(0.0)
	for frame in 12:
		await physics_frame
	if not require(absf(head.global_position.y - height_before_pause) < 0.04,
			"Pausing combat freezes the physical fall"):
		return
	logan.set_death_appearance_speed(1.0)
	for frame in 36:
		await physics_frame
	await snapshot(capture_path, "falling")
	for frame in 84:
		await physics_frame
	var resting_height := head.global_position.y
	if not require(resting_height < starting_height - 0.8 and resting_height > -0.25
			and logan.global_position.is_equal_approx(position_before) and get_outlines(logan) == outlines,
			"The corpse contacts the floor while the board position and original outline passes are preserved"):
		return
	print("LOGAN head %.3f -> %.3f, outlines %d" % [starting_height, resting_height, outlines.size()])
	await snapshot(capture_path, "down")

	fight.battle_time_q16 = 21 << 16
	fight._release_blessing(healer)
	if not require(not logan.defeated and _stage.grid.occupants.get(cell) == logan and logan._ragdoll == null
			and logan._death_blend_tween == null and ragdoll.is_queued_for_deletion() and get_outlines(logan) == outlines,
			"Combat resurrection restores visuals and clears the physics proxy"):
		return
	for frame in 10:
		await physics_frame
	if not require(not is_instance_valid(ragdoll), "Revive removes the physical bones"):
		return
	await snapshot(capture_path, "restored")

	logan.shields.clear()
	fight._land(logan, 100000, attacker)
	logan.set_death_appearance_speed(0.0)
	for frame in 8:
		await physics_frame
	if not require(logan._ragdoll == null and logan._ragdoll_start_delay != null,
			"Pausing combat also freezes the pending handoff"):
		return
	fight._release_blessing(healer)
	logan.set_death_appearance_speed(1.0)
	for frame in 6:
		await physics_frame
	if not require(not logan.defeated and logan._ragdoll == null and _stage.grid.occupants.get(cell) == logan,
			"Reviving during the physics delay cancels the pending ragdoll"):
		return
	logan.shields.clear()
	fight._land(logan, 100000, attacker)
	for frame in 6:
		await physics_frame
	if not require(logan.defeated and logan._ragdoll != null and logan._ragdoll.get_child_count() == 17,
			"The same character can fall again after being revived"):
		return
	if not await verify_catalog():
		return
	print("RAGDOLL physical fall, collision, pause, revive and repeated death OK")
	_stage.free()
	quit()


func verify_catalog() -> bool:
	var verified := 0
	var bones := 0
	var cell := Vector2i(0, 0)
	for id: int in _stage._heroes:
		var stats: Dictionary = _stage._heroes[id]
		var visual := str(int(_stage.field(stats, "VisualConfig").m_PathID))
		if not _stage._ragdolls.rigs.has(visual):
			continue
		var profile: Dictionary = _stage._ragdolls.rigs[visual]
		var expected: int = profile.bodies.size()
		var hero: GuildrunBoardUnit = _stage.deploy_hero(id, cell)
		hero.take_damage(hero.health)
		for frame in 6:
			await physics_frame
		if not require(hero._ragdoll != null and hero._ragdoll.get_child_count() == expected,
				"Visual %s must bind all %d source bones" % [visual, expected]):
			return false
		bones += expected
		verified += 1
		_stage.grid.occupants.erase(cell)
		hero.free()
	print("RAGDOLL catalog ", verified, " visual rigs and ", bones, " physical bones")
	return require(verified == 25 and bones == 464, "Every source ragdoll configuration was exercised")


func require(condition: bool, label: String) -> bool:
	if not condition:
		push_error(label)
		_stage.free()
		quit(1)
	return condition


func get_outlines(unit: GuildrunBoardUnit) -> Array[Material]:
	var result: Array[Material] = []
	for mesh: MeshInstance3D in unit.find_children("*", "MeshInstance3D", true, false):
		if mesh.is_visible_in_tree() and mesh.material_overlay != null:
			result.append(mesh.material_overlay)
	return result


func snapshot(prefix: String, label: String) -> void:
	if prefix.is_empty():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s-%s.png" % [prefix, label])
