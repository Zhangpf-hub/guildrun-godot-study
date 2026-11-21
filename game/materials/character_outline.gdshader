shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;

uniform float thickness = 0.0004;

void vertex() {
	// Outline_SG scales the extrusion by pivot distance and removes model scale per axis.
	vec3 model_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	float pivot_distance = distance(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
	VERTEX += normalize(NORMAL) * thickness * pivot_distance / max(model_scale, vec3(0.0001));
}

void fragment() {
	ALBEDO = vec3(0.0);
	// Draw after the opaque character and environment without writing depth or casting a shadow.
	ALPHA = 1.0;
}
