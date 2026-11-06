shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;
// The ballpark's light banks after dark (StadiumNight.bank_mesh): a soft bloom over each bank's
// lenses and a faint shaft of lit haze from it toward the field. The lens glare sprites
// (aircraft_lights, kind 4) are the lamps; this is the air round them, which is what makes a night
// game read from the hills. UV2.x 0 = bloom (camera-facing, UV the corner, UV2.y its size), 1 =
// shaft (a ribbon along NORMAL turned to face the eye, UV.x the side, UV.y 0 at the bank).
// Additive light in linear numbers on both renderers (cs_out); nothing by day (bp_flood()).

#include "res://shaders/ballpark_common.gdshaderinc"

uniform float bloom_energy = 0.3;
uniform float shaft_energy = 0.022;
uniform vec3 light_color = vec3(1.0, 0.95, 0.86);
// The smallest a bloom is drawn, in radians of view, so a bank across the basin still reads.
uniform float min_angle = 0.012;

varying float v_kind;
varying float v_face;
varying float v_t;

void vertex() {
	v_kind = UV2.x;
	vec3 wc = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_eye = CAMERA_POSITION_WORLD - wc;
	float dist = max(length(to_eye), 0.1);
	vec3 axis = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_t = UV.y;
	if (v_kind < 0.5) {
		// Bloom: a bank seen from in front blazes, from behind it is a soft glow.
		float f = dot(axis, to_eye / dist);
		v_face = 0.15 + 0.85 * pow(max(f, 0.0), 2.0);
		vec3 centre = (VIEW_MATRIX * vec4(wc, 1.0)).xyz;
		float size = max(UV2.y, dist * min_angle);
		vec2 corner = (UV - vec2(0.5)) * size;
		// Pulled toward the eye so the bank's own roof and frame do not cut it.
		centre += normalize(-centre) * min(size * 0.5, 12.0);
		VERTEX = centre + vec3(corner.x, -corner.y, 0.0);
	} else {
		// Shaft: widens from the bank toward the field, turned to face the eye.
		vec3 side = normalize(cross(axis, to_eye / dist));
		float w = mix(UV2.y * 0.12, UV2.y, UV.y);
		vec3 p = wc + side * UV.x * w;
		// Seen end-on a shaft is short and thick in the eye's view, side-on long and thin: keep
		// the light it adds about the same by how much air the eye looks through.
		v_face = 1.0 - 0.6 * abs(dot(axis, to_eye / dist));
		// From inside the bowl the shafts would veil the stands: they are a sight from the hills.
		v_face *= smoothstep(150.0, 320.0, dist);
		VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float level = bp_flood();
	if (level <= 0.0) {
		discard;
	}
	vec3 c;
	if (v_kind < 0.5) {
		float r = length(UV - vec2(0.5)) * 2.0;
		// A tight hot core over the lenses and a wide soft skirt; zero at the quad's edge.
		float core = exp(-r * r * 30.0);
		float skirt = exp(-r * r * 6.0) * 0.22;
		float a = (core + skirt) * (1.0 - smoothstep(0.75, 1.0, r));
		c = light_color * a * bloom_energy * v_face;
	} else {
		float across = 1.0 - abs(UV.x);
		float a = across * across * smoothstep(0.0, 0.12, v_t) * (1.0 - smoothstep(0.55, 1.0, v_t));
		c = light_color * a * shaft_energy * v_face;
	}
	ALBEDO = cs_out(c * level);
}
