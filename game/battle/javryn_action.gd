extends RefCounted


@warning_ignore("integer_division")
static func allocate(source: GuildrunBoardUnit, units: Array[GuildrunBoardUnit]) -> Array[GuildrunBoardUnit]:
	var data := source.ability_data
	var shot_count := mini(int(data._maxShots),
			int(data._numShots) + int(source.stat("AttackSpeed")) / int(data._shotAttackSpeedIncrement))
	var attack_range := int(source.stat("AttackRange"))
	var distances: Dictionary[GuildrunBoardUnit, int] = {}
	var candidates: Array[GuildrunBoardUnit] = []
	for unit in units:
		if unit.is_hero == source.is_hero or not unit.targetable():
			continue
		var distance := GuildrunBattleGrid.distance(source.grid_cell, unit.grid_cell)
		if distance <= attack_range:
			distances[unit] = distance
			candidates.append(unit)
	candidates.sort_custom(func(left: GuildrunBoardUnit, right: GuildrunBoardUnit):
		if distances[left] == distances[right]:
			return units.find(left) < units.find(right)
		return distances[left] < distances[right])
	var targets: Array[GuildrunBoardUnit] = []
	var pool_size := mini(candidates.size(), shot_count)
	if pool_size > 0:
		for index in shot_count:
			targets.append(candidates[index % pool_size])
	return targets


static func attack_at(source: GuildrunBoardUnit, index: int) -> Dictionary:
	var attacks: Array = source.ability_data._attacks._attacks
	return attacks[mini(index, attacks.size() - 1)]
