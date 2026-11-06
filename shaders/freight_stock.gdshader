shader_type spatial;
render_mode cull_back;

// The freight line's rolling stock (FreightStock): locomotives and cars, near and mid levels of
// one LOD ladder per type, drawn by MultiMeshes. What a vertex is rides in UV2.x (FreightStock.P_*),
// its ambient occlusion in UV2.y, its paint (sRGB) in the vertex colour; a car's own paint is the
// instance colour (P_PAINT, P_TANK multiply it). INSTANCE_CUSTOM = (wear, seed, lamps, number):
// lamps 1 lights this unit's cab-end headlight and ditch lights, 0.5 its rear-end headlight;
// number is the last three digits of the road or car number / 1000.
//
// The weather is worked out in the car's own space (the vertex position), so every car of a type
// wears it differently by its seed: road grime and brake dust up from the trucks, rust bleeding
// down the sides in streaks, sun-faded paint, soot on the roof; tank cars with spill stains under
// the manway. Number fields draw their digits with the port's stroke font (port_lettering).

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/port_lettering.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

uniform vec3 grime_color = vec3(0.075, 0.058, 0.042);
uniform vec3 rust_color = vec3(0.19, 0.075, 0.028);
uniform float lamp_energy = 14.0;
uniform float board_energy = 2.2;
// The freight yard refcam (RcFreightYard; 0 with RC4_FREIGHT_YARD=0, the old look bit for bit):
// graffiti pieces from the street wear tag atlas on a car's sides, rust runs and grime on an
// autorack's perforated panels, the panels' sheen broken up.
uniform float rc4 = 0.0;
uniform sampler2D tag_atlas : filter_linear_mipmap, repeat_disable;
uniform float tag_odds = 0.8;
// The freight trench refcam (RcFreightTrench; 0 with RC5_FREIGHT_TRENCH=0, the old look bit for
// bit): a locomotive's top seen from a bridge - the sun fade held off its red (faded red went
// salmon pink under AgX), diesel soot round the stacks and blown back along the roof, the roofs
// and the nose top grimed, the radiator fans drawn as guards over blades.
uniform float rc5 = 0.0;

varying vec3 mp;
varying vec3 mn;
varying vec4 inst;
varying vec3 paint;
varying vec3 wz;

// FreightStock.PALETTE (sRGB), kept equal (the checks compare them).
const vec3 PALETTE[28] = vec3[](
	vec3(0.30, 0.17, 0.11), vec3(0.12, 0.12, 0.13), vec3(0.36, 0.33, 0.30), vec3(0.42, 0.20, 0.12),
	vec3(0.07, 0.07, 0.075), vec3(0.72, 0.72, 0.70), vec3(0.42, 0.17, 0.11), vec3(0.45, 0.2, 0.12),
	vec3(0.3, 0.33, 0.36), vec3(0.55, 0.42, 0.18), vec3(0.18, 0.26, 0.40), vec3(0.33, 0.12, 0.10),
	vec3(0.66, 0.65, 0.62), vec3(0.78, 0.77, 0.74), vec3(0.50, 0.44, 0.36), vec3(0.36, 0.36, 0.38),
	vec3(0.76, 0.76, 0.74), vec3(0.25, 0.30, 0.38),
	vec3(0.55, 0.15, 0.09),
	vec3(0.10, 0.24, 0.47), vec3(0.46, 0.13, 0.10), vec3(0.12, 0.33, 0.22), vec3(0.85, 0.43, 0.12),
	vec3(0.70, 0.71, 0.70), vec3(0.42, 0.16, 0.32), vec3(0.62, 0.64, 0.66), vec3(0.32, 0.34, 0.36), vec3(0.88, 0.88, 0.85));


float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), f.x), mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), f.x), f.y);
}


uint fs_ihash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}


float fs_h01(uint x) {
	return float(fs_ihash(x) & 0xFFFFFFu) / 16777216.0;
}


// Graffiti paints (linear), as river_concrete.gdshader's.
const vec3 TAG_PAINTS[10] = vec3[](
	vec3(0.70, 0.70, 0.66), vec3(0.04, 0.04, 0.045), vec3(0.62, 0.08, 0.05), vec3(0.06, 0.18, 0.55),
	vec3(0.75, 0.55, 0.06), vec3(0.08, 0.40, 0.18), vec3(0.55, 0.12, 0.45), vec3(0.85, 0.30, 0.05),
	vec3(0.30, 0.62, 0.78), vec3(0.62, 0.62, 0.62)
);


// One or two pieces on a car's side: `u` metres along the side as a viewer reads it, `v` metres
// up; `car` the car's seed and the side. Big throw-ups and roller letters low on the body, a
// handstyle or two higher; some old and flaking, now and then one buffed out in a grey patch.
vec3 freight_tags(vec3 col, float u, float v, uint car, float detail) {
	for (uint k = 0u; k < 2u; k++) {
		uint tk = car * 7u + k * 131u + 9001u;
		if (fs_h01(tk) >= (k == 0u ? tag_odds : tag_odds * 0.45)) {
			continue;
		}
		uint cell = fs_ihash(tk + 1u) % 16u;
		if (k == 0u) {
			cell = 8u + cell % 8u;
		}
		float h = k == 0u ? mix(1.5, 2.4, fs_h01(tk + 2u)) : mix(0.55, 0.95, fs_h01(tk + 2u));
		float w = h * 2.0;
		float u0 = mix(-7.5, 7.5 - w, fs_h01(tk + 3u));
		float v0 = k == 0u ? mix(1.05, 1.5, fs_h01(tk + 4u)) : mix(2.6, 3.3, fs_h01(tk + 4u));
		vec2 local = vec2((u - u0) / w, (v - v0) / h);
		if (local.x <= 0.0 || local.x >= 1.0 || local.y <= 0.0 || local.y >= 1.0) {
			continue;
		}
		vec2 cxy = vec2(float(cell % 4u), float(cell / 4u));
		vec3 m = texture(tag_atlas, (cxy + vec2(local.x, 1.0 - local.y)) / 4.0).rgb;
		vec3 fill = TAG_PAINTS[fs_ihash(tk + 5u) % 10u];
		vec3 outline = TAG_PAINTS[fs_ihash(tk + 6u) % 10u];
		float age = fs_h01(tk + 7u);
		float flake = smoothstep(0.4, 0.8, vn(vec2(u, v) * 2.3) + age * 0.4);
		float a = 0.92 * (1.0 - flake * 0.55) * (0.85 + 0.15 * detail);
		if (age > 0.88) {
			vec2 bl = abs(local - 0.5);
			float buff = 1.0 - smoothstep(0.4, 0.5, max(bl.x * 0.92, bl.y));
			col = mix(col, vec3(0.16, 0.15, 0.14), buff * 0.85);
		} else {
			col = mix(col, outline, m.g * a);
			col = mix(col, fill, m.r * a);
			col = mix(col, vec3(0.85), m.b * a * 0.8);
		}
	}
	return col;
}


void vertex() {
	mp = VERTEX;
	mn = NORMAL;
	wz = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	inst = INSTANCE_CUSTOM;
	int code = int(round(INSTANCE_CUSTOM.r));
	paint = PALETTE[clamp(code / 16, 0, 27)];
	inst.r = float(code % 16) / 15.0;
}


void fragment() {
	int part = int(round(UV2.x));
	float ao = UV2.y;
	vec3 vc = cs_srgb_to_linear(COLOR.rgb);
	float wear = inst.r;
	float seed = inst.g;
	float lamps = inst.b;
	vec3 alb = vc;
	float rough = 0.7;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float night = clamp(lamp_factor, 0.0, 1.0);
	vec2 sp = vec2(mp.z + seed * 37.0, mp.y);
	bool painted = part == 0 || part == 15;

	if (painted) {
		alb = vc * cs_srgb_to_linear(paint);
		rough = part == 15 ? 0.38 : 0.62;
		metal = 0.05;
	} else if (part == 12 || part == 7) {
		rough = 0.55;
		if (rc5 > 0.5 && lamps > -0.5) {
			// A locomotive's red and sand deepened to a worn oxide and a dusty tan: the bright
			// livery went salmon pink and cream in the sun under AgX.
			float redness = smoothstep(0.08, 0.35, vc.r - vc.g);
			alb = vc * mix(0.82, 0.6, redness);
		}
	} else if (part == 1) {
		// Dark steel, rusted where the weather sits.
		float r = vn(mp.xz * 3.0 + mp.y * 2.0 + seed * 9.0);
		alb = mix(vc, rust_color * 0.8, smoothstep(0.4, 0.9, r) * 0.6);
		rough = 0.75;
		metal = 0.35;
	} else if (part == 2) {
		rough = 0.85;
	} else if (part == 3) {
		// Cab glass: dark, glossy; a dim interior glow after dark.
		alb = vec3(0.02, 0.025, 0.03);
		rough = 0.06;
		metal = 0.3;
		emit = vec3(0.09, 0.07, 0.05) * night;
	} else if (part == 4 || part == 13 || part == 14) {
		// Lamps: the cab end's (4, 13 the ditch lights) when it leads, the rear end's (14).
		bool on = (part == 14) ? (lamps > 0.25 && lamps < 0.75) : (lamps > 0.75);
		// Ditch lights alternate side to side while the horn sounds (lamps 2).
		if (part == 13 && lamps > 1.5) {
			on = fract(TIME * 1.1 + (mp.x > 0.0 ? 0.5 : 0.0)) < 0.5;
		}
		alb = vc * 0.3;
		rough = 0.1;
		emit = on ? vc * lamp_energy * (part == 13 ? 0.8 : 1.0) : vec3(0.0);
	} else if (part == 5) {
		rough = 0.5;
		metal = 0.1;
	} else if (part == 6) {
		// A number field: the digits in the vertex colour, the rest let through to what is behind.
		// UV is the field's own: x in heights from its centre, y 0..1 up it. A car's number has six
		// digits (lamps < 0), a locomotive's four (4 and the three from the custom data).
		int num = int(round(inst.a * 1000.0));
		bool car = lamps < -0.5;
		int n = car ? 6 : 4;
		int value = car ? (100 + int(floor(seed * 899.0))) * 1000 + num : 4000 + num;
		float h = 0.72;
		float unit = h / 6.0;
		float total = float(n) * unit * ADVANCE - unit * 1.3;
		vec2 q = vec2(UV.x + total * 0.5, UV.y - (1.0 - h) * 0.5);
		float cell = floor(q.x / (unit * ADVANCE));
		float cov = 0.0;
		if (cell >= 0.0 && cell < float(n) && q.y > -unit && q.y < h + unit) {
			int k = n - 1 - int(cell);
			int d = value;
			for (int i = 0; i < 8; i++) {
				if (i >= k) {
					break;
				}
				d /= 10;
			}
			cov = ink(16 + d % 10, q - vec2(cell * unit * ADVANCE, 0.0), h);
		}
		if (cov < 0.5) {
			discard;
		}
		alb = vc;
		rough = 0.5;
		// A number board (high up a cab, or on the hood's rear) is lit.
		emit = mp.y > 4.0 ? vc * board_energy * (0.25 + 0.75 * night) : vec3(0.0);
	} else if (part == 8) {
		// Grilles and louvres: dark slats.
		float slat = smoothstep(0.35, 0.65, fract(mp.y * 22.0 + mp.z * 0.0));
		alb = vc * (0.6 + 0.6 * slat);
		if (rc5 > 0.5 && lamps > -0.5 && mn.y > 0.9) {
			// A roof fan (radius 0.78, centred on x 0, z 7.5 or 9.25): a guard of rings and
			// spokes over dark blades, the hub; its average past a pixel.
			float zc = mp.z < 8.375 ? 7.5 : 9.25;
			vec2 d = vec2(mp.x, mp.z - zc);
			float r = length(d);
			float fwr = fwidth(r) + 1e-4;
			float ring = 1.0 - smoothstep(0.012, 0.012 + fwr, abs(fract(r / 0.09) - 0.5) * 0.09);
			float ang = atan(d.y, d.x);
			float spoke = 1.0 - smoothstep(0.015, 0.015 + fwr, abs(fract(ang / 6.2832 * 8.0) - 0.5) * r * 6.2832 / 8.0);
			float blade = smoothstep(0.2, 0.5, fract(ang / 6.2832 * 4.0 + r * 0.4));
			float det = 1.0 - smoothstep(0.02, 0.08, fwr);
			vec3 fan = mix(vec3(0.012), vec3(0.035), blade * det);
			fan = mix(fan, vec3(0.09, 0.09, 0.085), max(ring, spoke) * det * 0.9 + (1.0 - det) * 0.25);
			fan = mix(fan, vec3(0.06), 1.0 - smoothstep(0.14, 0.16, r));
			alb = fan;
		}
		rough = 0.6;
		metal = 0.4;
	} else if (part == 9) {
		// Wheels: the tread polished bright, the plate rusty.
		float r = vn(mp.zy * 14.0 + seed * 3.0);
		alb = mix(rust_color * 1.2, vc, 0.5 + 0.3 * r);
		metal = 0.6;
		rough = 0.55;
	} else if (part == 10) {
		// Conspicuity tape: retroreflective, a glint at night.
		alb = vc;
		rough = 0.3;
		emit = vc * 0.35 * night;
	} else if (part == 11) {
		// The autorack's perforated panels: punched round holes on a grid, dark behind.
		vec2 g = vec2(mp.z, mp.y) / 0.045;
		g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5;
		vec2 c = fract(g) - 0.5;
		float fw = max(fwidth(g.x), fwidth(g.y));
		float hole = 1.0 - smoothstep(0.3 - fw, 0.3 + fw, length(c));
		hole = mix(hole, 0.28, smoothstep(0.2, 0.55, fw));
		alb = mix(vc * cs_srgb_to_linear(paint), vec3(0.02), hole * 0.85);
		rough = 0.55;
		metal = 0.15;
	}

	// The weather.
	if (part != 3 && part != 4 && part != 13 && part != 14 && part != 6) {
		float up = smoothstep(0.55, 0.95, mn.y);
		// Road grime and brake dust from the trucks up.
		float low = 1.0 - smoothstep(0.6, 2.6, mp.y);
		float g = low * (0.35 + 0.65 * vn(sp * vec2(0.8, 2.0))) * (0.35 + 0.65 * wear);
		alb = mix(alb, grime_color, clamp(g, 0.0, 0.85));
		if (painted || part == 12 || part == 7) {
			// Rust bleeding down the sides from the top, in streaks.
			float streak = smoothstep(0.62, 0.92, vn(vec2(sp.x * 6.0, sp.y * 0.35)) * (0.5 + 0.5 * vn(vec2(sp.x * 0.7, 3.1))));
			float from_top = smoothstep(0.0, 2.5, mp.y) * (1.0 - up);
			alb = mix(alb, rust_color, streak * from_top * wear * 0.75);
			// Sun-faded: lighter and greyer with wear, more on top.
			float fade = wear * (0.18 + 0.25 * up);
			if (rc5 > 0.5 && lamps > -0.5) {
				fade *= 0.35;
			}
			alb = mix(alb, vec3(dot(alb, vec3(0.33))) * 1.35, fade);
			// Soot and dust on the roof.
			alb = mix(alb, grime_color * 1.3, up * (0.25 + 0.5 * vn(mp.xz * 1.3 + seed * 5.0)) * (0.4 + wear));
			// A tank car's spill stains under its manway.
			if (part == 15) {
				float spill = (1.0 - smoothstep(0.5, 2.6, abs(mp.z + 0.3 * vn(vec2(mp.y * 2.0, seed * 7.0))))) * smoothstep(1.2, 4.0, mp.y)
					* smoothstep(0.4, 0.8, vn(vec2(mp.z * 3.0, mp.y * 0.6 + seed * 11.0)));
				alb = mix(alb, vec3(0.32, 0.30, 0.27), spill * 0.8);
				rough = mix(rough, 0.8, spill);
			}
		}
	}

	if (rc5 > 0.5 && lamps > -0.5 && part != 3 && part != 4 && part != 13 && part != 14 && part != 6) {
		// A locomotive's top: grimed, and diesel soot from the stacks (z 1.0-2.6) blown back along
		// the roof over the radiators, the long hood's sides darkened under them.
		float up = smoothstep(0.4, 0.9, mn.y);
		float hi = smoothstep(3.6, 4.4, mp.y);
		float gr = up * (0.5 + 0.35 * vn(mp.xz * 2.1 + seed * 7.0)) * (0.7 + 0.3 * wear);
		alb = mix(alb, grime_color * 0.42, clamp(gr, 0.0, 0.78));
		float zr = mp.z - 1.0;
		float plume = smoothstep(-0.4, 0.4, zr) * (1.0 - smoothstep(1.6, 9.5, zr));
		float width = 0.45 + 0.08 * zr;
		float core = 1.0 - smoothstep(width * 0.5, width, abs(mp.x + 0.12 * sin(zr * 0.9 + seed * 6.0)));
		float soot = plume * core * hi * (0.55 + 0.45 * vn(vec2(mp.x * 3.0, mp.z * 1.2) + seed * 3.0));
		alb = mix(alb, vec3(0.012, 0.011, 0.010), clamp(soot * 1.1, 0.0, 0.92));
		rough = mix(rough, 0.9, soot);
	}

	vec3 n_tilt = vec3(0.0);
	if (rc4 > 0.5 && lamps < -0.5 && (painted || part == 11) && abs(mn.x) > 0.6) {
		// The perforated panels weather too (they were skipped): grime up from the sill, rust
		// runs from the top chord, a sun-faded patchiness panel to panel.
		if (part == 11) {
			float panel = vn(vec2(floor(mp.z / 1.55) * 3.7 + seed * 13.0, 0.5));
			alb *= 0.86 + 0.24 * panel;
			float streak = smoothstep(0.58, 0.9, vn(vec2(sp.x * 5.0, sp.y * 0.3)) * (0.55 + 0.45 * vn(vec2(sp.x * 0.6, 7.7))));
			alb = mix(alb, rust_color * 1.2, streak * smoothstep(1.5, 5.2, mp.y) * (0.25 + 0.6 * wear) * 0.7);
			alb = mix(alb, grime_color * 1.6, (1.0 - smoothstep(1.2, 2.8, mp.y)) * (0.3 + 0.4 * vn(sp * vec2(0.9, 2.4))) * 0.8);
			rough = 0.7;
			// The side is a row of pressed panels between posts, not one sheet: each panel leans a
			// little its own way (it catches the sun differently), dark deck rails cross it at the
			// two deck levels.
			float pid = floor(mp.z / 1.55);
			float lean = (h12(vec2(pid, seed * 31.0)) - 0.5) * 0.22;
			n_tilt = vec3(0.0, 0.0, lean);
			float deck = 0.0;
			for (int dk = 0; dk < 2; dk++) {
				float yd = dk == 0 ? 2.75 : 4.25;
				deck = max(deck, 1.0 - smoothstep(0.03, 0.07, abs(mp.y - yd)));
			}
			alb = mix(alb, vec3(0.03), deck * 0.75);
		}
		float side = sign(mn.x);
		float u = side > 0.0 ? -mp.z : mp.z;
		uint car = uint(floor(seed * 65521.0)) * 2u + (side > 0.0 ? 1u : 0u);
		float px = length(fwidth(mp.zy));
		alb = freight_tags(alb, u, mp.y, car, 1.0 - smoothstep(0.02, 0.2, px));
	}

	float wet = clamp(road_wetness, 0.0, 1.0) * smoothstep(0.2, 0.9, mn.y);
	alb *= mix(1.0, 0.75, wet);
	rough = mix(rough, 0.2, wet * 0.7);

	if (rc4 > 0.5 && n_tilt.z != 0.0) {
		NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * wz * n_tilt.z);
	}
	ALBEDO = cs_out(alb * mix(0.55, 1.0, ao));
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
