shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled;
// The night game's glow (BallparkBuild): the haze over a floodlit bowl, lit by the light banks.
// Drawn on the back faces of an ellipsoid round the bowl (so from inside it or outside it); each
// fragment integrates a haze that thins with height along the view ray's chord through the
// ellipsoid, cut short by the scene's depth, so the stands and the hills in front of it hide
// what is behind them. Nothing by day (lamp_factor). Works on both renderers.

#include "res://shaders/ballpark_common.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 radii = vec3(170.0, 90.0, 170.0);
uniform float density = 0.0035;
uniform float scale_height = 26.0;
uniform vec3 glow_color = vec3(1.0, 0.93, 0.8);

varying vec3 centre;

void vertex() {
	centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	float level = bp_flood();
	if (level <= 0.0) {
		discard;
	}
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 frag_w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 dir = normalize(frag_w - cam);
	// The scene behind this pixel, along the ray.
	float depth = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_t = length(vp.xyz / vp.w);
	// The ray through the ellipsoid, in its unit-sphere space.
	vec3 o = (cam - centre) / radii;
	vec3 d = dir / radii;
	float a = dot(d, d);
	float b = dot(o, d);
	float c = dot(o, o) - 1.0;
	float disc = b * b - a * c;
	if (disc <= 0.0) {
		discard;
	}
	float sq = sqrt(disc);
	float t0 = max((-b - sq) / a, 0.0);
	float t1 = min((-b + sq) / a, scene_t);
	if (t1 <= t0) {
		discard;
	}
	// Four samples along the chord: the haze is thickest low over the field.
	float acc = 0.0;
	for (int i = 0; i < 4; i++) {
		float t = mix(t0, t1, (float(i) + 0.5) / 4.0);
		vec3 p = cam + dir * t;
		float h = max(p.y - (centre.y - radii.y * 0.15), 0.0);
		vec3 rel = (p - centre) / radii;
		float r = clamp(1.0 - dot(rel.xz, rel.xz), 0.0, 1.0);
		acc += exp(-h / scale_height) * r;
	}
	float glow = acc * 0.25 * (t1 - t0) * density * level;
	ALBEDO = cs_out(glow_color * min(glow, 1.5));
}
