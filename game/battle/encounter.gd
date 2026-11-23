class_name GuildrunEncounter
extends Node

enum Phase { PICK, PLACE, FIGHT, RESULT, SHOP, CROSSROADS, EVENT, RELIC_REWARD, END_SCREEN }

# BattleSimulationData.UpdateInterval in Steam build 26551710.
const BATTLE_STEP_Q16 := 0x888
const BATTLE_STEP_SECONDS := BATTLE_STEP_Q16 / 65536.0
const RANK_AURA_INTERVAL_Q16 := 65536
const RANK_AURA_DAMAGE_Q16 := 1966
const VINDICTIVE_SHIELD_DURATION_Q16 := 10 << 16
# RelicEffectsProvider.PopulateEpic maps each reserve class to a stat and an amount per rank.
const RESERVE_PRISMS := {
	3051: {7: ["Magic", 20], 6: ["ManaRegen", 2]},
	3052: {4: ["Crit", 10], 5: ["AttackSpeed", 15], 1: ["Attack", 20]},
	3053: {2: ["Defense", 30], 3: ["MaxHealth", 200]},
}
const DRAGON_ATTACK_STATUS := {
	201: {"kind": 1, "base": 3, "magic_per_stack": 10},
	202: {"kind": 2, "base": 2, "magic_per_stack": 15},
	203: {"kind": 3, "base": 1, "magic_per_stack": 20},
}

var phase := Phase.PICK:
	set(value):
		if phase == value:
			return
		var leaving_result := phase == Phase.RESULT
		if phase == Phase.FIGHT:
			_pending_battle_result = Callable()
			for shot in _shots:
				var effect: Variant = shot.get("effect")
				if is_instance_valid(effect):
					effect.hide()
					effect.queue_free()
		phase = value
		if _stage == null or _stage.encounter != self:
			return
		_stage.set_panel_grade(phase == Phase.RESULT or phase == Phase.SHOP)
		if leaving_result:
			_stage.set_defeat_grade(false)
			_result_view.hide()
		if _stage.battle_camera == null:
			return
		match phase:
			Phase.PLACE: _stage.battle_camera.enter_placement()
			Phase.FIGHT: _stage.battle_camera.set_state("fight")
			Phase.RESULT: _stage.battle_camera.set_state("result")
			Phase.CROSSROADS: _stage.battle_camera.set_state("crossroads")
var _stage: Node3D
var _grid: GuildrunBattleGrid
var _javryn_action: GDScript = load("res://battle/javryn_action.gd")
var _area_ability_effects: GDScript = load("res://battle/area_ability_effects.gd")
var _deployment_grid_view: Node3D
var _hero: GuildrunBoardUnit
var _units: Array[GuildrunBoardUnit] = []
var _planned_moves: Dictionary[GuildrunBoardUnit, Dictionary] = {}
var _path_forecasts: Dictionary[GuildrunBoardUnit, Vector2i] = {}
var _shots: Array[Dictionary] = []
var _specialization_stat_effects: Array[Dictionary] = []
var _projectile_effects: Node3D
var _projectile_vfx: Dictionary[int, Dictionary] = {}
var _projectile_targets: Dictionary = {}
var _projectile_target_bones: Dictionary = {}
var _gained_items: Array[int] = []
var _drags: Array[Dictionary] = []
var _strike_areas: Array[Dictionary] = []
var _bars: Dictionary = {}
var _ui := Control.new()
var _choices := HBoxContainer.new()
var _founding_comic: Control
var _first_tutorial: RefCounted
var _combat_tracker_guide: RefCounted
var _combat_tracker_guide_due := false
var _tutorial_mana_seen := false
var _tutorial_mana_pending := false
var _tutorial_grid_visible := false
var _fight := Button.new()
var _result: Label
var _result_view: Control
var _result_rewards: Array[Dictionary] = []
var _continue := Button.new()
var _summary_button: Button
var _floor_label := Label.new()
var _anchor_warning: Label
var _endless_won := false
var first_shop: GuildrunFirstShop
var crossroads: GuildrunFirstCrossroads
var _equipment_panel: GuildrunEquipmentPanel
var _reserve_panel: Control
var _bottom_roster: Control
var _reserve_toggle := Button.new()
var _drag_portrait := TextureRect.new()
const NO_SLOT := Vector2i(-2, -2)
var _selected_slot := NO_SLOT
var _pressed_slot := NO_SLOT
var _pressed_at := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _combat_rng: RefCounted = load("res://battle/combat_random.gd").new()
var combat_seed: int
var _frame := 0
var _deaths_this_step: Dictionary[GuildrunBoardUnit, bool] = {}
var battle_time_q16 := 0
var _effect_scene_time := Time.get_ticks_usec() / 1000000.0
var _run_battle_time_q16: int = 0
var _completed_battles: int = 0
var _pending_battle_result: Callable
var _battle_end_remaining := 0.0
var _storm_start_q16 := 0
var _storm_damage_timer_q16 := 0
var _storm_damage := 0
var battle_statistics: GuildrunBattleStatistics
var last_battle_statistics: Dictionary = {}
const RANK_ATTACK_CONDITION := preload("res://battle/rank_attack_condition.gd")
var _rank_wallet: RefCounted = load("res://battle/rank_combat_wallet.gd").new()
var total_stall_triggers := 0
var total_rush_triggers := 0
var _stall_before_combat := 0
var _rush_before_combat := 0
var _run_trigger_stats: RefCounted = load("res://battle/rank_run_trigger_stats.gd").new()
var _rank_growth: RefCounted = load("res://battle/rank_permanent_growth.gd").new()
var _rank_stall: RefCounted = load("res://battle/rank_stall_actions.gd").new()
var _rank_rush: RefCounted = load("res://battle/rank_rush_effects.gd").new()
var _keyword_clocks: RefCounted = load("res://battle/stall_triggers.gd").new()
var _rank_aura_timers: Dictionary[GuildrunBoardUnit, int] = {}
var _rank_vindictive_pending: Array[GuildrunBoardUnit] = []
var simulation_speed: RefCounted
var _gm_panel: CanvasLayer
var _choice_rows: Array
var _draft: RefCounted
var _regular_wins := 0
var _xp_recorded := false
var _trial_previous_deployment_limit := 0
var _trial_previous_reserves: Array[int] = []
var _trial_previous_formation: Dictionary = {}
var _formation: Dictionary = {}
var class_play_counts: Dictionary = {}
var challenge_modifier := 0
var rewind_available := true
var rewind_reserve := 0
var _pain_timer := 0


var trial: Dictionary = {}
var _trial_won: bool = false


func setup(stage: Node3D) -> void:
	_stage = stage
	var settings_path := "" if DisplayServer.get_name() == "headless" else "user://simulation_speed.cfg"
	simulation_speed = load("res://battle/simulation_speed.gd").new(PackedFloat64Array([1.0, 1.6, 2.5]), 20.0, settings_path)
	simulation_speed.speed_changed.connect(func(_index: int, _multiplier: float, _automatic: bool) -> void:
		_update_death_appearance_speed())
	var speed_settings_error: Error = simulation_speed.load_settings()
	if speed_settings_error != OK:
		push_warning("Could not load simulation speed settings: %s" % error_string(speed_settings_error))
	restore_rewind()
	_grid = stage.grid
	_deployment_grid_view = load("res://battle/deployment_grid_view.gd").new()
	_deployment_grid_view.name = "DeploymentGridView"
	stage.get_node("Battle/BattleGrid").add_child(_deployment_grid_view)
	_rng.seed = stage.stage_id
	_combat_rng.reseed(stage.stage_id)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(_ui)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if stage.battle_camera != null and stage.encounter == self:
		stage.battle_camera.projection_changed.connect(_update_crossroads_geometry)
	else:
		get_viewport().size_changed.connect(_update_crossroads_geometry)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tracker := (load("res://UI/battle_tracker.tscn") as PackedScene).instantiate()
	tracker.name = "BattleTracker"
	tracker.set_script(load("res://battle/battle_tracker_view.gd"))
	_ui.add_child(tracker)
	tracker.bind(self)
	var top := (load("res://UI/battle_top.tscn") as PackedScene).instantiate()
	top.name = "BattleTop"
	top.set_script(load("res://battle/battle_top_view.gd"))
	_ui.add_child(top)
	top.bind(self)
	_bottom_roster = (load("res://UI/battle_roster.tscn") as PackedScene).instantiate()
	_bottom_roster.name = "BottomRoster"
	_bottom_roster.set_script(load("res://battle/bottom_roster_view.gd"))
	_ui.add_child(_bottom_roster)
	_bottom_roster.bind(self)
	var bag := (load("res://UI/battle_inventory.tscn") as PackedScene).instantiate()
	bag.name = "InventorySidebar"
	bag.set_script(load("res://battle/inventory_sidebar_view.gd"))
	_ui.add_child(bag)
	bag.bind(self)
	_ui.add_child(_choices)
	_choices.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_choices.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_choices.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_choices.offset_bottom = -28
	_choices.offset_top = -170
	_choices.add_theme_constant_override("separation", 12)
	if stage.normal_opening:
		_draft = load("res://battle/opening_draft.gd").new()
		_draft.start(stage.contract_progress_path)
		_choice_rows = _draft.choices
	else:
		_choice_rows = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/first_battle.json"))
	_draw_choices()
	var button_view := (load("res://UI/battle_start_button.tscn") as PackedScene).instantiate()
	button_view.name = "StartBattleView"
	button_view.set_script(load("res://battle/start_battle_view.gd"))
	_ui.add_child(button_view)
	button_view.bind(_fight)
	load("res://fonts/local_cjk_font.gd").apply_to(button_view.text, true)
	var speed_view := (load("res://UI/battle_speed.tscn") as PackedScene).instantiate()
	speed_view.name = "BattleSpeedView"
	speed_view.set_script(load("res://battle/battle_speed_view.gd"))
	_ui.add_child(speed_view)
	speed_view.bind(self)
	_fight.hide()
	_fight.pressed.connect(start_fight)
	var reserve_title: Control = _bottom_roster.get_node(
			"Canvas/Root/CoreGameUI/BottomHeroPanel/HeroReservePanel/ReserveTitle")
	_bottom_roster.bind_hit_area(_reserve_toggle, reserve_title, tr("UI.HeroPanel.Reserve.Button"))
	_reserve_toggle.tooltip_text = tr("UI.HeroPanel.Reserve.Button")
	_reserve_toggle.focus_mode = Control.FOCUS_NONE
	_reserve_toggle.pressed.connect(_toggle_reserve)
	_reserve_toggle.hide()
	_ui.add_child(_drag_portrait)
	_drag_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drag_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_portrait.size = Vector2(48, 48)
	_drag_portrait.z_index = 20
	_drag_portrait.modulate.a = 0.85
	_drag_portrait.hide()
	_result_view = (load("res://UI/battle_result.tscn") as PackedScene).instantiate()
	_result_view.set_script(load("res://battle/battle_result_view.gd"))
	_ui.add_child(_result_view)
	_ui.move_child(_result_view, 0)
	_result_view.bind(self)
	_result = _result_view.title
	_result_view.bind_hit_area(_continue, _result_view.proceed_slot, tr("UI.Common.Continue"))
	_continue.hide()
	_continue.pressed.connect(open_first_shop)
	_summary_button = Button.new()
	_result_view.bind_hit_area(_summary_button, _result_view.proceed_slot, tr("UI.EndScreen.Summary"))
	_summary_button.hide()
	_summary_button.pressed.connect(_show_end_screen)
	if _stage.red_rift != null:
		_anchor_warning = button_view.warning_label()
	_ui.add_child(_floor_label)
	_floor_label.position = Vector2(28, 20)
	_floor_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_floor_label.hide()
	for unit: GuildrunBoardUnit in _grid.occupants.values():
		_register(unit)
	if stage.show_first_fight_tutorial and not stage.normal_opening:
		_start_first_tutorial()
	if stage.show_founding_comic:
		_play_founding_comic()
	elif _first_tutorial != null:
		_first_tutorial.notify_comics_finished()
	if OS.is_debug_build():
		_gm_panel = load("res://battle/gm_panel.gd").new()
		_gm_panel.name = "BattleGM"
		_gm_panel.bind(self)
		add_child(_gm_panel)


func _start_first_tutorial() -> void:
	var script: GDScript = load("res://battle/first_fight_tutorial.gd")
	_first_tutorial = script.new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/first_fight_tutorial.json"))
	_first_tutorial.setup(data)
	_first_tutorial.grid_visibility_changed.connect(func(value: bool): _tutorial_grid_visible = value)
	_first_tutorial.simulation_pause_changed.connect(func(_paused: bool) -> void:
		_update_death_appearance_speed())
	_first_tutorial.step_finished.connect(func(trigger: int) -> void:
		if trigger == script.Trigger.RESOLUTION_STARTED:
			_combat_tracker_guide_due = true)
	_add_tutorial_view(_first_tutorial)
	_first_tutorial.notify_event(script.Trigger.RUN_STARTED)


func _add_tutorial_view(tutorial: RefCounted) -> Control:
	var view: Control = load("res://battle/first_tutorial_view.gd").new()
	_ui.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.bind(tutorial, self)
	return view


func _start_combat_tracker_guide() -> void:
	_combat_tracker_guide_due = false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/first_fight_tutorial.json"))
	var script: GDScript = load("res://battle/first_fight_tutorial.gd")
	_combat_tracker_guide = script.new()
	_combat_tracker_guide.setup({"steps": {str(script.Trigger.RUN_STARTED): data.combat_tracker}})
	_add_tutorial_view(_combat_tracker_guide).name = "CombatTrackerGuide"
	_combat_tracker_guide.step_finished.connect(_stop_combat_tracker_guide.unbind(1))
	_combat_tracker_guide.notify_event(script.Trigger.RUN_STARTED)


func _stop_combat_tracker_guide() -> void:
	var guide := _combat_tracker_guide
	_combat_tracker_guide = null
	guide.abort()
	var view := _ui.get_node("CombatTrackerGuide") as Control
	view.set_tracker_highlight(false)
	view.queue_free()


func _tutorial_paused() -> bool:
	return _first_tutorial != null and _first_tutorial.simulation_paused


func _update_death_appearance_speed() -> void:
	var multiplier: float = 0.0 if _tutorial_paused() else simulation_speed.multiplier()
	for unit: GuildrunBoardUnit in _units:
		unit.set_death_appearance_speed(multiplier)
	if is_instance_valid(_projectile_effects):
		for effect: Node3D in _projectile_effects.get_children():
			effect.speed_scale = multiplier


func _on_tutorial_hero_skill_attack_started() -> void:
	if _first_tutorial != null and not _tutorial_mana_seen and phase == Phase.FIGHT:
		_tutorial_mana_seen = true
		_tutorial_mana_pending = true


func _play_founding_comic() -> void:
	_choices.hide()
	var comic = load("res://UI/intro_comic.gd").new()
	comic.name = "Canvas_Comic"
	comic.template_path = "res://UI/founding_comic_content.tscn"
	comic.timeline_path = "res://balancing/founding_comic.json"
	_founding_comic = comic
	comic.completed.connect(func():
		_founding_comic = null
		_stage.sound.stop_intro_comic()
		_choices.show()
		if _first_tutorial != null:
			_first_tutorial.notify_comics_finished())
	_ui.add_child(comic)
	comic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.sound.play_intro_comic(comic.sound_event)


func _draw_choices() -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	for choice: Dictionary in _choice_rows:
		var button := Button.new()
		button.text = tr("Heroes.Hero_%d.Name" % int(choice.id))
		button.icon = load(choice.portrait)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.expand_icon = true
		button.custom_minimum_size = Vector2(120, 140)
		if choice.has("relic"):
			button.text += "\n" + tr("Relics.Relic_%d.Name" % int(choice.relic))
			button.tooltip_text = _draft.reward_description(int(choice.relic))
			button.custom_minimum_size = Vector2(160, 168)
			var badge := TextureRect.new()
			badge.texture = load(choice.relic_icon)
			badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.position = Vector2(6, 6)
			badge.size = Vector2(42, 42)
			button.add_child(badge)
		button.pressed.connect(select_hero.bind(int(choice.id)))
		_choices.add_child(button)
	if _draft != null and _draft.tokens > 0:
		var reroll := Button.new()
		reroll.text = "%s (%d)" % [tr("UI.Tokens.ReRollButton.Text"), _draft.tokens]
		reroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		reroll.pressed.connect(_reroll_choices)
		_choices.add_child(reroll)


func _reroll_choices() -> void:
	if phase == Phase.PICK and _draft != null and _draft.roll():
		_draw_choices()


func _create_party() -> void:
	first_shop = GuildrunFirstShop.new()
	first_shop.battle_stage = _stage
	_ui.add_child(first_shop)
	first_shop.departed.connect(_open_crossroads)
	first_shop.hero_sold.connect(_remove_sold_hero)
	first_shop.rank_modifier_choice_requested.connect(_show_rank_modifier_picker)


func _show_rank_modifier_picker(hero: int, rank: int, offers: Array[int]) -> void:
	var picker := _ui.get_node_or_null("RankModifierPicker")
	if picker == null:
		picker = load("res://battle/rank_modifier_picker.gd").new()
		picker.name = "RankModifierPicker"
		_ui.add_child(picker)
	else:
		_ui.move_child(picker, -1)
	picker.present(first_shop, hero, rank, offers)


func select_hero(id: int) -> void:
	if _first_tutorial != null and not _first_tutorial.can_pick_hero():
		return
	if phase != Phase.PICK or first_shop != null or is_instance_valid(_founding_comic):
		return
	for row: Dictionary in _choice_rows:
		if int(row.id) != id:
			continue
		if _stage.normal_opening:
			_create_party()
			var bonus := int(row.get("relic", 0))
			first_shop.start_normal(id, bonus, _draft.xp)
			if _stage.red_rift != null:
				_stage.red_rift.give_anchor(first_shop, id)
			if bonus == 6010:
				rewind_available = false
				rewind_reserve = 0
			elif bonus == 6015:
				rewind_reserve += 25
			elif bonus == 6013:
				_choices.hide()
				first_shop.show_rank_picker(id, row.portrait, _ui)
				first_shop._rank_picker.dismissed.connect(_deploy_starter.bind(row), CONNECT_ONE_SHOT)
				return
		_deploy_starter(row)
		return


func _deploy_starter(row: Dictionary) -> void:
	var id := int(row.id)
	var cell := _next_free_position()
	if first_shop != null:
		_hero = _stage.deploy_hero(id, cell, [], first_shop.equipment(id), first_shop.relics, first_shop.hero_ranks[id], first_shop.specializations.get(id, {}), first_shop.rank_modifiers_for(id))
	else:
		_hero = _stage.deploy_hero(id, cell)
	if _hero == null:
		return
	if row.has("turtle_hp"):
		for unit in _units:
			unit.max_health = int(row.turtle_hp)
			unit.health = unit.max_health
			unit.set_meta("health", unit.health)
	_register(_hero)
	_stage.sound.play_ui(2)
	_choices.hide()
	_fight.show()
	phase = Phase.PLACE
	if _first_tutorial != null:
		_first_tutorial.notify_hero_picked()
		_first_tutorial.notify_battle_flow(_first_tutorial.BattleFlow.PLACEMENT)
	if first_shop != null and not first_shop.items.is_empty():
		_open_equipment()


func _register(unit: GuildrunBoardUnit) -> void:
	_units.append(unit)
	unit.effect_scene_clock = effect_scene_time
	unit.effect_variable = _action_vfx_variable.bind(unit)
	unit.set_death_appearance_speed(0.0 if _tutorial_paused() else simulation_speed.multiplier())
	if phase == Phase.FIGHT:
		_register_battle_statistics(unit)
	if unit.is_hero and not is_instance_valid(_hero):
		_hero = unit
	if unit.is_hero and first_shop != null:
		var id := int(unit.stat("Id")._sequentialId)
		unit.rank = int(first_shop.hero_ranks.get(id, unit.rank))
		unit.permanent_stats = first_shop.permanent_stats.get_or_add(id, {})
		unit.ability_progress = first_shop.ability_progress.get_or_add(id, {})
	unit.mana_regen_remaining_q16 = _stage.mana_regen_interval_q16
	unit.basic_attack_action.connect(_on_attack_action.bind(unit))
	if unit.is_hero and _first_tutorial != null and not _tutorial_mana_seen:
		# The native tutorial relays the hero's SkillAttack animation event (150).
		unit.skill_attack_started.connect(_on_tutorial_hero_skill_attack_started, CONNECT_ONE_SHOT)
	if unit.is_hero and first_shop != null and first_shop.relics.has(1026):
		unit.shield_gained.connect(func(amount: int): first_shop.advance_quest(1026, amount))
	if unit.passive_id() == 204:
		unit.fury_triggered.connect(func(): _burn_opponents(unit, int(unit.stat("Attack"))))
	var bar: Control = load("res://battle/battle_health_bar.gd").new()
	_ui.add_child(bar)
	bar.setup(unit)
	unit.combat_number.connect(func(amount: int, kind: GuildrunBoardUnit.CombatNumber, critical: bool) -> void:
		if phase == Phase.FIGHT:
			bar.show_combat_number(amount, kind, critical, unit.is_hero))
	_bars[unit] = bar
	if unit.is_hero:
		bar.set_equipment(_stage, first_shop, _equipment_panel, int(unit.stat("Id")._sequentialId))


func effect_scene_time() -> float:
	return _effect_scene_time


func _advance_effect_scene_time(delta: float) -> void:
	if phase != Phase.FIGHT:
		_effect_scene_time += delta
	elif not _tutorial_paused():
		_effect_scene_time += delta * simulation_speed.multiplier()


func _process(delta: float) -> void:
	_advance_effect_scene_time(delta)
	if _first_tutorial != null:
		_first_tutorial.advance_time(delta)
	if _combat_tracker_guide != null:
		if phase in [Phase.FIGHT, Phase.RESULT]:
			_combat_tracker_guide.advance_time(delta)
		else:
			_stop_combat_tracker_guide()
	if _anchor_warning:
		var waiting: bool = phase == Phase.PLACE and first_shop != null and not _stage.red_rift.allows_deployment(first_shop, not trial.is_empty())
		_anchor_warning.visible = waiting
		if phase == Phase.PLACE:
			_fight.disabled = waiting or not is_instance_valid(_hero)
	if phase == Phase.PLACE and _first_tutorial != null:
		_fight.disabled = not _first_tutorial.can_start_fight() or not is_instance_valid(_hero)
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var drag_active := phase == Phase.PLACE and _drag_portrait.visible
	var hovered := NO_SLOT
	if drag_active and not get_viewport().gui_get_hovered_control():
		hovered = _cell_at(get_viewport().get_mouse_position(), false)
	var show_deployment_grid := phase == Phase.PLACE and (drag_active or _tutorial_grid_visible)
	_deployment_grid_view.update_tiles(_grid, show_deployment_grid, drag_active, hovered, _pressed_slot)
	for unit in _units:
		if not is_instance_valid(unit):
			continue
		var bar: Control = _bars[unit]
		bar.update_unit(unit, camera, phase in [Phase.PLACE, Phase.FIGHT], phase == Phase.PLACE, delta)


func _cell_at(point: Vector2, placement_only := true) -> Vector2i:
	var camera := get_viewport().get_camera_3d()
	var board := _stage.get_node("Battle/BattleGrid") as Node3D
	var plane := Plane(Vector3.UP, board.global_position.y)
	var intersection: Variant = plane.intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))
	if intersection == null:
		return NO_SLOT
	var local: Vector3 = board.to_local(intersection)
	var cell := NO_SLOT
	var closest := INF
	for x in _grid.size.x:
		for y in _grid.size.y:
			var candidate := Vector2i(x, y)
			var d := GuildrunBattleGrid.center(candidate).distance_squared_to(local)
			if d < closest:
				cell = candidate
				closest = d
	return cell if closest <= 2.25 and (not placement_only or cell.y < (_grid.size.y >> 1)) else NO_SLOT


func board_hero(id: int) -> GuildrunBoardUnit:
	for unit in _units:
		if is_instance_valid(unit) and unit.is_hero and int(unit.get_meta("hero_id")) == id:
			return unit
	return null


func _slot_id(slot: Vector2i) -> int:
	if slot.x == -1 and first_shop and slot.y >= 0 and slot.y < first_shop.reserve_slots.size():
		return first_shop.reserve_slots[slot.y]
	var unit: GuildrunBoardUnit = _grid.occupants.get(slot)
	return int(unit.get_meta("hero_id")) if unit and unit.is_hero else -1


func _toggle_reserve() -> void:
	if phase != Phase.PLACE or not is_instance_valid(_reserve_panel):
		return
	_reserve_panel.visible = not _reserve_panel.visible
	_pressed_slot = NO_SLOT
	_selected_slot = NO_SLOT
	_drag_portrait.hide()
	if _reserve_panel.visible:
		_reserve_panel.refresh()


func _input(event: InputEvent) -> void:
	if is_instance_valid(_gm_panel) and _gm_panel.captures(event):
		return
	if _combat_tracker_guide != null and event is InputEventMouseButton and event.pressed:
		_combat_tracker_guide.consume_mouse_press(event.button_index)
	if _first_tutorial != null:
		if event is InputEventMouseButton and event.pressed and _first_tutorial.consume_mouse_press(event.button_index):
			get_viewport().set_input_as_handled()
			return
		if _first_tutorial.input_locked:
			get_viewport().set_input_as_handled()
			return
	if phase != Phase.PLACE:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and _reserve_toggle.visible:
		_toggle_reserve()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _pressed_slot != NO_SLOT:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_pressed_slot = NO_SLOT
			_drag_portrait.hide()
		elif _pressed_at.distance_to(event.position) >= 8.0:
			var id := _slot_id(_pressed_slot)
			if id >= 0:
				if not _drag_portrait.visible:
					_tutorial_grid_visible = false
					_drag_portrait.texture = _stage.hero_portrait(id)
					_drag_portrait.show()
				_drag_portrait.position = event.position - _drag_portrait.size / 2
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if get_viewport().gui_is_dragging():
		_pressed_slot = NO_SLOT
		return
	var slot: Vector2i = _reserve_panel.slot_at(event.position) if is_instance_valid(_reserve_panel) else NO_SLOT
	if slot == NO_SLOT and is_instance_valid(_bottom_roster):
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered == null or not hovered.get_global_rect().has_point(event.position) or _bottom_roster.is_ancestor_of(hovered):
			if event.pressed and _bottom_roster.try_equip_at(event.position):
				_pressed_slot = NO_SLOT
				get_viewport().set_input_as_handled()
				return
			slot = _bottom_roster.slot_at(event.position)
	if event.pressed:
		if slot != NO_SLOT:
			_pressed_slot = slot
			_pressed_at = event.position
			get_viewport().set_input_as_handled()
		return
	if _pressed_slot == NO_SLOT:
		return
	var source := _pressed_slot
	_pressed_slot = NO_SLOT
	_drag_portrait.hide()
	if slot == NO_SLOT:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered and hovered.get_global_rect().has_point(event.position):
			return
		slot = _cell_at(event.position)
	if slot != NO_SLOT:
		if _pressed_at.distance_to(event.position) >= 8.0:
			transfer_hero(source, slot)
		elif source == slot:
			_click_slot(slot)
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.PLACE and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pressed_slot = _cell_at(event.position)
		_pressed_at = event.position


func _click_slot(slot: Vector2i) -> void:
	var id := _slot_id(slot)
	if _selected_slot != NO_SLOT and slot != _selected_slot and (id < 0 or slot.x < 0 or _selected_slot.x < 0):
		transfer_hero(_selected_slot, slot)
	elif id >= 0:
		_selected_slot = slot
		if slot.x >= 0:
			_hero = _grid.occupants[slot]
		_stage.sound.play_ui(4)
		if is_instance_valid(_reserve_panel) and _reserve_panel.visible:
			_reserve_panel.refresh(slot)
	elif slot.x >= 0 and is_instance_valid(_hero):
		transfer_hero(_hero.grid_cell, slot)


func _valid_slot(slot: Vector2i) -> bool:
	if slot.x == -1:
		return first_shop != null and slot.y >= 0 and slot.y < first_shop.reserve_slots.size()
	return _grid.contains(slot) and slot.y < (_grid.size.y >> 1) and (not _grid.occupants.has(slot) or _grid.occupants[slot].is_hero)


func enter_trial_formation() -> void:
	var modifier := int(trial.get("modifier", 0))
	if modifier not in [5500, 5501, 5502, 5509] or _trial_previous_deployment_limit > 0:
		return
	_trial_previous_deployment_limit = int(_stage.max_deployed)
	_trial_previous_reserves = first_shop.reserve_slots.duplicate()
	_trial_previous_formation = _formation.duplicate()
	_stage.max_deployed = 1


func leave_trial_formation() -> void:
	if _trial_previous_deployment_limit == 0:
		return
	_stage.max_deployed = _trial_previous_deployment_limit
	first_shop.reserve_slots = _trial_previous_reserves
	_formation = _trial_previous_formation
	_trial_previous_deployment_limit = 0


func _trial_time_limit_q16() -> int:
	var modifier := int(trial.get("modifier", 0))
	match modifier:
		5503, 5504, 5505:
			return (30 + (modifier - 5503) * 10) << 16
		5506, 5507, 5508, 5510:
			return 20 << 16
	return 0


func _trial_survival() -> bool:
	return int(trial.get("modifier", 0)) in [5503, 5504, 5505]


func _apply_trial_combat_effect(unit: GuildrunBoardUnit) -> void:
	var modifier := int(trial.get("modifier", 0))
	if unit.is_hero:
		if modifier in [5509, 5511]:
			unit.set_basic_stat_percent(-10 if modifier == 5509 else -50)
	elif _trial_survival():
		unit.trial_damage_immune = true
	elif modifier in [5507, 5508]:
		unit.combat_stats.MaxHealth = int(unit.combat_stats.get("MaxHealth", 0)) + unit.max_health * (modifier - 5506)
		unit.max_health = int(unit.stat("MaxHealth"))
		unit.health = unit.max_health
		unit.set_meta("health", unit.health)


func transfer_hero(source: Vector2i, target: Vector2i) -> bool:
	if _first_tutorial != null and _first_tutorial.input_locked:
		return false
	if phase != Phase.PLACE or source == target or not _valid_slot(source) or not _valid_slot(target):
		return false
	var id := _slot_id(source)
	if id < 0:
		return false
	var other := _slot_id(target)
	if source.x < 0 and target.x < 0:
		first_shop.reserve_slots[source.y] = other
		first_shop.reserve_slots[target.y] = id
	elif source.x >= 0 and target.x >= 0:
		var moved := board_hero(id)
		var displaced := board_hero(other)
		_grid.occupants.erase(source)
		if displaced:
			_place_at(displaced, source)
		_place_at(moved, target)
		_hero = moved
	else:
		var cell := source if source.x >= 0 else target
		var reserve := target if source.x >= 0 else source
		var leaving := board_hero(_slot_id(cell))
		var incoming := _slot_id(reserve)
		var active := first_shop.deployed_ids()
		if not leaving and active.size() >= int(_stage.max_deployed):
			_placement_notice("NoSpace")
			return false
		if incoming < 0 and active.size() == 1:
			_placement_notice("CantMoveOnlyHero")
			return false
		first_shop.reserve_slots[reserve.y] = _slot_id(cell)
		if leaving:
			_formation.erase(int(leaving.get_meta("hero_id")))
			_grid.occupants.erase(cell)
			_units.erase(leaving)
			_bars[leaving].free()
			_bars.erase(leaving)
			leaving.free()
		if incoming >= 0:
			_hero = _deploy_owned(incoming, cell)
			_fight.disabled = false
		elif not is_instance_valid(_hero):
			_hero = board_hero(first_shop.deployed_ids().front())
	_selected_slot = NO_SLOT
	_stage.sound.play_ui(5)
	if is_instance_valid(_reserve_panel) and _reserve_panel.visible:
		_reserve_panel.refresh()
	return true


func _place_at(unit: GuildrunBoardUnit, cell: Vector2i) -> void:
	_grid.occupants[cell] = unit
	unit.grid_cell = cell
	unit.set_meta("grid_cell", cell)
	unit.position = GuildrunBattleGrid.center(cell)


func _placement_notice(reason: String) -> void:
	var notice := AcceptDialog.new()
	notice.title = tr("UI.Dialog.Error.%s.Title" % reason)
	notice.dialog_text = tr("UI.Dialog.Error.%s.Description" % reason)
	_ui.add_child(notice)
	notice.visibility_changed.connect(func():
		if not notice.visible: notice.queue_free())
	notice.popup_centered()


func _deploy_owned(id: int, cell: Vector2i) -> GuildrunBoardUnit:
	var unit: GuildrunBoardUnit = _stage.deploy_hero(id, cell, first_shop.hero_modifiers.get(id, []),
			first_shop.equipment(id), first_shop.relics, int(first_shop.hero_ranks[id]),
			first_shop.specializations.get(id, {}), first_shop.rank_modifiers_for(id))
	_register(unit)
	return unit


func _action_vfx_variable(key: String, unit: GuildrunBoardUnit) -> Variant:
	match key:
		"totalRushTriggers":
			return total_rush_triggers << 16
		"totalStallTriggers":
			return total_stall_triggers << 16
		"loganTotalAbilityDamageDealt":
			return int(unit.ability_progress.get("damage", 0)) << 16
		"salFrostStacks":
			return unit.permafrost_frost << 16
		"VFXTriggerCount":
			return int(unit.combat_stats.get("VFXTriggerCount", 0)) << 16
	return null


func _register_battle_statistics(unit: GuildrunBoardUnit) -> void:
	var id := int(unit.stat("Id")._sequentialId)
	var name_key := ("Heroes.Hero_%d.Name" if unit.is_hero else "Enemies.Enemy_%d.Name") % id
	var portrait: Texture2D = _stage.character_portrait(unit.stat("VisualConfig"))
	battle_statistics.register(unit.get_instance_id(), tr(name_key), portrait.resource_path if portrait else "", unit.is_hero)
	unit.battle_statistics = battle_statistics


func start_fight() -> void:
	if _first_tutorial != null and not _first_tutorial.can_start_fight():
		return
	if _stage.red_rift != null and first_shop != null and not _stage.red_rift.allows_deployment(first_shop, not trial.is_empty()):
		return
	if phase == Phase.PLACE and is_instance_valid(_hero):
		_seed_combat()
		_storm_start_q16 = int(_stage.storm_rules.start_q16)
		_storm_damage_timer_q16 = 0
		_storm_damage = 0
		battle_statistics = GuildrunBattleStatistics.new()
		for unit in _units:
			_register_battle_statistics(unit)
		_pressed_slot = NO_SLOT
		_selected_slot = NO_SLOT
		_drag_portrait.hide()
		_reserve_toggle.hide()
		if is_instance_valid(_reserve_panel):
			_reserve_panel.hide()
		if _equipment_panel:
			_equipment_panel.hide()
		if first_shop:
			_rank_wallet.begin(first_shop, _units)
		var backup := _reserve_bonuses()
		for unit in _units:
			if unit.is_hero:
				if first_shop != null:
					first_shop.kit_growth(unit)
				for key: String in backup:
					unit.combat_stats[key] = int(unit.combat_stats.get(key, 0)) + int(backup[key])
				if backup.has("MaxHealth"):
					unit.max_health = int(unit.stat("MaxHealth"))
					unit.health = unit.max_health
					unit.set_meta("health", unit.health)
		var tycoon_hp := _tycoon_health_bonus()
		for unit in _units:
			if unit.is_hero:
				if tycoon_hp > 0:
					var old_hp := int(unit.stat("MaxHealth"))
					unit.combat_stats.MaxHealth = int(unit.combat_stats.get("MaxHealth", 0)) + tycoon_hp
					var increase := int(unit.stat("MaxHealth")) - old_hp
					unit.max_health += increase
					unit.health += increase
					unit.set_meta("health", unit.health)
				_formation[int(unit.stat("Id")._sequentialId)] = unit.grid_cell
				if _stage.contract.start_health_q16 != 65536:
					unit.health = mini(unit.health, (unit.max_health * int(_stage.contract.start_health_q16) + 32768) >> 16)
					unit.set_meta("health", unit.health)
				if _stage.contract.dragon_stacks > 0 and _stage.contract.DRAGON_STACKS.has(_stage.contract.active_boss_relic):
					_add_elemental_status(unit, _stage.contract.DRAGON_STACKS[_stage.contract.active_boss_relic][0], _stage.contract.dragon_stacks)
				if first_shop != null:
					if first_shop.relics.has(5105) or first_shop.relics.has(5128):
						unit.stun_remaining_q16 = 6 << 16
					for relic: int in [5115, 5127, 798]:
						if first_shop.relics.has(relic):
							var percent := int({5115: 15, 5127: 30, 798: 10}[relic])
							unit.take_damage(roundi(unit.max_health * percent / 100.0), null,
									GuildrunBattleStatistics.Origin.OTHER, 0, relic)
					if first_shop.relics.has(5118):
						_add_poison(unit, roundi(unit.max_health * 0.01))
					for curse: int in [5103, 5108]:
						if first_shop.relics.has(curse):
							var ratio := 1966 if curse == 5103 else 3277
							unit.burn_stacks += (unit.max_health * ratio) >> 16
							unit.burn_remaining_q16 = _stage.burn_interval_q16
		# The source frame updates deployed heroes before the enemy roster.
		_units.assign(_units.filter(func(unit: GuildrunBoardUnit): return unit.is_hero)
				+ _units.filter(func(unit: GuildrunBoardUnit): return not unit.is_hero))
		simulation_speed.begin_simulation()
		phase = Phase.FIGHT
		if _first_tutorial != null:
			_first_tutorial.notify_battle_flow(_first_tutorial.BattleFlow.RESOLUTION)
		elif _combat_tracker_guide_due:
			_start_combat_tracker_guide()
		_rank_growth.settle(first_shop, false)
		_run_trigger_stats.begin(first_shop, _units)
		_keyword_clocks.begin(_units, first_shop, _stage)
		_stall_before_combat = total_stall_triggers
		_rush_before_combat = total_rush_triggers
		total_rush_triggers += int(_keyword_clocks.opening_rush_count())
		_rank_rush.begin(self, _keyword_clocks.rank_rush_windows())
		var hero_count := _units.filter(func(u: GuildrunBoardUnit): return u.is_hero).size()
		_stage.sound.start_fight(hero_count, _units.size() - hero_count)
		for unit in _units:
			_apply_trial_combat_effect(unit)
			unit.has_boss_fury = not unit.is_hero and _stage.contract.active_boss_relic == 7000
			if not unit.is_hero and _stage.contract.active_boss_relic == 7001:
				unit.combat_stats.HPPerSecond = int(unit.combat_stats.get("HPPerSecond", 0)) + floori(unit.max_health / 150.0)
			if challenge_modifier in [5000, 5011] and not unit.is_hero:
				unit.set_basic_stat_percent(150 if challenge_modifier == 5000 else 66)
			elif challenge_modifier in [5003, 5014] and not unit.is_hero:
				var regen_q16 := 1966 if challenge_modifier == 5003 else 3277
				unit.combat_stats.HPPerSecond = int(unit.combat_stats.get("HPPerSecond", 0)) + ((unit.max_health * regen_q16) >> 16)
			elif challenge_modifier in [5004, 5015] and unit.is_hero:
				unit.set_basic_stat_percent(-20 if challenge_modifier == 5004 else -15)
			match unit.passive_id():
				110:
					unit.combat_stats.Defense = int(unit.combat_stats.get("Defense", 0)) + int(unit.stat("Magic"))
				109:
					unit.combat_stats.HPPerSecond = int(unit.combat_stats.get("HPPerSecond", 0)) + ((unit.max_health * 655) >> 16)
				115:
					var cell := _backline_cell(unit.grid_cell)
					_claim_cell(unit, cell)
					unit.position = GuildrunBattleGrid.center(cell)
				118:
					unit.combat_stats.OmniVamp = int(unit.combat_stats.get("OmniVamp", 0)) + 10
				101402:
					unit.combat_stats.AttackRange = int(unit.combat_stats.get("AttackRange", 0)) + 2
					_apply_fire_opener(unit)
				102602:
					unit.combat_stats.Defense = int(unit.combat_stats.get("Defense", 0)) + 30
		_apply_rank_opening_effects()
		_rank_aura_timers.clear()
		_rank_vindictive_pending.clear()
		for owner in _units:
			if owner.defeated:
				continue
			var modifiers := owner.earned_rank_modifiers.values()
			if modifiers.has(185):
				# Native interval state starts at zero for a newly registered effect.
				_rank_aura_timers[owner] = 0
			if modifiers.has(182):
				_rank_vindictive_pending.append(owner)
		_fight.hide()


func _apply_rank_stall(clock: Dictionary) -> void:
	var targets: Array[GuildrunBoardUnit] = []
	if int(clock.modifier) in [278, 282]:
		for unit in _units:
			if not unit.is_hero and not unit.defeated:
				targets.append(unit)
	_rank_stall.apply_stall(clock, clock.owner, targets, self)


func _apply_rank_opening_effects() -> void:
	var allies: Array[GuildrunBoardUnit] = _units.filter(
		func(unit: GuildrunBoardUnit) -> bool: return unit.is_hero and not unit.defeated)
	var extra: GDScript = load("res://battle/rank_opening_extra.gd")
	var status: GDScript = load("res://battle/rank_combat_start_status.gd")
	var grant := Callable(_rank_growth, "grant")
	# Normal effects precede reserve-only effects, which have priority 10.
	for owner in allies:
		var owner_id := int(owner.stat("Id")._sequentialId)
		for modifier: int in owner.earned_rank_modifiers.values():
			var rule: Dictionary = status.OPENING_STATUS.get(modifier, {})
			if rule.is_empty():
				extra.apply_opening(modifier, owner_id, owner.rank, owner, allies, grant)
			else:
				var amount: int = status.stacks(owner, rule)
				if amount > 0:
					for target in _units:
						if not target.is_hero and not target.defeated:
							_add_elemental_status(target, int(rule.status), amount, owner)
	if first_shop == null:
		return
	for owner_id: int in first_shop.roster:
		if not first_shop.reserve_slots.has(owner_id):
			continue
		var rank := int(first_shop.hero_ranks.get(owner_id, 1))
		for modifier: int in GuildrunPartyRankBonuses.earned_modifiers(first_shop, owner_id, rank):
			match modifier:
				57, 279:
					extra.apply_opening(modifier, owner_id, rank, null, allies, grant)
				138:
					_rank_wallet.apply_opening(first_shop, allies, owner_id)
				145:
					GuildrunPartyRankBonuses.apply_combat_start_owner(rank, allies)


func _tycoon_health_bonus() -> int:
	if not first_shop:
		return 0
	var stacks := int(first_shop.ability_progress.get(10, {}).get("stacks", 0))
	if stacks <= 0:
		return 0
	var fiona := board_hero(10)
	var regen: int
	if fiona and fiona.passive_id() == 101003:
		regen = int(fiona.stat("ManaRegen"))
	elif first_shop.reserve_slots.has(10) and int(first_shop.specializations.get(10, {}).get("passive", -1)) == 101003:
		var stats: Dictionary = _stage.hero_stats(10, first_shop.hero_modifiers.get(10, []), first_shop.equipment(10),
				first_shop.relics, first_shop.hero_ranks[10], first_shop.specializations[10], first_shop.rank_modifiers_for(10))
		regen = int(_stage.field(stats, "ManaRegen")) + int(first_shop.permanent_stats.get(10, {}).get("ManaRegen", 0))
	else:
		return 0
	return (75 + 4 * regen) * stacks


func _reserve_bonuses() -> Dictionary:
	var bonuses := {}
	if not first_shop:
		return bonuses
	for relic: int in first_shop.relics:
		if not RESERVE_PRISMS.has(relic):
			continue
		for id in first_shop.reserve_slots:
			if id < 0:
				continue
			var base: Dictionary = _stage._heroes[id]
			var rank := int(first_shop.hero_ranks[id])
			var secondary := int(first_shop.specializations.get(id, {}).get("class", -1))
			if rank < 2 or secondary < 1:
				secondary = int(base._class2ID)
			for profession: int in RESERVE_PRISMS[relic]:
				if profession == int(base._class1ID) or profession == secondary:
					var rule: Array = RESERVE_PRISMS[relic][profession]
					bonuses[rule[0]] = int(bonuses.get(rule[0], 0)) + rank * int(rule[1])
	return bonuses


func _backline_cell(origin: Vector2i) -> Vector2i:
	var best := origin
	var best_back := 2147483647
	var best_travel := 2147483647
	for y in _grid.size.y:
		for x in _grid.size.x:
			var cell := Vector2i(x, y)
			if _grid.occupants.has(cell):
				continue
			var back := GuildrunBattleGrid.distance(Vector2i(origin.x, 0), cell)
			var travel := GuildrunBattleGrid.distance(origin, cell)
			if back < best_back or (back == best_back and travel < best_travel):
				best = cell
				best_back = back
				best_travel = travel
	return best


func _physics_process(delta: float) -> void:
	if phase != Phase.FIGHT or _tutorial_paused():
		return
	if _pending_battle_result.is_valid():
		# The original countdown consumes unscaled time before dispatching battle end.
		_battle_end_remaining -= delta / Engine.time_scale
		if _battle_end_remaining <= 0.000001:
			var finish := _pending_battle_result
			_pending_battle_result = Callable()
			finish.call()
		return
	simulation_speed.advance_real_time(delta, BATTLE_STEP_SECONDS, _advance_battle_tick)


func _advance_battle_tick(_step_seconds: float) -> bool:
	_step_battle(BATTLE_STEP_Q16, true)
	var active := phase == Phase.FIGHT and not _pending_battle_result.is_valid()
	if active:
		simulation_speed.observe_simulation_time(battle_time_q16 / 65536.0)
	return active and not _tutorial_paused()


# A direct simulation step can settle immediately for deterministic battle analysis.
func _step_battle(dt: int, present_result := false) -> void:
	if _pending_battle_result.is_valid():
		return
	_frame += 1
	_deaths_this_step.clear()
	battle_time_q16 += dt
	_tick_rank_auras(dt)
	_tick_specialization_stat_effects(dt)
	_tick_rank_vindictive_shields()
	var clock_events: Array[Dictionary] = _keyword_clocks.tick(battle_time_q16, dt)
	_rank_rush.advance()
	for clock: Dictionary in clock_events:
		if int(clock.keyword) != 2:
			continue
		if clock.has("modifier"):
			_apply_rank_stall(clock)
		if int(clock.passive) == 101402 and clock.owner != null:
			_apply_fire_opener(clock.owner)
		total_stall_triggers += 1
		if first_shop:
			first_shop.advance_quest(1023, 1)
			_rank_wallet.apply_stall(first_shop, _units)
	_run_trigger_stats.refresh(total_rush_triggers, total_stall_triggers)
	if challenge_modifier in [5002, 5013]:
		var damage_q16 := 1638 if challenge_modifier == 5002 else 4588
		_pain_timer += dt
		while _pain_timer >= 65536:
			_pain_timer -= 65536
			for unit in _units:
				if unit.is_hero and not unit.defeated:
					_land(unit, (unit.max_health * damage_q16) >> 16)
	var rush_end := (8 if challenge_modifier == 5000 else 10) << 16
	if challenge_modifier in [5000, 5011] and battle_time_q16 >= rush_end and battle_time_q16 - dt < rush_end:
		for unit in _units:
			if not unit.is_hero:
				unit.set_basic_stat_percent(0)
	if battle_time_q16 >= 15 << 16 and battle_time_q16 - dt < 15 << 16:
		for unit in _units:
			if challenge_modifier in [5001, 5012] and not unit.is_hero:
				unit.set_basic_stat_percent(40 if challenge_modifier == 5001 else 55)
	_advance_strike_areas(dt)
	_advance_drags(dt)
	# ManaRegenSystem updates every living unit before EntityFsmSystem runs.
	for unit in _units:
		if not unit.defeated:
			unit.tick_mana(dt, _stage.mana_regen_interval_q16)
	_plan_battle_moves()
	for unit in _units:
		if not unit.defeated:
			unit.tick_shields(dt)
			if unit.passive_id() == 113:
				unit.shield_timer_q16 += dt
				if unit.shield_timer_q16 >= 10 << 16:
					unit.shield_timer_q16 -= 10 << 16
					unit.gain_shield((unit.max_health * 6554) >> 16, 10 << 16)
			_tick_burn(unit, dt)
			_tick_frost(unit, dt)
			_tick_poison(unit, dt)
			unit.stealth_remaining_q16 = maxi(0, unit.stealth_remaining_q16 - dt)
			unit.tick_health_regen(dt)
		if not unit.defeated:
			_tick_unit(unit, dt)
	_planned_moves.clear()
	_advance_projectiles(dt)
	_tick_riftstorm(dt)
	if battle_statistics != null:
		battle_statistics.settle_status_damage()
	_deaths_this_step.clear()
	var enemies_alive := _units.any(func(u: GuildrunBoardUnit): return not u.is_hero and not u.defeated)
	var survivors := _units.filter(func(u: GuildrunBoardUnit): return u.is_hero and not u.defeated).size()
	var limit := _trial_time_limit_q16()
	var timed_out := limit > 0 and battle_time_q16 >= limit
	var survival := _trial_survival()
	var finished := survivors == 0 or timed_out or (not enemies_alive and not survival)
	if _tutorial_mana_pending:
		# Present the tutorial after the entire fixed step, including projectile hits.
		_tutorial_mana_pending = false
		if not finished:
			_first_tutorial.notify_event(_first_tutorial.Trigger.HERO_MANA_IS_FULL)
	if finished:
		var victory := survivors > 0 and (timed_out if survival else not enemies_alive and not timed_out)
		if present_result:
			var has_fallen_hero := _units.any(func(unit: GuildrunBoardUnit): return unit.is_hero and unit.defeated)
			_battle_end_remaining = _stage.combat_end_delay if victory or has_fallen_hero else 0.0
			if victory and has_fallen_hero:
				_battle_end_remaining += _stage.victory_resurrect_delay
			_pending_battle_result = _settle_battle.bind(victory, survivors, true)
		else:
			_settle_battle(victory, survivors)


func _settle_battle(victory: bool, survivors: int, animate := false) -> void:
	_result_rewards.clear()
	_settle_battle_rewards(victory, survivors, animate)
	if phase == Phase.RESULT:
		var won := victory
		if _stage.red_rift != null and _stage.red_rift.status == _stage.red_rift.Status.FAILED:
			won = false
		_present_result(won, animate)
		if _first_tutorial != null:
			_first_tutorial.notify_battle_flow(_first_tutorial.BattleFlow.RESULT)


func _play_revival_effects(unit: GuildrunBoardUnit, victory: bool) -> void:
	unit.play_revival_flash()
	var effects: Array[String] = ["res://battle/revival_victory.tscn"]
	if not victory:
		effects.push_front("res://battle/revival_stabilizer.tscn")
	for path in effects:
		var prefab := load(path) as PackedScene
		if prefab == null:
			continue
		var effect := prefab.instantiate() as Node3D
		effect.position = unit.transform.basis.inverse() * unit.visual_offset
		unit.add_child(effect)


func _present_result(victory: bool, animate: bool) -> void:
	_result_view.proceed_text.text = tr("UI.EndScreen.Summary" if _summary_button.visible else "UI.Common.Continue")
	_result_view.present(last_battle_statistics, _result_rewards, victory, animate)


func _settle_battle_rewards(victory: bool, survivors: int, animate := false) -> void:
	var restore_hero_views: bool = victory or (rewind_available and trial.is_empty() and _stage.endless_floor < 0)
	phase = Phase.RESULT
	_stage.set_defeat_grade(not victory)
	if first_shop:
		var final_boss: bool = _stage.endless_floor < 0 and _stage.floor_rules().get("final_boss", false)
		var keep_changes: bool = not final_boss or (victory and not _stage.challenge_run)
		_rank_wallet.settle(first_shop, keep_changes)
		_rank_growth.settle(first_shop, keep_changes)
		if not keep_changes:
			total_stall_triggers = _stall_before_combat
			total_rush_triggers = _rush_before_combat
		first_shop.items.append_array(_gained_items)
	_gained_items.clear()
	_stage.sound.set_phase(false)
	_run_battle_time_q16 += battle_time_q16
	_completed_battles += 1
	last_battle_statistics = battle_statistics.snapshot(battle_time_q16, victory)
	last_battle_statistics.run_elapsed_q16 = _run_battle_time_q16
	last_battle_statistics.battle_count = _completed_battles
	for unit in _units:
		var entry: Dictionary = last_battle_statistics.units.get(unit.get_instance_id(), {})
		if not entry.is_empty():
			entry.defeated = unit.defeated
		unit.battle_statistics = null
	_result.text = tr("UI.Battle.ResultPanel.BattleWon") if victory else tr("UI.EndScreen.Defeat")
	for unit in _units:
		if unit.is_hero:
			for profession in range(1, 8):
				if unit.has_class(profession):
					class_play_counts[profession] = int(class_play_counts.get(profession, 0)) + 1
		var restored: bool = unit.is_hero and restore_hero_views
		if unit.defeated:
			unit.settle_death_appearance(restored)
			if animate and restored:
				_play_revival_effects(unit, victory)
		if not unit.defeated or restored:
			# VfxController.ReviveHeroes restores CharacterView without modifying the finished simulation.
			unit.play_idle()
	if _stage.red_rift != null:
		_stage.red_rift.finish_battle(first_shop, _units, victory, not trial.is_empty(), int(_stage.field(_stage.stage, "StageType")) == 3)
		if _finish_red_rift():
			return
	if not trial.is_empty():
		_trial_won = victory
		_result.text = tr("UI.BattleFlow.FightEventWon" if victory else "UI.BattleFlow.FightEventLost")
		if victory:
			var reward_name := tr("UI.BattleInfo.Shards.Title")
			if trial.kind in ["item", "relic"]:
				var category := "Items.Item" if trial.kind == "item" else "Relics.Relic"
				reward_name = tr("%s_%d.Name" % [category, int(trial.value)])
			var reward := {"title": reward_name}
			if trial.kind == "shards":
				reward.amount = int(trial.value)
			_result_rewards.append(reward)
		leave_trial_formation()
		_continue.show()
		return
	if first_shop != null:
		first_shop.settle_combat(_units, victory)
	if victory:
		if int(_stage.field(_stage.stage, "StageType")) == 2:
			_stage.last_miniboss_group = String(_stage.field(_stage.stage, "GroupName"))
		if _stage.endless_floor < 0:
			_regular_wins += 1
		_stage.contract.won_battle()
		if _stage.track_contract_progress and _stage.red_rift == null and _stage.field(_stage.stage, "StageType") == 3:
			_stage.contract.record_win(_stage.contract.selected, _stage.contract_progress_path)
	if _stage.endless_floor >= 0:
		_endless_won = victory
		if not victory:
			_record_run_end()
		first_shop.advance_event_rewards(victory)
		_result.text = tr("UI.BattleFlow.EndlessBattleWon" if victory else "UI.BattleFlow.EndlessModeOver")
		_continue.show()
		_floor_label.hide()
		return
	if victory or rewind_available:
		var payout := 0
		if victory:
			if rewind_available:
				rewind_reserve += int(_stage.rewind_shards_per_win)
				if _stage.floor_rules().get("before_final_boss", false):
					payout = rewind_reserve
					rewind_reserve = 0
					rewind_available = false
		else:
			payout = rewind_reserve
			rewind_reserve = 0
			rewind_available = false
			challenge_modifier = 0
			_result.text = tr("UI.BattleFlow.BattleLost")
		var table := "StageRewards" if victory else "DefeatStageRewards"
		var bounds: Dictionary = _stage.field(_stage.field(_stage.stage, table), "GoldRewardRange")
		var reward := _rng.randi_range(int(bounds.FromInclusive), int(bounds.ToInclusive))
		var floor_index := int(_stage.field(_stage.stage, "FloorNumber"))
		var paid_survivors := survivors if victory and floor_index > 0 else 0
		if first_shop == null:
			_create_party()
			first_shop.prepare(int(_hero.stat("Id")._sequentialId), _stage.stage, paid_survivors)
			if not victory:
				first_shop.battle_reward = reward
		elif not _stage.normal_opening and floor_index == 1:
			first_shop.prepare_second(_stage.second_battle_reward if victory else reward, paid_survivors)
		else:
			if victory:
				reward = first_shop.combat_shards(reward)
			first_shop.advance_event_rewards(victory)
			var stage_type := int(_stage.field(_stage.stage, "StageType"))
			first_shop.prepare_third(reward, paid_survivors, victory and stage_type in [2, 3])
		first_shop.rewind_payout = payout
		_result_rewards.append({"title": tr("UI.BattleFlow.BattleWon" if victory else "UI.BattleFlow.BattleLost"),
				"amount": first_shop.battle_reward})
		if first_shop.survival_reward > 0:
			_result_rewards.append({"title": tr("UI.BattleFlow.SurvivingHeroBonus"), "amount": first_shop.survival_reward})
		if not victory:
			_result_rewards.append({"title": tr("UI.BattleFlow.StabilizerBroken"), "amount": payout})
		elif payout > 0:
			var explanation := tr("UI.ShardStabilizer.FinalBoss").format([payout]).replace("[", "").replace("]", "") \
					.replace("<bold>", "").replace("<shard>", "").replace("\\n", "\n")
			_result_rewards.append({"title": tr("UI.BattleInfo.ShardStabilizer.Title"), "amount": payout, "explanation": explanation})
		_continue.show()
	else:
		if _stage.red_rift != null:
			_stage.red_rift.status = _stage.red_rift.Status.FAILED
			_finish_red_rift()
			return
		_record_run_end()
		_summary_button.show()


func _tick_riftstorm(dt: int) -> void:
	var rules: Dictionary = _stage.storm_rules
	var was_pending := _storm_start_q16 > 0
	_storm_start_q16 -= dt
	if was_pending:
		if _storm_start_q16 <= 0:
			_storm_damage_timer_q16 = int(rules.interval_q16)
			_storm_damage = int(rules.initial_damage)
		return
	_storm_damage_timer_q16 -= dt
	if _storm_damage_timer_q16 > 0 or _storm_damage == 0:
		return
	for unit in _units:
		if not unit.defeated:
			_land(unit, _storm_damage, null, false, GuildrunBattleStatistics.Origin.OTHER)
	# StormSystem.TickStorm resets the interval and rounds multiply damage down.
	_storm_damage_timer_q16 = int(rules.interval_q16)
	if _storm_start_q16 <= -int(rules.escalation_q16):
		_storm_damage = (_storm_damage * int(rules.multiplier_q16)) >> 16
	else:
		_storm_damage += int(rules.increment)


func _finish_red_rift() -> bool:
	var rift = _stage.red_rift
	if not rift or rift.status == rift.Status.PENDING:
		return false
	var won: bool = rift.status == rift.Status.COMPLETE
	if _stage.track_contract_progress:
		rift.save_outcome(_stage.contract_progress_path, won)
	_record_run_end()
	phase = Phase.RESULT
	if is_instance_valid(crossroads):
		crossroads.hide()
	if first_shop:
		first_shop.hide()
	_result.text = tr("UI.RiftSealingProtocol.Victory" if won else "UI.RiftSealingProtocol.Defeat")
	_continue.hide()
	_summary_button.show()
	return true


func restore_rewind() -> void:
	rewind_available = true
	rewind_reserve = int(_stage.rewind_starting_shards)


func _remove_sold_hero(id: int) -> void:
	_formation.erase(id)
	for unit in _units:
		if unit.is_hero and int(unit.stat("Id")._sequentialId) == id:
			unit.hide()
			break


func open_first_shop() -> void:
	if _first_tutorial != null and not _first_tutorial.can_open_shop():
		return
	if phase == Phase.RESULT and first_shop != null and _continue.visible:
		_continue.hide()
		_result_view.hide()
		if not trial.is_empty():
			_enter_next_battle()
			return
		if _stage.endless_floor >= 0:
			if not _endless_won:
				_show_end_screen()
			elif (_stage.endless_floor + 1) % _stage.endless_maps.size() == 0:
				_show_crossroads()
			else:
				_enter_next_battle()
			return
		if challenge_modifier and not crossroads.get("rewards").is_empty():
			phase = Phase.RELIC_REWARD
			crossroads.call("show_rewards")
		else:
			_show_shop()


func _show_shop() -> void:
	challenge_modifier = 0
	phase = Phase.SHOP
	if first_shop.super_shop:
		_stage.sound.start_super_shop()
	first_shop.claim_and_open()
	if _first_tutorial != null:
		_first_tutorial.notify_battle_flow(_first_tutorial.BattleFlow.SHOP)
		_first_tutorial = null


func _open_crossroads() -> void:
	if phase != Phase.SHOP:
		return
	if _stage.red_rift != null and int(_stage.floor_rules().local_floor) == 4:
		var rift = _stage.red_rift
		rift.fail(rift.Mission.FIRST_KEY if int(_stage.floor_rules().chunk) == 0 else rift.Mission.SECOND_KEY)
		if _finish_red_rift():
			_result_rewards.clear()
			_present_result(false, false)
			return
	if _stage.track_contract_progress and not _stage.normal_opening and first_shop.visit == 3:
		var draft_rules = load("res://battle/opening_draft.gd")
		draft_rules.save_value(_stage.contract.read_progress(_stage.contract_progress_path), _stage.contract_progress_path, "tutorial_checkpoint", true)
	if _stage.floor_rules().get("event_override") == 1 or int(_stage.field(_stage.stage, "StageType")) == 3:
		_enter_next_battle()
		return
	_show_crossroads()


func _show_crossroads() -> void:
	phase = Phase.CROSSROADS
	if is_instance_valid(crossroads):
		crossroads.queue_free()
	crossroads = (load("res://UI/first_crossroads.tscn") as PackedScene).instantiate()
	if _stage.endless_floor < 0 and _stage.floor_rules().get("event_override") == 3:
		crossroads.set_script(load("res://battle/challenge_crossroads.gd"))
		crossroads.connect("relic_selected", func(_id: int): _show_shop(), CONNECT_ONE_SHOT)
	_ui.add_child(crossroads)
	crossroads.path_selected.connect(func():
		phase = Phase.EVENT
		if _stage.battle_camera != null and _stage.encounter == self:
			var path := crossroads.offers.find(crossroads.selected_event)
			_stage.battle_camera.set_state("crossroads_zoom", _stage.crossroads_gate_position(path))
		_stage.set_crossroads_gate_icons())
	crossroads.paths_restored.connect(func():
		phase = Phase.CROSSROADS
		_show_crossroads_gate_icons())
	crossroads.path_hovered.connect(func(index: int): _stage.set_crossroads_gate_hover(index))
	crossroads.reward_claimed.connect(first_shop.apply_event_reward)
	crossroads.departed.connect(_enter_second_battle)
	crossroads.setup(first_shop.roster, first_shop)
	_show_crossroads_gate_icons()


func _show_crossroads_gate_icons() -> void:
	if phase != Phase.CROSSROADS or not is_instance_valid(crossroads):
		return
	var icons: Array[Texture2D] = []
	for index in crossroads.offers.size():
		icons.append(crossroads.path_icon(index))
	_stage.set_crossroads_gate_icons(icons)
	_update_crossroads_geometry()


func _update_crossroads_geometry() -> void:
	if phase != Phase.CROSSROADS or not is_instance_valid(crossroads):
		return
	var hit_rects: Array[Rect2] = _stage.crossroads_gate_screen_rects()
	var label_rects: Array[Rect2] = _stage.crossroads_gate_label_rects()
	crossroads.use_world_gates(hit_rects, label_rects)


func _enter_second_battle() -> void:
	if phase != Phase.EVENT or not crossroads.claimed:
		return
	_enter_next_battle(crossroads.pending_trial)


func _enter_next_battle(next_trial: Dictionary = {}) -> void:
	var endless: bool = _stage.endless_floor >= 0 or int(_stage.field(_stage.stage, "StageType")) == 3
	var from_challenge: bool = not endless and _stage.floor_rules().get("event_override") == 3
	if not next_trial.is_empty():
		if not _stage.load_board(int(next_trial.stage_id)):
			return
	elif endless:
		if not _stage.advance_endless():
			return
		var floor_number: int = _stage.endless_floor + 1
		_floor_label.text = tr("UI.EndScreen.EndlessFloor").format({"floor": floor_number})
		_floor_label.tooltip_text = tr("UI.EndlessMode.Description").format({"floor": floor_number, "cycle": _stage.endless_cycle() + 1})
		_floor_label.show()
	else:
		var candidates: Array[int] = _stage.next_floor_candidates()
		if candidates.is_empty() or not _stage.load_board(candidates.pick_random()):
			return
		first_shop.enter_kit_floor(int(_stage.field(_stage.stage, "FloorNumber")) + 1, int(_stage.field(_stage.stage, "StageType")) == 3)
		if _stage.track_contract_progress and int(_stage.field(_stage.stage, "StageType")) == 3:
			load("res://battle/opening_draft.gd").reached_boss(_stage.contract_progress_path)
	if not trial.is_empty() and _trial_won:
		first_shop.apply_event_reward(String(trial.kind), int(trial.value), 0)
	trial = next_trial.duplicate()
	_trial_won = false
	if is_instance_valid(crossroads):
		crossroads.hide()
	challenge_modifier = crossroads.selected_event if from_challenge and trial.is_empty() else 0
	_pain_timer = 0
	if is_instance_valid(_equipment_panel):
		_equipment_panel.free()
		_equipment_panel = null
	for bar: Control in _bars.values():
		bar.free()
	_bars.clear()
	_units.clear()
	_strike_areas.clear()
	_path_forecasts.clear()
	_shots.clear()
	_specialization_stat_effects.clear()
	if is_instance_valid(_projectile_effects):
		_projectile_effects.free()
		_projectile_effects = null
	_drags.clear()
	_frame = 0
	battle_time_q16 = 0
	_grid = _stage.grid
	for unit: GuildrunBoardUnit in _grid.occupants.values():
		_register(unit)
	enter_trial_formation()
	var active := first_shop.deployed_ids()
	_hero = null
	var reserved_cells: Array = []
	for id in active:
		if _formation.has(id):
			reserved_cells.append(_formation[id])
	for id in active:
		var cell: Vector2i = _formation.get(id, Vector2i(-1, -1))
		if not _grid.contains(cell) or _grid.occupants.has(cell):
			cell = _next_free_position(reserved_cells)
		var unit := _deploy_owned(id, cell)
		if id == active[0]:
			_hero = unit
	if not first_shop.items.is_empty():
		_open_equipment()
	if not is_instance_valid(_reserve_panel):
		_reserve_panel = load("res://battle/reserve_panel.gd").new()
		_ui.add_child(_reserve_panel)
		_reserve_panel.setup(self)
	_reserve_panel.hide()
	_reserve_toggle.show()
	_fight.show()
	_fight.disabled = active.is_empty()
	phase = Phase.PLACE
	if active.is_empty():
		_toggle_reserve()


func _open_equipment() -> void:
	_equipment_panel = GuildrunEquipmentPanel.new()
	_ui.add_child(_equipment_panel)
	_equipment_panel.setup(first_shop, _stage)
	_equipment_panel.hide()
	_equipment_panel.assignment_changed.connect(_refresh_deployed_stats)
	for unit in _units:
		if unit.is_hero:
			_bars[unit].set_equipment(_stage, first_shop, _equipment_panel, int(unit.stat("Id")._sequentialId))


func _record_run_end() -> void:
	if not _stage.track_contract_progress or _xp_recorded:
		return
	_xp_recorded = true
	var endless: bool = _stage.endless_floor >= 0
	var chunks := 2 if endless else int(_stage.floor_rules().get("chunk", 0))
	load("res://battle/opening_draft.gd").finish_run(_stage.contract_progress_path, _regular_wins, chunks, endless, _stage.endless_cycle() if endless else 0)


func _show_end_screen() -> void:
	if _first_tutorial != null:
		_first_tutorial.abort()
		_first_tutorial = null
	if phase != Phase.RESULT:
		return
	_summary_button.hide()
	_result_view.hide()
	phase = Phase.END_SCREEN
	var screen = (load("res://UI/end_screen.tscn") as PackedScene).instantiate()
	_ui.add_child(screen)
	screen.setup(_stage, first_shop)
	screen.new_run.connect(func():
		if _stage.track_contract_progress:
			var menu = (load("res://UI/contracts.tscn") as PackedScene).instantiate()
			menu.selecting = true
			menu.progress_path = _stage.contract_progress_path
			get_tree().change_scene_to_node(menu)
		else:
			get_tree().reload_current_scene(), CONNECT_ONE_SHOT)


func _refresh_deployed_stats() -> void:
	if phase != Phase.PLACE:
		return
	for unit in _units:
		if unit.is_hero:
			var id := int(unit.stat("Id")._sequentialId)
			var stats: Dictionary = _stage.hero_stats(id, first_shop.hero_modifiers.get(id, []),
					first_shop.equipment(id), first_shop.relics, int(first_shop.hero_ranks[id]),
					first_shop.specializations.get(id, {}), first_shop.rank_modifiers_for(id))
			unit.initialize(stats, unit.grid_cell, unit.direction)
			_bars[unit].set_equipment(_stage, first_shop, _equipment_panel, id)


func _next_free_position(excluded: Array = []) -> Vector2i:
	# Automatic deployment scans the full board. Direct drops have their own half-board check.
	for y in _grid.size.y:
		for x in range(3, _grid.size.x):
			var cell := Vector2i(x, y)
			if not _grid.occupants.has(cell) and not excluded.has(cell):
				return cell
	return Vector2i(-1, -1)


@warning_ignore("integer_division")
func _tick_unit(unit: GuildrunBoardUnit, dt: int) -> void:
	if is_instance_valid(_gm_panel) and _gm_panel.lab.manual_casts and _gm_panel.lab.is_test_scene():
		if unit.is_casting():
			_tick_cast(unit, dt)
		return
	if unit.is_casting() and (unit.ability_kind == "JavrynAction" or (unit.ability_kind == "skorn_taunt" and unit.cast_hit_index > 0)):
		unit.stun_remaining_q16 = 0
	if unit.stun_remaining_q16 > 0:
		unit.stun_remaining_q16 = maxi(0, unit.stun_remaining_q16 - dt)
		return
	# The native targeting pass has already run when an earlier unit kills this target.
	var previous_target := unit.current_target
	if is_instance_valid(previous_target) and previous_target.defeated and _deaths_this_step.has(previous_target):
		return
	if unit.is_casting():
		var cast_target := unit.cast_target
		var lost_target := is_instance_valid(cast_target) and not cast_target.targetable()
		if lost_target:
			cast_target = _nearest_enemy(unit)
		var target_in_range := is_instance_valid(cast_target) and (
				GuildrunBattleGrid.distance(unit.grid_cell, cast_target.grid_cell) <= int(unit.stat("AttackRange")))
		if target_in_range or (not lost_target and (unit.shadow_step >= 0 or unit.cast_release_q16 >= 0)):
			var resume_attack := unit.ability_kind == "SnipeAbilityAction" and unit.cast_release_q16 < 0
			_tick_cast(unit, dt)
			if not resume_attack or unit.is_casting():
				return
		else:
			# ActiveAbilityFsmState may leave a cast when the replacement target is out of range.
			if unit.shadow_step >= 0:
				_finish_shadow_strike(unit)
			else:
				unit.cast_release_q16 = -1
				unit.cast_remaining_q16 = 0
				unit.cancel_cast_visuals()
				_finish_cast(unit)
	if unit.moving and not unit.position.is_equal_approx(GuildrunBattleGrid.center(unit.move_destination)):
		var planned: Dictionary = _planned_moves.get(unit, {})
		if not planned.is_empty() and unit.move_destination != planned.path[0]:
			unit.move_destination = planned.path[0]
			_path_forecasts[unit] = planned.get("forecast", NO_SLOT)
			unit.current_target = planned.target
			unit.face_point(GuildrunBattleGrid.center(unit.move_destination))
		_advance_grid_move(unit, dt)
		return
	var target := unit.current_target
	if unit.is_hero or not is_instance_valid(target) or not target.targetable():
		target = _nearest_enemy(unit)
	if target != null and is_instance_valid(previous_target) and not previous_target.targetable() and not unit.moving:
		# EntityTargetingSystem resets the basic attack state when replacing a lost target.
		unit.attack_cooldown_q16 = 0
		unit.reset_basic_attack()
	unit.current_target = target
	var attack_range := int(unit.stat("AttackRange"))
	var in_range := target != null and GuildrunBattleGrid.distance(unit.grid_cell, target.grid_cell) <= attack_range
	if not in_range and target != null and _start_grid_move(unit, target, attack_range):
		_advance_grid_move(unit, dt)
		return
	if unit.moving or not in_range:
		if unit.moving or unit.attack_animation_active():
			unit.play_idle()
		unit.moving = false
		unit.reset_basic_attack()
		return
	unit.face_point(target.position)
	if not unit.ability_kind.is_empty() and unit.mana >= int(unit.stat("MaxMana")) and unit.mana_lock_q16 <= 0:
		unit.begin_active_ability(target, _keyword_clocks.stall_elapsed(unit, battle_time_q16))
		if unit.ability_kind == "JavrynAction":
			unit.javryn_targets = _javryn_action.allocate(unit, _units)
		_stage.sound.play_character(unit.base_stats, unit.is_hero, "skill_cast", unit.global_position)
		_stage.sound.play_character(unit.base_stats, unit.is_hero, "skill_vo", unit.global_position)
		_tick_cast(unit, dt)
		return
	unit.attack_cooldown_q16 -= dt
	if unit.attack_cooldown_q16 <= 0:
		var speed := maxi(1, 65536 + int(unit.stat("AttackSpeed")) * 65536 / 100)
		var rate := clampi((int(unit.stat("BaseAttackSpeed").RawValue) * speed + 32768) >> 16, 13107, 327680)
		unit.attack_cooldown_q16 += (1 << 32) / rate
		_begin_basic_attack(unit, target, speed)
		_stage.sound.play_character(unit.base_stats, unit.is_hero, "attack_cast", unit.global_position)
	var was_attacking := unit.attack_animation_active()
	unit.advance_basic_attack(dt)
	if was_attacking and not unit.attack_animation_active():
		unit.finish_action_motion(&"BasicAttack")


func _plan_battle_moves() -> void:
	_planned_moves.clear()
	# The native pathfinding pass takes the current occupancy, then reserves each
	# chosen step in effective-health order before any actor moves.
	var order: Array[int] = []
	var priorities: Dictionary[int, float] = {}
	var reserved: Dictionary[Vector2i, GuildrunBoardUnit] = {}
	for index in _units.size():
		var unit := _units[index]
		if unit.defeated:
			continue
		var able_to_plan := unit.stun_remaining_q16 <= 0 and not unit.is_casting()
		if unit.moving and (unit.grid_cell == unit.move_destination or not able_to_plan):
			reserved[unit.move_destination] = unit
			if not unit.position.is_equal_approx(GuildrunBattleGrid.center(unit.move_destination)):
				continue
		if not able_to_plan:
			continue
		order.append(index)
		priorities[index] = _effective_health(unit)
	order.sort_custom(func(a: int, b: int) -> bool:
		if _units[a].is_hero != _units[b].is_hero:
			return _units[a].is_hero
		return priorities[a] < priorities[b] if priorities[a] != priorities[b] else a < b)
	for index in order:
		var unit := _units[index]
		if unit.moving and unit.grid_cell != unit.move_destination:
			# Until a unit enters its destination, higher-priority allies may reserve it.
			if not reserved.has(unit.move_destination):
				reserved[unit.move_destination] = unit
				continue
			_planned_moves[unit] = {"target": unit.current_target, "path": [unit.grid_cell]}
		var target := unit.current_target
		if unit.is_hero or not is_instance_valid(target) or not target.targetable():
			target = _nearest_enemy(unit)
		if target == null:
			continue
		var attack_range := int(unit.stat("AttackRange"))
		if GuildrunBattleGrid.distance(unit.grid_cell, target.grid_cell) <= attack_range:
			continue
		var excluded: Array[GuildrunBoardUnit] = []
		while is_instance_valid(target):
			if GuildrunBattleGrid.distance(unit.grid_cell, _path_target_cell(target)) <= attack_range:
				break
			var path := _find_grid_path(unit, target, attack_range, reserved, not excluded.is_empty())
			if not path.is_empty():
				reserved[path[0]] = unit
				var forecast: Vector2i = path[1] if not excluded.is_empty() and path.size() > 1 else NO_SLOT
				_planned_moves[unit] = {"target": target, "path": path, "forecast": forecast}
				break
			# The native traversal tries the next candidate when the current
			# target has no reachable cell in attack range.
			excluded.append(target)
			target = _nearest_enemy(unit, excluded)


func _start_grid_move(unit: GuildrunBoardUnit, target: GuildrunBoardUnit, attack_range: int) -> bool:
	var planned: Dictionary = _planned_moves.get(unit, {})
	var path: Array = planned.get("path", [])
	var planned_target: GuildrunBoardUnit = planned.get("target")
	if path.is_empty() or not is_instance_valid(planned_target) or not planned_target.targetable() or _grid.occupants.has(path[0]):
		var reserved: Dictionary[Vector2i, GuildrunBoardUnit] = {}
		for other in _units:
			if other != unit and not other.defeated and other.moving:
				reserved[other.move_destination] = other
		for other: GuildrunBoardUnit in _planned_moves:
			if other != unit and not other.defeated:
				reserved[_planned_moves[other].path[0]] = other
		path = _find_grid_path(unit, target, attack_range, reserved)
	else:
		unit.current_target = planned_target
	if path.is_empty():
		return false
	_path_forecasts[unit] = planned.get("forecast", NO_SLOT) if path == planned.get("path") else NO_SLOT
	unit.move_destination = path[0]
	unit.face_point(GuildrunBattleGrid.center(unit.move_destination))
	if not unit.moving:
		unit.reset_basic_attack()
		unit.moving = true
		unit.play_state("Move")
	return true


func _path_target_cell(target: GuildrunBoardUnit) -> Vector2i:
	if _planned_moves.has(target):
		return _planned_moves[target].path[0]
	if target.moving:
		var forecast: Vector2i = _path_forecasts.get(target, NO_SLOT)
		if target.grid_cell == target.move_destination and forecast != NO_SLOT:
			return forecast
		return target.move_destination
	return target.grid_cell


func _find_grid_path(unit: GuildrunBoardUnit, target: GuildrunBoardUnit, attack_range: int,
		reserved: Dictionary[Vector2i, GuildrunBoardUnit], ordered_goals := false) -> Array[Vector2i]:
	var target_cell := _path_target_cell(target)
	if GuildrunBattleGrid.distance(unit.grid_cell, target_cell) <= attack_range:
		return []
	var goals: Array[Vector2i] = []
	if ordered_goals:
		# GetTargetPositions reverses the rings appended by HexGridUtils.
		const ring_directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
				Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
		var origin := Vector2i(target_cell.x - (target_cell.y >> 1), target_cell.y)
		for radius in range(attack_range, 0, -1):
			var axial := origin + ring_directions[4] * radius
			for direction in range(5, -1, -1):
				for step in radius:
					axial -= ring_directions[direction]
					var cell := Vector2i(axial.x + (axial.y >> 1), axial.y)
					if not _grid.contains(cell) or _grid.occupants.has(cell) or reserved.has(cell):
						continue
					var path := _grid.find_path(unit.grid_cell, [cell], reserved)
					if not path.is_empty():
						return path
		goals.append(target_cell)
		return _grid.find_path(unit.grid_cell, goals, reserved)
	for x in _grid.size.x:
		for y in _grid.size.y:
			var cell := Vector2i(x, y)
			if GuildrunBattleGrid.distance(cell, target_cell) <= attack_range:
				goals.append(cell)
	return _grid.find_path(unit.grid_cell, goals, reserved)

func _advance_grid_move(unit: GuildrunBoardUnit, dt: int) -> void:
	var dest := GuildrunBattleGrid.center(unit.move_destination)
	var distance_q16 := (int(unit.stat("MoveSpeed").RawValue) * dt + 32768) >> 16
	var travel := GuildrunBattleGrid.to_world_length_q16(distance_q16) / 65536.0
	unit.position = unit.position.move_toward(dest, travel)
	# During a step the occupied cell changes at the shared hex edge.
	if unit.grid_cell != unit.move_destination:
		var origin := GuildrunBattleGrid.center(unit.grid_cell)
		if unit.position.distance_squared_to(dest) <= unit.position.distance_squared_to(origin):
			if _grid.occupants.has(unit.move_destination):
				unit.position = origin
				unit.moving = false
				unit.play_idle()
				return
			_claim_cell(unit, unit.move_destination)


func _begin_basic_attack(unit: GuildrunBoardUnit, target: GuildrunBoardUnit, speed: int) -> void:
	unit.begin_basic_attack(target, speed)
	_record_rank_credit(&"attack", unit)
	RANK_ATTACK_CONDITION.apply_at_start(unit, target, first_shop, _units)


func _claim_cell(unit: GuildrunBoardUnit, cell: Vector2i) -> void:
	_grid.occupants.erase(unit.grid_cell)
	unit.grid_cell = cell
	unit.set_meta("grid_cell", cell)
	_grid.occupants[cell] = unit


@warning_ignore("integer_division")
func _on_attack_action(target: GuildrunBoardUnit, source: GuildrunBoardUnit) -> void:
	if target.defeated or source.defeated:
		return
	source.passive_attacks += 1
	if source.passive_attacks % 3 == 0:
		match source.passive_id():
			114: _add_poison(target, int(source.stat("Crit")) / 33, source)
			118: _add_poison(target, 1 + int(source.stat("Crit")) / 50, source)
			120: _add_poison(target, 1 + int(source.stat("Crit")) / 33, source)
	var damage := source.effective_attack_damage()
	var settings: Dictionary = source.stat("AttackSettings")
	var speed := int(settings["<ProjectileSpeed>k__BackingField"].RawValue)
	if speed > 0:
		_queue_shot(source, target, damage, speed, "attack_hit")
	else:
		_stage.sound.play_character(source.base_stats, source.is_hero, "attack_hit", target.global_position)
		_resolve_auto_hit(target, damage, source)
	source.gain_mana(_stage.mana_per_attack)
	if source.permafrost_targets > 0:
		_queue_permafrost_attacks(source, target, speed)
	if DRAGON_ATTACK_STATUS.has(source.passive_id()):
		for adjacent in _units:
			if adjacent.is_hero and not adjacent.defeated and GuildrunBattleGrid.distance(adjacent.grid_cell, target.grid_cell) == 1:
				var extra := (source.effective_attack_damage() * 43254) >> 16
				_queue_shot(source, adjacent, extra, speed, "attack_hit")
	if source.passive_id() == 205:
		for extra_hit in source.hydra_heads - 1:
			if target.defeated:
				break
			var bonus := (source.effective_attack_damage() * 21627) >> 16
			var bonus_crit := _is_critical(source)
			_land(target, _critical_damage(source, bonus) if bonus_crit else bonus, source, bonus_crit,
					GuildrunBattleStatistics.Origin.ATTACK)


func _queue_shot(source: GuildrunBoardUnit, target: GuildrunBoardUnit, damage: int, speed_q16: int, cue := "skill_hit") -> void:
	var shot := {"source": source, "target": target, "damage": damage, "position": source.position,
			"speed": GuildrunBattleGrid.to_world_length_q16(speed_q16), "cue": cue}
	if source.ability_kind == "wildfire" and cue == "skill_hit":
		var direction := source.position.direction_to(target.position)
		var flight_basis := Basis.IDENTITY if direction.is_zero_approx() else Basis.looking_at(direction)
		shot["effect"] = _play_projectile_effect("res://battle/funke_skill_projectile.tscn",
				Transform3D(flight_basis, source.position))
	elif cue == "attack_hit":
		_prepare_projectile_visual(shot, source, target)
	_shots.append(shot)


func _prepare_projectile_visual(shot: Dictionary, source: GuildrunBoardUnit, target: GuildrunBoardUnit) -> void:
	if _projectile_vfx.is_empty():
		_projectile_targets = _read_projectile_json("res://battle/projectiles/target_offsets.json")
		_projectile_target_bones = _read_projectile_json("res://battle/projectiles/target_bones.json")
	var prefab: int = _stage.character_projectile(source.stat("VisualConfig"))
	if not _projectile_vfx.has(prefab):
		_projectile_vfx[prefab] = _read_projectile_json("res://battle/projectiles/%d.json" % prefab)
	var visual: Dictionary = _projectile_vfx[prefab]
	if visual.is_empty():
		return
	shot["visual"] = visual
	shot["launch_offset"] = source.basis.orthonormalized() * _projectile_vector(visual.launch_offset) + source.visual_offset
	shot["distance_traveled"] = 0.0
	if bool(visual.match_source_scale):
		var rigs := source.find_children("*", "Skeleton3D", true, false)
		var visual_basis := source.basis
		if not rigs.is_empty():
			var skeleton: Skeleton3D = rigs[0]
			visual_basis = source.get_parent_node_3d().global_basis.inverse() * skeleton.global_basis
		shot["scale"] = visual_basis.get_scale().abs()
	var target_id := str(int(target.stat("VisualConfig").m_PathID))
	var bone: String = _projectile_target_bones.get(target_id, "")
	if not bone.is_empty():
		for skeleton: Skeleton3D in target.find_children("*", "Skeleton3D", true, false):
			var index := skeleton.find_bone(bone)
			if index >= 0:
				shot["target_skeleton"] = skeleton
				shot["target_bone"] = index
				break
	shot["visual_pose"] = _projectile_visual_pose(shot, source.position, source.position.direction_to(target.position))
	if visual.has("flight"):
		var pose: Transform3D = shot.visual_pose
		var effect := _play_projectile_effect(visual.flight, pose, true)
		if effect != null:
			shot["effect"] = effect
			shot["effect_local"] = pose.affine_inverse() * effect.transform


func _read_projectile_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _projectile_vector(data: Array) -> Vector3:
	return Vector3(data[0], data[1], data[2])


func _projectile_visual_pose(shot: Dictionary, position: Vector3, direction: Vector3) -> Transform3D:
	var visual: Dictionary = shot.visual
	var target: GuildrunBoardUnit = shot.target
	var target_id := str(int(target.stat("VisualConfig").m_PathID))
	var socket: Array = _projectile_targets.get(target_id, [0.0, 0.0, 0.0])
	var destination := target.basis * _projectile_vector(socket) + target.visual_offset
	var skeleton: Skeleton3D = shot.get("target_skeleton")
	if is_instance_valid(skeleton):
		var bone: Transform3D = skeleton.get_bone_global_pose(shot.target_bone)
		destination = target.get_parent_node_3d().to_local(skeleton.to_global(bone.origin)) - target.position
	var remaining := position.distance_to(target.position + destination)
	var traveled: float = shot.distance_traveled
	var progress := clampf(traveled / maxf(0.000001, traveled + remaining), 0.0, 1.0)
	var forward := _projectile_vector(visual.forward)
	var up := _projectile_vector(visual.up)
	var launch_offset: Vector3 = shot.launch_offset
	var origin := position + launch_offset.lerp(destination, progress)
	if visual.has("arc"):
		var arc: Dictionary = visual.arc
		var t := clampf((traveled + remaining) / float(arc.distance), 0.0, 1.0)
		var height := smoothstep(0.0, 1.0, t) * float(arc.height)
		height += t * (1.0 - t) * (1.0 - t) * float(arc.distance) * float(arc.initial_tangent)
		origin.y += sin(PI * progress) * height
	var previous: Transform3D = shot.get("visual_pose", Transform3D.IDENTITY)
	var alignment := previous.basis
	if not direction.is_zero_approx():
		var visual_direction := previous.origin.direction_to(origin) if shot.has("visual_pose") else direction
		if visual_direction.is_zero_approx() or absf(visual_direction.dot(Vector3.UP)) > 0.999:
			visual_direction = direction
		var pitch := deg_to_rad(float(visual.pitch_degrees)) * (1.0 - progress)
		alignment = Basis.looking_at(visual_direction) * Basis(Vector3.RIGHT, pitch)
		alignment *= Basis.looking_at(forward, up).inverse()
		alignment = alignment.scaled_local(shot.get("scale", Vector3.ONE))
	return Transform3D(alignment, origin)


func _play_projectile_effect(path: String, pose: Transform3D, retain_local := false) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	if not is_instance_valid(_projectile_effects):
		_projectile_effects = Node3D.new()
		_projectile_effects.name = &"ProjectileEffects"
		_stage.get_node("Battle/BattleGrid").add_child(_projectile_effects)
	var effect := scene.instantiate() as Node3D
	effect.transform = pose * effect.transform if retain_local else pose
	effect.speed_scale = 0.0 if _tutorial_paused() else simulation_speed.multiplier()
	effect.scene_time = effect_scene_time
	_projectile_effects.add_child(effect)
	return effect


func _advance_projectiles(dt: int) -> void:
	var pending: Array[Dictionary] = []
	for shot in _shots:
		var target: GuildrunBoardUnit = shot.target
		var effect: Variant = shot.get("effect")
		if not is_instance_valid(target):
			if is_instance_valid(effect):
				effect.hide()
				effect.queue_free()
			continue
		var travel_q16 := (int(shot.speed) * dt + 32768) >> 16
		var position: Vector3 = shot.position
		position = position.move_toward(target.position, float(travel_q16) / 65536.0)
		var movement: Vector3 = position - shot.position
		var direction := movement.normalized()
		shot.position = position.snappedf(1.0 / 65536.0)
		if shot.has("visual"):
			shot.distance_traveled += movement.length()
			shot["visual_pose"] = _projectile_visual_pose(shot, shot.position, direction)
			if is_instance_valid(effect):
				effect.transform = (shot.visual_pose as Transform3D) * (shot.effect_local as Transform3D)
		elif is_instance_valid(effect):
			if not direction.is_zero_approx():
				effect.basis = Basis.looking_at(direction)
			effect.position = shot.position
		var delta := Vector3i(((shot.position - target.position) * 65536.0).round())
		var squared := _squared_q16(delta.x) + _squared_q16(delta.y) + _squared_q16(delta.z)
		if squared <= _squared_q16(int(target.stat("CircleCollisorRadius").RawValue)):
			if shot.has("visual"):
				if shot.visual.has("impact"):
					_play_projectile_effect(shot.visual.impact, shot.visual_pose, true)
			elif shot.has("effect"):
				var impact_basis := Basis.IDENTITY if direction.is_zero_approx() else Basis.looking_at(direction)
				_play_projectile_effect("res://battle/funke_skill_hit.tscn",
						Transform3D(impact_basis, position + Vector3.UP))
			if is_instance_valid(effect):
				effect.hide()
				effect.queue_free()
			if not target.defeated:
				_stage.sound.play_character(shot.source.base_stats, shot.source.is_hero, shot.cue, target.global_position)
				if shot.cue == "attack_hit":
					_resolve_auto_hit(target, shot.damage, shot.source)
				elif shot.source.ability_kind in ["SnipeAbilityAction", "IriniSpearThrowAction"]:
					_land_critable(target, shot.damage, shot.source)
				elif shot.source.ability_kind == "HoyoungAbilityAction":
					_land_killshot(shot.source, target, shot.damage)
				elif shot.source.ability_kind == "JavrynAction":
					_land_critable(target, shot.damage, shot.source)
					if not target.defeated:
						_add_elemental_status(target, 2, 3 + 2 * shot.source.rank)
				else:
					_land(target, shot.damage, shot.source)
		else:
			pending.append(shot)
	_shots = pending


func _squared_q16(value: int) -> int:
	return (value * value + 32768) >> 16


func _tick_cast(unit: GuildrunBoardUnit, dt: int) -> void:
	if unit.shadow_step >= 0:
		_tick_shadow_strike(unit, dt)
		return
	if unit.cast_release_q16 >= 0:
		unit.cast_release_q16 -= dt
		if unit.cast_release_q16 <= 0:
			if unit.ability_kind == "hook_strike" and unit.cast_hit_index == 0:
				unit.cast_hit_index = 1
				unit.cast_release_q16 = _begin_hook(unit)
				unit.cast_remaining_q16 = maxi(1, unit.cast_remaining_q16 - dt)
				return
			if unit.ability_kind == "lizard_strike" and unit.cast_hit_index == 0:
				unit.cast_hit_index = 1
				var target := _lowest_health_enemy(unit)
				if target:
					var cell := _grid.best_front_cell(unit.grid_cell, target.grid_cell)
					_claim_cell(unit, cell)
					unit.position = GuildrunBattleGrid.center(cell)
					unit.face_point(target.position)
				unit.cast_release_q16 = int(unit.ability_data._attacks._attacks[0]["<Delay>k__BackingField"].RawValue)
				unit.cast_remaining_q16 = maxi(1, unit.cast_remaining_q16 - dt)
				return
			if unit.ability_kind == "slime_strike" and not unit.slime_cleansed:
				unit.slime_cleansed = true
				unit.burn_stacks -= (unit.burn_stacks * int(unit.ability_data.cleanse._cleansePercent.RawValue)) >> 16
				unit.poison_stacks -= (unit.poison_stacks * int(unit.ability_data.cleanse._cleansePercent.RawValue)) >> 16
				_set_frost(unit, unit.frost_stacks - ((unit.frost_stacks * int(unit.ability_data.cleanse._cleansePercent.RawValue)) >> 16))
				unit.cast_release_q16 = int(unit.ability_data._attacks._attacks[0]["<Delay>k__BackingField"].RawValue)
				unit.cast_remaining_q16 = maxi(1, unit.cast_remaining_q16 - dt)
				return
			var overshoot := -unit.cast_release_q16
			unit.cast_release_q16 = -1
			match unit.ability_kind:
				"ForestGolemAction":
					var damage := _ability_attack_damage(unit, unit.ability_data._attacks._attacks[0])
					for target in _units:
						if target.is_hero == unit.is_hero or target.defeated:
							continue
						if GuildrunBattleGrid.distance(unit.grid_cell, target.grid_cell) == 1:
							_land(target, damage, unit)
							target.stun_remaining_q16 = maxi(target.stun_remaining_q16, int(unit.ability_data._stunDuration.RawValue))
				"demon_anger":
					var shield: Dictionary = unit.ability_data.ApplyShieldFromTargetStatAction
					unit.gain_shield((unit.max_health * int(shield.Percent.RawValue)) >> 16, int(shield.Duration.RawValue))
					var fire: Dictionary = unit.ability_data.ApplyStatusFromOwnerStatPercentAction
					_burn_opponents(unit, int(fire._base) + ((int(unit.stat("Attack")) * int(fire._percent.RawValue)) >> 16))
				"HydraAction":
					var victim := unit.cast_target
					if is_instance_valid(victim) and not victim.defeated:
						var data := unit.ability_data
						var damage := _ability_attack_damage(unit, data._attacks._attacks[0])
						var poison := int(data._basePoisonPerHead) + int(unit.stat("Attack")) / int(data._poisonPerHeadAttackInterval)
						_add_poison(victim, unit.hydra_heads * poison, unit)
						_land(victim, unit.hydra_heads * damage, unit)
				"SeraphaelAbilityAction", "AreaOfEffectAction", "SnakeAction", "FloeriaAbilityAction", "GustavAbilityAction", "PimentaAbilityAction":
					_start_recruit_area(unit)
				"RookAction":
					if is_instance_valid(unit.cast_target) and unit.cast_target.targetable():
						_start_recruit_area(unit)
				"SpiderEnsnareAction":
					var victim := _farthest_enemy(unit)
					if victim:
						var poison := int(unit.ability_data._basePoison) + ((int(unit.stat("Crit")) * int(unit.ability_data._critPoisonScaling.RawValue)) >> 16)
						_add_poison(victim, poison, unit)
						victim.stun_remaining_q16 = maxi(victim.stun_remaining_q16, int(unit.ability_data._stunDuration.RawValue))
				"JosephinaAction":
					_release_blessing(unit)
				"FionaAction":
					_release_vault_spark(unit)
				"petrification":
					_release_petrification(unit)
				"skorn_taunt":
					_release_skorn_action(unit)
				"permafrost":
					var effect: Dictionary = unit.ability_data.SalActiveEffectAction
					unit.permafrost_targets += 1
					unit.permafrost_damage += int(effect.baseBonusDamage) + ((int(unit.stat("Magic")) * int(effect.magicBonusPercent.RawValue)) >> 16)
					unit.permafrost_frost += unit.rank * int(effect.frostPerRank)
				"specialization_stat_effect":
					_apply_specialization_stat_effect(unit, unit.ability_data)
				"TillyAction":
					_release_tilly_action(unit, overshoot)
				"MingAbilityAction":
					_release_ming_action(unit)
				"NyxaAction":
					_release_nyxa_action(unit)
				"IriniSpearThrowAction":
					_release_irini_action(unit)
				"HoyoungAbilityAction":
					var target := _farthest_enemy(unit)
					if target:
						var damage := _ability_attack_damage(unit, unit.ability_data._attacks._attacks[0])
						_queue_shot(unit, target, damage, int(unit.ability_data._projectileSpeed.RawValue))
				"NiklasAction":
					_release_wheel_and_deal(unit)
				"JavrynAction":
					_release_snowpiercer(unit)
				"ReynaAction", "DragomirAction", "RatnaAbilityAction", "LoganAbilityAction":
					_release_recruit_attack(unit)
					unit.cast_hit_index += 1
					var hits: Array = unit.ability_data._attacks._attacks
					if unit.cast_hit_index < hits.size():
						unit.cast_release_q16 = int(hits[unit.cast_hit_index]["<Delay>k__BackingField"].RawValue)
				"wildfire":
					_release_wildfire(unit)
				"SnipeAbilityAction":
					_release_enemy_attack(unit)
					# The native FSM returns to attacking on the step after launch.
					unit.cast_remaining_q16 = dt + 1
				"MeleeAbilityAction", "SkeletonSmashAction", "slime_strike", "lizard_strike", "hook_strike":
					_release_enemy_attack(unit)
				"resolute_strike":
					_strike_areas.append({"source": unit, "position": unit.position,
							"remaining": int(unit.ability_data._aoeDuration.RawValue), "until_hit": int(unit.ability_data.interval)})
			unit.mana = 0
			unit.set_meta("mana", 0)
			_notify_cast_effect(unit)
	unit.cast_remaining_q16 = maxi(unit.cast_release_q16, maxi(0, unit.cast_remaining_q16 - dt))
	if unit.cast_remaining_q16 == 0:
		_finish_cast(unit)


func _finish_cast(unit: GuildrunBoardUnit) -> void:
	if unit.ability_kind == "wildfire" and not unit.cast_effect_fired:
		unit._stop_funke_cast_effects()
	unit.mana_lock_q16 = int(unit.stat("ManaLockTime").RawValue)
	unit.play_idle()


func _apply_specialization_stat_effect(unit: GuildrunBoardUnit, effect: Dictionary) -> void:
	var applied: Dictionary[String, int] = {}
	for modifier: Dictionary in effect.modifiers:
		var data: Dictionary = modifier.data
		var stat: String
		var delta: int
		if modifier.kind == "ModifyStatPerRankAction":
			stat = GuildrunBoardUnit.STAT_NAMES[int(data.StatType)]
			delta = (int(data.Value) + (unit.rank - 1) * int(data.PerRank)) << 16
		else:
			stat = GuildrunBoardUnit.STAT_NAMES[int(data.StatTypeTarget)]
			var source: String = GuildrunBoardUnit.STAT_NAMES[int(data.StatTypeSource)]
			delta = (unit.stat_q16(source) * int(data.Percent.RawValue)) >> 16
			if int(data.Max.RawValue) > 0:
				delta = mini(delta, int(data.Max.RawValue))
		unit.modify_stat_flat_q16(stat, delta)
		applied[stat] = applied.get(stat, 0) + delta
	_specialization_stat_effects.append({"unit": unit, "remaining": int(effect.duration), "applied": applied})


func _tick_specialization_stat_effects(dt: int) -> void:
	for index in range(_specialization_stat_effects.size() - 1, -1, -1):
		var effect := _specialization_stat_effects[index]
		effect.remaining -= dt
		if int(effect.remaining) > 0:
			continue
		var unit: GuildrunBoardUnit = effect.unit
		if is_instance_valid(unit):
			for stat: String in effect.applied:
				unit.modify_stat_flat_q16(stat, -int(effect.applied[stat]))
			unit.health = mini(unit.health, unit.max_health)
			unit.set_meta("health", unit.health)
		_specialization_stat_effects.remove_at(index)


func _release_tilly_action(unit: GuildrunBoardUnit, overshoot: int) -> void:
	var data := unit.ability_data
	var attack: Dictionary = data._attacks._attacks[0]
	if unit.cast_hit_index == 0:
		_apply_specialization_stat_effect(unit, data.stat_effect)
		unit.cast_hit_index = 1
		unit.cast_release_q16 = maxi(0, int(attack["<Delay>k__BackingField"].RawValue) - int(data.stat_effect.delay) - overshoot)
		return
	var damage := _ability_attack_damage(unit, attack)
	var reach := int(unit.stat("AttackRange"))
	for enemy in _units:
		if enemy.is_hero != unit.is_hero and not enemy.defeated:
			if GuildrunBattleGrid.distance(unit.grid_cell, enemy.grid_cell) <= reach:
				_land_critable(enemy, damage, unit)


func _release_ming_action(unit: GuildrunBoardUnit) -> void:
	var data := unit.ability_data
	var damage := _ability_attack_damage(unit, data._attacks._attacks[0])
	var burn := int(data._burnPerRush) * total_rush_triggers
	for enemy in _units:
		if enemy.is_hero != unit.is_hero and not enemy.defeated:
			if GuildrunBattleGrid.distance(unit.grid_cell, enemy.grid_cell) == 1:
				_land_critable(enemy, damage, unit)
				enemy.stun_remaining_q16 = maxi(enemy.stun_remaining_q16, int(data._stunDuration.RawValue))
				_add_elemental_status(enemy, 1, burn, unit)


@warning_ignore("integer_division")
func _release_nyxa_action(unit: GuildrunBoardUnit) -> void:
	var target := unit.cast_target
	if not is_instance_valid(target) or not target.targetable():
		return
	var data := unit.ability_data
	var multiplier := int(data._percentDamage.RawValue)
	multiplier += (int(unit.stat("AttackSpeed")) << 16) / (100 * int(data._attackSpeedScalingInterval))
	multiplier += (int(unit.stat("Attack")) << 16) / (100 * int(data._attackAndMagicScalingInterval))
	multiplier += (int(unit.stat("Magic")) << 16) / (100 * int(data._attackAndMagicScalingInterval))
	_resolve_auto_hit(target, (unit.effective_attack_damage() * multiplier) >> 16, unit)
	unit.cast_hit_index += 1
	if target.defeated:
		var next := _nearest_enemy(unit, [target])
		if next == null:
			unit.cast_remaining_q16 = 0
			return
		var cell := unit.grid_cell
		var closest := 2147483647
		for direction in 6:
			var candidate := GuildrunBattleGrid.neighbor(next.grid_cell, direction)
			if not _grid.contains(candidate) or _grid.occupants.has(candidate):
				continue
			var distance := GuildrunBattleGrid.distance(unit.grid_cell, candidate)
			if distance < closest:
				cell = candidate
				closest = distance
		if cell != unit.grid_cell:
			_claim_cell(unit, cell)
			unit.position = GuildrunBattleGrid.center(cell)
		unit.cast_hit_index = 0
		unit.cast_target = next
		unit.face_point(next.position)
	var attacks: Array = data._attacks._attacks
	if unit.cast_hit_index < attacks.size():
		unit.cast_release_q16 = int(attacks[unit.cast_hit_index]["<Delay>k__BackingField"].RawValue)
	else:
		unit.cast_remaining_q16 = 0


func _release_irini_action(unit: GuildrunBoardUnit) -> void:
	var target := unit.cast_target
	if not is_instance_valid(target) or not target.targetable():
		return
	var data := unit.ability_data
	var per_trigger := int(data._baseDamagePerTrigger)
	per_trigger += (int(unit.stat("AttackSpeed")) * int(data._attackSpeedScalingPercent.RawValue)) >> 16
	per_trigger += (int(unit.stat("Attack")) * int(data._attackScalingPercent.RawValue)) >> 16
	per_trigger += (int(unit.stat("Magic")) * int(data._magicScalingPercent.RawValue)) >> 16
	_queue_shot(unit, target, per_trigger * (total_stall_triggers + total_rush_triggers), int(data._projectileSpeed.RawValue))


func _release_snowpiercer(unit: GuildrunBoardUnit) -> void:
	var index := unit.cast_hit_index
	if index >= unit.javryn_targets.size():
		return
	var target := unit.javryn_targets[index]
	if is_instance_valid(target):
		var attack: Dictionary = _javryn_action.attack_at(unit, index)
		var damage := _ability_attack_damage(unit, attack)
		_queue_shot(unit, target, damage, int(unit.ability_data._projectileSpeed.RawValue))
	unit.cast_hit_index += 1
	if unit.cast_hit_index < unit.javryn_targets.size():
		var next_attack: Dictionary = _javryn_action.attack_at(unit, unit.cast_hit_index)
		unit.cast_release_q16 = int(next_attack["<Delay>k__BackingField"].RawValue)
	else:
		unit.javryn_targets.clear()


func _release_wildfire(unit: GuildrunBoardUnit) -> void:
	var attack: Dictionary = unit.ability_data._attacks._attacks[0]
	var damage := _ability_attack_damage(unit, attack)
	var burn := (int(unit.ability_data._baseBurn.RawValue) + int(unit.stat("Magic")) * int(unit.ability_data._burnMagicMod.RawValue)) >> 16
	for target in _units:
		if target.is_hero == unit.is_hero or target.defeated:
			continue
		if GuildrunBattleGrid.distance(unit.grid_cell, target.grid_cell) <= int(unit.stat("AttackRange")):
			_queue_shot(unit, target, damage, int(unit.ability_data._projectileSpeed.RawValue))
			_add_elemental_status(target, 1, burn, unit)
			if unit.passive_id() == 101403:
				_land(target, target.burn_stacks * 7 * unit.rank, unit)


@warning_ignore("integer_division")
func _apply_fire_opener(unit: GuildrunBoardUnit) -> void:
	var stacks := 25 + int(unit.stat("Magic")) / 3
	for enemy in _units:
		if enemy.is_hero != unit.is_hero and not enemy.defeated and GuildrunBattleGrid.distance(unit.grid_cell, enemy.grid_cell) <= int(unit.stat("AttackRange")):
			_add_elemental_status(enemy, 1, stacks, unit)


func _burn_opponents(source: GuildrunBoardUnit, stacks: int) -> void:
	for target in _units:
		if target.is_hero != source.is_hero and not target.defeated and stacks > 0:
			_add_elemental_status(target, 1, stacks, source)


func _ability_attack_damage(unit: GuildrunBoardUnit, attack: Dictionary) -> int:
	var damage := int(attack["<Damage>k__BackingField"])
	damage += int(attack["<ExtraDamagePerRank>k__BackingField"]) * (unit.rank - 1)
	return _scaled_amount(unit, damage, attack["<Scalings>k__BackingField"])


func _scaled_amount(unit: GuildrunBoardUnit, base: int, scalings: Array) -> int:
	var amount := base
	for scaling: Dictionary in scalings:
		var stat_name: String = GuildrunBoardUnit.STAT_NAMES[int(scaling.Stat)]
		amount += (int(unit.stat(stat_name)) * int(scaling["Rank%dFactor" % clampi(unit.rank, 1, 4)].RawValue)) >> 16
	return amount


func _nearest_enemy(source: GuildrunBoardUnit, excluded: Array[GuildrunBoardUnit] = []) -> GuildrunBoardUnit:
	var target: GuildrunBoardUnit
	var nearest := 2147483647
	var class_priority := 0
	var effective_health := INF
	for candidate in _units:
		if not candidate.targetable() or candidate.is_hero == source.is_hero or excluded.has(candidate):
			continue
		var distance := GuildrunBattleGrid.distance(source.grid_cell, candidate.grid_cell)
		if distance > nearest:
			continue
		# NearestReachableEnemy uses the ordered class list for monsters,
		# followed by the lowest defense-adjusted health for either team.
		var priority := _target_class_priority(candidate) if candidate.is_hero else 0
		var health := _effective_health(candidate)
		if distance < nearest or priority < class_priority or (priority == class_priority and health < effective_health):
			target = candidate
			nearest = distance
			class_priority = priority
			effective_health = health
	return target


func _effective_health(unit: GuildrunBoardUnit) -> float:
	return float(unit.health) * pow(2.0, float(unit.stat_q16("Defense")) / 6553600.0)


func _target_class_priority(hero: GuildrunBoardUnit) -> int:
	var order: Array[int] = _stage.target_class_priority
	for index in order.size():
		if hero.has_class(order[index]):
			return index
	return order.size()


@warning_ignore("integer_division")
func _release_recruit_attack(unit: GuildrunBoardUnit) -> void:
	var target := unit.cast_target
	if not is_instance_valid(target) or not target.targetable():
		target = _nearest_enemy(unit)
		unit.cast_target = target
	if target == null:
		return
	var data := unit.ability_data
	if unit.ability_kind == "ReynaAction":
		var multiplier := mini(int(data._maxPercent.RawValue), 65536
				+ int(unit.stat("Attack")) * int(data._adScalingPercent.RawValue) / 100
				+ int(unit.stat("Magic")) * int(data._apScalingPercent.RawValue) / 100)
		var scaled := unit.effective_attack_damage() * multiplier
		_land_critable(target, scaled >> 16, unit)
		var shield := (scaled * int(data._shieldPercent.RawValue) + 32768) >> 32
		unit.gain_shield(shield, 999 << 16)
		return
	var damage := _ability_attack_damage(unit, data._attacks._attacks[unit.cast_hit_index])
	var critical := _is_critical(unit)
	var dealt := _land(target, _critical_damage(unit, damage) if critical else damage, unit, critical)
	match unit.ability_kind:
		"LoganAbilityAction":
			_track_execution(unit, dealt)
			if int(unit.ability_progress.get("tier", 0)) == 3:
				_start_recruit_area(unit)
		"DragomirAction":
			# The native ability invokes its effect triggers after resolving the hit.
			unit.combat_stats.OmniVamp = int(unit.combat_stats.get("OmniVamp", 0)) + 1 + ((int(unit.stat("Crit")) * 6554) >> 16)
			if target.defeated and first_shop != null:
				first_shop.shards += 2 * unit.rank
		"RatnaAbilityAction":
			if target.defeated:
				unit.permanent_stats.Magic = int(unit.permanent_stats.get("Magic", 0)) + 10 * unit.rank
			if critical:
				for enemy in _units:
					if enemy.is_hero != unit.is_hero and not enemy.defeated:
						enemy.stun_remaining_q16 = maxi(enemy.stun_remaining_q16, unit.rank * 32768)


@warning_ignore("integer_division")
func _release_vault_spark(unit: GuildrunBoardUnit) -> void:
	var data := unit.ability_data
	var candidates: Array[GuildrunBoardUnit] = []
	var ratios := {}
	for ally in _units:
		if ally.is_hero == unit.is_hero and not ally.defeated and ally.health > 0 and ally.max_health > 0:
			ratios[ally] = (ally.health << 16) / ally.max_health
			candidates.append(ally)
	candidates.sort_custom(func(a: GuildrunBoardUnit, b: GuildrunBoardUnit): return ratios[a] < ratios[b])
	var count := int(data._baseAllies) + int(unit.stat("ManaRegen")) / int(data._allyManaRegenIncrement)
	var shield := _scaled_amount(unit, int(data._shieldAmount), data._shieldScalings)
	for i in mini(count, candidates.size()):
		candidates[i].gain_shield(shield, int(data._duration.RawValue), unit)
	unit.ability_progress.casts = int(unit.ability_progress.get("casts", 0)) + 1
	if int(unit.ability_progress.casts) % 5 == 0:
		match unit.passive_id():
			101001:
				if first_shop:
					first_shop.shards += 2 * unit.rank
					_create_rank_item(unit)
			101003:
				unit.ability_progress.stacks = int(unit.ability_progress.get("stacks", 0)) + 1


func _land_killshot(unit: GuildrunBoardUnit, target: GuildrunBoardUnit, damage: int) -> void:
	var bonus := int(unit.stat("Crit")) + 50 * unit.rank
	if unit.passive_id() == 10202 and unit.hunter_hits < unit.rank:
		unit.hunter_hits += 1
		bonus += 50 + 50 * unit.rank
	var critical := _is_critical(unit, bonus)
	_land(target, _critical_damage(unit, damage, bonus) if critical else damage, unit, critical)
	if target.defeated and unit.passive_id() == 10202 and first_shop:
		first_shop.shards += maxi(0, GuildrunBattleGrid.distance(unit.grid_cell, target.grid_cell) - 1)


func _release_petrification(unit: GuildrunBoardUnit) -> void:
	var hit: Dictionary = unit.ability_data.DealDamageWithScalingAction
	var status: Dictionary = unit.ability_data.ZuriApplyStunAndPoisonAction
	var damage := _scaled_amount(unit, int(hit.BaseDamage), hit.Scalings)
	for target in _units:
		if target.is_hero == unit.is_hero or target.defeated or target.current_target != unit:
			continue
		target.stun_remaining_q16 = maxi(target.stun_remaining_q16, int(status._baseStunDuration) << 16)
		_add_poison(target, int(status._poisonPerStack) * int(unit.ability_progress.get("stone_skin", 0)), unit)
		_land(target, damage, unit)


func _release_skorn_action(unit: GuildrunBoardUnit) -> void:
	if unit.cast_hit_index == 0:
		var data: Dictionary = unit.ability_data.taunt
		var per_stall := int(data._baseShieldPerStall) + ((int(unit.stat("Defense")) * int(data._shieldDefensePercent.RawValue)) >> 16)
		per_stall += (int(unit.stat("Magic")) * int(data._shieldMagicPercent.RawValue)) >> 16
		unit.gain_shield(unit.rank * int(data._shieldsPerRank) + per_stall * total_stall_triggers, int(data._duration.RawValue))
		for enemy in _units:
			if enemy.is_hero != unit.is_hero and not enemy.defeated:
				enemy.current_target = unit
		unit.cast_hit_index = 1
		unit.cast_release_q16 = int(unit.ability_data.strike._delay.RawValue)
	else:
		var damage := (unit.total_shield() * int(unit.ability_data.strike._shieldPercentDamage.RawValue)) >> 16
		for enemy in _units:
			if enemy.is_hero != unit.is_hero and not enemy.defeated and enemy.current_target == unit and damage > 0:
				_land_critable(enemy, damage, unit)


func _queue_permafrost_attacks(source: GuildrunBoardUnit, primary: GuildrunBoardUnit, speed: int) -> void:
	var candidates: Array[GuildrunBoardUnit] = []
	for enemy in _units:
		if enemy != primary and enemy.is_hero != source.is_hero and enemy.targetable():
			candidates.append(enemy)
	candidates.sort_custom(func(a: GuildrunBoardUnit, b: GuildrunBoardUnit):
		return GuildrunBattleGrid.distance(primary.grid_cell, a.grid_cell) < GuildrunBattleGrid.distance(primary.grid_cell, b.grid_cell))
	for i in mini(source.permafrost_targets, candidates.size()):
		var damage := source.effective_attack_damage() >> 1
		_queue_shot(source, candidates[i], damage, speed, "attack_hit")


func _release_wheel_and_deal(unit: GuildrunBoardUnit) -> void:
	var target := unit.cast_target
	if not is_instance_valid(target) or not target.targetable():
		target = _nearest_enemy(unit)
	if not target:
		return
	var data := unit.ability_data
	_land_critable(target, _ability_attack_damage(unit, data._attacks._attacks[0]), unit)
	target.stun_remaining_q16 = maxi(target.stun_remaining_q16, int(data._baseStunDuration) << 16)
	unit.ability_progress.casts = int(unit.ability_progress.get("casts", 0)) + 1
	if int(unit.ability_progress.casts) % int(data._castInterval) == 0:
		_create_rank_item(unit)


func _create_rank_item(unit: GuildrunBoardUnit) -> void:
	var index := unit.rank - 2
	if not first_shop or index < 0 or index >= _stage.ability_item_pools.size():
		return
	var pool: int = _stage.ability_item_pools[index]
	# CreateItemAction samples the entire authored pool during battle.
	var item: int = load("res://battle/opening_draft.gd").pick_reward("Item", pool, 2147483647, _rng)
	if item >= 0:
		_gained_items.append(item)
		unit.ability_progress.items = int(unit.ability_progress.get("items", 0)) + 1


func _release_blessing(unit: GuildrunBoardUnit) -> void:
	var data := unit.ability_data
	var lowest: GuildrunBoardUnit
	var fallen: GuildrunBoardUnit
	for ally in _units:
		if ally.is_hero != unit.is_hero:
			continue
		if ally.defeated:
			if fallen == null or ally.rank > fallen.rank:
				fallen = ally
		elif lowest == null or ally.health * lowest.max_health < lowest.health * ally.max_health:
			lowest = ally
	var amount := _scaled_amount(unit, int(data._baseShieldAmount), data._shieldScalings)
	var target := lowest
	if fallen != null and _keyword_clocks.stall_elapsed(unit, battle_time_q16) >= int(data.stall_duration):
		var cell := fallen.grid_cell
		if _grid.occupants.has(cell):
			var nearest := 2147483647
			for y in _grid.size.y:
				for x in _grid.size.x:
					var candidate := Vector2i(x, y)
					var distance := GuildrunBattleGrid.distance(fallen.grid_cell, candidate)
					if not _grid.occupants.has(candidate) and distance < nearest:
						nearest = distance
						cell = candidate
		if not _grid.occupants.has(cell):
			fallen.grid_cell = cell
			fallen.set_meta("grid_cell", cell)
			_grid.occupants[cell] = fallen
			fallen.position = GuildrunBattleGrid.center(cell)
			fallen.resurrect(amount)
			target = fallen
	if target == null:
		return
	var duration := (int(data._shieldBaseDuration) << 16) + int(unit.stat("ManaRegen")) * int(data._mrShieldDurationPercent.RawValue)
	target.gain_shield(amount, duration, unit)
	if target == lowest:
		target.heal((amount * int(data._healPercent.RawValue)) >> 16, unit)


func _release_enemy_attack(unit: GuildrunBoardUnit) -> void:
	var targets: Array[GuildrunBoardUnit] = []
	var chooses_random_target := unit.ability_kind == "SnipeAbilityAction"
	for candidate in _units:
		if candidate.is_hero != unit.is_hero and not candidate.defeated:
			if chooses_random_target or candidate.targetable():
				targets.append(candidate)
	if targets.is_empty():
		return
	var damage := _ability_attack_damage(unit, unit.ability_data._attacks._attacks[0])
	match unit.ability_kind:
		"SnipeAbilityAction":
			var target := targets[_combat_rng.next_index(targets.size())]
			_queue_shot(unit, target, damage, int(unit.ability_data._projectileSpeed.RawValue))
		"SkeletonSmashAction":
			for target in targets:
				if GuildrunBattleGrid.distance(unit.grid_cell, target.grid_cell) == 1:
					_land_critable(target, damage, unit)
					target.stun_remaining_q16 = maxi(target.stun_remaining_q16, int(unit.ability_data._baseStunDuration) << 16)
		"MeleeAbilityAction", "slime_strike", "lizard_strike", "hook_strike":
			var nearest := targets[0]
			for target in targets:
				if GuildrunBattleGrid.distance(unit.grid_cell, target.grid_cell) < GuildrunBattleGrid.distance(unit.grid_cell, nearest.grid_cell):
					nearest = target
			_land_critable(nearest, damage, unit)


func _lowest_health_enemy(source: GuildrunBoardUnit) -> GuildrunBoardUnit:
	var target: GuildrunBoardUnit
	for candidate in _units:
		if candidate.is_hero != source.is_hero and candidate.targetable():
			if target == null or candidate.health < target.health:
				target = candidate
	return target


func _farthest_enemy(source: GuildrunBoardUnit) -> GuildrunBoardUnit:
	var target: GuildrunBoardUnit
	var farthest := -1
	for other in _units:
		if other.is_hero == source.is_hero or not other.targetable():
			continue
		var distance := GuildrunBattleGrid.distance(source.grid_cell, other.grid_cell)
		if distance > farthest:
			farthest = distance
			target = other
	return target


func _begin_hook(source: GuildrunBoardUnit) -> int:
	var target := _farthest_enemy(source)
	if not target:
		return 0
	var cell := _grid.best_front_cell(source.grid_cell, target.grid_cell)
	if _grid.occupants.has(cell):
		return 0
	var dest := GuildrunBattleGrid.center(cell)
	var travel := maxi(1, roundi(target.position.distance_to(dest) * 65536.0 * 65536.0 / float(source.ability_data.drag_speed)))
	_claim_cell(target, cell)
	target.moving = false
	target.stun_remaining_q16 = maxi(target.stun_remaining_q16, travel)
	_drags.append({"target": target, "start": target.position, "end": dest, "elapsed": 0, "duration": travel})
	return travel


func _advance_drags(dt: int) -> void:
	for i in range(_drags.size() - 1, -1, -1):
		var drag := _drags[i]
		var target: GuildrunBoardUnit = drag.target
		drag.elapsed = mini(int(drag.elapsed) + dt, int(drag.duration))
		if not target.defeated:
			target.position = (drag.start as Vector3).lerp(drag.end, float(drag.elapsed) / int(drag.duration))
		if target.defeated or drag.elapsed == drag.duration:
			_drags.remove_at(i)


@warning_ignore("integer_division")
func _tick_shadow_strike(unit: GuildrunBoardUnit, dt: int) -> void:
	var actions := unit.ability_data
	var volley: Dictionary = actions.AyakaDamageAction
	var attack: Dictionary = volley._attacks._attacks[0]
	unit.cast_release_q16 = maxi(0, unit.cast_release_q16 - dt)
	match unit.shadow_step:
		0:
			if unit.cast_release_q16 == 0:
				unit.shadow_step = 1
				unit.cast_release_q16 = int(attack["<Delay>k__BackingField"].RawValue)
		1:
			if unit.cast_release_q16 == 0:
				var count := int(volley._baseShuriken) + int(unit.stat("Crit")) / int(volley._critThreshold)
				if unit.passive_id() == 10402:
					count += int(volley._killerShurikenBonus)
				var damage := _ability_attack_damage(unit, attack)
				for i in mini(count, int(volley._maxShurikens)):
					var enemy := _lowest_health_enemy(unit)
					if enemy != null:
						var bonus := 150 if unit.passive_id() == 10403 and enemy.poison_stacks > 0 else 0
						_land_critable(enemy, damage, unit, bonus)
				unit.mana = 0
				unit.set_meta("mana", 0)
				_notify_cast_effect(unit)
				unit.shadow_step = 2
		2:
			unit.shadow_target = _lowest_health_enemy(unit)
			if unit.shadow_target == null:
				_finish_shadow_strike(unit)
				return
			unit.face_point(unit.shadow_target.position)
			unit.shadow_step = 3
			unit.cast_release_q16 = int(actions.VisuallyMoveToTargetAbilityAction._movementDuration.RawValue)
		3:
			var duration := int(actions.VisuallyMoveToTargetAbilityAction._movementDuration.RawValue)
			var fraction := 1.0 - float(unit.cast_release_q16) / duration
			unit.set_visual_offset((unit.shadow_target.position - unit.position) * fraction)
			if unit.cast_release_q16 == 0:
				var target := _lowest_health_enemy(unit)
				if target == null:
					_finish_shadow_strike(unit)
					return
				unit.shadow_target = target
				unit.shadow_landing = _grid.best_behind_cell(target, unit)
				unit.shadow_start_offset = unit.visual_offset
				unit.shadow_step = 4
				unit.cast_release_q16 = int(actions.AyakaMoveBehindTargetAbilityAction._movementDuration.RawValue)
		4:
			var duration := int(actions.AyakaMoveBehindTargetAbilityAction._movementDuration.RawValue)
			var fraction := 1.0 - float(unit.cast_release_q16) / duration
			var destination := GuildrunBattleGrid.center(unit.shadow_landing)
			unit.set_visual_offset(unit.shadow_start_offset.lerp(destination - unit.position, fraction))
			if unit.cast_release_q16 == 0:
				if not _grid.occupants.has(unit.shadow_landing) or _grid.occupants[unit.shadow_landing] == unit:
					_claim_cell(unit, unit.shadow_landing)
					unit.position = destination
				_finish_shadow_strike(unit, true)


func _finish_shadow_strike(unit: GuildrunBoardUnit, completed := false) -> void:
	unit.set_visual_offset(Vector3.ZERO)
	unit.shadow_target = null
	unit.shadow_step = -1
	unit.cast_release_q16 = -1
	unit.cast_remaining_q16 = 0
	unit.mana_lock_q16 = int(unit.stat("ManaLockTime").RawValue)
	if completed:
		unit.finish_action_motion(&"SkillAttack")
	else:
		unit.play_idle()


func _land_critable(target: GuildrunBoardUnit, damage: int, source: GuildrunBoardUnit, bonus_crit := 0) -> void:
	if not target.defeated:
		_stage.sound.play_character(source.base_stats, source.is_hero, "skill_hit", target.global_position)
	var critical := _is_critical(source, bonus_crit)
	_land(target, _critical_damage(source, damage, bonus_crit) if critical else damage, source, critical)


func _seed_combat() -> void:
	var route: Dictionary = _stage._current_route_stage()
	var floor_index := int(_stage.endless_floor)
	if floor_index < 0:
		floor_index = int(_stage.field(route, "FloorNumber"))
	var shards := first_shop.shards if first_shop != null else int(load("res://battle/opening_draft.gd").data().starting_shards)
	var rerolls := first_shop.successful_shop_rerolls if first_shop != null else 0
	var run_seed := _rng.seed if _stage.run_seed == null else int(_stage.run_seed)
	combat_seed = _combat_rng.battle_seed(run_seed, shards, rerolls, floor_index)
	_combat_rng.reseed(combat_seed)


@warning_ignore("integer_division")
func _is_critical(source: GuildrunBoardUnit, bonus := 0) -> bool:
	var chance_q16 := (int(source.stat("Crit")) + bonus) * 65536 / 100
	return _combat_rng.next_q16() < chance_q16


func _critical_damage(source: GuildrunBoardUnit, damage: int, bonus := 0) -> int:
	return (damage * GuildrunCombatMath.critical_multiplier((int(source.stat("Crit")) + bonus) << 16)) >> 16


func _advance_strike_areas(dt: int) -> void:
	for i in range(_strike_areas.size() - 1, -1, -1):
		var area := _strike_areas[i]
		var source: GuildrunBoardUnit = area.source
		area.until_hit -= mini(dt, int(area.remaining))
		area.remaining -= dt
		while area.until_hit <= 0:
			if area.has("pulse"):
				_apply_area_pulse(source, area.transform, area.shapes, area.pulse)
			elif area.has("transform"):
				_apply_recruit_area(source, area.transform)
			else:
				_apply_resolute_strike(source, area.position)
			area.until_hit += int(source.ability_data.interval)
		if area.remaining <= 0:
			_strike_areas.remove_at(i)


func _track_execution(unit: GuildrunBoardUnit, dealt: int) -> void:
	var tier := int(unit.ability_progress.get("tier", 0))
	if tier >= 3:
		return
	var total := int(unit.ability_progress.get("damage", 0)) + dealt
	unit.ability_progress.damage = total
	if total < [2500, 20000, 40000][tier]:
		return
	unit.ability_progress.tier = tier + 1
	if tier == 0:
		unit.permanent_stats.Attack = int(unit.permanent_stats.get("Attack", 0)) + 50
	elif tier == 1:
		unit.permanent_stats.Crit = int(unit.permanent_stats.get("Crit", 0)) + 30
		unit.permanent_stats.OmniVamp = int(unit.permanent_stats.get("OmniVamp", 0)) + 10


func _start_recruit_area(unit: GuildrunBoardUnit) -> void:
	var basis := unit.transform
	if unit.ability_data.has("area_pulse"):
		_start_area_pulse(unit)
		return
	if unit.ability_kind == "AreaOfEffectAction" and int(unit.ability_data.AoePlacementStrategyType) == 1:
		var target := unit.cast_target if is_instance_valid(unit.cast_target) and unit.cast_target.targetable() else _nearest_enemy(unit)
		if not target:
			return
		basis.origin = target.position
	_strike_areas.append({"source": unit, "transform": basis.affine_inverse(),
			"remaining": int(unit.ability_data._duration.RawValue), "until_hit": int(unit.ability_data.interval)})


func _start_area_pulse(unit: GuildrunBoardUnit) -> void:
	var data := unit.ability_data
	var shapes := unit.area_shapes
	var effects: Array = data.area_pulse
	if not data.stall_pulse.is_empty() and _keyword_clocks.stall_elapsed(unit, battle_time_q16) >= int(data.stall_since):
		effects = data.stall_pulse
		if data.has("_stallAoeEntry"):
			shapes = _stage._aoe_shapes[int(data._stallAoeEntry.m_PathID)]
	var basis := unit.transform
	if unit.ability_kind != "PimentaAbilityAction":
		var target := unit.cast_target if is_instance_valid(unit.cast_target) and unit.cast_target.targetable() else _nearest_enemy(unit)
		if not target:
			return
		basis.origin = _area_ability_effects.auto_position(unit, target, _units, float(shapes[0].radius))
	_strike_areas.append({"source": unit, "transform": basis.affine_inverse(), "shapes": shapes, "pulse": effects,
			"remaining": int(data._duration.RawValue), "until_hit": int(data.interval)})


@warning_ignore("integer_division")
func _apply_area_pulse(source: GuildrunBoardUnit, world_to_area: Transform3D, shapes: Array, pulse: Array) -> void:
	for effect: Dictionary in pulse:
		for target in _units:
			if target.defeated or (target.is_hero == source.is_hero) != (int(effect.team) == 2):
				continue
			var point := world_to_area * target.position
			var radius := float(target.stat("CircleCollisorRadius").RawValue) / 65536.0
			if not _overlaps_area(shapes, Vector2(point.x, -point.z), radius):
				continue
			for action: Dictionary in effect.actions:
				var data: Dictionary = action.data
				match action.kind:
					"ApplyStatusFromOwnerStatAction":
						var stat := int(source.stat(GuildrunBoardUnit.STAT_NAMES[int(data.StatType)]))
						var stacks := int(data.Base) + ((stat / int(data.Increment) * int(data.Multiplier.RawValue)) >> 16)
						_add_elemental_status(target, int(data.Status), stacks, source)
					"ApplyStatusFlatFromStatWithBaseAction":
						var stat := int(source.stat(GuildrunBoardUnit.STAT_NAMES[int(data.Stat)]))
						_add_elemental_status(target, int(data.Status), int(data.Base) + stat / int(data.Increment), source)
					"DealCritableDamageWithScalingAction":
						_land_critable(target, _scaled_amount(source, int(data.BaseDamage), data.Scalings), source)
					"ApplyShieldWithScalingAction":
						target.gain_shield(_scaled_amount(source, int(data.BaseShield), data.Scalings), 10 << 16, source)
					"HealWithScalingAction":
						target.heal(_scaled_amount(source, int(data.Base), data.Scalings), source)
					"ModifyOwnerStatPerRankAction":
						var stat: String = GuildrunBoardUnit.STAT_NAMES[int(data.StatType)]
						source.combat_stats[stat] = int(source.combat_stats.get(stat, 0)) + int(data.Value) + source.rank * int(data.PerRank)


@warning_ignore("integer_division")
func _apply_recruit_area(unit: GuildrunBoardUnit, world_to_area: Transform3D) -> void:
	var data := unit.ability_data
	if data.has("self_shield") and not unit.defeated:
		var shield: Dictionary = data.self_shield
		var source_stat := int(unit.stat(GuildrunBoardUnit.STAT_NAMES[int(shield.StatType)]))
		unit.gain_shield((source_stat * int(shield.Percent.RawValue)) >> 16, int(shield.Duration.RawValue))
	var damage := _scaled_amount(unit, int(data.strike.BaseDamage), data.strike.Scalings)
	for target in _units:
		if target.is_hero == unit.is_hero or target.defeated:
			continue
		var point := world_to_area * target.position
		var center := Vector2(point.x, -point.z)
		var radius := float(target.stat("CircleCollisorRadius").RawValue) / 65536.0
		if not _overlaps_area(unit.area_shapes, center, radius):
			continue
		if data.has("percent_status"):
			var status: Dictionary = data.percent_status
			var stat := int(unit.stat(GuildrunBoardUnit.STAT_NAMES[int(status._statType)]))
			_add_elemental_status(target, int(status._status), int(status._base) + ((stat * int(status._percent.RawValue)) >> 16), unit)
		_land_critable(target, damage, unit)
		if target.defeated:
			continue
		if data.has("stun_duration"):
			target.stun_remaining_q16 = maxi(target.stun_remaining_q16, int(data.stun_duration))
		if data.has("flat_status"):
			var status: Dictionary = data.flat_status
			var magnitude := int(unit.stat(GuildrunBoardUnit.STAT_NAMES[int(status.Stat)]))
			if int(status.Status) == 3:
				_add_poison(target, int(status.Base) + magnitude / int(status.Increment), unit)
		for status: Dictionary in data.statuses:
			var magnitude := int(unit.stat(GuildrunBoardUnit.STAT_NAMES[int(status.StatType)]))
			var stacks := int(status.Base) + (((magnitude / int(status.Increment)) * int(status.Multiplier.RawValue)) >> 16)
			if int(status.Status) in [1, 2]:
				_add_elemental_status(target, int(status.Status), stacks, unit)


func _overlaps_area(shapes: Array, center: Vector2, radius: float) -> bool:
	for shape: Dictionary in shapes:
		if shape.has("polygon"):
			var corners: PackedVector2Array = shape.polygon
			if Geometry2D.is_point_in_polygon(center, corners):
				return true
			for i in corners.size():
				var closest := Geometry2D.get_closest_point_to_segment(center, corners[i], corners[(i + 1) % corners.size()])
				if center.distance_squared_to(closest) <= radius * radius:
					return true
		else:
			var reach := radius + float(shape.radius)
			if center.distance_squared_to(shape.center) <= reach * reach:
				return true
	return false


func _set_frost(unit: GuildrunBoardUnit, stacks: int) -> void:
	if not unit.is_hero and first_shop != null:
		first_shop.advance_quest(1020, stacks - unit.frost_stacks)
	unit.frost_stacks = stacks
	var resistance: Variant = unit.stat("FrostResistance")
	var resistance_q16 := int(resistance.RawValue) if resistance is Dictionary else int(resistance) << 16
	for key: String in _stage.frost_reductions:
		var per_stack := (int(_stage.frost_reductions[key]) * (65536 - resistance_q16) + 32768) >> 16
		unit.frost_reductions[key] = (stacks * per_stack) >> 16


func _tick_frost(unit: GuildrunBoardUnit, dt: int) -> void:
	if unit.frost_stacks <= 0:
		return
	unit.frost_remaining_q16 -= dt
	if unit.frost_remaining_q16 <= 0:
		_set_frost(unit, unit.frost_stacks - 1)
		unit.frost_remaining_q16 += _stage.frost_interval_q16


func _apply_resolute_strike(source: GuildrunBoardUnit, center: Vector3) -> void:
	var data := source.ability_data
	var damage := _scaled_amount(source, int(data.strike.BaseDamage), data.strike.Scalings)
	var shield_damage := (source.total_shield() * int(data.shield_factor)) >> 16
	for target in _units:
		if target.defeated or target.is_hero == source.is_hero:
			continue
		var reach := source.strike_radius + float(target.stat("CircleCollisorRadius").RawValue) / 65536.0
		if center.distance_squared_to(target.position) <= reach * reach:
			_land_critable(target, damage, source)
			_land(target, shield_damage, source)


func _tick_burn(unit: GuildrunBoardUnit, dt: int) -> void:
	if unit.burn_stacks == 0:
		return
	unit.burn_remaining_q16 -= dt
	if unit.burn_remaining_q16 <= 0:
		unit.take_damage(unit.burn_stacks * _stage.burn_damage_per_stack, null,
				GuildrunBattleStatistics.Origin.STATUS, 0, 0, GuildrunBattleStatistics.StatusKind.BURN)
		for owner in _units:
			if owner.defeated or owner.is_hero == unit.is_hero or owner.passive_id() != 101401:
				continue
			if GuildrunBattleGrid.distance(owner.grid_cell, unit.grid_cell) <= int(owner.stat("AttackRange")):
				owner.gain_mana(1)
			for mage in _units:
				if mage.is_hero == owner.is_hero and mage.has_class(7) and not mage.defeated and GuildrunBattleGrid.distance(mage.grid_cell, unit.grid_cell) <= int(mage.stat("AttackRange")):
					mage.combat_stats.Magic = int(mage.combat_stats.get("Magic", 0)) + owner.rank
		unit.burn_stacks -= 1
		unit.burn_remaining_q16 += _stage.burn_interval_q16
		if unit.defeated:
			_on_defeated(unit)


func _add_elemental_status(target: GuildrunBoardUnit, kind: int, stacks: int,
		source: GuildrunBoardUnit = null) -> void:
	match kind:
		1:
			if target.burn_stacks == 0:
				target.burn_remaining_q16 = _stage.burn_interval_q16
			target.burn_stacks += stacks
			_record_status_stacks(source, GuildrunBattleStatistics.StatusKind.BURN, stacks)
			if not target.is_hero and first_shop != null:
				first_shop.advance_quest(1021, stacks)
		2:
			if target.frost_stacks == 0:
				target.frost_remaining_q16 = _stage.frost_interval_q16
			_set_frost(target, target.frost_stacks + stacks)
		3:
			_add_poison(target, stacks, source)


@warning_ignore("integer_division")
func _resolve_auto_hit(target: GuildrunBoardUnit, damage: int, source: GuildrunBoardUnit) -> void:
	# The native damage handler rolls crit on contact, using the attacker's current stats.
	var critical := _is_critical(source)
	_land_auto(target, _critical_damage(source, damage) if critical else damage, source, critical)


func _land_auto(target: GuildrunBoardUnit, damage: int, source: GuildrunBoardUnit, critical: bool) -> void:
	if target.defeated:
		return
	var spiked := target.earned_rank_modifiers.values().has(97)
	_land(target, damage, source, critical, GuildrunBattleStatistics.Origin.ATTACK, spiked)
	_apply_rank_attack_effects(source, target, spiked)
	# The triggering hit's receiver can still react before native death cleanup.
	if spiked:
		var attacker_was_alive := not source.defeated
		_land_adjacent_rank_damage(target, int(target.stat("Defense")) >> 1, target.defeated)
		if target.defeated:
			_settle_attack_defeat(target, source, attacker_was_alive and source.defeated)
	if source.permafrost_targets > 0 and not target.defeated:
		_add_elemental_status(target, 2, source.permafrost_frost)
		if source.passive_id() == 102303:
			_land_critable(target, source.permafrost_damage, source)
		else:
			_land(target, source.permafrost_damage, source)
	if not target.defeated and DRAGON_ATTACK_STATUS.has(source.passive_id()):
		var status: Dictionary = DRAGON_ATTACK_STATUS[source.passive_id()]
		var stacks := int(status.base) + int(source.stat("Magic")) / int(status.magic_per_stack)
		_add_elemental_status(target, int(status.kind), stacks, source)


func _apply_rank_attack_effects(source: GuildrunBoardUnit, target: GuildrunBoardUnit, defer_defeat: bool) -> void:
	if target.trial_damage_immune or source.earned_rank_modifiers.is_empty():
		return
	var rank_attack_status := load("res://battle/rank_attack_status.gd")
	var attack_speed := int(source.stat("AttackSpeed"))
	for modifier: int in source.earned_rank_modifiers.values():
		if target.defeated:
			break
		if modifier == 274:
			if not source.defeated:
				_land_rank_effect(target, int(source.stat("Magic")), source, defer_defeat)
		else:
			var status: Vector2i = rank_attack_status.attack_status_amount(modifier, attack_speed)
			if status.y > 0:
				_add_elemental_status(target, status.x, status.y, source)


func _tick_rank_auras(dt: int) -> void:
	for owner: GuildrunBoardUnit in _rank_aura_timers.keys():
		if not is_instance_valid(owner) or owner.defeated:
			_rank_aura_timers.erase(owner)
			continue
		var remaining := _rank_aura_timers[owner] - dt
		if remaining > 0:
			_rank_aura_timers[owner] = remaining
			continue
		_rank_aura_timers[owner] = remaining + RANK_AURA_INTERVAL_Q16
		var damage := (int(owner.stat("MaxHealth")) * RANK_AURA_DAMAGE_Q16) >> 16
		_land_adjacent_rank_damage(owner, damage)


func _tick_rank_vindictive_shields() -> void:
	for owner in _rank_vindictive_pending.duplicate():
		if owner.defeated:
			_rank_vindictive_pending.erase(owner)
			continue
		var maximum := int(owner.stat("MaxHealth"))
		if owner.health * 2 > maximum:
			continue
		_rank_vindictive_pending.erase(owner)
		var amount := maximum >> 1
		owner.gain_shield(amount, VINDICTIVE_SHIELD_DURATION_Q16)
		_land_adjacent_rank_damage(owner, amount)


func _land_adjacent_rank_damage(owner: GuildrunBoardUnit, damage: int, simultaneous_defeat := false) -> void:
	for target in _units:
		if target.is_hero != owner.is_hero and not target.defeated and GuildrunBattleGrid.distance(owner.grid_cell, target.grid_cell) == 1:
			_land_rank_effect(target, damage, owner, false, simultaneous_defeat)


func _land_rank_effect(target: GuildrunBoardUnit, damage: int, source: GuildrunBoardUnit, defer_defeat := false,
		simultaneous_defeat := false) -> void:
	if damage > 0:
		_land(target, damage, source, false, GuildrunBattleStatistics.Origin.OTHER, defer_defeat, simultaneous_defeat)


func _add_poison(target: GuildrunBoardUnit, stacks: int, source: GuildrunBoardUnit = null) -> void:
	if stacks <= 0:
		return
	if target.poison_stacks == 0:
		target.poison_remaining_q16 = _stage.poison_interval_q16
	target.poison_stacks += stacks
	_record_status_stacks(source, GuildrunBattleStatistics.StatusKind.POISON, stacks)
	if not target.is_hero and first_shop != null:
		first_shop.advance_quest(1018, stacks)


func _record_status_stacks(source: GuildrunBoardUnit, kind: GuildrunBattleStatistics.StatusKind,
		stacks: int) -> void:
	if source != null and source.battle_statistics != null:
		source.battle_statistics.record_status_applied(source.get_instance_id(), kind, stacks)


func _tick_poison(unit: GuildrunBoardUnit, dt: int) -> void:
	if unit.poison_stacks == 0 or unit.defeated:
		return
	unit.poison_remaining_q16 -= dt
	if unit.poison_remaining_q16 <= 0:
		unit.take_damage(unit.poison_stacks * _stage.poison_damage_per_stack, null,
				GuildrunBattleStatistics.Origin.STATUS, 0, 0, GuildrunBattleStatistics.StatusKind.POISON)
		unit.poison_remaining_q16 += _stage.poison_interval_q16
		if unit.defeated:
			_on_defeated(unit)


func _notify_cast_effect(unit: GuildrunBoardUnit) -> void:
	if unit.cast_effect_fired:
		return
	unit.cast_effect_fired = true
	_record_rank_credit(&"cast", unit)


func combat_shard_balance() -> int:
	return _rank_wallet.balance(first_shop)


func _record_rank_credit(event: StringName, source: GuildrunBoardUnit, simultaneous_defeat := false) -> void:
	if not first_shop:
		return
	var gained: int = _rank_wallet.notify(event, source, simultaneous_defeat)
	if gained > 0:
		_rank_wallet.record_quest(first_shop, gained)


func _on_defeated(unit: GuildrunBoardUnit) -> void:
	_deaths_this_step[unit] = true
	_grid.occupants.erase(unit.grid_cell)
	_stage.sound.play_character(unit.base_stats, unit.is_hero, "death", unit.global_position)
	_stage.sound.play_character(unit.base_stats, unit.is_hero, "death_vo", unit.global_position)


func _critical_effects(source: GuildrunBoardUnit, target: GuildrunBoardUnit) -> void:
	if source.passive_id() == 10501:
		@warning_ignore("integer_division")
		var limit := 2 + int(source.stat("Crit")) / 20 + int(source.stat("Defense")) / 60
		if source.stone_skin_triggers < limit:
			source.stone_skin_triggers += 1
			source.ability_progress.stone_skin = int(source.ability_progress.get("stone_skin", 0)) + 1
			for stat: String in ["Defense", "Magic"]:
				source.permanent_stats[stat] = int(source.permanent_stats.get(stat, 0)) + 1
	if source.passive_id() == 102603 and _keyword_clocks.rush_active(source, battle_time_q16, 6 << 16):
		source.permanent_stats.Attack = int(source.permanent_stats.get("Attack", 0)) + source.rank
		source.gain_shield(100 + 2 * int(source.stat("Attack")), 999 << 16)
	if target.defeated:
		return
	for owner in _units:
		if owner.is_hero != source.is_hero:
			continue
		match owner.passive_id():
			10403:
				if source.has_class(4):
					if target.poison_stacks == 0:
						target.poison_remaining_q16 = _stage.poison_interval_q16
					var stacks := 4 * owner.rank
					target.poison_stacks += stacks
					_record_status_stacks(owner, GuildrunBattleStatistics.StatusKind.POISON, stacks)
			102603:
				if source.has_class(1):
					target.combat_stats.Defense = int(target.combat_stats.get("Defense", 0)) - (owner.rank + 1)


@warning_ignore("integer_division")
func _land(target: GuildrunBoardUnit, damage: int, source: GuildrunBoardUnit = null, critical := false,
		origin := GuildrunBattleStatistics.Origin.ABILITY, defer_defeat := false, simultaneous_defeat := false) -> int:
	if target.defeated or target.trial_damage_immune:
		return 0
	var after_defense := target.damage_after_defense(damage)
	var unshielded := maxi(0, after_defense - target.total_shield())
	target.take_damage(after_defense, source, origin, maxi(0, damage - after_defense), 0,
			GuildrunBattleStatistics.StatusKind.NONE, critical)
	if source:
		source.heal(after_defense * int(source.stat("OmniVamp")) / 100)
		_rank_rush.damage_dealt(source, unshielded)
		if critical:
			if source.is_hero and first_shop != null:
				first_shop.advance_quest(1025, 1)
			_critical_effects(source, target)
			_record_rank_credit(&"critical", source)
	if target.defeated and not defer_defeat:
		_settle_attack_defeat(target, source, simultaneous_defeat)
	return unshielded


func _settle_attack_defeat(target: GuildrunBoardUnit, source: GuildrunBoardUnit, simultaneous_defeat := false) -> void:
	_on_defeated(target)
	_record_rank_credit(&"kill", source, simultaneous_defeat)
	if source and source.earned_rank_modifiers.values().has(238):
		source.gain_stealth(5 << 16)
	if source and source.passive_id() == 10402 and not source.bounty_claimed and first_shop != null:
		var reward := int(source.ability_progress.get("bounty", 5))
		first_shop.shards += reward
		first_shop.advance_quest(1022, reward)
		source.ability_progress.bounty = reward + 1
		source.bounty_claimed = true
