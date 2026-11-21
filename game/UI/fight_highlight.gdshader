shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec2 tex_scale = vec2(1.0);
uniform vec2 tex_offset = vec2(0.0);
uniform float intensity = 1.0;
uniform bool use_dissolve = false;
uniform sampler2D dissolve_tex : repeat_enable, filter_linear;
uniform vec2 dissolve_scale = vec2(1.0);
uniform vec2 dissolve_speed = vec2(0.0);
uniform float dissolve_amount = 0.5;
uniform float dissolve_softness = 0.8;
uniform float dissolve_power = 1.5;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 unity_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 main_uv = unity_uv * tex_scale + tex_offset;
	float coverage = texture(TEXTURE, vec2(fract(main_uv.x), clamp(1.0 - main_uv.y, 0.0, 1.0))).r;
	if (use_dissolve) {
		vec2 noise_uv = unity_uv * dissolve_scale + TIME * dissolve_speed;
		float noise = pow(texture(dissolve_tex, vec2(noise_uv.x, 1.0 - noise_uv.y)).r, dissolve_power);
		coverage *= smoothstep(dissolve_amount - dissolve_softness, dissolve_amount + dissolve_softness, noise);
	}
	COLOR = vec4(tint.rgb * intensity, tint.a * coverage);
}
