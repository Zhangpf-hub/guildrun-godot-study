extends SceneTree

const DUSK := "res://Scenes/Stage_Environment/RuinsForest/3Gates_Default/Environment_Default_3Gates_Dusk.tscn"
const TRIAL_DUSK := "res://Scenes/Stage_Environment/RuinsForest/FightScenarioRoom/Environment_FightScenarioRoom_Dusk.tscn"

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func check_material(id: String, variant: String, tint: Vector3, threshold := -1.0, sampler_mode := 0, has_texture := true) -> void:
	var material := load("res://materials/sharedassets%s.tres" % id) as ShaderMaterial
	expect(material != null, "Expected EnvironmentPlane shader material %s" % id)
	if material == null:
		return
	expect(material.shader.resource_path.ends_with("environment_plane_%s.gdshader" % variant), "Wrong pass variant for %s" % id)
	var actual_tint: Vector3 = material.get_shader_parameter("tint")
	expect(actual_tint.is_equal_approx(tint), "Wrong authored tint for %s" % id)
	var samplers := ["main_texture", "main_texture_clamped", "main_texture_point_clamped", "main_texture_mipped"]
	var imported_mode: Variant = material.get_shader_parameter("sampler_mode")
	if imported_mode == null:
		imported_mode = 0
	expect(imported_mode == sampler_mode, "Wrong texture sampler for %s" % id)
	var material_texture: Variant = material.get_shader_parameter(samplers[sampler_mode])
	expect((material_texture is Texture2D) == has_texture, "Wrong Unity texture binding for %s" % id)
	if threshold >= 0.0:
		expect(is_equal_approx(float(material.get_shader_parameter("alpha_threshold")), threshold), "Wrong cutoff for %s" % id)


func check_source_mips() -> void:
	var bindings := {"10_4": "10_26", "10_7": "10_17", "11_4": "11_7", "12_4": "12_14"}
	for id: String in bindings:
		var material := load("res://materials/sharedassets%s.tres" % id) as ShaderMaterial
		var texture := material.get_shader_parameter("main_texture_mipped") as Texture2D
		var path := "res://textures/sharedassets%s.dds" % bindings[id]
		expect(texture != null and texture.resource_path == path, "Missing original forest mip texture for %s" % id)
		expect(material.get_shader_parameter("nearest_mip") == true, "Wrong Unity mip filter for %s" % id)
		if texture != null:
			var image := texture.get_image()
			expect(image.get_format() == Image.FORMAT_DXT5 and image.get_mipmap_count() == 12,
					"Expected all 13 BC3 levels for %s" % id)


func check_scene(path: String) -> void:
	var scene := (load(path) as PackedScene).instantiate()
	var translated_nodes := 0
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		var surfaces := 0
		for index in mesh.get_surface_override_material_count():
			var material: Material = mesh.get_surface_override_material(index)
			if material is ShaderMaterial and material.get_meta("unity_shader", "") == "Shader Graphs/EnvironmentPlane_SG":
				surfaces += 1
		if surfaces > 0 and surfaces == mesh.get_surface_override_material_count():
			expect(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Environment plane casts shadows in %s" % path)
			translated_nodes += 1
	expect(translated_nodes > 0, "Missing environment material bindings in %s" % path)
	scene.free()


func check_gates() -> void:
	var material := load("res://materials/sharedassets7_4.tres") as StandardMaterial3D
	expect(material.emission_enabled and material.emission_texture.resource_path.ends_with("sharedassets7_17.png"),
			"Missing Unity gate frame emission")
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	expect(stage.stage_id == 10000 and stage._crossroads_gates().size() == 3, "Missing deployment gate templates")
	expect(stage.crossroads_gate_screen_rects().is_empty(), "Deployment exposed the world gates")
	fight.select_hero(4)
	if fight.first_shop == null:
		fight._create_party()
	fight._show_crossroads()
	await process_frame
	var rects: Array[Rect2] = stage.crossroads_gate_screen_rects()
	expect(rects.size() == fight.crossroads.offers.size(), "Gate count differs from realized paths")
	expect(stage.crossroads_gate_label_rects().size() == rects.size(), "Missing projected gate titles")
	if not rects.is_empty():
		for index in range(1, rects.size()):
			expect(rects[index - 1].get_center().x < rects[index].get_center().x, "Native gate path order")
		var click := InputEventMouseButton.new()
		click.position = rects[0].get_center()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		root.push_input(click, true)
		click.pressed = false
		root.push_input(click, true)
		await process_frame
		expect(fight.phase == GuildrunEncounter.Phase.EVENT, "Projected gate click did not enter its event")
		expect(fight.crossroads.selected_event == fight.crossroads.offers[0], "Projected gate picked a different path")
		expect(stage.crossroads_gate_screen_rects().is_empty(), "Event still shows world gates")
	stage.free()


func verify() -> void:
	check_material("10_5", "cutout", Vector3(0.74901962, 0.74901962, 0.74901962), 0.5)
	check_material("10_7", "cutout", Vector3.ONE, 0.6, 3)
	check_material("10_4", "cutout_double_sided", Vector3.ONE, 0.5, 3)
	check_material("17_2", "cutout", Vector3(0.74901962, 0.74901962, 0.74901962), 0.09)
	check_material("18_4", "transparent", Vector3.ONE, -1.0, 2)
	check_material("20_2", "transparent", Vector3(3.02806234, 2.78255153, 2.55671310), -1.0, 2)
	check_material("18_5", "transparent", Vector3(0.66274512, 0.62745100, 0.73725491), -1.0, 1)
	check_material("19_2", "cutout", Vector3(0.66397995, 0.62824845, 0.73584902), 0.5, 0, false)
	check_source_mips()
	check_scene(DUSK)
	check_scene(TRIAL_DUSK)
	await check_gates()
	print("ENVIRONMENT_PLANE authored shader and gate bindings, deployment visibility, and projected click")
	quit(1 if failed else 0)
