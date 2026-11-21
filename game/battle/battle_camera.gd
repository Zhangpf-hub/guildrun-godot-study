extends Node

signal projection_changed

const ANY_CAMERA := "**ANY CAMERA**"

var state := "cut"
var active_priority := 1
var _camera: Camera3D
var _rig: Node3D
var _nodes: Dictionary = {}
var _data: Dictionary
var _from: Transform3D
var _from_fov := 21.0
var _nominal_fov := 21.0
var _elapsed := 0.0
var _duration := 0.0
var _intro_remaining := 0.0
var _aspect := 1.0
var _focus := Vector3.ZERO
var _left_bar := ColorRect.new()
var _right_bar := ColorRect.new()


func setup(camera: Camera3D, rig: Node3D) -> void:
	_camera = camera
	_rig = rig
	_data = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/battle_camera.json"))
	_index_nodes(_rig)
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var bars := CanvasLayer.new()
	bars.layer = 0
	add_child(bars)
	for bar: ColorRect in [_left_bar, _right_bar]:
		bars.add_child(bar)
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera.get_viewport().size_changed.connect(_resize)
	_resize()
	set_state("start")


func _index_nodes(parent: Node3D) -> void:
	for child: Node3D in parent.get_children():
		if child.has_meta("unity_id"):
			_nodes[int(child.get_meta("unity_id"))] = child
		_index_nodes(child)


func set_state(next: String, focus := Vector3.ZERO) -> void:
	if next == state:
		return
	_intro_remaining = 0.0
	var transition := blend_for(state, next)
	_from = _camera.global_transform
	_from_fov = _nominal_fov
	_duration = 0.0 if int(transition[0]) == 0 else float(transition[1])
	_elapsed = 0.0
	state = next
	_focus = focus
	var settings: Dictionary = _data.cameras[state]
	active_priority = int(_data.active_priority) if state != "cut" else int(settings.priority)
	_camera.near = float(settings.near)
	_camera.far = float(settings.far)
	_apply(_duration <= 0.0)


func enter_placement() -> void:
	if state in ["result", "crossroads", "crossroads_zoom"]:
		set_state("intro")
		_intro_remaining = float(_data.intro_delay)
	else:
		set_state("placement")


func blend_for(previous: String, next: String) -> Array:
	var source: String = _data.cameras[previous].name
	var destination: String = _data.cameras[next].name
	var selected: Array = _data.default_blend
	var priority := -1
	for row: Array in _data.blends:
		if row[0] not in [source, ANY_CAMERA] or row[1] not in [destination, ANY_CAMERA]:
			continue
		var weight := int(row[0] == source) * 2 + int(row[1] == destination)
		if weight > priority:
			priority = weight
			selected = [row[2], row[3]]
	return selected


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if _intro_remaining > 0.0:
		var remaining := _intro_remaining
		_intro_remaining = maxf(0.0, remaining - delta)
		_advance_blend(minf(delta, remaining))
		if _intro_remaining == 0.0:
			set_state("placement")
			_advance_blend(maxf(0.0, delta - remaining))
		return
	_advance_blend(delta)


func _advance_blend(delta: float) -> void:
	if _elapsed < _duration:
		_elapsed = minf(_duration, _elapsed + delta)
		_apply(_elapsed >= _duration)


func target_transform(camera_state: String) -> Transform3D:
	var lens: Dictionary = _data.cameras[camera_state]
	var node: Node3D = _nodes[int(lens.id)]
	var local := node.transform
	if lens.has("aspect"):
		local.origin = Vector3(0.0, 0.0, lerpf(float(lens.z[0]), float(lens.z[1]), _ratio(lens.aspect)))
	if camera_state == "crossroads_zoom":
		var target := node.global_transform
		var limits: Array = _data.input.aim_distance
		target.origin = _focus + target.basis.z * lerpf(float(limits[0]), float(limits[1]), _ratio(_data.input.aspect))
		return target
	if camera_state != "fight":
		return node.get_parent().global_transform * local
	var input: Dictionary = _data.input
	var width := _ratio(input.aspect)
	var near_z := lerpf(float(input.narrow[0]), float(input.wide[0]), width)
	var far_z := lerpf(float(input.narrow[1]), float(input.wide[1]), width)
	var zoom := lerpf(float(input.initial[0]), float(input.initial[1]), width)
	local.origin.z = -lerpf(near_z, far_z, zoom)
	var parent: Node3D = node.get_parent()
	while int(parent.get_meta("unity_id", -1)) != int(input.mover):
		local = parent.transform * local
		parent = parent.get_parent()
	var pan := parent.transform
	pan.origin.x = _pan_center(input.bounds_x, zoom)
	pan.origin.z = -_pan_center(input.bounds_z, zoom)
	return parent.get_parent().global_transform * pan * local


func _pan_center(bounds: Array, zoom: float) -> float:
	return (lerpf(float(bounds[0]), float(bounds[2]), zoom)
			+ lerpf(float(bounds[1]), float(bounds[3]), zoom)) / 2.0


func _ratio(thresholds: Array) -> float:
	return clampf(inverse_lerp(float(thresholds[0]), float(thresholds[1]), _aspect), 0.0, 1.0)


func _resize() -> void:
	var viewport := _camera.get_viewport().get_visible_rect().size
	if viewport.y <= 0.0:
		return
	_aspect = minf(viewport.x / viewport.y, float(_data.effective_aspect_cap))
	var width := maxf(0.0, (viewport.x - viewport.y * float(_data.effective_aspect_cap)) / 2.0)
	_left_bar.size = Vector2(width, viewport.y)
	_right_bar.size = _left_bar.size
	_right_bar.position.x = viewport.x - width
	_left_bar.visible = width > 0.0
	_right_bar.visible = width > 0.0
	_apply(_duration <= _elapsed)


func _apply(complete: bool) -> void:
	var target := target_transform(state)
	var lens: Dictionary = _data.cameras[state]
	var target_fov := float(lens.fov)
	if complete:
		_camera.global_transform = target
		_nominal_fov = target_fov
	else:
		var t := _elapsed / _duration
		var weight := t * t * (3.0 - 2.0 * t)
		_camera.global_transform = _from.interpolate_with(target, weight)
		_nominal_fov = lerpf(_from_fov, target_fov, weight)
	_camera.fov = _gate_fitted_fov(lens)
	projection_changed.emit()


func _gate_fitted_fov(lens: Dictionary) -> float:
	var projection: Dictionary = _data.get("projection", {})
	var physical: Dictionary = lens.get("physical_lens", {})
	var mode: String = physical.get("mode_override", "inherit")
	var use_physical := mode == "physical" or (mode == "inherit" and bool(projection.get("physical", false)))
	if not use_physical or physical.get("gate_fit", projection.get("gate_fit", "")) != "horizontal":
		return _nominal_fov
	var sensor: Array = physical.get("sensor", projection.get("sensor", []))
	if sensor.size() != 2 or float(sensor[0]) <= 0.0 or float(sensor[1]) <= 0.0 or _aspect <= 0.0:
		return _nominal_fov
	# Unity fits the film width. Godot uses a vertical field of view, even over the cropped viewport.
	var film_aspect := float(sensor[0]) / float(sensor[1])
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(_nominal_fov) * 0.5) * film_aspect / _aspect))
