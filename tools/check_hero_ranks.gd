extends SceneTree


func _initialize() -> void:
	verify.call_deferred()


func require(ok: bool, detail: String) -> bool:
	if not ok:
		push_error(detail)
		quit(1)
	return ok


func verify() -> void:
	var rules = load("res://battle/hero_rank.gd")
	var choices: Dictionary = rules.data().choices
	if not require(choices.size() == 25, "Hero choice table is incomplete"):
		return
	for options: Array in choices.values():
		if not require(options.size() == 3, "Missing authored specialization"):
			return
		for option: Dictionary in options:
			if not require(ResourceLoader.exists(option.icon) and TranslationServer.translate(option.name) != option.name, "Missing icon or name at %d" % int(option.id)):
				return
	for hero_id: int in [4, 14, 26]:
		var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
		stage.stage_id = 10101
		root.add_child(stage)
		var fight := GuildrunEncounter.new()
		stage.add_child(fight)
		fight.setup(stage)
		fight.first_shop = GuildrunFirstShop.new()
		fight.add_child(fight.first_shop)
		fight.first_shop.hero_ranks[hero_id] = 2
		var option: Dictionary = rules.choices(hero_id)[1]
		var unit: GuildrunBoardUnit = stage.deploy_hero(hero_id, Vector2i(4, 3), [], [], [], 2, option)
		fight._register(unit)
		fight._hero = unit
		var melee: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 4)]
		var archer: GuildrunBoardUnit = stage.grid.occupants[Vector2i(0, 7)]
		match hero_id:
			4:
				if not require(unit.rank == 2 and unit.max_health == 900 and unit.stat("Crit") == 69 and unit.stat("Attack") == 12 and unit.stat("Magic") == 12, "Assassin rank bonuses"):
					return
				fight._land(melee, 100000, unit)
				fight._land(archer, 100000, unit)
				if not require(fight.first_shop.shards == 5 and unit.ability_progress.bounty == 6, "Bounty must pay only once per battle"):
					return
				var next: GuildrunBoardUnit = stage.deploy_hero(4, Vector2i(4, 2), [], [], [], 2, option)
				fight._register(next)
				if not require(not next.bounty_claimed and next.ability_progress.bounty == 6, "Bounty growth and per-battle reset"):
					return
			14:
				if not require(unit.max_health == 812 and unit.stat("Magic") == 56, "Mage rank bonuses"):
					return
				fight.phase = GuildrunEncounter.Phase.PLACE
				fight.start_fight()
				if not require(unit.stat("AttackRange") == 6 and melee.burn_stacks == 43, "Fire opener range and initial stacks"):
					return
				fight.battle_time_q16 = (15 << 16) - 1
				fight._step_battle(1)
				fight._step_battle(1)
				if not require(melee.burn_stacks == 86, "Fifteen-second burn must trigger once"):
					return
			26:
				if not require(unit.stat("Defense") == 79 and unit.max_health == 1202 and unit.stat("Attack") == 56 and unit.base_stats._class2ID == 2, "Warrior plus Tank rank bonuses"):
					return
				fight.phase = GuildrunEncounter.Phase.PLACE
				fight.start_fight()
				unit.begin_active_ability(melee, 15 << 16)
				if not require(unit.cast_release_q16 == 171486 - 65536 and unit.stat("Defense") == 109 and unit.shields[0].amount == 536 and unit.shields[0].remaining == 999 << 16, "Protector cast and lasting shield"):
					return
		print("B rank hero=", hero_id, " specialization=", int(option.id), " HP=", unit.max_health)
		stage.free()
		for index: int in [0, 2]:
			if not check_passive(hero_id, rules.choices(hero_id)[index]):
				return
	quit(0)


func check_passive(hero_id: int, option: Dictionary) -> bool:
	var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.stage_id = 10101
	root.add_child(stage)
	var fight := GuildrunEncounter.new()
	stage.add_child(fight)
	fight.setup(stage)
	var hero: GuildrunBoardUnit = stage.deploy_hero(hero_id, Vector2i(4, 3), [], [], [], 2, option)
	fight._register(hero)
	var enemy: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 4)]
	enemy.health = 10000
	var ok := false
	match int(option.id):
		401:
			hero.mana = 0
			hero.take_damage(225)
			var at_threshold := hero.targetable()
			hero.take_damage(1)
			var hidden := not hero.targetable() and fight._nearest_enemy(enemy) == null
			hero.stealth_remaining_q16 = 0
			hero.take_damage(1)
			ok = at_threshold and hidden and hero.stat("Crit") == 79 and hero.mana == 40 and hero.targetable()
		403:
			var ally: GuildrunBoardUnit = stage.deploy_hero(24, Vector2i(1, 2))
			fight._register(ally)
			ally.combat_stats.Crit = 100
			fight._on_attack_action(enemy, ally)
			var before := enemy.health
			fight._tick_poison(enemy, 131071)
			var not_early := before == enemy.health
			fight._tick_poison(enemy, 1)
			ok = not_early and enemy.poison_stacks == 8 and enemy.health == before - 8
		1401:
			var ally: GuildrunBoardUnit = stage.deploy_hero(17, Vector2i(3, 3))
			fight._register(ally)
			hero.mana = 0
			var ally_magic := int(ally.stat("Magic"))
			enemy.burn_stacks = 5
			enemy.burn_remaining_q16 = 1
			fight._tick_burn(enemy, 1)
			ok = hero.stat("Magic") == 58 and ally.stat("Magic") == ally_magic + 2 and hero.mana == 1
		1403:
			fight._release_wildfire(hero)
			ok = enemy.burn_stacks > 0 and enemy.health == 10000 - enemy.damage_after_defense(14 * enemy.burn_stacks) and not fight._shots.is_empty()
		2601:
			hero.gain_shield(100, 50)
			var complete: bool = hero.total_shield() == 160 and hero.stat("Attack") == 71
			hero.tick_shields(50)
			ok = complete and hero.total_shield() == 60 and hero.shields[0].remaining == (10 << 16) - 50
		2603:
			hero.combat_stats.Crit = 100
			var defense := int(enemy.stat("Defense"))
			fight._on_attack_action(enemy, hero)
			var first: bool = hero.stat("Attack") == 58 and hero.total_shield() == 216 and enemy.stat("Defense") == defense - 3
			fight.battle_time_q16 = 6 << 16
			fight._on_attack_action(enemy, hero)
			ok = first and hero.stat("Attack") == 58 and hero.total_shield() == 216 and enemy.stat("Defense") == defense - 6
	stage.free()
	if ok:
		print("passive=", int(option.passive), " verified")
	return require(ok, "Specialization effect mismatch at %d" % int(option.id))
