// The marina's water mirrors its lights at night (MarinaNight, scripts/world/marina_night.gd; wave 8
// refcam `marina_night`). A harbour at night is black water striped with the wavering column of
// every lamp round it, and the lit fronts across the basin laid upside down in it.
//
// MarinaNight hands (true world = this mesh's local space):
//   ml_p[i] = light x, y, z, size (m); ml_c[i] = linear colour x strength, half width (m, along x
//   across the ray: a lit cabin's row of windows);
//   mf_a[i] = a lit front's ends (x, z, x, z); mf_b[i] = its base y, top y, the bulkhead's line z in
//   front of it, the bulkhead's top y (a ray under it at that line meets the wall).
// mn_lights() follows the reflected ray `r` from water point `p` (its wobble `rw` the chop's,
// steeper) and returns linear light to EMIT before the water's Fresnel.
// Shader includes use // comments.

const int ML_MAX = 48;
uniform vec4 ml_p[48];
uniform vec4 ml_c[48];
uniform int ml_count = 0;
uniform vec4 mf_a[4];
uniform vec4 mf_b[4];
uniform int mf_count = 0;
// A column's height spread per metre the ray runs (the chop's tilt), and across it.
uniform float ml_spread = 0.07;
uniform float ml_across = 0.004;

float mn_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 mn_lights(vec3 p, vec3 r, vec3 rw, float px, float dcam) {
	vec3 acc = vec3(0.0);
	vec2 rh = r.xz;
	float rl = length(rh);
	if (rl < 1e-4) {
		return acc;
	}
	vec2 dir = rh / rl;
	// Rise per horizontal metre of the steady ray and the wobbling one.
	float rise = r.y / rl;
	float risew = rw.y / max(length(rw.xz), 1e-4);
	int count = min(ml_count, ML_MAX);
	for (int i = 0; i < count; i++) {
		vec4 lp = ml_p[i];
		vec4 lc = ml_c[i];
		vec2 d = lp.xz - p.xz;
		float t = dot(d, dir);
		if (t <= 0.5) {
			continue;
		}
		float lat = abs(d.x * dir.y - d.y * dir.x);
		lat = max(lat - lc.w, 0.0);
		float size = lp.w;
		float sh = size + t * ml_across + px * (dcam + t) * 0.7;
		if (lat > sh * 3.0) {
			continue;
		}
		// The height the ray is at when level with the light: the steady ray gives the column's
		// envelope, the wobbling one breaks it into the chop's glints.
		float yr = p.y + rise * t;
		float yw = p.y + risew * t;
		float sv = size + t * ml_spread;
		float env = exp(-pow((yr - lp.y) / (sv * 2.2), 2.0));
		float glint = exp(-pow((yw - lp.y) / (size + t * ml_spread * 0.35), 2.0));
		float g = exp(-lat * lat / (sh * sh)) * sqrt(size / sv) * (0.35 * env + 0.65 * glint * (0.4 + 0.6 * env));
		acc += lc.rgb * g;
	}
	// The lit fronts across the water.
	int nf = min(mf_count, 4);
	for (int i = 0; i < nf; i++) {
		vec4 fa = mf_a[i];
		vec4 fb = mf_b[i];
		// A front faces +z (the restaurants on the north quay face the basin, south).
		if (r.z > -1e-4) {
			continue;
		}
		float tz = (fa.y - p.z) / r.z;
		float tw = (fb.z - p.z) / r.z;
		if (tz <= 0.0) {
			continue;
		}
		vec3 h = p + rw * max((fa.y - p.z) / min(rw.z, -1e-4), 0.0);
		vec3 hs = p + r * tz;
		if (hs.x < fa.x - 1.0 || hs.x > fa.z + 1.0) {
			continue;
		}
		// The bulkhead in front: a ray still under its top where it crosses its line meets the wall.
		float wall_y = p.y + r.y * max(tw, 0.0);
		if (tw > 0.0 && wall_y < fb.w) {
			continue;
		}
		float k = (h.y - fb.x) / max(fb.y - fb.x, 0.1);
		float soft = (0.25 + tz * ml_spread * 0.25) / max(fb.y - fb.x, 0.1);
		float edge = smoothstep(-0.02 - soft, 0.02 + soft, hs.x - fa.x) * smoothstep(-0.02 - soft, 0.02 + soft, fa.z - hs.x);
		// The shop band (ground floor, warm and bright, broken by its mullions) and the windows
		// of the floor over it (dimmer, in a row).
		float shop = smoothstep(-soft, soft, k - 0.03) * smoothstep(-soft, soft, 0.48 - k);
		float mull = 0.55 + 0.45 * smoothstep(0.1, 0.25, abs(fract(hs.x / 2.4) - 0.5) * 2.0);
		float upper = smoothstep(-soft, soft, k - 0.6) * smoothstep(-soft, soft, 0.86 - k);
		float win = step(0.35, mn_hash(vec2(floor(hs.x / 2.6), fa.y))) * (0.55 + 0.45 * smoothstep(0.15, 0.3, abs(fract(hs.x / 2.6) - 0.5) * 2.0));
		vec3 shop_c = vec3(1.0, 0.62, 0.3) * 1.4 * mull * shop;
		vec3 win_c = vec3(1.0, 0.7, 0.42) * 0.55 * win * upper;
		acc += (shop_c + win_c) * edge;
	}
	return acc;
}
