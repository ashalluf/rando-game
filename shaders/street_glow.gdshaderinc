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
