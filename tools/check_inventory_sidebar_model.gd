extends SceneTree

const PHASE := GuildrunEncounter.Phase
var _failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	var sidebar = load("res://battle/inventory_sidebar_model.gd").new()
	sidebar.bind(fight)
	expect(not sidebar.snapshot().visible, "Inventory remains hidden in the starter picker")
	fight.select_hero(4)
	var state: Dictionary = sidebar.snapshot()
	expect(state.visible and state.count == 0, "First deployment exposes the empty inventory")
	expect(state.columns.size() == 1 and state.columns[0].size() == 7, "Empty inventory has exactly seven slots")
	expect(state.columns[0][6] == {"index": -1, "item_id": -1}, "Empty slots have no item instance")

	fight.start_fight()
	expect(sidebar.snapshot().visible, "The inventory stays visible in combat")
	for _tick in 2400:
		if fight.phase != PHASE.FIGHT:
			break
		fight._physics_process(1.0 / 30.0)
	expect(fight.phase == PHASE.RESULT and sidebar.snapshot().visible, "The shown inventory survives the result transition")
	fight.open_first_shop()
	var shop := fight.first_shop
	expect(fight.phase == PHASE.SHOP and sidebar.snapshot().visible, "The inventory is visible in the actual shop")
	if not shop.buy(3):
		expect(false, "Fixture could not purchase its first item")
		stage.free()
		quit(1)
		return
	state = sidebar.snapshot()
	expect(state.count == 1 and state.columns[0][0] == {"index": 0, "item_id": shop.items[0]},
			"A purchased item appears in the first backpack slot")

	if not is_instance_valid(fight._equipment_panel):
		fight._open_equipment()
	var equipment := fight._equipment_panel
	var payload := {"inventory": equipment.get_instance_id(), "index": 0}
	var item_id := shop.items[0]
	expect(GuildrunEquipmentPanel.item_texture(stage, item_id) != null, "The item uses the shared texture resolver")
	expect(GuildrunEquipmentPanel.item_texture(stage, -1) == null, "An unknown item has no texture")
	expect(equipment.can_drop_item(Vector2.ZERO, payload, 4), "The original payload works with the public drop check")
	expect(not equipment.can_drop_item(Vector2.ZERO, {"inventory": 0, "index": 0}, 4), "A foreign drag payload is rejected")
	expect(not equipment.can_drop_item(Vector2.ZERO, {"inventory": equipment.get_instance_id()}, 4), "An incomplete drag payload is rejected")
	expect(equipment.drop_item(Vector2.ZERO, payload, 4), "Public drop interface submits the equipment assignment")
	expect(shop.equipment(4) == [item_id], "The existing drag target equips the item")
	expect(sidebar.snapshot().count == 0, "Equipping removes the item from the backpack projection")
	equipment._drop(Vector2.ZERO, payload, -1)
	expect(shop.equipment(4).is_empty() and sidebar.snapshot().count == 1,
			"The existing drag target also returns the item to the backpack")

	equipment.select_item(0)
	expect(equipment.assign_selected_item(4), "Public click and assignment methods equip the selected instance")
	expect(equipment.drop_item(Vector2.ZERO, payload, -1), "Public drop also returns an item to the backpack")

	for _index in range(6):
		shop.items.append(item_id)
	state = sidebar.snapshot()
	expect(state.columns.size() == 2 and state.columns[1][0].index == -1, "A full column adds a second empty column")
	for index in 7:
		expect(state.columns[0][index].index == index, "Identical item IDs retain distinct instance indices")
	stage.free()
	expect(not sidebar.snapshot().visible, "A freed encounter no longer exposes inventory")
	if not _failed:
		print("Inventory sidebar data checks passed.")
	quit(1 if _failed else 0)


func expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)

