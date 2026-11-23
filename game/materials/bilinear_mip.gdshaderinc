float bilinear_mip_level(sampler2D image, vec2 uv) {
	// Unity's bilinear sampler interpolates only within the selected mip.
	vec2 texel = uv * vec2(textureSize(image, 0));
	vec2 dx = dFdx(texel);
	vec2 dy = dFdy(texel);
	float footprint_squared = max(dot(dx, dx), dot(dy, dy));
	return floor(0.5 * log2(max(1.0, footprint_squared)) + 0.5);
}

vec4 sample_bilinear_mip(sampler2D image, vec2 uv) {
	return textureLod(image, uv, bilinear_mip_level(image, uv));
}
