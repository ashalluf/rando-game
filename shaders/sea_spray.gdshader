// The spray of the life in the water (scripts/world/sea_life.gd): a dolphin breaking the
// surface, a pelican's plunge, a sea lion going in off the buoy, a whale's blow. One mesh of 14
// camera-facing quads (SeaLifeMesh._spray: UV the corner, UV2.x a seed, UV2.y the index / 16),
// each a clump the vertex stage flies from the instance's origin by its age; nothing per clump
// on the CPU.
// Per instance, INSTANCE_CUSTOM: .x age (seconds), .y kind (0 a splash, 1 a big plunge, 2 a
// whale's blow, a V of two plumes), .z size (1 a dolphin's), .w the wind's lean (m/s across).
// Unshaded: white water lit by the day, dimmed at night. Linear (color_space.gdshaderinc).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, skip_vertex_transform;

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;

uniform float brightness = 0.92;
// rc5-sea-life (SeaLifeSpray.LOOK, SEA_SPRAY=0 the A/B): flat white water on the sea, streaked
// throws and the surfacing rings; 0 is the old camera-facing clumps.
uniform float look2 = 0.0;
// 1 paints each clump by its seed (red) and index (green), opaque: what the vertex stage got.
uniform int debug = 0;

varying vec2 v_dbg;

varying float v_fade;
varying vec2 v_uv;
varying float v_seed;
varying float v_kind;
varying float v_age;
varying float v_streak;
varying float v_stretch;

void vertex() {
	float age = INSTANCE_CUSTOM.x;
	float k = floor(INSTANCE_CUSTOM.y + 0.5);
	float size = INSTANCE_CUSTOM.z;
	float r = UV2.x;
	float idx = floor(UV2.y * 16.0 + 0.5);
	float r2 = fract(r * 7.13 + 0.31);
	float r3 = fract(r * 3.71 + 0.57);
	vec3 off = vec3(0.0);
	float rad = 0.3;
	float fade = 0.0;
	// look2 (SeaLifeSpray, rc5-sea-life): the white water round the hole lies FLAT on the sea and
	// spreads, the thrown water flies as streaks along its own velocity; 0 = the old clumps.
	bool flat_q = false;
	bool streak = false;
	vec3 vel = vec3(0.0, 1.0, 0.0);
	if (k > 2.5) {
		// A ring: the slick and ripple where a back broke the surface or a bird sat down (look2).
		float ang = r * 6.2831853 + idx * 1.7;
		float spread = 0.25 + 0.55 * smoothstep(0.0, 3.0, age);
		off = vec3(cos(ang) * 0.35 * size, 0.06, sin(ang) * 0.35 * size) * step(idx, 1.5);
		rad = (0.9 + 1.6 * spread) * size;
		fade = smoothstep(0.0, 0.25, age) * (1.0 - smoothstep(1.5, 4.0, age)) * step(idx, 1.5) * step(0.5, look2);
		rad *= step(idx, 1.5);
		flat_q = true;
		v_kind = 3.0;
	} else if (k < 1.5) {
		// A splash: clumps of droplets thrown up and out and falling back; the first four stay
		// low and wide, the white water on the surface round the hole.
		float big = k;
		float ang = r * 6.2831853 + idx * 2.4;
		float low = step(idx, 3.5);
		float h = mix(0.5 + r2 * 1.3, 1.6 + r2, low) * (1.0 + big * 0.6) * size;
		float v0 = mix(2.6 + r3 * 3.2, 0.5, low) * (1.0 + big * 0.7) * sqrt(size);
		float rate = 0.85 + r2 * 0.3;
		float t = age * rate;
		off = vec3(cos(ang) * h * t * 1.2, max(v0 * t - 4.9 * t * t, -0.1 * low), sin(ang) * h * t * 1.2);
		vel = vec3(cos(ang) * h * 1.2, v0 - 9.8 * t, sin(ang) * h * 1.2) * rate;
		float life = mix(0.8 + r3 * 0.5, 2.2, low) + big * 0.5;
		rad = mix(0.12 + 0.35 * t + r * 0.12, 0.5 + 0.9 * t, low) * size * (1.0 + big * 0.5);
		fade = smoothstep(0.0, 0.04, age) * (1.0 - smoothstep(life * 0.4, life, age)) * step(-0.2, off.y);
		v_kind = mix(1.0, 0.0, low);
		if (look2 > 0.5) {
			if (low > 0.5) {
				// Lying on the water: a patch of white water that spreads and opens into lace,
				// lasting longer than the throw.
				flat_q = true;
				off = vec3(cos(ang) * (0.25 + 0.6 * t) * size, 0.05, sin(ang) * (0.25 + 0.6 * t) * size);
				rad = (0.55 + 0.75 * t + r * 0.2) * size * (1.0 + big * 0.5);
				fade = smoothstep(0.0, 0.06, age) * (1.0 - smoothstep(1.4, 3.2 + big, age));
			} else {
				streak = true;
				rad *= 0.75;
				// Gone once it is back in the water (no clump cut flat by the surface).
				fade *= smoothstep(-0.05, 0.25, off.y);
			}
		}
	} else {
		// A whale's blow: two plumes leaning out in a V, rising fast, spreading, drifting down
		// the wind and thinning away.
		float side = mod(idx, 2.0) * 2.0 - 1.0;
		float f = (floor(idx / 2.0) + r * 0.6) / 7.0;
		float rise = smoothstep(0.0, 0.9, age);
		float height = 6.5 * size * pow(f, 0.8) * (0.4 + 0.6 * rise);
		off = vec3(side * height * 0.3 + INSTANCE_CUSTOM.w * age * 0.8 * f, height, (r2 - 0.5) * 0.6 * size);
		off.y -= 0.3 * age * age * f;
		rad = (0.35 + 1.5 * f) * size * (0.6 + 0.35 * age);
		fade = smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(1.5, 5.0, age)) * (0.55 + 0.45 * (1.0 - f));
		v_kind = 2.0;
	}
	vec3 centre = (MODEL_MATRIX * vec4(off, 1.0)).xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world;
	v_stretch = 1.0;
	if (flat_q) {
		// On the water, turned by the seed so the patches do not line up.
		float a = r * 6.2831853;
		vec3 ax = vec3(cos(a), 0.0, sin(a));
		vec3 az = vec3(-sin(a), 0.0, cos(a));
		world = centre + (ax * UV.x + az * UV.y) * rad;
	} else if (streak) {
		// Stretched along the velocity as the eye sees it: a drop's path over a fraction of a
		// second, never a round ball.
		vec3 to_eye = normalize(INV_VIEW_MATRIX[3].xyz - centre);
		vec3 sv = vel - to_eye * dot(vel, to_eye);
		float sl = length(sv);
		vec3 along = sl > 0.001 ? sv / sl : up;
		vec3 across = normalize(cross(along, to_eye));
		float len = 1.0 + min(sl * 0.16, 2.2);
		world = centre + (across * UV.x * 0.55 + along * UV.y * len) * rad;
		v_stretch = len;
	} else {
		world = centre + (right * UV.x + up * UV.y) * rad;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_fade = fade;
	v_uv = UV;
	v_seed = r;
	v_age = age;
	v_streak = streak ? 1.0 : 0.0;
	v_dbg = vec2(r, idx / 16.0);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 q = v_uv;
	float d = length(q);
	vec2 o = vec2(v_seed * 17.0, v_seed * 31.0);
	float alpha;
	float tone = 1.0;
	if (v_kind > 2.5) {
		// The ring left on the sea: a band of fine foam and broken glitter round a calmer slick.
		float n = vnoise(q * 6.0 + o) * 0.6 + vnoise(q * 15.0 - o) * 0.4;
		float ang = atan(q.y, q.x);
		vec2 ap = vec2(cos(ang), sin(ang)) * 2.2 + o;
		float wob = vnoise(ap) - 0.5;
		// Broken into arcs, its radius wandering: never a drawn ellipse.
		float arcs = smoothstep(0.3, 0.6, vnoise(ap * 1.7 + 3.0));
		float band = exp(-pow((d - 0.76 + wob * 0.22 + (n - 0.5) * 0.1) / 0.085, 2.0)) * mix(0.35, 1.0, arcs);
		float inner = (1.0 - smoothstep(0.2, 0.75, d)) * 0.18;
		float px = clamp(length(fwidth(q * 15.0)) - 0.4, 0.0, 1.0);
		float lace = mix(smoothstep(0.42, 0.66, n), 0.5, px);
		alpha = (band * (0.35 + 0.65 * lace) * 0.55 + inner * lace) * (1.0 - smoothstep(0.92, 1.0, d));
		tone = 0.9;
	} else if (v_kind > 1.5) {
		// Mist: a billow thinned by noise at two scales, soft all round.
		float n = vnoise(q * 2.3 + o) * 0.6 + vnoise(q * 5.1 - o) * 0.4;
		alpha = (1.0 - smoothstep(0.15, 1.0, d + (n - 0.5) * 0.7)) * (0.5 + 0.5 * n) * 0.9;
	} else if (look2 > 0.5 && v_kind < 0.5) {
		// White water lying on the sea: solid where it is fresh, opening into lace and threads of
		// foam as it spreads and ages, its edge torn.
		float n = vnoise(q * 3.2 + o) * 0.55 + vnoise(q * 8.5 - o) * 0.3 + vnoise(q * 21.0 + o * 0.5) * 0.15;
		float px = clamp(length(fwidth(q * 8.5)) - 0.35, 0.0, 1.0);
		float open = smoothstep(0.1, 1.6, v_age);
		float ang = atan(q.y, q.x);
		float lobe = vnoise(vec2(cos(ang), sin(ang)) * 1.8 + o) - 0.5;
		float edge = 1.0 - smoothstep(0.4, 0.92, d + (n - 0.5) * 0.7 + lobe * 0.45);
		// The hole the body went through: darker, the white heaped round it.
		edge *= mix(1.0, smoothstep(0.05, 0.35, d + (n - 0.5) * 0.2), 0.6 * (1.0 - smoothstep(0.4, 1.2, v_age)));
		float lace = smoothstep(0.3 + 0.32 * open, 0.48 + 0.3 * open, mix(n, 0.55, px));
		alpha = edge * mix(1.0, lace, 0.5 + 0.45 * open) * (0.9 - 0.35 * open);
		tone = 0.92 + 0.12 * n;
	} else if (look2 > 0.5 && v_streak > 0.5) {
		// A streak of thrown water: a thin soft sheet tapering to both ends, drops strung along
		// and scattered round it, a faint veil of mist - never a solid capsule.
		float ay = abs(q.y);
		float taper = 1.0 - ay;
		float w = 0.04 + 0.22 * taper * taper;
		float core = exp(-pow(q.x / max(w, 0.02), 2.0)) * smoothstep(1.0, 0.55, ay) * 0.45;
		float beads = 0.0;
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			float by = hash2(vec2(v_seed * 13.0, fi)) * 1.7 - 0.85;
			float bx = (hash2(vec2(fi, v_seed * 7.0)) - 0.5) * (0.25 + 0.9 * abs(by));
			float br = 0.07 + 0.09 * hash2(vec2(fi * 3.1, v_seed));
			vec2 dq = vec2(q.x - bx, (q.y - by) * v_stretch * 0.6);
			beads = max(beads, 1.0 - smoothstep(br * 0.5, br, length(dq)));
		}
		float veil = vnoise(q * vec2(3.0, 1.2) + o) * 0.16 * taper;
		float px = clamp(length(fwidth(q)) * 4.0 - 0.6, 0.0, 1.0);
		alpha = max(max(core, veil), beads * mix(0.85, 0.3, px));
		tone = 1.0;
	} else {
		// Droplets: a grid of hashed dots of every size over a thin veil, sharper in the middle
		// of the throw (v_kind 1) than in the white water on the surface (0).
		vec2 g = q * mix(3.5, 6.0, v_kind) + o;
		vec2 c = floor(g);
		vec2 f = fract(g) - 0.5;
		vec2 jit = vec2(hash2(c), hash2(c + 7.1)) - 0.5;
		float sz = 0.12 + 0.28 * hash2(c + 3.3);
		float dot_a = 1.0 - smoothstep(sz * 0.6, sz, length(f - jit * 0.5));
		dot_a *= step(0.35, hash2(c + 9.7));
		float veil = (vnoise(q * 3.0 + o) * 0.5 + 0.25) * mix(0.9, 0.35, v_kind);
		alpha = max(dot_a, veil) * (1.0 - smoothstep(0.45, 1.0, d));
	}
	alpha *= v_fade;
	if (debug == 1) {
		alpha = max(alpha, 0.02) * 0.0 + 1.0;
	}
	if (alpha < 0.01) {
		discard;
	}
	float day = 1.0 - 0.85 * night_factor;
	// A blow is a column of sunlit droplets, brighter than the white water under it.
	vec3 col = vec3(brightness) * day * (0.88 + 0.12 * (1.0 - d)) * (v_kind > 1.5 && v_kind < 2.5 ? 1.35 : 1.0) * tone;
	ALBEDO = debug == 1 ? vec3(v_dbg, 0.0) : cs_out(col);
	ALPHA = alpha;
}
