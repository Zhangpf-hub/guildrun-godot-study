extends "check_fourth_shop_events.gd"


func verify() -> void:
	stage = load("res://battle/stage.tscn").instantiate()
	stage.stage_id = 10000
	root.add_child(stage)
	stage._trial_roads.clear()
	stage.encounter.class_play_counts = {7: 18, 6: 10, 5: 7, 1: 1}
	var event_ids := [1018, 1019, 1027, 1028, 1014, 1024, 1025, 1026, 1001, 1017, 1022, 1023]
	for id: int in event_ids:
		var road := fixture(id, 31, 7)
		inspect(road, road.choices)
		check(road._data.paths[0].size() == event_ids.size(), "Seventh road pool size")
		for entry: Array in road._data.paths[0]:
			check(event_ids.has(int(entry[0])) and int(entry[1]) == (30 if int(entry[0]) in event_ids.slice(0, 4) else 10), "Unexpected event weight")
		match id:
			1017:
				check(road.choices[0].choice == 2 and not road.choices[0].has("effect") and road.choices[1].effect == 5103 and road.choices[2].effect == 5108, "Sleeping Monster risks")
			1022:
				check(road.choices.size() == 3 and road.choices[0].value in [633, 634] and road.choices[1].value in [318, 319], "Class rewards should follow use history")
				road._party.relics.assign([633, 634])
				var builder = load("res://battle/fourth_shop_events.gd").new()
				builder.generate(id, road._data.pools, road._party, road._rng)
				check(builder.options.size() == 2 and builder.options[0].kind == "item", "Owned relic should suppress only its choice")
			1023:
				check(road.choices.map(func(o): return o.value) == [302, 303, 307], "Delivery should use deployed class history")
			1024:
				var original_spec: Dictionary = road._party.specializations[4]
				var requests: Array[Dictionary] = []
				road._party.rank_modifier_choice_requested.connect(func(hero: int, rank: int, offers: Array[int]):
					requests.append({"hero": hero, "rank": rank, "offers": offers}))
				var departures: Array[bool] = []
				road.departed.connect(func(): departures.append(true))
				road.choose_reward(0)
				road._choose_hero(4)
				var proceed: Button = road.get_node("Body/Event/Content/Continue")
				check(road.claimed and road._party.hero_ranks[4] == 2 and proceed.disabled, "Meditation waits at B until picking an A modifier")
				check(requests.size() == 1 and requests[0].hero == 4 and requests[0].rank == 3, "Meditation launches the shared A picker")
				check(road._party.event_durations.get(5112) == 2 and road._party.relics.has(5112),
					"Meditation activates the two-fight penalty")
				for hero: int in [4, 24]:
					var base_stats: Dictionary = stage.hero_stats(hero, [], [], [])
					var penalized: Dictionary = stage.hero_stats(hero, [], [], road._party.relics)
					for key: String in ["<Attack>k__BackingField", "<MaxHealth>k__BackingField"]:
						check(int(penalized[key]) == roundi(int(base_stats[key]) * 0.8), "Meditation reduces each hero's base stats by 20%")
				proceed.pressed.emit()
				check(departures.is_empty(), "Pending RankModifier prevents event departure")
				check(road._party.choose_rank_modifier(0), "Accept an offered A modifier")
				check(road._party.hero_ranks[4] == 3 and road._party.specializations[4] == original_spec
					and road._party.rank_modifiers_for(4).has(3), "Promote B with its specialization and chosen modifier")
				check(not proceed.disabled, "Accepting a modifier enables the event Continue button")
				proceed.pressed.emit()
				check(departures.size() == 1, "Completed meditation can leave exactly once")
				road._party.advance_event_rewards()
				check(road._party.event_durations.get(5112) == 1 and road._party.relics.has(5112), "Penalty persists for the second fight")
				road._party.advance_event_rewards()
				check(not road._party.relics.has(5112), "Penalty expires after the second fight")
			1026:
				road.choose_reward(0)
				check(road._party.event_durations[5113] == 5, "Puppy should wait five combats in chunk two")
		road.free()
	var meditation := fixture(1024, 31, 7)
	meditation.choose_reward(0)
	meditation._choose_hero(24)
	var specialization_picker: Control = meditation._party._rank_picker
	check(is_instance_valid(specialization_picker) and specialization_picker.get_parent() == meditation
		and meditation._party.hero_ranks[24] == 1, "C awaits its usual specialization above the event")
	var options: Array = load("res://battle/hero_rank.gd").choices(24)
	specialization_picker.chosen.emit(1)
	check(meditation._party.hero_ranks[24] == 2 and meditation._party.specializations[24] == options[1]
		and meditation._party.rank_modifiers_for(24).is_empty(), "C→B accepts the actual specialization choice signal")
	specialization_picker.dismissed.emit()
	check(not meditation.get_node("Body/Event/Content/Continue").disabled, "B result leaves event Continue enabled")
	meditation.free()
	check_event_picker_overlay()
	for pair: Array in fixture_tenth_pool():
		var id := int(pair[0])
		if int(pair[1]) == 0:
			check(id == 1027, "Unexpected zero-weight event")
			continue
		var road := fixture(id, 31, 10)
		inspect(road, road.choices)
		check(int(road._data.id) == 32 and int(road._data.remaining_victories) == 2, "Tenth road weights or chunk horizon")
		road.free()
	for profession in range(1, 8):
		stage.encounter.class_play_counts = {profession: 10}
		var banner := fixture(1013, 31, 9)
		check(banner.choices.size() == 3 and int(banner._data.pools.reward_count) == 3, "Three guild designs")
		var seen := {}
		for child: Dictionary in banner.choices[0].children:
			check(banner._data.pools.banners[str(profession)].has(float(child.value)) and not seen.has(child.value), "Banner reward outside chosen profession or duplicated")
			seen[child.value] = true
		check(seen.size() == 3, "Expected three individual banners")
		banner.free()
	stage.free()
	print("SEVENTH_SHOP_EVENTS all 12, class history, rank limits, expiry and burn risks")
	quit(1 if failed else 0)


func check_event_picker_overlay() -> void:
	var fight: GuildrunEncounter = stage.encounter
	fight._create_party()
	var party := fight.first_shop
	party.visit = 7
	party.roster.assign([4])
	party.hero_ranks[4] = 2
	party.specializations[4] = load("res://battle/hero_rank.gd").choices(4)[0]
	var event: GuildrunFirstCrossroads = load("res://UI/first_crossroads.tscn").instantiate()
	fight._ui.add_child(event)
	event.setup(party.roster, party)
	event.offers[0] = 1024
	event.select_path(0)
	event.choose_reward(0)
	event._choose_hero(4)
	var picker: Control = fight._ui.get_node_or_null("RankModifierPicker")
	check(is_instance_valid(picker) and picker.visible and picker.get_index() > event.get_index(),
		"Encounter shows the actual A picker above the crossroads event")
	if not is_instance_valid(picker):
		return
	var choice := picker.find_child("RankChoice0", true, false) as Button
	check(is_instance_valid(choice), "Real picker exposes its first choice")
	if is_instance_valid(choice):
		choice.pressed.emit()
		check(party.hero_ranks[4] == 3 and party.rank_modifiers_for(4).has(3),
			"The actual picker choice commits the event promotion")
	picker.free()
	event.free()


func fixture_tenth_pool() -> Array:
	var road := fixture(1001, 31, 10)
	var pool: Array = road._data.paths[0]
	road.free()
	return pool
