extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	root.size = Vector2i(1024, 768)
	var stage = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	var fight: GuildrunEncounter = stage.encounter
	var enemy: GuildrunBoardUnit = fight._units[0]
	var enemy_bar: Control = fight._bars[enemy]
	check(not enemy_bar.visible, "No combat bar on initial draft")
	fight.select_hero(4)
	stage.battle_camera.advance(4.0)
	fight._process(0.0)
	var hero := fight._hero
	var hero_bar: Control = fight._bars[hero]
	var hero_layout: Control = hero_bar.get_node("battle_health_barUI/HealthBar")
	var enemy_layout: Control = enemy_bar.get_node("battle_health_barUI/HealthBar")
	check(hero_layout.size.is_equal_approx(Vector2(123, 16)), "Original health prefab size")
	check(hero_bar.visible and enemy_bar.visible, "Both deployed sides have visible bars")
	var text: Label = hero_layout.get_node("HealthText/UnityText")
	check(text.is_visible_in_tree() and text.text == str(hero.max_health), "Preparation shows the original HP number")
	var equipment: Control = hero_layout.get_node("TopBar/HeroItemRows")
	var bottom_row: Control = equipment.get_node("HeroItemsView_Bottom")
	check(equipment.is_visible_in_tree() and not enemy_layout.get_node("TopBar/HeroItemRows").is_visible_in_tree(),
			"Preparation shows equipment slots only over deployed heroes")
	check(not equipment.get_node("HeroItemsView_Top").visible and bottom_row.get_child(2).visible,
			"Three starter slots fill the authored bottom row")
	check(is_equal_approx(bottom_row.get_child(1).position.x - bottom_row.get_child(0).position.x, 41.0),
			"Empty slots respect the source layout spacing")
	var camera := root.get_camera_3d()
	const SCALE := 1024.0 / 1920.0
	check(hero_bar.position.distance_to(camera.unproject_position(hero.to_global(Vector3(0, 2, 0)))
			- Vector2(0, 20 * SCALE)) < 0.1, "Authored Yuuna attachment and screen offset")
	check(enemy_bar.position.distance_to(camera.unproject_position(enemy.to_global(Vector3(0, 2, 0)))
			- Vector2(0, 20 * SCALE)) < 0.1, "Authored Turtle attachment and screen offset")
	check(is_equal_approx(hero_bar.scale.x, SCALE), "Original canvas scale")
	check(hero_layout.get_node("ManaBackgroundImage").visible and not enemy_layout.get_node("ManaBackgroundImage").visible,
			"Starter hero has a mana slider, tutorial Turtle has no mana slider")
	var mana: Control = hero_layout.get_node("ManaBackgroundImage/ManaSlider/PrimeryFillImage")
	check(is_equal_approx(mana.anchor_right, float(hero.mana) / int(hero.stat("MaxMana"))), "Mana fills the native slider proportionally")
	fight.start_fight()
	fight._process(0.0)
	check(not text.is_visible_in_tree() and hero_bar.visible, "Battle hides preparation numbers while keeping the bar")
	check(not equipment.is_visible_in_tree(), "Resolution hides the overhead equipment slots")
	hero.health = hero.max_health / 2
	hero.gain_shield(hero.max_health / 4, 10 << 16)
	fight._process(0.0)
	var fill: ShaderMaterial = hero_layout.get_node("HealthBarImage/UnityImage").material
	check(is_equal_approx(float(fill.get_shader_parameter("health_fill")), 0.4), "Health uses combined HP and shield denominator")
	check(is_equal_approx(float(fill.get_shader_parameter("shield_fill")), 0.6), "Shield uses its original independent channel")
	check(float(fill.get_shader_parameter("damage_fill")) > 0.4, "Original damage trail remains after a hit")
	fight._process(0.3)
	check(absf(float(fill.get_shader_parameter("damage_fill")) - 0.4) < 0.001, "Damage trail completes after 300 ms")
	enemy.defeated = true
	fight._process(0.5)
	check(enemy_bar.visible, "Defeated bar stays for the native delay")
	fight._process(0.5)
	check(not enemy_bar.visible, "Defeated bar expires after one second")
	stage.free()
	print("BATTLE_HEALTH_BARS original prefab, anchors, HP/mana/shield, damage trail and visibility")
	quit(1 if failed else 0)


func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
