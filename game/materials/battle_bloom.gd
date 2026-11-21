extends CompositorEffect

const BUFFER_CONTEXT := &"guildrun_battle_bloom"
const HDR_FORMAT := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
const BLOOM_USAGE := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT

enum Pass { PREFILTER, BLUR_HORIZONTAL, BLUR_VERTICAL, UPSAMPLE, COMPOSITE }

var _rd: RenderingDevice
var _shader_code: RDShaderSPIRV
var _shader: RID
var _pipeline: RID
var _sampler: RID
var _parameters: PackedByteArray
var _start_shift: int
var _max_levels: int
var _has_bloom: bool
var _grade_texture: Texture2D
var _grade_rd_texture: RID


func configure(shader_code: RDShaderSPIRV, filter: Vector4, strength: Vector4, quality: Vector3i) -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	_rd = RenderingServer.get_rendering_device()
	_shader_code = shader_code
	_parameters = PackedFloat32Array([
		filter.x, filter.y, filter.z, filter.w,
		strength.x, strength.y, strength.z, strength.w,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
	]).to_byte_array()
	_parameters.encode_s32(36, quality.x)
	_start_shift = quality.y
	_max_levels = quality.z
	_has_bloom = strength.w > 0.0


func configure_hdr_grade(material: ShaderMaterial) -> void:
	var center: Vector2 = material.get_shader_parameter("vignette_center")
	var color: Vector3 = material.get_shader_parameter("vignette_color")
	var grade := PackedFloat32Array([
		float(material.get_shader_parameter("exposure")),
		float(material.get_shader_parameter("neutral_tonemap")),
		float(material.get_shader_parameter("vignette_rounded")),
		0.0,
		center.x, center.y,
		float(material.get_shader_parameter("vignette_intensity")),
		float(material.get_shader_parameter("vignette_smoothness")),
		color.x, color.y, color.z, 0.0,
	]).to_byte_array()
	_parameters.resize(48)
	_parameters.append_array(grade)
	_grade_texture = material.get_shader_parameter("grade_lookup") as Texture2D


func set_grade_strip(strip: int) -> void:
	RenderingServer.call_on_render_thread(func() -> void:
		_parameters.encode_s32(40, strip)
	)


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or _rd == null:
		return
	if _shader.is_valid():
		_rd.free_rid(_shader) # Also frees the dependent pipeline and uniform sets.
	if _sampler.is_valid():
		_rd.free_rid(_sampler)


func _create_pipeline() -> void:
	_shader = _rd.shader_create_from_spirv(_shader_code, "Guildrun battle bloom")
	_shader_code = null
	if not _shader.is_valid():
		push_error("Could not create the battle bloom compute shader.")
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	var sampling := RDSamplerState.new()
	sampling.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampling.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampling.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampling.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(sampling)
	if _grade_texture != null:
		_grade_rd_texture = RenderingServer.texture_get_rd_texture(_grade_texture.get_rid())
		_parameters.encode_s32(44, int(_grade_rd_texture.is_valid()))


func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null or _rd == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	if _shader_code != null:
		_create_pipeline()
	if not _pipeline.is_valid():
		return

	if not _has_bloom:
		var commands := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(commands, _pipeline)
		for view in buffers.get_view_count():
			var scene := buffers.get_color_layer(view)
			_dispatch(commands, Pass.COMPOSITE, scene, scene, scene, size)
		_rd.compute_list_end()
		return

	var dimensions: Array[Vector2i] = [_mip_size(size, _start_shift)]
	# URP stops one level before its largest dimension would reach one texel.
	var largest := maxi(dimensions[0].x, dimensions[0].y)
	while largest >= 8 and dimensions.size() < _max_levels:
		dimensions.append(_mip_size(dimensions[-1], 1))
		largest >>= 1

	var down: Array[RID] = []
	var scratch: Array[RID] = []
	for level in dimensions.size():
		down.append(_texture(buffers, "down", level, dimensions[level]))
		scratch.append(_texture(buffers, "scratch", level, dimensions[level]))
	for view in buffers.get_view_count():
		_bloom_view(buffers.get_color_layer(view), size, dimensions, down, scratch)


func _bloom_view(scene: RID, size: Vector2i, dimensions: Array[Vector2i], down: Array[RID], scratch: Array[RID]) -> void:
	var commands := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(commands, _pipeline)
	_dispatch(commands, Pass.PREFILTER, scene, scene, down[0], dimensions[0])
	for level in range(1, down.size()):
		_dispatch(commands, Pass.BLUR_HORIZONTAL, down[level - 1], down[level - 1], scratch[level], dimensions[level])
		_dispatch(commands, Pass.BLUR_VERTICAL, scratch[level], scratch[level], down[level], dimensions[level])
	var bloom := down[-1]
	for level in range(down.size() - 2, -1, -1):
		_dispatch(commands, Pass.UPSAMPLE, down[level], bloom, scratch[level], dimensions[level])
		bloom = scratch[level]
	_dispatch(commands, Pass.COMPOSITE, bloom, bloom, scene, size)
	_rd.compute_list_end()


func _dispatch(commands: int, operation: Pass, source: RID, lower: RID, target: RID, size: Vector2i) -> void:
	var upper_mip := _sampled_uniform(0, source)
	var lower_mip := _sampled_uniform(1, lower)
	var image := RDUniform.new()
	image.binding = 2
	image.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	image.add_id(target)
	var grade_texture := _grade_rd_texture if _grade_rd_texture.is_valid() else source
	var grade_lookup := _sampled_uniform(3, grade_texture)
	var bindings := UniformSetCacheRD.get_cache(_shader, 0, [upper_mip, lower_mip, image, grade_lookup])

	_parameters.encode_s32(32, operation)
	_rd.compute_list_bind_uniform_set(commands, bindings, 0)
	_rd.compute_list_set_push_constant(commands, _parameters, _parameters.size())
	_rd.compute_list_dispatch(commands, ceili(float(size.x) / 8.0), ceili(float(size.y) / 8.0), 1)
	_rd.compute_list_add_barrier(commands)


func _sampled_uniform(binding: int, texture: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.binding = binding
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.add_id(_sampler)
	uniform.add_id(texture)
	return uniform


func _texture(buffers: RenderSceneBuffersRD, kind: String, level: int, size: Vector2i) -> RID:
	# Buffers own the textures and invalidate them when the viewport is resized.
	var name := StringName("%s_%d_%d" % [kind, _start_shift, level])
	return buffers.create_texture(BUFFER_CONTEXT, name, HDR_FORMAT, BLOOM_USAGE,
			RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)


func _mip_size(size: Vector2i, shift: int) -> Vector2i:
	return Vector2i(maxi(size.x >> shift, 1), maxi(size.y >> shift, 1))
