shader_type spatial;
render_mode cull_back;

// The fashion district's goods (scripts/world/fashion_kit.gd): garments, fabric bolts and rolls,
// mannequins, racks, hand trucks, cartons, tables, stalls, tarps, banners and bulb strings. One
// material for all of it, so each kind is one MultiMesh draw a chunk.
//
// * COLOR.rgb is the paint (sRGB); COLOR.a the surface kind as (kind + 0.5) / 16 (FashionKit.K_*).
// * UV is metres along the surface. UV2.x a pattern (FashionKit.P_*, (p + 0.5) / 16; 15 on canvas
//   is an awning's stripes), UV2.y the fold parameter (0 shoulder .. 1 hem; 2 the end of a roll,
//   3 the end of a bolt, 4 folded stock).
// * INSTANCE_CUSTOM.r shifts the hue of a display's dyes a little (no two racks alike),
//   .g is a seed, .b how worn the canvas is.
// * Worked in linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

// Bulb strings' glow at full night and by day.
uniform float bulb_night = 7.0;
uniform float bulb_day = 0.25;
// How deep the folds of a hung garment shade, and how strong the weave reads up close.
uniform float fold_shade = 0.35;
uniform float weave = 0.12;
// Detail under a pixel fades to its average from this many pixels per weave cell.
uniform float detail_fade_px = 2.0;

varying vec3 v_local;
varying flat int v_kind;
varying float v_hue;
varying float v_seed;
varying float v_wear;

float fg_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fg_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fg_hash(i), fg_hash(i + vec2(1.0, 0.0)), f.x),
		mix(fg_hash(i + vec2(0.0, 1.0)), fg_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 fg_hue(vec3 c, float a) {
	// Rodrigues rotation about the grey axis: a hue shift that keeps luminance roughly.
	vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

void vertex() {
	v_local = VERTEX;
	v_kind = int(COLOR.a * 16.0);
	v_hue = (INSTANCE_CUSTOM.r - 0.5) * 0.5;
	v_seed = INSTANCE_CUSTOM.g;
	v_wear = INSTANCE_CUSTOM.b;
}

// A fabric pattern over `base` at uv (metres); `px` the pixel footprint in metres, so patterns
// finer than a few pixels fade to their mean.
vec3 fg_pattern(int p, vec3 base, vec2 uv, float px, inout float rough, inout float metal) {
	float fade = 1.0 - smoothstep(0.02, 0.06, px);
	vec3 alt = mix(vec3(0.92, 0.91, 0.88), base * 0.35, step(0.45, dot(base, vec3(0.333))));
	if (p == 1) {
		// Stripes: 2-3 cm bands of a lighter or darker yarn.
		float s = smoothstep(0.4, 0.6, abs(fract(uv.x * 22.0) * 2.0 - 1.0));
		return mix(base, mix(base, alt, s), fade * 0.9 + (1.0 - fade) * 0.45);
	}
	if (p == 2) {
		// Plaid: two crossing bands and their overlap.
		float a = step(0.62, fract(uv.x * 7.0));
		float b = step(0.62, fract(uv.y * 7.0));
		float t = step(0.85, fract(uv.x * 28.0)) * 0.5 + step(0.85, fract(uv.y * 28.0)) * 0.5;
		vec3 c = base;
		c = mix(c, base * 0.45, max(a, b) * 0.8);
		c = mix(c, vec3(0.75, 0.70, 0.55) * base * 1.6, t * 0.35);
		return mix(base * 0.75, c, fade);
	}
	if (p == 3) {
		// Floral: scattered blooms, petals round a centre, on the ground colour.
		vec2 g = uv * 9.0;
		vec2 cell = floor(g);
		vec2 f = fract(g) - 0.5 - (vec2(fg_hash(cell), fg_hash(cell + 7.1)) - 0.5) * 0.4;
		float r = length(f);
		float ang = atan(f.y, f.x);
		float petal = 0.22 + 0.08 * cos(ang * 5.0 + fg_hash(cell + 3.3) * 6.0);
		float bloom = 1.0 - smoothstep(petal - 0.03, petal + 0.02, r);
		float eye = 1.0 - smoothstep(0.05, 0.08, r);
		vec3 flower = mix(vec3(0.95, 0.40, 0.55), vec3(0.98, 0.90, 0.75), step(0.5, fg_hash(cell + 1.7)));
		flower = mix(flower, vec3(0.45, 0.35, 0.80), step(0.8, fg_hash(cell + 2.9)));
		vec3 c = mix(base, flower, bloom);
		c = mix(c, vec3(0.95, 0.80, 0.25), eye);
		return mix(mix(base, flower, 0.25), c, fade);
	}
	if (p == 4) {
		// Polka dots.
		vec2 g = uv * 16.0;
		g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5;
		float d = 1.0 - smoothstep(0.2, 0.27, length(fract(g) - 0.5));
		return mix(mix(base, alt, 0.18), mix(base, alt, d), fade);
	}
	if (p == 5) {
		// Satin: smooth and glossy.
		rough = 0.28;
		return base;
	}
	if (p == 6) {
		// Sequins: glints in a grid.
		vec2 g = uv * 160.0;
		float h = fg_hash(floor(g));
		rough = mix(0.2, 0.55, h);
		metal = mix(0.6, 0.85, fade);
		return base * (0.8 + 0.6 * h * fade);
	}
	if (p == 7) {
		// Lace: a net of small holes shown as the darker under-layer.
		vec2 g = uv * 40.0;
		float d = smoothstep(0.18, 0.3, length(fract(g) - 0.5));
		return mix(base * 0.85, mix(base * 0.4, base, d), fade);
	}
	if (p == 8) {
		// Camouflage: three blobs of noise.
		float n1 = fg_noise(uv * 6.0);
		float n2 = fg_noise(uv * 6.0 + 17.0);
		vec3 c = mix(vec3(0.20, 0.24, 0.13), vec3(0.42, 0.38, 0.24), step(0.5, n1));
		c = mix(c, vec3(0.10, 0.09, 0.07), step(0.62, n2));
		return c;
	}
	if (p == 9) {
		// Leopard: rosettes.
		vec2 g = uv * 14.0;
		vec2 cell = floor(g);
		vec2 f = fract(g) - 0.5 - (vec2(fg_hash(cell), fg_hash(cell + 3.1)) - 0.5) * 0.4;
		float r = length(f * vec2(1.0, 1.3));
		float ring = smoothstep(0.12, 0.16, r) * (1.0 - smoothstep(0.24, 0.3, r));
		vec3 ground = vec3(0.78, 0.55, 0.28);
		vec3 c = mix(ground, vec3(0.06, 0.04, 0.03), ring);
		c = mix(c, vec3(0.55, 0.32, 0.14), (1.0 - smoothstep(0.08, 0.12, r)) * 0.8);
		return mix(ground * 0.75, c, fade);
	}
	return base;
}

void fragment() {
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	int kind = v_kind;
	vec2 uv = UV;
	float px = length(fwidth(v_local)) + 1e-5;
	float fade = 1.0 - smoothstep(0.004, 0.012, px);
	float rough = 0.8;
	float metal = 0.0;
	float spec = 0.4;
	vec3 emit = vec3(0.0);
	vec3 nrm_t = vec3(0.0, 0.0, 1.0);
	float ao = 1.0;
	int pattern = int(UV2.x * 16.0);
	float fold = UV2.y;
	float sheen = 0.0;

	if (kind <= 3) {
		// Cloth: the dye shifted per display, a pattern, folds and the weave.
		base = max(fg_hue(base, v_hue), vec3(0.0));
		if (kind == 3 && fold > 1.5) {
			// The end of a roll (2): wound layers as rings round the tube; a bolt's end (3): the
			// fold layers as bands across the board.
			float r = fold < 2.5 ? length(uv - 0.5) * 2.0 : abs(uv.y - 0.5) * 2.0;
			float layers = 0.5 + 0.5 * sin(r * 80.0);
			base *= mix(0.72, 1.0, mix(0.5, layers, fade));
			rough = 0.85;
		} else if (fold > 3.5) {
			// Folded stock: the folded edges catch the light, the faces lie flat.
			float edge = smoothstep(0.08, 0.0, min(min(uv.x, uv.y), 0.04));
			base *= 1.0 - 0.15 * edge;
			base = fg_pattern(pattern, base, uv, px, rough, metal);
		} else {
			base = fg_pattern(pattern, base, uv, px, rough, metal);
			// Folds down a hung garment: soft vertical valleys, deeper toward the hem.
			float f = fold < 1.01 ? fold : 0.0;
			float v = 0.5 + 0.5 * sin(uv.x * 14.0 + fg_noise(vec2(uv.x * 3.0, v_seed * 13.0)) * 4.0 + uv.y * 0.6);
			ao *= 1.0 - fold_shade * f * (1.0 - v) * fade;
			// The shoulders lighter (they face the sky), the hem's inside darker.
			ao *= mix(1.0, 0.82, smoothstep(0.85, 1.0, f));
		}
		// Weave relief and roughness per kind.
		if (kind == 2) {
			// Denim: a 3/1 twill's diagonal wales, slub streaks, a faded wash on the high spots.
			float tw = sin((uv.x + uv.y) * 900.0);
			float slub = fg_noise(vec2(uv.x * 3.0, uv.y * 60.0));
			base *= mix(1.0, 0.86 + 0.28 * slub, fade);
			base = mix(base, base * 1.35 + vec3(0.02, 0.03, 0.05), 0.25 * fg_noise(uv * 4.0 + v_seed * 9.0));
			nrm_t.xy += vec2(tw, tw) * weave * fade;
			rough = 0.82;
		} else if (kind == 1) {
			float k = sin(uv.x * 1100.0) * sin(uv.y * 900.0);
			nrm_t.xy += vec2(k * 0.5, k) * weave * 0.6 * fade;
			rough = 0.9;
			sheen = 0.25;
		} else {
			float w2 = sin(uv.x * 1200.0) + sin(uv.y * 1200.0);
			nrm_t.xy += vec2(w2, -w2) * weave * 0.35 * fade;
			rough = min(rough, 0.8);
			sheen = 0.15;
		}
		spec = 0.35;
	} else if (kind == 4) {
		// Chrome tube: brushed along u.
		metal = 1.0;
		rough = 0.18 + 0.1 * fg_noise(vec2(uv.x * 200.0, uv.y * 3.0)) * fade;
		base = vec3(0.62, 0.63, 0.64);
	} else if (kind == 5) {
		// Corrugated board: the flutes as faint ribs, dirt, a tape band on the top.
		float flute = sin(uv.x * 785.0);
		nrm_t.x += flute * 0.08 * fade;
		base *= 0.9 + 0.12 * fg_noise(uv * 9.0 + UV2.x * 40.0);
		float tape = 1.0 - smoothstep(0.022, 0.026, abs(fract(uv.x * 1.0 + UV2.x) - 0.5));
		base = mix(base, base * 1.25 + vec3(0.04, 0.03, 0.0), tape * step(0.3, UV2.x) * 0.6);
		rough = mix(0.88, 0.5, tape * step(0.3, UV2.x));
	} else if (kind == 6) {
		// Canvas / tarp: a coarse weave, sun fade, an awning's stripes.
		if (pattern == 15) {
			float s = step(0.5, fract(uv.x * 4.0 + fold * 0.5));
			base = mix(base, vec3(0.86, 0.84, 0.78), s * 0.9);
		}
		float w = sin(uv.x * 600.0) * sin(uv.y * 600.0);
		nrm_t.xy += vec2(w) * 0.15 * fade;
		base *= 0.88 + 0.16 * fg_noise(uv * 0.8 + v_seed * 31.0);
		base = mix(base, vec3(dot(base, vec3(0.333))) * 1.1, 0.15 * v_wear);
		rough = 0.82;
	} else if (kind == 7) {
		// Fibreglass: a gloss lacquer (white) or satin (black).
		float dark = step(dot(base, vec3(0.333)), 0.3);
		rough = mix(0.22, 0.38, dark);
		spec = 0.5;
	} else if (kind == 8) {
		// Wood: grain along u.
		float g = fg_noise(vec2(uv.x * 2.0, uv.y * 40.0));
		base *= 0.78 + 0.35 * g;
		rough = 0.7;
	} else if (kind == 9) {
		rough = 0.42;
		spec = 0.45;
	} else if (kind == 10) {
		// Card: torn-cardboard fibres.
		base *= 0.92 + 0.1 * fg_noise(uv * 60.0);
		rough = 0.92;
	} else if (kind == 11) {
		// Marker ink.
		rough = 0.6;
	} else if (kind == 12) {
		// A bulb: frosted glass lit after dark.
		rough = 0.25;
		emit = base * mix(bulb_day, bulb_night, smoothstep(0.05, 0.6, lamp_factor));
	} else if (kind == 13) {
		rough = 0.9;
	} else if (kind == 14) {
		// Gridwall: 6 mm wires on a 76 mm square grid; the squares are cut out.
		vec2 g = abs(fract(uv / 0.0762) - 0.5);
		float wire = 0.006 / 0.0762 * 0.5;
		// Past a few pixels the grid would alias: keep a thinned mesh (a dither on the cut).
		float keep = max(step(0.5 - wire, g.x), step(0.5 - wire, g.y));
		float far_keep = step(fg_hash(floor(FRAGCOORD.xy) + v_seed), 0.18);
		float lod = smoothstep(0.003, 0.008, px);
		if (mix(keep, far_keep, lod) < 0.5) {
			discard;
		}
		metal = 0.6;
		rough = 0.5;
	} else {
		rough = 0.55;
		metal = 0.3;
	}

	// Rain darkens the cloth and canvas out on the pavement.
	float wet = clamp(road_wetness, 0.0, 1.0) * (kind <= 3 || kind == 6 || kind == 5 ? 1.0 : 0.0);
	base *= 1.0 - 0.35 * wet;
	rough = mix(rough, rough * 0.6, wet);

	ALBEDO = cs_out(base * ao);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	// The meshes carry no tangents, so the weave's relief is shading, not a normal map.
	ALBEDO *= 1.0 - 0.6 * clamp(abs(nrm_t.x) + abs(nrm_t.y), 0.0, 0.5) * 0.5;
	if (sheen > 0.0) {
		RIM = sheen;
		RIM_TINT = 0.6;
	}
	EMISSION = cs_out(emit);
}
