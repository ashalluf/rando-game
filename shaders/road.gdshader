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

global uniform float road_wetness;

varying vec3 world_pos;


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
}


void fragment() {
	vec2 w = world_pos.xz;
	vec2 uv = w / tex_scale;
	vec3 base = texture(albedo_tex, uv).rgb * tint;
	float rough = texture(rough_tex, uv).r;

	// Slow mottling: patches of the road that have aged differently.
	float mottle = fbm(w * 0.045 + seed);
	base *= 0.86 + 0.28 * mottle;

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
		float shade = 0.72 + 0.44 * hash12(cell + 13.3);
		base = mix(base, base * shade, inside * 0.85);
		base *= 1.0 - 0.45 * seam;
		rough = mix(rough, rough * (0.7 + 0.5 * hash12(cell + 3.3)), inside);
	}

	// Cracks: fold the noise so it ridges, then keep only the sharpest lines.
	float ridge = 1.0 - abs(fbm(w * 0.75 + 17.0 + seed) * 2.0 - 1.0);
	float crack = smoothstep(0.93, 0.999, ridge) * crack_amount;
	base *= 1.0 - 0.5 * crack;
	rough = mix(rough, 1.0, crack * 0.6);

	// Oil and rubber: sparse dark blotches, smoother than the surrounding tarmac.
	// Kept fine and sparse: at a low frequency this reads as wandering tendrils of damp rather
	// than spots of oil.
	float stain = smoothstep(0.74, 0.96, fbm(w * 0.38 + 41.0 + seed)) * stain_amount;
	base *= 1.0 - 0.24 * stain;
	rough = mix(rough, 0.45, stain * 0.5);

	// Wet tarmac goes darker and far glossier.
	float wet = clamp(road_wetness, 0.0, 1.0);
	base *= mix(1.0, 0.62, wet);

	ALBEDO = base;
	ROUGHNESS = clamp(mix(rough, 0.18, wet), 0.05, 1.0);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.85, wet);
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - 0.6 * wet);
}
