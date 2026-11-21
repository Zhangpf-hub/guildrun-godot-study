extends "res://battle/fourth_shop_events.gd"

var event: Dictionary


func generate(id: int, pools: Dictionary, party: GuildrunFirstShop, rng: RandomNumberGenerator) -> void:
	super.generate(id, pools, party, rng)
	match id:
		2001, 2002, 2003:
			var kind := "item" if id == 2001 else "relic"
			options.assign(_picks(kind, int(event.pool), 1 if id == 2003 else 3))
			if not options.is_empty():
				return
		2004:
			_add(1, "retrain", 0, {"disabled": party.specializations.is_empty()})
		2012:
			_offer_heroes(pools.hero[str(int(event.pool))])
		_:
			var values := _stat_text(int(event.modifier))
			var heroes := []
			for hero in party.roster:
				var name_text := party.tr("Heroes.Hero_%d.Name" % hero)
				var result := values.duplicate()
				result.hero = name_text
				heroes.append({"kind": "training", "choice": 1, "value": int(event.modifier), "hero": hero,
					"caption": name_text, "outcome": party.tr("Events.Shared.MechanicalOutcome.AddPermanentStatBonus").format(result)})
			_add(1, "menu", 0, {"children": heroes, "caption": party.tr("Events.Shared.ChoiceText.ChooseHero").format(values)})
	_add(2, "leave", 0, {"caption": party.tr("Events.Event_2012.Choice_2.ChoiceTitle"),
		"outcome": party.tr("Events.Shared.ChoiceOutcome.Leave")})


static func can_offer_recruit(pool: Array, party: GuildrunFirstShop) -> bool:
	if not party.has_recruitment_space():
		return false
	return pool.any(func(entry: Array) -> bool: return not party.roster.has(int(entry[0])))


func _offer_heroes(pool: Array) -> void:
	if not can_offer_recruit(pool, _party):
		return
	for profession: int in _most_played_classes(7):
		var candidates := []
		for entry: Array in pool:
			var hero := int(entry[0])
			var row: Dictionary = _party.battle_stage._heroes[hero]
			if not _party.roster.has(hero) and profession in [int(row._class1ID), int(row._class2ID)]:
				candidates.append(hero)
		if candidates.is_empty():
			continue
		var hero := int(candidates[_rng.randi_range(0, candidates.size() - 1)])
		var rank_modifiers := _party._roll_pre_ranked(hero, 4, _rng)
		var specs: Array = preload("res://battle/hero_rank.gd").choices(hero)
		var spec: Dictionary = {} if specs.is_empty() else specs[_rng.randi_range(0, specs.size() - 1)]
		var child := {"kind": "hero", "choice": 1, "key": "Confirm", "value": hero, "hero": hero,
			"rank_modifiers": rank_modifiers, "spec": spec}
		_add(1, "menu", 0, {"key": "ClassChoice", "format": {"class": _party.tr("HeroClasses.HeroClass_%d.Name" % profession)},
			"children": [child]})
		if options.size() >= 3:
			break
