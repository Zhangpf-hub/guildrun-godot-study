extends Node3D

class Particle:
	var draw: MeshInstance3D
	var source: Node3D
	var profile: Dictionary
	var time_offset: float
	var initial_age: float
	var lifetime: float
	var tint: Color
	var size: Vector3
	var angles: Vector3
	var point: Vector3
	var velocity: Vector3
	var velocity_over_lifetime := Vector3.ZERO
	var orbit: float
	var size_mix: float
	var atlas_mix: float
	var emission_basis := Basis.IDENTITY
	var emission_frame: Transform3D
	var dissolve_shift_y: float
	var flare_stream: Vector3
	var wave_offset: float
	var simulation_speed := 1.0
	var ribbon_lifetime := 0.0
	var ribbon_width_mix := 0.0
	var radial_speed := 0.0
	var spin := 0.0
	var trail_points: Array[Vector3] = []
	var trail_ages: Array[float] = []
	var noise: FastNoiseLite
	var noise_origin: Vector3
	var noise_strength := 0.0
	var noise_offset := Vector3.ZERO

	func end_age() -> float:
		return lifetime if profile.get("ribbon_die_with_particle", false) else lifetime + ribbon_lifetime


class DistanceEmitter:
	var source: Node3D
	var profile: Dictionary
	var random: RandomNumberGenerator
	var noise: FastNoiseLite
	var position: Vector3
	var remainder := 0.0


class MotionTrail:
	var source: Node3D
	var mesh: ImmediateMesh
	var material: ShaderMaterial
	var profile: Dictionary
	var points: Array[Vector3] = []
	var timestamps: Array[float] = []


@export var lead_in: float
@export var duration: float
@export var hold_world_position_on_emit: bool
@export var finish_particles: bool

var speed_scale := 1.0
var action_speed_scale := 1.0
var scene_time: Callable
var action_mesh_phase: Callable
var _elapsed := 0.0
var _activation_time := 0.0
var _last_particle_end := 0.0
var _particles: Array[Particle] = []
var _motion_trails: Array[MotionTrail] = []
var _distance_emitters: Array[DistanceEmitter] = []
var _previous_birth_positions: Dictionary[Node3D, Vector3] = {}


func _ready() -> void:
	# The native VFX component divides its own delay by the action speed.
	_activation_time = lead_in / action_speed_scale
	for source: Node3D in get_children():
		if source.has_meta("motion_trail"):
			_prepare_motion_trail(source)
		else:
			_prepare_burst(source)
	if finish_particles:
		for particle in _particles:
			var remaining_age := particle.end_age() - particle.initial_age
			_last_particle_end = maxf(_last_particle_end, particle.time_offset + remaining_age / particle.simulation_speed)


func _prepare_motion_trail(source: Node3D) -> void:
	var trail := MotionTrail.new()
	trail.source = source
	trail.profile = source.get_meta("motion_trail")
	var draw := source.get_node("Ribbon") as MeshInstance3D
	draw.global_transform = Transform3D.IDENTITY
	trail.mesh = draw.mesh as ImmediateMesh
	trail.material = draw.material_override.duplicate() as ShaderMaterial
	trail.material.render_priority = trail.profile.get("render_priority", trail.material.render_priority)
	draw.material_override = trail.material
	_motion_trails.append(trail)


func _prepare_burst(source: Node3D) -> void:
	var profile: Dictionary = source.get_meta("particle")
	if profile.get("interpolate_birth_position", false):
		_previous_birth_positions[source] = source.global_position
	var random := RandomNumberGenerator.new()
	if profile.seed < 0:
		random.randomize()
	else:
		random.seed = profile.seed
	if profile.has("distance_rate"):
		var emitter := DistanceEmitter.new()
		emitter.source = source
		emitter.profile = profile
		emitter.random = random
		emitter.position = source.global_position
		if profile.has("noise_frequency"):
			emitter.noise = _make_noise(profile.noise_frequency, random.seed)
		_distance_emitters.append(emitter)
		if not profile.has("count"):
			return
	var position_noise: FastNoiseLite
	if profile.has("noise_strength"):
		position_noise = _make_noise(profile.noise_frequency, random.seed)
	var simulation_speed: float = profile.get("simulation_speed", 1.0)
	if profile.get("scale_with_action", false):
		simulation_speed *= action_speed_scale
	var emission_start := 0.0 if profile.get("start_on_enable", false) else _activation_time
	for overrides: Dictionary in profile.get("bursts", [{}]):
		var birth_profile := profile if overrides.is_empty() else profile.merged(overrides, true)
		var count_range: Vector2i = birth_profile.count
		for cycle in int(birth_profile.repeat_count):
			var start: float = emission_start + (birth_profile.delay + cycle * birth_profile.repeat_interval) / simulation_speed
			for i in random.randi_range(count_range.x, count_range.y):
				var particle := _prepare_particle(source, birth_profile, random, start, simulation_speed)
				if position_noise != null:
					particle.noise = position_noise
					particle.noise_strength = _value(random, birth_profile.noise_strength)


func _make_noise(frequency: float, seed_value: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = frequency
	noise.seed = seed_value
	return noise


func _prepare_particle(source: Node3D, profile: Dictionary, random: RandomNumberGenerator,
		start: float, simulation_speed: float = 1.0) -> Particle:
	var particle := Particle.new()
	particle.source = source
	particle.profile = profile
	particle.simulation_speed = simulation_speed
	particle.time_offset = start
	particle.initial_age = profile.get("initial_age", 0.0)
	particle.lifetime = _value(random, profile.lifetime)
	var width := _value(random, profile.width)
	particle.size = Vector3(width, _value(random, profile.height), _value(random, profile.depth)) if profile.size_3d else Vector3.ONE * width
	var size_scale: Vector3 = profile.get("size_scale", Vector3.ONE)
	var presentation_scale: float = profile.get("presentation_scale", 1.0)
	particle.size *= size_scale * presentation_scale
	particle.angles = Vector3(_value(random, profile.pitch), _value(random, profile.yaw), _value(random, profile.roll))
	particle.tint = profile.tint_min.lerp(profile.tint_max, random.randf())
	particle.orbit = _value(random, profile.orbit)
	particle.size_mix = random.randf()
	if profile.has("atlas_frames_min"):
		particle.atlas_mix = random.randf()
	if profile.has("dissolve_shift_y"):
		particle.dissolve_shift_y = _value(random, profile.dissolve_shift_y)
	if profile.has("flare_offset"):
		var warp_emission: Vector2 = profile.flare_warp_emission
		particle.flare_stream = Vector3(_value(random, profile.flare_offset), warp_emission.x, warp_emission.y)
	if profile.has("wave_offset"):
		particle.wave_offset = _value(random, profile.wave_offset)
	_prepare_origin(particle, random)
	if profile.has("linear_velocity_ranges"):
		var ranges: Array = profile.linear_velocity_ranges
		particle.velocity_over_lifetime = Vector3(_value(random, ranges[0]),
			_value(random, ranges[1]), _value(random, ranges[2]))
	if profile.has("spin"):
		particle.spin = _value(random, profile.spin)
	if profile.has("radial_speed"):
		particle.radial_speed = _value(random, profile.radial_speed)
	particle.ribbon_lifetime = profile.get("ribbon_lifetime", 0.0)
	if profile.has("ribbon_life_factor"):
		particle.ribbon_lifetime = _value(random, profile.ribbon_life_factor) * particle.lifetime
	if profile.has("ribbon_width_min"):
		particle.ribbon_width_mix = random.randf()
	if profile.get("tracked_ribbon", false):
		particle.radial_speed = _value(random, profile.ribbon_radial_range)
	_particles.append(particle)
	return particle


func _advance_distance_emitter(emitter: DistanceEmitter, delta: float) -> void:
	var position := emitter.source.global_position
	var distance := emitter.position.distance_to(position)
	emitter.position = position
	if is_zero_approx(distance):
		return
	var spacing: float = 1.0 / emitter.profile.distance_rate
	var accumulated := emitter.remainder + distance
	var count := floori(accumulated / spacing)
	for i in count:
		var fraction := ((i + 1) * spacing - emitter.remainder) / distance
		var start := _elapsed - delta * (1.0 - fraction)
		var particle := _prepare_particle(emitter.source, emitter.profile, emitter.random, start)
		particle.noise = emitter.noise
		var random := emitter.random
		if emitter.profile.has("noise_strength"):
			particle.noise_strength = _value(random, emitter.profile.noise_strength)
		else:
			particle.noise_origin = Vector3(random.randf_range(0.0, 64.0),
				random.randf_range(0.0, 64.0), random.randf_range(0.0, 64.0))
	emitter.remainder = fposmod(accumulated, spacing)


func _start_particle(particle: Particle, previous_elapsed: float) -> void:
	var profile := particle.profile
	var material: ShaderMaterial = profile.material
	particle.draw = MeshInstance3D.new()
	particle.draw.mesh = ImmediateMesh.new() if profile.mode == 5 else profile.mesh
	var instance := material.duplicate() as ShaderMaterial
	if profile.has("intensity_offset"):
		var intensity: float = material.get_shader_parameter(&"intensity")
		instance.set_shader_parameter(&"intensity", intensity + profile.intensity_offset)
	if profile.has("flare_offset"):
		instance.set_shader_parameter(&"flare_stream", particle.flare_stream)
	instance.render_priority = profile.get("render_priority", instance.render_priority)
	var on_hit_redraw: bool = profile.get("on_hit_vfx_redraw", false)
	if on_hit_redraw or profile.get("vfx_redraw", false):
		if profile.get("compensate_dark_blend", false):
			instance.set_shader_parameter(&"compensate_dark_blend", true)
		var redraw := instance.duplicate() as ShaderMaterial
		# Character passes end at 9. VFXRender draws before foreground (24), then onHitVFX Render draws.
		redraw.render_priority = (32 if on_hit_redraw else 16) + instance.render_priority
		if on_hit_redraw:
			redraw.set_shader_parameter(&"on_hit_vfx_redraw", true)
		instance.next_pass = redraw
	particle.draw.material_override = instance
	particle.draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particle.draw.sorting_offset = profile.sorting_offset
	particle.source.add_child(particle.draw)
	if profile.has("linear_velocity") or profile.has("linear_velocity_ranges"):
		var velocity: Vector3 = profile.get("linear_velocity", particle.velocity_over_lifetime)
		if profile.get("world_linear_velocity", false):
			# World-simulated particles keep this emission frame for their lifetime.
			velocity = particle.source.global_basis.inverse() * velocity
		elif profile.get("mesh_local_scale", false):
			velocity /= particle.source.global_basis.get_scale()
		particle.velocity += velocity
	if profile.get("world_space", false):
		particle.emission_frame = particle.source.global_transform
		if _previous_birth_positions.has(particle.source) and _elapsed > previous_elapsed:
			# The native emitter uses the current rotation and the position at the birth time.
			var weight := clampf(inverse_lerp(previous_elapsed, _elapsed, particle.time_offset), 0.0, 1.0)
			var previous_position: Vector3 = _previous_birth_positions[particle.source]
			particle.emission_frame.origin = previous_position.lerp(particle.emission_frame.origin, weight)
		particle.draw.top_level = true
		particle.draw.global_transform = particle.emission_frame
	if profile.get("tracked_ribbon", false):
		particle.trail_points.append(particle.emission_frame * particle.point)
		particle.trail_ages.append(0.0)


func _prepare_origin(particle: Particle, random: RandomNumberGenerator) -> void:
	var profile := particle.profile
	if profile.has("initial_position"):
		particle.point = profile.initial_position
		particle.velocity = profile.initial_velocity
		return
	var angle := random.randf_range(0.0, TAU)
	var direction := Vector3(cos(angle), sin(angle), 0.0)
	var cone_direction := Vector3.FORWARD.rotated(Vector3.FORWARD.cross(direction), profile.cone_angle)
	var radius_fraction := sqrt(random.randf_range(pow(1.0 - profile.radius_thickness, 2.0), 1.0))
	var radius: float = profile.radius * radius_fraction
	var point := Vector3.ZERO
	match int(profile.shape):
		0: # Sphere
			if profile.get("sphere_volume", false) or profile.get("align_to_direction", false):
				var elevation := random.randf_range(-1.0, 1.0)
				var outward := direction * sqrt(1.0 - elevation * elevation) + Vector3.FORWARD * elevation
				var inner: float = 1.0 - profile.radius_thickness
				var shell_radius: float = profile.radius * pow(random.randf_range(inner * inner * inner, 1.0), 1.0 / 3.0)
				point = outward * shell_radius
				cone_direction = outward
		2: # Hemisphere
			var elevation := random.randf_range(0.0, 1.0)
			point = radius * (direction * sqrt(1.0 - elevation * elevation) + Vector3.FORWARD * elevation)
		4, 8: # Cone base / volume
			point = radius * direction
			# A point emitter keeps the same angular spread when its radius is zero.
			var spread: float = tan(profile.cone_angle) * radius_fraction
			cone_direction = (Vector3.FORWARD + direction * spread).normalized()
			if profile.shape == 8:
				point += cone_direction * random.randf_range(0.0, profile.shape_length)
		14: # Small glints emitted where the character model stands.
			point = Vector3(direction.x * 0.27, random.randf_range(-0.8, 0.65), direction.y * 0.22)
		17: # Donut around the emitter's forward axis.
			var cross_section := random.randf_range(0.0, TAU)
			var thickness: float = profile.donut_radius * sqrt(random.randf_range(pow(1.0 - profile.radius_thickness, 2.0), 1.0))
			point = direction * (profile.radius + cos(cross_section) * thickness) + Vector3.FORWARD * (sin(cross_section) * thickness)
	# Unity applies rotations around Z, X, then Y. Godot names the matrix product YXZ.
	var shape_basis := Basis.from_euler(profile.shape_rotation, EULER_ORDER_YXZ)
	particle.point = profile.shape_position + shape_basis * (point * profile.shape_scale)
	var emission_direction := shape_basis * cone_direction
	particle.velocity = emission_direction * _value(random, profile.speed)
	if profile.get("align_to_direction", false):
		var up := Vector3.RIGHT if absf(emission_direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
		particle.emission_basis = Basis.looking_at(emission_direction, up)


func _process(delta: float) -> void:
	if speed_scale <= 0.0:
		return
	var previous_elapsed := _elapsed
	_elapsed += delta * speed_scale
	if hold_world_position_on_emit and not top_level and _elapsed >= _activation_time:
		var anchor := global_transform
		top_level = true
		global_transform = anchor
	if _elapsed >= maxf(_activation_time + duration, _last_particle_end):
		queue_free()
		return
	if action_mesh_phase.is_valid() and _elapsed >= _activation_time:
		action_mesh_phase.call(_elapsed - _activation_time)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_remember_birth_positions()
		return
	for trail in _motion_trails:
		_advance_motion_trail(trail, camera)
	for emitter in _distance_emitters:
		_advance_distance_emitter(emitter, delta * speed_scale)
	for particle in _particles:
		if _elapsed < particle.time_offset:
			continue
		var age := particle.initial_age + (_elapsed - particle.time_offset) * particle.simulation_speed
		var profile := particle.profile
		var ribbon_lifetime := particle.ribbon_lifetime
		if age >= particle.end_age():
			if is_instance_valid(particle.draw):
				particle.draw.queue_free()
				particle.draw = null
			continue
		if particle.draw == null:
			_start_particle(particle, previous_elapsed)
		var fraction := clampf(age / particle.lifetime, 0.0, 1.0)
		var tint := particle.tint
		if profile.has("color_gradient"):
			tint *= _sample_color(profile.color_gradient, fraction)
		else:
			tint.a *= _sample(profile.opacity, fraction)
		var material := particle.draw.material_override as ShaderMaterial
		_update_particle_material(particle, material, fraction, tint)
		var redraw := material.next_pass as ShaderMaterial
		if redraw != null:
			_update_particle_material(particle, redraw, fraction, tint)
		if profile.get("tracked_ribbon", false):
			_draw_tracked_ribbon(particle, camera, age)
		elif profile.mode == 5:
			_draw_ribbon(particle, camera, age, ribbon_lifetime)
		elif profile.has("noise_distance"):
			_draw_distance_spark(particle, camera, age, fraction)
		else:
			if particle.noise != null:
				var step := minf(age, delta * speed_scale * particle.simulation_speed)
				_advance_position_noise(particle, age, step)
			_draw_particle(particle, camera, age, fraction)
	_remember_birth_positions()


func _update_particle_material(particle: Particle, material: ShaderMaterial, fraction: float, tint: Color) -> void:
	var profile := particle.profile
	var uniform_tint := tint if profile.mode != 5 else Color.WHITE
	if profile.get("raw_particle_tint", false):
		# Godot converts Color values for linear rendering. Vector4 preserves the source vertex values.
		material.set_shader_parameter(&"particle_tint", Vector4(uniform_tint.r, uniform_tint.g, uniform_tint.b, uniform_tint.a))
	else:
		material.set_shader_parameter(&"particle_tint", uniform_tint)
	material.set_shader_parameter(&"particle_age", fraction)
	if profile.has("intensity_curve"):
		var base: float = profile.material.get_shader_parameter(&"intensity")
		material.set_shader_parameter(&"intensity", base + _sample(profile.intensity_curve, fraction))
	if profile.has("flare_offset"):
		material.set_shader_parameter(&"flare_time", _elapsed)
	if profile.has("wave_offset"):
		material.set_shader_parameter(&"wave_stream", Vector4(particle.wave_offset,
			_sample(profile.wave_far, fraction), _sample(profile.wave_near, fraction), _sample(profile.wave_phase, fraction)))
	if profile.has("dissolve_value"):
		var shift_y := particle.dissolve_shift_y
		if profile.has("dissolve_scroll_y"):
			shift_y = _sample(profile.dissolve_scroll_y, fraction)
		material.set_shader_parameter(&"dissolve_data", Vector3(_sample(profile.dissolve_value, fraction),
			_sample(profile.dissolve_scroll_x, fraction), -shift_y))
	if profile.has("slash_x"):
		material.set_shader_parameter(&"slash_data", Vector4(_sample(profile.slash_x, fraction),
			_sample(profile.slash_y, fraction), _sample(profile.slash_z, fraction), _sample(profile.slash_w, fraction)))
	if profile.has("atlas_grid"):
		var grid: Vector2i = profile.atlas_grid
		var frames := grid.x * grid.y
		var frame_progress := _sample(profile.atlas_frames, fraction)
		if profile.has("atlas_frames_min"):
			frame_progress = lerpf(_sample(profile.atlas_frames_min, fraction), frame_progress, particle.atlas_mix)
		var phase := fposmod(frame_progress * profile.atlas_cycles + profile.atlas_start, 1.0)
		var frame := mini(int(phase * frames), frames - 1)
		@warning_ignore("integer_division")
		var row := frame / grid.x
		material.set_shader_parameter(&"image_atlas", Vector4(1.0 / grid.x, 1.0 / grid.y,
			float(frame % grid.x) / grid.x, float(row) / grid.y))


func _remember_birth_positions() -> void:
	for source in _previous_birth_positions:
		_previous_birth_positions[source] = source.global_position


func _draw_distance_spark(particle: Particle, camera: Camera3D, age: float, fraction: float) -> void:
	var profile := particle.profile
	var anchor := particle.source.global_transform.orthonormalized()
	var point := _spark_position(particle, age)
	var previous := _spark_position(particle, maxf(age - 0.004, 0.0))
	var forward := camera.global_basis.z.normalized()
	var direction := (anchor.basis * (point - previous)).slide(forward).normalized()
	particle.draw.visible = not direction.is_zero_approx()
	if not particle.draw.visible:
		return
	var width := particle.size.x * _sample(profile.size_x, fraction)
	var length: float = width * profile.length_scale
	var center := anchor * point - direction * (length * 0.5)
	var orientation := Basis(direction.cross(forward), direction, forward)
	particle.draw.global_transform = Transform3D(orientation.scaled_local(Vector3(width, length, 1.0)), center)


func _spark_position(particle: Particle, age: float) -> Vector3:
	var profile := particle.profile
	var fraction := clampf(age / particle.lifetime, 0.0, 1.0)
	var distance := _sample(profile.noise_distance, fraction) * particle.lifetime
	var phase: float = (particle.time_offset + age) * profile.noise_scroll
	return particle.point + _noise_vector(particle.noise, particle.noise_origin + Vector3.ONE * phase) * distance


func _advance_position_noise(particle: Particle, age: float, delta: float) -> void:
	var sample_age := age - delta * 0.5
	var position := _point_at(particle, sample_age) + particle.noise_offset
	var phase: float = sample_age * particle.profile.noise_scroll
	particle.noise_offset += _noise_vector(particle.noise, position + Vector3.ONE * phase) * particle.noise_strength * delta


func _noise_vector(noise: FastNoiseLite, point: Vector3) -> Vector3:
	return Vector3(noise.get_noise_2d(point.x, point.y), noise.get_noise_2d(point.y, point.z),
		noise.get_noise_2d(point.z, point.x))


func _draw_particle(particle: Particle, camera: Camera3D, age: float, fraction: float) -> void:
	var profile := particle.profile
	var point := _point_at(particle, age) + particle.noise_offset
	var source_frame := particle.emission_frame if particle.draw.top_level else particle.source.global_transform
	# Animated attachment slots can collapse to zero scale between weapon poses.
	particle.draw.visible = source_frame.basis.determinant() != 0.0
	if not particle.draw.visible:
		return
	var local_billboard_scale: bool = profile.get("local_billboard_scale", false)
	if local_billboard_scale:
		source_frame = source_frame.orthonormalized()
	var angles := particle.angles
	angles.z += particle.spin * age
	if profile.has("spin_y_distance"):
		angles += Vector3(_sample(profile.spin_x_distance, fraction), _sample(profile.spin_y_distance, fraction),
			_sample(profile.spin_z_distance, fraction)) * particle.lifetime
	if profile.mode == 0 and profile.alignment == 0:
		# Unity's positive View billboard roll turns clockwise on screen.
		angles.z = -angles.z
	var orientation := particle.emission_basis * Basis.from_euler(angles, EULER_ORDER_YXZ)
	if profile.get("world_mesh_rotation", false):
		orientation = source_frame.basis.inverse() * orientation
	elif profile.get("mesh_local_scale", false):
		orientation = source_frame.basis.inverse() * source_frame.basis.orthonormalized() * orientation
	if profile.mode == 2:
		# Unity horizontal billboards have a world-up normal.
		var horizontal := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
		orientation = source_frame.basis.inverse() * horizontal * Basis(Vector3.BACK, -angles.z)
	elif profile.mode == 3:
		# Unity vertical billboards face the camera in yaw while keeping world up.
		var forward := camera.global_position - source_frame * point
		forward.y = 0.0
		var vertical := Basis.IDENTITY
		if not forward.is_zero_approx():
			vertical = Basis.looking_at(forward.normalized(), Vector3.UP, true)
		orientation = source_frame.basis.inverse() * vertical * Basis(Vector3.BACK, -angles.z)
	elif profile.mode != 4 and profile.alignment != 2:
		var view_basis := camera.global_basis.orthonormalized()
		if profile.alignment == 3:
			var forward := (camera.global_position - source_frame * point).normalized()
			if not forward.is_zero_approx() and absf(forward.dot(Vector3.UP)) < 0.999:
				view_basis = Basis.looking_at(forward, Vector3.UP, true)
		orientation = source_frame.basis.inverse() * view_basis * orientation
	var width := lerpf(_sample(profile.size_x_min, fraction), _sample(profile.size_x, fraction), particle.size_mix)
	var scale_factor := Vector3(width, _sample(profile.size_y, fraction), _sample(profile.size_z, fraction))
	var dimensions := particle.size * scale_factor
	if profile.mode == 1:
		dimensions.y *= profile.length_scale + profile.velocity_scale * particle.velocity.length()
		point += particle.velocity.normalized() * dimensions.y * 0.5
	var pivot: Vector3 = profile.pivot
	var transform := Transform3D(orientation.scaled_local(dimensions), point + orientation * (pivot * dimensions))
	if particle.draw.top_level or local_billboard_scale:
		particle.draw.global_transform = source_frame * transform
	else:
		particle.draw.transform = transform


func _point_at(particle: Particle, age: float) -> Vector3:
	var profile := particle.profile
	var fraction := clampf(age / particle.lifetime, 0.0, 1.0)
	var distance := _sample(profile.speed_distance, fraction) * particle.lifetime
	var radial := _sample(profile.radial_distance, fraction) * particle.lifetime + particle.radial_speed * distance
	var offset: Vector3 = particle.point - profile.shape_position
	var distance_to_center := offset.length()
	if distance_to_center > 0.0:
		offset *= maxf(0.0, distance_to_center + radial) / distance_to_center
	var position: Vector3 = profile.shape_position + offset.rotated(Vector3.UP, particle.orbit * age) + particle.velocity * distance
	if profile.has("velocity_x_distance"):
		var displacement := Vector3(_sample(profile.velocity_x_distance, fraction),
			_sample(profile.velocity_y_distance, fraction), _sample(profile.velocity_z_distance, fraction)) * particle.lifetime
		if profile.get("mesh_local_scale", false):
			var source_basis := particle.emission_frame.basis if particle.draw.top_level else particle.source.global_basis
			displacement /= source_basis.get_scale()
		position += displacement
	return position


func _draw_ribbon(particle: Particle, camera: Camera3D, age: float, lifetime: float) -> void:
	var ribbon := particle.draw.mesh as ImmediateMesh
	ribbon.clear_surfaces()
	var start := maxf(0.0, age - lifetime)
	var end := minf(age, particle.lifetime)
	if end <= start or particle.draw.global_basis.determinant() == 0.0:
		return
	var eye := particle.draw.to_local(camera.global_position)
	var profile := particle.profile
	var authored_colors := profile.has("ribbon_color")
	var lifetime_tint := Color.WHITE
	var segments := maxi(2, ceili((end - start) * 60.0))
	if authored_colors:
		lifetime_tint = _sample_color(profile.ribbon_life_color, clampf(age / particle.lifetime, 0.0, 1.0))
	else:
		var length: float = (end - start) * (absf(particle.orbit) * profile.radius + absf(profile.ribbon_radial_speed))
		segments = clampi(ceili(length / profile.ribbon_spacing), 2, 40)
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segments + 1:
		var fraction := float(i) / segments
		var time := lerpf(start, end, fraction)
		var center := _point_at(particle, time)
		var tangent := _point_at(particle, minf(time + 0.004, particle.lifetime)) - _point_at(particle, maxf(time - 0.004, 0.0))
		var side := tangent.cross(eye - center).normalized()
		var progress := 1.0 - fraction
		var width := _sample(profile.ribbon_width, progress) * 0.5
		var tint := particle.tint
		if authored_colors:
			if profile.has("ribbon_width_min"):
				width = lerpf(_sample(profile.ribbon_width_min, progress) * 0.5, width, particle.ribbon_width_mix)
			tint = _sample_color(profile.ribbon_color, progress) * lifetime_tint
		else:
			var size := lerpf(_sample(profile.size_x_min, time / particle.lifetime),
				_sample(profile.size_x, time / particle.lifetime), particle.size_mix)
			width *= particle.size.x * size
			tint.a *= _sample(profile.opacity, time / particle.lifetime) * _sample(profile.ribbon_opacity, progress)
		for edge in 2:
			ribbon.surface_set_color(tint)
			ribbon.surface_set_uv(Vector2(1.0 - fraction, edge))
			ribbon.surface_add_vertex(center + side * width * (2.0 * edge - 1.0))
	ribbon.surface_end()


func _draw_tracked_ribbon(particle: Particle, camera: Camera3D, age: float) -> void:
	var ribbon := particle.draw.mesh as ImmediateMesh
	ribbon.clear_surfaces()
	if particle.emission_frame.basis.determinant() == 0.0:
		return
	var profile := particle.profile
	var points := particle.trail_points
	var ages := particle.trail_ages
	var end := minf(age, particle.lifetime)
	if end > ages[-1]:
		var center := particle.source.to_global(profile.shape_position)
		var offset := points[-1] - center
		var change := particle.radial_speed * (end - ages[-1]) * particle.emission_frame.basis.get_scale().x
		points.append(center + offset.normalized() * maxf(0.0, offset.length() + change))
		ages.append(end)
	var start := maxf(0.0, age - particle.ribbon_lifetime)
	while ages.size() > 1 and ages[1] <= start:
		ages.pop_front()
		points.pop_front()
	if ages.size() < 2 or end <= start:
		return

	var eye := camera.global_position
	var lifetime_tint := _sample_color(profile.ribbon_life_color, clampf(age / particle.lifetime, 0.0, 1.0))
	var inverse_frame := particle.emission_frame.affine_inverse()
	var frame_scale := particle.emission_frame.basis.get_scale().x
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in points.size():
		var center := points[i]
		if i == 0 and ages[0] < start:
			center = center.lerp(points[1], inverse_lerp(ages[0], ages[1], start))
		var tangent := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
		var progress := 1.0 - clampf(inverse_lerp(start, end, ages[i]), 0.0, 1.0)
		var half_width := _sample(profile.ribbon_width, progress) * frame_scale * 0.5
		var side := tangent.cross(eye - center).normalized() * half_width
		var tint := _sample_color(profile.ribbon_color, progress) * lifetime_tint
		for edge in 2:
			ribbon.surface_set_color(tint)
			ribbon.surface_set_uv(Vector2(progress, edge))
			ribbon.surface_add_vertex(inverse_frame * (center + side * (2.0 * edge - 1.0)))
	ribbon.surface_end()


func _advance_motion_trail(trail: MotionTrail, camera: Camera3D) -> void:
	# The native component activates the GameObject before its particle delay.
	var position_now := trail.source.global_position
	var spacing: float = trail.profile.spacing
	if trail.points.is_empty() or trail.points[-1].distance_squared_to(position_now) >= spacing * spacing:
		trail.points.append(position_now)
		trail.timestamps.append(_elapsed)
	var cutoff: float = _elapsed - trail.profile.lifetime
	while not trail.timestamps.is_empty() and trail.timestamps[0] <= cutoff:
		trail.timestamps.pop_front()
		trail.points.pop_front()

	trail.mesh.clear_surfaces()
	if trail.points.is_empty() or (trail.points.size() == 1 and position_now == trail.points[0]):
		return
	# UberParticles scrolls with Unity's shader clock. Point lifetimes use the emitter clock.
	var shader_time: float = scene_time.call() if scene_time.is_valid() else _elapsed
	trail.material.set_shader_parameter(&"atlas_time", shader_time)
	_draw_motion_trail(trail, position_now, camera)


func _draw_motion_trail(trail: MotionTrail, head: Vector3, camera: Camera3D) -> void:
	# The live head has its own cross section, even when it coincides with a sample.
	var points: Array[Vector3] = trail.points.duplicate()
	points.reverse()
	points.push_front(head)
	var distances := PackedFloat32Array([0.0])
	var directions := PackedVector2Array()
	var previous_pixel := camera.unproject_position(head)
	if not previous_pixel.is_finite():
		return
	for i in range(1, points.size()):
		var pixel := camera.unproject_position(points[i])
		if not pixel.is_finite():
			return
		directions.append((previous_pixel - pixel).normalized())
		distances.append(distances[-1] + points[i - 1].distance_to(points[i]))
		previous_pixel = pixel

	var direction := directions[0]
	if directions.size() > 1:
		direction = directions[1]
		var sample_length := distances[2] - distances[1]
		if distances[1] >= 0.1 * sample_length:
			direction = (direction + directions[0]).normalized()

	var view_basis := camera.get_camera_transform().basis.orthonormalized()
	var width_multiplier: float = trail.profile.get("width_multiplier", 0.0)
	trail.mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in points.size():
		var across := direction
		var width_scale := 1.0
		if i > 0 and i + 1 < directions.size():
			# Unity smooths toward each older segment and reduces the blend on shallow bends.
			var next := (direction + directions[i + 1]).normalized()
			var midpoint := (direction + next).normalized()
			var blend := clampf((1.0 - direction.dot(next)) / 0.01, 0.0, 1.0)
			across = direction.lerp(midpoint, blend).normalized()
			if i >= 3 and width_multiplier > 0.0:
				# The earlier segment limits how far the corner can widen.
				var earlier_length := distances[i - 1] - distances[i - 2]
				var width_limit := maxf(1.0, 1.5 * earlier_length / width_multiplier)
				width_scale = 1.0 / maxf(across.dot(direction), 1.0 / width_limit)
			direction = next

		var center := points[i]
		var progress := distances[i] / distances[-1]
		var width := _sample(trail.profile.width, progress) * 0.5 * width_scale
		var side := (-view_basis.x * across.y - view_basis.y * across.x) * width
		var tint := _sample_color(trail.profile.color, progress)
		for edge in 2:
			trail.mesh.surface_set_color(tint)
			trail.mesh.surface_set_uv(Vector2(progress, edge))
			trail.mesh.surface_add_vertex(center + side * (2.0 * edge - 1.0))
	trail.mesh.surface_end()


func _sample_color(values: PackedColorArray, fraction: float) -> Color:
	var coordinate := fraction * (values.size() - 1)
	var index := int(coordinate)
	return values[index].lerp(values[mini(index + 1, values.size() - 1)], coordinate - index)


func _value(random: RandomNumberGenerator, interval: Vector2) -> float:
	return random.randf_range(interval.x, interval.y)


func _sample(values: PackedFloat32Array, fraction: float) -> float:
	var coordinate := fraction * (values.size() - 1)
	var index := int(coordinate)
	return lerpf(values[index], values[mini(index + 1, values.size() - 1)], coordinate - index)
