// The island on the horizon offshore (the form of the Channel Islands; OffshoreIsland,
// scripts/world/offshore_island.gd, sets every uniform here). It stands 30-40 km out across the
// water, three times past the camera's 12 km far plane, so it is drawn by the SKY: sky.gdshader
// calls island_draw() after the sun, moon and stars and before the clouds, and the sky is drawn
// behind everything, so the city, the headland and the near sea cover it with no depth trick.
//
// It is a real height field in true-world KILOMETRES (view_km is the camera), not a painted
// strip: each sky pixel's ray is followed across the island's footprint (an ellipse), the ground
// is sampled along that chord - densely round where it crosses the main ridge, which is what
// decides the skyline - and the pixel is island where the ray passes under the highest angle
// any sample makes, less the earth's curvature (with refraction), so the shoreline sinks a
// little under the sea horizon as real ones do. The first sample it passes under is the surface
// it sees: lit by the sun with a normal from the height field (the canyons show faintly by day),
// then laid in aerial perspective over `island_haze_km` - pale blue on a clear day, a dark
// silhouette against the sunset (in-scatter `island_glare` toward a low sun), gone in the marine
// layer (`island_amount` 0). After dark a few lights at the island's one town (`island_town`) and
// a red beacon on the summit, drawn no smaller than a pixel and twinkling through the sea air.
//
// Needs from the includer: hash12(), vnoise(), view_km (camera, true world km).

/// 0 hides the island (the marine layer, rain, ISLAND=0); 1 drawn in full.
uniform float island_amount = 0.0;
/// Centre of the footprint, true world km (x, z).
uniform vec2 island_centre = vec2(-33.5, 15.2);
/// The long axis (unit, world x z).
uniform vec2 island_axis = vec2(0.6, 0.8);
/// Half length and greatest half width of the footprint, km.
uniform float island_half_len = 17.0;
uniform float island_half_wid = 4.2;
/// Highest the main ridge stands, km.
uniform float island_peak = 0.68;
/// The distance over which the air takes the island (km; 1 - exp(-d / haze) is the haze share).
uniform float island_haze_km = 24.0;
/// How dark the haze in front reads against a low sun behind it (0 the sky's own colour, 1 black).
uniform float island_glare = 0.5;
/// Land colour (linear-ish albedo, the sky's own space): dry grass and chaparral.
uniform vec3 island_land = vec3(0.105, 0.092, 0.062);
/// The town, km (x, z), and the coast's outward direction there (unit, x z).
uniform vec2 island_town = vec2(-24.6, 8.1);
uniform vec2 island_town_out = vec2(0.8, -0.6);
/// Night lights (0 by day, 1 at night): the town, the coast road, the beacon.
uniform float island_lights = 0.0;
/// A seed for the shape (OffshoreIsland: from nothing the city rolls: the island is fixed).
uniform float island_seed = 3.7;

const float ISLAND_EARTH_R = 7330.0; // km: the earth with standard refraction (k 0.13)
const int ISLAND_SAMPLES = 8;
const int ISLAND_CREST = 6;
const int ISLAND_LIGHTS = 30;

// Ground height (km) at a world point (km, x z). 0 off the island.
float island_height(vec2 p) {
	vec2 rel = p - island_centre;
	vec2 perp = vec2(-island_axis.y, island_axis.x);
	float u = dot(rel, island_axis) / island_half_len;
	if (abs(u) >= 1.0) {
		return 0.0;
	}
	float x = u * island_half_len; // km along
	// The width along the island: fuller in the middle, narrowing to points, an isthmus a third
	// of the way along (the island's two halves), and a ragged coast.
	float w = island_half_wid * pow(1.0 - u * u, 0.45);
	w *= 0.62 + 0.38 * vnoise(vec2(x * 0.32 + island_seed, 7.1));
	w *= 1.0 - 0.72 * exp(-pow((u - 0.42) / 0.045, 2.0));
	w *= 0.85 + 0.15 * vnoise(vec2(x * 1.3, island_seed * 3.0));
	// The ridge wanders off the axis.
	float v0 = 0.22 * sin(u * 3.1 + island_seed) * w;
	float v = (dot(rel, perp) - v0) / max(w, 0.05);
	if (abs(v) >= 1.0) {
		return 0.0;
	}
	// The crest along the island: a broad envelope (high in its larger half), summits and saddles.
	float env = pow(1.0 - u * u, 0.55) * (0.8 + 0.2 * sin(u * 1.4 - 0.6));
	env *= 1.0 - 0.55 * exp(-pow((u - 0.42) / 0.06, 2.0));
	float c = 0.0;
	float amp = 0.5;
	float f = 0.42;
	for (int i = 0; i < 6; i++) {
		c += amp * vnoise(vec2(x * f + island_seed * 11.0, float(i) * 3.3));
		f *= 2.07;
		amp *= 0.5;
	}
	float crest = island_peak * env * (0.45 + 0.85 * c);
	// Down the flanks: steep near the sea (cliffs), canyons cut across the island.
	float side = pow(1.0 - v * v, 0.75);
	float g = abs(vnoise(vec2(x * 1.6, v * 2.2 + island_seed)) - 0.5) * 2.0;
	float canyon = 1.0 - 0.32 * (1.0 - g) * smoothstep(0.1, 0.6, abs(v));
	return crest * side * canyon;
}

// Where the island's footprint ellipse (greatest width) cuts a horizontal ray: (t in, t out), km.
vec2 island_chord(vec2 e, vec2 d) {
	vec2 rel = e - island_centre;
	vec2 perp = vec2(-island_axis.y, island_axis.x);
	float eu = dot(rel, island_axis) / island_half_len;
	float ev = dot(rel, perp) / island_half_wid;
	float du = dot(d, island_axis) / island_half_len;
	float dv = dot(d, perp) / island_half_wid;
	float a = du * du + dv * dv;
	float b = 2.0 * (eu * du + ev * dv);
	float cc = eu * eu + ev * ev - 1.0;
	float disc = b * b - 4.0 * a * cc;
	if (disc <= 0.0 || a < 1e-12) {
		return vec2(-1.0);
	}
	float sq = sqrt(disc);
	return vec2((-b - sq) / (2.0 * a), (-b + sq) / (2.0 * a));
}

// The island over `col` for a view direction. pix: one pixel in radians.
vec3 island_draw(vec3 col, vec3 dir, vec3 sdir, vec3 sun_light, float sun_up, float pix, bool cubemap) {
	if (island_amount <= 0.001) {
		return col;
	}
	float hl = length(dir.xz);
	if (hl < 0.2) {
		return col;
	}
	vec2 d = dir.xz / hl;
	float s = dir.y / hl; // the ray's slope (rise per km)
	vec2 e = view_km.xz;
	float camh = view_km.y;
	vec2 ch = island_chord(e, d);
	if (ch.y <= 0.5) {
		return col;
	}
	float t0 = max(ch.x, 0.5);
	float t1 = ch.y;
	// Nothing can stand higher than the peak at the nearest edge.
	if (s > (island_peak - camh) / t0 + pix) {
		return col;
	}
	// Under the sea's edge at the far side: water (the sky's own band).
	float sea = (-camh - t1 * t1 / (2.0 * ISLAND_EARTH_R)) / t1;
	if (s < sea - pix * 2.0) {
		return col;
	}
	// Where the ray crosses the island's long axis: the crest is round there.
	vec2 perp = vec2(-island_axis.y, island_axis.x);
	float dv = dot(d, perp);
	float tc = 0.5 * (t0 + t1);
	if (abs(dv) > 1e-3) {
		tc = clamp(-dot(e - island_centre, perp) / dv, t0, t1);
	}
	float span = t1 - t0;
	// The highest angle any sample makes, and the first sample the ray passes under.
	float top = -1e9;
	float hit_t = -1.0;
	float hit_h = 0.0;
	float prev_t = t0;
	float prev_k = -1e9;
	for (int i = 0; i < ISLAND_SAMPLES + ISLAND_CREST; i++) {
		float t;
		if (i < ISLAND_SAMPLES) {
			t = t0 + span * (float(i) + 0.5) / float(ISLAND_SAMPLES);
		} else {
			float k = float(i - ISLAND_SAMPLES) - float(ISLAND_CREST - 1) * 0.5;
			t = clamp(tc + k * span * 0.045, t0, t1);
		}
		float h = island_height(e + d * t);
		if (h <= 0.0) {
			continue;
		}
		float ang = (h - camh - t * t / (2.0 * ISLAND_EARTH_R)) / t;
		top = max(top, ang);
		if (ang >= s && (hit_t < 0.0 || t < hit_t)) {
			hit_t = t;
			hit_h = h;
		}
	}
	if (top < -1e8) {
		return col;
	}
	// Antialiased: the skyline over a pixel, the foot sinking into the sea haze.
	float cover = clamp((top - s) / pix + 0.5, 0.0, 1.0) * clamp((s - sea) / (pix * 2.0) + 0.5, 0.0, 1.0);
	if (cover <= 0.0) {
		return col;
	}
	if (hit_t < 0.0) {
		hit_t = tc;
		hit_h = island_height(e + d * tc);
	}
	// The surface's normal from the height field.
	vec2 p = e + d * hit_t;
	float eps = 0.12;
	float hx = island_height(p + vec2(eps, 0.0));
	float hz = island_height(p + vec2(0.0, eps));
	vec3 n = normalize(vec3(-(hx - hit_h) / eps, 1.0, -(hz - hit_h) / eps));
	float lambert = max(dot(n, sdir), 0.0) * sun_up;
	// Lit by the sun and the sky (the sky's light weaker on faces turned down to the sea).
	vec3 ambient = sky_top * 0.35 + sky_horizon * 0.45;
	vec3 lit = island_land * (sun_light * lambert * 1.6 + ambient * (0.55 + 0.45 * n.y));
	// The air between: its colour is the sky behind the island, darker when the island blocks a
	// low sun (forward scatter lights only the air beyond it), and thickest at the waterline.
	vec2 sh = sdir.xz;
	float sl = length(sh);
	float toward = sl > 1e-4 ? max(dot(d, sh / sl), 0.0) : 0.0;
	float low_sun = (1.0 - smoothstep(0.02, 0.3, sdir.y)) * smoothstep(-0.12, 0.0, sdir.y);
	float glare = island_glare * low_sun * pow(toward, 1.5);
	float ihaze = 1.0 - exp(-hit_t / max(island_haze_km, 1.0));
	ihaze = mix(ihaze, 1.0, 0.45 * exp(-hit_h / 0.12) * (1.0 - ihaze));
	// The sky behind a low sun is lit over hundreds of kilometres of air, the air in front of the
	// island over a few dozen: at dusk the island stands darker than the sky round it everywhere,
	// darkest against the glow.
	vec3 air = col * mix(0.92, 0.5, low_sun) * (1.0 - 0.55 * glare);
	vec3 isl = mix(lit, air, clamp(ihaze * (1.0 - 0.35 * low_sun) * (1.0 - 0.45 * glare), 0.0, 1.0));
	// Lights after dark.
	if (!cubemap && island_lights > 0.002) {
		vec2 town_rel = island_town - e;
		float town_t = length(town_rel);
		vec2 town_d = town_rel / max(town_t, 1e-3);
		vec3 lsum = vec3(0.0);
		float rad = max(pix * 0.75, 2e-5);
		float trans = exp(-town_t / max(island_haze_km * 2.2, 1.0));
		float tw = TIME;
		// Only near the town's bearing is there anything to draw (it spans ~4 km).
		if (dot(d, town_d) > cos(5.0 / max(town_t, 5.0))) {
			vec2 tangent = vec2(-island_town_out.y, island_town_out.x);
			for (int i = 0; i < ISLAND_LIGHTS; i++) {
				float fi = float(i);
				float r1 = hash12(vec2(fi, 3.1));
				float r2 = hash12(vec2(fi, 8.7));
				float r3 = hash12(vec2(fi, 1.9));
				vec2 lp;
				if (i < 22) {
					// The town: round the bay and up the hill behind it.
					float a = (r1 - 0.5) * 2.0;
					lp = island_town + tangent * a * 0.75 - island_town_out * (0.08 + r2 * r2 * 0.55 + a * a * 0.12);
				} else {
					// The coast road and a few houses out along it.
					float a = (r1 - 0.5) * 2.0;
					lp = island_town + tangent * (a * 3.2 + sign(a) * 0.8) - island_town_out * (0.15 + r2 * 0.4);
				}
				float lh = max(island_height(lp), 0.004) + 0.006;
				vec2 lr = lp - e;
				float lt = length(lr);
				vec3 ldir = normalize(vec3(lr.x, lh - camh - lt * lt / (2.0 * ISLAND_EARTH_R), lr.y));
				float c2 = dot(ldir, dir);
				float a2 = 2.0 * (1.0 - c2); // ~angle squared
				if (a2 > rad * rad * 9.0) {
					continue;
				}
				// Sodium and white, a few going off as the night goes on.
				vec3 lc = mix(vec3(1.0, 0.62, 0.28), vec3(1.0, 0.92, 0.8), step(0.7, r3));
				float on = step(0.12, hash12(vec2(fi, floor(tw / 600.0))));
				float twinkle = 0.75 + 0.25 * sin(tw * (6.0 + r3 * 9.0) + fi * 2.3);
				lsum += lc * exp(-a2 / (rad * rad)) * on * twinkle * (0.6 + 0.8 * r2);
			}
		}
		{
			// The red beacon on the summit, slow blink.
			vec2 bp = island_centre - island_axis * island_half_len * 0.3;
			vec2 br = bp - e;
			float bt = length(br);
			float bh = island_height(bp) + 0.03;
			vec3 bdir = normalize(vec3(br.x, bh - camh - bt * bt / (2.0 * ISLAND_EARTH_R), br.y));
			float ba = 2.0 * (1.0 - dot(bdir, dir));
			float blink = step(0.5, fract(TIME * 0.5));
			lsum += vec3(1.0, 0.08, 0.04) * exp(-ba / (rad * rad)) * blink * 1.4;
			// Sub-pixel lights keep their energy (a dot a pixel wide, dimmed by less than its area).
			isl += lsum * trans * island_lights * 2.5;
		}
	}
	return mix(col, isl, cover * island_amount);
}
