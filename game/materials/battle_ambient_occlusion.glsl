#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8) in;

layout(rgba8, set = 0, binding = 0) uniform writeonly image2D destination;
layout(set = 0, binding = 1) uniform sampler2D camera_depth;
layout(set = 0, binding = 2) uniform sampler2D camera_normals;
layout(set = 0, binding = 3) uniform sampler2D previous_pass;
layout(set = 0, binding = 4) uniform sampler2D blue_noise;

layout(push_constant, std430) uniform Settings {
	mat4 inverse_projection;
	vec4 projection_xy;
	vec4 projection_w;
	vec4 parameters; // Effective radius, intensity, eye-depth falloff, pass.
	vec4 noise; // Pixel offset, atlas row and row count.
} settings;

// The eight samples used by the PC profile's Medium quality variant.
const float sample_z[8] = float[8](0.00000000, 0.33984375, 0.75390625, 0.56640625,
		0.98437500, 0.07421875, 0.23828125, 0.64062500);
const float sample_angle[8] = float[8](0.92968750, 0.76171875, 0.13333330, 0.01562500,
		0.00000000, 0.10546875, 0.64062500, 0.74609375);

vec3 view_position(vec2 uv, float depth) {
	vec4 position = settings.inverse_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return position.xyz / position.w;
}

vec2 project_position(vec3 point) {
	vec2 xy = point.xy * settings.projection_xy.xy
			+ point.z * settings.projection_xy.zw + settings.projection_w.xy;
	float w = settings.projection_w.z * point.z + settings.projection_w.w;
	return clamp(0.5 + 0.5 * xy / w, vec2(0.0), vec2(1.0));
}

vec4 estimate_visibility(vec2 uv, ivec2 size) {
	float depth = textureLod(camera_depth, uv, 0.0).r;
	vec3 packed_normal = textureLod(camera_normals, uv, 0.0).rgb;
	if (depth < 0.00001) {
		return vec4(0.0, packed_normal);
	}
	vec3 center = view_position(uv, depth);
	if (-center.z >= settings.parameters.z) {
		return vec4(0.0, packed_normal);
	}
	vec3 normal = normalize(packed_normal * 2.0 - 1.0);
	float obscurance = 0.0;
	float radius = settings.parameters.x;
	for (int sample_index = 0; sample_index < 8; sample_index++) {
		float fraction = float(sample_index) / 8.0;
		vec2 noise_uv = fract((uv * vec2(size) + settings.noise.xy) / 256.0 + fraction);
		noise_uv.y = (noise_uv.y + settings.noise.z) / settings.noise.w;
		float random_value = textureLod(blue_noise, noise_uv, 0.0).r;
		float z = 2.0 * fract(sample_z[sample_index] + random_value) - 1.0;
		float angle = (sample_angle[sample_index] + random_value) * 628.3185307;
		vec3 direction = vec3(vec2(cos(angle), sin(angle)) * sqrt(max(0.0, 1.0 - z * z)), z);
		float side = dot(direction, normal) < 0.0 ? -1.0 : 1.0;
		vec3 sample_point = center + direction * (side * radius * mix(0.1, 1.0, fraction * fraction));
		vec2 sample_uv = project_position(sample_point);
		float sample_depth = textureLod(camera_depth, sample_uv, 0.0).r;
		if (sample_depth > 0.00001) {
			vec3 surface = view_position(sample_uv, sample_depth);
			if (abs(surface.z - sample_point.z) < radius) {
				vec3 offset = surface - center;
				obscurance += max(0.0, dot(offset, normal) + 0.004 * center.z)
						/ (dot(offset, offset) + 0.0001);
			}
		}
	}
	float falloff = 1.0 + center.z / settings.parameters.z;
	float amount = pow(clamp(obscurance * radius * settings.parameters.y * falloff * falloff / 8.0, 0.0, 1.0), 0.6);
	return vec4(amount, packed_normal);
}

float normal_weight(vec3 center, vec3 neighbor) {
	return smoothstep(0.8, 1.0, dot(center * 2.0 - 1.0, neighbor * 2.0 - 1.0));
}

vec4 bilateral_blur(vec2 uv, vec2 direction) {
	vec4 center = textureLod(previous_pass, uv, 0.0);
	float sum = center.r * 0.227027;
	float total_weight = 0.227027;
	for (int side = -1; side <= 1; side += 2) {
		vec4 near_sample = textureLod(previous_pass, uv + direction * (float(side) * 1.384615), 0.0);
		vec4 far_sample = textureLod(previous_pass, uv + direction * (float(side) * 3.230769), 0.0);
		float near_weight = 0.316216 * normal_weight(center.gba, near_sample.gba);
		float far_weight = 0.0702703 * normal_weight(center.gba, far_sample.gba);
		sum += near_sample.r * near_weight + far_sample.r * far_weight;
		total_weight += near_weight + far_weight;
	}
	return vec4(sum / total_weight, center.gba);
}

float finish_visibility(vec2 uv, vec2 pixel_size) {
	vec4 center = textureLod(previous_pass, uv, 0.0);
	float amount = center.r;
	float total_weight = 1.0;
	for (int x = -1; x <= 1; x += 2) {
		for (int y = -1; y <= 1; y += 2) {
			vec4 sample_value = textureLod(previous_pass, uv + vec2(x, y) * pixel_size, 0.0);
			float weight = normal_weight(center.gba, sample_value.gba);
			amount += sample_value.r * weight;
			total_weight += weight;
		}
	}
	return 1.0 - amount / total_weight;
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(destination);
	if (any(greaterThanEqual(pixel, size))) {
		return;
	}
	vec2 pixel_size = 1.0 / vec2(size);
	vec2 uv = (vec2(pixel) + 0.5) * pixel_size;
	int pass_index = int(settings.parameters.w);
	vec4 result;
	switch (pass_index) {
		case 0: result = estimate_visibility(uv, size); break;
		case 1: result = bilateral_blur(uv, vec2(pixel_size.x, 0.0)); break;
		case 2: result = bilateral_blur(uv, vec2(0.0, pixel_size.y)); break;
		default: result = vec4(vec3(finish_visibility(uv, pixel_size)), 1.0); break;
	}
	imageStore(destination, pixel, result);
}
