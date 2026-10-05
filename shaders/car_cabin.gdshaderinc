// The cabin behind a car's glass, traced in the body model's own mesh space so it has true
// parallax: the dash with its instruments and centre screen, the steering wheel on the driver's
// side (left-hand drive), the centre console and gear lever, two front seats and the rear bench
// with their headrests, the headliner, the door cards and floor, the far windows letting the day
// in - and whoever sits in the front seats. Shared by car_glass.gdshader (every intact window)
// and car_glass_damage.gdshader (a damaged car's glass: the cabin through an empty frame and
// through what is still whole). CarCabin (scripts/vehicles/car_cabin.gd) measures the numbers
// once per body model; who sits where is per car (the occupant uniforms, CarCabin.seat()): a car
// with nobody in it wears its body type's one shared material, an occupied car a copy of it.
//
// Define CABIN_FIRE before including it for `burnt` and `cabin_fire` uniforms (the damage);
// without it they are 0 and the compiler drops what they drive.

#include "res://shaders/car_damage.gdshaderinc"

global uniform vec4 sky_tint;
global uniform float night_factor;
global uniform float lamp_factor;

// Panes: pane_lo xyz / pane_hi xyz the box, pane_lo.w the state (0 whole, 1 crazed, 2 gone),
// pane_hi.w the kind (0 tempered, 1 laminated windscreen, 2 a lamp cover), pane_n xyz the mean
// normal and pane_n.w how much of the cabin it lets through head on (-1: side glass, side_t by
// where along the car).
uniform int pane_count = 0;
uniform vec4 pane_lo[16];
uniform vec4 pane_hi[16];
uniform vec4 pane_n[16];
// The cabin behind the glass, in mesh space: the box, the door line (bottom of the side glass)
// and where the two rows of seat backs stand along the car (z).
uniform vec3 cabin_lo = vec3(-0.75, 0.4, -1.0);
uniform vec3 cabin_hi = vec3(0.75, 1.4, 1.2);
uniform float belt_y = 0.95;
// The top of the side glass.
uniform float side_top = 1.3;
uniform vec2 seat_z = vec2(0.0, 1.0);
// Which side of the mesh (the sign of x) the driver sits on: the car's left.
uniform float driver_side = -1.0;
// Side glass: how much it lets through ahead of the front seat backs, and behind them (privacy
// glass on the crossover, pickup and van).
uniform vec2 side_t = vec2(0.6, 0.48);
// A bus (CarCabin.cabin()): rows of seat pairs either side of the aisle - x the first row's seat
// backs (z), y the pitch (signed toward the rear by the seat order), z how many rows, w the share of
// seats taken. 0 rows: a car. And the cabin's own lights after dark (a bus's ceiling strips).
uniform vec4 bus_rows = vec4(0.0);
uniform float interior_lamp = 0.0;
// How bright the cabin is, against the sky it is lit by (emitted, like the buildings' glass
// mirror, so it follows DayNight's sky_tint into the night).
uniform float cabin_light = 4.0;
// The instruments and the centre screen after dark, while somebody is in the driver's seat.
uniform float dash_glow = 1.0;
// After dark the street lamps light the cabin a little through the glass (times lamp_factor),
// and the street shows in the far windows: without it a car at night was a black box.
uniform vec3 street_light = vec3(0.04, 0.028, 0.015);
// People against the seats: the fabric's cabin_light is set for dark cloth, and at it a face or a
// white shirt glowed like the day outside.
uniform float people_light = 0.5;
// The glass's own colour on what it lets through (linear).
uniform vec3 glass_tint = vec3(0.84, 0.91, 0.88);
// The cabin seen through whole glass against cabin_light (which an empty frame shows at full):
// through the glass it read as bright as the paint outside on Forward+, where a real cabin by
// day is a dark room with the sky mirrored over it. The Compatibility renderer (the web, the
// opengl3 stills) lights the paint about half as bright again, and at the same number the
// people behind the glass were lost: it has its own.
uniform float through_light = 0.45;
uniform float through_light_compat = 0.9;
// Past this distance (mesh units, metres on every body) the glass is plain dark glass.
uniform float cabin_far = 70.0;
// Past this distance the small things are left out of the trace (the gear lever, the screen,
// the wheel's hub, spokes and column, the people's thighs): a few pixels each out there.
uniform float cabin_detail = 12.0;

#ifdef CABIN_FIRE
// 0 .. 1: every pane gone and the cabin burnt out.
uniform float burnt = 0.0;
// A cabin on fire (the wreck): an orange flicker on everything inside, hottest low down.
uniform float cabin_fire = 0.0;
#else
const float burnt = 0.0;
const float cabin_fire = 0.0;
#endif

// Who is in the car (CarCabin.seat()): top's colour (linear) and in .a the seats taken (bit 0
// the driver's, bit 1 the front passenger's); skin and in .a the hair style (0 short, 1 long,
// 2 shaved, 3 a cap); hair (or the cap) and in .a a 0..1 seed; the passenger's top and in .a
// their skin tone (0 fair .. 1 dark), plus 2 when they wear the driver's cap (a uniform).
// Plain uniforms on a per-car copy of the material, not `instance uniform`s: every instance that
// uses those takes a 16-item block of the global shader buffer, which the Compatibility renderer
// caps at 4096 items (WebGL2 may give a quarter of that) - the city's ~300 cars and their shadow
// twins overflowed it (267 allocation errors in one downtown still).
uniform vec4 occupant_top = vec4(0.0);
uniform vec4 occupant_skin = vec4(0.0);
uniform vec4 occupant_hair = vec4(0.0);
uniform vec4 occupant_mate = vec4(0.0);

// What a cabin hit is (the furniture's `mat`).
const int CAB_FABRIC = 0;
const int CAB_DASH = 1;
const int CAB_PLASTIC = 2;
const int CAB_SCREEN = 3;
const int CAB_SKIN = 4;
const int CAB_TOP = 5;
const int CAB_HEAD = 6;
const int CAB_LEGS = 7;
const int CAB_ARM = 8;
const int CAB_UPPER = 9;
const int CAB_CHEST = 10;

// Paints each part of a person its own flat colour (tools/glshot/car_shot.gd CABIN_DEBUG=1).
uniform bool cabin_debug = false;


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


// How much of the cabin pane `i` lets through head on at `p`: its own tint, or for side glass
// the front or the rear number by which side of the front seat backs the point is.
float pane_t(int i, vec3 p) {
	if (i < 0) {
		return side_t.x;
	}
	float t = pane_n[i].w;
	if (t < 0.0) {
		float back = seat_z.y > seat_z.x ? 1.0 : -1.0;
		t = (p.z - seat_z.x) * back > -0.04 ? side_t.y : side_t.x;
	}
	return t;
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


// Keeps the nearest of the cabin's boxes: `shade` for the seats' fabric, `mat` what it is.
void furniture(vec3 o, vec3 inv_d, vec3 lo, vec3 hi, float shade, int mat, inout float best, inout vec3 best_n, inout float best_shade, inout int best_mat) {
	vec3 n;
	float t = box_hit(o, inv_d, min(lo, hi), max(lo, hi), n);
	if (t >= 0.0 && t < best) {
		best = t;
		best_n = n;
		best_shade = shade;
		best_mat = mat;
	}
}


// A ray (unit `d`) and a capsule from `a` to `b` of radius `r`: the distance in, or -1.
float cap_hit(vec3 o, vec3 d, vec3 a, vec3 b, float r) {
	vec3 ba = b - a;
	vec3 oa = o - a;
	float baba = dot(ba, ba);
	float bard = dot(ba, d);
	float baoa = dot(ba, oa);
	float rdoa = dot(d, oa);
	float oaoa = dot(oa, oa);
	float qa = max(baba - bard * bard, 1e-7);
	float qb = baba * rdoa - baoa * bard;
	float qc = baba * oaoa - baoa * baoa - r * r * baba;
	float h = qb * qb - qa * qc;
	if (h < 0.0) {
		return -1.0;
	}
	float t = (-qb - sqrt(h)) / qa;
	float y = baoa + t * bard;
	if (y > 0.0 && y < baba) {
		return t;
	}
	// The round ends.
	vec3 oc = y <= 0.0 ? oa : o - b;
	float eb = dot(d, oc);
	float ec = dot(oc, oc) - r * r;
	float eh = eb * eb - ec;
	return eh > 0.0 ? -eb - sqrt(eh) : -1.0;
}


// Keeps a capsule if it is nearer; best_aux.x is where along it (0 at `a`, 1 at `b`), .w who.
void cap_keep(vec3 o, vec3 d, vec3 a, vec3 b, float r, int mat, float who, inout float best, inout vec3 best_n, inout float best_shade, inout int best_mat, inout vec4 best_aux) {
	float t = cap_hit(o, d, a, b, r);
	if (t > 0.0 && t < best) {
		vec3 p = o + d * t;
		vec3 ba = b - a;
		float h = clamp(dot(p - a, ba) / max(dot(ba, ba), 1e-7), 0.0, 1.0);
		best = t;
		best_n = normalize(p - a - ba * h);
		best_shade = 1.0;
		best_mat = mat;
		best_aux = vec4(h, 0.0, 0.0, who);
	}
}


// Keeps an ellipsoid (centre `c`, radii `r`) if it is nearer; for a head, best_aux.xyz is where
// on it, in its own unit sphere.
void ell_keep(vec3 o, vec3 d, vec3 c, vec3 r, int mat, float who, inout float best, inout vec3 best_n, inout float best_shade, inout int best_mat, inout vec4 best_aux) {
	vec3 oc = (o - c) / r;
	vec3 rd = d / r;
	float qa = dot(rd, rd);
	float qb = dot(oc, rd);
	float qc = dot(oc, oc) - 1.0;
	float h = qb * qb - qa * qc;
	if (h < 0.0) {
		return;
	}
	float t = (-qb - sqrt(h)) / qa;
	if (t > 0.0 && t < best) {
		vec3 q = (o + d * t - c) / r;
		best = t;
		best_n = normalize(q / r);
		best_shade = 1.0;
		best_mat = mat;
		best_aux = vec4(q, who);
	}
}


// The steering wheel's rim: a washer `rad` +- `rw` round `c`, `tw` either side of its plane
// (normal `n`, unit). The distance in, or -1, and the normal where it goes in.
float ring_hit(vec3 o, vec3 d, vec3 c, vec3 n, float rad, float rw, float tw, out vec3 nrm) {
	nrm = n;
	float dn = dot(d, n);
	float on = dot(o - c, n);
	float ta = 0.0;
	float tb = 1e4;
	if (abs(dn) > 1e-5) {
		float t1 = (-tw - on) / dn;
		float t2 = (tw - on) / dn;
		ta = max(min(t1, t2), 0.0);
		tb = max(t1, t2);
	} else if (abs(on) > tw) {
		return -1.0;
	}
	if (tb < ta) {
		return -1.0;
	}
	// The ray's shadow on the wheel's plane, from its centre: q0 + t * qd.
	vec3 q0 = (o - c) - on * n;
	vec3 qd = d - dn * n;
	float ro = rad + rw;
	float ri = max(rad - rw, 0.0);
	vec3 qa = q0 + qd * ta;
	float ra2 = dot(qa, qa);
	if (ra2 <= ro * ro && ra2 >= ri * ri) {
		// In through a face of the washer.
		nrm = n * (dn > 0.0 ? -1.0 : 1.0);
		return ta;
	}
	float A = max(dot(qd, qd), 1e-8);
	float B = dot(q0, qd);
	float t = -1.0;
	if (ra2 > ro * ro) {
		// Outside it: in through the outer wall.
		float h = B * B - A * (dot(q0, q0) - ro * ro);
		if (h < 0.0) {
			return -1.0;
		}
		t = (-B - sqrt(h)) / A;
		nrm = normalize(q0 + qd * t);
	} else {
		// In the hole: out of it through the inner wall.
		float h = max(B * B - A * (dot(q0, q0) - ri * ri), 0.0);
		t = (-B + sqrt(h)) / A;
		nrm = -normalize(q0 + qd * t);
	}
	return (t >= ta && t <= tb) ? t : -1.0;
}


// Somebody in the front seat whose middle is x = `sx`: head, neck, shoulders, chest, thighs and
// two arms, reaching for the wheel (hands at ten to two on the rim: centre `wc`, across `wu`, up
// `wv`, radius `wr`) or resting in the lap. Laid out from the side glass down, the way a person
// shows in a car window: the crown just under the top of the glass, the shoulders a hand over the
// door line, the neck whatever is between (a low car's driver sits low); `fs` scales the build
// (narrower in a small cabin, and by the seed). `who` 0 the driver, 1 the passenger.
void person(vec3 o, vec3 d, vec3 inv, float sx, float back, float fs, float who, bool drive, bool close_up, vec3 wc, vec3 wu, vec3 wv, float wr, inout float best, inout vec3 best_n, inout float best_shade, inout int best_mat, inout vec4 best_aux) {
	// The cushion's top and the seat back's face.
	float yc = belt_y - 0.42;
	float zb = seat_z.x;
	float fw = -back;
	// The crown: under the top of the side glass (further under in a low cabin, whose window top
	// slopes down fast behind its highest point), never higher than a real person's.
	float crown = min(side_top - 0.025 - (1.0 - fs) * 0.25, belt_y + 0.47 * fs);
	// Most rays miss the whole figure: one box first.
	vec3 bn;
	vec3 blo = vec3(sx - 0.32, yc - 0.02, zb + back * 0.06);
	vec3 bhi = vec3(sx + 0.32, crown + 0.01, zb + fw * 0.95);
	float tb = box_hit(o, inv, min(blo, bhi), max(blo, bhi), bn);
	if (tb < 0.0 || tb >= best) {
		return;
	}
	vec3 hr = vec3(0.078, 0.108, 0.096) * fs;
	vec3 hc = vec3(sx, crown - hr.y, zb + fw * 0.14 * fs);
	float chin = hc.y - hr.y * 0.85;
	// The shoulder line: a neck's length under the chin, never below the door line.
	float shy = max(chin - 0.15 * fs, belt_y - 0.02);
	ell_keep(o, d, hc, hr, CAB_HEAD, who, best, best_n, best_shade, best_mat, best_aux);
	cap_keep(o, d, vec3(sx, shy, zb + fw * 0.1 * fs), vec3(sx, hc.y - hr.y * 0.3, zb + fw * 0.13 * fs), 0.047 * fs, CAB_SKIN, who, best, best_n, best_shade, best_mat, best_aux);
	cap_keep(o, d, vec3(sx - 0.14 * fs, shy, zb + fw * 0.1 * fs), vec3(sx + 0.14 * fs, shy, zb + fw * 0.1 * fs), 0.068 * fs, CAB_TOP, who, best, best_n, best_shade, best_mat, best_aux);
	float chest_h = max((shy - yc) * 0.5, 0.12);
	ell_keep(o, d, vec3(sx, shy - chest_h * 0.8, zb + fw * 0.12 * fs), vec3(0.165 * fs, chest_h, 0.115 * fs), CAB_CHEST, who, best, best_n, best_shade, best_mat, best_aux);
	for (int k = 0; k < 2; k++) {
		float s = k == 0 ? -1.0 : 1.0;
		if (close_up) {
			cap_keep(o, d, vec3(sx + s * 0.09 * fs, yc + 0.08, zb + fw * 0.12), vec3(sx + s * 0.11 * fs, yc + 0.12, zb + fw * 0.5), 0.075 * fs, CAB_LEGS, who, best, best_n, best_shade, best_mat, best_aux);
		}
		vec3 sh = vec3(sx + s * 0.185 * fs, shy - 0.01, zb + fw * 0.1 * fs);
		vec3 hand = drive ? wc + wr * (s * 0.86 * wu + 0.5 * wv) : vec3(sx + s * 0.13 * fs, yc + 0.18, zb + fw * 0.36);
		// The elbow: bent down and out by as much as the arm's length allows.
		vec3 axis = hand - sh;
		float dist = max(length(axis), 1e-4);
		axis /= dist;
		float half_len = 0.33 * fs;
		float bend = sqrt(max(half_len * half_len - dist * dist * 0.25, 0.0));
		vec3 out_dir = vec3(s * 0.45, -1.0, 0.0);
		out_dir = normalize(out_dir - axis * dot(out_dir, axis));
		vec3 elbow = (sh + hand) * 0.5 + out_dir * bend;
		cap_keep(o, d, sh, elbow, 0.047 * fs, CAB_UPPER, who, best, best_n, best_shade, best_mat, best_aux);
		cap_keep(o, d, elbow, hand, 0.038 * fs, CAB_ARM, who, best, best_n, best_shade, best_mat, best_aux);
	}
}


// What a person's hit is coloured: skin, the top, the head (hair or a cap over the face), the
// legs, a forearm (sleeved or bare by the seed, the hand always bare).
vec3 person_albedo(int mat, vec4 aux, float back) {
	if (aux.w > 1.5) {
		// A bus passenger: colours from their seat's hash.
		float h = fract(aux.w);
		vec3 sk = mix(vec3(0.8, 0.56, 0.43), vec3(0.06, 0.03, 0.018), fract(h * 7.31));
		float t = fract(h * 3.17);
		vec3 tp = t < 0.35 ? vec3(0.03) : (t < 0.55 ? vec3(0.7, 0.7, 0.68) : vec3(fract(h * 5.1) * 0.5, fract(h * 9.3) * 0.35, fract(h * 2.7) * 0.4));
		if (mat == CAB_HEAD) {
			vec3 q = aux.xyz;
			float qb = q.z * back;
			return q.y > mix(0.42, -0.45, smoothstep(-0.3, 0.8, qb)) ? vec3(0.03, 0.02, 0.015) * (1.0 + fract(h * 11.0) * 3.0) : sk;
		}
		return tp;
	}
	bool mate = aux.w > 0.5;
	vec3 skin = occupant_skin.rgb;
	vec3 top = occupant_top.rgb;
	vec3 hair = occupant_hair.rgb;
	float style = occupant_skin.a;
	float seed = occupant_hair.a;
	if (mate) {
		// The passenger: their own top and skin, hair from the seed, the driver's cap only in a
		// uniform (occupant_mate.a over 2).
		top = occupant_mate.rgb;
		skin = mix(vec3(0.8, 0.56, 0.43), vec3(0.05, 0.028, 0.016), fract(occupant_mate.a));
		seed = fract(seed * 7.31 + 0.37);
		bool cap = occupant_mate.a > 1.5;
		hair = cap ? hair : mix(vec3(0.004, 0.003, 0.002), vec3(0.09, 0.05, 0.025), fract(seed * 3.7));
		style = cap ? 3.0 : (seed > 0.55 ? 1.0 : 0.0);
	}
	if (cabin_debug) {
		// Neck green, shoulders blue, chest white, upper arms cyan, forearms magenta, thighs
		// yellow, the head red with the hair dark.
		if (mat == CAB_SKIN) { return vec3(0.0, 1.0, 0.0); }
		if (mat == CAB_TOP) { return vec3(0.0, 0.0, 1.0); }
		if (mat == CAB_CHEST) { return vec3(1.0); }
		if (mat == CAB_UPPER) { return vec3(0.0, 1.0, 1.0); }
		if (mat == CAB_ARM) { return vec3(1.0, 0.0, 1.0); }
		if (mat == CAB_LEGS) { return vec3(1.0, 1.0, 0.0); }
	}
	if (mat == CAB_SKIN) {
		return skin;
	}
	if (mat == CAB_TOP || mat == CAB_CHEST || mat == CAB_UPPER) {
		return top;
	}
	if (mat == CAB_LEGS) {
		// Jeans, black, or chinos.
		return seed < 0.45 ? vec3(0.03, 0.045, 0.085) : (seed < 0.75 ? vec3(0.012, 0.012, 0.014) : vec3(0.26, 0.2, 0.12));
	}
	if (mat == CAB_ARM) {
		// Short sleeves on most (it is Los Angeles); the last stretch is the hand.
		bool sleeve = fract(seed * 13.7) < 0.35 || style > 2.5;
		return (aux.x > 0.82 || !sleeve) ? skin : top;
	}
	// The head: `aux.xyz` is the point on its unit sphere; `qb` toward the back of the head.
	vec3 q = aux.xyz;
	float qb = q.z * back;
	if (style > 2.5) {
		// A cap over the crown with its peak to the front, short hair under it at the back.
		if (q.y > 0.38 - 0.25 * max(-qb, 0.0)) {
			return hair;
		}
		return (qb > 0.25 && q.y > -0.4) ? vec3(0.02, 0.015, 0.012) : skin;
	}
	if (style > 1.5) {
		return skin * (q.y > 0.5 ? 0.92 : 1.0);
	}
	float line = style > 0.5 ? mix(0.42, -1.1, smoothstep(-0.55, 0.45, qb)) : mix(0.42, -0.45, smoothstep(-0.3, 0.8, qb));
	vec3 c = q.y > line ? (cabin_debug ? vec3(0.05) : hair) : (cabin_debug ? vec3(1.0, 0.0, 0.0) : skin);
	// Eyes and brows: a darker band across the face.
	if (qb < -0.55 && abs(q.x) < 0.62 && q.y > 0.02 && q.y < 0.24) {
		c *= 0.62;
	}
	return c;
}


// What a ray from `o` along `d` sees in the cabin: the dash, two front seats and the rear bench
// with their headrests, the wheel, console and lever, whoever is in the front, the headliner, the
// door cards and floor, and - out through the glass on the far side - the day (dimmed by that
// pane's tint while it is still in). `dist` is how far the camera is (cabin_detail).
vec3 cabin_view(vec3 o, vec3 d, float dist) {
	bool close_up = dist < cabin_detail;
	vec3 safe = vec3(abs(d.x) < 1e-4 ? 1e-4 : d.x, abs(d.y) < 1e-4 ? 1e-4 : d.y, abs(d.z) < 1e-4 ? 1e-4 : d.z);
	vec3 inv = 1.0 / safe;
	vec3 t1 = (cabin_lo - o) * inv;
	vec3 t2 = (cabin_hi - o) * inv;
	vec3 tf = max(t1, t2);
	float t_exit = max(min(min(tf.x, tf.y), tf.z), 0.0);
	vec3 sky = sky_tint.rgb + street_light * lamp_factor + vec3(0.17, 0.18, 0.19) * interior_lamp * lamp_factor;
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
	int best_mat = CAB_FABRIC;
	vec4 best_aux = vec4(0.0);
	for (int s = -1; s <= 1; s += 2) {
		float fs = float(s);
		float xa = cx + fs * 0.1;
		float xb = cx + fs * (half_w - 0.07);
		float mid = (xa + xb) * 0.5;
		// Front seat: backrest, cushion, headrest.
		furniture(o, inv, vec3(xa, fy, seat_z.x), vec3(xb, belt_y + 0.1, seat_z.x + back * 0.13), 0.9, CAB_FABRIC, best, best_n, best_shade, best_mat);
		furniture(o, inv, vec3(xa, fy, seat_z.x), vec3(xb, belt_y - 0.42, seat_z.x - back * 0.5), 0.8, CAB_FABRIC, best, best_n, best_shade, best_mat);
		if (char_ < 0.5) {
			furniture(o, inv, vec3(mid - 0.12, belt_y + 0.14, seat_z.x + back * 0.03), vec3(mid + 0.12, belt_y + 0.32, seat_z.x + back * 0.12), 1.0, CAB_FABRIC, best, best_n, best_shade, best_mat);
			furniture(o, inv, vec3(mid - 0.12, belt_y + 0.1, seat_z.y + back * 0.03), vec3(mid + 0.12, belt_y + 0.27, seat_z.y + back * 0.12), 1.0, CAB_FABRIC, best, best_n, best_shade, best_mat);
		}
	}
	// Rear bench and the dash.
	furniture(o, inv, vec3(cabin_lo.x + 0.03, fy, seat_z.y), vec3(cabin_hi.x - 0.03, belt_y + 0.06, seat_z.y + back * 0.14), 0.85, CAB_FABRIC, best, best_n, best_shade, best_mat);
	furniture(o, inv, vec3(cabin_lo.x + 0.03, fy, seat_z.y), vec3(cabin_hi.x - 0.03, belt_y - 0.44, seat_z.y - back * 0.5), 0.75, CAB_FABRIC, best, best_n, best_shade, best_mat);
	furniture(o, inv, vec3(cabin_lo.x, fy, front_end), vec3(cabin_hi.x, belt_y + 0.05, front_end + back * 0.42), 0.6, CAB_DASH, best, best_n, best_shade, best_mat);
	// A bus's rows: only those the ray can reach between the glass and where it leaves the cabin.
	if (bus_rows.z > 0.5) {
		float za = o.z;
		float zb = o.z + d.z * best;
		float ia = (za - bus_rows.x) * back / bus_rows.y;
		float ib = (zb - bus_rows.x) * back / bus_rows.y;
		int k0 = int(clamp(floor(min(ia, ib)), 0.0, bus_rows.z - 1.0));
		int k1 = int(clamp(ceil(max(ia, ib)), 0.0, bus_rows.z - 1.0));
		for (int k = k0; k <= k1 && k <= k0 + 7; k++) {
			float zk = bus_rows.x + back * bus_rows.y * float(k);
			for (int s = -1; s <= 1; s += 2) {
				float fs = float(s);
				float xa = cx + fs * 0.30;
				float xb = cx + fs * (half_w - 0.04);
				furniture(o, inv, vec3(xa, fy, zk), vec3(xb, belt_y + 0.02, zk + back * 0.09), 0.9, CAB_FABRIC, best, best_n, best_shade, best_mat);
				furniture(o, inv, vec3(xa, fy, zk), vec3(xb, belt_y - 0.40, zk - back * 0.44), 0.8, CAB_FABRIC, best, best_n, best_shade, best_mat);
				// Whoever sits in each of the pair's two seats, by a hash of the seat.
				for (int q = 0; q < 2; q++) {
					float px = mix(xa, xb, q == 0 ? 0.27 : 0.73);
					float id = float(k) * 4.0 + (fs + 1.0) + float(q);
					float h = fract(sin(id * 12.9898 + occupant_hair.a * 78.233) * 43758.5453);
					if (h < bus_rows.w && char_ < 0.5) {
						float sz = 0.92 + 0.14 * fract(h * 17.0);
						vec3 hc = vec3(px, belt_y + 0.30 * sz, zk - back * 0.12);
						ell_keep(o, d, hc, vec3(0.078, 0.105, 0.095) * sz, CAB_HEAD, 2.0 + h, best, best_n, best_shade, best_mat, best_aux);
						cap_keep(o, d, vec3(px - 0.14 * sz, belt_y + 0.10, zk - back * 0.13), vec3(px + 0.14 * sz, belt_y + 0.10, zk - back * 0.13), 0.07 * sz, CAB_TOP, 2.0 + h, best, best_n, best_shade, best_mat, best_aux);
						ell_keep(o, d, vec3(px, belt_y - 0.08, zk - back * 0.15), vec3(0.17, 0.2, 0.12) * sz, CAB_CHEST, 2.0 + h, best, best_n, best_shade, best_mat, best_aux);
					}
				}
			}
			// Grab poles on the aisle side of every other row.
			if (k % 2 == 0) {
				cap_keep(o, d, vec3(cx + 0.30, fy, zk - back * 0.5), vec3(cx + 0.30, cabin_hi.y, zk - back * 0.5), 0.016, CAB_PLASTIC, 0.0, best, best_n, best_shade, best_mat, best_aux);
			}
		}
	}
	// The centre console with the gear lever, and the screen in the middle of the dash.
	float dash_rear = front_end + back * 0.42;
	furniture(o, inv, vec3(cx - 0.1, fy, dash_rear - back * 0.05), vec3(cx + 0.1, belt_y - 0.36, seat_z.x + back * 0.03), 1.0, CAB_PLASTIC, best, best_n, best_shade, best_mat);
	if (close_up) {
		float zg = seat_z.x - back * 0.42;
		cap_keep(o, d, vec3(cx, belt_y - 0.36, zg), vec3(cx, belt_y - 0.25, zg - back * 0.02), 0.011, CAB_PLASTIC, 0.0, best, best_n, best_shade, best_mat, best_aux);
		cap_keep(o, d, vec3(cx, belt_y - 0.235, zg - back * 0.022), vec3(cx, belt_y - 0.225, zg - back * 0.024), 0.022, CAB_PLASTIC, 0.0, best, best_n, best_shade, best_mat, best_aux);
		furniture(o, inv, vec3(cx - 0.11, belt_y - 0.17, dash_rear - back * 0.01), vec3(cx + 0.11, belt_y - 0.03, dash_rear + back * 0.012), 1.0, CAB_SCREEN, best, best_n, best_shade, best_mat);
	}
	// The steering wheel in front of the driver's seat, its column raked up toward the driver.
	float sx = cx + driver_side * (half_w + 0.03) * 0.5;
	float zw = mix(seat_z.x - back * 0.7, dash_rear + back * 0.22, 0.5);
	zw = dash_rear + back * max((zw - dash_rear) * back, 0.12);
	vec3 wc = vec3(sx, belt_y - 0.05, zw);
	vec3 wn = normalize(vec3(0.0, 0.42, back * 0.91));
	vec3 wu = vec3(1.0, 0.0, 0.0);
	vec3 wv = normalize(cross(wn, wu));
	wv *= sign(wv.y);
	float wr = 0.185;
	// Only if the ray passes near the wheel at all.
	vec3 to_w = wc - o;
	float along_w = dot(to_w, d);
	if (along_w > 0.0 && along_w < best + 0.3 && length(to_w - d * along_w) < wr + 0.12) {
		vec3 rn;
		float t = ring_hit(o, d, wc, wn, wr, 0.016, 0.014, rn);
		if (t >= 0.0 && t < best) {
			best = t;
			best_n = rn;
			best_shade = 1.0;
			best_mat = CAB_PLASTIC;
		}
		if (close_up) {
			// The hub, and the spokes across and down to the rim.
			t = ring_hit(o, d, wc - wn * 0.02, wn, 0.035, 0.035, 0.03, rn);
			if (t >= 0.0 && t < best) {
				best = t;
				best_n = rn;
				best_shade = 1.0;
				best_mat = CAB_PLASTIC;
			}
			cap_keep(o, d, wc - wu * wr, wc + wu * wr, 0.013, CAB_PLASTIC, 0.0, best, best_n, best_shade, best_mat, best_aux);
			cap_keep(o, d, wc, wc - wv * wr, 0.013, CAB_PLASTIC, 0.0, best, best_n, best_shade, best_mat, best_aux);
			// The column into the dash.
			cap_keep(o, d, wc - wn * 0.03, wc - wn * 0.3, 0.032, CAB_PLASTIC, 0.0, best, best_n, best_shade, best_mat, best_aux);
		}
	}
	// Whoever is in the front seats, scaled to the headroom.
	float seats = occupant_top.a;
	if (seats > 0.5 && char_ < 0.5) {
		float fs = clamp((side_top - belt_y) / 0.42, 0.8, 1.0) * mix(0.94, 1.04, occupant_hair.a);
		float bit0 = mod(seats, 2.0);
		if (bit0 > 0.5) {
			person(o, d, inv, sx, back, fs, 0.0, true, close_up, wc, wu, wv, wr, best, best_n, best_shade, best_mat, best_aux);
		}
		if (seats > 1.5) {
			float px = cx - driver_side * (half_w + 0.03) * 0.5;
			person(o, d, inv, px, back, fs * 0.97, 1.0, false, close_up, wc, wu, wv, wr, best, best_n, best_shade, best_mat, best_aux);
		}
	}
	// Light in a cabin comes in through the windows: the tops of things catch it, the sides
	// facing the open frame a little, everything else sits in the dark.
	float flicker = 0.0;
	if (cabin_fire > 0.0) {
		flicker = cabin_fire * (0.55 + 0.45 * cd_noise3(vec3(TIME * 7.0, o.x * 3.0, o.z * 3.0)));
	}
	vec3 fire_c = vec3(1.9, 0.55, 0.12);
	// The instruments and the screen after dark, with somebody at the wheel.
	float glow = dash_glow * night_factor * step(0.5, mod(seats, 2.0)) * (1.0 - char_);
	if (best_shade >= 0.0) {
		vec3 h = o + d * best;
		float lit = 0.2 + 0.55 * max(best_n.y, 0.0) + 0.3 * max(dot(best_n, -d), 0.0);
		// The fire's light moves over the seats in patches, not as a flat wash.
		float patch = cd_noise3(h * 4.0 + vec3(0.0, TIME * 1.3, 0.0));
		vec3 fire_l = fire_c * flicker * (0.15 + 0.5 * max(best_n.y, 0.0)) * (0.3 + 0.9 * patch * patch);
		if (best_mat <= CAB_DASH) {
			vec3 fabric = mix(vec3(0.13, 0.125, 0.12), vec3(0.016, 0.014, 0.012), char_);
			fabric *= 0.8 + 0.4 * cd_noise3(h * 40.0);
			vec3 c = fabric * sky * lit * best_shade * cabin_light + fire_l;
			if (best_mat == CAB_DASH && glow > 0.0 && best_n.z * back > 0.5) {
				// The instrument cluster in front of the driver.
				vec2 q = vec2(h.x - sx, h.y - (belt_y - 0.03));
				float cl = (1.0 - smoothstep(0.12, 0.15, abs(q.x))) * (1.0 - smoothstep(0.04, 0.055, abs(q.y)));
				float dials = 0.55 + 0.45 * smoothstep(0.02, 0.035, abs(abs(q.x) - 0.065));
				c += vec3(0.22, 0.42, 0.85) * cl * dials * glow * 0.7;
			}
			return c;
		}
		vec3 alb;
		if (best_mat == CAB_PLASTIC) {
			alb = mix(vec3(0.035, 0.034, 0.033), vec3(0.012, 0.01, 0.009), char_);
		} else if (best_mat == CAB_SCREEN) {
			alb = vec3(0.012, 0.013, 0.015);
		} else {
			alb = person_albedo(best_mat, best_aux, back) * people_light;
		}
		vec3 c = alb * sky * lit * cabin_light + fire_l;
		if (glow > 0.0) {
			if (best_mat == CAB_SCREEN) {
				c += vec3(0.4, 0.52, 0.72) * glow * 0.45;
			} else if (best_mat >= CAB_SKIN) {
				// The dash lights the faces over it, faintly.
				c += alb * vec3(0.3, 0.45, 0.8) * glow * 1.2 * max(-best_n.z * back, 0.0);
			}
		}
		return c;
	}
	vec3 e = o + d * t_exit;
	int axis = (tf.x < tf.y && tf.x < tf.z) ? 0 : (tf.y < tf.z ? 1 : 2);
	if (axis != 1 && e.y > belt_y + 0.01) {
		// Out through the far glass (or the screens, front and back).
		int far_i = find_pane(e, axis == 0 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0));
		float open = 1.0;
		if (far_i >= 0 && pane_lo[far_i].w < 1.5) {
			// Still glazed: tinted, but you see the street through it (hardly, once crazed).
			open = pane_t(far_i, e) * (pane_lo[far_i].w > 0.5 ? 0.35 : 1.0);
		}
		if (far_i < 0 && pane_count > 0 && char_ < 0.5) {
			// Between the far panes: a pillar.
			return vec3(0.03, 0.029, 0.028) * sky * 0.6 * cabin_light;
		}
		open = max(open, char_);
		float lift = smoothstep(belt_y, cabin_hi.y, e.y);
		// The day outside, about as bright as the sky behind the car: not lifted like the cabin.
		return sky * open * (0.35 + 0.25 * lift) + fire_c * flicker * 0.25;
	}
	if (axis == 1 && d.y > 0.0) {
		// The headliner, or the bare roof skin once it has burnt away.
		vec3 roof = mix(vec3(0.34, 0.33, 0.31), vec3(0.03, 0.025, 0.02), char_);
		return roof * sky * 0.14 * cabin_light + fire_c * flicker * 0.5;
	}
	// Door cards and the floor.
	float low = smoothstep(cabin_lo.y, belt_y, e.y);
	vec3 trim = mix(vec3(0.08, 0.077, 0.074), vec3(0.01, 0.009, 0.008), char_);
	return trim * sky * (0.3 + 0.7 * low) * cabin_light + fire_c * flicker * (1.0 - 0.6 * low);
}


// What whole glass at `p` (on pane `i`, normal `n`, seen along unit `d` from `dist` away) lets
// through: the cabin, dimmed by the pane's tint and by the share Fresnel turns back as reflection
// - the renderer's own specular draws that half. Nothing through a lamp cover or a mirror, and
// past cabin_far the plain dark glass.
vec3 glass_view(vec3 p, vec3 d, vec3 n, int i, float dist) {
	float t = pane_t(i, p);
	if (dist > cabin_far || t <= 0.0 || (i >= 0 && pane_hi[i].w > 1.5)) {
		return vec3(0.0);
	}
	float c = abs(dot(d, n));
	float f = 0.04 + 0.96 * pow(1.0 - c, 5.0);
	float fade = 1.0 - smoothstep(cabin_far * 0.8, cabin_far, dist);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	float lift = through_light_compat;
#else
	float lift = through_light;
#endif
	return cabin_view(p, d, dist) * glass_tint * (t * lift * (1.0 - f) * fade);
}
