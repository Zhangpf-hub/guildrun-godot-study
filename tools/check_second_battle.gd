extends SceneTree

const FORMATION := Vector2i(2, 2)
const EXPECTED_ENEMIES := {
	10101: {Vector2i(4, 4): 102001, Vector2i(0, 7): 101901},
	10102: {Vector2i(3, 4): 102701, Vector2i(6, 7): 101902},
}


func _initialize() -> void:
	verify.call_deferred()


func resolve(fight: GuildrunEncounter) -> void:
	fight.start_fight()
	for i in 4800:
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			return
		fight._physics_process(1.0 / 30.0)


func verify() -> void:
	var seen := {}
	var starters := [4, 26, 14]
	for i in 12:
		var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
		root.add_child(stage)
		var fight: GuildrunEncounter = stage.encounter
		var starter: int = starters[i % 3]
		fight.select_hero(starter)
		fight._claim_cell(fight._hero, FORMATION)
		fight._hero.position = GuildrunBattleGrid.center(FORMATION)
		resolve(fight)
		fight.open_first_shop()
		var shop := fight.first_shop
		if not shop.buy(0) or not shop.buy(1):
			push_error("Could not recruit tutorial party")
			quit(1)
			return
		shop.leave()
		var road := fight.crossroads
		road.select_path(2)
		var training: Dictionary = road._data.events[str(road.selected_event)]
		var trained := shop.roster[1]
		road.claim(trained)
		seed(i + 1)
		road.get_node("Body/Event/Content/Continue").pressed.emit()
		if fight.phase != GuildrunEncounter.Phase.PLACE or stage.stage_id not in [10101, 10102]:
			push_error("Event did not advance to the next floor")
			quit(1)
			return
		seen[stage.stage_id] = true
		var party: Array = fight._units.filter(func(u): return u.is_hero)
		if party.size() != 3 or party[0].grid_cell != FORMATION or party[1].grid_cell != Vector2i(3, 0) or party[2].grid_cell != Vector2i(4, 0):
			push_error("Second-floor lineup mismatch")
			quit(1)
			return
		var key: String = GuildrunFirstCrossroads.STAT_KEYS[int(training.target_stat)]
		var raw: int = stage.field(stage._heroes[trained], key)
		if party[1].stat(key) != raw + (int(training.amount_q16) >> 16) or party[1].health != party[1].max_health:
			push_error("Permanent training missing or applied to base data")
			quit(1)
			return
		for cell: Vector2i in EXPECTED_ENEMIES[stage.stage_id]:
			if stage.grid.occupants[cell].get_meta("enemy_id") != EXPECTED_ENEMIES[stage.stage_id][cell]:
				push_error("Enemy does not match the selected room")
				quit(1)
				return
		resolve(fight)
		if fight.phase != GuildrunEncounter.Phase.RESULT or shop.visit != 2 or shop.battle_reward != 35:
			push_error("Second battle did not reach victory for starter %d, stage %d" % [starter, stage.stage_id])
			quit(1)
			return
		var survivors := party.filter(func(u): return not u.defeated).size()
		var combat_wallet := shop.shards
		fight._continue.pressed.emit()
		if fight.phase != GuildrunEncounter.Phase.SHOP or shop.shards != combat_wallet + 35 + 2 * survivors:
			push_error("Second shop lost currency or survivor bonus")
			quit(1)
			return
		if starter == 4 and shop.stock[1] != "Hero_18":
			push_error("Owned Dragomir did not use second-shop fallback")
			quit(1)
			return
		if not shop.buy(0) or shop.hero_ranks[starter] != 1 or shop.pending_hero != starter or shop.buy(1):
			push_error("Duplicate purchase did not wait for a specialization")
			quit(1)
			return
		if not shop.choose_specialization(1) or shop.hero_ranks[starter] != 2 or shop.roster.size() != 3 or shop.choose_specialization(0):
			push_error("Specialization did not commit the rank exactly once")
			quit(1)
			return
		print("starter=", starter, " floor=", stage.stage_id, " survivors=", survivors, " training=", key, " second shop=", shop.stock)
		stage.free()
		if i >= 2 and seen.size() == 2:
			quit(0)
			return
	push_error("Missing second-floor formation")
	quit(1)
