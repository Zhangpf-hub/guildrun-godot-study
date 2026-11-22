shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform sampler2D main_mask : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D radial_noise : source_color, filter_linear, repeat_enable;
uniform sampler2D distortion : source_color, filter_linear, repeat_enable;
uniform sampler2D distortion_mask : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D color_ramp : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;

uniform vec4 particle_tint : source_color = vec4(1.0);
uniform vec4 ramp_tint : source_color = vec4(1.0);
uniform vec3 flare_stream = vec3(0.0);
uniform float flare_time = 0.0;
uniform vec2 distortion_scroll;
uniform vec2 noise_scroll;
uniform float distortion_power;
uniform float noise_bias;
uniform float opacity_power;
uniform float opacity_exponent;
uniform float color_power;
uniform float ramp_bias;
uniform float ramp_dynamics;
uniform float custom_mask_mix;
uniform float fade_distance;

vec2 texture_uv(vec2 uv) {
	return vec2(uv.x, 1.0 - uv.y);
}

float mask_value(float texel) {
	if (OUTPUT_IS_SRGB) {
		return texel <= 0.04045 ? texel / 12.92 : pow((texel + 0.055) / 1.055, 2.4);
	}
	return texel;
}

void fragment() {
	vec2 unity_uv = texture_uv(UV);
	vec2 centered = unity_uv * 2.0 - 1.0;
	float radius = length(centered);
	float angle = radius > 0.0 ? (atan(centered.x, centered.y) + PI) / TAU : 0.5;
	vec2 polar = vec2(radius, angle);
	float warp = mask_value(texture(distortion, texture_uv(polar + distortion_scroll * flare_time)).r);
	float warp_mask = mask_value(texture(distortion_mask, UV).r);
	vec2 distorted = unity_uv + centered * (warp * warp_mask * distortion_power * flare_stream.y);
	float mask = mask_value(texture(main_mask, texture_uv(distorted)).r);
	vec2 noise_uv = vec2(0.0, angle) + noise_scroll * flare_time + vec2(flare_stream.x);
	float noise = clamp(mask_value(texture(radial_noise, texture_uv(noise_uv)).r) + noise_bias, 0.0, 1.0);
	float dynamic_alpha = clamp(noise * mask * opacity_power, 0.0, 1.0);

	// The enabled dissolve graph yields zero threshold with this emitter's Custom1.z.
	float ramp = mix(mix(mask, dynamic_alpha, ramp_dynamics), dynamic_alpha, custom_mask_mix);
	vec3 color = texture(color_ramp, vec2(clamp(ramp + ramp_bias, 0.0, 1.0), 1.0)).rgb;
	float opacity = 1.0 - pow(1.0 - clamp(dynamic_alpha * particle_tint.a, 0.0, 1.0), opacity_exponent);
	float depth = texture(scene_depth, SCREEN_UV).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, mix(CLIP_SPACE_FAR, 1.0, depth), 1.0);
	float gap = abs(VERTEX.z - scene.z / scene.w);
	ALBEDO = color * ramp_tint.rgb * particle_tint.rgb * color_power * flare_stream.z;
	ALPHA = opacity * clamp(gap / fade_distance, 0.0, 1.0);
}
