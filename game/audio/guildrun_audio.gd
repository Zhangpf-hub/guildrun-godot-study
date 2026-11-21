extends Node
## Keeps the demo's authored FMOD events and their parameter-driven transitions alive across boards.

const BANKS := ["MASTER.strings", "MASTER", "MUSIC", "SFX", "VO"]
const OVERRIDES := {
	"attack_cast": "OverrideAttackSFX", "attack_hit": "OverrideAttackHitSFX",
	"skill_cast": "OverrideSkillSFX", "skill_hit": "OverrideSkillHitSFX", "death": "OverrideDeathSFX"
}

var server: Object
var banks: Array = []
var descriptions := {}
var ui_paths := {}
var visual_audio := {}
var loops := {}
var camera: Camera3D


func _ready() -> void:
	set_process(false)
	if DisplayServer.get_name() == "headless" and not "--test-audio" in OS.get_cmdline_user_args():
		return
	server = Engine.get_singleton("FmodServer")
	if server == null:
		push_error("FMOD runtime unavailable")
		return
	for bank_name: String in BANKS:
		var path := "res://audio/banks/%s.bank" % bank_name
		var bank: Object = server.load_bank(path, 0)
		if bank == null or not bank.is_valid():
			push_error("FMOD bank unavailable: " + path)
			_release_banks()
			return
		banks.append(bank)
		for event: Object in bank.get_description_list():
			descriptions[String(event.get_path()).to_lower()] = event
	process_mode = PROCESS_MODE_ALWAYS
	set_process(true)


func set_board(biome: String, variation: String, environment: String, listener: Camera3D) -> void:
	if banks.is_empty():
		return
	camera = listener
	server.set_listener_transform3d(0, camera.global_transform)
	_set_loop("music", "event:/MUSIC/BIOMES/%s/mus_%s_%s" % [biome, biome, variation])
	_set_loop("ambience", "event:/SFX/AMB/Biomes/" + biome)
	var daytime := {"Morning": 1.0, "Evening": 2.0, "Dusk": 3.0}
	var lighting := environment.get_slice("_", environment.count("_"))
	if daytime.has(lighting):
		server.set_global_parameter_by_name("daytime", daytime[lighting])
	set_phase(false)


func start_menu(events: Array) -> void:
	if banks.is_empty():
		return
	for path: String in events:
		_set_loop("music" if path.begins_with("event:/MUSIC/") else "ambience", path)


func play_intro_comic(path: String) -> void:
	_set_loop("comic_snapshot", "snapshot:/comic_playing")
	_set_loop("comic_panel", path)


func stop_intro_comic() -> void:
	for slot in ["comic_panel", "comic_snapshot"]:
		if loops.has(slot):
			_stop_loop(slot)


func _set_loop(slot: String, path: String) -> void:
	if loops.has(slot):
		if loops[slot].path == path:
			return
		_stop_loop(slot)
	var desc: Object = descriptions.get(path.to_lower())
	if desc == null:
		return
	var event: Object = server.create_event_instance_from_description(desc)
	if event == null:
		return
	if desc.is_3d():
		event.set_3d_attributes(camera.global_transform if is_instance_valid(camera) else Transform3D.IDENTITY)
	event.start()
	loops[slot] = {"path": path, "event": event}


func start_super_shop() -> void:
	if not banks.is_empty():
		_set_loop("music", "event:/MUSIC/BIOMES/mus_auction_house")


func set_phase(fighting: bool) -> void:
	if not banks.is_empty():
		server.set_global_parameter_by_name("game_phase", 1.0 if fighting else 0.0)


func start_fight(heroes: int, enemies: int) -> void:
	if banks.is_empty():
		return
	set_phase(true)
	server.set_global_parameter_by_name("battle_hero_amount", heroes)
	server.set_global_parameter_by_name("battle_enemy_amount", enemies)
	play_ui(30)


func play_ui(kind: int) -> void:
	if ui_paths.has(kind):
		play_path(ui_paths[kind])


func play_shop_voice(row: Dictionary, cue: String) -> void:
	if is_instance_valid(camera):
		play_character(row, true, cue, camera.global_position)


func play_character(row: Dictionary, hero: bool, cue: String, position: Vector3) -> void:
	if banks.is_empty() or row.is_empty():
		return
	var config: Dictionary = visual_audio.get(int(row["<VisualConfig>k__BackingField"].m_PathID), {})
	if config.is_empty():
		return
	var actor := "hero" if hero else "enemy"
	if not OVERRIDES.has(cue) or config.get("<%s>k__BackingField" % OVERRIDES[cue], false):
		if config.get("<OverrideCharacterName>k__BackingField", false):
			actor = config["<NameOverride>k__BackingField"]
		else:
			var id: Dictionary = row["<Id>k__BackingField"]
			var key: String = row["<NameLocaKey>k__BackingField"]._key
			if key.is_empty():
				key = "%s.%s_%d.Name" % ["Heroes" if hero else "Enemies", id._prefix, int(id._sequentialId)]
			var english := TranslationServer.get_translation_object("en")
			actor = String(english.get_message(key)).replace(" ", "") if english else ""
	var folder := "HEROES" if hero else "ENEMIES"
	play_path("event:/SFX/COMB/%s/%s/%s_%s" % [folder, actor, actor, cue], position)


func play_path(path: String, position := Vector3.ZERO) -> bool:
	var desc: Object = descriptions.get(path.to_lower())
	if desc == null:
		return false
	var event: Object = server.create_event_instance_from_description(desc)
	if event == null:
		return false
	if desc.is_3d():
		event.set_3d_attributes(Transform3D(Basis.IDENTITY, position))
	event.start()
	event.release()
	return true


func _process(_delta: float) -> void:
	if is_instance_valid(camera):
		server.set_listener_transform3d(0, camera.global_transform)
	server.update()


func _stop_loop(slot: String) -> void:
	var event: Object = loops[slot].event
	event.stop(0)
	event.release()
	loops.erase(slot)


func _release_banks() -> void:
	for slot: String in loops.keys():
		_stop_loop(slot)
	descriptions.clear()
	while not banks.is_empty():
		banks.pop_back()


func _exit_tree() -> void:
	_release_banks()
