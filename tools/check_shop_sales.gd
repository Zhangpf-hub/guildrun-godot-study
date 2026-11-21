extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failed = true


func resolve(fight: GuildrunEncounter) -> void:
	fight.start_fight()
	for frame in 5400:
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			break
		fight._physics_process(1.0 / 30.0)
	fight.open_first_shop()


func motion(at: Vector2, change: Vector2, down: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = change
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(event, true)


func press(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	root.push_input(event, true)


func drag_to_sale(shop: GuildrunFirstShop, button: Button) -> void:
	var start := button.get_global_rect().get_center()
	var end: Vector2 = shop._selling.target.get_global_rect().get_center()
	motion(start, Vector2.ZERO, false)
	press(start, true)
	motion(start + Vector2(14, 0), Vector2(14, 0), true)
	await process_frame
	motion(end, end - start - Vector2(14, 0), true)
	await process_frame
	check(root.gui_is_dragging(), "Shop drag reached viewport")
	press(end, false)
	await process_frame


func verify() -> void:
	root.size = Vector2i(1280, 720)
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	resolve(fight)
	var shop := fight.first_shop
	check(shop.buy(0) and not shop.sell("Hero", 4), "Selling locked in first shop")
	check(shop.buy(3), "First item purchase")
	shop.leave()
	fight.crossroads.select_path(0)
	fight.crossroads.claim()
	fight.crossroads.departed.emit()
	resolve(fight)
	check(shop.buy(0) and shop.choose_specialization(0), "Starter promoted")
	shop._close_rank_picker()
	check(not shop.sell("Hero", 4), "Selling locked in second shop")
	shop.leave()
	var road := fight.crossroads
	road.offers[0] = 1025
	road.select_path(0)
	road.choose_reward(0)
	road.departed.emit()
	resolve(fight)
	if shop.visit != 3 or not is_instance_valid(shop._selling):
		check(false, "Regular shop did not open")
		quit(1)
		return
	check(stage.resale_prices.heroRank == {1: 9, 2: 16, 3: 23, 4: 29}, "Rank resale prices")
	check(stage.resale_prices.itemRarity == {1: 3, 2: 9, 3: 16, 4: 3}, "Item resale prices and fallback")
	var other := shop.roster[1]
	var item := shop.items[0]
	shop.items.append(item)
	shop.items.append(item)
	shop.assign_item(0, 4, 3)
	shop.assign_item(1, other, 3)
	shop.assign_item(2, 4, 3)
	shop._refresh()
	for frame in 4:
		await process_frame
	var balance := shop.shards
	var price := shop.resale_price("Item", 0)
	await drag_to_sale(shop, shop._selling.row.get_child(shop.roster.size()))
	check(shop.shards == balance + price and shop.items.size() == 2 and shop.equipped_to == {0: other, 1: 4},
			"Drop sells only the selected equipped copy")
	await drag_to_sale(shop, shop._selling.row.get_child(0))
	check(shop.shards == balance + price + 16 and shop.roster == [other], "B-rank sale")
	check(shop.equipped_to == {0: other} and shop.items.size() == 2 and not shop.specializations.has(4),
			"Sold hero returns equipment and loses specialization")
	var after := shop.shards
	await drag_to_sale(shop, shop._selling.row.get_child(0))
	var dialogs := shop._selling.find_children("*", "AcceptDialog", false, false)
	check(dialogs.size() == 1 and dialogs[0].visible, "Dropping last hero displays the original warning")
	if not dialogs.is_empty():
		dialogs[0].hide()
	check(not shop.sell("Hero", other) and not shop.sell("Relic", 0) and not shop.sell("Item", 99)
			and shop.shards == after, "Last hero and invalid sales preserve balance")
	shop.leave()
	check(not shop.sell("Item", 0), "Cannot sell after closing the shop")
	fight.crossroads.select_path(0)
	fight.crossroads.departed.emit()
	check(fight.phase == GuildrunEncounter.Phase.PLACE and fight._hero.stat("Id")._sequentialId == other,
			"Remaining hero deploys after selling starter")
	stage.free()
	print("SHOP_SALES checked tutorial gate, native prices, drag targets, equipment ownership and deployment")
	quit(1 if failed else 0)
