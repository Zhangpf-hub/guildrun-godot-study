shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, fog_disabled;

uniform sampler2D opaque_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D opaque_depth : hint_depth_texture, repeat_disable, filter_nearest;

void fragment() {
	// HeroRender02 restores the visible layer-10 surface after ordinary transparency.
	// Reuse opaque lighting only where this surface supplied the scene depth.
	float depth = textureLod(opaque_depth, SCREEN_UV, 0.0).r;
	if (abs(depth - FRAGCOORD.z) > 0.0000002) {
		discard;
	}
	ALBEDO = textureLod(opaque_color, SCREEN_UV, 0.0).rgb;
	ALPHA = 1.0;
}
