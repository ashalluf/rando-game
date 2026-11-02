// The streets round the refinery at night (rc4-refinery-road, fleet wave 7; RcRefineryRoad,
// docs/HANDOFF.md "The refinery's road at night"). The plant's flares and high masts are not
// renderer lights (a 90 m flame is a shader, the masts' omnis reach 40 m), so the road outside the
// fence was lit by its street lamps' broad additive pools alone - a flat grey sheet in front of a
// dark plant. Here the asphalt and the pavement take the light the flares and masts really throw:
//   - diffuse, as EMISSION times the surface's own albedo (so the paint stays brighter than the
//     tarmac and the texture keeps its contrast, never a flat wash), an illuminance falloff from
//     each source (cosine at the surface over the squared distance, eased by a half distance);
//   - damp: the night air off the harbour leaves the tarmac dark and a little glossy;
//   - glints: each flame and flood standing in that damp tarmac as a stretched highlight (Blinn
//     lobe of the reflected view ray), emitted - neither is a light the renderer knows.
// Everything is behind `rr_on` (0 on every road but the refinery's perimeter streets and its
// pavement ring, and with RC4_REFINERY_ROAD=0): every other road draws bit for bit as before.
// The positions are TRUE world (origin_shift brings the scene back to them). GDScript copy of the
// diffuse term: RcRefineryRoad.light_at() (the checks hold the numbers together).

uniform float rr_on = 0.0;
// Flame bodies (xyz TRUE world, w a phase 0..1) and mast heads (xyz, w the share of the mast's
// floods aimed outward over the fence: most of a perimeter mast's light falls inside).
uniform vec4 rr_flares[8];
uniform int rr_flare_count = 0;
uniform vec4 rr_masts[32];
uniform int rr_mast_count = 0;
// The plant's centre (xz, TRUE world) and, in y, the reach (m) past which nothing is worked out.
uniform vec3 rr_centre = vec3(0.0, 0.0, 0.0);
// Linear colours of the two sources (a flare's amber, a high-pressure sodium flood).
uniform vec3 rr_flare_color = vec3(1.0, 0.6, 0.3);
uniform vec3 rr_mast_color = vec3(1.0, 0.7, 0.4);
// Gains and half distances (m): a flare's light at `rr_flare_half` is half what it is at the foot.
uniform float rr_flare_gain = 5.0;
uniform float rr_flare_half = 55.0;
uniform float rr_flare_reach = 520.0;
uniform float rr_mast_gain = 3.0;
uniform float rr_mast_reach = 70.0;
uniform float rr_mast_half = 12.0;
// The damp: how much darker and how much glossier the tarmac goes, and the glints' strength.
uniform float rr_damp = 0.5;
uniform float rr_glint = 1.0;
uniform float rr_glint_power = 160.0;
global uniform vec3 origin_shift;


// The illuminance (unitless) at TRUE world `tp` facing up from a source at `s` of half distance
// `half_d`: cosine over the squared distance, eased (1 at the foot of a source as high as half_d).
float rr_fall(vec3 s, vec3 tp, float half_d, float reach) {
	vec3 d = s - tp;
	float dist = length(d);
	float cosv = clamp(d.y / max(dist, 0.01), 0.0, 1.0);
	float fall = (half_d * half_d) / (half_d * half_d + dist * dist);
	return fall * cosv * (1.0 - smoothstep(reach * 0.7, reach, dist));
}


// A flood's spill on the ground: a pool round the mast's foot by horizontal distance, half its
// light at `half_d` (the floods aim down into the plant: the spill over the fence is narrow).
float rr_pool(vec3 s, vec3 tp, float half_d, float reach) {
	float r = length(s.xz - tp.xz);
	float q = 1.0 + (r * r) / (half_d * half_d);
	return pow(q, -1.5) * (1.0 - smoothstep(reach * 0.7, reach, r));
}


// The damp tarmac's lobe round the mirror direction (a normalised Blinn on the half vector, up = the
// surface's normal): a bright source standing in it reads as a streak toward the eye.
float rr_lobe(vec3 h) {
	return pow(max(h.y, 0.0), rr_glint_power) * (rr_glint_power + 2.0) * 0.125;
}


// Adds the plant's light on a road / pavement pixel: `albedo` in the material's own space (what
// ALBEDO is set to), `rough` its roughness. Returns the emission to add and darkens / glosses the
// surface through `albedo_io` and `rough_io`. `wpos` scene world position, `cam` the camera.
vec3 rr_light(vec3 wpos, vec3 cam, inout vec3 albedo_io, inout float rough_io, float night) {
	vec3 tp = wpos + origin_shift;
	if (rr_on < 0.5 || distance(tp.xz, rr_centre.xz) > rr_centre.y) {
		return vec3(0.0);
	}
	// Damp tarmac: darker, and smoother where it is not cracked or patched; in patches (the camber,
	// the low spots), never one even film.
	float patches = smoothstep(0.3, 0.7, fbm(tp.xz * 0.07 + 13.0) + 0.25 * value_noise(tp.xz * 0.6));
	float damp = rr_damp * night * mix(0.35, 1.0, patches);
	albedo_io *= 1.0 - 0.32 * damp;
	rough_io = mix(rough_io, min(rough_io, 0.42), damp);
	vec3 v = normalize(cam - wpos);
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(v.y, 0.0, 1.0), 5.0);
	vec3 fl_sum = vec3(0.0);
	vec3 glint = vec3(0.0);
	for (int i = 0; i < rr_flare_count; i++) {
		vec4 f = rr_flares[i];
		float ph = f.w * 6.2832;
		float flick = 0.84 + 0.1 * sin(TIME * 9.3 + ph) + 0.06 * sin(TIME * 23.1 + ph * 3.0);
		float e = rr_fall(f.xyz, tp, rr_flare_half, rr_flare_reach) * flick;
		fl_sum += rr_flare_color * e * rr_flare_gain;
		vec3 l = normalize(f.xyz - tp);
		vec3 h = normalize(l + v);
		float gd = length(f.xyz - tp);
		glint += rr_flare_color * rr_lobe(h) * flick * rr_flare_gain * (3600.0 / (3600.0 + gd * gd));
	}
	for (int i = 0; i < rr_mast_count; i++) {
		vec4 m = rr_masts[i];
		float e = rr_pool(m.xyz, tp, rr_mast_half, rr_mast_reach) * m.w;
		fl_sum += rr_mast_color * e * rr_mast_gain;
		vec3 l = normalize(m.xyz - tp);
		vec3 h = normalize(l + v);
		float gd = length(m.xyz - tp);
		glint += rr_mast_color * rr_lobe(h) * m.w * rr_mast_gain * (900.0 / (900.0 + gd * gd));
	}
	vec3 emit = albedo_io * cs_as_uniform(cs_linear_to_srgb(fl_sum));
	// The glints only where the tarmac is smooth enough to hold them (a crack or a rough patch
	// breaks the streak), dimmed by the albedo the light was not reflected off.
	float smooth_k = 1.0 - smoothstep(0.45, 0.85, rough_io);
	emit += cs_as_uniform(cs_linear_to_srgb(glint)) * fres * smooth_k * damp * rr_glint;
	return emit * night;
}
