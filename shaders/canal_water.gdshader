shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// The canals' water (Canals._water()): shallow, still, a little green, and almost all of what it
// shows is what it mirrors - the houses along the canal, their lit windows and porch lights after
// dark, the sky. Screen-space reflections cannot carry that (they only mirror what is on screen,
// and the facades a canal mirrors are mostly above the frame; the web has none), so the mirror is
// worked out here: the reflected ray is followed across the canal to the bank, the garden fence
// and the row of house fronts, each a vertical plane parallel to the canal at a known offset, and
// what it meets there is drawn from a hash of the lot it lands on (a pastel wall, its windows,
// its roof line, the porch light by the door). Above the roofs it is the sky. EMITTED, scaled by
// Fresnel: a reflection does not depend on the light falling on the water, and in the albedo the
// golden-hour canal would go black. On Forward+ SSR adds the real thing on top, so the made-up
// mirror runs at `mirror_forward` there.
//
// UV.x is the offset across the canal from its centre line, UV.y the coordinate along it, UV2.x
// which way it runs (0: along z, 1: along x), UV2.y the canal's index (the hashes are per canal).
// Everything is in the mesh's local space, which for a chunk child is true world space.

#include "res://shaders/color_space.gdshaderinc"

global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform float night_factor;
global uniform float lamp_factor;
global uniform float wind_factor;
global uniform float ground_detail;
global uniform float rain_intensity;

// Where the mirrored things stand, metres across from the centre line, and their heights over
// the water. The house fronts are at about the walk + garden + front yard.
uniform float facade_offset = 13.9;
uniform float lot_width = 11.5;
uniform float bank_offset = 7.5;
uniform float bank_height = 0.95;
uniform float fence_offset = 10.0;
uniform float fence_height = 1.85;
uniform float walk_height = 0.87;
// The body of the water, LINEAR: dark, green, a little silty.
uniform vec3 deep_color = vec3(0.008, 0.017, 0.011);
uniform vec3 silt_color = vec3(0.030, 0.034, 0.020);
uniform float mirror_forward = 0.55;
uniform float mirror_gain = 0.9;
uniform float ruffle = 0.22;

varying vec3 v_local;
varying vec2 v_canal;

float wh(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float wnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(wh(i), wh(i + vec2(1.0, 0.0)), f.x), mix(wh(i + vec2(0.0, 1.0)), wh(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Small travelling wavelets: height gradient (x, z) at `p`.
vec2 wavelets(vec2 p, float t) {
	vec2 g = vec2(0.0);
	vec2 dirs[3] = vec2[](vec2(0.94, 0.34), vec2(-0.41, 0.91), vec2(0.72, -0.69));
	float lens[3] = float[](1.6, 0.9, 0.55);
	for (int i = 0; i < 3; i++) {
		float k = 6.2831853 / lens[i];
		float ph = dot(dirs[i], p) * k - sqrt(9.81 * k) * 0.4 * t;
		g += lens[i] * k * cos(ph) * dirs[i];
	}
	return g * 0.02;
}

// Pastel stucco and painted siding (linear), the canal's house colours.
vec3 house_paint(float h) {
	vec3 c[6] = vec3[](vec3(0.86, 0.84, 0.78), vec3(0.80, 0.66, 0.55), vec3(0.62, 0.74, 0.74),
		vec3(0.84, 0.80, 0.62), vec3(0.70, 0.74, 0.80), vec3(0.88, 0.86, 0.84));
	return c[int(floor(h * 5.999))];
}

// What the reflected ray (from across offset `a0`, along `b0`; direction in the canal's frame:
// `ra` across, `rb` along, `ry` up) meets: the bank, the garden fence, the house fronts, the sky.
// `day` is how lit the facades are, `px` how many metres one pixel covers there (for filtering).
vec3 mirrored(float a0, float b0, float ra, float rb, float ry, float canal, float day, vec3 sky) {
	float s = ra >= 0.0 ? 1.0 : -1.0;
	float ar = max(abs(ra), 1e-4);
	// The bank and the coping: a dark wall of plants and stone just over the water.
	float tb = max((bank_offset - a0 * s) / ar, 0.0);
	if (tb * ry < bank_height) {
		float n = wh(vec2(floor((b0 + tb * rb) * 1.3), s));
		return mix(vec3(0.020, 0.028, 0.016), vec3(0.05, 0.06, 0.04), n) * (0.4 + 0.6 * day);
	}
	// The garden fences.
	float tf = max((fence_offset - a0 * s) / ar, 0.0);
	float hf = tf * ry;
	float bf = b0 + tf * rb;
	float lot_f = floor(bf / lot_width);
	if (hf < fence_height) {
		float kind = wh(vec2(lot_f, s * 7.0 + canal));
		vec3 fc = kind < 0.45 ? vec3(0.80, 0.80, 0.76) : (kind < 0.75 ? house_paint(wh(vec2(lot_f, s + canal * 3.0))) * 0.8 : vec3(0.18, 0.12, 0.08));
		// The low hedge and flowers behind the fence from below.
		float shrub = step(walk_height + 0.9, hf);
		fc = mix(fc, vec3(0.04, 0.07, 0.03), shrub);
		return fc * (0.25 + 0.75 * day);
	}
	// The house fronts.
	float tw = max((facade_offset - a0 * s) / ar, 0.0);
	float hw = tw * ry;
	float bw = b0 + tw * rb;
	float lot = floor(bw / lot_width);
	float u = fract(bw / lot_width);
	float hr = wh(vec2(lot, s * 3.0 + canal * 11.0));
	float H = walk_height + mix(5.8, 9.6, hr);
	// Side gaps between houses: the sky shows through them over the fences.
	float gap = step(0.93, u) + step(u, 0.04);
	// A gable or hip on some: the roof line comes down toward each end of the front.
	float roof = wh(vec2(lot, s * 5.0 + canal)) < 0.5 ? 1.6 * (1.0 - abs(u - 0.5) * 2.0) : 0.35;
	if (hw < H + roof && gap < 0.5) {
		if (hw > H) {
			// The roof: clay or dark shingle.
			vec3 rc = wh(vec2(lot, 9.0 + s)) < 0.5 ? vec3(0.42, 0.16, 0.08) : vec3(0.08, 0.08, 0.08);
			return rc * (0.3 + 0.7 * day);
		}
		vec3 wall = house_paint(wh(vec2(lot, s + canal * 3.0)));
		vec3 col = wall * (0.18 + 0.82 * day);
		// Windows: a row a storey, two or three a front; the glass mirrors the sky by day and is a
		// lit room or a dark one at night.
		float y = hw - walk_height - 0.25;
		float storey = floor(y / 3.0);
		float fy = fract(y / 3.0);
		float wide = wh(vec2(lot, 13.0 + s)) < 0.45 ? 1.0 : 0.0;
		float in_x = wide > 0.5 ? step(0.14, u) * step(u, 0.86) : (step(0.14, u) * step(u, 0.38) + step(0.58, u) * step(u, 0.84));
		float in_y = step(0.27, fy) * step(fy, 0.86);
		float win = in_x * in_y * step(0.0, y);
		if (win > 0.5) {
			float lit = step(0.42, wh(vec2(lot * 7.0 + storey, s + canal))) * lamp_factor;
			vec3 glass = mix(sky * 0.55, vec3(0.03, 0.035, 0.04), 0.35 + 0.4 * night_factor);
			vec3 room = vec3(1.0, 0.62, 0.30) * (1.2 + 0.8 * wh(vec2(lot, storey + 4.0)));
			col = mix(glass, room, lit);
		}
		// The porch light by the door, smeared down the water by the ripples.
		vec2 d = vec2((u - 0.62) * lot_width, (hw - (walk_height + 2.3)) * 0.28);
		float porch = exp(-dot(d, d) * 14.0) * step(0.15, wh(vec2(lot, 21.0 + s))) * lamp_factor;
		col += vec3(1.0, 0.70, 0.36) * porch * 6.0;
		return col;
	}
	return sky;
}

void vertex() {
	v_local = VERTEX;
	v_canal = UV2;
}

void fragment() {
	vec2 p = v_local.xz;
	float t = TIME;
	float axis = v_canal.x;
	float canal = v_canal.y;
	// Still water: patches of faint ruffle drifting over glassy stretches; rings when it rains.
	float patch = wnoise(p * 0.05 + vec2(t * 0.01, -t * 0.007));
	float wind = clamp(0.15 + wind_factor * 0.6, 0.1, 1.5) * smoothstep(0.35, 0.85, patch);
	vec2 grad = wavelets(p, t) * ruffle * wind;
	if (rain_intensity > 0.01) {
		vec2 cell = floor(p * 1.4);
		vec2 f = fract(p * 1.4) - 0.5;
		float ph = fract(t * 0.9 + wh(cell));
		float r = length(f + (vec2(wh(cell + 3.1), wh(cell + 7.7)) - 0.5) * 0.5);
		float ring = sin((r - ph * 0.6) * 40.0) * (1.0 - ph) * exp(-r * 6.0);
		grad += normalize(f + 1e-4) * ring * 0.18 * rain_intensity;
	}
	vec3 n_local = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_local, 0.0)).xyz);
	vec3 n_world = n_local;
	vec3 v_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v_world, n_world);
	r.y = max(r.y, 0.002);
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - nv, 5.0);

	// The sky the water sees: the horizon colour, deepening upward, dimmed at night.
	float dark = 1.0 - 0.9 * night_factor;
	vec3 horizon = sky_tint.rgb;
	vec3 zenith = horizon * vec3(0.55, 0.70, 1.0);
	vec3 sky = mix(horizon, zenith, smoothstep(0.05, 0.6, r.y)) * dark;
	float sun = pow(max(dot(r, normalize(sun_direction)), 0.0), 300.0) * 6.0 * dark;
	sky += vec3(1.0, 0.85, 0.6) * sun;
	float day = clamp(dot(sky_tint.rgb, vec3(0.299, 0.587, 0.114)) / 0.74, 0.0, 1.3) * dark;

	// The canal's frame: across and along components of the reflected ray.
	float ra = axis < 0.5 ? r.x : r.z;
	float rb = axis < 0.5 ? r.z : r.x;
	vec3 refl = mirrored(UV.x, UV.y, ra, rb, r.y, canal, day, sky);

	// The body: dark green, silt toward the banks, a scum of leaves and pollen along the edges.
	float edge = smoothstep(3.8, 5.6, abs(UV.x));
	float scum = edge * smoothstep(0.55, 0.8, wnoise(p * 0.9 + vec2(canal * 13.0, 0.0))) * 0.8;
	vec3 body = mix(deep_color, silt_color, edge * 0.6);
	body = mix(body, vec3(0.10, 0.12, 0.05), scum);

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	float mirror = mirror_gain;
#else
	float mirror = mirror_gain * mirror_forward;
#endif
	ALBEDO = cs_out(body);
	ROUGHNESS = mix(0.03, 0.12, clamp(wind + scum, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.5;
	EMISSION = cs_out(refl * fres * mirror * (1.0 - scum * 0.8));
}
