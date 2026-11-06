// The power plant at dusk (RcPowerPlant, scripts/world/rc5_power_plant.gd; wave 8 refcam
// power_plant_dusk). Included by power_plant.gdshader. Two things:
//  - pp_flood(): the plant's own lamps light it after dark - the halls' wall packs, the stair
//    towers' landing lamps, the eave floods and the yard's flood masts. Every source is TRUE world
//    (xyz) with its reach in metres (w); a negative reach marks a wall pack / bulkhead (light all
//    round it below, falling off fast), a positive one a flood aimed down, reach + 1000 a flood
//    aimed up (a stack's foot). Returned as a plain
//    level; the caller multiplies its albedo, the tint and lamp_factor in (through fh_level()).
//    GDScript copy: RcPowerPlant.flood_at() (change both).
//  - pp_window(): an industrial window band or strip after dark - panes between mullions and a
//    transom, each bay of five panes lit (or not) by a hash, fluorescent or sodium, brighter
//    toward the high-bay lights at the top, the crane girder and machinery as dark shapes behind
//    the glass, dirty panes. Returns the emitted colour in DISPLAY numbers (the caller hands it
//    over with fh_display()), alpha = how much of the pane is lit room (0 = a dark pane).
// `rc5` 0 (RC5_POWER_PLANT=0) is the A/B: the caller skips both.

uniform float rc5 = 0.0;
uniform vec4 pp_src[48];
uniform int pp_src_count = 0;
uniform vec3 pp_tint = vec3(1.0, 0.86, 0.66);
uniform float pp_gain = 0.85;
uniform float pp_cap = 1.0;

#ifndef ORIGIN_SHIFT_DECLARED
#define ORIGIN_SHIFT_DECLARED
global uniform vec3 origin_shift;
#endif

float pp_flood(vec3 tp, vec3 n) {
	float fl = 0.0;
	for (int i = 0; i < pp_src_count; i++) {
		vec3 d = pp_src[i].xyz - tp;
		bool up = pp_src[i].w > 500.0;
		float reach = up ? pp_src[i].w - 1000.0 : abs(pp_src[i].w);
		float dist2 = dot(d, d);
		if (dist2 < reach * reach) {
			float dist = sqrt(dist2);
			vec3 dn = d / max(dist, 0.01);
			float facing = clamp(dot(n, dn), 0.0, 1.0);
			if (up) {
				// Aimed up a stack: a long soft throw up the shaft, nothing below the lamp.
				float h = reach * 0.45;
				float fall = 1.0 / (1.0 + dist2 / (h * h));
				fall *= 1.0 - smoothstep(reach * 0.55, reach, dist);
				float cone = smoothstep(0.0, 0.35, -dn.y);
				fl += fall * cone * (0.15 + 0.85 * facing);
			} else if (pp_src[i].w < 0.0) {
				// A wall pack: a scallop on its own wall (the wall's face is nearly side-on to it,
				// so the base term carries it) and a pool on the ground under it.
				float h = reach * 0.22;
				float fall = 1.0 / (1.0 + dist2 / (h * h));
				fall *= 1.0 - smoothstep(reach * 0.5, reach, dist);
				float cone = smoothstep(-0.25, 0.35, dn.y);
				fl += fall * cone * (0.45 + 0.55 * facing);
			} else {
				float h = reach * 0.3;
				float fall = 1.0 / (1.0 + dist2 / (h * h));
				fall *= 1.0 - smoothstep(reach * 0.6, reach, dist);
				float cone = smoothstep(0.0, 0.3, dn.y);
				fl += fall * cone * (0.2 + 0.8 * facing);
			}
		}
	}
	return min(fl, pp_cap);
}

float pp_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// uv: metres along the band / up from its foot; h: the band's height; seed: the band's own.
vec4 pp_window(vec2 uv, float h, float seed) {
	float pitch = 1.5;
	float bay = floor(uv.x / (pitch * 5.0));
	float on = step(0.42, pp_hash(vec2(bay, seed * 1.37 + 3.1)));
	float cool = step(0.45, pp_hash(vec2(bay + 17.0, seed + 9.7)));
	vec3 tone = mix(vec3(1.0, 0.74, 0.42), vec3(0.78, 0.9, 1.0), cool);
	float lvl = 0.38 + 0.4 * pp_hash(vec2(bay + 5.0, seed + 1.3));
	// Toward the high-bay lights: the top of a band is the brightest, the foot dim.
	float t = clamp(uv.y / max(h, 0.5), 0.0, 1.0);
	float grad = mix(0.45, 1.15, smoothstep(0.0, 0.9, t));
	// The crane girder across a hall's band, and dark machinery silhouettes in the lower half.
	float girder = smoothstep(0.02, 0.0, abs(t - 0.72) - 0.06) * step(h, 6.0);
	float mach = step(0.55, pp_hash(vec2(floor(uv.x / 2.3), seed + 4.4))) * (1.0 - smoothstep(0.25, 0.45, t)) * step(h, 6.0);
	// Tall strips (a boiler house): a lit floor every 6 m, the rest the dark boiler behind.
	if (h > 6.0) {
		float fl = fract(uv.y / 6.0);
		float floor_on = step(0.35, pp_hash(vec2(floor(uv.y / 6.0), seed + bay * 3.1)));
		grad = mix(0.25, 1.0, smoothstep(0.55, 0.9, fl)) * floor_on;
		on = 1.0;
	}
	float pane = 0.82 + 0.18 * pp_hash(floor(uv / vec2(pitch, 1.6)) + seed);
	float lit = on * grad * (1.0 - girder * 0.85) * (1.0 - mach * 0.7) * pane;
	return vec4(tone * lvl * lit, clamp(on * grad, 0.0, 1.0));
}
