shader_type canvas_item;
render_mode unshaded;

vec3 to_linear(vec3 srgb) {
	return mix(srgb / 12.92, pow((srgb + 0.055) / 1.055, vec3(2.4)), greaterThan(srgb, vec3(0.04045)));
}

void fragment() {
	// CanvasNoSaturation evaluates sprite luminance in linear light.
	float luminance = dot(to_linear(texture(TEXTURE, UV).rgb), vec3(0.212673, 0.715152, 0.072175));
	float gray = luminance > 0.0031308 ? 1.055 * pow(luminance, 1.0 / 2.4) - 0.055 : 12.92 * luminance;
	COLOR = vec4(vec3(gray), 1.0) * vec4(1.0, 1.0, 1.0, COLOR.a);
}
