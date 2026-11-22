extends SceneTree

var failed := false
var shown: Array[String] = []
var hidden: Array[int] = []
var completed: Array[int] = []
var locks: Array[bool] = []
var pauses: Array[bool] = []
var grid: Array[bool] = []
var reference_log: Array[Array] = []
var cleanup: Array = []


func _initialize() -> void:
	verify.call_deferred()


func expect(condition: bool, reason: String) -> void:
	if not condition:
		failed = true
		push_error(reason)


func new_machine() -> RefCounted:

	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/first_fight_tutorial.json"))
	var machine = load("res://battle/first_fight_tutorial.gd").new()
	machine.setup(data)
	machine.text_shown.connect(func(_display: int, key: String, _timed: bool): shown.append(key))
	machine.text_hidden.connect(func(display: int): hidden.append(display))
	machine.step_finished.connect(func(step: int): completed.append(step))
	machine.input_lock_changed.connect(func(value: bool): locks.append(value))
	machine.simulation_pause_changed.connect(func(value: bool): pauses.append(value))
	machine.grid_visibility_changed.connect(func(value: bool): grid.append(value))
	machine.reference_visibility_changed.connect(func(reference: int, value: bool): reference_log.append([reference, value]))
	machine.source_objects_hidden.connect(func(objects: Array): cleanup.assign(objects))
	return machine


func verify() -> void:
	var machine = new_machine()
	machine.notify_event(0)
	machine.advance_time(100.0)
	expect(shown.is_empty(), "First explanation must await the founding comic")
	machine.notify_comics_finished()
	machine.advance_time(0.49)
	expect(shown.is_empty(), "First explanation starts after the authored delay")
	machine.advance_time(0.01)
	expect(shown.back() == "Tutorial.NTUT-A01.InfoText1", "First caption is sourced and shown")
	machine.advance_time(15.0)
	expect(shown.back() == "Tutorial.NTUT-A01.InfoText2", "First info advances after its authored timeout")
	expect(not machine.consume_mouse_press(MOUSE_BUTTON_WHEEL_UP), "Scrolling is not one of the three native skip buttons")
	expect(machine.consume_mouse_press(MOUSE_BUTTON_RIGHT) and machine.consume_mouse_press(MOUSE_BUTTON_MIDDLE),
			"All mouse buttons can advance timed info")
	expect(shown.back() == "Tutorial.NTUT-A01.PromptText1", "Hero-pick prompt follows info")
	expect(not machine.consume_mouse_press(MOUSE_BUTTON_LEFT), "The prompt waits on hero selection")
	machine.notify_battle_flow(2)
	expect(completed.is_empty(), "Placement before the pick does not bypass the pick gate")
	machine.notify_hero_picked()
	expect(completed == [0] and machine.input_locked, "Placement introduces two input-locked captions")
	expect(shown.back() == "Tutorial.NTUT-A02.InfoText1" and hidden.has(65348), "Hero prompt hides on confirmed pick")
	machine.consume_mouse_press(MOUSE_BUTTON_LEFT)
	expect(grid == [true] and machine.input_locked, "Placement grid opens during the second caption")
	expect(machine.current_positioning().get("source_id") == 72985 and
			machine.current_positioning().target_rect.path_id == 53925, "Placement caption carries its authored target Rect")
	machine.advance_time(15.0)
	expect(shown.back() == "Tutorial.NTUT-A02.PromptText1" and not machine.input_locked,
			"Unblocked battle prompt uses the native caption")
	expect(not machine.consume_mouse_press(MOUSE_BUTTON_LEFT), "Arbitrary clicks cannot close battle prompt")
	var fight_prompt: Dictionary = machine.current_positioning()
	expect(fight_prompt.get("source_id") == 69334 and fight_prompt.get("target_reference") == 10 and
			fight_prompt.get("padding") == 30, "Battle prompt carries the FightButton reference and padding")
	expect(reference_log.has([1002, true]), "Battle button tutorial highlight is active")
	machine.notify_battle_flow(3)
	expect(completed == [0, 1] and grid == [true, false] and reference_log.has([1002, false]),
			"Resolution hides deployment UI and completes the battle prompt")
	machine.notify_event(3)
	machine.advance_time(0.5)
	expect(shown.back() == "Tutorial.NTUT-A03.InfoText1" and not machine.simulation_paused,
			"Queued full mana still waits for the attack explanation")
	machine.advance_time(5.0)
	expect(completed == [0, 1, 2] and machine.simulation_paused and pauses == [true],
			"Full mana pauses simulation once")
	expect(machine.current_positioning().get("source_id") == 72122 and
			machine.current_positioning().get("target_reference") == 14, "Mana caption follows the projected health bar")
	machine.notify_event(3)
	machine.consume_mouse_press(MOUSE_BUTTON_LEFT)
	expect(shown.back() == "Tutorial.NTUT-A04.InfoText2" and machine.simulation_paused,
			"Skipping the first mana text keeps simulation paused")
	machine.advance_time(15.0)
	expect(pauses == [true, false] and completed == [0, 1, 2, 3],
			"Full mana explanations resume simulation once")
	machine.notify_battle_flow(4)
	machine.advance_time(1.64)
	expect(shown.back() == "Tutorial.NTUT-A04.InfoText2", "Rewards explanation respects its initial delay")
	machine.advance_time(0.02)
	expect(shown.back() == "Tutorial.NTUT-A05.InfoText2", "Rewards explanation shown")
	machine.consume_mouse_press(MOUSE_BUTTON_LEFT)
	expect(shown.back() == "Tutorial.NTUT-A05.PromptText1" and completed == [0, 1, 2, 3, 4],
			"Proceed prompt stays visible after completing the results step")
	var past := hidden.size()
	machine.notify_battle_flow(5)
	expect(hidden.size() == past + 1 and cleanup == [2504, 17147] and completed == [0, 1, 2, 3, 4, 5],
			"Entering shop clears the remaining prompts")
	machine.abort()
	expect(not machine.input_locked and not machine.simulation_paused, "Abort releases input and simulation")
	verify_abort_while_paused()
	await verify_gameplay()
	verify_pause_equivalence()
	print("FIRST_FIGHT_TUTORIAL native timeouts, tracker guide, skippable text, hero and resolution gates, mana pause, shop cleanup, equal combat traces")
	quit(1 if failed else 0)


func verify_abort_while_paused() -> void:
	var machine = new_machine()
	machine.notify_event(0)
	machine.notify_comics_finished()
	machine.advance_time(45.5)
	machine.notify_hero_picked()
	machine.notify_battle_flow(2)
	machine.advance_time(30.0)
	machine.notify_battle_flow(3)
	machine.advance_time(5.5)
	machine.notify_event(3)
	expect(machine.simulation_paused, "Abort fixture reaches the paused mana explanation")
	machine.abort()
	expect(pauses.back() == false and not machine.simulation_paused and hidden.back() == 77122,
			"Closing an active tutorial restores simulation and hides its active caption")


func open_title(path: String) -> Control:
	var title: Control = load("res://UI/contracts.tscn").instantiate()
	title.progress_path = path
	root.add_child(title)
	current_scene = title
	return title


func click() -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_visible_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func verify_gameplay() -> void:
	var path := "user://ftue-runtime-test-%d.cfg" % OS.get_process_id()
	var progress := ConfigFile.new()
	progress.set_value("opening", "intro_comic_seen", true)
	progress.save(path)
	var title := open_title(path)
	title.get_node("TitleMenu/Start").pressed.emit()
	await process_frame
	await process_frame
	var stage: Node = current_scene
	var fight: GuildrunEncounter = stage.encounter
	var machine := fight._first_tutorial
	var tutorial_view: Control = fight._ui.get_node_or_null("FirstTutorialView")
	expect(machine != null and is_instance_valid(fight._founding_comic), "Fresh Start activates tutorial and founding comic")
	expect(tutorial_view != null, "The actual tutorial view is bound on fresh Start")
	if machine == null or tutorial_view == null:
		stage.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var comic := fight._founding_comic
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await comic.completed
	await process_frame
	fight.select_hero(26)
	expect(fight.phase == GuildrunEncounter.Phase.PICK, "Gameplay cannot skip the pick introduction")
	fight._process(0.5)
	for page in 3:
		click()
	fight._choices.get_child(1).pressed.emit()
	expect(fight.phase == GuildrunEncounter.Phase.PLACE and machine.input_locked, "Hero choice starts locked deployment instructions")
	fight._process(0.0)
	expect(not fight._deployment_grid_view.visible, "First placement caption hides the actual deployment grid")
	fight.start_fight()
	expect(fight.phase == GuildrunEncounter.Phase.PLACE, "Start remains gated during placement instructions")
	expect(not fight.transfer_hero(Vector2i(3, 0), Vector2i(3, 1)), "Placement instructions lock actual transfers")
	click()
	fight._process(0.0)
	expect(fight._deployment_grid_view.visible, "Second placement caption reveals the actual deployment grid")
	click()
	fight._process(0.0)
	expect(not machine.input_locked and not fight._fight.disabled, "Both placement captions release the normal Start button")
	expect(tutorial_view._panels[65348].visible, "The place-to-fight prompt is actually visible")
	fight._fight.pressed.emit()
	expect(fight.phase == GuildrunEncounter.Phase.FIGHT, "Start enters actual battle and clears its prompt")
	expect(not tutorial_view._panels[65348].visible, "Resolution hides the bound fight prompt")
	fight._process(0.0)
	expect(not fight._deployment_grid_view.visible, "Entering resolution hides the actual deployment grid")
	fight._process(0.5)
	click()
	var observed: Array[bool] = []
	machine.simulation_pause_changed.connect(func(value: bool): observed.append(value))
	for tick in 2400:
		if fight.phase != GuildrunEncounter.Phase.FIGHT or machine.simulation_paused:
			break
		fight._physics_process(1.0 / Engine.physics_ticks_per_second)
	expect(machine.simulation_paused and observed == [true] and fight._tutorial_mana_seen,
			"The first natural SkillAttack starts the mana tutorial once")
	expect(fight._hero.is_casting() and fight._hero.mana == int(fight._hero.stat("MaxMana")),
			"The first casting step completes with its mana bar still full")
	var elapsed := fight.battle_time_q16
	var shader_time := fight.effect_scene_time()
	fight._physics_process(1.0)
	expect(fight.battle_time_q16 == elapsed, "Mana explanation does not advance the fixed-step battle")
	fight._advance_effect_scene_time(1.0)
	expect(is_equal_approx(fight.effect_scene_time(), shader_time), "The paused battle also freezes the shader clock")
	click()
	expect(machine.simulation_paused, "First mana caption leaves actual battle paused")
	click()
	expect(not machine.simulation_paused and observed == [true, false], "Second mana caption resumes fixed steps")
	var multiplier: float = fight.simulation_speed.multiplier()
	fight._advance_effect_scene_time(0.5)
	expect(is_equal_approx(fight.effect_scene_time(), shader_time + 0.5 * multiplier),
			"The shader clock resumes at the current battle speed")
	for tick in 7200:
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			break
		fight._physics_process(1.0 / Engine.physics_ticks_per_second)
	expect(fight.phase == GuildrunEncounter.Phase.RESULT and observed == [true, false], "Fight resolves with one mana tutorial")
	fight._continue.pressed.emit()
	expect(fight.phase == GuildrunEncounter.Phase.RESULT, "Result explanation gates actual continuation")
	var reward_outline := fight._result_view.reward_target.get_node("HighlightUI") as Control
	var continue_outline := fight._result_view.proceed_slot.get_node("HighlightUI_Proceed") as Control
	var reward_viewport := fight._result_view._rewards.get_parent() as Control
	expect(not reward_outline.visible and not continue_outline.visible, "The result highlights must wait for the tutorial")
	for outline: Control in [reward_outline, continue_outline]:
		var background := outline.get_node("UnityImage") as ColorRect
		var highlight := outline.get_node("Highlight_Rotating/UnityImage") as ColorRect
		var base_material := background.material as ShaderMaterial
		var highlight_material := highlight.material as ShaderMaterial
		expect(base_material != null and highlight_material != null and base_material.shader == highlight_material.shader
				and not bool(base_material.get_shader_parameter("rotating"))
				and bool(highlight_material.get_shader_parameter("rotating"))
				and highlight_material.get_shader_parameter("rect_size") == highlight.size,
				"Both tutorial border passes must be bound to their own rectangle")
	var saved_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_Hans")
	fight._process(1.66)
	var caption := tutorial_view._panels[77122].get_node("TutorialText/UnityText") as Label
	expect(caption.get_line_count() == 2, "The original Simplified Chinese shard tutorial wraps in two lines")
	expect(reward_outline.visible and not continue_outline.visible and not reward_viewport.clip_contents,
			"The shard explanation must show the full border outside the reward clip")
	click()
	expect(not reward_outline.visible and continue_outline.visible and reward_viewport.clip_contents,
			"Dismissing the shard explanation must restore clipping and highlight Continue")
	TranslationServer.set_locale(saved_locale)
	fight._continue.pressed.emit()
	expect(fight.phase == GuildrunEncounter.Phase.SHOP and fight._first_tutorial == null and machine._active_displays.is_empty(),
			"Entering the real shop clears and releases tutorial state")
	expect(not tutorial_view._panels[65348].visible and not tutorial_view._panels[77122].visible,
			"Shop cleanup hides both actual tutorial displays")
	verify_combat_tracker_guide(fight)
	stage.free()

	var direct: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(direct)
	expect(direct.encounter._first_tutorial == null, "Direct stage tests do not implicitly start the tutorial")
	direct.free()
	var preview: Node = load("res://battle/stage.tscn").instantiate()
	preview.show_first_fight_tutorial = true
	root.add_child(preview)
	var preview_fight: GuildrunEncounter = preview.encounter
	expect(preview_fight._first_tutorial != null and preview_fight._founding_comic == null,
			"The direct F6 opt-in begins at the first tutorial without a title save")
	preview_fight._process(0.5)
	for page in 3:
		click()
	expect(preview_fight._first_tutorial.can_pick_hero(), "Direct preview advances to the real hero choice")
	preview.free()
	progress.set_value("opening", "tutorial_checkpoint", true)
	progress.save(path)
	title = open_title(path)
	title.get_node("TitleMenu/Start").pressed.emit()
	expect(title.selecting, "Past-checkpoint save opens contracts")
	title.get_node("Panel/Actions/Play").pressed.emit()
	await process_frame
	await process_frame
	stage = current_scene
	expect(stage.normal_opening and stage.encounter._first_tutorial == null, "Normal contract run bypasses first-fight tutorial")
	stage.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func verify_combat_tracker_guide(fight: GuildrunEncounter) -> void:
	expect(fight._combat_tracker_guide_due, "Completing the first fight explanation must enable the next combat's tracker guide")
	fight.first_shop.leave()
	var road := fight.crossroads
	road.select_path(0)
	road.claim()
	road.get_node("Body/Event/Content/Continue").pressed.emit()
	expect(fight.phase == GuildrunEncounter.Phase.PLACE and fight._combat_tracker_guide == null,
			"The tracker guide waits for combat to begin")
	fight.start_fight()
	var guide := fight._combat_tracker_guide
	var view := fight._ui.get_node_or_null("CombatTrackerGuide") as Control
	expect(guide != null and view != null, "The regular fight starts its imported guide")
	if guide == null or view == null:
		return
	var tracker := fight._ui.get_node("BattleTracker") as Control
	var panel := tracker.get_node(tracker.PANEL) as Control
	var outline := panel.get_node("HighlightUI") as Control
	guide.advance_time(2.99)
	expect(not outline.visible and not view._panels[77122].visible, "Tracker guide must wait the authored three seconds")
	guide.advance_time(0.02)
	var prompt := view._panels[77122] as Control
	var line := prompt.get_node("TutorialText/UnityText") as Label
	expect(prompt.visible and outline.visible and line.text == tr("Tutorial.NTUT-A08.2.InfoText1"),
			"The tracker guide displays its original caption and border")
	expect(prompt.get_global_rect().end.x <= panel.get_global_rect().position.x
			and view._mask.get_shader_parameter("show_grid"), "The prompt sits left of the unmasked tracker")
	expect(not fight._tutorial_paused() and not guide.input_locked,
			"The tracker guide leaves the battle running and its controls available")
	guide.advance_time(14.0)
	expect(prompt.visible, "Tracker guide remains visible during its fifteen-second window")
	click()
	expect(fight._combat_tracker_guide == null and not outline.visible and not prompt.visible
			and not fight._combat_tracker_guide_due, "Skipping the guide removes its overlay and prevents replay")


func verify_pause_equivalence() -> void:
	for id: int in [4, 14, 26]:
		var ordinary := run_combat_trace(id, false)
		var tutorial_run := run_combat_trace(id, true)
		for key: String in ordinary:
			expect(ordinary[key] == tutorial_run[key], "Hero %d tutorial pause changed %s" % [id, key])


func run_combat_trace(id: int, tutorial_enabled: bool) -> Dictionary:
	seed(1940)
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	stage.show_first_fight_tutorial = tutorial_enabled
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight._rng.seed = 1940
	var machine := fight._first_tutorial
	if tutorial_enabled:
		machine.advance_time(45.5)
	fight.select_hero(id)
	if tutorial_enabled:
		machine.advance_time(30.0)
	expect(fight._hero.grid_cell == Vector2i(3, 0), "Trace uses the same native starter cell")
	var events: Array = []
	for unit: GuildrunBoardUnit in fight._units:
		var actor := int(unit.stat("Id")._sequentialId)
		unit.basic_attack_action.connect(func(target: GuildrunBoardUnit):
			events.append([fight._frame, actor, "attack", int(target.stat("Id")._sequentialId)]))
		unit.skill_attack_started.connect(func(): events.append([fight._frame, actor, "skill_attack"]))
		unit.shield_gained.connect(func(amount: int): events.append([fight._frame, actor, "shield", amount]))
	fight.start_fight()
	if tutorial_enabled:
		machine.advance_time(5.5)
	var trace: Array = []
	var pause_count := 0
	for tick in 7200:
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			break
		fight._advance_battle_tick(GuildrunEncounter.BATTLE_STEP_SECONDS)
		if fight._pending_battle_result.is_valid():
			fight._physics_process(1.5)
		trace.append(combat_frame(fight))
		if tutorial_enabled and machine.simulation_paused:
			pause_count += 1
			expect(fight._hero.is_casting() and fight._hero.mana == int(fight._hero.stat("MaxMana")),
					"The mana tutorial waits for the actual cast, with its mana still visible")
			fight._physics_process(0.75)
			expect(combat_frame(fight) == trace.back(), "A displayed tutorial cannot advance an extra fixed step")
			machine.consume_mouse_press(MOUSE_BUTTON_LEFT)
			machine.consume_mouse_press(MOUSE_BUTTON_LEFT)
	expect(fight.phase == GuildrunEncounter.Phase.RESULT, "Both comparison battles reach the results")
	expect(pause_count == int(tutorial_enabled), "Each tutorial battle pauses exactly once")
	var result := fight.last_battle_statistics
	var totals: Array = []
	for unit: GuildrunBoardUnit in fight._units:
		totals.append(result.units[unit.get_instance_id()])
	var comparison := {"fixed-step state": trace, "event sequence": events, "per-unit statistics": totals,
			"elapsed Q16": fight.battle_time_q16, "verdict": result.victory}
	stage.free()
	return comparison


func combat_frame(fight: GuildrunEncounter) -> Array:
	var units: Array = []
	for unit: GuildrunBoardUnit in fight._units:
		units.append([unit.grid_cell, unit.position, unit.health, unit.mana, unit.total_shield(), unit.defeated,
				unit.cast_remaining_q16, unit.cast_release_q16, unit.attack_cooldown_q16,
				unit.frost_stacks, unit.burn_stacks, unit.poison_stacks])
	var shots: Array = []
	for shot: Dictionary in fight._shots:
		shots.append([shot.position, shot.target.grid_cell, shot.damage, shot.cue])
	return [fight._frame, fight.battle_time_q16, fight.phase, fight._combat_rng.state, fight._rng.state, units, shots]

