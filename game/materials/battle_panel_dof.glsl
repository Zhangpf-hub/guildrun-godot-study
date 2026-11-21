#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D source_image;
layout(set = 0, binding = 1) uniform sampler2D camera_depth;
layout(rgba16f, set = 0, binding = 2) uniform image2D target_image;

layout(push_constant, std430) uniform DepthOfFieldParameters {
	vec4 focus; // Far start, reciprocal falloff distance and max radius.
	vec4 inverse_depth; // Z and W coefficients of the inverse render projection.
	vec4 frame; // Reciprocal full-resolution dimensions.
	ivec4 operation;
} params;

const int PREFILTER = 0;
const int BLUR_HORIZONTAL = 1;
const int BLUR_VERTICAL = 2;
const int COMPOSITE = 3;
const float TWO_PI = 6.28318530718;

float coc_at(ivec2 pixel) {
	float depth = texelFetch(camera_depth, pixel, 0).r;
	vec2 view = params.inverse_depth.xz * depth + params.inverse_depth.yw;
	float eye_depth = -view.x / view.y;
	return clamp((eye_depth - params.focus.x) * params.focus.y, 0.0, 1.0);
}

float sample_coc(vec2 uv) {
	// Bilinear filtering operates on the circles of confusion, after depth conversion.
	ivec2 size = textureSize(camera_depth, 0);
	vec2 position = clamp(uv * vec2(size) - 0.5, vec2(0.0), vec2(size - 1));
	vec2 weight = fract(position);
	ivec2 low = ivec2(position);
	ivec2 high = min(low + 1, size - 1);
	return mix(mix(coc_at(low), coc_at(ivec2(high.x, low.y)), weight.x),
			mix(coc_at(ivec2(low.x, high.y)), coc_at(high), weight.x), weight.y);
}

vec4 blur(ivec2 pixel, vec2 uv, bool horizontal) {
	const float offsets[3] = float[3](-1.33333333, 0.0, 1.33333333);
	const float weights[3] = float[3](0.35294118, 0.29411765, 0.35294118);
	float center_coc = texelFetch(source_image, pixel, 0).a;
	vec2 axis = horizontal ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec2 step_uv = axis * params.frame.xy * (2.0 * center_coc * params.focus.z);
	vec3 sum = vec3(0.0);
	float divisor = 0.0;
	for (int tap = 0; tap < 3; ++tap) {
		vec4 sample_color = textureLod(source_image, uv + offsets[tap] * step_uv, 0.0);
		float weight = weights[tap] * clamp(1.0 - center_coc + sample_color.a, 0.0, 1.0);
		sum += sample_color.rgb * weight;
		divisor += weight * (horizontal ? sample_color.a : 1.0);
	}
	// Preserve the unblurred CoC for the next pass. Only the horizontal pass removes premultiplication.
	return vec4(sum / (divisor + 0.0001), center_coc);
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(target_image);
	if (any(greaterThanEqual(pixel, size))) {
		return;
	}
	vec2 uv = (vec2(pixel) + 0.5) / vec2(size);
	if (params.operation.x == COMPOSITE) {
		float coc = coc_at(pixel);
		if (coc > 0.0) {
			vec4 original = imageLoad(target_image, pixel);
			vec3 soft = textureLod(source_image, uv, 0.0).rgb;
			original.rgb = mix(original.rgb, soft, min(sqrt(coc * TWO_PI), 1.0));
			imageStore(target_image, pixel, original);
		}
		return;
	}
	if (params.operation.x == PREFILTER) {
		float coc = sample_coc(uv);
		imageStore(target_image, pixel, vec4(textureLod(source_image, uv, 0.0).rgb * coc, coc));
		return;
	}
	imageStore(target_image, pixel, blur(pixel, uv, params.operation.x == BLUR_HORIZONTAL));
}
