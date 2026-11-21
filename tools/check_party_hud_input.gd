extends SceneTree

const PHASE := GuildrunEncounter.Phase
const ITEM_BUTTON := "Canvas/Root/CoreGameUI/LeftPanel/ItemButton"
const INVENTORY := "Canvas/Root/CoreGameUI/LeftPanel/ItemReserveUIController"

var _failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var stage := open_stage(false)
	await frames()
	var fight: GuildrunEncounter = stage.encounter
	var roster := fight._ui.get_node_or_null("BottomRoster") as Control
	var sidebar := fight._ui.get_node_or_null("InventorySidebar") as Control
	if not expect(roster != null and sidebar != null, "Actual bottom roster and inventory are mounted"):
		quit(1)
		return
	fight.select_hero(4)
	await frames()
	expect(roster.is_visible_in_tree() and sidebar.is_visible_in_tree(), "First deployment reveals both views")
	expect(visible_cards(roster._active_cards) == 3 and visible_cards(roster._reserve_cards) == 3,
			"First deployment shows three active and three reserve cards")
	var bag := sidebar.get_node(INVENTORY) as Control
	var toggle := sidebar.get_node(ITEM_BUTTON) as Control
	expect(bag.is_visible_in_tree() and sidebar._slots.size() == 7, "First deployment shows seven empty inventory slots")
	click(center(toggle))
	expect(not bag.is_visible_in_tree(), "The mounted inventory button collapses the bag")
	click(center(toggle))
	expect(bag.is_visible_in_tree(), "The mounted inventory button expands the bag")
	fight.start_fight()
	for tick in 2400:
		if fight.phase != PHASE.FIGHT:
			break
		fight._physics_process(fight.BATTLE_STEP_SECONDS)
	fight.open_first_shop()
	var shop := fight.first_shop
	if not expect(is_instance_valid(shop) and shop.buy(3), "Buy the tutorial gem in the real first shop"):
		quit(1)
		return
	expect(shop.items == [119], "The purchased gem is an unequipped inventory instance")
	shop.leave()
	fight.crossroads.select_path(0)
	fight.crossroads.claim()
	fight.crossroads.get_node("Body/Event/Content/Continue").pressed.emit()
	await frames()
	if not expect(fight.phase == PHASE.PLACE and sidebar.is_visible_in_tree() and sidebar._slots[0].index == 0,
			"The second deployment exposes the purchased item in the mounted inventory"):
		quit(1)
		return
	expect(not fight._equipment_panel.is_visible_in_tree(), "The translated sidebar and portraits are the visible item controls")
	var portrait: Control = roster._nodes[int(roster._records[roster._active_cards[0]]._heroIcon)]
	var active_card: Control = roster._active_cards[0]
	expect(roster.card_state(active_card).hero_id == 4, "The target is the owned starter")
	var item_hit: Control = sidebar._slots[0].hit
	click(center(item_hit))
	click(center(portrait))
	await frames()
	expect(shop.equipment(4) == [119] and sidebar._slots[0].index == -1,
			"Clicking the bag item and owned portrait equips the gem and empties the bag slot")
	var equipped: Control = roster._nodes[int(roster._records[active_card].equipment_slots[0].root)]
	if shop.equipment(4) == [119]:
		drag(center(equipped), center(item_hit), fight._equipment_panel)
		await frames()
		expect(shop.equipment(4).is_empty() and sidebar._slots[0].index == 0,
				"Dragging the equipped gem back returns it to the bag")
	# Recover the fixture after a failed return so the independent inbound drag still runs.
	if sidebar._slots[0].index != 0:
		shop.assign_item(0, -1, stage.base_equipment_limit)
		await frames()
	if sidebar._slots[0].index == 0:
		drag(center(item_hit), center(portrait), fight._equipment_panel)
		await frames()
		expect(shop.equipment(4) == [119] and sidebar._slots[0].index == -1,
				"Dragging the bag item onto the owned portrait equips the gem")
	var overhead: Control = fight._bars[fight._hero].get_node(
			"battle_health_barUI/HealthBar/TopBar/HeroItemRows/HeroItemsView_Bottom/ItemSlot_Small_1")
	var overhead_icon: TextureRect = overhead.get_node("ActiveSlot/UnityImage")
	expect(overhead_icon.is_visible_in_tree() and overhead_icon.texture == GuildrunEquipmentPanel.item_texture(stage, 119),
			"Equipment changes update the overhead item icon")
	if shop.equipment(4) == [119]:
		drag(center(overhead), center(item_hit), fight._equipment_panel)
		await frames()
		expect(shop.equipment(4).is_empty() and not overhead_icon.is_visible_in_tree(),
				"Dragging the overhead item to the bag reopens its slot")
	if sidebar._slots[0].index == 0:
		drag(center(item_hit), center(overhead), fight._equipment_panel)
		await frames()
		expect(shop.equipment(4) == [119] and overhead_icon.is_visible_in_tree(),
				"Dragging a bag item onto the overhead slot equips it")
	await verify_capacity_and_resize(fight, sidebar, roster, portrait)
	stage.free()
	await verify_modal()
	if not _failed:
		print("Party HUD input checks passed.")
	quit(int(_failed))


func verify_capacity_and_resize(fight: GuildrunEncounter, sidebar: Control, roster: Control, portrait: Control) -> void:
	var shop := fight.first_shop
	var old_center := center(sidebar.get_node(ITEM_BUTTON))
	root.size = Vector2i(960, 600)
	await frames()
	var toggle_center := center(sidebar.get_node(ITEM_BUTTON))
	var bag := sidebar.get_node(INVENTORY) as Control
	expect(old_center.distance_to(toggle_center) > 20.0, "Resizing moves the rendered inventory button")
	click(old_center)
	expect(bag.is_visible_in_tree(), "The obsolete hit point cannot toggle the resized bag")
	click(toggle_center)
	expect(not bag.is_visible_in_tree(), "The resized hit point collapses the bag")
	click(toggle_center)
	expect(bag.is_visible_in_tree(), "The resized hit point also expands the bag")
	expect(roster.is_visible_in_tree() and portrait.is_visible_in_tree(), "The owned portrait remains interactable after resize")
	# Keep instance zero equipped and inject equal-ID instances to cross the column boundary.
	if shop.equipment(4).is_empty():
		shop.assign_item(0, 4, fight._stage.base_equipment_limit)
	for index in 7:
		shop.items.append(119)
	await frames()
	expect(visible_cards(sidebar._columns) == 2 and sidebar._slots[6].index == 7 and sidebar._slots[7].index == -1,
			"Seven unequipped gems leave a second visible column with empty slots")
	shop.items.append(119)
	await frames()
	expect(visible_cards(sidebar._columns) == 2 and sidebar._slots[7].index == 8,
			"The eighth unequipped gem occupies the resized second column")
	drag(center(sidebar._slots[0].hit), center(portrait), fight._equipment_panel, 1)
	await frames()
	expect(shop.equipped_to.get(0) == 4 and shop.equipped_to.get(1) == 4 and sidebar._slots[0].index == 2,
			"After resizing, the equal-ID gem at index one equips without moving index zero")
	shop.items.resize(2)
	await frames()
	expect(visible_cards(sidebar._columns) == 1 and sidebar._slots[0].index == -1,
			"Zero unequipped items shrink the sidebar to its one visible empty column")


func verify_modal() -> void:
	var stage := open_stage(true)
	await frames()
	var fight: GuildrunEncounter = stage.encounter
	fight._process(0.5)
	for page in 3:
		click(root.get_visible_rect().get_center())
	fight.select_hero(26)
	await frames()
	var sidebar := fight._ui.get_node("InventorySidebar") as Control
	var toggle := sidebar.get_node(ITEM_BUTTON) as Control
	var bag := sidebar.get_node(INVENTORY) as Control
	var tutorial := fight._first_tutorial
	expect(fight.phase == PHASE.PLACE and tutorial.input_locked and bag.is_visible_in_tree(),
			"The real placement tutorial locks input over the expanded inventory")
	click(center(toggle))
	expect(tutorial.input_locked and bag.is_visible_in_tree(),
			"A tutorial caption click does not toggle the inventory behind it")
	click(center(toggle))
	expect(not tutorial.input_locked and bag.is_visible_in_tree(),
			"Closing the last tutorial caption does not toggle the inventory behind it")
	click(center(toggle))
	expect(not bag.is_visible_in_tree(), "The next unlocked click toggles the inventory")
	stage.free()


func open_stage(tutorial: bool) -> Node:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.show_first_fight_tutorial = tutorial
	root.add_child(stage)
	return stage


func frames() -> void:
	await process_frame
	await process_frame


func visible_cards(cards: Array[Control]) -> int:
	var count := 0
	for card in cards:
		if card.is_visible_in_tree():
			count += 1
	return count


func center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func click(point: Vector2) -> void:
	motion(point, Vector2.ZERO, false)
	mouse_button(point, true)
	mouse_button(point, false)


func drag(from: Vector2, to: Vector2, panel: Control, item_index := 0) -> void:
	motion(from, Vector2.ZERO, false)
	mouse_button(from, true)
	var offset := (to - from).normalized() * 14.0
	motion(from + offset, offset, true)
	expect(root.gui_is_dragging() and root.gui_get_drag_data() == {"inventory": panel.get_instance_id(), "index": item_index},
			"Real drag from %s exposes inventory instance %d" % [from, item_index])
	motion(to, to - from - offset, true)
	mouse_button(to, false)
	expect(not root.gui_is_dragging(), "Mouse release finishes the drag")


func motion(point: Vector2, relative: Vector2, pressed: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)


func mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)


func expect(condition: bool, description: String) -> bool:
	if not condition:
		_failed = true
		push_error(description)
	return condition


