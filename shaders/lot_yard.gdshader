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

varying vec3 local_pos;
varying vec3 local_normal;
varying float kind;
varying float variant;

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
	vec3 a = texture(tex, p / scale).rgb;
	if (ground_detail < 0.5) {
		return a;
	}
	vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / (scale * 1.37) + vec2(0.31, 0.77);
	vec3 b = texture(tex, q).rgb;
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

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	kind = floor(COLOR.r * 16.0 + 0.5);
	variant = COLOR.g;
}

void fragment() {
	vec2 p = local_pos.xz;
	vec3 albedo = vec3(0.5);
	float rough = 0.88;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float nm_depth = 0.0;
	float wet_k = 1.0;
	float mottle = 0.9 + 0.2 * vnoise(p * 0.13 + variant * 7.0) + 0.06 * (vnoise(p * 1.1) - 0.5);
	if (kind < 0.5) {
		// A lawn: watered green to summer-dry by the variant, in patches.
		vec3 g = tiled(grass_tex, p, 2.6);
		float dry = clamp(variant * 0.9 + 0.35 * (vnoise(p * 0.21 + 3.0) - 0.5), 0.0, 1.0);
		albedo = g * mix(lawn_tint, lawn_dry, dry) * mottle;
		rough = 0.95;
		wet_k = 0.4;
	} else if (kind < 1.5) {
		// Concrete: broom-finished slabs between tooled joints, a slab or two a shade off its
		// neighbours (poured on different days), darker toward the lot's old oil and leaf stains.
		vec2 cell = floor(p / joint_spacing);
		float slab = hash12(cell + floor(variant * 31.0));
		vec3 c = tiled(concrete_tex, p, 3.2) * concrete_tint * (0.9 + 0.14 * slab);
		float stain = smoothstep(0.6, 0.85, vnoise(p * 0.45 + 11.0 + variant * 5.0));
		c *= 1.0 - 0.22 * stain - 0.18 * variant;
		float j = joints(p, joint_spacing, 0.012);
		albedo = c * (1.0 - 0.45 * j) * mottle;
		nm = texture(concrete_nrm, p / 3.2).rgb;
		nm_depth = 0.35;
		rough = 0.8;
	} else if (kind < 2.5) {
		// Decomposed granite: the tan crushed stone of a drought-tolerant yard.
		albedo = tiled(dirt_tex, p, 2.2) * dg_tint * mix(vec3(1.0), vec3(1.06, 1.0, 0.92), variant) * mottle;
		rough = 0.95;
		wet_k = 0.7;
	} else if (kind < 3.5) {
		// Brick pavers, laid in rows on sand.
		vec2 q = variant > 0.5 ? p.yx : p;
		albedo = tiled(brick_tex, q, 1.6) * brick_tint * mottle;
		nm = texture(brick_nrm, q / 1.6).rgb;
		if (variant > 0.5) {
			nm.xy = nm.yx;
		}
		nm_depth = 0.6;
		rough = 0.82;
	} else if (kind < 4.5) {
		// Saltillo tile: square terracotta pavers, every one fired a little differently, in pale
		// grout - the courtyard of a Spanish revival apartment.
		vec2 t = floor(p / tile_size);
		float h = hash12(t + 17.0);
		vec3 base = tiled(concrete_tex, p, 2.0);
		vec3 clay = tile_tint * mix(vec3(0.82, 0.86, 0.9), vec3(1.15, 1.06, 0.96), h) * (0.75 + 0.5 * dot(base, vec3(0.33)));
		float g = joints(p, tile_size, 0.014);
		albedo = mix(clay, vec3(0.62, 0.58, 0.52), g) * mottle;
		rough = mix(0.62, 0.9, g);
	} else if (kind < 5.5) {
		// A timber deck: boards along x or z by the variant, silvered toward the edges of the yard.
		vec2 q = variant > 0.5 ? p.yx : p;
		vec3 w = texture(planks_tex, vec2(q.x / 2.4, q.y / 0.6)).rgb;
		float gap = joint1(q.y + 0.05, 0.14, 0.008);
		albedo = w * deck_tint * (1.0 - 0.55 * gap) * mottle;
		rough = 0.78;
	} else if (kind < 6.5) {
		// Bark mulch under the shrubs: dark chips on the dirt.
		float chips = vnoise(p * 9.0) * 0.6 + vnoise(p * 23.0) * 0.4;
		albedo = tiled(dirt_tex, p, 1.4) * mulch_tint * (0.7 + 0.6 * chips) * mottle;
		rough = 0.96;
		wet_k = 0.6;
	} else if (kind < 7.5) {
		// Ivy over the freeway's slopes, dense and dark with leafy clumps; where the deck's shade
		// keeps it off (variant up to 1 right under it) the bare compacted dirt Caltrans leaves.
		vec3 g = tiled(grass_tex, p, 1.3);
		float clumps = vnoise(p * 1.7) * 0.65 + vnoise(p * 5.3) * 0.35;
		vec3 ivy = g * ivy_tint * (0.55 + 0.9 * clumps);
		vec3 dirt = tiled(dirt_tex, p, 2.4) * dirt_tint * mottle;
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
	} else {
		// A gravel yard (a service yard, a maintenance yard under the freeway).
		float stones = vnoise(p * 14.0) * 0.5 + vnoise(p * 31.0) * 0.5;
		albedo = tiled(dirt_tex, p, 1.8) * gravel_tint * (0.8 + 0.4 * stones) * mottle;
		float oil = smoothstep(0.66, 0.85, vnoise(p * 0.3 + 4.0));
		albedo *= 1.0 - 0.35 * oil * variant;
		rough = 0.93;
	}
	float wet = clamp(road_wetness, 0.0, 1.0) * wet_k;
	albedo *= 1.0 - 0.35 * wet;
	rough = mix(rough, 0.14, wet * 0.85);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	// The detail normal as a slope on the ground plane (these meshes have no tangents). Tops only.
	if (local_normal.y > 0.9 && nm_depth > 0.0) {
		vec2 slope = (nm.xy * 2.0 - 1.0) * nm_depth * (1.0 - 0.6 * wet);
		vec3 n = normalize(vec3(slope.x, 1.0, -slope.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
}
