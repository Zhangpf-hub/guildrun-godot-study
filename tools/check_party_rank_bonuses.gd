extends SceneTree

const PHASE := GuildrunEncounter.Phase
var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	await verify_opening(false)
	await verify_opening(true)
	if not failed:
		print("Party rank modifiers: class masks, two owners, reserve swaps, equipment and opening order passed.")
	quit(int(failed))


func verify_opening(two_backups: bool) -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	fight.start_fight()
	for tick in 2400:
		if fight.phase != PHASE.FIGHT:
			break
		fight._physics_process(fight.BATTLE_STEP_SECONDS)
	fight.open_first_shop()
	var shop := fight.first_shop
	if not expect(is_instance_valid(shop), "The real starter reaches first shop"):
		stage.free()
		return
	shop.roster.assign([4, 9, 11, 18] if two_backups else [4, 9, 11])
	shop.hero_ranks = {4: 3, 9: 3, 11: 4, 18: 4}
	shop.reserve_slots.assign([18, -1, -1] if two_backups else [-1, -1, -1])
	shop.items.assign([803])
	for hero: int in shop.roster:
		if hero in [4, 18]:
			expect(shop.record_rank_modifier(hero, 3, 145), "Register opening bonus")
		else:
			expect(shop.record_rank_modifier(hero, 3, 190), "Register Vanguard attack")
	if not two_backups:
		expect(shop.record_rank_modifier(11, 4, 183), "Register Vanguard healing")
		# A stale S entry on a rank A owner cannot execute.
		expect(shop.record_rank_modifier(9, 4, 183), "Store future S entry for eligibility boundary")
	shop.leave()
	fight.crossroads.select_path(0)
	fight.crossroads.claim()
	fight.crossroads.get_node("Body/Event/Content/Continue").pressed.emit()
	if not expect(fight.phase == PHASE.PLACE and fight.board_hero(9) != null, "Second deployment loaded"):
		stage.free()
		return
	var active := fight.board_hero(9)
	var starter := fight.board_hero(4)
	var base_attack := baseline(stage, 9, "Attack", 3)
	var base_regen := baseline(stage, 9, "ManaRegen", 3)
	var base_magic := baseline(stage, 9, "Magic", 3)
	var base_healing := baseline(stage, 9, "HPPerSecond", 3)
	expect(int(active.stat("Attack")) == base_attack + 350, "A/S owners stack 150 + 200 exactly once")
	expect(int(active.stat("HPPerSecond")) == base_healing + (0 if two_backups else 43), "S owner grants character HP/S, future S entry is ignored")
	expect(int(active.stat("ManaRegen")) == base_regen and int(active.stat("Magic")) == base_magic,
			"Opening-only #145 prepares no placement stats")
	if not two_backups:
		var starter_attack := baseline(stage, 4, "Attack", 3)
		expect(int(starter.stat("Attack")) == starter_attack, "Non-Vanguard does not receive attack aura")
		fight._equipment_panel.select_item(0)
		expect(fight._equipment_panel.assign_selected_item(4), "Equip Vanguard medal through equipment entry")
		expect(starter.has_class(3) and int(starter.stat("Attack")) == starter_attack + 350,
				"Equipment preview includes added Vanguard class")
		fight._equipment_panel.select_item(0)
		expect(fight._equipment_panel.assign_selected_item(-1), "Remove Vanguard medal")
		expect(not starter.has_class(3) and int(starter.stat("Attack")) == starter_attack,
				"Removing class from equipment immediately removes bonus")
		var second := fight.board_hero(11)
		var cell := second.grid_cell
		var blank := Vector2i(-1, 0)
		expect(fight.transfer_hero(cell, blank), "Put an aura owner in reserve")
		expect(int(active.stat("Attack")) == base_attack + 350 and int(active.stat("HPPerSecond")) == base_healing + 43,
				"Changing owner placement does not double or remove either aura")
		expect(fight.transfer_hero(blank, cell), "Redeploy aura owner")
		shop.hero_ranks[11] = 3
		fight._refresh_deployed_stats()
		expect(int(active.stat("Attack")) == base_attack + 300 and int(active.stat("HPPerSecond")) == base_healing,
				"Recompute according to current owner rank and slot eligibility")
		shop.hero_ranks[11] = 4
		fight._refresh_deployed_stats()
	else:
		expect(fight.transfer_hero(starter.grid_cell, Vector2i(-1, 1)), "Move other opening-bonus owner into reserve")
		for pass_index in 2:
			fight._refresh_deployed_stats()
		expect(int(active.stat("Attack")) == base_attack + 350, "Placement refresh remains free of opening bonus")
	var other := fight.board_hero(11)
	var other_attack := int(other.stat("Attack"))
	fight.start_fight()
	expect(fight.phase == PHASE.FIGHT and fight.battle_time_q16 == 0, "Real battle enters simulation before the first tick")
	var power := 225 if two_backups else 0
	var regen := 28 if two_backups else 0
	expect(int(active.stat("Attack")) == base_attack + 350 + power and int(active.stat("Magic")) == base_magic + power
			and int(active.stat("ManaRegen")) == base_regen + regen, "145 applies exactly once per reserve owner after constant modifiers")
	expect(int(other.stat("Attack")) == other_attack + power, "145 reaches each deployed recipient")
	fight.start_fight()
	expect(int(active.stat("Attack")) == base_attack + 350 + power, "Duplicate start does not replay opening effects")
	stage.free()
	await process_frame


func baseline(stage: Node, id: int, stat: String, rank: int) -> int:
	var stats: Dictionary = stage._heroes[id].duplicate()
	load("res://battle/hero_rank.gd").apply(stats, rank, {})
	return int(stats.get("<%s>k__BackingField" % stat, 0))


func expect(ok: bool, message: String) -> bool:
	if not ok:
		failed = true
		push_error(message)
	return ok


