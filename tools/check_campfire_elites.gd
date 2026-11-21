extends "check_challenge_effects.gd"


func verify() -> void:
	check_demon()
	check_hydra()
	check_rewind_and_training()
	print("Checked elite casts, passive thresholds, campfire training, recharge and two consecutive losses.")
	quit(1 if failed else 0)


func check_demon() -> void:
	var fight := fixture(10601)
	var demon := fight._units[0]
	var target := fight._units.back() as GuildrunBoardUnit
	check(demon.passive_id() == 204 and demon.ability_kind == "demon_anger", "Missing Demon Elite rules")
	demon.begin_active_ability(target)
	fight._tick_cast(demon, 32767)
	check(demon.total_shield() == 0 and target.burn_stacks == 0, "Anger fired before 0.5 seconds")
	fight._tick_cast(demon, 1)
	var shield := (demon.max_health * 6554) >> 16
	var burn := (int(demon.stat("Attack")) * 21627) >> 16
	check(demon.total_shield() == shield and demon.shields[0].remaining == 655360, "Anger shield")
	check(target.burn_stacks == burn and fight._units[-2].burn_stacks == burn, "Anger must affect every hero")
	var speed := int(demon.stat("AttackSpeed"))
	demon.take_damage(shield + ceili(demon.max_health * 0.5) - 1)
	check(not demon.fury_used, "Fury triggered above half HP")
	demon.take_damage(1)
	check(demon.fury_used and demon.total_shield() == demon.max_health >> 2 and int(demon.stat("AttackSpeed")) == speed + 25, "Fury shield and speed")
	demon.take_damage(1)
	check(target.burn_stacks == burn + int(demon.stat("Attack")), "Fury burn must trigger once")
	fight._stage.free()


func check_hydra() -> void:
	var fight := fixture(10602)
	var hydra := fight._units[0]
	var target := fight._units.back() as GuildrunBoardUnit
	check(hydra.passive_id() == 205 and hydra.ability_kind == "HydraAction", "Missing Hydra rules")
	var poison := 2 + int(hydra.stat("Attack")) / 20
	for heads in [3, 2, 1]:
		var fraction: float = {3: 0.9, 2: 0.60, 1: 0.30}[heads]
		hydra.health = floori(hydra.max_health * fraction)
		var before_hp := hydra.health
		hydra.heal_remaining_q16 = 1
		hydra.tick_health_regen(1)
		check(hydra.hydra_heads == heads and hydra.health == before_hp + 15 * heads + int(hydra.stat("HPPerSecond")), "Regen per head")
		target.health = 20000
		target.poison_stacks = 0
		hydra.begin_active_ability(target)
		fight._tick_cast(hydra, 1)
		var damage := fight._ability_attack_damage(hydra, hydra.ability_data._attacks._attacks[0])
		check(target.health == 20000 - target.damage_after_defense(heads * damage) and target.poison_stacks == heads * poison, "Bite must scale damage and poison by heads")
		hydra.combat_stats.Crit = -10000
		var hp := target.health
		fight._on_attack_action(target, hydra)
		var basic := hydra.effective_attack_damage()
		check(hp - target.health == target.damage_after_defense(basic) + (heads - 1) * target.damage_after_defense((basic * 21627) >> 16), "Instant bonus strikes")
	hydra.heal(hydra.max_health)
	hydra.tick_health_regen(1)
	check(hydra.hydra_heads == 1, "Healing regrew severed heads")
	fight._stage.free()


func check_rewind_and_training() -> void:
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	stage._trial_roads.clear()
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	fight.start_fight()
	fight._hero.take_damage(fight._hero.max_health)
	fight._step_battle(1)
	var shop := fight.first_shop
	check(fight._continue.visible and not fight.rewind_available and fight.rewind_reserve == 0, "First loss must consume the rewind")
	fight.open_first_shop()
	check(shop.rewind_payout == 10 and shop.shards == 25 and shop.battle_reward == 0, "Initial reserve paid without victory rewards")
	shop.visit = 5
	for action: int in [0, 2]:
		var road: GuildrunFirstCrossroads = load("res://UI/first_crossroads.tscn").instantiate()
		root.add_child(road)
		road.setup(shop.roster, shop)
		road.select_path(0)
		var buttons := road.get_node("Body/Event/Content/Actions")
		if action == 0:
			check(buttons.get_child(1).disabled, "Study enabled without an upgrade")
			road.choose_reward(0)
			buttons.get_child(-1).pressed.emit()
			check(not road.claimed and buttons.get_child_count() == 4, "Back consumed campfire")
			road.choose_reward(0)
			buttons.get_child(0).pressed.emit()
			buttons.get_child(0).pressed.emit()
			check(road.claimed and shop.hero_ranks[4] == 2 and shop.specializations.has(4), "Campfire training")
		else:
			check(buttons.get_child(0).disabled and not buttons.get_child(2).disabled, "C rank limit or recharge eligibility")
			road.choose_reward(2)
			check(road.claimed and fight.rewind_available and fight.rewind_reserve == 10, "Recharge must refill starting reserve")
		road.free()
	shop.visit = 1
	shop.leave()
	fight.crossroads.select_path(0)
	fight.crossroads.claim()
	fight.crossroads.departed.emit()
	fight.start_fight()
	for unit in fight._units:
		if unit.is_hero:
			unit.take_damage(unit.max_health)
	fight._step_battle(1)
	check(fight._continue.visible and shop.visit == 2 and shop.rewind_payout == 10 and not fight.rewind_available, "Recharged rewind did not protect next loss")
	fight.open_first_shop()
	shop.leave()
	fight.crossroads.offers[0] = 503
	fight.crossroads.select_path(0)
	fight.crossroads.choose_reward(0)
	fight.crossroads.departed.emit()
	fight.start_fight()
	for unit in fight._units:
		if unit.is_hero:
			unit.take_damage(unit.max_health)
	fight._step_battle(1)
	check(fight.phase == GuildrunEncounter.Phase.RESULT and not fight._continue.visible and shop.visit == 2, "Second loss without recharge must end the run")
	stage.free()
