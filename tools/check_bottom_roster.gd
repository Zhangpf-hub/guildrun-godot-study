extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failed = true


func verify() -> void:
	root.size = Vector2i(1280, 720)
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	var panel := Control.new()
	panel.set_script(load("res://battle/bottom_roster.gd"))
	fight._ui.add_child(panel)
	var active := make_cards(panel, 30)
	var reserve := make_cards(panel, 110)
	panel.bind_cards(active, reserve)
	panel.setup(fight)
	check(not panel.visible, "Roster is hidden before selecting a hero")
	fight.select_hero(4)
	panel.refresh()
	check(panel.visible and panel.card_state(active[0]).hero_id == 4, "Starter binds to the first active card")
	check(stage.max_deployed == 3 and stage.max_total_heroes == 6, "Initial run has three active and three reserve slots")
	check(reserve[2].visible and not reserve[3].visible, "Reserve cards follow the initial capacity")
	check(panel.card_state(active[0]).rank == 1, "Starter rank is one-based")
	var skills_api := load("res://battle/bottom_roster_abilities.gd")
	for starter: Vector2i in [Vector2i(4, 4), Vector2i(14, 14), Vector2i(26, 28)]:
		var slots: Array[Dictionary] = skills_api.slots_for(starter.x)
		check(slots.size() == 4 and slots[0].kind == "active" and slots[0].id == starter.y
				and slots[1].is_empty() and slots[2].is_empty() and slots[3].is_empty(),
				"Starter %d displays its authored starting skill only" % starter.x)
	check(panel.card_state(active[0]).skills == skills_api.slots_for(4), "Starter skill display has no shop dependency")
	check(panel.card_state(active[0]).capacity == stage.base_equipment_limit, "Starter equipment capacity needs no shop")
	check(not active[int(stage.max_deployed)].visible, "Cards beyond deployment capacity are hidden")
	fight.start_fight()
	panel.refresh()
	check(panel.visible and panel.slot_at(active[0].get_global_rect().get_center()) == Vector2i(-2, -2),
			"Battle keeps the cards visible and disables placement targets")
	for step in 5400:
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			break
		fight._physics_process(1.0 / 30.0)
	fight.open_first_shop()
	var shop := fight.first_shop
	shop.shards = 500
	for index in 4:
		check(shop.buy(index), "Buy tutorial offer %d" % index)
	panel.refresh()
	check(panel.card_state(reserve[0]).hero_id == 26, "Fourth recruit appears in reserve")
	check(panel.card_state(reserve[0]).skills == skills_api.slots_for(26), "Reserve displays the same starter slots")
	shop.apply_event_reward("training", 1, 26)
	panel.refresh()
	check(panel.card_state(reserve[0]).skills[2].is_empty(), "Ordinary training is separate from rank modifiers")
	shop.hero_modifiers.erase(26)
	shop.rank_modifiers_by_hero["26"] = {"3": 1.0}
	panel.refresh()
	check(panel.card_state(reserve[0]).skills[2].get("id") == 1, "Rank 3 accepts JSON string keys and numeric IDs")
	check(shop.record_rank_modifier(26, 4, 2), "Acquiring a rank 4 modifier succeeds")
	panel.refresh()
	var rank_slots: Array[Dictionary] = panel.card_state(reserve[0]).skills
	check(rank_slots[2].get("id") == 1 and rank_slots[3].get("id") == 2,
			"Rank slots refresh independently and preserve the acquisition rank")
	shop.rank_modifiers_by_hero[26] = [1, 2]
	panel.refresh()
	check(panel.card_state(reserve[0]).skills[2].is_empty(), "An unranked legacy array has no known slot")
	shop.rank_modifiers_by_hero.erase(26)
	var chosen: Array[Dictionary] = skills_api.slots_for(4, 401)
	check(chosen[1].get("kind") == "passive", "A chosen specialization fills its native slot")
	shop.specializations[4] = {"id": 401}
	panel.refresh()
	check(panel.card_state(active[0]).skills == chosen, "Specialization change refreshes card state")
	shop.specializations.erase(4)
	var base_limit: int = stage.base_equipment_limit
	var max_slots: int = stage.max_item_slots
	check(shop.equipment_limit(26) == base_limit, "Shop uses the stage's base limit")
	for rank in range(1, 5):
		shop.hero_ranks[26] = rank
		panel.refresh()
		check(panel.card_state(reserve[0]).rank == rank, "Card forwards rank %d without shifting it" % rank)
	check(shop.equipment_limit(26) == mini(base_limit + 1, max_slots), "Maximum rank adds an equipment slot")
	shop.hero_ranks[26] = 2
	stage.contract.slots_by_rank = true
	check(shop.equipment_limit(26) == mini(2, max_slots), "Rank-based contract replaces the base limit")
	stage.contract.slots_by_rank = false
	var relics: Array[int] = shop.relics.duplicate()
	var kit_id: int = shop.kit_id
	shop.relics.append(6012)
	panel.refresh()
	check(panel.card_state(reserve[0]).capacity == maxi(1, base_limit - 1), "Capacity changes when a relic is acquired")
	shop.relics.append(6016)
	shop.kit_id = 771
	check(shop.equipment_limit(26) == mini(maxi(1, base_limit - 1) + 3, max_slots),
			"Relic and kit modifiers retain their order and cap")
	shop.relics = relics
	shop.kit_id = kit_id
	shop.hero_ranks[26] = 1
	shop.leave()
	fight.crossroads.select_path(0)
	fight.crossroads.claim()
	fight.crossroads.departed.emit()
	await process_frame
	panel.refresh()
	var cell := fight.board_hero(4).grid_cell
	var bench: Vector2i = panel.slot_at(reserve[0].get_global_rect().get_center())
	check(bench == Vector2i(-1, 0), "First bench card resolves to its actual reserve index")
	var legacy_panel: Control = fight._reserve_panel
	fight._reserve_panel = panel
	click(reserve[0].get_global_rect().get_center())
	click(active[0].get_global_rect().get_center())
	fight._reserve_panel = legacy_panel
	panel.refresh()
	check(panel.card_state(reserve[0]).hero_id == 4 and fight.board_hero(26).grid_cell == cell,
			"Card and board are updated after exchange")
	check(fight.transfer_hero(bench, Vector2i(-1, 2)), "Move a benched hero into an empty reserve slot")
	panel.refresh()
	check(panel.card_state(reserve[0]).hero_id == -1 and panel.card_state(reserve[2]).hero_id == 4,
			"Reserve hole and moved hero are preserved")
	var active_cell := fight.board_hero(24).grid_cell
	check(fight.transfer_hero(active_cell, bench), "Withdraw an active hero into reserve")
	check(fight.transfer_hero(bench, Vector2i(-1, 2)), "Swap two occupied reserve slots")
	panel.refresh()
	check(panel.card_state(reserve[0]).hero_id == 4 and panel.card_state(reserve[2]).hero_id == 24,
			"Reserve cards track occupied swaps")
	if not failed:
		print("Bottom roster integration passed")
	quit(int(failed))


func make_cards(panel: Control, y: int) -> Array[Control]:
	var cards: Array[Control] = []
	for index in 8:
		var card := Button.new()
		card.position = Vector2(30 + index * 70, y)
		card.size = Vector2(60, 60)
		panel.add_child(card)
		cards.append(card)
	return cards




func click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)

