extends HBoxContainer

const NO_SLOT := Vector2i(-2, -2)
const RANK_FRAMES := [402, 589, 521, 359]

var _encounter: GuildrunEncounter
var _slots: Dictionary[Button, Vector2i] = {}


func setup(encounter: GuildrunEncounter) -> void:
	_encounter = encounter
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_theme_constant_override("separation", 18)
	mouse_filter = Control.MOUSE_FILTER_STOP
	refresh()


func refresh(selected := NO_SLOT) -> void:
	_slots.clear()
	var active := _encounter.first_shop.deployed_ids()
	var reserve := _encounter.first_shop.reserve_slots
	for section in 2:
		if get_child_count() <= section:
			var column := VBoxContainer.new()
			add_child(column)
			var title := Label.new()
			title.text = tr("UI.HeroPanel.Active.Title" if section == 0 else "UI.HeroPanel.Reserve.Title")
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(title)
			column.add_child(HBoxContainer.new())
		var row := get_child(section).get_child(1) as HBoxContainer
		var count := int(_encounter._stage.max_deployed) if section == 0 else reserve.size()
		for index in count:
			var id := -1
			var destination := Vector2i(-1, index)
			if section == 0:
				destination = _encounter._next_free_position()
				if index < active.size():
					id = active[index]
					destination = _encounter.board_hero(id).grid_cell
			else:
				id = reserve[index]
			if row.get_child_count() <= index:
				var card := Button.new()
				card.focus_mode = Control.FOCUS_NONE
				card.custom_minimum_size = Vector2(64, 64)
				card.expand_icon = true
				card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				row.add_child(card)
				var border := TextureRect.new()
				border.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				border.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				border.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.add_child(border)
				border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var button := row.get_child(index) as Button
			var frame := button.get_child(0) as TextureRect
			_slots[button] = destination
			frame.visible = id >= 0
			button.self_modulate = Color("ffe3a6") if destination == selected and id >= 0 else Color.WHITE
			if id >= 0:
				var rank := int(_encounter.first_shop.hero_ranks.get(id, 1))
				button.tooltip_text = "%s · %s" % [tr("Heroes.Hero_%d.Name" % id), ["C", "B", "A", "S"][rank - 1]]
				button.icon = _encounter._stage.hero_portrait(id)
				frame.texture = load("res://sprites/sharedassets3_%d.png" % RANK_FRAMES[rank - 1])
			else:
				button.tooltip_text = ""
				button.icon = null
	var minimum := get_combined_minimum_size()
	offset_left = -minimum.x / 2
	offset_right = minimum.x / 2
	offset_top = -20 - minimum.y
	offset_bottom = -20


func slot_at(point: Vector2) -> Vector2i:
	if is_visible_in_tree():
		for button in _slots:
			if button.get_global_rect().has_point(point):
				return _slots[button]
	return NO_SLOT
