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
	var fight := GuildrunEncounter.new()
	stage.add_child(fight)
	fight.setup(stage)
	var first: GuildrunBoardUnit = stage.deploy_hero(26, Vector2i(4, 3), [], [], [], 4, {}, {3: 191, 4: 229})
	var second: GuildrunBoardUnit = stage.deploy_hero(14, Vector2i(4, 1), [], [], [], 3, {}, {3: 191})
	var control: GuildrunBoardUnit = stage.deploy_hero(4, Vector2i(4, 2), [], [], [], 2, {}, {3: 229})
	for hero in [first, second, control]:
		fight._register(hero)
	fight._create_party()
	fight.first_shop.roster.assign([26, 14, 4, 24])
	fight.first_shop.reserve_slots.assign([24, -1, -1])
	fight.first_shop.hero_ranks = {26: 4, 14: 3, 4: 2, 24: 3}
	fight.first_shop.rank_modifiers_by_hero[24] = {3: 191}
	fight._hero = first
	fight.phase = GuildrunEncounter.Phase.PLACE
	first.combat_stats.MaxHealth = 1049 - int(first.stat("MaxHealth"))
	first.combat_stats.Crit = 101 - int(first.stat("Crit"))
	second.combat_stats.MaxHealth = 400 - int(second.stat("MaxHealth"))
	var targets: Array = fight._units.filter(func(unit: GuildrunBoardUnit): return not unit.is_hero)
	check(targets.size() >= 2, "Exercise more than one enemy at different distances")
	for target in targets:
		check(target.burn_stacks == 0 and target.poison_stacks == 0, "No status during placement")
	fight.start_fight()
	check(fight.phase == GuildrunEncounter.Phase.FIGHT and fight.battle_time_q16 == 0,
		"Opening effects run through Start Fight before the first simulation tick")
	for target in targets:
		check(target.burn_stacks == 88 and target.poison_stacks == 80,
			"Every enemy gains both source-based statuses with native truncation and stacking")
		check(target.burn_remaining_q16 == stage.burn_interval_q16
			and target.poison_remaining_q16 == stage.poison_interval_q16,
			"The existing elemental status clocks start at application")
	for hero in [first, second, control]:
		check(hero.burn_stacks == 0 and hero.poison_stacks == 0, "Opening effects leave allied targets untouched")
	fight.start_fight()
	check(targets[0].burn_stacks == 88 and targets[0].poison_stacks == 80, "A repeated start command does not apply again")
	stage.free()
	if not failed:
		print("Rank opening statuses 191 and 229 passed normal combat start, scaling, all enemies and once-only timing")
	quit(int(failed))

