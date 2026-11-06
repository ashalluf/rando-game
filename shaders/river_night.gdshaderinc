// The LA River at night (RiverNight, scripts/world/river_night.gd; docs/HANDOFF.md "The LA River at
// night"). The bridges round the camera as uniform arrays in TRUE world (RiverNight.arrays()):
//   rn_a = o.x, o.z, u.x, u.z      (the road's centre line on the river; u along the road)
//   rn_b = half, deck y, thick, kind (0 ribbon, 1 arch, 2 girder)
//   rn_c = the ribbon's span ends in t (else t0, the bed's edges, t1)
//   rn_d = t0, t1, rise, lean      rn_e = the bed's edges in t, the two piers' t
// q (across the road) = (-u.z, u.x). Everything here is called only after dark (lamp_factor) and
// behind the `river_night` global; nothing samples a texture (WebGL's sampler budget).

global uniform float river_night;
global uniform vec3 origin_shift;

uniform vec4 rn_a[6];
uniform vec4 rn_b[6];
uniform vec4 rn_c[6];
uniform vec4 rn_d[6];
uniform vec4 rn_e[6];
uniform int rn_count = 0;

// The fixtures under each deck (RiverNight.FIX_IN / FIX_DROP), their pitch along the bridge and
// their intensity; the ribbon's LEDs are cool, the older bridges' fixtures warm (LINEAR).
const float RN_FIX_IN = 1.6;
const float RN_FIX_DROP = 0.35;
const float RN_FIX_PITCH = 8.0;
uniform float rn_fix_energy = 46.0;
uniform vec3 rn_led = vec3(0.70, 0.84, 1.0);
uniform vec3 rn_warm = vec3(1.0, 0.70, 0.42);
uniform float rn_rib_wash = 1.5;

vec3 rn_color(float kind) {
	return kind < 0.5 ? rn_led : rn_warm;
}

// The ribbon's rib centre at t on side sg: (a, y), or y = -1e5 outside its spans
// (RiverNight.rib_at(), change both).
vec2 rn_rib(int i, float t, float sg) {
	vec4 st = rn_c[i];
	float ta = st.x;
	float tz = st.y;
	if (t > st.y) {
		ta = st.y;
		tz = st.z;
	}
	if (t > st.z) {
		ta = st.z;
		tz = st.w;
	}
	if (t < st.x || t > st.w) {
		return vec2(0.0, -1e5);
	}
	float e = 2.0 * (t - ta) / max(tz - ta, 0.1) - 1.0;
	float h = rn_d[i].z * pow(max(1.0 - e * e, 0.0), 0.7);
	return vec2(sg * (rn_b[i].x + 0.4 + h * rn_d[i].w), rn_b[i].y + 0.2 + h);
}

// Irradiance (LINEAR) at true-world point p with world normal n from every bridge's under-deck
// fixtures: discrete downlights every RN_FIX_PITCH over the channel, both fascias.
vec3 rn_light(vec3 p, vec3 n) {
	vec3 e = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		if (i >= rn_count) {
			break;
		}
		vec2 u = rn_a[i].zw;
		vec2 q = vec2(-u.y, u.x);
		vec2 d = p.xz - rn_a[i].xy;
		float t = dot(d, u);
		float a = dot(d, q);
		float half_w = rn_b[i].x;
		if (abs(a) > half_w + 30.0 || t < rn_e[i].x - 30.0 || t > rn_e[i].y + 30.0) {
			continue;
		}
		float yl = rn_b[i].y - rn_b[i].z - RN_FIX_DROP;
		float t0 = rn_e[i].x - 2.0;
		float t1 = rn_e[i].y + 2.0;
		float k = clamp(floor((t - t0) / RN_FIX_PITCH + 0.5), 0.0, floor((t1 - t0) / RN_FIX_PITCH));
		vec3 col = rn_color(rn_b[i].w);
		for (int s = 0; s < 2; s++) {
			float al = (s == 0 ? -1.0 : 1.0) * (half_w - RN_FIX_IN);
			for (int j = -1; j <= 1; j++) {
				float tl = t0 + (k + float(j)) * RN_FIX_PITCH;
				vec2 lxz = rn_a[i].xy + u * tl + q * al;
				vec3 l = vec3(lxz.x, yl, lxz.y) - p;
				float d2 = dot(l, l);
				vec3 ld = l * inversesqrt(max(d2, 1e-4));
				// A wide flood aimed down: only what is below its lens.
				float cone = smoothstep(0.05, 0.55, ld.y);
				e += col * (rn_fix_energy * cone * max(dot(n, ld), 0.0) / (d2 + 3.0));
			}
		}
	}
	return e;
}

// How much of the ribbon's own LED wash a bridge-concrete point gets (0 off a rib): the whole rib
// lit softly, its LED side (under the soffit) hard.
float rn_rib_glow(vec3 p) {
	float g = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= rn_count) {
			break;
		}
		if (rn_b[i].w > 0.5) {
			continue;
		}
		vec2 u = rn_a[i].zw;
		vec2 q = vec2(-u.y, u.x);
		vec2 d = p.xz - rn_a[i].xy;
		float t = dot(d, u);
		float a = dot(d, q);
		vec2 c = rn_rib(i, t, a >= 0.0 ? 1.0 : -1.0);
		vec2 dd = vec2(a - c.x, p.y - c.y);
		float r = length(dd);
		if (r < 1.2) {
			g = max(g, (0.32 + 1.8 * smoothstep(0.0, 0.7, -dd.y)) * (1.0 - smoothstep(0.9, 1.2, r)));
		}
	}
	return g;
}

// A soft line: 1 on it, falling off over w.
float rn_line(float x, float w) {
	return exp(-x * x / max(w * w, 1e-5));
}

// What the reflected ray `r` (world, unit) from the water at true-world `w` meets on the bridges:
// the nearest solid thing's rgb (emitted, LINEAR) and coverage; the lit lines and lamps are added
// to `glow`. `lat` the river's +o (world xz), `o0` the water point's o,
// `bh` the bed's half width, `h_top` the coping over the water: a hit inside the bank's slope
// (the bank between) is dropped. `blur` widens the lit lines (the riffles' scatter).
vec4 rn_mirror(vec3 w, vec3 r, vec2 lat, float o0, float bh, float h_top, float toe, float slope, float blur, inout vec3 glow) {
	vec4 best = vec4(0.0);
	float best_l = 1e9;
	for (int i = 0; i < 6; i++) {
		if (i >= rn_count) {
			break;
		}
		vec2 u = rn_a[i].zw;
		vec2 q = vec2(-u.y, u.x);
		vec2 d = w.xz - rn_a[i].xy;
		float aw = dot(d, q);
		float tw = dot(d, u);
		float rq = dot(r.xz, q);
		float ru = dot(r.xz, u);
		float sg = aw >= 0.0 ? 1.0 : -1.0;
		if (-sg * rq < 1e-3 || abs(aw) > 400.0) {
			continue;
		}
		float half_w = rn_b[i].x;
		float deck = rn_b[i].y;
		float thick = rn_b[i].z;
		float kind = rn_b[i].w;
		vec3 col = rn_color(kind);
		// The planes the ray crosses, near to far: the near rib (ribbon), the near fascia, the far rib.
		for (int pass = 0; pass < 3; pass++) {
			bool rib = pass != 1;
			if (rib && kind > 0.5) {
				continue;
			}
			float side = pass == 2 ? -sg : sg;
			float ap = side * half_w;
			if (rib) {
				ap = side * (half_w + 0.4 + rn_d[i].z * 0.55 * rn_d[i].w);
			}
			float lam = (ap - aw) / rq;
			if (lam <= 0.0) {
				continue;
			}
			vec3 h = w + r * lam;
			float t = tw + ru * lam;
			if (rib) {
				// Two steps onto the leaning rib's own plane.
				for (int it = 0; it < 2; it++) {
					vec2 c0 = rn_rib(i, t, side);
					if (c0.y < -1e4) {
						break;
					}
					lam = (c0.x - aw) / rq;
					h = w + r * lam;
					t = tw + ru * lam;
				}
			}
			if (t < rn_d[i].x - 1.0 || t > rn_d[i].y + 1.0 || lam <= 0.0) {
				continue;
			}
			// The bank in the way: the hit is under the coping and outside the channel there.
			float yr = h.y - w.y;
			float lh = o0 + lam * dot(r.xz, lat);
			if (yr < h_top && abs(lh) > bh + max(yr - toe, 0.0) * slope) {
				continue;
			}
			float bw = 0.06 + blur * lam;
			// Faded over the last metres at each end (the abutments), not cut.
			float ends = smoothstep(rn_d[i].x - 1.0, rn_d[i].x + 5.0, t) * smoothstep(rn_d[i].y + 1.0, rn_d[i].y - 5.0, t);
			if (rib) {
				vec2 c = rn_rib(i, t, side);
				if (c.y < -1e4) {
					continue;
				}
				float dy = h.y - c.y;
				// The LED line under the soffit, then the rib washed by it.
				glow += col * 1.8 * ends * rn_line(dy + 0.62, 0.1 + bw);
				float body = 1.0 - smoothstep(0.62, 0.62 + bw * 2.0, abs(dy));
				if (body > 0.01 && lam < best_l) {
					vec3 rc = vec3(0.30, 0.285, 0.255) * col * (0.55 + 1.6 * smoothstep(0.0, 0.7, -dy)) * rn_rib_wash * 0.35;
					best = vec4(rc, body * ends);
					best_l = lam;
				}
				continue;
			}
			// The fascia and parapet, the lamps over them and the fixtures under.
			float lamp_h = kind < 0.5 ? 7.07 : (kind < 1.5 ? 6.1 : 9.12);
			float lamp_t0 = kind < 0.5 ? 6.0 : (kind < 1.5 ? 4.0 : 8.0);
			float lamp_gap = kind < 0.5 ? 12.8 : (kind < 1.5 ? 16.0 : 25.6);
			float lt = mod(t - (rn_d[i].x + lamp_t0) + lamp_gap * 0.5, lamp_gap) - lamp_gap * 0.5;
			vec3 lamp_col = kind < 0.5 ? vec3(0.85, 0.9, 1.0) : rn_warm;
			glow += lamp_col * 4.0 * rn_line(lt, 0.3 + bw) * rn_line(h.y - (deck + lamp_h), 0.3 + bw * 2.5);
			float yl = deck - thick - RN_FIX_DROP;
			if (t > rn_e[i].x - 2.0 && t < rn_e[i].y + 2.0) {
				float ft = mod(t - (rn_e[i].x - 2.0) + RN_FIX_PITCH * 0.5, RN_FIX_PITCH) - RN_FIX_PITCH * 0.5;
				glow += col * 3.0 * rn_line(ft, 0.25 + bw) * rn_line(h.y - yl, 0.12 + bw * 2.0);
			}
			if (h.y > deck - thick && h.y < deck + 1.25 && lam < best_l) {
				// The fascia: dark concrete, its foot lit by the fixtures' spill, the parapet half see-through.
				float foot = smoothstep(deck - thick + 0.6, deck - thick, h.y);
				vec3 fc = vec3(0.30, 0.285, 0.255) * (0.025 + col * 0.35 * foot);
				best = vec4(fc, h.y > deck + 0.15 ? 0.55 : 1.0);
				best_l = lam;
			}
		}
	}
	return best;
}
