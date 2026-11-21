shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D background : hint_screen_texture, repeat_disable, filter_nearest;

vec3 to_linear(vec3 srgb) {
	return mix(srgb / 12.92, pow((srgb + 0.055) / 1.055, vec3(2.4)), greaterThan(srgb, vec3(0.04045)));
}

vec3 to_srgb(vec3 linear_rgb) {
	return mix(linear_rgb * 12.92, 1.055 * pow(linear_rgb, vec3(1.0 / 2.4)) - 0.055,
			greaterThan(linear_rgb, vec3(0.0031308)));
}

void fragment() {
	// The Compatibility canvas contains sRGB pixels. Blend the Unity UI tint
	// and sprite with the backdrop in linear light before storing them again.
	vec3 behind = texture(background, SCREEN_UV).rgb;
	vec3 composite = mix(to_linear(behind), to_linear(COLOR.rgb), COLOR.a);
	COLOR = vec4(to_srgb(composite), 1.0);
}
