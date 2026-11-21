shader_type canvas_item;
render_mode unshaded;

uniform vec4 primary : source_color;
uniform vec4 secondary : source_color;
uniform vec4 shield : source_color;
uniform vec4 background : source_color;
uniform vec4 separator : source_color;
uniform float health_fill = 1.0;
uniform float damage_fill = 1.0;
uniform float shield_fill = 1.0;
uniform float minor_divisions = 1.0;
uniform float major_divisions = 0.1;
uniform float minor_thickness = 1.0;
uniform float major_thickness = 2.0;
uniform float width = 119.0;

float separator_mask(float x, float divisions, float thickness) {
	float position = x * divisions;
	float boundary = floor(position + 0.5);
	float distance_px = abs(position - boundary) * width / max(divisions, 0.001);
	return step(1.0, boundary) * (1.0 - step(divisions, boundary)) *
			(1.0 - step(thickness * 0.5, distance_px));
}

void fragment() {
	vec4 fill = UV.x < shield_fill ? shield : background;
	if (UV.x < damage_fill) {
		fill = secondary;
	}
	if (UV.x < health_fill) {
		fill = primary;
	}
	if (shield_fill > health_fill && UV.x > health_fill && UV.x < shield_fill) {
		fill = shield;
	}
	float divider = max(separator_mask(UV.x, minor_divisions, minor_thickness),
			separator_mask(UV.x, major_divisions, major_thickness));
	COLOR = mix(fill, vec4(separator.rgb, fill.a), separator.a * divider);
}
