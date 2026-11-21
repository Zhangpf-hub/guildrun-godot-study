extends RefCounted
## Combat-start actions evaluated after Constant and Rush effects.
## Call once per applicable effect in trigger priority and registration order.


## grant_permanent(target, owner_id, modifier, stat, amount) tracks the effect on its owner.
static func apply_opening(modifier: int, owner_id: int, rank: int, owner: GuildrunBoardUnit,
		allies: Array[GuildrunBoardUnit], grant_permanent: Callable) -> void:
	if modifier == 57:
		for target in allies:
			if not target.defeated and target.has_class(1):
				target.gain_shield(1000 + 500 * (rank - 1), 999 << 16, owner)
		return
	if modifier == 279:
		for target in allies:
			if not target.defeated and target.has_class(7):
				grant_permanent.call(target, owner_id, modifier, "Magic", 20)
		return
	if not is_instance_valid(owner) or owner.defeated:
		return

	var row := owner.grid_cell.y
	match modifier:
		14, 60:
			var adjacent: Array[GuildrunBoardUnit] = []
			for target in allies:
				if target != owner and not target.defeated and _distance(owner, target) == 1:
					adjacent.append(target)
			if adjacent.size() == 1:
				var stat := "AttackSpeed" if modifier == 14 else "Attack"
				var amount := 25 if modifier == 14 else 33
				grant_permanent.call(owner, owner_id, modifier, stat, amount)
				grant_permanent.call(adjacent[0], owner_id, modifier, stat, amount)
		105:
			if row == 0:
				for target in allies:
					if not target.defeated:
						var defense_q16 := target.stat_q16("Defense")
						target.modify_stat_flat_q16("Defense", (defense_q16 * 49152 + 32768) >> 16)
		144:
			var amount := 400 + ((int(owner.stat("Magic")) * 163840) >> 16) + 10 * int(owner.stat("ManaRegen"))
			for target in allies:
				if not target.defeated and (target == owner or _distance(owner, target) == 1):
					target.gain_shield(amount, 10 << 16, owner)
		181:
			for target in allies:
				if not target.defeated and (target == owner or _distance(owner, target) == 1):
					# Read the owner's current maximum at each action execution.
					var bonus := int(owner.stat("MaxHealth")) >> 2
					target.modify_stat_flat_q16("MaxHealth", bonus << 16)
		195:
			var amount := (int(owner.stat("MaxHealth")) * 43254) >> 16
			for target in allies:
				if not target.defeated and target.grid_cell.y in [2, 3]:
					target.gain_shield(amount, 10 << 16, owner)
		230, 271:
			if row == 3:
				var stat := "Crit" if modifier == 230 else "Magic"
				var multiplier_q16 := 163840 if modifier == 230 else 65536
				owner.modify_stat_flat_q16(stat, int(owner.stat("Defense")) * multiplier_q16)
		238:
			owner.gain_stealth(5 << 16)
		239:
			if row == 0:
				owner.modify_stat_percent("Crit", 65536)
				owner.gain_stealth(5 << 16)
		272:
			if row not in [0, 1]:
				return
			for target in allies:
				if target != owner and not target.defeated and target.grid_cell.y in [0, 1]:
					return
			owner.modify_stat_percent("Magic", 21627)
			owner.modify_stat_percent("Crit", 32768)


static func _distance(first: GuildrunBoardUnit, second: GuildrunBoardUnit) -> int:
	return GuildrunBattleGrid.distance(first.grid_cell, second.grid_cell)
