extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)


func verify() -> void:
	var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.stage_id = 10101
	root.add_child(stage)
	var encounter := GuildrunEncounter.new()
	stage.add_child(encounter)
	encounter.setup(stage)
	encounter._create_party()
	var shop := encounter.first_shop
	shop.roster.assign([14, 4, 26, 24])
	shop.hero_ranks = {14: 4, 4: 4, 26: 4, 24: 4}
	shop.reserve_slots.assign([24, -1, -1])
	shop.rank_modifiers_by_hero[24] = {3: 138, 4: 139}
	shop.shards = 27
	shop.relics.assign([1022, 1007])
	var archer: GuildrunBoardUnit = stage.deploy_hero(14, Vector2i(4, 3), [], [], [], 4, {}, {3: 12, 4: 235})
	var killer: GuildrunBoardUnit = stage.deploy_hero(4, Vector2i(4, 1), [], [], [], 4, {}, {3: 236, 4: 235})
	var caster: GuildrunBoardUnit = stage.deploy_hero(26, Vector2i(4, 2), [], [], [], 4, {}, {3: 137, 4: 139})
	for hero in [archer, killer, caster]:
		encounter._register(hero)
	encounter._hero = archer
	encounter.phase = GuildrunEncounter.Phase.PLACE
	encounter.start_fight()
	var targets := encounter._units.filter(func(u: GuildrunBoardUnit): return not u.is_hero)
	var target: GuildrunBoardUnit = targets[0]
	target.health = 90000
	target.max_health = 90000
	check(encounter.combat_shard_balance() == 32 and shop.shards == 27, "Reserve opening credit has its own live balance")
	var hud = encounter._ui.get_node("BattleTop")
	var label := hud.panel.get_node("Middle/Left_Shard/CurrentGoldAmount/UnityText") as Label
	hud.refresh()
	check(label.text == "32", "The translated battle HUD shows uncommitted combat earnings")
	for ally in [archer, killer, caster]:
		check(ally.total_shield() == 2000, "Each deployed ally gets a rank-four reserve shield at the opening")
	check(target.total_shield() == 0, "Reserve opening shield excludes enemies")
	for cast in 2:
		caster.begin_active_ability(target)
		check(encounter._rank_wallet.tracked(26, 137) == 0, "Windup does not count as ability execution")
		encounter._tick_cast(caster, caster.cast_release_q16 + 1)
	check(encounter._rank_wallet.tracked(26, 137) == 3, "Two ability executions pay the finalized provider value")
	encounter._notify_cast_effect(caster)
	check(encounter._rank_wallet.tracked(26, 137) == 3, "Later parts of the same cast do not count again")
	var initial_regen := int(archer.stat("ManaRegen"))
	archer.stun_remaining_q16 = 3
	encounter.battle_time_q16 = (10 << 16) - 1
	encounter._step_battle(1)
	check(int(archer.stat("ManaRegen")) == initial_regen + 6 and encounter.combat_shard_balance() == 37,
			"An actual Stall pulse fires once for each deployed or reserve owner")
	caster.take_damage(caster.health + caster.total_shield() + 1)
	encounter.battle_time_q16 = (20 << 16) - 1
	encounter._step_battle(1)
	check(int(archer.stat("ManaRegen")) == initial_regen + 9 and encounter.combat_shard_balance() == 38,
			"Later Stall pulses suspend the defeated owner while the reserve owner still provides the effect")
	archer.stun_remaining_q16 = 0
	for i in 8:
		encounter._begin_basic_attack(archer, target, 65536)
	check(encounter._rank_wallet.tracked(14, 12) == 0, "Eight attack starts stay below the threshold")
	encounter._begin_basic_attack(archer, target, 65536)
	check(encounter._rank_wallet.tracked(14, 12) == 1, "Ninth attack starts before the projectile launches")
	encounter._land(target, 1, archer, true)
	encounter._land(target, 1, killer, true)
	check(encounter._rank_wallet.tracked(14, 235) == 0 and encounter._rank_wallet.tracked(4, 235) == 0,
			"Two different heroes do not pool their critical hits")
	encounter._land(target, 1, archer, true)
	check(encounter._rank_wallet.tracked(14, 235) == 1 and encounter._rank_wallet.tracked(24, 235) == 0,
			"The attributed attacker owns the reward")
	encounter._land(targets[1], 999999, killer)
	encounter._land(targets[1], 999999, killer)
	check(encounter._rank_wallet.tracked(4, 236) == 8 and encounter._rank_wallet.tracked(14, 236) == 0,
			"Repeated hits on the defeated victim pay only once")
	check(shop.shards == 27 and int(shop.quest_progress.get(1022, 0)) == 21,
			"Battle gain advances the generation quest before paying the persistent wallet")
	for unit: GuildrunBoardUnit in targets:
		if not unit.defeated:
			unit.take_damage(unit.health + 1)
	encounter._step_battle(GuildrunEncounter.BATTLE_STEP_Q16)
	check(encounter.phase == GuildrunEncounter.Phase.RESULT and shop.shards == 48,
			"Combat result pays its delta exactly once, separate from stage and survivor rewards")
	check(shop.ability_progress[24].rank_tracking == {138: 5, 139: 2}
			and shop.ability_progress[26].rank_tracking == {137: 3, 139: 1},
			"Settlement keeps tracking per rank and per hero")
	encounter._rank_wallet.settle(shop)
	check(shop.shards == 48, "Repeated application of the resolved combat cannot duplicate credits")
	stage.free()
	for scenario in [[true, false, false], [true, true, false], [true, true, true], [false, false, false]]:
		check_boss_settlement(scenario[0], scenario[1], scenario[2])
	if not failed:
		print("Rank combat credits passed source attribution, attack execution, critical and kill counters, settlement and quest progress")
	quit(int(failed))


func check_boss_settlement(final_floor: bool, won: bool, challenge: bool) -> void:
	var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.stage_id = 10101
	root.add_child(stage)
	var board := -1
	for id: int in stage._stages:
		var row: Dictionary = stage._stages[id]
		if int(stage.field(row, "ActNumber")) == 1 and int(stage.field(row, "StageType")) == (3 if final_floor else 2):
			board = id
			break
	check(board >= 0 and stage.load_board(board), "Load an authored final or intermediate boss board")
	check(bool(stage.floor_rules().get("final_boss", false)) == final_floor, "The act schedule identifies its final node")
	stage.challenge_run = challenge
	var encounter := GuildrunEncounter.new()
	stage.add_child(encounter)
	encounter.setup(stage)
	encounter._create_party()
	var shop := encounter.first_shop
	shop.shards = 9
	shop.roster.assign([4, 24])
	shop.hero_ranks = {4: 3, 24: 3}
	shop.reserve_slots.assign([24, -1, -1])
	shop.rank_modifiers_by_hero[24] = {3: 138}
	shop.relics.assign([1022])
	shop.rank_modifiers_by_hero[4] = {3: 283}
	encounter._hero = stage.deploy_hero(4, Vector2i(3, 1), [], [], [], 3, {}, {3: 283})
	encounter._register(encounter._hero)
	encounter.phase = GuildrunEncounter.Phase.PLACE
	encounter.start_fight()
	check(encounter.combat_shard_balance() == 14, "Reserve generation is visible before boss resolution")
	var original_magic := int(encounter._hero.stat("Magic"))
	for unit in encounter._units:
		unit.stun_remaining_q16 = 100 << 16
	encounter.battle_time_q16 = (25 << 16) - 1
	encounter._step_battle(1)
	check(encounter._hero.stat("Magic") == original_magic + 40, "The 25s Stall increases Magic within combat")
	for unit in encounter._units:
		if unit.is_hero != won:
			unit.take_damage(unit.health + unit.total_shield() + 1)
	encounter._step_battle(GuildrunEncounter.BATTLE_STEP_Q16)
	var keep := not final_floor or (won and not challenge)
	check(shop.shards == (14 if keep else 9) and encounter.combat_shard_balance() == shop.shards,
			"Final-node outcome and challenge status gate permanent credits")
	check(int(shop.ability_progress.get(24, {}).get("rank_tracking", {}).get(138, 0)) == (5 if keep else 0)
			and int(shop.quest_progress.get(1022, 0)) == (5 if keep else 0), "Tracking follows the same permanent-change branch")
	check(int(shop.permanent_stats[4].get("Magic", 0)) == (40 if keep else 0)
			and int(shop.ability_progress[4].get("rank_tracking", {}).get(283, 0)) == (40 if keep else 0),
			"Permanent Stall stats and hero tracking follow the final-node result")
	stage.free()
