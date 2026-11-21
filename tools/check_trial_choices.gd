extends SceneTree

const EVENTS := [1032, 1033, 1034, 1035]
const TITLES := ["试炼：单挑", "试炼：持久战", "试炼：歼灭战", "试炼：再战"]
const EVENT_CONTENT := "Canvas/Root/EventUIController/EventContentPanel"
const EVENT_IMAGE := "Canvas/Root/EventImagePanel/EventImage/UnityImage"
const OPTIONS := EVENT_CONTENT + "/ScrollView/Viewport/ChoicesHolder"

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	TranslationServer.set_locale("zh_CN")
	root.size = Vector2i(1280, 720)
	var stage = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	if fight.first_shop == null:
		fight._create_party()
	var shop := fight.first_shop
	stage._trial_roads = {3: 34, 9: 36}
	for i in EVENTS.size():
		var event_id: int = EVENTS[i]
		check(stage.load_board(101001 if event_id == 1035 else 10301), "Load trial predecessor board")
		stage.last_miniboss_group = "Hydra"
		var road: GuildrunFirstCrossroads = null
		for seed_value in 16:
			road = load("res://UI/first_crossroads.tscn").instantiate()
			road._rng.seed = seed_value
			root.add_child(road)
			road.setup(shop.roster, shop)
			if road.offers.has(event_id):
				break
			road.free()
			road = null
		if not check(road != null, "Trial event %d appears under fixed seeds" % event_id):
			continue
		var stage_id: int = stage.trial_map(event_id)
		var icons: Array[Texture2D] = []
		for index in road.offers.size():
			icons.append(road.path_icon(index))
		stage.set_crossroads_gate_icons(icons)
		var hit_rects: Array[Rect2] = stage.crossroads_gate_screen_rects()
		var title_rects: Array[Rect2] = stage.crossroads_gate_label_rects()
		hit_rects.resize(road.offers.size())
		title_rects.resize(road.offers.size())
		road.use_world_gates(hit_rects, title_rects)
		var view: Control = road.get_child(-1)
		var gates: Control = view.get_node("WorldGateTargets")
		var gate: Button = gates.get_child(road.offers.find(event_id))
		check(gates.visible and not view.get_child(0).visible, "World-only path presentation")
		check(road.path_icon(road.offers.find(event_id)).resource_path == "res://sprites/sharedassets3_495.png", "Original default gate icon")
		await click(gate)
		check(road.selected_event == event_id and not gates.visible, "World click chooses the event and hides gates")
		var event_view: Control = view.get_child(1)
		var title: Label = event_view.get_node(EVENT_CONTENT + "/EventNameText/UnityText")
		check(title.text == TITLES[i], "Localized event title %d" % event_id)
		var artwork: TextureRect = event_view.get_node(EVENT_IMAGE)
		check(artwork.texture.resource_path == ("res://sprites/sharedassets1_3721.png" if i == 0 else "res://sprites/sharedassets4_15.png"),
				"Original event artwork with prefab default")
		if event_id == 1035:
			var description: Label = event_view.get_node(EVENT_CONTENT + "/EventDescriptionText/UnityText")
			check("恶魔" in description.text and stage_id == 50402, "Opposite miniboss and its localized name")
		var choices: Control = event_view.get_node(OPTIONS)
		check(road.choices.size() == 3, "Three eligible reward choices")
		var option: Button = choices.get_child(3).get_node("Button/InputButton")
		var wallet := shop.shards
		var relics := shop.relics.duplicate()
		await click(option)
		check(road.pending_trial.get("stage_id") == stage_id and road.pending_trial.get("modifier") == 5500 + i * 3,
				"Selection queues the chosen stage and modifier")
		check(shop.shards == wallet and shop.relics == relics, "Rewards stay pending")
		var departed := [false]
		road.departed.connect(func(): departed[0] = true)
		var proceed: Button = event_view.get_node("Canvas/Root/EventUIController/PrimaryButton/InputButton")
		await click(proceed)
		check(departed[0], "Translated Continue departs")
		road.free()
	var builder = load("res://battle/forest_trial.gd")
	var pools: Dictionary = builder.road(36).pools
	for pair: Array in pools.relic:
		shop.relics.append(int(pair[0]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	check(builder.generate(1035, pools, shop, rng).is_empty(), "No rematch choice with exhausted relic pool")
	var choices: Array = builder.generate(1032, pools, shop, rng)
	check(choices.size() == 2 and choices[0].modifier == 5500 and choices[1].modifier == 5502,
			"Duel skips unavailable relic while preserving shards then item order")
	var locked_item: Array = pools.item.filter(func(pair: Array): return int(pair[2]) > 0)[0]
	var one_item := {"relic": [], "item": [locked_item]}
	shop.opening_xp = int(locked_item[2]) - 1
	check(builder.generate(1032, one_item, shop, rng).size() == 1, "Epic reward stays locked below its XP threshold")
	shop.opening_xp += 1
	var unlocked: Array = builder.generate(1032, one_item, shop, rng)
	check(unlocked.size() == 2 and unlocked[1].value == int(locked_item[0]), "Epic reward becomes eligible at its XP threshold")
	stage.free()
	print("TRIAL_CHOICES four localized events, original/default art, world/choice/continue clicks and exhausted pool")
	quit(1 if failed else 0)


func click(button: Button) -> void:
	await process_frame
	var click_event := InputEventMouseButton.new()
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.position = button.get_global_transform_with_canvas() * (button.size / 2.0)
	click_event.global_position = click_event.position
	click_event.pressed = true
	root.push_input(click_event)
	click_event.pressed = false
	root.push_input(click_event)
	await process_frame


func check(condition: bool, message: String) -> bool:
	if not condition:
		failed = true
		push_error(message)
	return condition
