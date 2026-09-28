shader_type spatial;

// Everything LotFill lays on the ground and in its planters and pools, as ONE material, so a
// chunk's forecourts, car parks, lawns, planted tops and water are one mesh and one draw call
// (LotFill.commit()). Each vertex says what it is in COLOR.r (LotFill.KIND_*, in 16ths):
//   0-3 forecourt paving (four looks: setts, dark pavers, warm stone, pale pavers)
//   4   car-park asphalt      5 lawn      6 planted soil (ground cover)
//   7   still dark water / polished granite / glass      8 a swimming pool
// Mapped from the chunk-space position (true world inside a chunk, so nothing swims on an origin
// re-centre), with the road shader's tricks in small: a second rotated sample against the tile
// grid (ground_detail), slow mottling, and the wet street (road_wetness).

uniform sampler2D setts_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D setts_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pavers_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pavers_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Per paving look: metres a tile, and its tint (LotFill.PAVINGS).
uniform vec4 paving_scale = vec4(2.2, 1.25, 1.6, 1.8);
uniform vec3 paving_tint_0 : source_color = vec3(0.80, 0.79, 0.78);
uniform vec3 paving_tint_1 : source_color = vec3(0.66, 0.65, 0.64);
uniform vec3 paving_tint_2 : source_color = vec3(0.96, 0.87, 0.75);
uniform vec3 paving_tint_3 : source_color = vec3(0.86, 0.84, 0.80);
uniform vec3 asphalt_tint : source_color = vec3(0.60, 0.60, 0.62);
uniform float asphalt_scale = 7.0;
uniform vec3 lawn_tint : source_color = vec3(0.46, 0.62, 0.30);
uniform vec3 soil_tint : source_color = vec3(0.36, 0.46, 0.24);
uniform float grass_scale = 3.0;

global uniform float road_wetness;
global uniform float ground_detail;

varying vec3 local_pos;
varying vec3 local_normal;
varying float kind;

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

// A texture sampled twice, the second rotated and scaled, cross-faded on slow noise: the tile
// grid is the first thing the eye finds on a plaza.
vec3 tiled(sampler2D tex, vec2 p, float scale) {
	vec3 a = texture(tex, p / scale).rgb;
	if (ground_detail < 0.5) {
		return a;
	}
	vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / (scale * 1.37) + vec2(0.31, 0.77);
	vec3 b = texture(tex, q).rgb;
	return mix(a, b, smoothstep(0.35, 0.65, vnoise(p * 0.07)) * 0.5);
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	kind = floor(COLOR.r * 16.0 + 0.5);
}

void fragment() {
	vec2 p = local_pos.xz;
	vec3 albedo = vec3(0.5);
	float rough = 0.85;
	float metal = 0.0;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float nm_depth = 0.0;
	float wet_k = 1.0;
	float mottle = 0.9 + 0.2 * vnoise(p * 0.11) + 0.06 * (vnoise(p * 0.9) - 0.5);
	if (kind < 3.5) {
		int k = int(kind);
		float scale = k == 0 ? paving_scale.x : (k == 1 ? paving_scale.y : (k == 2 ? paving_scale.z : paving_scale.w));
		vec3 tint = k == 0 ? paving_tint_0 : (k == 1 ? paving_tint_1 : (k == 2 ? paving_tint_2 : paving_tint_3));
		bool setts = k == 0 || k == 2;
		albedo = (setts ? tiled(setts_tex, p, scale) : tiled(pavers_tex, p, scale)) * tint * mottle;
		nm = setts ? texture(setts_nrm, p / scale).rgb : texture(pavers_nrm, p / scale).rgb;
		nm_depth = 0.7;
		rough = 0.82;
	} else if (kind < 4.5) {
		albedo = tiled(asphalt_tex, p, asphalt_scale) * asphalt_tint * mottle;
		// Oil down the middle of each stall and tyre polish, in slow blotches.
		float oil = smoothstep(0.62, 0.8, vnoise(p * 0.35 + 17.0));
		albedo *= 1.0 - 0.3 * oil;
		nm = texture(asphalt_nrm, p / asphalt_scale).rgb;
		nm_depth = 0.6;
		rough = mix(0.9, 0.6, oil);
	} else if (kind < 6.5) {
		// Lawn and planted soil: the grass texture, mottled drier and greener in patches.
		vec3 g = tiled(grass_tex, p, grass_scale);
		float dry = smoothstep(0.45, 0.8, vnoise(p * 0.18 + 5.0));
		vec3 tint = kind < 5.5 ? lawn_tint : soil_tint;
		albedo = g * mix(tint, tint * vec3(1.25, 1.1, 0.7), dry * 0.6) * mottle;
		rough = 0.95;
		wet_k = 0.4;
	} else if (kind < 7.5) {
		albedo = vec3(0.05, 0.065, 0.07);
		rough = 0.08;
		metal = 0.15;
		wet_k = 0.0;
	} else {
		// A swimming pool: pale tiles under clear water, with slow caustic ripples.
		float c = vnoise(p * 1.7 + vec2(TIME * 0.3, TIME * 0.2)) * vnoise(p * 2.3 - vec2(TIME * 0.25, 0.0));
		albedo = vec3(0.14, 0.50, 0.60) * (0.9 + 0.35 * c);
		rough = 0.25;
		wet_k = 0.0;
	}
	// The wet street: darker and far smoother where it holds water.
	float wet = clamp(road_wetness, 0.0, 1.0) * wet_k;
	albedo *= 1.0 - 0.35 * wet;
	rough = mix(rough, 0.12, wet * 0.85);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	// The detail normal as a slope on the ground plane: these meshes have no tangents, and a
	// NORMAL_MAP without tangents does nothing. Tops only; the skirts and box sides stay flat.
	if (local_normal.y > 0.9 && nm_depth > 0.0) {
		vec2 slope = (nm.xy * 2.0 - 1.0) * nm_depth * (1.0 - 0.6 * wet);
		vec3 n = normalize(vec3(slope.x, 1.0, -slope.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
}
