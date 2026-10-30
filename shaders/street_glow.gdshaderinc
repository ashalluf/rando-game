// Street lamp glow on a carriageway, seen from far enough away that the lamps themselves are not
// built or not resolved: a run of warm light down the road with a brighter pool under each lamp.
// Shared by far_ground.gdshader (far chunks, which have no lamps) and road.gdshader (near chunks,
// faded in with distance), so the two agree where they meet. `axis` 1 = the road runs along Z,
// 2 = along X, 0 = a junction (lit evenly: it has a lamp on every corner).

global uniform float lamp_factor;
uniform vec3 street_glow_color : source_color = vec3(1.0, 0.62, 0.30);
// Emitted light on the carriageway at full night, between the lamps and under one.
uniform float street_glow_base = 0.025;
uniform float street_glow_pool = 0.16;
// Metres between lamps along a road.
uniform float street_glow_spacing = 32.0;


// How much of the glow shows for a given `lamp_factor`. The lamps are on from sunset, but a
// street lamp is invisible from the air against a lit city until it is properly dark: linear in
// lamp_factor, the far streets wore orange bands in the golden hour.
float street_glow_level() {
	return lamp_factor * lamp_factor * lamp_factor;
}


// `p` is the plan position, `uv` the road slab's own 0..1 across its rect (so the kerbs are at
// 0 and 1 across it). Lamps stand at both kerbs, staggered half a spacing, and each throws an
// oval pool out into the carriageway: seen from the air that is the double row of orange dots a
// lit street really is. A pool the width of the road read as a row of orange tiles.
vec3 street_glow(vec2 p, vec2 uv, int axis) {
	float pool = 0.35;
	if (axis != 0) {
		float along = (axis == 1 ? p.y : p.x) / street_glow_spacing;
		float across = axis == 1 ? uv.x : uv.y;
		float near_kerb = 1.0 - smoothstep(0.0, 0.42, across);
		float far_kerb = 1.0 - smoothstep(0.0, 0.42, 1.0 - across);
		float a0 = abs(fract(along) - 0.5) * 2.0;
		float a1 = abs(fract(along + 0.5) - 0.5) * 2.0;
		pool = near_kerb * smoothstep(0.55, 1.0, a0) + far_kerb * smoothstep(0.55, 1.0, a1);
	}
	return street_glow_color * (street_glow_base + street_glow_pool * pool);
}


// --- Which lamps: high-pressure sodium or LED (NightCity.lamp_led() is the GDScript copy) ---
// Los Angeles changed most of its street lamps to white LEDs and left pockets of the old orange
// sodium: from a hill the grid is both, in patches a few blocks across. The patch is a
// `LAMP_CELL` square of TRUE world XZ, rolled from integers (bit-exact with GDScript), LED more
// often near downtown (`LAMP_CENTRE`) than out at the edges.
const float LAMP_CELL = 420.0;
const vec2 LAMP_CENTRE = vec2(2800.0, 100.0);
// The LED's colour as a ratio of street_glow_color's sodium (4000 K white against 2000 K).
const vec3 LED_RATIO = vec3(0.86, 1.42, 2.95);

uint lamp_hash(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

// 1 where this point's lamps are LED, 0 sodium.
float lamp_led(vec2 world_xz) {
	ivec2 c = ivec2(floor(world_xz / LAMP_CELL));
	uint h = lamp_hash(uint(c.x + 32768) * 65536u + uint(c.y + 32768));
	float roll = float(h >> 8u) * (1.0 / 16777216.0);
	float share = mix(0.72, 0.38, clamp((length(world_xz - LAMP_CENTRE) - 2000.0) / 4500.0, 0.0, 1.0));
	return roll < share ? 1.0 : 0.0;
}

// street_glow_color times this is the lamp colour at a point.
vec3 lamp_ratio(vec2 world_xz) {
	return mix(vec3(1.0), LED_RATIO, lamp_led(world_xz));
}


// The lamp HEADS, seen from far enough out that the lamps are not built (the LOD chunks and the
// far city): the points of light a lit street is from a hill, where the pools under them are only
// a wash. Where street_glow() puts its pools, 1.6 m in from each kerb. `along` metres down the
// road, `across` metres from the near kerb, `w` the road's width, `mpp` metres a pixel. Drawn at
// least `lamp_head_px` across and dimmed by less than their area (a distant point light blooms),
// then the mean once a spacing is under a few pixels. Times the glow's colour and level.
uniform float lamp_head_energy = 7.0;
uniform float lamp_head_px = 0.8;
float street_lamp_heads(float along, float across, float w, float mpp) {
	const float r = 0.35;
	float re = max(r, min(mpp, 5.0) * lamp_head_px);
	float gain = pow(r / re, 1.2);
	float sharp = 1.0 - smoothstep(street_glow_spacing * 0.06, street_glow_spacing * 0.16, mpp);
	float v = 0.0;
	if (sharp > 0.001) {
		float a0 = (fract(along / street_glow_spacing + 0.5) - 0.5) * street_glow_spacing;
		float a1 = (fract(along / street_glow_spacing) - 0.5) * street_glow_spacing;
		float d0 = length(vec2(a0, across - 1.6));
		float d1 = length(vec2(a1, across - (w - 1.6)));
		v += (1.0 - smoothstep(re * 0.45, re, min(d0, d1))) * gain * sharp;
	}
	// Two heads a spacing, spread over the road.
	v += 2.0 * 0.55 * 3.14159 * re * re * gain / (street_glow_spacing * max(w, 4.0)) * (1.0 - sharp);
	return v * lamp_head_energy;
}
