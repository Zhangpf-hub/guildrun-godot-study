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
	shop.roster.assign([14, 4, 26])
	shop.hero_ranks = {14: 4, 4: 3, 26: 3}
	shop.reserve_slots.assign([26, -1, -1])
	shop.rank_modifiers_by_hero[26] = {3: 2, 4: 4}
	var archer: GuildrunBoardUnit = stage.deploy_hero(14, Vector2i(4, 3), [], [], [], 4, {}, {3: 4, 4: 6})
	var owner: GuildrunBoardUnit = stage.deploy_hero(4, Vector2i(4, 1), [], [], [], 3, {}, {3: 2})
	encounter._register(archer)
	encounter._register(owner)
	encounter._hero = archer
	encounter.phase = GuildrunEncounter.Phase.PLACE
	encounter.start_fight()
	var target: GuildrunBoardUnit = encounter._nearest_enemy(archer)
	archer.grid_cell = target.grid_cell + Vector2i(1, 0)
	archer.ability_kind = ""
	archer.base_stats._class1ID = -1
	archer.base_stats._class2ID = -1
	archer.base_stats.equipment_classes = []
	var baseline := int(archer.stat("AttackSpeed"))
	target.burn_stacks = 1
	start_attack(encounter, archer)
	check(int(archer.stat("AttackSpeed")) == baseline, "Only a Duelist can receive the bonus")
	archer.base_stats.equipment_classes = [GuildrunPartyRankBonuses.DUELIST]
	target.burn_stacks = 0
	start_attack(encounter, archer)
	check(int(archer.stat("AttackSpeed")) == baseline, "A target without the matching status gives no bonus")
	var original_hit_at := archer._hit_remaining_q16

	target.burn_stacks = 5
	start_attack(encounter, archer)
	check(int(archer.stat("AttackSpeed")) == baseline + 4, "One deployed and one reserve owner each grant 2 despite five stacks")
	check(archer._hit_remaining_q16 == original_hit_at and archer.passive_attacks == 0,
			"At windup the animation timing has already been sampled and the attack action is still pending")
	target.burn_stacks = 0
	target.poison_stacks = 1
	start_attack(encounter, archer)
	check(int(archer.stat("AttackSpeed")) == baseline + 6 and archer._hit_remaining_q16 < original_hit_at,
			"Poison contributes 2, and the preceding bonus accelerates this new windup")

	target.frost_stacks = 1
	start_attack(encounter, archer)
	check(int(archer.stat("AttackSpeed")) == baseline + 10, "Eligible Poison and Frost effects stack on one attack")
	archer.advance_basic_attack(archer._hit_remaining_q16 + 1)
	check(archer.passive_attacks == 1 and int(archer.stat("AttackSpeed")) == baseline + 10,
			"The delayed attack action does not grant another stack")

	target.burn_stacks = 1
	target.poison_stacks = 0
	target.frost_stacks = 0
	owner.take_damage(owner.health + owner.total_shield() + 1)
	start_attack(encounter, archer)
	check(int(archer.stat("AttackSpeed")) == baseline + 12, "The defeated deployed owner contributes nothing")
	target.take_damage(target.health + target.total_shield() + 1)
	archer.advance_basic_attack(archer._hit_remaining_q16 + 1)
	check(archer.passive_attacks == 1 and int(archer.stat("AttackSpeed")) == baseline + 12,
			"A defeated target cancels release without rolling back the windup bonus")
	if not failed:
		print("Rank 2/4/6 attack start and cancellation checks passed")
	quit(int(failed))


func start_attack(encounter: GuildrunEncounter, archer: GuildrunBoardUnit) -> void:
	archer.attack_cooldown_q16 = 0
	encounter._tick_unit(archer, 1)
