shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

// Every light on an aircraft - nav lights, strobes, the beacon, the landing lights - in one mesh
// (AmbientCraft._build_lights()), one draw per aircraft. Each light is a quad whose four corners
// all sit at the light's centre; the vertex shader spreads them into a camera-facing billboard,
// so a light reads from every side instead of vanishing edge-on like a flat quad would.
//
// Per light, in the mesh:
//   VERTEX  the light's centre (all four corners the same point)
//   UV      the corner, 0..1, for the round falloff
//   UV2.x   the light's size in metres
//   UV2.y   kind * 10 + phase * 9: kind 0 steady, 1 strobe, 2 beacon, 3 landing light; the phase
//           (0..1) is rolled per aircraft so two planes do not flash in step
//   NORMAL  which way a directional light faces (landing lights), zero for all-round lights
//   COLOR   rgb colour, a strength
//
// Two things let a real plane's lights read across a city at night the way they do in life:
// a light never shrinks below `min_angle` of the view (a couple of pixels), and one beyond
// `max_depth` is pulled in along its own view ray to just inside the camera's far plane, with
// its size scaled to match, so it lands on exactly the same pixels and survives the far
// clip that the aircraft itself does not. The MeshInstance3D carries a huge extra_cull_margin
// for the same reason.

// Not night_factor: the lamps come on in a storm too (DayNight publishes max(night, weather)).
global uniform float lamp_factor;
// Share of full brightness nav lights and strobes keep by day. Real strobes read in daylight.
uniform float day_level : hint_range(0.0, 1.0) = 0.22;
// Landing lights by day: they are bright enough to see at noon on final.
uniform float day_landing : hint_range(0.0, 1.0) = 0.45;
// Smallest angular size a light's quad is drawn at (radians of view; its bright core is about a
// third of that). 0.006 keeps a distant strobe at a few pixels on a 1080p frame.
uniform float min_angle = 0.006;
// How far over white the core of a light goes, so the glow pass blooms it.
uniform float hdr = 2.5;
// Lights further than this are drawn at this depth instead (keep it under the camera's far).
uniform float max_depth = 11000.0;
// 0 hides the landing lights (they are only on during approach, take-off and the landing roll).
uniform float landing_on : hint_range(0.0, 1.0) = 1.0;

varying float v_kind;
varying float v_phase;
varying float v_facing;
varying float v_far;

void vertex() {
	vec3 centre = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float depth = max(-centre.z, 0.01);
	float size = max(UV2.x, depth * min_angle);
	v_far = smoothstep(2600.0, 7000.0, depth);
	if (depth > max_depth) {
		float k = max_depth / depth;
		centre *= k;
		size *= k;
	}
	vec2 corner = (UV - vec2(0.5)) * size;
	VERTEX = centre + vec3(corner.x, -corner.y, 0.0);
	vec3 n = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	float nl = length(n);
	v_facing = 1.0;
	if (nl > 0.01) {
		// A light facing the eye points back along the view ray.
		float f = dot(n / nl, -normalize(centre));
		v_facing = 0.06 + 0.94 * pow(max(f, 0.0), 2.5);
	}
	float code = UV2.y;
	v_kind = floor(code / 10.0 + 0.001);
	v_phase = (code - v_kind * 10.0) / 9.0;
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float core = exp(-r * r * 10.0);
	float halo = exp(-r * r * 2.6) * 0.30;
	float shape = (core + halo) * (1.0 - smoothstep(0.82, 1.0, r));
	float on = 1.0;
	float level = max(lamp_factor, day_level);
	if (v_kind > 0.5 && v_kind < 1.5) {
		// Strobe: a double flash every 1.3 s.
		float f = fract(TIME / 1.3 + v_phase);
		on = step(f, 0.03) + step(abs(f - 0.10), 0.015);
		level = max(lamp_factor, day_level * 2.0);
	} else if (v_kind > 1.5 && v_kind < 2.5) {
		// Beacon: a red pulse a second.
		float f = fract(TIME + v_phase);
		on = pow(max(sin(f * 6.2832), 0.0), 5.0);
	} else if (v_kind > 2.5) {
		on = landing_on;
		level = max(lamp_factor, day_landing);
	}
	float a = shape * on * level * COLOR.a * v_facing * (1.0 - 0.5 * v_far);
	// The colour carries the brightness past 1.0 in the core; alpha only masks the shape.
	ALBEDO = COLOR.rgb * (1.0 + hdr * core * min(a, 1.0));
	// A light far across the basin fades a little into the haze, like everything else there.
	ALPHA = clamp(a, 0.0, 1.0);
}
