shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform sampler2D main_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D flow_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dissolve_texture : source_color, filter_linear, repeat_enable;
uniform sampler2D distortion_normal : filter_linear_mipmap, repeat_enable;
uniform vec4 particle_tint : source_color = vec4(1.0);
uniform vec4 wave_stream = vec4(0.0);
uniform vec2 distortion_scale;
uniform vec2 dissolve_scale;
uniform vec2 flow_fade_in;
uniform vec2 flow_fade_out;
uniform float uv_turns;
uniform float final_uv_scale;
uniform float main_scale;
uniform float main_scroll;
uniform float flow_scale;
uniform float flow_scroll;
uniform float flow_exponent;
uniform float flow_bias;
uniform float distortion_amount;
uniform float dissolve_distortion;
uniform float dissolve_steepness;
uniform float dissolve_softness;
uniform float opacity_exponent;

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
	vec2 uv = texture_uv(UV) - vec2(0.5);
	float angle = uv_turns * TAU;
	float sinus = sin(angle);
	float cosinus = cos(angle);
	uv = vec2(dot(uv, vec2(cosinus, sinus)), dot(uv, vec2(-sinus, cosinus))) + vec2(0.5);
	float time = wave_stream.w + wave_stream.x;
	vec2 uv_scale = vec2(final_uv_scale, 1.0);
	vec2 normal_uv = uv * distortion_scale + wave_stream.x * vec2(0.751, 1.124);
	vec4 packed_normal = texture(distortion_normal, texture_uv(normal_uv * uv_scale));
	vec2 distortion = vec2(packed_normal.r * packed_normal.a, packed_normal.g) * 2.0 - 1.0;
	vec2 warp = distortion * distortion_amount;
	float flow_v = pow(clamp(uv.y, 0.0, 1.0), flow_exponent);
	vec2 flow_uv = vec2(uv.x * flow_scale, flow_v + time * flow_scroll);
	float flow = mix(flow_bias, 1.0, mask_value(texture(flow_texture, texture_uv((flow_uv + warp) * uv_scale)).r));
	vec2 main_uv = vec2(uv.x * main_scale, flow_v + time * main_scroll);
	float main_mask = mask_value(texture(main_texture, texture_uv((main_uv + warp) * uv_scale)).r);
	vec2 dissolve_uv = uv * dissolve_scale + wave_stream.x * vec2(0.713, 1.175) + distortion * dissolve_distortion;
	float dissolve_noise = 1.0 - mask_value(texture(dissolve_texture, texture_uv(dissolve_uv * uv_scale)).r);
	float gate = min(smoothstep(flow_fade_in.x, flow_fade_in.y, uv.y),
		1.0 - smoothstep(flow_fade_out.y, flow_fade_out.x, uv.y));
	float start = -dissolve_steepness - 1.0;
	float near_edge = dissolve_steepness * uv.y + mix(start, 1.0, wave_stream.z);
	float far_edge = dissolve_steepness * (1.0 - uv.y) + mix(start, 1.0, wave_stream.y);
	float dissolve = clamp(clamp(max(near_edge, far_edge), -1.0, 1.0) + dissolve_noise, 0.0, 1.0);
	float opacity = clamp(main_mask * flow * gate * max(0.0, 1.0 - dissolve * dissolve_softness) * particle_tint.a, 0.0, 1.0);
	// The authored Custom2.x is zero. The forward pass blends black with the animated alpha.
	ALBEDO = vec3(0.0);
	ALPHA = 1.0 - pow(1.0 - opacity, opacity_exponent);
}
