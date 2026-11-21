extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, reason: String) -> void:
	if not ok:
		failed = true
		push_error(reason)


func encounter() -> GuildrunEncounter:
	var stage = load("res://battle/stage.tscn").instantiate()
	stage.stage_id = 10101
	root.add_child(stage)
	var fight := GuildrunEncounter.new()
	stage.add_child(fight)
	fight.setup(stage)
	fight._create_party()
	fight.phase = GuildrunEncounter.Phase.PLACE
	return fight


func hero(fight: GuildrunEncounter, id: int, slot: int, mods: Dictionary, specialization := {}) -> GuildrunBoardUnit:
	var shop := fight.first_shop
	shop.roster.append(id)
	shop.hero_ranks[id] = 4
	shop.rank_modifiers_by_hero[id] = mods
	var unit: GuildrunBoardUnit = fight._stage.deploy_hero(id, Vector2i(4, slot), [], [], [], 4, specialization, mods)
	fight._register(unit)
	if not fight._hero:
		fight._hero = unit
	return unit


func reserve(fight: GuildrunEncounter, id: int, mods: Dictionary) -> void:
	var shop := fight.first_shop
	shop.roster.append(id)
	shop.reserve_slots.append(id)
	shop.hero_ranks[id] = 4
	shop.rank_modifiers_by_hero[id] = mods


func hold_units(fight: GuildrunEncounter) -> void:
	for unit in fight._units:
		unit.stun_remaining_q16 = 100 << 16


func verify() -> void:
	check_shifted_clocks()
	check_boundary()
	check_rush_actions()
	check_stall_actions()
	check_run_counts_across_boards()
	if not failed:
		print("Keyword clocks passed six duration modifiers, first step, independent equal deadlines, suspension, Rush stat sampling, shield damage and expiration")
	quit(int(failed))


func check_shifted_clocks() -> void:
	var fight := encounter()
	hero(fight, 4, 1, {3: 49, 4: 92})
	var guard := hero(fight, 26, 2, {3: 188, 4: 141}, load("res://battle/hero_rank.gd").choices(26)[2])
	var timed := hero(fight, 8, 3, {3: 95, 4: 9})
	reserve(fight, 24, {3: 228, 4: 273})
	fight.first_shop.relics.assign([1023])
	var starting_crit := int(timed.stat("Crit"))
	fight.start_fight()
	hold_units(fight)
	check(fight.total_stall_triggers == 0, "No Stall fires inside begin even if its adjusted duration is negative")
	check(timed.active_stall_q16 == 15 << 16 and timed.stat("Crit") == floori(starting_crit * 1.5), "Pollen has its real 15s active clock and rank 9's opening Rush")
	fight._step_battle(1)
	check(fight.total_stall_triggers == 2, "Three reductions move the 15s ability and the first 10s rank 95 clock into the first step")
	timed.take_damage(timed.health + timed.total_shield() + 1)
	fight._step_battle(1 << 16)
	check(timed.stat("Crit") == starting_crit and fight.total_stall_triggers == 2, "Defeated owner loses Rush grant and its clocks stop advancing")
	timed.resurrect(timed.max_health)
	hold_units(fight)
	fight.battle_time_q16 = (3 << 16) - 2
	fight._step_battle(1)
	check(fight.total_stall_triggers == 2 and timed.stat("Crit") == floori(starting_crit * 1.5), "Revival restores Rush and the remaining second of owner time")
	fight._step_battle(1)
	check(fight.total_stall_triggers == 4 and fight.first_shop.quest_progress.get(1023) == 4, "The two separate 20s rank effects each fire exactly once at the same adjusted deadline")
	var enemy: GuildrunBoardUnit = fight._units.filter(func(u: GuildrunBoardUnit): return not u.is_hero)[0]
	check(fight._keyword_clocks.stall_elapsed(enemy, 65536) == 65536, "Enemy keyword duration is unaffected by the player's reductions")
	check(fight._keyword_clocks.rush_active(guard, (15 << 16) - 1, 6 << 16) and not fight._keyword_clocks.rush_active(guard, 15 << 16, 6 << 16),
			"All three earned Rush extenders stack across board and reserve and preserve the strict end boundary")
	fight._stage.free()


func check_stall_actions() -> void:
	var fight := encounter()
	var elementalist := hero(fight, 14, 1, {3: 278, 4: 282})
	var student := hero(fight, 8, 2, {3: 140, 4: 283})
	var defender := hero(fight, 26, 3, {3: 91, 4: 284})
	elementalist.combat_stats.Magic = 40 - int(elementalist.stat("Magic"))
	var initial_magic := int(student.stat("Magic"))
	var initial_regen := int(student.stat("ManaRegen"))
	var initial_defense := int(defender.stat("Defense"))
	fight.start_fight()
	hold_units(fight)
	var targets := fight._units.filter(func(u: GuildrunBoardUnit): return not u.is_hero)
	var live: GuildrunBoardUnit = targets[0]
	var inactive: GuildrunBoardUnit = targets[1]
	inactive.take_damage(inactive.health + 1)
	defender.mana = 0
	fight.battle_time_q16 = (15 << 16) - 1
	fight._step_battle(1)
	check(defender.mana == mini(100, int(defender.stat("MaxMana"))), "The first of three separate 284 effects restores mana")
	fight.battle_time_q16 = (20 << 16) - 1
	fight._step_battle(1)
	check(live.burn_stacks == 40 and live.frost_stacks == 14 and inactive.burn_stacks == 0 and inactive.frost_stacks == 0,
			"278 and 282 use the current owner's Magic and only living opponents")
	fight.battle_time_q16 = (25 << 16) - 1
	fight._step_battle(1)
	check(student.stat("Magic") == initial_magic + 40 and int(student.permanent_stats.get("Magic", 0)) == 0,
			"283 uses the native 25s deadline and the current fight sees the gain before settlement")
	defender.health = 1
	defender.mana = 0
	fight.battle_time_q16 = (30 << 16) - 1
	fight._step_battle(1)
	check(defender.health == defender.max_health and defender.mana == int(defender.stat("MaxMana"))
			and defender.stat("Defense") == (initial_defense * 81920) >> 16, "91 heals, grants mana and then adds its 25% defense")
	check(student.stat("ManaRegen") == initial_regen + 5, "140 uses the initialized +5 permanent gain")
	defender.mana = 0
	fight.battle_time_q16 = (45 << 16) - 1
	fight._step_battle(1)
	check(defender.mana == mini(100, int(defender.stat("MaxMana"))), "284's third clock remains independent")
	live.take_damage(live.health + 1)
	fight._step_battle(1)
	check(fight.phase == GuildrunEncounter.Phase.RESULT and student.permanent_stats == {"Magic": 40, "ManaRegen": 5}
			and student.ability_progress.rank_tracking == {283: 40, 140: 5}, "Normal resolution commits permanent growth and its tracking once")
	fight._stage.free()


func check_run_counts_across_boards() -> void:
	var fight := encounter()
	fight._stage.normal_opening = true
	var recipient := hero(fight, 15, 1, {3: 8, 4: 15})
	hero(fight, 26, 2, {3: 56}, load("res://battle/hero_rank.gd").choices(26)[2])
	hero(fight, 4, 3, {3: 48})
	reserve(fight, 24, {3: 56})
	fight.first_shop.specializations[26] = load("res://battle/hero_rank.gd").choices(26)[2]
	fight.first_shop.relics.assign([1007])
	var speed := int(recipient.stat("AttackSpeed"))
	var attack := int(recipient.stat("Attack"))
	fight.start_fight()
	hold_units(fight)
	check(recipient.has_class(1) and recipient.has_class(5) and fight.total_rush_triggers == 2,
			"An initialized hero passive and rank 48 independently announce Rush")
	fight._step_battle(1)
	check(recipient.stat("Attack") == attack + 4 and recipient.stat("AttackSpeed") == speed + 6,
			"56 grants different stats for the board and reserve branches, alongside 8")
	fight.battle_time_q16 = (10 << 16) - 1
	fight._step_battle(1)
	check(fight.total_stall_triggers == 1 and recipient.stat("AttackSpeed") == speed + 7,
			"One due relic clock increases the Duelist's 15 contribution on evaluation")
	for enemy in fight._units:
		if not enemy.is_hero:
			enemy.take_damage(enemy.health + enemy.total_shield() + 1)
	fight._step_battle(1)
	check(fight.phase == GuildrunEncounter.Phase.RESULT, "The first board reaches result")
	fight._enter_next_battle()
	check(fight.phase == GuildrunEncounter.Phase.PLACE, "Normal floor progression rebuilds the party")
	var next := fight.board_hero(15)
	var next_speed := int(next.stat("AttackSpeed"))
	fight.start_fight()
	hold_units(fight)
	fight._step_battle(1)
	check(fight.total_rush_triggers == 4 and fight.total_stall_triggers == 1 and next.stat("AttackSpeed") == next_speed + 13,
			"The next floor keeps committed counts and applies the two new opening occurrences")
	fight._stage.free()


func check_boundary() -> void:
	var fight := encounter()
	var first := hero(fight, 4, 2, {3: 92, 4: 141})
	first.active_stall_q16 = 12 << 16
	hero(fight, 14, 3, {})
	fight.start_fight()
	hold_units(fight)
	check(fight.total_stall_triggers == 0, "A reduced zero deadline starts pending")
	fight._step_battle(1)
	fight._step_battle(1)
	check(fight.total_stall_triggers == 1, "An original positive reduced to zero fires once and the absent second ability never fires")
	fight._stage.free()


func check_rush_actions() -> void:
	var fight := encounter()
	var shield := hero(fight, 4, 1, {3: 52, 4: 54})
	var mage := hero(fight, 14, 2, {3: 48, 4: 187})
	var other := hero(fight, 26, 3, {3: 234})
	reserve(fight, 24, {3: 237})
	fight.first_shop.shards = 31
	var attack := int(shield.stat("Attack"))
	var crit := int(shield.stat("Crit"))
	var mage_crit := int(mage.stat("Crit"))
	var other_crit := int(other.stat("Crit"))
	var hp := mage.max_health
	fight.start_fight()
	hold_units(fight)
	check(mage.max_health == 2 * hp and mage.health == 2 * hp, "Max health Rush applies before the first step")
	check(mage.stat("Crit") == 2 * mage_crit and other.stat("Crit") == 2 * other_crit, "Two different 100% critical stat effects remain owner-only")
	check(shield.has_class(4) and shield.stat("Crit") == crit + 31, "Reserve rank 237 samples wallet and buffs the Assassin")
	check(shield.stat("Attack") == attack, "Per-frame rank 54 waits for the first simulation step")
	fight.first_shop.shards += 13
	fight._step_battle(1)
	fight._step_battle(1)
	check(shield.stat("Attack") == 2 * attack and shield.stat("Crit") == crit + 31, "Continuous buff is applied once and the sampled wallet stays fixed")
	var victim: GuildrunBoardUnit = fight._units.filter(func(u: GuildrunBoardUnit): return not u.is_hero)[0]
	victim.combat_stats.Defense = -int(victim.stat("Defense"))
	victim.health = 5
	victim.gain_shield(14, 100 << 16)
	fight._land(victim, 2, shield)
	check(shield.total_shield() == 0, "Wholly shielded damage gives no rank 52 shield")
	fight._land(victim, 32, shield)
	check(shield.total_shield() == 10, "Shield calculation uses 20 post-shield damage including overkill")
	fight.battle_time_q16 = (8 << 16) - 1
	fight._step_battle(1)
	check(shield.stat("Attack") == attack and shield.total_shield() == 10, "Rush ending removes the attack buff and retains the granted long-lived shield")
	fight.battle_time_q16 = (10 << 16) - 1
	fight._step_battle(1)
	check(mage.stat("Crit") == mage_crit and other.stat("Crit") == other_crit and shield.stat("Crit") == crit, "10s expiry withdraws the exact original critical bonuses")
	fight.battle_time_q16 = (12 << 16) - 1
	var health_before_expiry := mage.health
	fight._step_battle(1)
	check(mage.max_health == hp and mage.health == health_before_expiry, "12s expiry withdraws maximum capacity and preserves current health")
	fight._stage.free()
