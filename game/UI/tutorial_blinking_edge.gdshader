shader_type canvas_item;
render_mode blend_premul_alpha;

// BlinkingRectEdge_Mat and Highlight_Mat_Tutorial (sharedassets3.assets:14/26).
uniform vec2 rect_size;
uniform bool rotating = false;
uniform bool blink = true;
varying vec2 rect_position;

void vertex() {
	// ColorRect can draw without a texture. Use its local geometry for the edge test.
	rect_position = VERTEX;
}

void fragment() {
	vec2 thickness = vec2(3.5, 3.4);
	vec2 opposing_edges = step(rect_position, thickness) + step(rect_size - rect_position, thickness);
	float pulse = blink ? 0.8 + 0.2 * sin(4.0 * TIME) : 1.0;
	if (rotating) {
		vec2 uv = rect_position / max(rect_size, vec2(1.0));
		vec2 centered = vec2(uv.x, 1.0 - uv.y) - 0.5;
		float angle = 2.0 * TIME;
		vec2 direction = vec2(cos(angle), sin(angle));
		vec2 point = vec2(dot(centered, direction), dot(centered, vec2(-direction.y, direction.x)));
		pulse = smoothstep(0.5, 0.55, fract(atan(point.x, point.y) * 0.318471));
	}
	float opacity = clamp(COLOR.a * (opposing_edges.x + opposing_edges.y) * pulse, 0.0, 1.0);
	COLOR = vec4(COLOR.rgb * opacity, opacity);
}
