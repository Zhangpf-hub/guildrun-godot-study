extends RefCounted

const DATA_PATH := "res://balancing/bottom_roster_abilities.json"
static var _data: Dictionary


static func slots_for(hero_id: int, specialization_id: int = -1, modifiers: Dictionary = {}) -> Array[Dictionary]:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var result: Array[Dictionary] = []
	for slot in int(_data.slots.count):
		result.append({})
	var hero: Dictionary = _data.heroes.get(str(hero_id), {})
	if hero.is_empty():
		return result

	var starting: Dictionary = hero.starting
	result[int(_data.slots.starting)] = _entry(String(starting.kind), int(starting.id))
	if hero.specialization_ids.any(func(choice: Variant) -> bool: return int(choice) == specialization_id):
		var specialization: Variant = _data.specializations[str(specialization_id)].display
		if specialization is Dictionary:
			result[int(_data.slots.specialization)] = _entry(String(specialization.kind), int(specialization.id))
	for rank: int in range(1, result.size() + 1):
		var modifier := int(modifiers.get(rank, modifiers.get(str(rank), -1)))
		var entry := _entry("rank_modifier", modifier)
		if not entry.is_empty():
			result[rank + int(_data.slots.rank_modifier_index_offset)] = entry
	return result


static func _entry(kind: String, id: int) -> Dictionary:
	var record: Dictionary = _data.icons[kind].get(str(id), {})
	if record.is_empty():
		return {}
	return {"kind": kind, "id": id, "icon": String(record.icon)}
