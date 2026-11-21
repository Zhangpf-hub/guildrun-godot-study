shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D world_frame : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D grade_lookup : repeat_disable, filter_linear;
uniform int grade_strip = 0;
uniform float exposure = 1.0;
uniform float result_blur : hint_range(0.0, 12.0) = 0.0;
uniform bool neutral_tonemap = false;
uniform vec3 vignette_color = vec3(0.0);
uniform vec2 vignette_center = vec2(0.5);
uniform float vignette_intensity = 0.0;
uniform float vignette_smoothness = 1.0;
uniform bool vignette_rounded = false;

vec3 from_srgb(vec3 value) {
	return mix(value / 12.92, pow((value + 0.055) / 1.055, vec3(2.4)), greaterThan(value, vec3(0.04045)));
}

vec3 to_srgb(vec3 value) {
	return mix(value * 12.92, 1.055 * pow(value, vec3(1.0 / 2.4)) - 0.055, greaterThan(value, vec3(0.0031308)));
}

vec3 neutral_curve(vec3 x) {
	return (x * (0.2 * x + 0.24 * 0.29) + 0.272 * 0.02)
			/ (x * (0.2 * x + 0.29) + 0.272 * 0.3) - 0.02 / 0.3;
}

vec3 apply_grade(vec3 color) {
	// Same linear 32^3 LUT as Forward+, from the already resolved SDR frame.
	vec3 grid = color * 31.0;
	vec2 uv = (vec2(grid.r + 32.0 * floor(grid.b), grid.g + 32.0 * float(grade_strip)) + 0.5)
			/ vec2(1024.0, 128.0);
	vec3 first = texture(grade_lookup, uv).rgb;
	vec3 next = texture(grade_lookup, uv + vec2(1.0 / 32.0, 0.0)).rgb;
	return mix(first, next, fract(grid.b));
}

void fragment() {
	vec3 sample_rgb = texture(world_frame, SCREEN_UV).rgb;
	if (result_blur > 0.0) {
		vec2 step_uv = SCREEN_PIXEL_SIZE * (result_blur / (769.0 * SCREEN_PIXEL_SIZE.y));
		vec2 x = vec2(step_uv.x, 0.0);
		vec2 y = vec2(0.0, step_uv.y);
		sample_rgb = (sample_rgb * 4.0 + 2.0 * (
				texture(world_frame, SCREEN_UV - x).rgb + texture(world_frame, SCREEN_UV + x).rgb
				+ texture(world_frame, SCREEN_UV - y).rgb + texture(world_frame, SCREEN_UV + y).rgb)
				+ texture(world_frame, SCREEN_UV - x - y).rgb + texture(world_frame, SCREEN_UV + x - y).rgb
				+ texture(world_frame, SCREEN_UV - x + y).rgb + texture(world_frame, SCREEN_UV + x + y).rgb) / 16.0;
	}
	vec3 rgb = from_srgb(sample_rgb);
	if (vignette_intensity > 0.0) {
		vec2 distance_from_center = (SCREEN_UV - vignette_center) * vignette_intensity;
		if (vignette_rounded) {
			distance_from_center.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		}
		float center_weight = pow(clamp(1.0 - dot(distance_from_center, distance_from_center), 0.0, 1.0), vignette_smoothness);
		rgb *= mix(vignette_color, vec3(1.0), center_weight);
	}
	rgb *= exposure;
	if (neutral_tonemap) {
		vec3 white_scale = 1.0 / neutral_curve(vec3(5.3));
		rgb = neutral_curve(rgb * white_scale) * white_scale;
	}
	COLOR = vec4(to_srgb(apply_grade(clamp(rgb, vec3(0.0), vec3(1.0)))), 1.0);
}
