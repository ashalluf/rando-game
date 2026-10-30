shader_type spatial;
render_mode cull_back;

// The freeway deck's driving surface (FreewayKit's `top` mesh, FreewayCloseup): Los Angeles's
// elevated freeways are portland cement concrete - lane-wide slabs with skewed transverse joints at
// Caltrans's repeating 12-13-19-18 ft spacing, longitudinal tining (or diamond grinding) a few
// millimetres deep - with stretches overlaid in asphalt whose cracks mirror the slab joints under
// it. Seen from the chase camera at speed what reads is the wear: two polished, rubber-darkened
// wheel paths a lane, the dark oil-drip band down every lane's middle, the odd set of skid marks,
// replaced and patched slabs, cracked corners, a milled rumble strip and grit, litter and weeds
// along the shoulders, water in the wheel ruts and the gutters when it rains.
//
// UV = (metres along the route, metres across from the deck's centre line, signed); UV2 = (the
// deck's half width, the lane layout: route + 1 for a main deck - Freeway.lane_layout()'s numbers,
// copied below and checked by tests/freeway_closeup_checks.gd -, 0 for a ramp or a connector,
// which gets lanes of `ramp_lane` from its left edge). Works in LINEAR on both renderers
// (color_space.gdshaderinc). Everything finer than a pixel fades to its average (fwidth).

#include "res://shaders/color_space.gdshaderinc"

global uniform float road_wetness;

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// The scans' linear means (PropFactory.TEXTURE_MEAN), so they add detail round our own colours.
uniform float concrete_mean = 0.4818;
uniform float asphalt_mean = 0.1300;
uniform float tex_metres = 3.0;
uniform float asphalt_metres = 6.0;

// Freeway.lane_layout() (checked): the median strip's lane line, the lane width's ceiling, the
// shoulder the barrier toe leaves, the inset of the barrier toe from the deck edge, the lanes.
uniform float lane_inner = 1.305;
uniform float lane_max = 3.6;
uniform float outer_shoulder_min = 1.2;
uniform float outer_inset = 0.42;
uniform float lanes = 4.0;
uniform float ramp_lane = 3.6;

// LINEAR albedos: weathered concrete (warm pale grey in the sun), a replaced slab, the asphalt
// overlay, the shoulder's grit, rubber, oil.
uniform vec3 concrete_color = vec3(0.158, 0.153, 0.141);
uniform vec3 fresh_color = vec3(0.205, 0.199, 0.184);
uniform vec3 overlay_color = vec3(0.070, 0.068, 0.066);
uniform vec3 patch_color = vec3(0.050, 0.049, 0.048);
uniform vec3 grit_color = vec3(0.170, 0.150, 0.118);
uniform vec3 rubber_color = vec3(0.030, 0.030, 0.031);
uniform vec3 oil_color = vec3(0.045, 0.042, 0.038);
uniform vec3 weed_color = vec3(0.040, 0.058, 0.022);
uniform vec3 dry_weed_color = vec3(0.150, 0.120, 0.060);
uniform vec3 sealant_color = vec3(0.020, 0.020, 0.021);

// Slab joints: the four-slab cycle (metres), the skew (along per metre across), the sealant width.
uniform vec4 joint_cycle = vec4(3.66, 3.96, 5.79, 5.49);
uniform float joint_skew = 0.1667;
uniform float joint_width = 0.007;
// Tining: groove pitch and depth (as a normal tilt).
uniform float tine_pitch = 0.019;
uniform float tine_tilt = 0.55;
// How much of the deck is asphalt overlay (stretches of `overlay_stretch` metres a route).
uniform float overlay_share = 0.28;
uniform float overlay_stretch = 520.0;
// Per-slab rolls: a replaced slab, a cracked one, an asphalt patch in one.
uniform float replaced_share = 0.07;
uniform float cracked_share = 0.14;
uniform float patched_share = 0.05;
// Wear in the lanes (0..1 each).
uniform float wheel_wear = 0.8;
uniform float oil_amount = 0.85;
uniform float skid_share = 0.16;
uniform float grit_amount = 0.85;
uniform float weed_share = 0.32;
// Rumble strip on the outer shoulder: milled dimples (along pitch, along length, across width).
uniform vec3 rumble = vec3(0.30, 0.18, 0.40);

varying vec3 w_pos;


uint ihash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}


float h01(uint x) {
	return float(ihash(x) & 0xFFFFFFu) / 16777216.0;
}


uint key2(float a, float b) {
	return ihash(uint(int(a) + 65536) * 2654435761u + uint(int(b) + 4096) * 40503u);
}


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}


float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.11 + 3.3) * 0.2;
}


// A soft line at distance `d` of half width `w`, faded to its coverage once under a pixel (`px`).
float aa_line(float d, float w, float px) {
	float ww = max(w, px * 0.5);
	return (1.0 - smoothstep(ww - px * 0.5, ww + px * 0.5, abs(d))) * min(1.0, w / ww);
}


void vertex() {
	w_pos = VERTEX;
}


void fragment() {
	float s = UV.x;
	float x = UV.y;
	float half_w = UV2.x;
	float route = UV2.y;
	float a = abs(x);
	bool main_deck = route > 0.5;
	// Pixel footprint in metres along and across.
	float px_s = max(fwidth(s), 0.0004);
	float px_x = max(fwidth(x), 0.0004);
	float px = max(px_s, px_x);

	// --- Lanes ------------------------------------------------------------------------------
	// Distance from the lane's centre, which lane, and whether this is a shoulder.
	float lw;
	float lane_f;
	float inner_edge;
	float outer_edge;
	float toe;
	if (main_deck) {
		toe = half_w - outer_inset;
		lw = min(lane_max, (toe - outer_shoulder_min - lane_inner) / lanes);
		inner_edge = lane_inner;
		outer_edge = lane_inner + lw * lanes;
		lane_f = (a - lane_inner) / lw;
	} else {
		toe = half_w - 0.38;
		float n = max(1.0, floor(toe * 2.0 / ramp_lane));
		lw = toe * 2.0 / n;
		inner_edge = -toe;
		outer_edge = toe;
		lane_f = (x + toe) / lw;
		a = x + half_w;
	}
	float lane_i = floor(lane_f);
	float in_lane = main_deck ? step(lane_inner, a) * step(a, outer_edge) : 1.0;
	float lc = (fract(lane_f) - 0.5) * lw;  // metres from the lane's centre
	// Which way traffic runs in this carriageway (for the skid marks' and the slab ids' sides).
	float side = x >= 0.0 ? 1.0 : -1.0;
	float lane_id = main_deck ? (lane_i + (side > 0.0 ? 10.0 : 20.0)) : lane_i;

	// --- Slabs ------------------------------------------------------------------------------
	float cyc = joint_cycle.x + joint_cycle.y + joint_cycle.z + joint_cycle.w;
	float sk = s - x * joint_skew;
	float c_i = floor(sk / cyc);
	float r = sk - c_i * cyc;
	float j0 = joint_cycle.x;
	float j1 = j0 + joint_cycle.y;
	float j2 = j1 + joint_cycle.z;
	float sub = r < j0 ? 0.0 : (r < j1 ? 1.0 : (r < j2 ? 2.0 : 3.0));
	float start = sub < 0.5 ? 0.0 : (sub < 1.5 ? j0 : (sub < 2.5 ? j1 : j2));
	float slab_len = sub < 0.5 ? joint_cycle.x : (sub < 1.5 ? joint_cycle.y : (sub < 2.5 ? joint_cycle.z : joint_cycle.w));
	float t_in = r - start;  // metres into this slab
	float d_tj = min(t_in, slab_len - t_in);
	float slab_i = c_i * 4.0 + sub;
	// Lanes are one slab wide; the shoulders are their own slabs.
	float strip_i = main_deck ? (in_lane > 0.5 ? lane_id : (a < lane_inner ? 30.0 : 31.0) + (side > 0.0 ? 0.0 : 4.0)) : lane_i;
	float d_lj = main_deck ? abs(fract((a - lane_inner) / lw + 0.5) - 0.5) * lw : abs(fract(lane_f + 0.5) - 0.5) * lw;
	if (main_deck && a > outer_edge) {
		d_lj = min(abs(a - outer_edge), abs(toe - a));
	} else if (main_deck && a < lane_inner) {
		d_lj = abs(a - lane_inner);
	}
	uint slab_key = key2(slab_i, strip_i * 3.0 + route * 41.0);
	float roll_tone = h01(slab_key);
	float roll_kind = h01(slab_key + 1u);

	// Overlay stretches: a hash of the route and the stretch, with a ragged transverse seam.
	float st_i = floor((s + vnoise(vec2(x * 0.3, 2.0)) * 3.0) / overlay_stretch);
	bool overlay = h01(key2(st_i, route * 7.0 + 900.0)) < overlay_share;

	// --- Base colour ------------------------------------------------------------------------
	vec2 tuv = vec2(x, s) / tex_metres;
	vec3 ctex = cs_in(texture(concrete_tex, tuv).rgb);
	vec3 cn = texture(concrete_nrm, tuv).rgb * 2.0 - 1.0;
	vec2 auv = vec2(x, s) / asphalt_metres;
	vec3 atex = cs_in(texture(asphalt_tex, auv).rgb);
	vec3 an = texture(asphalt_nrm, auv).rgb * 2.0 - 1.0;
	float ctl = dot(ctex, vec3(0.3333)) / concrete_mean;
	float atl = dot(atex, vec3(0.3333)) / asphalt_mean;

	bool replaced = !overlay && roll_kind < replaced_share;
	bool cracked = !overlay && !replaced && roll_kind > 1.0 - cracked_share;
	bool patched = !overlay && roll_kind > replaced_share && roll_kind < replaced_share + patched_share;
	vec3 slab_col = replaced ? fresh_color : concrete_color * (0.9 + 0.2 * roll_tone);
	// Big soft blotches: curing, staining, sun.
	float blot = fbm(vec2(s, x) * 0.11 + route * 3.7);
	float blot2 = fbm(vec2(s, x) * 0.9 + 17.0);
	vec3 alb = slab_col * mix(1.0, ctl, 0.7) * (0.8 + 0.32 * blot) * (0.9 + 0.2 * blot2);
	vec2 slope = cn.xy * 0.35;
	float rough = 0.84;
	float tine = replaced ? 1.0 : 0.75;  // how crisp the tining is

	// --- Joints and cracks ------------------------------------------------------------------
	float joint = 0.0;
	float crack = 0.0;
	if (!overlay) {
		// Sealant in the sawn joints, a little spalling (chipped edges) along them.
		float spall = smoothstep(0.75, 0.95, vnoise(vec2(s * 4.0, x * 4.0))) * 0.02;
		joint = max(aa_line(d_tj, joint_width + spall, px), aa_line(d_lj, joint_width * 0.8 + spall * 0.6, px));
		if (cracked) {
			// One crack per cracked slab: a corner break or a crack across mid-slab, wandering.
			float k2 = h01(slab_key + 2u);
			float wob = (vnoise(vec2(s * 1.7, x * 1.7)) - 0.5) * 0.35 + (vnoise(vec2(s * 9.0, x * 9.0)) - 0.5) * 0.06;
			float d;
			if (k2 < 0.5) {
				d = t_in - slab_len * (0.35 + 0.3 * h01(slab_key + 3u)) + (lc * 0.3) + wob;
			} else {
				float cx = (k2 < 0.75 ? 1.0 : -1.0) * lc - lw * 0.15;
				d = (t_in - 1.4) * 0.7 + cx * 0.7 + wob;
			}
			crack = aa_line(d, 0.004, px) * 0.9;
		}
	} else {
		// Reflective cracks: the slab joints under the overlay show through it as ragged cracks,
		// some sealed with a tar band, and a crack along the old lane joints in places.
		float wob = (vnoise(vec2(x * 2.3, s * 0.4)) - 0.5) * 0.25 + (vnoise(vec2(x * 11.0, s)) - 0.5) * 0.05;
		float live = step(0.35, h01(slab_key + 5u));
		float sealed = step(0.6, h01(slab_key + 6u));
		crack = max(aa_line(d_tj + wob, 0.004, px) * live, aa_line(d_lj + wob * 0.6, 0.004, px) * step(0.7, h01(slab_key + 7u)));
		joint = aa_line(d_tj + wob * 0.6, 0.05, px) * live * sealed * 0.85;
		alb = overlay_color * mix(1.0, atl, 0.7) * (0.85 + 0.3 * blot);
		slope = an.xy * 0.45;
		rough = 0.86;
		tine = 0.0;
	}

	// An asphalt patch over part of a slab: a ragged rectangle, its seam tarred.
	float patch_m = 0.0;
	if (patched) {
		vec2 c0 = vec2(slab_len * (0.25 + 0.5 * h01(slab_key + 8u)), (h01(slab_key + 9u) - 0.5) * lw * 0.4);
		vec2 hs = vec2(0.6 + 1.4 * h01(slab_key + 10u), 0.5 + 0.9 * h01(slab_key + 11u));
		vec2 q = abs(vec2(t_in, lc) - c0) - hs;
		float dq = max(q.x, q.y) + (vnoise(vec2(t_in, lc) * 3.0) - 0.5) * 0.12;
		patch_m = 1.0 - smoothstep(-px, px, dq);
		float seam = aa_line(dq, 0.035, px);
		alb = mix(alb, patch_color * mix(1.0, atl, 0.7), patch_m);
		alb = mix(alb, sealant_color, seam * 0.8);
		slope = mix(slope, an.xy * 0.5, patch_m);
		tine *= 1.0 - patch_m;
		rough = mix(rough, 0.8, patch_m);
	}
	alb = mix(alb, sealant_color, max(joint * 0.6, crack * 0.75));

	// --- Lane wear ----------------------------------------------------------------------------
	float wheels = 0.0;
	float oil = 0.0;
	if (in_lane > 0.5) {
		// Two wheel paths at +-0.85 m: polished smooth, darkened by rubber, a little rutted.
		float wp = 1.0 - smoothstep(0.18, 0.42, abs(abs(lc) - 0.85) + (vnoise(vec2(s * 0.2, lane_id)) - 0.5) * 0.1);
		wheels = wp * wheel_wear * (0.75 + 0.25 * vnoise(vec2(s * 0.05, lane_id * 3.0)));
		alb = mix(alb, alb * (overlay ? 0.72 : 0.58) + rubber_color * 0.15, wheels);
		rough = mix(rough, overlay ? 0.6 : 0.5, wheels);
		tine *= 1.0 - wheels * 0.8;
		// The oil-drip band down the lane's middle: blotchy, darkest where traffic queues.
		float ob = 1.0 - smoothstep(0.18, 0.55, abs(lc) + (vnoise(vec2(s * 0.7, lane_id)) - 0.5) * 0.25);
		float drops = smoothstep(0.35, 0.8, fbm(vec2(s * 0.9, lc * 2.5) + lane_id * 5.1));
		oil = ob * (0.35 + 0.65 * drops) * oil_amount * (0.6 + 0.4 * vnoise(vec2(s * 0.013, lane_id)));
		alb = mix(alb, oil_color, oil * (overlay ? 0.45 : 0.75));
		rough = mix(rough, 0.45, oil * 0.6);
		// Skid marks: now and then two dark streaks down the wheel paths, fading in and out,
		// drifting a little across (a hard stop, a slide).
		float cell = floor(s / 46.0);
		uint sk_key = key2(cell, lane_id + route * 13.0 + 500.0);
		if (h01(sk_key) < skid_share) {
			float s0 = cell * 46.0 + h01(sk_key + 1u) * 20.0;
			float ln = 8.0 + h01(sk_key + 2u) * 26.0;
			float u = (s - s0) / ln;
			if (u > 0.0 && u < 1.0) {
				float drift = (h01(sk_key + 3u) - 0.5) * 1.4 * u * u + sin(u * 3.0 + h01(sk_key + 4u) * 6.0) * 0.08;
				float mk = max(aa_line(lc - drift - 0.8, 0.11, px_x), aa_line(lc - drift + 0.8, 0.11, px_x));
				float fade = smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.7, 1.0, u)) * (0.55 + 0.45 * vnoise(vec2(s * 2.0, lc * 8.0)));
				alb = mix(alb, rubber_color, mk * fade * 0.85);
				rough = mix(rough, 0.55, mk * fade);
			}
		}
	}

	// --- Tining -------------------------------------------------------------------------------
	// Longitudinal grooves: a tilt of the normal across the lane, faded once a groove is under
	// ~2 pixels; their average shows as a slightly rougher, darker concrete.
	float tf = tine * (1.0 - smoothstep(0.35, 1.0, px_x / tine_pitch));
	if (tine > 0.0) {
		float ph = x / tine_pitch + h01(slab_key + 12u) * 7.0 + vnoise(vec2(s * 0.5, slab_i)) * 0.6;
		float gp = fract(ph);
		// Asymmetric groove: a steep wall and a shallow one.
		float tilt = (gp < 0.35 ? -1.0 : (gp < 0.5 ? 1.6 : 0.0)) * tine_tilt;
		slope.x += tilt * tf;
		alb *= 1.0 - 0.05 * tine * (1.0 - tf) - (gp < 0.5 ? 0.06 : 0.0) * tf;
		rough = mix(rough, 0.9, tine * 0.4);
	}

	// --- Shoulders ----------------------------------------------------------------------------
	float grit = 0.0;
	if (main_deck && (a > outer_edge + 0.08 || a < lane_inner - 0.08)) {
		float to_wall = a > outer_edge ? toe - a : a - 0.305;
		grit = (1.0 - smoothstep(0.05, 0.9, to_wall)) * grit_amount * (0.55 + 0.45 * fbm(vec2(s * 0.4, x)));
		grit += smoothstep(0.55, 0.85, fbm(vec2(s * 0.15, x * 0.6) + 11.0)) * 0.35;
		alb = mix(alb, grit_color * (0.8 + 0.4 * vnoise(vec2(s, x) * 13.0)), clamp(grit, 0.0, 1.0));
		// Litter: specks of glass, plastic and paper, a few cm each, only while resolvable.
		vec2 lc2 = vec2(s, x) / 0.12;
		vec2 li = floor(lc2);
		float lr = hash12(li + route);
		if (lr > 0.992 && px < 0.06) {
			vec2 lf = fract(lc2) - 0.5;
			float sp = 1.0 - smoothstep(0.2, 0.35, length(lf));
			vec3 lcol = lr > 0.997 ? vec3(0.55, 0.53, 0.47) : (lr > 0.9945 ? vec3(0.03, 0.03, 0.035) : vec3(0.22, 0.06, 0.03));
			alb = mix(alb, lcol, sp * (1.0 - smoothstep(0.03, 0.06, px)));
		}
		// Glass glitter: a pinprick sun glint now and then.
		if (hash12(floor(vec2(s, x) / 0.05) + 3.7) > 0.997 && px < 0.03) {
			rough = min(rough, 0.08);
		}
		// Weeds where the deck meets the barrier, and up through the shoulder's cracks.
		float wz = 1.0 - smoothstep(0.02, 0.22 + 0.2 * vnoise(vec2(s * 0.8, 0.0)), to_wall);
		float patch_on = step(1.0 - weed_share, vnoise(vec2(s * 0.35, side * 7.0)));
		float tuft = smoothstep(0.45, 0.75, vnoise(vec2(s * 6.0, x * 6.0)) * 0.6 + vnoise(vec2(s * 21.0, x * 21.0)) * 0.4);
		float weed = wz * patch_on * tuft;
		weed = max(weed, crack * patch_on * 0.8);
		vec3 wcol = mix(weed_color, dry_weed_color, vnoise(vec2(s * 0.5, 3.0)));
		alb = mix(alb, wcol * (0.7 + 0.6 * vnoise(vec2(s, x) * 40.0)), weed);
		rough = mix(rough, 0.95, weed);
		slope += vec2(vnoise(vec2(s, x) * 30.0) - 0.5, vnoise(vec2(x, s) * 30.0) - 0.5) * weed * 1.2;
		// The milled rumble strip on the outer shoulder, just past the edge line.
		if (a > outer_edge && rumble.x > 0.0) {
			float ra = a - outer_edge - 0.25;
			float rs = mod(s, rumble.x) - rumble.x * 0.5;
			float inside = (1.0 - smoothstep(rumble.z * 0.5 - px, rumble.z * 0.5, abs(ra - rumble.z * 0.5)))
				* (1.0 - smoothstep(rumble.y * 0.5 - px, rumble.y * 0.5 + px, abs(rs)));
			float fade_r = 1.0 - smoothstep(0.03, 0.12, px_s);
			alb *= 1.0 - inside * 0.16 * fade_r - inside * 0.06 * (1.0 - fade_r);
			slope.y += sign(rs) * inside * 0.7 * fade_r;
			grit = max(grit, inside * 0.3);
		}
	}

	// --- Rain -----------------------------------------------------------------------------------
	// Darker and glossier everywhere; water stands in the wheel ruts and down the shoulders'
	// gutters, where it is a mirror.
	float wet = clamp(road_wetness, 0.0, 1.0);
	if (wet > 0.001) {
		float pond = clamp(wheels * 1.2 + grit * 0.6, 0.0, 1.0) * smoothstep(0.35, 0.9, wet)
			* smoothstep(0.35, 0.65, vnoise(vec2(s * 0.12, x * 0.5)) + wet * 0.3);
		alb *= mix(1.0, overlay ? 0.72 : 0.6, wet);
		rough = mix(rough, 0.16, wet * 0.85);
		rough = mix(rough, 0.03, pond);
		slope *= 1.0 - max(pond, wet * 0.5);
	}

	ALBEDO = cs_out(alb);
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = 0.5;

	// The slopes are metres up per metre (along, across) in the deck's own frame: build that frame
	// from the screen derivatives of the view-space position against UV (the deck has no tangents).
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec2 dux = dFdx(UV);
	vec2 duy = dFdy(UV);
	vec3 dp2perp = cross(dpy, NORMAL);
	vec3 dp1perp = cross(NORMAL, dpx);
	vec3 t_s = dp2perp * dux.x + dp1perp * duy.x;
	vec3 t_x = dp2perp * dux.y + dp1perp * duy.y;
	float inv = inversesqrt(max(max(dot(t_s, t_s), dot(t_x, t_x)), 1e-20));
	t_s *= inv;
	t_x *= inv;
	NORMAL = normalize(NORMAL - t_s * slope.y - t_x * slope.x);
}
