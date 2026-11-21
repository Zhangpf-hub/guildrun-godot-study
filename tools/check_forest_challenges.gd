extends "check_seventh_battle.gd"

var ninth_room := 0
var tenth_rooms: Dictionary = {}
var eleventh_rooms: Dictionary = {}
var bosses: Dictionary = {}


func verify() -> void:
	for i in [0, 1]:
		seventh_room = 10701 + i
		eighth_room = 10801 + i
		ninth_room = 10901 + i
		run_variant(i)
	for i in 11:
		ninth_room = 10901 + i
		var stage := late_party()
		play_late_chunk(stage)
		stage.free()
	check(reached_shops == 2 and tenth_rooms.size() == 11 and eleventh_rooms.size() == 8, "Second forest chunk coverage")
	check(bosses.size() == 3, "All three dragon rooms should be reachable from camp")
	print("Forest prepared-party encounters: ninth=11 tenth=", tenth_rooms.size(), " eleventh=", eleventh_rooms.size())
	quit(1 if failed else 0)


func verify_eighth(stage: Node) -> void:
	super.verify_eighth(stage)
	play_late_chunk(stage)


func late_party() -> Node:
	# A separate late-game party fixture exercises every layout without depending on early shop RNG.
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	stage._trial_roads.clear()
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(26)
	resolve(fight)
	fight.open_first_shop()
	var shop := fight.first_shop
	for bar: Control in fight._bars.values():
		bar.free()
	fight._bars.clear()
	fight._units.clear()
	stage.load_board(10801)
	fight._grid = stage.grid
	for enemy: GuildrunBoardUnit in stage.grid.occupants.values():
		fight._register(enemy)
	shop.roster.assign([26, 14, 13])
	shop.hero_ranks = {26: 4, 14: 4, 13: 4}
	var rank = load("res://battle/hero_rank.gd")
	shop.specializations = {26: rank.choices(26)[0], 14: rank.choices(14)[1], 13: rank.choices(13)[0]}
	shop.items.assign([703, 703, 702, 702, 706, 706, 707, 706, 701, 701, 701, 704])
	shop.equipped_to.clear()
	for i in shop.items.size():
		check(shop.assign_item(i, shop.roster[i / 4], stage.base_equipment_limit), "S rank should unlock its fourth equipment slot")
	fight._formation = {26: Vector2i(3, 3), 14: Vector2i(3, 1), 13: Vector2i(4, 1)}
	shop.visit = 7
	shop.prepare_third(30, 3, false)
	shop.claim_and_open()
	return stage


func play_late_chunk(stage: Node) -> void:
	var fight: GuildrunEncounter = stage.encounter
	var shop := fight.first_shop
	stock_up(shop, stage)
	shop._leave.pressed.emit()
	var challenge = fight.crossroads
	check(challenge.offers.size() == 2 and int(challenge.offers[1]) in range(5011, 5016), "Second enemy relic pool")
	var path := ninth_room % 2
	next_room(stage, ninth_room)
	challenge.get_node("Body/Paths").get_child(path).pressed.emit()
	check(stage.stage_id == ninth_room and fight.phase == GuildrunEncounter.Phase.PLACE, "Ninth deployment")
	check(fight.challenge_modifier == int(challenge.offers[path]), "Ninth modifier")
	if path:
		check(challenge.rewards.size() == 3, "Three epic rewards")
		for relic: int in challenge.rewards:
			check(int(challenge._data.relics[str(relic)].rarity) == 3 and not shop.relics.has(relic), "Epic reward availability")
	resolve(fight)
	var victory := fight._units.any(func(u): return u.is_hero and not u.defeated)
	if not fight._continue.visible:
		check(not victory and not fight.rewind_available, "Unexpected ninth terminal state")
		return
	fight._continue.pressed.emit()
	if path and victory:
		check(fight.phase == GuildrunEncounter.Phase.RELIC_REWARD, "Epic reward screen")
		var actions: Node = challenge.get_node("Body/Paths")
		var pick := 3 if ninth_room % 3 == 0 else 0
		var count := shop.relics.size()
		actions.get_child(pick).pressed.emit()
		check(shop.relics.size() == count + int(pick != 3), "Skip or take epic relic")
	check(shop.visit == 9 and fight.phase == GuildrunEncounter.Phase.SHOP, "Missing ninth shop")
	stock_up(shop, stage)
	shop._leave.pressed.emit()
	var road := fight.crossroads
	check(road.offers == [1013], "Specific Guild Banner road")
	road.get_node("Body/Paths").get_child(0).pressed.emit()
	var options := road.choices.duplicate(true)
	road.choose_reward(0)
	var buttons := road.get_node("Body/Event/Content/Actions")
	buttons.get_child(-1).pressed.emit()
	check(road.choices == options and not road.claimed, "Back must preserve banner designs")
	road.choose_reward(ninth_room % options.size())
	check(road.choices.size() <= 3 and not road.choices.is_empty(), "Missing banner designs")
	var banner := int(road.choices[0].value)
	road.choose_reward(0)
	check(road.claimed and shop.relics.has(banner), "Chose banner without granting relic")
	var tenth := 101001 + ninth_room - 10901
	next_room(stage, tenth)
	road.get_node("Body/Event/Content/Continue").pressed.emit()
	check(stage.stage_id == tenth and fight.phase == GuildrunEncounter.Phase.PLACE and fight.challenge_modifier == 0, "Tenth deployment or stale modifier")
	tenth_rooms[tenth] = true
	resolve(fight)
	if not fight._continue.visible:
		check(not fight.rewind_available, "Unexpected tenth terminal state")
		return
	fight._continue.pressed.emit()
	check(shop.visit == 10, "Tenth shop")
	stock_up(shop, stage)
	shop._leave.pressed.emit()
	road = fight.crossroads
	check(int(road._data.id) == 32 and road.offers != [1027], "Tenth weighted road")
	road.offers[0] = 1017 if ninth_room % 2 else 1022
	road.select_path(0)
	road.choose_reward(0)
	var eleventh := 101101 + (ninth_room - 10901) % 8
	next_room(stage, eleventh)
	road.get_node("Body/Event/Content/Continue").pressed.emit()
	check(stage.stage_id == eleventh and fight.phase == GuildrunEncounter.Phase.PLACE, "Eleventh deployment")
	eleventh_rooms[eleventh] = true
	var had_rewind := fight.rewind_available
	var reserve := fight.rewind_reserve
	resolve(fight)
	if fight._continue.visible:
		fight._continue.pressed.emit()
		check(shop.visit == 11 and fight.phase == GuildrunEncounter.Phase.SHOP, "Eleventh shop")
		check(not fight.rewind_available and fight.rewind_reserve == 0, "Rewind remained active before the final boss")
		if had_rewind and fight._units.any(func(u): return u.is_hero and not u.defeated):
			check(shop.rewind_payout == reserve + int(stage.rewind_shards_per_win), "Unused rewind payout")
		play_boss(stage)
	print("forest stage=", ninth_room, "/", tenth, "/", eleventh, " ninth victory=", victory, " banner=", banner, " shop=", shop.visit)


func play_boss(stage: Node) -> void:
	var fight: GuildrunEncounter = stage.encounter
	var shop := fight.first_shop
	shop._leave.pressed.emit()
	var camp := fight.crossroads
	check(camp.offers == [601], "Expected second campfire")
	camp.select_path(0)
	var picks := camp.get_node("Body/Event/Content/Actions")
	check(picks.get_child_count() == 4 and camp.choices[2].kind == "effect" and camp.choices[3].kind == "leave", "Second campfire options")
	var rest := ninth_room % 2 == 0
	picks.get_child(2 if rest else 3).pressed.emit()
	check(shop.relics.has(5106) == rest, "Rest and skip should be distinct")
	var room := 101301 + (ninth_room - 10901) % 3
	next_room(stage, room)
	camp.get_node("Body/Event/Content/Continue").pressed.emit()
	check(stage.stage_id == room and fight.phase == GuildrunEncounter.Phase.PLACE and not fight.rewind_available, "Final deployment")
	bosses[room] = true
	# This fixture exercises the final blow and auction transition separately from full-health dragon fights.
	var finishing_blow := ninth_room in [10901, 10902, 10903]
	if finishing_blow:
		for unit in fight._units:
			if not unit.is_hero:
				unit.health = 1
	resolve(fight)
	check(fight.phase == GuildrunEncounter.Phase.RESULT, "Final result")
	if fight._continue.visible:
		fight._continue.pressed.emit()
		check(shop.visit == 12 and shop.super_shop and shop.stock.size() == 10 and not shop.relics.has(5106), "Final victory auction")
		shop._leave.pressed.emit()
		check(stage.stage_id == 101 and stage.endless_floor == 0 and fight.phase == GuildrunEncounter.Phase.PLACE, "Auction to endless")
	else:
		check(not finishing_blow and not fight.rewind_available, "Boss defeat incorrectly allowed a rewind or lost the finishing fixture")
		check(fight._summary_button.visible, "Missing terminal defeat action")
		fight._summary_button.pressed.emit()
		check(fight.phase == GuildrunEncounter.Phase.END_SCREEN and not fight._ui.get_node("EndScreen/Center/Summary/Scores").visible,
				"Forest defeat should show the final party")
	print("dragon stage=", room, " final-blow fixture=", finishing_blow, " shop=", shop.visit)
