uniform sampler2D main_texture : source_color, filter_linear, repeat_enable;
uniform sampler2D main_texture_clamped : source_color, filter_linear, repeat_disable;
uniform sampler2D main_texture_point_clamped : source_color, filter_nearest, repeat_disable;
uniform sampler2D main_texture_mipped : source_color, filter_linear_mipmap, repeat_enable;
uniform int sampler_mode = 0;
uniform vec3 tint = vec3(1.0);

vec4 environment_texel(vec2 uv) {
	if (sampler_mode == 1) {
		return texture(main_texture_clamped, uv);
	}
	if (sampler_mode == 2) {
		return texture(main_texture_point_clamped, uv);
	}
	if (sampler_mode == 3) {
		return texture(main_texture_mipped, uv);
	}
	return texture(main_texture, uv);
}

vec3 srgb_to_linear(vec3 color) {
	return mix(color / 12.92, pow((color + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), color));
}

vec3 linear_to_srgb(vec3 color) {
	return mix(color * 12.92, 1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055,
		step(vec3(0.0031308), color));
}

vec3 environment_rgb(vec3 sample_rgb, vec3 vertex_rgb, bool output_is_srgb) {
	vec3 linear_rgb = output_is_srgb ? srgb_to_linear(sample_rgb) : sample_rgb;
	linear_rgb *= tint * vertex_rgb;
	return output_is_srgb ? linear_to_srgb(linear_rgb) : linear_rgb;
}
