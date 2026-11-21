extends Control

const CANVAS_SCRIPT := preload("res://battle/translated_battle_canvas.gd")
const PANEL_PATH := "Canvas/Root/CoreGameUI/RankModifierPicker"
const BODY := "Root/Mask/BodyPanel/"

var _shop: GuildrunFirstShop
var _hero: int
var _rank: int
var _before: Dictionary
var _old_capacity: int
var _data: Dictionary
var _sheet: Control
var _panel: Control
var _holder: Control
var _hero_card: Control
var _next: Control
var _choices: Array[Control] = []
var _movement: Tween


func present(shop: GuildrunFirstShop, hero: int, rank: int, offers: Array[int]) -> void:
	if _movement and _movement.is_valid():
		_movement.kill()
	if is_instance_valid(_sheet) and resized.is_connected(_sheet._resize_canvas):
		resized.disconnect(_sheet._resize_canvas)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_choices.clear()
	_shop = shop
	_hero = hero
	_rank = rank
	_before = _stats()
	_old_capacity = shop.equipment_limit(hero)
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/rank_modifier_display.json"))
	show()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.035, 0.03, 0.055, 0.91)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_sheet = (load("res://UI/rank_modifier_picker.tscn") as PackedScene).instantiate()
	_sheet.set_script(CANVAS_SCRIPT)
	add_child(_sheet)
	_sheet.fit_source_canvas(_sheet.get_node("Canvas"))
	_panel = _sheet.get_node(PANEL_PATH)
	_panel.show()
	_panel.modulate.a = 1.0
	_holder = _panel.get_node("RankModifierChoiceHolder")
	_hero_card = _holder.get_node("HeroCardPanel/HeroCard")
	_setup_hero()
	_update_hero(_rank, _before)
	var banner: Control = _panel.get_node("TopBanner")
	banner.show()
	banner.modulate.a = 1.0
	banner.offset_top = 0
	banner.offset_bottom = 132
	var heading: Label = banner.get_node("TitleText/UnityText")
	heading.text = "RANK UP"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next = _panel.get_node("PrimaryButton")
	for part in ["Hover", "Pressed", "Disabled", "Highlight", "VFX_Button_Chosen"]:
		_next.get_node("Button_Graphics/" + part).hide()
	var caption := tr("UI.Common.Continue")
	_next.get_node("Text (TMP)/UnityText").text = caption
	var finish := _hit(_next, "RankContinue", caption)
	finish.pressed.connect(hide)
	_next.hide()
	var hero_panel: Control = _holder.get_node("HeroCardPanel")
	var left := hero_panel.size.x + float(_data.hero_gap)
	for index in offers.size():
		var choice := _add_choice(index, _data.entries[str(offers[index])])
		choice.position = Vector2(left, (_holder.size.y - choice.size.y) * 0.5)
		left += choice.size.x + float(_data.spacing)
	var width := left - float(_data.spacing)
	_holder.offset_left = -width / 2.0
	_holder.offset_right = width / 2.0


func _stats() -> Dictionary:
	return _shop.battle_stage.hero_stats(_hero, _shop.hero_modifiers.get(_hero, []), _shop.equipment(_hero),
			_shop.relics, int(_shop.hero_ranks[_hero]), _shop.specializations.get(_hero, {}), _shop.rank_modifiers_for(_hero))


func _setup_hero() -> void:
	for path in ["Mask/UnityImage", "Root/Mask/UnityImage", "Root/FrameBreakPortrait", "Root/CompendiumButton",
			"Root/AbilityPanel", "Root/HeroBasicInfoPanel", "HeroClasses", "HeroArchetypes", "ValuePanel", "RankUpInfo",
			"StatusEffectPanel", BODY + "DynamicStatsHolderPanel", BODY + "DamageText"]:
		var part := _hero_card.get_node_or_null(path) as Control
		if part:
			part.hide()
	# The native preview samples the expanded HeroCard_Hover clip at normalized time 1.
	for track: Dictionary in _data.hero_open_pose:
		var control: Control = _hero_card.get_node(track.path)
		var anchored := float(track.value)
		match String(track.property):
			"m_Alpha":
				control.modulate.a = anchored
			"m_AnchoredPosition.x":
				var dx := control.offset_right - control.offset_left
				control.offset_left = anchored - control.pivot_offset_ratio.x * dx
				control.offset_right = control.offset_left + dx
			"m_AnchoredPosition.y":
				var dy := control.offset_bottom - control.offset_top
				control.offset_top = -anchored - control.pivot_offset_ratio.y * dy
				control.offset_bottom = control.offset_top + dy
	var portraits: Dictionary = _data.portraits[str(_hero)]
	var normal: String = portraits.PortraitSpritesPerRank[_rank - 1] if portraits.PortraitSpritesPerRank.size() >= _rank else ""
	var breakout: String = portraits.BreakoutPortraitSpritesPerRank[_rank - 1] if portraits.BreakoutPortraitSpritesPerRank.size() >= _rank else ""
	if normal.is_empty():
		normal = portraits.fallback
	if not normal.is_empty():
		_set_image(_hero_card.get_node("Mask/Portrait/UnityImage"), normal)
	_hero_card.get_node("Mask").visible = breakout.is_empty()
	var overlay: Control = _hero_card.get_node("Root/FrameBreakPortrait")
	overlay.visible = not breakout.is_empty()
	if overlay.visible:
		_set_image(overlay.get_node("UnityImage"), breakout)
	_hero_card.get_node(BODY + "NamePanel/HeroNameText/UnityText").text = tr("Heroes.Hero_%d.Name" % _hero)


func _update_hero(rank: int, stats: Dictionary) -> void:
	var controls := _hero_card.find_children("*", "Control", true, false)
	for entry: Dictionary in _data.hero_frames.values():
		for node: Control in controls:
			if int(node.get_meta("unity_id", 0)) == int(entry.node):
				_set_image(node.get_node("UnityImage"), entry.textures[rank - 1])
				break
	_update_equipment()
	var bars: Control = _hero_card.get_node(BODY + "BarPanel")
	bars.get_node("HealthBarStatPanel/HealthBar/Text (TMP)/UnityText").text = str(_value(stats, "MaxHealth"))
	bars.get_node("ManaBarStatPanel/ManaBar/Text (TMP)/UnityText").text = str(_value(stats, "MaxMana"))
	bars.get_node("ManaBarStatPanel/SingleStatPanel_MR/StatValueText/UnityText").text = str(_value(stats, "ManaRegen"))
	var keys := {"Attack": "Attack", "Magic": "Magic", "AtkSpd": "AttackSpeed", "Crit": "Crit", "Def": "Defense",
			"Range": "AttackRange", "Omnivamp": "OmniVamp", "HPRegen": "HPPerSecond", "DamageAmp": "DamageAmp",
			"BaseTrueDamage": "BaseTrueDamage", "BonusTrueDamage": "BonusTrueDamage"}
	var stats_panel: Control = _hero_card.get_node(BODY + "StatsHolderPanel")
	stats_panel.get_node("SingleStatPanel").hide()
	for key: String in keys:
		var cell: Control = stats_panel.get_node("SingleStatPanel_" + key)
		cell.get_node("StatValueText/UnityText").text = str(_value(stats, keys[key]))


func _update_equipment() -> void:
	var panel: Control = _hero_card.get_node(BODY + "EquipmentHolderPanel")
	var slots := panel.find_children("ItemPlaceholderSlot*", "Control", false, false)
	var capacity := _shop.equipment_limit(_hero)
	var items := _shop.equipment(_hero)
	while slots.size() < capacity:
		var copy := slots[0].duplicate() as Control
		panel.add_child(copy)
		slots.append(copy)
	for index in slots.size():
		var slot := slots[index] as Control
		slot.visible = index < capacity
		if not slot.visible:
			continue
		var width := slot.size.x
		var gap := float(panel.get_meta("layout_spacing", 0))
		slot.position.x = (panel.size.x - (width * capacity + gap * (capacity - 1))) * 0.5 + (width + gap) * index
		slot.get_node("EmptySlotBackground").visible = index >= items.size()
		slot.get_node("ActiveSlot").visible = index < items.size()
		slot.get_node("RankFrame").visible = index < items.size()
		for path in ["ActiveSlot/NameText", "HoveringSlot", "CounterPanel"]:
			slot.get_node(path).hide()
		if index < items.size():
			slot.get_node("ActiveSlot/UnityImage").texture = GuildrunEquipmentPanel.item_texture(_shop.battle_stage, items[index])


func _value(stats: Dictionary, key: String) -> int:
	var value: Variant = stats.get("<%s>k__BackingField" % key, 0)
	if value is Dictionary:
		return int(value.get("RawValue", 0)) >> 16
	return int(value)


func _set_image(image: Control, resource: String) -> void:
	if "texture" in image:
		image.set("texture", load(resource))
		image.queue_redraw()


func _hit(parent: Control, id: String, caption: String) -> Button:
	var button := Button.new()
	button.name = id
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	_sheet.bind_hit_area(button, parent, caption)
	return button


func _add_choice(index: int, entry: Dictionary) -> Control:
	var shell: Control = (load("res://UI/rank_modifier_choice.tscn") as PackedScene).instantiate()
	_holder.add_child(shell)
	shell.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	var card: Control = shell.get_node("RankModifierChoiceView")
	var width := card.size.x
	card.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var title_box: Control = card.get_node("TitleContainer")
	var body_box: Control = card.get_node("BodyContainer")
	title_box.get_node("SubtitlePanel").hide()
	var title: Label = title_box.get_node("ModifierTitleText/UnityText")
	var body: Label = body_box.get_node("MiddleContainer/ModifierDescription/UnityText")
	var pad: Vector4 = card.get_meta("layout_padding")
	var gap := float(card.get_meta("layout_spacing"))
	var inner_width := width - pad.x - pad.z
	title.text = tr(entry.name)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.text = _description(entry)
	var styled := RichTextLabel.new()
	styled.name = "KeywordText"
	styled.bbcode_enabled = true
	styled.scroll_active = false
	styled.mouse_filter = Control.MOUSE_FILTER_IGNORE
	styled.add_theme_font_override("normal_font", body.get_theme_font("font"))
	styled.add_theme_font_size_override("normal_font_size", body.get_theme_font_size("font_size"))
	styled.add_theme_color_override("default_color", body.get_theme_color("font_color"))
	styled.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	styled.text = _description(entry, true)
	body.add_child(styled)
	styled.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	body.self_modulate.a = 0.0
	for label in [title, body]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var y := pad.y
	# RectTransforms driven by Unity's preferred-size fitter have zero serialized extents.
	for pair in [[title_box, title], [body_box, body]]:
		var box: Control = pair[0]
		var label: Label = pair[1]
		box.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
		box.position = Vector2(pad.x, y)
		var ancestor := label.get_parent() as Control
		while ancestor != box:
			ancestor.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			ancestor = ancestor.get_parent() as Control
		box.size = Vector2(inner_width, 1)
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		box.size.y = ceilf(font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
				inner_width, font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y)
		y += box.size.y + gap
	shell.size = Vector2(width, y - gap + pad.w)
	card.get_node("Icon/IconReference_1/UnityImage").texture = load(entry.icon)
	for pair in [["InnerBorder", "_rarityInnerFrameSprites"], ["OuterBorder", "_rarityOuterFrameSprites"], ["Icon/Frame", "_rarityiconFrame"]]:
		_set_image(card.get_node(pair[0] + "/UnityImage"), _data.frames[pair[1]][_rank - 1])
	var hit := _hit(card, "RankChoice%d" % index, title.text)
	for path in ["InnerBorder_Highlight", "OuterBorder_Highlight", "Icon/Icon_Highlight"]:
		var highlight: Control = card.get_node(path)
		hit.mouse_entered.connect(highlight.show)
		hit.mouse_exited.connect(highlight.hide)
	hit.pressed.connect(_choose.bind(index))
	_choices.append(shell)
	return shell


func _description(entry: Dictionary, styled := false) -> String:
	var text := tr(entry.description).format(entry.variables)
	var markup := RegEx.create_from_string("\\[([^\\]]*)\\]<([^>]+)>")
	for match_row in markup.search_all(text):
		var content := match_row.get_string(1)
		if match_row.get_string(2).begins_with("statcalc"):
			content = _formula(content)
		var color: String = _data.keyword_colors.get(match_row.get_string(2), "")
		if styled and not color.is_empty():
			content = "[color=%s]%s[/color]" % [color, content]
		text = text.replace(match_row.get_string(), content)
	return text


func _formula(expression: String) -> String:
	var value := 0.0
	for part in expression.split("+"):
		if part.is_valid_float():
			value += part.to_float()
			continue
		var term := part.split("_")
		if term.size() != 2:
			return expression
		var coefficient := term[0].split("/")
		var stat := _value(_before, term[1])
		if term[1] == "Rank":
			value += coefficient[0].to_float() * (_rank - 1)
		elif coefficient.size() == 2:
			value += floorf(stat / coefficient[1].to_float()) * coefficient[0].to_float()
		else:
			value += stat * coefficient[0].to_float() / 100.0
	return str(floori(value))


func _choose(index: int) -> void:
	if not _shop.choose_rank_modifier(index):
		return
	var after := _stats()
	for card in _choices:
		card.hide()
	_update_hero(_rank, after)
	_shop.battle_stage.sound.play_ui(9)
	var hp: Control = _holder.get_node("HeroCardPanel")
	var target := (_holder.size.x - hp.size.x) * 0.5
	_movement = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_movement.tween_property(hp, "position:x", target, float(_data.movement.duration))
	_movement.tween_callback(_show_result.bind(after))


func _show_result(after: Dictionary) -> void:
	var changes := PackedStringArray()
	for key: String in GuildrunBoardUnit.STAT_NAMES.values():
		var old_value := _value(_before, key)
		var new_value := _value(after, key)
		if old_value != new_value:
			changes.append("%s   %d → %d" % [tr("UI.Stat.%s.Title" % key), old_value, new_value])
	var capacity := _shop.equipment_limit(_hero)
	if capacity != _old_capacity:
		changes.append("%s   %d → %d" % [tr("UI.RankUp.ItemSlots"), _old_capacity, capacity])
	var info: Control = _hero_card.get_node("RankUpInfo")
	for child in info.get_children():
		if child is CanvasItem:
			child.hide()
	info.show()
	var label := Label.new()
	label.text = "\n".join(changes)
	label.add_theme_font_size_override("font_size", 22)
	info.add_child(label)
	_next.show()
	_next.modulate.a = 1.0
