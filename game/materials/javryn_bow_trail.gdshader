shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D main_texture : repeat_enable, filter_linear_mipmap;
uniform sampler2D warp_texture : repeat_enable, filter_linear_mipmap;
uniform sampler2D dissolve_texture : repeat_enable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float intensity = 1.0;
uniform vec2 warp_speed = vec2(0.29, -0.25);
uniform float warp_strength = 0.04;
uniform vec2 dissolve_speed = vec2(0.10, -0.50);
uniform float dissolve_threshold = 0.8;
instance uniform float effect_scene_seconds = 0.0;

vec2 sampled_uv(vec2 native_uv) {
	return vec2(native_uv.x, 1.0 - native_uv.y);
}

void fragment() {
	// Material 620 uses the red-channel and no-scroll branches of resources.assets:707.
	vec2 uv = sampled_uv(UV);
	float warp = texture(warp_texture, sampled_uv(2.0 * (uv + warp_speed * effect_scene_seconds))).r;
	float opacity = texture(main_texture, sampled_uv(uv * mix(1.0, warp, warp_strength))).r;
	float dissolve = texture(dissolve_texture, sampled_uv(2.0 * (uv + dissolve_speed * effect_scene_seconds))).r;
	opacity *= dissolve - (2.0 * abs(dissolve_threshold) - 1.0);
	// The source adds the undissolved source texture and doubles the result in its non-distort branch.
	opacity += texture(main_texture, UV).r;
	ALBEDO = tint.rgb * COLOR.rgb * intensity;
	ALPHA = clamp(2.0 * opacity * COLOR.a, 0.0, 1.0);
}
