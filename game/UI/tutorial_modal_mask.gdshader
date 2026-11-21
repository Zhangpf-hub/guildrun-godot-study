shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 opening = vec4(0.0);
uniform bool show_grid = false;

vec3 to_linear(vec3 value) {
	return mix(value / 12.92, pow((value + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), value));
}

vec3 to_srgb(vec3 value) {
	return mix(12.92 * value, 1.055 * pow(value, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), value));
}

void fragment() {
	if (show_grid && UV.x >= opening.x && UV.y >= opening.y && UV.x <= opening.z && UV.y <= opening.w) {
		discard;
	}
	// Unity's black tutorial image blends before the linear framebuffer is encoded.
	vec4 behind = textureLod(screen_texture, SCREEN_UV, 0.0);
	COLOR = vec4(to_srgb(to_linear(behind.rgb) * (1.0 - COLOR.a)), behind.a);
}
