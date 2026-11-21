shader_type canvas_item;
uniform float fraction : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 from_center = UV - vec2(0.5);
	float clockwise_from_bottom = mod(atan(-from_center.x, from_center.y) / TAU + 1.0, 1.0);
	COLOR.a *= float(fraction > 0.0 && clockwise_from_bottom <= fraction);
}
