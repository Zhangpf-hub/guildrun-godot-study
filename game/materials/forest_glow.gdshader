shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_back, fog_disabled;

uniform int alignment = 0; // Local, view-facing, horizontal.
uniform bool additive = false;
uniform float intensity = 1.0;
uniform vec3 material_tint = vec3(1.0);
uniform bool double_opacity = false;
uniform float fade_distance = 0.0;
uniform float alpha_cutoff = 0.0;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D main_texture : repeat_enable, filter_linear_mipmap;
uniform sampler2D mask_texture : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform sampler2D dissolve_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D distortion_texture : repeat_enable, filter_linear_mipmap;
uniform vec4 main_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 mask_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 dissolve_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 distortion_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 dissolve_speed = vec2(0.0);
uniform float dissolve_amount = 0.0;
uniform float distortion_amount = 0.0;
uniform bool animated_ground = false;
instance uniform vec4 particle_tint : source_color = vec4(1.0);
instance uniform vec4 sprite_pose = vec4(0.0, 1.0, 0.0, 0.0); // Roll, atlas width and offset.

vec2 transform_uv(vec2 uv, vec4 transform) {
	return uv * transform.xy + transform.zw;
}

void vertex() {
	float width = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz);
	if (alignment == 1) {
		MODELVIEW_MATRIX[0] = vec4(width, 0.0, 0.0, 0.0);
		MODELVIEW_MATRIX[1] = vec4(0.0, height, 0.0, 0.0);
		MODELVIEW_MATRIX[2] = vec4(0.0, 0.0, 1.0, 0.0);
	} else if (alignment == 2) {
		MODELVIEW_MATRIX[0] = VIEW_MATRIX * vec4(width, 0.0, 0.0, 0.0);
		MODELVIEW_MATRIX[1] = VIEW_MATRIX * vec4(0.0, 0.0, -height, 0.0);
		MODELVIEW_MATRIX[2] = VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0);
	}
	float sine = sin(sprite_pose.x);
	float cosine = cos(sprite_pose.x);
	VERTEX.xy = mat2(vec2(cosine, sine), vec2(-sine, cosine)) * VERTEX.xy;
}

void fragment() {
	vec2 uv = vec2(UV.x * sprite_pose.y + sprite_pose.z, UV.y);
	vec2 sampled_uv = uv;
	float dissolve = 1.0;
	if (animated_ground) {
		// VFXTrail_SG's distortion scales the source UV from its lower-left corner.
		float warp = mix(1.0, texture(distortion_texture, transform_uv(uv, distortion_uv)).r, distortion_amount);
		sampled_uv = vec2(uv.x * warp, 1.0 - (1.0 - uv.y) * warp);
		float noise = texture(dissolve_texture, transform_uv(uv + TIME * dissolve_speed, dissolve_uv)).r;
		dissolve = noise - (abs(dissolve_amount) * 2.0 - 1.0);
	}
	// Both source materials are in the monochrome branch and take red for opacity.
	float opacity = texture(main_texture, transform_uv(sampled_uv, main_uv)).r
			* texture(mask_texture, transform_uv(uv, mask_uv)).r * particle_tint.a * dissolve;
	if (fade_distance > 0.0) {
		float depth = texture(scene_depth, SCREEN_UV).r;
		float ndc_depth = mix(CLIP_SPACE_FAR, 1.0, depth);
		vec4 view_position = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, ndc_depth, 1.0);
		float distance_to_scene = VERTEX.z - view_position.z / view_position.w;
		opacity *= clamp(distance_to_scene / fade_distance, 0.0, 1.0);
	}
	// VFXTrail_SG's _NonDistort branch adds a second copy of the same opacity.
	opacity = clamp(double_opacity ? 2.0 * opacity : opacity, 0.0, 1.0);
	if (opacity < alpha_cutoff) {
		discard;
	}
	ALBEDO = material_tint * particle_tint.rgb * intensity * opacity;
	ALPHA = additive ? 0.0 : opacity;
}
