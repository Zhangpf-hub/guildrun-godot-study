extends RefCounted


static func apply_at_start(source: GuildrunBoardUnit, target: GuildrunBoardUnit,
		party: GuildrunFirstShop, units: Array[GuildrunBoardUnit]) -> void:
	if party == null or not source.is_hero or not source.has_class(GuildrunPartyRankBonuses.DUELIST):
		return
	var matches: Array[int] = []
	if target.burn_stacks > 0:
		matches.append(2)
	if target.poison_stacks > 0:
		matches.append(4)
	if target.frost_stacks > 0:
		matches.append(6)
	if matches.is_empty():
		return
	var amount := 0
	for owner in units:
		if owner.is_hero and not owner.defeated:
			for modifier: int in owner.earned_rank_modifiers.values():
				if matches.has(modifier):
					amount += 2
	for owner: int in party.reserve_slots:
		if owner < 0:
			continue
		var rank := int(party.hero_ranks.get(owner, 1))
		for modifier: int in GuildrunPartyRankBonuses.earned_modifiers(party, owner, rank):
			if matches.has(modifier):
				amount += 2
	if amount > 0:
		source.combat_stats.AttackSpeed = int(source.combat_stats.get("AttackSpeed", 0)) + amount
