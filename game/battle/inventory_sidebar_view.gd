extends "res://battle/translated_battle_canvas.gd"

const ITEM_VIEW := preload("res://battle/party_item_view.gd")
const SIDEBAR := "Canvas/Root/CoreGameUI/LeftPanel"

var _encounter: GuildrunEncounter
var _model: RefCounted
var _spec: Dictionary
var _panel: Control
var _holder: Control
var _columns: Array[Control] = []
var _slots: Array[Dictionary] = []
var _last_items: Array = []
var _last_owners: Dictionary = {}
var _last_phase := -1
var _opened := true


func bind(encounter: GuildrunEncounter) -> void:
	_encounter = encounter
	_model = load("res://battle/inventory_sidebar_model.gd").new()
	_model.bind(encounter)
	_spec = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/battle_party_ui.json")).inventory
	_panel = get_node(SIDEBAR + "/ItemReserveUIController")
	_holder = _panel.get_node("ItemReserveColumnHolder")
	_holder.get_node("ItemReserveColumn").hide()
	var button_node := get_node(SIDEBAR + "/ItemButton") as Control
	var button := Button.new()
	bind_hit_area(button, button_node, tr("UI.Common.Items"))
	button.pressed.connect(_toggle)
	fit_source_canvas($Canvas)
	refresh()


func _toggle() -> void:
	_opened = not _opened
	_panel.visible = _opened
	get_node(SIDEBAR + "/ItemButton/ButtonActive").visible = _opened


func _process(_delta: float) -> void:
	if is_instance_valid(_encounter):
		refresh()


func refresh() -> void:
	var shop := _encounter.first_shop
	var items: Array = shop.items if is_instance_valid(shop) else []
	var owners: Dictionary = shop.equipped_to if is_instance_valid(shop) else {}
	if _last_phase == _encounter.phase and _last_items == items and _last_owners == owners:
		return
	_last_phase = _encounter.phase
	_last_items = items.duplicate()
	_last_owners = owners.duplicate()
	var snapshot: Dictionary = _model.snapshot()
	visible = snapshot.visible
	if not visible:
		return
	var columns: Array = snapshot.columns
	var spacing := float(_holder.get_meta("layout_spacing"))
	var panel_padding: Vector4 = _panel.get_meta("layout_padding")
	while _columns.size() < columns.size():
		_columns.append(_instantiate_source("res://UI/battle_item_column.tscn", _holder))
	var template_width := 0.0
	for index in _columns.size():
		var column := _columns[index]
		column.visible = index < columns.size()
		if not column.visible:
			continue
		_render_column(index, column, columns[index])
		template_width = (_slots[0].root as Control).size.x
		column.size.x = template_width
		column.position = Vector2(index * (template_width + spacing), (_holder.size.y - column.size.y) * 0.5)
	_holder.size.x = columns.size() * template_width + (columns.size() - 1) * spacing
	_panel.size.x = float(_panel.get_meta("min_width")) + (columns.size() - 1) * (template_width + spacing)
	_holder.position = Vector2(panel_padding.x, (_panel.size.y - _holder.size.y) * 0.5)


func _instantiate_source(path: String, parent: Control) -> Control:
	var wrapper := (load(path) as PackedScene).instantiate()
	var content := wrapper.get_child(0) as Control
	wrapper.remove_child(content)
	wrapper.free()
	parent.add_child(content)
	return content


func _render_column(index: int, column: Control, items: Array) -> void:
	for row in items.size():
		var slot_index := index * items.size() + row
		if slot_index >= _slots.size():
			var slot := _instantiate_source("res://UI/battle_item_slot.tscn", column)
			var button := Button.new()
			bind_hit_area(button, slot, tr("UI.Common.Items"))
			button.pressed.connect(_click_slot.bind(slot_index))
			button.set_drag_forwarding(_start_drag.bind(slot_index, button), _can_drop, _drop)
			_slots.append({"root": slot, "nodes": ITEM_VIEW.index_controls(slot), "hit": button})
		var view: Dictionary = _slots[slot_index]
		var root: Control = view.root
		root.position = Vector2(0.0, row * column.size.y / items.size())
		view["index"] = int(items[row].index)
		var id := int(items[row].item_id)
		var hit: Button = view.hit
		hit.tooltip_text = tr("Items.Item_%d.Name" % id) if id >= 0 else ""
		ITEM_VIEW.show_item(view.nodes, _spec.slot, id, _encounter._stage)


func _click_slot(slot: int) -> void:
	var panel := _encounter._equipment_panel
	if is_instance_valid(panel) and _encounter.phase == GuildrunEncounter.Phase.PLACE:
		var index := int(_slots[slot].index)
		if index >= 0:
			panel.select_item(index)
		else:
			panel.assign_selected_item(-1)


func _start_drag(point: Vector2, slot: int, button: Button) -> Variant:
	var panel := _encounter._equipment_panel
	if is_instance_valid(panel) and _encounter.phase == GuildrunEncounter.Phase.PLACE:
		return panel.item_drag_data(point, int(_slots[slot].index), button)
	return null


func _can_drop(point: Vector2, data: Variant) -> bool:
	var panel := _encounter._equipment_panel
	return is_instance_valid(panel) and _encounter.phase == GuildrunEncounter.Phase.PLACE and panel.can_drop_item(point, data, -1)


func _drop(point: Vector2, data: Variant) -> void:
	if _can_drop(point, data):
		_encounter._equipment_panel.drop_item(point, data, -1)
