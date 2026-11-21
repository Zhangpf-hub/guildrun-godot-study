extends RefCounted

# Values from the runtime-generated rank definitions after balancing initialization.
const OPENING_STATUS := {
	191: {"status": 1, "stat": "MaxHealth", "base": 30, "divisor": 50},
	229: {"status": 3, "stat": "Crit", "base": 30, "divisor": 2},
}


@warning_ignore("integer_division")
static func stacks(owner: GuildrunBoardUnit, rule: Dictionary) -> int:
	return int(rule.base) + int(owner.stat(String(rule.stat))) / int(rule.divisor)

