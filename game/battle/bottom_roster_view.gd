extends "res://battle/bottom_roster.gd"

const PANEL := "Canvas/Root/CoreGameUI/BottomHeroPanel"
const ITEM_VIEW := preload("res://battle/party_item_view.gd")

var _roster: Dictionary
var _skill_views: Dictionary
var _nodes: Dictionary[int, Control]
var _records: Dictionary[Control, Dictionary] = {}
var _layout_pending := false
var _shop_transfer: GDScript = load("res://battle/shop_party_transfer.gd")


func bind(encounter: GuildrunEncounter) -> void:
	_roster = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/battle_party_ui.json")).roster
	_skill_views = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/bottom_roster_abilities.json")).views
	_nodes = ITEM_VIEW.index_controls(self)
	var active := _source_cards(_roster.active)
	var reserves := _source_cards(_roster.reserve)
	bind_cards(active, reserves)
	card_updated.connect(_render_card)
	for pair: Array in [["ActiveHeroPanel/ActiveTitle", "UI.Battle.Party"], ["HeroReservePanel/ReserveTitle", "UI.Battle.Reserve"]]:
		var label := get_node(PANEL + "/" + pair[0] + "/UnityText") as Label
		label.text = tr(pair[1])
	fit_source_canvas($Canvas)
	setup(encounter)
	_layout_roster()


func _source_cards(section: Dictionary) -> Array[Control]:
	var cards: Array[Control] = []
	for record: Dictionary in section.cards:
		var card := _nodes[int(record.root)]
		_records[card] = record
		cards.append(card)
		card.visibility_changed.connect(_queue_layout)
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.set_drag_forwarding(_drag_shop_hero.bind(card), _can_receive_card.bind(card), _receive_card.bind(card))
	return cards


func _queue_layout() -> void:
	if not _layout_pending:
		_layout_pending = true
		_layout_roster.call_deferred()


func _layout_roster() -> void:
	_layout_pending = false
	var panel := get_node(PANEL) as Control
	var active := _nodes[int(_roster.active.root)]
	var reserves := _nodes[int(_roster.reserve.root)]
	var divider := _nodes[int(_roster.divider)]
	var padding: Vector4 = panel.get_meta("layout_padding")
	var gap := float(panel.get_meta("layout_spacing"))
	var left_width := _layout_section(active, _active_cards)
	var right_width := _layout_section(reserves, _reserve_cards)
	var width := padding.x + left_width + gap * 2 + divider.size.x + right_width + padding.z
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	active.position = Vector2(padding.x, panel.size.y - padding.w - active.size.y)
	divider.position = Vector2(active.position.x + left_width + gap, panel.size.y - padding.w - divider.size.y)
	reserves.position = Vector2(divider.position.x + divider.size.x + gap, panel.size.y - padding.w - reserves.size.y)


func _layout_section(section: Control, cards: Array[Control]) -> float:
	var padding: Vector4 = section.get_meta("layout_padding")
	var gap := float(section.get_meta("layout_spacing"))
	var x := padding.x
	for card in cards:
		if card.visible:
			card.size.x = float(card.get_meta("preferred_width"))
			card.position = Vector2(x, section.size.y - padding.w - card.size.y)
			x += card.size.x + gap
	section.size.x = maxf(padding.x, x - gap) + padding.z
	return section.size.x


func _render_card(card: Control, state: Dictionary) -> void:
	var record := _records[card]
	var occupied := int(state.hero_id) >= 0
	var portrait := _nodes[int(record._heroIcon)]
	portrait.visible = occupied
	var frame := _nodes[int(record._frameImage)].get_node("UnityImage") as TextureRect
	frame.visible = occupied
	frame.texture = load(record.rank_frames[clampi(int(state.rank) - 1, 0, record.rank_frames.size() - 1)])
	if occupied:
		(portrait.get_node("UnityImage") as TextureRect).texture = _encounter._stage.hero_portrait(int(state.hero_id))
	_nodes[int(record._portraitActiveContainer)].visible = occupied
	_nodes[int(record._backupIconContainer)].hide()
	_nodes[int(record._damageIndicatorView)].hide()
	var abilities := _nodes[int(record._abilitiesViewContainer)]
	abilities.visible = occupied
	if occupied:
		_render_abilities(abilities, state.skills, _skill_views.reserve if state.reserve else _skill_views.deployed)
	card.get_node("HeroRoundPortrait/Highlight").visible = state.selected
	_nodes[int(record._itemRowsContainer)].visible = occupied
	if occupied:
		_render_equipment(record, state)


func _render_abilities(panel: Control, skills: Array, source: Dictionary) -> void:
	var slots := ["AbilityViewTop", "AbilityViewLeft", "AbilityViewRight", "AbilityViewBottom"]
	for i in slots.size():
		var cell := panel.get_node(slots[i]) as Control
		var skill: Dictionary = skills[i]
		var icon := cell.get_node("AbilityIcon") as Control
		icon.visible = not skill.is_empty()
		var frame := cell.get_node("Frame/UnityImage") as TextureRect
		var frame_type := str(skill.get("kind", "empty"))
		frame.texture = load(source.slot_render[i].frames[frame_type].texture)
		if icon.visible:
			var image := icon.get_node("UnityImage") as TextureRect
			image.texture = load(skill.icon) if not str(skill.icon).is_empty() else null


func _render_equipment(card: Dictionary, state: Dictionary) -> void:
	var rows: Dictionary[Control, Array] = {}
	var item_indices: Array[int] = []
	var shop := _encounter.first_shop
	if is_instance_valid(shop):
		for item_index: int in shop.equipped_to:
			if int(shop.equipped_to[item_index]) == int(state.hero_id):
				item_indices.append(item_index)
	for index in card.equipment_slots.size():
		var slot: Dictionary = card.equipment_slots[index]
		var node := _nodes[int(slot.root)]
		node.visible = index < int(state.capacity)
		if node.visible:
			var item := int(state.equipment[index]) if index < state.equipment.size() else -1
			ITEM_VIEW.show_item(_nodes, slot, item, _encounter._stage)
			_bind_item_hit(node, item_indices[index] if index < item_indices.size() else -1, state.hero_id)
			var row := node.get_parent() as Control
			if not rows.has(row):
				rows[row] = []
			rows[row].append(node)
	var holder := _nodes[int(card._itemRowsContainer)]
	var bottom := holder.size.y
	for row: Control in rows:
		var slots := rows[row]
		var gap := float(row.get_meta("layout_spacing"))
		var width := -gap
		for slot: Control in slots:
			width += slot.size.x + gap
		row.position = Vector2((holder.size.x - row.size.x) * 0.5, bottom - row.size.y)
		bottom -= row.size.y + float(holder.get_meta("layout_spacing"))
		var x := (row.size.x - width) * 0.5
		for slot: Control in slots:
			slot.position = Vector2(x, (row.size.y - slot.size.y) * 0.5)
			x += slot.size.x + gap


func _bind_item_hit(slot: Control, item_index: int, hero_id: int) -> void:
	var hit := slot.get_node_or_null("InventoryHit") as Button
	if hit == null:
		hit = Button.new()
		hit.name = "InventoryHit"
		bind_hit_area(hit, slot, tr("UI.Common.Items"))
		hit.pressed.connect(_click_item.bind(hit))
		hit.set_drag_forwarding(_drag_item.bind(hit), _can_drop_on_item.bind(hit), _drop_on_item.bind(hit))
	hit.set_meta("item_index", item_index)
	hit.set_meta("hero_id", hero_id)
	hit.visible = is_instance_valid(_encounter._equipment_panel) or (item_index >= 0 and is_instance_valid(_shop_selling()))


func _click_item(hit: Button) -> void:
	var panel := _encounter._equipment_panel
	if not is_instance_valid(panel) or _encounter.phase != GuildrunEncounter.Phase.PLACE:
		return
	var index := int(hit.get_meta("item_index"))
	if index >= 0:
		panel.select_item(index)
	else:
		panel.assign_selected_item(int(hit.get_meta("hero_id")))


func _drag_item(point: Vector2, hit: Button) -> Variant:
	var panel := _encounter._equipment_panel
	var index := int(hit.get_meta("item_index"))
	if is_instance_valid(panel) and _encounter.phase == GuildrunEncounter.Phase.PLACE:
		return panel.item_drag_data(point, index, hit)
	var selling := _shop_selling()
	var shop := _encounter.first_shop
	if is_instance_valid(selling) and index >= 0 and index < shop.items.size():
		return selling.begin_drag("Item", index, hit, GuildrunEquipmentPanel.item_texture(_encounter._stage, shop.items[index]))
	return null


func _can_drop_on_item(point: Vector2, data: Variant, hit: Button) -> bool:
	var panel := _encounter._equipment_panel
	return is_instance_valid(panel) and _encounter.phase == GuildrunEncounter.Phase.PLACE and panel.can_drop_item(point, data, int(hit.get_meta("hero_id")))


func _drop_on_item(point: Vector2, data: Variant, hit: Button) -> void:
	if _can_drop_on_item(point, data, hit):
		_encounter._equipment_panel.drop_item(point, data, int(hit.get_meta("hero_id")))


func try_equip_at(point: Vector2) -> bool:
	var panel := _encounter._equipment_panel
	if not is_visible_in_tree() or not is_instance_valid(panel) or panel._selected < 0:
		return false
	for card in _records:
		if card.is_visible_in_tree() and card.get_global_rect().has_point(point):
			var id := int(card_state(card).get("hero_id", -1))
			return id >= 0 and panel.assign_selected_item(id)
	return false


func _shop_selling() -> Control:
	var shop := _encounter.first_shop
	if _encounter.phase == GuildrunEncounter.Phase.SHOP and is_instance_valid(shop):
		return shop._selling
	return null


func _can_move_shop_party() -> bool:
	var shop := _encounter.first_shop
	return _encounter.phase == GuildrunEncounter.Phase.SHOP and is_instance_valid(shop) \
			and shop._claimed and not shop._departed and shop._rank_picker == null and not shop.has_pending_rank_modifier()


func _shop_slot(state: Dictionary) -> Vector2i:
	return Vector2i(1 if state.reserve else 0, int(state.index))


func _drag_shop_hero(_point: Vector2, card: Control) -> Variant:
	var selling := _shop_selling()
	var state := card_state(card)
	var hero := int(state.get("hero_id", -1))
	if not _can_move_shop_party() or hero < 0:
		return null
	var texture: Texture2D = _encounter._stage.hero_portrait(hero)
	if is_instance_valid(selling):
		return selling.begin_drag("Hero", hero, card, texture, _shop_slot(state))
	var preview := TextureRect.new()
	preview.texture = texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = Vector2(40, 40)
	card.set_drag_preview(preview)
	return {"roster": get_instance_id(), "kind": "Hero", "key": hero, "roster_slot": _shop_slot(state)}


func _can_receive_card(point: Vector2, data: Variant, card: Control) -> bool:
	var selling := _shop_selling()
	if _can_move_shop_party() and data is Dictionary and data.get("kind") == "Hero":
		if (is_instance_valid(selling) and selling.accepts_drag(data)) or data.get("roster") == get_instance_id():
			var state := card_state(card)
			return not state.is_empty() and _shop_transfer.can_move(_encounter.first_shop, data.roster_slot,
					_shop_slot(state), int(data.key))
	return _can_receive_item(point, data, card)


func _receive_card(point: Vector2, data: Variant, card: Control) -> void:
	if not _can_receive_card(point, data, card):
		return
	if _encounter.phase == GuildrunEncounter.Phase.SHOP:
		var shop := _encounter.first_shop
		var target := _shop_slot(card_state(card))
		if _shop_transfer.is_last_active_drop(shop, data.roster_slot, target):
			var dialog := AcceptDialog.new()
			dialog.name = "LastActiveHeroNotice"
			dialog.title = tr("UI.Dialog.Error.CantMoveOnlyHero.Title")
			dialog.dialog_text = tr("UI.Dialog.Error.CantMoveOnlyHero.Description")
			add_child(dialog)
			dialog.visibility_changed.connect(func() -> void:
				if not dialog.visible:
					dialog.queue_free())
			dialog.popup_centered()
			return
		_shop_transfer.move(shop, _encounter._formation, data.roster_slot, target, int(data.key))
		refresh()
	else:
		_receive_item(point, data, card)


func _can_receive_item(point: Vector2, data: Variant, card: Control) -> bool:
	var panel := _encounter._equipment_panel
	var hero := int(card_state(card).get("hero_id", -1))
	return hero >= 0 and _encounter.phase == GuildrunEncounter.Phase.PLACE and is_instance_valid(panel) and panel.can_drop_item(point, data, hero)


func _receive_item(point: Vector2, data: Variant, card: Control) -> void:
	if _can_receive_item(point, data, card):
		_encounter._equipment_panel.drop_item(point, data, int(card_state(card).hero_id))
