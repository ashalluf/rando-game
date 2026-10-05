shader_type spatial;
render_mode cull_back;

// The ground of the city's service alleys (Alleys): ONE mesh a chunk, no shadow. Each piece says
// what it is in COLOR.r (Alleys.G_*, in 16ths), a variant in COLOR.g and in COLOR.b whether its
// alley runs along z; on the alley, its aprons and its bumps UV is (metres along the alley,
// metres across from its centre line) and UV2 (the half width, a per-run seed); elsewhere UV is
// world metres.
//   0 the alley: poured concrete slabs either side of a V-gutter ribbon, sawn joints, cracks,
//     asphalt patches where it was dug up, oil under where trucks stand, tyre polish, a cast-iron
//     drain in the gutter now and then, grit and leaves along the walls, a damp line down the V
//   1 the driveway apron across the pavement and its wedge in the gutter
//   2 the old concrete at the alley's sides
//   3 a speed bump: asphalt with worn yellow chevrons
//   4 stencil paint (COLOR.g 0 white, 1 yellow)
// Tuned in display numbers (disp() / to_lit(), as the industrial ground does).

uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cracked_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float road_wetness;

varying float kind;
varying float variant;
varying vec3 world_p;

#include "res://shaders/color_space.gdshaderinc"

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

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.3) * 0.2;
}

// Distance to the nearest edge of a jittered Voronoi tessellation `scale` m across.
float crack_dist(vec2 p, float scale) {
	vec2 q = p / scale;
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 best = vec2(8.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + hash22(i + o) * 0.85 - f;
			float d = dot(r, r);
			if (d < best.x) {
				best.y = best.x;
				best.x = d;
			} else if (d < best.y) {
				best.y = d;
			}
		}
	}
	return (sqrt(best.y) - sqrt(best.x)) * scale * 0.5;
}

// 1 on a line every `spacing` m, `w` wide, faded to its average once under a few pixels.
float lines(float v, float spacing, float w) {
	float g = abs(fract(v / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(v), 0.0005);
	float fade = 1.0 - smoothstep(0.03, 0.12, fw / spacing * 4.0);
	return (1.0 - smoothstep(w * 0.5, w * 0.5 + fw, g)) * fade;
}

float band(float v, float c, float w) {
	float fw = max(fwidth(v), 0.0005);
	return 1.0 - smoothstep(w, w + fw, abs(v - c));
}

void vertex() {
	kind = floor(COLOR.r * 16.0);
	variant = COLOR.g;
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = UV;
	vec2 w = world_p.xz;
	float hw = max(UV2.x, 0.5);
	float seed = UV2.y;
	float foot = length(vec2(length(dFdx(p)), length(dFdy(p))));
	float fade = 1.0 - smoothstep(0.006, 0.03, foot);
	vec3 albedo;
	float rough = 0.88;
	float wet_k = 1.0;
	float damp = 0.0;
	if (kind < 0.5) {
		float s = p.x;
		float o = p.y;
		float ao = abs(o);
		vec3 c = disp(texture(concrete_tex, vec2(s, o) / 3.4).rgb);
		vec3 cr = disp(texture(cracked_tex, vec2(s, o) / 6.0 + seed * 9.0).rgb);
		float tone = dot(mix(c, cr, 0.45), vec3(0.333));
		// Slab by slab: joints across every 3-4.5 m (the run's own pitch), and along the ribbon.
		float pitch = 3.0 + 1.5 * seed;
		float slab = floor(s / pitch);
		float side = o < 0.0 ? 0.0 : 1.0;
		float stone = 0.9 + 0.14 * hash12(vec2(slab, side + seed * 13.0));
		vec3 base = vec3(0.45, 0.44, 0.415) * (0.62 + 0.55 * tone) * stone;
		// Decades of grime: broad dark weathering, darker toward the walls and down the middle
		// where the trucks run, lighter in the scuffed wheel paths.
		float weather = fbm(vec2(s, o) * 0.11 + seed * 3.0);
		base *= mix(0.72, 1.02, weather);
		float ribbon = 1.0 - smoothstep(0.43, 0.47, ao);
		// The ribbon is a smoother, darker pour, stained by what runs down it.
		vec3 rib = vec3(0.33, 0.32, 0.30) * (0.75 + 0.4 * tone);
		// Half the alleys are asphalt either side of the concrete ribbon: old, grey, oxidised in
		// broad patches, alligator-cracked where it has failed.
		if (seed < 0.5) {
			vec3 a = disp(texture(asphalt_tex, vec2(s, o) / 3.6).rgb);
			float age = fbm(vec2(s, o) * 0.07 + 3.0 + seed * 9.0);
			base = a * mix(0.6, 0.82, age) * vec3(1.0, 0.99, 0.97);
			float failed = smoothstep(0.5, 0.68, fbm(vec2(s, o) * 0.09 + 11.0 + seed * 5.0));
			float acd = crack_dist(vec2(s, o) + vec2(vnoise(vec2(s, o) * 0.8), vnoise(vec2(s, o) * 0.8 + 3.0)) * 0.5, 0.8);
			base *= 1.0 - 0.5 * (1.0 - smoothstep(0.012, 0.012 + foot, acd)) * fade * failed;
			// The ribbon's own concrete reads lighter against it.
			rib = vec3(0.47, 0.46, 0.43) * (0.7 + 0.45 * tone);
		}
		albedo = mix(base, rib, ribbon);
		float concrete = seed < 0.5 ? ribbon : 1.0;
		float joint = max(lines(s, pitch, 0.012) * concrete, band(ao, 0.45, 0.008));
		albedo *= 1.0 - 0.38 * joint;
		// The damp line down the V, with a scum of algae and silt either side of it.
		float trickle = (1.0 - smoothstep(0.03, 0.16, ao + 0.05 * (vnoise(vec2(s * 0.7, 3.0)) - 0.5))) * (0.55 + 0.45 * vnoise(vec2(s * 0.25, 1.0) + seed * 5.0));
		vec3 silt = vec3(0.32, 0.31, 0.24);
		albedo = mix(albedo, silt * (0.7 + 0.4 * vnoise(vec2(s * 3.0, o * 9.0))), trickle * 0.6);
		damp = max(damp, trickle * 0.7);
		// Cracks: a network on old slabs, and long ones across.
		float old = smoothstep(0.6, 0.85, hash12(vec2(slab * 1.7, side + 4.0 + seed * 3.0)));
		float cd = crack_dist(vec2(s, o) + vec2(vnoise(vec2(s, o) * 0.9), vnoise(vec2(s, o) * 0.9 + 4.0)) * 0.4, 1.1);
		float crack = (1.0 - smoothstep(0.004, 0.004 + foot * 0.7, cd)) * fade * old * concrete;
		float cd2 = crack_dist(vec2(s * 0.3, o * 1.4) + seed * 7.0, 2.2);
		crack = max(crack, (1.0 - smoothstep(0.004, 0.004 + foot * 0.7, cd2)) * fade * 0.5 * step(0.55, vnoise(vec2(s * 0.2, o) + 7.0)));
		albedo *= 1.0 - 0.38 * crack;
		albedo *= 1.0 - 0.05 * old * (1.0 - fade);
		// Asphalt patches where the alley was dug up for a pipe: across it, and in lumps.
		float trench = step(0.78, hash12(vec2(floor(s / 11.0), seed * 31.0)));
		float tc = (floor(s / 11.0) + 0.3 + 0.4 * hash12(vec2(floor(s / 11.0), 5.0 + seed))) * 11.0;
		float in_trench = trench * (1.0 - smoothstep(0.55, 0.62, abs(s - tc) + 0.06 * vnoise(vec2(o * 3.0, s))));
		float lump = smoothstep(0.69, 0.71, fbm(vec2(s, o) * 0.28 + seed * 17.0));
		float patch_ = max(in_trench, lump);
		vec3 asph = disp(texture(asphalt_tex, vec2(s, o) / 3.0).rgb);
		vec3 a_col = asph * mix(0.48, 0.66, fbm(vec2(s, o) * 0.6 + 2.0)) * vec3(1.0, 0.99, 0.97);
		albedo = mix(albedo, a_col, patch_);
		// The patch's edge sealant: a dark tar line round it.
		float seal = max(band(abs(s - tc) + 0.06 * vnoise(vec2(o * 3.0, s)), 0.585, 0.035) * trench,
			band(fbm(vec2(s, o) * 0.28 + seed * 17.0), 0.70, 0.004));
		albedo *= 1.0 - 0.55 * seal * fade;
		// Tyre polish either side of the ribbon, oil where the trucks stand.
		float track = (1.0 - smoothstep(0.18, 0.4, abs(ao - 0.95))) * (0.6 + 0.4 * vnoise(vec2(s * 0.2, side)));
		albedo *= 1.0 - 0.14 * track;
		// Oil: drips where trucks stand (in the wheel paths, stretched along the alley), soaked in
		// and soft-edged, a ring where an old stain spread.
		float drip = vnoise(vec2(s * 0.55, o * 1.9) + seed * 23.0 + 11.0) * 0.7 + vnoise(vec2(s, o) * 3.1 + 2.0) * 0.3;
		float oil = smoothstep(0.6, 0.86, drip) * (1.0 - smoothstep(0.35, 0.9, abs(ao - 0.85))) ;
		oil += smoothstep(0.7, 0.92, vnoise(vec2(s, o) * 0.9 + 40.0)) * 0.35;
		oil = clamp(oil, 0.0, 1.0);
		albedo = mix(albedo, albedo * vec3(0.45, 0.44, 0.43), oil * 0.6);
		rough = mix(0.86, 0.6, oil);
		// Grit, dead leaves and litter blown against the walls.
		float edge = smoothstep(hw - 0.9, hw, ao);
		float grit = edge * smoothstep(0.35, 0.75, fbm(vec2(s, o) * 2.3 + 5.0));
		vec3 leaf = mix(vec3(0.36, 0.27, 0.15), vec3(0.47, 0.40, 0.24), vnoise(vec2(s, o) * 31.0));
		albedo = mix(albedo, mix(vec3(0.33, 0.30, 0.26), leaf, step(0.62, vnoise(vec2(s, o) * 13.0))), grit * 0.7);
		albedo *= 1.0 - 0.22 * edge;
		// A cast-iron grate in the V every so often (a hash of the 24 m stretch).
		float cell = floor(s / 24.0);
		float gs = (cell + 0.25 + 0.5 * hash12(vec2(cell, seed * 41.0))) * 24.0;
		vec2 gq = vec2(s - gs, o);
		if (hash12(vec2(cell, seed * 7.0 + 2.0)) < 0.7 && abs(gq.x) < 0.48 && abs(gq.y) < 0.33) {
			float frame = step(0.42, abs(gq.x)) + step(0.27, abs(gq.y));
			// Bars across the gutter every 9 cm, box-filtered to their average once a bar is under
			// a few pixels (at a grazing angle they shimmered into a moire).
			float sfw = max(fwidth(gq.x) / 0.09, 0.0005);
			float bar = 1.0 - smoothstep(0.32 - sfw, 0.32 + sfw, abs(fract(gq.x / 0.09) - 0.5) * 2.0);
			bar = mix(bar, 0.32, smoothstep(0.15, 0.45, sfw));
			float slot = (1.0 - bar) * step(abs(gq.y), 0.25);
			vec3 iron = vec3(0.13, 0.12, 0.11) * (0.8 + 0.4 * vnoise(gq * 30.0));
			albedo = mix(iron * mix(1.0, 0.18, slot), vec3(0.2, 0.18, 0.16), clamp(frame, 0.0, 1.0));
			rough = 0.75;
		} else {
			// A rust bloom on the concrete round it.
			float rust = (1.0 - smoothstep(0.48, 0.9, length(max(abs(gq) - vec2(0.48, 0.33), 0.0)))) * step(hash12(vec2(cell, seed * 7.0 + 2.0)), 0.7);
			albedo = mix(albedo, vec3(0.36, 0.24, 0.15), rust * 0.35 * vnoise(gq * 6.0));
		}
	} else if (kind < 1.5) {
		// The apron: brushed concrete, scored into squares, stained where tyres turn in.
		vec3 c = disp(texture(concrete_tex, w / 2.6).rgb);
		albedo = vec3(0.74, 0.73, 0.70) * (0.7 + 0.45 * dot(c, vec3(0.333)));
		float brush = 0.96 + 0.06 * vnoise(vec2(p.x * 40.0, p.y * 1.5));
		albedo *= brush;
		float score = max(lines(p.x, 1.5, 0.01), lines(p.y + 0.0, 1.5, 0.01));
		albedo *= 1.0 - 0.35 * score;
		float tyre = smoothstep(0.55, 0.85, fbm(w * 0.6 + 3.0));
		albedo *= 1.0 - 0.22 * tyre;
		rough = 0.82;
	} else if (kind < 2.5) {
		// The old concrete beside the alley and behind the buildings: weathered, cracked, weeds at
		// the joints; or (COLOR.g 1) a service yard's old asphalt.
		vec3 cr = disp(texture(cracked_tex, w / 5.0).rgb);
		vec3 c = disp(texture(concrete_tex, w / 3.0).rgb);
		albedo = vec3(0.44, 0.43, 0.41) * (0.62 + 0.5 * dot(mix(c, cr, 0.6), vec3(0.333)));
		albedo *= mix(0.74, 1.02, fbm(w * 0.12 + 5.0));
		if (variant > 0.5) {
			vec3 a = disp(texture(asphalt_tex, w / 3.5).rgb);
			albedo = a * mix(0.55, 0.75, fbm(w * 0.06 + 3.0));
			float cd = crack_dist(w + vec2(vnoise(w * 0.8), vnoise(w * 0.8 + 3.0)) * 0.5, 1.2);
			albedo *= 1.0 - 0.45 * (1.0 - smoothstep(0.008, 0.008 + foot, cd)) * fade * smoothstep(0.45, 0.7, fbm(w * 0.07 + 1.0));
		}
		float joint = max(lines(w.x, 3.0, 0.012), lines(w.y, 3.0, 0.012)) * step(variant, 0.5);
		albedo *= 1.0 - 0.4 * joint;
		float weeds = joint * smoothstep(0.55, 0.8, vnoise(w * 2.0)) * fade;
		albedo = mix(albedo, vec3(0.30, 0.34, 0.16) * (0.7 + 0.5 * vnoise(w * 19.0)), weeds * 0.8);
		albedo *= 1.0 - 0.22 * smoothstep(0.5, 0.8, fbm(w * 0.3 + 9.0));
		rough = 0.9;
	} else if (kind < 3.5) {
		// A speed bump: dark asphalt, worn yellow chevrons across it.
		vec3 a = disp(texture(asphalt_tex, p / 2.0).rgb);
		albedo = a * 0.55;
		float chev = step(0.5, fract((abs(p.y) * 0.9 + p.x * 1.6) / 0.9));
		float worn = smoothstep(0.35, 0.75, fbm(p * 3.0 + 5.0));
		albedo = mix(albedo, vec3(0.86, 0.68, 0.14), chev * (1.0 - worn * 0.75));
		rough = 0.8;
	} else {
		// Stencil paint, overspray at the edges, worn through by tyres.
		vec2 q = vec2(p.x, p.y);
		vec3 a = vec3(0.6, 0.59, 0.56);
		vec3 paint = variant > 0.5 ? vec3(0.88, 0.70, 0.16) : vec3(0.88, 0.88, 0.84);
		float wear = smoothstep(0.4, 0.8, fbm(q * 3.5 + 7.0));
		albedo = mix(paint, a, wear * 0.75);
		rough = 0.75;
	}
	float wet = clamp(road_wetness, 0.0, 1.0) * wet_k;
	wet = max(wet, damp * 0.5);
	albedo *= 1.0 - 0.32 * wet;
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	ROUGHNESS = mix(rough, 0.12, wet * 0.8);
	SPECULAR = 0.5;
}
