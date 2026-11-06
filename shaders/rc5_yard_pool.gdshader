shader_type spatial;
render_mode cull_back;

// A back-yard pool's water (Rc5Backyard, the refcam5 `backyard_pool`): one flat quad at the
// coping's top, and the whole pool TRACED under it - the waterline a hand below the coping with a
// band of blue mosaic tile above it, the water's rippled surface, the tank under it refracted
// (white plaster walls and a floor that slopes from the shallow end to the deep end, a dark tile
// stripe down the floor, a step at the shallow end), the sun's light through the ripples as a
// caustic net on the floor and walls, the shadow the sunny wall throws into the tank, the light
// absorbed with the distance through the water (red first: deep water turns teal-blue), and on
// the surface the sky and the yard round it mirrored by fresnel. EMITTED (a reflection does not
// depend on the light falling on it; the tank's own light is worked out here from the sun), the
// albedo near black so the renderer adds only the sun's glint on the ripples. Linear on both
// renderers (color_space.gdshaderinc).
//
// UV: metres from the pool's -x / -z corner along world x / z; UV2: the pool's size (x, z).
// COLOR.r: the pool's own random (the tile's colour); COLOR.g 1 when its light is on after dark
// (HouseNights.pool_variant()). Everything else is from the
// globals: no texture.

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;
global uniform float lamp_factor;
global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform vec3 tree_sun;

// How far under the coping's top the water stands, and the tank's depth at its two ends.
uniform float water_drop = 0.09;
uniform float depth_shallow = 1.0;
uniform float depth_deep = 1.85;
// The mosaic band: from the coping down this far (above and a little under the water).
uniform float band = 0.22;
uniform float ripple = 0.05;
// Absorption per metre of water (linear, red goes first) and the light the water scatters back.
uniform vec3 absorb = vec3(0.75, 0.19, 0.11);
uniform vec3 scatter = vec3(0.012, 0.13, 0.17);
uniform vec3 plaster = vec3(0.5, 0.68, 0.73);
// The pool light after dark (the same idea as lot_yard's).
uniform vec3 night_glow = vec3(0.05, 0.55, 0.66);
uniform float night_energy = 1.1;

varying vec3 wpos;


void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


// The caustic net: two warped sine fields, sharp where they meet.
float caustic(vec2 p, float t) {
	float c1 = abs(sin(p.x * 3.3 + sin(p.y * 2.6 + t * 0.9) * 1.6 + t * 0.7));
	float c2 = abs(sin(p.y * 3.7 + sin(p.x * 2.2 - t * 0.8) * 1.6 - t * 0.6));
	float c3 = abs(sin((p.x + p.y) * 2.9 + sin((p.x - p.y) * 2.0 + t * 1.1) * 1.3 + t * 0.5));
	float m = 1.0 - min(min(c1, c2), c3);
	return pow(m, 6.0) * 0.55 + pow(m, 2.0) * 0.2;
}


// The ray from p along d to the tank's sides and floor: the distance, and which (0 floor,
// 1 the -x wall, 2 +x, 3 -z, 4 +z).
vec2 tank_hit(vec3 p, vec3 d, vec2 size, bool long_x, float hw) {
	float best = 1e6;
	float which = 0.0;
	// Walls.
	if (d.x < -1e-5) { float t = -p.x / d.x; if (t < best) { best = t; which = 1.0; } }
	if (d.x > 1e-5) { float t = (size.x - p.x) / d.x; if (t < best) { best = t; which = 2.0; } }
	if (d.z < -1e-5) { float t = -p.z / d.z; if (t < best) { best = t; which = 3.0; } }
	if (d.z > 1e-5) { float t = (size.y - p.z) / d.z; if (t < best) { best = t; which = 4.0; } }
	// The floor: y = -(hw + depth), the depth linear along the long axis.
	float len = long_x ? size.x : size.y;
	float k = (depth_deep - depth_shallow) / max(len, 0.1);
	float a = long_x ? p.x : p.z;
	float da = long_x ? d.x : d.z;
	// p.y + d.y t = -(hw + shallow + k (a + da t))
	float den = d.y + k * da;
	if (den < -1e-5) {
		float t = (-(hw + depth_shallow + k * a) - p.y) / den;
		if (t > 0.0 && t < best) { best = t; which = 0.0; }
	}
	return vec2(best, which);
}


void fragment() {
	vec2 size = max(UV2, vec2(0.5));
	bool long_x = size.x >= size.y;
	float rnd = COLOR.r;
	float t = TIME;
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 d = -V;
	vec3 o = vec3(UV.x, 0.0, UV.y);
	float hw = water_drop;
	float day = 1.0 - clamp(night_factor, 0.0, 1.0);
	vec3 sun = normalize(sun_direction);
	vec3 sun_c = tree_sun;
	if (dot(sun_c, sun_c) < 1e-4) {
		sun_c = vec3(1.0, 0.95, 0.88) * 2.2 * day * smoothstep(-0.02, 0.15, sun.y);
	}
	vec3 sky = cs_srgb_to_linear(sky_tint.rgb);
	float lamp = clamp(max(lamp_factor, night_factor), 0.0, 1.0);
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	float far = smoothstep(25.0, 70.0, dist);
	// The tile colours: a blue or a teal-green glass mosaic, a white plaster tank.
	vec3 tile = mix(vec3(0.03, 0.13, 0.36), vec3(0.03, 0.24, 0.27), step(0.6, rnd));
	vec3 col = vec3(0.0);
	vec3 n = vec3(0.0, 1.0, 0.0);
	float t1 = d.y < -1e-4 ? hw / -d.y : 1e6;
	vec3 p1 = o + d * t1;
	bool on_band = p1.x < 0.0 || p1.x > size.x || p1.z < 0.0 || p1.z > size.y;
	if (on_band) {
		// The ray meets a side above the water: the mosaic band (and its shade under the coping).
		vec2 h = tank_hit(o, d, size, long_x, hw);
		vec3 hp = o + d * h.x;
		vec2 wq = (h.y < 2.5) ? hp.zy : hp.xy;
		vec2 cell = abs(fract(wq / 0.05) - 0.5);
		float grout = smoothstep(0.38, 0.5, max(cell.x, cell.y)) * (1.0 - far);
		float chip = 0.85 + 0.3 * h21(floor(wq / 0.05) + rnd * 13.0);
		vec3 wn = h.y < 1.5 ? vec3(1, 0, 0) : (h.y < 2.5 ? vec3(-1, 0, 0) : (h.y < 3.5 ? vec3(0, 0, 1) : vec3(0, 0, -1)));
		float lit = max(dot(wn, sun), 0.0) * smoothstep(-0.02, -0.06, hp.y);
		vec3 tc = tile * chip * mix(1.0, 0.75, grout);
		col = tc * (sun_c * lit * 0.8 + sky * 0.55 + vec3(0.02));
		// A wet line where the water laps.
		col *= 1.0 - 0.35 * smoothstep(-hw + 0.05, -hw, hp.y);
	} else {
		// The surface: ripples crossing, their slope as the normal (wind, a swimmer long gone).
		vec2 q = p1.xz;
		vec2 g = vec2(0.0);
		g += vec2(0.8, 0.3) * cos(dot(q, vec2(2.3, 0.8)) * 2.6 + t * 1.5);
		g += vec2(-0.4, 0.9) * cos(dot(q, vec2(-1.0, 2.1)) * 2.9 + t * 1.2);
		g += vec2(0.5, -0.6) * cos(dot(q, vec2(1.4, -1.7)) * 4.7 + t * 2.1) * 0.5;
		g += vec2(0.3, 0.7) * cos(dot(q, vec2(3.1, 2.2)) * 3.9 - t * 2.6) * 0.35;
		n = normalize(vec3(-g.x * ripple, 1.0, -g.y * ripple));
		float ndv = clamp(dot(n, V), 0.0, 1.0);
		float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
		// Into the tank.
		vec3 r = refract(d, n, 1.0 / 1.333);
		vec2 h = tank_hit(p1, r, size, long_x, hw);
		vec3 hp = p1 + r * h.x;
		float path = h.x;
		vec3 base = plaster;
		vec3 hn = vec3(0.0, 1.0, 0.0);
		vec2 tq;
		if (h.y < 0.5) {
			tq = hp.xz;
			float along = long_x ? hp.x : hp.z;
			float across = long_x ? hp.z : hp.x;
			float width = long_x ? size.y : size.x;
			float len = long_x ? size.x : size.y;
			// A dark tile stripe down the middle of the floor, a cross bar at the deep end's wall.
			float stripe = 1.0 - smoothstep(0.1, 0.13, abs(across - width * 0.5));
			stripe *= smoothstep(0.6, 0.8, along) * (1.0 - smoothstep(len - 0.9, len - 0.7, along));
			float tbar = (1.0 - smoothstep(0.1, 0.13, abs(along - (len - 0.75)))) * step(width * 0.18, across) * step(across, width * 0.82);
			base = mix(base, tile * 0.8, max(stripe, tbar));
			// The step across the shallow end (a lighter edge, a shade in front of it).
			base *= 1.0 + 0.18 * (1.0 - smoothstep(0.42, 0.48, along)) - 0.12 * smoothstep(0.48, 0.55, along) * (1.0 - smoothstep(0.55, 0.9, along));
			hn = normalize(vec3(long_x ? (depth_deep - depth_shallow) / len : 0.0, 1.0, long_x ? 0.0 : (depth_deep - depth_shallow) / len));
		} else {
			tq = (h.y < 2.5) ? hp.zy : hp.xy;
			hn = h.y < 1.5 ? vec3(1, 0, 0) : (h.y < 2.5 ? vec3(-1, 0, 0) : (h.y < 3.5 ? vec3(0, 0, 1) : vec3(0, 0, -1)));
			// The band of mosaic runs on a little under the waterline.
			float in_band = step(-band, hp.y);
			vec2 cell = abs(fract(tq / 0.05) - 0.5);
			float grout = smoothstep(0.38, 0.5, max(cell.x, cell.y)) * (1.0 - far);
			base = mix(base, tile * mix(1.0, 0.75, grout), in_band);
		}
		// Plaster mottle (pebble finish) and a little dirt in the deep end's corners.
		base *= 0.9 + 0.2 * h21(floor(tq * 9.0) + 0.5) * (1.0 - far);
		// The sun into the water: bent at the surface, shadowed by the sunny side wall.
		vec3 sr = refract(-sun, vec3(0.0, 1.0, 0.0), 1.0 / 1.333);
		vec3 su = -sr;
		float back_t = (-hw - hp.y) / max(su.y, 1e-3);
		vec2 exit_p = hp.xz + su.xz * back_t;
		float m = 0.04;
		float shadow = smoothstep(-m, m, exit_p.x) * smoothstep(-m, m, size.x - exit_p.x) * smoothstep(-m, m, exit_p.y) * smoothstep(-m, m, size.y - exit_p.y);
		float ndl = max(dot(hn, su), 0.0);
		float cst = caustic(exit_p * 1.15, t) * (1.0 - far);
		float down = back_t;
		vec3 trans_sun = exp(-absorb * down);
		vec3 trans_view = exp(-absorb * path);
		vec3 light = sun_c * ndl * shadow * trans_sun * (0.5 + 0.9 * cst) + sky * 0.55 * exp(-absorb * (-hp.y)) + vec3(0.01);
		vec3 body = base * light * trans_view;
		// What the water scatters back along the view: more the longer the path.
		vec3 inscatter = scatter * (sun_c * 0.25 + sky * 0.6) * (1.0 - exp(-path * 0.9));
		// After dark: the pool light in the deep end's wall.
		vec3 glow = night_glow * night_energy * lamp * step(0.5, COLOR.g) * (0.55 + 0.45 * exp(-path * 0.3)) * (0.8 + 0.3 * cst);
		vec3 water = (body + inscatter + glow) * (1.0 - fres);
		// The mirror: what stands round a back yard pool, by the reflected ray's elevation - the
		// fence low down (weathered wood, its boards), the neighbours' walls and the trees over it,
		// then the sky; the ripples break the bands up. Never a clean sky at a grazing look.
		vec3 R = reflect(d, n);
		float el = clamp(R.y, 0.0, 1.0);
		float az = atan(R.z, R.x);
		vec3 sky_r = sky * mix(1.05, 0.55, smoothstep(0.35, 0.95, el));
		vec3 amb = sky * 0.4 + sun_c * 0.14 * day;
		float wob = 0.03 * sin(az * 23.0 + g.x * 2.0);
		float fence_top = 0.16 + 0.03 * sin(az * 3.0 + rnd * 9.0);
		float roof_top = 0.3 + 0.1 * h21(vec2(floor(az * 2.5 + rnd * 7.0), 1.0));
		vec3 fence_c = vec3(0.30, 0.22, 0.15) * (0.8 + 0.3 * h21(vec2(floor(az * 90.0), 2.0)) * (1.0 - far)) * amb;
		vec3 wall_c = mix(vec3(0.42, 0.40, 0.34), vec3(0.08, 0.12, 0.06), step(0.55, h21(vec2(floor(az * 5.0 + rnd * 3.0), 4.0)))) * amb;
		vec3 yard_c = mix(fence_c, wall_c, smoothstep(fence_top - 0.01, fence_top + 0.01, el + wob));
		float yard = 1.0 - smoothstep(roof_top - 0.02, roof_top + 0.02, el + wob);
		vec3 mir = mix(sky_r, yard_c, yard) * fres * mix(1.0, 0.55, night_factor);
		col = water + mir;
	}
	ALBEDO = cs_out(vec3(0.01));
	ROUGHNESS = 0.04;
	SPECULAR = on_band ? 0.2 : 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	EMISSION = cs_out(col);
}
