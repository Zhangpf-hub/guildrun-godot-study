extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func expect(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)


func verify() -> void:
	for fallen in [false, true]:
		verify_victory(fallen)
	for stabilizer in [false, true]:
		verify_defeat(stabilizer)
	verify_timed_defeat()
	if not failed:
		print("Battle aftermath: frame freeze, 1s and 1.5s holds, visual revival, survivor rewards and immediate timed defeat")
	quit(int(failed))


func new_stage() -> Node:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	stage.encounter.select_hero(4)
	return stage


func start_fallen_ragdoll(unit: GuildrunBoardUnit) -> PhysicalBoneSimulator3D:
	var delay := unit._ragdoll_start_delay
	expect(delay != null, "Fatal damage must schedule the custom death motion")
	if delay != null:
		delay.custom_step(0.09)
	var body := unit._ragdoll
	expect(body != null and body.is_simulating_physics(), "The fallen hero must enter the physics pose")
	return body


func verify_victory(fallen: bool) -> void:
	var stage := new_stage()
	var fight: GuildrunEncounter = stage.encounter
	var ally: GuildrunBoardUnit
	if fallen:
		fight._create_party()
		fight.first_shop.roster.assign([4, 8])
		fight.first_shop.hero_ranks = {4: 1, 8: 1}
		fight._formation = {4: Vector2i(1, 1), 8: Vector2i(2, 1)}
		fight._enter_next_battle()
		ally = fight.board_hero(8)
	fight.start_fight()
	var defeated_enemies: Array[GuildrunBoardUnit] = []
	var ally_ragdoll: PhysicalBoneSimulator3D
	if is_instance_valid(ally):
		fight._land(ally, ally.max_health * 2)
		ally_ragdoll = start_fallen_ragdoll(ally)
	for unit in fight._units:
		if not unit.is_hero:
			fight._land(unit, unit.max_health * 2, fight._hero)
			defeated_enemies.append(unit)
			if not unit._death_blend_times.is_empty():
				expect(unit._death_blend_tween != null and unit._death_blend_tween.is_running(),
						"Fatal hit must start the authored material transition")
	expect(not fight._advance_battle_tick(0.0), "Final step did not stop the battle clock")
	var last_frame := fight._frame
	var last_time := fight.battle_time_q16
	var duration := 1.5 if fallen else 1.0
	fight._physics_process(duration - 0.01)
	expect(fight.phase == GuildrunEncounter.Phase.FIGHT and fight.last_battle_statistics.is_empty(),
			"Victory settled before the native countdown ended")
	if is_instance_valid(ally):
		expect(ally_ragdoll != null and ally._ragdoll == ally_ragdoll and ally_ragdoll.is_simulating_physics(),
				"The fallen hero must keep the ragdoll until revival begins")
		expect(ally.get_node_or_null("VFX_Char_Resurrect_BattleEnd") == null, "Victory effect started before revival")
	fight._physics_process(0.01)
	expect(fight.phase == GuildrunEncounter.Phase.RESULT and fight.last_battle_statistics.get("victory", false),
			"Victory did not settle at its native deadline")
	expect(fight._frame == last_frame and fight.battle_time_q16 == last_time, "The result hold advanced the simulation")
	var view := fight._result_view
	var tracker := view.get_node(view.TRACKER) as Control
	expect(view.visible and view.reward_target.get_node("ShardValueText/UnityText").text ==
			str(fight.first_shop.battle_reward), "Result visual must show the settled battle reward")
	expect(tracker.get_child_count() == (3 if fallen else 2), "Results must display every deployed hero")
	var ally_portraits: Control = view.get_node(view.VERSUS + "/PortraitsRow_Heroes")
	var enemy_portraits: Control = view.get_node(view.VERSUS + "/PortraitsRow_Enemies")
	expect(ally_portraits.get_child_count() == tracker.get_child_count()
			and enemy_portraits.get_child_count() == defeated_enemies.size() + 1,
			"Results must place heroes and enemies on their respective sides")
	for i in defeated_enemies.size():
		var enemy := defeated_enemies[i]
		var portrait := enemy_portraits.get_child(i + 1) as Control
		expect(portrait.get_node("HeroDamageIndicator").visible and portrait.get_node(view.DAMAGE_ICON).texture == view.BANISHED_ICON
				and portrait.get_node(view.PORTRAIT).material == view._desaturated_portrait,
				"A defeated enemy portrait uses the native skull and grayscale")
		expect(enemy._death_blend_tween == null and enemy.visible,
				"A defeated enemy completes its material transition and remains on the board")
	verify_result_entrance(view, tracker)
	var hero_stats: Button = view.get_node(view.SWITCH + "/HeroStatsButton").get_children().back()
	hero_stats.pressed.emit()
	expect(not tracker.visible and view._hero_details.visible, "Hero attribute tab must switch the result panel")
	if is_instance_valid(ally):
		expect(ally.defeated and ally.health == 0 and ally._ragdoll == null and ally_ragdoll != null
				and ally_ragdoll.is_queued_for_deletion(),
				"Victory should restore the hero pose while keeping combat death")
		verify_revival_effects(ally, false)
		expect(ally._death_blend_tween == null, "Victory should reset the fallen hero's material animation")
		expect(fight.first_shop.survival_reward == fight.first_shop._survivor_price(),
				"The restored hero must not count toward survivor rewards")
	fight._continue.pressed.emit()
	if not fallen:
		expect(fight._hero.get_node_or_null("VFX_Char_Resurrect_BattleEnd") == null, "Living hero received a revival effect")
	expect(fight.phase == GuildrunEncounter.Phase.SHOP and not view.visible, "Continue opens shop and closes results")
	stage.free()


func verify_result_entrance(view: Control, tracker: Control) -> void:
	var stats := view.get_node(view.STATS) as Control
	var rewards := view.get_node(view.REWARDS) as Control
	var buttons := rewards.get_node("ButtonContainer") as Control
	var first_meter := tracker.get_child(1).get_node("DamageSlidersHolder") as Control
	var tween: Tween = view._transition
	tween.pause()
	expect(stats.position.x == 200.0 and stats.size.y == 0.0 and rewards.size.x == 0.0,
			"The statistics and rewards must start closed")
	tween.custom_step(0.15)
	expect(stats.size.y == 654.0 and rewards.size.x == 0.0 and first_meter.size.x == 0.0,
			"The statistics frame should open before the rows and rewards")
	tween.custom_step(0.13)
	expect(first_meter.size.x > 0.0 and first_meter.size.x < 500.0 and rewards.size.x == 0.0,
			"The first damage row should reveal while the rewards remain closed")
	var two_rows := tracker.get_child_count() > 2
	if two_rows:
		var second_meter := tracker.get_child(2).get_node("DamageSlidersHolder") as Control
		expect(second_meter.size.x == 0.0, "The second row should start 0.1s after the first")
	tween.custom_step(0.16)
	expect((rewards.size.x == 0.0) == two_rows and buttons.modulate.a == 0.0,
			"Reward reveal should wait for the last damage row")
	tween.custom_step(0.42)
	expect(stats.position.x == 0.0 and rewards.size.x == 388.0 and buttons.modulate.a == 1.0,
			"Result entrance should finish at the authored layout")


func verify_defeat(stabilizer: bool) -> void:
	var stage := new_stage()
	var fight: GuildrunEncounter = stage.encounter
	fight.rewind_available = stabilizer
	fight.start_fight()
	var hero := fight._hero
	fight._land(hero, hero.max_health * 2)
	var ragdoll := start_fallen_ragdoll(hero)
	fight._advance_battle_tick(0.0)
	fight._physics_process(0.99)
	expect(fight.phase == GuildrunEncounter.Phase.FIGHT, "Defeat with a fatality must hold for one second")
	fight._physics_process(0.01)
	expect(fight.phase == GuildrunEncounter.Phase.RESULT and not fight.last_battle_statistics.get("victory", true),
			"Defeat did not settle at its native deadline")
	expect(hero.defeated and ragdoll != null and ragdoll.is_queued_for_deletion() == stabilizer
			and (hero._ragdoll == null) == stabilizer,
			"Only a normal defeat with a Stabilizer should restore the hero pose")
	if stabilizer:
		verify_revival_effects(hero, true)
	else:
		expect(hero.get_node_or_null("VFX_Char_Resurrect_BattleEnd") == null, "Ordinary defeat must not play revival")
	stage.free()


func verify_revival_effects(hero: GuildrunBoardUnit, stabilizer: bool) -> void:
	var common: Node3D = hero.get_node_or_null("VFX_Char_Resurrect_BattleEnd")
	var wings: Node3D = hero.get_node_or_null("VFX_Char_Resurrect_Start1")
	expect(common != null and (wings != null) == stabilizer, "Wrong native revival prefab selection")
	if common != null:
		expect(common.get_meta("unity_prefab", 0) == 61208 and is_equal_approx(common.lead_in, 0.45)
				and is_equal_approx(common.duration, 2.0) and common.get_child_count() == 9,
				"Victory revival lost a particle layer or its authored timing")
		expect(common.get_node("Feathers_01").get_meta("particle").repeat_count == 12,
				"Victory must play all twelve triangle bursts")
	if wings != null:
		expect(wings.get_meta("unity_prefab", 0) == 62030 and is_zero_approx(wings.lead_in)
				and wings.get_child_count() == 6 and wings.get_node("Wings_01").get_meta("particle").delay > 0.39,
				"Stabilizer wings must keep their own timing and six particle layers")
	var flash := hero._revive_tween
	expect(flash != null and not hero._death_blend_times.is_empty(), "The revived actor must schedule its original material flash")
	if flash != null and not hero._death_blend_times.is_empty():
		var mesh: MeshInstance3D = hero._death_blend_times.keys().front()
		var previous := mesh.material_override
		flash.pause()
		flash.custom_step(0.44)
		expect(mesh.material_override == previous, "Revival flash must wait 0.45 seconds")
		flash.custom_step(0.02)
		expect(mesh.material_override != null and mesh.material_override.get_meta("unity_material", "") == "sharedassets1.assets:9",
				"The flash temporarily applies the source character material")
		flash.custom_step(0.10)
		expect(mesh.material_override == previous and hero._revive_tween == null, "The flash must restore all original materials")


func verify_timed_defeat() -> void:
	var stage := new_stage()
	var fight: GuildrunEncounter = stage.encounter
	fight._create_party()
	fight.first_shop.roster.assign([4])
	fight.first_shop.hero_ranks = {4: 1}
	fight._formation = {4: Vector2i(1, 1)}
	fight._enter_next_battle({"stage_id": 50301, "modifier": 5506, "kind": "shards", "value": 20})
	fight.start_fight()
	for unit in fight._units:
		unit.stun_remaining_q16 = 60 << 16
	fight.battle_time_q16 = fight._trial_time_limit_q16() - 1
	fight._advance_battle_tick(0.0)
	expect(fight.phase == GuildrunEncounter.Phase.FIGHT, "Battle end dispatch must follow the last simulation frame")
	fight._physics_process(1.0 / 60.0)
	expect(fight.phase == GuildrunEncounter.Phase.RESULT and not fight._trial_won and not fight._hero.defeated,
			"Timed defeat with all heroes alive must skip the one-second hold")
	stage.free()
