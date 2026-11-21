extends SceneTree

const PHASE := GuildrunEncounter.Phase
var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var stage := stage_with_shop()
	var fight: GuildrunEncounter = stage.encounter
	var shop := fight.first_shop
	if not expect(is_instance_valid(shop), "First shop is available"):
		quit(1)
		return
	expect(not shop.reroll() and shop.successful_shop_rerolls == 0, "Tutorial shop does not count a failed reroll")
	shop.roster.assign([4, 1, 10])
	shop.reserve_slots.assign([-1, -1, -1])
	shop.hero_ranks = {4: 3, 1: 3, 10: 4}
	expect(shop.record_rank_modifier(4, 3, 11) and shop.record_rank_modifier(10, 3, 136), "Record both eligible modifiers")
	var base_speed := stat(stage, shop, 1, "AttackSpeed")
	var base_mana := stat(stage, shop, 10, "ManaRegen")
	var unrelated_speed := stat(stage, shop, 4, "AttackSpeed")
	shop.visit = 2
	shop.prepare_third(0, 0)
	expect(not shop.reroll() and shop.successful_shop_rerolls == 0, "Unclaimed shop does not count a reroll")
	shop.claim_and_open()
	shop.shards = 0
	expect(not shop.reroll() and shop.successful_shop_rerolls == 0, "Unaffordable reroll does not count")
	shop.shards = 500
	shop.toggle_freeze()
	expect(shop.frozen and shop.successful_shop_rerolls == 0, "Freezing stock does not count")
	expect(shop.reroll() and shop.successful_shop_rerolls == 1 and not shop.frozen,
			"Successful paid reroll counts exactly once and clears frozen stock")
	expect(stat(stage, shop, 1, "AttackSpeed") == base_speed + 2, "Duelist receives +2 AttackSpeed per reroll")
	expect(stat(stage, shop, 10, "ManaRegen") == base_mana + 1, "Mystic receives +1 ManaRegen per reroll")
	expect(stat(stage, shop, 4, "AttackSpeed") == unrelated_speed, "Non-Duelist receives no AttackSpeed from owner aura")
	shop.toggle_freeze()
	var held := shop.stock.duplicate()
	shop.prepare_third(0, 0)
	expect(shop.stock == held and shop.successful_shop_rerolls == 1, "Frozen rollover preserves stock and run counter")
	shop.claim_and_open()
	expect(shop.reroll() and shop.successful_shop_rerolls == 2, "Second store advances the same run counter")
	shop.prepare_third(0, 0, true)
	shop.claim_and_open()
	expect(shop.reroll() and shop.successful_shop_rerolls == 3, "Super shop uses the same successful counter")
	# Resume the actual first-floor route after exercising the three shop visits.
	shop.visit = 1
	shop.leave()
	fight.crossroads.select_path(0)
	fight.crossroads.claim()
	fight.crossroads.get_node("Body/Event/Content/Continue").pressed.emit()
	if expect(fight.phase == PHASE.PLACE and fight.board_hero(1) != null and fight.board_hero(10) != null,
			"Deploy the next actual board with the stored counter"):
		expect(int(fight.board_hero(1).stat("AttackSpeed")) == base_speed + 6
				and int(fight.board_hero(10).stat("ManaRegen")) == base_mana + 3,
				"The next combat board consumes the full persisted count")
	stage.free()
	await process_frame
	stage = stage_with_shop()
	fight = stage.encounter
	expect(fight.first_shop.successful_shop_rerolls == 0, "New run begins with no shop rerolls")
	stage.free()
	if not failed:
		print("Run-wide shop reroll count and Duelist/Mystic rank modifiers passed.")
	quit(int(failed))


func stage_with_shop() -> Node:
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
	return stage


func stat(stage: Node, shop: GuildrunFirstShop, hero: int, key: String) -> int:
	var stats: Dictionary = stage.hero_stats(hero, [], [], [], shop.hero_ranks[hero])
	return int(stats.get("<%s>k__BackingField" % key, 0))


func expect(ok: bool, message: String) -> bool:
	if not ok:
		failed = true
		push_error(message)
	return ok

