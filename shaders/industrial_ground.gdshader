shader_type spatial;
render_mode cull_back;

// The industrial district's yards (Industrial.commit()): ONE mesh a chunk, no shadow. Each piece
// says what it is in COLOR.r (Industrial.G_*, in 16ths) and carries a variant in COLOR.g; UV is
// world metres (x, z), so nothing tiles to the piece.
//   0 truck-court and yard asphalt: cracked into slabs, weeds in the cracks, patches, oil and
//     tyre marks       1 concrete dock apron: 4.5 m slabs, saw joints, drips and rust stains
//   2 gravel           3 dirt with weeds      4 rail ballast with ties (COLOR.g 0 runs along x,
//     1 along z)       5 paint (stall stripes; worn)     6 dry weeds and grass

uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float road_wetness;

varying float kind;
varying float variant;
varying float centre_mod;

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

// Distance to the nearest edge of a jittered Voronoi tessellation (cells `scale` m across): the
// crack network of old asphalt.
float crack_dist(vec2 p, float scale) {
	vec2 q = p / scale;
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 best = vec2(8.0);
	vec2 bo = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + hash22(i + o) * 0.85 - f;
			float d = dot(r, r);
			if (d < best.x) {
				best.y = best.x;
				best.x = d;
				bo = r;
			} else if (d < best.y) {
				best.y = d;
			}
		}
	}
	// The second-minus-first distance approximates the edge distance well enough for cracks.
	return (sqrt(best.y) - sqrt(best.x)) * scale * 0.5;
}

float lines(float v, float spacing, float w) {
	float g = abs(fract(v / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(v), 0.0005);
	float fade = 1.0 - smoothstep(0.03, 0.12, fw / spacing * 4.0);
	return (1.0 - smoothstep(w * 0.5, w * 0.5 + fw, g)) * fade;
}

void vertex() {
	kind = floor(COLOR.r * 16.0);
	variant = COLOR.g;
	centre_mod = COLOR.b * 4.2;
}

void fragment() {
	vec2 p = UV;
	float px = max(fwidth(p.x), fwidth(p.y));
	vec3 albedo;
	float rough = 0.9;
	float wet_k = 1.0;
	vec3 weed = vec3(0.30, 0.34, 0.16);
	if (kind < 0.5) {
		// Asphalt: old and grey, oxidised paler in broad patches, alligator-cracked where it has
		// failed (weeds in the wider cracks), patched with newer darker asphalt, stained with oil.
		vec3 a = disp(texture(asphalt_tex, p / 4.0).rgb);
		float age = fbm(p * 0.05 + 3.0);
		albedo = a * mix(0.68, 0.86, age) * vec3(1.0, 0.995, 0.98);
		float patch_n = fbm(floor(p / 0.5) * 0.5 * 0.09 + variant * 17.0);
		float patch_ = smoothstep(0.66, 0.67, patch_n);
		float failed = smoothstep(0.52, 0.66, fbm(p * 0.06 + 11.0 + variant * 5.0)) * (1.0 - patch_);
		float cd = crack_dist(p + vec2(vnoise(p * 0.8), vnoise(p * 0.8 + 3.0)) * 0.5, 0.9);
		float crack_w = mix(0.006, 0.022, smoothstep(0.5, 0.9, vnoise(p * 0.3 + 9.0)));
		float fade = 1.0 - smoothstep(0.015, 0.06, px);
		float crack = (1.0 - smoothstep(crack_w, crack_w + px, cd)) * fade * failed;
		// A few long cracks across the rest: a coarse network, hairline.
		float cd2 = crack_dist(p * vec2(1.0, 0.35), 7.0);
		crack = max(crack, (1.0 - smoothstep(0.008, 0.008 + px, cd2)) * fade * 0.7 * (1.0 - patch_));
		albedo *= 1.0 - 0.55 * crack;
		float tuft = smoothstep(0.45, 0.8, vnoise(p * 4.0)) * (1.0 - smoothstep(crack_w + 0.03, crack_w + 0.12, cd)) * failed;
		albedo = mix(albedo, weed * (0.6 + 0.7 * vnoise(p * 17.0)), tuft * 0.75);
		albedo = mix(albedo, a * 0.55, patch_ * 0.85);
		float oil = smoothstep(0.64, 0.8, fbm(p * 0.3 + 21.0));
		albedo *= 1.0 - 0.3 * oil;
		rough = mix(0.9, 0.6, oil);
	} else if (kind < 1.5) {
		// Concrete apron: 4.5 m slabs with saw joints, darker drips under the trailers' doors,
		// rust rings from the landing gear, cracks across a few slabs.
		vec3 c = disp(texture(concrete_tex, p / 3.0).rgb);
		vec2 slab = floor(p / 4.5);
		float st = 0.92 + 0.12 * hash12(slab);
		albedo = c * 1.05 * st * vec3(1.0, 0.99, 0.96);
		float joint = max(lines(p.x, 4.5, 0.012), lines(p.y, 4.5, 0.012));
		albedo *= 1.0 - 0.45 * joint;
		float stain = smoothstep(0.55, 0.85, fbm(p * 0.3 + 7.0));
		albedo *= 1.0 - 0.3 * stain;
		float cd = crack_dist(p, 3.0);
		float crack = (1.0 - smoothstep(0.008, 0.008 + px, cd)) * step(0.7, hash12(slab + 3.1)) * (1.0 - smoothstep(0.02, 0.08, px));
		albedo *= 1.0 - 0.4 * crack;
		rough = 0.85;
	} else if (kind < 2.5) {
		// Gravel: crushed stone over the base, a grey-brown with pebbles picked out.
		vec3 g = disp(texture(gravel_tex, p / 2.0).rgb);
		vec3 d = disp(texture(dirt_tex, p / 3.0).rgb);
		float peb = vnoise(p * 9.0) * 0.6 + vnoise(p * 23.0) * 0.4;
		albedo = mix(g, d, 0.4) * vec3(0.92, 0.9, 0.86) * (0.8 + 0.35 * peb);
		float ruts = smoothstep(0.6, 0.9, vnoise(vec2(p.x * 0.4, p.y * 0.05) + variant * 9.0));
		albedo *= 1.0 - 0.18 * ruts;
		albedo = mix(albedo, weed * 0.9, smoothstep(0.72, 0.85, fbm(p * 0.6 + 5.0)) * 0.5);
		rough = 0.95;
		wet_k = 0.6;
	} else if (kind < 3.5) {
		// Dirt with weeds in clumps and dry grass along the edges of the clumps.
		vec3 d = disp(texture(dirt_tex, p / 3.0).rgb);
		float clump = smoothstep(0.45, 0.7, fbm(p * 0.45 + variant * 13.0));
		vec3 dry = vec3(0.5, 0.47, 0.36) * (0.75 + 0.5 * vnoise(p * 11.0));
		d = mix(d, vec3(dot(d, vec3(0.333))), 0.55) * 0.92;
		albedo = mix(d, mix(dry, weed, smoothstep(0.6, 0.9, vnoise(p * 2.0))), clump);
		rough = 0.96;
		wet_k = 0.6;
	} else if (kind < 4.5) {
		// Ballast and ties: crushed stone, rust-brown along the rails, creosoted ties every 0.6 m
		// across the track.
		float along = variant > 0.5 ? p.y : p.x;
		float across = variant > 0.5 ? p.x : p.y;
		vec3 g = disp(texture(gravel_tex, p / 1.6).rgb);
		float peb = vnoise(p * 14.0) * 0.6 + vnoise(p * 31.0) * 0.4;
		albedo = g * vec3(0.78, 0.74, 0.7) * (0.75 + 0.4 * peb);
		// Metres off the track's centre line (COLOR.b is the line's position mod 4.2 m, in 4.2ths).
		float off = abs(fract((across - centre_mod) / 4.2 + 0.5) - 0.5) * 4.2;
		float rails = smoothstep(1.0, 0.6, abs(off - 0.75));
		albedo = mix(albedo, vec3(0.34, 0.24, 0.17), rails * 0.35);
		float tie = step(fract(along / 0.6), 0.38) * step(off, 1.3);
		vec3 wood = vec3(0.24, 0.19, 0.15) * (0.75 + 0.4 * vnoise(vec2(along * 2.0, across * 9.0)));
		float tfade = 1.0 - smoothstep(0.05, 0.15, px);
		albedo = mix(albedo, wood, tie * tfade + (1.0 - tfade) * 0.38 * step(off, 1.3));
		albedo = mix(albedo, weed, smoothstep(0.72, 0.88, fbm(p * 0.8 + 2.0)) * step(1.6, off) * 0.6);
		rough = 0.95;
		wet_k = 0.5;
	} else if (kind < 5.5) {
		// Paint: worn white (or yellow), the asphalt showing through.
		vec3 a = disp(texture(asphalt_tex, p / 4.0).rgb);
		float wear = smoothstep(0.35, 0.75, fbm(p * 2.5 + 3.0));
		vec3 pcol = variant > 0.97 ? vec3(0.9, 0.72, 0.18) : vec3(0.86, 0.86, 0.82);
		albedo = mix(pcol, a, wear * 0.7);
		rough = 0.75;
	} else {
		// Dry weeds and grass strip.
		vec3 d = disp(texture(dirt_tex, p / 3.0).rgb);
		float g = vnoise(p * 6.0) * 0.5 + vnoise(p * 19.0) * 0.5;
		vec3 dry = mix(vec3(0.5, 0.47, 0.34), vec3(0.38, 0.4, 0.22), smoothstep(0.4, 0.7, vnoise(p * 0.7)));
		d = mix(d, vec3(dot(d, vec3(0.333))), 0.55) * 0.9;
		albedo = mix(d, dry * (0.7 + 0.6 * g), smoothstep(0.25, 0.55, fbm(p * 0.5 + variant * 7.0)));
		rough = 0.97;
		wet_k = 0.5;
	}
	float wet = clamp(road_wetness, 0.0, 1.0) * wet_k;
	albedo *= 1.0 - 0.32 * wet;
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	ROUGHNESS = mix(rough, 0.12, wet * 0.8);
	SPECULAR = 0.5;
}
