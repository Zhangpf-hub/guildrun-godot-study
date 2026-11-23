shader_type spatial;
render_mode cull_back, ambient_light_disabled;

uniform sampler2D diffuse_map : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D emissive_map : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D specular_map : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D shadow_map : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D galaxy_mask : source_color, filter_linear_mipmap, repeat_enable, hint_default_black;
uniform sampler2D toon_ramp : filter_nearest, repeat_disable, hint_default_white;
uniform samplerCube galaxy_map : source_color, filter_linear;
uniform samplerCube star_map : source_color, filter_linear;

uniform vec4 main_color : source_color = vec4(1.0);
uniform vec4 emissive_color : source_color = vec4(0.0);
uniform vec4 specular_color : source_color = vec4(0.0);
uniform vec4 ambient_color : source_color = vec4(0.0);
uniform vec4 shadow_color : source_color = vec4(0.0);
uniform vec4 galaxy_color : source_color = vec4(1.0);
uniform vec4 fresnel_color : source_color = vec4(0.0);
uniform vec4 star_color : source_color = vec4(1.0);
uniform vec3 galaxy_offset = vec3(0.0);
uniform vec3 star_offset = vec3(0.0);
uniform vec2 distortion_speed = vec2(0.0);
uniform vec2 fresnel_noise_speed = vec2(0.0);
uniform float shadow_amount = 0.5;
uniform float glossiness = 1.0;
uniform float desaturate = 0.0;
uniform float fresnel_exponent = 1.0;
uniform float fresnel_intensity = 1.0;
uniform float distortion_amount = 0.0;
uniform float distortion_scale = 1.0;
uniform float twirl_strength = 0.0;
uniform float fresnel_noise_scale = 1.0;
uniform float fresnel_noise_power = 1.0;
uniform bool use_emissive = false;
uniform bool use_gloss = false;

varying vec3 surface_color;
varying vec3 shadow_response;
varying float specular_mask;

// Hash and two Voronoi random channels from the demo's Universal Forward DXBC, shader 2999.
uint cell_hash(ivec2 cell) {
	uint y = uint(cell.y) ^ 0x41c64e6du;
	uint bits = y * (y + uint(cell.x));
	return (bits ^ (bits >> 5u)) * 0x27d4eb2du;
}

float cell_value(ivec2 cell) {
	return float(cell_hash(cell) >> 8u) * 0.00000005960465188;
}

float value_noise(vec2 position) {
	ivec2 cell = ivec2(floor(position));
	vec2 weight = fract(position);
	weight = weight * weight * (3.0 - 2.0 * weight);
	float bottom = mix(cell_value(cell), cell_value(cell + ivec2(1, 0)), weight.x);
	float top = mix(cell_value(cell + ivec2(0, 1)), cell_value(cell + ivec2(1, 1)), weight.x);
	return mix(bottom, top, weight.y);
}

float voronoi_distance(vec2 position) {
	ivec2 cell = ivec2(floor(position));
	vec2 origin = fract(position);
	float nearest = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 neighbor = ivec2(x, y);
			ivec2 point = cell + neighbor;
			uint hash_value = cell_hash(point);
			uint salt = uint(point.y) ^ 0x41c64e6du;
			vec2 seed = vec2(float((salt ^ (hash_value << 3u)) >> 8u), float(hash_value >> 8u));
			seed *= 0.0000002384186075;
			vec2 offset = vec2(sin(seed.x), cos(seed.y)) * 0.5 + 0.5;
			nearest = min(nearest, length(vec2(neighbor) + offset - origin));
		}
	}
	return nearest;
}

vec3 desaturated(vec3 color) {
	float luminance = dot(color, vec3(0.212673, 0.715152, 0.072175));
	return mix(color, vec3(luminance), desaturate);
}

void fragment() {
	vec2 unity_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 centered = unity_uv - vec2(0.5);
	vec2 twirled = unity_uv + vec2(centered.y, -centered.x) * dot(centered, centered) * twirl_strength;
	float distortion = voronoi_distance((twirled + distortion_speed * TIME) * distortion_scale);
	vec3 view_dir = normalize(VIEW);
	vec3 tangent_view = vec3(dot(TANGENT, view_dir), dot(BINORMAL, view_dir), dot(NORMAL, view_dir));
	vec3 cube_axes = vec3(-1.0, 1.0, -1.0);
	vec3 galaxy_dir = (2.0 * tangent_view + galaxy_offset + vec3(distortion * distortion_amount)) * cube_axes;
	vec3 space_color = textureLod(galaxy_map, galaxy_dir, 0.0).rgb * galaxy_color.rgb;
	space_color += textureLod(star_map, (tangent_view + star_offset) * cube_axes, 0.0).rgb * star_color.rgb;

	vec2 noise_uv = (unity_uv + fresnel_noise_speed * TIME) * fresnel_noise_scale;
	float noise_sum = 0.125 * value_noise(noise_uv) + 0.25 * value_noise(noise_uv * 0.5)
			+ 0.5 * value_noise(noise_uv * 0.25);
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), view_dir), 0.0, 1.0), fresnel_exponent);
	space_color += fresnel_color.rgb * rim * fresnel_intensity * pow(abs(noise_sum), fresnel_noise_power);
	surface_color = mix(texture(diffuse_map, UV).rgb * main_color.rgb, space_color, texture(galaxy_mask, UV).rgb);
	shadow_response = texture(shadow_map, UV).rgb * shadow_color.rgb;
	specular_mask = texture(specular_map, UV).r;
	vec3 emissive_sample = texture(emissive_map, UV).rgb;
	vec3 emission = surface_color * (ambient_color.rgb + shadow_response);
	if (use_emissive) {
		surface_color *= vec3(1.0) - emissive_sample * emissive_color.a;
		emission = surface_color * (ambient_color.rgb + shadow_response) + emissive_sample * emissive_color.rgb;
	}
	ALBEDO = vec3(1.0);
	EMISSION = desaturated(emission);
}

void light() {
	// The source applies a separate screen-space shadow pass. Use the scene's
	// directional shadow attenuation for the corresponding direct contribution.
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 direct = LIGHT_COLOR / PI;
		float angle = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
		float band = textureLod(toon_ramp, vec2(angle * direct.r - (2.0 * shadow_amount - 1.0), 1.0), 0.0).r;
		vec3 lit = band * direct * (vec3(1.0) - shadow_response);
		float highlight = specular_mask;
		if (use_gloss) {
			float halfway = clamp(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0, 1.0);
			float gloss = pow(halfway * band, max(glossiness * glossiness, 0.00001));
			highlight *= textureLod(toon_ramp, vec2(gloss, 0.0), 0.0).r;
		}
		DIFFUSE_LIGHT += desaturated(surface_color * (lit + specular_color.rgb * highlight)) * ATTENUATION;
	}
}
