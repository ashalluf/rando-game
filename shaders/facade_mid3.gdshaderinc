// Masonry walls that read as built at 30-150 m (fleet wave 5 "facades-mid-3", 2026-11-01).
// Included by building.gdshader (near walls) and building_lod.gdshader (the coded far boxes) after
// facade_variety.gdshaderinc (fx_member(), fx_overlap()) and window_lights.gdshaderinc (wl_roll()).
// Everything both must agree on is rolled from INTEGERS of the building's seed (salts 120-129), so
// a wall keeps its piers across the LOD line. Shader includes use // comments.
//
// A punched or slot-window wall used to be one flat plane with a perfect grid of holes in it - the
// look of a box with a window texture. Most of the city's real mid-rises (1910s-1960s, brick,
// render, precast) are articulated: the windows of a bay are set back in a recessed strip, with
// the spandrel panels between them, and the PIERS between the strips stand proud and run from the
// base course to the attic, so a facade is vertical stripes of light pier and darker recess, with
// the sun throwing the piers' shadows across the strips. Two systems by hash: a pier on every bay
// line, or on every second one (the windows paired in each strip); the rest stay flat.
// Worked out as coverage (fx_member()), so it is depth at any range and its average past a pixel.

// The building's pier system: 0 a flat wall (as before), 1 a pier on every bay line, 2 on every
// second one. Only punched (0) and slot (3) windows on render (0), brick (1) or panels (2).
int fm3_system(float b_seed, int ws, int fin) {
	if ((ws != 0 && ws != 3) || fin > 2) {
		return 0;
	}
	float k = wl_roll(uint(clamp(b_seed, 0.0, 999.0) + 0.5), 120u);
	if (fin == 1) {
		return k < 0.22 ? 0 : (k < 0.68 ? 1 : 2);
	}
	if (fin == 2) {
		return k < 0.45 ? 0 : 1;
	}
	return k < 0.34 ? 0 : (k < 0.74 ? 1 : 2);
}

// The pier's width (metres) for a bay `pitch` wide: what the window gap leaves, less a margin so
// the recess shows a strip of its own wall either side of the glass.
float fm3_pier_width(int ws, float pitch) {
	return (ws == 0 ? 0.30 : 0.44) * pitch;
}

// How far the piers stand proud of the recessed strip (metres): a brick pier deeper than render.
float fm3_depth(int fin) {
	return fin == 1 ? 0.34 : 0.28;
}

// How much darker the recessed strip is than the pier face (its own ambient shade, and on brick
// and panels a spandrel in a darker batch).
float fm3_recess_mul(int fin) {
	return fin == 1 ? 0.70 : (fin == 2 ? 0.78 : 0.80);
}

// Where the piers run on a part, in metres up from its bottom: from the top of the base (the
// storefront, the stone base course, or the ground floor of a wall with no shops) to under the
// attic (the crown floors, or the top half storey). `sf` the storefront's height (0 none),
// `base_h` the base course's top (0 none), `crown` where the crown floors start (< 0 none).
vec2 fm3_run(float sf, float base_h, float part_h, float floor_h, float crown) {
	float lo = max(sf, base_h);
	if (sf < 0.01) {
		lo = max(lo, floor_h);
	}
	float hi = crown > 0.0 ? crown : part_h - 0.45 * floor_h;
	return vec2(lo, hi);
}

// The piers at a wall point: `u` metres along the wall, `vrel` metres up from the part's bottom,
// `run` from fm3_run(), `px` metres a pixel spans, `vw` the view ray and `sw` the sun in wall
// space (x along +u, y up, z out of the wall). Returns x the pier's front face, y its side face
// (the one turned to the eye), z the sun's shadow on the recess (the piers' and the attic's), w
// the recess (the strip between, at its own depth) - each a coverage of the pixel, box filtered,
// at their averages once a pixel spans a bay. All 0 on a wall without piers.
vec4 fm3_piers(int sys, int ws, int fin, float pitch, float u, float vrel, vec2 run, float px, vec3 vw, vec3 sw) {
	if (sys == 0 || vw.z < 0.02 || run.y - run.x < 2.0) {
		return vec4(0.0);
	}
	float inside = fx_overlap(vrel, px, run.x, run.y);
	if (inside <= 0.0) {
		return vec4(0.0);
	}
	float d = fm3_depth(fin);
	float w = fm3_pier_width(ws, pitch);
	float pp = sys == 2 ? 2.0 * pitch : pitch;
	float dxv = -vw.x / vw.z * d;
	float dsv = sw.z > 0.03 ? sw.x / sw.z * d : 0.0;
	vec3 cv = fx_member(u, px, pp, -0.5 * w, w, dxv, dsv);
	// The attic's soffit over the top of the strips throws its shadow down them.
	float sy = (sw.z > 0.03 && sw.y > 0.0) ? sw.y / sw.z * d : 0.0;
	float top_sh = fx_overlap(vrel, px, run.y - sy, run.y);
	float front = cv.x * inside;
	float side = cv.y * inside;
	float strip = clamp(1.0 - cv.x - cv.y, 0.0, 1.0);
	float shade = clamp(cv.z + top_sh * strip, 0.0, 1.0) * inside;
	return vec4(front, side, shade, strip * inside);
}

// How a pier's side face is lit against the facade's own light (`lit_front`, the renderer's): from
// the side the sun is on, or the sky alone.
float fm3_side_light(float dxv_sign, vec3 sw, float day, float lit_front) {
	float lit_side = 0.38 + max(dxv_sign * sw.x, 0.0) * day;
	return clamp(lit_side / max(lit_front, 1e-3), 0.25, 1.4);
}
