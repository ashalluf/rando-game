shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// The marina's water (MarinaBuild, Marina): the sea let in behind a breakwater and two jetties,
// so a sheltered version of it - no swell, no surf - and what a harbour basin looks like is mostly
// what it mirrors: the sky, the white hulls and the masts, the towers. Under that a green-grey,
// faintly turbid body (harbour water is never ocean blue), a small chop that comes and goes in
// wind patches, calm glassy lanes in the lee of the docks, the wakes of the boats running in the
// channel (none drawn: the wake is the chop's), and after dark the dock lamps' sodium streaks.
//
// Worked out in the mesh's LOCAL space, which for a chunk child is true world space (the chunk
// sits at -WorldState.world_offset): nothing jumps on an origin re-centre. No depth or screen
// texture: the sky is emitted from the `sky_tint` global by Fresnel (Compatibility has no
// screen-space reflections; on Forward+ SSR adds the boats and masts on top). Linear on both
// renderers (color_space.gdshaderinc).

global uniform vec4 sky_tint;
global uniform float night_factor;
global uniform float lamp_factor;
global uniform float wind_factor;
global uniform float ground_detail;
global uniform float rain_intensity;

#include "res://shaders/color_space.gdshaderinc"

// LINEAR: the body of the water, and a lighter, greener tone in the shallows along the walls.
uniform vec3 deep_color = vec3(0.012, 0.026, 0.028);
uniform vec3 turbid_color = vec3(0.024, 0.040, 0.034);
// Chop: normal strength and wavelength (m).
uniform float chop = 0.7;
uniform float chop_scale = 2.4;
// The sky's share at a grazing angle (the web's only reflection; a floor under SSR).
uniform float sky_emit = 0.30;
uniform float roughness_calm = 0.03;
uniform float roughness_chop = 0.10;
// Night: the city's sodium glow broken into streaks by the chop.
uniform vec3 night_glow = vec3(0.09, 0.05, 0.018);

varying vec3 v_local;

float mw_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float mw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mw_hash(i), mw_hash(i + vec2(1.0, 0.0)), f.x), mix(mw_hash(i + vec2(0.0, 1.0)), mw_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Travelling wavelets: height and gradient (x, z).
vec3 wavelets(vec2 p, float t, float scale) {
	vec3 acc = vec3(0.0);
	vec2 dirs[5] = vec2[](vec2(0.94, 0.34), vec2(-0.41, 0.91), vec2(0.72, -0.69), vec2(-0.99, -0.12), vec2(0.2, -0.98));
	float lens[5] = float[](1.0, 0.63, 0.41, 0.27, 0.17);
	for (int i = 0; i < 5; i++) {
		float k = 6.2831853 / (scale * lens[i]);
		float w = sqrt(9.81 * k) * 0.6;
		float ph = dot(dirs[i], p) * k - w * t + float(i) * 1.7;
		float a = lens[i];
		acc.x += a * sin(ph);
		acc.yz += a * k * cos(ph) * dirs[i];
	}
	return acc * 0.2;
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 p = v_local.xz;
	float t = TIME;
	// Wind in patches drifting across the basin: glassy stretches between ruffled ones.
	float patch = mw_noise(p * 0.03 + vec2(t * 0.015, -t * 0.01));
	float wind = clamp(0.35 + 0.6 * wind_factor, 0.25, 2.0) * mix(0.25, 1.0, smoothstep(0.3, 0.75, patch));
	vec3 w = wavelets(p, t, chop_scale);
	vec2 grad = w.yz * chop * wind * 0.07;
	if (ground_detail > 0.5) {
		vec3 w2 = wavelets(p * 3.1 + vec2(11.3, 5.9), t * 1.3, chop_scale);
		grad += w2.yz * chop * wind * 0.022;
	}
	// Rain: a fine roughening of the whole surface.
	float rain = clamp(rain_intensity, 0.0, 1.0);
	grad += (vec2(mw_noise(p * 7.0 + t * 3.0), mw_noise(p * 7.0 - t * 3.0)) - 0.5) * rain * 0.12;
	vec3 n_local = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_local, 0.0)).xyz);
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - nv, 5.0);
	// The body: turbid in drifting clouds of silt.
	float silt = mw_noise(p * 0.05 + vec2(-t * 0.004, t * 0.003));
	vec3 body = mix(deep_color, turbid_color, 0.35 + 0.5 * silt);
	ALBEDO = cs_out(body);
	ROUGHNESS = mix(roughness_calm, roughness_chop, clamp(wind * 0.7 + rain * 0.5, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.5;
	// sky_tint is sRGB numbers, raw on both renderers: decoded to the linear light this works in.
	vec3 sky = cs_srgb_to_linear(sky_tint.rgb) * (1.0 - 0.88 * night_factor);
	// At night the city's warm glow on the water, broken up by the chop (a faint floor: the lamps'
	// pools and, on Forward+, SSR carry the real reflections).
	float sparkle = clamp(length(grad) * 6.0, 0.0, 1.0);
	vec3 glow = night_glow * lamp_factor * (0.4 + 0.6 * sparkle);
	EMISSION = cs_out(sky * fres * sky_emit + glow * fres);
}
