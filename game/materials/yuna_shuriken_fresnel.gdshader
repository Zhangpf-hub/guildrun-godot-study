shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec4 particle_tint : source_color = vec4(1.0);
uniform vec4 tint = vec4(1.0);
uniform float emission_strength = 1.0;
uniform float fresnel_scale = 1.0;
uniform float fresnel_power = 1.0;

void fragment() {
	float grazing = max(1.0 - dot(NORMAL, normalize(-VERTEX)), 0.0);
	float rim = clamp(pow(grazing, fresnel_power) * fresnel_scale, 0.0, 1.0);
	ALBEDO = particle_tint.rgb * tint.rgb * emission_strength;
	ALPHA = FRONT_FACING ? rim * particle_tint.a * tint.a : 0.0;
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
	// Calibrate the contribution to the battle HDR buffer against the PC flight frames.
	const float max_hdr_contribution = 3.5;
	float peak = max(ALBEDO.r, max(ALBEDO.g, ALBEDO.b)) * ALPHA;
	ALBEDO *= max_hdr_contribution / max(max_hdr_contribution, peak);
#endif
}
