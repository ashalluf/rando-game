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
	ALBEDO = tint;
	ALPHA = a;
}
