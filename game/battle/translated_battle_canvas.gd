extends Control

var _reference_width := 1920.0
var _wide_screen_threshold := INF
var _reference_height := 1080.0


func fit_source_canvas(canvas: Control, wide_screen_threshold: float = NAN) -> void:
	var reference: Vector2 = canvas.get_meta("reference_resolution")
	_reference_width = reference.x
	_reference_height = reference.y
	_wide_screen_threshold = wide_screen_threshold
	if is_nan(_wide_screen_threshold):
		_wide_screen_threshold = float(canvas.get_meta("aspect_ratio_threshold", INF))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parent: Control = get_parent()
	if not parent.resized.is_connected(_resize_canvas):
		parent.resized.connect(_resize_canvas)
	_resize_canvas()


func _resize_canvas() -> void:
	var bounds: Vector2 = get_parent().size
	if bounds.x <= 0 or bounds.y <= 0:
		return
	var factor := bounds.x / _reference_width
	if bounds.x / bounds.y >= _wide_screen_threshold:
		factor = bounds.y / _reference_height
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = bounds / factor
	scale = Vector2.ONE * factor


func bind_hit_area(button: Button, container: Control, accessible_text: String) -> void:
	button.text = ""
	button.accessibility_name = accessible_text
	button.custom_minimum_size = Vector2.ZERO
	for style: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	container.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
