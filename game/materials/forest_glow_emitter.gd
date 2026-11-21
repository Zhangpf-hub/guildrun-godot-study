extends Node3D

# The source emitters have at most two visible particles each.
class GlowParticle:
	var quad: MeshInstance3D
	var tint: Color
	var emitted_at: float
	var lifetime: float
	var speed: float
	var origin: Vector3


@export var source_seed: int
@export var duration: float = 5.0
@export var simulation_speed: float = 1.0
@export var prewarm: bool
@export var looping: bool
@export var births_per_second: float
@export var burst_count: int
@export var lifetime_range: Vector2
@export var speed_range: Vector2
@export var width_range: Vector2
@export var height_range: Vector2
@export var independent_height: bool
@export var spin_range: Vector2
@export var tint_min: Color = Color.WHITE
@export var tint_max: Color = Color.WHITE
@export var alpha_curve: Gradient
@export var ground_half_extents: Vector2
@export var emission_direction: Vector3 = Vector3.FORWARD
# Radius and depth of a zero-angle cone volume.
@export var emission_cylinder: Vector2
@export var atlas_columns: int = 1
@export var start_frame_range: Vector2

var _rng := RandomNumberGenerator.new()
var _particles: Array[GlowParticle] = []
var _elapsed: float = 0.0
var _next_burst: float = 0.0
var _next_birth: float = INF
var _birth_interval: float = INF


func _ready() -> void:
	if source_seed < 0:
		_rng.randomize()
	else:
		_rng.seed = source_seed
	for child in get_children():
		if child is MeshInstance3D:
			var particle := GlowParticle.new()
			particle.quad = child
			particle.emitted_at = -INF
			_particles.append(particle)
	if births_per_second > 0.0:
		_birth_interval = 1.0 / births_per_second
		_next_birth = _birth_interval
	_advance_to(duration if prewarm else 0.0)
	set_process(looping)


func _process(delta: float) -> void:
	_advance_to(_elapsed + delta * simulation_speed)


func _advance_to(time: float) -> void:
	# Process births at their scheduled time, even after a slow rendered frame.
	while minf(_next_burst, _next_birth) <= time:
		if _next_burst <= _next_birth:
			for count in burst_count:
				_emit_at(_next_burst)
			_next_burst = _next_burst + duration if looping else INF
		else:
			_emit_at(_next_birth)
			_next_birth += _birth_interval
	_elapsed = time
	for particle in _particles:
		var age := time - particle.emitted_at
		var active := age < particle.lifetime
		particle.quad.visible = active
		if active:
			_update_quad(particle, age)


func _emit_at(time: float) -> void:
	for particle in _particles:
		if time - particle.emitted_at < particle.lifetime:
			continue
		particle.emitted_at = time
		particle.lifetime = _between(lifetime_range) if looping else INF
		particle.speed = _between(speed_range)
		particle.tint = tint_min.lerp(tint_max, _rng.randf())
		if emission_cylinder.x > 0.0:
			var angle := _rng.randf_range(0.0, TAU)
			var radius := sqrt(_rng.randf()) * emission_cylinder.x
			var depth := _rng.randf_range(0.0, emission_cylinder.y)
			particle.origin = particle.quad.basis.orthonormalized() * Vector3(
					cos(angle) * radius, depth, sin(angle) * radius)
		else:
			particle.origin = Vector3(
					_rng.randf_range(-ground_half_extents.x, ground_half_extents.x), 0.0,
					_rng.randf_range(-ground_half_extents.y, ground_half_extents.y))
		var width := _between(width_range)
		particle.quad.scale = Vector3(width, _between(height_range) if independent_height else width, 1.0)
		if emission_cylinder.x <= 0.0:
			var start_frame := mini(int(_between(start_frame_range) * atlas_columns), atlas_columns - 1)
			particle.quad.set_instance_shader_parameter(&"sprite_pose", Vector4(
					_between(spin_range), 1.0 / float(atlas_columns), float(start_frame) / float(atlas_columns), 0.0))
		return


func _update_quad(particle: GlowParticle, age: float) -> void:
	particle.quad.position = particle.origin + emission_direction * (particle.speed * age)
	var tint := particle.tint
	if alpha_curve != null:
		tint.a *= alpha_curve.sample(age / particle.lifetime).a
	particle.quad.set_instance_shader_parameter(&"particle_tint", tint)


func _between(limits: Vector2) -> float:
	return _rng.randf_range(limits.x, limits.y)
