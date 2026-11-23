extends RefCounted

const TEST_SCENE := "res://battle/stage.tscn"
const PRESET_PATH := "user://gm_battle_lineup.json"
const REPLAY_KEY := &"guildrun_gm_next_lineup"
const NO_CELL := Vector2i(-1, -1)

var fight: GuildrunEncounter
var stage: Node3D
var tree: SceneTree
var owns_pause := false
var manual_casts := false
var visual_frames := 0
var round_lineup: Dictionary = {}
var _borrower: GuildrunBoardUnit
var _borrowed_original := -1
var _particle_script: Script = load("res://battle/revival_effect.gd")


func bind(encounter: GuildrunEncounter) -> void:
	fight = encounter
	stage = fight._stage
	tree = fight.get_tree()


func is_test_scene() -> bool:
	return stage.get_parent() == tree.root and stage.scene_file_path == TEST_SCENE and fight.first_shop == null


func can_edit() -> bool:
	return is_test_scene() and fight.phase in [GuildrunEncounter.Phase.PICK, GuildrunEncounter.Phase.PLACE]


func configure_unit(hero: bool, id: int, cell: Vector2i, facing: int = 0) -> String:
	if not can_edit():
		return "请在独立测试场景的布阵阶段编辑。"
	var catalog: Dictionary = stage._heroes if hero else stage._enemies
	if not catalog.has(id):
		return "找不到该单位。"
	if not fight._grid.contains(cell) or fight._grid.occupants.has(cell):
		return "请选一个有效的空格。"
	if hero and is_instance_valid(fight.board_hero(id)):
		return "这名英雄已在场。"
	var unit: GuildrunBoardUnit = stage.deploy_hero(id, cell) if hero else stage.spawn_unit(catalog[id], cell, facing, false)
	unit.direction = facing
	unit.rotation.y = float(facing) * TAU / 6.0 + (0.0 if hero else PI)
	fight._register(unit)
	_sync_placement()
	return "已布置 %s。" % _unit_label(unit)


func move_unit(unit: GuildrunBoardUnit, cell: Vector2i) -> String:
	if not can_edit() or not is_instance_valid(unit):
		return "请选择布阵中的单位。"
	if not fight._grid.contains(cell) or fight._grid.occupants.has(cell):
		return "目标格不存在或已被占用。"
	fight._claim_cell(unit, cell)
	unit.position = GuildrunBattleGrid.center(cell)
	return "已移动到 (%d, %d)。" % [cell.x, cell.y]


func remove_unit(unit: GuildrunBoardUnit) -> String:
	if not can_edit() or not is_instance_valid(unit):
		return "请选择布阵中的单位。"
	_remove(unit)
	_sync_placement()
	return "已移除选中单位。"


func _remove(unit: GuildrunBoardUnit) -> void:
	fight._grid.occupants.erase(unit.grid_cell)
	fight._units.erase(unit)
	var bar: Control = fight._bars.get(unit)
	fight._bars.erase(unit)
	if is_instance_valid(bar):
		bar.hide()
		bar.queue_free()
	if fight._hero == unit:
		fight._hero = null
	unit.hide()
	unit.queue_free()


func clear_board() -> String:
	if not can_edit():
		return "只能在布阵阶段清空棋盘。"
	for unit: GuildrunBoardUnit in fight._units.duplicate():
		_remove(unit)
	_sync_placement()
	return "棋盘已清空。"


func _sync_placement() -> void:
	if not is_instance_valid(fight._hero):
		for unit: GuildrunBoardUnit in fight._units:
			if unit.is_hero:
				fight._hero = unit
				break
	var has_hero := is_instance_valid(fight._hero)
	fight._choices.visible = not has_hero
	fight._fight.visible = has_hero
	fight.phase = GuildrunEncounter.Phase.PLACE if has_hero else GuildrunEncounter.Phase.PICK


func _unit_label(unit: GuildrunBoardUnit) -> String:
	var id := int(unit.stat("Id")._sequentialId)
	var key := ("Heroes.Hero_%d.Name" if unit.is_hero else "Enemies.Enemy_%d.Name") % id
	var title := TranslationServer.translate(key)
	return str(id) if title == key else str(title)


func snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	for unit: GuildrunBoardUnit in fight._units:
		rows.append({"hero": unit.is_hero, "id": int(unit.stat("Id")._sequentialId),
			"x": unit.grid_cell.x, "y": unit.grid_cell.y, "facing": unit.direction})
	return {"stage": stage.stage_id, "run_seed": stage.run_seed, "units": rows}


func _valid_layout(layout: Dictionary) -> bool:
	if int(layout.get("stage", -1)) != stage.stage_id or not layout.get("units") is Array:
		return false
	var seed: Variant = layout.get("run_seed")
	if seed != null:
		if not (seed is int or seed is float) or float(seed) != floorf(float(seed)) or seed < -2147483648 or seed > 2147483647:
			return false
	var cells: Dictionary = {}
	var heroes: Dictionary = {}
	for row: Variant in layout.units:
		if not row is Dictionary or not row.get("hero") is bool:
			return false
		for field: String in ["id", "x", "y", "facing"]:
			var number: Variant = row.get(field)
			if not (number is int or number is float) or not is_equal_approx(float(number), floorf(float(number))):
				return false
		var id := int(row.id)
		var cell := Vector2i(int(row.x), int(row.y))
		var catalog: Dictionary = stage._heroes if row.hero else stage._enemies
		if not catalog.has(id) or not fight._grid.contains(cell) or cells.has(cell) or int(row.facing) not in range(6):
			return false
		cells[cell] = true
		if row.hero:
			if heroes.has(id):
				return false
			heroes[id] = true
	return true


func apply_layout(layout: Dictionary) -> String:
	if not can_edit() or not _valid_layout(layout):
		return "阵容无效，或当前阶段不能载入。"
	clear_board()
	stage.run_seed = int(layout.run_seed) if layout.get("run_seed") != null else null
	for row: Dictionary in layout.units:
		configure_unit(row.hero, int(row.id), Vector2i(int(row.x), int(row.y)), int(row.facing))
	return "已载入 %d 个单位。" % layout.units.size()


func apply_pending_layout() -> String:
	if not is_test_scene() or not tree.has_meta(REPLAY_KEY):
		return ""
	var request: Dictionary = tree.get_meta(REPLAY_KEY)
	if request.source == stage.get_instance_id():
		return ""
	tree.remove_meta(REPLAY_KEY)
	return apply_layout(request.layout)


func save_layout() -> String:
	if not can_edit() and round_lineup.is_empty():
		return "没有可保存的测试阵容。"
	var temp := ProjectSettings.globalize_path("%s.%d.tmp" % [PRESET_PATH, OS.get_process_id()])
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return "无法写入本地阵容。"
	file.store_string(JSON.stringify(snapshot() if can_edit() else round_lineup))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temp, ProjectSettings.globalize_path(PRESET_PATH))
	if error != OK:
		DirAccess.remove_absolute(temp)
		return "保存阵容失败。"
	return "已保存本地测试阵容。"


func load_layout() -> String:
	if not FileAccess.file_exists(PRESET_PATH):
		return "还没有保存本地测试阵容。"
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRESET_PATH))
	if not saved is Dictionary or not is_test_scene() or not _valid_layout(saved):
		return "本地阵容损坏或属于其他关卡。"
	if can_edit():
		return apply_layout(saved)
	return reload_layout(saved)


func reload_layout(layout: Dictionary) -> String:
	if not is_test_scene():
		return "请在独立测试场景中复位。"
	if not layout.is_empty():
		tree.set_meta(REPLAY_KEY, {"source": stage.get_instance_id(), "layout": layout})
	set_paused(false)
	tree.reload_current_scene.call_deferred()
	return "正在重载场景。"


func start_battle(isolate: bool) -> String:
	if not is_test_scene():
		return "请在独立测试场景中运行自定义战斗。"
	if fight.phase == GuildrunEncounter.Phase.FIGHT and not fight._pending_battle_result.is_valid():
		if not isolate and not _restore_skill():
			return "等正在进行的施法、弹丸或持续范围效果结束后，再开启 AI。"
		manual_casts = isolate
		set_paused(isolate)
		return "已进入单招预览。" if isolate else "已启用自动战斗。"
	if not can_edit() or not is_instance_valid(fight._hero) or not fight._units.any(func(unit: GuildrunBoardUnit) -> bool: return not unit.is_hero):
		return "请先在棋盘放置至少一名英雄和一名敌人。"
	round_lineup = snapshot()
	manual_casts = isolate
	fight.start_fight()
	if fight.phase != GuildrunEncounter.Phase.FIGHT:
		manual_casts = false
		return "当前无法开战。"
	set_paused(isolate)
	return "已进入单招预览。" if isolate else "已开始自动战斗。"


func default_skill(unit: GuildrunBoardUnit) -> int:
	if unit.is_hero and not bool(unit.stat("StartWithActiveAbility")):
		return -1
	return int(unit.base_stats.get("_activeAbilityID", -1))


func cast(unit: GuildrunBoardUnit, ability_id: int, target: GuildrunBoardUnit = null) -> String:
	if not is_test_scene() or not is_instance_valid(unit) or unit.defeated:
		return "请选择独立测试场景里存活的施法单位。"
	if ability_id < 0:
		ability_id = default_skill(unit)
	if not stage._abilities.has(ability_id):
		return "这项技能在当前 Godot 构建中还不能执行。"
	if unit.is_casting() or _has_pending_skill(unit) or not _restore_skill():
		return "已有施法、弹丸或持续范围效果。请先继续或步进到结束。"
	if fight.phase != GuildrunEncounter.Phase.FIGHT:
		var result := start_battle(true)
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			return result
	if fight._pending_battle_result.is_valid():
		return "战斗正在结算。请先复位阵容。"
	manual_casts = true
	set_paused(true)
	if target == null or target.defeated:
		target = fight._nearest_enemy(unit)
	if target != null and target != unit:
		unit.face_point(target.position)
	_borrowed_original = default_skill(unit)
	_borrower = unit
	stage.configure_active_ability(unit, ability_id)
	unit.begin_active_ability(target, fight.battle_time_q16)
	if not unit.is_casting():
		_restore_skill()
		return "技能 %d 未进入施法。" % ability_id
	advance_visual(0.0)
	return "%s 已开始技能 %d。继续预览，或使用模拟步检查命中。" % [_unit_label(unit), ability_id]


func _has_pending_skill(unit: GuildrunBoardUnit) -> bool:
	return fight._shots.any(func(shot: Dictionary) -> bool: return shot.source == unit) \
			or fight._strike_areas.any(func(area: Dictionary) -> bool: return area.source == unit)


func _restore_skill() -> bool:
	if not is_instance_valid(_borrower):
		return true
	if (not _borrower.defeated and _borrower.is_casting()) or _has_pending_skill(_borrower):
		return false
	stage.configure_active_ability(_borrower, _borrowed_original)
	_borrower = null
	return true


func clip_names(unit: GuildrunBoardUnit) -> Array[String]:
	var names: Array[String] = []
	if is_instance_valid(unit):
		for player: AnimationPlayer in unit._motion_players:
			for clip: String in player.get_animation_list():
				if clip != "RESET" and clip not in names:
					names.append(clip)
	names.sort()
	return names


func play_clip(unit: GuildrunBoardUnit, clip: String) -> String:
	if not is_test_scene() or clip not in clip_names(unit):
		return "请选择该角色已导入的动作。"
	set_paused(true)
	for player: AnimationPlayer in unit._motion_players:
		if player.has_animation(clip):
			player.play(clip, 0.0)
			player.seek(0.0, true)
	advance_visual(0.0)
	return "已定位动作起帧。可用画面步进检查姿势。"


func seek_clip(unit: GuildrunBoardUnit, seconds: float) -> String:
	if not is_test_scene() or not is_instance_valid(unit) or not tree.paused:
		return "暂停后选择一个正在播放动作的单位。"
	for player: AnimationPlayer in unit._motion_players:
		if player.is_playing():
			player.seek(minf(seconds, player.current_animation_length), true)
	advance_visual(0.0)
	return "已定位动作时间。"


func set_paused(enabled: bool) -> String:
	if tree.paused and not owns_pause:
		return "暂停由其他系统控制。"
	tree.paused = enabled
	owns_pause = enabled
	return "已暂停。" if enabled else "已继续。"


func step_battle(count: int) -> String:
	if fight.phase != GuildrunEncounter.Phase.FIGHT or fight._pending_battle_result.is_valid():
		return "暂无可推进的战斗步。"
	if fight._tutorial_paused() or (tree.paused and not owns_pause):
		return "请先结束教程或外部暂停。"
	set_paused(true)
	var start := fight._frame
	for i in count:
		var running := fight._advance_battle_tick(GuildrunEncounter.BATTLE_STEP_SECONDS)
		advance_visual(GuildrunEncounter.BATTLE_STEP_SECONDS)
		if not running:
			break
	return "已推进 %d 个战斗步及对应画面。" % (fight._frame - start)


func step_visual(fps: float) -> String:
	if tree.paused and not owns_pause:
		return "暂停由其他系统控制。"
	set_paused(true)
	advance_visual(1.0 / fps)
	visual_frames += 1
	return "已推进 1 个表现帧，战斗逻辑时钟保持不变。"


func advance_visual(seconds: float) -> void:
	var delta := seconds / float(fight.simulation_speed.multiplier())
	fight._effect_scene_time += seconds
	for unit: GuildrunBoardUnit in fight._units:
		for player: AnimationPlayer in unit._motion_players:
			player.advance(delta)
		for skeleton: Skeleton3D in unit.find_children("*", "Skeleton3D", true, false):
			skeleton.force_update_all_bone_transforms()
			for mount: BoneAttachment3D in skeleton.find_children("*", "BoneAttachment3D", true, false):
				mount.on_skeleton_update()
	if seconds > 0.0:
		var board: Node3D = stage.get_node("Battle/BattleGrid")
		for effect: Node3D in board.find_children("*", "Node3D", true, false):
			if effect.get_script() == _particle_script and not effect.is_queued_for_deletion():
				effect._process(delta)
