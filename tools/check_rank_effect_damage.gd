extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)


func verify() -> void:
	verify_attack()
	verify_aura()
	if not failed:
		print("Rank effect damage passed ordinary impact, defenses, first fixed step, cadence, adjacency and owner death")
	quit(int(failed))


func make_fight() -> GuildrunEncounter:
	var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.stage_id = 10101
	root.add_child(stage)
	var fight := GuildrunEncounter.new()
	stage.add_child(fight)
	fight.setup(stage)
	return fight


func verify_attack() -> void:
	var fight := make_fight()
	var stage := fight._stage
	var target: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 4)]
	var bystander: GuildrunBoardUnit = stage.grid.occupants[Vector2i(0, 7)]
	var mage: GuildrunBoardUnit = stage.deploy_hero(14, Vector2i(4, 1), [], [], [], 3, {}, {3: 274})
	fight._register(mage)
	mage.combat_stats.Magic = 237 - int(mage.stat("Magic"))
	mage.combat_stats.Crit = 100 - int(mage.stat("Crit"))
	target.health = 10000
	target.max_health = 10000
	target.gain_shield(300, 5 << 16)
	var bystander_health := bystander.health
	mage.basic_attack_action.emit(target)
	check(fight._shots.size() == 1 and target.total_shield() == 300, "Launch neither damages nor procs Enchanted Attacks")
	var base_damage := target.damage_after_defense(fight._critical_damage(mage, int(fight._shots[0].damage)))
	var extra_damage := target.damage_after_defense(237)
	advance_projectiles(fight)
	var damage := base_damage + extra_damage
	check(target.health == 10000 - maxi(0, damage - 300) and target.total_shield() == maxi(0, 300 - damage),
		"Enchanted Attacks deals a separate mitigated, noncritical Magic hit into normal shields")
	check(bystander.health == bystander_health, "The extra hit affects only the original projectile target")
	var before := target.total_shield() + target.health
	fight._land(target, 100, mage)
	check(target.total_shield() + target.health == before - target.damage_after_defense(100),
		"Ability damage does not proc an attack-only effect")
	before = target.total_shield() + target.health
	mage.basic_attack_action.emit(target)
	base_damage = target.damage_after_defense(fight._critical_damage(mage, int(fight._shots[0].damage)))
	mage.take_damage(mage.health)
	advance_projectiles(fight)
	check(target.total_shield() + target.health == before - base_damage,
		"An already launched attack can land after the owner's death without another rank proc")
	bystander.defeated = true
	var dead_health := bystander.health
	fight._land_auto(bystander, 1000, mage, false)
	check(bystander.health == dead_health, "A defeated target receives neither the base hit nor a rank proc")
	stage.free()


func advance_projectiles(fight: GuildrunEncounter) -> void:
	for step in 240:
		if fight._shots.is_empty():
			return
		fight._advance_projectiles(GuildrunEncounter.BATTLE_STEP_Q16)
	check(false, "Target projectile reached its target")


func verify_aura() -> void:
	var fight := make_fight()
	var stage := fight._stage
	var target: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 4)]
	var bystander: GuildrunBoardUnit = stage.grid.occupants[Vector2i(0, 7)]
	var first: GuildrunBoardUnit = stage.deploy_hero(26, Vector2i(4, 3), [], [], [], 3, {}, {3: 185})
	var second: GuildrunBoardUnit = stage.deploy_hero(14, Vector2i(3, 4), [], [], [], 3, {}, {3: 185})
	for hero in [first, second]:
		fight._register(hero)
	for unit in fight._units:
		unit.stun_remaining_q16 = 5 << 16
	first.combat_stats.MaxHealth = 1001 - int(first.stat("MaxHealth"))
	second.combat_stats.MaxHealth = 1501 - int(second.stat("MaxHealth"))
	target.health = 10000
	target.max_health = 10000
	var first_hit := target.damage_after_defense(30)
	var second_hit := target.damage_after_defense(45)
	var bystander_health := bystander.health
	fight.phase = GuildrunEncounter.Phase.PLACE
	fight.start_fight()
	check(target.health == 10000 and fight.battle_time_q16 == 0, "Aura is an interval effect and does not apply at start itself")
	fight._step_battle(GuildrunEncounter.BATTLE_STEP_Q16)
	check(target.health == 10000 - first_hit - second_hit and bystander.health == bystander_health,
		"Each owner pulses on the first step, exclusively to currently neighboring enemies")
	first.take_damage(first.health)
	for step in 29:
		fight._step_battle(GuildrunEncounter.BATTLE_STEP_Q16)
	check(target.health == 10000 - first_hit - second_hit, "No additional pulse before the one-second Q16 threshold")
	fight._step_battle(GuildrunEncounter.BATTLE_STEP_Q16)
	check(target.health == 10000 - first_hit - 2 * second_hit, "The remaining owner's pulse stays on schedule after a death")
	check(not fight._rank_aura_timers.has(first) and fight._rank_aura_timers.has(second), "Dead and active owners have separate lifetime state")
	fight._claim_cell(second, Vector2i(3, 2))
	for step in 30:
		fight._step_battle(GuildrunEncounter.BATTLE_STEP_Q16)
	check(target.health == 10000 - first_hit - 2 * second_hit and bystander.health == bystander_health,
		"Moving out of adjacency removes targets on the following pulse")
	stage.free()
