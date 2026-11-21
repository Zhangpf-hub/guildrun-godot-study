extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func expect(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)


func verify_hdr_response(stage: Node, morning: CanvasLayer) -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(71, 49)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.compositor = Compositor.new()
	var code: RDShaderSPIRV = stage._postprocess_shader("battle_bloom")
	var bloom: CompositorEffect = load("res://materials/battle_bloom.gd").new()
	bloom.configure(code, morning.get_meta("bloom_filter"), morning.get_meta("bloom_strength"),
			morning.get_meta("bloom_quality"))
	camera.compositor.compositor_effects = [bloom]
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	viewport.add_child(camera)
	camera.make_current()
	# Constant linear inputs below the knee, on the knee, and above the threshold.
	# Expected output includes additive bloom and conversion to the SDR target.
	var samples := [Vector2(0.18, 0.46135613), Vector2(0.5, 0.78768897), Vector2(0.85, 1.0)]
	for sample: Vector2 in samples:
		camera.environment.background_color = (Color.WHITE * sample.x).linear_to_srgb()
		for frame in 3:
			await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image().get_pixel(19, 17).r
		expect(absf(actual - sample.y) < 2.0 / 255.0, "Incorrect HDR bloom response for %s: %s" % [sample.x, actual])
		viewport.size += Vector2i(7, 12)

	var source_grade: ShaderMaterial = morning.get_node("ColorGrade").material
	var material := source_grade.duplicate() as ShaderMaterial
	material.set_shader_parameter("grade_lookup", null)
	material.set_shader_parameter("exposure", 0.8)
	material.set_shader_parameter("vignette_color", Vector3.ZERO)
	material.set_shader_parameter("vignette_intensity", 1.5)
	material.set_shader_parameter("vignette_smoothness", 1.0)
	material.set_shader_parameter("vignette_rounded", true)
	var combined: CompositorEffect = load("res://materials/battle_bloom.gd").new()
	combined.configure(code, morning.get_meta("bloom_filter"), morning.get_meta("bloom_strength"),
			morning.get_meta("bloom_quality"))
	combined.configure_hdr_grade(material)
	camera.compositor.compositor_effects = [combined]
	viewport.size = Vector2i(71, 49)
	for frame in 3:
		await RenderingServer.frame_post_draw
	var graded := viewport.get_texture().get_image()
	# Linear 0.85 plus bloom yields 1.4867. Exposure 0.8 and the rounded vignette
	# reduce it to 0.4929 at the side, or 0.7306 in sRGB.
	expect(absf(graded.get_pixel(10, 24).r - 0.7305758) < 2.0 / 255.0 and graded.get_pixel(35, 24).r > 0.99,
			"HDR exposure or vignette clipped the bloom before grading: %s" % [graded.get_pixel(10, 24)])

	material.set_shader_parameter("exposure", 1.2)
	material.set_shader_parameter("vignette_intensity", 0.0)
	material.set_shader_parameter("neutral_tonemap", true)
	var neutral: CompositorEffect = load("res://materials/battle_bloom.gd").new()
	neutral.configure(code, Vector4.ZERO, Vector4.ZERO, Vector3i.ZERO)
	neutral.configure_hdr_grade(material)
	camera.compositor.compositor_effects = [neutral]
	for sample: Vector2 in [Vector2(0.18, 0.49963974), Vector2(1.2, 0.8780014), Vector2(2.4, 0.96859943)]:
		camera.environment.background_color = (Color.WHITE * sample.x).linear_to_srgb()
		for frame in 3:
			await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image().get_pixel(35, 24).r
		expect(absf(actual - sample.y) < 2.0 / 255.0, "Incorrect HDR Neutral response for %s: %s" % [sample.x, actual])

	material.set_shader_parameter("exposure", 1.0)
	material.set_shader_parameter("neutral_tonemap", false)
	material.set_shader_parameter("grade_lookup", source_grade.get_shader_parameter("grade_lookup"))
	var lut: CompositorEffect = load("res://materials/battle_bloom.gd").new()
	lut.configure(code, Vector4.ZERO, Vector4.ZERO, Vector3i.ZERO)
	lut.configure_hdr_grade(material)
	camera.compositor.compositor_effects = [lut]
	camera.environment.background_color = Color(10.5 / 31, 17.25 / 31, 25.75 / 31).linear_to_srgb()
	# Samples midway between RGB grid points exercise both bilinear reads and blue interpolation.
	var colors: Array[Vector3] = [
		Vector3(0.70278, 0.74907, 0.86588), Vector3(0.65168, 0.72031, 0.87725),
		Vector3(0.73689, 0.74907, 0.78066), Vector3(0.70235, 0.71972, 0.76646),
	]
	for strip in colors.size():
		lut.set_grade_strip(strip)
		for frame in 3:
			await RenderingServer.frame_post_draw
		var pixel := viewport.get_texture().get_image().get_pixel(35, 24)
		var error := (Vector3(pixel.r, pixel.g, pixel.b) - colors[strip]).abs()
		expect(error[error.max_axis_index()] < 2.0 / 255.0, "Wrong LUT color in strip %s: %s" % [strip, pixel])
	viewport.free()


func verify_panel_depth_response(effect: CompositorEffect) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(192, 96)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.compositor = Compositor.new()
	camera.compositor.compositor_effects = [effect]
	viewport.add_child(camera)
	camera.make_current()
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = "shader_type spatial; render_mode unshaded; void fragment() { ALBEDO = vec3(float(int(FRAGCOORD.x) % 2)); }"
	var depths := [8.0, 11.0, 30.0]
	for i in depths.size():
		var depth: float = depths[i]
		var height := 2.0 * depth * tan(deg_to_rad(camera.fov) * 0.5)
		var card := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(height * 2.0 / 3.0, height)
		card.mesh = quad
		card.material_override = material
		card.position = Vector3(float(i - 1) * quad.size.x, 0.0, -depth)
		viewport.add_child(card)
	var was_enabled := effect.enabled
	effect.enabled = false
	for frame in 3:
		await RenderingServer.frame_post_draw
	var sharp := viewport.get_texture().get_image()
	effect.enabled = true
	for frame in 3:
		await RenderingServer.frame_post_draw
	var filtered := viewport.get_texture().get_image()
	var contrast: Array[float] = []
	for x in [32, 96, 160]:
		var source_delta := absf(sharp.get_pixel(x, 48).r - sharp.get_pixel(x + 1, 48).r)
		expect(source_delta > 0.95, "Depth-of-field source stripes should start sharp")
		contrast.append(absf(filtered.get_pixel(x, 48).r - filtered.get_pixel(x + 1, 48).r))
	# At 11 units CoC is 1/15 and the blur blends towards uniform linear gray.
	var blend := sqrt(TAU / 15.0)
	var dark := (Color.WHITE * (0.5 * blend)).linear_to_srgb().r
	var bright := (Color.WHITE * (1.0 - 0.5 * blend)).linear_to_srgb().r
	expect(contrast[0] > 0.95 and absf(contrast[1] - (bright - dark)) < 2.0 / 255.0 and contrast[2] < 0.05,
			"Wrong foreground, falloff or far blur contrast: %s" % [contrast])
	effect.enabled = was_enabled
	viewport.free()


func verify_shaft_depth_response() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color.BLACK
	viewport.add_child(camera)
	camera.make_current()
	var quad := QuadMesh.new()
	quad.size = Vector2(12.0, 12.0)
	var wall := MeshInstance3D.new()
	wall.mesh = quad
	var opaque := StandardMaterial3D.new()
	opaque.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	opaque.albedo_color = Color.BLACK
	wall.material_override = opaque
	viewport.add_child(wall)
	var shaft := MeshInstance3D.new()
	shaft.mesh = quad
	shaft.position.z = -5.0
	var material := ShaderMaterial.new()
	material.shader = load("res://materials/forest_light_shafts.gdshader")
	var pixel := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	pixel.fill(Color.WHITE)
	var white := ImageTexture.create_from_image(pixel)
	material.set_shader_parameter("beam_texture", white)
	material.set_shader_parameter("beam_mask", white)
	material.set_shader_parameter("fade_distance", 3.0)
	shaft.material_override = material
	viewport.add_child(shaft)
	var linear := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	for additive in [false, true]:
		material.set_shader_parameter("additive", additive)
		for gap in [-1.0, 0.75, 3.0]:
			wall.position.z = shaft.position.z - gap
			for frame in 3:
				await RenderingServer.frame_post_draw
			var color := viewport.get_texture().get_image().get_pixel(32, 32)
			var sample := color.srgb_to_linear().r if linear else color.r
			expect(absf(sample - clampf(gap / 3.0, 0.0, 1.0)) < 0.012,
					"Wrong shaft opacity at opaque depth gap %s (additive %s): %s" % [gap, additive, sample])
	viewport.free()


func verify_ground_glow_response(source: ShaderMaterial) -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color.BLACK
	viewport.add_child(camera)
	camera.make_current()
	var quad := QuadMesh.new()
	quad.size = Vector2(12.0, 12.0)
	var glow := MeshInstance3D.new()
	glow.mesh = quad
	glow.position.z = -5.0
	var material := source.duplicate() as ShaderMaterial
	material.set_shader_parameter("alignment", 0)
	var pixel := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	pixel.fill(Color.WHITE)
	var white := ImageTexture.create_from_image(pixel)
	pixel.fill(Color(64.0 / 255.0, 0.0, 0.0))
	material.set_shader_parameter("main_texture", ImageTexture.create_from_image(pixel))
	for uniform in ["mask_texture", "distortion_texture", "dissolve_texture"]:
		material.set_shader_parameter(uniform, white)
	glow.material_override = material
	viewport.add_child(glow)
	var linear := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	for double_opacity in [false, true]:
		material.set_shader_parameter("double_opacity", double_opacity)
		glow.set_instance_shader_parameter("particle_tint", Color(1.0, 1.0, 1.0, 0.4))
		for frame in 3:
			await RenderingServer.frame_post_draw
		var color := viewport.get_texture().get_image().get_pixel(32, 32)
		var sample := color.srgb_to_linear().r if linear else color.r
		# Source red sample, dissolve factor (1 + 0.5), particle alpha, HDR tint.
		var expected := (64.0 / 255.0) * 1.5 * 0.4 * sqrt(2.0)
		expect(absf(sample - expected * (2.0 if double_opacity else 1.0)) < 0.012,
				"Ground light should apply the native opacity branch and HDR material tint")
	viewport.free()


func verify_shadow_receiver_response() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.position.y = 4.0
	camera.rotation.x = -PI / 2.0
	viewport.add_child(camera)
	camera.make_current()
	var quad := PlaneMesh.new()
	quad.size = Vector2(4.0, 4.0)
	var ground := MeshInstance3D.new()
	ground.mesh = quad
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.material_override = white
	viewport.add_child(ground)
	var receiver := MeshInstance3D.new()
	receiver.mesh = quad
	receiver.position.y = 0.05
	receiver.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow := (load("res://materials/sharedassets7_10.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	receiver.material_override = shadow
	viewport.add_child(receiver)
	var caster := MeshInstance3D.new()
	caster.mesh = BoxMesh.new()
	caster.position.y = 1.0
	viewport.add_child(caster)
	var sun := DirectionalLight3D.new()
	sun.rotation.x = -PI / 4.0
	sun.light_color = Color.CYAN
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 10.0
	viewport.add_child(sun)
	var point := OmniLight3D.new()
	point.light_color = Color.RED
	point.position.y = 2.0
	viewport.add_child(point)
	var tint: Color = shadow.get_shader_parameter("shadow_tint")
	# A black receiver with alpha 1 exposes the backend's filtered shadow coverage.
	shadow.set_shader_parameter("shadow_tint", Color.BLACK)
	for frame in 4:
		await RenderingServer.frame_post_draw
	var mask := viewport.get_texture().get_image()
	var sample := Vector2i(32, 17)
	var coverage := 0.0
	for y in range(6, 23):
		var pixel := mask.get_pixel(32, y)
		var amount := 1.0 - pixel.srgb_to_linear().r
		if amount > coverage:
			sample.y = y
			coverage = amount
	expect(coverage > 0.1, "The angled light must cast a measurable shadow outside the mesh silhouette")
	shadow.set_shader_parameter("shadow_tint", tint)
	for strength in [0.0, 0.5, 1.0]:
		sun.shadow_opacity = strength
		for frame in 4:
			await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var center := image.get_pixelv(sample)
		var expected := Color.WHITE.lerp(tint.srgb_to_linear(), tint.a * strength * coverage).linear_to_srgb()
		var error := (Vector3(center.r, center.g, center.b) - Vector3(expected.r, expected.g, expected.b)).abs()
		expect(error[error.max_axis_index()] < 0.01 and image.get_pixel(10, 48).r > 0.98,
				"ShadowDrawer opacity and tint at strength %s: %s, expected %s" % [strength, center, expected])
	var before_point_shadow := viewport.get_texture().get_image().get_pixelv(sample)
	point.position.z = 1.5
	point.shadow_enabled = true
	for frame in 4:
		await RenderingServer.frame_post_draw
	var after_point_shadow := viewport.get_texture().get_image().get_pixelv(sample)
	expect(absf(before_point_shadow.r - after_point_shadow.r) < 0.01,
			"ShadowDrawer must ignore additional lights and their shadows")
	viewport.free()


func verify() -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var morning: CanvasLayer = stage._environment.get_node("BattleVolume")
	var material := morning.get_node("ColorGrade").material as ShaderMaterial
	expect(morning.layer < stage.encounter._ui.get_canvas_layer_node().layer, "Grade must run before battle UI")
	expect(str(morning.get_meta("unity_profiles")).contains("level12:641"), "Wrong normal morning Volume")
	expect(is_equal_approx(float(material.get_shader_parameter("exposure")), pow(2, 0.4)), "Wrong morning EV")
	var world := morning.get_node("WorldEffects") as WorldEnvironment
	var far_plane: Node3D = stage._environment.find_child("Background_02", true, false)
	var backdrop := far_plane.get_node_or_null("UnitySprite") as Sprite3D if far_plane else null
	expect(backdrop != null and backdrop.offset.is_equal_approx(Vector2(0.0, 205.038147)),
			"The cropped far backdrop must keep its original pivot")
	var near_plane: Node3D = stage._environment.find_child("Foreground_01", true, false)
	var foreground := near_plane.get_node_or_null("UnitySprite") as Sprite3D if near_plane else null
	expect(foreground != null and foreground.offset.is_equal_approx(Vector2(56.538033, -53.538086)),
			"The cropped foreground must keep its original pivot")
	var hdr_bloom := RenderingServer.get_current_rendering_method() == "forward_plus" and RenderingServer.get_rendering_device() != null
	expect(morning.get_node("ColorGrade").visible != hdr_bloom,
			"The canvas fallback should be hidden when Forward+ applies the full grade")
	var bloom_filter: Vector4 = morning.get_meta("bloom_filter", Vector4.ZERO)
	expect(bloom_filter.is_equal_approx(Vector4(0.32, 65472.0, 0.60382734, 0.30191367)), "Wrong morning bloom filter")
	expect(morning.get_meta("bloom_quality", Vector3i.ZERO) == Vector3i(1, 1, 6), "Wrong morning bloom pyramid")
	var bloom_strength: Vector4 = morning.get_meta("bloom_strength", Vector4.ZERO)
	expect(bloom_strength.is_equal_approx(Vector4(1.0, 1.0, 1.0, 2.56)), "Wrong morning bloom tint or intensity")
	var ambient_settings: Vector4 = morning.get_meta("ambient_occlusion", Vector4.ZERO)
	expect(ambient_settings.is_equal_approx(Vector4(0.3, 0.4, 100.0, 0.25)), "Wrong PC renderer ambient occlusion parameters")
	if hdr_bloom:
		expect(world.compositor != null and world.compositor.compositor_effects.size() == 3 and not world.environment.glow_enabled,
				"The HDR bloom should replace built-in glow on Forward+")
		expect(stage._panel_dof != null and not stage._panel_dof.enabled and
				world.compositor.compositor_effects[1] == stage._panel_dof, "Panel depth must precede bloom and start disabled")
		if world.compositor != null and world.compositor.compositor_effects.size() == 3:
			var ambient: CompositorEffect = world.compositor.compositor_effects[0]
			expect(ambient.effect_callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_OPAQUE
					and ambient.needs_normal_roughness and not world.environment.ssao_enabled,
					"Environment AO should resolve depth and normals before opaque drawing")
			for i in 3:
				await RenderingServer.frame_post_draw
			expect(ambient._visibility.get_width() > 0, "Environment AO visibility was never published")
	else:
		expect(world.environment.glow_enabled and is_equal_approx(world.environment.glow_hdr_threshold, 0.8), "Missing built-in glow fallback")
	var shafts := morning.get_parent().find_children("UnityLightShaft1", "MeshInstance3D", true, false)
	expect(shafts.size() == 4, "Missing morning shaft emitters")
	for shaft: MeshInstance3D in shafts:
		var emitter: Node3D = shaft.get_parent()
		var second := emitter.get_node_or_null("UnityLightShaft2") as MeshInstance3D
		expect(second != null and emitter._particles.size() == 2 and shaft.visible and second.visible,
				"Each source emitter prewarms with a two-particle limit")
		expect(emitter.prewarm and emitter.source_seed == -1 and is_equal_approx(emitter.duration, 5.0)
				and emitter.lifetime_range == Vector2(8.0, 12.0) and emitter.emission_cylinder == Vector2(5.0, 2.0),
				"Forest beam prewarm, lifetime and emission volume must match the source")
		var rate: float = 2.0 if emitter.name == &"Rays_02" else 1.0
		expect(emitter.births_per_second == rate and emitter.independent_height,
				"Source rate and independent width and height must survive the particle cap")
		var beam := (shaft.mesh as QuadMesh).material as ShaderMaterial
		expect(beam.render_priority == 1 and is_equal_approx(beam.get_shader_parameter("fade_distance"), 3.0),
				"Forest rays should use the material's transparent order and opaque-depth fade")
		expect((beam.get_shader_parameter("beam_is_srgb") == true) == (beam.get_shader_parameter("additive") == true),
				"The colored rays use an sRGB intensity map and the blurry rays use a linear map")
	var glows: Array[Node] = stage._environment.find_children("UnityGlow*", "MeshInstance3D", true, false)
	expect(glows.size() == 21, "Wrong number of morning glow particle slots")
	var gradient: Node3D = stage._environment.find_child("Gradient_01", true, false)
	var gradient_quad := gradient.get_node_or_null("UnityGlow1") as MeshInstance3D if gradient else null
	if gradient_quad != null:
		var gradient_glow := (gradient_quad.mesh as QuadMesh).material as ShaderMaterial
		expect(gradient.looping and gradient.prewarm and is_equal_approx(gradient.simulation_speed, 0.5)
				and gradient.lifetime_range == Vector2(4.0, 5.0), "Wrong morning gradient emission")
		expect(not gradient_glow.get_shader_parameter("additive") and
				is_equal_approx(gradient_glow.get_shader_parameter("fade_distance"), 4.0), "Wrong gradient depth blend")
	else:
		expect(false, "Missing morning gradient particle")
	var ground: Node3D = stage._environment.find_child("Ground_Glow_Left", true, false)
	var ground_quad := ground.get_node_or_null("UnityGlow1") as MeshInstance3D if ground else null
	var ground_glow: ShaderMaterial
	if ground_quad != null:
		ground_glow = (ground_quad.mesh as QuadMesh).material as ShaderMaterial
		expect(ground.get_child_count() == 2 and ground_quad.visible and not ground.is_processing(), "Wrong ground glow burst")
		expect(ground_glow.get_shader_parameter("animated_ground") and ground_glow.get_shader_parameter("additive")
				and is_equal_approx(ground_glow.get_shader_parameter("alpha_cutoff"), 0.007)
				and ground_glow.get_shader_parameter("double_opacity") == true
				and ground_glow.get_shader_parameter("material_tint").is_equal_approx(Vector3.ONE * sqrt(2.0)),
				"Wrong ground glow material")
	else:
		expect(false, "Missing morning ground light")
	var shine: Node = stage._environment.find_child("PlayStage_Crystal_Shine", true, false)
	var glow_mesh := shine.get_node_or_null("UnityMesh") as MeshInstance3D if shine else null
	var sweep := glow_mesh.get_surface_override_material(0) as ShaderMaterial if glow_mesh else null
	expect(sweep != null and sweep.shader.resource_path.ends_with("forest_crystal_shine.gdshader")
			and sweep.get_shader_parameter("crystal_mask") is Texture2D
			and is_equal_approx(sweep.get_shader_parameter("intensity"), 0.4), "Missing native additive crystal sweep")
	var lights: Array[Node] = stage._environment.find_children("*", "DirectionalLight3D", true, false)
	expect(lights.size() == 1, "Missing morning directional light")
	if lights.size() == 1:
		var sun := lights[0] as DirectionalLight3D
		expect(float(sun.get_meta("unity_color_temperature", 0)) == 5000.0, "Missing morning sunlight temperature")
		expect(sun.light_energy == 4.0 and sun.light_color.b < 1.0, "Morning temperature did not tint direct light")
		expect(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL
				and sun.directional_shadow_max_distance == 150.0 and sun.shadow_opacity == 1.0,
				"Expected the PC single directional shadow map and authored strength")
	var shadow_plane: Node3D = stage._environment.find_child("ShadowPlane", true, false)
	var receiver := shadow_plane.get_node("UnityMesh") as MeshInstance3D
	var receiver_material := receiver.get_active_material(0) as ShaderMaterial
	expect(receiver_material != null and receiver_material.shader.resource_path.ends_with("battle_shadow_receiver.gdshader")
			and is_equal_approx(receiver_material.get_shader_parameter("shadow_tint").a, 0.68627453)
			and receiver.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Missing native shadow receiver")
	var gates: Array[Node] = stage._crossroads_gates()
	var hover := gates[0].get_node("VFX_Hover") as Node3D
	expect(not hover.visible and hover.find_children("UnityRay", "MeshInstance3D", true, false).size() == 1,
			"Gate hover beam is missing or visible outside the crossroads")
	(gates[0] as Node3D).show()
	stage.set_crossroads_gate_hover(0)
	expect(hover.visible, "Gate did not turn on its beam when hovered")
	stage.set_crossroads_gate_hover(-1)
	expect(not hover.visible, "Beam remained visible after the pointer left")
	(gates[0] as Node3D).hide()
	stage.encounter.select_hero(4)
	stage.encounter.start_fight()
	stage.encounter._hero.take_damage(stage.encounter._hero.health)
	stage.encounter._advance_battle_tick(0.0)
	stage.encounter._physics_process(1.0)
	expect(stage.encounter.phase == GuildrunEncounter.Phase.RESULT, "Defeat did not enter result")
	expect(int(material.get_shader_parameter("grade_strip")) == 3, "Defeat should combine the results curve and desaturation")
	var lens := root.get_camera_3d().attributes as CameraAttributesPractical
	var depth_supported := RenderingServer.get_current_rendering_method() in ["forward_plus", "mobile"]
	if hdr_bloom:
		expect(stage._panel_dof != null and stage._panel_dof.enabled and not lens.dof_blur_far_enabled,
				"The result should enable URP Gaussian depth of field once")
	elif depth_supported:
		expect(lens != null and lens.dof_blur_far_enabled and is_equal_approx(lens.dof_blur_far_distance, 10.0)
				and is_equal_approx(lens.dof_blur_far_transition, 15.0), "Missing camera-depth result blur")
	expect(is_equal_approx(float(material.get_shader_parameter("result_blur")), 0.0 if depth_supported else 2.5),
			"Result blur should use one rendering path")
	stage.encounter.phase = GuildrunEncounter.Phase.SHOP
	expect(int(material.get_shader_parameter("grade_strip")) == 1, "Shop should use the panel curve at normal saturation")
	expect(stage._panel_dof.enabled if hdr_bloom else (lens == null or lens.dof_blur_far_enabled), "Shop lost its far depth of field")
	stage.encounter.phase = GuildrunEncounter.Phase.PLACE
	expect(int(material.get_shader_parameter("grade_strip")) == 0, "Panel color curve leaked into deployment")
	expect((stage._panel_dof == null or not stage._panel_dof.enabled) and (lens == null or not lens.dof_blur_far_enabled) and
			is_zero_approx(float(material.get_shader_parameter("result_blur"))), "Panel blur leaked into deployment")
	var color: Vector3 = material.get_shader_parameter("vignette_color")
	expect(color.is_equal_approx(Vector3(0.26666668, 0.19215687, 0.16078432)), "Wrong morning vignette tint")
	if hdr_bloom and world.compositor != null:
		await verify_hdr_response(stage, morning)
		if stage._panel_dof != null:
			await verify_panel_depth_response(stage._panel_dof)
	if DisplayServer.get_name() != "headless":
		await verify_shaft_depth_response()
		if ground_glow != null:
			await verify_ground_glow_response(ground_glow)
		await verify_shadow_receiver_response()
	var count := 0
	for environment: String in stage._environment_paths:
		var path := "res://materials/volumes/%s.tscn" % environment
		expect(ResourceLoader.exists(path), "Missing volume binding for " + environment)
		if not ResourceLoader.exists(path):
			continue
		var layer: CanvasLayer = load(path).instantiate()
		var grade := layer.get_node("ColorGrade").material as ShaderMaterial
		expect(grade.shader == material.shader, "Unexpected grading shader in " + environment)
		var table := grade.get_shader_parameter("grade_lookup") as Texture2D
		expect(table != null and table.get_size() == Vector2(1024, 128), "Missing four 32^3 LUT strips in " + environment)
		expect(str(layer.get_meta("unity_profiles")).contains("level3:26856"), "Missing camera base Volume")
		expect(layer.get_meta("ambient_occlusion", Vector4.ZERO) == ambient_settings, "Missing PC renderer AO in " + environment)
		if environment == "Environment_BossRoom":
			expect(bool(grade.get_shader_parameter("neutral_tonemap")), "Boss room lost neutral tonemapping")
		layer.free()
		count += 1
	expect(count == 14, "Expected fourteen source environment bindings")
	stage.set_panel_grade(true)
	var morning_dof: CompositorEffect = stage._panel_dof
	for id: int in stage._stages:
		if stage.field(stage._stages[id], "EnvironmentSceneName") == "Environment_Default_3Gates_Evening":
			stage.load_board(id)
			break
	expect(not is_instance_valid(morning), "Previous Volume survived scene switch")
	var evening: CanvasLayer = stage._environment.get_node("BattleVolume")
	expect(str(evening.get_meta("unity_profiles")).contains("level11:678"), "Wrong evening profile after switch")
	expect(stage._environment.find_children("UnityGlow*", "MeshInstance3D", true, false).size() == 14,
			"Evening should retain the crystal emitters from its source scene")
	var evening_filter: Vector4 = evening.get_meta("bloom_filter", Vector4.ZERO)
	expect(is_equal_approx(evening_filter.z, 0.69207106), "Wrong evening linear bloom threshold after switch")
	if hdr_bloom:
		var evening_world := evening.get_node("WorldEffects") as WorldEnvironment
		expect(evening_world.compositor != null and not evening_world.environment.glow_enabled, "HDR bloom was lost on stage change")
		expect(not evening.get_node("ColorGrade").visible and
				evening_world.compositor.compositor_effects[-1] == stage._hdr_postprocess,
				"HDR grading was lost on stage change")
		expect(stage._panel_dof != null and stage._panel_dof != morning_dof and stage._panel_dof.enabled,
				"Scene switch lost an active panel depth effect")
		await RenderingServer.frame_post_draw
	stage.set_panel_grade(false)
	stage.free()
	if not failed:
		print("Battle Volume: fourteen profiles, LUT strips, sprite pivots, lights, depth, bloom and HDR grading OK")
	quit(int(failed))
