#include "res://materials/environment_plane.gdshaderinc"

uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D ambient_visibility : hint_default_white, filter_linear, repeat_disable;
uniform float ambient_direct_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 texel = environment_texel(UV);
	if (texel.a * COLOR.a < alpha_threshold) {
		discard;
	}
	float visibility = 1.0;
	if (ambient_direct_strength > 0.0) {
		visibility = mix(1.0, texture(ambient_visibility, SCREEN_UV).r, ambient_direct_strength);
	}
	ALBEDO = environment_rgb(texel.rgb, COLOR.rgb * visibility, OUTPUT_IS_SRGB);
}
