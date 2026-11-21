shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, fog_disabled;

uniform sampler2D beam_texture : repeat_enable, filter_linear_mipmap;
uniform sampler2D beam_mask : repeat_enable, filter_linear_mipmap;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 beam_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 mask_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform float intensity = 1.0;
uniform float fade_distance = 0.0;
uniform bool additive = false;
uniform bool beam_is_srgb = false;
instance uniform vec4 particle_tint : source_color = vec4(1.0);

void vertex() {
	// Match stretched billboards by projecting particle velocity onto the camera plane.
	vec2 projected = MODELVIEW_MATRIX[1].xy;
	vec2 up = length(projected) > 0.0001 ? normalize(projected) : vec2(0.0, 1.0);
	vec2 right = vec2(up.y, -up.x);
	MODELVIEW_MATRIX[0] = vec4(right * length(MODEL_MATRIX[0].xyz), 0.0, 0.0);
	MODELVIEW_MATRIX[1] = vec4(up * length(MODEL_MATRIX[1].xyz), 0.0, 0.0);
	MODELVIEW_MATRIX[2] = vec4(0.0, 0.0, 1.0, 0.0);
}

void fragment() {
	// The forest materials select the monochrome branch of VFX_SG (resources.assets:711).
	// Unity's beam maps run along U. The Godot quad stretches along local Y.
	vec2 ray_uv = vec2(1.0 - UV.y, UV.x);
	float beam = texture(beam_texture, ray_uv * beam_uv.xy + beam_uv.zw).r;
	if (beam_is_srgb) {
		beam = beam <= 0.04045 ? beam / 12.92 : pow((beam + 0.055) / 1.055, 2.4);
	}
	float mask = texture(beam_mask, ray_uv * mask_uv.xy + mask_uv.zw).r;
	float fade = 1.0;
	if (fade_distance > 0.0) {
		// The source DEPTHFADE variant uses an eye-space depth difference.
		float depth = texture(scene_depth, SCREEN_UV).r;
		float ndc_depth = mix(CLIP_SPACE_FAR, 1.0, depth);
		vec4 scene_position = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, ndc_depth, 1.0);
		fade = clamp((VERTEX.z - scene_position.z / scene_position.w) / fade_distance, 0.0, 1.0);
	}
	float opacity = clamp(beam * mask * particle_tint.a * fade, 0.0, 1.0);
	ALBEDO = particle_tint.rgb * opacity * intensity;
	ALPHA = additive ? 0.0 : opacity;
}
