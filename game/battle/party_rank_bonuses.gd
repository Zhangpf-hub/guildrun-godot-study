class_name GuildrunPartyRankBonuses
extends RefCounted

const VANGUARD := 3
const DUELIST := 5
const MYSTIC := 6


static func constant_bonuses(party: GuildrunFirstShop, classes: Array[int]) -> Dictionary:
	var bonuses := {}
	for owner: int in party.roster:
		var rank := int(party.hero_ranks.get(owner, 1))
		for modifier: int in earned_modifiers(party, owner, rank):
			match modifier:
				11:
					if classes.has(DUELIST):
						_add(bonuses, 9, 2 * party.successful_shop_rerolls)
				136:
					if classes.has(MYSTIC):
						_add(bonuses, 12, party.successful_shop_rerolls)
				183:
					if classes.has(VANGUARD):
						_add(bonuses, 15, 13 + 10 * (rank - 1))
				190:
					if classes.has(VANGUARD):
						_add(bonuses, 6, 50 * rank)
	return bonuses


static func _add(bonuses: Dictionary, stat: int, amount: int) -> void:
	if amount != 0:
		bonuses[stat] = int(bonuses.get(stat, 0)) + amount


static func apply_combat_start_owner(rank: int, units: Array[GuildrunBoardUnit]) -> void:
	var mana_regen := 4 * rank
	var power := 25 * rank + 25
	for unit in units:
		if unit.is_hero and not unit.defeated:
			unit.combat_stats["Attack"] = int(unit.combat_stats.get("Attack", 0)) + power
			unit.combat_stats["Magic"] = int(unit.combat_stats.get("Magic", 0)) + power
			unit.combat_stats["ManaRegen"] = int(unit.combat_stats.get("ManaRegen", 0)) + mana_regen


static func earned_modifiers(party: GuildrunFirstShop, owner: int, rank: int) -> Array[int]:
	var result: Array[int] = []
	var selected := party.rank_modifiers_for(owner)
	for earned_rank in range(3, mini(rank, 4) + 1):
		if selected.has(earned_rank):
			result.append(int(selected[earned_rank]))
	return result
