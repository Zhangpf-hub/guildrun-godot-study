extends Polygon2D

@export var period := 1.0
@export var lifetime := 1.0
@export var horizontal_size: Curve
@export var vertical_size: Curve
@export var opacity: Curve

var _elapsed := 0.0


func _ready() -> void:
	visibility_changed.connect(_visibility_changed)
	_visibility_changed()


func _visibility_changed() -> void:
	_elapsed = 0.0
	set_process(is_visible_in_tree())
	_sample()


func _process(delta: float) -> void:
	_elapsed = fmod(_elapsed + delta, period)
	_sample()


func _sample() -> void:
	var phase := clampf(_elapsed / lifetime, 0.0, 1.0)
	scale = Vector2(horizontal_size.sample(phase) if horizontal_size else 1.0,
			vertical_size.sample(phase) if vertical_size else 1.0)
	self_modulate.a = opacity.sample(phase) if opacity else 1.0
	if _elapsed >= lifetime:
		self_modulate.a = 0.0
