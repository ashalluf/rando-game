shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, sss_mode_skin;

// The hero's skin (hero.glb, material hero_skin; HeroLook puts it on). Built by tools/hero/.
//
// Three scales of detail, because a 2K map across a whole body gives the face under half a
// millimetre a texel and skin's texture lives below that:
//  - the body map (albedo, wrinkle normal, roughness) - complexion zones, wrinkles, T-zone
//  - the mask (R stubble, G thinness, B cavity, A oil) - where each effect applies
//  - a tiling micro-detail, repeated about every 3 cm: pores and the crosshatch of the skin's
//    relief in RGB (a normal), stubble hairs in alpha, so a close-up still has grain
// Subsurface scattering is Forward+ only (sss_mode_skin, SSS_STRENGTH, transmittance through the
// ears and nose); the Compatibility renderer ignores those and keeps BACKLIGHT, a cheap red
// glow where the mask says the skin is thin, so the web build is not waxy either.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
// How many micro-detail tiles fit across one UV unit (46 = a tile every ~3 cm on the face).
uniform float detail_scale = 46.0;
// Pore and crosshatch depth.
uniform float detail_strength = 0.6;
uniform float normal_depth = 1.0;
// Stubble hairs over the beard mask: their colour and how dense they grow.
uniform vec3 stubble_color : source_color = vec3(0.045, 0.038, 0.034);
uniform float stubble_amount = 0.9;
uniform float roughness_scale = 1.0;
uniform float specular_level = 0.5;
// Oily T-zone: extra specular where the mask's alpha says so.
uniform float oil_specular = 0.25;
// Specular occlusion in creases (the mask's cavity channel).
uniform float cavity_strength = 0.6;
uniform float sss_strength = 0.4;
uniform vec3 transmit_color : source_color = vec3(0.95, 0.32, 0.2);
uniform float transmit_depth = 0.25;
uniform float transmit_boost = 0.35;
uniform vec3 backlight_color : source_color = vec3(0.32, 0.08, 0.045);

void fragment() {
	vec4 m = texture(mask_tex, UV);
	vec4 d = texture(detail_tex, UV * detail_scale);
	vec3 alb = texture(albedo_tex, UV).rgb * albedo_tint.rgb;
	float hairs = clamp(d.a * m.r * stubble_amount, 0.0, 1.0);
	ALBEDO = mix(alb, stubble_color, hairs * 0.9);
	float rough = texture(rough_tex, UV).g * roughness_scale;
	ROUGHNESS = clamp(mix(rough, 0.72, hairs), 0.04, 1.0);
	SPECULAR = clamp(specular_level * mix(1.0, m.b, cavity_strength) + oil_specular * m.a, 0.0, 1.0);
	// Base wrinkles plus the tiling pores, blended by adding slopes (whiteout). The base map is
	// imported as a two-channel normal map, so its z is rebuilt here.
	vec2 nb = texture(normal_tex, UV).rg * 2.0 - 1.0;
	vec2 nd = (d.rg * 2.0 - 1.0) * detail_strength;
	vec2 nxy = nb + nd * (1.0 - hairs * 0.5);
	NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_depth;
	SSS_STRENGTH = sss_strength;
	SSS_TRANSMITTANCE_COLOR = vec4(transmit_color, 1.0);
	SSS_TRANSMITTANCE_DEPTH = transmit_depth * (0.3 + m.g);
	SSS_TRANSMITTANCE_BOOST = transmit_boost * m.g;
	BACKLIGHT = backlight_color * m.g;
}
