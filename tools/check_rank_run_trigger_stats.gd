extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.stage_id = 10101
	root.add_child(stage)
	var fight := GuildrunEncounter.new()
	stage.add_child(fight)
	fight.setup(stage)
	fight._create_party()
	var shop := fight.first_shop
	shop.roster.assign([14, 4, 26, 24, 13])
	shop.reserve_slots.assign([26, 24, 13])
	shop.hero_ranks = {14: 1, 4: 4, 26: 3, 24: 3, 13: 3}
	shop.rank_modifiers_by_hero = {26: {3: 15}, 24: {3: 56}, 13: {3: 8, 4: 15}}
	var recipient: GuildrunBoardUnit = stage.deploy_hero(14, Vector2i(4, 3), [], [], [], 1)
	var owner: GuildrunBoardUnit = stage.deploy_hero(4, Vector2i(4, 1), [], [], [], 4, {}, {3: 8, 4: 56})
	var units: Array[GuildrunBoardUnit] = [recipient, owner]
	recipient.base_stats._class1ID = -1
	recipient.base_stats._class2ID = -1
	recipient.base_stats.equipment_classes = [1, 5]
	owner.base_stats._class1ID = -1
	owner.base_stats._class2ID = -1
	owner.base_stats.equipment_classes = []
	recipient.combat_stats.AttackSpeed = 7
	var component: RefCounted = load("res://battle/rank_run_trigger_stats.gd").new()
	component.begin(shop, units)
	component.refresh(3, 4)
	check_bonus(recipient, 6, 23, "Earlier battles' 3 Rush and 4 Stall apply from the first evaluation")
	check_bonus(owner, 0, 0, "The owner does not benefit without the appropriate class")
	component.refresh(3, 4)
	check_bonus(recipient, 6, 23, "An identical evaluation cannot compound the contribution")
	recipient.combat_stats.AttackSpeed += 2
	component.refresh(5, 5)
	check_bonus(recipient, 10, 34, "Two Rush and one Stall change the bonus and preserve an unrelated modifier")
	owner.defeated = true
	component.refresh(5, 5)
	check_bonus(recipient, 0, 29, "Defeated deployed owner stops contributing while reserve owners continue")
	recipient.base_stats.equipment_classes = [1]
	component.refresh(5, 5)
	check_bonus(recipient, 0, 9, "Loss of the Duelist qualification removes only the owned contribution")
	recipient.base_stats.equipment_classes = [5]
	component.refresh(3, 4)
	check_bonus(recipient, 0, 22, "A restored counter snapshot and qualification recompute the contribution")

	shop.reserve_slots.assign([26, 4, -1])
	shop.rank_modifiers_by_hero[4] = {3: 8, 4: 56}
	var next_units: Array[GuildrunBoardUnit] = [recipient]
	component.begin(shop, next_units)
	check_bonus(recipient, 0, 9, "New battle clears previous bindings without losing other combat modifiers")
	component.refresh(3, 4)
	check_bonus(recipient, 0, 22, "The same rank 56 in reserve now gives Duelist attack speed, not Warrior Attack")
	component.begin(null, next_units)
	component.refresh(99, 99)
	check_bonus(recipient, 0, 9, "No owners or stale reserve entries apply in a new run")
	if not failed:
		print("Rank 8/15/56 per-frame Rush and Stall stat checks passed")
	quit(int(failed))


func check_bonus(unit: GuildrunBoardUnit, attack: int, speed: int, message: String) -> void:
	var actual := Vector2i(int(unit.combat_stats.get("Attack", 0)), int(unit.combat_stats.get("AttackSpeed", 0)))
	if actual != Vector2i(attack, speed):
		failed = true
		push_error("%s. Expected %s, got %s" % [message, Vector2i(attack, speed), actual])
