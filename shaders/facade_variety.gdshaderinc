// What makes a generated facade read as a built thing at 30-500 m rather than a box wrapped in a
// perfect grid (fleet "facades-gta", 2026-10-29): per-pane and per-floor variety in the glass, the
// street opposite mirrored with real parallax, the depth of the members that stand proud of the
// glass (mullion caps, fins, slab bands) as analytic shadow and side faces, and weathering that
// runs down from the roofline. Shared by the near walls (building.gdshader) and the far boxes
// (building_lod.gdshader); everything a near wall and its far box must agree on is rolled from
// INTEGERS (wl_hash, window_lights.gdshaderinc - include that first), so a tower keeps its blinds
// and its system across the LOD line. Salts 70-89 (window_lights has 60-64, the shops 1-57).
// Building.facade_system() is the GDScript copy of fx_system() (the fins' real geometry).
// Shader includes use // comments.

// The building's facade system. Curtain walls: 0 a flush unitised wall (the old look), 1 deep
// vertical fins on every mullion, 2 a slab band standing proud at every floor (the spandrels are
// the band's face). Other window styles: 0. Half the curtain walls stay flush.
int fx_system(float b_seed, int ws) {
	if (ws != 2) {
		return 0;
	}
	float k = wl_roll(uint(clamp(b_seed, 0.0, 999.0) + 0.5), 70u);
	return k < 0.5 ? 0 : (k < 0.76 ? 1 : 2);
}


// How far each system's members stand proud of the glass (metres) and how wide they are: the
// vertical member (x: depth, y: width) and the horizontal one at the slab (z: depth, w: height as
// a share of the storey). The flush wall's are the kit's caps (ShopfrontKit, 15 cm).
vec4 fx_members(int sys) {
	if (sys == 1) {
		return vec4(0.48, 0.13, 0.10, 0.12);
	} else if (sys == 2) {
		return vec4(0.12, 0.075, 0.42, 0.135);
	}
	return vec4(0.15, 0.075, 0.08, 0.12);
}


// A coating batch: curtain-wall glass comes in lots, and a tower re-glazed floor by floor in
// different decades shows it as bands of slightly different tint. A run of 3-9 storeys shares
// one; the multiplier stays within a few percent so it reads as glass, not stripes.
vec3 fx_floor_tint(float b_seed, float row) {
	uint sd = uint(clamp(b_seed, 0.0, 999.0) + 0.5);
	float run = 3.0 + floor(wl_roll(sd, 76u) * 7.0);
	uint batch = uint(clamp(floor(max(row, 0.0) / run), 0.0, 255.0));
	float a = wl_roll(sd * 256u + batch, 77u) - 0.5;
	float b = wl_roll(sd * 256u + batch, 78u) - 0.5;
	return vec3(1.0 + 0.10 * a, 1.0 + 0.05 * b, 1.0 - 0.08 * a);
}


// One pane: x its tone (0.78..1.22, mostly near 1: a pane that is a different batch, a different
// room behind it), y how strongly it mirrors (the coating's age), z where its blind hangs from the
// top (0 none .. 1 drawn right down), w a spare roll. A floor pulls its blinds together more often
// than not (a tenant's habit, the sunny side), so the drop mixes the pane's roll with the floor's.
vec4 fx_pane(float b_seed, float face, float row, float col) {
	uint fr = wl_face_row(b_seed, face, row);
	uint key = fr + uint(clamp(col, 0.0, 255.0));
	float a = wl_roll(key, 71u);
	float b = wl_roll(key, 72u);
	float c = wl_roll(key, 73u);
	float d = wl_roll(key, 74u);
	float floor_k = wl_roll(fr, 79u);
	float tone = 1.0 + (a - 0.5) * 0.24 + (a > 0.94 ? 0.18 : 0.0);
	float mirror = 0.86 + 0.28 * b;
	// About 60 % of panes have a blind down at all; the drop clusters by floor.
	float drop = c < 0.40 ? 0.0 : clamp(mix((c - 0.40) / 0.60, floor_k, 0.55), 0.06, 1.0);
	return vec4(tone, mirror, drop, d);
}


// A pane's blind seen from outside: `fv_in` 0..1 up the pane, `drop` from fx_pane().z. 1 under the
// blind (the slat lines left to the caller: they are under a pixel past a few tens of metres).
float fx_blind(float fv_in, float drop) {
	return drop > 0.0 ? step(1.0 - drop, fv_in) : 0.0;
}


// Box-filtered overlap of the pixel [x - f/2, x + f/2] with [a, b], as a share of the pixel.
float fx_overlap(float x, float f, float a, float b) {
	float lo = max(x - 0.5 * f, a);
	float hi = min(x + 0.5 * f, b);
	return clamp((hi - lo) / max(f, 1e-4), 0.0, 1.0);
}


// A member `w` wide standing `d` proud of the glass, repeated every `pitch` from `x0`, seen on the
// glass plane at `x` (metres) by a pixel `f` wide. `dx` is how far sideways the view ray moves over
// the member's depth going toward the eye, `ds` the same for the sun ray (a huge number when the
// sun is behind the wall). Returns x: the member's front face, y: its side face (the one turned to
// the eye; its normal is sign(dx) along x), z: the glass in the member's shadow - each a coverage
// of the pixel, box filtered, and their averages over the period once a pixel spans one.
vec3 fx_member(float x, float f, float pitch, float x0, float w, float dx, float ds) {
	float base = x0 + floor((x - x0) / pitch) * pitch;
	vec3 cov = vec3(0.0);
	for (int k = -1; k <= 1; k++) {
		float a = base + float(k) * pitch;
		float b = a + w;
		// The front face as it lands on the glass plane, and the whole occluded run.
		float fa = a - dx;
		float fb = b - dx;
		float oa = min(a, fa);
		float ob = max(b, fb);
		float front = fx_overlap(x, f, fa, fb);
		float all_ = fx_overlap(x, f, oa, ob);
		float sa = min(a, a - ds);
		float sb = max(b, b - ds);
		float shade = fx_overlap(x, f, sa, sb);
		cov += vec3(front, max(all_ - front, 0.0), max(shade - all_, 0.0));
	}
	// Past a pixel per period the window is the period's average.
	float span = min(abs(dx), pitch - w);
	float shadow_span = min(abs(ds), pitch - w);
	vec3 mean = vec3(w, span, max(shadow_span - span, 0.0)) / max(pitch, 1e-4);
	return mix(min(cov, vec3(1.0)), mean, smoothstep(0.35 * pitch, 0.9 * pitch, f));
}


// The street opposite, mirrored with its parallax: the reflected ray `rw` in wall space (x along
// +u, y up, z out of the wall) from a point `u` along the wall and `h` metres over the street,
// meets the facades across the street (one plane `street_w` out, a building every 14-32 m along it
// at its own height, its own finish and window grid) or the street before them, else the sky. That
// is what puts the opposite roofline across a tower floor by floor and moves it as you walk: the
// old mirror was keyed on the ray's heading alone, so every pane of a facade mirrored the same
// thing. `fkey` names the wall (the building and face), `sun_out` is the sun's share on the
// opposite facade (dot(sun, -n)), `px` how many metres a pixel spans on the wall. `hit` comes back
// 1 on a building or the street, 0 on the sky (the caller adds its far skyline there).
vec3 fx_opposite(vec3 rw, float u, float h, uint fkey, vec3 sky, vec3 street, float sun_out, float px, out float hit) {
	hit = 0.0;
	float street_w = 18.0 + 26.0 * wl_roll(fkey, 80u);
	if (rw.z < 0.02) {
		return sky;
	}
	float t = street_w / rw.z;
	if (rw.y < -1e-4) {
		float tg = h / -rw.y;
		if (tg < t) {
			hit = 1.0;
			// The street: asphalt, a kerb line now and then.
			float along_g = u + rw.x * tg;
			float lane = step(0.94, fract(along_g * 0.05 + rw.z * tg * 0.27));
			return street * (0.9 + 0.25 * lane);
		}
	}
	float along = u + rw.x * t;
	float hy = h + rw.y * t;
	// Lots across the street, 14-32 m each, from a hash of the wall: their widths are a running sum
	// approximated by a jittered grid (cells of 23 m, the edge moved within the cell).
	float cell = 23.0;
	float ci = floor(along / cell);
	float jit = (wl_roll(fkey + uint(int(ci) + 8192), 81u) - 0.5) * 0.6 * cell;
	float lot = (along - ci * cell) < 0.5 * cell + jit ? ci * 2.0 : ci * 2.0 + 1.0;
	uint lk = fkey * 977u + uint(int(lot) + 16384);
	float k1 = wl_roll(lk, 82u);
	float k2 = wl_roll(lk, 83u);
	float k3 = wl_roll(lk, 84u);
	// Mostly low-rise with the odd tower, and now and then a gap (a car park, a cross street).
	float tall = 7.0 + 38.0 * k1 * k1 + (k2 > 0.86 ? 60.0 * k3 : 0.0);
	if (hy < 0.0) {
		hit = 1.0;
		return street;
	}
	if (k2 < 0.08 || hy > tall) {
		return sky;
	}
	hit = 1.0;
	// Its finish: render, stone, brick, dark glass.
	vec3 wall = k3 < 0.3 ? vec3(0.42, 0.40, 0.36) : (k3 < 0.55 ? vec3(0.30, 0.27, 0.23) : (k3 < 0.75 ? vec3(0.24, 0.12, 0.09) : vec3(0.07, 0.08, 0.10)));
	wall *= 0.35 + 0.85 * clamp(sun_out, 0.0, 1.0);
	// Its windows, faded to their average once under a couple of pixels (the pixel on the opposite
	// facade is `px` on ours times how much further the ray went).
	float bay = 2.6 + 1.4 * k2;
	float storey = 3.4 + 0.6 * k1;
	float fp = px * (1.0 + t / max(h + 1.0, 1.0));
	float sharp = 1.0 - smoothstep(0.25, 0.9, fp / min(bay, storey));
	float win = step(0.30, fract(along / bay)) * step(0.35, fract(hy / storey));
	vec3 pane = mix(street * 0.6, sky * 0.55, 0.5);
	vec3 col = mix(wall, pane, mix(0.45, win, sharp));
	// Its roofline: a cornice line of light under the sky.
	col = mix(col, wall * 1.35, (1.0 - smoothstep(0.0, 0.5, tall - hy)) * 0.6);
	return col;
}


// Water and dirt washed down from the roofline: the coping drips, and a streak runs a few metres
// down the wall under it, under every scupper a darker one. `top` is metres from the part's top,
// `u` metres along the wall, `fkey` the wall. 0 clean .. 1 the darkest streak.
float fx_roof_drip(float top, float u, uint fkey) {
	float cell = floor(u / 0.55);
	float r = wl_roll(fkey + uint(int(cell) + 65536), 85u);
	float len = 0.6 + 3.8 * r * r;
	float scupper = step(0.93, wl_roll(fkey + uint(int(floor(u / 6.0)) + 4096), 86u));
	len += scupper * 6.0;
	float body = (1.0 - smoothstep(0.0, len, top)) * smoothstep(0.0, 0.08, top);
	return clamp(body * (0.35 + 0.65 * r) + scupper * body * 0.5, 0.0, 1.0);
}
