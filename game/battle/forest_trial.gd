extends RefCounted


static func road(id: int) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/forest_trials.json"))
	return {"id": id, "paths": data.roads[str(id)], "events": data.events, "pools": data.pools, "fallback_icon": data.fallback_icon}


static func description_format(event_id: int, last_miniboss_group: String) -> Dictionary:
	if event_id != 1035:
		return {}
	var boss := 10901 if last_miniboss_group == "Hydra" else 103201
	return {"bossname": TranslationServer.translate("Enemies.Enemy_%d.Name" % boss)}


static func generate(event_id: int, pools: Dictionary, party: GuildrunFirstShop, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var stage_id: int = party.battle_stage.trial_map(event_id)
	var options: Array[Dictionary] = []
	var rare: Array = pools.relic.filter(func(pair: Array):
		return int(pair[2]) <= party.opening_xp and not party.relics.has(int(pair[0])))
	match event_id:
		1032:
			options.append(_option(1, 5500, "shards", 20, stage_id, {"shards": 20}))
			var relic := _draw(rare, rng)
			if relic >= 0:
				options.append(_option(3, 5501, "relic", relic, stage_id))
			var items: Array = pools.item.filter(func(pair: Array): return int(pair[2]) <= party.opening_xp)
			var item := _draw(items, rng)
			if item >= 0:
				options.append(_option(2, 5502, "item", item, stage_id))
		1033, 1034:
			for i in 3:
				var shards := (i + 1) * 10
				var values := {"shards": shards, "survivetime": 30 + 10 * i, "timelimit": 20, "hpbonus": 100 * i}
				var modifier := (5503 if event_id == 1033 else 5506) + i
				options.append(_option(i + 1, modifier, "shards", shards, stage_id, values))
		1035:
			for i in mini(3, rare.size()):
				var values := description_format(event_id, party.battle_stage.last_miniboss_group)
				values.merge({"statreduction": 20 if i == 0 else 60, "timelimit": 15})
				var relic := _draw(rare, rng)
				values.relicname = party._entry_name("Relic", relic)
				options.append(_option(i + 1, 5509 + i, "relic", relic, stage_id, values))
	return options


static func _option(choice: int, modifier: int, kind: String, value: int, stage_id: int, values := {}) -> Dictionary:
	return {"choice": choice, "modifier": modifier, "kind": kind, "value": value, "stage_id": stage_id, "format": values}


static func _draw(pool: Array, rng: RandomNumberGenerator) -> int:
	if pool.is_empty():
		return -1
	var total := 0
	for pair: Array in pool:
		total += int(pair[1])
	var roll := rng.randi_range(0, total - 1)
	for i in pool.size():
		roll -= int(pool[i][1])
		if roll < 0:
			var picked: Array = pool.pop_at(i)
			return int(picked[0])
	return -1

