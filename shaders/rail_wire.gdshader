// The Coral Line's overhead wires on the aerial structure (RcRailAerial; LightRailKit's
// "RailWires", one mesh a chunk): the contact wire, the messenger and the droppers. The ribbon is
// utility_wire.gdshader's (every vertex on the wire's centre line, the tangent in NORMAL, UV.x the
// side, turned to the camera and never thinner than min_px pixels; a sub-pixel wire's real width
// is its alpha). What differs: the wire is weathered copper, and at night it catches the walkway
// luminaires on the poles - UV.y is metres to the nearest pole, and the light the wire takes from
// the lamp there is emitted (x lamp_factor), so the catenary reads as fine lit lines near each
// pole fading into the dark between them, as it does in a photograph of an aerial line at night.
//   UV2   x: radius (m), y: kind (0 contact wire / messenger, 4 dropper)
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

uniform float min_px = 1.0;
uniform float coverage_gamma = 0.75;
uniform float fade_start = 260.0;
uniform float fade_end = 380.0;
// The lamps' light on the wire: its colour (linear), how bright at the pole, how fast it falls off
// along the wire (metres), and a floor all along it (the street's glow).
uniform vec3 catch_color = vec3(1.0, 0.72, 0.42);
uniform float catch_gain = 0.55;
uniform float catch_reach = 6.0;
uniform float catch_floor = 0.05;

varying vec3 v_side;
varying vec3 v_toc;
varying float v_alpha;
varying flat float v_kind;

void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 t = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 toc = normalize(-c);
	vec3 side = cross(t, toc);
	float sl = length(side);
	side = sl > 1e-5 ? side / sl : vec3(1.0, 0.0, 0.0);
	float depth = max(-c.z, 0.05);
	// Metres per pixel at this depth (utility_wire.gdshader's rule: VIEWPORT_SIZE can read 0 in
	// a vertex stage; [1][1] is negative on Compatibility).
	float vh = VIEWPORT_SIZE.y > 120.0 ? VIEWPORT_SIZE.y : 1080.0;
	float px = 2.0 * depth / (max(abs(PROJECTION_MATRIX[1][1]), 0.1) * vh);
	float r = UV2.x;
	float w = max(r, 0.5 * min_px * px);
	v_alpha = pow(r / w, coverage_gamma) * (1.0 - smoothstep(fade_start, fade_end, depth));
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
	NORMAL = normalize(v_side * x * 0.5 + v_toc * sqrt(1.0 - x * x * 0.25));
	// Weathered copper (the contact wire, the messenger), galvanised droppers.
	vec3 alb = v_kind > 2.0 ? vec3(0.26) : vec3(0.16, 0.115, 0.085);
	float lamp = clamp(lamp_factor, 0.0, 1.0);
	float near = exp(-max(UV.y, 0.0) / catch_reach);
	vec3 emit = catch_color * lamp * (catch_gain * near + catch_floor);
	float wet = clamp(road_wetness, 0.0, 1.0);
	ALBEDO = cs_out(alb);
	ROUGHNESS = mix(0.45, 0.25, wet);
	METALLIC = 0.6;
	SPECULAR = 0.4;
	EMISSION = cs_out(emit);
	ALPHA = clamp(v_alpha, 0.0, 1.0);
}
