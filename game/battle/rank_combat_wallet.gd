extends RefCounted

const ACTIVE_RULES := {
	12: [&"attack", 9, 1],
	137: [&"cast", 2, 3],
	235: [&"critical", 2, 1],
	236: [&"kill", 1, 8],
}

var _ledger: RefCounted = load("res://battle/combat_credit_ledger.gd").new()
var _reserve_shields: Dictionary[int, int] = {}
var _stall_reserves: Array[int] = []
var _has_stall := false
var _sequence := 0
var _quest_credit := 0
var _had_quest_counter := false
var _active := false
var _preview_delta := 0


func begin(shop: GuildrunFirstShop, units: Array[GuildrunBoardUnit]) -> void:
	var bindings: Array[Dictionary] = []
	_reserve_shields.clear()
	_stall_reserves.clear()
	_has_stall = false
	for unit in units:
		if not unit.is_hero or unit.defeated:
			continue
		var hero := int(unit.stat("Id")._sequentialId)
		for modifier: int in unit.earned_rank_modifiers.values():
			if modifier == 139:
				_add_stall_binding(bindings, hero)
			elif ACTIVE_RULES.has(modifier):
				var spec: Array = ACTIVE_RULES[modifier]
				bindings.append({"owner": hero, "rule": modifier, "event": spec[0],
						"threshold": spec[1], "amount": spec[2], "owner_only": true})
	for owner: int in shop.roster:
		if not shop.reserve_slots.has(owner):
			continue
		var rank := int(shop.hero_ranks.get(owner, 1))
		for modifier: int in GuildrunPartyRankBonuses.earned_modifiers(shop, owner, rank):
			if modifier == 139:
				_stall_reserves.append(owner)
				_add_stall_binding(bindings, owner)
			elif modifier == 138:
				_reserve_shields[owner] = 500 * rank
				bindings.append({"owner": owner, "rule": modifier, "event": &"opening",
						"threshold": 1, "amount": 5, "owner_only": true})
	_ledger.begin(shop.shards, bindings)
	_had_quest_counter = shop.quest_progress.has(1022)
	_quest_credit = 0
	_sequence = 0
	_preview_delta = 0
	_active = not bindings.is_empty()


func _add_stall_binding(bindings: Array[Dictionary], owner: int) -> void:
	_has_stall = true
	bindings.append({"owner": owner, "rule": 139, "event": &"stall", "threshold": 1,
			"amount": 1, "owner_only": true})


func apply_stall(shop: GuildrunFirstShop, units: Array[GuildrunBoardUnit]) -> void:
	if not _active or not _has_stall:
		return
	var gained := 0
	for owner in _stall_reserves:
		gained += _record(&"stall", owner)
	for owner in units:
		if owner.is_hero and not owner.defeated and owner.earned_rank_modifiers.values().has(139):
			gained += _record(&"stall", int(owner.stat("Id")._sequentialId))
	if gained > 0:
		record_quest(shop, gained)
		for target in units:
			if target.is_hero and not target.defeated:
				target.combat_stats.ManaRegen = int(target.combat_stats.get("ManaRegen", 0)) + 3 * gained


func apply_opening(shop: GuildrunFirstShop, units: Array[GuildrunBoardUnit], owner: int) -> void:
	if not _reserve_shields.has(owner):
		return
	var amount := _reserve_shields[owner]
	_reserve_shields.erase(owner)
	for target in units:
		if target.is_hero and not target.defeated:
			target.gain_shield(amount, 10 << 16)
	record_quest(shop, _record(&"opening", owner))


func notify(event: StringName, unit: GuildrunBoardUnit, simultaneous_defeat := false) -> int:
	if not _active or not is_instance_valid(unit) or not unit.is_hero or (unit.defeated and not simultaneous_defeat):
		return 0
	return _record(event, int(unit.stat("Id")._sequentialId))


func _record(event: StringName, hero: int) -> int:
	_sequence += 1
	var gained: int = _ledger.record(_sequence, event, hero)
	_preview_delta += gained
	return gained


func balance(shop: GuildrunFirstShop) -> int:
	return shop.shards + _preview_delta


func tracked(hero: int, modifier: int) -> int:
	return _ledger.tracked(hero, modifier)


func record_quest(shop: GuildrunFirstShop, gained: int) -> void:
	if gained > 0:
		var previous := int(shop.quest_progress.get(1022, 0))
		shop.advance_quest(1022, gained)
		_quest_credit += int(shop.quest_progress.get(1022, 0)) - previous


func settle(shop: GuildrunFirstShop, keep_changes := true) -> void:
	if not _active:
		return
	_active = false
	_preview_delta = 0
	var delta: int = _ledger.take_delta()
	if not keep_changes:
		if _quest_credit > 0:
			var remaining := int(shop.quest_progress.get(1022, 0)) - _quest_credit
			if remaining == 0 and not _had_quest_counter:
				shop.quest_progress.erase(1022)
			else:
				shop.quest_progress[1022] = remaining
		return
	shop.shards += delta
	for key: Vector2i in _ledger.tracking_totals():
		var data: Dictionary = shop.ability_progress.get_or_add(key.x, {})
		var tracking: Dictionary = data.get_or_add("rank_tracking", {})
		tracking[key.y] = int(tracking.get(key.y, 0)) + tracked(key.x, key.y)
