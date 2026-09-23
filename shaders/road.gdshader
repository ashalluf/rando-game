shader_type spatial;

// Worn asphalt. The road fills the bottom third of nearly every screenshot, and a single tiled
// texture reads as a flat grey plane however good the lighting is. This layers the things that
// actually make tarmac look used, all generated from world position so they tile seamlessly
// across chunks and never repeat visibly:
//   - slow mottling, so the surface is never one tone
//   - resurfacing patches on a jittered grid, each a slightly different colour and smoothness,
//     with a darker seam around the edge
//   - cracks, as thin dark ridges from folded noise
//   - oil and tyre staining in sparse blotches
// Wetness comes from the `road_wetness` global that Weather drives: wet tarmac is darker and
// much smoother, which is what makes rain read.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.72, 0.72, 0.74);
// Metres per texture tile.
uniform float tex_scale = 8.0;
uniform float seed = 0.0;
// Size of a resurfacing patch (metres) and how much of the road is patched.
uniform float patch_size = 7.0;
uniform float patch_amount = 0.30;
uniform float crack_amount = 0.5;
uniform float stain_amount = 0.32;
uniform float normal_depth = 0.75;
// Spacing of expansion joints in metres (0 = none). Pavements are poured in slabs; the grid of
// joints between them is the single most recognisable thing about a concrete sidewalk.
uniform float joint_spacing = 0.0;
uniform float joint_depth = 0.26;

global uniform float road_wetness;
// 0 turns off the second texture fetch that breaks up the tiling. Quality clears it on the web
// and at the low levels, where roads fill the screen and every fetch counts.
global uniform float ground_detail;

varying vec3 world_pos;
varying vec2 plan_pos;
varying vec2 slab_uv;

#include "res://shaders/street_glow.gdshaderinc"
// Which way this road's lamps run (CityChunk._road_look): 0 no glow, 1 along Z, 2 along X. Seen
// from past `street_glow_near` metres the road wears the same lamp glow the far chunks do
// (far_ground.gdshader); closer in, the real lamps and their light pools take over.
uniform int lamp_axis = 0;
uniform float street_glow_near = 90.0;
uniform float street_glow_far = 200.0;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


vec2 hash22(vec2 p) {
	return vec2(hash12(p), hash12(p + 71.3));
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// City ground is laid out in plan coordinates in its chunk, so object space does not move
	// when the origin is re-centred (only the lamp pattern reads it).
	plan_pos = VERTEX.xz;
	slab_uv = UV;
}


void fragment() {
	vec2 w = world_pos.xz;
	vec2 uv = w / tex_scale;
	vec3 base = texture(albedo_tex, uv).rgb * tint;
	float rough = texture(rough_tex, uv).r;

	// Kill the visible repeat. Across a plaza or a long pavement the eye picks the tile grid
	// out immediately, and no amount of wear on top hides it. Sample the same texture a second
	// time, rotated and at a different scale, and cross-fade between the two on slow noise:
	// one extra fetch, and the grid stops existing.
	if (ground_detail > 0.5) {
		vec2 uv2 = (mat2(vec2(0.80, -0.60), vec2(0.60, 0.80)) * w) / (tex_scale * 1.37) + vec2(13.7, 4.1);
		float variant = smoothstep(0.34, 0.66, fbm(w * 0.019 + 91.0 + seed));
		base = mix(base, texture(albedo_tex, uv2).rgb * tint, variant);
	}

	// Slow mottling: patches of the road that have aged differently.
	float mottle = fbm(w * 0.045 + seed);
	base *= 0.82 + 0.36 * mottle;

	// Resurfacing patches on a jittered grid. Each patch has its own tone and smoothness, and a
	// darker seam where the new asphalt meets the old.
	vec2 cell = floor(w / patch_size);
	vec2 jitter = (hash22(cell + seed) - 0.5) * 0.55;
	vec2 local = fract(w / patch_size) - 0.5 - jitter;
	float patch_roll = hash12(cell * 1.7 + seed);
	if (patch_roll < patch_amount) {
		float half_w = 0.30 + 0.16 * hash12(cell + 5.1);
		float half_h = 0.30 + 0.16 * hash12(cell + 9.7);
		float inside = step(abs(local.x), half_w) * step(abs(local.y), half_h);
		float edge = max(abs(local.x) / half_w, abs(local.y) / half_h);
		float seam = inside * smoothstep(0.78, 1.0, edge);
		float shade = 0.84 + 0.26 * hash12(cell + 13.3);
		base = mix(base, base * shade, inside * 0.5);
		base *= 1.0 - 0.28 * seam;
		rough = mix(rough, rough * (0.7 + 0.5 * hash12(cell + 3.3)), inside);
	}

	// Cracks: fold the noise so it ridges, then keep only the sharpest lines. The frequency is
	// what decides whether this reads as a crack or as a dried-mud pattern: at 0.75 the lines
	// wandered over several metres and were a hand's width across.
	float ridge = 1.0 - abs(fbm(w * 1.7 + 17.0 + seed) * 2.0 - 1.0);
	float crack = smoothstep(0.955, 0.999, ridge) * crack_amount;
	base *= 1.0 - 0.34 * crack;
	rough = mix(rough, 1.0, crack * 0.6);

	// Oil and rubber: sparse dark blotches, smoother than the surrounding tarmac. Same trap as
	// the cracks - at a low frequency these became metres-long tendrils crawling down the
	// carriageway, which is the first thing the eye picks out as wrong.
	float stain = smoothstep(0.82, 0.98, fbm(w * 1.15 + 41.0 + seed)) * stain_amount;
	base *= 1.0 - 0.15 * stain;
	rough = mix(rough, 0.45, stain * 0.5);

	// Expansion joints, with each slab cast at a slightly different shade.
	if (joint_spacing > 0.01) {
		vec2 slab = w / joint_spacing;
		vec2 edge = abs(fract(slab) - 0.5);
		// edge is 0 at a slab's centre and 0.5 at its joint, so this has to RISE toward 0.5.
		// It used to be smoothstep(0.5, 0.5 - 0.025, ...) - edge0 above edge1, a decreasing
		// ramp - which made `line` 1 over about 95 % of every slab and 0 on the joint. Every
		// pavement, plaza, car park and port yard in the city was therefore multiplied by
		// 1 - joint_depth across its whole face and wore a BRIGHT grid where the joints should
		// be, which is most of why the ground read as a dark sheet from the air.
		float line = smoothstep(0.5 - 0.025, 0.5, max(edge.x, edge.y));
		base *= mix(1.0, 1.0 - joint_depth, line);
		rough = mix(rough, 1.0, line * 0.5);
		base *= 0.965 + 0.07 * hash12(floor(slab) + seed);
	}

	// Wet tarmac goes darker and far glossier, and water stands in the low spots. The puddles
	// are what make a rainy street at night read: mirror-flat, they hold the lit windows and
	// the lamps, where evenly glossy tarmac only ever gives a smeared sheen. They spread as the
	// street soaks, and pavements, which drain, get fewer.
	float wet = clamp(road_wetness, 0.0, 1.0);
	float puddle = 0.0;
	if (wet > 0.01) {
		float pn = fbm(w * 0.075 + 57.0 + seed) + 0.25 * value_noise(w * 0.9 + 3.0);
		float cover = mix(0.80, 0.52, wet) + (joint_spacing > 0.01 ? 0.08 : 0.0);
		puddle = smoothstep(cover, cover + 0.05, pn) * wet;
	}
	base *= mix(1.0, 0.62, wet);
	base *= 1.0 - 0.35 * puddle;

	ALBEDO = base;
	// 0.07, not 0.18: at 0.18 the screen-space reflections blur into a warm smear, and a soaked
	// street at night is nearly a mirror - the lit windows and tail lights standing in it are
	// the whole look.
	ROUGHNESS = clamp(mix(mix(rough, 0.07, wet), 0.02, puddle), 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.85, wet);
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - 0.6 * wet) * (1.0 - puddle);
	if (lamp_axis > 0 && lamp_factor > 0.001) {
		float far = smoothstep(street_glow_near, street_glow_far, length(VERTEX));
		if (far > 0.0) {
			EMISSION = street_glow(plan_pos, slab_uv, lamp_axis) * street_glow_level() * far;
		}
	}
}
