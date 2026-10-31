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
// The face's regions (hero-face-2, hero_x_skin_region.png): R pore size, G redness under the
// skin, B cartilage that passes light (ears, nose wings).
uniform sampler2D region_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
// 0 is the old skin (HERO_FACE_2=0): the region map, the pore cavities and the breakup unused.
uniform float face2 = 1.0;
// Pore depth where the region map says big pores, against where it says none.
uniform float pore_region_gain = 1.6;
// Specular occlusion inside the pores (the detail's B: 0 the bottom of a pore).
uniform float pore_cavity = 0.55;
// A second, coarser read of the pores that breaks the roughness up at a few millimetres.
uniform float rough_breakup = 0.12;
// Transmittance on Forward+: deep red, thin and only where the cartilage map says so, so a
// backlit ear reads as blood behind skin rather than an orange lamp.
uniform vec3 transmit_deep : source_color = vec3(0.62, 0.16, 0.10);
uniform float transmit_gain2 = 0.06;
// What is left of BACKLIGHT on Forward+ under face2.
uniform float backlight_fwd = 0.05;
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
// HeroLook sets 0.3 on the Compatibility renderer, where BACKLIGHT is a glow, not scattering.
uniform float backlight_gain = 1.0;
// Wet: a film of water on the skin - glossier, a touch darker.
// Rain (HeroLook.setup_wet): the wet world's water (wet_surface.gdshaderinc, the same numbers as
// the street, the crowd's clothes and the hero's velour and hair), or wet_hold (>= 0) for stills;
// wet_gain 0 is the A/B (HERO_CLOSEUP=0).
uniform float wet_gain = 0.0;
uniform float wet_hold = -1.0;
// hero-closeup-2 (HERO_CLOSEUP_2=0 sets 0: the skin as hero-face-2 left it).
//  - the lips: the region map's lip patch (redness G with no pores R) recoloured from the atlas'
//    pale lavender to a dusky rose, the pale halo along their outline taken back toward it,
//    moist but not mirror-glossy, the vertical furrows of real lips in the normal
//  - the oily T-zone broken up by the pores, so it glints in points rather than reflecting the
//    sky as one pale sheet down the nose (the waxy look)
uniform float closeup2 = 1.0;
uniform vec3 lip_color : source_color = vec3(0.64, 0.36, 0.34);
uniform float lip_recolor = 0.7;
uniform float lip_roughness = 0.42;
uniform float lip_furrows = 0.35;
// The lowest roughness the oily patches may reach, and how much of it the pores break up.
uniform float oil_floor = 0.32;
uniform float oil_breakup = 0.7;
// Forward+ only: the screen-space scattering blurred the pores away (a smooth wax forehead at
// half a metre); a little less of it, and deeper pores there.
uniform float forward_sss = 0.72;
uniform float forward_pores = 1.3;
// The hands (their atlas islands, the bottom row left of the mouth's: UV.y > 0.8, UV.x < 0.75 -
// the feet beside them are inside the shoes): deeper crosshatch and creases, drier and less
// glossy, so a hand on the gun at arm's length is skin and not rubber.
uniform float hand_detail = 1.7;
uniform float hand_roughness = 0.12;
#include "res://shaders/wet_surface.gdshaderinc"

void fragment() {
	float wet = (wet_hold >= 0.0 ? wet_hold : (ws_on() ? ws_wet(0.5) : 0.0)) * wet_gain;
	vec4 m = texture(mask_tex, UV);
	vec4 d = texture(detail_tex, UV * detail_scale);
	vec3 rg = mix(vec3(1.0, 0.0, 0.0), texture(region_tex, UV).rgb, face2);
	vec3 alb = texture(albedo_tex, UV).rgb * albedo_tint.rgb;
	float hand = closeup2 * step(0.8, UV.y) * step(UV.x, 0.75);
	float hairs = clamp(d.a * m.r * stubble_amount, 0.0, 1.0);
	// pores: how deep depends on where on the face (the nose and cheeks most, lips none)
	float pw = mix(1.0, mix(0.25, pore_region_gain, rg.r), face2);
	float cav = mix(1.0, d.b, face2 * pore_cavity * rg.r);
	alb *= mix(1.0, 0.94 + 0.06 * cav, face2);
	// The lips (hero-closeup-2): G redness with no pores R is only the lips on the region map.
	float lip = closeup2 * smoothstep(0.18, 0.34, rg.g) * (1.0 - smoothstep(0.06, 0.2, rg.r));
	if (lip > 0.0) {
		float lum = dot(alb, vec3(0.3, 0.55, 0.15));
		float tl = dot(lip_color, vec3(0.3, 0.55, 0.15));
		// keep the atlas' shading (the mouth's line, the fullness of the lower lip) as a ratio,
		// but no brighter than the lip colour itself: the pale halo round the outline goes
		vec3 rose = lip_color * clamp(lum / tl, 0.45, 1.05);
		alb = mix(alb, rose, lip * lip_recolor);
	}
	ALBEDO = mix(alb, stubble_color, hairs * 0.9) * (1.0 - 0.12 * wet);
	// a second read of the detail, turned and at another scale: its cavity breaks the
	// roughness up into the oily and dry patches skin has at a few millimetres
	float br = texture(detail_tex, mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * UV * detail_scale * 0.37).b;
	float rough = texture(rough_tex, UV).g * roughness_scale + face2 * rough_breakup * (0.5 - br);
	// The oil sits on the ridges between pores, not in them: break the shine up with the
	// detail's cavity, and never let it go below oil_floor (a sheet of 0.15 mirrored the sky).
	float oil = m.a * closeup2;
	float ridge = smoothstep(0.35, 0.85, d.b);
	rough = mix(rough, max(rough, oil_floor + (1.0 - ridge) * 0.25 * oil_breakup), oil);
	// The lips: moist, a little rougher where the furrows run.
	rough = mix(rough, lip_roughness + 0.12 * (0.5 - br), lip);
	rough += hand * hand_roughness * (0.6 + 0.8 * (1.0 - d.b));
	ROUGHNESS = clamp(mix(mix(rough, 0.72, hairs), 0.12 + 0.3 * abs(d.r * 2.0 - 1.0), wet * 0.85), 0.04, 1.0);
	float oil_spec = oil_specular * m.a * mix(1.0, mix(0.35, 1.25, ridge), oil_breakup * closeup2);
	SPECULAR = clamp((specular_level * mix(1.0, m.b, cavity_strength) + oil_spec) * cav * mix(1.0, 0.55, lip) + 0.2 * wet, 0.0, 1.0);
	// Base wrinkles plus the tiling pores, blended by adding slopes (whiteout). The base map is
	// imported as a two-channel normal map, so its z is rebuilt here.
	vec2 nb = texture(normal_tex, UV).rg * 2.0 - 1.0;
	float fwd = (CURRENT_RENDERER == RENDERER_COMPATIBILITY) ? 0.0 : closeup2;
	vec2 nd = (d.rg * 2.0 - 1.0) * detail_strength * pw * mix(1.0, forward_pores, fwd) * mix(1.0, hand_detail, hand);
	vec2 nxy = nb + nd * (1.0 - hairs * 0.5);
	// The lips' vertical furrows. The head's atlas island is turned a quarter: the mouth's
	// line runs along v there, so the furrows across it run along u and vary with v. Faded
	// out once a furrow is under a couple of pixels (fwidth outside any branch).
	float fv = UV.y * 2600.0 + sin(UV.x * 900.0) * 1.7;
	float fpx = clamp(1.6 - fwidth(fv) * 1.2, 0.0, 1.0);
	if (lip > 0.0) {
		float f = sin(fv) * 0.6 + sin(fv * 2.31 + 1.3) * 0.4;
		nxy.y += f * lip_furrows * lip * fpx;
	}
	NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_depth;
	SSS_STRENGTH = sss_strength * mix(1.0, forward_sss, fwd) * (1.0 - 0.5 * lip);
	float thin = mix(m.g, m.g * (0.35 + 0.65 * rg.b), face2);
	SSS_TRANSMITTANCE_COLOR = vec4(mix(transmit_color, transmit_deep, face2), 1.0);
	SSS_TRANSMITTANCE_DEPTH = transmit_depth * (0.3 + thin) * mix(1.0, 0.6, face2);
	SSS_TRANSMITTANCE_BOOST = mix(transmit_boost, transmit_gain2, face2) * thin;
	// BACKLIGHT is a second, cruder transmittance: on Forward+, where the real one runs, it only
	// doubled it, and it alone lit a sunlit-from-behind ear solid orange. face2 keeps a trace of
	// it there (the Compatibility renderer, with no transmittance, keeps HeroLook's 0.3).
	float bl_keep = mix(1.0, (CURRENT_RENDERER == RENDERER_COMPATIBILITY) ? 0.6 : backlight_fwd, face2);
	BACKLIGHT = backlight_color * thin * backlight_gain * bl_keep;
}
