extends RefCounted

signal text_shown(display: int, key: String, timed: bool)
signal text_hidden(display: int)
signal timer_progress(display: int, fraction: float)
signal input_lock_changed(locked: bool)
signal simulation_pause_changed(paused: bool)
signal grid_visibility_changed(visible: bool)
signal reference_visibility_changed(reference: int, visible: bool)
signal reference_reparent_requested(reference: int, parent_reference: int, all_matches: bool)
signal source_objects_hidden(objects: Array)
signal step_finished(trigger: int)

enum Trigger { RUN_STARTED, PLACEMENT_STARTED, RESOLUTION_STARTED, HERO_MANA_IS_FULL, RESULT_SCREEN_SHOWN, SHOP_SHOWN }
enum BattleFlow { INITIAL_SELECTION, INTRO, PLACEMENT, RESOLUTION, RESULT, SHOP }

var input_locked := false
var simulation_paused := false

var _steps: Dictionary
var _pending: Dictionary = {}
var _next_step := Trigger.RUN_STARTED
var _active_step := -1
var _actions: Array = []
var _index := 0
var _action: Dictionary = {}
var _elapsed := 0.0
var _active_displays: Dictionary = {}
var _flow := BattleFlow.INITIAL_SELECTION
var _comics_finished := false
var _hero_picked := false
var _grid_visible := false


func setup(data: Dictionary) -> void:
	_steps = data.steps


func current_positioning() -> Dictionary:
	return _action.get("positioning", {}).duplicate(true)


func can_pick_hero() -> bool:
	return _action.get("kind") == "WaitForHeroPickElement"


func can_start_fight() -> bool:
	return _action.get("kind") == "WaitForBattleFlowStateElement"


func can_open_shop() -> bool:
	if _active_step == Trigger.RESULT_SCREEN_SHOWN:
		return false
	return not _pending.has(Trigger.RESULT_SCREEN_SHOWN) or (
			_next_step < Trigger.RESULT_SCREEN_SHOWN and not _pending.has(Trigger.HERO_MANA_IS_FULL))

func notify_event(trigger: Trigger) -> void:
	if trigger >= _next_step and _steps.has(str(trigger)):
		_pending[trigger] = true
		_pump()


func notify_comics_finished() -> void:
	_comics_finished = true
	_pump()


func notify_hero_picked() -> void:
	_hero_picked = true
	_pump()


func notify_battle_flow(state: BattleFlow) -> void:
	_flow = state
	match state:
		BattleFlow.PLACEMENT:
			notify_event(Trigger.PLACEMENT_STARTED)
		BattleFlow.RESOLUTION:
			notify_event(Trigger.RESOLUTION_STARTED)
		BattleFlow.RESULT:
			notify_event(Trigger.RESULT_SCREEN_SHOWN)
		BattleFlow.SHOP:
			if _next_step < Trigger.SHOP_SHOWN:
				abort()
				_next_step = Trigger.SHOP_SHOWN
			notify_event(Trigger.SHOP_SHOWN)
	_pump()


func advance_time(delta: float) -> void:
	var remaining := maxf(0.0, delta)
	while not _action.is_empty():
		var duration := _duration()
		if duration < 0.0:
			return
		var spent := minf(remaining, duration - _elapsed)
		_elapsed += spent
		remaining -= spent
		if _action.kind == "TimedInfoFlowElement":
			timer_progress.emit(int(_action.display), 1.0 if duration <= 0.0 else _elapsed / duration)
		if _elapsed < duration:
			return
		_pump()


func consume_mouse_press(button: int) -> bool:
	if _action.get("kind") != "TimedInfoFlowElement" or not bool(_action.skippable):
		return false
	if bool(_action.anyMouseButton):
		if button not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			return false
	elif button != int(_action.specificButton) + 1:
		return false
	_elapsed = _duration()
	_pump()
	return true


func abort() -> void:
	_pending.clear()
	_active_step = -1
	_next_step = Trigger.SHOP_SHOWN + 1
	_action = {}
	_actions = []
	for display in _active_displays.keys():
		_hide(int(display))
	_set_locked(false)
	_set_paused(false)
	_set_grid(false)


func _duration() -> float:
	match _action.kind:
		"DelayElement":
			return float(_action.delaySeconds)
		"TimedInfoFlowElement":
			return float(_action.waitDuration)
	return -1.0


func _pump() -> void:
	while true:
		if _active_step < 0:
			if not _pending.erase(_next_step):
				return
			_active_step = _next_step
			_next_step += 1
			_actions = _steps[str(_active_step)].actions
			_index = 0
		if _action.is_empty():
			if _index >= _actions.size():
				var finished := _active_step
				_active_step = -1
				step_finished.emit(finished)
				continue
			_action = _actions[_index]
			_elapsed = 0.0
			_begin_action()
		if not _action_complete():
			return
		if bool(_action.get("hide", false)):
			_hide(int(_action.display))
		_set_locked(false)
		_action = {}
		_index += 1


func _action_complete() -> bool:
	match _action.kind:
		"WaitForComicsFinishedFlowStateElement":
			return _comics_finished
		"WaitForHeroPickElement":
			return _hero_picked
		"WaitForBattleFlowStateElement":
			return _flow == int(_action.state)
		"DelayElement", "TimedInfoFlowElement":
			return _elapsed >= _duration()
	return true


func _begin_action() -> void:
	_set_locked(bool(_action.lock))
	if _action.has("display"):
		var display := int(_action.display)
		_active_displays[display] = true
		text_shown.emit(display, String(_action.text), _action.kind == "TimedInfoFlowElement")
	match _action.kind:
		"PauseSimulationControlElement":
			_set_paused(bool(_action.setPaused))
		"SetGridVisibleElement":
			_set_grid(bool(_action.visible))
		"SetReferencesObjectActiveElement":
			reference_visibility_changed.emit(int(_action.reference), bool(_action.setActive))
		"ReparentReferenceObjectElement":
			reference_reparent_requested.emit(int(_action.reference), int(_action.targetParentReference), bool(_action.reparentAll))
		"SetGameObjectActiveElement":
			for display in _active_displays.keys():
				_hide(int(display))
			source_objects_hidden.emit(_action.objects.map(func(id): return int(id)))


func _hide(display: int) -> void:
	if _active_displays.erase(display):
		text_hidden.emit(display)


func _set_locked(value: bool) -> void:
	if input_locked != value:
		input_locked = value
		input_lock_changed.emit(value)


func _set_paused(value: bool) -> void:
	if simulation_paused != value:
		simulation_paused = value
		simulation_pause_changed.emit(value)


func _set_grid(value: bool) -> void:
	if _grid_visible != value:
		_grid_visible = value
		grid_visibility_changed.emit(value)


