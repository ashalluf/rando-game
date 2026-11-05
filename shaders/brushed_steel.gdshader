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
#include "res://shaders/color_space.gdshaderinc"

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
// rc5-wingsuit-golden (Rc5Wingsuit.steel_look()): 1 is the polished-stainless look - the mirror
// is the sky of THIS hour (sky_tint's horizon, brighter toward the sun, a cooler zenith, the dark
// street below the horizon) and carries the colour, the renderer's own reflection kept low (it
// mirrors one flat radiance on Compatibility: every sail one beige), each panel a different tone,
// the sun's glint capped and tinted so it never blows a sail out, and a broad lobe that lights the
// sails turned to the low sun and leaves the others in shade (through the evening haze that
// contrast is what reads as metal). Faded in as the sun sinks under ~29 degrees: with it high,
// and with 0, exactly as before.
uniform float look = 0.0;

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
	if (look > 0.5) {
		vec3 sd = normalize(sun_direction);
		// The horizon of this hour (sky_tint: sRGB numbers, the renderer's own space here).
		vec3 h_now = cs_as_uniform(sky_tint.rgb);
		vec2 rh = normalize(refl.xz + vec2(1e-4));
		vec2 sh = normalize(sd.xz + vec2(1e-4));
		float toward = max(dot(rh, sh), 0.0);
		vec3 horizon = h_now * (0.75 + 1.2 * toward * toward * toward);
		vec3 zenith = mix(h_now, sky_zenith * lm_sky_now(), 0.6) * vec3(0.62, 0.70, 0.95);
		vec3 below = street_reflect * 0.45 * lm_sky_now() + h_now * 0.05;
		vec3 mirror = refl.y >= 0.0 ? mix(horizon, zenith, smoothstep(0.0, 0.6, refl.y))
			: mix(horizon * 0.6, below, smoothstep(0.0, 0.12, -refl.y));
		float pan = 0.88 + 0.24 * ptone;
		// Brushed steel under a low sun: a broad lobe across the brushing lights a whole sail
		// that turns to the sun and leaves the ones turned away in their own shade. Through the
		// evening haze at a few hundred metres that face-to-face contrast is what reads as metal.
		vec2 nh = normalize(N.xz + vec2(1e-4));
		float face = max(dot(nh, sh), 0.0);
		float low = (1.0 - smoothstep(0.18, 0.5, sd.y)) * smoothstep(-0.08, 0.0, sd.y);
		float shade = 0.25 + 0.75 * face;
		vec3 e2 = mirror * steel_color * fres * pan * 1.35 * shade * (1.0 - 0.7 * night_factor);
		vec3 warm = normalize(h_now + vec3(0.06)) * 1.7;
		e2 += warm * steel_color * pan * pow(face, 2.0) * 1.1 * (1.0 - 0.6 * seam);
		float g = lm_glint(refl, power);
		e2 += normalize(h_now + vec3(0.08)) * min(g * 2.2, 1.6) * (1.0 - seam);
		e2 += col * flood_color * flood_strength * lamp_factor * (0.25 + 0.75 * exp(-up / flood_reach));
		e2 *= 1.0 - 0.6 * seam;
		// All of it only while the sun is low: with it high, the steel exactly as before.
		emission = mix(emission, e2, low);
		// The renderer's own metal reflection a fraction of what it was.
		col *= mix(1.0, 0.45 * (0.4 + 0.6 * face), low);
	}
	col *= 1.0 - 0.55 * seam;
	ALBEDO = col;
	METALLIC = 1.0 - 0.4 * seam;
	ROUGHNESS = mix(rough, 0.6, seam);
	SPECULAR = 0.5;
	EMISSION = emission;
}
