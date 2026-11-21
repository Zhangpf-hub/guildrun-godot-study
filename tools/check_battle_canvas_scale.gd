extends SceneTree

const REFERENCE := Vector2(1920.0, 1080.0)
const THRESHOLD := 1.7999999523162842

var _failures: int = 0


func _initialize() -> void:
	_check.call_deferred()


func _check() -> void:
	var parent := Control.new()
	root.add_child(parent)
	var canvas := Control.new()
	canvas.set_meta("reference_resolution", REFERENCE)
	canvas.set_meta("aspect_ratio_threshold", THRESHOLD)
	var view := Control.new()
	view.set_script(load("res://battle/translated_battle_canvas.gd"))
	parent.add_child(view)
	view.add_child(canvas)
	var center := Control.new()
	view.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	view.fit_source_canvas(canvas)
	_expect_geometry(parent, view, center, Vector2(1000, 1000), 1000.0 / REFERENCE.x)
	_expect_geometry(parent, view, center, Vector2(1280, 720), 2.0 / 3.0)
	_expect_geometry(parent, view, center, Vector2(1799, 1000), 1799.0 / REFERENCE.x)
	_expect_geometry(parent, view, center, Vector2(1800, 1000), 1000.0 / REFERENCE.y)
	_expect_geometry(parent, view, center, Vector2(2560, 1080), 1.0)
	_expect_geometry(parent, view, center, Vector2(1000, 1000), 1000.0 / REFERENCE.x)
	view.fit_source_canvas(canvas, INF)
	_expect_geometry(parent, view, center, Vector2(2560, 1080), 2560.0 / REFERENCE.x)
	view.fit_source_canvas(canvas, 2.0)
	_expect_geometry(parent, view, center, Vector2(1800, 1000), 1800.0 / REFERENCE.x)
	_expect_geometry(parent, view, center, Vector2(2400, 1000), 1000.0 / REFERENCE.y)
	canvas.remove_meta("aspect_ratio_threshold")
	view.fit_source_canvas(canvas)
	_expect_geometry(parent, view, center, Vector2(2560, 1080), 2560.0 / REFERENCE.x)
	if _failures == 0:
		print("Battle canvas scale passed")
	quit(int(_failures > 0))


func _expect_geometry(parent: Control, view: Control, center: Control, bounds: Vector2, factor: float) -> void:
	parent.size = bounds
	var projected_center: Vector2 = center.get_global_transform().origin
	if not view.scale.is_equal_approx(Vector2.ONE * factor) \
			or not (view.size * factor).is_equal_approx(bounds) \
			or not projected_center.is_equal_approx(bounds * 0.5):
		_failures += 1
		push_error("Wrong canvas geometry for %s at scale %f" % [bounds, factor])
