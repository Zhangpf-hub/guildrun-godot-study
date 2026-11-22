extends SceneTree

func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var scene: PackedScene = load("res://battle/stage.tscn")
	var stage = scene.instantiate()
	root.add_child(stage)
	if not check_kai(stage):
		push_error("Kai shield, timing, or damage mismatch")
		quit(1)
		return
	stage.free()
	stage = scene.instantiate()
	root.add_child(stage)
	if not check_yuuna(stage):
		push_error("Yuuna cast, retargeting, landing, or action effect mismatch")
		quit(1)
		return
	stage.free()
	print("Verified Kai's shield and area damage, and Yuuna's volley, landing and action effects.")
	quit()


func check_kai(stage: Node3D) -> bool:
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(26)
	var kai := fight._hero
	var turtle: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
	kai.base_stats = kai.base_stats.duplicate(true)
	kai.base_stats["<Crit>k__BackingField"] = 0
	fight._claim_cell(kai, Vector2i(3, 3))
	kai.position = GuildrunBattleGrid.center(kai.grid_cell)
	var distant: GuildrunBoardUnit = stage.spawn_unit(turtle.base_stats, Vector2i(0, 7), 0, false)
	fight._register(distant)
	var initial_hp := turtle.health
	var distant_hp := distant.health
	kai.mana = int(kai.stat("MaxMana"))
	kai.begin_active_ability()
	if kai.total_shield() != 400:
		return false
	var kai_hp := kai.health
	kai.take_damage(75)
	fight._tick_cast(kai, 171485)
	if kai.health != kai_hp or kai.total_shield() != 325 or not fight._strike_areas.is_empty():
		return false
	fight._tick_cast(kai, 1)
	fight._advance_strike_areas(32112)
	if turtle.health != initial_hp or kai.mana != 0:
		return false
	fight._advance_strike_areas(1)
	var damage := turtle.damage_after_defense(137) + turtle.damage_after_defense(325)
	fight._advance_strike_areas(65536)
	if turtle.health != initial_hp - damage or distant.health != distant_hp or not fight._strike_areas.is_empty():
		return false
	kai.shields.append({"amount": 20, "remaining": 2})
	kai.take_damage(15)
	kai.tick_shields(2)
	if kai.total_shield() != 325:
		return false
	kai.tick_shields(10 * 65536 - 3)
	if kai.total_shield() != 325:
		return false
	kai.tick_shields(1)
	kai.take_damage(2)
	return kai.total_shield() == 0 and kai.health == kai_hp - 2


func check_yuuna(stage: Node3D) -> bool:
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	fight._effect_scene_time = 8.0
	fight._advance_effect_scene_time(0.5)
	var yuuna := fight._hero
	var turtle: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
	var weak: GuildrunBoardUnit = stage.spawn_unit(turtle.base_stats, Vector2i(0, 7), 0, false)
	fight._register(weak)
	# The first two rolls for this seed are both above Yuuna's 50% crit chance.
	fight._combat_rng.reseed(1940)
	weak.health = 1
	var initial_hp := turtle.health
	var start := yuuna.grid_cell
	yuuna.mana = int(yuuna.stat("MaxMana"))
	yuuna.begin_active_ability()
	var effect := yuuna._yuna_skill_effect
	var charge := yuuna._yuna_charge_effect
	if effect == null or not is_equal_approx(effect.lead_in, 2.65):
		return false
	if charge == null or not is_equal_approx(charge.lead_in, 1.62):
		return false
	var mount := yuuna._yuna_charge_mount
	if mount.get_skeleton().get_bone_name(mount.bone_idx) != &"hand_R":
		return false
	yuuna.set_death_appearance_speed(0.0)
	effect._process(10.0)
	charge._process(10.0)
	if not is_zero_approx(effect._elapsed) or not is_zero_approx(charge._elapsed):
		return false
	yuuna.set_death_appearance_speed(2.0)
	if not check_yuuna_wind_effect(yuuna):
		return false
	var wide_flare := charge.get_node("Flare_02")
	charge._process(0.8)
	if charge.get_node("Flare_01").get_child_count() != 0 or wide_flare.get_child_count() != 0:
		return false
	mount.on_skeleton_update()
	charge._process(0.02)
	if charge.get_node("Flare_01").get_child_count() != 1 or charge.get_node("Circle_01").get_child_count() != 1:
		return false
	if wide_flare.get_child_count() != 1:
		return false
	var wide_quad := wide_flare.get_child(0) as MeshInstance3D
	var wide_material := wide_quad.material_override as ShaderMaterial
	var flare_stream: Vector3 = wide_material.get_shader_parameter(&"flare_stream")
	if (not wide_quad.top_level or flare_stream.x < 0.0 or flare_stream.x > 120.0
			or not is_equal_approx(flare_stream.y, -0.4) or not is_equal_approx(flare_stream.z, 3.99)
			or not is_equal_approx(wide_material.get_shader_parameter(&"flare_time"), 1.64)):
		return false
	for particle: Variant in charge._particles:
		if particle.source == wide_flare and not is_equal_approx(particle.size.x, 11.4):
			return false
	var wide_position := wide_quad.global_position
	if not charge.global_position.is_equal_approx(mount.global_position):
		return false
	var arc_source := charge.get_node("Charge_01")
	var center := charge.get_node("Center_01")
	var lines := charge.get_node("Line_01")
	charge._process(0.035)
	if arc_source.get_child_count() != 0 or center.get_child_count() != 0:
		return false
	charge._process(0.01)
	if arc_source.get_child_count() != 3 or center.get_child_count() != 1 or lines.get_child_count() != 3:
		return false
	var arc := arc_source.get_child(0) as MeshInstance3D
	var flare := charge.get_node("Flare_01").get_child(0) as MeshInstance3D
	var flare_position := flare.global_position
	var arc_position := arc.global_position
	var shader := arc.material_override as ShaderMaterial
	var initial_dissolve: Vector3 = shader.get_shader_parameter(&"dissolve_data")
	mount.position += Vector3.RIGHT
	charge._process(0.05)
	if arc_source.get_child_count() != 6 or arc.mesh == null:
		return false
	if not flare.global_position.is_equal_approx(flare_position) or arc.global_position.is_equal_approx(arc_position):
		return false
	if (not wide_quad.global_position.is_equal_approx(wide_position)
			or not is_equal_approx(wide_material.get_shader_parameter(&"flare_time"), 1.83)):
		return false
	var advanced_dissolve: Vector3 = shader.get_shader_parameter(&"dissolve_data")
	if advanced_dissolve.y <= initial_dissolve.y:
		return false
	mount.on_skeleton_update()
	charge._process(0.025)
	if arc_source.get_child_count() != 8:
		return false
	charge._process((2.65 - charge._elapsed) / 2.0)
	if charge.is_queued_for_deletion() or wide_flare.get_child_count() != 1:
		return false
	charge._process((2.83 - charge._elapsed) / 2.0)
	if not wide_quad.is_queued_for_deletion() or charge.is_queued_for_deletion():
		return false
	charge._process((2.93 - charge._elapsed) / 2.0)
	if not charge.is_queued_for_deletion():
		return false
	if not check_yuuna_throw_effects(yuuna):
		return false
	var smoke := effect.get_node("Smoke_01")
	effect._process(1.32)
	if effect.get_node("Spikes_01").get_child_count() != 0 or smoke.get_child_count() != 0:
		return false
	if not is_equal_approx(effect.duration, 3.0):
		return false
	effect._process(0.01)
	if not effect.top_level or effect.get_node("CoreWhite_01").get_child_count() != 0 or smoke.get_child_count() != 5:
		return false
	var first_smoke := smoke.get_child(0) as MeshInstance3D
	var smoke_material := first_smoke.material_override as ShaderMaterial
	var smoke_dissolve: Vector3 = smoke_material.get_shader_parameter(&"dissolve_data")
	if not smoke_material.get_shader_parameter(&"custom_dissolve") or smoke_dissolve.x <= 0.0:
		return false
	var smoke_redraw := smoke_material.next_pass as ShaderMaterial
	if (smoke_redraw == null or smoke_redraw.render_priority != 32
			or not smoke_redraw.get_shader_parameter(&"on_hit_vfx_redraw")
			or smoke_material.get_shader_parameter(&"on_hit_vfx_redraw")
			or not smoke_redraw.get_shader_parameter(&"compensate_dark_blend")
			or smoke_redraw.get_shader_parameter(&"dissolve_data") != smoke_dissolve):
		return false
	var impact_anchor: Vector3 = effect.global_position
	yuuna.set_visual_offset(Vector3.RIGHT)
	effect._process(0.025)
	if smoke.get_child_count() != 10 or effect.get_node("CoreWhite_01").get_child_count() != 0:
		return false
	effect._process(0.075)
	if not effect.global_position.is_equal_approx(impact_anchor):
		return false
	yuuna.set_visual_offset(Vector3.ZERO)
	if effect.get_node("Spikes_01").get_child_count() != 1 or effect.get_node("Glow_01").get_child_count() != 1:
		return false
	if effect.get_node("CoreWhite_01").get_child_count() != 1 or smoke.get_child_count() != 10:
		return false
	if not is_equal_approx(smoke.position.y, 0.57):
		return false
	var core_rolls := {"CoreWhite_01": deg_to_rad(204.8808), "Spikes_01": deg_to_rad(356.9663)}
	for particle: Variant in effect._particles:
		var emitter_name: String = particle.source.name
		if core_rolls.has(emitter_name):
			if (not is_equal_approx(particle.angles.z, core_rolls[emitter_name])
					or not is_equal_approx(particle.size.x, 9.12)):
				return false
		if particle.source != smoke:
			continue
		var source: Dictionary = particle.profile
		var shape_basis := Basis.from_euler(source.shape_rotation, EULER_ORDER_YXZ)
		var birth: Vector3 = shape_basis.inverse() * (particle.point - source.shape_position) / source.size_scale.x
		var expected: Vector3 = (Vector3.FORWARD + birth * (tan(source.cone_angle) / source.radius)).normalized()
		var actual: Vector3 = shape_basis.inverse() * particle.velocity.normalized()
		if not actual.is_equal_approx(expected):
			return false
		if particle.draw == smoke.get_child(0):
			if (not particle.point.is_equal_approx(Vector3(-0.1418939, 0.0, -0.4568362) * 1.14)
					or not is_equal_approx(particle.size.x, 1.039163 * 1.14)
					or not is_equal_approx(particle.lifetime, 1.966099)):
				return false
	if effect.get_node("Circle_01").get_child_count() != 1 or effect.get_node("Spike_01").get_child_count() != 3:
		return false
	var impact_lines := effect.get_node("Line_01")
	if impact_lines.get_child_count() != 0:
		return false
	for name in ["Line_02", "Impact_01"]:
		var emitter := effect.get_node(NodePath(name))
		if emitter.get_child_count() != 1:
			return false
	var impact := effect.get_node("Impact_01").get_child(0) as MeshInstance3D
	var impact_redraw := impact.material_override.next_pass as ShaderMaterial
	if (impact_redraw == null or impact_redraw.render_priority != 16
			or impact_redraw.get_shader_parameter(&"on_hit_vfx_redraw")):
		return false
	var slash := effect.get_node("Slash_01")
	if slash.get_child_count() != 0:
		return false
	var line: MeshInstance3D = effect.get_node("Line_02").get_child(0)
	var line_material := line.material_override as ShaderMaterial
	var first_frame: Vector4 = line_material.get_shader_parameter(&"image_atlas")
	if not first_frame.is_equal_approx(Vector4(1.0 / 3.0, 1.0 / 3.0, 0.0, 0.0)):
		return false
	effect._process(0.025)
	var first_line_burst := impact_lines.get_child_count()
	if first_line_burst < 2 or first_line_burst > 5 or smoke.get_child_count() != 10:
		return false
	effect._process(0.025)
	if slash.get_child_count() != 1 or line_material.get_shader_parameter(&"image_atlas").is_equal_approx(first_frame):
		return false
	var line_redraw := line_material.next_pass as ShaderMaterial
	if (line_redraw == null or line_redraw.get_shader_parameter(&"image_atlas") != line_material.get_shader_parameter(&"image_atlas")
			or smoke_redraw.get_shader_parameter(&"particle_tint") != smoke_material.get_shader_parameter(&"particle_tint")
			or smoke_redraw.get_shader_parameter(&"dissolve_data") != smoke_material.get_shader_parameter(&"dissolve_data")):
		return false
	var second_line_burst := impact_lines.get_child_count() - first_line_burst
	if second_line_burst < 2 or second_line_burst > 5:
		return false
	for trail: MeshInstance3D in impact_lines.get_children():
		if trail.mesh.get_surface_count() != 1:
			return false
	fight._tick_cast(yuuna, 80609)
	fight._tick_cast(yuuna, 80608)
	if weak.defeated or turtle.health != initial_hp:
		return false
	fight._tick_cast(yuuna, 1)
	if not weak.defeated or initial_hp - turtle.health != turtle.damage_after_defense(150) or yuuna.mana != 0:
		return false
	fight._tick_cast(yuuna, 1092)
	fight._tick_cast(yuuna, 26214)
	if yuuna.grid_cell != start or yuuna.visual_offset.is_zero_approx() or yuuna.shadow_step != 4:
		return false
	var landing := yuuna.shadow_landing
	fight._tick_cast(yuuna, 28180)
	return (not yuuna.is_casting() and yuuna.visual_offset.is_zero_approx() and landing != start
			and stage.grid.occupants.get(landing) == yuuna and not stage.grid.occupants.has(start)
			and yuuna.position.is_equal_approx(GuildrunBattleGrid.center(landing))
			and check_yuuna_landing_smoke(yuuna) and check_yuuna_distance_sparks(yuuna)
			and check_yuuna_basic_slash(yuuna, turtle))


func check_yuuna_basic_slash(yuuna: GuildrunBoardUnit, target: GuildrunBoardUnit) -> bool:
	yuuna.face_point(target.global_position)
	yuuna.set_death_appearance_speed(0.0)
	yuuna.begin_basic_attack(target, GuildrunCombatMath.ONE)
	if yuuna._yuna_basic_effects.is_empty():
		return false
	var normal: Node3D = yuuna._yuna_basic_effects.back()
	if normal.get_child_count() != 3 or normal.has_node("Highlight_01"):
		return false
	var forward := -yuuna.global_basis.z.normalized()
	var offset := normal.global_position - yuuna._yuna_basic_mount.global_position
	if not is_equal_approx(offset.dot(forward), 0.413 * 1.14):
		return false
	normal._process(1.0)
	if not is_zero_approx(normal._elapsed):
		return false
	yuuna.set_death_appearance_speed(1.0)
	normal._process(0.299)
	if normal.get_node("Slash_01").get_child_count() != 0:
		return false
	normal._process(0.002)
	for emitter: Node3D in normal.get_children():
		if emitter.get_child_count() != 1:
			return false
	var slash := normal.get_node("Slash_01").get_child(0) as MeshInstance3D
	var material := slash.material_override as ShaderMaterial
	var atlas: Vector4 = material.get_shader_parameter(&"image_atlas")
	if not slash.top_level or not atlas.is_equal_approx(Vector4(0.25, 0.125, 0.5, 0.25)):
		return false
	var redraw := material.next_pass as ShaderMaterial
	if redraw == null or redraw.render_priority != 16 or redraw.get_shader_parameter(&"image_atlas") != atlas:
		return false
	var texture := material.get_shader_parameter(&"image_texture") as Texture2D
	var wind := normal.get_node("Wind_01").get_child(0) as MeshInstance3D
	if (texture == null or texture.resource_path != "res://textures/sharedassets1_2029.dds"
			or redraw.get_shader_parameter(&"image_texture") != texture
			or wind.material_override.get_shader_parameter(&"image_texture") != texture):
		return false
	# The baked Unity mesh turns its local up axis toward the emitter's forward axis at birth.
	if slash.global_basis.y.normalized().dot(-normal.global_basis.z.normalized()) < 0.999:
		return false
	var emission_position := slash.global_position
	yuuna.rotate_y(PI)
	normal._process(0.01)
	if not slash.global_position.is_equal_approx(emission_position):
		return false
	yuuna.begin_basic_attack(target, 2 * GuildrunCombatMath.ONE)
	var fast: Node3D = yuuna._yuna_basic_effects.back()
	fast._process(0.149)
	if fast.get_node("Slash_01").get_child_count() != 0:
		return false
	fast._process(0.002)
	return fast.get_node("Slash_01").get_child_count() == 1


func check_yuuna_throw_effects(yuuna: GuildrunBoardUnit) -> bool:
	var release := yuuna._yuna_release_effect
	var flight := yuuna._yuna_flight_effect
	var mount := yuuna._yuna_flight_mount
	if release == null or flight == null or mount == null:
		return false
	if not is_equal_approx(release.lead_in, 2.334) or not is_equal_approx(flight.lead_in, 2.37):
		return false
	if mount.get_skeleton().get_bone_name(mount.bone_idx) != &"Shuriken":
		return false
	var aura := release.get_node("Aura_01")
	var release_particles := release.get_node("ParticlesAB")
	release._process(1.16)
	if aura.get_child_count() != 0 or release_particles.get_child_count() != 0:
		return false
	release._process(0.01)
	if aura.get_child_count() != 2 or release.get_node("Spike_01").get_child_count() != 11:
		return false
	for quad: MeshInstance3D in aura.get_children():
		var material := quad.material_override as ShaderMaterial
		if (typeof(material.get_shader_parameter(&"particle_tint")) != TYPE_VECTOR4
				or not is_equal_approx(material.get_shader_parameter(&"soft_depth"), 20.0)):
			return false
	var count := release_particles.get_child_count()
	if count < 6 or count > 8:
		return false
	for quad: MeshInstance3D in release_particles.get_children():
		var material := quad.material_override as ShaderMaterial
		var image: Texture2D = material.get_shader_parameter(&"image_texture")
		if (not quad.top_level or material.render_priority != -2 or image == null
				or not image.resource_path.ends_with("sharedassets1_2215.png")
				or not is_equal_approx(material.get_shader_parameter(&"fade_distance"), 1.0)
				or typeof(material.get_shader_parameter(&"particle_tint")) != TYPE_VECTOR4):
			return false
	var ring_source := release.get_node("Rings_01") as Node3D
	var ring := ring_source.get_child(0) as MeshInstance3D
	var ring_start := ring.global_position
	release._process(0.05)
	var expected_ring_direction := -ring_source.global_basis.y.normalized()
	if (ring.global_position - ring_start).normalized().dot(expected_ring_direction) < 0.999:
		return false
	for particle: Variant in release._particles:
		if particle.source == release_particles and (particle.noise == null or particle.noise_offset.is_zero_approx()):
			return false
	var lines := flight.get_node("Line_01")
	var glow := flight.get_node("Glow_01") as Node3D
	var wave := flight.get_node("Wave_01")
	var rim_source := flight.get_node("Shuriken_01")
	var fill_source := flight.get_node("Shuriken_02")
	var motion_ribbon := flight.get_node("Trail_02/Ribbon") as MeshInstance3D
	var motion_trail: Variant = flight._motion_trails[0]
	mount.on_skeleton_update()
	flight._process(1.15)
	if lines.get_child_count() == 0 or glow.get_child_count() != 3 or motion_trail.points.size() != 1:
		return false
	var glow_billboard := glow.get_child(0) as MeshInstance3D
	if not glow_billboard.top_level or not is_equal_approx(glow_billboard.global_basis.x.length(), 3.0):
		return false
	var motion_start: Vector3 = motion_trail.points[0]
	if (motion_trail.material.render_priority != -1 or not is_zero_approx(motion_ribbon.sorting_offset)
			or not is_equal_approx(motion_trail.profile.width_multiplier, 1.4)):
		return false
	mount.position += Vector3.DOWN * 0.02
	flight._process(0.0)
	if motion_trail.points.size() != 1 or motion_ribbon.mesh.get_surface_count() != 1:
		return false
	var motion_vertices: PackedVector3Array = motion_ribbon.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var trail_head := (motion_vertices[0] + motion_vertices[1]) * 0.5
	if not trail_head.is_equal_approx(motion_trail.source.global_position):
		return false
	mount.position += Vector3.DOWN * 0.08
	flight._process(0.03)
	if wave.get_child_count() != 0 or motion_trail.points.size() != 2 or motion_ribbon.mesh.get_surface_count() != 1:
		return false
	motion_vertices = motion_ribbon.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if motion_vertices.size() != 6:
		return false
	if rim_source.get_child_count() != 0 or fill_source.get_child_count() != 0:
		return false
	flight._process(0.01)
	var ribbon: MeshInstance3D
	for particle: Variant in flight._particles:
		if particle.source == lines and is_equal_approx(particle.time_offset, flight.lead_in):
			ribbon = particle.draw
			break
	if ribbon == null or wave.get_child_count() != 5 or motion_trail.points.size() != 2:
		return false
	var prewarmed_wave := wave.get_child(0) as MeshInstance3D
	var prewarmed_material := prewarmed_wave.material_override as ShaderMaterial
	var prewarmed_stream: Vector4 = prewarmed_material.get_shader_parameter(&"wave_stream")
	var wave_mesh := wave.get_child(3) as MeshInstance3D
	var wave_material := wave_mesh.material_override as ShaderMaterial
	var first_wave: Vector4 = wave_material.get_shader_parameter(&"wave_stream")
	var dissolve := wave_material.get_shader_parameter(&"dissolve_texture") as Texture2D
	if dissolve == null or dissolve.resource_path != "res://textures/resources_567.png":
		return false
	var wave_origin := wave_mesh.global_position
	var wave_width := wave_mesh.mesh.get_aabb().size.x * wave_mesh.global_basis.x.length()
	if (not wave_mesh.top_level or not is_equal_approx(first_wave.x, 0.733895)
			or not is_equal_approx(prewarmed_stream.x, 21.281950) or prewarmed_stream.w < 0.9
			or not is_equal_approx(wave_width, 0.040925)
			or prewarmed_wave.global_position.distance_to(wave_origin) > 0.00001):
		return false
	var emission_position := ribbon.global_position
	var previous_glow_position := glow.global_position
	mount.position += Vector3.DOWN * 0.25
	yuuna.set_death_appearance_speed(0.0)
	flight._process(1.0)
	if motion_trail.points.size() != 2:
		return false
	yuuna.set_death_appearance_speed(2.0)
	flight._process(0.025)
	if (ribbon.mesh.get_surface_count() == 0
			or not ribbon.global_position.is_equal_approx(emission_position)):
		return false
	if (motion_ribbon.mesh.get_surface_count() != 1 or not motion_ribbon.top_level
			or motion_trail.points.size() != 3 or not motion_trail.points[0].is_equal_approx(motion_start)
			or not motion_trail.points[2].is_equal_approx(motion_trail.source.global_position)):
		return false
	var atlas_time: float = motion_trail.material.get_shader_parameter(&"atlas_time")
	if not is_equal_approx(atlas_time, 8.5) or not is_equal_approx(flight._elapsed, 2.43):
		return false
	var glow_birth_position := previous_glow_position.lerp(glow.global_position, 0.4)
	var expected_glow_center := glow_birth_position + glow.global_basis.orthonormalized() * Vector3(-0.02070851, 0.10039270, 0.0)
	var new_glow: MeshInstance3D
	for particle: Variant in flight._particles:
		if particle.source == glow and is_equal_approx(particle.time_offset, 2.4):
			new_glow = particle.draw
			break
	if new_glow == null or not new_glow.global_position.is_equal_approx(expected_glow_center):
		return false
	var advanced_wave: Vector4 = wave_material.get_shader_parameter(&"wave_stream")
	if (not wave_mesh.global_position.is_equal_approx(wave_origin)
			or not is_equal_approx(advanced_wave.x, first_wave.x) or advanced_wave.w <= first_wave.w):
		return false
	if rim_source.get_child_count() != 0 or fill_source.get_child_count() != 0:
		return false
	flight._process(0.025)
	if not check_yuuna_projectile_meshes(flight, rim_source, fill_source, mount):
		return false
	flight._process(0.051)
	mount.on_skeleton_update()
	var active_waves := wave.get_children().filter(func(node: Node) -> bool:
		return not node.is_queued_for_deletion()
	)
	if (motion_ribbon.mesh.get_surface_count() != 0 or active_waves.size() != 5
			or not prewarmed_wave.is_queued_for_deletion()):
		return false
	var next_wave := active_waves.back() as MeshInstance3D
	var next_material := next_wave.material_override as ShaderMaterial
	var next_stream: Vector4 = next_material.get_shader_parameter(&"wave_stream")
	if not is_equal_approx(next_stream.x, 56.91767) or next_wave.global_position.distance_to(wave_origin) < 0.2:
		return false
	flight._process(0.04)
	return flight.is_queued_for_deletion()


func check_yuuna_projectile_meshes(flight: Node3D, rim_source: Node3D, fill_source: Node3D, mount: Node3D) -> bool:
	if rim_source.get_child_count() != 1 or fill_source.get_child_count() != 1:
		return false
	var rim := rim_source.get_child(0) as MeshInstance3D
	var fill := fill_source.get_child(0) as MeshInstance3D
	var rim_material := rim.material_override as ShaderMaterial
	var trail_material := (flight.get_node("Trail_02/Ribbon") as MeshInstance3D).material_override as ShaderMaterial
	var rim_tint: Vector4 = rim_material.get_shader_parameter(&"tint")
	if (not rim_tint.is_equal_approx(Vector4(21.11213, 0.0, 0.0, 1.0))
			or not is_equal_approx(rim_material.get_shader_parameter(&"emission_strength"), 3.0)
			or not is_equal_approx(trail_material.get_shader_parameter(&"intensity"), 4.0)
			or not trail_material.get_shader_parameter(&"linearize_vertex_tint")):
		return false
	var origin := rim.global_position
	var axis := rim.global_basis.x.normalized()
	if (not rim.top_level or not fill.top_level or rim.mesh != fill.mesh
			or not origin.is_equal_approx(rim_source.global_position)
			or not fill.global_transform.is_equal_approx(rim.global_transform)
			or not is_equal_approx(rim.global_basis.x.length() * rim.mesh.get_aabb().size.x, 1.02707934)
			or not rim.global_basis.z.normalized().is_equal_approx(Vector3.BACK)):
		return false
	mount.position += Vector3.RIGHT
	flight._process(0.025)
	var expected_axis := axis.rotated(Vector3.BACK, TAU * 2.0 * 0.05)
	return (not rim.is_queued_for_deletion() and rim.global_position.is_equal_approx(origin)
			and rim.global_basis.x.normalized().is_equal_approx(expected_axis)
			and fill.global_transform.is_equal_approx(rim.global_transform))


func check_yuuna_distance_sparks(yuuna: GuildrunBoardUnit) -> bool:
	var anchor := Node3D.new()
	anchor.scale = Vector3.ONE * 0.0114
	yuuna.add_child(anchor)
	var flight := (load("res://battle/yuna_skill_flight.tscn") as PackedScene).instantiate() as Node3D
	anchor.add_child(flight)
	var result := check_spark_emission(anchor, flight)
	anchor.free()
	return result


func check_spark_emission(anchor: Node3D, flight: Node3D) -> bool:
	var source := flight.get_node("Sparkle_01") as Node3D
	var dust_source := flight.get_node("Dust_01") as Node3D
	flight._process(0.05)
	anchor.position.x += 0.26
	flight._process(0.016)
	anchor.position.x += 0.21
	flight._process(0.016)
	if source.get_child_count() != 0 or dust_source.get_child_count() != 0:
		return false
	anchor.position.x += 0.08
	flight._process(0.016)
	if source.get_child_count() != 1 or flight._elapsed >= flight.lead_in:
		return false
	if dust_source.get_child_count() != 1:
		return false
	var spark := source.get_child(0) as MeshInstance3D
	var dust := dust_source.get_child(0) as MeshInstance3D
	flight._process(0.02)
	# Authored Local scaling keeps the sparkle visible on the 0.01-scale weapon socket.
	if spark.global_basis.x.length() < 0.05 or spark.global_position.distance_to(source.global_position) > 0.4:
		return false
	var dust_width := dust.global_basis.x.length()
	var dust_material := dust.material_override as ShaderMaterial
	if (dust_width < 0.3 or dust_width > 0.5
			or dust.global_position.distance_to(dust_source.global_position) > 0.65
			or not is_equal_approx(dust_material.get_shader_parameter(&"fade_distance"), 0.05)):
		return false
	var position_before := spark.global_position
	var dust_position_before := dust.global_position
	flight.speed_scale = 0.0
	flight._process(1.0)
	if not spark.global_position.is_equal_approx(position_before) or spark.is_queued_for_deletion():
		return false
	if not dust.global_position.is_equal_approx(dust_position_before) or dust.is_queued_for_deletion():
		return false
	flight.speed_scale = 1.0
	flight._process(0.1)
	return spark.is_queued_for_deletion() and not dust.is_queued_for_deletion()


func check_yuuna_landing_smoke(yuuna: GuildrunBoardUnit) -> bool:
	var landing := yuuna._yuna_landing_effect
	if landing == null or not is_equal_approx(landing.lead_in, 3.62):
		return false
	var emitter := landing.get_node("Smoke_01") as Node3D
	landing._process(1.8)
	yuuna.set_death_appearance_speed(0.0)
	landing._process(1.0)
	if emitter.get_child_count() != 0:
		return false
	yuuna.set_death_appearance_speed(2.0)
	landing._process(0.02)
	if emitter.get_child_count() != 2:
		return false
	var origin := emitter.global_position
	if origin.distance_to(yuuna.global_position) > 0.1:
		return false
	var smoke := emitter.get_child(0) as MeshInstance3D
	var redraw := smoke.material_override.next_pass as ShaderMaterial
	if redraw == null or redraw.render_priority != 17 or redraw.get_shader_parameter(&"on_hit_vfx_redraw"):
		return false
	var start := smoke.global_position
	yuuna.set_visual_offset(Vector3.RIGHT)
	var stays_at_landing := smoke.global_position.is_equal_approx(start)
	yuuna.set_visual_offset(Vector3.ZERO)
	landing._process(0.05)
	return stays_at_landing and smoke.global_position.distance_to(origin) > start.distance_to(origin)


func check_yuuna_wind_effect(yuuna: GuildrunBoardUnit) -> bool:
	var effect := yuuna._yuna_wind_effect
	var mount := yuuna._yuna_wind_mount
	if effect == null or mount == null or not is_equal_approx(effect.lead_in, 1.0):
		return false
	if mount.get_skeleton().get_bone_name(mount.bone_idx) != &"spine":
		return false
	var lines := effect.get_node("Line_01")
	var ring := effect.get_node("Wind_01")
	mount.on_skeleton_update()
	effect._process(0.49)
	if lines.get_child_count() != 0:
		return false
	effect._process(0.03)
	if lines.get_child_count() != 2 or ring.get_child_count() != 0:
		return false
	var ribbon := lines.get_child(0) as MeshInstance3D
	if ribbon.mesh.get_surface_count() != 1 or ribbon.top_level:
		return false
	effect._process(0.31)
	return ring.get_child_count() == 1
