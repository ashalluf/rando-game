shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;

// A lighthouse's light as it is seen from far away (Lighthouses): one camera-facing billboard at
// the lens, the way aircraft_lights.gdshader draws a plane's lights - never smaller than
// `min_angle` of the view, and pulled in along its own view ray to just inside the camera's far
// plane past `max_depth` - so it reads as a point across the whole basin. It FLASHES: the rotor it
// hangs on (LighthouseBeacon) turns the lens, and the light is bright only while one of its
// `beams` panels points at the eye. The beam axis is the rotor's local +X, read off MODEL_MATRIX,
// so nothing per frame is set from script and every copy turns in step. Between flashes the lamp
// still glows faintly through the lens.
//
// Mesh: one quad whose four corners all sit at the light's centre; UV the corner; UV2.x the light's
// core size in metres.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
uniform vec3 lamp_color = vec3(1.0, 0.93, 0.78);
// Lens panels (beams) round the rotor, and how tightly a flash is focused (a power of the cosine
// of the angle between the beam and the eye: 220 is a flash of about a sixth of a second at a
// 20 s turn).
uniform float beams = 2.0;
uniform float focus = 220.0;
// The steady glow between flashes, and how much a flash grows the light.
uniform float glow = 0.10;
uniform float flash_grow = 3.0;
uniform float min_angle = 0.0055;
uniform float hdr = 3.0;
uniform float max_depth = 11000.0;
// By day the lamp is off (the flash still shows a little: a lighthouse in daylight reads as a
// glint, not a lamp).
uniform float day_level = 0.06;

// RcLighthouse (look 1): the lantern reads as the source - a steady lamp with a soft halo between
// flashes (the old glow was a faint dot), swelling as a panel swings toward the eye (the lens's
// fringe, a broad cosine power) before the flash itself. 0 = the old lamp.
uniform float look = 0.0;
uniform float look_glow = 0.34;
uniform float look_swell = 0.9;
uniform float look_halo = 4.5;
// Metres the billboard is pulled toward the eye: at the lamp's centre the lens barrel (0.55 m) and
// the lantern's glass (1.3 m) stood in front of it and the old lamp's core was never seen.
uniform float look_pull = 1.9;

varying float v_flash;
varying float v_far;
varying float v_swell;

void vertex() {
	vec3 centre_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_eye = CAMERA_POSITION_WORLD - centre_w;
	vec3 axis = MODEL_MATRIX[0].xyz;
	vec2 a2 = normalize(axis.xz + vec2(1e-6, 0.0));
	vec2 e2 = normalize(to_eye.xz + vec2(1e-6, 0.0));
	float az = atan(a2.x * e2.y - a2.y * e2.x, dot(a2, e2));
	float f = 0.0;
	float sw = 0.0;
	for (int k = 0; k < 4; k++) {
		if (float(k) < beams) {
			float c = cos(az - 6.2831853 * float(k) / beams);
			f += pow(max(c, 0.0), focus);
			sw += pow(max(c, 0.0), 14.0);
		}
	}
	v_swell = sw * look;
	// Seen from well above or below the beam's plane the flash is weaker.
	float elev = abs(to_eye.y) / max(length(to_eye), 1.0);
	v_flash = f * (1.0 - smoothstep(0.08, 0.5, elev));
	vec3 centre = (VIEW_MATRIX * vec4(centre_w, 1.0)).xyz;
	float depth = max(-centre.z, 0.01);
	if (look > 0.5) {
		centre *= max(depth - look_pull, 0.5) / depth;
	}
	float size = max(UV2.x, depth * min_angle) * (1.0 + flash_grow * v_flash) * (1.0 + look * (look_halo - 1.0 + v_swell));
	v_far = smoothstep(3000.0, 9000.0, depth);
	if (depth > max_depth) {
		float k = max_depth / depth;
		centre *= k;
		size *= k;
	}
	vec2 corner = (UV - vec2(0.5)) * size;
	VERTEX = centre + vec3(corner.x, -corner.y, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float core = exp(-r * r * 12.0);
	float halo = exp(-r * r * 2.4) * 0.32;
	float shape = (core + halo) * (1.0 - smoothstep(0.82, 1.0, r));
	float night = clamp(lamp_factor, 0.0, 1.0);
	float level = max(night, day_level * v_flash);
	float a = shape * (glow * night + v_flash * 1.6) * level * (1.0 - 0.45 * v_far);
	if (look > 0.5) {
		// The quad is look_halo times bigger: the core keeps its old size, a halo fills the rest.
		float rc = r * look_halo * (1.0 + v_swell);
		float lcore = exp(-rc * rc * 12.0);
		float lhalo = exp(-r * r * 5.0) * (1.0 - smoothstep(0.7, 1.0, r));
		float steady = look_glow + look_swell * v_swell;
		a = (lcore * (steady + v_flash * 1.6) + lhalo * (0.07 + 0.22 * v_swell + 0.5 * v_flash)) * level * (1.0 - 0.45 * v_far);
		vec3 lc = lamp_color * (1.0 + hdr * lcore * min(a, 1.0));
		ALBEDO = cs_out(lc * clamp(a, 0.0, 1.0));
	} else {
		vec3 col = lamp_color * (1.0 + hdr * core * min(a, 1.0));
		ALBEDO = cs_out(col * clamp(a, 0.0, 1.0));
	}
}
