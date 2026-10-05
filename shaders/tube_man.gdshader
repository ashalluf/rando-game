shader_type spatial;
// An inflatable tube man (CarDealers): a ripstop nylon tube with two arm tubes, blown up from a
// fan at its foot, dancing. The mesh stands straight (CarDealers.tube_man_mesh()); everything it
// does is here, worked out from shader TIME and the instance's phase, never ticked on the CPU.
//
// The body is a chain: its curvature is a sum of travelling waves up the tube plus, every few
// seconds, a fold a third of the way up (the fan's gust lets go and the top flops over, then
// whips back up). The centre line is integrated in a few steps per vertex (cheap: a tube man is
// a few hundred vertices) and every ring is turned to the chain's angle there, so the tube keeps
// its girth through a bend. The arms are chains too, flapping up and down, carried by the body's
// tilt at the shoulder.
//
// Mesh contract: UV = (around 0..1, up the part 0..1); UV2.x = part (0 body, -1 left arm,
// +1 right arm), UV2.y unused. Model units: metres, foot at the origin, +Z the face.
// Instance: COLOR the nylon (sRGB, as written), INSTANCE_CUSTOM.r phase 0..1, .g tempo 0..1,
// .b the face's second colour index (0..1).
#include "res://shaders/color_space.gdshaderinc"

render_mode cull_disabled;

global uniform float wind_factor;

uniform float height = 6.0;
uniform float shoulder = 0.74;
uniform float arm_length = 1.45;

varying float v_up;
varying float v_part;
varying vec3 v_tint;
varying float v_hair;

// Curvature of the body at s (0 foot .. 1 head), time t.
float body_k(float s, float t, float fold) {
	float k = 0.9 * sin(2.3 * t - 7.0 * s) + 0.55 * sin(3.9 * t + 4.0 * s + 1.3);
	k *= smoothstep(0.0, 0.25, s);
	// The fold: a sharp kink just above the waist.
	k += fold * 9.0 * exp(-pow((s - 0.36) / 0.07, 2.0));
	return k;
}

// Angle and centre line (along d, up) of the body at s.
vec3 body_at(float s, float t, float fold) {
	const int N = 10;
	float ds = s / float(N);
	float th = 0.0;
	vec2 p = vec2(0.0);
	for (int i = 0; i < N; i++) {
		float si = (float(i) + 0.5) * ds;
		th += body_k(si, t, fold) * ds;
		p += vec2(sin(th), cos(th)) * ds * height;
	}
	return vec3(th, p);
}

void vertex() {
	float t = TIME * (1.6 + 0.6 * INSTANCE_CUSTOM.g) + INSTANCE_CUSTOM.r * 61.0;
	// A fold every ~6 s: the gust drops, the top flops, it whips back.
	float cyc = fract(t / 9.0 + INSTANCE_CUSTOM.r);
	float fold = smoothstep(0.55, 0.66, cyc) * (1.0 - smoothstep(0.74, 0.86, cyc));
	fold *= 0.55 + 0.45 * sin(INSTANCE_CUSTOM.r * 40.0);
	// The bending plane turns slowly; a little of the wind's push leans it.
	float phi = 0.6 * sin(0.37 * t + INSTANCE_CUSTOM.r * 9.0) + 1.2 * INSTANCE_CUSTOM.r;
	vec3 d = vec3(cos(phi), 0.0, sin(phi));
	vec3 pr = vec3(-d.z, 0.0, d.x);
	float part = UV2.x;
	v_part = part;
	if (abs(part) < 0.5) {
		float s = clamp(VERTEX.y / height, 0.0, 1.0);
		vec3 b = body_at(s, t, fold);
		float th = b.x;
		vec3 r = vec3(VERTEX.x, 0.0, VERTEX.z);
		float rd = dot(r, d);
		float rp = dot(r, pr);
		// A side wobble across the plane, smaller.
		float side = 0.35 * sin(1.7 * t + 3.0 * s) * s * s * height * 0.25;
		VERTEX = d * (b.y + rd * cos(th)) + vec3(0.0, b.z - rd * sin(th), 0.0) + pr * (rp + side);
		vec3 n = NORMAL;
		float nd = dot(n, d);
		float np = dot(n, pr);
		NORMAL = normalize(d * (nd * cos(th)) + vec3(0.0, n.y * cos(th) - nd * sin(th), 0.0) + pr * np);
		v_up = s;
	} else {
		float side = sign(part);
		float a = UV.y;
		// The arm's centre line in its own plane (out along x, up y), flapping.
		float e0 = 0.25 + 0.75 * sin(4.4 * t + side * 1.9) * (0.6 + 0.4 * sin(1.1 * t + side));
		const int M = 6;
		float da = a / float(M);
		float ang = e0;
		vec2 c = vec2(0.0);
		for (int i = 0; i < M; i++) {
			float ai = (float(i) + 0.5) * da;
			ang += 1.6 * sin(6.0 * t - 5.0 * ai + side) * da;
			c += vec2(cos(ang), sin(ang)) * da * arm_length;
		}
		// The cross-section offset from the rest centre line, turned to the arm's angle.
		vec3 rest = vec3(side * (0.28 + a * arm_length), shoulder * height, 0.0);
		vec3 off = VERTEX - rest;
		float ox = off.x * side;
		vec3 arm_local = vec3(side * (0.28 + c.x + ox * cos(ang) - off.y * sin(ang)), c.y + ox * sin(ang) + off.y * cos(ang), off.z);
		vec3 an = NORMAL;
		vec3 arm_n = vec3(side * (an.x * side * cos(ang) - an.y * sin(ang)), an.x * side * sin(ang) + an.y * cos(ang), an.z);
		// Carried by the body at the shoulder: its tilt and its position.
		vec3 b = body_at(shoulder, t, fold);
		float th = b.x;
		vec3 base = d * b.y + vec3(0.0, b.z, 0.0);
		float rd = dot(arm_local, d);
		float rp = dot(arm_local, pr);
		VERTEX = base + d * (rd * cos(th)) + vec3(0.0, arm_local.y * cos(th) - rd * sin(th), 0.0) + pr * rp;
		float nd = dot(arm_n, d);
		NORMAL = normalize(d * (nd * cos(th)) + vec3(0.0, arm_n.y * cos(th) - nd * sin(th), 0.0) + pr * dot(arm_n, pr));
		v_up = shoulder;
	}
	v_tint = COLOR.rgb;
	v_hair = INSTANCE_CUSTOM.b;
}

float ellipse(vec2 p, vec2 c, vec2 r) {
	vec2 q = (p - c) / r;
	return 1.0 - smoothstep(0.85, 1.0, dot(q, q));
}

void fragment() {
	vec3 col = cs_srgb_to_linear(v_tint);
	// Ripstop: a faint square grid, and the seams down the tube.
	vec2 g = abs(fract(UV * vec2(40.0, 90.0)) - 0.5);
	col *= 1.0 - 0.05 * step(0.44, max(g.x, g.y));
	col *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.012, abs(fract(UV.x * 2.0) - 0.5) - 0.488));
	// Air rippling up the nylon: soft bands that run up the body.
	float ripple = 0.5 + 0.5 * sin(UV.y * 38.0 - TIME * 9.0 + UV.x * 6.28);
	col *= 0.9 + 0.1 * ripple;
	float rough = 0.42;
	// The face, on the body's front near the top: two eyes and a big open mouth, and a mop of
	// "hair" fringe as a darker band round the head's top.
	if (abs(v_part) < 0.5) {
		vec2 fp = vec2((UV.x - 0.25) * 6.0, UV.y * height);
		float eyes = ellipse(fp, vec2(-0.17, height * 0.905), vec2(0.07, 0.11)) + ellipse(fp, vec2(0.17, height * 0.905), vec2(0.07, 0.11));
		float whites = ellipse(fp, vec2(-0.17, height * 0.905), vec2(0.12, 0.17)) + ellipse(fp, vec2(0.17, height * 0.905), vec2(0.12, 0.17));
		float mouth = ellipse(fp, vec2(0.0, height * 0.835), vec2(0.26, 0.12));
		col = mix(col, vec3(0.92), clamp(whites, 0.0, 1.0));
		col = mix(col, vec3(0.02), clamp(eyes + mouth, 0.0, 1.0));
		float hair = smoothstep(0.955, 0.965, UV.y);
		vec3 hair_col = mix(vec3(0.95, 0.85, 0.05), vec3(0.08, 0.35, 0.9), step(0.5, v_hair));
		col = mix(col, cs_srgb_to_linear(hair_col), hair);
	} else {
		// The arms' frayed ends are a lighter colour.
		col = mix(col, col * 1.35 + 0.05, smoothstep(0.88, 0.95, UV.y));
	}
	// The fan's light shines through the nylon a little on the backlit side.
	BACKLIGHT = cs_out(col * 0.35);
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
