extends SceneTree

var _failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var settings_path := "user://simulation_speed.cfg"
	var settings_before := FileAccess.get_file_as_bytes(settings_path) if FileAccess.file_exists(settings_path) else PackedByteArray()
	var settings_existed := FileAccess.file_exists(settings_path)
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(26)
	fight.simulation_speed.select_manual(2)
	fight.start_fight()
	fight._physics_process(fight.BATTLE_STEP_SECONDS * 2.0)
	expect(fight._frame == 5, "2.5× should produce five fixed ticks")
	expect(fight.battle_time_q16 == 5 * fight.BATTLE_STEP_Q16, "speed should preserve the Q16 step")
	fight.simulation_speed.set_automatic(true)
	fight._physics_process(fight.BATTLE_STEP_SECONDS)
	expect(fight._frame == 6 and fight.simulation_speed.multiplier() == 1.6, "first AUTO tick should ramp to 1.6×")
	fight.battle_time_q16 = (20 << 16) - fight.BATTLE_STEP_Q16
	fight._physics_process(fight.BATTLE_STEP_SECONDS)
	expect(fight._frame == 7 and fight.simulation_speed.multiplier() == 2.5, "AUTO should ramp at 20 simulated seconds")
	expect(FileAccess.file_exists(settings_path) == settings_existed, "headless setting controls must not create live settings")
	if settings_existed:
		expect(FileAccess.get_file_as_bytes(settings_path) == settings_before, "headless setting controls must not overwrite live settings")
	stage.free()
	if not _failed:
		print("Battle speed integration checks passed.")
	quit(1 if _failed else 0)


func expect(condition: bool, failure: String) -> void:
	if not condition:
		push_error(failure)
		_failed = true
