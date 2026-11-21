extends CompositorEffect

const BUFFER_CONTEXT := &"guildrun_battle_occlusion"
const BUFFER_FORMAT := RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
const BUFFER_USAGE := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT

var _rd: RenderingDevice
var _shader_code: RDShaderSPIRV
var _shader: RID
var _pipeline: RID
var _nearest: RID
var _linear: RID
var _noise_atlas: Texture2D
var _noise_rid: RID
var _sample_settings: Vector4
var _direct_strength: float
var _receivers: Array[ShaderMaterial] = []
var _visibility := Texture2DRD.new()
var _frame := 0
var _target := RID()
var _target_size := Vector2i.ZERO
var _published := RID()
var _retired: Array[RID] = []
var _publication_pending := false


func configure(code: RDShaderSPIRV, noise_atlas: Texture2D, settings: Vector4) -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_OPAQUE
	needs_normal_roughness = true
	access_resolved_depth = true
	_rd = RenderingServer.get_rendering_device()
	_shader_code = code
	_noise_atlas = noise_atlas
	_sample_settings = Vector4(settings.x * 1.5, settings.y, settings.z, 0.0)
	_direct_strength = settings.w


func bind_receiver(material: ShaderMaterial) -> void:
	material.set_shader_parameter("ambient_visibility", _visibility)
	_receivers.append(material)


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or _rd == null:
		return
	# Detach the material samplers before releasing the underlying RD texture.
	for receiver in _receivers:
		receiver.set_shader_parameter("ambient_visibility", null)
	_visibility.texture_rd_rid = RID()
	for resource in _retired + [_shader, _nearest, _linear, _target]:
		if resource.is_valid():
			_rd.free_rid(resource)


func _create_pipeline() -> void:
	_shader = _rd.shader_create_from_spirv(_shader_code, "Guildrun ambient occlusion")
	_shader_code = null
	if not _shader.is_valid():
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	var sampler := RDSamplerState.new()
	_nearest = _rd.sampler_create(sampler)
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_linear = _rd.sampler_create(sampler)
	_noise_rid = RenderingServer.texture_get_rd_texture(_noise_atlas.get_rid())


func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null or buffers.get_view_count() != 1 or not buffers.has_texture(&"forward_clustered", &"normal_roughness"):
		return
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	if _shader_code != null:
		_create_pipeline()
	if not _pipeline.is_valid() or not _noise_rid.is_valid():
		return
	var depth := buffers.get_depth_layer(0)
	var normals := buffers.get_texture(&"forward_clustered", &"normal_roughness")
	var a := buffers.create_texture(BUFFER_CONTEXT, &"estimate", BUFFER_FORMAT, BUFFER_USAGE,
			RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)
	var b := buffers.create_texture(BUFFER_CONTEXT, &"blur", BUFFER_FORMAT, BUFFER_USAGE,
			RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)
	if _target_size != size:
		if _target.is_valid():
			_retired.append(_target)
		var format := RDTextureFormat.new()
		format.format = BUFFER_FORMAT
		format.width = size.x
		format.height = size.y
		format.usage_bits = BUFFER_USAGE | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		_target = _rd.texture_create(format, RDTextureView.new())
		_target_size = size
	if not _target.is_valid():
		return

	var scene := render_data.get_render_scene_data()
	var projection := scene.get_view_projection(0)
	var inverse := projection.inverse()
	var noise_rows := maxi(1, _noise_atlas.get_height() >> 8)
	var parameters := PackedFloat32Array([
		inverse.x.x, inverse.x.y, inverse.x.z, inverse.x.w,
		inverse.y.x, inverse.y.y, inverse.y.z, inverse.y.w,
		inverse.z.x, inverse.z.y, inverse.z.z, inverse.z.w,
		inverse.w.x, inverse.w.y, inverse.w.z, inverse.w.w,
		projection.x.x, projection.y.y, projection.z.x, projection.z.y,
		projection.w.x, projection.w.y, projection.z.w, projection.w.w,
		_sample_settings.x, _sample_settings.y, _sample_settings.z, 0.0,
		float((_frame * 157) & 255), float((_frame * 67) & 255), float(_frame % noise_rows), float(noise_rows),
	]).to_byte_array()
	_frame += 1
	var inputs: Array[RID] = [depth, a, b, a]
	var outputs: Array[RID] = [a, b, a, _target]
	var commands := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(commands, _pipeline)
	for pass_index in 4:
		var image := RDUniform.new()
		image.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		image.binding = 0
		image.add_id(outputs[pass_index])
		var bindings := UniformSetCacheRD.get_cache(_shader, 0, [
			image,
			_sampled(1, depth, _nearest),
			_sampled(2, normals, _nearest),
			_sampled(3, inputs[pass_index], _linear),
			_sampled(4, _noise_rid, _nearest),
		])
		parameters.encode_float(108, float(pass_index))
		_rd.compute_list_bind_uniform_set(commands, bindings, 0)
		_rd.compute_list_set_push_constant(commands, parameters, parameters.size())
		_rd.compute_list_dispatch(commands, ceili(float(size.x) / 8.0), ceili(float(size.y) / 8.0), 1)
		_rd.compute_list_add_barrier(commands)
	_rd.compute_list_end()
	if _published != _target and not _publication_pending:
		_publication_pending = true
		_publish_between_frames.call_deferred()


func _publish_between_frames() -> void:
	# Updating a material's texture inside PRE_OPAQUE invalidates uniforms
	# already collected for this frame's draw lists.
	RenderingServer.call_on_render_thread(func() -> void:
		_visibility.texture_rd_rid = _target
		_published = _target
		for receiver in _receivers:
			receiver.set_shader_parameter("ambient_direct_strength", _direct_strength)
		for texture in _retired:
			_rd.free_rid(texture)
		_retired.clear()
		_publication_pending = false
	)


func _sampled(binding: int, texture: RID, sampler: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.binding = binding
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.add_id(sampler)
	uniform.add_id(texture)
	return uniform
