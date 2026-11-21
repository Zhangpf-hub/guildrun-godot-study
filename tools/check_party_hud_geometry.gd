extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1022, 768)
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var encounter: GuildrunEncounter = stage.encounter
	encounter.select_hero(4)
	await process_frame
	await process_frame
	var roster: Control = encounter._ui.get_node("BottomRoster")
	var bag: Control = encounter._ui.get_node("InventorySidebar")
	var hero: Control = roster._active_cards[0]
	var empty: Control = roster._active_cards[1]
	var photo := hero.get_node("HeroRoundPortrait") as Control
	var center := photo.get_global_rect().get_center()
	# Measured on the Steam client image after removing its title bar.
	expect(center.distance_to(Vector2(273, 745)) <= 5.0, "Starter portrait center at 1022 x 768: %s" % center)
	var toggle: Control = bag.get_node(bag.SIDEBAR + "/ItemButton")
	expect(toggle.get_global_rect().position.distance_to(Vector2(-1, 241)) < 2.0, "Left item toggle position")
	var first := (bag._slots[0].root as Control).get_global_rect().get_center()
	var last := (bag._slots[6].root as Control).get_global_rect().get_center()
	expect(absf(first.y - 295.0) < 3 and absf(last.y - 457.0) < 3, "First and seventh item slots %s %s" % [first, last])
	var ability := hero.get_node("AbilityPanel/AbilityViewTop") as Control
	var icon := ability.get_node("AbilityIcon/UnityImage") as TextureRect
	expect(icon.is_visible_in_tree() and icon.texture == load("res://sprites/sharedassets1_4539.png"),
			"The selected hero uses its own starting ability icon")
	expect(ability.get_node("Frame/UnityImage").texture == load("res://sprites/sharedassets3_469.png"), "Occupied ability frame")
	for name in ["AbilityViewLeft", "AbilityViewRight", "AbilityViewBottom"]:
		var slot := hero.get_node("AbilityPanel/" + name) as Control
		expect(slot.is_visible_in_tree() and not slot.get_node("AbilityIcon").is_visible_in_tree() and
				slot.get_node("Frame/UnityImage").texture == load("res://sprites/sharedassets3_453.png"), "Empty ability frame")
	expect(not empty.get_node("HeroRoundPortrait/Image/RoundFrame/UnityImage").is_visible_in_tree() and
			empty.get_node("HeroRoundPortrait/Image/UnityImage").is_visible_in_tree(), "Empty portrait retains only its background")
	root.size = Vector2i(2560, 1080)
	await process_frame
	await process_frame
	expect(roster.scale.is_equal_approx(Vector2.ONE) and bag.scale.is_equal_approx(Vector2.ONE), "Ultrawide height scaling")
	expect(roster.slot_at(photo.get_global_rect().get_center()) == encounter._hero.grid_cell, "Portrait hit area after resizing")
	stage.free()
	if not failed:
		print("Party HUD native screenshot geometry, frame visibility, ability sprites and ultrawide hit area passed")
	quit(int(failed))


func expect(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error(description)
