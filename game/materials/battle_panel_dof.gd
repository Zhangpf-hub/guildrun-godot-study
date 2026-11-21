extends CompositorEffect

const BUFFER_CONTEXT := &"guildrun_panel_dof"
const HDR_FORMAT := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
const SCRATCH_USAGE := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT

# The shop (29288) and result (33369) use the same original Volume profile, 65264.
const FAR_START := 10.0
const FAR_END := 25.0
const MAX_RADIUS := 0.914

enum Pass { PREFILTER, BLUR_HORIZONTAL, BLUR_VERTICAL, COMPOSITE }

var _rd: RenderingDevice
var _shader_code: RDShaderSPIRV
var _shader: RID
var _pipeline: RID
var _linear_sampler: RID
var _depth_sampler: RID


func configure(shader_code: RDShaderSPIRV) -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	enabled = false
	_rd = RenderingServer.get_rendering_device()
	_shader_code = shader_code


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or _rd == null:
		return
	for resource in [_shader, _linear_sampler, _depth_sampler]:
		if resource.is_valid():
			_rd.free_rid(resource)


func _create_pipeline() -> void:
	_shader = _rd.shader_create_from_spirv(_shader_code, "Guildrun panel depth of field")
	_shader_code = null
	if not _shader.is_valid():
		push_error("Could not create the panel depth of field compute shader.")
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	var sampling := RDSamplerState.new()
	_depth_sampler = _rd.sampler_create(sampling)
	sampling.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampling.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_linear_sampler = _rd.sampler_create(sampling)


func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null or _rd == null:
		return
	var full_size := buffers.get_internal_size()
	if full_size.x == 0 or full_size.y == 0:
		return
	if _shader_code != null:
		_create_pipeline()
	if not _pipeline.is_valid():
		return

	var half_size := Vector2i(maxi(full_size.x >> 1, 1), maxi(full_size.y >> 1, 1))
	var ping := _scratch(buffers, &"ping", half_size)
	var pong := _scratch(buffers, &"pong", half_size)
	var scene_data := render_data.get_render_scene_data()
	for view in buffers.get_view_count():
		# The render projection already includes Godot's reversed depth and GPU clip correction.
		var inverse := scene_data.get_view_projection(view).inverse()
		var constants := PackedFloat32Array([
			FAR_START, 1.0 / (FAR_END - FAR_START), minf(MAX_RADIUS * half_size.x / 1080.0, 2.0), 0.0,
			inverse.z.z, inverse.w.z, inverse.z.w, inverse.w.w,
			1.0 / full_size.x, 1.0 / full_size.y, 0.0, 0.0,
			0.0, 0.0, 0.0, 0.0,
		]).to_byte_array()
		var scene := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)
		var depth_input := _sampler_binding(1, _depth_sampler, depth)
		var commands := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(commands, _pipeline)
		_dispatch(commands, constants, Pass.PREFILTER, scene, depth_input, ping, half_size)
		_dispatch(commands, constants, Pass.BLUR_HORIZONTAL, ping, depth_input, pong, half_size)
		_dispatch(commands, constants, Pass.BLUR_VERTICAL, pong, depth_input, ping, half_size)
		_dispatch(commands, constants, Pass.COMPOSITE, ping, depth_input, scene, full_size)
		_rd.compute_list_end()


func _dispatch(commands: int, constants: PackedByteArray, operation: Pass,
		source: RID, depth_input: RDUniform, target: RID, size: Vector2i) -> void:
	var output := RDUniform.new()
	output.binding = 2
	output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output.add_id(target)
	var color_input := _sampler_binding(0, _linear_sampler, source)
	var bindings := UniformSetCacheRD.get_cache(_shader, 0, [color_input, depth_input, output])
	constants.encode_s32(48, operation)
	_rd.compute_list_bind_uniform_set(commands, bindings, 0)
	_rd.compute_list_set_push_constant(commands, constants, constants.size())
	_rd.compute_list_dispatch(commands, ceili(float(size.x) / 8.0), ceili(float(size.y) / 8.0), 1)
	_rd.compute_list_add_barrier(commands)


func _sampler_binding(binding: int, sampler: RID, texture: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.binding = binding
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.add_id(sampler)
	uniform.add_id(texture)
	return uniform


func _scratch(buffers: RenderSceneBuffersRD, name: StringName, size: Vector2i) -> RID:
	return buffers.create_texture(BUFFER_CONTEXT, name, HDR_FORMAT, SCRATCH_USAGE,
			RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)
