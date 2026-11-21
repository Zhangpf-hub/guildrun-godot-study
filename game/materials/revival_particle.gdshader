shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha, fog_disabled;

uniform sampler2D image_texture : filter_linear_mipmap, repeat_disable;
uniform sampler2D mask_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D flow_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 image_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 mask_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 noise_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 flow_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 noise_scroll = vec2(0.0);
uniform vec2 flow_scroll = vec2(0.0);
uniform vec2 image_scroll = vec2(0.0);
uniform float flow_strength = 0.0;
uniform bool flow_graph = false;
uniform bool image_is_srgb = false;
uniform bool use_rgb = false;
uniform bool additive = false;
uniform float intensity = 1.0;
uniform float fade_distance = 0.0;
uniform float dissolve_amount = 0.0;
uniform float dissolve_softness = 0.1;
uniform bool vertex_tint = false;
uniform vec4 particle_tint : source_color = vec4(1.0);
uniform float particle_age = 0.0;

vec3 linear_rgb(vec3 value) {
	return mix(value / 12.92, pow((value + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), value));
}

void fragment() {
	vec2 base_uv = UV * image_uv.xy + image_uv.zw;
	vec4 noise_color = vec4(1.0);
	if (flow_graph) {
		vec2 flow = texture(flow_texture, UV * flow_uv.xy + flow_uv.zw + TIME * flow_scroll).rg;
		vec2 mask_flow = texture(mask_texture, UV * mask_uv.xy + mask_uv.zw).rg;
		base_uv += TIME * image_scroll - flow_strength * flow * mask_flow;
		noise_color = texture(noise_texture, UV * noise_uv.xy + noise_uv.zw + TIME * noise_scroll);
	}
	vec4 sample_color = texture(image_texture, base_uv);
	if (image_is_srgb && !OUTPUT_IS_SRGB) {
		sample_color.rgb = linear_rgb(sample_color.rgb);
	}
	vec3 rgb = use_rgb ? sample_color.rgb * noise_color.rgb : vec3(1.0);
	float opacity = use_rgb ? sample_color.a * noise_color.a : sample_color.r;
	vec4 tint = vertex_tint ? COLOR : particle_tint;
	opacity *= tint.a;
	if (!flow_graph) {
		opacity *= texture(mask_texture, UV * mask_uv.xy + mask_uv.zw).r;
	}
	if (dissolve_amount > 0.0) {
		float noise = texture(noise_texture, (UV + particle_age * noise_scroll) * noise_uv.xy + noise_uv.zw).r;
		float threshold = dissolve_amount * particle_age;
		opacity *= smoothstep(threshold - dissolve_softness, threshold + dissolve_softness, noise);
	}
	if (fade_distance > 0.0) {
		float depth = texture(scene_depth, SCREEN_UV).r;
		vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, mix(CLIP_SPACE_FAR, 1.0, depth), 1.0);
		opacity *= clamp((VERTEX.z - scene.z / scene.w) / fade_distance, 0.0, 1.0);
	}
	opacity = clamp(opacity, 0.0, 1.0);
	ALBEDO = rgb * tint.rgb * opacity * intensity;
	ALPHA = additive ? 0.0 : opacity;
}
