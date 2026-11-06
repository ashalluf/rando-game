// The beach as a postcard (BeachGolden, scripts/world/beach_golden.gd): what a low sun picks out
// on real sand, worked out per pixel on the sand's own coordinates (true world metres, so it runs
// on across chunks and never moves with an origin shift). Included by beach_sand.gdshader only;
// every function returns 0 when `golden_on` is 0 (BEACH_GOLDEN=0, the A/B).
//
// * Wind ripples: the onshore wind (from the sea, -x, toward the town, +x) combs dry sand into
//   ripples 9-15 cm apart, crests running along the shore, the gentle slope to windward and the
//   steep one to lee, bending and forking where a slow warp field turns them. Only on the dry
//   upper beach, patchy (trampled ground has none), faded to flat once a ripple is under a pixel.
// * Hummocks: the wind's and the walkers' coarser relief, 0.6-3 m across and a few cm high, on
//   every dry metre; it is what gives the sand texture a surface to lie on at a grazing sun.
// * Footprints: trails of prints walked down to the water (bands along the shore, each with one
//   wandering line of left / right prints at a 0.72 m stride (bands of 5 m)) and along the wet sand near the
//   water. Each print is a heel and a toe dent with the displaced sand heaped round it, softened
//   with age on the dry sand, crisp and holding water on the wet. Under a pixel a trail is its
//   average, a faint darker trodden line.
// * The wrack line: kelp, shell grit and drift at the high-tide line (the swash's top), a ragged
//   band of dark speckle; and quartz glints, single grains catching the sun.
//
// Height fields return (dh/dx, dh/dz, h); the caller turns the slope into its normal map.

uniform float golden_on = 1.0;
// Ripples: amplitude (m), wavelength range (m).
uniform float ripple_amp = 0.003;
uniform vec2 ripple_wave = vec2(0.09, 0.15);
// Hummocks: amplitude (m).
uniform float hummock_amp = 0.05;
// Footprints: depth (m) on the dry sand, how many bands (of 5 m along the shore) carry a trail.
uniform float print_depth = 0.014;
uniform float print_share = 0.5;
// Quartz glints: how bright and how many.
uniform float glint_gain = 6.0;
uniform float glint_share = 0.06;


float bg_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float bg_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(bg_hash(i), bg_hash(i + vec2(1.0, 0.0)), u.x),
		mix(bg_hash(i + vec2(0.0, 1.0)), bg_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}


// A value noise with its gradient (returns gradient.xy, value).
vec3 bg_noise_d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = bg_hash(i);
	float b = bg_hash(i + vec2(1.0, 0.0));
	float c = bg_hash(i + vec2(0.0, 1.0));
	float d = bg_hash(i + vec2(1.0, 1.0));
	float v = a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y;
	vec2 g = du * vec2(b - a + (a - b - c + d) * u.y, c - a + (a - b - c + d) * u.x);
	return vec3(g, v);
}


// Wind ripples at true world `p`; `px` is metres per pixel there. `dry` 0..1 says how dry and
// loose the sand is.
vec3 bg_ripples(vec2 p, float px, float dry) {
	if (golden_on < 0.5 || dry < 0.01) {
		return vec3(0.0);
	}
	float lam = mix(ripple_wave.x, ripple_wave.y, bg_noise(p * 0.07 + 3.1));
	float fade = 1.0 - smoothstep(0.02, 0.06, px / lam);
	if (fade < 0.001) {
		return vec3(0.0);
	}
	// The warp turns the crests (a slow field) and the patch says where they are at all.
	vec3 w1 = bg_noise_d(p * 0.35);
	vec3 w2 = bg_noise_d(p * 1.3 + 7.7);
	float s = p.x + (w1.z - 0.5) * 1.6 + (w2.z - 0.5) * 0.18;
	vec2 ds = vec2(1.0, 0.0) + w1.xy * 0.35 * 1.6 + w2.xy * 1.3 * 0.18;
	float ph = fract(s / lam);
	// Asymmetric profile: rises over 70 % of the wavelength (to windward), falls over 30 %.
	float k = 0.62;
	float h;
	float dh;
	if (ph < k) {
		float t = ph / k;
		h = t * t * (3.0 - 2.0 * t);
		dh = 6.0 * t * (1.0 - t) / k;
	} else {
		float t = (ph - k) / (1.0 - k);
		h = 1.0 - t * t * (3.0 - 2.0 * t);
		dh = -6.0 * t * (1.0 - t) / (1.0 - k);
	}
	float patch_v = smoothstep(0.42, 0.72, bg_noise(p * 0.11 + 11.0)) * (0.6 + 0.4 * bg_noise(p * 0.6 + 4.0));
	float a = ripple_amp * fade * dry * patch_v;
	return vec3(ds * (dh / lam) * a, (h - 0.5) * a);
}


// Value noise at frequency `f` in a domain turned by `R`, with its gradient in the unturned one.
// Turning each octave matters: a value noise's gradient carries its lattice's axes, and laid in
// the world's axes those read as fine streaks along x and z (a corduroy) at a grazing sun.
vec3 bg_noise_rot(vec2 p, float f, mat2 R) {
	vec3 n = bg_noise_d(R * p * f);
	return vec3(transpose(R) * n.xy * f, n.z);
}


// Coarser relief: hummocks and wind scour, everywhere on the dry sand.
vec3 bg_hummocks(vec2 p, float px, float dry) {
	if (golden_on < 0.5) {
		return vec3(0.0);
	}
	vec3 a = bg_noise_rot(p, 0.33, mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80)));
	vec3 b = bg_noise_rot(p + 5.3, 1.1, mat2(vec2(0.28, -0.96), vec2(0.96, 0.28)));
	float fb = 1.0 - smoothstep(0.15, 0.4, px);
	vec3 r = a + b * 0.4 * fb;
	return r * hummock_amp * mix(0.35, 1.0, dry);
}


// One print in a print's own frame (u along the walk, v across, metres): a heel and a toe dent,
// the sand pushed out round them. Returns (dh/du, dh/dv, h) for a depth of 1.
vec3 bg_print(vec2 q) {
	vec3 r = vec3(0.0);
	// heel at u -0.07, toe at u +0.06 (the ball, wider and a little to the inside).
	for (int k = 0; k < 2; k++) {
		vec2 c = k == 0 ? vec2(-0.07, 0.0) : vec2(0.06, 0.008);
		vec2 rad = k == 0 ? vec2(0.055, 0.04) : vec2(0.07, 0.048);
		vec2 d = (q - c) / rad;
		float rr = dot(d, d);
		if (rr < 2.6) {
			// A dent of depth 1 inside rr 1, a rim of +0.25 round it at rr ~1.4.
			float hd = -exp(-rr * 1.6) + 0.28 * exp(-pow(rr - 1.45, 2.0) * 4.0);
			float g = 1.6 * exp(-rr * 1.6) - 0.28 * 8.0 * (rr - 1.45) * exp(-pow(rr - 1.45, 2.0) * 4.0);
			vec2 drr = 2.0 * d / rad;
			r += vec3(g * drr, hd);
		}
	}
	return r;
}


// Trails of footprints at true world `p`. `wet` 0..1 (crisp prints in damp sand), `keep` 0..1
// (0 where the swash has washed them out). Returns (dh/dx, dh/dz, h) and in `trod` the average
// a trail leaves once its prints are under a pixel.
vec3 bg_footprints(vec2 p, float px, float wet, float keep, out float trod) {
	trod = 0.0;
	if (golden_on < 0.5 || keep < 0.01) {
		return vec3(0.0);
	}
	vec3 r = vec3(0.0);
	float fade = 1.0 - smoothstep(0.03, 0.08, px);
	float depth = print_depth * mix(0.75, 1.15, wet) * keep;
	// Family A: down the beach to the water, one trail per 5 m band along the shore.
	float band = floor(p.y / 5.0);
	for (int i = -1; i <= 1; i++) {
		float b = band + float(i);
		if (bg_hash(vec2(b, 4.2)) > print_share) {
			continue;
		}
		float h2 = bg_hash(vec2(b, 9.7));
		float h3 = bg_hash(vec2(b, 1.3));
		float zc = (b + 0.2 + 0.6 * h2) * 5.0 + 2.2 * sin(p.x * 0.06 + h3 * 6.28) + 0.8 * sin(p.x * 0.19 + h2 * 6.28) + 0.25 * sin(p.x * 0.7 + h3 * 3.0);
		float d = p.y - zc;
		if (abs(d) > 0.4) {
			continue;
		}
		float age = 0.35 + 0.65 * bg_hash(vec2(b, 2.9));
		float stride = 0.36 * (0.9 + 0.2 * h3);
		float kk = floor(p.x / stride);
		float side = mod(kk, 2.0) < 0.5 ? -1.0 : 1.0;
		float jit = (bg_hash(vec2(kk, b)) - 0.5) * 0.05;
		vec2 q = vec2(p.x - (kk + 0.5) * stride, d - side * 0.09 - jit);
		// The walk heads for the water (-x), so the toe is at -u.
		vec3 pr = bg_print(vec2(-q.x, q.y));
		pr.x = -pr.x;
		float gap = smoothstep(0.3, 0.55, bg_noise(vec2(p.x * 0.12, b * 3.1)));
		float soft = mix(age, 1.0, wet) * gap;
		r += pr * soft;
		trod = max(trod, (1.0 - smoothstep(0.1, 0.25, abs(d))) * 0.6 * soft);
	}
	// Family B: along the wet sand, a few walkers' lines a band apart across the shore.
	float bx = floor(p.x / 9.0);
	for (int i = -1; i <= 1; i++) {
		float b = bx + float(i);
		if (bg_hash(vec2(b, 17.3)) > 0.3) {
			continue;
		}
		float h2 = bg_hash(vec2(b, 5.1));
		float xc = (b + 0.2 + 0.6 * h2) * 9.0 + 1.2 * sin(p.y * 0.05 + h2 * 6.28) + 0.4 * sin(p.y * 0.17);
		float d = p.x - xc;
		if (abs(d) > 0.4) {
			continue;
		}
		float stride = 0.37;
		float kk = floor(p.y / stride);
		float side = mod(kk, 2.0) < 0.5 ? -1.0 : 1.0;
		vec2 q = vec2(p.y - (kk + 0.5) * stride, d - side * 0.09);
		vec3 pr = bg_print(q);
		// Frame (u along z, v along x) back to (x, z).
		float soft = mix(0.5, 1.0, wet) * smoothstep(0.3, 0.55, bg_noise(vec2(p.y * 0.1, b * 2.3)));
		r += vec3(pr.y, pr.x, pr.z) * soft;
		trod = max(trod, (1.0 - smoothstep(0.1, 0.25, abs(d))) * 0.6 * soft);
	}
	trod *= keep * (1.0 - fade);
	return r * depth * fade;
}


// The wrack line: kelp and shell grit along the top of the swash. `up` is metres landward of the
// waterline, `top` where the swash tops out. Returns how much wrack covers the pixel (0..1).
float bg_wrack(vec2 p, float up, float top, float px) {
	if (golden_on < 0.5) {
		return 0.0;
	}
	float wander = (bg_noise(vec2(p.y * 0.06, 2.0)) - 0.5) * 3.0;
	float d = abs(up - top - 1.0 - wander);
	float band = 1.0 - smoothstep(0.3, 1.4 + 0.8 * bg_noise(vec2(p.y * 0.3, 7.0)), d);
	if (band < 0.01) {
		return 0.0;
	}
	float clumps = smoothstep(0.55, 0.8, bg_noise(p * vec2(1.4, 0.5)));
	float fine = smoothstep(0.6, 0.75, bg_noise(p * 9.0 + 3.0));
	float f = 1.0 - smoothstep(0.02, 0.1, px);
	return band * max(clumps * 0.9, mix(0.18, fine, f) * 0.6) * mix(0.6, 1.0, bg_noise(vec2(p.y * 0.04, 5.0)));
}


// Quartz and shell glints: grains whose facets mirror the sun into the eye. Returns a brightness.
float bg_glint(vec2 p, vec3 view_dir, vec3 sun_n, float px, float dry) {
	if (golden_on < 0.5 || sun_n.y < -0.02) {
		return 0.0;
	}
	float f = 1.0 - smoothstep(0.004, 0.02, px);
	if (f < 0.001) {
		return 0.0;
	}
	vec2 cell = floor(p / 0.012);
	float h = bg_hash(cell);
	if (h > glint_share) {
		return 0.0;
	}
	// A facet's normal: tilted from up by up to ~40 degrees in a hashed direction.
	float a = bg_hash(cell + 3.7) * 6.2831853;
	float t = bg_hash(cell + 9.1) * 0.7;
	vec3 n = normalize(vec3(cos(a) * t, 1.0, sin(a) * t));
	vec3 refl = reflect(view_dir, n);
	float g = pow(max(dot(refl, sun_n), 0.0), 900.0);
	return g * glint_gain * f * dry;
}
