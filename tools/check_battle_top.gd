extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func expect(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)


func verify() -> void:
	root.size = Vector2i(1024, 768)
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	var hud = fight._ui.get_node("BattleTop")
	var clock: Control = hud.panel.get_node(hud.CLOCK)
	var timer := clock.get_node("TimerText/UnityText") as Label
	var wallet := hud.panel.get_node("Middle/Left_Shard/CurrentGoldAmount/UnityText") as Label
	var stabilizer := hud.panel.get_node("Middle/Right_RiftStabilizer/AccumulatedShardsText/UnityText") as Label
	expect(not clock.visible and wallet.text == "15" and stabilizer.text == "10", "Selection HUD differs from the tutorial wallet and stabilizer")
	fight.select_hero(4)
	hud.refresh()
	expect(clock.visible and timer.text == "00:00", "Deploy phase must start at zero")
	var nodes: Array = hud.route.filter(func(e: Dictionary): return e.icon != "")
	expect(nodes.size() == 12 and nodes[0].icon == "fight" and nodes[1].icon == "mining", "First chunk fight/event sequence")
	expect(nodes[5].icon == "fightEvent" and nodes[9].icon == "campfire", "Challenge and campfire route icons")
	expect(nodes[10].icon == "miniBoss" and nodes[11].icon == "actBoss", "First chunk final preview")
	expect(nodes[0].image.self_modulate == Color("#56b389") and nodes[1].image.self_modulate == Color("#f3edd8"), "Current/next route colors")
	expect(nodes[10].image.self_modulate == Color("#825b5d") and nodes[11].image.self_modulate == Color("#a1a091"), "Preview must use its distinct future tint")
	expect(is_equal_approx(hud.scale.x, 1024.0 / 1920.0), "Source CanvasScaler at 1024")
	var left_before: float = hud.panel.get_global_rect().position.x
	root.size = Vector2i(1600, 900)
	await process_frame
	await process_frame
	expect(is_equal_approx(hud.scale.x, 1600.0 / 1920.0) and is_equal_approx(left_before / 1024, hud.panel.get_global_rect().position.x / 1600), "Top HUD resize shifted its reference anchor")
	fight.start_fight()
	fight.battle_time_q16 = (60 << 16) - 1
	hud.refresh()
	expect(timer.text == "00:59", "Timer rounded up before the minute boundary")
	fight.battle_time_q16 += 1
	hud.refresh()
	expect(timer.text == "01:00", "Timer minute rollover")
	fight._create_party()
	fight.first_shop.shards = 108
	fight.phase = GuildrunEncounter.Phase.CROSSROADS
	hud.refresh()
	expect(wallet.text == "108" and nodes[1].slot.get_node("CurrentMarker").visible, "Crossroads counter or current marker")
	expect(nodes[0].image.self_modulate == Color("#5b5b5b") and nodes[2].image.self_modulate == Color("#a1a091"), "Encounter/event phase colors")
	for id: int in stage._stages:
		var row: Dictionary = stage._stages[id]
		if int(stage.field(row, "ActNumber")) == 1 and int(stage.field(row, "FloorNumber")) == 6 and int(stage.field(row, "StageType")) == 1:
			stage.load_board(id)
			break
	fight.phase = GuildrunEncounter.Phase.PLACE
	hud.refresh()
	nodes = hud.route.filter(func(e: Dictionary): return e.icon != "")
	expect(hud.chunk == 1 and nodes.size() == 11 and nodes.back().icon == "actBoss", "Second chunk has six encounters and five events without preview")
	stage.free()
	if not failed:
		print("Top HUD: native templates, two chunks, phase markers, currencies, Q16 clock, resize OK")
	quit(int(failed))
