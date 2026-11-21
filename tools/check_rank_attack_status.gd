extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, detail: String) -> void:
	if not ok:
		failed = true
		push_error(detail)


func verify() -> void:
	var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.stage_id = 10101
	root.add_child(stage)
	var fight := GuildrunEncounter.new()
	stage.add_child(fight)
	fight.setup(stage)
	var target: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 4)]
	var bystander: GuildrunBoardUnit = stage.grid.occupants[Vector2i(0, 7)]
	var melee: GuildrunBoardUnit = stage.deploy_hero(26, Vector2i(4, 3), [], [], [], 4, {}, {3: 1, 4: 3})
	var ranged: GuildrunBoardUnit = stage.deploy_hero(14, Vector2i(4, 1), [], [], [], 3, {}, {"3": 5})
	var control: GuildrunBoardUnit = stage.deploy_hero(26, Vector2i(4, 2), [], [], [], 2, {}, {3: 1})
	for unit in [melee, ranged, control]:
		fight._register(unit)
	check(int(melee.stat("AttackSettings")["<ProjectileSpeed>k__BackingField"].RawValue) == 0, "Use a native melee attack profile")
	check(int(ranged.stat("AttackSettings")["<ProjectileSpeed>k__BackingField"].RawValue) > 0, "Use a native ranged attack profile")
	target.health = 100000
	target.max_health = 100000
	target.gain_shield(100000, 20 << 16)
	melee.combat_stats.AttackSpeed = 100 - int(melee.stat("AttackSpeed"))
	melee.basic_attack_action.emit(target)
	check(target.health == 100000 and target.total_shield() < 100000, "Armor did not consume any HP")
	check(target.burn_stacks == 4 and target.poison_stacks == 3,
		"Normal melee attack applies both runtime-scaled statuses after damage")
	check(bystander.burn_stacks == 0 and bystander.poison_stacks == 0, "Only the triggering target receives statuses")
	fight._land(target, 1, melee)
	check(target.burn_stacks == 4 and target.poison_stacks == 3, "An ability damage event does not route this trigger")
	control.basic_attack_action.emit(target)
	check(target.burn_stacks == 4 and target.poison_stacks == 3, "An invalid rank-3 effect on a B hero is ignored")
	melee.combat_stats.AttackSpeed += 1000
	melee.basic_attack_action.emit(target)
	check(target.burn_stacks == 14 and target.poison_stacks == 9, "Per-hit native caps are 10 Burn and 6 Poison")
	ranged.combat_stats.AttackSpeed = 160 - int(ranged.stat("AttackSpeed"))
	ranged.basic_attack_action.emit(target)
	check(target.frost_stacks == 0 and fight._shots.size() == 1, "Ranged attack waits until the projectile hits")
	for step in 240:
		if fight._shots.is_empty():
			break
		fight._advance_projectiles(1092)
	check(fight._shots.is_empty() and target.frost_stacks == 3 and bystander.frost_stacks == 0,
		"Projectile impact applies the native Frost formula to its target only")
	stage.free()
	if not failed:
		print("Rank attack status normal melee/ranged impact, attack speed, caps, shielding and earned rank passed")
	quit(int(failed))

