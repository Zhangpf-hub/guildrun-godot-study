extends RefCounted
## One combat clock per keyword-bearing effect or active ability in build 26551710.

static var _rank_data: Dictionary = {}

var _pending: Array[Dictionary] = []
var _paused_q16: Dictionary[GuildrunBoardUnit, int] = {}
var _rush_bonus_q16 := 0
var _stall_change_q16 := 0


func begin(units: Array[GuildrunBoardUnit], party: GuildrunFirstShop, stage: Node) -> void:
	if _rank_data.is_empty():
		_rank_data = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/rank_keyword_clocks.json"))
	_pending.clear()
	_paused_q16.clear()
	_rush_bonus_q16 = 0
	_stall_change_q16 = 0
	for unit in units:
		if unit.is_hero:
			_paused_q16[unit] = 0
			for modifier: int in unit.earned_rank_modifiers.values():
				_apply_duration_modifier(modifier, false)
	if party:
		for hero in party.reserve_slots:
			if hero >= 0:
				var rank := int(party.hero_ranks.get(hero, 1))
				for modifier: int in GuildrunPartyRankBonuses.earned_modifiers(party, hero, rank):
					_apply_duration_modifier(modifier, true)
	for unit in units:
		if not unit.is_hero:
			continue
		for modifier: int in unit.earned_rank_modifiers.values():
			_add_rank_windows(unit, int(unit.stat("Id")._sequentialId), modifier, false)
		_add(unit, 2, unit.active_stall_q16)
		_add_source("ability", int(unit.base_stats._activeAbilityID), unit, false)
		_add_source("passive", unit.passive_id(), unit, false)
		if party:
			for item: int in party.equipment(int(unit.get_meta("hero_id"))):
				_add_source("item", item, unit, false)
	if party:
		for hero in party.reserve_slots:
			if hero < 0:
				continue
			var rank := int(party.hero_ranks.get(hero, 1))
			for modifier: int in GuildrunPartyRankBonuses.earned_modifiers(party, hero, rank):
				_add_rank_windows(null, hero, modifier, true)
			var passive := int(party.specializations.get(hero, {}).get("passive", -1))
			if passive < 0:
				passive = int(stage._heroes[hero]._passiveAbilityID)
			_add_source("passive", passive, null, true)
		for relic: int in party.relics:
			_add_source("relic", relic, null, false)


func _add_source(origin: String, entry: int, owner: GuildrunBoardUnit, reserve: bool) -> void:
	for rule: Dictionary in _rank_data.sources[origin].get(str(entry), []):
		if bool(rule.reserve) == reserve:
			_add(owner, int(rule.keyword), int(rule.duration_q16), entry if origin == "passive" else -1)


func _apply_duration_modifier(modifier: int, reserve: bool) -> void:
	for rule: Dictionary in _rank_data.duration_modifiers.get(str(modifier), []):
		if bool(rule.reserve) == reserve:
			if int(rule.keyword) == 1:
				_rush_bonus_q16 += int(rule.shift_q16)
			else:
				_stall_change_q16 += int(rule.shift_q16)


func _add_rank_windows(owner: GuildrunBoardUnit, hero: int, modifier: int, reserve: bool) -> void:
	for rule: Dictionary in _rank_data.clocks.get(str(modifier), []):
		if bool(rule.reserve) != reserve:
			continue
		var keyword := int(rule.keyword)
		var shift := _rush_bonus_q16 if keyword == 1 else _stall_change_q16
		_pending.append({"owner": owner, "owner_id": hero, "due": int(rule.duration_q16) + shift,
				"passive": -1, "keyword": keyword, "modifier": modifier, "effect": int(rule.effect), "rule": rule})


func _add(owner: GuildrunBoardUnit, keyword: int, nominal_q16: int, passive := -1) -> void:
	if nominal_q16 > 0:
		var shift := _rush_bonus_q16 if keyword == 1 else _stall_change_q16
		_pending.append({"owner": owner, "due": nominal_q16 + shift, "passive": passive, "keyword": keyword})


func tick(now_q16: int, step_q16: int) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	for owner: GuildrunBoardUnit in _paused_q16:
		if owner.defeated:
			_paused_q16[owner] += step_q16
	for index in range(_pending.size() - 1, -1, -1):
		var clock: Dictionary = _pending[index]
		var owner: GuildrunBoardUnit = clock.owner
		if owner != null and owner.defeated:
			continue
		var elapsed := now_q16 - int(_paused_q16.get(owner, 0))
		if elapsed >= int(clock.due):
			clock["expired"] = true
			due.append(clock)
			_pending.remove_at(index)
	due.reverse()
	return due


func stall_elapsed(owner: GuildrunBoardUnit, now_q16: int) -> int:
	if not owner.is_hero:
		return now_q16
	return now_q16 - int(_paused_q16.get(owner, 0)) - _stall_change_q16


func rush_active(owner: GuildrunBoardUnit, now_q16: int, duration_q16: int) -> bool:
	if not owner.is_hero:
		return now_q16 < duration_q16
	return not owner.defeated and now_q16 - int(_paused_q16.get(owner, 0)) < duration_q16 + _rush_bonus_q16


func rank_rush_windows() -> Array[Dictionary]:
	var windows: Array[Dictionary] = []
	for clock in _pending:
		if int(clock.keyword) == 1 and clock.has("rule"):
			windows.append(clock)
	return windows


func opening_rush_count() -> int:
	var total := 0
	for clock in _pending:
		if int(clock.keyword) == 1:
			total += 1
	return total
