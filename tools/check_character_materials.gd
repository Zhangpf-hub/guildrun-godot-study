extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var rigs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Characters/rigs.json"))
	var inspected := {}
	for bindings: Array in rigs.values():
		for rig: Dictionary in bindings:
			for mesh: Dictionary in rig.meshes.values():
				if not mesh.visible:
					continue
				for path: String in mesh.surfaces:
					if not path.is_empty() and not inspected.has(path):
						inspected[path] = load(path)
	check(inspected.size() == 86, "All visible rig material paths were checked")
	var counts := {}
	var emitting := 0
	var highlighted := 0
	var mixed_shadow := 0
	for value: Material in inspected.values():
		var shader_name: String = value.get_meta("unity_shader", "")
		counts[shader_name] = int(counts.get(shader_name, 0)) + 1
		if shader_name not in ["lilToon", "Hidden/lilToonCutout"]:
			continue
		check(value is ShaderMaterial, "Toon material uses the translated shader")
		var material := value as ShaderMaterial
		if not material:
			continue
		check(material.shader.resource_path == "res://materials/character_toon.gdshader", "Shared toon shader")
		check(material.get_shader_parameter("main_texture") is Texture2D, "Native main texture")
		var cutoff: Variant = material.get_shader_parameter("cutoff")
		check(float(cutoff) == (0.5 if shader_name == "Hidden/lilToonCutout" else 0.0),
				"Original render mode and cutoff")
		if material.get_shader_parameter("use_emission"):
			emitting += 1
		if material.get_shader_parameter("use_highlight"):
			highlighted += 1
		var shadow_environment: Variant = material.get_shader_parameter("shadow_environment")
		if shadow_environment != null and float(shadow_environment) > 0:
			mixed_shadow += 1
			var probe: Vector4 = material.get_shader_parameter("probe_ar")
			check(absf(probe.w - 0.16995363) < 0.0001, "Native ambient SH coefficient")
	check(counts.get("lilToon") == 81 and counts.get("Hidden/lilToonCutout") == 3,
			"Native opaque and cutout material coverage")
	check(emitting == 38, "All originally enabled emission branches were translated")
	check(highlighted == 44, "All gated direct highlights were translated")
	check(mixed_shadow == 10, "All authored ambient shadow blends were translated")
	var shader: Shader = load("res://materials/character_toon.gdshader")
	check("cull_back" in shader.code, "Native back-face culling is enabled")
	var fallback := (load("res://Characters/Reyna.tscn") as PackedScene).instantiate()
	var found := false
	for mesh: MeshInstance3D in fallback.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh.get_surface_count() > 0 and mesh.get_active_material(0) is ShaderMaterial:
			found = true
	check(found, "Static fallback loads the regenerated external material")
	fallback.free()
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	stage.encounter.select_hero(4)
	var turtle: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
	for unit: GuildrunBoardUnit in [stage.encounter._hero, turtle]:
		var outlined := 0
		for mesh: MeshInstance3D in unit.find_children("*", "MeshInstance3D", true, false):
			if not mesh.visible or mesh.material_overlay == null:
				continue
			var outline := mesh.material_overlay as ShaderMaterial
			check(outline.shader.resource_path == "res://materials/character_outline.gdshader", "PC HeroRender overlay")
			check(is_equal_approx(float(outline.get_shader_parameter("thickness")), 0.0004), "Source outline thickness")
			check(outline.render_priority == 8 and outline.next_pass is ShaderMaterial
					and outline.next_pass.render_priority == 9, "Layer 10 redraws its surface after HeroRender")
			outlined += 1
		check(outlined > 0, "Both teams should have a live outline")
	var foreground_count: int = 0
	for sprite: Sprite3D in stage._environment.find_children("*", "Sprite3D", true, false):
		if sprite.render_priority == 24:
			foreground_count += 1
	check(foreground_count == 5, "The morning forest's five original foreground sprites draw after VFXRender")
	check(stage.load_board(10601), "Load the dusk demon stage")
	var demon: GuildrunBoardUnit = stage.grid.occupants.get(Vector2i(3, 4))
	var torso := demon.find_child("Body_002", true, false) as MeshInstance3D if demon else null
	var leaves := demon.find_child("Body_003", true, false) as MeshInstance3D if demon else null
	check(torso != null and torso.get_active_material(0).resource_path == "res://materials/sharedassets1_78.tres"
			and torso.material_overlay != null, "Imported Body_002 uses the authored Body.002 material and outline")
	check(leaves != null and leaves.get_active_material(0).resource_path == "res://materials/sharedassets1_80.tres",
			"Imported Body_003 uses the authored Body.003 cutout")
	check(leaves != null and leaves.material_overlay != null and leaves.material_overlay.next_pass != null,
			"The demon cutout participates in the same original layer-10 draw passes")
	stage.free()
	if "--gpu" in OS.get_cmdline_user_args():
		await verify_gpu()
	print("CHARACTER_MATERIALS 81 opaque, 3 cutout, 38 emitting, 44 direct highlights, 10 ambient shadows")
	quit(1 if failed else 0)


func verify_gpu() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.position.z = 3.0
	viewport.add_child(camera)
	camera.make_current()
	var quad := MeshInstance3D.new()
	var surface := QuadMesh.new()
	surface.size = Vector2(2, 2)
	quad.mesh = surface
	viewport.add_child(quad)
	var material := (load("res://materials/sharedassets1_80.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	var mask := Image.create_empty(8, 2, false, Image.FORMAT_RGBA8)
	mask.fill_rect(Rect2i(0, 0, 4, 2), Color(1, 1, 1, 0.2))
	mask.fill_rect(Rect2i(4, 0, 4, 2), Color(1, 1, 1, 0.8))
	material.set_shader_parameter("main_texture", ImageTexture.create_from_image(mask))
	material.set_shader_parameter("tint", Color.WHITE)
	material.set_shader_parameter("use_emission", true)
	material.set_shader_parameter("emission_color", Color.RED)
	quad.material_override = material
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	check(pixels.get_pixel(41, 64).r < 0.01 and pixels.get_pixel(87, 64).r > 0.25,
			"GPU clips the low-alpha fragment and renders the high-alpha fragment")
	quad.set_instance_shader_parameter(&"death_blend", 0.5)
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().get_pixel(87, 64).r < 0.01,
			"The death override reduces cutout coverage with the authored alpha")
	quad.set_instance_shader_parameter(&"death_blend", 0.0)
	material.set_shader_parameter("cutoff", 0.0)
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().get_pixel(41, 64).r > 0.25, "GPU preserves low alpha in the opaque pass")
	quad.rotation.y = PI
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().get_pixel(87, 64).r < 0.01, "GPU culls the back face")
	quad.rotation.y = 0.0
	material.set_shader_parameter("use_emission", false)
	material.set_shader_parameter("use_shadow", true)
	material.set_shader_parameter("shadow_environment", 0.0)
	material.set_shader_parameter("shadow_color", Color(0.2, 0.2, 0.2, 1))
	material.set_shader_parameter("shade_controls", Vector4(1, 0, 0, 0))
	var sun := DirectionalLight3D.new()
	viewport.add_child(sun)
	await RenderingServer.frame_post_draw
	var direct := viewport.get_texture().get_image().get_pixel(87, 64).r
	sun.rotation.y = TAU / 3.0
	await RenderingServer.frame_post_draw
	var shadow := viewport.get_texture().get_image().get_pixel(87, 64).r
	check(shadow + 0.15 < direct and shadow > 0.01, "GPU renders the translated shadow band")
	material.set_shader_parameter("shadow_environment", 0.69)
	await RenderingServer.frame_post_draw
	var filled_shadow := viewport.get_texture().get_image().get_pixel(87, 64).r
	check(filled_shadow > shadow + 0.01 and filled_shadow < direct, "GPU applies the extracted ambient probe to dark bands")
	material.set_shader_parameter("use_shadow", false)
	material.set_shader_parameter("use_highlight", false)
	material.set_shader_parameter("tint", Color(0.1, 0.1, 0.1, 1.0))
	sun.rotation.y = 0.0
	await RenderingServer.frame_post_draw
	var without_highlight := viewport.get_texture().get_image().get_pixel(87, 64).r
	material.set_shader_parameter("highlight_texture", null)
	material.set_shader_parameter("highlight_color", Color(0.5, 0, 0, 1))
	material.set_shader_parameter("use_highlight", true)
	await RenderingServer.frame_post_draw
	var with_highlight := viewport.get_texture().get_image().get_pixel(87, 64).r
	check(with_highlight > without_highlight + 0.15, "GPU applies the direct toon highlight")
	material.set_shader_parameter("cutoff", 0.5)
	material.set_shader_parameter("use_emission", true)
	material.set_shader_parameter("emission_color", Color.RED)
	await verify_character_pass_order(viewport, quad)
	await verify_emission_screen(viewport, environment.environment, quad, material, sun)
	viewport.free()


func verify_emission_screen(viewport: SubViewport, environment: Environment, body: MeshInstance3D,
		material: ShaderMaterial, sun: DirectionalLight3D) -> void:
	body.material_overlay = null
	material.set_shader_parameter("cutoff", 0.0)
	material.set_shader_parameter("tint", Color(0.45, 0.5, 0.55, 1.0))
	material.set_shader_parameter("emission_color", Color(0.58, 0.46, 0.36, 1.0))
	material.set_shader_parameter("emission_texture", null)
	material.set_shader_parameter("emission_controls", Vector3(1, 2, 0))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.7, 0.65)
	environment.ambient_light_energy = 0.0
	sun.hide()
	await RenderingServer.frame_post_draw
	var emission := viewport.get_texture().get_image().get_pixel(87, 64).srgb_to_linear()
	environment.ambient_light_energy = 0.75
	sun.light_energy = 0.35
	var ambient_red := 0.0
	for direct in [false, true]:
		sun.visible = direct
		material.set_shader_parameter("use_emission", false)
		await RenderingServer.frame_post_draw
		var base := viewport.get_texture().get_image().get_pixel(87, 64).srgb_to_linear()
		if direct:
			check(base.r > ambient_red + 0.02, "The directional light and highlight contribute to the Screen test")
		else:
			ambient_red = base.r
		material.set_shader_parameter("use_emission", true)
		await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image().get_pixel(87, 64)
		var expected := Color(
			base.r + (1.0 - base.r) * emission.r,
			base.g + (1.0 - base.g) * emission.g,
			base.b + (1.0 - base.b) * emission.b).linear_to_srgb()
		check(base.r > 0.005 and absf(expected.r - actual.r) < 3.0 / 255.0
				and absf(expected.g - actual.g) < 3.0 / 255.0
				and absf(expected.b - actual.b) < 3.0 / 255.0,
				"Screen emission blends over all light (direct=%s, expected=%s, actual=%s)" % [direct, expected, actual])


func verify_character_pass_order(viewport: SubViewport, body: MeshInstance3D) -> void:
	var solid := Vector2i(87, 64)
	var cutout := Vector2i(41, 64)
	await RenderingServer.frame_post_draw
	var scene := viewport.get_texture().get_image()
	var surface_color := scene.get_pixelv(solid)
	var glow := MeshInstance3D.new()
	glow.mesh = body.mesh
	glow.position.z = 0.25
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.albedo_color = Color(0, 0, 1, 0.5)
	glow_material.render_priority = 1
	glow.material_override = glow_material
	viewport.add_child(glow)
	await RenderingServer.frame_post_draw
	var early := viewport.get_texture().get_image()
	body.material_overlay = load("res://materials/character_outline_layer10.tres")
	await RenderingServer.frame_post_draw
	var late := viewport.get_texture().get_image()
	var visible := late.get_pixelv(solid)
	var tolerance: float = 0.018 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1.0 / 255.0
	check(early.get_pixelv(solid).b > 0.25
			and absf(visible.r - surface_color.r) <= tolerance
			and absf(visible.g - surface_color.g) <= tolerance
			and absf(visible.b - surface_color.b) <= tolerance,
			"HeroRender02 restores the opaque-lit surface over ordinary world translucency")
	check(early.get_pixelv(cutout).b > 0.25 and early.get_pixelv(cutout).is_equal_approx(late.get_pixelv(cutout)),
			"HeroRender02 does not fill a cutout hole with the opaque scene")
	glow_material.render_priority = 16
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().get_pixelv(solid).b > 0.25,
			"VFXRender covers the restored character surface")
	var foreground := glow.duplicate() as MeshInstance3D
	foreground.position.z = 0.5
	var foreground_material := glow_material.duplicate() as StandardMaterial3D
	foreground_material.albedo_color = Color.GREEN
	foreground_material.render_priority = 24
	foreground.material_override = foreground_material
	viewport.add_child(foreground)
	await RenderingServer.frame_post_draw
	var front := viewport.get_texture().get_image().get_pixelv(solid)
	check(front.is_equal_approx(Color.GREEN), "ForegroundRender covers layer 8")
	foreground.free()
	glow.free()


func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
