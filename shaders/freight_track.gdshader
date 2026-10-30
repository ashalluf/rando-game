shader_type spatial;
render_mode cull_back;

// The freight line's track and its hardware (FreightKit's `track` mesh and tie MultiMeshes,
// FreightYard's yard tracks): what a vertex IS rides in its colour's alpha (FreightKit.T_*, alpha *
// 32), its base colour (sRGB) in the rgb. Everything is laid out in TRUE world space (positions +
// origin_shift), so nothing jumps on a re-centre.
//
//   ballast   crushed granite: a field of stones (a jittered cell per stone, lit as a dome from
//             its own bump), browned by brake dust and rust near the rails, oily down the middle
//             of each track where the locomotives drip;
//   tie       pre-stressed concrete (the main) or creosoted timber (the yard), weathered, with
//             rust weeping from each fastener;
//   rail      the running surface polished bright by the wheels, the web and foot rusted brown;
//   lens      a signal or a gate lamp, lit day and night (its brightness in UV2.x);
//   steel     galvanised masts and boxes; paint flat colour; panel the crossing's rubber panels.

#include "res://shaders/color_space.gdshaderinc"

global uniform vec3 origin_shift;
global uniform float road_wetness;
global uniform float lamp_factor;

uniform float lens_energy = 6.0;
uniform vec3 rust_color = vec3(0.17, 0.075, 0.028);
uniform vec3 dust_color = vec3(0.13, 0.085, 0.05);
uniform vec3 oil_color = vec3(0.025, 0.022, 0.02);
// How big a ballast stone is (m) and how much it bumps the light.
uniform float stone_size = 0.055;
uniform float stone_relief = 0.65;

varying vec3 tw;
varying vec3 wn;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}


// Nearest stone centre: (distance, its id hash, offset x, offset y).
vec4 stones(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	vec2 bo = vec2(0.0);
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g) * 0.8 + 0.1;
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < best) {
				best = d;
				bo = r;
				id = hash12(i + g + 0.37);
			}
		}
	}
	return vec4(sqrt(best), id, bo);
}


void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tw = w + origin_shift;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	int kind = int(round(COLOR.a * 32.0));
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	vec3 alb = base;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float px = length(fwidth(tw.xz)) + 0.0001;
	// Distance (m) from the nearest rail centre in the track's cross section, when the mesh knows it
	// (UV.y: metres across from the track centre; UV.x metres along).
	float across = UV.y;
	vec3 n_out = wn;

	if (kind == 1) {
		// Ballast: stones a few centimetres across, each its own grey, lit as a dome from its bump.
		vec4 st = stones(tw.xz / stone_size);
		float shade = 0.72 + 0.5 * st.y;
		float edge = smoothstep(0.25, 0.62, st.x);
		float detail = 1.0 - smoothstep(0.35, 1.2, px / stone_size);
		vec3 rock = base * mix(1.0, shade * (1.0 - edge * 0.45), detail);
		// The stone's dome tilts the normal (faded out once the stones are under a pixel).
		vec2 tilt = -st.zw * stone_relief * detail * (1.0 - edge);
		n_out = normalize(wn + vec3(tilt.x, 0.0, tilt.y));
		// Brake dust and rust by the rails, oil down the middle, both broken up by noise.
		float near_rail = 1.0 - smoothstep(0.08, 0.55, abs(abs(across) - 0.7175));
		float mid = 1.0 - smoothstep(0.1, 0.45, abs(across));
		float n1 = vnoise(tw.xz * vec2(0.9, 0.35));
		float n2 = vnoise(tw.xz * 4.0);
		rock = mix(rock, dust_color, clamp(near_rail * (0.35 + 0.4 * n1) * UV2.y, 0.0, 0.8));
		rock = mix(rock, oil_color, clamp(mid * smoothstep(0.35, 0.8, n1 * 0.7 + n2 * 0.3) * 0.7 * UV2.y, 0.0, 0.85));
		alb = rock;
		rough = 0.92;
	} else if (kind == 2) {
		// Concrete tie: weathered grey, rust weeping off the clips at each rail seat.
		float n = vnoise(tw.xz * 6.0) * 0.6 + vnoise(tw.xz * 23.0) * 0.4;
		alb = base * (0.82 + 0.3 * n);
		float seat = 1.0 - smoothstep(0.06, 0.32, abs(abs(across) - 0.7175));
		alb = mix(alb, rust_color, seat * (0.25 + 0.35 * vnoise(tw.xz * 11.0)));
		rough = 0.88;
	} else if (kind == 11) {
		// Timber tie: creosoted, split along the grain, sun-greyed on top.
		float grain = vnoise(vec2(tw.x * 2.0 + tw.z * 0.2, tw.z * 40.0 + tw.x * 3.0));
		float split = smoothstep(0.86, 0.95, vnoise(vec2(tw.x * 1.3, tw.z * 90.0)));
		alb = base * (0.75 + 0.45 * grain) * (1.0 - split * 0.6);
		alb = mix(alb, vec3(0.16, 0.15, 0.14), smoothstep(0.5, 0.95, wn.y) * 0.35 * vnoise(tw.xz * 3.0));
		rough = 0.9;
	} else if (kind == 3) {
		// Running surface: bright where the wheels ride (the middle of the head), dull at its edges.
		alb = vec3(0.62, 0.61, 0.6) * mix(0.75, 1.05, vnoise(tw.xz * vec2(1.0, 0.2)));
		metal = 0.95;
		rough = 0.2 + 0.15 * vnoise(tw.xz * vec2(0.3, 3.0));
	} else if (kind == 4) {
		// Web and foot: rust.
		float n = vnoise(tw.xz * vec2(3.0, 0.6) + tw.y * 4.0);
		alb = mix(rust_color, rust_color * 1.6, n) * mix(0.8, 1.0, vnoise(tw.zy * 9.0));
		metal = 0.3;
		rough = 0.8;
	} else if (kind == 5) {
		// Fasteners: dark spring steel.
		alb = vec3(0.035, 0.034, 0.033) + rust_color * 0.25 * vnoise(tw.xz * 30.0);
		metal = 0.6;
		rough = 0.55;
	} else if (kind == 6) {
		// Crossing panel: concrete with a rubber flangeway strip (UV2.x 1).
		float n = vnoise(tw.xz * 5.0) * 0.6 + vnoise(tw.xz * 19.0) * 0.4;
		alb = base * (0.8 + 0.3 * n);
		alb = mix(alb, vec3(0.02), UV2.x);
		rough = mix(0.86, 0.75, UV2.x);
	} else if (kind == 7) {
		// A lamp: lit day and night (signals are), UV2.x its brightness (0: dark glass).
		alb = base * 0.15;
		rough = 0.15;
		emit = base * lens_energy * UV2.x * (0.6 + 0.6 * max(lamp_factor, 0.0));
	} else if (kind == 8) {
		// Galvanised steel.
		float m = vnoise(tw.xz * 3.0 + tw.y * 2.0) * 0.6 + vnoise(tw.xy * 11.0) * 0.4;
		alb = base * (0.72 + 0.42 * m);
		metal = 0.65;
		rough = 0.45 + 0.25 * m;
	} else if (kind == 9) {
		// Paint.
		alb = base * (0.92 + 0.12 * vnoise(tw.xz * 5.0 + tw.y));
		rough = 0.6;
		metal = 0.1;
	} else if (kind == 10) {
		// Dirt and grit between the tracks of the yard.
		float n = vnoise(tw.xz * 0.7) * 0.5 + vnoise(tw.xz * 4.0) * 0.3 + vnoise(tw.xz * 17.0) * 0.2;
		alb = base * (0.78 + 0.4 * n);
		rough = 0.95;
	}

	float wet = clamp(road_wetness, 0.0, 1.0) * mix(0.35, 1.0, smoothstep(0.3, 0.9, wn.y));
	alb *= mix(1.0, 0.7, wet);
	rough = mix(rough, 0.3, wet * 0.7);

	NORMAL = normalize((VIEW_MATRIX * vec4(n_out, 0.0)).xyz);
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
