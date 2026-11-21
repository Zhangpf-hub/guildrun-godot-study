extends RefCounted

const DELIVERY_ITEMS := {1: 301, 2: 304, 3: 305, 4: 306, 5: 307, 6: 303, 7: 302}
## ThreePathsEvent pairs each reward with Poison, Frost, Burn, Debuff, Shields, Rush, Stall or Generate.
const PATH_RELICS := {
	503: [700, -1, 704, 706, 708, 711, 714, 717],
	504: [-1, 702, -1, 706, 709, 712, 715, 718],
	505: [701, 703, 705, 707, 710, 713, 716, 719],
}

var options: Array[Dictionary] = []
var _pools: Dictionary
var _party: GuildrunFirstShop
var _rng: RandomNumberGenerator


func generate(id: int, pools: Dictionary, party: GuildrunFirstShop, rng: RandomNumberGenerator) -> void:
	_pools = pools
	_party = party
	_rng = rng
	options.clear()
	match id:
		600, 601:
			var eligible := _party.hero_ranks.values().any(func(rank: int): return rank <= int(pools.max_rank))
			_add(1, "rank", 0, {"disabled": not eligible, "format": {"rank": ["C", "B", "A"][int(pools.max_rank) - 1]}})
			_add(2, "retrain", 0, {"disabled": _party.specializations.is_empty()})
			if id == 600:
				_add(3, "recharge", 0, {"disabled": _party.battle_stage.encounter.rewind_available})
				_add(4, "effect", int(pools.rested), {"duration": 1})
				if _party.battle_stage.red_rift != null:
					_add(5, "skip_rift_campfire", 0)
			else:
				_add(3, "effect", int(pools.rested), {"duration": 1})
				_add(4, "skip_rift_campfire" if _party.battle_stage.red_rift != null else "leave", 0)
		503, 504, 505:
			var item_pool: Array = _pools.item[str(39 + id - 503)]
			var item_keys := range(item_pool.size())
			var first: int = item_keys.pop_at(_rng.randi_range(0, item_keys.size() - 1))
			_add(0, "item", int(item_pool[first][0]))
			var relic_pool: Array = PATH_RELICS[id]
			var relic_keys := item_keys.filter(func(k: int): return relic_pool[k] >= 0 and not _party.relics.has(relic_pool[k]))
			if not relic_keys.is_empty():
				var second: int = relic_keys.pop_at(_rng.randi_range(0, relic_keys.size() - 1))
				_add(0, "relic", relic_pool[second])
				item_keys.erase(second)
			if relic_keys.is_empty() or _rng.randf() < 0.5:
				var third: int = item_keys[_rng.randi_range(0, item_keys.size() - 1)]
				_add(0, "item", int(item_pool[third][0]))
			else:
				var third: int = relic_keys[_rng.randi_range(0, relic_keys.size() - 1)]
				_add(0, "relic", relic_pool[third])
		1001:
			for pool: int in [111, 112, 113]:
				var relic := _draw("relic", pool)
				if relic >= 0:
					_add(1, "relic", relic, {"effect": 5105, "duration": 1})
			_add(2, "effect", 5106, {"duration": 1})
		1013:
			for profession: int in _most_played_classes():
				var title := _party.tr("HeroClasses.HeroClass_%d.Name" % profession)
				var available: Array = pools.banners[str(profession)].filter(func(id): return not _party.relics.has(int(id)))
				var designs := []
				while not available.is_empty() and designs.size() < int(pools.reward_count):
					var relic := int(available.pop_at(_rng.randi_range(0, available.size() - 1)))
					designs.append({"choice": 2, "kind": "relic", "value": relic, "format": {"class": title}})
				if not designs.is_empty():
					_add(1, "menu", 0, {"children": designs, "format": {"name": title, "class": title}})
			if options.is_empty():
				_add(0, "leave", 0, {"skip": true})
		1014:
			if not _party.specializations.is_empty():
				_add(1, "retrain", 0)
			_add(2, "item", _draw("item", 112))
			_add(3, "item", _draw("item", 110))
		1023:
			for profession: int in _most_played_classes():
				_add(1, "item", DELIVERY_ITEMS[profession])
		1024:
			var max_rank := int(pools.get("max_rank", 1))
			if _party.hero_ranks.values().any(func(rank: int): return rank <= max_rank):
				_add(1, "rank", 0, {"effect": 5112, "duration": 2, "format": {"rank": ["C", "B", "A"][max_rank - 1]}})
			_add(2, "item", _draw("item", 112))
			_add(3, "item", _draw("item", 110))
		1025:
			_add(1, "relic", _draw("relic", 101), {"delay": 1})
			_add(2, "item", _draw("item", 2), {"delay": 1})
			_add(3, "item", _draw("item", 1), {"delay": 2})
			_add(4, "relic", _draw("relic", 102), {"delay": 2})


func _most_played_classes(limit := 3) -> Array:
	var counts := {}
	if _party.battle_stage.encounter != null:
		counts = _party.battle_stage.encounter.class_play_counts
	var classes := DELIVERY_ITEMS.keys()
	var ordered := []
	while not classes.is_empty():
		ordered.append(classes.pop_at(_rng.randi_range(0, classes.size() - 1)))
	ordered.sort_custom(func(a: int, b: int): return int(counts.get(a, 0)) > int(counts.get(b, 0)))
	return ordered.slice(0, limit)


func _add(choice: int, kind: String, value: int, extra: Dictionary = {}) -> void:
	if value < 0:
		return
	var option := {"choice": choice, "kind": kind, "value": value}
	option.merge(extra)
	options.append(option)


func _draw(kind: String, pool: int) -> int:
	var entries: Array = _pools[kind][str(pool)]
	var candidates := []
	var total := 0
	for entry: Array in entries:
		var id := int(entry[0])
		if kind == "relic" and _party.relics.has(id):
			continue
		if options.any(func(o: Dictionary): return o.kind == kind and o.value == id):
			continue
		total += int(entry[1])
		candidates.append([id, total])
	if total:
		var roll := _rng.randi_range(0, total - 1)
		for candidate: Array in candidates:
			if roll < candidate[1]:
				return int(candidate[0])
	return -1
