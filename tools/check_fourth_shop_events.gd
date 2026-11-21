extends SceneTree

var failed := false
var stage: Node


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failed = true


func fixture(id: int, key := 31, visit := 4) -> GuildrunFirstCrossroads:
	var shop := GuildrunFirstShop.new()
	shop.battle_stage = stage
	shop.visit = visit
	shop.roster.assign([4, 24, 13])
	shop.hero_ranks = {4: 2, 24: 1, 13: 1}
	shop.specializations[4] = preload("res://battle/hero_rank.gd").choices(4)[0]
	var road: GuildrunFirstCrossroads = load("res://UI/first_crossroads.tscn").instantiate()
	root.add_child(road)
	road.add_child(shop)
	road._rng.seed = key
	road.setup(shop.roster, shop)
	road.offers[0] = id
	road.select_path(0)
	return road


func inspect(road: GuildrunFirstCrossroads, options: Array) -> void:
	check(not options.is_empty(), "Empty event step %d" % road.selected_event)
	for o: Dictionary in options:
		var caption := road._choice_text(o, false)
		check(not caption.is_empty() and not caption.contains("{") and not caption.begins_with("Events."),
				"Unresolved UI text %d %s" % [road.selected_event, caption])
		for key: String in ["children", "after"]:
			if o.has(key):
				inspect(road, o[key])


func verify() -> void:
	stage = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	stage._trial_roads.clear()
	for id: int in [1014, 1024, 1025, 1026, 1018, 1019, 1027, 1028, 1006, 1029, 1030]:
		var road := fixture(id)
		inspect(road, road.choices)
		road.free()
	var nest := fixture(1018)
	nest.choose_reward(0)
	var id := int(nest.choices[0].value)
	nest.choose_reward(0)
	check(nest.claimed and not nest._party.relics.has(id) and nest._party.event_durations.has(5124), "Nest starts its timer")
	nest._party.advance_event_rewards()
	check(nest._party.relics.has(id) and not nest._party.relics.has(5124), "Nest delivers after winning")
	nest.free()
	var puppy := fixture(1026)
	puppy.choose_reward(0)
	puppy._party.advance_event_rewards()
	check(puppy._party.shards == 0 and puppy._party.relics.has(5113), "Puppy waits until chunk end")
	puppy._party.advance_event_rewards()
	check(puppy._party.shards == 25 and not puppy._party.relics.has(5113), "Puppy awards shards on effect removal")
	var loss := fixture(1026)
	loss.choose_reward(0)
	loss._party.advance_event_rewards()
	loss._party.advance_event_rewards(false)
	check(loss._party.shards == 25 and not loss._party.relics.has(5113), "Puppy payout follows expiry even after a protected loss")
	loss.free()
	puppy.free()
	var fruits := fixture(1019)
	fruits.choose_reward(2)
	fruits._party.advance_event_rewards()
	check(fruits._party.event_durations[5128] == 1 and not fruits._party.relics.has(799), "Yellow fruit second stun")
	fruits._party.advance_event_rewards()
	var enhanced: Dictionary = stage.hero_stats(4, [], [], fruits._party.relics)
	check(enhanced["<MaxHealth>k__BackingField"] == stage._heroes[4]["<MaxHealth>k__BackingField"] + 500, "Permanent fruit HP reward")
	fruits.free()
	var curse := fixture(1006)
	curse.choose_reward(1)
	curse.choose_reward(1)
	check(curse.claimed and curse._party.hero_modifiers.keys() == [24], "Curse applies only to selected hero")
	curse.free()
	var divide := fixture(1027)
	divide.choose_reward(1)
	check(divide._party.combat_shards(30) == 40, "Two-victory shard bonus starts")
	divide._party.advance_event_rewards()
	check(divide._party.combat_shards(30) == 40, "Two-victory shard bonus persists")
	divide._party.advance_event_rewards()
	check(divide._party.combat_shards(30) == 30, "Two-victory shard bonus ends")
	divide.free()
	var fairy := fixture(1028)
	fairy.choose_reward(2)
	check(fairy._party.combat_shards(30) == 0 and fairy._party.relics.has(5119), "Fairy Ring suppresses victory shards")
	fairy.free()
	var debt := fixture(1030)
	for tier in 3:
		debt.choose_reward(0)
		check(debt.choices.size() == 3, "Three available relics at each debt tier")
		debt.choose_reward(0)
	check(debt.claimed and debt._party.combat_shards(50) == 15 and debt._party.relics.has(798), "Three debts stack before victory")
	debt._party.advance_event_rewards()
	check(debt._party.combat_shards(50) == 50 and debt._party.relics.has(798), "Permanent debt remains after payout")
	debt.free()
	var results := {}
	for key in 160:
		var well := fixture(1029, key)
		well.choose_reward(0)
		while well.choices.back().get("key", "").begins_with("Drink"):
			well.choose_reward(well.choices.size() - 1)
		var result: String = well.choices[0].key
		results[result] = true
		well.choose_reward(0)
		if not well.claimed and result in ["BadOutcome", "BadOutcome_1"]:
			well.choose_reward(0)
		if not well.claimed and well.choices[0].kind == "well_rank":
			var target := int(well.choices[0].hero)
			well._choose_specialization(preload("res://battle/hero_rank.gd").choices(target)[0])
		check(well.claimed, "Well ended without reward")
		well.free()
	for key in ["TakeStatL3", "TakeItemL3", "TakeRelicL3", "TakeShardsL3_Hero", "BadOutcome_2"]:
		check(results.has(key), "Well outcome missing: " + key)
	stage.free()
	print("FOURTH_SHOP_EVENTS 11 authored encounters, well outcomes=", results.size())
	quit(1 if failed else 0)
