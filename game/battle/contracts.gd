extends Control

var selecting := false
var selected := 0
var progress_path := "user://forest_contracts.cfg"
var _rules = load("res://battle/difficulty_rules.gd")
var _progress: ConfigFile
var _records: Array
var _intro_comic: Control
var _opening = load("res://battle/opening_draft.gd")


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--stage="):
			_start_game.call_deferred(false)
			return
	_progress = _rules.read_progress(progress_path)
	$Sound.start_menu(_rules.data().menu_audio)
	_records = _rules.data().contracts.duplicate()
	_records.append({"name": "UI.RiftSealingProtocol", "icon": _rules.data().red_rift.icon})
	var group := ButtonGroup.new()
	for i in _records.size():
		var choice := Button.new()
		choice.toggle_mode = true
		choice.button_group = group
		choice.expand_icon = true
		choice.icon = load(_records[i].icon)
		choice.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		choice.custom_minimum_size = Vector2(34, 80)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.tooltip_text = tr(_records[i].name)
		choice.accessibility_name = choice.tooltip_text
		choice.modulate.a = 0.45 if _locked(i) else 1.0
		choice.pressed.connect(select.bind(i))
		$Panel/Options.add_child(choice)
	$TitleMenu/Start.pressed.connect(_start_from_title)
	$TitleMenu/Quit.pressed.connect(func(): get_tree().quit())
	$Panel/Actions/Back.pressed.connect(_show_title)
	$Panel/Actions/Play.pressed.connect(_start_game)
	if selecting:
		show_contracts()
	elif not _opening.past_tutorial(_progress) and not _progress.get_value("opening", "intro_comic_seen", false):
		_play_intro_comic()


func _play_intro_comic() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/intro_comic.json"))
	_intro_comic = load("res://UI/intro_comic.gd").new()
	_intro_comic.name = "Canvas_Comic"
	_intro_comic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intro_comic.completed.connect(func():
		$Sound.stop_intro_comic()
		_opening.save_value(_progress, progress_path, "intro_comic_seen", true)
		_intro_comic = null)
	add_child(_intro_comic)
	$Sound.play_intro_comic(data.sound)


func _start_from_title() -> void:
	if is_instance_valid(_intro_comic):
		return
	if _opening.past_tutorial(_progress):
		show_contracts()
	else:
		selected = 0
		_launch_stage(true, true)


func show_contracts() -> void:
	selecting = true
	$TitleMenu.hide()
	$Panel.show()
	$Backdrop.texture = load("res://sprites/sharedassets2_134.png")
	select(_rules.unlocked_through(_progress))


func _show_title() -> void:
	selecting = false
	$Panel.hide()
	$TitleMenu.show()
	$Backdrop.texture = load("res://sprites/sharedassets2_132.png")


func _locked(index: int) -> bool:
	if index == _rules.data().contracts.size():
		return int(_progress.get_value("forest", "highest_beaten", -1)) < index - 1
	return index > _rules.unlocked_through(_progress)


func select(index: int) -> void:
	if index < 0 or index >= _records.size():
		return
	selected = index
	$Panel/Options.get_child(index).set_pressed_no_signal(true)
	$Panel/Name.text = tr(_records[index].name)
	var lines := PackedStringArray()
	var locked := _locked(index)
	if locked:
		lines.append(tr("UI.Difficulty.LockedDecription"))
	if index == _rules.data().contracts.size():
		for key: String in load("res://battle/red_rift.gd").NAME_KEYS:
			lines.append(tr("UI.RiftSealingProtocol." + key).format([
					int(_rules.data().red_rift.ChallengeMaxHeroDeaths) if key == "HeroDeath" else "0/3"]))
		$Panel/Scroll/Details.text = "\n".join(lines)
		$Panel/Scroll.scroll_vertical = 0
		$Panel/Stats.text = tr("UI.Leaderboard.ChallengeStreak").format([int(_progress.get_value("red_rift", "streak", 0))])
		$Panel/Actions/Play.disabled = locked
		return
	for i in range(0 if index == 0 else 1, index + 1):
		lines.append(tr(_records[i].description))
	$Panel/Scroll/Details.text = "\n".join(lines)
	$Panel/Scroll.scroll_vertical = 0
	$Panel/Stats.text = tr("UI.Difficulty.TotalWins").format([int(_progress.get_value("forest", "wins_%d" % index, 0))]) + "     " + tr("UI.Difficulty.EndlessBonus").format([index * int(_rules.data().score_per_difficulty)])
	$Panel/Actions/Play.disabled = locked


func _start_game(track_progress := true) -> void:
	if track_progress and (is_instance_valid(_intro_comic) or not selecting or _locked(selected)):
		return
	_launch_stage(track_progress)


func _launch_stage(track_progress: bool, first_tutorial := false) -> void:
	var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.challenge_run = selected == _rules.data().contracts.size()
	stage.contract_index = mini(selected, _rules.data().contracts.size() - 1)
	stage.track_contract_progress = track_progress
	stage.show_founding_comic = track_progress
	stage.show_first_fight_tutorial = first_tutorial
	stage.contract_progress_path = progress_path
	get_tree().change_scene_to_node(stage)
