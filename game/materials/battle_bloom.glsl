#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D source_image;
layout(set = 0, binding = 1) uniform sampler2D lower_mip;
layout(rgba16f, set = 0, binding = 2) uniform image2D target_image;
layout(set = 0, binding = 3) uniform sampler2D grade_lookup;

layout(push_constant, std430) uniform BloomParameters {
	vec4 settings; // Scatter, clamp, linear threshold, soft knee.
	vec4 strength; // Luminance-normalized tint and additive intensity.
	ivec4 operation; // Pass index, high quality filtering, grade strip, LUT enabled.
	vec4 exposure; // Exposure multiplier (zero bypasses grading), Neutral, rounded vignette.
	vec4 vignette_shape; // Center, intensity, smoothness.
	vec4 vignette_color;
} params;

const int PREFILTER = 0;
const int BLUR_HORIZONTAL = 1;
const int BLUR_VERTICAL = 2;
const int UPSAMPLE = 3;
const int COMPOSITE = 4;

// The source ships the Unity 6 URP high-quality bloom filter. The near samples
// are centered halfway between texels. The threshold is applied after filtering.
vec3 prefilter(vec2 uv, vec2 pixel) {
	vec3 color = textureLod(source_image, uv, 0.0).rgb;
	if (params.operation.y != 0) {
		vec2 x = vec2(pixel.x, 0.0);
		vec2 y = vec2(0.0, pixel.y);
		color *= 0.125;
		color += (textureLod(source_image, uv + x, 0.0).rgb + textureLod(source_image, uv - x, 0.0).rgb
				+ textureLod(source_image, uv + y, 0.0).rgb + textureLod(source_image, uv - y, 0.0).rgb) * 0.0625;
		for (int sign_y = -1; sign_y <= 1; sign_y += 2) {
			for (int sign_x = -1; sign_x <= 1; sign_x += 2) {
				vec2 diagonal = vec2(sign_x, sign_y) * pixel;
				color += textureLod(source_image, uv + diagonal, 0.0).rgb * 0.03125;
				color += textureLod(source_image, uv + 0.5 * diagonal, 0.0).rgb * 0.125;
			}
		}
	}
	color = min(color, vec3(params.settings.y));
	float peak = max(max(color.r, color.g), color.b);
	float threshold = params.settings.z;
	float knee = params.settings.w;
	float shoulder = clamp(peak - threshold + knee, 0.0, 2.0 * knee);
	float contribution = max(peak - threshold, shoulder * shoulder / (4.0 * knee + 0.0001));
	return max(color * contribution / max(peak, 0.0001), vec3(0.0));
}

vec3 symmetric_taps(vec2 uv, vec2 offset) {
	return textureLod(source_image, uv - offset, 0.0).rgb + textureLod(source_image, uv + offset, 0.0).rgb;
}

vec3 blur(vec2 uv, vec2 pixel, int operation) {
	vec3 center = textureLod(source_image, uv, 0.0).rgb * 0.22702703;
	if (operation == BLUR_HORIZONTAL) {
		vec2 step_x = vec2(2.0 * pixel.x, 0.0);
		return center + symmetric_taps(uv, step_x) * 0.19459459
				+ symmetric_taps(uv, step_x * 2.0) * 0.12162162
				+ symmetric_taps(uv, step_x * 3.0) * 0.05405405
				+ symmetric_taps(uv, step_x * 4.0) * 0.01621622;
	}
	vec2 step_y = vec2(0.0, pixel.y);
	return center + symmetric_taps(uv, step_y * 1.38461538) * 0.31621622
			+ symmetric_taps(uv, step_y * 3.23076923) * 0.07027027;
}

vec3 reconstruct(sampler2D tex, vec2 uv) {
	if (params.operation.y == 0) {
		return textureLod(tex, uv, 0.0).rgb;
	}
	// Cubic B-spline reconstruction, paired into four hardware bilinear samples.
	vec2 size = vec2(textureSize(tex, 0));
	vec2 position = uv * size - 0.5;
	vec2 f = fract(position);
	vec2 g = 1.0 - f;
	vec2 first = g * g * g / 6.0;
	vec2 second = (4.0 + f * f * (3.0 * f - 6.0)) / 6.0;
	vec2 last = f * f * f / 6.0;
	vec2 left = first + second;
	vec2 right = 1.0 - left;
	vec2 base = floor(position) + 0.5;
	vec2 low = (base - 1.0 + second / left) / size;
	vec2 high = (base + 1.0 + last / right) / size;
	return textureLod(tex, low, 0.0).rgb * left.x * left.y
			+ textureLod(tex, vec2(high.x, low.y), 0.0).rgb * right.x * left.y
			+ textureLod(tex, vec2(low.x, high.y), 0.0).rgb * left.x * right.y
			+ textureLod(tex, high, 0.0).rgb * right.x * right.y;
}

vec3 neutral_curve(vec3 x) {
	return (x * (0.2 * x + 0.24 * 0.29) + 0.272 * 0.02)
			/ (x * (0.2 * x + 0.29) + 0.272 * 0.3) - 0.02 / 0.3;
}

vec3 prepare_ldr_grade(vec3 color, vec2 uv, float aspect) {
	// URP's UberPost applies these to scene-linear HDR, with bloom already included.
	if (params.vignette_shape.z > 0.0) {
		vec2 delta = (uv - params.vignette_shape.xy) * params.vignette_shape.z;
		delta.x *= params.exposure.z > 0.0 ? aspect : 1.0;
		float center_weight = pow(clamp(1.0 - dot(delta, delta), 0.0, 1.0), params.vignette_shape.w);
		color *= mix(params.vignette_color.rgb, vec3(1.0), center_weight);
	}
	color *= params.exposure.x;
	if (params.exposure.y > 0.0) {
		vec3 white_scale = 1.0 / neutral_curve(vec3(5.3));
		color = neutral_curve(max(color, vec3(0.0)) * white_scale) * white_scale;
	}
	return clamp(color, vec3(0.0), vec3(1.0));
}

vec3 apply_grade(vec3 color) {
	// Each strip contains the 32 blue slices of the 32^3 linear RGB LUT.
	vec3 grid = color * 31.0;
	vec2 uv = (vec2(grid.r + 32.0 * floor(grid.b), grid.g + 32.0 * float(params.operation.z)) + 0.5)
			/ vec2(1024.0, 128.0);
	vec3 first = textureLod(grade_lookup, uv, 0.0).rgb;
	vec3 next = textureLod(grade_lookup, uv + vec2(1.0 / 32.0, 0.0), 0.0).rgb;
	return mix(first, next, fract(grid.b));
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(target_image);
	if (any(greaterThanEqual(pixel, size))) {
		return;
	}
	vec2 uv = (vec2(pixel) + 0.5) / vec2(size);
	vec2 source_pixel = 1.0 / vec2(textureSize(source_image, 0));
	vec3 color;
	switch (params.operation.x) {
		case PREFILTER:
			color = prefilter(uv, source_pixel);
			break;
		case BLUR_HORIZONTAL:
		case BLUR_VERTICAL:
			color = blur(uv, source_pixel, params.operation.x);
			break;
		case UPSAMPLE:
			color = mix(textureLod(source_image, uv, 0.0).rgb, reconstruct(lower_mip, uv), params.settings.x);
			break;
		case COMPOSITE:
			vec4 scene = imageLoad(target_image, pixel);
			if (params.strength.a > 0.0) {
				scene.rgb += reconstruct(source_image, uv) * params.strength.rgb * params.strength.a;
			}
			if (params.exposure.x > 0.0) {
				scene.rgb = prepare_ldr_grade(scene.rgb, uv, float(size.x) / float(size.y));
				if (params.operation.w != 0) {
					scene.rgb = apply_grade(scene.rgb);
				}
			}
			imageStore(target_image, pixel, scene);
			return;
	}
	imageStore(target_image, pixel, vec4(color, 1.0));
}
