shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float fresnel_power = 0.41;

float noise_at(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.546875);
}

float value_noise(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 fraction = fract(uv);
	vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
	float bottom = mix(noise_at(cell), noise_at(cell + vec2(1.0, 0.0)), blend.x);
	float top = mix(noise_at(cell + vec2(0.0, 1.0)), noise_at(cell + vec2(1.0)), blend.x);
	return mix(bottom, top, blend.y);
}

void fragment() {
	// Unity's transparent forward pass of sharedassets1.assets:3001.
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, fresnel_power);
	ALBEDO = COLOR.rgb * tint.rgb * rim;
	ALPHA = 0.125 * value_noise(uv * 30.0)
			+ 0.25 * value_noise(uv * 15.0) + 0.5 * value_noise(uv * 7.5);
}
