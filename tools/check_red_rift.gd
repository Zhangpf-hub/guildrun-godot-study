extends SceneTree

var failed := false
var rules = load("res://battle/difficulty_rules.gd")
var rift_script = load("res://battle/red_rift.gd")


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)


func contract_menu(path: String) -> Control:
	var menu: Control = load("res://UI/contracts.tscn").instantiate()
	menu.selecting = true
	menu.progress_path = path
	root.add_child(menu)
	current_scene = menu
	menu.get_node("Panel/Options").get_child(7).pressed.emit()
	return menu


func verify() -> void:
	var path := "user://red-rift-test-%d.cfg" % OS.get_process_id()
	var save := ConfigFile.new()
	save.set_value("opening", "tutorial_checkpoint", true)
	save.set_value("forest", "highest_beaten", 5)
	save.save(path)
	var menu := contract_menu(path)
	var play: Button = menu.get_node("Panel/Actions/Play")
	check(play.disabled and menu.selected == 7, "SSS must be beaten before Red Rift unlocks")
	menu._start_game()
	check(current_scene == menu, "Locked challenge cannot start")
	menu.free()
	rules.record_win(6, path)
	menu = contract_menu(path)
	check(not menu.get_node("Panel/Actions/Play").disabled, "SSS winner can enter the challenge")
	menu.get_node("Panel/Actions/Play").pressed.emit()
	await process_frame
	await process_frame
	var stage = current_scene
	check(stage.contract_index == 6 and stage.red_rift != null and stage.stage_id == 10000,
			"Menu opens the highest contract and separate Red Rift mode")
	var fight: GuildrunEncounter = stage.encounter
	if is_instance_valid(fight._founding_comic):
		var comic := fight._founding_comic
		comic.advance()
		comic.advance()
		await comic.completed
		await process_frame
	fight._choices.get_child(0).pressed.emit()
	var shop := fight.first_shop
	var rift = stage.red_rift
	var hero := fight._hero
	var id := int(hero.get_meta("hero_id"))
	check(rift.first_run and shop.items.has(501) and rift.carrier_id(shop) == -1, "First challenge grants an unequipped seal")
	fight._process(0.0)
	fight.start_fight()
	check(fight.phase == GuildrunEncounter.Phase.PLACE and fight._fight.disabled and fight._anchor_warning.visible,
			"First normal battle requires a deployed seal holder")
	var before: int = hero.max_health
	fight._equipment_panel._select(shop.items.find(501))
	fight._equipment_panel._assign(id)
	fight._process(0.0)
	check(not fight._fight.disabled and not fight._anchor_warning.visible and hero.max_health == roundi(before * 0.75),
			"Equipping the seal via placement UI permits fighting and reduces basic stats")
	fight.start_fight()
	for enemy in fight._units:
		if not enemy.is_hero:
			enemy.take_damage(enemy.health + enemy.total_shield() + 1)
	fight._step_battle(fight.BATTLE_STEP_Q16)
	check(fight.phase == GuildrunEncounter.Phase.RESULT and rift.charges.reduce(func(a, b): return a + b, 0) == 1,
			"One combat victory yields at most one seal charge")
	fight.open_first_shop()
	check(fight.phase == GuildrunEncounter.Phase.SHOP and shop._tax_button.visible, "Original shop flow exposes the key fragment")
	check(root.get_visible_rect().encloses(shop._tax_button.get_global_rect()), "Complete key-fragment button fits within the viewport")
	check(root.get_visible_rect().encloses(shop._panel.get_node("Background").get_global_rect()), "Original shop backdrop and bottom offers remain in view below the tax button")
	var balance := shop.shards
	shop._tax_button.pressed.emit()
	check(shop.shards == balance - 10 and not shop._tax_button.visible and not shop.pay_rift_tax(),
			"First key fragment costs ten, completes its objective and cannot be bought twice")
	check(rift.tax(0, 5) == 18 and rift.tax(1, 1) == 15 and rift.tax(1, 5) == 27,
			"Each six-floor chunk has independent tax growth")
	check_rewards(stage, shop)
	check_objectives(stage, shop, hero, path)
	check_cutoff(stage, shop)
	stage.free()
	check_final_boss(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RED_RIFT locked and unlocked menu, first seal, deployment, stats, 3 class groups, taxes, death limit, terminal state and streak")
	quit(1 if failed else 0)


func check_rewards(stage: Node, shop: GuildrunFirstShop) -> void:
	var rift = stage.red_rift
	stage._trial_roads.clear()
	for visit: int in [5, 11]:
		shop.visit = visit
		var camp: GuildrunFirstCrossroads = load("res://UI/first_crossroads.tscn").instantiate()
		stage.add_child(camp)
		camp.setup(shop.roster, shop)
		camp.select_path(0)
		var actions := camp.get_node("Body/Event/Content/Actions")
		check(camp.choices.back().kind == "skip_rift_campfire", "Both campfires offer the challenge skip")
		if visit == 5:
			actions.get_child(3).pressed.emit()
			check(camp.claimed and rift.missions[1] == rift.Status.PENDING, "Taking the first campfire reward leaves a second opportunity")
		else:
			actions.get_child(2).pressed.emit()
			var warning := camp.find_children("*", "ConfirmationDialog", false, false)
			check(warning.size() == 1 and not camp.claimed, "Taking a reward at the second campfire asks for confirmation")
			if not warning.is_empty():
				warning[0].hide()
			actions.get_child(-1).pressed.emit()
			check(camp.claimed and rift.missions[1] == rift.Status.COMPLETE, "Final campfire skip completes its mission")
		camp.free()
	# The challenge panel uses floor_rules rather than the number of visits to build its reward offers.
	var original_stage: Dictionary = stage.stage
	stage.stage = stage._stages[10801]
	var challenge: Control = load("res://UI/first_crossroads.tscn").instantiate()
	challenge.set_script(load("res://battle/challenge_crossroads.gd"))
	stage.add_child(challenge)
	shop.visit = 8
	challenge.setup(shop.roster, shop)
	challenge.get_node("Body/Paths").get_child(1).pressed.emit()
	challenge.show_rewards()
	check(not challenge.rewards.is_empty(), "Final challenge fight offers real relics")
	challenge.take_relic(challenge.rewards[0])
	var warning := challenge.find_children("*", "ConfirmationDialog", false, false)
	check(warning.size() == 1 and not challenge.reward_closed, "Final challenge relic asks for confirmation")
	if not warning.is_empty():
		warning[0].hide()
	challenge.get_node("Body/Paths").get_child(-1).pressed.emit()
	check(challenge.reward_closed and rift.missions[0] == rift.Status.COMPLETE, "Skipping the post-battle relic completes its mission")
	challenge.free()
	stage.stage = original_stage


func check_cutoff(stage: Node, shop: GuildrunFirstShop) -> void:
	var fight: GuildrunEncounter = stage.encounter
	var rift = rift_script.new()
	rift.configure(rules.data().red_rift, ConfigFile.new())
	stage.red_rift = rift
	stage.track_contract_progress = false
	stage.stage = stage._stages[10401]
	shop.visit = 5
	fight.phase = GuildrunEncounter.Phase.SHOP
	fight._open_crossroads()
	check(int(stage.floor_rules().local_floor) == 4 and rift.status == rift.Status.FAILED and fight.phase == GuildrunEncounter.Phase.RESULT,
			"Leaving the fifth room of a chunk with unpaid tax ends the run")
	check(fight._summary_button.visible and not fight._continue.visible, "Failed challenge routes to summary")
	fight._summary_button.pressed.emit()
	check(fight.phase == GuildrunEncounter.Phase.END_SCREEN, "Failed challenge opens the end screen")


func check_final_boss(path: String) -> void:
	for ready_to_seal in [true, false]:
		var stage = load("res://battle/stage.tscn").instantiate()
		stage.challenge_run = true
		stage.contract_index = 6
		stage.track_contract_progress = true
		stage.contract_progress_path = path
		root.add_child(stage)
		var fight: GuildrunEncounter = stage.encounter
		fight._choices.get_child(0).pressed.emit()
		var shop := fight.first_shop
		var rift = stage.red_rift
		for mission in [0, 1, 2, 3, 5]:
			if ready_to_seal or mission != 2:
				rift.complete(mission)
		var boss_id: int = stage.contract.planned_bosses[1]
		for bar: Control in fight._bars.values():
			bar.free()
		fight._bars.clear()
		fight._units.clear()
		fight._hero = null
		check(stage.load_board(boss_id), "Load the selected SSS dragon with its actual enemy set")
		fight._grid = stage.grid
		for enemy: GuildrunBoardUnit in stage.grid.occupants.values():
			fight._register(enemy)
		var id := shop.roster[0]
		fight._deploy_owned(id, Vector2i(3, 1))
		fight.phase = GuildrunEncounter.Phase.PLACE
		fight.start_fight()
		for unit in fight._units:
			if not unit.is_hero:
				unit.take_damage(unit.health + unit.total_shield() + 1)
		fight._step_battle(fight.BATTLE_STEP_Q16)
		check(rift.status == (rift.Status.COMPLETE if ready_to_seal else rift.Status.FAILED),
				"Final dragon evaluates all unfinished challenge objectives")
		check(fight.phase == GuildrunEncounter.Phase.RESULT and fight._summary_button.visible and not fight._continue.visible,
				"Challenge final boss goes to challenge summary without auction or endless")
		var progress: ConfigFile = rules.read_progress(path)
		check(progress.get_value("forest", "wins_6") == 1 and progress.get_value("red_rift", "wins") == 2,
				"Final dragon updates challenge wins independently from SSS")
		fight._summary_button.pressed.emit()
		var floor_label: Label = fight._ui.get_node("EndScreen/Center/Summary/Floor")
		check(floor_label.text == tr("UI.RiftSealingProtocol.Victory" if ready_to_seal else "UI.RiftSealingProtocol.Defeat"),
				"End screen displays the real challenge outcome")
		stage.free()


func check_objectives(stage: Node, shop: GuildrunFirstShop, hero: GuildrunBoardUnit, path: String) -> void:
	var rift = rift_script.new()
	rift.configure(rules.data().red_rift, rules.read_progress(path))
	var units: Array[GuildrunBoardUnit] = [hero]
	hero.base_stats = hero.base_stats.duplicate()
	hero.base_stats.equipment_classes = [1, 2, 7]
	for n in 9:
		rift.finish_battle(shop, units, true, false, false)
		var completed_group: int = n / 3
		check(rift.charges[completed_group] == 1 + n % 3, "First matching unfinished class group gets the charge")
	check(not shop.items.has(501) and rift.missions[5] == rift.Status.COMPLETE, "Full charge consumes the seal")
	for mission in [0, 1, 2, 3]:
		rift.complete(mission)
	rift.finish_battle(shop, units, true, false, true)
	check(rift.status == rift.Status.COMPLETE, "All six objectives complete the challenge")
	rift.save_outcome(path, true)
	rift.save_outcome(path, true)
	var progress: ConfigFile = rules.read_progress(path)
	check(progress.get_value("red_rift", "streak") == 1 and progress.get_value("forest", "wins_6") == 1,
			"Challenge streak persists once, separate from the SSS record")
	var next = rift_script.new()
	next.configure(rules.data().red_rift, progress)
	next.give_anchor(shop, int(hero.get_meta("hero_id")))
	check(not next.first_run and next.carrier_id(shop) == int(hero.get_meta("hero_id")), "Later challenge auto-equips the starter")
	hero.defeated = true
	next.finish_battle(shop, units, false, true, false)
	check(next.deaths == 0, "Event battles are excluded from the death limit")
	for n in 9:
		next.finish_battle(shop, units, false, false, false)
	check(next.status == next.Status.PENDING, "Nine deaths permitted")
	next.finish_battle(shop, units, false, false, false)
	check(next.deaths == 10 and next.status == next.Status.FAILED, "Tenth death ends the challenge")
	next.save_outcome(path, false)
	progress = rules.read_progress(path)
	check(progress.get_value("red_rift", "streak") == 0 and progress.get_value("red_rift", "best") == 1, "Defeat resets current streak and preserves best")
	stage.red_rift = next
