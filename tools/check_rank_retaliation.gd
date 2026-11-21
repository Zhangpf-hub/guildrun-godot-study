extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)


func verify() -> void:
	test_spiked()
	test_vindictive()
	test_lethal_attack_pays_once(false)
	test_lethal_attack_pays_once(true)
	test_lethal_attack_pays_once(true, true)
	if not failed:
		print("Rank reactions passed shielded and lethal auto hits, half-health timing, proximity and single reward settlement")
	quit(int(failed))


func make_fight() -> GuildrunEncounter:
	var scene: PackedScene = load("res://battle/stage.tscn")
	var stage = scene.instantiate()
	stage.stage_id = 10101
	root.add_child(stage)
	var fight := GuildrunEncounter.new()
	stage.add_child(fight)
	fight.setup(stage)
	return fight


func test_spiked() -> void:
	var fight := make_fight()
	var stage := fight._stage
	var attacker: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 4)]
	var distant: GuildrunBoardUnit = stage.grid.occupants[Vector2i(0, 7)]
	var owner: GuildrunBoardUnit = stage.deploy_hero(26, Vector2i(4, 3), [], [], [], 3, {}, {3: 97})
	var other: GuildrunBoardUnit = stage.spawn_unit(attacker.base_stats.duplicate(true), Vector2i(5, 3), 3, false)
	fight._register(owner)
	fight._register(other)
	check(GuildrunBattleGrid.distance(other.grid_cell, owner.grid_cell) == 1, "Test second adjacent enemy")
	var far_before := distant.health
	attacker.health = 10000
	other.health = 10000
	owner.combat_stats.Defense = 101 - int(owner.stat("Defense"))
	var attacker_reflect := attacker.damage_after_defense(50)
	var other_reflect := other.damage_after_defense(50)
	var living_hp := owner.health
	owner.gain_shield(10000, 5 << 16)
	attack(fight, attacker, owner)
	check(owner.health == living_hp and owner.total_shield() < 10000,
		"A fully absorbed basic hit still reaches its attack-received trigger")
	check(attacker.health == 10000 - attacker_reflect and other.health == 10000 - other_reflect,
		"Spiked retaliates against every adjacent enemy, not only the attacker")
	fight._land(owner, 100, attacker)
	check(attacker.health == 10000 - attacker_reflect, "Ability damage does not trigger Spiked")
	owner.shields.clear()
	owner.health = 1
	other.max_health = 10000
	other.health = 5000 + other_reflect
	other.has_boss_fury = true
	var still_registered: Array[bool] = []
	other.shield_gained.connect(func(_amount: int): still_registered.append(stage.grid.occupants.get(owner.grid_cell) == owner))
	attack(fight, attacker, owner)
	check(owner.defeated and attacker.health == 10000 - 2 * attacker_reflect and other.health == 5000,
		"The lethal auto hit still receives one retaliation before death cleanup")
	check(still_registered == [true] and not stage.grid.occupants.has(owner.grid_cell),
		"Retaliation executes before removal, then the owner's cell is cleared")
	attack(fight, attacker, owner)
	check(attacker.health == 10000 - 2 * attacker_reflect and distant.health == far_before,
		"An already dead owner does not react or affect distant enemies")
	stage.free()


func attack(fight: GuildrunEncounter, source: GuildrunBoardUnit, target: GuildrunBoardUnit) -> void:
	source.basic_attack_action.emit(target)
	for step in 240:
		if fight._shots.is_empty():
			break
		fight._advance_projectiles(GuildrunEncounter.BATTLE_STEP_Q16)


func test_vindictive() -> void:
	var fight := make_fight()
	var stage := fight._stage
	var near: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 4)]
	var far: GuildrunBoardUnit = stage.grid.occupants[Vector2i(0, 7)]
	var owner: GuildrunBoardUnit = stage.deploy_hero(26, Vector2i(4, 3), [], [], [], 3, {}, {3: 182})
	var control: GuildrunBoardUnit = stage.deploy_hero(14, Vector2i(4, 1), [], [], [], 2, {}, {3: 182})
	fight._register(owner)
	fight._register(control)
	for unit in fight._units:
		unit.stun_remaining_q16 = 15 << 16
		unit.combat_stats.HPPerSecond = -int(unit.stat("HPPerSecond"))
	owner.combat_stats.MaxHealth = 1000 - int(owner.stat("MaxHealth"))
	owner.max_health = 1000
	owner.health = 501
	control.health = 1
	near.health = 10000
	near.max_health = 10000
	var hit := near.damage_after_defense(500)
	var far_before := far.health
	fight.phase = GuildrunEncounter.Phase.PLACE
	fight.start_fight()
	var dt := GuildrunEncounter.BATTLE_STEP_Q16
	fight._step_battle(dt)
	check(owner.total_shield() == 0 and near.health == 10000, "More than half health does not trigger")
	owner.health = 500
	var landed_after_shield: Array[bool] = []
	owner.shield_gained.connect(func(_amount: int): landed_after_shield.append(near.health == 10000))
	fight._step_battle(dt)
	check(owner.total_shield() == 500 and owner.shields[0].remaining == (10 << 16) - dt,
		"Exactly half creates a 50% MaxHealth shield expiring in ten seconds including this step")
	check(landed_after_shield == [true] and near.health == 10000 - hit and far.health == far_before,
		"Shield is granted before the damage and distant enemies are unaffected")
	check(control.total_shield() == 0, "B-rank control cannot activate an ineligible modifier")
	owner.shields.clear()
	owner.health = 800
	fight._step_battle(dt)
	owner.health = 1
	fight._step_battle(dt)
	check(owner.total_shield() == 0 and near.health == 10000 - hit, "A later threshold crossing does not repeat the effect")
	stage.free()


func test_lethal_attack_pays_once(double_defeat: bool, hunter_is_holder := false) -> void:
	var fight := make_fight()
	var stage := fight._stage
	fight._create_party()
	var shop := fight.first_shop
	var specialization: Dictionary = load("res://battle/hero_rank.gd").choices(4)[1]
	shop.roster.assign([4])
	shop.hero_ranks[4] = 4
	shop.specializations[4] = specialization
	var modifiers := {3: 236, 4: 97} if hunter_is_holder else {3: 236}
	shop.rank_modifiers_by_hero[4] = modifiers
	shop.shards = 20
	var hunter: GuildrunBoardUnit = stage.deploy_hero(4, Vector2i(4, 3), [], [], [], 4, specialization, modifiers)
	var target: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 4)]
	if hunter_is_holder:
		hunter.combat_stats.Defense = 101 - int(hunter.stat("Defense"))
	else:
		target.earned_rank_modifiers[3] = 97
		target.combat_stats.Defense = 101 - int(target.stat("Defense"))
	target.health = 1
	fight._register(hunter)
	fight.phase = GuildrunEncounter.Phase.PLACE
	fight.start_fight()
	if double_defeat:
		hunter.health = 1
	var hunter_health := hunter.health
	if hunter_is_holder:
		attack(fight, target, hunter)
	else:
		attack(fight, hunter, target)
	check(target.defeated and hunter.health < hunter_health and hunter.defeated == double_defeat,
		"Lethal Spiked response executes, including when it also kills the attacker")
	check(fight._rank_wallet.tracked(4, 236) == 8 and shop.shards == 25 and fight.combat_shard_balance() == 33,
		"The kill pays one 236 credit and one Hunter bounty")
	attack(fight, hunter, target)
	fight._land_auto(target, 1000, hunter, true)
	check(fight._rank_wallet.tracked(4, 236) == 8 and shop.shards == 25 and hunter.ability_progress.get("bounty") == 6,
		"Replaying the hit against a defeated target cannot pay the rank or passive bounty again")
	fight._rank_wallet.settle(shop)
	fight._rank_wallet.settle(shop)
	check(shop.shards == 33, "Repeated combat settlement merges the one pending kill credit once")
	stage.free()

