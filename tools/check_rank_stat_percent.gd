extends SceneTree


func _initialize() -> void:
	var unit := GuildrunBoardUnit.new()
	unit.initialize({
		"<Id>k__BackingField": {"_sequentialId": 4},
		"<MaxHealth>k__BackingField": 101,
		"<Attack>k__BackingField": 100,
		"<Defense>k__BackingField": 11,
		"<MoveSpeed>k__BackingField": {"RawValue": 100001},
		"<StartingMana>k__BackingField": 0,
	}, Vector2i.ZERO, 0)
	unit.modify_stat_percent("Attack", 16384)
	unit.modify_stat_percent("Attack", 16384)
	assert(unit.stat("Attack") == 150, "percentage deltas add")
	unit.permanent_stats.Attack = 20
	unit.combat_stats.Attack = 12
	unit.frost_reductions.Attack = 2
	assert(unit.stat("Attack") == 195, "flats added later also scale")
	unit.modify_stat_percent("Attack", -49152)
	assert(unit.stat("Attack") == 97, "signed delta can bring total below zero")
	unit.modify_stat_percent("Attack", 16384)
	assert(unit.stat("Attack") == 130, "inverse delta removes modifier")
	unit.modify_stat_percent("MoveSpeed", 32768)
	assert(unit.stat("MoveSpeed").RawValue == 150002, "Q16 product retains fractional precision")
	assert(unit.base_stats["<MoveSpeed>k__BackingField"].RawValue == 100001)
	unit.health = 30
	unit.modify_stat_percent("MaxHealth", 32768)
	assert(unit.max_health == 151 and unit.health == 80, "max-health increase fills gained capacity")
	unit.modify_stat_percent("MaxHealth", -32768)
	assert(unit.max_health == 101 and unit.health == 80, "expiry leaves current health alone")
	unit.set_basic_stat_percent(10)
	assert(unit.max_health == 111 and unit.health == 88, "challenge preserves ratio")
	assert(unit.stat("Defense") == 12 and unit.stat("Attack") == 143, "challenge still floors its existing scale")
	unit.free()
	print("Rank percentage stat regression passed")
	quit()
