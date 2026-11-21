extends Control

signal completed

const TIMELINE := "res://balancing/intro_comic.json"
const CONTENT := "res://UI/intro_comic_content.tscn"

var template_path := CONTENT
var timeline_path := TIMELINE
var sound_event := ""

var _layout: Control
var _backdrop: ColorRect
var _fade: ColorRect
var _animation: Tween
var _duration := 0.0
var _nodes: Dictionary[int, Control] = {}
var _closing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop = _add_cover(Color.BLACK)
	_layout = (load(template_path) as PackedScene).instantiate()
	add_child(_layout)
	_layout.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fit_panel()
	resized.connect(_fit_panel)
	for child in _layout.find_children("*", "Control"):
		var id := int(child.get_meta("unity_id", 0))
		if id:
			_nodes[id] = child
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(timeline_path))
	sound_event = String(data.sound)
	_duration = float(data.duration)
	var text_boxes := {}
	for id in data.captions:
		var control := _nodes[int(id)]
		var caption: Dictionary = data.captions[id]
		var label := control.get_node("UnityText") as Label
		label.text = tr(caption.key)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if caption.has("padding"):
			var box := control.get_parent() as Control
			if not text_boxes.has(box):
				text_boxes[box] = []
			text_boxes[box].append([control, caption])
	for box: Control in text_boxes:
		_layout_captions(box, text_boxes[box])
	_fade = _add_cover(Color(0, 0, 0, 0))
	_animation = create_tween().set_parallel()
	_animation.tween_interval(_duration)
	for track: Dictionary in data.tracks:
		_add_track(track)


func _fit_panel() -> void:
	# Canvas_Comic matches width at a 1920 × 1080 reference resolution.
	var factor := maxf(0.001, size.x / 1920.0)
	_layout.size = size / factor
	_layout.scale = Vector2.ONE * factor


func _add_cover(color: Color) -> ColorRect:
	var cover := ColorRect.new()
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.color = color
	add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return cover


func _layout_captions(box: Control, entries: Array) -> void:
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0].get_index() < b[0].get_index())
	var anchor := box.position
	var data: Dictionary = entries[0][1]
	var padding := Vector2(float(data.padding[0]), float(data.padding[1]))
	var trailing := Vector2(float(data.padding[2]), float(data.padding[3]))
	var spacing := float(data.get("spacing", 0.0))
	var cursor := padding
	var widest := 0.0
	for entry: Array in entries:
		var control: Control = entry[0]
		var label := control.get_node("UnityText") as Label
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		var width := float(entry[1].width)
		if width < 0.0:
			width = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var paragraph := TextParagraph.new()
		paragraph.width = width
		paragraph.add_string(label.text, font, font_size)
		var height := paragraph.get_size().y
		control.set_anchors_preset(Control.PRESET_TOP_LEFT)
		control.position = cursor
		control.size = Vector2(width, height)
		cursor.y += height + spacing
		widest = maxf(widest, width)
	box.size = Vector2(widest + padding.x, cursor.y - spacing) + trailing
	box.position = anchor - box.size * box.pivot_offset_ratio


func _add_track(track: Dictionary) -> void:
	var node: Control = _nodes.get(int(track.node))
	if node == null:
		return
	var start := Vector2(float(track.from[0]), float(track.from[1]))
	var end := Vector2(float(track.to[0]), float(track.to[1]))
	var path: NodePath
	var from_value: Variant
	var to_value: Variant
	match track.property:
		"group_alpha", "image_alpha":
			if track.property == "image_alpha":
				node = node.get_node_or_null("UnityImage") as Control
				if node == null:
					return
			path = "modulate:a"
			from_value = start.x
			to_value = end.x
		"scale":
			path = "scale"
			from_value = Vector2.ONE * start.x
			to_value = Vector2.ONE * end.x
		"position", "position_x":
			path = "position"
			from_value = node.position
			to_value = node.position + Vector2(end.x - start.x, start.y - end.y)
		"size":
			path = "size"
			from_value = node.size
			to_value = node.size + end - start
		_:
			return
	_animation.tween_property(node, path, to_value, float(track.duration)).from(from_value).set_delay(float(track.start))


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		skip()
	elif (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
			or event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_SPACE]):
		get_viewport().set_input_as_handled()
		advance()


func advance() -> void:
	if _closing:
		return
	if _animation.is_running():
		_animation.custom_step(_duration + 1.0)
	else:
		skip()


func skip() -> void:
	if _closing:
		return
	_closing = true
	_animation.kill()
	var outro := create_tween()
	outro.tween_property(_fade, "color:a", 1.0, 0.2)
	outro.tween_interval(0.1)
	outro.tween_callback(func():
		_layout.hide()
		_backdrop.hide())
	outro.tween_interval(0.1)
	outro.tween_property(_fade, "color:a", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await outro.finished
	completed.emit()
	queue_free()
