shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha, fog_disabled;

uniform sampler2D image_texture : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D repeating_image_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D dissolve_mask_texture : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D flow_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 image_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 image_atlas = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 mask_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 noise_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 dissolve_mask_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 flow_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 noise_scroll = vec2(0.0);
uniform vec2 flow_scroll = vec2(0.0);
uniform vec2 image_scroll = vec2(0.0);
uniform bool scroll_atlas = false;
uniform vec2 atlas_scroll = vec2(0.0);
uniform float atlas_time = 0.0;
uniform float flow_strength = 0.0;
uniform bool flow_graph = false;
uniform bool image_is_srgb = false;
uniform bool use_rgb = false;
uniform bool additive = false;
uniform float intensity = 1.0;
uniform float fade_distance = 0.0;
uniform float raw_depth_fade = 0.0;
uniform bool custom_dissolve = false;
uniform float custom_dissolve_softness = 0.0;
uniform bool dissolve_is_srgb = false;
uniform bool dissolve_mask_is_srgb = false;
uniform bool mask_is_srgb = false;
uniform bool atlas_mask_uv = false;
uniform float dissolve_mix = 0.0;
uniform vec3 dissolve_data = vec3(0.0);
uniform float dissolve_amount = 0.0;
uniform float dissolve_softness = 0.1;
uniform bool vertex_tint = false;
uniform bool linearize_vertex_tint = false;
uniform bool on_hit_vfx_redraw = false;
uniform bool compensate_dark_blend = false;
uniform vec4 particle_tint : source_color = vec4(1.0);
uniform vec4 material_tint = vec4(1.0);
uniform float particle_age = 0.0;

vec3 linear_rgb(vec3 value) {
	return mix(value / 12.92, pow((value + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), value));
}


void vertex() {
	if (on_hit_vfx_redraw) {
		// PC_Renderer onHitVFX keeps the view rotation and adds 3 to its view-space Z translation.
		MODELVIEW_MATRIX[3].z += 3.0;
		float focal_length = 1.0 / tan(radians(8.5));
		PROJECTION_MATRIX[0][0] = sign(PROJECTION_MATRIX[0][0]) * focal_length * VIEWPORT_SIZE.y / VIEWPORT_SIZE.x;
		PROJECTION_MATRIX[1][1] = sign(PROJECTION_MATRIX[1][1]) * focal_length;
		PROJECTION_MATRIX[2].xy = vec2(0.0);
	}
	if (linearize_vertex_tint && !OUTPUT_IS_SRGB) {
		// Unity converts the packed vertex color before interpolating along the ribbon.
		COLOR.rgb = round(linear_rgb(COLOR.rgb) * 255.0) / 255.0;
	}
}

void fragment() {
	vec2 atlas_uv = UV * image_atlas.xy + image_atlas.zw;
	vec2 base_uv = atlas_uv * image_uv.xy + image_uv.zw;
	vec4 noise_color = vec4(1.0);
	if (flow_graph) {
		vec2 flow = texture(flow_texture, UV * flow_uv.xy + flow_uv.zw + TIME * flow_scroll).rg;
		vec2 mask_flow = texture(mask_texture, UV * mask_uv.xy + mask_uv.zw).rg;
		base_uv += TIME * image_scroll - flow_strength * flow * mask_flow;
		noise_color = texture(noise_texture, UV * noise_uv.xy + noise_uv.zw + TIME * noise_scroll);
	}
	vec4 sample_color = scroll_atlas ? texture(repeating_image_texture, base_uv + atlas_scroll * atlas_time)
		: texture(image_texture, base_uv);
	if (image_is_srgb && !OUTPUT_IS_SRGB) {
		sample_color.rgb = linear_rgb(sample_color.rgb);
	}
	vec3 rgb = use_rgb ? sample_color.rgb * noise_color.rgb : vec3(1.0);
	float opacity = use_rgb ? sample_color.a * noise_color.a : sample_color.r;
	vec4 tint = (vertex_tint ? COLOR : particle_tint) * material_tint;
	opacity *= tint.a;
	vec2 mask_base_uv = atlas_mask_uv ? atlas_uv : UV;
	if (!flow_graph) {
		float mask = texture(mask_texture, mask_base_uv * mask_uv.xy + mask_uv.zw).r;
		if (mask_is_srgb && !OUTPUT_IS_SRGB) {
			mask = linear_rgb(vec3(mask)).r;
		}
		opacity *= mask;
	}
	if (custom_dissolve) {
		vec2 dissolve_uv = (mask_base_uv + dissolve_data.yz) * noise_uv.xy + noise_uv.zw;
		float noise = texture(noise_texture, dissolve_uv).r;
		if (dissolve_is_srgb && !OUTPUT_IS_SRGB) {
			noise = linear_rgb(vec3(noise)).r;
		}
		if (dissolve_mix > 0.0) {
			float secondary = texture(dissolve_mask_texture, mask_base_uv * dissolve_mask_uv.xy + dissolve_mask_uv.zw).r;
			if (dissolve_mask_is_srgb && !OUTPUT_IS_SRGB) {
				secondary = linear_rgb(vec3(secondary)).r;
			}
			noise *= mix(1.0, secondary, dissolve_mix);
		}
		float threshold = 1.0 - dissolve_data.x;
		float softness = custom_dissolve_softness;
		opacity *= softness > 0.0 ? smoothstep(threshold - softness, threshold + softness, noise) : float(noise > threshold);
	} else if (dissolve_amount > 0.0) {
		float noise = texture(noise_texture, (UV + particle_age * noise_scroll) * noise_uv.xy + noise_uv.zw).r;
		float threshold = dissolve_amount * particle_age;
		opacity *= smoothstep(threshold - dissolve_softness, threshold + dissolve_softness, noise);
	}
	if (raw_depth_fade > 0.0) {
		float depth = texture(scene_depth, SCREEN_UV).r;
		opacity *= clamp((FRAGCOORD.z - depth) * raw_depth_fade, 0.0, 1.0);
	} else if (fade_distance > 0.0) {
		float depth = texture(scene_depth, SCREEN_UV).r;
		vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, mix(CLIP_SPACE_FAR, 1.0, depth), 1.0);
		opacity *= clamp((VERTEX.z - scene.z / scene.w) / fade_distance, 0.0, 1.0);
	}
	opacity = clamp(opacity, 0.0, 1.0);
	if (compensate_dark_blend && OUTPUT_IS_SRGB) {
		// Approximate linear transmission through near-black particles on the Compatibility target.
		opacity = 1.0 - pow(1.0 - opacity, 1.0 / 2.2);
	}
	ALBEDO = rgb * tint.rgb * opacity * intensity;
	ALPHA = additive ? 0.0 : opacity;
}
