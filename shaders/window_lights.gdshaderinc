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

#ifndef CITY_HOUR_DECLARED
#define CITY_HOUR_DECLARED
global uniform float city_hour;
#endif

// The night skyline pass (NightSkyline, NIGHT_SKYLINE=0 in the environment sets it 0: the A/B):
// offices in their own colour temperature, cleaners' floors lit end to end, crown washes and stone
// floodlighting on the towers. Salts 65-69 belong to it.
#ifndef NIGHT_SKYLINE_DECLARED
#define NIGHT_SKYLINE_DECLARED
global uniform float night_skyline;
#endif


// How many of the offices that light up at all are still lit at this hour (DayNight's clock,
// `city_hour`): fuller in the evening, emptying toward three in the morning, back before dawn.
// Both shaders scale the building's lit ratio by it, so near and far keep the same windows.
// Keys every two hours from midnight; NightCity.WINDOW_KEYS is the GDScript copy.
float window_hour_scale() {
	float k[13] = float[13](0.66, 0.46, 0.38, 0.52, 0.90, 1.0, 1.0, 1.0, 1.05, 1.25, 1.18, 1.04, 0.66);
	float f = mod(city_hour, 24.0) * 0.5;
	int i = int(floor(f));
	float t = f - float(i);
	t = t * t * (3.0 - 2.0 * t);
	return mix(k[clamp(i, 0, 12)], k[clamp(i + 1, 0, 12)], t);
}


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
uint wl_face_row(float b_seed, float face, float row) {
	uint sd = uint(clamp(b_seed, 0.0, 999.0) + 0.5);
	uint f = uint(clamp(face, 0.0, 7.0) + 0.5);
	uint r = uint(clamp(row, 0.0, 255.0));
	return ((sd * 8u + f) * 256u + r) * 256u;
}


// An office tower after dark does not light up as a checkerboard of single windows: a tenancy
// takes a run of three bays and leaves them all on, some floors go dark altogether, a few are lit
// end to end because somebody is cleaning them. `ratio_in` is the building's lit_ratio
// (Building.style; a parameter may not share a uniform's name, and building.gdshader has one).
// The floors with floor_k at or over this are the cleaners' (NightSkyline.CLEANERS_FLOOR).
const float CLEANERS_FLOOR = 0.955;


bool window_lit(float b_seed, float face, float row, float col, float ratio_in) {
	uint sd = uint(clamp(b_seed, 0.0, 999.0) + 0.5);
	float floor_k = wl_roll(sd * 256u + uint(clamp(row, 0.0, 255.0)), 60u);
	// 0 on a dark floor, about double on a busy one, 1 on an ordinary one.
	float floor_mul = floor_k < 0.20 ? 0.0 : (floor_k > 0.88 ? 2.3 : 1.0);
	float ratio = clamp(ratio_in * floor_mul * window_hour_scale(), 0.0, 1.0);
	uint fr = wl_face_row(b_seed, face, row);
	float run_k = wl_roll(fr + uint(clamp(floor(col / 3.0), 0.0, 255.0)), 61u);
	float k = wl_roll(fr + uint(clamp(col, 0.0, 255.0)), 62u);
	// The cleaners: one floor in twenty-odd of a lit building is lit end to end at any hour.
	if (night_skyline > 0.5 && floor_k >= CLEANERS_FLOOR && ratio_in > 0.0) {
		return true;
	}
	// The whole office, plus the odd single window inside a dark one.
	return run_k < ratio || k < ratio * 0.16;
}


// How bright a lit window is against its neighbours, 0.55..1.
float window_glow(float b_seed, float face, float row, float col) {
	return 0.55 + 0.45 * wl_roll(wl_face_row(b_seed, face, row) + uint(clamp(col, 0.0, 255.0)), 64u);
}


// A curtain wall's spandrel panels are the pale one (else the dark one) on 45 % of buildings.
bool spandrel_pale(float b_seed) {
	return wl_roll(uint(clamp(b_seed, 0.0, 999.0) + 0.5), 63u) >= 0.55;
}


// What colour a lit office is, as a multiplier on the building's lit colour (luminance kept):
// a tenancy (the same three-bay run window_lit() lights together, salt 66) has its own fittings -
// most the building's own light, some cool LED panels, some a neutral 4000 K, a few warm halogen
// or a greenish old fluorescent tube - and a cleaners' floor is cold fluorescent end to end.
// NightSkyline.TEMPS is the GDScript copy. 1 with the pass off.
vec3 window_temp(float b_seed, float face, float row, float col) {
	if (night_skyline < 0.5) {
		return vec3(1.0);
	}
	uint sd = uint(clamp(b_seed, 0.0, 999.0) + 0.5);
	float floor_k = wl_roll(sd * 256u + uint(clamp(row, 0.0, 255.0)), 60u);
	vec3 m = vec3(1.0);
	if (floor_k >= CLEANERS_FLOOR) {
		m = vec3(0.78, 1.0, 1.42);
	} else {
		float t = wl_roll(wl_face_row(b_seed, face, row) + uint(clamp(floor(col / 3.0), 0.0, 255.0)), 66u);
		if (t < 0.22) {
			m = vec3(0.74, 0.98, 1.55);
		} else if (t < 0.40) {
			m = vec3(0.88, 1.0, 1.25);
		} else if (t < 0.50) {
			m = vec3(1.10, 0.93, 0.72);
		} else if (t < 0.56) {
			m = vec3(0.80, 1.08, 1.0);
		}
	}
	return m / dot(m, vec3(0.2126, 0.7152, 0.0722));
}


// The colour a tower's architectural lighting is (salt 67): mostly whites, now and then a colour
// - no logo, no lettering, a lit top is the sign.
vec3 wash_color(float r) {
	if (r < 0.34) return vec3(1.0, 0.80, 0.56);
	if (r < 0.58) return vec3(0.80, 0.90, 1.0);
	if (r < 0.70) return vec3(0.30, 0.60, 1.0);
	if (r < 0.79) return vec3(1.0, 0.56, 0.20);
	if (r < 0.87) return vec3(1.0, 0.34, 0.58);
	if (r < 0.94) return vec3(0.22, 0.88, 0.76);
	return vec3(0.60, 0.38, 1.0);
}


// Floodlights grazing a wall from fittings `spacing` metres apart: bright scallops between dark
// gaps, at their average (0.775) once `fade` (1 sharp .. 0 under a pixel) runs out.
float wash_scallop(float u, float spacing, float fade) {
	float c = cos(3.14159265 * u / spacing);
	return mix(0.775, 0.55 + 0.45 * c * c, fade);
}


// The light the night pass throws on a wall of a building part (multiply by the albedo):
// - a CROWN WASH on half the tall parts (salt 65), down from the top over a few storeys in the
//   tower's colour (salt 67), scalloped by the fittings on the parapet;
// - FLOODLIGHTS up a masonry wall (stone, brick, render: `masonry`) on 60 % of buildings over
//   22 m (salt 68), from fittings at the foot, warm or white (salt 69), above the shopfront.
// `part_h` the part's height, `up` metres over its foot, `u` metres along the wall, `night` the
// lamps (lamp_factor) times the pass. Both building shaders call it with their own numbers, and
// every choice is an integer roll on the seed, so a tower keeps its wash across the LOD line.
vec3 tower_wash(float b_seed, float part_h, float up, float u, bool masonry, float night, float fade) {
	if (night <= 0.001 || part_h < 22.0 || night_skyline < 0.5) {
		return vec3(0.0);
	}
	uint sd = uint(clamp(b_seed, 0.0, 999.0) + 0.5);
	vec3 e = vec3(0.0);
	float tall = smoothstep(38.0, 70.0, part_h);
	if (tall > 0.0 && wl_roll(sd, 65u) < 0.5) {
		float h = clamp(part_h * 0.09, 4.0, 15.0);
		float d = max(part_h - up, 0.0);
		float k = exp(-d / h) * (0.35 + 0.65 * smoothstep(0.0, 1.2, d));
		e += wash_color(wl_roll(sd, 67u)) * (2.4 * tall * k * wash_scallop(u, 3.2, fade));
	}
	if (masonry && wl_roll(sd, 68u) < 0.6) {
		float h = clamp(part_h * 0.3, 9.0, 30.0);
		float k = exp(-max(up - 4.0, 0.0) / h) * smoothstep(3.0, 5.0, up);
		vec3 col = wl_roll(sd, 69u) < 0.6 ? vec3(1.0, 0.78, 0.52) : vec3(0.92, 0.95, 1.0);
		e += col * (1.5 * k * wash_scallop(u, 4.6, fade));
	}
	return e * night;
}
