extends SceneTree

const EXPECTED := {
	4: ["Hero_24", "Hero_13", "Hero_26", "Item_119", "Item_104", "Relic_1003"],
	26: ["Hero_3", "Hero_27", "Hero_14", "Item_101", "Item_114", "Relic_1000"],
	14: ["Hero_17", "Hero_6", "Hero_26", "Item_114", "Item_101", "Relic_1006"]
}

func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var scene: PackedScene = load("res://battle/stage.tscn")
	for id: int in EXPECTED:
		var stage = scene.instantiate()
		root.add_child(stage)
		var fight: GuildrunEncounter = stage.encounter
		fight.select_hero(id)
		fight.start_fight()
		for frame in 3600:
			if fight.phase != GuildrunEncounter.Phase.FIGHT:
				break
			fight._physics_process(1.0 / 60.0)
		var shop := fight.first_shop
		if shop == null or shop.shards != 15 or shop.battle_reward != 15 or shop.survival_reward != 0:
			push_error("Wrong first fight rewards")
			quit(1)
			return
		fight._continue.pressed.emit()
		fight.open_first_shop()
		if fight.phase != GuildrunEncounter.Phase.SHOP or shop.shards != 30 or shop.stock != EXPECTED[id]:
			push_error("Wrong balance or stock for starter %d" % id)
			quit(1)
			return
		var button: Button = shop._buttons[0]
		button.pressed.emit()
		if shop.shards != 15 or shop.roster.size() != 2 or shop.buy(0):
			push_error("Hero buy or repeated purchase mismatch")
			quit(1)
			return
		if not shop.buy(3) or not shop.buy(5) or shop.shards != 0 or shop.items.size() != 1 or shop.relics.size() != 1:
			push_error("Item/relic buy mismatch")
			quit(1)
			return
		if shop.buy(4) or shop.shards != 0 or not (shop._buttons[4] as Button).disabled:
			push_error("Unaffordable transaction changed state")
			quit(1)
			return
		print("starter=", id, " stock=", shop.stock, " final shards=", shop.shards)
		shop._leave.pressed.emit()
		if fight.phase != GuildrunEncounter.Phase.CROSSROADS or shop.buy(1):
			push_error("Departure did not close the shop")
			quit(1)
			return
		var crossroads := fight.crossroads
		var path_button := crossroads.get_node("Body/Paths").get_child(0) as Button
		path_button.pressed.emit()
		if fight.phase != GuildrunEncounter.Phase.EVENT or crossroads.selected_event != 809:
			push_error("Wrong first crossroads event")
			quit(1)
			return
		crossroads.claim()
		crossroads.claim()
		if shop.shards != 5:
			push_error("Shard event did not award exactly five shards")
			quit(1)
			return
		stage.free()
	quit()
