extends "check_fifth_battle.gd"

var seventh_room := 0
var eighth_room := 0
var reached_shops := 0


func verify() -> void:
	check_golem()
	for i in 11:
		seventh_room = 10701 + i % 9
		eighth_room = 10801 + i
		run_variant(i % 2)
	check(reached_shops == 11, "All eleven eighth battles should reach their shops")
	quit(1 if failed else 0)


func check_golem() -> void:
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	stage.stage_id = 10706
	root.add_child(stage)
	stage._trial_roads.clear()
	var fight := GuildrunEncounter.new()
	stage.add_child(fight)
	fight.setup(stage)
	var golem: GuildrunBoardUnit = fight._units.filter(func(u): return u.passive_id() == 110)[0]
	var adjacent: Array[GuildrunBoardUnit] = []
	for direction in 6:
		var cell := GuildrunBattleGrid.neighbor(golem.grid_cell, direction)
		if stage.grid.contains(cell) and not stage.grid.occupants.has(cell):
			var hero: GuildrunBoardUnit = stage.deploy_hero(26, cell)
			fight._register(hero)
			adjacent.append(hero)
	var distant: GuildrunBoardUnit = stage.deploy_hero(26, Vector2i.ZERO)
	fight._register(distant)
	var defense := int(golem.stat("Defense"))
	fight.phase = GuildrunEncounter.Phase.PLACE
	fight.start_fight()
	check(int(golem.stat("Defense")) == defense + int(golem.stat("Magic")), "Golem opening armor must scale with Magic")
	golem.begin_active_ability(distant)
	fight._tick_cast(golem, 41483)
	check(adjacent[0].health == adjacent[0].max_health and adjacent[0].stun_remaining_q16 == 0, "Slam released early")
	var damage := 150 + ((int(golem.stat("Magic")) * 98304) >> 16)
	var cells := adjacent.map(func(hero): return hero.grid_cell)
	fight._tick_cast(golem, 1)
	for i in adjacent.size():
		var hero := adjacent[i]
		check(hero.health == hero.max_health - hero.damage_after_defense(damage) and hero.stun_remaining_q16 == 163840, "Slam should hit all adjacent heroes")
		check(hero.grid_cell == cells[i] and stage.grid.occupants[cells[i]] == hero, "Slam moved an adjacent hero")
	check(distant.health == distant.max_health and distant.stun_remaining_q16 == 0, "Slam reached a distant target")
	stage.free()


func verify_sixth(stage: Node, variant: int) -> void:
	super.verify_sixth(stage, variant)
	var fight: GuildrunEncounter = stage.encounter
	var shop := fight.first_shop
	if shop.visit != 6 or not shop.super_shop:
		check(false, "Expected a playable elite shop")
		return
	stock_up(shop, stage)
	var frozen_stock := shop.stock.duplicate()
	var frozen_purchases := shop.purchased.duplicate()
	var ranks := shop.hero_ranks.duplicate()
	var gear := shop.equipped_to.duplicate()
	var frozen_offers := shop.offer_ranks.duplicate()
	var was_frozen := seventh_room % 2 == 1
	if was_frozen:
		shop.toggle_freeze()
	var previous_event := fight.crossroads.get_instance_id()
	check(stage.next_floor_candidates().size() == 9, "Wrong pool after the first elite")
	next_room(stage, seventh_room)
	shop._leave.pressed.emit()
	check(stage.stage_id == seventh_room and fight.phase == GuildrunEncounter.Phase.PLACE, "Shop did not open seventh deployment")
	check(fight.crossroads.get_instance_id() == previous_event and not fight.crossroads.visible, "NoCrossroads opened another event")
	check(shop.hero_ranks == ranks and shop.equipped_to == gear and fight.challenge_modifier == 0, "Deployment lost ranks, equipment or cleared modifiers")
	for unit in fight._units:
		if unit.is_hero:
			var hero := int(unit.stat("Id")._sequentialId)
			check(unit.rank == ranks[hero] and unit.grid_cell == fight._formation[hero], "Hero formation or rank changed")
		else:
			check(not unit.ability_kind.is_empty(), "Unimplemented enemy active ability on seventh floor")
	if seventh_room == 10709:
		# Put the high-rank starter in front and the two allies one row behind.
		# This route needs to survive both the ninth seventh-floor layout and its successor.
		for placement: Array in [[4, Vector2i(3, 3)], [24, Vector2i(2, 2)], [13, Vector2i(4, 2)]]:
			check(fight.transfer_hero(fight.board_hero(placement[0]).grid_cell, placement[1]), "Deploy the room 10709 formation")
	var wallet := shop.shards
	resolve(fight)
	var survivors := fight._units.filter(func(u): return u.is_hero and not u.defeated).size()
	check(fight.phase == GuildrunEncounter.Phase.RESULT and fight._continue.visible, "Seventh result")
	fight._continue.pressed.emit()
	check(shop.visit == 7 and not shop.super_shop and fight.phase == GuildrunEncounter.Phase.SHOP, "Seventh shop missing")
	check(shop.shards >= wallet + shop.battle_reward + shop.survival_reward + shop.rewind_payout, "Seventh result underpaid")
	if was_frozen:
		check(shop.stock == frozen_stock and shop.purchased == frozen_purchases and shop.offer_ranks == frozen_offers, "Frozen elite offers lost")
		for i in shop.stock.size():
			check(shop._buttons.has(i) and shop._buttons[i].visible == not frozen_purchases.has(i), "Frozen or purchased slot inaccessible")
	var before_reroll := shop.shards
	var cost := shop.reroll_cost
	check(shop.reroll() and shop.stock.size() == 6 and shop._buttons.size() == 6 and shop.shards == before_reroll - cost, "Seventh shop refresh or charge")
	check(shop.offer_ranks.size() == 3 and int(stage.floor_rules().chunk) == 1, "Second chunk hero ranks")
	print("seventh stage=", seventh_room, " survivors=", survivors, " shop=", shop.visit, " frozen=", was_frozen)
	verify_eighth(stage)


func verify_eighth(stage: Node) -> void:
	var fight: GuildrunEncounter = stage.encounter
	var shop := fight.first_shop
	var uses := fight.class_play_counts.duplicate()
	check(not uses.is_empty(), "Completed fights should count deployed classes")
	stock_up(shop, stage)
	shop._leave.pressed.emit()
	var road := fight.crossroads
	check(fight.phase == GuildrunEncounter.Phase.CROSSROADS and int(road._data.id) == 31 and road.offers.size() == 1, "Seventh road")
	var monster := eighth_room % 2 == 1
	road.offers[0] = 1017 if monster else 1022
	road._rng.seed = 301
	road.get_node("Body/Paths").get_child(0).pressed.emit()
	var choice := eighth_room % 3 if monster else 0
	var option := road.choices[choice].duplicate()
	road.get_node("Body/Event/Content/Actions").get_child(choice).pressed.emit()
	check(road.claimed and (shop.items.has(option.value) if option.kind == "item" else shop.relics.has(option.value)), "Missing chosen reward")
	check(stage.next_floor_candidates().size() == 11, "Wrong eighth encounter pool")
	next_room(stage, eighth_room)
	road.get_node("Body/Event/Content/Continue").pressed.emit()
	check(stage.stage_id == eighth_room and fight.phase == GuildrunEncounter.Phase.PLACE, "Eighth deployment")
	fight.start_fight()
	for unit in fight._units:
		if unit.is_hero:
			var ratio := 1966 if int(option.get("effect", 0)) == 5103 else 3277
			var expected := (unit.max_health * ratio) >> 16 if option.has("effect") else 0
			check(unit.burn_stacks == expected, "Wrong opening burn at eighth fight")
		else:
			check(not unit.ability_kind.is_empty(), "Missing eighth enemy ability")
	resolve(fight)
	check(fight.phase == GuildrunEncounter.Phase.RESULT and fight._continue.visible, "Expected victory or rewind")
	check(fight.class_play_counts != uses, "Eighth battle did not increment class counts")
	fight._continue.pressed.emit()
	check(shop.visit == 8 and fight.phase == GuildrunEncounter.Phase.SHOP, "Eighth shop missing")
	check(not shop.relics.has(5103) and not shop.relics.has(5108), "Monster burn curse exceeded one encounter")
	reached_shops += 1
	print("eighth stage=", eighth_room, " event=", road.selected_event, " reward=", option.value, " shop=", shop.visit)
