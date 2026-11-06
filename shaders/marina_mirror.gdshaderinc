// The marina's water mirrors its boats (MarinaGolden, scripts/world/marina_golden.gd; wave 6 refcam
// `marina_golden`). A harbour at golden hour is mostly what stands in it, upside down and broken by
// the chop: white hulls and dark cabins as wobbling blocks, the masts as long wavering lines - and
// a basin that mirrors only the sky reads as a pink sheet with the boats pasted on top.
//
// MarinaGolden hands the MAX boats nearest the camera (true world = this mesh's local space):
//   mm_a[i] = centre x, z, yaw, length; mm_b[i] = beam, hull top, cabin top, mast top (0 none);
//   mm_c[i] = hull paint (sRGB), type.
// mm_trace() follows the reflected ray from a point on the water against each boat - a hull box
// narrowed to the bow, a cabin box, the mast as a line - and returns the nearest hit's colour
// (linear, premultiplied) in rgb and its coverage in a (the mast's is fractional: it is anti-aliased by the
// pixel's footprint: `px` radians a pixel, `dcam` metres from the camera to the water point).
//
// The includer declares sun_direction, tree_sun, skyline_sky_top / _rim and color_space.
// Shader includes use // comments.

const int MM_MAX = 40;
uniform vec4 mm_a[40];
uniform vec4 mm_b[40];
uniform vec4 mm_c[40];
uniform int mm_count = 0;
// Past this many metres along the reflected ray a hit fades into the sky (aerial haze).
uniform float mm_haze = 260.0;

// The light on a surface of normal n (world), linear: the sky's ambient and the sun. The ambient
// is DayNight's horizon and zenith (display numbers, raw on both renderers: decoded here).
vec3 mm_light(vec3 n) {
	vec3 rim = cs_srgb_to_linear(skyline_sky_rim.rgb);
	vec3 top = cs_srgb_to_linear(skyline_sky_top.rgb);
	vec3 amb = mix(rim, top, clamp(n.y * 0.5 + 0.5, 0.0, 1.0)) * 0.55;
	float ndl = max(dot(n, normalize(sun_direction)), 0.0);
	return amb + tree_sun * ndl;
}

// Ray-box (axis-aligned, in the boat's frame) entry distance and the entry face's axis (0 x,
// 1 y, 2 z) with its sign; t < 0 for a miss.
vec2 mm_box(vec3 o, vec3 d, vec3 lo, vec3 hi, out vec3 nrm) {
	vec3 inv = 1.0 / d;
	vec3 t0 = (lo - o) * inv;
	vec3 t1 = (hi - o) * inv;
	vec3 tn = min(t0, t1);
	vec3 tf = max(t0, t1);
	float a = max(max(tn.x, tn.y), tn.z);
	float b = min(min(tf.x, tf.y), tf.z);
	nrm = vec3(0.0);
	if (b < max(a, 0.0)) {
		return vec2(-1.0, 0.0);
	}
	if (a == tn.x) {
		nrm = vec3(-sign(d.x), 0.0, 0.0);
	} else if (a == tn.y) {
		nrm = vec3(0.0, -sign(d.y), 0.0);
	} else {
		nrm = vec3(0.0, 0.0, -sign(d.z));
	}
	return vec2(max(a, 0.0), b);
}

vec4 mm_trace(vec3 p, vec3 r, float water_y, float px, float dcam) {
	vec4 best = vec4(0.0);
	float best_t = 1e9;
	float haze_t = 1e9;
	int count = min(mm_count, MM_MAX);
	for (int i = 0; i < count; i++) {
		vec4 a = mm_a[i];
		vec4 b = mm_b[i];
		float yaw = a.z;
		float len = a.w;
		// The boat's frame: f toward the bow, x to starboard.
		vec2 f = vec2(-sin(yaw), -cos(yaw));
		vec2 x = vec2(cos(yaw), -sin(yaw));
		vec2 o2 = p.xz - a.xy;
		vec3 o = vec3(dot(o2, x), p.y - water_y, dot(o2, f));
		vec3 d = vec3(dot(r.xz, x), r.y, dot(r.xz, f));
		// Cheap reject: the ray's closest approach to the boat's centre in plan, and the height it
		// has climbed by then.
		float top = max(b.z, b.w);
		vec2 d2 = d.xz;
		float dd = max(dot(d2, d2), 1e-6);
		float tc = max(-dot(o.xz, d2) / dd, 0.0);
		vec2 cpos = o.xz + d2 * tc;
		if (dot(cpos, cpos) > len * len * 0.36 + 1.0) {
			continue;
		}
		float hb = b.x * 0.5;
		float hl = len * 0.5;
		if (o.y + d.y * max(tc - hl, 0.0) > top) {
			continue;
		}
		vec3 paint = cs_srgb_to_linear(mm_c[i].rgb);
		// The hull: a box to the gunwale, narrowed to the bow at the hit (a box's square bow
		// mirrored as a wall).
		vec3 nb;
		vec2 hit = mm_box(o, d, vec3(-hb, 0.0, -hl), vec3(hb, b.y, hl), nb);
		if (hit.x >= 0.0 && hit.x < best_t) {
			vec3 q = o + d * hit.x;
			float u = q.z / hl;
			float taper = mix(1.0, 0.25, smoothstep(0.25, 1.0, u)) * mix(1.0, 0.85, smoothstep(-0.7, -1.0, u));
			if (abs(q.x) <= hb * taper + 0.05) {
				vec3 n_w = normalize(vec3(nb.x * x.x + nb.z * f.x, nb.y, nb.x * x.y + nb.z * f.y));
				vec3 col = paint;
				// A darker band at the waterline (scum, the boot top's shadow).
				col *= mix(0.45, 1.0, smoothstep(0.05, 0.3, q.y));
				best_t = hit.x;
				haze_t = hit.x;
				best = vec4(col * mm_light(n_w), 1.0);
			}
		}
		// The cabin (or a motor yacht's whole superstructure): white, a band of dark glass.
		if (b.z > b.y + 0.05) {
			vec3 nc;
			float aft = -len * 0.06;
			vec2 hc = mm_box(o, d, vec3(-hb * 0.72, b.y, aft - len * 0.24), vec3(hb * 0.72, b.z, aft + len * 0.2), nc);
			if (hc.x >= 0.0 && hc.x < best_t) {
				vec3 q = o + d * hc.x;
				vec3 n_w = normalize(vec3(nc.x * x.x + nc.z * f.x, nc.y, nc.x * x.y + nc.z * f.y));
				float k = (q.y - b.y) / max(b.z - b.y, 0.01);
				float glass = step(0.35, k) * step(k, 0.75) * step(abs(nc.y), 0.5);
				vec3 col = mix(vec3(0.82, 0.82, 0.8), vec3(0.02, 0.025, 0.03), glass);
				best_t = hc.x;
				haze_t = hc.x;
				best = vec4(col * mm_light(n_w), 1.0);
			}
		}
		// The mast (or a tuna tower's legs) as a line a tenth of the length forward of the centre:
		// the ray's closest approach to it in plan, anti-aliased by the pixel's footprint there.
		if (b.w > 0.0) {
			vec2 mpos = vec2(0.0, len * 0.1);
			float tm = max(dot(mpos - o.xz, d2) / dd, 0.0);
			float y = o.y + d.y * tm;
			if (tm < best_t && y > b.y && y < b.w) {
				float dist = length(o.xz + d2 * tm - mpos);
				float foot = px * (dcam + tm);
				float w = 0.09 * (1.0 - 0.5 * (y - b.y) / max(b.w - b.y, 0.1));
				float cov = clamp((w + foot * 0.5 - dist) / max(foot, 1e-3), 0.0, 1.0) * min(1.0, 2.0 * w / max(foot, 1e-3) + 0.15);
				if (cov > 0.01) {
					vec2 side = normalize(-d2);
					vec3 n_w = normalize(vec3(side.x * x.x + side.y * f.x, 0.0, side.x * x.y + side.y * f.y));
					vec3 col = vec3(0.72, 0.73, 0.74) * mm_light(n_w);
					// In front of whatever was hit beyond it (premultiplied: a miss is all zero).
					best = mix(best, vec4(col, 1.0), cov);
					haze_t = min(haze_t, tm);
					if (cov > 0.5) {
						best_t = tm;
					}
				}
			}
		}
	}
	// Far hits go into the haze.
	// rgb is premultiplied by a (a hull is 1, a mast over open sky its coverage).
	if (best.a > 0.0) {
		best *= 1.0 - smoothstep(mm_haze * 0.5, mm_haze, haze_t);
	}
	return best;
}
