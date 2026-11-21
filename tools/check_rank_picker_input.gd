extends "check_rank_shop.gd"

const HERO := 4


func verify() -> void:
	root.size = Vector2i(1280, 720)
	var stage: Node = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(HERO)
	fight.start_fight()
	for frame in 3600:
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			break
		fight._physics_process(1.0 / 60.0)
	fight._continue.pressed.emit()
	fight.open_first_shop()
	var shop := fight.first_shop
	shop.rank_modifier_choice_requested.connect(_on_request)
	shop.specializations[HERO] = load("res://battle/hero_rank.gd").choices(HERO)[0]
	shop.hero_ranks[HERO] = 2
	shop._rank_rng.seed = 10000

	for earned_rank in [3, 4]:
		shop.prepare_third(0, 0)
		shop.stock.assign(["Hero_%d" % HERO, "Hero_26"])
		shop.offer_ranks.clear()
		shop.offer_specs.clear()
		shop.offer_rank_modifiers.clear()
		shop.sale_index = -1
		shop.shards = 500
		shop.claim_and_open()
		await process_frame
		if not await _exercise_upgrade(fight, shop, earned_rank):
			quit(1)
			return

	if not failed:
		print("Rank picker input, resize, single commit and shop isolation passed")
	quit(int(failed))


func _exercise_upgrade(fight: GuildrunEncounter, shop: GuildrunFirstShop, earned_rank: int) -> bool:
	var balance := shop.shards
	var price := shop.price_at(0)
	click((shop._buttons[0] as Button).get_global_rect().get_center())

	var choice := await _wait_button(fight._ui, "RankChoice0")
	check(choice != null, "Shop click opens rank choice %d" % earned_rank)
	if choice == null:
		return false
	check(requests.size() == earned_rank - 2 and requests.back().rank == earned_rank, "One request for the new rank")
	check(shop.shards == balance - price and shop.hero_ranks[HERO] == earned_rank - 1
			and shop.has_pending_rank_modifier(), "One charge and provisional rank before choice")

	root.size = Vector2i(1100, 760) if earned_rank == 3 else Vector2i(1500, 720)
	await process_frame
	await process_frame
	choice = await _wait_button(fight._ui, "RankChoice0")
	if choice == null:
		check(false, "Picker survives resizing")
		return false
	_check_hero_preview(fight._ui.get_node("RankModifierPicker"), earned_rank)
	var shop_point := _uncovered_shop_point(fight._ui, shop._buttons[1])
	check(shop_point.x >= 0, "An underlying offer remains outside the choice buttons")
	if shop_point.x < 0:
		return false
	click(shop_point)
	await process_frame
	check(not shop.purchased.has(1) and shop.shards == balance - price and shop.has_pending_rank_modifier(),
			"Click on underlying offer cannot buy or select")

	var choice_point := choice.get_global_rect().get_center()
	click(choice_point)
	var recorded := shop.rank_modifiers_for(HERO)
	check(not shop.has_pending_rank_modifier() and shop.hero_ranks[HERO] == earned_rank
			and recorded.size() == earned_rank - 2 and recorded.get(earned_rank) == requests.back().offers[0],
			"Choice click commits the correct modifier")
	click(choice_point)
	check(shop.rank_modifiers_for(HERO) == recorded and shop.shards == balance - price, "Double click cannot reapply or charge again")

	var continue_button := await _wait_button(fight._ui, "RankContinue")
	check(continue_button != null, "Committed choice reaches the continue screen")
	if continue_button == null:
		return false
	click(continue_button.get_global_rect().get_center())
	await process_frame
	var picker := fight._ui.get_node_or_null("RankModifierPicker") as Control
	check((picker == null or not picker.is_visible_in_tree())
			and _find_button(fight._ui, "RankContinue") == null
			and _find_button(fight._ui, "RankChoice0") == null, "Continue closes the picker")
	check(not shop.purchased.has(1) and shop.shards == balance - price and shop.rank_modifiers_for(HERO) == recorded,
			"Closing does not buy through or change the accepted rank modifier")
	return not failed


func _check_hero_preview(picker: Control, earned_rank: int) -> void:
	var card: Control = picker._hero_card
	var body: Control = card.get_node("Root/Mask/BodyPanel")
	var badge: Control = body.get_node("BarPanel/RankPanel/HeroRank")
	var health: Control = body.get_node("BarPanel/HealthBarStatPanel")
	check(is_equal_approx(body.offset_bottom, 4.0) and is_equal_approx(body.get_node("StatsHolderPanel").modulate.a, 1.0),
			"The expanded animation makes the card stats visible")
	check(badge.get_global_rect().get_center().x < health.get_global_rect().position.x,
			"The animated rank badge sits to the left of the health bar")
	var portrait: TextureRect = card.get_node("Root/FrameBreakPortrait/UnityImage")
	var expected := "res://sprites/sharedassets1_%d.png" % (3877 if earned_rank == 3 else 3927)
	check(portrait.is_visible_in_tree() and portrait.texture.resource_path == expected,
			"The preview uses Yuuna's breakout portrait for the incoming rank")
	var shield: Dictionary = picker._data.entries["138"]
	var expected_shield := str(500 * earned_rank)
	check(picker._description(shield).contains(expected_shield), "Shield preview uses the incoming rank")
	check(picker._description(shield, true).contains("[color=#88d392ff]%s[/color]" % expected_shield),
			"The shield value retains its native keyword color")


func _wait_button(parent: Node, name_pattern: String) -> BaseButton:
	for attempt in range(120):
		var button := _find_button(parent, name_pattern)
		if button != null:
			return button
		await create_timer(0.025).timeout
	return null


func _find_button(parent: Node, name_pattern: String) -> BaseButton:
	for candidate in parent.find_children(name_pattern, "BaseButton", true, false):
		var button := candidate as BaseButton
		if button.is_visible_in_tree() and not button.disabled and button.size.x > 0.0 and button.size.y > 0.0:
			return button
	return null


func _uncovered_shop_point(parent: Node, offer: Control) -> Vector2:
	var rect := offer.get_global_rect()
	var buttons := parent.find_children("RankChoice*", "BaseButton", true, false)
	for fraction: Vector2 in [Vector2(0.5, 0.5), Vector2(0.15, 0.15), Vector2(0.85, 0.15), Vector2(0.15, 0.85), Vector2(0.85, 0.85)]:
		var point := rect.position + rect.size * fraction
		var over_choice := false
		for candidate in buttons:
			var button := candidate as BaseButton
			if button.is_visible_in_tree() and button.get_global_rect().has_point(point):
				over_choice = true
				break
		if not over_choice:
			return point
	return Vector2(-1, -1)
