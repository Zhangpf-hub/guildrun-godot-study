extends RefCounted
## Actions attached to intrinsic Stall effects, in provider order for each effect.


func apply_stall(clock: Dictionary, owner: GuildrunBoardUnit,
		targets: Array[GuildrunBoardUnit], encounter: GuildrunEncounter) -> void:
	if not is_instance_valid(owner) or owner.defeated:
		return
	var modifier := int(clock.modifier)
	match modifier:
		9:
			owner.modify_stat_percent("Crit", 32768)
		91:
			owner.heal(owner.max_health, owner)
			owner.gain_mana(100)
			owner.modify_stat_percent("Defense", 16384)
		95:
			# The effect targets its owner. The taunt action enumerates the opposing side.
			for enemy: GuildrunBoardUnit in encounter._units:
				if not enemy.defeated and enemy.is_hero != owner.is_hero:
					enemy.current_target = owner
		140:
			encounter._rank_growth.grant(owner, int(clock.owner_id), modifier, "ManaRegen", 5)
		278, 282:
			var frost := modifier == 282
			var multiplier_q16 := 22938 if frost else 65536
			var stacks := (int(owner.stat("Magic")) * multiplier_q16) >> 16
			if stacks > 0:
				for enemy: GuildrunBoardUnit in targets:
					if not enemy.defeated and enemy.is_hero != owner.is_hero:
						encounter._add_elemental_status(enemy, 2 if frost else 1, stacks, owner)
		283:
			encounter._rank_growth.grant(owner, int(clock.owner_id), modifier, "Magic", 40)
		284:
			owner.gain_mana(100)

