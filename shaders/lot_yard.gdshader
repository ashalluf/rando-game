shader_type spatial;

// The ground YardFill lays outside downtown and midtown - beach-town yards, the campus's walks
// and service yards, the freeway's right of way - as ONE material, so a chunk's yards are one
// mesh and one draw call (YardFill.commit()). The forecourts keep their own (lot_ground): this
// one carries the surfaces a house, a campus or Caltrans uses, and sampling both sets in one
// shader would pass the Compatibility renderer's texture units. Each vertex says what it is in
// COLOR.r (YardFill.G_*, in 16ths) and carries a 0..1 variant in COLOR.g (a lawn's thirst, the
// concrete's age, which way a deck's boards run; on the ivy, how bare the ground under the deck
// is). Mapped from the chunk-space position (true world inside a chunk, so nothing swims on an
// origin re-centre), the wet street from road_wetness like the rest of the ground.
//   0 lawn       1 concrete (broom finish, tooled joints)   2 decomposed granite
//   3 brick pavers   4 saltillo tile   5 timber deck   6 bark mulch
//   7 ivy, bare dirt under the deck (COLOR.g)   8 a swimming pool   9 gravel yard

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D planks_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 lawn_tint : source_color = vec3(0.42, 0.56, 0.27);
uniform vec3 lawn_dry : source_color = vec3(0.62, 0.60, 0.36);
uniform vec3 concrete_tint : source_color = vec3(0.86, 0.85, 0.82);
uniform vec3 dg_tint : source_color = vec3(1.08, 0.96, 0.80);
// RcSuburb: 1 the pale crushed-granite DG (display numbers, a plain uniform: raw on both
// renderers), 0 the old orange (RC2_SUBURB=0).
uniform float dg_real = 1.0;
uniform vec3 dg_color = vec3(0.64, 0.62, 0.58);
uniform vec3 brick_tint : source_color = vec3(0.92, 0.78, 0.70);
uniform vec3 tile_tint : source_color = vec3(0.70, 0.47, 0.37);
uniform vec3 deck_tint : source_color = vec3(1.25, 1.02, 0.80);
uniform vec3 mulch_tint : source_color = vec3(0.42, 0.28, 0.20);
uniform vec3 ivy_tint : source_color = vec3(0.17, 0.27, 0.11);
uniform vec3 dirt_tint : source_color = vec3(0.60, 0.57, 0.52);
uniform vec3 gravel_tint : source_color = vec3(0.78, 0.76, 0.72);
// Metres a concrete slab runs between tooled joints, and a saltillo tile's side.
uniform float joint_spacing = 1.5;
uniform float tile_size = 0.31;

global uniform float road_wetness;
global uniform float ground_detail;
// A pool's light after dark (HouseNights: its variant 0.75 on, 0.25 off, 0 the old pool).
global uniform float lamp_factor;
uniform float pool_light = 1.4;

varying vec3 local_pos;
varying vec3 local_normal;
varying float kind;
varying float variant;

#include "res://shaders/color_space.gdshaderinc"

// The arithmetic below is tuned in display (sRGB) numbers, which is what Compatibility hands a
// shader. Forward+ decodes the textures and the `source_color` tints first, so they go back to
// display numbers here (disp()) and the result goes out in the renderer's own space (to_lit()):
// both renderers draw the same albedo (CLAUDE.md, the colour-space trap).
vec3 disp(vec3 c) {
	return cs_linear_renderer() ? cs_linear_to_srgb(c) : c;
}


vec3 to_lit(vec3 c) {
	return cs_linear_renderer() ? cs_srgb_to_linear(c) : c;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A texture sampled twice, the second rotated and scaled, cross-faded on slow noise: a yard's
// worth of one 1K tile shows its grid otherwise.
vec3 tiled(sampler2D tex, vec2 p, float scale) {
	vec3 a = disp(texture(tex, p / scale).rgb);
	if (ground_detail < 0.5) {
		return a;
	}
	vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / (scale * 1.37) + vec2(0.31, 0.77);
	vec3 b = disp(texture(tex, q).rgb);
	return mix(a, b, smoothstep(0.35, 0.65, vnoise(p * 0.07)) * 0.5);
}

// A groove of `w` metres every `spacing` metres along both world axes, anti-aliased: 1 in the
// joint, 0 on the slab.
float joints(vec2 p, float spacing, float w) {
	vec2 g = abs(fract(p / spacing + 0.5) - 0.5) * spacing;
	vec2 fw = max(fwidth(p), vec2(0.0005));
	vec2 j = 1.0 - smoothstep(vec2(w * 0.5), vec2(w * 0.5) + fw, g);
	// Faded out once a joint is under a pixel: a grid of moire lines from the air.
	float fade = 1.0 - smoothstep(0.02, 0.06, max(fw.x, fw.y) / spacing * 4.0);
	return max(j.x, j.y) * fade;
}

// The same along one axis.
float joint1(float x, float spacing, float w) {
	float g = abs(fract(x / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(x), 0.0005);
	float fade = 1.0 - smoothstep(0.02, 0.06, fw / spacing * 4.0);
	return (1.0 - smoothstep(w * 0.5, w * 0.5 + fw, g)) * fade;
}

#include "res://shaders/lawn_field.gdshaderinc"
#include "res://shaders/pattern_aa.gdshaderinc"

// Bark mulch up close (lawns_closeup on): shredded chips about 3-6 cm long lying every which way,
// each its own tone of brown - fresh red-brown to weathered grey - with dark gaps and shade
// between them. Returns (tone multiplier, gap darkness, slope x, slope z); faded to its own
// average as a chip passes a pixel or two.
vec4 mulch_chips(vec2 p) {
	vec2 q = p / 0.045;
	vec2 ci = floor(q);
	float best = 10.0;
	float second = 10.0;
	vec2 best_d = vec2(0.0);
	float best_h = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = ci + vec2(float(x), float(y));
			float h = hash12(c + 13.7);
			vec2 o = vec2(hash12(c + 2.1), hash12(c + 5.3));
			vec2 d = q - (c + o);
			// A chip is an elongated cell: the distance squashed along its own direction.
			float a = h * 6.2831;
			vec2 ax = vec2(cos(a), sin(a));
			vec2 dd = vec2(dot(d, ax) * 0.45, dot(d, vec2(-ax.y, ax.x)));
			float r = length(dd);
			if (r < best) {
				second = best;
				best = r;
				best_d = dd;
				best_h = h;
			} else if (r < second) {
				second = r;
			}
		}
	}
	float gap = 1.0 - smoothstep(0.02, 0.14, second - best);
	float tone = mix(0.62, 1.32, fract(best_h * 7.13));
	vec2 slope = -normalize(best_d + 1.0e-4) * smoothstep(0.0, 0.5, best) * 0.5;
	float fade = 1.0 - smoothstep(0.004, 0.02, length(fwidth(p)));
	return vec4(mix(1.0, tone, fade), gap * fade, slope * fade);
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	kind = floor(COLOR.r * 16.0 + 0.5);
	variant = COLOR.g;
}

void fragment() {
	vec2 p = local_pos.xz;
	// The footprint in metres, in uniform control flow (pattern_aa: never inside a branch).
	vec2 fwp = fwidth(p);
	vec3 albedo = vec3(0.5);
	float rough = 0.88;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float nm_depth = 0.0;
	float wet_k = 1.0;
	vec3 pool_em = vec3(0.0);
	float mottle = 0.9 + 0.2 * vnoise(p * 0.13 + variant * 7.0) + 0.06 * (vnoise(p * 1.1) - 0.5);
	if (kind < 0.5) {
		// A lawn: watered green to summer-dry by the variant, in patches.
		vec3 g = tiled(grass_tex, p, 2.6);
		float dry = clamp(variant * 0.9 + 0.35 * (vnoise(p * 0.21 + 3.0) - 0.5), 0.0, 1.0);
		albedo = g * mix(disp(lawn_tint), disp(lawn_dry), dry) * mottle;
		if (lawn_field_on()) {
			// The lawn field's clover and brown spots (lawn_field.gdshaderinc), the seed from the
			// lawn's thirst so neighbouring yards differ.
			float ls = floor(floor(variant * 255.0 + 0.5) * 997.0 / 255.0) * 0.37;
			float d2 = clamp(dry + smoothstep(0.68, 0.86, lf_noise(p * 0.42 + ls * 2.9 + 17.0)) * 0.4, 0.0, 1.0);
			float clover = lf_clover(p, ls, d2);
			albedo = g * mix(mix(disp(lawn_tint), disp(lawn_dry), d2), disp(lawn_tint) * vec3(0.86, 0.97, 1.03), clover * 0.6) * mottle;
		}
		rough = 0.95;
		wet_k = 0.4;
	} else if (kind < 1.5) {
		// Concrete: broom-finished slabs between tooled joints, a slab or two a shade off its
		// neighbours (poured on different days), darker toward the lot's old oil and leaf stains.
		vec2 cell = floor(p / joint_spacing);
		// The variant snapped to its 8-bit vertex value first: interpolated, a constant 0.0 can
		// read -1e-7 on some pixel rows and floor() flipped every slab's shade in stripes.
		float slab = hash12(cell + floor(floor(variant * 255.0 + 0.5) * 31.0 / 255.0));
		if (paa_on()) {
			// A slab's own shade under two pixels is its mean (pattern_aa).
			slab = mix(0.5, slab, paa_keep(joint_spacing, max(fwp.x, fwp.y)));
		}
		vec3 c = tiled(concrete_tex, p, 3.2) * disp(concrete_tint) * (0.9 + 0.14 * slab);
		float stain = smoothstep(0.6, 0.85, vnoise(p * 0.45 + 11.0 + variant * 5.0));
		c *= 1.0 - 0.22 * stain - 0.18 * variant;
		float j = paa_on() ? paa_grid(p, joint_spacing, 0.012, fwp) : joints(p, joint_spacing, 0.012);
		albedo = c * (1.0 - 0.45 * j) * mottle;
		nm = texture(concrete_nrm, p / 3.2).rgb;
		nm_depth = 0.35;
		rough = 0.8;
	} else if (kind < 2.5) {
		// Decomposed granite: the tan crushed stone of a drought-tolerant yard.
		albedo = tiled(dirt_tex, p, 2.2) * disp(dg_tint) * mix(vec3(1.0), vec3(1.06, 1.0, 0.92), variant) * mottle;
		if (dg_real > 0.5) {
			// RcSuburb (rc2-suburb): the tinted dry-ground scan read as orange clay. Real DG is
			// a pale tan of crushed granite: the scan's own relief at 40 % of its colour, the tan
			// laid on, and grains of pale feldspar and dark mica under a few cm, faded to their
			// average once a grain is under a pixel.
			vec3 t = tiled(dirt_tex, p, 2.2);
			float l = dot(t, vec3(0.299, 0.587, 0.114));
			vec3 g = mix(vec3(l), t, 0.4) / 121.0 * 255.0;
			// Round stones, one a 3 cm cell at a jittered spot, 4-13 mm across; between them
			// the fines carry the scan's tone.
			vec2 gq = p * 33.0;
			vec2 gc = floor(gq);
			float gr = hash12(gc + variant * 31.0);
			vec2 go = vec2(hash12(gc + 17.3), hash12(gc + 41.9)) * 0.5 + 0.25;
			float rad = 0.12 + 0.3 * hash12(gc + 7.7);
			float gd = length(fract(gq) - go);
			float gaa = max(fwp.x, fwp.y) * 33.0;
			float stone = 1.0 - smoothstep(rad - gaa, rad + gaa, gd);
			float grain = stone * (gr > 0.62 ? 0.22 : (gr < 0.12 ? -0.3 : (gr - 0.4) * 0.25));
			// A rim of shade on the stone's lower side (the sun is overhead most of the day).
			grain -= 0.1 * stone * smoothstep(rad * 0.4, rad, gd);
			grain *= 1.0 - smoothstep(0.012, 0.045, max(fwp.x, fwp.y));
			albedo = g * dg_color * mix(vec3(1.0), vec3(1.03, 1.0, 0.95), variant) * mottle * (1.0 + grain);
			// The edges of a bed scuffed into the soil, the middle raked lighter.
			albedo *= 0.94 + 0.08 * vnoise(p * 0.7 + 3.0);
		}
		rough = 0.95;
		wet_k = 0.7;
	} else if (kind < 3.5) {
		// Brick pavers, laid in rows on sand.
		// (Sampled once: the rotated second sample tiled() blends in crosses a pattern like this
		// with a diagonal hatch.)
		vec2 q = variant > 0.5 ? p.yx : p;
		vec3 laid = texture(brick_tex, q / 1.6).rgb;
		nm = texture(brick_nrm, q / 1.6).rgb;
		nm_depth = 0.6;
		if (paa_on()) {
			// The courses under two pixels are their average, not moire (PavingAA.MODULE).
			float keep = paa_keep(1.6 / 15.0, max(fwp.x, fwp.y));
			laid = mix(paa_tex_mean(brick_tex), laid, keep);
			nm_depth *= mix(0.3, 1.0, keep);
		}
		albedo = disp(laid) * disp(brick_tint) * mottle;
		if (variant > 0.5) {
			nm.xy = nm.yx;
		}
		rough = 0.82;
	} else if (kind < 4.5) {
		// Saltillo tile: square terracotta pavers, every one fired a little differently, in pale
		// grout - the courtyard of a Spanish revival apartment.
		vec2 t = floor(p / tile_size);
		float h = hash12(t + 17.0);
		if (paa_on()) {
			h = mix(0.5, h, paa_keep(tile_size, max(fwp.x, fwp.y)));
		}
		vec3 base = tiled(concrete_tex, p, 2.0);
		vec3 clay = disp(tile_tint) * mix(vec3(0.82, 0.86, 0.9), vec3(1.15, 1.06, 0.96), h) * (0.75 + 0.5 * dot(base, vec3(0.33)));
		float g = paa_on() ? paa_grid(p, tile_size, 0.014, fwp) : joints(p, tile_size, 0.014);
		albedo = mix(clay, vec3(0.62, 0.58, 0.52), g) * mottle;
		rough = mix(0.62, 0.9, g);
	} else if (kind < 5.5) {
		// A timber deck: boards along x or z by the variant, silvered toward the edges of the yard.
		vec2 q = variant > 0.5 ? p.yx : p;
		vec3 w = disp(texture(planks_tex, vec2(q.x / 2.4, q.y / 0.6)).rgb);
		float gap = joint1(q.y + 0.05, 0.14, 0.008);
		albedo = w * disp(deck_tint) * (1.0 - 0.55 * gap) * mottle;
		rough = 0.78;
	} else if (kind < 6.5) {
		// Bark mulch under the shrubs: dark chips on the dirt.
		float chips = vnoise(p * 9.0) * 0.6 + vnoise(p * 23.0) * 0.4;
		albedo = tiled(dirt_tex, p, 1.4) * disp(mulch_tint) * (0.7 + 0.6 * chips) * mottle;
		rough = 0.96;
		wet_k = 0.6;
		if (lawn_field_on()) {
			vec4 mc = mulch_chips(p);
			// Chips over the dirt: their own tone, a red-brown or grey cast per bed patch, the
			// gaps between them dark, each chip tilted (a slope for the normal below).
			vec3 cast = mix(vec3(1.08, 0.92, 0.82), vec3(0.88, 0.9, 0.92), smoothstep(0.3, 0.7, vnoise(p * 0.6 + 21.0)));
			albedo = disp(mulch_tint) * 1.55 * (0.82 + 0.3 * chips) * mc.x * cast * (1.0 - 0.72 * mc.y) * mottle;
			nm = vec3(mc.z * 0.5 + 0.5, -mc.w * 0.5 + 0.5, 1.0);
			nm_depth = 0.9;
		}
	} else if (kind < 7.5) {
		// Ivy over the freeway's slopes, dense and dark with leafy clumps; where the deck's shade
		// keeps it off (variant up to 1 right under it) the bare compacted dirt Caltrans leaves.
		vec3 g = tiled(grass_tex, p, 1.3);
		float clumps = vnoise(p * 1.7) * 0.65 + vnoise(p * 5.3) * 0.35;
		vec3 ivy = g * disp(ivy_tint) * (0.55 + 0.9 * clumps);
		vec3 dirt = tiled(dirt_tex, p, 2.4) * disp(dirt_tint) * mottle;
		float bare = smoothstep(0.25, 0.75, variant + 0.35 * (vnoise(p * 0.6 + 9.0) - 0.5));
		albedo = mix(ivy, dirt, bare);
		rough = mix(0.9, 0.97, bare);
		wet_k = mix(0.4, 0.7, bare);
	} else if (kind < 8.5) {
		// A swimming pool: pale tiles under clear water, slow caustic ripples.
		float c = vnoise(p * 1.7 + vec2(TIME * 0.3, TIME * 0.2)) * vnoise(p * 2.3 - vec2(TIME * 0.25, 0.0));
		albedo = vec3(0.14, 0.50, 0.60) * (0.9 + 0.35 * c);
		rough = 0.22;
		wet_k = 0.0;
		if (variant > 0.5) {
			// The pool light: the water lit turquoise from below, brightest round the lamp in
			// the deep end's wall, the caustics lit through it.
			float lampd = 0.5 + 0.5 * vnoise(p * 0.35 + 3.0);
			pool_em = vec3(0.06, 0.62, 0.72) * pool_light * (0.55 + 0.45 * lampd + 0.6 * c) * lamp_factor;
		}
	} else {
		// A gravel yard (a service yard, a maintenance yard under the freeway).
		float stones = vnoise(p * 14.0) * 0.5 + vnoise(p * 31.0) * 0.5;
		albedo = tiled(dirt_tex, p, 1.8) * disp(gravel_tint) * (0.8 + 0.4 * stones) * mottle;
		float oil = smoothstep(0.66, 0.85, vnoise(p * 0.3 + 4.0));
		albedo *= 1.0 - 0.35 * oil * variant;
		rough = 0.93;
	}
	float wet = clamp(road_wetness, 0.0, 1.0) * wet_k;
	albedo *= 1.0 - 0.35 * wet;
	rough = mix(rough, 0.14, wet * 0.85);
	ALBEDO = to_lit(albedo);
	EMISSION = to_lit(pool_em);
	ROUGHNESS = rough;
	// The detail normal as a slope on the ground plane (these meshes have no tangents). Tops only.
	if (local_normal.y > 0.9 && nm_depth > 0.0) {
		vec2 slope = (nm.xy * 2.0 - 1.0) * nm_depth * (1.0 - 0.6 * wet);
		vec3 n = normalize(vec3(slope.x, 1.0, -slope.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
}
