extends Control

static var _settings: Dictionary
static var _font: Font
static var _icons: Dictionary[String, Texture2D]

class DamageNumber:
	var text: String
	var color: Color
	var icon: Texture2D
	var font_size: float
	var start_x: float
	var end_x: float
	var elapsed := 0.0

var _popups: Array[DamageNumber] = []
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1
	if _settings.is_empty():
		_settings = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/battle_damage_text.json"))
		_font = load("res://fonts/battle_damage_text.fnt")
		for icon in ["crit", "burn", "frost", "poison"]:
			_icons[icon] = load("res://fonts/battle_damage_%s.png" % icon)


func show_number(amount: int, kind: GuildrunBoardUnit.CombatNumber, critical: bool, player: bool) -> void:
	var popup := DamageNumber.new()
	var side := "player" if player else "enemy"
	var color_key := side + "TakeDamageColor"
	var icon := ""
	match kind:
		GuildrunBoardUnit.CombatNumber.HEAL:
			color_key = side + "HealColor"
		GuildrunBoardUnit.CombatNumber.SHIELD:
			color_key = side + "ShieldColor"
		GuildrunBoardUnit.CombatNumber.BURN:
			icon = "burn"
		GuildrunBoardUnit.CombatNumber.FROST:
			icon = "frost"
		GuildrunBoardUnit.CombatNumber.POISON:
			icon = "poison"
	if not icon.is_empty():
		color_key = icon + "DamageColor"
	if critical:
		color_key = side + "CritTakeDamageColor"
		icon = "crit"
	var color: Array = _settings.colors[color_key]
	popup.color = Color(color[0], color[1], color[2], color[3])
	popup.icon = _icons.get(icon)
	popup.text = ("+" if amount > 0 else "") + str(absi(amount))
	var weight := inverse_lerp(float(_settings[side + "MinDamage"]), float(_settings[side + "MaxDamage"]), float(absi(amount)))
	popup.font_size = lerpf(float(_settings.minFontSize), float(_settings.maxFontSize), clampf(weight, 0.0, 1.0))
	var half_range := float(_settings.positionVariation) * 0.5
	popup.end_x = _random.randf_range(-half_range, half_range) + _random.randf_range(-half_range, half_range)
	popup.start_x = _random.randf_range(-half_range, half_range)
	_popups.append(popup)
	queue_redraw()


func advance(delta: float) -> void:
	if _popups.is_empty():
		return
	for i in range(_popups.size() - 1, -1, -1):
		_popups[i].elapsed += delta
		if _popups[i].elapsed >= float(_settings.movementDuration):
			_popups.remove_at(i)
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	var point_size := int(_settings.point_size)
	var pop_time := float(_settings.popInDuration)
	var movement := float(_settings.movementDuration)
	var fade := float(_settings.fadeOutDuration)
	for popup: DamageNumber in _popups:
		var scale_factor: float = popup.font_size * lerpf(1.5, 1.0, minf(popup.elapsed / pop_time, 1.0)) / point_size
		var motion := clampf((popup.elapsed - pop_time) / movement, 0.0, 1.0)
		var jump := 1.0 - absf(2.0 * motion - 1.0)
		var point := Vector2(lerpf(popup.start_x, popup.end_x, motion), -(1.0 - pow(1.0 - jump, 2.0)) * float(_settings.jumpPower))
		var fade_progress := clampf((popup.elapsed - movement + fade) / fade, 0.0, 1.0)
		var alpha := 1.0 - pow(fade_progress, 4.0)
		var color := Color(popup.color, popup.color.a * alpha)
		var width := _font.get_string_size(popup.text, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x
		var baseline := (_font.get_ascent(point_size) - _font.get_descent(point_size)) * 0.5
		var icon_size := Vector2.ZERO
		if popup.icon != null:
			icon_size = popup.icon.get_size() * (float(_settings.cap_height) / popup.icon.get_height())
		var left := -(width + icon_size.x) * 0.5
		draw_set_transform(point, 0.0, Vector2.ONE * scale_factor)
		if popup.icon != null:
			draw_texture_rect(popup.icon, Rect2(Vector2(left, baseline - icon_size.y), icon_size), false, Color(1, 1, 1, alpha))
		draw_string(_font, Vector2(left + icon_size.x, baseline), popup.text, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size, color)
