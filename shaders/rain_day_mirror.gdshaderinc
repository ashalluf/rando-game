// The wet road by day (RainDay, refcam rain_day; docs/HANDOFF.md "The rainy day"). By day the
// renderer's own reflection is all there is in a wet road, and its radiance map is the SKY: so the
// whole carriageway mirrored bright grey cloud from kerb to kerb, and a soaked boulevard read as a
// pale dry one. A real wet street by day mirrors the sky down the middle, toward the vanishing
// point, and the darker canyon of fronts along both sides of it - the dark streaks under every
// building and tree are what say "wet". So where the reflected ray meets a front, this takes the
// sky's specular away (SPECULAR) and emits the front instead: the overcast sky's light off a facade,
// a share of the horizon's brightness, blurred like wet_road_mirror's streaks.
//
// Included by road.gdshader AFTER wet_road_mirror.gdshaderinc (it reuses wrm_box, wrm_setback,
// wrm_unit, wrm_street_reach and the same per-unit hashes, so a front's roofline in the day mirror
// is the one the night mirror lights). `rain_day` is RainDay's daylight weight: 0 at night and with
// RAIN_DAY=0, so the night road is bit for bit what it was.

global uniform float rain_day;

// The fronts' brightness as a share of the sky's horizon (an overcast sky lights a facade from
// above and the side: about a quarter of the sky's own radiance comes back off render and glass).
uniform float rdm_wall = 0.26;
// How much of the sky's specular a front takes away where it stands in the mirror.
uniform float rdm_spec_cut = 0.85;
// Off a street slab (pavements, squares, car parks) the canyon is generic: what is mirrored under
// this elevation (the reflected ray's y) is fronts and trees, over `rdm_open_y` the open sky.
uniform float rdm_low_y = 0.06;
uniform float rdm_open_y = 0.42;
uniform float rdm_generic = 0.75;


// How much of a reflected ray `r` runs into the fronts of the street `street` (wrm_st: along,
// across from the first kerb, width, axis; z 0 off a street), blurred by `se` (the elevation smear,
// in units of r.y); `tone` the front's own brightness (0.6..1.4). Pure geometry of the plan.
float rdm_cover(vec3 r, vec4 street, float se, float rseed, out float tone) {
	tone = 1.0;
	float ry = max(r.y, 0.0);
	float generic = rdm_generic * (1.0 - smoothstep(rdm_low_y, rdm_open_y, ry + se));
	if (street.z <= 0.0) {
		return generic;
	}
	float ra = street.w > 1.5 ? r.x : r.z;
	float rx = street.w > 1.5 ? r.z : r.x;
	float side = rx >= 0.0 ? 1.0 : -1.0;
	float gap = rx >= 0.0 ? (street.z + wrm_setback - street.y) : (street.y + wrm_setback);
	float hz = max(length(vec2(ra, rx)), 1.0e-4);
	float t = gap / max(abs(rx), 1.0e-4);
	float y = ry / hz * t;
	float at = street.x + ra / hz * t;
	float len = t * sqrt(1.0 + (ry / hz) * (ry / hz));
	float sy = max(se * len / max(hz, 0.05), 0.6);
	float u0 = at / wrm_unit;
	float u = u0 + 0.8 * (value_noise(vec2(u0 * 0.37, side * 13.0 + rseed)) - 0.5);
	float c = floor(u);
	vec2 id = vec2(c, side * 31.0 + floor(rseed));
	// The same roofline as wrm_street(): the shop band's top plus 4-50 m of floors.
	float top = 3.0 + 1.4 * hash12(id + vec2(0.0, 6.7));
	float roof = top + mix(4.0, 50.0, hash12(id + vec2(0.0, 10.3)));
	tone = 0.6 + 0.8 * hash12(id + vec2(0.0, 14.1));
	float wall = wrm_box(y, -1.0, roof, sy);
	// Past the street's reach the fronts hand over to the generic canyon (and the vanishing point's
	// open sky): a ray running straight down the street never meets them.
	float near_k = 1.0 - smoothstep(wrm_street_reach * 0.5, wrm_street_reach, len);
	return mix(generic * 0.6, wall, near_k);
}
