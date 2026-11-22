shader_type spatial;
render_mode cull_back;

uniform sampler2D main_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D shadow_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_black;
uniform sampler2D emission_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D highlight_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D smoothness_texture : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 main_transform = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 emission_transform = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 tint : source_color = vec4(1.0);
// CharacterMaterialOverridesConfig MaterialOverrideDeathLilToon (sharedassets1:60896).
uniform vec4 death_tint : source_color = vec4(0.3764706, 0.3764706, 0.3764706, 0.0);
instance uniform float death_blend = 0.0;
uniform float cutoff = 0.0;
uniform bool use_shadow = true;
uniform bool use_shadow_texture = false;
uniform vec4 shadow_color : source_color = vec4(1.0);
uniform vec4 second_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 shadow_border_color : source_color = vec4(1.0, 0.1, 0.0, 1.0);
uniform vec4 shade_shape = vec4(0.69, 0.0, 0.11, 0.1);
uniform vec4 shade_controls = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec3 shade_receivers = vec3(0.0);
uniform vec2 light_limits = vec2(0.05, 1.0);
uniform bool use_emission = false;
uniform vec4 emission_color : source_color = vec4(0.0);
uniform vec4 emission_blink = vec4(0.0);
uniform vec3 emission_controls = vec3(1.0, 1.0, 0.0);
uniform bool use_highlight = false;
uniform bool highlight_additional_lights = false;
uniform vec4 highlight_color : source_color = vec4(1.0);
uniform vec3 highlight_shape = vec3(0.5, 0.5, 0.0);
uniform float shadow_environment = 0.0;
uniform vec4 probe_ar;
uniform vec4 probe_ag;
uniform vec4 probe_ab;
uniform vec4 probe_br;
uniform vec4 probe_bg;
uniform vec4 probe_bb;
uniform vec3 probe_c;

varying vec3 shadow_sample;
varying vec3 lit_albedo;
varying vec3 emission_screen_mask;
varying vec4 highlight_sample;
varying float highlight_roughness;

float band(float angle, float border, float blur, float feather) {
	float start = clamp(border - blur * 0.5 - feather, 0.0, 1.0);
	float end = clamp(border + blur * 0.5, 0.0, 1.0);
	float width = max(end - start + fwidth(angle) * shade_controls.w, 0.0001);
	return clamp((angle - start) / width, 0.0, 1.0);
}

vec3 srgb_to_linear(vec3 color) {
	return mix(color / 12.92, pow((max(color, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)),
			greaterThan(color, vec3(0.04045)));
}

vec3 linear_to_srgb(vec3 color) {
	return mix(12.92 * color, 1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055,
			greaterThan(color, vec3(0.0031308)));
}

vec3 inverse_light_probe(vec3 main_direction_world, vec3 main_color) {
	// Unity evaluates the authored ambient SH opposite the direct light.
	vec3 unity_direction = main_direction_world * vec3(1.0, 1.0, -1.0);
	vec3 average_probe = (probe_ar.xyz + probe_ag.xyz + probe_ab.xyz) / 3.0;
	float luminance = dot(main_color, vec3(0.2126, 0.7152, 0.0722));
	vec3 direction = unity_direction * luminance + average_probe;
	direction *= inversesqrt(max(dot(direction, direction), 0.000001)) * -0.666666;
	vec4 linear_terms = vec4(direction, 1.0);
	vec4 quadratic_terms = direction.xyzz * direction.yzzx;
	vec3 irradiance = vec3(dot(probe_ar, linear_terms), dot(probe_ag, linear_terms), dot(probe_ab, linear_terms));
	irradiance += vec3(dot(probe_br, quadratic_terms), dot(probe_bg, quadratic_terms), dot(probe_bb, quadratic_terms));
	irradiance += probe_c * (direction.x * direction.x - direction.y * direction.y);
	return clamp(irradiance, vec3(0.0), vec3(1.0));
}

void fragment() {
	vec2 uv = UV * main_transform.xy + main_transform.zw;
	vec4 texel = texture(main_texture, uv);
	// At constant hue and value, scaling HSV saturation is a mix toward value.
	float value = max(texel.r, max(texel.g, texel.b));
	vec3 main_rgb = mix(texel.rgb, vec3(value), 0.28 * death_blend);
	vec4 surface = vec4(main_rgb * mix(tint.rgb, death_tint.rgb, death_blend),
			texel.a * mix(tint.a, death_tint.a, death_blend));
	if (cutoff > 0.0) {
		// lilToonCutout discards zero coverage after filtering the clip edge.
		float half_edge = 0.5 * max(fwidth(surface.a), 0.0001);
		if (surface.a <= cutoff - half_edge) {
			discard;
		}
	}
	ALBEDO = surface.rgb;
	lit_albedo = OUTPUT_IS_SRGB ? srgb_to_linear(surface.rgb) : surface.rgb;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	vec4 shadow_layer = use_shadow_texture ? texture(shadow_texture, uv) : vec4(0.0);
	shadow_sample = mix(surface.rgb, shadow_layer.rgb, shadow_layer.a);
	if (use_highlight) {
		highlight_sample = highlight_color * texture(highlight_texture, uv);
		float roughness = 1.0 - highlight_shape.x * texture(smoothness_texture, uv).r;
		highlight_roughness = max(roughness * roughness, 0.000001);
	}
	emission_screen_mask = vec3(1.0);
	if (use_emission) {
		vec4 source = emission_color * texture(emission_texture, UV * emission_transform.xy + emission_transform.zw);
		float blink = sin(TIME * emission_blink.z + emission_blink.w) * 0.5 + 0.5;
		if (emission_blink.y > 0.5) {
			blink = round(blink);
		}
		float intensity = emission_controls.x * mix(1.0, blink, emission_blink.x) * source.a;
		EMISSION = mix(source.rgb, source.rgb * surface.rgb, emission_controls.z) * intensity;
		if (emission_controls.y == 2.0) {
			// Godot scales ambient and diffuse by the linear albedo. Compatibility decodes these outputs.
			vec3 linear_emission = OUTPUT_IS_SRGB ? srgb_to_linear(EMISSION) : EMISSION;
			emission_screen_mask = vec3(1.0) - clamp(linear_emission, vec3(0.0), vec3(1.0));
			vec3 masked_albedo = lit_albedo * emission_screen_mask;
			ALBEDO = OUTPUT_IS_SRGB ? linear_to_srgb(masked_albedo) : masked_albedo;
		}
	}
}

void light() {
	vec3 raw_color = LIGHT_COLOR / PI;
	vec3 color = clamp(raw_color, vec3(light_limits.x), vec3(light_limits.y));
	vec3 direct = lit_albedo * color;
	vec3 surface = direct;
	if (use_shadow) {
		float angle = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
		float first_angle = angle * mix(1.0, ATTENUATION, shade_receivers.x);
		float second_angle = angle * mix(1.0, ATTENUATION, shade_receivers.y);
		float first = mix(1.0, band(first_angle, shade_shape.x, shade_shape.y, 0.0), shade_controls.x);
		float second = (1.0 - band(second_angle, shade_shape.z, shade_shape.w, 0.0)) * second_color.a;
		float feather = band(first_angle, shade_shape.x, shade_shape.y, shade_controls.y);
		vec3 indirect = mix(shadow_sample * shadow_color.rgb, lit_albedo * second_color.rgb, second);
		indirect *= mix(vec3(1.0), lit_albedo, shade_controls.z);
		indirect *= color;
		if (shadow_environment > 0.0 && LIGHT_IS_DIRECTIONAL) {
			vec3 probe = inverse_light_probe(mat3(INV_VIEW_MATRIX) * LIGHT, raw_color);
			indirect = mix(indirect, lit_albedo, clamp(probe * shadow_environment, vec3(0.0), vec3(1.0)));
		}
		indirect = mix(min(indirect, direct), direct, feather * shadow_border_color.rgb);
		surface = mix(indirect, direct, first);
	}
	// Spatial diffuse input is multiplied by the surface albedo after this pass.
	vec3 relative = surface / max(lit_albedo, vec3(0.00001));
	float falloff = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	DIFFUSE_LIGHT += relative * falloff;
	if (use_highlight && (LIGHT_IS_DIRECTIONAL || highlight_additional_lights)) {
		vec3 halfway = normalize(LIGHT + VIEW);
		float profile = pow(clamp(dot(NORMAL, halfway), 0.0, 1.0), 1.0 / highlight_roughness);
		float highlight = band(profile, highlight_shape.y, highlight_shape.z, 0.0);
		SPECULAR_LIGHT += highlight_sample.rgb * highlight_sample.a * color * highlight * falloff * emission_screen_mask;
	}
}
