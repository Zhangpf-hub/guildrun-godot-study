extends SceneTree

var failures: Array[String] = []
var tested_actions := 0
var tested_scenes: Dictionary[String, bool] = {}


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var stage: Node3D = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var encounter: GuildrunEncounter = stage.encounter
	var target: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
	var roster: Dictionary = {}
	for heroes: bool in [true, false]:
		var rows: Dictionary = stage._heroes if heroes else stage._enemies
		for stats: Dictionary in rows.values():
			var visual := str(int(stage.field(stats, "VisualConfig").m_PathID))
			roster.get_or_add(visual, {"stats": stats, "hero": heroes})
	var runtime: GDScript = load("res://battle/character_action_vfx.gd")
	for file: String in DirAccess.get_files_at("res://Characters/action_vfx"):
		if file.get_extension() != "json":
			continue
		var visual: String = file.get_basename()
		var row: Dictionary = roster.get(visual, {})
		if row.is_empty():
			failures.append("Action binding %s has no battle unit" % visual)
			continue
		var actions: Dictionary = runtime.bindings(visual)
		var unit: GuildrunBoardUnit = stage.spawn_unit(row.stats, Vector2i(0, 0), 0, row.hero)
		encounter._register(unit)
		verify_action_set(unit, actions)
		var ranks: Dictionary = actions.get("ranks", {})
		for rank: String in ranks:
			verify_action_set(unit, ranks[rank])
		var action_player: Node = unit.get("_action_vfx")
		if action_player != null:
			unit.effect_variable = func(_key: String) -> Variant: return null
			var expected: Array = action_player._bindings_for_state(&"BasicAttack")
			unit.begin_basic_attack(target, 65536)
			var active: Dictionary = action_player.get("_active")
			if active.size() != expected.size():
				failures.append("%s spawned %d basic effects, expected %d" % [visual, active.size(), expected.size()])
			tested_actions += 1
		encounter._units.erase(unit)
		stage.grid.occupants.erase(unit.grid_cell)
		unit.free()
	stage.free()
	print("Character action verification checked %d normal attack mounts and %d effect scenes" %
			[tested_actions, tested_scenes.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func verify_action_set(unit: GuildrunBoardUnit, actions: Dictionary) -> void:
	var scaling: Dictionary = actions.get("scaling", {})
	for state: String in ["BasicAttack", "SkillAttack", "Die"]:
		verify_entries(unit, actions.get(state, []))
		for group: Dictionary in scaling.get(state, []):
			verify_entries(unit, group.get("default", []))
			for tier: Dictionary in group.tiers:
				verify_entries(unit, tier.effects)


func verify_entries(unit: GuildrunBoardUnit, entries: Array) -> void:
	for entry: Dictionary in entries:
		var bone: String = entry.get("bone", "")
		if not bone.is_empty():
			var found := false
			for skeleton: Skeleton3D in unit.find_children("*", "Skeleton3D", true, false):
				found = found or skeleton.find_bone(bone) >= 0
			if not found:
				failures.append("Missing bone %s on %s" % [bone, unit.name])
		var path: String = entry.scene
		if tested_scenes.has(path):
			continue
		tested_scenes[path] = true
		var scene := load(path) as PackedScene
		if scene == null:
			failures.append("Missing action scene %s" % path)
			continue
		var effect := scene.instantiate() as Node3D
		unit.add_child(effect)
		if effect.get_child_count() == 0:
			failures.append("No emitters in %s" % path)
		effect.free()
