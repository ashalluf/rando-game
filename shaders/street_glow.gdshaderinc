// Street lamp glow on a carriageway, seen from far enough away that the lamps themselves are not
// built or not resolved: a run of warm light down the road with a brighter pool under each lamp.
// Shared by far_ground.gdshader (far chunks, which have no lamps) and road.gdshader (near chunks,
// faded in with distance), so the two agree where they meet. `axis` 1 = the road runs along Z,
// 2 = along X, 0 = a junction (lit evenly: it has a lamp on every corner).

global uniform float lamp_factor;
uniform vec3 street_glow_color : source_color = vec3(1.0, 0.62, 0.30);
// Emitted light on the carriageway at full night, between the lamps and under one.
uniform float street_glow_base = 0.10;
uniform float street_glow_pool = 0.13;
// Metres between lamps along a road.
uniform float street_glow_spacing = 32.0;


vec3 street_glow(vec2 p, int axis) {
	float pool = 0.6;
	if (axis != 0) {
		float along = axis == 1 ? p.y : p.x;
		float f = abs(fract(along / street_glow_spacing) - 0.5) * 2.0;
		pool = smoothstep(0.25, 1.0, f);
	}
	return street_glow_color * (street_glow_base + street_glow_pool * pool);
}
