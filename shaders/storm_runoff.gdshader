// Water running off the city in the rain (StormDrama, scripts/world/storm_drama.gd): one MultiMesh
// of unit quads, each a stream off a roof's edge or a drip line off an awning, turned to the camera
// about its own vertical axis in the vertex stage (skip_vertex_transform: view space out).
// INSTANCE_CUSTOM: x kind (0 a spout / roof edge, 1 the splash at its foot, 2 an awning's drip
// line), y the height in metres, z a seed (0..1), w how much water (0..1). Half-float safe.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;
global uniform float lamp_factor;

// The rain, 0..1 (Weather's rain_level), and the storm's gust (StormDrama.gust()).
uniform float flow = 0.0;
uniform float gust = 0.0;
// Linear grey of the water by day, and how much of it is left at night (the lamps' share).
uniform vec3 water = vec3(0.62, 0.66, 0.71);
uniform float night_keep = 0.28;

varying float v_kind;
varying float v_height;
varying float v_seed;
varying float v_amount;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_kind = INSTANCE_CUSTOM.x;
	v_height = INSTANCE_CUSTOM.y;
	v_seed = INSTANCE_CUSTOM.z;
	v_amount = INSTANCE_CUSTOM.w;
	vec3 c = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - c;
	to_cam.y = 0.0;
	vec3 right = normalize(vec3(to_cam.z, 0.0, -to_cam.x) + vec3(1e-5, 0.0, 0.0));
	// The wind pushes a falling stream over toward its foot (more in a gust).
	vec3 wp = c + right * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
	wp.xz -= vec2(0.949, 0.316) * (1.0 - (VERTEX.y + 0.5)) * (0.15 + 0.7 * gust) * step(v_kind, 0.5) * min(sy * 0.08, 1.2);
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
}

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float down = UV.y;                // 0 at the top, 1 at the foot
	float y_m = down * v_height;
	float a = 0.0;
	if (v_kind < 0.5) {
		// A stream: a wavering core, broken into falling slugs of water further down.
		float wob = sin(y_m * 1.7 + TIME * 6.0 + v_seed * 20.0) * 0.18 * down;
		float core = exp(-(x - wob) * (x - wob) * 5.0);
		float slug = hash12(vec2(floor(y_m * 1.4 - TIME * 11.0), v_seed * 91.0));
		float broken = mix(1.0, 0.25 + 0.75 * step(0.35, slug), smoothstep(0.15, 0.7, down));
		a = core * broken * smoothstep(0.0, 0.04, down) * (1.0 - smoothstep(0.96, 1.0, down)) * 0.7;
	} else if (v_kind < 1.5) {
		// The splash where it lands: a churning low puff.
		float r = length(vec2(x, (down - 0.75) * 2.2));
		float churn = 0.6 + 0.4 * sin(TIME * 23.0 + v_seed * 40.0 + x * 9.0);
		a = (1.0 - smoothstep(0.2, 1.0, r)) * churn * 0.42;
	} else {
		// A drip line: columns of drops falling off an edge.
		float col = floor(UV.x * 18.0);
		float cx = fract(UV.x * 18.0) * 2.0 - 1.0;
		float h = hash12(vec2(col, v_seed * 57.0));
		float fall = fract(y_m * 0.45 - TIME * (2.4 + h * 1.2) + h);
		float drop = exp(-cx * cx * 3.0) * smoothstep(0.82, 1.0, fall) * step(0.3, h);
		a = drop * 0.75 * (1.0 - smoothstep(0.85, 1.0, down));
	}
	float light = mix(1.0, night_keep, night_factor) * (0.9 + 0.2 * lamp_factor);
	ALBEDO = cs_out(water * light);
	ALPHA = clamp(a * flow * v_amount, 0.0, 1.0);
}
