// The pier amusement park (PierPark): every surface of the midway, the rides and their lights on
// ONE shader, the surface kind per vertex in UV2.x (PierMesh.K_*), so a ride or the whole midway
// is one material and one draw:
//   0 paint   1 galvanised metal   2 striped canvas   3 incandescent bulb   4 LED (the wheel)
//   5 back-lit sign face   6 window (lit interior at night)   7 painted boards   8 rubber
//   9 neon   10 chrome   11 gold leaf
// COLOR is the paint in sRGB, decoded here on both renderers (vertex colours arrive raw on both);
// everything is worked in LINEAR and handed back through cs_out() (color_space.gdshaderinc).
//
// `ride` animates a ride in the vertex stage from TIME - nothing on the CPU, so the far copy turns
// too:
//   1 Ferris wheel: the body (UV2.y 0, the LEDs, the bulbs) turns about +Z round `hub` at `omega`;
//     gondola k (UV2.y k + 1) is TRANSLATED with its pivot on the rim, so it hangs plumb, with a
//     slow swing.
//   2 carousel: everything turns about +Y round `hub`; horse k (UV2.y k + 1) rides its pole up and
//     down.
//   3 bumper cars: car k (UV2.y k + 1, modelled at the floor centre, nose +X) runs its own loop
//     over the floor (`floor_half`), turned to its heading.
// Lights follow `lamp_factor` (the street lamps' global): bulbs, signs, neon and windows glow after
// dark; the wheel's LEDs run chasing patterns (radial runs, a rotating sweep, a spiral, a sparkle
// fill), crossfaded every `pattern_seconds`.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

uniform int ride = 0;
uniform vec3 hub = vec3(0.0);
uniform float omega = 0.05;
uniform float count = 1.0;
uniform float radius = 10.0;
uniform vec2 floor_half = vec2(10.0, 8.0);
uniform float spokes = 20.0;
uniform float pattern_seconds = 14.0;
uniform float led_energy = 22.0;
uniform float bulb_energy = 5.0;
uniform float sign_energy = 2.2;
uniform float neon_energy = 6.0;
uniform float window_energy = 1.6;
uniform float stripe_width = 0.55;
uniform float time_offset = 0.0;

varying vec2 v_data;
varying vec3 v_local;

vec3 rot_z(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

vec3 rot_y(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

float h11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	v_data = UV2;
	v_local = VERTEX;
	float t = TIME + time_offset;
	int kind = int(UV2.x + 0.5);
	bool light_kind = kind == 3 || kind == 4;
	float idx = light_kind ? 0.0 : floor(UV2.y + 0.5);
	if (ride == 1) {
		float th = omega * t;
		if (idx >= 1.0) {
			float k = idx - 1.0;
			float a0 = TAU * k / count;
			vec3 p0 = hub + vec3(cos(a0), sin(a0), 0.0) * radius;
			vec3 p1 = hub + vec3(cos(a0 + th), sin(a0 + th), 0.0) * radius;
			// A gondola hangs plumb from its pin; the turn and a breeze rock it a little.
			float sway = 0.035 * sin(t * 0.9 + k * 1.7) + 0.02 * sin(a0 + th);
			VERTEX = p1 + rot_z(VERTEX - p0, sway);
			NORMAL = rot_z(NORMAL, sway);
		} else {
			VERTEX = hub + rot_z(VERTEX - hub, th);
			NORMAL = rot_z(NORMAL, th);
		}
	} else if (ride == 2) {
		float th = omega * t;
		if (idx >= 1.0) {
			float k = idx - 1.0;
			VERTEX.y += 0.24 * sin(t * 2.1 + k * 2.39);
		}
		VERTEX = hub + rot_y(VERTEX - hub, th);
		NORMAL = rot_y(NORMAL, th);
	} else if (ride == 3) {
		if (idx >= 1.0) {
			float k = idx - 1.0;
			float a = 0.21 + 0.13 * h11(k + 1.0);
			float b = 0.17 + 0.15 * h11(k + 7.3);
			float pa = TAU * h11(k + 3.1);
			float pb = TAU * h11(k + 5.7);
			vec2 lim = floor_half - vec2(1.4);
			vec2 p = vec2(sin(a * t + pa) * lim.x, sin(b * t + pb) * lim.y);
			vec2 v = vec2(a * cos(a * t + pa) * lim.x, b * cos(b * t + pb) * lim.y);
			float yaw = atan(-v.y, v.x) + 0.25 * sin(t * 3.0 + k);
			VERTEX = hub + rot_y(VERTEX - hub, yaw) + vec3(p.x, 0.0, p.y);
			NORMAL = rot_y(NORMAL, yaw);
		}
	}
}

// Wheel LED patterns: brightness and colour of an LED at radius r (0..1 of the rim) on spoke s.
vec3 hue(float h) {
	vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return k * k;
}

vec3 led_pattern(int p, float s, float r, float t) {
	float n = spokes;
	if (p == 0) {
		// Runs of light racing out along every spoke, a colour per spoke round the wheel.
		float run = fract(r * 1.6 - t * 0.55);
		float b = smoothstep(0.0, 0.08, run) * smoothstep(0.42, 0.18, run);
		return hue(s / n + t * 0.03) * b;
	} else if (p == 1) {
		// A sweep going round: the spokes light one after another, with a fading tail.
		float a = fract(s / n - t * 0.12);
		float b = pow(1.0 - a, 6.0) + 0.06;
		return mix(vec3(1.0, 0.25, 0.55), vec3(0.3, 0.6, 1.0), r) * b;
	} else if (p == 2) {
		// A spiral: the phase runs round and out together.
		float ph = fract(s / n * 2.0 + r * 1.2 - t * 0.35);
		float b = smoothstep(0.5, 0.0, abs(ph - 0.5) * 2.0 - 0.35);
		return hue(ph * 0.5 + 0.55) * (0.15 + b);
	}
	// The whole wheel in one slow colour with a sparkle running through it.
	float sp = step(0.93, h11(floor(t * 7.0) * 13.1 + s * 3.7 + floor(r * 22.0) * 1.3));
	vec3 base = hue(t * 0.02 + 0.6) * 0.55;
	return base + vec3(1.0) * sp;
}

void fragment() {
	int kind = int(v_data.x + 0.5);
	vec3 paint = cs_srgb_to_linear(COLOR.rgb);
	vec3 alb = paint;
	vec3 emit = vec3(0.0);
	float rough = 0.5;
	float metal = 0.0;
	float spec = 0.5;
	float lit = smoothstep(0.08, 0.6, lamp_factor);
	float t = TIME + time_offset;
	vec2 uv = UV;
	float px = max(length(fwidth(uv)), 1e-4);
	if (kind == 0) {
		rough = 0.42;
	} else if (kind == 1) {
		// Galvanised steel: a dull spangle.
		float sp = h11(floor(uv.x * 9.0) + floor(uv.y * 9.0) * 31.0);
		alb = paint * (0.85 + 0.15 * sp);
		metal = 0.75;
		rough = 0.45;
	} else if (kind == 2) {
		// Canvas: two-colour stripes along u, a seam darkening at each stripe edge, the weave.
		float w = stripe_width;
		float f = fract(uv.x / (2.0 * w));
		float edge = min(abs(f - 0.5), min(f, 1.0 - f)) * 2.0 * w;
		float aa = clamp(px * 0.75, 0.002, 0.5);
		float sel = smoothstep(0.5 - aa / (2.0 * w), 0.5 + aa / (2.0 * w), f);
		vec3 cream = vec3(0.86, 0.82, 0.72);
		alb = mix(paint, cream, sel);
		alb *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.02 + aa, edge));
		float weave = h11(floor(uv.x * 60.0) + floor(uv.y * 60.0) * 17.0);
		alb *= 0.94 + 0.06 * mix(weave, 0.5, clamp(px * 30.0, 0.0, 1.0));
		rough = 0.85;
		// Lit from beneath by the bulbs at night, a little light shows through.
		emit = alb * 0.06 * lit;
	} else if (kind == 3) {
		// A bulb: warm glass by day; at night it burns, the marquee runs chasing in threes.
		alb = mix(paint, vec3(1.0), 0.5) * 0.8;
		rough = 0.15;
		float chase = 0.7 + 0.3 * step(0.5, fract(v_data.y * 0.6 - t * 1.4));
		emit = paint * bulb_energy * lit * chase;
	} else if (kind == 4) {
		// An LED on the wheel: UV.x the distance from the hub, v_data.y the spoke.
		float r01 = clamp(uv.x / max(radius, 1.0), 0.0, 1.2);
		float s = floor(v_data.y + 0.5);
		float cyc = t / pattern_seconds;
		int p0 = int(mod(floor(cyc), 4.0));
		int p1 = int(mod(floor(cyc) + 1.0, 4.0));
		float fade = smoothstep(0.85, 1.0, fract(cyc));
		vec3 c = mix(led_pattern(p0, s, r01, t), led_pattern(p1, s, r01, t), fade);
		// Every LED keeps a faint glow of the wheel's colour, so the whole wheel draws its outline.
		c += hue(t * 0.015 + 0.55) * 0.08;
		// Dots every 0.3 m, averaged once a dot is under a pixel.
		float dot_m = abs(fract(uv.x / 0.3) - 0.5) * 2.0;
		float dots = mix(smoothstep(0.75, 0.35, dot_m), 0.55, clamp(px / 0.3, 0.0, 1.0));
		alb = vec3(0.75);
		rough = 0.3;
		emit = c * led_energy * lit * dots;
	} else if (kind == 5) {
		alb = paint * 0.9;
		rough = 0.35;
		emit = paint * sign_energy * (0.04 + lit);
	} else if (kind == 6) {
		// Window: dark glass; at night the room behind it glows in its own colour, flickering
		// a little (the arcade's screens).
		alb = vec3(0.02, 0.025, 0.03);
		rough = 0.06;
		spec = 0.6;
		float fl = 0.85 + 0.15 * sin(t * 6.0 + uv.x * 3.0) * sin(t * 2.3 + uv.y);
		emit = paint * window_energy * (0.25 + 0.75 * lit) * fl;
	} else if (kind == 7) {
		// Painted boards: a seam every 0.18 m up, each board its own shade.
		float b = floor(uv.y / 0.18);
		float seam = abs(fract(uv.y / 0.18) - 0.5) * 2.0;
		float aa = clamp(px / 0.18, 0.0, 1.0);
		float line = mix(smoothstep(0.82, 0.97, seam), 0.08, aa);
		alb = paint * (0.92 + 0.08 * h11(b)) * (1.0 - 0.45 * line);
		rough = 0.6;
	} else if (kind == 8) {
		alb = vec3(0.025);
		rough = 0.8;
	} else if (kind == 9) {
		alb = paint * 0.6 + 0.3;
		rough = 0.25;
		emit = paint * neon_energy * (0.03 + lit);
	} else if (kind == 10) {
		alb = mix(vec3(0.9), paint, 0.15);
		metal = 1.0;
		rough = 0.12;
	} else {
		alb = vec3(0.95, 0.70, 0.30);
		metal = 1.0;
		rough = 0.28;
	}
	ALBEDO = cs_out(alb);
	EMISSION = cs_out(emit);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
}
