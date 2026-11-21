extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.show_first_fight_tutorial = false
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	fight._create_party()
	var shop := fight.first_shop
	shop.roster.assign([4, 14, 26])
	shop.hero_ranks = {4: 1, 14: 1, 26: 1}
	shop.reserve_slots.assign([-1, 26, -1])
	shop.items.assign([119, 119])
	shop.equipped_to[0] = 26
	shop.equipped_to[1] = 4
	shop.visit = 2
	shop.prepare_third(0, 0)
	fight.phase = GuildrunEncounter.Phase.SHOP
	shop.claim_and_open()
	var view: Control = fight._bottom_roster
	await process_frame
	await process_frame
	var active: Array[Control] = view._active_cards
	var reserve: Array[Control] = view._reserve_cards
	drag(avatar(view, active[0]), avatar(view, active[1]), true)
	expect(shop.deployed_ids() == [4, 14], "Dropping active on active does not reorder")
	drag(avatar(view, reserve[1]), center(reserve[2]), true)
	expect(shop.reserve_slots == [-1, -1, 26], "Reserve drop preserves exact holes")
	drag(avatar(view, reserve[2]), avatar(view, active[0]), true)
	expect(shop.deployed_ids() == [14, 26] and shop.reserve_slots == [-1, -1, 4],
			"A reserve hero can replace an active hero without changing registration order")
	expect(shop.equipment(26) == [119], "Equipment moves with its hero")
	drag(avatar(view, active[0]), center(reserve[0]), true)
	expect(shop.deployed_ids() == [26] and shop.reserve_slots == [14, -1, 4], "Active can move into a free reserve slot")
	drag(avatar(view, active[0]), center(reserve[1]), true)
	expect(shop.deployed_ids() == [26] and shop.reserve_slots == [14, -1, 4], "The last active hero cannot enter an empty reserve slot")
	var notice := view.get_node_or_null("LastActiveHeroNotice") as AcceptDialog
	expect(is_instance_valid(notice) and notice.visible, "An illegal last-active drop opens the localized notice")
	if is_instance_valid(notice):
		notice.hide()
	await process_frame
	drag(avatar(view, reserve[0]), center(active[1]), true)
	expect(shop.deployed_ids() == [14, 26] and shop.reserve_slots == [-1, -1, 4],
			"An empty active card promotes the reserve hero and leaves its reserve hole")

	var modal := Control.new()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	fight._ui.add_child(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drag(avatar(view, reserve[2]), center(reserve[1]), false)
	expect(shop.reserve_slots == [-1, -1, 4], "A modal intercepts pointer input")
	modal.queue_free()
	await process_frame

	var sale_target: Control = shop._selling.target
	var equipped_card := reserve[2]
	var item_slot: Dictionary = view._records[equipped_card].equipment_slots[0]
	var item_hit: Control = view._nodes[int(item_slot.root)].get_node("InventoryHit")
	var item_price := shop.resale_price("Item", 1)
	var balance := shop.shards
	drag(center(item_hit), center(sale_target), true)
	expect(shop.items == [119] and shop.equipped_to == {0: 26} and shop.shards == balance + item_price,
			"Dragging the second equipped copy sells that exact instance and preserves the identical first copy")
	var price := shop.resale_price("Hero", 26)
	var prior := shop.shards
	drag(avatar(view, active[1]), center(sale_target), true)
	expect(shop.roster == [4, 14] and shop.shards == prior + price and shop.equipped_to.is_empty() and shop.items == [119],
			"Selling the hero from the roster pays the correct price and leaves its gear unequipped")

	var row_offer: Control = shop._selling.row.get_child(2)
	# The existing selling row rebuilds on sale and gets its size on the next pass.
	await process_frame
	drag(center(row_offer), center(sale_target), true)
	expect(shop.items.is_empty(), "Existing shop row sale still uses ordinary drop acceptance")
	if not failed:
		print("Regular shop roster pointer checks passed")
	quit(int(failed))


func avatar(view: Control, card: Control) -> Vector2:
	return center(view._nodes[int(view._records[card]._heroIcon)])


func center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func drag(from: Vector2, to: Vector2, expected_drag: bool) -> void:
	motion(from, Vector2.ZERO, false)
	mouse_button(from, true)
	var offset := (to - from).normalized() * 16
	motion(from + offset, offset, true)
	expect(root.gui_is_dragging() == expected_drag, "Pointer drag begins only from an unobstructed origin at %s" % from)
	motion(to, to - from - offset, true)
	mouse_button(to, false)


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


func expect(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error(description)
