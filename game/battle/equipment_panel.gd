class_name GuildrunEquipmentPanel
extends HBoxContainer

signal assignment_changed

var _inventory: GuildrunFirstShop
var _stage: Node3D
var _selected := -1


func setup(inventory: GuildrunFirstShop, stage: Node3D) -> void:
	_inventory = inventory
	_stage = stage
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = 16
	offset_bottom = -20
	add_theme_constant_override("separation", 8)
	minimum_size_changed.connect(_fit)
	_refresh()


func _refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var bag := _column(tr("UI.Common.Items"), -1)
	var heroes := {}
	for hero in _inventory.roster:
		heroes[hero] = _column(tr("Heroes.Hero_%d.Name" % hero), hero)
	for index in _inventory.items.size():
		var owner_id := int(_inventory.equipped_to.get(index, -1))
		var target: VBoxContainer = heroes[owner_id] if owner_id >= 0 else bag
		var item := _inventory.items[index]
		var button := Button.new()
		button.text = tr("Items.Item_%d.Name" % item)
		var bonuses := PackedStringArray()
		for bonus: Dictionary in _stage.field(_stage.items[item], "StatModifications"):
			var stat_id := int(_stage.field(bonus, "TargetStat"))
			bonuses.append("%s +%d" % [tr("UI.Stat.%s.Title" % GuildrunBoardUnit.STAT_NAMES[stat_id]), int(_stage.field(bonus, "Value"))])
		button.tooltip_text = "\n".join(bonuses)
		var icon := item_texture(_stage, item)
		if icon != null:
			button.icon = icon
			button.add_theme_constant_override("icon_max_width", 30)
		button.toggle_mode = true
		button.button_pressed = _selected == index
		button.pressed.connect(select_item.bind(index))
		target.add_child(button)
		button.set_drag_forwarding(item_drag_data.bind(index, button), can_drop_item.bind(owner_id), drop_item.bind(owner_id))
	_fit.call_deferred()


func _fit() -> void:
	var minimum := get_combined_minimum_size()
	offset_top = -20 - minimum.y
	offset_bottom = -20
	offset_right = 16 + minimum.x


func _column(caption: String, hero: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	add_child(column)
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(94, 40)
	column.add_child(button)
	button.pressed.connect(assign_selected_item.bind(hero))
	button.set_drag_forwarding(Callable(), can_drop_item.bind(hero), drop_item.bind(hero))
	return column


static func item_texture(stage: Node3D, item_id: int) -> Texture2D:
	if not is_instance_valid(stage) or not stage.items.has(item_id):
		return null
	var sprite: Dictionary = stage.field(stage.items[item_id], "Icon")
	var path := "res://sprites/sharedassets1_%d.png" % int(sprite.m_PathID)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _select(index: int) -> void:
	select_item(index)


func select_item(index: int) -> void:
	if index < 0 or index >= _inventory.items.size():
		return
	_selected = -1 if _selected == index else index
	_refresh()


func item_drag_data(_position: Vector2, index: int, source: Control) -> Variant:
	if index < 0 or index >= _inventory.items.size():
		return null
	var preview := Label.new()
	preview.text = tr("Items.Item_%d.Name" % _inventory.items[index])
	source.set_drag_preview(preview)
	return {"inventory": get_instance_id(), "index": index}


func can_drop_item(_position: Vector2, data: Variant, hero: int) -> bool:
	if not data is Dictionary or data.get("inventory") != get_instance_id():
		return false
	return _inventory.can_assign(int(data.get("index", -1)), hero, _stage.base_equipment_limit)


func drop_item(position: Vector2, data: Variant, hero: int) -> bool:
	if not can_drop_item(position, data, hero):
		return false
	_selected = int(data.index)
	return assign_selected_item(hero)


func _drop(position: Vector2, data: Variant, hero: int) -> void:
	drop_item(position, data, hero)


func _assign(hero: int) -> void:
	assign_selected_item(hero)


func assign_selected_item(hero: int) -> bool:
	if not _inventory.assign_item(_selected, hero, _stage.base_equipment_limit):
		return false
	_selected = -1
	_refresh()
	assignment_changed.emit()
	return true
