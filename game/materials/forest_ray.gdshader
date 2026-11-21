shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, fog_disabled;

uniform sampler2D beam_texture : source_color, repeat_disable, filter_linear_mipmap;
uniform sampler2D beam_mask : repeat_disable, filter_linear_mipmap;
uniform sampler2D distortion_texture : repeat_enable, filter_linear_mipmap;
uniform vec4 beam_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 mask_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 distortion_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 distortion_speed = vec2(0.0);
uniform float distortion_amount = 0.0;
instance uniform vec4 beam_tint : source_color = vec4(1.0);

void fragment() {
	vec2 noise_uv = UV * distortion_uv.xy + distortion_uv.zw + TIME * distortion_speed;
	vec2 distortion = (texture(distortion_texture, noise_uv).rg * 2.0 - 1.0) * distortion_amount;
	float beam = texture(beam_texture, (UV + distortion) * beam_uv.xy + beam_uv.zw).a;
	float mask = texture(beam_mask, UV * mask_uv.xy + mask_uv.zw).a;
	ALBEDO = beam_tint.rgb;
	ALPHA = beam_tint.a * beam * mask;
}
