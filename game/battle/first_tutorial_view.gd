extends "res://battle/translated_battle_canvas.gd"

const PROMPT := 65348
const TIMED := 77122
const MODAL := "Canvas/Root/CoreGameUI/TutorialModal"

var _encounter: GuildrunEncounter
var _tutorial: RefCounted
var _panels: Dictionary = {}
var _positioning: Dictionary = {}
var _active_refs: Dictionary = {}
var _modal: Control
var _mask: ShaderMaterial
var _progress: ShaderMaterial


func bind(tutorial: RefCounted, encounter: GuildrunEncounter) -> void:
	name = "FirstTutorialView"
	_tutorial = tutorial
	_encounter = encounter
	z_index = 101
	var shade := (load("res://UI/tutorial_modal.tscn") as PackedScene).instantiate()
	add_child(shade)
	_modal = shade.get_node(MODAL)
	_modal.get_node("UnityImage").hide()
	_modal.get_node("ModalMask_FirstFight").hide()
	_mask = ShaderMaterial.new()
	_mask.shader = load("res://UI/tutorial_modal_mask.gdshader")
	var shade_rect := _modal.get_node("Modal/UnityImage") as Control
	var back_buffer := BackBufferCopy.new()
	back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	shade_rect.get_parent().add_child(back_buffer)
	shade_rect.get_parent().move_child(back_buffer, shade_rect.get_index())
	shade_rect.material = _mask
	_add_display(PROMPT, "res://UI/tutorial_prompt.tscn", "TextDisplay")
	var timed := _add_display(TIMED, "res://UI/tutorial_timed.tscn", "TimedTextDisplay")
	_progress = ShaderMaterial.new()
	_progress.shader = load("res://UI/tutorial_radial.gdshader")
	timed.get_node("DurationFeedbackSlider/Fill Area/Fill/UnityImage").material = _progress
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/first_fight_tutorial.json"))
	fit_source_canvas(timed.get_parent().get_parent(), float(settings.canvas.aspect_ratio_threshold))
	tutorial.text_shown.connect(_show_text)
	tutorial.text_hidden.connect(_hide_text)
	tutorial.timer_progress.connect(_update_progress)
	tutorial.reference_visibility_changed.connect(_set_reference)
	tutorial.reference_reparent_requested.connect(_raise_reference)
	resized.connect(_update_geometry)
	_update_geometry()


func _add_display(id: int, path: String, group: String) -> Control:
	var prefab := (load(path) as PackedScene).instantiate()
	add_child(prefab)
	var box := prefab.get_node("UtilitiesCanvas/" + group + "/TextContainer") as Control
	var caption := box.get_node("TutorialText/UnityText") as Label
	var serif := load("res://fonts/tutorial_serif.fnt") as Font
	if serif != null:
		caption.add_theme_font_override("font", serif)
	load("res://fonts/local_cjk_font.gd").apply_to(caption)
	_panels[id] = box
	return box


func _show_text(id: int, key: String, _timed: bool) -> void:
	var box: Control = _panels[id]
	var holder := box.get_node("TutorialText") as Control
	var label := holder.get_node("UnityText") as Label
	var pad: Vector4 = box.get_meta("layout_padding")
	var text_width := box.size.x - pad.x - pad.z
	label.text = tr(key).strip_edges()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var body_height := ceilf(font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER,
			text_width, font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y)
	box.size.y = pad.y + body_height + pad.w
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	holder.position = Vector2(pad.x, pad.y)
	holder.size = Vector2(text_width, body_height)
	_positioning[id] = _tutorial.current_positioning()
	if id == TIMED:
		_update_progress(TIMED, 0.0)
	box.show()
	_position_display(id)


func _hide_text(id: int) -> void:
	_panels[id].hide()
	_positioning.erase(id)


func _update_progress(_id: int, amount: float) -> void:
	_progress.set_shader_parameter("fraction", amount)


func _raise_reference(id: int, _parent: int, _all: bool) -> void:
	# Repeated use of the same element restores the original parent.
	var target: Control = _encounter._choices if id == 1500 else _encounter._result_view.reward_target
	if id in [1500, 21] and is_instance_valid(target):
		target.z_index = 0 if target.z_index != 0 else z_index
		# Shade / lifted control / text are consecutive in the tutorial sorting order.
		_modal.z_index = -1


func _set_reference(id: int, active: bool) -> void:
	_active_refs[id] = active
	match id:
		1: _modal.visible = active
		1002:
			# Both Unity controls share this reference type in their respective phase.
			_encounter._ui.get_node("StartBattleView").set_tutorial_highlight(active and _encounter.phase == GuildrunEncounter.Phase.PLACE)
			_encounter._result_view.set_proceed_highlight(active and _encounter.phase == GuildrunEncounter.Phase.RESULT)
		1003:
			_encounter._result_view.set_reward_highlight(active and _encounter.phase == GuildrunEncounter.Phase.RESULT)
		1015: _mask.set_shader_parameter("show_grid", active)
		1019: set_tracker_highlight(active)
		1016:
			var hero := _encounter._hero
			if is_instance_valid(hero) and _encounter._bars.has(hero):
				var bar: Control = _encounter._bars[hero]
				var glow := bar.find_child("HighlightUI_Mana", true, false) as Control
				if glow:
					glow.visible = active


func _tracker_panel() -> Control:
	var tracker := _encounter._ui.get_node("BattleTracker") as Control
	return tracker.get_node(tracker.PANEL) as Control


func set_tracker_highlight(active: bool) -> void:
	var outline := _tracker_panel().get_node("HighlightUI") as Control
	if active and outline.get_node("UnityImage").material == null:
		var shader := load("res://UI/tutorial_blinking_edge.gdshader") as Shader
		var images: Array[Control] = [outline.get_node("UnityImage"), outline.get_node("Highlight_Rotating/UnityImage")]
		for image in images:
			var shading := ShaderMaterial.new()
			shading.shader = shader
			shading.set_shader_parameter(&"blink", false)
			shading.set_shader_parameter(&"rotating", image.get_parent() != outline)
			image.material = shading
			var update_size := func() -> void: shading.set_shader_parameter(&"rect_size", image.size)
			image.resized.connect(update_size)
			update_size.call()
	outline.visible = active
	_active_refs[1019] = active
	_mask.set_shader_parameter(&"show_grid", active or _active_refs.get(1015, false))
	_update_geometry()


func _process(_delta: float) -> void:
	if _active_refs.get(1019, false):
		_update_geometry()
	for id: int in _positioning:
		_position_display(id)


func _update_geometry() -> void:
	if _mask == null or size.x <= 0.0 or size.y <= 0.0:
		return
	if _active_refs.get(1019, false):
		var shade := _modal.get_node("Modal/UnityImage") as Control
		var frame := shade.get_global_rect()
		var highlight := _tracker_panel().get_global_rect()
		if frame.has_area():
			var corner := (highlight.position - frame.position) / frame.size
			var end := (highlight.end - frame.position) / frame.size
			_mask.set_shader_parameter(&"opening", Vector4(corner.x, corner.y, end.x, end.y))
		return
	var opening: Rect2 = _modal.get_node("ModalMask_FirstFight").get_rect()
	var full := _modal.size
	if full.x > 0 and full.y > 0:
		_mask.set_shader_parameter("opening", Vector4(opening.position.x / full.x, opening.position.y / full.y,
				opening.end.x / full.x, opening.end.y / full.y))


func _source_target(info: Dictionary) -> Rect2:
	var target: Control
	match int(info.get("target_reference", 0)):
		10: target = _encounter._fight
		14:
			if _encounter._bars.has(_encounter._hero):
				target = _encounter._bars[_encounter._hero].find_child("TutorialViewReference", true, false)
		21: target = _encounter._result_view.reward_target
		22: target = _encounter._continue
		100: target = _tracker_panel().get_parent() as Control
	if is_instance_valid(target):
		var rect := target.get_global_rect()
		return Rect2(get_global_transform().affine_inverse() * rect.position, rect.size / scale)
	var data: Dictionary = info.get("target_rect", {})
	if data.is_empty():
		return Rect2(size / 2, Vector2.ZERO)
	var dimensions := Vector2(float(data.size_delta.x), float(data.size_delta.y))
	var offset := Vector2(float(data.anchored_position.x), -float(data.anchored_position.y))
	var pivot := Vector2(float(data.pivot.x), 1.0 - float(data.pivot.y))
	return Rect2(size / 2 + offset - pivot * dimensions, dimensions)


func _candidate(side: int, target: Rect2, bounds: Vector2, spacing: float) -> Vector2:
	var center := target.get_center()
	match side:
		1: return Vector2(center.x - bounds.x / 2, target.position.y - spacing - bounds.y)
		2: return Vector2(center.x - bounds.x / 2, target.end.y + spacing)
		3: return Vector2(target.position.x - spacing - bounds.x, center.y - bounds.y / 2)
		_: return Vector2(target.end.x + spacing, center.y - bounds.y / 2)


func _position_display(id: int) -> void:
	var info: Dictionary = _positioning[id]
	if info.is_empty():
		return
	var box: Control = _panels[id]
	var target := _source_target(info)
	var padding := float(info.padding)
	var side := int(info.alignment)
	var origin := _candidate(side, target, box.size, padding)
	var frame := Rect2(Vector2.ZERO, size)
	if side == 0 or (info.fallback_to_auto_mode_when_missing_space and not frame.encloses(Rect2(origin, box.size))):
		for candidate in [1, 2, 3, 4]:
			var alternative := _candidate(candidate, target, box.size, padding)
			if frame.encloses(Rect2(alternative, box.size)):
				origin = alternative
				break
	origin = origin.clamp(Vector2.ZERO, (size - box.size).max(Vector2.ZERO))
	box.global_position = get_global_transform() * origin
