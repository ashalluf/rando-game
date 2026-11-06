shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// The street-level hardware FacadeStreet hangs on a Building's lowest storeys (downpipes, conduit,
// meter and panel boxes, wall condensers, window grilles, door lamps and steps, gooseneck sign
// lamps, shutter housings, thresholds): one mesh a building, one draw. What a face is rides in the
// vertex alpha (kind / 16, FacadeStreet.K_*), its paint in COLOR.rgb as written (sRGB, decoded
// here: vertex colours arrive raw on both renderers), UV in metres along the piece, UV2.x 1 on a
// lamp lens that is lit after dark. Linear on both renderers (color_space.gdshaderinc). Kinds
// 10-15 are ShopfrontDress's door things (coir mats, foliage, mulch, menus, hanging signs with
// an emblem in UV2.y, glazed pots).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

varying flat float kind;
varying vec3 wpos;

float fsp_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fsp_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fsp_hash(i), fsp_hash(i + vec2(1.0, 0.0)), f.x),
		mix(fsp_hash(i + vec2(0.0, 1.0)), fsp_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	kind = floor(COLOR.a * 16.0 + 0.5);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = cs_srgb_to_linear(COLOR.rgb);
	float rough = 0.55;
	float metal = 0.0;
	vec3 em = vec3(0.0);
	float px = length(fwidth(wpos));
	float mott = fsp_noise(UV * vec2(6.0, 3.0));
	if (kind < 0.5) {
		// Paint on metal: a little chalky, chipped on the edges of what gets knocked.
		c *= 0.9 + 0.2 * mott;
		rough = 0.5 + 0.15 * mott;
		metal = 0.1;
	} else if (kind < 1.5) {
		// Galvanised steel: spangled grey, dulled.
		c = vec3(0.40, 0.41, 0.40) * (0.82 + 0.3 * fsp_noise(UV * 22.0));
		rough = 0.48;
		metal = 0.7;
	} else if (kind < 2.5) {
		// Concrete: a step or a plinth, scuffed paler on its nosing.
		c *= 0.86 + 0.24 * fsp_noise(UV * 9.0);
		rough = 0.92;
	} else if (kind < 3.5) {
		// A lamp's lens: frosted, lit after dark when UV2.x says so.
		c = vec3(0.75, 0.74, 0.70);
		rough = 0.25;
		em = cs_srgb_to_linear(COLOR.rgb) * 6.0 * UV2.x * clamp(lamp_factor, 0.0, 1.0);
	} else if (kind < 4.5) {
		// A condenser's fan grille: concentric wire rings over the dark fan, the hub in the middle.
		vec2 q = UV - 0.5;
		float r = length(q);
		float ring = 1.0 - smoothstep(0.0, max(px * 2.0, 0.01), abs(fract(r / 0.03) - 0.5) * 0.03);
		ring = mix(ring, 0.35, smoothstep(0.004, 0.012, px));
		float spoke = 1.0 - smoothstep(0.0, 0.02, abs(sin(atan(q.y, q.x) * 2.0)) * r);
		float hub = 1.0 - smoothstep(0.06, 0.07, r);
		c = mix(vec3(0.03), cs_srgb_to_linear(COLOR.rgb) * 0.8, clamp(ring + spoke * 0.6 + hub, 0.0, 1.0));
		c *= step(r, 0.5);
		rough = 0.6;
		metal = 0.3;
	} else if (kind < 5.5) {
		// A meter's glass: dark, glossy.
		c = vec3(0.04, 0.045, 0.05);
		rough = 0.06;
		metal = 0.0;
	} else if (kind < 6.5) {
		// Copper line set, gone brown.
		c = vec3(0.42, 0.20, 0.10) * (0.8 + 0.3 * mott);
		rough = 0.4;
		metal = 0.85;
	} else if (kind < 7.5) {
		// Rubber, insulation, the black of a cable.
		c = vec3(0.025);
		rough = 0.75;
	} else if (kind < 8.5) {
		// Wrought iron: paint over rust, the rust showing where hands and rain go.
		float rust = smoothstep(0.62, 0.85, fsp_noise(UV * vec2(9.0, 4.0)));
		c = mix(c, vec3(0.19, 0.08, 0.035), rust * 0.6);
		rough = 0.55 + 0.3 * rust;
		metal = 0.3;
	} else if (kind < 9.5) {
		// Stone or terrazzo: a threshold, worn glossy in the middle.
		float chips = step(0.86, fsp_hash(floor(UV * 60.0)));
		c *= 0.9 + 0.15 * chips;
		rough = 0.35;
	} else if (kind < 10.5) {
		// Coir (ShopfrontDress's door mats): bristle tufts in rows, trodden darker in the middle
		// of the walk. Box faces carry UV in metres.
		vec2 q = UV * vec2(140.0, 52.0);
		float tuft = fsp_hash(floor(q));
		float row = 0.75 + 0.25 * sin(UV.y * 52.0 * 6.2832);
		float fibre = mix(0.55 + 0.6 * tuft * row, 0.82, smoothstep(0.003, 0.012, px));
		// Trodden darker in patches where feet go.
		float trod = 1.0 - 0.22 * smoothstep(0.35, 0.8, fsp_noise(UV * vec2(2.5, 3.5) + 4.0));
		c *= fibre * trod * (0.78 + 0.34 * fsp_noise(UV * 7.0));
		rough = 0.97;
	} else if (kind < 11.5) {
		// Clipped foliage (box balls, cones, grass): small leaves as a broken, lumpy cover with
		// dark gaps between them, sunlit tips paler. Faded to its mean where a leaf is under a pixel.
		vec3 p3 = wpos * 62.0;
		float lf = fsp_noise(p3.xy + p3.z * 1.7) * 0.5 + fsp_noise(p3.zy * 1.9 + 11.0) * 0.3 + fsp_noise(p3.xz * 0.37 + 5.0) * 0.2;
		float gap = smoothstep(0.18, 0.40, lf);
		float lit_tip = smoothstep(0.60, 0.85, lf);
		float near_k = 1.0 - smoothstep(0.003, 0.015, px);
		float cover = mix(0.82, (0.52 + 0.48 * gap) * (0.9 + 0.35 * lit_tip), near_k);
		c *= cover * (0.8 + 0.4 * fsp_noise(wpos.xz * 4.0 + wpos.y * 3.0));
		c = mix(c, c * vec3(1.15, 1.05, 0.75), lit_tip * near_k * 0.5);
		rough = 0.72;
	} else if (kind < 12.5) {
		// Soil under bark mulch.
		float chip = fsp_hash(floor(UV * 45.0));
		c = mix(c, vec3(0.30, 0.20, 0.12), step(0.55, chip) * 0.8) * (0.75 + 0.4 * fsp_noise(UV * 30.0));
		rough = 0.95;
	} else if (kind < 13.5) {
		// A printed menu behind glass (UV in metres over the sheet): a heading, two columns of
		// lines with prices, a rule; glossy (the glass), lit after dark (UV2.x).
		vec2 sz = vec2(0.33, 0.47);
		vec2 q = UV / sz;
		float ink = 0.0;
		float fine = 1.0 - smoothstep(0.0015, 0.005, px);
		if (q.y > 0.84 && q.y < 0.92 && abs(q.x - 0.5) < 0.30) {
			ink = step(0.35, fsp_hash(vec2(floor(q.x * 24.0), 3.0))) * fine + 0.45 * (1.0 - fine);
		} else if (q.y > 0.80 && q.y < 0.81 && abs(q.x - 0.5) < 0.38) {
			ink = 1.0;
		} else if (q.y > 0.08 && q.y < 0.76 && q.x > 0.08 && q.x < 0.92) {
			float ln = floor(q.y * 34.0);
			float on_line = step(0.45, fract(q.y * 34.0)) * step(0.18, fsp_hash(vec2(ln, 7.0)));
			float word = step(0.28, fsp_hash(vec2(floor(q.x * 40.0), ln)));
			float len = 0.45 + 0.4 * fsp_hash(vec2(ln, 1.0));
			float price = step(0.82, q.x) * step(q.x, 0.9);
			ink = on_line * (step(q.x, 0.08 + len * 0.7) * word + price) * fine + on_line * 0.35 * (1.0 - fine);
		}
		vec3 paper = c;
		vec3 ink_c = paper.r > 0.5 ? vec3(0.06, 0.05, 0.05) : vec3(0.92, 0.90, 0.84);
		c = mix(paper, ink_c, clamp(ink, 0.0, 1.0));
		rough = 0.12;
		em = c * 1.6 * UV2.x * clamp(lamp_factor, 0.0, 1.0);
	} else if (kind < 14.5 && UV2.y > 7.5) {
		// A sandwich board's slate (UV in metres over 0.49 x 0.80): chalk, hand-lettered and wiped:
		// a heading, a wavy rule, lines of specials with prices, a chalk smear over all of it.
		vec2 sz = vec2(0.49, 0.80);
		vec2 q = UV / sz;
		float seed = UV2.x * 17.0;
		float fine = 1.0 - smoothstep(0.0015, 0.006, px);
		float chalk = 0.0;
		if (q.y > 0.80 && q.y < 0.92 && abs(q.x - 0.5) < 0.36) {
			float letters = step(0.3, fsp_hash(vec2(floor(q.x * 14.0), seed))) * step(0.15, fract(q.x * 14.0)) * step(fract(q.x * 14.0), 0.85);
			chalk = letters * fine + 0.5 * (1.0 - fine);
		} else if (abs(q.y - 0.75 - 0.012 * sin(q.x * 25.0 + seed)) < 0.006 && abs(q.x - 0.5) < 0.38) {
			chalk = 1.0;
		} else if (q.y > 0.10 && q.y < 0.70 && q.x > 0.10 && q.x < 0.90) {
			float ln = floor(q.y * 11.0);
			float on_line = step(0.55, fract(q.y * 11.0)) * step(fract(q.y * 11.0), 0.85) * step(0.25, fsp_hash(vec2(ln, seed)));
			float word = step(0.32, fsp_hash(vec2(floor(q.x * 22.0), ln + seed)));
			float len = 0.35 + 0.35 * fsp_hash(vec2(ln, seed + 1.0));
			float price = step(0.72, q.x) * step(q.x, 0.86);
			chalk = on_line * (step(q.x, 0.10 + len) * word + price) * fine + on_line * 0.4 * (1.0 - fine);
		}
		vec3 tint = fsp_hash(vec2(seed, 3.0)) < 0.4 ? vec3(0.95, 0.80, 0.55) : vec3(0.92, 0.92, 0.88);
		float smear = 0.10 + 0.08 * fsp_noise(UV * vec2(9.0, 4.0) + seed);
		c = mix(c + vec3(smear * 0.35), tint * (0.75 + 0.25 * fsp_noise(UV * 90.0)), clamp(chalk, 0.0, 1.0) * 0.85);
		rough = 0.9;
	} else if (kind < 14.5) {
		// A hanging sign's painted face (UV in metres over the board): a gilt border line and the
		// trade's emblem (UV2.y) in cream, the paint a little weathered.
		vec2 sz = vec2(0.56, 0.40);
		vec2 q = UV - sz * 0.5;
		vec2 e = abs(q) - (sz * 0.5 - 0.035);
		float border = 1.0 - smoothstep(0.0, max(px, 0.004), abs(max(e.x, e.y)) - 0.006);
		float em_id = floor(UV2.y + 0.5);
		vec2 s = q / 0.13;
		float d = 1e3;
		if (em_id < 1.5) {
			// A cup and saucer, steam over it.
			d = min(length(max(abs(s - vec2(0.0, -0.15)) - vec2(0.55, 0.45), 0.0)) - 0.12, abs(length(s - vec2(0.78, -0.1)) - 0.25) - 0.07);
			d = min(d, length(max(abs(s - vec2(0.0, -0.78)) - vec2(0.95, 0.04), 0.0)) - 0.04);
			d = min(d, abs(s.x - 0.25 * sin(s.y * 6.0)) - 0.07 + step(s.y, 0.55) * 9.0 + step(1.3, s.y) * 9.0);
		} else if (em_id < 2.5) {
			// Fork and knife, crossed.
			mat2 r1 = mat2(vec2(0.82, 0.57), vec2(-0.57, 0.82));
			mat2 r2 = mat2(vec2(0.82, -0.57), vec2(0.57, 0.82));
			vec2 a1 = r1 * s;
			vec2 a2 = r2 * s;
			d = min(length(max(abs(a1) - vec2(0.07, 1.1), 0.0)) - 0.02, length(max(abs(a2 - vec2(0.0, -0.2)) - vec2(0.07, 0.9), 0.0)) - 0.02);
			d = min(d, length(max(abs(a2 - vec2(0.0, 0.85)) - vec2(0.17, 0.25), 0.0)) - 0.02);
		} else if (em_id < 3.5) {
			// A barber's pole: stripes in a rounded bar.
			float bar = length(max(abs(s) - vec2(0.28, 1.0), 0.0)) - 0.06;
			float stripe = step(0.5, fract(s.y * 1.4 + s.x * 1.4));
			if (bar < 0.0) {
				c = mix(vec3(0.85, 0.82, 0.76), vec3(0.62, 0.06, 0.05), stripe);
			}
			d = abs(bar) - 0.04;
		} else if (em_id < 4.5) {
			// A price tag with its hole.
			vec2 t = mat2(vec2(0.87, 0.5), vec2(-0.5, 0.87)) * s;
			float body = max(length(max(abs(t) - vec2(0.75, 0.42), 0.0)) - 0.06, t.x - 0.75 + abs(t.y) * 0.9);
			d = max(body, 0.13 - length(t - vec2(0.45, 0.0)));
		} else if (em_id < 6.5 && em_id > 5.5) {
			// Scissors: two rings and two blades.
			d = min(abs(length(s - vec2(-0.45, -0.7)) - 0.25) - 0.06, abs(length(s - vec2(0.45, -0.7)) - 0.25) - 0.06);
			d = min(d, length(max(abs(mat2(vec2(0.95, 0.3), vec2(-0.3, 0.95)) * (s - vec2(-0.15, 0.3))) - vec2(0.07, 0.8), 0.0)) - 0.02);
			d = min(d, length(max(abs(mat2(vec2(0.95, -0.3), vec2(0.3, 0.95)) * (s - vec2(0.15, 0.3))) - vec2(0.07, 0.8), 0.0)) - 0.02);
		} else {
			// A star.
			float an = atan(s.y, s.x);
			float rr = 0.75 * (0.62 + 0.38 * cos(5.0 * an - 1.5708) * 0.5 + 0.19);
			d = length(s) - rr;
		}
		float mark = 1.0 - smoothstep(0.0, max(px / 0.13, 0.03), d);
		vec3 cream = c.r > 0.6 ? vec3(0.10, 0.09, 0.08) : vec3(0.86, 0.76, 0.48);
		c = mix(c, cream, clamp(max(border, mark), 0.0, 1.0));
		c *= 0.85 + 0.25 * fsp_noise(UV * 18.0);
		rough = 0.55;
	} else {
		// Glazed ceramic: a glossy pot, its glaze pooling darker toward the foot.
		c *= 0.85 + 0.25 * fsp_noise(UV * vec2(3.0, 9.0));
		rough = 0.16;
	}
	ALBEDO = cs_out(c);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.4;
	EMISSION = cs_out(em);
}
