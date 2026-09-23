shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The pool of light a street lamp throws on the pavement. Additive, unshaded, flat on the
// ground, and driven straight off night_factor so it costs nothing by day. This is what keeps
// the street readable at night even on the web build, where a few hundred real omni lights are
// not an option.

// Not night_factor: the lamps come on in a storm too, and a storm at noon is dark enough that
// a black street reads as a bug. DayNight sets this to max(night, weather).
global uniform float lamp_factor;
uniform vec3 tint : source_color = vec3(1.0, 0.84, 0.58);
uniform float strength : hint_range(0.0, 4.0) = 1.0;
// How hard the pool falls off from the centre. Higher is a tighter, brighter middle.
uniform float falloff : hint_range(0.5, 6.0) = 2.4;

void fragment() {
	float r = clamp(1.0 - length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	float a = pow(r, falloff) * lamp_factor * strength;
	// A headlight beam (PropFactory.vehicle_lights() shifts its UVs to 2..3): a fan that starts
	// at the bumper, widens and dies away down the road. Drawn as a round pool it was a white
	// oval on the asphalt - at dusk, as bright as the sky - and from beside the car a smear.
	if (UV.y > 1.5) {
		vec2 b = vec2(UV.x, UV.y - 2.0); // x across the beam, y from the car (0) to its end (1)
		float half_w = 0.16 + 0.34 * b.y;
		float across = 1.0 - smoothstep(half_w * 0.45, half_w, abs(b.x - 0.5));
		float along = smoothstep(0.10, 0.22, b.y) * pow(1.0 - b.y, 1.7);
		a = across * along * lamp_factor * strength * 0.45;
	}
	// COLOR carries the per-part tint, so one mesh can hold a car's white headlights, its red
	// tail lights and its beam on the road and still be a single draw.
	ALBEDO = tint * COLOR.rgb;
	ALPHA = a * COLOR.a;
}
