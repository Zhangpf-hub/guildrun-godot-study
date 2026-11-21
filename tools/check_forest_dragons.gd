extends "check_challenge_effects.gd"


func status(unit: GuildrunBoardUnit, kind: int) -> int:
	return [unit.burn_stacks, unit.frost_stacks, unit.poison_stacks][kind - 1]


func verify() -> void:
	for room in range(101301, 101304):
		var kind := int([1, 3, 2][room - 101301])
		var fight := fixture(room)
		var dragon := fight._units[0]
		var distant := fight._units[-2]
		var target := fight._units[-1]
		var adjacent: GuildrunBoardUnit = fight._stage.deploy_hero(26, Vector2i(4, 2))
		fight._register(adjacent)
		check(dragon.passive_id() == 200 + kind and dragon.ability_kind == "AreaOfEffectAction", "Wrong forest dragon")
		dragon.combat_stats.Crit = -int(dragon.stat("Crit"))
		var magic := int(dragon.stat("Magic"))
		var increments := [10, 15, 20]
		var stacks := int([3, 2, 1][kind - 1]) + magic / int(increments[kind - 1])
		var attack := dragon.effective_attack_damage()
		var primary_damage := target.damage_after_defense(attack)
		var splash_damage := adjacent.damage_after_defense((attack * 43254) >> 16)
		fight._on_attack_action(target, dragon)
		check(fight._shots.size() == 2 and status(target, kind) == 0 and adjacent.health == adjacent.max_health, "Dragon attacks must travel to each target")
		fight._advance_projectiles(20 << 16)
		check(target.health == target.max_health - primary_damage and status(target, kind) == stacks, "Primary dragon hit or status")
		check(adjacent.health == adjacent.max_health - splash_damage and status(adjacent, kind) == stacks, "Dragon splash or status")
		check(distant.health == distant.max_health and status(distant, kind) == 0, "Splash on distant hero")
		var hp := target.health
		dragon.begin_active_ability(target)
		fight._tick_cast(dragon, 90439)
		check(fight._strike_areas.is_empty(), "Dragon breath windup ended early")
		fight._tick_cast(dragon, 1)
		check(fight._strike_areas.size() == 1, "Dragon breath area missing")
		fight._advance_strike_areas(26213)
		check(target.health == hp, "Dragon breath ticked early")
		fight._advance_strike_areas(1)
		var amount := int([15, 10, 5][kind - 1]) + ((magic * int([39322, 26214, 13107][kind - 1])) >> 16)
		check(target.health == hp - target.damage_after_defense(200 + 2 * magic) and status(target, kind) == stacks + amount, "Dragon breath damage or status")
		fight._advance_strike_areas(32768 - 26214)
		check(fight._strike_areas.is_empty(), "Dragon breath area persisted")
		fight._stage.free()
	print("FOREST_DRAGONS projectiles, 66% splash, three elemental on-hit effects and timed breath areas")
	quit(1 if failed else 0)
