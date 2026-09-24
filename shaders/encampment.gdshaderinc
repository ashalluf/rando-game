// The encampment kit (tools/encampment_kit.py -> assets/models/encampment_kit.glb, placed by
// scripts/world/encampment.gd, materials from PropFactory.camp_material()). Shared by
// encampment.gdshader (solid pieces) and encampment_2side.gdshader (fabric, tarp, cardboard).
//
// Things that have lived outdoors for months: tents and tarps sun-bleached to a chalky version of
// the colour they were sold in, grime creeping up from the pavement, water stains and dark patches
// where the ground wicks into cloth and cardboard.
//
// * Colour: the texture is DETAIL only - its luminance divided by its own mean - and the tint is
//   the colour, so one fabric scan serves every tent in the city. `tint_source` 0 takes the
//   MultiMesh instance colour (each tent, tarp, bag and bike its own), 1 `base_tint`.
//   `tint_mul` darkens a panel of the same colour (a tent's zipped door).
// * INSTANCE_CUSTOM.r is how sun-bleached this one is (0 new, 1 chalky), .g a per-item seed that
//   moves the stains so no two tents wear the same ones.
// * UV is metres (the kit's rule), tiled by `tile_m`; UV2.x is the baked occlusion (0 open).
// * Colour space: Forward+ decodes `source_color` uniforms and textures but NOT a MultiMesh
//   instance colour, Compatibility decodes nothing - `color_space_probe` tells them apart, the
//   same trick shaders/facade_kit.gdshaderinc uses.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_textures = true;
uniform float tile_m = 0.6;
// Mean luminance of the albedo map: linear (what Forward+ samples) and raw sRGB (Compatibility).
uniform float tex_mean_linear = 0.25;
uniform float tex_mean_srgb = 0.5;
// How much of the texture's own variation shows through the tint (0 flat, 1 all of it).
uniform float detail = 0.8;
uniform int tint_source = 0;
uniform vec3 base_tint : source_color = vec3(0.5);
uniform float tint_mul = 1.0;
uniform float roughness = 0.8;
uniform float rough_detail = 0.3;
uniform float metallic = 0.0;
uniform float normal_strength = 0.8;
uniform float ao_strength = 0.9;
// Dirt: how dark the ground grime gets, and how high up it creeps (metres above the piece's base).
uniform float grime = 0.45;
uniform float grime_height = 0.35;
// Blotchy stains over the whole piece (water marks, spills), 0 none.
uniform float stains = 0.3;
// How far a fully bleached instance moves toward a pale, greyed version of its colour.
uniform float bleach = 0.55;
uniform vec3 color_space_probe : source_color = vec3(0.5, 0.5, 0.5);

varying vec3 v_tint;
varying vec3 v_local;
varying vec3 v_world_normal;
varying float v_bleach;
varying float v_seed;

vec3 camp_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float camp_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float camp_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(camp_hash(i), camp_hash(i + vec2(1.0, 0.0)), f.x),
		mix(camp_hash(i + vec2(0.0, 1.0)), camp_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 tint = COLOR.rgb;
	if (color_space_probe.r < 0.35) {
		tint = camp_to_linear(tint);
	}
	if (tint_source == 1) {
		tint = base_tint;
	}
	v_tint = tint * tint_mul;
	v_local = VERTEX;
	v_bleach = INSTANCE_CUSTOM.r;
	v_seed = INSTANCE_CUSTOM.g * 97.0;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Instances may be scaled a little; keep the texture in metres through that.
	UV *= vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
}

void fragment() {
	vec2 uv = UV / tile_m;
	vec3 tint = v_tint;
	// Sun bleaching: toward a lighter, greyer version of the same colour.
	float grey = dot(tint, vec3(0.299, 0.587, 0.114));
	vec3 bleached = mix(vec3(grey), tint, 0.45) * 1.35 + 0.03;
	tint = mix(tint, bleached, clamp(v_bleach * bleach, 0.0, 1.0));
	vec3 albedo = tint;
	float rough = roughness;
	if (use_textures) {
		vec3 tex = texture(albedo_tex, uv).rgb;
		float mean = color_space_probe.r < 0.35 ? tex_mean_linear : tex_mean_srgb;
		float lum = dot(tex, vec3(0.299, 0.587, 0.114)) / max(mean, 0.02);
		albedo *= mix(1.0, lum, detail);
		rough += (texture(rough_tex, uv).r - 0.5) * rough_detail;
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	// Grime from the pavement up, ragged at its top edge; heavier on what faces sideways (the walls
	// of a tent take the splash, its roof the dust).
	float n1 = camp_noise(v_local.xz * 3.1 + vec2(v_seed, v_seed * 0.7));
	float n2 = camp_noise(v_local.xy * 5.3 + vec2(v_local.z * 2.0, v_seed));
	float edge = grime_height * (0.6 + 0.8 * n1);
	float low = 1.0 - smoothstep(0.0, edge, v_local.y);
	float g = grime * low * (0.55 + 0.45 * n2);
	// Stains: a few big soft blotches with darker rims, the way a water mark dries.
	float s = camp_noise(v_local.xz * 1.3 + v_local.y * 0.8 + vec2(v_seed * 1.3, 0.0));
	float blot = smoothstep(0.62, 0.7, s) * (0.6 + 0.4 * smoothstep(0.7, 0.66, s));
	g = max(g, blot * stains);
	vec3 dirt = vec3(0.26, 0.22, 0.17) * albedo + vec3(0.012, 0.010, 0.008);
	albedo = mix(albedo, dirt, clamp(g, 0.0, 0.9));
	float occ = clamp(UV2.x, 0.0, 1.0) * ao_strength;
	ALBEDO = clamp(albedo * (1.0 - occ * 0.6), vec3(0.0), vec3(1.0));
	AO = 1.0 - occ;
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = clamp(rough + g * 0.15, 0.04, 1.0);
	METALLIC = metallic;
	SPECULAR = 0.5;
}
