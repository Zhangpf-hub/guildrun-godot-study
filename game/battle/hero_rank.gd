extends RefCounted

static var catalog: Dictionary


static func data() -> Dictionary:
	if catalog.is_empty():
		catalog = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/hero_ranks.json"))
	return catalog


static func choices(hero: int) -> Array:
	return data().choices.get(str(hero), [])


static func apply(stats: Dictionary, rank: int, specialization: Dictionary) -> void:
	if rank <= 1:
		return
	if int(specialization.get("class", -1)) > 0:
		stats._class2ID = int(specialization["class"])
	if int(specialization.get("active", -1)) > 0:
		stats._activeAbilityID = int(specialization.active)
		stats["<StartWithActiveAbility>k__BackingField"] = 1
	if int(specialization.get("passive", -1)) > 0:
		stats._passiveAbilityID = int(specialization.passive)
	var rules := data()
	var levels := rank - 1
	var amounts := {}
	var hp := int(stats["<MaxHealth>k__BackingField"])
	for key: String in rules.growth.base:
		amounts[key] = _bonus(key, int(rules.growth.base[key]), hp, levels)
	for class_id: int in [int(stats._class1ID), int(stats._class2ID)]:
		var profession: Dictionary = rules.classes.get(str(class_id), {})
		if profession.is_empty():
			continue
		var primary: String = GuildrunBoardUnit.STAT_NAMES[int(profession.primary)]
		amounts[primary] += _bonus(primary, int(rules.growth.primary[primary]), hp, levels)
		for stat_id: int in profession.secondary:
			var key: String = GuildrunBoardUnit.STAT_NAMES[stat_id]
			amounts[key] += _bonus(key, int(rules.growth.secondary[key]), hp, levels)
	for key: String in amounts:
		stats["<%s>k__BackingField" % key] += amounts[key]


static func _bonus(key: String, per_level: int, hp: int, levels: int) -> int:
	return (hp * levels * per_level) >> 16 if key == "MaxHealth" else levels * per_level
