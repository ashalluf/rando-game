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
	vec3 white = vec3(0.68, 0.68, 0.66);
	// Dirt in drifts: warmer, greyer where it gathers (value-noise fbm sits round 0.5, so the
	// drifts are its upper half stretched out).
	float dirt = smoothstep(0.36, 0.64, rw_fbm(p * 0.09 + sd * 3.1));
	vec3 s = mix(white, vec3(0.47, 0.455, 0.42), dirt * 0.7);
	// Fine mottle a metre across, gone into the tone once it is under a pixel.
	s *= 1.0 + 0.06 * (rw_vnoise(p * 1.1 + sd) - 0.5) * (1.0 - smoothstep(0.3, 1.0, px));
	// Ponds: low spots that hold water, a stain with a darker tide line at its rim.
	float pn = rw_fbm(p * 0.07 + vec2(sd * 1.7, 5.3));
	float pond = smoothstep(0.57, 0.63, pn);
	float rim = smoothstep(0.53, 0.58, pn) * (1.0 - smoothstep(0.59, 0.64, pn));
	s = mix(s, vec3(0.46, 0.45, 0.42), pond * 0.65);
	s *= 1.0 - 0.18 * rim;
	// Rolls along x, welded seams; end laps staggered roll by roll.
	float roll = floor(p.x / 3.05 + hash21(vec2(sd, 2.0)));
	float seam = rw_line(p.x + hash21(vec2(sd, 2.0)) * 3.05, 3.05, 0.09, px);
	float lap = rw_line(p.y + hash21(vec2(roll, sd)) * 15.0, 15.0, 0.12, px);
	s *= 1.0 - 0.14 * max(seam, lap);
	// Grime along the parapet's foot, where wind drops the dust and the flashing runs.
	s *= 1.0 - 0.28 * (1.0 - smoothstep(0.2, 2.2, edge)) * (0.6 + 0.4 * dirt);
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

// Gravel ballast, weathered (fleet wave 5 "facades-mid-3", the FACADES_MID3 switch): the old roof
// was one flat grey with a 0.7 m speckle, so a third of the city's flat roofs read as grey card
// from the air. Wind scours the ballast off the black membrane in long patches and drifts it up
// against the parapet; the roof drains sit in dark rings where the fines wash to; fresh gravel
// tops up bare spots a shade paler; a fine speckle until it is under a pixel. `facade` the
// building's colour (the old ballast took a quarter of it).
vec3 rw_gravel(vec2 p, float edge, float sd, vec3 facade, float px, out float rough) {
	vec3 g = mix(vec3(0.40, 0.39, 0.37), facade, 0.22);
	// Fine speckle of the stones, gone into the tone under a pixel.
	g *= 1.0 + 0.10 * (rw_vnoise(p * 3.1 + sd) - 0.5) * (1.0 - smoothstep(0.15, 0.6, px));
	// Patches of fresh ballast and of old dirty gravel.
	float tone = rw_fbm(p * 0.11 + vec2(sd * 2.7, 1.3));
	g *= mix(0.86, 1.12, smoothstep(0.30, 0.72, tone));
	// Scours: the membrane bare and black where the wind has moved the stones off it.
	float sc = rw_fbm(vec2(p.x * 0.05, p.y * 0.13) + vec2(3.7, sd * 1.9));
	float bare = smoothstep(0.64, 0.70, sc);
	g = mix(g, vec3(0.085, 0.082, 0.08), bare * 0.85);
	// Drifted up against the parapet: a pale band of loose stone at its foot, dirt above it.
	float drift = 1.0 - smoothstep(0.15, 1.4, edge);
	g = mix(g, g * 1.12, drift * 0.6);
	g *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.35, edge));
	// The drains: two or three per roof on a 14 m grid, each in a dark ring of washed-down fines.
	vec2 cell = floor(p / 14.0);
	vec2 dc = (cell + 0.3 + 0.4 * vec2(hash21(cell + sd), hash21(cell + sd + 7.7))) * 14.0;
	float dd = length(p - dc);
	float sump = (1.0 - smoothstep(0.6, 2.2, dd)) * step(0.45, hash21(cell * 1.3 + sd));
	g *= 1.0 - 0.35 * sump;
	rough = mix(0.95, 0.75, bare);
	return g;
}
