shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha, fog_disabled;

uniform sampler2D image_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;

uniform vec4 image_atlas = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 slash_data = vec4(0.0, 0.0, 0.0, 50.0);
uniform vec4 particle_tint : source_color = vec4(1.0);
uniform bool additive = false;
uniform bool depth_fade = true;
uniform float intensity = 1.0;

vec3 linear_rgb(vec3 rgb) {
	return mix(rgb / 12.92, pow((rgb + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), rgb));
}

vec3 atlas_sample(vec2 uv) {
	vec3 rgb = texture(image_texture, uv).rgb;
	// The linear renderers decode the source texels before filtering.
	return OUTPUT_IS_SRGB ? linear_rgb(rgb) : rgb;
}

void fragment() {
	vec2 uv = UV * image_atlas.xy + image_atlas.zw;
	float shift = atlas_sample(uv).b * slash_data.z;
	vec2 warped_uv = uv + vec2(shift, -shift);
	vec2 channels = atlas_sample(warped_uv).rg;
	float progress = slash_data.x;
	float gain = progress * slash_data.y;
	float mask = clamp((channels.g - progress + 1.0) * (1.0 + gain) / (1.0 + 0.1 * progress) - gain, 0.0, 1.0);
	float coverage = mask * channels.r;
	float opacity = coverage * mask * particle_tint.a;
	if (depth_fade) {
		float depth = texture(scene_depth, SCREEN_UV).r;
		vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, mix(CLIP_SPACE_FAR, 1.0, depth), 1.0);
		opacity *= clamp((VERTEX.z - scene.z / scene.w) * slash_data.w, 0.0, 1.0);
	}
	vec3 tint = particle_tint.rgb;
	if (additive && OUTPUT_IS_SRGB) {
		tint = linear_rgb(tint);
	}
	ALBEDO = coverage * tint * opacity * intensity;
	ALPHA = additive ? 0.0 : opacity;
}
