extends Control

signal chosen(index: int)
signal dismissed

const CANVAS := Vector2(1920, 1080)
const CARD_WIDTH := 300.0
const CARD_GAP := 72.0
const HERO_GAP := 64.0

var _page: Control
var _holder: Control
var _hero_panel: Control
var _continue: Control
var _rank_label: Label
var _cards: Array[Control] = []


func setup(hero: int, portrait: String, options: Array) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.03, 0.055, 0.91)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page = (load("res://UI/specialization_picker.tscn") as PackedScene).instantiate()
	add_child(_page)
	_page.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_page.size = CANVAS
	var panel: Control = _page.get_node("SpecializationPicker")
	panel.show()
	_holder = panel.get_node("SpecializationChoiceHolder")
	_hero_panel = _holder.get_node("HeroCardPanel")
	var card: Control = _hero_panel.get_node("HeroCard")
	for label: Label in card.find_children("*", "Label", true, false):
		label.hide()
	var name_label: Label = card.get_node("Root/Mask/BodyPanel/NamePanel/HeroNameText/UnityText")
	name_label.text = tr("Heroes.Hero_%d.Name" % hero)
	name_label.show()
	card.get_node("Mask/Portrait/UnityImage").texture = load(portrait)
	card.get_node("Root/FrameBreakPortrait").hide()
	for path: String in ["Mask/UnityImage", "Root/Mask/UnityImage", "Root/Mask/BodyPanel/BarPanel",
			"Root/Mask/BodyPanel/DynamicStatsHolderPanel", "Root/Mask/BodyPanel/EquipmentHolderPanel",
			"Root/Mask/BodyPanel/StatsHolderPanel", "Root/AbilityPanel", "Root/HeroBasicInfoPanel", "Root/CompendiumButton"]:
		card.get_node(path).hide()
	_rank_label = Label.new()
	_rank_label.text = "C"
	_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_label.add_theme_font_size_override("font_size", 40)
	card.add_child(_rank_label)
	_rank_label.position = Vector2(0, 410)
	_rank_label.size.x = card.size.x
	panel.get_node("TopBanner").show()
	panel.get_node("TopBanner").position.y = 0
	var heading: Label = panel.get_node("TopBanner/TitleText/UnityText")
	heading.text = tr("UI.HeroCard.Specialization.Title")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue = panel.get_node("PrimaryButton")
	_continue.get_node("Text (TMP)/UnityText").text = tr("UI.Common.Continue")
	_continue.hide()
	var finish := _button(_continue, tr("UI.Common.Continue"))
	finish.pressed.connect(func(): dismissed.emit())
	var width := 360.0 + HERO_GAP + CARD_WIDTH * options.size() + CARD_GAP * (options.size() - 1)
	_holder.size.x = width
	_holder.position = (CANVAS - _holder.size) * 0.5 + Vector2.DOWN * 50.0
	_hero_panel.position.x = 0
	for i in options.size():
		var choice := _make_card(options[i], i)
		choice.position = Vector2(360.0 + HERO_GAP + i * (CARD_WIDTH + CARD_GAP), (_holder.size.y - choice.size.y) * 0.5)
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	var zoom := minf(size.x / CANVAS.x, size.y / CANVAS.y)
	_page.scale = Vector2.ONE * zoom
	_page.position = (size - CANVAS * zoom) * 0.5


func _button(parent: Control, caption: String) -> Button:
	var button := Button.new()
	parent.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.accessibility_name = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _make_card(option: Dictionary, index: int) -> Control:
	var shell: Control = (load("res://UI/specialization_choice.tscn") as PackedScene).instantiate()
	_holder.add_child(shell)
	shell.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var card: Control = shell.get_node("SpecializationChoiceView")
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.get_node("TitleContainer").hide()
	card.get_node("BodyContainer").hide()
	card.get_node("VFX_Glow").hide()
	var icon: TextureRect = card.get_node("Icon/IconReference_1/UnityImage")
	icon.texture = load(option.icon)
	var title := Label.new()
	title.text = tr(option.name)
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(title)
	title.position = Vector2(22, 58)
	title.size = Vector2(CARD_WIDTH - 44, 42)
	var body := Label.new()
	body.text = _description(option)
	body.add_theme_font_size_override("font_size", 23)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(body)
	body.position = Vector2(22, 112)
	body.size.x = CARD_WIDTH - 44
	shell.size = Vector2(CARD_WIDTH, maxf(313.0, body.position.y + body.get_minimum_size().y + 24))
	var button := _button(card, title.text)
	button.pressed.connect(func(): chosen.emit(index))
	_cards.append(shell)
	return shell


func _description(option: Dictionary) -> String:
	var result := tr(option.description)
	for key: String in option.variables:
		var value := str(option.variables[key])
		if value.contains("d") and value.get_slice("d", 0).is_valid_int() and value.get_slice("d", 1).is_valid_int():
			value = value.get_slice("d", 1)
		result = result.replace("{%s}" % key, value)
	var markup := RegEx.new()
	markup.compile("\\[([^\\]]*)\\]<[^>]+>")
	result = markup.sub(result, "$1", true)
	var rank_formula := RegEx.new()
	rank_formula.compile("(\\d+)\\+(\\d+)_Rank")
	for hit: RegExMatch in rank_formula.search_all(result):
		# The B-rank preview has one completed promotion.
		result = result.replace(hit.get_string(), str(int(hit.get_string(1)) + int(hit.get_string(2))))
	var stat_formula := RegEx.new()
	stat_formula.compile("(\\d+(?:/\\d+)?)_(Attack|Defense|Magic|MaxHealth|ManaRegen)")
	for hit: RegExMatch in stat_formula.search_all(result):
		var coefficient := hit.get_string(1)
		var label := tr("UI.Stat.%s.Title" % hit.get_string(2))
		var factor := coefficient if coefficient.contains("/") else coefficient + "%"
		result = result.replace(hit.get_string(), factor + " × " + label)
	return result


func show_result(index: int, changes: PackedStringArray) -> void:
	_rank_label.text = "B"
	for i in _cards.size():
		_cards[i].visible = i == index
	var selected := _cards[index]
	selected.position.x = 360 + HERO_GAP
	for button: Button in selected.find_children("*", "Button", true, false):
		button.disabled = true
	var stats := Label.new()
	stats.text = "\n".join(changes)
	stats.add_theme_font_size_override("font_size", 27)
	_holder.add_child(stats)
	stats.position = Vector2(360 + HERO_GAP + CARD_WIDTH + CARD_GAP, 0)
	_continue.show()
