// The night city in a wet road, as a real wet street shows it (docs/HANDOFF.md "The wet road's
// mirror"): long vertical streaks under the shop fronts and the lit windows, smeared toward the
// viewer by the asphalt's roughness, broken into glints by its micro relief, sharp only in
// standing water. Included by road.gdshader (after its hashes and noise); WetRoadMirror
// (scripts/world/wet_road_mirror.gd) is the switch: the `wet_road_mirror` global 0 draws the old
// mirrored_city() exactly as it was.
//
// Why streaks: a rough wet surface is a mirror whose facets are tilted a little at random. Seen at
// a grazing angle, a tilt of d moves the reflected ray about 2d in ELEVATION but only about
// 2d sin(g) in heading (g the view ray's depression), so every light is smeared up and down the
// reflection and hardly sideways. The canyon a puddle mirrors (heading -> facade, elevation ->
// shop band, floors, roofline) is drawn here already blurred: each feature is a box in
// (heading, elevation) and a box blurred by a gaussian is a difference of two ramps, so the blur
// costs nothing per tap. The old canyon sat on a fixed 4-degree heading grid with floors every
// 1/36 of elevation, which across the carriageway read as a regular grid of orange tiles.

global uniform float wet_road_mirror;

// The film's elevation smear (sigma, in units of the reflected ray's y) between the smoothest and
// the roughest tarmac of the roughness field, and in standing water.
uniform float wrm_smear_min = 0.035;
uniform float wrm_smear_max = 0.13;
uniform float wrm_smear_puddle = 0.014;
// The heading spread as a share of the elevation one at a grazing angle (it grows as sin(g)), and
// its floor, in turns.
uniform float wrm_side_share = 1.0;
uniform float wrm_side_min = 0.0006;
// How bright the shop fronts stand (they are what a wet street shows most), the neon over some
// of them, and how much a streak keeps its brightness as it spreads (1 conserves the energy:
// a smear twice as long is half as bright; 0 keeps the peak).
uniform float wrm_shop_gain = 3.0;
uniform float wrm_neon_gain = 1.2;
uniform float wrm_spread_keep = 0.75;
// How much brighter the film's streaks stand than the old film's (the puddles keep their gain).
uniform float wrm_film_gain = 1.8;
// The micro relief breaking the film's streaks into glints: how much of the film it takes away,
// and the size of a speck of aggregate catching the light (m).
uniform float wrm_break = 0.6;
uniform float wrm_glint_size = 0.06;

const float WRM_CELLS = 110.0;


// A box [a, b] blurred by a gaussian of sigma `s`, at x (a smoothstep ramp stands in for the
// error function: two of them, 2.2 sigma either side).
float wrm_box(float x, float a, float b, float s) {
	float k = 1.0 / max(s * 2.2, 1.0e-5);
	return clamp(smoothstep(-1.0, 1.0, (x - a) * k) - smoothstep(-1.0, 1.0, (x - b) * k), 0.0, 1.0);
}


// Gives back part of the brightness a box of width `wide` loses when blurred by `s` (its peak
// falls to about wide / (wide + 2.5 s)): none at wrm_spread_keep 1, all of it at 0.
float wrm_keep(float wide, float s) {
	float peak = clamp(wide / max(wide + 2.5 * s, 1.0e-5), 0.02, 1.0);
	return pow(peak, wrm_spread_keep - 1.0);
}


// The mirrored canyon at reflected ray `r`, blurred by `se` in elevation and `sh` in heading
// (turns). Facades are cells of heading of uneven width (warped, so no two neighbours match and no
// grid repeats), each with its own shop front (span, colour, brightness, how tall), a neon sign
// over some, office floors of its own spacing with its own lit share, and its roofline.
vec3 wrm_city(vec3 r, float se, float sh) {
	float e = r.y;
	float turns = atan(r.x, r.z) * 0.159155;
	float u0 = turns * WRM_CELLS;
	// A slow warp of the heading: cells from ~0.55 to ~1.45 of the mean width.
	float u = u0 + 0.9 * (value_noise(vec2(u0 * 0.23, 7.7)) - 0.5);
	float shu = max(sh * WRM_CELLS, 0.004);
	vec3 sum = vec3(0.0);
	// The cell under the ray and its two neighbours (a smear may reach across a gap).
	for (int k = -1; k <= 1; k++) {
		float c = floor(u) + float(k);
		float f = u - c;
		float h0 = hash12(vec2(c, 31.7));
		float h1 = hash12(vec2(c, 47.3));
		float h2 = hash12(vec2(c, 59.9));
		float h3 = hash12(vec2(c, 71.1));
		// The shop front: a span of the cell, lit in 6 of 10, a few of them very bright.
		float s0 = 0.06 + 0.22 * h0;
		float s1 = 0.94 - 0.22 * h1;
		float shop_on = step(0.5, h2);
		float shop_k = shop_on * (0.12 + 1.9 * h3 * h3 * h3 * h3);
		float top = 0.022 + 0.05 * hash12(vec2(c, 83.9));
		float hue = hash12(vec2(c, 17.9));
		vec3 col = hue < 0.55 ? vec3(1.0, 0.64, 0.33) : (hue < 0.8 ? vec3(1.0, 0.86, 0.66) : (hue < 0.93 ? vec3(0.70, 0.84, 1.0) : vec3(1.0, 0.45, 0.70)));
		float sx = wrm_box(f, s0, s1, shu);
		float sy = wrm_box(e, -0.01, top, se) * wrm_keep(top + 0.01, se);
		sum += col * (shop_k * sx * sy * wrm_shop_gain);
		// Neon over a quarter of the lit fronts: a narrow bar just above the band.
		float neon = shop_on * step(0.72, hash12(vec2(c, 91.3)));
		if (neon > 0.0) {
			float n0 = mix(s0, s1, 0.15 + 0.3 * hash12(vec2(c, 5.1)));
			float n1 = n0 + 0.18 + 0.25 * hash12(vec2(c, 6.3));
			float ny = wrm_box(e, top + 0.008, top + 0.02, se) * wrm_keep(0.012, se);
			vec3 ncol = hue < 0.5 ? vec3(1.0, 0.25, 0.35) : vec3(0.3, 0.8, 1.0);
			sum += ncol * (wrm_box(f, n0, n1, shu) * ny * wrm_neon_gain);
		}
		// Offices: bays and floors of this facade's own size, a share of them lit. Sharp, each
		// window; smeared past a floor, each column of windows averaged into its lit share.
		float roof = mix(0.18, 0.85, hash12(vec2(c, 3.7)));
		float bays = floor(3.0 + 5.0 * hash12(vec2(c, 13.1)));
		float rows = mix(26.0, 46.0, hash12(vec2(c, 19.3)));
		float bay_f = clamp((f - 0.04) / 0.92, 0.0, 0.999) * bays;
		float bay = floor(bay_f);
		float lit_share = (1.0 - mirror_window_lit) * (0.4 + 1.2 * hash12(vec2(c, 29.9)));
		float fx = fract(bay_f);
		float pane_x = wrm_box(fx, 0.18, 0.82, shu * bays);
		float row_f = (e - top - 0.012) * rows + hash12(vec2(c, 37.1));
		float row = floor(row_f);
		float lit = step(1.0 - lit_share, hash12(vec2(c * 7.13 + bay, row + 3.1)));
		float pane_y = wrm_box(fract(row_f), 0.3, 0.85, se * rows);
		// How far a floor is smeared away: 0 sharp, 1 the column's average.
		float avg = smoothstep(0.25, 0.9, se * rows);
		float col_share = lit_share * (0.5 + hash12(vec2(c * 7.13 + bay, 11.0)));
		// Smeared, the bays blur into the facade's glow too: a crisp column per bay drew a comb.
		pane_x = mix(pane_x, 0.64, avg);
		col_share = mix(col_share, lit_share, avg);
		float win = mix(lit * pane_y, col_share * 0.2, avg) * pane_x;
		float facade = wrm_box(e, top + 0.01, roof, se);
		sum += vec3(1.0, 0.8, 0.55) * (win * facade * mirror_windows * mix(1.0, 0.7, mirror_window_smear * avg));
	}
	return sum;
}


// The street a slab of carriageway runs down: the fronts stand `wrm_setback` past each kerb (the
// pavement), so the reflected ray is followed to the plane on its side and the front drawn where it
// lands - shop by shop along the street, fixed to the plan (so a streak stays under its shop as you
// walk), lit band at the foot, floors above, the roofline. Units of `wrm_unit` metres (warped, so
// they never line up), each with its own shop span, colour, brightness and height. `along` / `a` are
// the fragment's position along the street and across it from its first kerb (metres), `width` the
// carriageway's, `ra` / `rx` the reflected ray's along / across parts, `ry` its rise. Blurred by `se`
// (the ray's rise) and `sh` (turns of heading), turned into metres on the facade by the distance.
// Returns the light (rgb) and how far the ray ran to the plane (a), which hands over to the canyon.
uniform float wrm_setback = 4.5;
uniform float wrm_unit = 9.0;
uniform float wrm_street_reach = 140.0;
// The least a front is smeared on the film (m on the front): even close by, wet tarmac never
// mirrors a shop window's edges.
uniform float wrm_smear_floor = 0.6;
uniform float wrm_street_gain = 0.2;

vec4 wrm_street(float along, float a, float width, float ra, float rx, float ry, float se, float sh, float floor_m, float rseed) {
	float side = rx >= 0.0 ? 1.0 : -1.0;
	float gap = rx >= 0.0 ? (width + wrm_setback - a) : (a + wrm_setback);
	float hz = max(length(vec2(ra, rx)), 1.0e-4);
	float t = gap / max(abs(rx), 1.0e-4);
	// Height on the front over the road, and where along the street the ray meets it.
	float y = ry / hz * t;
	float at = along + ra / hz * t;
	float len = t * sqrt(1.0 + (ry / hz) * (ry / hz));
	// The blur in metres on the front: elevation spread by the ray's length (stretched as the ray
	// grazes the road), heading spread likewise along it.
	float sy = max(se * len / max(hz, 0.05), floor_m);
	float sa = max(sh * 6.2832 * len, floor_m * 0.6);
	float u0 = at / wrm_unit;
	float u = u0 + 0.8 * (value_noise(vec2(u0 * 0.37, side * 13.0 + rseed)) - 0.5);
	float su = sa / wrm_unit;
	vec3 sum = vec3(0.0);
	for (int k = -1; k <= 1; k++) {
		float c = floor(u) + float(k);
		vec2 id = vec2(c, side * 31.0 + floor(rseed));
		float f = u - c;
		float h0 = hash12(id + vec2(0.0, 1.7));
		float h1 = hash12(id + vec2(0.0, 2.9));
		float h2 = hash12(id + vec2(0.0, 4.1));
		float h3 = hash12(id + vec2(0.0, 5.3));
		float s0 = 0.05 + 0.2 * h0;
		float s1 = 0.95 - 0.2 * h1;
		float shop_on = step(0.38, h2);
		float shop_k = shop_on * (0.15 + 1.6 * h3 * h3 * h3);
		float top = 3.0 + 1.4 * hash12(id + vec2(0.0, 6.7));
		float hue = hash12(id + vec2(0.0, 7.9));
		vec3 col = hue < 0.55 ? vec3(1.0, 0.64, 0.33) : (hue < 0.8 ? vec3(1.0, 0.86, 0.66) : (hue < 0.93 ? vec3(0.70, 0.84, 1.0) : vec3(1.0, 0.45, 0.70)));
		float sx = wrm_box(f, s0, s1, su);
		float syk = wrm_box(y, 0.4, top, sy) * wrm_keep(top - 0.4, sy);
		sum += col * (shop_k * sx * syk * wrm_shop_gain * wrm_street_gain);
		// A sign or neon over some fronts.
		float neon = shop_on * step(0.7, hash12(id + vec2(0.0, 8.3)));
		if (neon > 0.0) {
			float n0 = mix(s0, s1, 0.1 + 0.4 * hash12(id + vec2(0.0, 9.1)));
			float n1 = min(n0 + 0.2 + 0.3 * hash12(id + vec2(0.0, 9.7)), s1);
			vec3 ncol = hue < 0.5 ? vec3(1.0, 0.25, 0.35) : vec3(0.3, 0.8, 1.0);
			sum += ncol * (wrm_box(f, n0, n1, su) * wrm_box(y, top + 0.2, top + 0.8, sy) * wrm_keep(0.6, sy) * wrm_neon_gain * wrm_street_gain);
		}
		// Floors over the shop: this building's own floor height and bays, a share lit.
		float roof = top + mix(4.0, 50.0, hash12(id + vec2(0.0, 10.3)));
		float storey = mix(3.3, 4.2, hash12(id + vec2(0.0, 11.9)));
		float bays = floor(2.0 + 4.0 * hash12(id + vec2(0.0, 12.7)));
		float lit_share = (1.0 - mirror_window_lit) * (0.4 + 1.2 * hash12(id + vec2(0.0, 13.3)));
		float bay_f = clamp((f - 0.04) / 0.92, 0.0, 0.999) * bays;
		float row_f = (y - top - 0.6) / storey;
		float avg = smoothstep(0.25, 0.9, sy / storey);
		float pane_x = mix(wrm_box(fract(bay_f), 0.2, 0.8, su * bays), 0.6, avg);
		float lit = step(1.0 - lit_share, hash12(vec2(c * 7.13 + floor(bay_f), floor(row_f) + side * 3.0)));
		float pane_y = wrm_box(fract(row_f), 0.25, 0.8, sy / storey);
		float win = mix(lit * pane_y, lit_share * 0.2, avg) * pane_x;
		float facade = wrm_box(y, top + 0.6, roof, sy);
		sum += vec3(1.0, 0.8, 0.55) * (win * facade * mirror_windows * mix(1.0, 0.7, mirror_window_smear * avg));
	}
	return vec4(sum, len);
}


// What a wet pixel mirrors: `r` the reflected ray, `to_frag` the view ray, `w` its world XZ,
// `standing` how much standing water lies there, `rough` the tarmac's roughness texel, `px_m` the
// pixel's footprint in metres across the view (distance x the pixel's angle). Returns the city
// (rgb) with the film's glints in it, and in `sky_break` how much of the film mirrors the sky
// there (long soft smears along the view, never the glints: those over the whole road read as a
// grain of grass).
vec3 wet_road_mirror_city(vec3 r, vec3 to_frag, vec2 w, float standing, float rough, float px_m, float rseed, vec4 street, out float sky_break) {
	float st = clamp(standing, 0.0, 1.0);
	// The roughness field: the texture's own roughness, slow patches of smoother and coarser
	// asphalt (worn wheel paths, a newer overlay), and finer variation inside them.
	float field = clamp(0.55 * rough + 0.6 * value_noise(w * 0.11 + rseed + 21.0) + 0.25 * value_noise(w * 0.9 + rseed) - 0.35, 0.0, 1.0);
	float s_film = mix(wrm_smear_min, wrm_smear_max, field);
	float se = mix(s_film, wrm_smear_puddle, st);
	float g = clamp(-to_frag.y, 0.02, 1.0);
	float sh = max(se * g * wrm_side_share * 0.159155, wrm_side_min);
	vec3 city = wrm_city(r, se, sh);
	// On a street slab (street.z, its width, over 0) the fronts along it, handed over to the far
	// canyon as the ray runs past wrm_street_reach.
	if (street.z > 0.0) {
		float ra = street.w > 1.5 ? r.x : r.z;
		float rx = street.w > 1.5 ? r.z : r.x;
		vec4 st_l = wrm_street(street.x, street.y, street.z, ra, rx, r.y, se, sh, mix(wrm_smear_floor, 0.08, st), rseed);
		float near_k = 1.0 - smoothstep(wrm_street_reach * 0.5, wrm_street_reach, st_l.a);
		city = mix(city, st_l.rgb, near_k);
	}
	// Glints: the film catches the light on the tops of the aggregate, so a streak is broken into
	// bright and dark specks fixed to the road (never to the view: a pattern in the view's own
	// frame is constant along each view ray and drew lines fanning out from the camera), faded to
	// their mean once a speck is under a pixel or two (the footprint along a grazing view is long).
	float px = px_m / (g * wrm_glint_size);
	vec2 q = w / wrm_glint_size;
	float gl = value_noise(q + rseed * 3.0) * 0.6 + value_noise(q * 2.7 + 17.0) * 0.4;
	gl = mix(smoothstep(0.3, 0.7, gl), 0.5, smoothstep(0.5, 1.5, px));
	// Patches of smoother and thinner film, fixed to the road; two octaves turned against each
	// other so the value noise's square cells never show.
	vec2 pw = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * w;
	float pn = 0.6 * value_noise(w * 0.45 + rseed + 5.0) + 0.4 * value_noise(pw * 1.1 + 9.0);
	float patches = smoothstep(0.32, 0.68, pn);
	float brk = mix(1.0, (0.3 + 0.7 * gl) * (0.4 + 0.6 * patches) * 1.5, wrm_break * (1.0 - st));
	sky_break = mix(1.0, 0.45 + 0.55 * patches, 1.0 - st);
	return city * clamp(brk, 0.0, 1.5) * mix(wrm_film_gain, 1.0, st);
}
