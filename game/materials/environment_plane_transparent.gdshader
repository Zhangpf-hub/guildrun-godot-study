shader_type spatial;
render_mode unshaded, shadows_disabled, blend_mix, cull_back, depth_draw_never;

#include "res://materials/environment_plane.gdshaderinc"

void fragment() {
	vec4 texel = environment_texel(UV);
	ALBEDO = environment_rgb(texel.rgb, COLOR.rgb, OUTPUT_IS_SRGB);
	ALPHA = texel.a * COLOR.a;
}
