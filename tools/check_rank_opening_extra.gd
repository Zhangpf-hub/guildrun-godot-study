extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.stage_id = 10101
	root.add_child(stage)
	var fight := GuildrunEncounter.new()
	stage.add_child(fight)
	fight.setup(stage)
	fight._create_party()
	var party := fight.first_shop
	party.roster.assign([4, 14, 26, 24, 23, 11])
	party.reserve_slots.assign([24, 23, 11])
	party.hero_ranks = {4: 4, 14: 4, 26: 4, 24: 3, 23: 3, 11: 3}
	party.rank_modifiers_by_hero = {
		4: {3: 181, 4: 14}, 14: {3: 191, 4: 105}, 26: {3: 195, 4: 230},
		24: {3: 57}, 23: {3: 279}, 11: {3: 138},
	}
	var first: GuildrunBoardUnit = stage.deploy_hero(4, Vector2i(3, 0), [], [], [], 4, {}, party.rank_modifiers_for(4))
	var second: GuildrunBoardUnit = stage.deploy_hero(14, Vector2i(4, 0), [], [], [], 4, {}, party.rank_modifiers_for(14))
	var front: GuildrunBoardUnit = stage.deploy_hero(26, Vector2i(5, 3), [], [], [], 4, {}, party.rank_modifiers_for(26))
	for hero in [first, second, front]:
		fight._register(hero)
		hero.base_stats.equipment_classes = []
	first.base_stats._class1ID = 7
	first.base_stats._class2ID = 0
	second.base_stats._class1ID = 1
	second.base_stats._class2ID = 0
	front.base_stats._class1ID = 3
	front.base_stats._class2ID = 0
	set_health(first, 200)
	set_health(second, 390)
	front.combat_stats.Defense = 7 - int(front.stat("Defense"))
	var first_magic := int(first.stat("Magic"))
	var front_crit := int(front.stat("Crit"))
	var attack_speed := int(second.stat("AttackSpeed"))
	var shards := party.shards

	fight._hero = first
	fight.phase = GuildrunEncounter.Phase.PLACE
	fight.start_fight()
	check(fight.phase == GuildrunEncounter.Phase.FIGHT and fight.battle_time_q16 == 0,
			"Opening resolves through Start Fight before the first fixed step")
	check(first.max_health == 250 and second.max_health == 452, "181 visits recipients in registration order")
	for enemy in fight._units:
		if not enemy.is_hero:
			check(enemy.burn_stacks == 39, "191 sees prior owner's 181 maximum health increase")
	check(front.stat_q16("Defense") == 802816 and front.stat("Crit") == front_crit + 30,
			"105 preserves fractional Defense but 230 takes whole Defense")
	check(front.total_shield() == ((front.max_health * 43254) >> 16) + 1500 and second.total_shield() == 3500,
			"195 and reserve 57/138 shield the right targets before the first fixed step: %s %s %s" % [front.shields, front.max_health, second.shields])
	check(fight._rank_wallet.balance(party) == shards + 5, "Reserve 138 credits once")
	check(first.stat("Magic") == first_magic + 20 and second.stat("AttackSpeed") == attack_speed + 25,
			"Opening growth changes the intended recipients immediately")
	check(party.permanent_stats[14].get("AttackSpeed", 0) == 0, "Growth is pending until settlement")
	fight.start_fight()
	check(second.total_shield() == 3500, "Duplicate start does not replay rank events")

	fight._rank_growth.settle(party, true)
	check(party.permanent_stats[14].get("AttackSpeed", 0) == 25 and party.permanent_stats[4].get("Magic", 0) == 20,
			"Settlement commits each recipient's permanent stat")
	check(party.ability_progress[4].rank_tracking[14] == 50 and party.ability_progress[23].rank_tracking[279] == 20,
			"Settlement credits the active or reserve source, rather than the recipient: %s" % str(party.ability_progress))
	stage.free()
	verify_position_rules()
	if not failed:
		print("Rank opening order, shields, Q16 and permanent tracking passed through Start Fight")
	quit(int(failed))


func verify_position_rules() -> void:
	var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.stage_id = 10101
	root.add_child(stage)
	var fight := GuildrunEncounter.new()
	stage.add_child(fight)
	fight.setup(stage)
	var back: GuildrunBoardUnit = stage.deploy_hero(4, Vector2i(0, 0), [], [], [], 4, {}, {3: 239, 4: 272})
	var front: GuildrunBoardUnit = stage.deploy_hero(14, Vector2i(2, 3), [], [], [], 4, {}, {3: 60, 4: 271})
	var neighbor: GuildrunBoardUnit = stage.deploy_hero(26, Vector2i(3, 3), [], [], [], 4, {}, {3: 144, 4: 238})
	for hero in [back, front, neighbor]:
		fight._register(hero)
	fight._hero = back
	fight.phase = GuildrunEncounter.Phase.PLACE
	var back_crit := int(back.stat("Crit"))
	var back_magic := int(back.stat("Magic"))
	var front_magic := int(front.stat("Magic"))
	var front_defense := int(front.stat("Defense"))
	var front_attack := int(front.stat("Attack"))
	var neighbor_attack := int(neighbor.stat("Attack"))
	var shield := 400 + ((int(neighbor.stat("Magic")) * 163840) >> 16) + 10 * int(neighbor.stat("ManaRegen"))
	fight.start_fight()
	check(back.stat("Crit") == (5 * back_crit >> 1)
			and back.stat("Magic") == (back_magic * 87163 >> 16),
			"An isolated rear hero obtains stacking 239/272 percentages")
	check(back.stealth_remaining_q16 == 5 << 16 and neighbor.stealth_remaining_q16 == 5 << 16
			and front.stealth_remaining_q16 == 0, "Both stealth effects run on their owners for five seconds")
	check(front.stat("Magic") == front_magic + front_defense, "271 converts front-row Defense to Magic")
	check(front.stat("Attack") == front_attack + 33 and neighbor.stat("Attack") == neighbor_attack + 33,
			"60 grows only the adjacent pair's Attack")
	check(front.total_shield() == shield and neighbor.total_shield() == shield and back.total_shield() == 0,
			"144 shields only the owner and adjacent allies")
	var enemies := fight._units.filter(func(unit: GuildrunBoardUnit) -> bool: return not unit.is_hero)
	if enemies.size() >= 2:
		neighbor.stealth_remaining_q16 = 1
		back.stealth_remaining_q16 = 7
		fight._land(enemies[0], 1, neighbor)
		check(neighbor.stealth_remaining_q16 == 1, "238 requires a credited defeat")
		fight._land(enemies[0], 999999, back)
		check(neighbor.stealth_remaining_q16 == 1 and back.stealth_remaining_q16 == 7,
				"Only 238, and only the killer, can renew stealth")
		fight._land(enemies[1], 999999, neighbor)
		check(neighbor.stealth_remaining_q16 == 5 << 16 and not neighbor.targetable(),
				"A credited kill renews 238 for five seconds")
		neighbor.stealth_remaining_q16 = 2
		fight._land(enemies[1], 999999, neighbor)
		check(neighbor.stealth_remaining_q16 == 2, "A defeated victim cannot award a second kill")
		neighbor.take_damage(neighbor.health + neighbor.total_shield() + 1)
		neighbor.resurrect(1)
		check(neighbor.stealth_remaining_q16 == 0 and neighbor.targetable(),
				"Death clears stealth before resurrection")
	else:
		check(false, "Kill-credit fixture requires two enemies")
	stage.free()


func set_health(unit: GuildrunBoardUnit, value: int) -> void:
	unit.combat_stats.MaxHealth = value - int(unit.stat("MaxHealth"))
	unit.max_health = value
	unit.health = value


func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
