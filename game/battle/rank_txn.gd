extends RefCounted

# Draft. Caller owns the native pending choice UI, combat effect installation, and run RNG.
var pending: Dictionary = {}



static func pool_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://balancing/rank_modifier_pools.json"))


static func draw(data: Dictionary, classes: Array[int], rank: int, count: int, used: Array, rng: RandomNumberGenerator) -> Array[int]:
	var result: Array[int] = []
	for class_id in classes:
		var pool: Dictionary = data.pools.get("%d:%d" % [class_id, rank], {})
		var candidates: Array = pool.get("weights", []).filter(func(row: Array) -> bool:
			return not used.has(int(row[0])) and not result.has(int(row[0])))
		for pick in (count / classes.size() + int(classes.find(class_id) < count % classes.size())):
			if candidates.is_empty():
				break
			var total := 0
			for row: Array in candidates:
				total += int(row[1])
			var ticket := rng.randi_range(1, total)
			for index in candidates.size():
				ticket -= int(candidates[index][1])
				if ticket <= 0:
					result.append(int(candidates[index][0]))
					candidates.remove_at(index)
					break
	return result

func begin_existing(hero: int, current_rank: int, rank_cap: int, offers: Array[int]) -> bool:
	if not pending.is_empty() or current_rank < 2 or current_rank >= rank_cap or offers.is_empty():
		return false
	pending = {"hero": hero, "rank": current_rank + 1, "offers": offers.duplicate()}
	return true


func accept_existing(index: int, ranks: Dictionary, record: Callable) -> bool:
	if pending.is_empty() or index < 0 or index >= pending.offers.size():
		return false
	var hero := int(pending.hero)
	var rank := int(pending.rank)
	if int(ranks.get(hero, 0)) != rank - 1 or not bool(record.call(hero, rank, int(pending.offers[index]))):
		return false
	ranks[hero] = rank
	pending.clear()
	return true


func grant_pre_ranked(hero: int, rank: int, explicit: Dictionary, enabled: Dictionary, record: Callable) -> void:
	for earned_rank in migrate(explicit, rank, enabled):
		record.call(hero, earned_rank, migrate_id(explicit, earned_rank))


static func migrate(stored: Variant, current_rank: int, enabled: Dictionary) -> Dictionary:
	var result := {}
	if not stored is Dictionary:
		return result
	for earned_rank in range(3, mini(current_rank, 4) + 1):
		var value: Variant = stored.get(earned_rank, stored.get(str(earned_rank)))
		if (value is int or value is float) and float(value) == int(value) and enabled.has(int(value)):
			result[earned_rank] = int(value)
	return result


static func migrate_id(stored: Dictionary, earned_rank: int) -> int:
	return int(stored.get(earned_rank, stored.get(str(earned_rank), -1)))
