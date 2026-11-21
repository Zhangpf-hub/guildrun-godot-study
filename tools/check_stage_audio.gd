extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failed = true


func verify() -> void:
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var sound: Node = stage.sound
	check(sound.banks.size() == 5 and sound.descriptions.size() == 358, "Original FMOD banks")
	if failed:
		quit(1)
		return
	check(sound.loops.size() == 2, "Forest music and ambience")
	var main: Object = sound.loops.music.event
	check(sound.loops.music.path.ends_with("mus_forest_01_main"), "Tutorial music selection")
	stage.encounter.select_hero(4)
	stage.encounter.start_fight()
	for attempt in 50:
		await create_timer(0.1).timeout
		if main.get_timeline_position() > 0 and sound.loops.ambience.event.get_timeline_position() > 0:
			break
	check(main.get_timeline_position() > 0, "Music timeline advances")
	check(sound.loops.ambience.event.get_timeline_position() > 0, "Ambience timeline advances")
	check(not main.is_virtual(), "Music instance is audible to listener")
	check(sound.server.get_global_parameter_by_name("game_phase") == 1.0, "Fight phase parameter")
	check(sound.server.get_global_parameter_by_name("battle_hero_amount") == 1.0, "Hero count")
	check(sound.play_path(sound.ui_paths[14]), "Original shop reroll event")
	sound.play_shop_voice(stage._heroes[6], "purchase_vo")
	await create_timer(0.12).timeout
	var voice: Object = sound.descriptions["event:/sfx/comb/heroes/seraphael/seraphael_purchase_vo"]
	check(voice.get_instance_count() > 0, "Shop voice resolves from character settings")
	for tick in 3600:
		if stage.encounter.phase != GuildrunEncounter.Phase.FIGHT:
			break
		stage.encounter._step_battle(1092)
	await create_timer(0.12).timeout
	check(stage.encounter.phase == GuildrunEncounter.Phase.RESULT, "Battle resolved")
	check(sound.server.get_global_parameter_by_name("game_phase") == 0.0, "Result phase parameter")
	stage.encounter.free()
	stage.load_board(10101)
	check(sound.loops.music.event == main, "Same-biome music continues across rooms")
	var lighting := {}
	for id: int in stage._stages:
		var room: String = stage.field(stage._stages[id], "EnvironmentSceneName")
		var period := room.get_slice("_", room.count("_"))
		if lighting.has(period):
			continue
		stage.load_board(id)
		await create_timer(0.1).timeout
		lighting[period] = sound.server.get_global_parameter_by_name("daytime")
	check(lighting == {"Morning": 1.0, "Evening": 2.0, "Dusk": 3.0}, "Room time of day")
	for variation: String in ["miniboss", "finalboss"]:
		for id: int in stage._stages:
			if stage.field(stage._stages[id], "BiomeBgmVariation") == variation:
				stage.load_board(id)
				break
		check(sound.loops.music.path.ends_with("_" + variation), variation + " music selection")
	sound.start_super_shop()
	for attempt in 50:
		await create_timer(0.1).timeout
		if sound.loops.music.event.get_timeline_position() > 0:
			break
	check(sound.loops.music.path == "event:/MUSIC/BIOMES/mus_auction_house" and sound.loops.music.event.get_timeline_position() > 0, "Elite shop music begins")
	print("STAGE_AUDIO banks=", sound.banks.size(), " events=", sound.descriptions.size(), " checked phases, 3 music variations and the auction house")
	stage.queue_free()
	await process_frame
	quit(1 if failed else 0)
