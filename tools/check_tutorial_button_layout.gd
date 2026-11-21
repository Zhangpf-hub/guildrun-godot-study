extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1024, 768)
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	stage.show_first_fight_tutorial = true
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	var tutorial: RefCounted = fight._first_tutorial
	tutorial.advance_time(0.51)
	for _i in 3:
		tutorial.consume_mouse_press(MOUSE_BUTTON_LEFT)
	fight.select_hero(4)
	for _i in 2:
		tutorial.consume_mouse_press(MOUSE_BUTTON_LEFT)
	var view: Control = fight._ui.get_node("FirstTutorialView")
	var panel: Control = view._panels[65348]
	var start: Control = fight._ui.get_node("StartBattleView")
	var holder: Control = start.get_node(start.HOLDER)
	var front := holder.get_node("HighlightAbility/HighlightOrigin")
	var back := holder.get_node("HighlightAbility_Back/HighlightOrigin")
	var pulse := front.get_node("Burst9535") as Polygon2D
	var steady := front.get_node("Burst9536") as Polygon2D
	var quad := back.get_node("Burst10391") as Polygon2D
	for bounds: Vector2i in [Vector2i(1024, 768), Vector2i(1800, 1000), Vector2i(2560, 1080)]:
		root.size = bounds
		await process_frame
		await process_frame
		var button_rect := fight._fight.get_global_rect()
		var prompt_rect := panel.get_global_rect()
		var scaled_gap := 30.0 * (bounds.y / 1080.0 if float(bounds.x) / bounds.y >= 1.8 else bounds.x / 1920.0)
		expect(panel.is_visible_in_tree() and absf(prompt_rect.get_center().x - button_rect.get_center().x) < 1.0,
				"The ready prompt follows the live button center at %s" % bounds)
		expect(absf(button_rect.position.y - prompt_rect.end.y - scaled_gap) < 1.0,
				"The gap follows the source Canvas scaler at %s" % bounds)
	expect(pulse.is_visible_in_tree() and steady.is_visible_in_tree() and quad.is_visible_in_tree(),
			"The placement prompt enables both layers and all three bursts")
	expect(pulse.polygon.size() == 21 and pulse.polygons.size() == 24 and quad.polygon.size() == 4,
			"Both source renderer modes retain their geometry")
	pulse._elapsed = 0.196475
	pulse._sample()
	expect(pulse.self_modulate.a > 0.99, "Pulse reaches its source alpha key")
	pulse._elapsed = 1.15
	pulse._sample()
	expect(is_zero_approx(pulse.self_modulate.a), "Pulse disappears after lifetime and before next emission")
	fight.start_fight()
	await process_frame
	expect(not pulse.is_visible_in_tree() and not quad.is_visible_in_tree(), "Combat dismisses both highlight layers")
	stage.free()
	if not failed:
		print("Tutorial layout, three particle bursts and wide-screen attachment passed")
	quit(int(failed))


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
