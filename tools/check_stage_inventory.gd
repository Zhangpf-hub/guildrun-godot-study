extends SceneTree


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	# The original BuildSettings inventory sits beside game/ in the learning project.
	var inventory_path: String = get_script().resource_path.get_base_dir().path_join("../scene_inventory.json")
	var inventory: Array = JSON.parse_string(FileAccess.get_file_as_string(inventory_path))
	var mapped_objects := 0
	for record: Dictionary in inventory:
		var scene: PackedScene = load("res://" + str(record.scene))
		var instance := scene.instantiate()
		var object_count := 0
		for node in instance.find_children("*", "", true, false):
			if node.has_meta("unity_id"):
				object_count += 1
		instance.free()
		if object_count != int(record.components.get("GameObject", 0)):
			push_error("Object count differs in %s" % record.scene)
			quit(1)
			return
		mapped_objects += object_count
	var stage = load("res://battle/stage.tscn").instantiate()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(stage)
	var enabled_heroes := 0
	var active_heroes := 0
	for hero_id: int in stage._heroes:
		var hero: Dictionary = stage._heroes[hero_id]
		if stage.field(hero, "DisabledInGame"):
			continue
		enabled_heroes += 1
		var skill_id := int(hero._activeAbilityID)
		if skill_id < 0:
			continue
		active_heroes += 1
		if not stage._abilities.has(skill_id):
			push_error("Missing authored ability %d on hero %d" % [skill_id, hero_id])
			quit(1)
			return
	var placements := 0
	var enemy_ids := {}
	for id: int in stage._stages:
		if not stage.load_board(id) or root.get_camera_3d() == null:
			push_error("Missing board or camera for stage %d" % id)
			quit(1)
			return
		var entries: Array = stage.field(stage.stage, "EnemyPlacements")
		if stage.grid.occupants.size() != entries.size():
			push_error("Wrong number of enemies on stage %d" % id)
			quit(1)
			return
		for entry: Dictionary in entries:
			var location: Dictionary = stage.field(entry, "Position")
			var unit: GuildrunBoardUnit = stage.grid.occupants.get(Vector2i(location.x, location.y))
			var enemy_id := int(entry._enemyId._sequentialId)
			if not unit or int(unit.stat("Id")._sequentialId) != enemy_id or unit.direction != int(stage.field(entry, "Direction")):
				push_error("Wrong enemy or facing on stage %d at %s" % [id, location])
				quit(1)
				return
			if not unit.transform.basis.z.is_equal_approx(Vector3.FORWARD):
				push_error("Enemy preparation rotation differs on stage %d" % id)
				quit(1)
				return
			enemy_ids[enemy_id] = true
		placements += entries.size()
		# Real board transitions span frames. Let the engine release the previous board's render resources.
		await process_frame
	print("Steam build 26551710: scenes=", inventory.size(), " objects=", mapped_objects,
			" stages=", stage._stages.size(), " placements=", placements, " enemy IDs=", enemy_ids.size(),
			" enabled heroes=", enabled_heroes, " authored hero actives=", active_heroes)
	var valid: bool = inventory.size() == 22 and mapped_objects == 11836 and stage._stages.size() == 247 and placements == 1033 and enemy_ids.size() == 644 and enabled_heroes == 25 and active_heroes == 20
	stage.free()
	quit(0 if valid else 1)
