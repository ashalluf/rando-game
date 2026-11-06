// The oil islands' floodlit towers, falls and walls mirrored in the bay at night (rc5-oil-islands-
// dusk; Rc5OilIslands pushes the sources from OilIslands, Weather calls it with the piers'
// rows). Each source is a lit vertical slab standing at a point in TRUE world XZ: the reflected
// view ray is met with the vertical plane through that point square to the ray's own heading
// (a billboard, the way the piers' lamp rows are met with their own plane), and the hit lights
// the water where it falls inside the slab's half width and between its foot and its top - the
// ripples stretch it down the water toward the eye (a column of coloured light per tower, which
// is what a lit structure standing in a calm bay at dusk reads as). LINEAR colours, energy
// included; the caller hands the sum over in the renderer's space. Nothing runs while
// isl_count is 0 (by day the caller does not call it).
const int ISL_MAX = 16;
// x, z (true world), half width (m), top y.
uniform vec4 isl_src[16];
// Linear colour with energy (rgb), foot y (a).
uniform vec4 isl_col[16];
uniform int isl_count = 0;
// Ripple smear: metres of vertical spread per metre the reflected ray travels.
uniform float isl_smear = 0.11;

vec3 oil_island_mirror(vec3 wp, vec3 refl) {
	vec3 em = vec3(0.0);
	float rl = length(refl.xz);
	if (rl < 0.0001) {
		return em;
	}
	vec2 m = refl.xz / rl;
	vec2 side = vec2(-m.y, m.x);
	for (int i = 0; i < ISL_MAX; i++) {
		if (i >= isl_count) {
			break;
		}
		vec4 s = isl_src[i];
		vec4 c = isl_col[i];
		float t = dot(s.xy - wp.xz, m) / rl;
		if (t <= 0.0 || t > 4000.0) {
			continue;
		}
		vec3 hit = wp + refl * t;
		float da = abs(dot(hit.xz - s.xy, side));
		float sh = 0.8 + t * 0.006;
		float lat = 1.0 - smoothstep(s.z - sh, s.z + sh, da);
		if (lat <= 0.0) {
			continue;
		}
		float sv = 0.8 + t * isl_smear;
		float tall = max(s.w - c.a, 1.0);
		float band = smoothstep(c.a - sv, c.a + sv, hit.y) * (1.0 - smoothstep(s.w - sv, s.w + sv, hit.y));
		// The floods stand at the foot: brightest low, fading up the face (oil_island.gdshader).
		float h = clamp(hit.y - c.a, 0.0, tall);
		float rise = exp(-h / min(13.0, max(tall * 0.45, 2.0))) * 0.9 + 0.1;
		em += c.rgb * lat * band * rise;
	}
	return em;
}
