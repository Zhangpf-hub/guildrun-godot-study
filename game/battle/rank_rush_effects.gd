extends RefCounted

var _windows: Array[Dictionary] = []
var _encounter: GuildrunEncounter


func begin(encounter: GuildrunEncounter, clocks: Array[Dictionary]) -> void:
	for window in _windows:
		_remove_grants(window)
	_windows.clear()
	_encounter = encounter
	for clock in clocks:
		if int(clock.keyword) == 1 and clock.has("rule"):
			var window := {"clock": clock, "active": false, "grants": []}
			_windows.append(window)
			if int(clock.rule.trigger) != 2:
				_activate(window)


func advance() -> void:
	for i in range(_windows.size() - 1, -1, -1):
		var window: Dictionary = _windows[i]
		var clock: Dictionary = window.clock
		var owner: GuildrunBoardUnit = clock.owner
		if clock.get("expired", false):
			_remove_grants(window)
			_windows.remove_at(i)
		elif owner != null and owner.defeated:
			_remove_grants(window)
		elif not window.active:
			_activate(window)


func _activate(window: Dictionary) -> void:
	var clock: Dictionary = window.clock
	var rule: Dictionary = clock.rule
	var action: Dictionary = rule.action
	window.active = true
	if action.kind == "damage_shield":
		return
	var delta: int = int(action.value_q16)
	if action.kind == "wallet_stat":
		var balance := _encounter.combat_shard_balance() if _encounter.first_shop else 0
		@warning_ignore("integer_division")
		var steps := (balance << 16) / int(action.interval_q16)
		delta = (delta * steps) >> 16
	var stat: String = GuildrunBoardUnit.STAT_NAMES[int(action.stat)]
	for target in _encounter._units:
		if not target.is_hero or target.defeated:
			continue
		if int(rule.target) == 1 and target != clock.owner:
			continue
		if int(rule.target) == 5 and not target.has_class(int(rule.target_class)):
			continue
		_change(target, stat, delta, action.kind == "percent")
		window.grants.append({"target": target, "stat": stat, "delta": delta, "percent": action.kind == "percent"})


func _remove_grants(window: Dictionary) -> void:
	for grant: Dictionary in window.grants:
		if is_instance_valid(grant.target):
			_change(grant.target, grant.stat, -int(grant.delta), grant.percent)
	window.grants.clear()
	window.active = false


func _change(target: GuildrunBoardUnit, stat: String, delta: int, percent: bool) -> void:
	if percent:
		target.modify_stat_percent(stat, delta)
	else:
		target.combat_stats[stat] = int(target.combat_stats.get(stat, 0)) + delta


func damage_dealt(source: GuildrunBoardUnit, hp_damage: int) -> void:
	if hp_damage <= 0 or source.defeated:
		return
	for window in _windows:
		var clock: Dictionary = window.clock
		if not window.active or clock.owner != source:
			continue
		var action: Dictionary = clock.rule.action
		if action.kind == "damage_shield":
			source.gain_shield((hp_damage * int(action.ratio_q16)) >> 16, int(action.duration_q16), source)
