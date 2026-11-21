extends Control

const ROAD_PANEL := "Canvas/Root/CrossroadsPanel"
const ROAD_CONTENT := ROAD_PANEL + "/CrossroadsContentPanel"
const EVENT_CONTROLLER := "Canvas/Root/EventUIController"
const EVENT_CONTENT := EVENT_CONTROLLER + "/EventContentPanel"
const EVENT_IMAGE := "Canvas/Root/EventImagePanel/EventImage"
const CHOICE_HOLDER := EVENT_CONTENT + "/ScrollView/Viewport/ChoicesHolder"

var _roads: Control
var _event: Control
var _scroll_limit := 0.0
var _default_artwork: Texture2D
var _world_gates: Control
var _entries: Array[Dictionary]
var _select_path: Callable
var _hover_path: Callable


func setup_world(entries: Array[Dictionary], select: Callable, hover: Callable) -> void:
	_entries.assign(entries)
	_select_path = select
	_hover_path = hover
	_world_gates = Control.new()
	_world_gates.name = "WorldGateTargets"
	_world_gates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world_gates)
	_world_gates.hide()


func setup(title: String, entries: Array[Dictionary], select: Callable, hover: Callable) -> void:
	_roads = (load("res://UI/forest_trial_roads.tscn") as PackedScene).instantiate()
	_event = (load("res://UI/forest_trial_event.tscn") as PackedScene).instantiate()
	for canvas: Control in [_roads, _event]:
		canvas.set_anchors_preset(Control.PRESET_TOP_LEFT)
		add_child(canvas)
	setup_world(entries, select, hover)
	_event.hide()
	_default_artwork = _event.get_node(EVENT_IMAGE + "/UnityImage").texture
	_roads.get_node(ROAD_PANEL).show()
	_roads.get_node(ROAD_PANEL + "/Modal").show()
	_label(_roads, ROAD_CONTENT + "/CrossroadsTitleText", title)
	var holder: Control = _roads.get_node(ROAD_CONTENT + "/CrossroadsButtonHolder")
	var template: Control = holder.get_node("CrossroadsPathView")
	var cards: Array[Control] = [template]
	for i in range(1, entries.size()):
		var card := template.duplicate() as Control
		holder.add_child(card)
		cards.append(card)
	_fit_canvases()
	var spacing: float = holder.get_meta("layout_spacing")
	for i in entries.size():
		var card := cards[i]
		card.show()
		var slot := (holder.size.x - spacing * (entries.size() - 1)) / entries.size()
		card.position.x = (slot + spacing) * i + (slot - card.size.x) / 2.0
		_label(card, "TitleText", entries[i].title)
		var description := _label(card, "DescriptionText", entries[i].description, true)
		var title_box: Control = card.get_node("TitleText")
		var enter: Control = card.get_node("EnterButton")
		var gap: float = -enter.offset_top + description.get_parent().offset_bottom
		card.size.y = title_box.size.y + _text_height(description) + enter.size.y + absf(gap)
		_label(card, "EnterButton/Text (TMP)", tr("UI.Common.Proceed"))
		_bind_button(card.get_node("EnterButton"), select.bind(i))
	resized.connect(_fit_canvases)


func show_event(title: String, description: String, artwork: Texture2D, options: Array[Dictionary], choose: Callable, back: Callable) -> void:
	_roads.hide()
	_world_gates.hide()
	_event.show()
	_label(_event, EVENT_CONTENT + "/EventNameText", title)
	_label(_event, EVENT_CONTENT + "/EventDescriptionText", description, true)
	_label(_event, EVENT_CONTENT + "/EventOutcomeText", "")
	var image: TextureRect = _event.get_node(EVENT_IMAGE + "/UnityImage")
	image.texture = artwork if artwork != null else _default_artwork
	_event.get_node(EVENT_IMAGE + "/PlaceholderPanel").hide()
	var holder: Control = _event.get_node(CHOICE_HOLDER)
	var start: Control = holder.get_node("ChoiceButtonView_2")
	var reward: Control = holder.get_node("ChoiceButtonView_Artifact_Variant")
	var last: Control = holder.get_node("ChoiceButtonView_Last")
	var templates: Array[Control] = [start, reward, last]
	for child: Control in holder.get_children():
		if child in templates:
			child.hide()
		else:
			holder.remove_child(child)
			child.queue_free()
	var offset := start.position.y
	var spacing: float = holder.get_meta("layout_spacing")
	var padding: Vector4 = holder.get_meta("layout_padding")
	_layout_event_content()
	holder.position.y = 0.0
	for i in options.size():
		var option := options[i]
		var reward_icon: Texture2D = option.get("icon")
		var template := reward if reward_icon != null else (last if i == options.size() - 1 else start)
		var card := template.duplicate() as Control
		holder.add_child(card)
		card.show()
		var card_padding: Vector4 = card.get_meta("layout_padding")
		var card_width := holder.size.x - padding.x - padding.z
		card.position = Vector2(padding.x, offset)
		card.size.x = card_width
		var caption := _label(card, "ButtonText", option.text, true)
		var caption_color := caption.get_theme_color("font_color")
		caption_color.a = 1.0
		caption.add_theme_color_override("font_color", caption_color)
		_place(caption.get_parent(), Vector2(card_padding.x, card_padding.y),
				Vector2(card_width - card_padding.x - card_padding.z, caption.size.y))
		caption.get_parent().size.y = _text_height(caption)
		card.size.y = card_padding.y + caption.get_parent().size.y + card_padding.w
		offset += card.size.y + spacing
		if reward_icon != null:
			_set_reward_icon(card, option.kind, reward_icon, option.name)
		var icon: Control = card.get_node_or_null("Icon")
		if icon != null:
			icon.hide()
		_bind_button(card.get_node("Button"), choose.bind(i), "Graphics")
	var primary: Control = _event.get_node(EVENT_CONTROLLER + "/PrimaryButton")
	primary.visible = options.is_empty()
	if options.is_empty():
		_label(primary, "Text (TMP)", tr("UI.Common.Back"))
		_bind_button(primary, back, "Button_Graphics")
	holder.show()
	var viewport: Control = holder.get_parent()
	_scroll_limit = maxf(0.0, offset - viewport.size.y)
	_event.get_node(EVENT_CONTENT + "/ScrollView/Scrollbar Vertical").visible = _scroll_limit > 0


func show_outcome(outcome: String, proceed: Callable) -> void:
	_event.get_node(CHOICE_HOLDER).hide()
	_label(_event, EVENT_CONTENT + "/EventDescriptionText", outcome, true)
	_layout_event_content()
	_event.get_node(EVENT_CONTENT + "/ScrollView").hide()
	var primary: Control = _event.get_node(EVENT_CONTROLLER + "/PrimaryButton")
	primary.show()
	_label(primary, "Text (TMP)", tr("UI.Common.Continue"))
	_bind_button(primary, proceed, "Button_Graphics")


func use_world_gates(rects: Array[Rect2], label_rects: Array[Rect2]) -> void:
	var count := rects.size() if rects.size() == _entries.size() else 0
	for index in range(_world_gates.get_child_count() - 1, count - 1, -1):
		var obsolete := _world_gates.get_child(index)
		_world_gates.remove_child(obsolete)
		obsolete.queue_free()
	var local := get_global_transform_with_canvas().affine_inverse()
	for index in count:
		var button := _world_gates.get_child(index) as Button if index < _world_gates.get_child_count() else _make_gate(index)
		button.position = local * rects[index].position
		button.size = local.basis_xform(rects[index].size)
		if label_rects.size() != count:
			button.tooltip_text = "%s\n%s" % [_entries[index].title, _entries[index].description]
			continue
		button.tooltip_text = ""
		if button.get_child_count() == 0:
			_add_gate_labels(button, _entries[index])
		var label_rect := Rect2(local * label_rects[index].position, local.basis_xform(label_rects[index].size))
		_place_gate_labels(button, label_rect)
	if _event == null or not _event.visible:
		show_roads()


func _make_gate(index: int) -> Button:
	var button := Button.new()
	button.name = "Gate%d" % index
	button.flat = true
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, empty)
	_world_gates.add_child(button)
	button.pressed.connect(_select_path.bind(index))
	button.mouse_entered.connect(_hover_path.bind(index))
	button.mouse_exited.connect(_hover_path.bind(-1))
	return button


func _add_gate_labels(button: Button, entry: Dictionary) -> void:
	var title_scene: Control = (load("res://UI/forest_trial_gate_title.tscn") as PackedScene).instantiate()
	title_scene.set_anchors_preset(Control.PRESET_TOP_LEFT)
	button.add_child(title_scene)
	var title_box: Control = title_scene.get_node("Title")
	title_box.scale = Vector2.ONE
	var title := _label(title_scene, "Title", entry.title)
	title.set_meta("native_font_size", title.get_theme_font_size("font_size"))

	var tooltip_scene: Control = (load("res://UI/forest_trial_gate_tooltip.tscn") as PackedScene).instantiate()
	tooltip_scene.set_anchors_preset(Control.PRESET_TOP_LEFT)
	button.add_child(tooltip_scene)
	var panel: Control = tooltip_scene.get_node("ComplexTooltip_01")
	var box: Control = panel.get_node("DescriptionWorldSpace")
	var text_box: Control = box.get_node("MainText")
	var padding: Vector4 = panel.get_meta("layout_padding")
	var panel_width := panel.size.x
	tooltip_scene.set_meta("native_bottom", panel.offset_bottom)
	_place(box, Vector2(padding.x, padding.y), Vector2(panel_width - padding.x - padding.z, 0))
	_place(text_box, Vector2.ZERO, box.size)
	var text := _label(box, "MainText", entry.description, true)
	box.size.y = _text_height(text)
	text_box.size.y = box.size.y
	_place(panel, Vector2.ZERO, Vector2(panel_width, box.size.y + padding.y + padding.w))
	tooltip_scene.hide()
	button.mouse_entered.connect(func():
		title_scene.hide()
		tooltip_scene.show())
	button.mouse_exited.connect(func():
		tooltip_scene.hide()
		title_scene.show())


func _place_gate_labels(button: Button, label_rect: Rect2) -> void:
	var title_scene: Control = button.get_child(0)
	var title_box: Control = title_scene.get_node("Title")
	_place(title_box, label_rect.position - button.position, label_rect.size)
	var title: Label = title_box.get_node("UnityText")
	var font_size := maxi(1, roundi(int(title.get_meta("native_font_size")) * label_rect.size.y / 10.0))
	if title.get_theme_font_size("font_size") != font_size:
		title.add_theme_font_size_override("font_size", font_size)
	var tooltip_scene: Control = button.get_child(1)
	var panel: Control = tooltip_scene.get_node("ComplexTooltip_01")
	var tooltip_scale := 0.025 * label_rect.size.y
	var world_to_tooltip := float(tooltip_scene.get_meta("native_bottom")) * tooltip_scale
	tooltip_scene.scale = Vector2.ONE * tooltip_scale
	tooltip_scene.position = Vector2((button.size.x - panel.size.x * tooltip_scale) / 2.0,
			button.size.y / 2.0 + 1.47 * label_rect.size.y + world_to_tooltip - panel.size.y * tooltip_scale)


func show_roads() -> void:
	if _event != null:
		_event.hide()
	var use_gates := _world_gates.get_child_count() > 0
	if _roads != null:
		_roads.visible = not use_gates
	_world_gates.visible = use_gates


func _fit_canvases() -> void:
	for canvas_scene: Control in [_roads, _event]:
		var canvas: Control = canvas_scene.get_node("Canvas")
		var resolution: Vector2 = canvas.get_meta("reference_resolution")
		var ratio := size / resolution
		var match_axis: float = canvas.get_meta("match_width_or_height")
		if ratio.x <= 0 or ratio.y <= 0:
			continue
		var ui_scale := pow(2.0, lerpf(log(ratio.x) / log(2.0), log(ratio.y) / log(2.0), match_axis))
		canvas_scene.size = size / ui_scale
		canvas_scene.scale = Vector2.ONE * ui_scale


func _layout_event_content() -> void:
	var content: Control = _event.get_node(EVENT_CONTENT)
	var padding: Vector4 = content.get_meta("layout_padding")
	var spacing: float = content.get_meta("layout_spacing")
	var width := content.size.x - padding.x - padding.z
	var y := padding.y
	for name in ["EventNameText", "EventDescriptionText"]:
		var box: Control = content.get_node(name)
		_place(box, Vector2(padding.x, y), Vector2(width, box.size.y))
		box.size.y = _text_height(box.get_node("UnityText"))
		y += box.size.y + spacing
	var scroll: Control = content.get_node("ScrollView")
	scroll.show()
	_place(scroll, Vector2(padding.x, y), Vector2(width, maxf(0.0, content.size.y - y - padding.w)))
	var viewport: Control = scroll.get_node("Viewport")
	_place(viewport, Vector2.ZERO, scroll.size)


func _place(control: Control, at: Vector2, dimensions: Vector2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = at
	control.size = dimensions


func _text_height(label: Label) -> float:
	var paragraph := TextParagraph.new()
	paragraph.break_flags = TextServer.BREAK_MANDATORY
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		paragraph.break_flags |= TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		paragraph.width = label.get_parent().size.x
	paragraph.add_string(label.text, label.get_theme_font("font"),
			label.get_theme_font_size("font_size"), TranslationServer.get_locale())
	var line_spacing := label.get_theme_constant("line_spacing")
	return ceilf(paragraph.get_size().y + maxi(0, paragraph.get_line_count() - 1) * line_spacing)


func _label(root: Control, path: String, value: String, wrap := false) -> Label:
	var label: Label = root.get_node(path + "/UnityText")
	label.text = value
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or _event == null or not _event.visible or _scroll_limit <= 0:
		return
	var delta := float(event.button_index == MOUSE_BUTTON_WHEEL_UP) - float(event.button_index == MOUSE_BUTTON_WHEEL_DOWN)
	if delta == 0.0:
		return
	var holder: Control = _event.get_node(CHOICE_HOLDER)
	if holder.visible and holder.get_parent().get_global_rect().has_point(get_global_mouse_position()):
		holder.position.y = clampf(holder.position.y + delta * holder.get_parent().size.y / 3.0, -_scroll_limit, 0.0)
		accept_event()


func _bind_button(target: Control, action: Callable, graphics := "") -> void:
	var previous := target.get_node_or_null("InputButton")
	if previous != null:
		target.remove_child(previous)
		previous.queue_free()
	var button := Button.new()
	button.name = "InputButton"
	button.flat = true
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, empty)
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.add_child(button)
	button.pressed.connect(action)
	if graphics.is_empty():
		return
	var layers: Control = target.get_node(graphics)
	var hover: Control = layers.get_node("Hover")
	var pressed: Control = layers.get_node("Pressed")
	for layer_name in ["Hover", "Hover_Highlight", "Pressed", "Highlight", "Disabled", "SwipeIn"]:
		var layer: Control = layers.get_node_or_null(layer_name)
		if layer != null:
			layer.hide()
	button.mouse_entered.connect(hover.show)
	button.mouse_exited.connect(hover.hide)
	button.button_down.connect(pressed.show)
	button.button_up.connect(pressed.hide)


func _set_reward_icon(card: Control, kind: String, icon: Texture2D, reward_name: String) -> void:
	var holder: Control = card.get_node("Button/RewardHolder")
	holder.show()
	holder.modulate.a = 1.0
	var reward: Control = holder.get_node("ItemSimple" if kind == "item" else "RelicSimple")
	for child: Control in holder.get_children():
		child.visible = child == reward
	var active: Control = reward.get_node("ActiveSlot")
	var image: TextureRect = active.get_node("UnityImage")
	image.texture = icon
	image.show()
	var label_root: Control = reward.get_node("ActiveSlot/NameText" if kind == "item" else "NameText")
	var label: Label = label_root.get_node("UnityText")
	label.text = reward_name

