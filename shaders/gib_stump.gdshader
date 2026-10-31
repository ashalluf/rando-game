shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// A torn stump (BloodGore.stump_mesh(), blood-gore-2): the tissue's colour in the vertex colour
// (sRGB, raw on both renderers: decoded here), its kind in COLOR.a - 0 muscle, 0.33 fat, 0.66 bone,
// 1 the lip of torn skin and cloth. Muscle is drawn in fibre bundles (a stretched noise across the
// cut), fat in lobules, bone porous; all of it wet except the cloth, so it catches the light.

#include "res://shaders/color_space.gdshaderinc"

float sh(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float sn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(sh(i), sh(i + vec2(1.0, 0.0)), f.x), mix(sh(i + vec2(0.0, 1.0)), sh(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 c = cs_srgb_to_linear(COLOR.rgb);
	float kind = COLOR.a;
	float muscle = 1.0 - smoothstep(0.1, 0.25, kind);
	float fat = smoothstep(0.2, 0.3, kind) * (1.0 - smoothstep(0.45, 0.55, kind));
	float bone = smoothstep(0.55, 0.62, kind) * (1.0 - smoothstep(0.85, 0.95, kind));
	float lip = smoothstep(0.85, 0.95, kind);
	// Fibre bundles: long along one way across the cut, short across it.
	float fib = sn(vec2(UV.x * 1.5, UV.y * 9.0)) * 0.6 + sn(vec2(UV.x * 4.0, UV.y * 30.0)) * 0.4;
	float lob = sn(UV * 6.0) * 0.6 + sn(UV * 15.0) * 0.4;
	float por = sn(UV * 24.0);
	float tone = 1.0 + muscle * (fib - 0.5) * 0.7 + fat * (lob - 0.5) * 0.5 + bone * (por - 0.5) * 0.25 + lip * (lob - 0.5) * 0.3;
	ALBEDO = cs_out(c * tone);
	// Wet tissue: muscle and fat glisten, the bone's end less, the cloth lip not at all.
	ROUGHNESS = muscle * mix(0.2, 0.38, fib) + fat * 0.2 + bone * 0.45 + lip * 0.75;
	SPECULAR = mix(0.5, 0.35, lip);
	// A little light through the flesh, none through bone.
	BACKLIGHT = cs_out(vec3(0.35, 0.02, 0.015) * (muscle + fat) * 0.6);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	BACKLIGHT *= 0.4;
#endif
}
