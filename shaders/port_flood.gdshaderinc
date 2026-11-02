// The container terminal's floodlights (PortNight, scripts/world/port_night.gd; wave 7 refcam
// port_night): the high masts and the cranes' lamps light what stands round them after dark.
// Included by container.gdshader and port_steel.gdshader. Every source is TRUE world (xyz) with
// its reach in metres (w); the light falls off inverse-square-ish from a "half" distance of a third
// of the reach and fades out over its last 40 %, the face turned to it lit most, the far side a
// quarter (the yard's bounce); a floodlight aims down, so what stands level with it or above it
// gets none. Returned as a plain number: the caller multiplies its own albedo,
// the tint and lamp_factor in. GDScript copy: PortNight.flood_at() (change both).
// `port_night` 0 (PORT_NIGHT=0) is the A/B: the caller skips the block.

uniform float port_night = 0.0;
uniform vec4 flood_src[64];
uniform int flood_count = 0;
uniform vec3 flood_tint = vec3(1.0, 0.88, 0.7);
uniform float flood_gain = 0.8;
// The most light a face takes from all the floods together (a face right under a lamp, or in
// reach of five, would otherwise burn white).
uniform float flood_cap = 1.1;

#ifndef ORIGIN_SHIFT_DECLARED
#define ORIGIN_SHIFT_DECLARED
global uniform vec3 origin_shift;
#endif

float port_flood(vec3 tp, vec3 n) {
	float fl = 0.0;
	for (int i = 0; i < flood_count; i++) {
		vec3 d = flood_src[i].xyz - tp;
		float reach = flood_src[i].w;
		float dist2 = dot(d, d);
		if (dist2 < reach * reach) {
			float dist = sqrt(dist2);
			float h = reach * 0.32;
			float fall = 1.0 / (1.0 + dist2 / (h * h));
			fall *= 1.0 - smoothstep(reach * 0.6, reach, dist);
			float facing = clamp(dot(n, d / max(dist, 0.01)), 0.0, 1.0);
			// Floodlights aim down: nothing level with a lamp or above it is in its beam.
			float cone = smoothstep(0.0, 0.3, d.y / max(dist, 0.01));
			fl += fall * cone * (0.25 + 0.75 * facing);
		}
	}
	return fl;
}
