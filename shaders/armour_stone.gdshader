shader_type spatial;
render_mode cull_back;

// The breakwater's armour (Lighthouses, LighthouseKit): quarried stone blocks of a few tonnes
// each, mapped triplanar in TRUE world metres (origin_shift) from the CC0 rock set, tinted per
// stone (the instance colour), and banded by the sea: a dark wet band and a black-olive crust of
// mussels and weed round the waterline, salt-white bird lime on the tops, everything wet in rain
// (road_wetness). `blocks` > 0 is the far copy and the mound core under the near stones: there is
// no stone geometry, so the shader cuts the surface into blocks itself (3D cells, dark crevices
// between them, each its own shade) - from a few hundred metres that IS what an armour face is.

#include "res://shaders/color_space.gdshaderinc"

global uniform vec3 origin_shift;
global uniform float road_wetness;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Texture tiles per metre, and the stone's own linear colour multiplied in.
uniform float tex_scale = 0.33;
uniform vec3 stone_tint = vec3(0.60, 0.58, 0.55);
uniform float water_y = 0.15;
// Heights over the water of the weed crust's top and the wet band's top.
uniform float crust_top = 0.85;
uniform float wet_top = 2.3;
uniform float blocks = 0.0;
uniform float block_size = 2.3;

varying vec3 v_w;
varying vec3 v_n;

vec3 h33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

float h13(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = h13(i);
	float n100 = h13(i + vec3(1, 0, 0));
	float n010 = h13(i + vec3(0, 1, 0));
	float n110 = h13(i + vec3(1, 1, 0));
	float n001 = h13(i + vec3(0, 0, 1));
	float n101 = h13(i + vec3(1, 0, 1));
	float n011 = h13(i + vec3(0, 1, 1));
	float n111 = h13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_shift;
	v_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_n);
	vec3 w = v_w;
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec2 ux = w.zy * tex_scale;
	vec2 uy = w.xz * tex_scale;
	vec2 uz = w.xy * tex_scale;
	vec3 alb = cs_in(texture(rock_albedo, ux).rgb) * bw.x + cs_in(texture(rock_albedo, uy).rgb) * bw.y + cs_in(texture(rock_albedo, uz).rgb) * bw.z;
	float rough = texture(rock_rough, ux).r * bw.x + texture(rock_rough, uy).r * bw.y + texture(rock_rough, uz).r * bw.z;
	vec3 tx = texture(rock_normal, ux).xyz * 2.0 - 1.0;
	vec3 ty = texture(rock_normal, uy).xyz * 2.0 - 1.0;
	vec3 tz = texture(rock_normal, uz).xyz * 2.0 - 1.0;
	// UDN blend: each plane's tangent-space bumps laid along the two world axes it maps.
	vec3 nw = normalize(n + bw.x * vec3(0.0, tx.y, tx.x) + bw.y * vec3(ty.x, 0.0, ty.y) + bw.z * vec3(tz.x, tz.y, 0.0));
	float shade = 1.0;
	vec3 tint = cs_srgb_to_linear(COLOR.rgb) * stone_tint;
	// COLOR.a 0 is the walkway cap in the far copy: poured concrete, no blocks, no crust.
	bool cap = COLOR.a < 0.5;
	if (cap) {
		tint = cs_srgb_to_linear(COLOR.rgb) * 1.4;
		alb = mix(vec3(0.5), alb, 0.25);
	}
	if (blocks > 0.5 && !cap) {
		// Cells of block_size: distance to the nearest and second-nearest jittered centre.
		vec3 p = w / block_size;
		vec3 ip = floor(p);
		float d1 = 9.0;
		float d2 = 9.0;
		vec3 id1 = ip;
		for (int z = -1; z <= 1; z++) {
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					vec3 c = ip + vec3(float(x), float(y), float(z));
					vec3 q = c + 0.15 + 0.7 * h33(c);
					float d = length(p - q);
					if (d < d1) {
						d2 = d1;
						d1 = d;
						id1 = c;
					} else if (d < d2) {
						d2 = d;
					}
				}
			}
		}
		float edge = (d2 - d1) * block_size;
		float px = max(length(dFdx(w)), length(dFdy(w)));
		float crev = smoothstep(0.0, 0.22 + px, edge);
		shade *= mix(0.18, 1.0, crev);
		tint *= mix(vec3(0.82), vec3(1.15), h33(id1 + 7.0));
	}
	float hy = w.y - water_y;
	float wob = vnoise(w * 0.9) * 0.5 + vnoise(w * 3.1) * 0.25;
	float crust = 1.0 - smoothstep(crust_top - 0.25, crust_top + 0.2, hy + (wob - 0.4) * 0.5);
	float wet = 1.0 - smoothstep(wet_top - 0.8, wet_top + 0.4, hy + (wob - 0.4) * 1.2);
	wet = max(wet, clamp(road_wetness, 0.0, 1.0) * 0.8);
	float lime = smoothstep(0.55, 0.85, n.y) * smoothstep(2.6, 3.4, hy) * smoothstep(0.62, 0.8, vnoise(w * 1.7) * 0.6 + vnoise(w * 6.0) * 0.4);
	vec3 col = alb * tint * shade;
	col = mix(col, vec3(0.030, 0.034, 0.024) * (0.7 + 0.6 * wob), crust * 0.92);
	col = mix(col, vec3(0.62, 0.61, 0.57), lime * 0.75);
	col *= mix(1.0, 0.55, wet * (1.0 - crust));
	if (cap) {
		col = alb * tint * mix(1.0, 0.6, clamp(road_wetness, 0.0, 1.0));
	}
	ALBEDO = cs_out(col);
	ROUGHNESS = clamp(mix(rough * 0.95, 0.18, wet * (1.0 - lime)), 0.05, 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
