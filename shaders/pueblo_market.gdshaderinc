// The marketplace lane's stalls and goods (PuebloMarket, scripts/world/pueblo_market.gd): the
// puestos' timber, their striped awnings, folded and hanging sarapes, glazed and bare pottery,
// woven straw hats and baskets, leather, embroidered dresses, crepe-paper pinatas, candy, silver,
// the papel picado strung over the lane and the plaza, bulb strings and lanterns. Everything is
// built in code at real size into ONE mesh per material (solid: pueblo_market.gdshader, culled;
// thin things seen from both sides: pueblo_market_thin.gdshader), so the whole market is a few
// draws a chunk. Shader includes use // comments.
//
// Vertex data (written by PuebloMarket.Acc):
//   COLOR   rgb: the paint / dye, sRGB as authored (vertex colours arrive raw on both renderers);
//           a: the KIND, (k + 0.5) / 16 (PuebloMarket.K_*)
//   UV      metres in the face's own frame (u across, v up), or 0..1 over a paper flag
//   UV2.x   a per-piece seed 0..1 (which sarape palette, which cut pattern, which bulb)
//   UV2.y   how free the vertex is in the wind (0 fixed .. 1 a flag's free corner)
//
// Colours: worked in LINEAR on both renderers (color_space.gdshaderinc), handed over by cs_out().

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float wind_factor;
global uniform float road_wetness;

// Bulbs and lanterns: how bright after dark, and by day (a bulb in the shade still reads lit).
uniform float bulb_night = 7.0;
uniform float bulb_day = 0.25;
uniform float lantern_night = 2.6;
// How far a paper flag or a hanging blanket swings at wind 1 (metres) and how fast.
uniform float sway = 0.07;
uniform float sway_speed = 1.6;
// Light through tissue paper and canvas (the sun behind a flag lights it from behind).
uniform float paper_glow = 0.55;
// Detail under a pixel is averaged away from this many metres.
uniform float detail_fade = 40.0;

varying float v_kind;
varying float v_seed;
varying vec3 v_paint;
varying vec3 v_world;

float pm_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float pm_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(pm_hash(i), pm_hash(i + vec2(1.0, 0.0)), f.x),
		mix(pm_hash(i + vec2(0.0, 1.0)), pm_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The vivid dyes of the market, sRGB: fuchsia, orange, yellow, lime, turquoise, cobalt, purple,
// red, white, black.
const vec3 DYES[10] = vec3[](vec3(0.93, 0.13, 0.52), vec3(0.98, 0.47, 0.06), vec3(0.99, 0.82, 0.12),
	vec3(0.45, 0.78, 0.16), vec3(0.06, 0.70, 0.70), vec3(0.10, 0.30, 0.78), vec3(0.50, 0.18, 0.66),
	vec3(0.86, 0.08, 0.10), vec3(0.95, 0.93, 0.88), vec3(0.06, 0.05, 0.06));

vec3 pm_dye(float i) {
	return DYES[int(mod(i, 10.0))];
}

// How far a vertex swings in the wind (world space), from its world position, its freedom
// (UV2.y) and the time.
vec3 pm_sway(vec3 wp, float free, float t) {
	if (free <= 0.0) {
		return vec3(0.0);
	}
	float w = 0.35 + clamp(wind_factor, 0.0, 3.0);
	float ph = dot(wp.xz, vec2(0.41, 0.29));
	float s = sin(t * sway_speed + ph) + 0.35 * sin(t * sway_speed * 2.3 + ph * 1.7);
	float f = sin(t * sway_speed * 4.1 + ph * 3.1 + wp.y * 5.0);
	return vec3(0.7 * s + 0.15 * f, 0.08 * f, 0.5 * cos(t * sway_speed * 0.8 + ph) + 0.15 * f) * sway * w * free;
}

// The body of vertex() (varyings may only be written there): kind, seed, paint, sway.
#define PM_VERTEX \
	v_kind = floor(COLOR.a * 16.0); \
	v_seed = UV2.x; \
	v_paint = cs_srgb_to_linear(COLOR.rgb); \
	vec3 pm_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; \
	v_world = pm_wp; \
	VERTEX += inverse(mat3(MODEL_MATRIX)) * pm_sway(pm_wp, UV2.y, TIME);

// What a fragment is: albedo (linear), roughness, metallic, emission (linear), how much light it
// lets through from behind (0..1), and whether it is cut away.
struct PmSurf {
	vec3 albedo;
	float rough;
	float metal;
	vec3 emit;
	float through;
	bool cut;
};

// The cut pattern of a papel picado flag, uv 0..1 (v down from the string), `pick` which of four
// designs: true where the paper is cut away.
bool pm_picado_cut(vec2 uv, float pick) {
	// The fold at the top over the string, and a solid border.
	if (uv.y < 0.08) {
		return false;
	}
	// Scalloped bottom edge.
	float sc = 0.93 - 0.035 * abs(sin(uv.x * 3.14159 * 6.0));
	if (uv.y > sc) {
		return true;
	}
	vec2 b = min(uv, 1.0 - uv);
	if (b.x < 0.07 || uv.y < 0.13 || uv.y > sc - 0.05) {
		return false;
	}
	vec2 p = (uv - vec2(0.5, 0.52)) * vec2(1.0, 1.25);
	float r = length(p);
	float a = atan(p.y, p.x);
	int k = int(pick * 4.0);
	bool cut = false;
	if (k == 0) {
		// A flower: petals round a ring, a diamond lattice outside.
		float petals = 0.22 + 0.07 * cos(a * 8.0);
		cut = r < petals && r > 0.07 && fract(a * 8.0 / 6.28318 + 0.5) > 0.18 && fract(a * 8.0 / 6.28318 + 0.5) < 0.82;
		vec2 q = fract(uv * vec2(7.0, 9.0)) - 0.5;
		cut = cut || (r > 0.33 && abs(q.x) + abs(q.y) < 0.26);
	} else if (k == 1) {
		// A sun: rays and a ring of dots.
		cut = (r < 0.12) || (r > 0.17 && r < 0.3 && fract(a * 12.0 / 6.28318) < 0.45);
		vec2 q = fract(uv * vec2(6.0, 7.0)) - 0.5;
		cut = cut || (r > 0.36 && length(q) < 0.2);
	} else if (k == 2) {
		// A bird in a wreath of leaves.
		float wing = abs(p.x) * 1.4 - 0.05;
		cut = (p.y > -0.12 + wing * wing * 2.2 && p.y < 0.02 + wing * 0.6 && abs(p.x) < 0.24) || (length(p - vec2(0.0, 0.08)) < 0.05);
		float ring = abs(r - 0.36);
		cut = cut || (ring < 0.05 && fract(a * 10.0 / 6.28318) > 0.25);
	} else {
		// Hearts and stars in a grid.
		vec2 q = fract(uv * vec2(4.0, 5.0)) - 0.5;
		vec2 hq = vec2(abs(q.x), q.y + 0.08);
		float heart = length(hq - vec2(0.12, 0.0)) - 0.14;
		cut = heart < 0.0 && q.y > -0.28 + abs(q.x) * 0.9;
		cut = cut || (abs(q.x) + abs(q.y) < 0.1);
	}
	return cut;
}

// How much of a pattern of `freq` cycles a metre survives when a pixel spans `px` metres: faded
// to its average before it aliases into moire.
float pm_keep(float freq, float px) {
	return 1.0 - smoothstep(0.25, 0.6, freq * px);
}

PmSurf pm_surface(vec2 uv, float dist, float px) {
	PmSurf s;
	s.albedo = v_paint;
	s.rough = 0.7;
	s.metal = 0.0;
	s.emit = vec3(0.0);
	s.through = 0.0;
	s.cut = false;
	float k = v_kind;
	// How much fine pattern survives at this range (a pixel's worth of metres).
	float fine = 1.0 - smoothstep(detail_fade * 0.5, detail_fade, dist);
	float wet = clamp(road_wetness, 0.0, 1.0);
	if (k < 0.5) {
		// Painted timber: brush marks along the board, worn paint at the edges by noise.
		float g = pm_noise(vec2(uv.x * 3.0, uv.y * 40.0));
		s.albedo *= mix(1.0, 0.86 + 0.2 * g, fine * pm_keep(40.0, px));
		s.rough = 0.62;
	} else if (k < 1.5) {
		// Natural timber: grain along v, knots.
		float g = pm_noise(vec2(uv.x * 18.0, uv.y * 1.2)) * 0.6 + pm_noise(vec2(uv.x * 60.0, uv.y * 3.0)) * 0.4;
		s.albedo *= mix(1.0, 0.72 + 0.45 * g, fine * pm_keep(60.0, px));
		s.rough = 0.78;
	} else if (k < 2.5) {
		// Awning canvas: wide stripes across u, the second colour cream; fading toward the top.
		float st = step(0.5, fract(uv.x / 0.42));
		vec3 cream = cs_srgb_to_linear(vec3(0.94, 0.9, 0.8));
		s.albedo = mix(v_paint, cream, st);
		float weave = pm_noise(uv * vec2(140.0, 140.0));
		s.albedo *= mix(1.0, 0.9 + 0.15 * weave, fine * pm_keep(140.0, px));
		s.rough = 0.85;
		s.through = 0.35;
	} else if (k < 3.5) {
		// A sarape: bands across v in vivid dyes, pinstripes between them, a weave texture, a
		// fringe at the ends (u wraps the cloth's width, v its length).
		float band = floor(uv.y / 0.09);
		float h = pm_hash(vec2(band, v_seed * 97.0));
		vec3 c = cs_srgb_to_linear(pm_dye(floor(h * 10.0 + v_seed * 13.0)));
		float sub = fract(uv.y / 0.09);
		if (sub < 0.12 || sub > 0.88) {
			c = mix(c, cs_srgb_to_linear(pm_dye(mod(band + 8.0 + floor(v_seed * 3.0), 10.0))), pm_keep(1.0 / 0.011, px));
		}
		// Wide grounds every few bands (the dark or natural field of a real sarape).
		if (pm_hash(vec2(floor(uv.y / 0.36), v_seed * 31.0)) < 0.35) {
			c = mix(c, v_paint, 0.75);
		}
		float weave = step(0.5, fract(uv.x * 160.0)) * 0.5 + step(0.5, fract(uv.y * 160.0)) * 0.5;
		s.albedo = c * mix(1.0, 0.85 + 0.2 * weave, fine * pm_keep(160.0, px));
		s.rough = 0.92;
		s.through = 0.2;
	} else if (k < 4.5) {
		// Glazed pottery: the ground colour, painted bands and dots, glossy.
		float band = fract(uv.y * 5.0 + v_seed);
		vec3 c2 = cs_srgb_to_linear(pm_dye(floor(v_seed * 10.0) + 3.0));
		float ring = step(0.42, band) * step(band, 0.58);
		float dots = step(length(fract(vec2(uv.x * 9.0, uv.y * 5.0)) - 0.5), 0.18) * step(0.6, band) * step(band, 0.9);
		s.albedo = mix(v_paint, c2, max(ring, dots * 0.9) * fine * pm_keep(9.0, px));
		s.rough = 0.16;
	} else if (k < 5.5) {
		// Terracotta: fired clay, mottled.
		s.albedo *= 0.85 + 0.25 * pm_noise(uv * 12.0);
		s.rough = 0.88;
	} else if (k < 6.5) {
		// Papel picado: tissue cut out by pattern; light through it.
		s.cut = pm_picado_cut(uv, v_seed);
		s.rough = 0.8;
		s.through = 0.8;
	} else if (k < 7.5) {
		// A bulb: glows after dark, a little by day.
		float on = mix(bulb_day, bulb_night, lamp_factor);
		s.emit = v_paint * on;
		s.albedo = v_paint * 0.6;
		s.rough = 0.2;
	} else if (k < 8.5) {
		// Painted wrought iron.
		s.rough = 0.45;
		s.metal = 0.5;
	} else if (k < 9.5) {
		// Woven straw: a diagonal plait.
		float w = step(0.5, fract((uv.x + uv.y) * 22.0)) * 0.5 + step(0.5, fract((uv.x - uv.y) * 22.0)) * 0.5;
		s.albedo *= mix(1.0, 0.78 + 0.3 * w, fine * pm_keep(44.0, px));
		s.rough = 0.85;
	} else if (k < 10.5) {
		// Leather: tooled, a little sheen.
		float n = pm_noise(uv * 30.0);
		s.albedo *= 0.8 + 0.35 * n;
		s.rough = 0.5;
	} else if (k < 11.5) {
		// White cotton with embroidered bands of flowers near the hem and the yoke (v metres up).
		float hem = smoothstep(0.0, 0.02, uv.y) * (1.0 - smoothstep(0.18, 0.2, uv.y));
		float yoke = smoothstep(0.78, 0.8, uv.y) * (1.0 - smoothstep(0.95, 0.97, uv.y));
		vec2 q = fract(vec2(uv.x * 9.0, uv.y * 9.0)) - 0.5;
		float flower = step(length(q), 0.33);
		float pick = pm_hash(floor(vec2(uv.x * 9.0, uv.y * 9.0)) + v_seed * 17.0);
		vec3 thread = cs_srgb_to_linear(pm_dye(floor(pick * 8.0)));
		s.albedo = mix(v_paint, mix(v_paint * 0.8 + thread * 0.2, thread, flower * pm_keep(18.0, px)), max(hem, yoke) * fine);
		s.rough = 0.9;
		s.through = 0.15;
	} else if (k < 12.5) {
		// Candy, toys, glossy plastic.
		s.rough = 0.25;
	} else if (k < 13.5) {
		// A pinata's crepe fringes: ruffled bands, each its own colour.
		float band = floor(uv.y / 0.07);
		vec3 c = cs_srgb_to_linear(pm_dye(floor(pm_hash(vec2(band, v_seed * 53.0)) * 10.0)));
		float ruff = pm_noise(vec2(uv.x * 45.0, uv.y * 8.0));
		s.albedo = mix(v_paint, c, 0.85) * mix(0.93, 0.75 + 0.35 * ruff, pm_keep(45.0, px));
		s.rough = 0.9;
		s.through = 0.3;
	} else if (k < 14.5) {
		// A lantern's or sign's glass: warm glow after dark.
		s.emit = v_paint * mix(0.08, lantern_night, lamp_factor);
		s.rough = 0.3;
	} else {
		// Silver.
		s.albedo = cs_srgb_to_linear(vec3(0.82, 0.82, 0.84));
		s.rough = 0.22;
		s.metal = 1.0;
	}
	// The street gets wet; so does anything near the ground in the rain.
	s.rough = mix(s.rough, s.rough * 0.55, wet * step(v_world.y, 0.4));
	return s;
}
