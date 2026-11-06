// The overhead wires (UtilityPoles.ribbon_mesh(): one mesh a chunk). Every vertex sits on its
// wire's centre line with the wire's direction in NORMAL, UV (side -1 / +1, metres along) and
// UV2 (radius in metres, kind). The vertex shader turns each piece into a ribbon facing the
// camera, never thinner than min_px pixels: below that the wire's real width goes into ALPHA,
// so a 14 mm conductor two hundred metres off is a faint hairline rather than a dashed alias. The
// fragment shades it as the round wire it stands for (the normal swept across the ribbon) and
// draws what each kind is: the bare stranded primaries, twisted triplex (secondary, drops) with
// its bare neutral, the comm bundles with their helical lashing wire, the guys. Detail under a
// few pixels fades to its average. No shadow (the node casts none).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/color_space.gdshaderinc"

global uniform float road_wetness;

// Narrowest a wire is drawn, in pixels across.
uniform float min_px = 1.15;
// A sub-pixel wire's coverage is raised to this power for its alpha: under 1 keeps a hairline
// readable (what a camera's sharpening and the eye do to a wire against the sky) without
// thickening it.
uniform float coverage_gamma = 0.75;
// Wires fade out between these distances (metres).
uniform float fade_start = 230.0;
uniform float fade_end = 340.0;
// 1: every wire drawn solid red at full alpha (the ribbon's real footprint).
uniform float debug_solid = 0.0;

varying vec3 v_side;
varying vec3 v_toc;
varying float v_alpha;
varying flat float v_kind;
varying float v_cover;

void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 t = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 toc = normalize(-c);
	vec3 side = cross(t, toc);
	float sl = length(side);
	side = sl > 1e-5 ? side / sl : vec3(1.0, 0.0, 0.0);
	float depth = max(-c.z, 0.05);
	// Metres per pixel at this depth. VIEWPORT_SIZE has read 0 in a vertex stage before (the far
	// city's masts) and small garbage on Compatibility: fall back to 1080 lines.
	float vh = VIEWPORT_SIZE.y > 120.0 ? VIEWPORT_SIZE.y : 1080.0;
	// [1][1] is negative on Compatibility (its projection is flipped in y).
	float px = 2.0 * depth / (max(abs(PROJECTION_MATRIX[1][1]), 0.1) * vh);
	float r = UV2.x;
	float w = max(r, 0.5 * min_px * px);
	v_alpha = pow(r / w, coverage_gamma) * (1.0 - smoothstep(fade_start, fade_end, depth));
	v_cover = r / max(px, 1e-5);
	VERTEX = c + side * w * UV.x;
	NORMAL = toc;
	v_side = side;
	v_toc = toc;
	v_kind = UV2.y;
}

void fragment() {
	if (v_alpha < 0.004) {
		discard;
	}
	float x = clamp(UV.x, -0.999, 0.999);
	// How much of the wire's own pattern a pixel can show (its radius over ~1.5 px).
	float detail = smoothstep(0.75, 2.5, v_cover);
	// Round across the ribbon when it is wide enough to show it; a hairline faces the camera,
	// or its grazing rim (Fresnel) is all a pixel holds and the wire turns pale against the sky.
	float xs = x * mix(0.35, 1.0, detail);
	NORMAL = normalize(v_side * xs + v_toc * sqrt(1.0 - xs * xs));
	float along = UV.y;
	float ang = asin(x);
	vec3 alb;
	float rough = 0.5;
	float metal = 0.0;
	int k = int(v_kind + 0.5);
	if (k == 0) {
		// Bare stranded aluminium, dulled grey.
		float strand = 0.5 + 0.5 * sin((along / 0.014 + ang / TAU * 7.0) * TAU);
		alb = vec3(0.3) * (1.0 + 0.18 * (strand - 0.5) * detail);
		metal = 0.65;
		rough = 0.48;
	} else if (k == 1 || k == 3) {
		// Triplex: two black insulated conductors twisted round a bare neutral.
		float tw = fract(along / (k == 1 ? 0.36 : 0.26) + ang / TAU * 3.0);
		float groove = smoothstep(0.0, 0.1, tw) * smoothstep(1.0, 0.9, fract(tw * 3.0));
		float neutral = step(0.667, tw);
		alb = mix(vec3(0.03), vec3(0.26), neutral * detail * 0.85 + (1.0 - detail) * 0.12);
		alb *= mix(1.0, 0.45 + 0.55 * groove, detail);
		metal = neutral * detail * 0.55;
		rough = 0.5;
	} else if (k == 2) {
		// A comm bundle: black jackets lashed to the strand by a bright helical wire.
		float lash = fract(along / 0.42 + ang / TAU);
		float lw = smoothstep(0.04, 0.0, abs(lash - 0.5));
		alb = mix(vec3(0.025), vec3(0.38), lw * detail);
		alb = mix(alb, vec3(0.04), 1.0 - detail);
		metal = lw * detail * 0.7;
		rough = 0.55;
	} else if (k == 4) {
		// Galvanised guy strand.
		alb = vec3(0.28);
		metal = 0.6;
		rough = 0.5;
	} else {
		alb = vec3(0.03);
		rough = 0.5;
	}
	float wet = clamp(road_wetness, 0.0, 1.0);
	rough = mix(rough, rough * 0.5, wet);
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.35;
	ALPHA = clamp(v_alpha, 0.0, 1.0);
	if (debug_solid > 0.5) {
		ALBEDO = vec3(1.0, 0.0, 0.0);
		ALPHA = 1.0;
	}
}
