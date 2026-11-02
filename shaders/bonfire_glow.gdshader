shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The glow of a beach bonfire seen across the sand at night (BonfireNight, the bonfire_night
// refcam): a camera-facing additive quad over the ring - a tight hot core where the flames are,
// a warm halo round it - so a fire 20-200 m off reads as a fire, not as a dim brown puff behind
// the ring's wall. It never shrinks under `min_angle` of the view (a far fire stays a point of
// light), flickers on its own phase, and reaches exactly zero at the quad's edge (an additive
// tail adds the fog-free quad's outline on Forward+). Works in LINEAR on both renderers.

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;

// Linear colours of the core and the halo, their strengths, and the halo's share of the quad.
uniform vec3 core_color = vec3(1.0, 0.62, 0.22);
uniform vec3 halo_color = vec3(1.0, 0.36, 0.08);
uniform float core_gain = 2.2;
uniform float halo_gain = 0.16;
uniform float core_share = 0.16;
// Smallest size the quad is drawn at, as an angle (radians) at its distance.
uniform float min_angle = 0.02;
// Flicker strength (each fire on its own phase, a hash of where it stands).
uniform float flicker = 0.18;

varying float v_phase;
varying float v_shrink;
// 0 near (the real flames carry the fire there), 1 from a few tens of metres.
varying float v_far;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	float dist = length(centre - INV_VIEW_MATRIX[3].xyz);
	float grow = max(size, dist * min_angle) / max(size, 1e-3);
	// The core keeps its share of a quad grown only for the far view (a point of light, not a disc).
	v_shrink = 1.0 / grow;
	v_far = smoothstep(10.0, 45.0, dist);
	v_phase = fract(sin(dot(floor(centre.xz + 0.5), vec2(12.9898, 78.233))) * 43758.5453) * 6.2831;
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * world * mat4(vec4(size * grow, 0.0, 0.0, 0.0), vec4(0.0, size * grow, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	// Taller than wide: flames rise.
	p.y = p.y > 0.0 ? p.y * 1.25 : p.y * 0.85;
	float r = length(p);
	float edge = 1.0 - smoothstep(0.2, 1.0, r);
	float halo = pow(max(1.0 - r, 0.0), 3.0) * edge;
	float cr = core_share * mix(1.0, 2.2, 1.0 - v_shrink);
	float core = exp(-r * r / max(cr * cr, 1e-4)) * edge;
	float t = TIME + v_phase;
	float f = 1.0 - flicker + flicker * (0.55 + 0.3 * sin(t * 7.3) + 0.15 * sin(t * 17.9 + 1.3));
	float on = smoothstep(0.3, 0.9, night_factor);
	vec3 col = (core_color * core * core_gain * mix(0.12, 1.0, v_far) + halo_color * halo * halo_gain * mix(0.45, 1.0, v_far)) * f * on;
	ALBEDO = cs_out(col);
}
