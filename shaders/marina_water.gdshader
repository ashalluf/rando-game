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
global uniform vec3 sun_direction;
global uniform vec3 tree_sun;
global uniform vec4 skyline_sky_top;
global uniform vec4 skyline_sky_rim;

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/marina_mirror.gdshaderinc"
#include "res://shaders/marina_night.gdshaderinc"

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
// MarinaNight: the glow's share while the real lights are mirrored (its crazing read as brick
// paving), the chop's steepness for the lights' glints, and the lights' gain.
uniform float night_glow_keep = 0.2;
uniform float ml_wobble = 6.0;
uniform float ml_gain = 1.0;

varying vec3 v_local;
varying vec3 v_cam;

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
	// The camera in the mesh's space (true world: the chunk only translates it).
	v_cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_local.xz;
	float t = TIME;
	// Wind in patches drifting across the basin: glassy stretches between ruffled ones.
	float patch = mw_noise(p * 0.03 + vec2(t * 0.015, -t * 0.01));
	float wind = clamp(0.35 + 0.6 * wind_factor, 0.25, 2.0) * mix(0.25, 1.0, smoothstep(0.3, 0.75, patch));
	vec3 w = wavelets(p, t, chop_scale);
	if (mm_count > 0) {
		// MarinaGolden: a second set of wavelets turned 1.1 rad, cross-faded in patches, so the
		// chop never lines up into the long parallel bands five fixed directions draw at a grazing
		// angle (turning one set's frame with a noise drew rings instead).
		const mat2 TURN = mat2(vec2(0.4536, 0.8912), vec2(-0.8912, 0.4536));
		vec3 wb = wavelets(TURN * p + vec2(17.0, 9.0), t * 1.07, chop_scale * 0.83);
		wb.yz = transpose(TURN) * wb.yz;
		float mixk = smoothstep(0.25, 0.75, mw_noise(p * 0.035 + vec2(5.3, 1.9)));
		w = mix(w, wb, mixk);
	}
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
	// Mostly where the chop catches it: at 0.4 of it everywhere the whole basin drew as one flat
	// orange-brown sheet on Forward+ at night (its night exposure lifts it).
	vec3 glow = night_glow * lamp_factor * (0.08 + 0.92 * sparkle * sparkle);
	bool night_lights = (ml_count > 0 || mf_count > 0) && lamp_factor > 0.01;
	if (night_lights) {
		glow *= night_glow_keep;
	}
	vec3 emit = sky * fres * sky_emit + glow * fres;
	float boat_a = 0.0;
	if (mm_count > 0) {
		// The boats in the water (MarinaGolden): the reflected ray traced against the nearest
		// hulls, cabins and masts. Where one stands in it the renderer's own reflection (the sky,
		// SSR) is taken away - SPECULAR 0 zeroes Godot's f0 and with it the ambient and direct
		// specular - and the boat is emitted at the water's Fresnel.
		vec3 vi = normalize(v_local - v_cam);
		vec3 rr = reflect(vi, n_local);
		rr.y = max(rr.y, 0.004);
		rr = normalize(rr);
		float px = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * max(VIEWPORT_SIZE.y, 240.0));
		vec4 hit = mm_trace(v_local, rr, v_local.y, px, distance(v_local, v_cam));
		float fr = 0.02 + 0.98 * pow(1.0 - clamp(-vi.y, 0.0, 1.0), 5.0);
		fr = max(fr, fres);
		SPECULAR = 0.5 * (1.0 - hit.a);
		emit = emit * (1.0 - hit.a) + hit.rgb * fr;
		boat_a = hit.a;
	}
	if (night_lights) {
		// The lights in the water (MarinaNight): every lamp's column and the lit fronts across the
		// basin, behind whatever boat stands in the mirror.
		vec3 vi = normalize(v_local - v_cam);
		vec3 rf = vec3(vi.x, abs(vi.y), vi.z);
		vec3 rw = reflect(vi, normalize(vec3(-grad.x * ml_wobble, 1.0, -grad.y * ml_wobble)));
		rw.y = max(rw.y, 0.002);
		float px = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * max(VIEWPORT_SIZE.y, 240.0));
		float frn = max(0.02 + 0.98 * pow(1.0 - clamp(-vi.y, 0.0, 1.0), 5.0), 0.1);
		vec3 lights = mn_lights(v_local, rf, rw, px, distance(v_local, v_cam));
		emit += lights * frn * ml_gain * smoothstep(0.05, 0.5, lamp_factor) * (1.0 - boat_a);
	}
	EMISSION = cs_out(emit);
}
