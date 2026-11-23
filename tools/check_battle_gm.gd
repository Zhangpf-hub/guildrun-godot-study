extends SceneTree

const TEST_SCENE := "res://battle/stage.tscn"
var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	if change_scene_to_file(TEST_SCENE) != OK:
		push_error("Cannot open the standalone test stage")
		quit(1)
		return
	await scene_changed
	var fight: GuildrunEncounter = current_scene.encounter
	var gm := fight.get_node("BattleGM") as CanvasLayer
	var lab: RefCounted = gm.lab
	expect(not gm.visible, "Panel starts hidden")
	press_f2()
	expect(gm.visible, "F2 opens the test panel")
	press_f2(true)
	expect(gm.visible, "Holding F2 ignores key repeat")
	gm._submit("clear")
	gm._submit("hero 14 3 1")
	gm._submit("hero 26 2 1")
	gm._submit("enemy 1001 3 2")
	gm._submit("enemy 101 4 2")
	var funke := fight.board_hero(14)
	var kai := fight.board_hero(26)
	var turtle: GuildrunBoardUnit = fight._grid.occupants.get(Vector2i(3, 2))
	var mushroom: GuildrunBoardUnit = fight._grid.occupants.get(Vector2i(4, 2))
	if not is_instance_valid(funke) or not is_instance_valid(kai) or not is_instance_valid(turtle) or not is_instance_valid(mushroom):
		push_error("Custom battlefield did not spawn all four units: " + gm._feedback.text)
		quit(1)
		return
	gm._submit("enemy 1001 3 2")
	expect(fight._units.size() == 4, "An occupied hex cannot be overwritten")
	gm._choose_cell(Vector2i(2, 1))
	gm._assign_cell(false)
	gm._submit("move 1 1")
	expect(kai.grid_cell == Vector2i(1, 1), "A deployed hero can be moved")
	gm._choose_cell(Vector2i(4, 2))
	gm._remove_selected()
	expect(not fight._grid.occupants.has(Vector2i(4, 2)), "A selected enemy can be removed")
	gm._submit("enemy 101 4 2")
	gm._submit("seed 262144")
	var formation: Dictionary = lab.snapshot()
	var rejected := formation.duplicate(true)
	rejected.units[1].x = rejected.units[0].x
	rejected.units[1].y = rejected.units[0].y
	lab.apply_layout(rejected)
	expect(lab.snapshot() == formation, "Invalid preset leaves the original formation intact")

	gm._choose_cell(Vector2i(3, 1))
	gm._assign_cell(false)
	gm._choose_cell(Vector2i(3, 2))
	gm._assign_cell(true)
	expect(gm._chosen(gm._actor) == funke and gm._chosen(gm._target) == turtle, "Board selection sets caster and target")
	expect("Funke_ActiveAbility" in lab.clip_names(funke), "All imported clips are available to preview")
	gm._submit("anim Funke_ActiveAbility")
	var player := funke._motion_players[0]
	expect(paused and player.current_animation == &"Funke_ActiveAbility", "Animation-only preview loads the selected clip")
	lab.seek_clip(funke, 0.3)
	var motion_time := player.current_animation_position
	gm._submit("frame")
	expect(player.current_animation_position > motion_time and fight._frame == 0,
			"A visual frame advances the action without advancing combat")

	gm._submit("cast 14")
	if funke._funke_cast_effects.is_empty():
		push_error("Wildfire failed to enter the real animation and VFX path: " + gm._feedback.text)
		quit(1)
		return
	expect(fight.phase == GuildrunEncounter.Phase.FIGHT and paused and funke.cast_target == turtle,
			"An explicitly targeted cast starts an isolated paused combat")
	gm._submit("step 3")
	expect(fight._frame == 3 and funke.is_casting() and kai.current_target == null,
			"Fixed steps advance the forced cast while AI stays inactive")
	var charge: Node3D = funke._funke_cast_effects[0]
	var elapsed: float = charge._elapsed
	gm._submit("frame")
	expect(charge._elapsed > elapsed and fight._frame == 3, "A paused visual frame advances authored particle time only")
	gm._submit("step 50")
	expect(turtle.burn_stacks > 0 and fight._frame == 53, "The forced cast applies the real ability at its scheduled step")
	press_f2()
	expect(not gm.visible and paused, "Closing the panel leaves the frame paused")
	press_f2()
	gm._submit("reset")
	await scene_changed
	fight = current_scene.encounter
	gm = fight.get_node("BattleGM")
	await process_frame
	expect(not paused and fight._frame == 0 and fight._units.size() == 4,
			"Reset restores the edited formation in a clean match")
	expect(is_instance_valid(fight.board_hero(26)) and fight.board_hero(26).grid_cell == Vector2i(1, 1) and current_scene.run_seed == 262144,
			"Reset retains unit locations and the deterministic seed")
	gm._choose_cell(Vector2i(1, 1))
	gm._assign_cell(false)
	gm._choose_cell(Vector2i(3, 2))
	gm._assign_cell(true)
	gm._submit("cast 14")
	kai = fight.board_hero(26)
	expect(kai.ability_kind == "wildfire" and kai.is_casting(), "A different hero can borrow the requested skill")
	gm._submit("step 120")
	gm._submit("step 60")
	gm._submit("start")
	expect(kai.ability_kind == "resolute_strike" and not gm.lab.manual_casts,
			"Resuming AI restores the actor's original skill after the preview finishes")
	print("Battle lab checked: editable lineup, target selection, animation seek, motion and particle frames, native and borrowed spells, and deterministic reset.")
	quit(1 if failed else 0)


func press_f2(echo := false) -> void:
	var input := InputEventKey.new()
	input.keycode = KEY_F2
	input.pressed = true
	input.echo = echo
	root.push_input(input)


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
