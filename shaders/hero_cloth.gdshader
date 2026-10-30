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
// Wet: soaked velour goes darker, its pile lies flat (less sheen) and it shines.
// Rain on the hero (HeroLook.setup_wet): Weather's street wetness (soaks in the rain, dries over
// minutes) and the rain itself, or wet_hold (>= 0) for stills; wet_gain 0 is the A/B.
global uniform float road_wetness;
global uniform float rain_intensity;
uniform float wet_gain = 0.0;
uniform float wet_hold = -1.0;
float hero_wet() {
	float w = wet_hold >= 0.0 ? wet_hold : max(road_wetness, rain_intensity);
	return clamp(w, 0.0, 1.0) * wet_gain;
}


void fragment() {
	float wet = hero_wet();
	vec3 base = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	vec2 nr = texture(normal_tex, UV).rg * 2.0 - 1.0;
	if (use_wrinkles) {
		float w = clamp(dot(texture(wrinkle_mask, UV), wrinkle_weights), 0.0, 1.0);
		nr = mix(nr, texture(bent_tex, UV).rg * 2.0 - 1.0, w);
	}
	vec4 p = texture(pile_tex, UV * pile_scale);
	vec2 nxy = nr + (p.rg * 2.0 - 1.0) * pile_strength;
	NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_depth;
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float cr = mix(1.0 - crush, 1.0 + crush, p.a);
	ALBEDO = base * (1.0 - 0.45 * wet) + sheen_color * sheen * (1.0 - 0.7 * wet) * pow(1.0 - nv, sheen_power) * cr;
	ROUGHNESS = mix(roughness, 0.55, wet);
	SPECULAR = mix(specular, 0.35, wet);
	RIM = rim * cr * (1.0 - 0.6 * wet);
	RIM_TINT = rim_tint;
}
