extends "res://battle/curated_event.gd"
## Event builders shared by the single-path forest crossroads.

var remaining_victories: int

func generate(id: int, pools: Dictionary, party: GuildrunFirstShop, rng: RandomNumberGenerator) -> void:
	super.generate(id, pools, party, rng)
	match id:
		1017:
			_add(2, "item", _draw("item", 3))
			_add(1, "item", _draw("item", 2), {"effect": 5103, "duration": 1, "format": {"burnpercent": 3}})
			_add(3, "item", _draw("item", 1), {"effect": 5108, "duration": 1, "format": {"burnpercent": 5}})
		1022:
			var classes := _most_played_classes()
			for i in classes.size():
				var profession := int(classes[i])
				var relics := _class_rewards("relic", profession)
				var items := _class_rewards("item", profession)
				var give_relic := i == 0 or (i == 2 and not relics.is_empty() and (items.is_empty() or rng.randf() < 0.5))
				var candidates := relics if give_relic else items
				if not candidates.is_empty():
					_add(2 if give_relic else 1, "relic" if give_relic else "item",
							int(candidates[rng.randi_range(0, candidates.size() - 1)]),
							{"format": {"class": party.tr("HeroClasses.HeroClass_%d.Name" % profession)}})
		1006:
			var small := _draw("stat", 4)
			var medium := _draw("stat", 5)
			_add(1, "relic", _draw("relic", 102), {"party_modifier": small, "format": _stat_text(small)})
			var common := _draw("relic", 101)
			var heroes := []
			for hero in party.roster:
				heroes.append({"choice": 2, "kind": "relic", "value": common, "hero": hero,
						"modifier": medium, "label_hero": true})
			_add(2, "relic", common, {"children": heroes, "format": _stat_text(medium)})
			var rare := _draw("item", 2)
			_hero_choice(3, "random_spec", {"item": rare})
			_add(4, "effect", 5106, {"duration": 1})
		1018:
			_pick(1, "relic", 101, {"delay": 1, "effect": 5124, "duration": 1}, {"reliccount": 3, "combatcount": 1})
			for tier in [2, 3]:
				_add(tier, "relic", _draw("relic", 100 + tier), {"effect": 5104, "duration": tier - 1,
						"format": {"defensepenalty": 50, "combatcount": tier - 1}})
		1019:
			var rares := _picks("relic", 102)
			var losses := _fruit_ids(783)
			for i in mini(rares.size(), losses.size()):
				rares[i].extra_relic = losses[i]
			_menu(1, rares.slice(0, mini(rares.size(), losses.size())), {"reliccount": rares.size()})
			var boosts := []
			for relic in _fruit_ids(790).slice(0, 3):
				boosts.append({"choice": 0, "kind": "relic", "value": relic, "effect": 5105, "duration": 1})
			_menu(2, boosts, {"reliccount": boosts.size(), "stuntime": 6})
			_add(3, "relic", 799, {"delay": 2, "effect": 5128, "duration": 2,
					"format": {"stuncombatcount": 2, "stunduration": 6, "maxhpbonus": 500}})
			_add(4, "effect", 5106, {"duration": 1})
		1026:
			_add(1, "effect", 5113, {"duration": remaining_victories, "format": {"shardbonus": 25}})
			_pick(2, "item", 2, {"effect": 5115, "duration": 1}, {"itemcount": 3, "damagepercent": 15})
			_pick(3, "item", 1, {"effect": 5127, "duration": 1}, {"itemcount": 3, "damagepercent": 30})
		1027:
			_add(1, "item", _draw("item", 110))
			_add(2, "effect", 5116, {"duration": 2, "shard_delta": 10, "format": {"shardbonus": 10, "statlosspercent": 10, "combatcount": 2}})
			_pick(3, "relic", 103, {"delay": 1, "effect": 5117, "duration": 1}, {"reliccount": 3, "statlosspercent": 15})
		1028:
			_add(1, "item", _draw("item", 30))
			_add(2, "item", _draw("item", 1), {"effect": 5118, "duration": 1, "delay": 1, "format": {"poisonpercent": 1}})
			_add(3, "relic", _draw("relic", 103), {"effect": 5119, "duration": 1, "delay": 1})
		1029:
			var family := rng.randi_range(0, 3)
			options.assign([_drink(1, family), _option("Leave")])
		1030:
			options.assign(_debt(1))


func _class_rewards(kind: String, profession: int) -> Array:
	var first := (621 if kind == "relic" else 308) + 2 * (profession - 1)
	return [first, first + 1].filter(func(id: int): return _pools[kind].class_rewards.has(float(id)) and (kind != "relic" or not _party.relics.has(id)))


func _fruit_ids(first: int) -> Array:
	var source := range(first, first + 7).filter(func(id: int): return not _party.relics.has(id))
	var result := []
	while not source.is_empty():
		result.append(source.pop_at(_rng.randi_range(0, source.size() - 1)))
	return result


func _stat_text(id: int) -> Dictionary:
	var row: Dictionary = _party.battle_stage._stat_modifiers[id]
	var stat := int(_party.battle_stage.field(row, "TargetStat"))
	var amount := int(_party.battle_stage.field(row, "Value").RawValue) >> 16
	return {"amount": absi(amount), "stat": _party.tr("UI.Stat.%s.Title" % GuildrunBoardUnit.STAT_NAMES[stat])}


func _picks(kind: String, pool: int, count := 3) -> Array:
	var result := []
	var entries: Array = _pools[kind][str(pool)].duplicate()
	if kind == "relic":
		entries = entries.filter(func(row: Array): return not _party.relics.has(int(row[0])))
	while result.size() < count and not entries.is_empty():
		var total := 0
		for entry: Array in entries:
			total += int(entry[1])
		if total <= 0:
			break
		var pick := _rng.randi_range(0, total - 1)
		for i in entries.size():
			pick -= int(entries[i][1])
			if pick < 0:
				result.append({"kind": kind, "choice": 0, "value": int(entries[i][0])})
				entries.remove_at(i)
				break
	return result


func _pick(choice: int, kind: String, pool: int, reward: Dictionary, values: Dictionary) -> void:
	var children := _picks(kind, pool)
	for child: Dictionary in children:
		child.merge(reward)
	_menu(choice, children, values)


func _menu(choice: int, children: Array, values: Dictionary) -> void:
	if not children.is_empty():
		_add(choice, "menu", 0, {"children": children, "format": values})


func _hero_choice(choice: int, kind: String, extra: Dictionary) -> void:
	var children := []
	for hero: int in _party.roster:
		if kind == "random_spec" and not _party.specializations.has(hero):
			continue
		var option := {"choice": choice, "kind": kind, "value": 0, "hero": hero, "label_hero": true}
		option.merge(extra)
		children.append(option)
	_menu(choice, children, {})


func _option(key: String, kind := "leave", value := 0, extra: Dictionary = {}) -> Dictionary:
	var option := {"choice": -1, "key": key, "kind": kind, "value": value}
	option.merge(extra)
	return option


func _drink(depth: int, family: int) -> Dictionary:
	var next := []
	if _rng.randi_range(0, 99) < 66:
		var key := ["Item", "Relic", "Stat", "Shards"][family] as String
		var text_key := "Take%sL%d" % [key, depth]
		match family:
			0, 1:
				var kind := "item" if family == 0 else "relic"
				var pool := (1 if depth == 3 else 2) if family == 0 else (103 if depth == 3 else 102)
				for pick: Dictionary in _picks(kind, pool, 1 if depth == 1 else 3):
					next.append(_option(text_key, kind, pick.value))
			2:
				next.append(_option(text_key, "relic" if depth == 3 else "effect", 797 if depth == 3 else 5120,
						{"duration": depth, "format": {"statbonus": 10, "combatcount": depth}}))
			3:
				var count := 7 if depth == 1 else 15
				if depth == 3:
					for hero in _party.roster:
						if int(_party.hero_ranks[hero]) <= 2:
							next.append(_option("TakeShardsL3_Hero", "well_rank", count, {"hero": hero, "format": {"shards": count}}))
				if next.is_empty():
					next.append(_option(text_key, "shards", count, {"format": {"shards": count}}))
		if depth < 3:
			next.append(_drink(depth + 1, family))
	else:
		var bad := _rng.randi_range(0, 2)
		var mod := _draw("stat", 4)
		var targets := []
		for hero in _party.roster:
			if bad == 0 and _party.specializations.has(hero):
				targets.append(_option("BadSpecReroll_Hero", "random_spec", 0, {"hero": hero}))
			elif bad == 1:
				targets.append(_option("BadStatLoss_Hero", "training", mod, {"hero": hero}))
		if targets.is_empty():
			next.append(_option("BadOutcome_2", "effect", 5125, {"duration": 1, "shard_delta": -5, "format": {"shards": 5}}))
		else:
			next.append(_option("BadOutcome" if bad == 0 else "BadOutcome_1", "menu", 0, {"children": targets}))
	return _option("DrinkL%d" % depth, "menu", 0, {"children": next, "format": {"goodchance": 66, "badchance": 33}})


func _debt(level: int) -> Array:
	var picks := _picks("relic", 100 + level)
	var after := _debt(level + 1) if level < 3 else []
	for pick: Dictionary in picks:
		pick.effect = 5121 if level == 1 else 5122
		pick.shard_delta = -5 if level == 1 else -15
		pick.duration = 1
		if level < 3:
			pick.after = after
		else:
			pick.extra_relic = 798
	var result := [{"choice": 2 if level == 1 else 5, "kind": "leave", "value": 0}]
	if not picks.is_empty():
		result.push_front({"choice": [1, 3, 4][level - 1], "kind": "menu", "value": 0, "children": picks,
				"format": {"reliccount": picks.size(), "shards": 5 if level == 1 else 15, "damagepercent": 10}})
	return result
