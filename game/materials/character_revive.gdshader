shader_type spatial;
// Keep the revived surface in the depth buffer used by the outline.
render_mode cull_back;

uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 rim_tint : source_color = vec4(0.0);
uniform vec3 rim_profile = vec3(3.5, 0.5, 0.65);
uniform vec2 light_limits = vec2(0.05, 1.0);
uniform float antialias_strength = 1.0;

void fragment() {
	float fresnel = pow(clamp(1.0 - abs(dot(NORMAL, VIEW)), 0.0, 1.0), rim_profile.x);
	float low = clamp(rim_profile.y - rim_profile.z * 0.5, 0.0, 1.0);
	float high = clamp(rim_profile.y + rim_profile.z * 0.5, 0.0, 1.0);
	float width = clamp(high - low + fwidth(fresnel) * antialias_strength, 0.0001, 1.0);
	float rim = clamp((fresnel - low) / width, 0.0, 1.0);
	ALBEDO = tint.rgb + rim_tint.rgb * rim_tint.a * rim;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	vec3 color = clamp(LIGHT_COLOR / PI, vec3(light_limits.x), vec3(light_limits.y));
	DIFFUSE_LIGHT += color * (LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION);
}
