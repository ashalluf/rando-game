shader_type spatial;
render_mode cull_back;

// The civic park's fountain pool and the shallow reflecting water round the landmarks: dark
// water that mirrors the sky (mostly emitted, like the glass, so it reads on the web too),
// wind ripples and the rings round each jet, and underwater lights after dark. UV is world
// (x, z) in metres.
//
// Shader files use // comments, never #.

#include "res://shaders/landmark_common.gdshaderinc"

uniform vec3 water_color : source_color = vec3(0.05, 0.08, 0.09);
uniform vec3 sky_zenith : source_color = vec3(0.30, 0.46, 0.76);
uniform vec3 sky_horizon : source_color = vec3(0.50, 0.54, 0.60);
uniform vec3 street_reflect : source_color = vec3(0.12, 0.12, 0.12);
uniform float ripple = 0.35;
// Rings spreading from jets every jet_spacing metres along x, at z jet_z (0 = none).
uniform float jet_spacing = 0.0;
uniform float jet_z = 0.0;
uniform vec3 light_color : source_color = vec3(0.55, 0.85, 1.0);
uniform float light_strength = 0.8;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = UV;
	float t = TIME;
	vec2 g = vec2(
		sin(p.x * 3.1 + t * 1.7) * 0.5 + sin(p.y * 4.3 - t * 1.3 + p.x * 0.7) * 0.5,
		cos(p.y * 3.7 + t * 1.5) * 0.5 + cos(p.x * 5.1 - t * 1.9 + p.y * 0.4) * 0.5) * ripple;
	if (jet_spacing > 0.0) {
		vec2 c = vec2((floor(p.x / jet_spacing) + 0.5) * jet_spacing, jet_z);
		vec2 d = p - c;
		float r = length(d);
		float ring = sin(r * 9.0 - t * 7.0) * exp(-r * 0.9);
		g += normalize(d + vec2(1e-4)) * ring * 0.6;
	}
	vec3 N = normalize(vec3(-g.x * 0.25, 1.0, -g.y * 0.25));
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 refl = reflect(-V, N);
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(V, N), 0.0, 1.0), 5.0);
	vec3 sky = lm_reflection(refl, sky_zenith, sky_horizon, street_reflect, 0.8);
	vec3 emission = sky * fres * 0.8 * lm_sky_now() * (1.0 - 0.7 * night_factor);
	emission += vec3(1.0, 0.96, 0.9) * lm_glint(refl, 500.0) * 4.0;
	emission += light_color * light_strength * lamp_factor * (0.4 + 0.3 * (g.x + g.y));
	NORMAL = (VIEW_MATRIX * vec4(N, 0.0)).xyz;
	ALBEDO = water_color;
	ROUGHNESS = 0.04;
	SPECULAR = 0.6;
	EMISSION = emission;
}
