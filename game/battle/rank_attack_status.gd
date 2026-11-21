extends RefCounted

# Generated provider values applied to the runtime balancing entries at startup.
const AUTO_ATTACK_STATUS := {
	1: {"status": 1, "base": 1, "increment": 33, "maximum": 10},
	3: {"status": 3, "base": 1, "increment": 50, "maximum": 6},
	5: {"status": 2, "base": 1, "increment": 80, "maximum": 6},
}


@warning_ignore("integer_division")
static func attack_status_amount(modifier: int, attack_speed: int) -> Vector2i:
	var effect: Dictionary = AUTO_ATTACK_STATUS.get(modifier, {})
	if effect.is_empty():
		return Vector2i.ZERO
	var amount := mini(int(effect.maximum), int(effect.base) + attack_speed / int(effect.increment))
	return Vector2i(int(effect.status), amount)

