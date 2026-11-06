// The apron's high-mast floodlights falling on what stands under them (AirportNight, refcam3
// "airport_night"): the jets at the gates (airliner_livery.gdshader) and the ground equipment
// (airport_kit.gdshader). A jet at a stand at night is lit by the masts behind its wings; without
// this the gate line was moonlit grey toys in front of a lit concourse.
//
// Every mast is a point source `af_height` metres over its foot: irradiance h^2 cos / r^2, which
// on the ground straight under the head is 1 and falls as (1 + d^2/h^2)^-1.5 - the same curve the
// floods' pools on the concrete are drawn with (airport_flood.gdshader), so a jet and the concrete
// round it agree. Positions are TRUE world (x, ground y, z, facing angle): the includer adds the
// `origin_shift` global to its world position. Nothing runs while `af_count` is 0 (AIRPORT_NIGHT=0,
// or before the airport has been built) or by day (`lamp_factor`).
//
// The includer declares `global uniform float lamp_factor;` and `global uniform vec3 origin_shift;`.
// Shader files use // comments.

uniform vec4 af_masts[16];
uniform int af_count = 0;
uniform float af_height = 28.0;
uniform float af_reach = 110.0;
// The floods' colour (linear) and how much of it a surface emits under the head.
uniform vec3 af_tint = vec3(1.0, 0.88, 0.70);
uniform float af_gain = 0.0;
// Behind a mast (away from where its floods face) the light is this share.
uniform float af_back = 0.45;

// The floods' light at `p` (true world) on a surface facing `n` (world, unit): 0 by day.
vec3 af_flood(vec3 p, vec3 n) {
	if (af_count <= 0 || af_gain <= 0.0 || lamp_factor <= 0.001) {
		return vec3(0.0);
	}
	float e = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= af_count) {
			break;
		}
		vec4 m = af_masts[i];
		vec3 head = vec3(m.x, m.y + af_height, m.z);
		vec3 l = head - p;
		float d = length(l.xz);
		if (d > af_reach) {
			continue;
		}
		float r2 = dot(l, l) + 1.0;
		float lit = max(dot(n, l * inversesqrt(r2)), 0.0);
		vec2 face = vec2(sin(m.w), cos(m.w));
		float fwd = dot(-l.xz, face) / max(d, 1.0);
		float aim = mix(af_back, 1.0, smoothstep(-0.3, 0.4, fwd));
		e += af_height * af_height * lit / r2 * aim * (1.0 - smoothstep(af_reach * 0.7, af_reach, d));
	}
	return af_tint * (af_gain * lamp_factor * min(e, 2.5));
}
