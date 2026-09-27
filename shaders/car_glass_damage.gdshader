shader_type spatial;
render_mode cull_disabled;

// The glass slot of a damaged car (CarDamage swaps it in the first time a window is hit; an
// undamaged car keeps the model's own plain glass material). Opaque, like every car window in
// this game, so a window that is gone is not a hole: it is drawn as the cabin seen through the
// empty frame - traced in the body's own space, so it has true parallax - with the far windows
// letting the day in above the door line, the seat backs and headrests cutting across them.
//
// The panes are the glass surface's connected pieces (CarDamage measures them once per model):
// an AABB and a mean normal each, smallest first, so a fragment finds its pane in a few tests.
// Side and rear glass is tempered - it crazes into small cubes on the first round and falls out
// on the next - and the windscreen is laminated, so it only collects spider webs.

#include "res://shaders/car_damage.gdshaderinc"

global uniform vec4 sky_tint;
global uniform float night_factor;

// The model's own glass material.
uniform vec3 glass_albedo : source_color = vec3(0.14, 0.155, 0.175);
uniform float glass_roughness = 0.05;
uniform float glass_metallic = 0.0;
// Panes: pane_lo xyz / pane_hi xyz the box, pane_lo.w the state (0 whole, 1 crazed, 2 gone),
// pane_hi.w the kind (0 tempered, 1 laminated windscreen, 2 a lamp cover), pane_n the mean normal.
uniform int pane_count = 0;
uniform vec4 pane_lo[16];
uniform vec4 pane_hi[16];
uniform vec4 pane_n[16];
// Spider webs: xyz the hit, w the web's radius; crack_n xyz the glass normal there, w a seed.
uniform int crack_count = 0;
uniform vec4 cracks[12];
uniform vec4 crack_n[12];
// The cabin behind the glass, in mesh space: the box, the door line (bottom of the side glass)
// and where the two rows of seat backs stand along the car (z).
uniform vec3 cabin_lo = vec3(-0.75, 0.4, -1.0);
uniform vec3 cabin_hi = vec3(0.75, 1.4, 1.2);
uniform float belt_y = 0.95;
uniform vec2 seat_z = vec2(0.0, 1.0);
// 0 .. 1: every pane gone and the cabin burnt out.
uniform float burnt = 0.0;
// How bright the cabin behind an empty frame is, against the sky it is lit by (emitted, like the
// buildings' glass mirror, so it follows DayNight's sky_tint into the night).
uniform float cabin_light = 4.0;

varying vec3 lp;
varying vec3 ln;
varying vec3 cam_local;


void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	cam_local = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
}


int find_pane(vec3 p, vec3 n) {
	for (int i = 0; i < pane_count && i < 16; i++) {
		vec3 lo = pane_lo[i].xyz - vec3(0.012);
		vec3 hi = pane_hi[i].xyz + vec3(0.012);
		if (all(greaterThanEqual(p, lo)) && all(lessThanEqual(p, hi)) && abs(dot(n, pane_n[i].xyz)) > 0.3) {
			return i;
		}
	}
	return -1;
}


// A box hit by a ray (`inv_d` = 1 / direction): the distance in, or -1, and the face's normal.
float box_hit(vec3 o, vec3 inv_d, vec3 lo, vec3 hi, out vec3 nrm) {
	vec3 t1 = (lo - o) * inv_d;
	vec3 t2 = (hi - o) * inv_d;
	vec3 tn = min(t1, t2);
	vec3 tf = max(t1, t2);
	float t_near = max(max(tn.x, tn.y), tn.z);
	float t_far = min(min(tf.x, tf.y), tf.z);
	nrm = vec3(0.0, 1.0, 0.0);
	if (t_near > t_far || t_far < 0.0) {
		return -1.0;
	}
	if (tn.x >= tn.y && tn.x >= tn.z) {
		nrm = vec3(-sign(inv_d.x), 0.0, 0.0);
	} else if (tn.y >= tn.z) {
		nrm = vec3(0.0, -sign(inv_d.y), 0.0);
	} else {
		nrm = vec3(0.0, 0.0, -sign(inv_d.z));
	}
	return max(t_near, 0.0);
}


// Keeps the nearest of the cabin's furniture boxes.
void furniture(vec3 o, vec3 inv_d, vec3 lo, vec3 hi, float shade, inout float best, inout vec3 best_n, inout float best_shade) {
	vec3 n;
	float t = box_hit(o, inv_d, min(lo, hi), max(lo, hi), n);
	if (t >= 0.0 && t < best) {
		best = t;
		best_n = n;
		best_shade = shade;
	}
}


// What a ray from `o` along `d` sees in the cabin: the dash, two front seats and the rear bench
// with their headrests, the headliner, the door cards and floor, and - out through the glass on
// the far side - the day (dimmed where that pane is still in).
vec3 cabin_view(vec3 o, vec3 d) {
	vec3 safe = vec3(abs(d.x) < 1e-4 ? 1e-4 : d.x, abs(d.y) < 1e-4 ? 1e-4 : d.y, abs(d.z) < 1e-4 ? 1e-4 : d.z);
	vec3 inv = 1.0 / safe;
	vec3 t1 = (cabin_lo - o) * inv;
	vec3 t2 = (cabin_hi - o) * inv;
	vec3 tf = max(t1, t2);
	float t_exit = max(min(min(tf.x, tf.y), tf.z), 0.0);
	vec3 sky = sky_tint.rgb;
	float char_ = burnt;
	float cx = (cabin_hi.x + cabin_lo.x) * 0.5;
	float half_w = (cabin_hi.x - cabin_lo.x) * 0.5;
	// The rear of the car is +z when the seat rows run that way.
	float back = seat_z.y > seat_z.x ? 1.0 : -1.0;
	float fy = cabin_lo.y;
	float front_end = back > 0.0 ? cabin_lo.z : cabin_hi.z;
	float best = t_exit;
	vec3 best_n = vec3(0.0);
	float best_shade = -1.0;
	for (int s = -1; s <= 1; s += 2) {
		float fs = float(s);
		float xa = cx + fs * 0.1;
		float xb = cx + fs * (half_w - 0.07);
		float mid = (xa + xb) * 0.5;
		// Front seat: backrest, cushion, headrest.
		furniture(o, inv, vec3(xa, fy, seat_z.x), vec3(xb, belt_y + 0.1, seat_z.x + back * 0.13), 0.9, best, best_n, best_shade);
		furniture(o, inv, vec3(xa, fy, seat_z.x), vec3(xb, belt_y - 0.42, seat_z.x - back * 0.5), 0.8, best, best_n, best_shade);
		if (char_ < 0.5) {
			furniture(o, inv, vec3(mid - 0.12, belt_y + 0.14, seat_z.x + back * 0.03), vec3(mid + 0.12, belt_y + 0.32, seat_z.x + back * 0.12), 1.0, best, best_n, best_shade);
			furniture(o, inv, vec3(mid - 0.12, belt_y + 0.1, seat_z.y + back * 0.03), vec3(mid + 0.12, belt_y + 0.27, seat_z.y + back * 0.12), 1.0, best, best_n, best_shade);
		}
	}
	// Rear bench and the dash.
	furniture(o, inv, vec3(cabin_lo.x + 0.03, fy, seat_z.y), vec3(cabin_hi.x - 0.03, belt_y + 0.06, seat_z.y + back * 0.14), 0.85, best, best_n, best_shade);
	furniture(o, inv, vec3(cabin_lo.x + 0.03, fy, seat_z.y), vec3(cabin_hi.x - 0.03, belt_y - 0.44, seat_z.y - back * 0.5), 0.75, best, best_n, best_shade);
	furniture(o, inv, vec3(cabin_lo.x, fy, front_end), vec3(cabin_hi.x, belt_y + 0.05, front_end + back * 0.42), 0.6, best, best_n, best_shade);
	// Light in a cabin comes in through the windows: the tops of things catch it, the sides
	// facing the open frame a little, everything else sits in the dark.
	if (best_shade >= 0.0) {
		vec3 h = o + d * best;
		vec3 fabric = mix(vec3(0.13, 0.125, 0.12), vec3(0.016, 0.014, 0.012), char_);
		fabric *= 0.8 + 0.4 * cd_noise3(h * 40.0);
		float lit = 0.2 + 0.55 * max(best_n.y, 0.0) + 0.3 * max(dot(best_n, -d), 0.0);
		return fabric * sky * lit * best_shade;
	}
	vec3 e = o + d * t_exit;
	int axis = (tf.x < tf.y && tf.x < tf.z) ? 0 : (tf.y < tf.z ? 1 : 2);
	if (axis != 1 && e.y > belt_y + 0.01) {
		// Out through the far glass (or the screens, front and back).
		int far_i = find_pane(e, axis == 0 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0));
		float open = 1.0;
		if (far_i >= 0 && pane_lo[far_i].w < 1.5) {
			open = 0.3;
		}
		if (far_i < 0 && pane_count > 0 && char_ < 0.5) {
			// Between the far panes: a pillar.
			return vec3(0.03, 0.029, 0.028) * sky * 0.6;
		}
		open = max(open, char_);
		float lift = smoothstep(belt_y, cabin_hi.y, e.y);
		return sky * open * (0.45 + 0.3 * lift);
	}
	if (axis == 1 && d.y > 0.0) {
		// The headliner, or the bare roof skin once it has burnt away.
		vec3 roof = mix(vec3(0.34, 0.33, 0.31), vec3(0.03, 0.025, 0.02), char_);
		return roof * sky * 0.14;
	}
	// Door cards and the floor.
	float low = smoothstep(cabin_lo.y, belt_y, e.y);
	vec3 trim = mix(vec3(0.08, 0.077, 0.074), vec3(0.01, 0.009, 0.008), char_);
	return trim * sky * (0.3 + 0.7 * low);
}


void fragment() {
	vec3 n = normalize(ln);
	int pi = find_pane(lp, n);
	float state = 0.0;
	float kind = 0.0;
	if (pi >= 0) {
		state = pane_lo[pi].w;
		kind = pane_hi[pi].w;
	}
	if (burnt > 0.5) {
		state = 2.0;
	}
	float px = max(length(fwidth(lp)), 1e-5);
	vec3 alb = glass_albedo;
	float rough = glass_roughness;
	float metal = glass_metallic;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	vec3 tilt = vec3(0.0);
	// The model's glass has no clearcoat of its own.
	float cc = 0.0;

	if (state > 1.5 && pi >= 0) {
		// Gone. Tempered glass leaves a ragged row of cubes along the bottom seal of the frame.
		float remnant = 0.0;
		if (kind < 0.5) {
			float rim = pane_lo[pi].y + 0.012 + 0.03 * cd_noise3(lp * 55.0);
			remnant = 1.0 - smoothstep(rim - px, rim + px, lp.y);
		}
		if (kind > 1.5) {
			// A lamp cover: the dark, broken reflector behind it.
			alb = vec3(0.06, 0.06, 0.065);
			rough = 0.45;
			metal = 0.5;
			cc = 0.0;
		} else if (remnant > 0.5) {
			vec2 tl;
			vec3 t;
			vec3 b;
			cd_frame(n, t, b);
			float lines = cd_craze(vec2(dot(lp, t), dot(lp, b)), 0.011, px, tl);
			alb = mix(glass_albedo * 1.6 + 0.12, vec3(0.8), lines);
			rough = 0.2;
			tilt = (t * tl.x + b * tl.y) * 0.6;
		} else {
			vec3 rd = normalize(lp - cam_local);
			emit = cabin_view(lp, rd) * cabin_light;
			alb = vec3(0.0);
			rough = 1.0;
			metal = 0.0;
			spec = 0.0;
			cc = 0.0;
		}
	} else {
		float lines = 0.0;
		if (state > 0.5) {
			// Crazed tempered glass: a frosted sheet of small cubes each catching the light
			// its own way.
			vec2 tl;
			vec3 t;
			vec3 b;
			cd_frame(n, t, b);
			lines = cd_craze(vec2(dot(lp, t), dot(lp, b)), 0.012, px, tl);
			// Milky where the cubes are too small to see one by one; each cube glints on its
			// own only up close (a tilt per sub-pixel cell is just noise).
			float resolved = smoothstep(2.5, 7.0, 0.012 / px);
			alb = mix(glass_albedo, vec3(0.46, 0.48, 0.5), mix(0.62, 0.42, resolved));
			rough = mix(0.3, 0.14, resolved);
			tilt = (t * tl.x + b * tl.y) * 0.5 * resolved;
		}
		for (int i = 0; i < crack_count && i < 12; i++) {
			vec2 facet;
			float web = cd_crack_web(lp, cracks[i].xyz, crack_n[i].xyz, cracks[i].w, crack_n[i].w, px, facet);
			if (web > 0.0 || dot(facet, facet) > 0.0) {
				vec3 t;
				vec3 b;
				cd_frame(crack_n[i].xyz, t, b);
				tilt += (t * facet.x + b * facet.y) * 0.18;
			}
			lines = max(lines, web);
		}
		// A crack scatters light, so it reads pale against the dark tint by day; at night it
		// only catches whatever lights it.
		alb = mix(alb, vec3(0.7, 0.72, 0.74), lines * 0.85);
		rough = mix(rough, 0.4, lines);
	}
	// Soot on whatever glass survives a fire.
	alb *= 1.0 - 0.8 * clamp(burnt * 2.0, 0.0, 1.0);

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = 0.03;
	float tl2 = length(tilt);
	if (tl2 > 1e-4) {
		vec3 tv = (VIEW_MATRIX * (MODEL_MATRIX * vec4(tilt, 0.0))).xyz;
		NORMAL = normalize(NORMAL + normalize(tv) * tl2);
	}
}
