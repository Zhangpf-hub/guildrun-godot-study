extends "res://battle/translated_battle_canvas.gd"

const HOLDER := "Canvas/Root/PlacementPhasePanel/StartBattleButton"
var button: Button
var graphics: Control
var text: Label
var tutorial_highlight := false


func bind(action: Button) -> void:
	button = action
	var source := get_node(HOLDER + "/StartBattleButton") as Control
	graphics = source.get_node("Button_Graphics")
	text = source.get_node("Text (TMP)/UnityText")
	text.text = tr("UI.Battle.Fight")
	bind_hit_area(action, source, text.text)
	source.get_node("AnchorWarnText").show()
	var warning := source.get_node("AnchorWarnText/UnityText") as Label
	warning.text = tr("UI.RiftAnchorNotEquiped")
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.hide()
	fit_source_canvas($Canvas)
	get_node(HOLDER + "/HighlightAbility_Back").add_child((load("res://UI/fight_highlight_back.tscn") as PackedScene).instantiate())
	get_node(HOLDER + "/HighlightAbility").add_child((load("res://UI/fight_highlight_front.tscn") as PackedScene).instantiate())
	graphics.get_node("Highlight").hide()
	button.mouse_entered.connect(_update_graphics)
	button.mouse_exited.connect(_update_graphics)
	button.button_down.connect(_update_graphics)
	button.button_up.connect(_update_graphics)
	_update_graphics()


func warning_label() -> Label:
	return get_node(HOLDER + "/StartBattleButton/AnchorWarnText/UnityText")


func set_tutorial_highlight(value: bool) -> void:
	tutorial_highlight = value
	get_node(HOLDER + "/HighlightAbility").visible = value
	get_node(HOLDER + "/HighlightAbility_Back").visible = value
	_update_graphics()


func _process(_delta: float) -> void:
	if is_instance_valid(button):
		_update_graphics()


func _update_graphics() -> void:
	visible = button.visible
	graphics.get_node("Hover").visible = button.is_hovered() and not button.disabled
	graphics.get_node("Pressed").visible = button.button_pressed and not button.disabled
	graphics.get_node("Disabled").visible = button.disabled
