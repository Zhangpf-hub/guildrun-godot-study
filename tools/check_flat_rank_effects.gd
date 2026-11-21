extends SceneTree

const Phase := GuildrunEncounter.Phase
const EXPECTED := {
	13: {"AttackRange": 1, "AttackSpeed": 40},
	50: {"Attack": 100, "OmniVamp": 20},
	55: {"AttackRange": 1, "Attack": 50},
	194: {"MaxHealth": 1000, "OmniVamp": 20},
	240: {"Crit": 60, "OmniVamp": 20},
	285: {"StartingMana": 40, "ManaRegen": 8},
}
var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	fight.start_fight()
	for tick in 2400:
		if fight.phase != Phase.FIGHT:
			break
		fight._physics_process(fight.BATTLE_STEP_SECONDS)
	fight.open_first_shop()
	var shop := fight.first_shop
	if not expect(is_instance_valid(shop) and shop.buy(2) and shop.buy(3), "Buy second hero and equipment"):
		quit(1)
		return
	# A deliberate ID collision models the independent training namespace.
	stage._stat_modifiers[50] = {
		"<TargetStat>k__BackingField": 4,
		"<Value>k__BackingField": {"RawValue": 3 << 16},
	}
	shop.hero_modifiers[4] = [50]
	shop.hero_ranks[4] = 3
	shop.leave()
	fight.crossroads.select_path(0)
	fight.crossroads.claim()
	fight.crossroads.get_node("Body/Event/Content/Continue").pressed.emit()
	if not expect(fight.phase == Phase.PLACE and fight.board_hero(4) != null, "Next deployment contains starter"):
		quit(1)
		return
	var base := baseline(stage, shop)
	expect(int(fight.board_hero(4).stat("Attack")) == int(stage.field(base, "Attack")),
			"Generic training ID 50 cannot grant rank modifier 50")
	var no_training: Dictionary = stage.hero_stats(4, [], [], shop.relics, 3)
	expect(int(fight.board_hero(4).stat("Defense")) == int(stage.field(no_training, "Defense")) + 3,
			"Generic training ID 50 retains its independent defense effect")
	var unsupported_rank: Dictionary = stage.hero_stats(4, [50], [], shop.relics, 3, {}, {4: 50})
	expect(stage.field(unsupported_rank, "Attack") == stage.field(base, "Attack"),
			"An S modifier cannot apply at rank A")
	for modifier: int in EXPECTED:
		expect(shop.record_rank_modifier(4, 3, modifier), "Record selected modifier %d at A" % modifier)
		fight._refresh_deployed_stats()
		expect_delta(fight.board_hero(4), base, EXPECTED[modifier], "Modifier %d on deployed hero" % modifier)
	expect(shop.record_rank_modifier(4, 3, 55), "Set runtime A modifier")
	shop.hero_ranks[4] = 4
	expect(shop.record_rank_modifier(4, 4, 285), "Set S modifier")
	var combined := {"Attack": 50, "AttackRange": 1, "StartingMana": 40, "ManaRegen": 8}
	var panel := fight._equipment_panel
	panel.select_item(0)
	expect(panel.assign_selected_item(4), "Equip through normal panel entry point")
	base = baseline(stage, shop)
	expect_delta(fight.board_hero(4), base, combined, "Equipment refresh preserves each earned bonus once")
	panel.select_item(0)
	expect(panel.assign_selected_item(-1), "Return equipment through panel")
	base = baseline(stage, shop)
	for refresh in 3:
		fight._refresh_deployed_stats()
	expect_delta(fight.board_hero(4), base, combined, "Repeated refresh does not accumulate selected effects")
	var cell := fight.board_hero(4).grid_cell
	var reserve := Vector2i(-1, 0)
	expect(fight.transfer_hero(cell, reserve) and fight.board_hero(4) == null, "Withdraw starter to reserve")
	expect(fight.transfer_hero(reserve, cell), "Redeploy starter from reserve")
	expect_delta(fight.board_hero(4), base, combined, "Redeployed unit rebuilds both selected effects once")
	fight.start_fight()
	expect(fight.phase == Phase.FIGHT, "Enter actual second battle")
	expect_delta(fight.board_hero(4), base, combined, "Actual combat stats retain each selected effect once")
	if not failed:
		print("Six constant rank effects passed deployment, equipment, reserve and combat checks.")
	quit(int(failed))


func baseline(stage: Node, shop: GuildrunFirstShop) -> Dictionary:
	return stage.hero_stats(4, shop.hero_modifiers.get(4, []), shop.equipment(4), shop.relics,
			shop.hero_ranks[4], shop.specializations.get(4, {}))


func expect_delta(unit: GuildrunBoardUnit, base: Dictionary, deltas: Dictionary, label: String) -> void:
	for stat: String in deltas:
		var initial: Variant = base.get("<%s>k__BackingField" % stat, 0)
		var current: Variant = unit.stat(stat)
		if initial is Dictionary:
			initial = int(initial.RawValue) >> 16
			current = int(current.RawValue) >> 16
		expect(int(current) == int(initial) + int(deltas[stat]), "%s / %s: %s + %s got %s" % [label, stat, initial, deltas[stat], current])


func expect(ok: bool, label: String) -> bool:
	if not ok:
		failed = true
		push_error(label)
	return ok



