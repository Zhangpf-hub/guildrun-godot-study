extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(value: bool, context: String) -> void:
	if not value:
		failures.append(context)
		push_error(context)


func run() -> void:
	for id: int in [2, 5, 9, 10, 11, 12, 23]:
		var stage = load("res://battle/stage.tscn").instantiate()
		stage.stage_id = 10101
		root.add_child(stage)
		var fight := GuildrunEncounter.new()
		stage.add_child(fight)
		fight.setup(stage)
		fight.first_shop = GuildrunFirstShop.new()
		fight.add_child(fight.first_shop)
		var hero: GuildrunBoardUnit
		if id in [5, 9, 11, 12]:
			var locked: GuildrunBoardUnit = stage.deploy_hero(id, Vector2i(0, 0))
			check(locked.ability_kind.is_empty(), "Hero %d C rank starts without the specialization" % id)
			var choice: Dictionary = load("res://battle/hero_rank.gd").choices(id)[0]
			hero = stage.deploy_hero(id, Vector2i(4, 3), [], [], [], 2, choice)
			check(hero.stat("StartWithActiveAbility") == 1, "Specialization enables mana generation for %d" % id)
		else:
			hero = stage.deploy_hero(id, Vector2i(4, 3))
		fight._register(hero)
		var near: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 4)]
		var far: GuildrunBoardUnit = stage.grid.occupants[Vector2i(0, 7)]
		near.health = 10000
		far.health = 10000
		hero.base_stats["<Crit>k__BackingField"] = 0
		hero.base_stats["<Attack>k__BackingField"] = 40
		hero.base_stats["<Magic>k__BackingField"] = 30
		var ally: GuildrunBoardUnit
		if id == 10:
			ally = stage.deploy_hero(4, Vector2i(3, 3))
			fight._register(ally)
			ally.health = 10
		elif id == 5:
			fight._tick_unit(near, fight.BATTLE_STEP_Q16)
			for crit in 9:
				fight._land(near, 1, hero, true)
			check(near.current_target == hero and hero.stone_skin_triggers == 2 + int(hero.stat("Defense")) / 60, "Stone Skin critical cap and current target")
			near.health = 10000
		if id == 9:
			fight.phase = GuildrunEncounter.Phase.PLACE
			fight.start_fight()
		hero.mana = int(hero.stat("MaxMana"))
		fight._tick_unit(hero, fight.BATTLE_STEP_Q16)
		var delay: int = {2: 101581, 5: 55706, 9: 80609, 10: 32768, 11: 32768, 12: 16384, 23: 0}[id]
		check(hero.cast_target == near, "Full-mana cast target %d" % id)
		if delay == 0:
			check(hero.cast_release_q16 == -1 and hero.permafrost_targets > 0, "Instant cast releases on entry")
		else:
			check(hero.cast_release_q16 == delay - fight.BATTLE_STEP_Q16, "Cast advances on entry %d" % id)
			fight._tick_cast(hero, delay - fight.BATTLE_STEP_Q16 - 1)
		check(fight._shots.is_empty() and near.health == 10000 and (not ally or ally.total_shield() == 0), "Premature release %d" % id)
		if id == 12:
			fight.total_stall_triggers = 3
		if delay > 0:
			fight._tick_cast(hero, 1)
		match id:
			5:
				var expected := 275 + ((int(hero.stat("Magic")) * 163840) >> 16)
				check(near.health == 10000 - near.damage_after_defense(expected) and near.stun_remaining_q16 == 4 << 16, "Petrification targets enemies locked on Zuri")
				check(near.poison_stacks == 2 * hero.stone_skin_triggers and far.poison_stacks == 0 and far.health == 10000, "Petrification uses permanent Stone Skin stacks")
			2:
				check(fight._shots.size() == 1, "Killshot projectile spawned")
				if not fight._shots.is_empty():
					var shot: Dictionary = fight._shots[0]
					check(shot.target == far and shot.damage == 460 and far.health == 10000, "Killshot target and prepared damage")
					check(shot.speed == GuildrunBattleGrid.to_world_length_q16(786432), "Killshot projectile speed")
					# At zero base crit Killshot still has a 50% chance at C rank.
					var stream: int = fight._combat_rng.state
					var critical: bool = fight._combat_rng.next_q16() < (1 << 15)
					fight._combat_rng.state = stream
					fight._advance_projectiles(5 << 16)
					check(far.health == 10000 - far.damage_after_defense(920 if critical else 460) and near.health == 10000, "Killshot contact damage")
					var before := far.health
					hero.begin_active_ability(near)
					fight._tick_cast(hero, delay)
					hero.base_stats["<Crit>k__BackingField"] = 100
					fight._advance_projectiles(5 << 16)
					check(far.health == before - far.damage_after_defense(1610), "Killshot uses 250 Crit at impact")
			9:
				var expected := 225 + 45 + 80 + (int(hero.stat("MaxHealth")) >> 2)
				check(near.health == 10000 - near.damage_after_defense(expected) and near.stun_remaining_q16 == 3 << 16, "Wheel and Deal damage and stun")
				for cast in 2:
					hero.begin_active_ability(near)
					fight._tick_cast(hero, delay)
				check(fight.first_shop.items.is_empty(), "Item given before fourth cast")
				var next: GuildrunBoardUnit = stage.deploy_hero(9, Vector2i(4, 2), [], [], [], 2, load("res://battle/hero_rank.gd").choices(9)[0])
				fight._register(next)
				next.begin_active_ability(near)
				fight._tick_cast(next, delay)
				check(int(next.ability_progress.casts) == 4 and int(next.ability_progress.items) == 1, "Niklas counter on redeploy")
				check(fight.first_shop.items.is_empty() and fight._gained_items.size() == 1, "Fourth cast rolls an item before settlement")
				if not fight._gained_items.is_empty():
					var rolled: int = fight._gained_items[0]
					var pool: Array = load("res://battle/opening_draft.gd").data().rewards.Item_3
					check(pool.any(func(row: Array): return int(row[0]) == rolled), "B-rank Wheel and Deal common item pool")
					fight.trial = {"id": 1033, "modifier": 5503, "kind": "shards", "value": 10}
					fight.battle_time_q16 = 30 << 16
					fight._step_battle(fight.BATTLE_STEP_Q16)
					check(fight.first_shop.items.has(rolled) and fight._gained_items.is_empty(), "Result phase settles the rolled item")
			10:
				check(ally.total_shield() == 325 and ally.health == 10 and hero.total_shield() == 0, "Vault Spark lowest HP percentage and shield")
				ally.tick_shields(655359)
				check(ally.total_shield() == 325, "Vault Spark shield expired early")
				ally.tick_shields(1)
				hero.base_stats["<ManaRegen>k__BackingField"] = 12
				hero.begin_active_ability(near)
				fight._tick_cast(hero, delay)
				check(ally.total_shield() == 325 and hero.total_shield() == 325, "Vault Spark additional target at 12 regen")
				var tycoon: Dictionary = load("res://battle/hero_rank.gd").choices(10)[2]
				hero.base_stats._passiveAbilityID = int(tycoon.passive)
				for cast in 3:
					hero.begin_active_ability(near)
					fight._tick_cast(hero, delay)
				check(fight._tycoon_health_bonus() == 123, "Fifth Vault Spark grants a Tycoon stack")
				var max_hp := ally.max_health
				ally.health = 10
				fight.phase = fight.Phase.PLACE
				fight.start_fight()
				check(ally.max_health == max_hp + 123 and ally.health == 133, "Combat start preserves missing HP when applying Tycoon")
				fight._units.erase(hero)
				fight.first_shop.reserve_slots.assign([10])
				fight.first_shop.hero_ranks[10] = 2
				fight.first_shop.specializations[10] = tycoon
				var reserve_stats: Dictionary = stage.hero_stats(10, [], [], [], 2, tycoon)
				check(fight._tycoon_health_bonus() == 75 + 4 * int(stage.field(reserve_stats, "ManaRegen")), "Reserve Tycoon uses Fiona's current stats")
			11:
				var hp := int(hero.stat("MaxHealth"))
				var defense := int(hero.stat("Defense"))
				fight._advance_strike_areas(26213)
				check(near.health == 10000 and hero.total_shield() == 0, "Rook area delay")
				fight._advance_strike_areas(1)
				check(near.health == 10000 - near.damage_after_defense(50 + (hp >> 2) + 2 * defense + 30), "Rook forward strike")
				check(near.stun_remaining_q16 == 262144 and hero.total_shield() == (hp >> 2) and far.health == 10000, "Rook stun, owner shield, area exclusion")
				check(fight._overlaps_area(hero.area_shapes, Vector2(6, 3), 0.1) and not fight._overlaps_area(hero.area_shapes, Vector2(6, 0.5), 0.1), "Rook side arm uses oriented collider")
			23:
				hero.rank = 2
				hero.begin_active_ability(near)
				fight._tick_cast(hero, 1)
				check(hero.permafrost_frost == 3 and hero.permafrost_damage == 50 and hero.permafrost_targets == 2, "Permafrost stacks use rank and Magic at cast")
				fight._on_attack_action(near, hero)
				check(fight._shots.size() == 2, "Permafrost secondary count limited by distinct enemies")
				if fight._shots.size() == 2:
					check(fight._shots[0].target == near and fight._shots[1].target == far and int(fight._shots[1].damage) == hero.effective_attack_damage() >> 1, "Permafrost separate half-damage arrow")
				fight._advance_projectiles(5 << 16)
				check(near.frost_stacks == 3 and far.frost_stacks == 3 and not fight._shots.size(), "Permafrost main and secondary impacts each apply frost")
			12:
				var expected := 200 + 3 * (10 + ((int(hero.stat("Defense")) * 6554) >> 16) + 3)
				check(hero.total_shield() == expected and near.current_target == hero and far.current_target == hero, "Skorn absorbs per Stall and taunts every live enemy")
				hero.take_damage(19)
				far.current_target = null
				fight._tick_cast(hero, 310640)
				check(near.health == 10000, "Skorn retaliation fired early")
				fight._tick_cast(hero, 1)
				check(near.health == 10000 - near.damage_after_defense((expected - 19) >> 1) and far.health == 10000, "Skorn retaliation samples remaining shield and current target")
		print("hero=", id, " action=", hero.ability_kind, " delay=", delay)
		stage.free()
	check_stall_triggers()
	quit(int(not failures.is_empty()))


func check_stall_triggers() -> void:
	var stage = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	var front := fight.board_hero(4)
	var shop := GuildrunFirstShop.new()
	fight.add_child(shop)
	fight.first_shop = shop
	front.base_stats = front.base_stats.duplicate()
	front.base_stats._passiveAbilityID = 10802
	front.active_stall_q16 = 15 << 16
	shop.reserve_slots.assign([8, -1])
	shop.specializations[8] = {"passive": 10802}
	shop.relics.assign([1007, 1023])
	shop.items.assign([725, 609])
	shop.equipped_to[0] = 4
	fight.start_fight()
	var expected: Array[int] = []
	for time: int in [40, 30, 30, 20, 15, 10, 10]:
		expected.append(time << 16)
	check(stall_deadlines(fight) == expected, "Independent board, bench, active, relic and equipped Stall timers")
	for unit in fight._units:
		unit.stun_remaining_q16 = 90 << 16
	for time: int in [10, 15, 20, 30, 40]:
		fight.battle_time_q16 = (time << 16) - 2
		var before := fight.total_stall_triggers
		fight._step_battle(1)
		check(fight.total_stall_triggers == before, "Stall timer fired early")
		fight._step_battle(1)
		var total: int = {10: 2, 15: 3, 20: 4, 30: 6, 40: 7}[time]
		check(fight.total_stall_triggers == total and shop.quest_progress.get(1023) == total, "Every due Stall counts once for Skorn and quest 1023")
		fight._step_battle(1)
		check(fight.total_stall_triggers == total, "Expired Stall timer fired twice")
	fight.phase = GuildrunEncounter.Phase.PLACE
	fight.start_fight()
	check(stall_deadlines(fight) == expected and fight.total_stall_triggers == 7, "Starting a battle rebuilds timers and preserves the run counter")
	stage.free()


func stall_deadlines(fight: GuildrunEncounter) -> Array[int]:
	var deadlines: Array[int] = []
	for clock: Dictionary in fight._keyword_clocks._pending:
		if int(clock.keyword) == 2:
			deadlines.append(int(clock.due))
	deadlines.sort()
	deadlines.reverse()
	return deadlines
