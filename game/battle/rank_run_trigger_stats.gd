extends RefCounted

const WARRIOR := 1
const DUELIST := GuildrunPartyRankBonuses.DUELIST

var _units: Array[GuildrunBoardUnit] = []
var _reserve_weights := Vector3i.ZERO
var _applied: Dictionary[int, Vector2i] = {}


func begin(shop: GuildrunFirstShop, units: Array[GuildrunBoardUnit]) -> void:
	for id in _applied:
		if is_instance_id_valid(id):
			_replace(instance_from_id(id) as GuildrunBoardUnit, Vector2i.ZERO, _applied[id])
	_applied.clear()
	_units = units
	_reserve_weights = Vector3i.ZERO
	if shop == null:
		return
	for owner: int in shop.roster:
		if shop.reserve_slots.has(owner):
			var rank := int(shop.hero_ranks.get(owner, 1))
			_reserve_weights += _weights(GuildrunPartyRankBonuses.earned_modifiers(shop, owner, rank), true)


func refresh(total_rush_triggers: int, total_stall_triggers: int) -> void:
	var weights := _reserve_weights
	for owner in _units:
		if is_instance_valid(owner) and owner.is_hero and not owner.defeated:
			weights += _weights(owner.earned_rank_modifiers.values(), false)
	if weights == Vector3i.ZERO and _applied.is_empty():
		return
	var next: Dictionary[int, Vector2i] = {}
	for unit in _units:
		if not is_instance_valid(unit) or not unit.is_hero or unit.defeated:
			continue
		var speed := (weights.x * total_rush_triggers + weights.y * total_stall_triggers) if unit.has_class(DUELIST) else 0
		var attack := weights.z * total_rush_triggers if unit.has_class(WARRIOR) else 0
		var bonus := Vector2i(attack, speed)
		if bonus != Vector2i.ZERO:
			next[unit.get_instance_id()] = bonus
		_replace(unit, bonus, _applied.get(unit.get_instance_id(), Vector2i.ZERO))
	for id in _applied:
		if is_instance_id_valid(id):
			var unit := instance_from_id(id) as GuildrunBoardUnit
			if unit.defeated or not _units.has(unit):
				_replace(unit, Vector2i.ZERO, _applied[id])
	_applied = next


static func _weights(modifiers: Array, reserve: bool) -> Vector3i:
	var weights := Vector3i.ZERO
	for modifier: int in modifiers:
		match modifier:
			8:
				weights.x += 1
			15:
				weights.y += 1
			56:
				if reserve:
					weights.x += 2
				else:
					weights.z += 2
	return weights


static func _replace(unit: GuildrunBoardUnit, bonus: Vector2i, old: Vector2i) -> void:
	var delta := bonus - old
	if delta.x != 0:
		unit.combat_stats.Attack = int(unit.combat_stats.get("Attack", 0)) + delta.x
	if delta.y != 0:
		unit.combat_stats.AttackSpeed = int(unit.combat_stats.get("AttackSpeed", 0)) + delta.y
