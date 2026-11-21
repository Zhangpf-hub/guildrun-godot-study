shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, fog_disabled;

uniform sampler2D sweep_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D crystal_mask : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 sweep_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 mask_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 sweep_speed = vec2(0.0);
uniform vec3 tint = vec3(1.0);
uniform float intensity = 1.0;

void fragment() {
	vec2 moving_uv = (UV + TIME * sweep_speed) * sweep_uv.xy + sweep_uv.zw;
	float sweep = texture(sweep_texture, moving_uv).r;
	float mask = texture(crystal_mask, UV * mask_uv.xy + mask_uv.zw).r;
	ALBEDO = COLOR.rgb * tint * intensity;
	ALPHA = clamp(sweep * mask * COLOR.a, 0.0, 1.0);
}
