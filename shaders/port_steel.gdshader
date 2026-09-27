shader_type spatial;
render_mode cull_back;

// The terminal's steelwork (scripts/world/port_kit.gd): ship-to-shore cranes, yard gantries,
// bollards and fenders. The colour is the vertex colour (sRGB; times the instance colour, which
// is white for these batches), UV2.x picks a finish and UV is metres in each face's plane:
//   0 paint   1 hazard stripes (the vertex colour and black, diagonal)   2 grating
//   3 glass (lit from inside at night)   4 rubber   5 floodlight (lit at night)
//   6 cladding (panel seams and a louvre band)   7 ribbed girder (stiffeners every 2.4 m)
//   8 red obstruction light   9 accommodation windows (lit at night)
//   10 a ship's topsides: paint with the line's name and mark in big letters (UV = x, y)
// Weathering is a little dirt run down the faces and grime near the ground; UV2.y is AO.
// Colour space as in container.gdshader (`color_space_probe`).

uniform vec3 color_space_probe : source_color = vec3(0.5, 0.5, 0.5);
uniform float grime : hint_range(0.0, 1.0) = 0.35;
uniform float lamp_energy = 5.0;

global uniform float lamp_factor;
global uniform float road_wetness;

varying vec3 v_col;
varying float v_part;
varying float v_ao;
varying vec3 v_nrm;
varying vec3 v_world;
varying float v_fwd;

#include "res://shaders/port_lettering.gdshaderinc"

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 col(vec3 srgb) {
	return v_fwd > 0.5 ? to_linear(srgb) : srgb;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A line of width `w` every `pitch` along x, faded to its average under a pixel.
float lines(float x, float pitch, float w) {
	float fw = fwidth(x);
	float d = abs(fract(x / pitch + 0.5) - 0.5) * pitch;
	float l = 1.0 - smoothstep(w - fw, w + fw, d);
	return mix(l, w * 2.0 / pitch, smoothstep(0.3, 1.0, fw * 4.0 / pitch));
}

void vertex() {
	v_fwd = color_space_probe.r < 0.35 ? 1.0 : 0.0;
	v_col = v_fwd > 0.5 ? to_linear(COLOR.rgb) : COLOR.rgb;
	v_part = UV2.x;
	v_ao = UV2.y;
	v_nrm = NORMAL;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	int part = int(v_part + 0.5);
	vec3 albedo = v_col;
	float rough = 0.48;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	bool vertical = abs(v_nrm.y) < 0.5;
	if (part == 1) {
		float s = step(0.5, fract((UV.x + UV.y) / 0.9));
		albedo = mix(v_col, col(vec3(0.05, 0.05, 0.05)), s);
		rough = 0.55;
	} else if (part == 2) {
		float g = max(lines(UV.x, 0.08, 0.012), lines(UV.y, 0.3, 0.02));
		albedo *= mix(0.55, 1.0, g);
		rough = 0.75;
	} else if (part == 3) {
		albedo = col(vec3(0.03, 0.04, 0.05));
		rough = 0.06;
		metal = 0.35;
		emit = col(vec3(1.0, 0.86, 0.62)) * lamp_factor * 0.9;
	} else if (part == 4) {
		albedo = col(vec3(0.03, 0.03, 0.03));
		rough = 0.8;
	} else if (part == 5) {
		albedo = col(vec3(0.6, 0.6, 0.58));
		rough = 0.3;
		emit = col(vec3(1.0, 0.93, 0.8)) * lamp_factor * lamp_energy * step(v_nrm.y, -0.5);
	} else if (part == 6) {
		if (vertical) {
			float seam = lines(UV.x, 1.0, 0.012);
			float v = UV.y;
			// Bands of louvres, in panels along the wall.
			float lv = smoothstep(0.0, 0.02, fract(v * 7.0)) * (1.0 - smoothstep(0.6, 0.62, fract(v * 7.0)));
			float in_band = step(0.0, fract(UV.x / 6.0) - 0.08) * step(fract(UV.x / 6.0), 0.55);
			float bh = fract((v - 1.2) / 2.2);
			in_band *= step(bh, 0.45) * step(0.0, bh);
			albedo *= mix(1.0, 0.72, seam);
			albedo = mix(albedo, albedo * mix(0.55, 0.95, lv), in_band);
		}
		rough = 0.5;
	} else if (part == 7) {
		if (vertical) {
			float rib = lines(UV.x, 2.4, 0.05);
			float weld = lines(UV.y, 1.8, 0.01) * 0.4;
			albedo *= mix(1.0, 0.8, max(rib, weld));
		}
	} else if (part == 9) {
		// A ship's accommodation: rows of windows a deck apart, a few lit at night.
		if (vertical) {
			vec2 cell = vec2(UV.x / 2.0, (UV.y - 0.6) / 2.8);
			vec2 f = fract(cell);
			float win = step(0.22, f.x) * step(f.x, 0.78) * step(0.38, f.y) * step(f.y, 0.74);
			float fw = max(fwidth(cell.x), fwidth(cell.y));
			win = mix(win, 0.2, smoothstep(0.2, 0.6, fw));
			albedo = mix(albedo, col(vec3(0.05, 0.07, 0.09)), win);
			rough = mix(0.5, 0.08, win);
			float lit = step(0.45, hash12(floor(cell) + 3.0));
			emit = col(vec3(1.0, 0.85, 0.6)) * lamp_factor * 0.7 * win * lit;
		}
	} else if (part == 10) {
		// The line's name down both sides amidships, read from outside: u runs along +x on the
		// starboard (+z) side and -x on the port side. The mark ahead of it.
		float u = v_nrm.z > 0.0 ? UV.x : -UV.x;
		float h = 4.2;
		float wdt = name_width(0, h);
		float u0 = -wdt * 0.5 + 6.0;
		float cov = name_line(0, vec2(u - u0, UV.y - 2.7), h);
		vec2 mc = (vec2(u, UV.y) - vec2(u0 - 4.2, 2.7 + h * 0.5)) / 2.6;
		if (abs(mc.x) < 1.2 && abs(mc.y) < 1.2) {
			cov = max(cov, mark(0, mc, max(fwidth(mc.x), fwidth(mc.y))));
		}
		albedo = mix(albedo, col(vec3(0.92, 0.92, 0.9)), cov);
	} else if (part == 8) {
		albedo = col(vec3(0.5, 0.05, 0.03));
		emit = col(vec3(1.0, 0.08, 0.04)) * (0.8 + 3.0 * lamp_factor);
	}
	// Weathering: dirt run down the faces from every ledge, grime low down, dust on the tops.
	if (part != 3 && part != 5 && part != 8) {
		float streak = noise(vec2((v_world.x + v_world.z) * 3.1, v_world.y * 0.35));
		float runs = smoothstep(0.55, 0.9, streak) * float(vertical);
		float low = 1.0 - smoothstep(0.0, 3.0, v_world.y);
		float d = grime * (runs * 0.35 + low * 0.45 + 0.08 * noise(v_world.xz * 0.7 + v_world.y));
		albedo *= 1.0 - d * 0.5;
		if (!vertical && v_nrm.y > 0.5) {
			albedo = mix(albedo, col(vec3(0.45, 0.43, 0.4)) * 0.8, grime * 0.25);
		}
	}
	float wet = clamp(road_wetness, 0.0, 1.0) * 0.6;
	albedo *= (1.0 - wet * 0.2) * v_ao;
	rough = mix(rough, 0.2, wet);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
