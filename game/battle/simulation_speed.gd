extends RefCounted

signal speed_changed(index: int, multiplier: float, automatic: bool)

const SETTINGS_SECTION := "simulation_speed"

var _multipliers: PackedFloat64Array
var _fast_after_seconds: float
var _settings_path: String
var _manual_index := 1
var _index := 1
var _automatic := true
var _tick_progress := 0.0


func _init(
	multipliers := PackedFloat64Array([1.0, 1.6, 2.5]),
	fast_after_seconds := 20.0,
	settings_path := ""
) -> void:
	assert(multipliers.size() == 3)
	assert(multipliers[0] > 0.0 and multipliers[1] >= multipliers[0])
	assert(multipliers[2] >= multipliers[1] and fast_after_seconds >= 0.0)
	_multipliers = multipliers
	_fast_after_seconds = fast_after_seconds
	_settings_path = settings_path


func speed_index() -> int:
	return _index


func multiplier() -> float:
	return _multipliers[_index]


func is_automatic() -> bool:
	return _automatic


func select_manual(index: int) -> Error:
	_manual_index = clampi(index, 0, _multipliers.size() - 1)
	_set_speed(_manual_index, false)
	return save_settings()


func set_automatic(enabled: bool) -> Error:
	_set_speed(0 if enabled else _index, enabled)
	return save_settings()


func begin_simulation() -> void:
	_tick_progress = 0.0
	if _automatic:
		_set_speed(0, true)


func observe_simulation_time(elapsed_seconds: float) -> void:
	if _automatic and elapsed_seconds >= 0.0:
		var target := 2 if elapsed_seconds >= _fast_after_seconds else 1
		if target > _index:
			_set_speed(target, true)


# The callback advances one fixed tick and returns whether the simulation is still running.
# The callback owns the simulation clock and can publish it with observe_simulation_time().
func advance_real_time(real_seconds: float, step_seconds: float, step: Callable) -> int:
	assert(step_seconds > 0.0 and step.is_valid())
	var remaining := maxf(real_seconds, 0.0)
	var ticks := 0
	while remaining > 0.0:
		var active_multiplier := multiplier()
		var time_to_tick := (1.0 - _tick_progress) * step_seconds / active_multiplier
		if remaining + 1e-10 < time_to_tick:
			_tick_progress += remaining / step_seconds * active_multiplier
			break
		remaining = maxf(remaining - time_to_tick, 0.0)
		_tick_progress = 0.0
		ticks += 1
		if not bool(step.call(step_seconds)):
			break
	return ticks


func load_settings() -> Error:
	if _settings_path.is_empty():
		return OK
	var settings := ConfigFile.new()
	var error := settings.load(_settings_path)
	if error != OK:
		return OK if error == ERR_FILE_NOT_FOUND else error
	var saved_index: Variant = settings.get_value(SETTINGS_SECTION, "manual_index", 1)
	var saved_auto: Variant = settings.get_value(SETTINGS_SECTION, "automatic", true)
	if typeof(saved_index) != TYPE_INT or typeof(saved_auto) != TYPE_BOOL:
		return ERR_INVALID_DATA
	_manual_index = clampi(saved_index, 0, _multipliers.size() - 1)
	_set_speed(0 if saved_auto else _manual_index, saved_auto)
	return OK


func save_settings() -> Error:
	if _settings_path.is_empty():
		return OK
	var settings := ConfigFile.new()
	var error := settings.load(_settings_path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	settings.set_value(SETTINGS_SECTION, "manual_index", _manual_index)
	settings.set_value(SETTINGS_SECTION, "automatic", _automatic)
	return settings.save(_settings_path)


func _set_speed(index: int, automatic: bool) -> void:
	if _index == index and _automatic == automatic:
		return
	_index = index
	_automatic = automatic
	speed_changed.emit(_index, multiplier(), _automatic)
