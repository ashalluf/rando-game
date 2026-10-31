shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The hero's velour tracksuit and its rib bands (hero.glb, materials hero_tracksuit and
// hero_tracksuit_rib; HeroLook puts it on). Built by tools/hero/.
//  - folds that follow the pose: normal_tex holds the folds of a straight arm and leg, bent_tex
//    the same cloth with the elbows and knees closed (deep rings in the crook, bags over the
//    knee). wrinkle_mask says which joint each texel belongs to (R left elbow, G right elbow,
//    B left knee, A right knee) and HeroLook.update() sets wrinkle_weights from the skeleton
//    every frame, so the folds deepen as a joint closes - the standard wrinkle-map trick.
//  - velour: a tiling pile (pile_tex: a fibre normal, and crushed-pile patches in alpha) and a
//    sheen. Velour is brighter edge-on than face-on, because the standing fibres catch light
//    sideways; that lift goes into the albedo (so it works in ambient light too) as well as
//    Godot's rim lobe for the sun.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bent_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wrinkle_mask : hint_default_black, filter_linear;
uniform vec4 wrinkle_weights = vec4(0.0);
uniform bool use_wrinkles = true;
uniform sampler2D pile_tex : filter_linear_mipmap_anisotropic, repeat_enable;
// Pile tiles per UV unit, and how rough the pile's own normal is.
uniform float pile_scale = 140.0;
uniform float pile_strength = 0.3;
uniform float normal_depth = 1.0;
uniform float roughness = 0.8;
uniform float specular = 0.25;
uniform vec3 sheen_color : source_color = vec3(0.30, 0.30, 0.33);
uniform float sheen = 0.55;
// Higher keeps the sheen to the very edges.
uniform float sheen_power = 3.0;
uniform float rim = 0.45;
uniform float rim_tint = 0.6;
// How much the crushed-pile patches change the sheen.
uniform float crush = 0.3;

// hero-closeup-2 (HERO_CLOSEUP_2=0 sets 0: the renderer's own lobes, as before):
//  - the velour's sheen for the sun as a proper cloth lobe (Charlie distribution, Neubelt
//    visibility) in light(): bright where the light grazes the pile, the side toward the sun
//    and the edges, dark face-on - velour, not matte black plastic
//  - the folds read: the curvature of the fold normals (their divergence in UV, two more taps of
//    each map) darkens the valleys and lifts the ridges, so the elbow's rings and the knee's
//    bags show at the street distance and not only in a grazing light
uniform float closeup2 = 0.0;
uniform float sheen_roughness = 0.42;
// The cloth lobe's strength: on Compatibility, and on Forward+ (see forward_sheen).
uniform float sheen_gain = 1.0;
uniform float sheen_gain_forward = 2.9;
// Forward+ decodes sheen_color (0.30 -> 0.07 linear) and lights in linear: the same sheen was a
// quarter as strong there as on Compatibility, and the velour read as matte black on the Mac.
uniform float forward_sheen = 1.8;
uniform float crease_ao = 0.55;
uniform float crease_lift = 0.12;
// The fold maps' texel, for the curvature taps.
uniform float fold_texel = 0.0012;

#include "res://shaders/wet_surface.gdshaderinc"

varying float pile_crush;
varying float crease;
varying float sheen_scale;

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	vec2 nr = texture(normal_tex, UV).rg * 2.0 - 1.0;
	float w = 0.0;
	if (use_wrinkles) {
		w = clamp(dot(texture(wrinkle_mask, UV), wrinkle_weights), 0.0, 1.0);
		nr = mix(nr, texture(bent_tex, UV).rg * 2.0 - 1.0, w);
	}
	crease = 0.0;
	if (closeup2 > 0.5) {
		// The divergence of the fold normals: negative in a valley, positive on a ridge.
		vec2 nu = texture(normal_tex, UV + vec2(fold_texel, 0.0)).rg * 2.0 - 1.0;
		vec2 nw = texture(normal_tex, UV + vec2(0.0, fold_texel)).rg * 2.0 - 1.0;
		vec2 n0 = texture(normal_tex, UV).rg * 2.0 - 1.0;
		if (w > 0.001) {
			vec2 bu = texture(bent_tex, UV + vec2(fold_texel, 0.0)).rg * 2.0 - 1.0;
			vec2 bv = texture(bent_tex, UV + vec2(0.0, fold_texel)).rg * 2.0 - 1.0;
			vec2 b0 = texture(bent_tex, UV).rg * 2.0 - 1.0;
			nu = mix(nu, bu, w);
			nw = mix(nw, bv, w);
			n0 = mix(n0, b0, w);
		}
		// v runs down the texture while the map's green runs up: the second term is negated.
		crease = clamp(((nu.x - n0.x) - (nw.y - n0.y)) * 2.2, -1.0, 1.0);
	}
	vec4 p = texture(pile_tex, UV * pile_scale);
	vec2 nxy = nr + (p.rg * 2.0 - 1.0) * pile_strength;
	NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_depth;
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float cr = mix(1.0 - crush, 1.0 + crush, p.a);
	float fsh = (CURRENT_RENDERER == RENDERER_COMPATIBILITY) ? 1.0 : mix(1.0, forward_sheen, closeup2);
	sheen_scale = (CURRENT_RENDERER == RENDERER_COMPATIBILITY) ? sheen_gain : sheen_gain_forward;
	ALBEDO = base + sheen_color * sheen * pow(1.0 - nv, sheen_power) * cr * mix(1.0, 0.7, closeup2) * fsh;
	pile_crush = cr;
	if (closeup2 > 0.5) {
		float valley = max(-crease, 0.0);
		float ridge = max(crease, 0.0);
		ALBEDO *= 1.0 - crease_ao * valley;
		ALBEDO += sheen_color * crease_lift * fsh * ridge * (1.0 - nv * 0.5);
		AO = 1.0 - crease_ao * 0.8 * valley;
	}
	ROUGHNESS = roughness;
	SPECULAR = specular;
	RIM = rim * cr;
	RIM_TINT = rim_tint;
	if (ws_on()) {
		// Rain (wet_surface.gdshaderinc): the velour soaks dark where it faces the sky, its pile
		// flattened (less sheen), a wet shine on top.
		float face_up = smoothstep(-0.15, 0.75, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
		float wet = ws_wet(0.55) * mix(0.35, 1.0, face_up);
		ALBEDO = mix(ALBEDO, base * 0.6, wet);
		ROUGHNESS = mix(ROUGHNESS, 0.45, wet);
		RIM *= 1.0 - 0.6 * wet;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float nl = clamp(ndl, 0.0, 1.0);
	float nv = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
	vec3 h = normalize(LIGHT + VIEW);
	float nh = clamp(dot(NORMAL, h), 0.0, 1.0);
	if (closeup2 > 0.5) {
		// Lambert, a touch wrapped: the pile scatters light round onto the shadow side.
		DIFFUSE_LIGHT += clamp((ndl + 0.15) / 1.15, 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
		// Charlie sheen (Estevez & Kulla) with Neubelt's visibility.
		float inv = 1.0 / max(sheen_roughness, 0.05);
		float d = (2.0 + inv) * pow(max(1.0 - nh * nh, 1e-4), inv * 0.5) / (2.0 * PI);
		float vis = 1.0 / (4.0 * (nl + nv - nl * nv) + 1e-3);
		SPECULAR_LIGHT += sheen_color * sheen_scale * d * vis * nl * pile_crush * (1.0 - 0.6 * max(-crease, 0.0)) * ATTENUATION * LIGHT_COLOR;
	} else {
		// The renderer's own lobes, near enough: Burley diffuse, a GGX of the material's
		// roughness, Godot's rim.
		float lh = clamp(dot(LIGHT, h), 0.0, 1.0);
		float fd90 = 0.5 + 2.0 * lh * lh * ROUGHNESS;
		float fl = 1.0 + (fd90 - 1.0) * pow(1.0 - nl, 5.0);
		float fv = 1.0 + (fd90 - 1.0) * pow(1.0 - nv, 5.0);
		DIFFUSE_LIGHT += nl * fl * fv * ATTENUATION * LIGHT_COLOR / PI;
		float a2 = ROUGHNESS * ROUGHNESS * ROUGHNESS * ROUGHNESS;
		float dd = a2 / (PI * pow(nh * nh * (a2 - 1.0) + 1.0, 2.0));
		float f0 = 0.16 * specular * specular;
		float f = f0 + (1.0 - f0) * pow(1.0 - lh, 5.0);
		float k = ROUGHNESS * 0.5;
		float g = 0.25 / ((nl * (1.0 - k) + k) * (nv * (1.0 - k) + k));
		SPECULAR_LIGHT += dd * f * g * nl * ATTENUATION * LIGHT_COLOR;
		float rm = rim * pile_crush;
		float rim_light = pow(max(1e-4, 1.0 - nv), max(0.0, (1.0 - rm) * 16.0));
		DIFFUSE_LIGHT += rim_light * rm * mix(vec3(1.0), ALBEDO, rim_tint) * nl * ATTENUATION * LIGHT_COLOR / PI;
	}
}
