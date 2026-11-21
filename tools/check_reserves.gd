extends "check_shop_sales.gd"


func slot_button(fight: GuildrunEncounter, slot: Vector2i) -> Button:
	for button: Button in fight._reserve_panel._slots:
		if fight._reserve_panel._slots[button] == slot:
			return button
	return null


func space() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func drag(start: Vector2, end: Vector2) -> void:
	motion(start, Vector2.ZERO, false)
	press(start, true)
	motion(end, end - start, true)
	await process_frame
	press(end, false)
	await process_frame


func click(point: Vector2) -> void:
	motion(point, Vector2.ZERO, false)
	press(point, true)
	press(point, false)


func dismiss_notice(parent: Node) -> String:
	for window: AcceptDialog in parent.find_children("*", "AcceptDialog", false, false):
		if window.visible:
			var title := window.title
			window.hide()
			return title
	return ""


func verify() -> void:
	root.size = Vector2i(1280, 720)
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	resolve(fight)
	var shop := fight.first_shop
	# Keep the tutorial's real offers and prices. Extra funds let one run exercise the roster cap.
	shop.shards = 500
	for index in 4:
		check(shop.buy(index), "Tutorial purchase %d" % index)
	check(shop.deployed_ids() == [4, 24, 13] and shop.reserve_slots == [26, -1, -1], "Fourth recruit starts on reserve")
	check(shop.assign_item(0, 26, stage.base_equipment_limit), "Equip reserve Kai")
	shop.leave()
	fight.crossroads.select_path(0)
	fight.crossroads.claim()
	fight.crossroads.departed.emit()
	await process_frame
	space()
	for frame in 3:
		await process_frame
	check(fight._reserve_panel.visible and not fight._equipment_panel.visible, "Space opens reserve roster")
	var reserve_title := fight._reserve_toggle.get_global_transform_with_canvas() * (fight._reserve_toggle.size * 0.5)
	check(not fight._fight.get_global_rect().has_point(reserve_title),
			"Reserve title control does not overlap the fight button")
	click(reserve_title)
	check(not fight._reserve_panel.visible, "Clicking the reserve title closes reserve roster")
	click(reserve_title)
	check(fight._reserve_panel.visible, "Clicking the reserve title opens reserve roster")
	var home := fight.board_hero(4).grid_cell
	var idle := fight._next_free_position()
	check(not fight.transfer_hero(Vector2i(-1, 0), idle) and dismiss_notice(fight._ui) == tr("UI.Dialog.Error.NoSpace.Title"), "Reject reserve to vacant hex on full board")
	var cam := root.get_camera_3d()
	var pos := cam.unproject_position(fight.board_hero(4).global_position)
	await drag(slot_button(fight, Vector2i(-1, 0)).get_global_rect().get_center(), pos)
	check(fight.board_hero(4) == null and fight.board_hero(26) != null, "Mouse drag on board exchanges heroes")
	if fight.board_hero(26) == null:
		quit(1)
		return
	check(fight.board_hero(26).grid_cell == home and fight.board_hero(26).stat("Crit") == stage.field(stage._heroes[26], "Crit") + 15,
			"Incoming hero retains equipment")
	var left := fight.board_hero(24).grid_cell
	var right := fight.board_hero(13).grid_cell
	check(fight.transfer_hero(left, right) and fight.board_hero(24).grid_cell == right and fight.board_hero(13).grid_cell == left,
			"Swap occupied board hexes")
	await drag(cam.unproject_position(fight.board_hero(24).global_position), slot_button(fight, Vector2i(-1, 1)).get_global_rect().get_center())
	check(shop.reserve_slots == [4, 24, -1] and fight.board_hero(24) == null, "Drag board hero to empty reserve slot")
	check(fight.transfer_hero(left, Vector2i(-1, 2)), "Field may shrink to one")
	check(fight.transfer_hero(home, Vector2i(-1, 0)) and shop.deployed_ids() == [4], "Last field hero may exchange with occupied reserve")
	check(fight.transfer_hero(Vector2i(-1, 2), left), "Vacant hex accepts a reserve when below cap")
	check(fight.transfer_hero(left, Vector2i(-1, 0)), "Swap second deployed hero with reserve")
	check(fight.transfer_hero(left, Vector2i(-1, 2)), "Bench outgoing hero")
	check(fight.transfer_hero(Vector2i(-1, 2), left), "Return Kai to board")
	check(fight.transfer_hero(Vector2i(-1, 0), Vector2i(-1, 2)) and shop.reserve_slots == [-1, 24, 13], "Reserve reorder preserves holes")
	check(fight.transfer_hero(Vector2i(-1, 1), Vector2i(-1, 2)) and shop.reserve_slots == [-1, 13, 24], "Swap two occupied reserve slots")
	var first_card := slot_button(fight, Vector2i(-1, 1)).get_global_rect().get_center()
	var second_card := slot_button(fight, Vector2i(-1, 2)).get_global_rect().get_center()
	click(first_card)
	click(second_card)
	check(shop.reserve_slots == [-1, 24, 13], "Click selection can exchange two benched heroes")
	click(second_card)
	click(first_card)
	check(shop.reserve_slots == [-1, 13, 24], "Click exchange back preserves slot order")
	await capture(fight)
	var counts := fight.class_play_counts.duplicate()
	for id in shop.deployed_ids():
		var unit := fight.board_hero(id)
		for profession in range(1, 8):
			if unit.has_class(profession):
				counts[profession] = int(counts.get(profession, 0)) + 1
	resolve(fight)
	check(counts == fight.class_play_counts and not fight._reserve_panel.visible, "Only field heroes count for battle")
	shop.leave()
	fight.crossroads.offers[0] = 1025
	fight.crossroads.select_path(0)
	fight.crossroads.choose_reward(0)
	fight.crossroads.departed.emit()
	check(fight.board_hero(4).grid_cell == home and fight.board_hero(26).grid_cell == left, "Next encounter restores exchanged lineup and hexes")
	resolve(fight)
	check(shop.sell("Hero", 24) and shop.sell("Hero", 26), "Sell a reserve and an active hero")
	shop.leave()
	fight.crossroads.select_path(0)
	fight.crossroads.departed.emit()
	check(not fight.transfer_hero(fight.board_hero(4).grid_cell, Vector2i(-1, 0)) and dismiss_notice(fight._ui) == tr("UI.Dialog.Error.CantMoveOnlyHero.Title"),
			"Last deployed hero cannot move to empty reserve")
	stage.free()
	await verify_limit()
	verify_prisms()
	print("RESERVES checked shop capacity, mouse exchanges, blocked moves, ranks, gear, deployed class counts and retained formation")
	quit(1 if failed else 0)


func capture(_fight: GuildrunEncounter) -> void:
	pass


func verify_limit() -> void:
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	resolve(fight)
	var shop := fight.first_shop
	shop.prepare_third(1000, 1)
	shop.stock = ["Hero_24", "Hero_13", "Hero_26", "Hero_14", "Hero_22", "Hero_1"]
	shop.claim_and_open()
	for index in 5:
		check(shop.buy(index), "Purchase %d towards cap" % index)
	var shards := shop.shards
	check(not shop.buy(5) and dismiss_notice(shop) == tr("UI.Dialog.MaxHeroes.Title") and shop.shards == shards and not shop.purchased.has(5), "Rejected seventh purchase is free")
	shop.stock[5] = "Hero_26"
	check(shop.buy(5) and shop.choose_specialization(0) and shop.hero_ranks[26] == 2 and shop.reserve_slots[0] == 26,
			"Benched duplicate upgrades at cap")
	shop._close_rank_picker()
	shop.visit = 3
	check(shop.sell("Hero", 4) and shop.sell("Hero", 24) and shop.sell("Hero", 13) and shop.deployed_ids().is_empty(),
			"Sale preserves assignments when multiple reserves remain")
	shop.leave()
	fight.crossroads.select_path(0)
	fight.crossroads.claim()
	fight.crossroads.departed.emit()
	fight.start_fight()
	check(fight.phase == GuildrunEncounter.Phase.PLACE and fight._fight.disabled and fight._reserve_panel.visible,
			"Empty deployment waits for a reserve")
	check(fight.transfer_hero(Vector2i(-1, 0), Vector2i(3, 1)) and not fight._fight.disabled and fight._hero.rank == 2,
			"Deploy upgraded reserve into an empty formation")
	# This fixture began at tutorial level zero, whose next shop uses fixed starter offers.
	# Finish the sale checks in a prepared regular shop, avoiding the starter-only offer override.
	shop.prepare_third(30, 1)
	shop.claim_and_open()
	check(shop.sell("Hero", 26) and shop.sell("Hero", 14) and shop.deployed_ids() == [22],
			"The sole remaining owned hero is removed from reserve")
	stage.free()


func verify_prisms() -> void:
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	resolve(fight)
	var shop := fight.first_shop
	shop.roster.assign([4, 26, 14, 17, 9, 15])
	shop.hero_ranks = {4: 1, 26: 1, 14: 1, 17: 2, 9: 3, 15: 4}
	shop.specializations = {17: {"class": 6}, 9: {"class": 2}}
	shop.relics.assign([3051, 3052, 3053])
	shop.leave()
	fight.crossroads.select_path(0)
	fight.crossroads.claim()
	fight.crossroads.departed.emit()
	var expected := {"Magic": 40, "ManaRegen": 4, "MaxHealth": 600, "Defense": 90, "Attack": 80, "AttackSpeed": 60}
	check(fight._reserve_bonuses() == expected, "Prisms use both classes and ranks, including innate dual classes")
	var base := {}
	for key: String in expected:
		base[key] = fight._hero.stat(key)
	fight.start_fight()
	for key: String in expected:
		check(fight._hero.stat(key) == int(base[key]) + int(expected[key]), "Prism combat stat " + key)
	check(fight._hero.health == int(base.MaxHealth) + 600 and fight._hero.max_health == fight._hero.health, "Vanguard prism starts with the extra health")
	for unit in fight._units:
		if not unit.is_hero:
			check(not unit.combat_stats.has("Magic"), "Enemies cannot receive player prism effects")
	shop.reserve_slots[0] = 4
	check(fight._reserve_bonuses().get("Crit") == 10 and not fight._reserve_bonuses().has("Magic"), "Assassin prism and class removal")
	stage.free()
