extends SceneTree

const Opening = preload("res://battle/opening_draft.gd")
const Rules = preload("res://battle/difficulty_rules.gd")
var failed := false


func _initialize() -> void:
	run_checks.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failed = true


func run_checks() -> void:
	var path := "user://opening-test-%d.cfg" % OS.get_process_id()
	var progress := ConfigFile.new()
	check(not Opening.past_tutorial(progress), "Fresh profile should play the tutorial")
	check_tutorial_checkpoint(path)
	check(Opening.past_tutorial(Rules.read_progress(path)), "Third shop checkpoint is saved")
	var encountered := {}
	var draft := Opening.new()
	draft._rng.seed = 17
	for iteration in 150:
		draft.start(path)
		var ids := {}
		for hero in draft.choices:
			ids[hero.id] = true
			encountered[hero.id] = true
			check(not hero.has("relic") and ResourceLoader.exists(hero.portrait), "Unfunded opening hero")
		check(ids.size() == 3 and not draft.roll(), "Three distinct heroes and guarded reroll")
	check(encountered.size() == 22, "Fresh profile's eligible starter pool")
	var kit_rng := RandomNumberGenerator.new()
	kit_rng.seed = 73
	var kit_ids := {}
	var roster: Array[int] = [4, 26, 14]
	for iteration in 320:
		var kits := Opening.kit_choices(roster, kit_rng)
		check(kits.size() == 3, "One choice per kit category")
		for option: Dictionary in kits:
			kit_ids[option.value] = true
			if option.has("children"):
				check(option.children.size() == roster.size(), "Instant training offers each owned hero")
	check(kit_ids.size() == 33, "Every starter kit relic reached")
	check(Opening.finish_run(path, 4, 1, false, 0) == 60, "Three paid encounters plus a chunk")
	Opening.reached_boss(path)
	check(Rules.read_progress(path).get_value("opening", "tokens") == 0, "Locked token slots")
	Opening.finish_run(path, 40, 0, false, 0)
	check(Rules.read_progress(path).get_value("opening", "tokens") == 1, "First slot includes a token at 450 XP")
	Opening.finish_run(path, 61, 0, false, 0)
	check(Opening.token_cap(1050) == 2 and Opening.token_cap(1650) == 4, "Native token caps")
	draft.start(path)
	check(draft.tokens == 1 and draft.choices.all(func(c: Dictionary): return c.has("relic")), "Initial bundle consumes one token")
	check(draft.roll() and draft.tokens == 0 and not draft.roll(), "Paid reroll and exhaustion")
	for choice in draft.choices:
		check(ResourceLoader.exists(choice.relic_icon), "Relic artwork")
	var stage = load("res://battle/stage.tscn").instantiate()
	stage.contract_progress_path = path
	stage.track_contract_progress = true
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	var turtle: GuildrunBoardUnit = fight._units[0]
	var base_hp := turtle.max_health
	check(stage.normal_opening and fight._choices.get_child_count() == 3, "Regular initial selection from saved checkpoint")
	fight._choices.get_child(0).pressed.emit()
	var shop := fight.first_shop
	check(fight.phase == GuildrunEncounter.Phase.PLACE and turtle.max_health == base_hp and shop.shards == 15, "Regular turtle and party")
	var chosen := int(fight._hero.stat("Id")._sequentialId)
	check(shop.roster == [chosen] and shop.relics.is_empty(), "Only selected hero joins")
	for floor_index in 2:
		fight.start_fight()
		for enemy in fight._units:
			if not enemy.is_hero:
				enemy.take_damage(enemy.max_health * 2)
		fight._step_battle(2184)
		check(fight.phase == GuildrunEncounter.Phase.RESULT, "Controlled victory on floor %d" % floor_index)
		var bounds: Dictionary = stage.field(stage.field(stage.stage, "StageRewards"), "GoldRewardRange")
		check(shop.battle_reward >= int(bounds.FromInclusive) and shop.battle_reward <= int(bounds.ToInclusive), "Native floor reward")
		fight.open_first_shop()
		check(shop.visit == floor_index + 1 and shop.regular_stock and shop.stock.size() == 6 and shop.sale_index >= 0, "Regular shop from first visit")
		if floor_index == 0:
			check(shop.reroll(), "First visit permits a paid reroll")
			shop.toggle_freeze()
			shop.leave()
			check(fight.crossroads.offers == [506], "Returning players receive the guild starter kit at crossroads 23")
			fight.crossroads.select_path(0)
			check(fight.crossroads.choices.size() == 3, "Three starter kit categories")
			fight.crossroads.choose_reward(0)
			check(shop.kit_id in [720, 723, 724], "Selected shard kit reaches the party")
			fight.crossroads.departed.emit()
	check_bonuses(stage)
	check_kit_effects(stage)
	stage.free()
	check_paid_pick(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Opening: fresh and returning profile, 22 starters, unlock XP, token cap, reroll, turtle and first two shops")
	quit(1 if failed else 0)


func win(fight: GuildrunEncounter) -> void:
	fight.start_fight()
	for enemy in fight._units:
		if not enemy.is_hero:
			enemy.take_damage(enemy.max_health * 2)
	fight._step_battle(2184)


func check_tutorial_checkpoint(path: String) -> void:
	var stage = load("res://battle/stage.tscn").instantiate()
	stage.track_contract_progress = true
	stage.contract_progress_path = path
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	check(not stage.normal_opening, "New campaign uses the tutorial")
	fight.select_hero(4)
	for visit in range(1, 4):
		win(fight)
		fight.open_first_shop()
		if visit == 3:
			check(not Opening.past_tutorial(Rules.read_progress(path)), "Tutorial checkpoint before third departure")
		fight.first_shop.leave()
		if visit < 3:
			var road := fight.crossroads
			if visit == 2:
				# Choose a real second-floor event with a one-click reward.
				road.offers[0] = 1025
			road.select_path(0)
			if visit == 1:
				check(road._data.id == 120, "First tutorial crossroads")
				road.claim()
			else:
				road.choose_reward(0)
			road.departed.emit()
	stage.free()


func check_paid_pick(path: String) -> void:
	Opening.reached_boss(path)
	var stage = load("res://battle/stage.tscn").instantiate()
	stage.track_contract_progress = true
	stage.contract_progress_path = path
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	check(fight._choices.get_child_count() == 4, "Funded campaign includes reroll button")
	fight._choices.get_child(3).pressed.emit()
	check(fight._draft.tokens == 0 and fight._choices.get_child_count() == 3, "Reroll repaints the three cards")
	var row: Dictionary = fight._choice_rows[0]
	# Keep the drawn hero and exercise the rank-up card's interactive follow-up.
	row.relic = 6013
	row.relic_icon = Opening.data().pools.relic.filter(func(r: Dictionary): return int(r.id) == 6013)[0].icon
	fight._draw_choices()
	fight._choices.get_child(0).pressed.emit()
	var party := fight.first_shop
	check(party.choose_specialization(0), "Choose a B-rank specialization before the first battle")
	party._rank_picker.dismissed.emit()
	check(fight.phase == GuildrunEncounter.Phase.PLACE and fight._hero.rank == 2 and party.shards == 5, "Rank-up card reaches deployment")
	stage.free()


func check_bonuses(stage: Node3D) -> void:
	for row: Dictionary in Opening.data().pools.relic:
		var id := int(row.id)
		var party := GuildrunFirstShop.new()
		party.battle_stage = stage
		stage.add_child(party)
		var original_limit: int = stage.max_deployed
		party.start_normal(4, id, 1050)
		check(party.relics.has(id), "Starter relic %d belongs to the party" % id)
		if id >= 6018 and id <= 6038:
			check(party.items.size() == 1 and stage.items.has(party.items[0]), "Item starter reward %d" % id)
		match id:
			6001: check(party.items.size() == 1 and party.relics.size() == 2 and party.shards == 18, "Starter Bundle")
			6002, 1029:
				var wins := 6 if id == 6002 else 3
				var empty: Array[GuildrunBoardUnit] = []
				for n in wins + 1:
					party.settle_combat(empty, true)
				check(party.shards == (55 if id == 6002 else 40), "Victory quest settles only once")
			6003: check(party.shards == 27, "Immediate shard grant")
			6004: check(party.items.size() == 3, "Three common items")
			6005: check(party.relics.size() == 2, "Rare relic")
			6006: check(party.items.size() == 2, "Two class glyphs")
			6007:
				for special: bool in [false, true]:
					party.prepare_third(15, 1, special)
					party.claim_and_open()
					check(party.stock.size() == (11 if special else 7) and party._buttons.size() == party.stock.size(), "Extra relic has a shop button")
			6009:
				party.prepare_third(15, 2)
				check(party.survival_reward == 6, "Two survivors receive six shards")
			6010: check(party.shards == 60, "Rewind trade gives 45 shards")
			6012: check(stage.max_deployed == 4, "Extra deployed hero")
			6013: check(party.shards == 5, "Rank-up starting price")
			6014: check(int(stage.hero_stats(4, [], [], [6014])["<OmniVamp>k__BackingField"]) == 10, "Opening omnivamp")
			6016: check(stage.max_deployed == 2, "Extra equipment slot trade")
		stage.max_deployed = original_limit
		party.free()


func check_kit_effects(stage: Node3D) -> void:
	var fight: GuildrunEncounter = stage.encounter
	var prior_party := fight.first_shop
	var data := Opening.data()
	var groups: Array = [data.kit.shards] + data.kit.items + data.kit.stats
	var hero_id := int(fight._hero.stat("Id")._sequentialId)
	for group: Array in groups:
		for raw: float in group:
			var id := int(raw)
			var party := GuildrunFirstShop.new()
			party.battle_stage = stage
			stage.add_child(party)
			party.start_normal(hero_id, 0, 0)
			fight.first_shop = party
			party.visit = 1
			party.take_starter_kit(id, hero_id)
			var amount: Dictionary = data.descriptions[str(id)].Description
			check(party.kit_id == id and party.relics.has(id), "Kit grant %d" % id)
			if id >= 725 and id <= 731:
				check(party.items.size() == 1 and stage.items.has(party.items[0]), "Rare item kit %d" % id)
			elif id >= 736 and id <= 742:
				var stat := int(data.kit.stat_types[id - 736])
				check(party.kit_hero_stats[hero_id][stat] == int(amount["0"]), "Permanent stat kit %d" % id)
			elif id >= 757 and id <= 763:
				var keeper: GuildrunBoardUnit = fight._hero
				var stat := int(data.kit.stat_types[id - 757])
				party.kit_growth(keeper)
				party.visit = 2
				party.kit_growth(keeper)
				party.visit = 3
				party.kit_growth(keeper)
				check(party.kit_hero_stats[hero_id][stat] == 2 * int(amount["2"]), "Growth lasts the two prescribed combats")
			elif id in [764, 777, 778, 779, 780, 781, 782]:
				var stat: int = data.kit.stat_types[data.kit.stats[2].find(raw)]
				var key := "<%s>k__BackingField" % GuildrunBoardUnit.STAT_NAMES[stat]
				var boosted := int(stage.hero_stats(hero_id, [], [], party.relics)[key])
				party.enter_kit_floor(12, true)
				check(boosted - int(stage.hero_stats(hero_id, [], [], party.relics)[key]) == int(amount["0"]), "Sustained stat expires at the dragon")
			elif id == 720:
				check(party.shards == 22, "Instant kit adds seven shards")
			elif id in [723, 724, 734, 771]:
				party.prepare_third(0, 2)
				if id in [723, 724]:
					check(party.survival_reward == (8 if id == 723 else 6), "Survivors receive the selected kit")
				elif id == 734:
					party.sale_index = -1
					check(party.price_at(3) == int(party._data.catalog[party.stock[3]].price) - 2, "Temporary item discount")
				else:
					party.items.assign([101, 102, 103, 104, 105, 106])
					for n in int(stage.base_equipment_limit):
						party.equipped_to[n] = hero_id
					check(party.can_assign(int(stage.base_equipment_limit), hero_id, int(stage.base_equipment_limit)), "Extra equipment slot")
				party.enter_kit_floor(4, false)
				check((party.kit_id == 0) == (id in [723, 734]), "Temporary kit expires before fourth combat")
				party.enter_kit_floor(12, true)
				check(party.kit_id == 0, "Sustained kit expires before dragon")
			fight.first_shop = prior_party
			party.free()
