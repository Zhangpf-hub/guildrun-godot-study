extends Node

static var _catalog: Dictionary[String, Dictionary] = {}

var _unit: GuildrunBoardUnit
var _actions: Dictionary
var _anchors: Dictionary[String, Node3D] = {}
var _active: Dictionary[Node3D, StringName] = {}
var _animation_owners: Dictionary[Node3D, Node3D] = {}


static func bindings(visual_id: String) -> Dictionary:
	if not _catalog.has(visual_id):
		var path := "res://Characters/action_vfx/%s.json" % visual_id
		var actions: Dictionary = {}
		if FileAccess.file_exists(path):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary:
				actions = data
			else:
				push_error("Invalid character action VFX bindings: %s" % path)
		_catalog[visual_id] = actions
	return _catalog[visual_id]


func setup(unit: GuildrunBoardUnit, actions: Dictionary) -> void:
	_unit = unit
	_actions = actions


func play(state: StringName, action_speed: float, battle_speed: float) -> void:
	for binding: Dictionary in _bindings_for_state(state):
		var bone: String = binding.get("bone", "")
		var anchor := _anchor(bone)
		if anchor == null:
			push_error("Action VFX %s has no bone %s on %s" % [binding.scene, bone, _unit.name])
			continue
		var scene := load(binding.scene) as PackedScene
		if scene == null:
			push_error("Missing action VFX scene: %s" % binding.scene)
			continue
		var effect := scene.instantiate() as Node3D
		var offset: Array = binding.get("position", [0, 0, 0])
		var orientation: Array = binding.get("rotation", [0, 0, 0, 1])
		var size: Array = binding.get("scale", [1, 1, 1])
		var basis := Basis(Quaternion(orientation[0], orientation[1], orientation[2], orientation[3]))
		basis = basis.scaled_local(Vector3(size[0], size[1], size[2]))
		var placement := Transform3D(basis, Vector3(offset[0], offset[1], offset[2]))
		if anchor == _unit:
			placement.origin += _unit.basis.inverse() * _unit.visual_offset
		effect.transform = placement * effect.transform
		effect.speed_scale = battle_speed
		effect.action_speed_scale = action_speed
		effect.scene_time = _unit.effect_scene_clock
		_active[effect] = state
		effect.tree_exited.connect(func() -> void: _active.erase(effect), CONNECT_ONE_SHOT)
		anchor.add_child(effect)
		if binding.has("animation"):
			_bind_animated_model(effect, binding.animation)


func _bind_animated_model(effect: Node3D, clip: StringName) -> void:
	for candidate: Node in _unit.get_children():
		var rig := candidate as Node3D
		if rig == null or not rig.has_meta(&"action_only"):
			continue
		for player: AnimationPlayer in rig.find_children("*", "AnimationPlayer", true, false):
			if not player.has_animation(clip):
				continue
			var previous_effect: Node3D = _animation_owners.get(rig)
			if is_instance_valid(previous_effect):
				previous_effect.action_mesh_phase = Callable()
			rig.hide()
			player.stop()
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			_animation_owners[rig] = effect
			var meshes: Array[Node] = rig.find_children("*", "MeshInstance3D", true, false)
			effect.action_mesh_phase = _sample_animated_model.bind(rig, player, clip, meshes)
			effect.tree_exiting.connect(_hide_animated_model.bind(rig, effect), CONNECT_ONE_SHOT)
			return
	push_error("Missing action model with clip %s on %s" % [clip, _unit.name])


func _sample_animated_model(phase: float, rig: Node3D, player: AnimationPlayer,
		clip: StringName, meshes: Array[Node]) -> void:
	if not rig.visible:
		player.play(clip)
		player.advance(0.0)
		rig.show()
	player.seek(minf(phase, player.current_animation_length), true)
	var shader_time: float = _unit.effect_scene_clock.call() if _unit.effect_scene_clock.is_valid() else phase
	for mesh: MeshInstance3D in meshes:
		mesh.set_instance_shader_parameter(&"effect_scene_seconds", shader_time)


func _hide_animated_model(rig: Node3D, effect: Node3D) -> void:
	if _animation_owners.get(rig) != effect:
		return
	_animation_owners.erase(rig)
	if is_instance_valid(rig):
		rig.hide()


func _bindings_for_state(state: StringName) -> Array:
	var state_key := String(state)
	var ranks: Dictionary = _actions.get("ranks", {})
	var ranked: Dictionary = ranks.get(str(_unit.rank), {})
	var ranked_scaling: Dictionary = ranked.get("scaling", {})
	var store := ranked if ranked.has(state_key) or ranked_scaling.has(state_key) else _actions
	var actions: Array = store.get(state_key, []).duplicate()
	var scaled: Dictionary = store.get("scaling", {})
	for group: Dictionary in scaled.get(state_key, []):
		var selected: Array = group.get("default", [])
		if _unit.effect_variable.is_valid():
			for tier: Dictionary in group.tiers:
				var key: String = tier.get("key", group.get("key", ""))
				var value: Variant = _unit.effect_variable.call(key)
				if value != null and _matches_tier(int(value), int(tier.comparison), int(tier.value)):
					selected = tier.effects
					break
		actions.append_array(selected)
	return actions


static func _matches_tier(actual: int, comparison: int, threshold: int) -> bool:
	match comparison:
		0: return actual == threshold
		1: return actual != threshold
		2: return actual >= threshold
		3: return actual > threshold
		4: return actual <= threshold
		5: return actual < threshold
	return false


func set_speed(multiplier: float) -> void:
	for effect: Node3D in _active:
		effect.speed_scale = multiplier


func stop(state: StringName) -> void:
	for effect: Node3D in _active:
		if _active[effect] == state:
			effect.hide()
			for rig: Node3D in _animation_owners.keys():
				_hide_animated_model(rig, effect)
			effect.queue_free()


func _anchor(bone: String) -> Node3D:
	if bone.is_empty():
		return _unit
	var existing: Node3D = _anchors.get(bone)
	if is_instance_valid(existing):
		return existing
	for skeleton: Skeleton3D in _unit.find_children("*", "Skeleton3D", true, false):
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		var attachment := BoneAttachment3D.new()
		attachment.bone_idx = index
		skeleton.add_child(attachment)
		_anchors[bone] = attachment
		return attachment
	return null
