extends "res://battle/translated_battle_canvas.gd"

const ROOT_PATH := "Canvas/Root/CoreGameUI/SpeedControls"
const PHASE := GuildrunEncounter.Phase
var encounter: GuildrunEncounter
var _model: RefCounted
var _controls: Array[Control] = []
var _last_phase := -1


func bind(value: GuildrunEncounter) -> void:
	encounter = value
	_model = encounter.simulation_speed
	var source := get_node(ROOT_PATH) as Control
	var body := source.get_node("Root") as Control
	var row := body.get_node("ButtonPanel") as Control
	var auto := row.get_node("SpeedButton_Auto") as Control
	var label := auto.get_node("Text/UnityText") as Label
	load("res://fonts/local_cjk_font.gd").apply_to(label)
	# The demo displays the serialized AUTO legend in its compact speed bar.
	label.uppercase = true
	var icon := auto.get_node("Icon") as Control
	var padding: Vector4 = auto.get_meta("layout_padding")
	var icon_width := float(icon.get_meta("preferred_width"))
	var spacing := float(auto.get_meta("layout_spacing"))
	var text_width := ceilf(label.get_minimum_size().x)
	_position(icon, padding.x, 0, icon_width, 18)
	_position(label.get_parent(), padding.x + icon_width + spacing, 0, text_width, 32)
	icon.position.y = (32 - icon.size.y) / 2
	var auto_width := padding.x + icon_width + spacing + text_width + padding.z
	var x := 0.0
	for i in 4:
		var slot := auto if i == 0 else row.get_node("SpeedButton_%d" % i) as Control
		var width := auto_width if i == 0 else float(slot.get_meta("preferred_width"))
		_position(slot, x, 0, width, 32)
		_controls.append(slot)
		var hit := Button.new()
		hit.name = "SelectSpeed"
		bind_hit_area(hit, slot, tr("UI.Battle.BattleSpeed.Auto") if i == 0 else ["1×", "1.6×", "2.5×"][i-1])
		hit.pressed.connect(_select.bind(i))
		x += width + float(row.get_meta("layout_spacing"))
	var width := x - float(row.get_meta("layout_spacing"))
	source.offset_left = source.offset_right - width
	_position(body, 0, 0, width, source.size.y)
	_position(row, 0, 0, width, 32)
	var caption := body.get_node("SpeedControlsText") as Control
	caption.get_node("UnityText").text = tr("UI.Battle.BattleSpeed")
	_position(caption, 0, 32, width, caption.size.y)
	fit_source_canvas($Canvas)
	_model.speed_changed.connect(_speed_changed)
	_refresh()


func _position(slot: Control, x: float, y: float, width: float, height: float) -> void:
	slot.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	slot.position = Vector2(x, y)
	slot.size = Vector2(width, height)


func _select(index: int) -> void:
	if encounter._first_tutorial != null and encounter._first_tutorial.input_locked:
		return
	if index == 0:
		_model.set_automatic(not _model.is_automatic())
	else:
		_model.select_manual(index - 1)


func _speed_changed(_index: int, _multiplier: float, _automatic: bool) -> void:
	_refresh()


func _process(_delta: float) -> void:
	if is_instance_valid(encounter) and encounter.phase != _last_phase:
		_refresh()


func _refresh() -> void:
	_last_phase = encounter.phase
	visible = encounter.phase in [PHASE.PICK, PHASE.PLACE, PHASE.FIGHT, PHASE.RESULT]
	var auto: bool = _model.is_automatic()
	_controls[0].get_node("EnabledGraphic").visible = auto
	var tint := Color.WHITE if auto else Color("#82816e")
	_controls[0].get_node("Icon").modulate = tint
	_controls[0].get_node("Text").modulate = tint
	for i in 3:
		var slot := _controls[i + 1]
		var current: bool = i == _model.speed_index()
		slot.get_node("EnabledGraphic").visible = current and not auto
		slot.get_node("CurrentTriangle").visible = current and auto and encounter.phase == PHASE.FIGHT
