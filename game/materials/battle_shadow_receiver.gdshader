shader_type spatial;
render_mode cull_back, depth_draw_never, fog_disabled, ambient_light_disabled, specular_disabled;

uniform vec4 shadow_tint : source_color = vec4(0.0, 0.0, 0.0, 0.6);

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
uniform sampler2D opaque_color : hint_screen_texture, repeat_disable, filter_nearest;

vec3 from_srgb(vec3 color) {
	return mix(color / 12.92, pow((color + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), color));
}
#endif

void fragment() {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = vec3(1.0);
	ALPHA = 1.0;
#else
	// ShadowDrawerMod outputs the authored tint independently of the light color.
	ALBEDO = vec3(0.0);
	EMISSION = shadow_tint.rgb;
	ALPHA = 0.0;
#endif
}

void light() {
	// Each battle environment has one main directional light.
	if (LIGHT_IS_DIRECTIONAL) {
		float opacity = shadow_tint.a * (1.0 - clamp(ATTENUATION, 0.0, 1.0));
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		// GLES3 fixes the fragment's alpha before processing the shadowed light.
		// Restore the opaque floor with the same linear blend inside that pass.
		if (opacity <= 0.00001) {
			discard;
		}
		vec3 floor_color = from_srgb(textureLod(opaque_color, SCREEN_UV, 0.0).rgb);
		DIFFUSE_LIGHT = mix(floor_color, from_srgb(shadow_tint.rgb), opacity);
#else
		ALPHA = opacity;
#endif
	}
}
