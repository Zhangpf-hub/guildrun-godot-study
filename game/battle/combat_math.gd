class_name GuildrunCombatMath
extends RefCounted

const ONE := 1 << 16

## Build 26551710, DamageHandler.CalculateDamageAfterDefense(int damage, int defense).
## Preserve both truncations on the positive-defense path.
@warning_ignore("integer_division")
static func after_defense(damage: int, defense: int) -> int:
	if defense > 0:
		var denominator := ONE + (defense * ONE / 100)
		return ((damage << 32) / denominator) >> 16
	var multiplier := ONE + (-defense * ONE / 100)
	return (damage * multiplier) >> 16


## CharacterStatsComponent.GetCritDamageMultiplier(FP critValue), Q16.16 in and out.
@warning_ignore("integer_division")
static func critical_multiplier(crit_value: int) -> int:
	return (200 * ONE + maxi(0, crit_value - 100 * ONE)) / 100
