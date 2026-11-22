class_name GuildrunCharacterRagdoll
extends PhysicalBoneSimulator3D

# Unity's layer 13 collides with the layer-6 arena and excludes layer 10 and other proxies.
const BODY_LAYER := 1 << 13
const FLOOR_LAYER := 1 << 6

var _bodies: Array[PhysicalBone3D] = []
var _linear_damping: float
var _angular_damping: float
var _speed := 1.0
var _paused_linear: Array[Vector3] = []
var _paused_angular: Array[Vector3] = []


static func bind_floor(environment: Node3D) -> bool:
	var receiver := environment.find_child("ShadowPlane", true, false)
	if receiver == null:
		return false
	var surface := receiver.get_node_or_null(^"UnityMesh") as MeshInstance3D
	if surface == null or surface.mesh == null:
		return false

	# Unity uses a MeshCollider on this same mesh. Bake the scene transform into the shape
	# so the physics body doesn't inherit the receiver's nonuniform scale.
	var vertices := surface.mesh.get_faces()
	var to_environment := environment.global_transform.affine_inverse() * surface.global_transform
	for i in vertices.size():
		vertices[i] = to_environment * vertices[i]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(vertices)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var floor := StaticBody3D.new()
	floor.name = &"RagdollGround"
	floor.collision_layer = FLOOR_LAYER
	floor.collision_mask = BODY_LAYER
	floor.add_child(collision)
	environment.add_child(floor)
	return true


func start(skeleton: Skeleton3D, profile: Dictionary, impulse: Vector3, speed: float) -> void:
	_linear_damping = profile.linear_damping
	_angular_damping = profile.angular_damping
	var definitions: Dictionary[int, Dictionary] = {}
	for definition: Dictionary in profile.bodies:
		var index := skeleton.find_bone(definition.name)
		if index >= 0:
			definitions[index] = definition
	var scale_factor := skeleton.global_basis.get_scale().y
	for index in skeleton.get_bone_count():
		if definitions.has(index):
			_add_body(definitions[index], scale_factor)
	physical_bones_start_simulation()
	for body in _bodies:
		body.linear_velocity = impulse / body.mass
	set_speed(speed)


static func restore_missing_leaves(skeleton: Skeleton3D, profile: Dictionary) -> void:
	for definition: Dictionary in profile.bodies:
		if not definition.has("rest") or skeleton.find_bone(definition.name) >= 0:
			continue
		var rest: Dictionary = definition.rest
		var parent := skeleton.find_bone(rest.parent)
		if parent < 0:
			continue
		var index := skeleton.add_bone(definition.name)
		skeleton.set_bone_parent(index, parent)
		var q: Array = rest.rotation
		skeleton.set_bone_rest(index, Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3]).normalized()),
				_vector(rest.position)))
		skeleton.reset_bone_pose(index)


func set_speed(multiplier: float) -> void:
	if is_equal_approx(multiplier, _speed):
		return
	var denominator := _speed if _speed > 0.0 else 1.0
	if _speed > 0.0 and multiplier == 0.0:
		for body in _bodies:
			_paused_linear.append(body.linear_velocity / denominator)
			_paused_angular.append(body.angular_velocity / denominator)
	for i in _bodies.size():
		var body := _bodies[i]
		var linear := body.linear_velocity / denominator if _speed > 0.0 else _paused_linear[i]
		var angular := body.angular_velocity / denominator if _speed > 0.0 else _paused_angular[i]
		if multiplier == 0.0:
			PhysicsServer3D.body_set_mode(body.get_rid(), PhysicsServer3D.BODY_MODE_STATIC)
		elif _speed == 0.0:
			PhysicsServer3D.body_set_mode(body.get_rid(), PhysicsServer3D.BODY_MODE_RIGID)
		# Scale velocity by the clock rate and acceleration by its square.
		body.gravity_scale = multiplier * multiplier
		body.linear_damp = _linear_damping * multiplier
		body.angular_damp = _angular_damping * multiplier
		body.linear_velocity = linear * multiplier
		body.angular_velocity = angular * multiplier
	if multiplier > 0.0:
		_paused_linear.clear()
		_paused_angular.clear()
	_speed = multiplier


func _add_body(definition: Dictionary, scale_factor: float) -> void:
	var body := PhysicalBone3D.new()
	body.name = definition.name
	body.bone_name = definition.name
	body.mass = maxf(0.001, definition.mass)
	body.collision_layer = BODY_LAYER
	body.collision_mask = FLOOR_LAYER
	body.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	body.linear_damp = _linear_damping
	body.angular_damp = _angular_damping
	body.friction = 0.6
	add_child(body)
	if definition.has("joint"):
		_add_joint(body, definition.joint)
	for shape: Dictionary in definition.shapes:
		_add_shape(body, shape, scale_factor)
	_bodies.append(body)


func _add_joint(body: PhysicalBone3D, joint: Dictionary) -> void:
	var twist := _vector(joint.twist)
	var swing := _vector(joint.swing)
	body.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
	if not twist.cross(swing).is_zero_approx():
		body.joint_offset = Transform3D(Basis(twist, swing, twist.cross(swing)).orthonormalized(), Vector3.ZERO)
	for i in 3:
		var prefix := "joint_constraints/%s/" % "xyz"[i]
		body.set(prefix + "linear_limit_enabled", true)
		body.set(prefix + "linear_limit_lower", 0.0)
		body.set(prefix + "linear_limit_upper", 0.0)
		var limited: bool = joint.has("lower")
		body.set(prefix + "angular_limit_enabled", limited)
		if limited:
			body.set(prefix + "angular_limit_lower", float(joint.lower[i]))
			body.set(prefix + "angular_limit_upper", float(joint.upper[i]))


func _add_shape(body: PhysicalBone3D, definition: Dictionary, scale_factor: float) -> void:
	var collision := CollisionShape3D.new()
	var radius: float = definition.radius * scale_factor
	if definition.has("height"):
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		capsule.height = maxf(2.0 * radius, definition.height * scale_factor)
		collision.shape = capsule
		if int(definition.axis) == 0:
			collision.rotate_z(PI / 2.0)
		elif int(definition.axis) == 2:
			collision.rotate_x(PI / 2.0)
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		collision.shape = sphere
	if definition.has("rotation"):
		var euler := _vector(definition.rotation) * (PI / 180.0)
		collision.basis = Basis.from_euler(euler, EULER_ORDER_ZXY) * collision.basis
	collision.position = _vector(definition.center) * scale_factor
	body.add_child(collision)


static func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
