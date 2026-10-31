// Weathered flat roofs, seen from above (rc-downtown-aerial, 2026-10-31). Included by
// building.gdshader after hash21. A flat roof is most of what a player sees of downtown from the
// air; the white membrane used to be a clean 0.78 sheet with its "ponding" a hash per 2.9 m
// square, so every roof read as a faint checkerboard of tiles. Here the membrane is rolled 10 ft
// (3.05 m) wide along x with staggered end laps, dirty in smooth drifts, stained where water
// stands (a darker tide line round each pond) and grimed along the foot of the parapet; bitumen
// gets smooth patches the same way. Everything is box-filtered by the pixel footprint `px`
// (metres; taken outside any branch by the caller), so it settles to its average with distance.
// `roof_weather` false (Building, ROOF_WEATHER=0) keeps the old look: the A/B.

uniform bool roof_weather = true;

float rw_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float rw_fbm(vec2 p) {
	return rw_vnoise(p) * 0.55 + rw_vnoise(p * 2.13 + 7.1) * 0.3 + rw_vnoise(p * 4.37 + 3.3) * 0.15;
}

// A thin line at every multiple of `pitch` along t, `w` metres wide, faded to its share of the
// pitch once it is under a pixel.
float rw_line(float t, float pitch, float w, float px) {
	float d = abs(fract(t / pitch + 0.5) - 0.5) * pitch;
	float aa = max(px, 1e-4);
	float l = 1.0 - smoothstep(w * 0.5 - aa * 0.5, w * 0.5 + aa * 0.5, d);
	return mix(l, min(w / pitch, 1.0), smoothstep(w, w * 6.0, px));
}

// The membrane at p (building metres on the roof), `edge` metres in from the roof's edge.
vec3 rw_membrane(vec2 p, float edge, float sd, float px, out float rough) {
	vec3 white = vec3(0.70, 0.70, 0.68);
	// Dirt in drifts: warmer, greyer where it gathers.
	float dirt = rw_fbm(p * 0.11 + sd * 3.1);
	vec3 s = mix(white, vec3(0.55, 0.535, 0.50), smoothstep(0.35, 0.85, dirt) * 0.55);
	// Ponds: low spots that hold water, a stain with a darker tide line at its rim.
	float pn = rw_fbm(p * 0.075 + vec2(sd * 1.7, 5.3));
	float pond = smoothstep(0.62, 0.70, pn);
	float rim = smoothstep(0.58, 0.63, pn) * (1.0 - smoothstep(0.64, 0.70, pn));
	s = mix(s, vec3(0.50, 0.49, 0.46), pond * 0.6);
	s *= 1.0 - 0.12 * rim;
	// Rolls along x, welded seams; end laps staggered roll by roll.
	float roll = floor(p.x / 3.05 + hash21(vec2(sd, 2.0)));
	float seam = rw_line(p.x + hash21(vec2(sd, 2.0)) * 3.05, 3.05, 0.09, px);
	float lap = rw_line(p.y + hash21(vec2(roll, sd)) * 15.0, 15.0, 0.12, px);
	s *= 1.0 - 0.13 * max(seam, lap);
	// Grime along the parapet's foot, where wind drops the dust and the flashing runs.
	s *= 1.0 - 0.22 * (1.0 - smoothstep(0.2, 1.8, edge)) * (0.6 + 0.4 * dirt);
	rough = mix(0.82, 0.55, pond * 0.4);
	return s;
}

// Bitumen: dark, patched and resealed in smooth patches rather than squares.
vec3 rw_bitumen(vec2 p, float edge, float sd, out float rough) {
	float patch = smoothstep(0.42, 0.62, rw_fbm(p * 0.16 + sd * 2.3));
	vec3 s = vec3(0.14, 0.135, 0.13) * mix(0.85, 1.25, rw_fbm(p * 0.4 + sd)) * mix(1.0, 0.72, patch);
	s *= 1.0 - 0.18 * (1.0 - smoothstep(0.2, 1.5, edge));
	rough = mix(0.92, 0.55, patch);
	return s;
}
