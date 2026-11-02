shader_type spatial;
render_mode cull_back;

// A beach bonfire ring (Bonfires): the precast concrete ring, its ash bed and charred stubs, the
// fresh logs of tonight's fire and a bundle of firewood. What a face is rides in the vertex
// colour's alpha (round(alpha * 8), Bonfires.K_*); UV is metres on the face (u round, v up) and
// UV2.x the height in the mesh. Works in LINEAR on both renderers (color_space.gdshaderinc).
//
// `heat` 1 is the burning stack's material: its coals and the logs' undersides glow, cracked and
// flickering, and the bark chars toward the bottom.

#include "res://shaders/color_space.gdshaderinc"

global uniform float road_wetness;

uniform float heat = 0.0;
// The ring's size (Bonfires.RING_R, RING_WALL, RING_H): where the soot is.
uniform float ring_r = 0.61;
uniform float ring_wall = 0.11;
uniform float ring_h = 0.62;

varying flat float kind;
// The ring's painted number (INSTANCE_CUSTOM.r * 256, Bonfires.ring_number()).
varying flat float num;
varying vec3 lpos;
varying vec3 seed3;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1.0, 0.0));
	float c = h21(i + vec2(0.0, 1.0));
	float d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += vnoise(p) * a;
		p = p * 2.03 + vec2(17.1, 3.7);
		a *= 0.5;
	}
	return s;
}

float seg_d(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Distance (cell units) to a stencilled seven-segment digit in a 1 x 1.6 cell.
float digit_d(vec2 p, int d) {
	int masks[10] = int[](63, 6, 91, 79, 102, 109, 125, 7, 127, 111);
	int m = masks[clamp(d, 0, 9)];
	float r = 1e3;
	if ((m & 1) != 0) r = min(r, seg_d(p, vec2(0.15, 1.5), vec2(0.85, 1.5)));
	if ((m & 2) != 0) r = min(r, seg_d(p, vec2(0.9, 1.45), vec2(0.9, 0.85)));
	if ((m & 4) != 0) r = min(r, seg_d(p, vec2(0.9, 0.75), vec2(0.9, 0.15)));
	if ((m & 8) != 0) r = min(r, seg_d(p, vec2(0.15, 0.1), vec2(0.85, 0.1)));
	if ((m & 16) != 0) r = min(r, seg_d(p, vec2(0.1, 0.75), vec2(0.1, 0.15)));
	if ((m & 32) != 0) r = min(r, seg_d(p, vec2(0.1, 1.45), vec2(0.1, 0.85)));
	if ((m & 64) != 0) r = min(r, seg_d(p, vec2(0.15, 0.8), vec2(0.85, 0.8)));
	return r;
}

void vertex() {
	kind = round(COLOR.a * 8.0);
	num = round(INSTANCE_CUSTOM.r * 256.0);
	lpos = VERTEX;
	seed3 = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec3 albedo;
	float rough = 0.9;
	vec3 emit = vec3(0.0);
	float sd = h21(seed3.xz * 0.37 + seed3.y);
	vec2 uvm = UV;
	float r = length(lpos.xz);
	float px = length(fwidth(lpos)) + 1e-4;
	if (kind < 0.5) {
		// Concrete: a weathered precast grey, aggregate speckle (faded under a pixel), blotches.
		vec2 q = vec2(atan(lpos.z, lpos.x) * ring_r, lpos.y);
		float blot = fbm(q * 3.1 + sd * 40.0);
		float spk = h21(floor(q * 260.0) + sd * 91.0);
		float spk_vis = 1.0 - smoothstep(0.003, 0.012, px);
		vec3 grey = vec3(0.33, 0.305, 0.27) * (0.78 + 0.42 * blot);
		grey *= mix(1.0, 0.82 + 0.36 * spk, spk_vis);
		// Soot: black inside, over the rim toward the inner edge, and in streaks down the outside
		// where the smoke rolled over it.
		float inside = 1.0 - smoothstep(ring_r - ring_wall + 0.004, ring_r - ring_wall + 0.03, r);
		float rim = smoothstep(ring_h - 0.03, ring_h, lpos.y) * (1.0 - smoothstep(ring_r - ring_wall, ring_r - 0.01, r));
		float streak = smoothstep(0.45, 0.85, fbm(vec2(q.x * 7.0, q.y * 0.9) + sd * 13.0));
		float down = smoothstep(ring_h * 0.25, ring_h, lpos.y) * smoothstep(ring_r - 0.012, ring_r, r);
		float soot = max(inside * (0.75 + 0.25 * blot), max(rim * 0.85, streak * down * 0.7));
		soot = max(soot, 0.25 * smoothstep(ring_h - 0.12, ring_h, lpos.y) * (0.6 + 0.4 * blot));
		// Long faint stains down the outside where years of smoke rolled over the rim.
		float drip = smoothstep(0.55, 0.9, vnoise(vec2(q.x * 11.0 + sd * 7.0, 0.5))) * smoothstep(0.05, ring_h, lpos.y);
		soot = max(soot, drip * 0.35 * smoothstep(ring_r - 0.012, ring_r, r));
		albedo = mix(grey, vec3(0.018, 0.016, 0.015), soot);
		// The ring's number, stencilled in white on two sides, half worn away.
		float outer = smoothstep(ring_r - 0.012, ring_r - 0.002, r) * (1.0 - smoothstep(ring_h - 0.05, ring_h - 0.03, lpos.y));
		if (outer > 0.0 && num > 0.5) {
			float ang = atan(lpos.z, lpos.x);
			float side = abs(ang) < 1.5708 ? ang : (ang > 0.0 ? ang - 3.14159 : ang + 3.14159);
			// Read from outside the ring: u runs the other way round to the angle.
			vec2 g = vec2(-side * ring_r / 0.105 + 1.08, (lpos.y - 0.24) / 0.105);
			int n = int(num);
			float dd = 1e3;
			if (g.x > -0.2 && g.x < 2.4 && g.y > -0.2 && g.y < 1.8) {
				if (n >= 10) {
					dd = min(digit_d(g, n / 10), digit_d(g - vec2(1.25, 0.0), n % 10));
				} else {
					dd = digit_d(g - vec2(0.62, 0.0), n);
				}
			}
			float spray = 1.0 - smoothstep(0.1, 0.17 + 0.05 * blot, dd);
			spray *= smoothstep(0.25, 0.55, fbm(q * 18.0 + sd * 3.0) + 0.3);
			albedo = mix(albedo, vec3(0.62, 0.61, 0.57), spray * outer * 0.85);
		}
		// Sand blown against the foot, and the wet line after rain.
		float sand = 1.0 - smoothstep(0.0, 0.14 + 0.06 * blot, lpos.y);
		albedo = mix(albedo, vec3(0.42, 0.34, 0.24), sand * 0.7 * (1.0 - inside));
		albedo *= 1.0 - 0.35 * road_wetness * (1.0 - inside);
		rough = mix(0.86, 0.97, soot) - 0.3 * road_wetness;
	} else if (kind < 1.5) {
		// Ash: pale grey powder, charcoal bits through it, darker toward the middle.
		float n = fbm(lpos.xz * 9.0 + sd * 20.0);
		float bits = step(0.72, h21(floor(lpos.xz * 70.0) + sd * 7.0)) * (1.0 - smoothstep(0.004, 0.02, px));
		albedo = mix(vec3(0.24, 0.23, 0.22), vec3(0.05, 0.045, 0.04), smoothstep(0.35, 0.0, r) * 0.6 + n * 0.35);
		albedo = mix(albedo, vec3(0.02), bits * 0.8);
		rough = 0.98;
		// Under a live fire the bed glows in the middle.
		float glow = heat * (1.0 - smoothstep(0.08, 0.36, r)) * smoothstep(0.35, 0.75, n);
		emit = vec3(1.0, 0.32, 0.05) * glow * 1.6;
	} else if (kind < 2.5) {
		// Char: black, cracked into scales (alligatored charcoal).
		vec2 c = uvm * vec2(22.0, 14.0);
		vec2 cell = fract(c) - 0.5;
		float crack = 1.0 - smoothstep(0.32, 0.47, max(abs(cell.x), abs(cell.y)));
		float n = vnoise(c * 0.5 + sd * 3.0);
		albedo = vec3(0.028, 0.025, 0.023) * (0.7 + 0.6 * n);
		rough = 0.82;
		if (heat > 0.5) {
			float t = TIME * 1.7 + sd * 30.0 + lpos.x * 5.0;
			float flick = 0.65 + 0.2 * sin(t) + 0.15 * sin(t * 3.7 + n * 6.0);
			float low = 1.0 - smoothstep(0.17, 0.42, lpos.y);
			emit = vec3(1.0, 0.3, 0.04) * (1.0 - crack) * low * flick * 2.6;
		}
	} else if (kind < 3.5) {
		// Tonight's logs: bark, charring from the bottom up as the fire takes them, the cracks
		// glowing where the flames are.
		float n = fbm(vec2(uvm.x * 18.0, uvm.y * 3.0) + sd * 9.0);
		vec3 bark = vec3(0.13, 0.085, 0.05) * (0.6 + 0.7 * n);
		float charred = heat * (1.0 - smoothstep(0.22, 0.55 + 0.15 * n, lpos.y));
		vec2 c = uvm * vec2(24.0, 12.0);
		vec2 cell = fract(c) - 0.5;
		float crack = 1.0 - smoothstep(0.3, 0.46, max(abs(cell.x), abs(cell.y)));
		albedo = mix(bark, vec3(0.025, 0.022, 0.02), charred);
		rough = 0.9;
		float t = TIME * 2.1 + sd * 30.0 + lpos.y * 7.0;
		float flick = 0.6 + 0.25 * sin(t) + 0.15 * sin(t * 4.3 + n * 5.0);
		emit = vec3(1.0, 0.34, 0.05) * charred * (1.0 - crack) * flick * 2.2 * (1.0 - smoothstep(0.2, 0.5, lpos.y));
	} else if (kind < 4.5) {
		// Firewood bark: grey-brown, ridged along the log.
		float n = fbm(vec2(uvm.x * 22.0, uvm.y * 2.5) + sd * 5.0);
		albedo = vec3(0.17, 0.12, 0.08) * (0.55 + 0.75 * n);
		rough = 0.92;
	} else {
		// A cut end: pale wood with its rings and a check or two.
		float rr = length(uvm - 0.5) * 2.0;
		float rings = 0.5 + 0.5 * sin(rr * 38.0 + vnoise(uvm * 6.0) * 4.0);
		albedo = mix(vec3(0.5, 0.36, 0.22), vec3(0.38, 0.25, 0.14), rings * (1.0 - smoothstep(0.004, 0.015, px)) * 0.6);
		albedo = mix(albedo, vec3(0.12, 0.08, 0.05), smoothstep(0.86, 1.0, rr));
		// A burning stack's ends glow at the bottom.
		float low = 1.0 - smoothstep(0.2, 0.45, lpos.y);
		albedo = mix(albedo, vec3(0.03), heat * low);
		emit = vec3(1.0, 0.33, 0.05) * heat * low * 1.4 * (0.7 + 0.3 * sin(TIME * 2.3 + sd * 20.0));
		rough = 0.85;
	}
	ALBEDO = cs_out(albedo);
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	EMISSION = cs_out(emit);
}
