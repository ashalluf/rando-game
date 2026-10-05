shader_type spatial;
// The street's signs (SignKit / StreetSigns): sheeting, bare aluminium backs, galvanised posts,
// clamp hardware and printed black legends, all on one material. What a vertex is rides in its
// colour's alpha (kind / 16, SignKit.K_*), its colour sRGB in the rgb (vertex colours arrive raw
// on both renderers: decoded here, worked in linear, handed over by cs_out()). UV is the face's
// own metres. INSTANCE_CUSTOM.r is a per-sign roll (wear: sun fade, grime, a dented plate's
// sheen).
//
// Retroreflective sheeting sends light back toward its source, so at night a sign is as bright
// as the headlights pointing at it, seen from beside them - the freeway signs' rule
// (freeway_paint.gdshader headlit()): the headlights are taken to be at the camera, aimed along
// it, so whatever the camera looks at within the cone glows, and a free camera at night glints
// too. Gated by lamp_factor (nothing by day).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

// Headlight glint: the headlights' reach (metres), the cone's half-angle (cosine) and how bright
// the sheeting comes back in it.
uniform float glint_reach = 55.0;
uniform float glint_cone = 0.93;
uniform float sheet_retro = 2.4;
// What the sheeting sends back of the street lamps behind the viewer (a faint lift at night).
uniform float lamp_retro = 0.08;
// How much a sign's colours fade in the sun at most (reds first), and grime on everything.
uniform float sun_fade = 0.22;
uniform float grime = 0.18;

varying vec3 obj_pos;
varying float roll;

void vertex() {
	obj_pos = VERTEX;
	roll = INSTANCE_CUSTOM.r;
}


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}


// How strongly headlights at the camera light a retroreflector at `wp` whose face is `n`.
float headlit(vec3 wp, vec3 n, vec3 cam, vec3 fwd) {
	vec3 to_cam = cam - wp;
	float dist = length(to_cam);
	vec3 vd = to_cam / max(dist, 0.001);
	float facing = dot(n, vd);
	vec2 vh = to_cam.xz / max(length(to_cam.xz), 0.001);
	vec2 fh = fwd.xz / max(length(fwd.xz), 0.001);
	float cone = dot(fh, -vh);
	float reach = 1.0 / (1.0 + pow(dist / glint_reach, 2.0));
	return smoothstep(glint_cone, 1.0, cone) * smoothstep(0.05, 0.45, facing) * reach * smoothstep(1.0, 4.0, dist);
}


void fragment() {
	int kind = int(round(COLOR.a * 16.0));
	vec3 col = cs_srgb_to_linear(COLOR.rgb);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
	float night = clamp(lamp_factor, 0.0, 1.0);
	float wet = clamp(road_wetness, 0.0, 1.0);
	// Metres a pixel covers here: detail finer than that is faded to its average.
	float foot = max(length(fwidth(wp)), 0.0004);
	float near = 1.0 - smoothstep(0.002, 0.01, foot);
	// Grime: soft blotches, heavier on the older signs.
	float g = vnoise(obj_pos.xy * 9.0 + roll * 37.0) * 0.6 + vnoise(obj_pos.zy * 23.0) * 0.4;
	float dirt = grime * (0.4 + roll) * smoothstep(0.35, 0.9, g);

	vec3 alb = col;
	float rough = 0.5;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);

	if (kind == 1) {
		// Sheeting: sun-faded by the sign's age (red goes toward salmon, green toward teal-grey).
		float fade = sun_fade * roll * roll;
		vec3 faded = mix(col, vec3(dot(col, vec3(0.3, 0.5, 0.2))) * vec3(1.05, 1.0, 0.98) + vec3(0.04, 0.02, 0.02), 0.6);
		alb = mix(col, faded, fade);
		rough = 0.36 + 0.08 * roll;
		alb *= 1.0 - dirt * 0.6;
		// At night: the headlights coming back, and a little of the street lamps behind.
		float retro = headlit(wp, nw, cam, fwd) * sheet_retro + lamp_retro;
		emit = alb * night * retro * (1.0 - dirt * 0.5);
	} else if (kind == 5) {
		// Printed black legend: matte, not reflective.
		alb = col;
		rough = 0.62;
		spec = 0.35;
	} else if (kind == 2) {
		// Mill-finish aluminium back: brushed streaks across the plate, a dull oxide, grime.
		float streak = vnoise(vec2(UV.x * 3.0, UV.y * 160.0) + roll * 11.0) * near;
		alb = col * (0.92 + 0.12 * streak) * (1.0 - dirt);
		metal = 0.82;
		rough = 0.38 + 0.18 * streak + 0.15 * dirt;
	} else if (kind == 3) {
		// Galvanised post: spangle (crystal patches of slightly different sheen), darker and
		// splashed at the foot.
		float sp = vnoise(UV * vec2(55.0, 30.0) + roll * 7.0);
		float foot_dirt = 1.0 - smoothstep(0.05, 0.7, obj_pos.y);
		alb = col * (0.9 + 0.16 * sp * near) * (1.0 - dirt * 0.8) * (1.0 - foot_dirt * 0.35);
		metal = 0.72;
		rough = 0.42 + 0.2 * sp + 0.2 * foot_dirt;
	} else {
		// Clamps, brackets, bolts.
		alb = col * (1.0 - dirt * 0.6);
		metal = 0.6;
		rough = 0.55;
	}

	// Rain: everything glosses, bare metal darkens a little.
	rough = mix(rough, rough * 0.45, wet);
	alb *= mix(1.0, (kind == 1 || kind == 5) ? 0.95 : 0.85, wet);

	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = cs_out(emit);
}
