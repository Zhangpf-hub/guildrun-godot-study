extends ScrollContainer

var shop: GuildrunFirstShop
var target: Control
var row := HBoxContainer.new()
var held := {}
var revision := 0


func setup(inventory: GuildrunFirstShop, selling_panel: Control) -> void:
	shop = inventory
	target = selling_panel
	position = Vector2(32, 71)
	size = Vector2(1270, 45)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	target.show()
	target.mouse_filter = Control.MOUSE_FILTER_STOP
	target.set_drag_forwarding(Callable(), _can_drop, _drop)
	target.mouse_entered.connect(_show_state)
	target.mouse_exited.connect(_show_state)
	target.get_node("InactiveFill").set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.get_node("InactiveFill/InactiveText").set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.get_node("InactiveFill/InactiveText").offset_left = 98
	target.get_node("InactiveFill/InactiveText/UnityText").text = tr("UI.Battle.ShopPanel.DropToSell")


func refresh() -> void:
	revision += 1
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for id: int in shop.roster:
		var name_text := shop._entry_name("Hero", id)
		var rank := int(shop.hero_ranks.get(id, 1))
		if rank > 1:
			name_text += " (%s)" % ["C", "B", "A", "S"][clampi(rank - 1, 0, 3)]
		_add_button("Hero", id, name_text)
	for index in shop.items.size():
		_add_button("Item", index, shop._entry_name("Item", shop.items[index]))
	for id: int in shop.relics:
		var label := Label.new()
		label.text = shop._entry_name("Relic", id)
		row.add_child(label)


func _add_button(kind: String, key: int, caption: String) -> void:
	var button := Button.new()
	button.text = caption
	var item_id := key if kind == "Hero" else shop.items[key]
	var offer: Dictionary = shop._data.catalog.get("%s_%d" % [kind, item_id], {})
	var icon_path: String = offer.get("icon", "")
	if icon_path.is_empty() and kind == "Item":
		var sprite: Dictionary = shop.battle_stage.field(shop.battle_stage.items[item_id], "Icon")
		icon_path = "res://sprites/sharedassets1_%d.png" % int(sprite.m_PathID)
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		button.icon = load(icon_path)
		button.expand_icon = true
		button.custom_minimum_size.x = button.get_theme_font("font").get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT,
				-1, button.get_theme_font_size("font_size")).x + 46
		button.add_theme_constant_override("icon_max_width", 25)
	var allowed := kind != "Hero" or shop.roster.size() > 1
	button.tooltip_text = ("%s · %s %d" % [tr("UI.Battle.ShopPanel.DropToSell"),
			tr("UI.BattleInfo.Shards.Title"), shop.resale_price(kind, key)]
			if allowed else tr("UI.Dialog.Error.CantSellOnlyHero.Description"))
	row.add_child(button)
	button.set_drag_forwarding(_drag.bind(kind, key, button), Callable(), Callable())


func _drag(_position: Vector2, kind: String, key: int, button: Button) -> Variant:
	return begin_drag(kind, key, button, button.icon)


func begin_drag(kind: String, key: int, control: Control, texture: Texture2D,
		roster_slot: Vector2i = Vector2i(-1, -1)) -> Variant:
	if not can_interact() or shop.resale_price(kind, key) < 0:
		return null
	var preview := Control.new()
	var icon := TextureRect.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(16, 16)
	icon.size = Vector2(40, 40)
	preview.add_child(icon)
	control.set_drag_preview(preview)
	held = {"shop": get_instance_id(), "revision": revision, "kind": kind, "key": key,
			"roster_slot": roster_slot}
	_show_state()
	return held


func _show_state() -> void:
	var dragging := not held.is_empty()
	target.get_node("InactiveFill").visible = not dragging
	target.get_node("OpenFill").visible = dragging
	if dragging:
		var over := target.get_global_rect().has_point(target.get_global_mouse_position())
		target.get_node("OpenFill/ActiveFill").visible = over
		target.get_node("OpenFill/ActiveText/UnityText").text = "%s %d" % [tr("UI.BattleInfo.Shards.Title"),
				shop.resale_price(held.kind, held.key)]


func can_interact() -> bool:
	return is_visible_in_tree() and shop.regular_stock and shop._claimed and not shop._departed \
			and shop._rank_picker == null and not shop.has_pending_rank_modifier()


func accepts_drag(data: Variant) -> bool:
	return can_interact() and not held.is_empty() and data is Dictionary and data == held and data.get("revision") == revision


func _can_drop(_position: Vector2, data: Variant) -> bool:
	return accepts_drag(data)


func _drop(position_in_target: Vector2, data: Variant) -> void:
	if not _can_drop(position_in_target, data):
		return
	if data.kind == "Hero" and shop.roster.size() == 1:
		var message := AcceptDialog.new()
		message.title = tr("UI.Dialog.Error.CantSellOnlyHero.Title")
		message.dialog_text = tr("UI.Dialog.Error.CantSellOnlyHero.Description")
		add_child(message)
		message.visibility_changed.connect(func():
			if not message.visible:
				message.queue_free())
		message.popup_centered()
	else:
		shop.sell(data.kind, data.key)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not held.is_empty():
		held = {}
		_show_state()
