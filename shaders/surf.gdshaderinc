// The breaking surf, shared by the ocean (shaders/ocean.gdshader: the waves themselves and their
// whitewater), the sand (shaders/beach_sand.gdshader: the swash that runs up it and drains back)
// and the spray off the breakers (shaders/surf_spray.gdshader). All three have to agree about
// where every wave is at every instant - a swash that does not start the moment its bore reaches
// the sand reads as two animations laid over each other - so the model is written once, here,
// and driven by the same shader TIME and the same globals. scripts/world/surf.gd is the same
// model in GDScript (Surf), which is where Weather works out the globals and what the smoke test
// checks; change one, change both.
//
// The model. Waves come in toward the shore as a train of crests parallel to it. A point is
// described by `s`, its distance offshore from the waterline (the ocean shader's shore_distance,
// the sand's own metres up the beach as a negative), and the phase
//     phi = TAU * ((s + wob(p)) / L + t / T)
// so crests sit where phi / TAU is a whole number and walk toward the sand at L / T metres a
// second; `wob` bends the crests along the shore so they never read as ruled lines. Wave n is
// the crest at phi = n * TAU. Each wave has its own height (sets of bigger ones, quieter gaps,
// sections along the shore) and so its own break point: a wave stands up as it comes in,
// steepens, throws a lip at `break`, and runs on to the sand as a bore that shrinks to nothing
// at the waterline. The bore that arrives starts the swash: a sheet of water up the sand to the
// wave's run-up, and back.
//
// Globals (Weather._push_surf(), from Surf.params(wave_scale) - the weather, so a storm's surf
// is three metres and breaks a hundred metres out):
//   surf_shape = (face height m, crest spacing m, period s, break distance m)
//   surf_extra = (run-up m, lip throw (fraction of height), surf zone width m, swash length (periods))
global uniform vec4 surf_shape;
global uniform vec4 surf_extra;
// The water review (WaterReview, WATER_REVIEW=0 the A/B: 0 draws the foam, swash, shallows and night
// mirror as they were before it).
global uniform float water_review;

const float SURF_H_LO = 0.62;
const float SURF_H_SPAN = 0.68;


float surf_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float surf_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(surf_hash(i), surf_hash(i + vec2(1.0, 0.0)), f.x),
		mix(surf_hash(i + vec2(0.0, 1.0)), surf_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}


vec2 surf_hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}


// Worley F1 and F2 (cell units): the nearest and the second-nearest of a jittered grid of points.
vec2 surf_worley2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = surf_hash22(i + g) * 0.86 + 0.07;
			float d = length(g + o - f);
			d2 = d < d1 ? d1 : min(d2, d);
			d1 = min(d1, d);
		}
	}
	return vec2(d1, d2);
}


// Churned foam (water-review; the ocean's whitewater and old foam, the swash's lace): coverage
// 0..1 at `p` (the caller's own foam frame, about half a metre a unit), `age` 0 fresh (solid) .. 1
// old (threads and islands), `px` a pixel's size in those units. A warped four-octave noise cut at
// a threshold that rises with age, so the holes come in every size, merge and split and the foam
// between them runs in streaks and islands - not the round, evenly spaced dots a threshold on Worley
// F1 gives (the old nets read as rows of polka dots from the beach), nor thin noise contours (the
// swash's old web read as white spaghetti). The finer octaves and the bubble walls only where they
// span a pixel or two; under that the cut is its average.
float surf_foam(vec2 p, float age, float px) {
	float pch = surf_noise(p * 0.07 + 3.0);
	vec2 warp = vec2(surf_noise(p * 0.23 + 1.3), surf_noise(p * 0.23 + 8.1)) - 0.5;
	vec2 q = p + warp * 3.0;
	float f = surf_noise(q * 0.31) * 0.47 + surf_noise(q * 0.77 + 5.2) * 0.29;
	float k2 = 1.0 - smoothstep(0.5, 1.4, px);
	float k3 = 1.0 - smoothstep(0.2, 0.6, px);
	f += mix(0.5, surf_noise(q * 1.9 + 9.7), k2) * 0.16 + mix(0.5, surf_noise(q * 4.3 + 2.4), k3) * 0.08;
	float th = mix(0.18, 0.62, age) + (pch - 0.5) * 0.28;
	float soft = 0.035 + 0.12 * smoothstep(0.2, 2.5, px);
	float cov = smoothstep(th - soft, th + soft, f);
	// The bubbles inside it: faint walls round darker cells, more open as the foam ages.
	if (k3 > 0.01) {
		vec2 c = surf_worley2(q * 1.7);
		float walls = 1.0 - smoothstep(0.0, 0.08 + 0.06 * (1.0 - age), c.y - c.x);
		cov *= mix(1.0, 0.78 + 0.22 * walls, (0.2 + 0.5 * age) * k3);
	}
	return clamp(cov, 0.0, 1.0);
}


// Caustics on a sandy floor at true-world `fw` (water-review): the light the ripples on the
// surface focus into a drifting net of bright lines - two Voronoi edge fields, crossed - sharp under
// a few centimetres of water, softer and wider with `depth` (metres). 0..~1.2; under a few pixels
// (`px` metres a pixel) the net is its average.
float surf_caustic(vec2 fw, float depth, float px, float t) {
	float cs = 0.7 + 0.3 * clamp(depth, 0.0, 2.0);
	vec2 q = fw / cs;
	// A strong slow warp rounds the cells and bends their edges, as the swell's lens does.
	vec2 warp = vec2(surf_noise(q * 0.45 + t * 0.19), surf_noise(q * 0.45 + 4.0 - t * 0.15)) - 0.5;
	vec2 a = surf_worley2(q + warp * 2.2 + vec2(t * 0.27, t * 0.11));
	vec2 b = surf_worley2(q * 1.31 + warp * 2.8 - vec2(t * 0.19, t * 0.24) + 7.0);
	float soft0 = 0.10 + 0.14 * clamp(depth, 0.0, 2.5);
	// A line is never drawn thinner than a few pixels (seen at a grazing angle a thin core aliased
	// into dotted rows down the beach): widened past that, and dimmed by as much, so it keeps its
	// energy as it blurs into the average.
	float soft = max(soft0, 2.5 * px / cs);
	float keep = soft0 / soft;
	// Thin bright cores fading out to the cell (a power of the edge distance, not a step).
	float la = pow(1.0 - clamp((a.y - a.x) / soft, 0.0, 1.0), 3.0) * keep;
	float lb = pow(1.0 - clamp((b.y - b.x) / soft, 0.0, 1.0), 3.0) * keep;
	// Brightest where the two nets cross; patchy, as the focusing comes and goes with the swell.
	float lines = (la * 0.55 + lb * 0.45) * (0.7 + 0.6 * la * lb / max(keep, 0.05));
	lines *= 0.35 + 0.9 * smoothstep(0.3, 0.75, surf_noise(fw * 0.23 + t * 0.05 + 2.0));
	return mix(lines, 0.12, smoothstep(cs * 0.05, cs * 0.25, px));
}


// How far (metres) the crests are bent along the shore at true-world XZ p.
float surf_wob(vec2 p) {
	return 9.0 * (surf_noise(p / 95.0) - 0.5) + 4.0 * (surf_noise(p / 33.0 + 7.3) - 0.5);
}


// Phase at true-world p, `s` metres offshore, time t (seconds).
float surf_phase(vec2 p, float s, float t) {
	return TAU * ((s + surf_wob(p)) / max(surf_shape.y, 1.0) + t / max(surf_shape.z, 0.5));
}


// Wave n's height as a share of surf_shape.x: sets of three or four bigger waves with smaller
// ones between, and sections along the shore where the bottom is shallower and the waves stand
// up more. Continuous in p, so one wave is one wave all along its crest.
float surf_wave_gain(float n, vec2 p) {
	float sets = 0.5 + 0.5 * sin(n * 0.85 + surf_noise(p / 400.0) * 3.0);
	float wave = surf_hash(vec2(n, 17.0));
	float section = surf_noise(p / 70.0 + vec2(n * 0.61, n * 0.23));
	return SURF_H_LO + SURF_H_SPAN * (0.40 * sets + 0.25 * wave + 0.35 * section);
}


// A wave's profile through one period, u = 0 at its crest and growing seaward (the back face),
// with the steep front face last, just landward of the next crest. 0 in the trough, 1 at the
// crest. `steep` 0 is a rolling swell, 1 a breaking face.
float surf_profile(float u, float steep) {
	float wf = mix(0.40, 0.13, steep);
	if (u > 1.0 - wf) {
		float v = (u - (1.0 - wf)) / wf;
		return pow(v, mix(1.6, 2.6, steep));
	}
	float v = u / (1.0 - wf);
	return (1.0 - v) * (1.0 - v);
}


// Height envelope of a wave of gain g at `s` metres offshore: 0 offshore of the surf zone,
// rising to its full face at its break point, collapsing into a bore that runs out to nothing
// at the waterline. `sig` is s over that wave's break point (1 = breaking now, < 1 broken).
float surf_envelope(float s, float g, out float sig, out float steep) {
	float brk = max(surf_shape.w * pow(g, 0.8), 2.0);
	sig = s / brk;
	float start = max(surf_extra.z, brk * 1.4);
	steep = 1.0 - smoothstep(1.0, 1.9, sig);
	float rise = 1.0 - smoothstep(1.0, start / brk, sig);
	float unbroken = rise * rise * (0.55 + 0.45 * steep);
	float bore = 0.5 * sqrt(max(sig, 0.0)) + 0.5 * smoothstep(0.80, 1.0, sig);
	float env = sig >= 1.0 ? unbroken : bore;
	// Flat for the last few metres: the water plane meets the sand there, and any height left in
	// it saws their intersection into teeth along the 1 m mesh. The whitewater (painted) and the
	// swash on the sand carry the motion over that last stretch instead.
	return env * smoothstep(3.0, 10.0, s);
}


// The surf at true-world p, s metres offshore, time t. Returns the height above the mean water
// (metres) and in `lip` the throw of the crest toward the land; `u` is the phase within the
// period (0 crest, rising seaward), `sig` / `steep` / `g` are those of the wave the point
// belongs to.
// `phi` is surf_phase() / TAU (so the fragment shader can pass the interpolated phase in).
float surf_height_at(vec2 p, float s, float phi, out float lip, out float u, out float sig,
		out float steep, out float g) {
	float n = floor(phi);
	u = phi - n;
	float h0 = surf_shape.x;
	// The profile's steepness comes from the mean wave, so where the trough is does not depend
	// on which wave a point belongs to: the front face belongs to the next crest (n + 1, seaward
	// of it), the back face to this one, and the switch is exactly in the trough, where the
	// profile is 0 - so two waves of different heights still meet without a step.
	float mean_sig;
	float mean_env = surf_envelope(s, 1.0, mean_sig, steep);
	float wf = mix(0.40, 0.13, steep);
	float nw = u > 1.0 - wf ? n + 1.0 : n;
	g = surf_wave_gain(nw, p);
	float wave_steep;
	float env = surf_envelope(s, g, sig, wave_steep);
	float shape = surf_profile(u, steep);
	// The lip: the top of the face thrown forward over the trough in front of it, strongest at
	// the break and gone once it is a bore.
	float at_break = smoothstep(0.80, 1.0, sig) * (1.0 - smoothstep(1.0, 1.25, sig));
	float face = u > 0.70 ? smoothstep(0.70, 1.0, u) : smoothstep(0.12, 0.0, u);
	lip = surf_extra.y * h0 * g * at_break * face * smoothstep(0.35, 1.0, shape);
	// Never thrown further than the face is wide: past that the mesh folds through itself and
	// a far break line is drawn as a row of torn rectangles.
	lip = min(lip, 0.35 * wf * max(surf_shape.y, 1.0));
	// Mean level is held: the troughs sit a fifth of the mean face under it.
	return h0 * (g * env * shape - 0.22 * mean_env);
}


float surf_height(vec2 p, float s, float t, out float lip, out float u, out float sig,
		out float steep, out float g) {
	return surf_height_at(p, s, surf_phase(p, s, t) / TAU, lip, u, sig, steep, g);
}


// The swash on the sand `up` metres landward of the waterline at true-world p (on the shore),
// time t. Returns the sheet's depth share (0 dry, 1 deep at the waterline), and in `front` how
// near this point is to the moving edge (the foam lace), in `wet` how recently the water left
// it (1 now, falling over a few seconds) and in `rush` +1 while the water runs up and -1 while it
// drains.
float surf_swash(vec2 p, float up, float t, out float front, out float wet, out float rush) {
	float T = max(surf_shape.z, 0.5);
	float phi = surf_phase(p, 0.0, t) / TAU;
	float n = floor(phi);
	float sheet = 0.0;
	front = 0.0;
	wet = 0.0;
	rush = 0.0;
	float len = max(surf_extra.w, 0.5);
	// The three latest arrivals: a swash outlasts one period, so the next one runs up over the
	// last one's backwash, and the sand an older one wetted is still drying.
	for (int k = 0; k < 3; k++) {
		float nk = n - float(k);
		float x = (phi - nk) / len;
		float g = surf_wave_gain(nk, p);
		float reach = surf_extra.x * g * g;
		// Fast up, slower down: a thrown sheet slowing on the slope, then the drain.
		float r = x < 1.0 ? reach * sin(PI * pow(x, 0.62)) : 0.0;
		float d = r - up;
		if (d > 0.0) {
			float depth = clamp(d / max(reach * 0.55, 0.5), 0.0, 1.0);
			if (depth > sheet) {
				sheet = depth;
				rush = x < 0.327 ? 1.0 : -1.0;
			}
			// 1 at the edge, falling to 0 three metres behind it: the foam line and the web of
			// bubbles it trails.
			front = max(front, 1.0 - smoothstep(0.0, 2.0 + 1.0 * g, d));
			wet = 1.0;
		} else if (up < reach && x > 0.327) {
			// Uncovered on the way back down: when did the edge pass here?
			float xo = pow(1.0 - asin(clamp(up / reach, 0.0, 1.0)) / PI, 1.0 / 0.62);
			float since = max(x - xo, 0.0) * len * T;
			wet = max(wet, exp(-since / 4.5));
		}
	}
	return sheet;
}
