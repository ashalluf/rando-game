// Which office windows are lit after dark, how bright each is, and whether a curtain wall's
// spandrels are the pale or the dark panel - rolled from INTEGERS, and shared by the near walls
// (building.gdshader) and the far boxes (building_lod.gdshader), so a tower crossing the LOD line
// at night keeps every lit window it had. A float hash of the same numbers would agree only
// until two compilers schedule its multiply-adds differently; this agrees to the bit on every
// GPU and on the CPU (Building.shop_hash is the same function).
//
// `seed` is the building's seed % 1000 (Building sets the near material's `seed`; the far box
// carries it in its instance code, FarBuilding). `face` 1..4 (+X, -X, +Z, -Z) and 5 for a cut
// corner, `row` the storey above the shopfront, `col` the bay along the wall - all counted the
// same way by both shaders. Salts 60-64; the shop rolls (Building.shop_byte) use 1-45 on other keys.
// Shader includes use // comments.

uint wl_hash(uint key, uint salt) {
	uint h = key * 747796405u + salt * 2891336453u;
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return h;
}


// 0..1, 24 bits of the hash.
float wl_roll(uint key, uint salt) {
	return float(wl_hash(key, salt) >> 8u) * (1.0 / 16777216.0);
}


// The integer key of a storey of one wall of a building, a bay index short.
uint wl_face_row(float seed, float face, float row) {
	uint sd = uint(clamp(seed, 0.0, 999.0) + 0.5);
	uint f = uint(clamp(face, 0.0, 7.0) + 0.5);
	uint r = uint(clamp(row, 0.0, 255.0));
	return ((sd * 8u + f) * 256u + r) * 256u;
}


// An office tower after dark does not light up as a checkerboard of single windows: a tenancy
// takes a run of three bays and leaves them all on, some floors go dark altogether, a few are lit
// end to end because somebody is cleaning them. `lit_ratio` is the building's (Building.style).
bool window_lit(float seed, float face, float row, float col, float lit_ratio) {
	uint sd = uint(clamp(seed, 0.0, 999.0) + 0.5);
	float floor_k = wl_roll(sd * 256u + uint(clamp(row, 0.0, 255.0)), 60u);
	// 0 on a dark floor, about double on a busy one, 1 on an ordinary one.
	float floor_mul = floor_k < 0.20 ? 0.0 : (floor_k > 0.88 ? 2.3 : 1.0);
	float ratio = clamp(lit_ratio * floor_mul, 0.0, 1.0);
	uint fr = wl_face_row(seed, face, row);
	float run_k = wl_roll(fr + uint(clamp(floor(col / 3.0), 0.0, 255.0)), 61u);
	float k = wl_roll(fr + uint(clamp(col, 0.0, 255.0)), 62u);
	// The whole office, plus the odd single window inside a dark one.
	return run_k < ratio || k < ratio * 0.16;
}


// How bright a lit window is against its neighbours, 0.55..1.
float window_glow(float seed, float face, float row, float col) {
	return 0.55 + 0.45 * wl_roll(wl_face_row(seed, face, row) + uint(clamp(col, 0.0, 255.0)), 64u);
}


// A curtain wall's spandrel panels are the pale one (else the dark one) on 45 % of buildings.
bool spandrel_pale(float seed) {
	return wl_roll(uint(clamp(seed, 0.0, 999.0) + 0.5), 63u) >= 0.55;
}
