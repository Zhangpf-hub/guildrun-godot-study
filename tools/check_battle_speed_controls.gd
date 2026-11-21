extends SceneTree

const SLOT_PATH := "Canvas/Root/CoreGameUI/SpeedControls/Root/ButtonPanel"
const PHASE := GuildrunEncounter.Phase

var _failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1152, 648)
	var stage := open_stage()
	await process_frame
	await process_frame
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(26)
	var view := speed_view(fight)
	expect(view != null and fight.phase == PHASE.PLACE, "Open the real speed view during deployment")
	if view == null:
		quit(1)
		return
	for index in 3:
		click_button(slot(view, index))
		expect(fight.simulation_speed.speed_index() == index and not fight.simulation_speed.is_automatic(),
				"Manual speed %d is selectable through its visible hit area" % index)
		expect(slot(view, index).get_node("EnabledGraphic").visible, "Manual selection updates the visible highlight")
	click_button(slot(view, -1))
	expect(fight.simulation_speed.is_automatic(), "AUTO button enables automatic mode")
	expect(slot(view, -1).get_node("EnabledGraphic").visible, "AUTO highlight turns on")
	click_button(slot(view, -1))
	expect(not fight.simulation_speed.is_automatic() and fight.simulation_speed.speed_index() == 0,
			"Turning AUTO off preserves its current tier")
	click_button(slot(view, -1))
	for index in 3:
		expect(not slot(view, index).get_node("CurrentTriangle").visible, "Deployment hides AUTO speed triangles")
	fight.start_fight()
	fight._physics_process(fight.BATTLE_STEP_SECONDS)
	await process_frame
	expect(fight.phase == PHASE.FIGHT and fight.simulation_speed.speed_index() == 1, "Entering an actual fight starts AUTO")
	expect(slot(view, 1).get_node("CurrentTriangle").visible, "Combat triangle identifies the active AUTO speed")
	expect(not slot(view, 1).get_node("EnabledGraphic").visible, "AUTO indicator is distinct from a manual toggle")
	fight.battle_time_q16 = (20 << 16) - fight.BATTLE_STEP_Q16
	fight._physics_process(fight.BATTLE_STEP_SECONDS)
	expect(slot(view, 2).get_node("CurrentTriangle").visible and not slot(view, 1).get_node("CurrentTriangle").visible,
			"The AUTO indicator moves to the faster tier at the 20-second simulation boundary")
	stage.free()

	stage = open_stage()
	await process_frame
	await process_frame
	fight = stage.encounter
	fight.select_hero(26)
	view = speed_view(fight)
	expect(fight.simulation_speed.is_automatic() and fight.simulation_speed.speed_index() == 1,
			"A new headless scene has clean speed settings")
	var original_center := center_of(slot(view, 2).get_node("SelectSpeed"))
	root.size = Vector2i(960, 720)
	await process_frame
	await process_frame
	var resized_center := center_of(slot(view, 2).get_node("SelectSpeed"))
	expect(original_center.distance_to(resized_center) > 25.0, "Viewport resizing moves the speed hit box")
	click_at(original_center)
	expect(fight.simulation_speed.is_automatic(), "The stale pre-resize hit box is inactive")
	click_at(resized_center)
	expect(fight.simulation_speed.speed_index() == 2 and not fight.simulation_speed.is_automatic(),
			"The resized speed hit box still selects its own tier")
	stage.free()

	await verify_tutorial_input()
	if not _failed:
		print("Battle speed UI checks passed.")
	quit(1 if _failed else 0)


func verify_tutorial_input() -> void:
	var stage := open_stage(true)
	await process_frame
	await process_frame
	var fight: GuildrunEncounter = stage.encounter
	var machine := fight._first_tutorial
	expect(machine != null, "Direct tutorial preview creates the actual input lock")
	if machine == null:
		stage.free()
		return
	fight._process(0.5)
	for page in 3:
		click_at(root.get_visible_rect().get_center())
	fight.select_hero(26)
	var view := speed_view(fight)
	expect(fight.phase == PHASE.PLACE and machine.input_locked, "Tutorial reaches locked deployment")
	click_button(slot(view, 2))
	expect(machine.input_locked and fight.simulation_speed.is_automatic(), "A locked tutorial click cannot select speed")
	click_button(slot(view, 2))
	expect(not machine.input_locked and fight.simulation_speed.is_automatic(),
			"The click releasing the tutorial cannot also select speed")
	click_button(slot(view, 2))
	expect(fight.simulation_speed.speed_index() == 2 and not fight.simulation_speed.is_automatic(),
			"The next unlocked click selects speed normally")
	stage.free()


func open_stage(tutorial := false) -> Node:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.show_first_fight_tutorial = tutorial
	root.add_child(stage)
	return stage


func speed_view(fight: GuildrunEncounter) -> Control:
	return fight._ui.get_node_or_null("BattleSpeedView") as Control


func slot(view: Control, manual_index: int) -> Control:
	var suffix := "Auto" if manual_index < 0 else str(manual_index + 1)
	return view.get_node("%s/SpeedButton_%s" % [SLOT_PATH, suffix]) as Control


func center_of(button: Control) -> Vector2:
	return button.get_global_transform_with_canvas() * (button.size * 0.5)


func click_button(container: Control) -> void:
	click_at(center_of(container.get_node("SelectSpeed")))


func click_at(position: Vector2) -> void:
	var mouse := InputEventMouseMotion.new()
	mouse.position = position
	mouse.global_position = position
	root.push_input(mouse, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = position
		event.global_position = position
		root.push_input(event, true)


func expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)

