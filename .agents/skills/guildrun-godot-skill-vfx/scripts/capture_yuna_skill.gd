extends SceneTree

const LAST_COMBAT_STEP := 409
const FILTERS := [
	"--without-basic-slash", "--without-flight-trail", "--without-flight-sparks",
	"--without-impact-layers", "--without-impact-smoke", "--without-release-particles",
	"--without-charge-flare", "--without-flight-wave", "--without-shuriken-mesh", "--without-shuriken-rim",
	"--without-impact-core",
	"--without-hit-redraw", "--without-vfx-redraw",
	"--without-flight-dust",
	"--without-flight-glow", "--without-flight-lines",
]
const CAPTURE_STEPS := [
	301, 329, 331, 334, 339, 344, 349, 352, 353, 355, 358, 360, 364,
	369, 370, 371, 372, 373, 374, 375, 376, 377, 378,
	379, 380, 381, 382, 383, 385, 386, 388, 390, 394, 398, 401, 403, 405, 407, 409,
	410, 411, 412, 413, 414, 415, 416, 417, 418, 421, 427,
]


func _initialize() -> void:
	capture.call_deferred()


func capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass a screenshot filename prefix after --.")
		quit(1)
		return
	for arg in args.slice(1):
		if arg not in FILTERS:
			push_error("Unknown capture filter: %s" % arg)
			quit(1)
			return
	var show_basic_slash := not args.has("--without-basic-slash")
	var show_flight_trail := not args.has("--without-flight-trail")
	var show_flight_sparks := not args.has("--without-flight-sparks")
	var show_flight_dust := not args.has("--without-flight-dust")
	var show_flight_glow := not args.has("--without-flight-glow")
	var show_flight_lines := not args.has("--without-flight-lines")
	var show_impact_layers := not args.has("--without-impact-layers")
	var show_impact_smoke := not args.has("--without-impact-smoke")
	var show_impact_core := not args.has("--without-impact-core")
	var show_hit_redraw := not args.has("--without-hit-redraw")
	var show_vfx_redraw := not args.has("--without-vfx-redraw")
	var show_release_particles := not args.has("--without-release-particles")
	var show_charge_flare := not args.has("--without-charge-flare")
	var show_flight_wave := not args.has("--without-flight-wave")
	var show_shuriken := not args.has("--without-shuriken-mesh")
	var show_shuriken_rim := show_shuriken and not args.has("--without-shuriken-rim")
	root.size = Vector2i(819, 616)
	TranslationServer.set_locale("zh_Hans")
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.run_seed = 262144
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.set_physics_process(false)
	fight.simulation_speed._settings_path = ""
	fight.simulation_speed.select_manual(0)
	fight.select_hero(4)
	var yuna := fight.board_hero(4)
	for unit: GuildrunBoardUnit in fight._units:
		for player: AnimationPlayer in unit._motion_players:
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	fight.start_fight()
	fight._effect_scene_time = 0.0
	if fight.combat_seed != 500813409:
		push_error("Unexpected combat seed: %d" % fight.combat_seed)
		stage.free()
		quit(1)
		return
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	fight._ui.get_node("StartBattleView").hide()

	for step in range(1, CAPTURE_STEPS.back() + 1):
		if step <= LAST_COMBAT_STEP:
			fight._step_battle(fight.BATTLE_STEP_Q16, true)
		fight._advance_effect_scene_time(fight.BATTLE_STEP_SECONDS)
		stage.battle_camera.advance(fight.BATTLE_STEP_SECONDS)
		for unit: GuildrunBoardUnit in fight._units:
			for player: AnimationPlayer in unit._motion_players:
				player.advance(fight.BATTLE_STEP_SECONDS)
		if is_instance_valid(yuna._yuna_wind_effect):
			yuna._yuna_wind_mount.on_skeleton_update()
		if is_instance_valid(yuna._yuna_charge_effect):
			yuna._yuna_charge_mount.on_skeleton_update()
			if not show_charge_flare:
				yuna._yuna_charge_effect.get_node("Flare_02").hide()
		if not show_release_particles and is_instance_valid(yuna._yuna_release_effect):
			yuna._yuna_release_effect.get_node("ParticlesAB").hide()
		if is_instance_valid(yuna._yuna_flight_effect):
			yuna._yuna_flight_mount.on_skeleton_update()
			if not show_flight_wave:
				yuna._yuna_flight_effect.get_node("Wave_01").hide()
			if not show_shuriken_rim:
				yuna._yuna_flight_effect.get_node("Shuriken_01").hide()
			if not show_shuriken:
				yuna._yuna_flight_effect.get_node("Shuriken_02").hide()
			if not show_flight_trail:
				yuna._yuna_flight_effect.get_node("Trail_02").hide()
			if not show_flight_sparks:
				yuna._yuna_flight_effect.get_node("Sparkle_01").hide()
			if not show_flight_dust:
				yuna._yuna_flight_effect.get_node("Dust_01").hide()
			if not show_flight_glow:
				yuna._yuna_flight_effect.get_node("Glow_01").hide()
			if not show_flight_lines:
				yuna._yuna_flight_effect.get_node("Line_01").hide()
		if is_instance_valid(yuna._yuna_skill_effect):
			if not show_impact_core:
				yuna._yuna_skill_effect.get_node("CoreWhite_01").hide()
			if not show_impact_layers:
				for emitter in ["Circle_01", "Spike_01", "Line_01"]:
					yuna._yuna_skill_effect.get_node(emitter).hide()
			if not show_impact_smoke:
				yuna._yuna_skill_effect.get_node("Smoke_01").hide()
		for effect: Variant in yuna._yuna_effects:
			if is_instance_valid(effect):
				effect._process(fight.BATTLE_STEP_SECONDS)
		if not show_hit_redraw and is_instance_valid(yuna._yuna_skill_effect):
			_remove_redraw(yuna._yuna_skill_effect, &"on_hit_vfx_redraw")
		for effect: Variant in yuna._yuna_basic_effects:
			if is_instance_valid(effect):
				if not show_basic_slash:
					effect.hide()
				effect._process(fight.BATTLE_STEP_SECONDS)
		if not show_vfx_redraw:
			for effect: Variant in yuna._yuna_effects + yuna._yuna_basic_effects:
				if is_instance_valid(effect):
					_remove_redraw(effect, &"vfx_redraw")
		if step in CAPTURE_STEPS:
			for frame in 3:
				await process_frame
				RenderingServer.force_draw(false)
			var frame_path := "%s-%d.png" % [args[0], step]
			var snapshot := root.get_texture().get_image()
			if snapshot == null or snapshot.save_png(frame_path) != OK:
				push_error("Could not save frame %d to %s." % [step, frame_path])
				stage.free()
				quit(1)
				return
			print("step=%d combat_step=%d shadow_step=%d cell=%s offset=%s" % [step,
				mini(step, LAST_COMBAT_STEP), yuna.shadow_step, yuna.grid_cell, yuna.visual_offset])
	stage.free()
	quit()


func _remove_redraw(effect: Node3D, pass_flag: StringName) -> void:
	for emitter: Node3D in effect.get_children():
		var profile: Dictionary = emitter.get_meta(&"particle", {})
		if not profile.get(pass_flag, false):
			continue
		for draw: MeshInstance3D in emitter.get_children():
			draw.material_override.next_pass = null
