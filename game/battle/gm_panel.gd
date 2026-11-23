extends CanvasLayer

const NO_CELL := Vector2i(-1, -1)
const HELP := "hero / enemy <ID> <X> <Y>    move <X> <Y>    remove\ncast <技能ID>    anim <片段名>    frame    step [次数]\nstart    pause    resume    speed <1|1.6|2.5>    seed <数字>\nsave    load    reset    mana    heal    status    help"

var lab: RefCounted = load("res://battle/gm_battle_lab.gd").new()
var _encounter: GuildrunEncounter
var _panel: PanelContainer
var _tabs: TabContainer
var _status: Label
var _feedback: Label
var _command: LineEdit
var _actor: OptionButton
var _target: OptionButton
var _skill: OptionButton
var _clip: OptionButton
var _seek: SpinBox
var _fps: SpinBox
var _selection: Label
var _faction: OptionButton
var _catalog: OptionButton
var _filter: LineEdit
var _facing: SpinBox
var _grid_buttons: Dictionary[Vector2i, Button] = {}
var _units: Array[GuildrunBoardUnit] = []
var _cell := NO_CELL


func bind(encounter: GuildrunEncounter) -> void:
	_encounter = encounter
	lab.bind(encounter)


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -454
	_panel.offset_right = -12
	_panel.offset_top = 57
	_panel.offset_bottom = -16
	_panel.theme = _create_theme()
	var body := VBoxContainer.new()
	_panel.add_child(body)
	var heading := Label.new()
	heading.text = "战斗测试台 · F2"
	heading.add_theme_font_size_override("font_size", 19)
	body.add_child(heading)
	_status = Label.new()
	body.add_child(_status)
	var timebar := _row(body)
	_button(timebar, "暂停", "Pause", _submit.bind("pause"))
	_button(timebar, "继续", "Resume", _submit.bind("resume"))
	_button(timebar, "模拟 +1 步", "BattleStep", _submit.bind("step"))
	_button(timebar, "画面 +1 帧", "VisualStep", _submit.bind("frame"))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_tabs)
	_build_actions(_tab("动作与技能"))
	_build_lineup(_tab("战斗阵容"))
	_build_commands(_tab("指令"))
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_feedback)
	hide()
	_restore_pending.call_deferred()


func _create_theme() -> Theme:
	var font := FontVariation.new()
	font.base_font = _panel.get_theme_default_font()
	font.fallbacks = [load("res://fonts/noto/NotoSansSC-Regular.ttf") as Font]
	var result := Theme.new()
	result.default_font = font
	result.default_font_size = 14
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.06, 0.09, 0.12, 0.97)
	background.border_color = Color(0.30, 0.44, 0.47)
	background.set_border_width_all(1)
	background.set_corner_radius_all(8)
	background.content_margin_left = 12
	background.content_margin_right = 12
	background.content_margin_top = 10
	background.content_margin_bottom = 9
	result.set_stylebox("panel", "PanelContainer", background)
	return result


func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return body


func _row(parent: Container) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	return row


func _label(parent: Container, title: String) -> Label:
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 70
	parent.add_child(label)
	return label


func _select(parent: Container, title: String, node_name: String) -> OptionButton:
	var row := _row(parent)
	_label(row, title)
	var option := OptionButton.new()
	option.name = node_name
	option.fit_to_longest_item = false
	option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option


func _number(parent: Container, min_value: float, max_value: float, value: float, increment: float) -> SpinBox:
	var control := SpinBox.new()
	control.min_value = min_value
	control.max_value = max_value
	control.step = increment
	control.value = value
	parent.add_child(control)
	return control


func _button(parent: Container, title: String, node_name: String, action: Callable) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = title
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 26
	button.pressed.connect(action)
	parent.add_child(button)


func _build_actions(body: VBoxContainer) -> void:
	_actor = _select(body, "操作单位", "Actor")
	_actor.item_selected.connect(_refresh_clips.unbind(1))
	_target = _select(body, "指定目标", "Target")
	var match_actions := _row(body)
	_button(match_actions, "开启自动战斗", "StartBattle", _submit.bind("start"))
	_button(match_actions, "复位阵容", "ResetLineup", _submit.bind("reset"))
	_skill = _select(body, "技能", "Skill")
	_skill.add_item("角色原有技能", -1)
	var ids: Array = _encounter._stage._abilities.keys()
	ids.sort()
	for id: int in ids:
		var entry: Dictionary = _encounter._stage._abilities[id]
		_skill.add_item("%s  [%d]" % [_localized("ActiveAbilities.ActiveAbility_%d.Name" % id, entry.kind), id], id)
	_button(body, "触发所选技能并暂停", "CastSkill", _cast_selected)
	_clip = _select(body, "动作片段", "Clip")
	_button(body, "播放所选动作的起帧", "PlayClip", _play_selected)
	var seek_row := _row(body)
	_label(seek_row, "动作秒数")
	_seek = _number(seek_row, 0.0, 600.0, 0.0, 0.01)
	_button(seek_row, "定位", "SeekClip", _seek_selected)
	var frames := _row(body)
	_label(frames, "画面 FPS")
	_fps = _number(frames, 1.0, 240.0, 60.0, 1.0)
	_button(frames, "法力全满", "RefillMana", _submit.bind("mana"))
	_button(frames, "生命全满", "RefillHealth", _submit.bind("heal"))


func _build_lineup(body: VBoxContainer) -> void:
	_selection = _label(body, "未选格")
	var grid := GridContainer.new()
	grid.columns = _encounter._grid.size.x
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	body.add_child(grid)
	for y in range(_encounter._grid.size.y - 1, -1, -1):
		for x in _encounter._grid.size.x:
			var cell := Vector2i(x, y)
			var button := Button.new()
			button.custom_minimum_size.y = 24
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.toggle_mode = true
			button.add_theme_font_size_override("font_size", 10)
			button.pressed.connect(_choose_cell.bind(cell))
			grid.add_child(button)
			_grid_buttons[cell] = button
	var picking := _row(body)
	_button(picking, "选为操作单位", "ActorAtCell", _assign_cell.bind(false))
	_button(picking, "选为技能目标", "TargetAtCell", _assign_cell.bind(true))
	_faction = _select(body, "放置阵营", "Faction")
	_faction.add_item("我方英雄", 0)
	_faction.add_item("敌人", 1)
	_faction.item_selected.connect(_refresh_catalog.unbind(1))
	var filter_row := _row(body)
	_label(filter_row, "查找单位")
	_filter = LineEdit.new()
	_filter.placeholder_text = "输入名称或 ID"
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_child(_filter)
	_filter.text_changed.connect(_refresh_catalog.unbind(1))
	_catalog = _select(body, "单位", "Catalog")
	var deployment := _row(body)
	_label(deployment, "朝向 0–5")
	_facing = _number(deployment, 0.0, 5.0, 0.0, 1.0)
	_button(deployment, "放入选格", "PlaceUnit", _place_selected)
	var edits := _row(body)
	_button(edits, "将操作单位移到选格", "MoveUnit", _move_selected)
	_button(edits, "移除选格单位", "RemoveUnit", _remove_selected)
	_button(edits, "清空", "ClearBoard", _submit.bind("clear"))
	var presets := _row(body)
	_button(presets, "保存阵容", "SaveLineup", _submit.bind("save"))
	_button(presets, "载入阵容", "LoadLineup", _submit.bind("load"))


func _build_commands(body: VBoxContainer) -> void:
	_command = LineEdit.new()
	_command.name = "Command"
	_command.placeholder_text = "输入指令后按 Enter"
	_command.text_submitted.connect(_submit)
	body.add_child(_command)
	var help := _label(body, HELP)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var seed_row := _row(body)
	_label(seed_row, "运行种子")
	var seed := LineEdit.new()
	seed.placeholder_text = "例如 262144"
	seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed)
	_button(seed_row, "应用", "SetSeed", func() -> void: _submit("seed " + seed.text))


func _restore_pending() -> void:
	var result: String = lab.apply_pending_layout()
	if not result.is_empty():
		show()
		_refresh_catalog()
		_report(result)


func captures(event: InputEvent) -> bool:
	if not visible:
		return false
	if event is InputEventMouse:
		return _panel.get_global_rect().has_point(event.position)
	var focused := get_viewport().gui_get_focus_owner()
	return is_instance_valid(focused) and _panel.is_ancestor_of(focused)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		visible = not visible
		if visible:
			_refresh_units()
			_refresh_catalog()
		get_viewport().set_input_as_handled()
	elif visible and _tabs.current_tab == 1 and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not captures(event) \
			and get_viewport().get_camera_3d() != null:
		var cell := _encounter._cell_at(event.position, false)
		if _encounter._grid.contains(cell):
			_choose_cell(cell)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	if _unit_count_changed():
		_refresh_units()
	if _tabs.current_tab == 1:
		_refresh_cell_labels()
	var mode := "单招" if lab.manual_casts else "自动"
	var speed := "暂停" if get_tree().paused else "%.1f×" % _encounter.simulation_speed.multiplier()
	var actor := _chosen(_actor)
	var motion := ""
	if is_instance_valid(actor) and not actor._motion_players.is_empty():
		var player := actor._motion_players[0]
		motion = " · 动作 %.3fs" % player.current_animation_position if player.is_playing() else ""
	var unit_stats := ""
	if is_instance_valid(actor):
		unit_stats = " · HP %d/%d · MP %d" % [actor.health, actor.max_health, actor.mana]
	var seed := "战斗种子 %d" % _encounter.combat_seed
	if lab.can_edit():
		var value: Variant = _encounter._stage.run_seed
		seed = "运行种子 %s" % ("默认" if value == null else str(int(value)))
	_status.text = "%s · %s · 步 %d · 画面单步 %d\n%s%s%s" % [
		mode, speed, _encounter._frame, lab.visual_frames, seed, motion, unit_stats]


func _exit_tree() -> void:
	if lab.owns_pause:
		get_tree().paused = false


func _unit_count_changed() -> bool:
	if _units.size() != _encounter._units.size():
		return true
	for unit: GuildrunBoardUnit in _units:
		if not is_instance_valid(unit) or unit not in _encounter._units:
			return true
	return false


func _refresh_units() -> void:
	var previous_actor := _chosen(_actor)
	var previous_target := _chosen(_target)
	_units.assign(_encounter._units)
	_actor.clear()
	_target.clear()
	_target.add_item("自动按技能规则选目标")
	for unit: GuildrunBoardUnit in _units:
		var id := int(unit.stat("Id")._sequentialId)
		var text := "%s %s (%d, %d)" % ["我方" if unit.is_hero else "敌方", _unit_name(unit.is_hero, id), unit.grid_cell.x, unit.grid_cell.y]
		_actor.add_item(text)
		_target.add_item(text)
	_actor.select(_units.find(previous_actor if is_instance_valid(previous_actor) else _encounter._hero))
	if _actor.selected < 0 and not _units.is_empty():
		_actor.select(0)
	_target.select(_units.find(previous_target) + 1)
	_refresh_clips()
	_refresh_cell_labels()


func _chosen(option: OptionButton) -> GuildrunBoardUnit:
	var index := option.selected - (1 if option == _target else 0)
	if index < 0 or index >= _units.size() or not is_instance_valid(_units[index]):
		return null
	return _units[index]


func _refresh_clips() -> void:
	var last := _clip.get_item_text(_clip.selected) if _clip.selected >= 0 else ""
	_clip.clear()
	for clip: String in lab.clip_names(_chosen(_actor)):
		_clip.add_item(clip)
		if clip == last:
			_clip.select(_clip.item_count - 1)


func _localized(key: String, fallback: String) -> String:
	var value := String(TranslationServer.translate(key))
	return fallback if value == key else value


func _unit_name(hero: bool, id: int) -> String:
	return _localized(("Heroes.Hero_%d.Name" if hero else "Enemies.Enemy_%d.Name") % id, str(id))


func _refresh_catalog() -> void:
	var hero := _faction.selected == 0
	var catalog: Dictionary = _encounter._stage._heroes if hero else _encounter._stage._enemies
	var filter := _filter.text.strip_edges().to_lower()
	var previous_id := _catalog.get_selected_id()
	var ids: Array = catalog.keys()
	ids.sort()
	_catalog.clear()
	for id: int in ids:
		var label := "%s  [%d]" % [_unit_name(hero, id), id]
		if filter.is_empty() or label.to_lower().contains(filter):
			_catalog.add_item(label, id)
			if id == previous_id:
				_catalog.select(_catalog.item_count - 1)


func _refresh_cell_labels() -> void:
	for cell: Vector2i in _grid_buttons:
		if not _encounter._grid.contains(cell):
			_grid_buttons[cell].hide()
			continue
		var unit: GuildrunBoardUnit = _encounter._grid.occupants.get(cell)
		var button := _grid_buttons[cell]
		button.set_pressed_no_signal(cell == _cell)
		if is_instance_valid(unit):
			var id := int(unit.stat("Id")._sequentialId)
			button.text = ("我%d" if unit.is_hero else "敌%d") % id
			button.tooltip_text = "%s · (%d, %d)" % [_unit_name(unit.is_hero, id), cell.x, cell.y]
			button.modulate = Color(0.72, 0.92, 1.0) if unit.is_hero else Color(1.0, 0.74, 0.69)
		else:
			button.text = "%d,%d" % [cell.x, cell.y]
			button.tooltip_text = ""
			button.modulate = Color.WHITE


func _choose_cell(cell: Vector2i) -> void:
	_cell = cell
	_selection.text = "已选格 (%d, %d)" % [cell.x, cell.y]
	_refresh_cell_labels()


func _assign_cell(as_target: bool) -> void:
	var unit: GuildrunBoardUnit = _encounter._grid.occupants.get(_cell)
	var index := _units.find(unit)
	if index < 0:
		_report("请先选择有单位的格子。")
		return
	if as_target:
		_target.select(index + 1)
	else:
		_actor.select(index)
		_refresh_clips()
	_tabs.current_tab = 0


func _place_selected() -> void:
	if _catalog.selected < 0:
		_report("请先从清单选择单位。")
		return
	_report(lab.configure_unit(_faction.selected == 0, _catalog.get_selected_id(), _cell, int(_facing.value)))


func _move_selected() -> void:
	_report(lab.move_unit(_chosen(_actor), _cell))


func _remove_selected() -> void:
	_report(lab.remove_unit(_encounter._grid.occupants.get(_cell)))


func _cast_selected() -> void:
	var ability_id := -1 if _skill.selected == 0 else _skill.get_selected_id()
	_report(lab.cast(_chosen(_actor), ability_id, _chosen(_target)))


func _play_selected() -> void:
	if _clip.selected >= 0:
		_report(lab.play_clip(_chosen(_actor), _clip.get_item_text(_clip.selected)))
	else:
		_report("当前单位没有已导入的动作。")


func _seek_selected() -> void:
	_report(lab.seek_clip(_chosen(_actor), _seek.value))


func _report(result: String) -> void:
	_feedback.text = result
	_refresh_units()


func _submit(line: String) -> void:
	if _command.has_focus():
		_command.clear()
	_report(execute_command(line))


func execute_command(line: String) -> String:
	var words := line.strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	var action := words[0].to_lower()
	var argument := words[1] if words.size() >= 2 else ""
	match action:
		"help": return HELP
		"status": return _status.text
		"pause", "resume": return lab.set_paused(action == "pause")
		"frame": return lab.step_visual(_fps.value)
		"step":
			var count := 1 if argument.is_empty() else argument.to_int()
			return lab.step_battle(count) if count >= 1 and count <= 120 and (argument.is_empty() or argument.is_valid_int()) else "单步次数须为 1–120。"
		"start": return lab.start_battle(false)
		"save": return lab.save_layout()
		"load": return lab.load_layout()
		"reset":
			return lab.reload_layout(lab.round_lineup) if not lab.round_lineup.is_empty() else "开战前还没有可复位的阵容。"
		"reload": return lab.reload_layout({})
		"clear": return lab.clear_board()
		"remove": return lab.remove_unit(_chosen(_actor))
		"seed":
			if not lab.can_edit() or not argument.is_valid_int() or absi(argument.to_int()) > 2147483647:
				return "请在布阵阶段输入 32 位整数种子。"
			_encounter._stage.run_seed = argument.to_int()
			return "已设置运行种子。"
		"hero", "enemy":
			if words.size() != 4 or not words[1].is_valid_int() or not words[2].is_valid_int() or not words[3].is_valid_int():
				return "请输入单位 ID、X 和 Y。"
			return lab.configure_unit(action == "hero", words[1].to_int(), Vector2i(words[2].to_int(), words[3].to_int()))
		"move":
			if words.size() != 3 or not words[1].is_valid_int() or not words[2].is_valid_int():
				return "请输入 X 和 Y。"
			return lab.move_unit(_chosen(_actor), Vector2i(words[1].to_int(), words[2].to_int()))
		"cast":
			if not argument.is_valid_int():
				return "请输入技能 ID。"
			return lab.cast(_chosen(_actor), argument.to_int(), _chosen(_target))
		"anim":
			return lab.play_clip(_chosen(_actor), line.strip_edges().substr(words[0].length()).strip_edges())
		"speed":
			var index := ["1", "1.6", "2.5"].find(argument)
			if index < 0:
				return "可用倍速为 1、1.6、2.5。"
			_encounter.simulation_speed._set_speed(index, false)
			return "已设置速度。"
		"pick":
			if _encounter.phase == GuildrunEncounter.Phase.PICK and argument.is_valid_int():
				_encounter.select_hero(argument.to_int())
				_refresh_units()
			return "已处理选将请求。"
		"mana", "heal":
			var unit := _encounter.board_hero(argument.to_int()) if argument.is_valid_int() else _chosen(_actor)
			if not is_instance_valid(unit) or unit.defeated:
				return "请选择存活的单位。"
			if action == "heal":
				unit.heal(unit.max_health - unit.health)
			else:
				unit.mana = int(unit.stat("MaxMana"))
				unit.set_meta("mana", unit.mana)
			return "已恢复。"
		_:
			return "未知指令，输入 help 查看。"
