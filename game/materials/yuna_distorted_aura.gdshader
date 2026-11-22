shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha, fog_disabled;

uniform sampler2D image_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D warp_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;

uniform vec4 texture_srgb = vec4(0.0);
uniform vec2 image_tiling = vec2(1.0);
uniform vec2 warp_tiling = vec2(1.0);
uniform vec2 noise_tiling = vec2(1.0);
uniform vec2 image_speed = vec2(0.0);
uniform vec2 warp_speed = vec2(0.0);
uniform vec2 noise_speed = vec2(0.0);
uniform float warp_amount = 0.0;
uniform float noise_exponent = 1.0;
uniform float soft_depth = 1.0;
uniform float intersection_depth = 0.0;
uniform vec4 aura_tint = vec4(1.0);
uniform vec4 intersection_tint = vec4(1.0);
uniform vec4 particle_tint : source_color = vec4(1.0);

vec2 flip_uv(vec2 uv) {
	return vec2(uv.x, 1.0 - uv.y);
}

vec4 decode_texel(vec4 texel, float srgb) {
	if (!OUTPUT_IS_SRGB && srgb > 0.0) {
		texel.rgb = mix(texel.rgb / 12.92, pow((texel.rgb + 0.055) / 1.055, vec3(2.4)),
			step(vec3(0.04045), texel.rgb));
	}
	return texel;
}

void fragment() {
	vec2 uv = flip_uv(UV);
	vec4 mask = decode_texel(texture(mask_texture, UV), texture_srgb.y);
	vec2 warp_uv = flip_uv(uv * warp_tiling + TIME * warp_speed);
	vec2 flow = decode_texel(texture(warp_texture, warp_uv), texture_srgb.z).rg;
	vec2 displaced = uv + flow * warp_amount;
	float main_alpha = texture(image_texture, flip_uv((displaced + TIME * image_speed) * image_tiling)).a;
	vec2 noise_uv = flip_uv((displaced + TIME * noise_speed) * noise_tiling);
	vec4 noise = decode_texel(texture(noise_texture, noise_uv), texture_srgb.w);

	float depth = texture(scene_depth, SCREEN_UV).r;
	vec4 reconstructed = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, mix(CLIP_SPACE_FAR, 1.0, depth), 1.0);
	float gap = VERTEX.z - reconstructed.z / reconstructed.w;
	float fade = clamp(gap * soft_depth, 0.0, 1.0);
	vec4 color = mask * pow(noise, vec4(noise_exponent)) * main_alpha * aura_tint * particle_tint * fade;
	float intersection = 1.0 - smoothstep(0.0, 1.0, gap + intersection_depth);
	color.rgb += particle_tint.rgb * intersection_tint.rgb * intersection;
	ALBEDO = color.rgb * clamp(color.a, 0.0, 1.0);
	ALPHA = 0.0;
}
