shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// A car's lamps as one additive mesh (PropFactory.vehicle_lights()): head and tail glows, the
// indicators, the reversing lamps, the beam fan on the road ahead and the red wash on the road
// behind. Which part a quad is rides in its UV: u is shifted by 2 x the part (0..1 inside it),
// and the beam's v by 2 (light_pool.gdshader's old convention, kept). What the car is DOING -
// braking, signalling, reversing - is the material: PropFactory.vehicle_light_material() keeps one
// shared copy per combination, so a street of cars is still a handful of materials and one draw a
// car. Never instance uniforms here (CLAUDE.md, Car glass and drivers: the Compatibility global
// buffer). Head, tail and beam follow lamp_factor as before; brake, indicator and reverse lamps
// also show by day (`day_glow`), the way a real one does.

global uniform float lamp_factor;
uniform vec3 tint : source_color = vec3(1.0);
uniform float strength : hint_range(0.0, 4.0) = 1.6;
uniform float falloff : hint_range(0.5, 6.0) = 1.3;
// 1 while the brake is on: the tail lamps go from their running glow to a brake light.
uniform float brake = 0.0;
// -1 left, 1 right, 2 hazards, 0 none.
uniform float signal_side = 0.0;
// Where in the blink this car is (0..1), so a queue does not flash in step.
uniform float blink_phase = 0.0;
// 1 while reversing.
uniform float reverse = 0.0;
// Blinks a second (a real flasher is 1-2 Hz).
uniform float blink_rate = 1.5;
// How bright the brake, indicator and reversing lamps are by day (lamp_factor 0).
uniform float day_glow = 1.1;
// Tail lamp running glow, and how much brighter the brake makes it (both x lamp level).
uniform float tail_level = 0.55;
uniform float brake_gain = 2.4;

void fragment() {
	float part = floor(UV.x * 0.5 + 0.001);
	vec2 uv = vec2(UV.x - part * 2.0, UV.y);
	float r = clamp(1.0 - length(uv - vec2(0.5)) * 2.0, 0.0, 1.0);
	float glow = pow(r, falloff);
	float day = max(lamp_factor, day_glow);
	float a = 0.0;
	float blink = step(0.5, fract(TIME * blink_rate + blink_phase));
	if (uv.y > 1.5) {
		// The headlight beam: a fan that starts at the bumper, widens and dies away down the road.
		vec2 b = vec2(uv.x, uv.y - 2.0);
		float half_w = 0.16 + 0.34 * b.y;
		float across = 1.0 - smoothstep(half_w * 0.45, half_w, abs(b.x - 0.5));
		float along = smoothstep(0.06, 0.30, b.y) * pow(1.0 - b.y, 2.0);
		a = across * along * lamp_factor * 0.30;
	} else if (part < 0.5) {
		a = glow * lamp_factor; // headlamps
	} else if (part < 1.5) {
		a = glow * (lamp_factor * tail_level + brake * max(lamp_factor * brake_gain, day_glow));
	} else if (part < 2.5) {
		float on = (signal_side < -0.5 || signal_side > 1.5) ? 1.0 : 0.0;
		a = glow * on * blink * day * 1.4; // left indicators
	} else if (part < 3.5) {
		float on = signal_side > 0.5 ? 1.0 : 0.0;
		a = glow * on * blink * day * 1.4; // right indicators
	} else if (part < 4.5) {
		a = glow * reverse * day * 1.2; // reversing lamps
	} else {
		// The red wash on the road behind: faint while the lamps are on, strong on the brake.
		a = glow * glow * lamp_factor * (0.1 + 0.9 * brake) * 0.3;
	}
	ALBEDO = tint * COLOR.rgb;
	ALPHA = a * strength * COLOR.a;
}
