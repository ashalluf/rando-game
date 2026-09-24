shader_type spatial;
render_mode cull_back;

// The concert hall's sails: brushed stainless steel panels over curved forms. What makes the real
// building is how the steel catches the sky and the sun - a curved mirror, softened by the
// brushing, that throws a hot glint where it faces the sun and goes gold at sunset - and at night
// how it takes the floodlights at its foot.
//
// Metallic PBR does most of it on Forward+ (the sky radiance, SSR). As on the glass, part of the
// mirror is also EMITTED (landmark_common's lm_reflection), because a mirror in shade still shows
// the bright sky, and the Compatibility renderer's reflections are too weak to carry a whole
// building on their own. Panel seams come from the model's UV (metres, see tools/make_concert_hall.py):
// u runs round each sail, v up it.
//
// Shader files use // comments, never #.

#include "res://shaders/landmark_common.gdshaderinc"

uniform vec3 steel_color : source_color = vec3(0.78, 0.79, 0.80);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.24;
// Brushing: fine streaks along u, and how much they move the roughness.
uniform float brush_scale = 90.0;
uniform float brush_amount = 0.10;
// Panel seams (metres): the steel is hung as panels about 1.2 x 3 m.
uniform vec2 panel = vec2(1.25, 3.1);
uniform float seam_width = 0.022;
uniform float reflect_emit = 0.42;
uniform float reflect_energy = 1.1;
uniform vec3 sky_zenith : source_color = vec3(0.30, 0.46, 0.76);
uniform vec3 sky_horizon : source_color = vec3(0.50, 0.53, 0.58);
// What the sails mirror below the horizon: the pale stone plaza and street at their foot, not
// tarmac - at 0.16 every downward-leaning panel read as a dark smudge.
uniform vec3 street_reflect : source_color = vec3(0.34, 0.33, 0.31);
uniform float glint_strength = 5.0;
// Floodlights at the foot of the sails after dark: colour, strength, how high they reach (m).
uniform vec3 flood_color : source_color = vec3(1.0, 0.86, 0.66);
uniform float flood_strength = 0.9;
uniform float flood_base_y = 0.0;
uniform float flood_reach = 18.0;

varying vec3 wpos;
varying vec3 wnrm;

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(lm_hash21(vec2(i, 1.7)), lm_hash21(vec2(i + 1.0, 1.7)), f * f * (3.0 - 2.0 * f));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV;
	vec2 pid = floor(uv / panel);
	vec2 pf = fract(uv / panel);
	vec2 to_edge = min(pf, 1.0 - pf) * panel;
	float aa = max(fwidth(uv.x), fwidth(uv.y));
	float seam = 1.0 - smoothstep(seam_width, seam_width + aa, min(to_edge.x, to_edge.y));
	seam *= 1.0 - smoothstep(seam_width, seam_width * 4.0, aa);
	// Each panel is brushed a little differently and sits a hair off its neighbours.
	float ptone = lm_hash21(pid + 3.3);
	float streak = noise1(uv.y * brush_scale + ptone * 50.0) * 0.6 + noise1(uv.y * brush_scale * 3.1 + 7.0) * 0.4;
	float rough = clamp(roughness_base + (streak - 0.5) * brush_amount + (ptone - 0.5) * 0.06, 0.06, 0.6);
	vec3 col = steel_color * (0.94 + 0.08 * ptone) * COLOR.rgb;

	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 N = normalize(wnrm);
	vec3 bow = vec3(ptone - 0.5, lm_hash21(pid.yx) - 0.5, 0.0) * 0.05;
	vec3 refl = normalize(reflect(-V, N) + bow);
	float fres = 0.55 + 0.45 * pow(1.0 - clamp(dot(V, N), 0.0, 1.0), 3.0);
	vec3 sky = lm_reflection(refl, sky_zenith, sky_horizon, street_reflect, 0.6);
	vec3 emission = sky * col * fres * reflect_emit * reflect_energy * lm_sky_now() * (1.0 - 0.7 * night_factor);
	// The glint, spread by the brushing: tighter where the steel is smoother.
	float power = mix(60.0, 700.0, 1.0 - rough * 1.6);
	emission += vec3(1.0, 0.96, 0.88) * lm_glint(refl, power) * glint_strength * (1.0 - seam);
	// Floodlit after dark, brightest at the foot of each sail.
	float up = max(wpos.y - flood_base_y, 0.0);
	emission += col * flood_color * flood_strength * lamp_factor * (0.25 + 0.75 * exp(-up / flood_reach));
	col *= 1.0 - 0.55 * seam;
	ALBEDO = col;
	METALLIC = 1.0 - 0.4 * seam;
	ROUGHNESS = mix(rough, 0.6, seam);
	SPECULAR = 0.5;
	EMISSION = emission;
}
