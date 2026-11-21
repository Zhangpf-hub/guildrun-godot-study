extends RefCounted

# Permanent changes are visible in this combat immediately. Stat recipients and
# modifier owners differ for group effects, so record their deltas separately.
var _stats: Dictionary = {}
var _tracking: Dictionary[Vector2i, int] = {}


func grant(target: GuildrunBoardUnit, owner_id: int, modifier: int, stat: String, amount: int) -> void:
	target.combat_stats[stat] = int(target.combat_stats.get(stat, 0)) + amount
	var flat: Dictionary = _stats.get_or_add(target, {})
	flat[stat] = int(flat.get(stat, 0)) + amount
	var key := Vector2i(owner_id, modifier)
	_tracking[key] = int(_tracking.get(key, 0)) + amount


func settle(party: GuildrunFirstShop, keep: bool) -> void:
	for target: GuildrunBoardUnit in _stats:
		if not is_instance_valid(target):
			continue
		var flat: Dictionary = _stats[target]
		for stat: String in flat:
			var amount: int = flat[stat]
			target.combat_stats[stat] = int(target.combat_stats.get(stat, 0)) - amount
			if keep:
				target.permanent_stats[stat] = int(target.permanent_stats.get(stat, 0)) + amount
	if keep and party != null:
		for key: Vector2i in _tracking:
			var progress: Dictionary = party.ability_progress.get_or_add(key.x, {})
			var tracked: Dictionary = progress.get_or_add("rank_tracking", {})
			tracked[key.y] = int(tracked.get(key.y, 0)) + _tracking[key]
	_stats.clear()
	_tracking.clear()
