extends Node3D

class Particle:
	var draw: MeshInstance3D
	var source: Node3D
	var profile: Dictionary
	var time_offset: float
	var lifetime: float
	var tint: Color
	var size: Vector3
	var angles: Vector3
	var point: Vector3
	var velocity: Vector3
	var orbit: float
	var size_mix: float

@export var lead_in: float
@export var duration: float

var _elapsed := 0.0
var _particles: Array[Particle] = []


func _ready() -> void:
	for source: Node3D in get_children():
		_prepare_burst(source)


func _prepare_burst(source: Node3D) -> void:
	var profile: Dictionary = source.get_meta("particle")
	var random := RandomNumberGenerator.new()
	if profile.seed < 0:
		random.randomize()
	else:
		random.seed = profile.seed
	var count_range: Vector2i = profile.count
	for cycle in int(profile.repeat_count):
		for i in random.randi_range(count_range.x, count_range.y):
			_prepare_particle(source, profile, random, cycle)


func _prepare_particle(source: Node3D, profile: Dictionary, random: RandomNumberGenerator, cycle: int) -> void:
	var particle := Particle.new()
	particle.source = source
	particle.profile = profile
	particle.time_offset = lead_in + profile.delay + cycle * profile.repeat_interval
	particle.lifetime = _value(random, profile.lifetime)
	var width := _value(random, profile.width)
	particle.size = Vector3(width, _value(random, profile.height), _value(random, profile.depth)) if profile.size_3d else Vector3.ONE * width
	particle.angles = Vector3(_value(random, profile.pitch), _value(random, profile.yaw), _value(random, profile.roll))
	particle.tint = profile.tint_min.lerp(profile.tint_max, random.randf())
	particle.orbit = _value(random, profile.orbit)
	particle.size_mix = random.randf()
	_prepare_origin(particle, random)
	_particles.append(particle)


func _start_particle(particle: Particle) -> void:
	var profile := particle.profile
	var material: ShaderMaterial = profile.material
	particle.draw = MeshInstance3D.new()
	particle.draw.mesh = ImmediateMesh.new() if profile.mode == 5 else profile.mesh
	particle.draw.material_override = material.duplicate()
	particle.draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particle.draw.sorting_offset = profile.sorting_offset
	particle.source.add_child(particle.draw)


func _prepare_origin(particle: Particle, random: RandomNumberGenerator) -> void:
	var profile := particle.profile
	var angle := random.randf_range(0.0, TAU)
	var direction := Vector3(cos(angle), sin(angle), 0.0)
	var cone_direction := Vector3.FORWARD.rotated(Vector3.FORWARD.cross(direction), profile.cone_angle)
	var radius: float = profile.radius * sqrt(random.randf_range(pow(1.0 - profile.radius_thickness, 2.0), 1.0))
	var point := Vector3.ZERO
	match int(profile.shape):
		2: # Hemisphere
			var elevation := random.randf_range(0.0, 1.0)
			point = radius * (direction * sqrt(1.0 - elevation * elevation) + Vector3.FORWARD * elevation)
		4, 8: # Cone base / volume
			point = radius * direction
			if profile.shape == 8:
				point += cone_direction * random.randf_range(0.0, profile.shape_length)
		14: # Small glints emitted where the character model stands.
			point = Vector3(direction.x * 0.27, random.randf_range(-0.8, 0.65), direction.y * 0.22)
	var shape_basis := Basis.from_euler(profile.shape_rotation, EULER_ORDER_ZXY)
	particle.point = profile.shape_position + shape_basis * (point * profile.shape_scale)
	particle.velocity = shape_basis * cone_direction * _value(random, profile.speed)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lead_in + duration:
		queue_free()
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for particle in _particles:
		var age := _elapsed - particle.time_offset
		var profile := particle.profile
		var ribbon_lifetime: float = profile.get("ribbon_lifetime", 0.0)
		if age < 0.0:
			continue
		if age >= particle.lifetime + ribbon_lifetime:
			if is_instance_valid(particle.draw):
				particle.draw.queue_free()
				particle.draw = null
			continue
		if particle.draw == null:
			_start_particle(particle)
		var fraction := clampf(age / particle.lifetime, 0.0, 1.0)
		var tint := particle.tint
		tint.a *= _sample(profile.opacity, fraction)
		var material := particle.draw.material_override as ShaderMaterial
		material.set_shader_parameter(&"particle_tint", tint if profile.mode != 5 else Color.WHITE)
		material.set_shader_parameter(&"particle_age", fraction)
		if profile.mode == 5:
			_draw_ribbon(particle, camera, age, ribbon_lifetime)
		else:
			_draw_particle(particle, camera, age, fraction)


func _draw_particle(particle: Particle, camera: Camera3D, age: float, fraction: float) -> void:
	var profile := particle.profile
	var point := _point_at(particle, age)
	var orientation := Basis.from_euler(particle.angles, EULER_ORDER_ZXY)
	if profile.mode != 4 and profile.alignment != 2:
		var view_basis := camera.global_basis.orthonormalized()
		if profile.alignment == 3:
			var forward := (camera.global_position - particle.source.to_global(point)).normalized()
			if not forward.is_zero_approx() and absf(forward.dot(Vector3.UP)) < 0.999:
				view_basis = Basis.looking_at(forward, Vector3.UP, true)
		orientation = particle.source.global_basis.inverse() * view_basis * orientation
	var width := lerpf(_sample(profile.size_x_min, fraction), _sample(profile.size_x, fraction), particle.size_mix)
	var scale_factor := Vector3(width, _sample(profile.size_y, fraction), _sample(profile.size_z, fraction))
	var dimensions := particle.size * scale_factor
	if profile.mode == 1:
		dimensions.y *= profile.length_scale + profile.velocity_scale * particle.velocity.length()
		point += particle.velocity.normalized() * dimensions.y * 0.5
	var pivot: Vector3 = profile.pivot
	particle.draw.transform = Transform3D(orientation.scaled_local(dimensions), point + orientation * (pivot * dimensions))


func _point_at(particle: Particle, age: float) -> Vector3:
	var profile := particle.profile
	var fraction := clampf(age / particle.lifetime, 0.0, 1.0)
	var distance := _sample(profile.speed_distance, fraction) * particle.lifetime
	var radial := _sample(profile.radial_distance, fraction) * particle.lifetime
	var offset: Vector3 = particle.point - profile.shape_position
	var distance_to_center := offset.length()
	if distance_to_center > 0.0:
		offset *= maxf(0.0, distance_to_center + radial) / distance_to_center
	return profile.shape_position + offset.rotated(Vector3.UP, particle.orbit * age) + particle.velocity * distance


func _draw_ribbon(particle: Particle, camera: Camera3D, age: float, lifetime: float) -> void:
	var ribbon := particle.draw.mesh as ImmediateMesh
	ribbon.clear_surfaces()
	var start := maxf(0.0, age - lifetime)
	var end := minf(age, particle.lifetime)
	if end <= start:
		return
	var eye := particle.source.to_local(camera.global_position)
	var profile := particle.profile
	var length: float = (end - start) * (absf(particle.orbit) * profile.radius + absf(profile.ribbon_radial_speed))
	var segments := clampi(ceili(length / profile.ribbon_spacing), 2, 40)
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segments + 1:
		var fraction := float(i) / segments
		var time := lerpf(start, end, fraction)
		var center := _point_at(particle, time)
		var tangent := _point_at(particle, minf(time + 0.004, particle.lifetime)) - _point_at(particle, maxf(time - 0.004, 0.0))
		var side := tangent.cross(eye - center).normalized()
		var size := lerpf(_sample(profile.size_x_min, time / particle.lifetime),
				_sample(profile.size_x, time / particle.lifetime), particle.size_mix)
		var width := particle.size.x * size * _sample(profile.ribbon_width, 1.0 - fraction) * 0.5
		var tint := particle.tint
		tint.a *= _sample(profile.opacity, time / particle.lifetime) * _sample(profile.ribbon_opacity, 1.0 - fraction)
		for edge in 2:
			ribbon.surface_set_color(tint)
			ribbon.surface_set_uv(Vector2(1.0 - fraction, edge))
			ribbon.surface_add_vertex(center + side * width * (2.0 * edge - 1.0))
	ribbon.surface_end()


func _value(random: RandomNumberGenerator, interval: Vector2) -> float:
	return random.randf_range(interval.x, interval.y)


func _sample(values: PackedFloat32Array, fraction: float) -> float:
	var coordinate := fraction * (values.size() - 1)
	var index := int(coordinate)
	return lerpf(values[index], values[mini(index + 1, values.size() - 1)], coordinate - index)
