// The Pacific close up (ocean.gdshader includes this; OceanCloseup, scripts/world/ocean_closeup.gd,
// pushes the uniforms). Everything here is FRAGMENT-only and faded out with `detail` before the
// hand-over to the far plane, so the vertex stage (and SeaSurface, its GDScript mirror) and the far
// sea are untouched. `closeup` 0 is the A/B (OCEAN_CLOSEUP=0): the water as it was.
//
//   - capillary ripples: a third, wind-aligned ripple octave a few centimetres across, faded by the
//     pixel's own footprint (never by a guessed distance), so it is there under the pier and gone
//     before it aliases;
//   - wind streaks: long glassy slicks running down the wind where the chop lies flat, and gust
//     patches ("cat's paws") where it is rougher - the two things that make open water read as
//     water under wind rather than a noise field;
//   - the sun glitter as separate sparkles: cells of a few centimetres, each a facet with its own
//     tilt and a short life, flashing only when its tilt mirrors the sun into the eye; faded to the
//     statistical glint the old pow() lobe already draws once a cell is under a pixel or two;
//   - foam that ages: bubble cells (Worley) that open into holes and lace as the foam gets older,
//     and the wind tearing it into streaks downwind of a crest;
//   - the piles: foam and wet churn round every pile of the piers (pile grids, below).
//
// Colour: plain uniforms written LINEAR (color_space.gdshaderinc rules), emitted or albedo as the
// ocean shader hands them on.

// OCEAN_CLOSEUP=0 sets this global to 0 (OceanCloseup.apply()).
global uniform float ocean_closeup;
#define closeup ocean_closeup
// Capillary ripples: metres across, slope gain, and how many pixels one must span to be drawn.
uniform float capillary_size = 0.085;
uniform float capillary_slope = 0.30;
uniform float capillary_px = 3.0;
// Wind streaks: metres between slick bands (across the wind), their length down it, how much of the
// chop a slick takes away, and the gust patches' size and extra chop.
uniform float streak_spacing = 26.0;
uniform float streak_length = 260.0;
uniform float streak_calm = 0.72;
uniform float gust_size = 55.0;
uniform float gust_gain = 0.55;
// Sparkles: cell size (m), the facets' slope spread, the cone a facet must mirror the sun inside
// (cosine), their brightness and life (s).
uniform float glint_cell = 0.11;
uniform float glint_tilt = 0.22;
uniform float glint_cos = 0.9980;
uniform float glint_energy = 70.0;
uniform float glint_life = 0.35;
// Light through the thin top of a wave (LINEAR): green-blue, by sun height and how thin the water is
// along the view; and the deep water's own blue scatter seen looking down into it, which the bake's
// near-black deep colour cannot carry close to (faded out by `scatter_fade`).
uniform vec3 crest_sss = vec3(0.020, 0.150, 0.125);
uniform float crest_sss_gain = 1.6;
uniform vec3 deep_scatter = vec3(0.0030, 0.0110, 0.0300);
uniform vec2 scatter_fade = vec2(70.0, 210.0);
// Reflected cloud base in the sky reflection (the cloud shadow's own field mirrored).
uniform float cloud_reflect = 0.45;
// Foam ageing: how far out from a whitecap the old foam reaches (as a fraction of foam_fold_lo) and
// how strongly it breaks into lace.
uniform float foam_trail = 0.40;
uniform float foam_lace = 0.85;
// Pile grids (OceanCloseup.pile_grids()): a.xy the first pile's centre in TRUE world XZ, a.zw the
// steps along x and z; b.xy how many piles each way, b.z the pile radius, b.w spare.
const int PILE_GRIDS = 12;
uniform vec4 pile_a[12];
uniform vec4 pile_b[12];
uniform int pile_count = 0;
uniform float pile_foam = 0.95;


float oc_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


vec2 oc_hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}


// Value noise with its gradient (x value, yz d/dx d/dy).
vec3 oc_noised(vec2 x) {
	vec2 i = floor(x);
	vec2 f = x - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = oc_hash12(i);
	float b = oc_hash12(i + vec2(1.0, 0.0));
	float c = oc_hash12(i + vec2(0.0, 1.0));
	float d = oc_hash12(i + vec2(1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k3 = a - b - c + d;
	return vec3(a + k1 * u.x + k2 * u.y + k3 * u.x * u.y, du.x * (k1 + k3 * u.y), du.y * (k2 + k3 * u.x));
}


float oc_vnoise(vec2 p) {
	return oc_noised(p).x;
}


// Distance to the nearest of a jittered grid of points (Worley F1), 0..~1 in cell units.
float oc_worley(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	float d = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = oc_hash22(i + g) * 0.8 + 0.1;
			d = min(d, length(g + o - f));
		}
	}
	return d;
}


// The sea floor under the near water (water-review), `s` metres offshore: SeaSurface.seabed() line
// for line (the sand's own rows under the water, CityChunk SAND_STEEP_AT / SAND_STEEP_Y / SAND_WET /
// SAND_LOW, from the water plane's MESH_Y, then shelving at 9 cm a metre to the floor box).
// tests/water_review_checks.gd reads these numbers back against the GDScript: change one, change both.
const float OC_BED_TOP = 0.15;
const float OC_BED_STEEP_AT = 3.5;
const float OC_BED_STEEP_Y = -0.6;
const float OC_BED_WET = 26.0;
const float OC_BED_LOW = -3.0;
const float OC_BED_SHELF = 0.09;
float oc_seabed(float s) {
	if (s < OC_BED_STEEP_AT) {
		return mix(OC_BED_TOP, OC_BED_STEEP_Y, clamp(s / OC_BED_STEEP_AT, 0.0, 1.0));
	}
	if (s < OC_BED_WET) {
		return mix(OC_BED_STEEP_Y, OC_BED_LOW, (s - OC_BED_STEEP_AT) / (OC_BED_WET - OC_BED_STEEP_AT));
	}
	return max(OC_BED_LOW - (s - OC_BED_WET) * OC_BED_SHELF, -13.0);
}


// Clear shallows: how far the water is seen through (1/m absorption, LINEAR, red first), the wet
// sand on the floor (LINEAR: the swash sheet's colour on beach_sand), and the caustics' strength.
uniform vec3 shallow_absorb = vec3(0.42, 0.095, 0.075);
uniform float shallow_turbid = 0.55;
uniform vec3 floor_color = vec3(0.098, 0.076, 0.047);
uniform float caustic_gain = 1.1;
uniform float shallows_reach = 60.0;


// The floor seen through the water at true-world `fw`: wet sand with ripple marks running along the
// shore (oscillation ripples a dozen centimetres apart, broken and wandering) and a few darker
// patches, lit by caustics - the light the ripples on the surface focus into a moving net of bright
// lines, sharp in a few centimetres of water and gone by a few metres. `depth` metres of water,
// `px` a pixel's size in metres, `sun` 0..1 how much sunlight reaches it.
vec3 oc_sea_floor(vec2 fw, float depth, float px, float t, float sun) {
	vec3 c = floor_color * (0.85 + 0.3 * oc_vnoise(fw * 0.21 + 2.0));
	// Ripple marks: crests along the shore (true-world z), wandering.
	float wob = oc_vnoise(fw * vec2(0.6, 0.25) + 5.0) * 2.0;
	float rp = fw.x / 0.13 + wob * 3.0 + oc_vnoise(fw * vec2(0.9, 0.4)) * 1.6;
	// Gone before a 13 cm ripple is under three pixels (at 1.4 it aliased into dotted lines down the
	// beach). `px` is taken outside any branch by the caller: derivatives in divergent flow are
	// undefined.
	float keep = 1.0 - smoothstep(0.02, 0.045, px);
	float rip = mix(0.5, 0.5 + 0.5 * sin(rp * 6.2832), keep * smoothstep(0.25, 0.6, oc_vnoise(fw * 0.35 + 9.0)));
	c *= 0.86 + 0.24 * rip;
	// Shell grit and darker weed-stained patches.
	c *= mix(1.0, 0.72, smoothstep(0.66, 0.82, oc_vnoise(fw * 0.08 + 13.0)));
	// Caustics (surf.gdshaderinc, shared with the swash on the sand).
	if (sun > 0.001) {
		c += floor_color * (caustic_gain * sun * surf_caustic(fw, depth, px, t) * exp(-depth * 0.55));
	}
	return c;
}


// The pier park's Ferris wheel mirrored at night (water-review): its LED rims and spokes are the
// brightest thing on the coast after dark, and on the water they were missing. `pier_wheel` is the
// hub in TRUE world (x, y, z) and the rim radius (w; 0 = none), from FerrisWheel / PierPark's
// constants (OceanCloseup.apply()); the wheel stands in the world XY plane (it faces north and
// south). The reflected ray is intersected with that plane, and what it meets - the two rims and
// twenty spokes - is drawn smeared along the view by the water's ripple (`smear_m` metres at the
// plane, growing with distance), in a slow cycle of the wheel's colours.
uniform vec4 pier_wheel = vec4(0.0);
// The pier park's decks round the wheel in TRUE world (x0, z0, x1, z1): under them the deck hides
// the wheel from the water (OceanCloseup.wheel_deck()).
uniform vec4 pier_deck = vec4(0.0);
uniform float wheel_light = 1.6;
const float OC_WHEEL_SPOKES = 20.0;
vec3 oc_hue(float h) {
	vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return k * k;
}
vec3 oc_wheel_mirror(vec3 p, vec3 refl, float smear, float t) {
	if (pier_wheel.w <= 0.0 || abs(refl.z) < 0.0005) {
		return vec3(0.0);
	}
	// Under the deck (and a few metres round it, where the deck's edge still cuts the view up).
	vec2 dk = max(pier_deck.xy - p.xz, p.xz - pier_deck.zw);
	float under = 1.0 - smoothstep(-1.0, 4.0, max(dk.x, dk.y));
	if (under > 0.999) {
		return vec3(0.0);
	}
	float tt = (pier_wheel.z - p.z) / refl.z;
	if (tt <= 0.0 || tt > 2500.0) {
		return vec3(0.0);
	}
	vec3 hit = p + refl * tt;
	vec2 d = hit.xy - pier_wheel.xy;
	float r = length(d);
	float R = pier_wheel.w;
	// Ripples smear the reflection up and down the view far more than across it: the vertical
	// tolerance grows with the distance travelled, the sideways one a little.
	float sv = 0.35 + tt * 0.14 * smear;
	float sh = 0.25 + tt * 0.006;
	float w = mix(sh, sv, abs(d.y) / max(r, 0.01));
	float rim = exp(-pow((r - R) / w, 2.0)) + 0.6 * exp(-pow((r - R * 0.89) / w, 2.0));
	float a = atan(d.y, d.x) / 6.2832 + 0.5;
	float sp = (fract(a * OC_WHEEL_SPOKES) - 0.5) * (6.2832 * r / OC_WHEEL_SPOKES);
	float spoke = exp(-pow(sp / sh, 2.0)) * (1.0 - smoothstep(R * 0.95, R + w, r)) * smoothstep(0.0, 2.0, r);
	vec3 c = oc_hue(a + t * 0.03) * 0.8 + vec3(0.2);
	// The energy is kept as the smear spreads it (a wider streak is a dimmer one).
	return c * (rim + spoke * 0.55) * sqrt(0.35 / sv) * wheel_light * (1.0 - under);
}


// The wind's frame on the water: `wv` down the wind, `wp` across it.
void oc_wind_frame(vec2 wind, out vec2 wv, out vec2 wp) {
	wv = normalize(wind + vec2(0.0001, 0.0));
	wp = vec2(-wv.y, wv.x);
}


// Chop gain from the wind streaks and gusts at true world `w` (1 = as before): below 1 in a slick,
// above in a gust. `wind` 0..1 the wind's strength.
float oc_wind_chop(vec2 w, vec2 wind_d, float wind, float t) {
	vec2 wv;
	vec2 wp;
	oc_wind_frame(wind_d, wv, wp);
	float a = dot(w, wv);
	float c = dot(w, wp);
	// Slicks: thin bands along the wind, wandering sideways, broken along their length.
	float wob = oc_vnoise(vec2(a / 180.0, c / 90.0) + 3.7) * 2.0 - 1.0;
	float band = oc_vnoise(vec2(a / streak_length - t * 0.004, c / streak_spacing + wob * 0.9));
	float slick = smoothstep(0.62, 0.80, band) * smoothstep(0.25, 0.6, oc_vnoise(vec2(a / 70.0, c / 30.0) + 11.0));
	// Gusts: darker, rougher patches running down the wind.
	float gust = smoothstep(0.55, 0.85, oc_vnoise(w / gust_size - wv * t * (0.05 + 0.08 * wind) + 7.3));
	return (1.0 - streak_calm * slick * (1.0 - 0.5 * wind)) * (1.0 + gust_gain * gust * (0.4 + 0.6 * wind));
}


// The capillary ripples' slope (world XZ) at `w`: a wind-aligned octave whose crests run across
// the wind, `px` the pixel's size in metres there (faded once a ripple spans under capillary_px).
vec2 oc_capillary(vec2 w, vec2 wind_d, float px, float t) {
	float keep = 1.0 - smoothstep(capillary_size / capillary_px, capillary_size * 2.0 / capillary_px, px);
	if (keep <= 0.001) {
		return vec2(0.0);
	}
	vec2 wv;
	vec2 wp;
	oc_wind_frame(wind_d, wv, wp);
	// Stretched across the wind (crests across it), moving down it at a capillary's speed.
	vec2 q = vec2(dot(w, wv), dot(w, wp) * 0.42) / capillary_size - vec2(t * 2.6, 0.0);
	vec3 r = oc_noised(q);
	vec3 r2 = oc_noised(q * 2.3 + vec2(5.1, 1.7) - vec2(t * 1.4, t * 0.6));
	vec2 dq = r.yz + r2.yz * 0.55;
	vec2 g = wv * dq.x + wp * (dq.y * 0.42);
	return g * (capillary_slope * keep);
}


// One octave of flashing facets, cells `cell` metres across: HDR sparkle where a facet's tilt
// mirrors the sun to the eye. `n` the shading normal, `v` eye-to-point, `L` toward the sun, `px` a
// pixel's size in metres. y: how far this octave has handed over (1 = its cells under a pixel).
vec2 oc_glint_octave(vec2 w, vec3 n, vec3 v, vec3 L, float px, float t, float cell, float salt) {
	float far_w = smoothstep(cell * 0.35, cell * 1.1, px);
	if (far_w >= 0.999) {
		return vec2(0.0, 1.0);
	}
	vec2 g = w / cell + salt;
	vec2 ci = floor(g);
	vec2 f = g - ci;
	float h0 = oc_hash12(ci + 17.0);
	// Each facet lives `glint_life` seconds (staggered), reseeded every life.
	float life = t / glint_life + h0;
	float gen = floor(life);
	float age = life - gen;
	vec2 hs = oc_hash22(ci + gen * 13.7);
	vec2 tilt = (hs - 0.5) * 2.0 * glint_tilt;
	vec3 nf = normalize(n + vec3(tilt.x, 0.0, tilt.y));
	float a = dot(reflect(v, nf), L);
	float hit = smoothstep(glint_cos, mix(glint_cos, 1.0, 0.6), a);
	vec2 at = oc_hash22(ci + gen * 5.3 + 3.1) * 0.5 + 0.25;
	float r0 = 0.12;
	float r = max(r0, px / cell * 0.7);
	float shape = 1.0 - smoothstep(r * 0.35, r, length(f - at));
	// Energy kept as the dot grows to a pixel.
	shape *= (r0 * r0) / (r * r);
	float pulse = sin(age * 3.14159);
	return vec2(hit * shape * pulse * glint_energy * (1.0 - far_w), far_w);
}


// The glitter as separate sparkles at three sizes (capillary facets close to, wavelet facets
// further out), each octave taking over where the finer one has fallen under a pixel. y: how far
// the whole has handed over to the statistical lobe (1 = past the coarsest octave).
vec2 oc_glint(vec2 w, vec3 n, vec3 v, vec3 L, float px, float t) {
	vec2 a = oc_glint_octave(w, n, v, L, px, t, glint_cell, 0.0);
	float sum = a.x;
	float handed = a.y;
	if (handed > 0.001) {
		vec2 b = oc_glint_octave(w, n, v, L, px, t * 0.8, glint_cell * 5.5, 7.31);
		sum += b.x * handed;
		handed *= b.y;
		if (handed > 0.001) {
			vec2 c = oc_glint_octave(w, n, v, L, px, t * 0.6, glint_cell * 30.0, 3.17);
			sum += c.x * handed;
			handed *= c.y;
		}
	}
	return vec2(sum, handed);
}


// Metres from `w` to the surface of the nearest pile in the pile grids (large if none).
float oc_pile_dist(vec2 w) {
	float best = 1e6;
	for (int i = 0; i < PILE_GRIDS; i++) {
		if (i >= pile_count) {
			break;
		}
		vec4 a = pile_a[i];
		vec4 b = pile_b[i];
		vec2 st = vec2(abs(a.z) > 0.001 ? a.z : 1.0, abs(a.w) > 0.001 ? a.w : 1.0);
		vec2 k = clamp(floor((w - a.xy) / st + 0.5), vec2(0.0), max(b.xy - 1.0, vec2(0.0)));
		vec2 c = a.xy + k * vec2(a.z, a.w);
		best = min(best, length(w - c) - b.z);
	}
	return best;
}
