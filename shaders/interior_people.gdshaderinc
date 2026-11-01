// People behind the glass (InteriorsGlass, scripts/world/interiors_glass.gd; INTERIORS_GLASS=0 in
// the environment turns it off through the `interiors_glass` global).
//
// A person here is a signed distance field - head, neck, a torso of two capsules (shoulders and a
// chest, wider than deep), hips, two-segment arms and legs - ray-marched inside its own bounding
// box, so from two metres off the glass a shopper reads as a body with shoulders, a waist, legs
// that swing as they walk and arms that hang, not as a pill. Poses: STAND (idle sway), WALK (the
// legs and arms swing with the distance walked), SIT (thighs level forward, shins down) and REACH
// (an arm up at a shelf). Clothes, skin and hair are picked by what part of the body the ray met.
//
// Used by shop_interior() (shop_interior.gdshaderinc, people at the counters, browsing the aisles,
// at the tables, in the barber's chairs, the teller line, a lobby's desk) and by the homes' and the
// offices' traces (window_rooms.gdshaderinc) within `ip_near` metres of the camera; past it they
// keep the old capsule. Every roll is wl_hash()/shop_byte() of an integer key, never a float hash
// of a position. Needs hash21() from building.gdshader. Shader includes use // comments.

global uniform float interiors_glass;

const int IP_STAND = 0;
const int IP_WALK = 1;
const int IP_SIT = 2;
const int IP_REACH = 3;

// What the ray met (material ids).
const int IP_SKIN = 1;
const int IP_HAIR = 2;
const int IP_TOP = 3;
const int IP_BOTTOM = 4;
const int IP_SHOES = 5;

// Metres from the camera within which the march runs at all (beyond, a person is a few pixels and
// the cheap capsule stands in).
const float IP_NEAR = 34.0;
// A storefront's mirror by day against the old 0.66 (building.gdshader's glass).
const float ip_shop_mirror_day = 1.25;

float ip_on() {
	return interiors_glass;
}

float ip_seg(vec3 p, vec3 a, vec3 b, float r) {
	vec3 pa = p - a;
	vec3 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

float ip_smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// The body in its own frame: feet at y 0, facing +z, x to its left. `pose` as above, `ph` the gait
// phase (radians), `s` the height scale (1 = 1.75 m), `build` 0 slim .. 1 broad, `sit_y` the seat's
// height. Returns the distance and the material id.
vec2 ip_body(vec3 p, int pose, float ph, float s, float build, float sit_y) {
	p /= s;
	float w = mix(0.94, 1.12, build);
	float hip_y = 0.92;
	float sh_y = 1.39;
	float swing = 0.0;
	float arm_sw = 0.0;
	float bob = 0.0;
	if (pose == IP_WALK) {
		swing = sin(ph) * 0.30;
		arm_sw = -sin(ph) * 0.22;
		bob = 0.018 * abs(cos(ph));
	} else {
		bob = 0.006 * sin(ph);
	}
	vec3 q = p - vec3(0.0, bob, 0.0);
	float seat = 0.0;
	if (pose == IP_SIT) {
		// The hips down on the seat; the torso as standing, lowered.
		seat = hip_y - (sit_y / s + 0.06);
		q.y += seat;
	}
	// Head and hair.
	vec3 hc = vec3(0.0, 1.63, 0.01);
	vec3 hq = (q - hc) / vec3(0.080, 0.108, 0.094);
	float head = (length(hq) - 1.0) * 0.080;
	float neck = ip_seg(q, vec3(0.0, 1.43, -0.005), vec3(0.0, 1.55, 0.0), 0.050);
	// The torso: shoulders and chest as two capsules either side, a waist, the hips.
	float chest = min(ip_seg(q, vec3(-0.085 * w, 1.06, 0.0), vec3(-0.095 * w, 1.33, 0.0), 0.115 * w),
		ip_seg(q, vec3(0.085 * w, 1.06, 0.0), vec3(0.095 * w, 1.33, 0.0), 0.115 * w));
	float shoulders = ip_seg(q, vec3(-0.17 * w, 1.37, -0.01), vec3(0.17 * w, 1.37, -0.01), 0.062 * w);
	float hips = ip_seg(q, vec3(-0.085 * w, hip_y, 0.0), vec3(0.085 * w, hip_y, 0.0), 0.105 * w);
	float torso = ip_smin(ip_smin(chest, shoulders, 0.05), ip_smin(hips, chest, 0.06), 0.03);
	// Arms: shoulder, elbow, hand, swinging with the stride (or one up at a shelf).
	float arms = 1e3;
	for (int i = 0; i < 2; i++) {
		float sd = i == 0 ? -1.0 : 1.0;
		float sw = arm_sw * sd;
		vec3 a = vec3(0.205 * w * sd, sh_y, -0.01);
		vec3 e = a + vec3(0.03 * sd, -0.28, sw * 0.35);
		vec3 h = e + vec3(-0.01 * sd, -0.25, 0.03 + sw * 0.5);
		if (pose == IP_SIT) {
			// Forearms forward onto the lap or the table.
			h = e + vec3(-0.04 * sd, -0.04, 0.26);
		} else if (pose == IP_REACH && i == 1) {
			e = a + vec3(0.02, 0.18, 0.22);
			h = e + vec3(-0.02, 0.20, 0.10);
		}
		arms = min(arms, min(ip_seg(q, a, e, 0.048), ip_seg(q, e, h, 0.040)));
	}
	// Legs: hip, knee, ankle.
	float legs = 1e3;
	float shoes = 1e3;
	for (int i = 0; i < 2; i++) {
		float sd = i == 0 ? -1.0 : 1.0;
		vec3 hp = vec3(0.090 * w * sd, hip_y - 0.03, 0.0);
		vec3 k;
		vec3 an;
		if (pose == IP_SIT) {
			k = hp + vec3(0.02 * sd, 0.0, 0.46);
			an = vec3(k.x, 0.08 + seat, k.z + 0.04);
		} else {
			float sw = swing * sd;
			// The knee bends on the leg swinging forward.
			k = hp + vec3(0.0, -0.43, 0.43 * sin(sw));
			float bend = pose == IP_WALK ? max(sin(ph * sd + 1.2), 0.0) * 0.35 : 0.0;
			an = k + vec3(0.0, -0.42, 0.42 * sin(sw - bend));
		}
		legs = min(legs, min(ip_seg(q, hp, k, 0.078 * w), ip_seg(q, k, an, 0.058)));
		shoes = min(shoes, ip_seg(q, an + vec3(0.0, -0.03, -0.02), an + vec3(0.0, -0.045, 0.13), 0.045));
	}
	float d = head;
	float id = float(IP_SKIN);
	if (neck < d) { d = neck; id = float(IP_SKIN); }
	float body = ip_smin(torso, neck, 0.03);
	if (body < d) { d = body; id = float(IP_TOP); }
	if (arms < d) { d = ip_smin(d, arms, 0.025); id = float(IP_TOP); }
	if (legs < d) { d = ip_smin(d, legs, 0.03); id = float(IP_BOTTOM); }
	if (shoes < d) { d = shoes; id = float(IP_SHOES); }
	// Hair: the top and back of the head.
	if (id == float(IP_SKIN) && q.y > 1.56 && (q.y > 1.68 || q.z < -0.01)) {
		id = float(IP_HAIR);
	}
	// Bare forearms and hands: below the sleeve's end.
	if (id == float(IP_TOP) && arms <= body + 0.002 && q.y < (pose == IP_SIT ? 1.02 : 0.98)) {
		id = float(IP_SKIN);
	}
	return vec2(d * s, id);
}

// One person standing at `at` (frame x, z; the floor at y 0) turned `yaw` (radians; 0 faces +z).
// Marches `rd` from `ro` within its box and returns the hit distance (or 1e9), the normal in the
// frame and the material id. `tmax` is what the ray already hit nearer.
float ip_trace(vec3 ro, vec3 rd, vec2 at, float yaw, int pose, float ph, float s, float build, float sit_y,
		float tmax, out vec3 n, out int mat) {
	n = vec3(0.0, 0.0, -1.0);
	mat = 0;
	float c = cos(yaw);
	float sn = sin(yaw);
	// Into the body's frame (the ray is turned by -yaw about y).
	vec3 o = ro - vec3(at.x, 0.0, at.y);
	vec3 lo = vec3(c * o.x - sn * o.z, o.y, sn * o.x + c * o.z);
	vec3 ld = vec3(c * rd.x - sn * rd.z, rd.y, sn * rd.x + c * rd.z);
	// The box round it.
	float hgt = 1.80 * s;
	vec3 b0 = vec3(-0.36, -0.02, -0.30) * vec3(s, 1.0, s);
	vec3 b1 = vec3(0.36 * s, hgt, (pose == IP_SIT ? 0.62 : 0.36) * s);
	vec3 inv = 1.0 / vec3(abs(ld.x) > 1e-5 ? ld.x : 1e-5, abs(ld.y) > 1e-5 ? ld.y : 1e-5, abs(ld.z) > 1e-5 ? ld.z : 1e-5);
	vec3 t0 = (b0 - lo) * inv;
	vec3 t1 = (b1 - lo) * inv;
	vec3 tmn = min(t0, t1);
	vec3 tmx = max(t0, t1);
	float ta = max(max(max(tmn.x, tmn.y), tmn.z), 0.0);
	float tb = min(min(min(tmx.x, tmx.y), tmx.z), tmax);
	if (tb <= ta) {
		return 1e9;
	}
	float t = ta;
	float hit = 1e9;
	for (int i = 0; i < 28; i++) {
		vec2 dd = ip_body(lo + ld * t, pose, ph, s, build, sit_y);
		if (dd.x < 0.0025) {
			hit = t;
			mat = int(dd.y + 0.5);
			break;
		}
		t += max(dd.x * 0.9, 0.004);
		if (t > tb) {
			break;
		}
	}
	if (hit > 1e8) {
		return 1e9;
	}
	vec3 hp = lo + ld * hit;
	const vec2 e = vec2(0.006, -0.006);
	vec3 ln = normalize(e.xyy * ip_body(hp + e.xyy, pose, ph, s, build, sit_y).x
		+ e.yyx * ip_body(hp + e.yyx, pose, ph, s, build, sit_y).x
		+ e.yxy * ip_body(hp + e.yxy, pose, ph, s, build, sit_y).x
		+ e.xxx * ip_body(hp + e.xxx, pose, ph, s, build, sit_y).x);
	// Back into the frame (turned by +yaw).
	n = vec3(c * ln.x + sn * ln.z, ln.y, -sn * ln.x + c * ln.z);
	return hit;
}

// Clothes, skin and hair for a person of key `k` (LINEAR). `worn` dulls them a little.
vec3 ip_color(int mat, uint k, vec3 n) {
	float r0 = float(k % 977u) / 977.0;
	float r1 = float((k / 977u) % 991u) / 991.0;
	float r2 = float((k / 7919u) % 983u) / 983.0;
	if (mat == IP_SKIN) {
		vec3 light = vec3(0.62, 0.42, 0.32);
		vec3 dark = vec3(0.16, 0.09, 0.06);
		return mix(light, dark, r0 * r0 * 1.1);
	}
	if (mat == IP_HAIR) {
		return mix(vec3(0.03, 0.025, 0.02), vec3(0.30, 0.20, 0.10), r1 * r1) * (r2 > 0.92 ? 3.0 : 1.0);
	}
	if (mat == IP_SHOES) {
		return r1 > 0.7 ? vec3(0.75, 0.74, 0.72) : vec3(0.05, 0.045, 0.04);
	}
	if (mat == IP_BOTTOM) {
		// Jeans, black, khaki, grey.
		vec3 c = r2 < 0.45 ? vec3(0.08, 0.11, 0.20) : (r2 < 0.7 ? vec3(0.04) : (r2 < 0.85 ? vec3(0.36, 0.30, 0.20) : vec3(0.20)));
		return c;
	}
	// Tops: muted colours, whites and blacks.
	vec3 c = 0.5 + 0.5 * cos(6.2832 * (r1 + vec3(0.0, 0.33, 0.67)));
	c = mix(vec3(dot(c, vec3(0.333))), c, 0.55) * mix(0.25, 0.75, r0);
	if (r2 > 0.78) {
		c = vec3(0.72, 0.71, 0.68);
	} else if (r2 < 0.18) {
		c = vec3(0.04);
	}
	return c;
}

// The soft dark patch under somebody's feet on the floor (0..1).
float ip_foot_shadow(vec2 p, vec2 at, float s) {
	float d = length(p - at) / (0.34 * s);
	return 1.0 - smoothstep(0.35, 1.0, d);
}
