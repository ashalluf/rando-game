shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The pool of light a street lamp throws on the pavement. Additive, unshaded, flat on the
// ground, and driven straight off night_factor so it costs nothing by day. This is what keeps
// the street readable at night even on the web build, where a few hundred real omni lights are
// not an option.

// Not night_factor: the lamps come on in a storm too, and a storm at noon is dark enough that
// a black street reads as a bug. DayNight sets this to max(night, weather).
global uniform float lamp_factor;
// How much of the way the pools come in on the square of lamp_factor (DayNight hands it from
// SunsetReview: 1 at a clear dusk, 0 in the A/B and in bad weather): a lamp switched on at sunset
// does not lay a pool on a road still in daylight. 1 by default, where it changes nothing at 0 or 1.
global uniform float lamp_ease;
uniform vec3 tint : source_color = vec3(1.0, 0.84, 0.58);
uniform float strength : hint_range(0.0, 4.0) = 1.0;
// How hard the pool falls off from the centre. Higher is a tighter, brighter middle.
uniform float falloff : hint_range(0.5, 6.0) = 2.4;
// Add as Compatibility does: in DISPLAY numbers. Forward+ adds in linear HDR, where a broad pool's
// 0.3 over dark asphalt (linear ~0.02) is a jump from display 0.15 to 0.6 - a flat white disc on
// the Mac (the metro kiosk's and the freeway's pools, fwd-review-e). With this on, Forward+ adds the
// display-space amount decoded, which over a dark ground is what the opengl3 still shows.
uniform bool display_add = false;
// A street lamp's pool on Forward+, where the lamp's real light already lights the road (see below).
uniform float street_forward = 0.4;

// A street lamp's pool (StreetLamps, the night lamps review): INSTANCE_CUSTOM.a 1 marks it, and
// the pool is the light a real head throws rather than a soft dot - illuminance off a point
// source h metres up, E ~ (1 + d^2/h^2)^-1.5, broad and flat, stretched along the street by the
// arm heads' distribution (the quad is laid in the lamp's frame: x toward the street, y along it).
//   r  h over the pool's across radius     g  the quad's along / across aspect
//   b  how much an arm head's back (house) side is cut                    a  1
// Every other pool (custom 0) keeps its old soft dot.
varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
}

vec3 lp_to_linear(vec3 c) {
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	float r = clamp(1.0 - length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	float a = pow(r, falloff) * lamp_factor * mix(1.0, lamp_factor, lamp_ease) * strength;
	if (v_custom.a > 0.5) {
		vec2 q = (UV - vec2(0.5)) * 2.0;
		float hr = max(v_custom.r, 0.05);
		float aspect = max(v_custom.g, 0.5);
		// Metres over the across radius; the arm heads throw further along the street.
		vec2 m = vec2(q.x, q.y * aspect);
		float along_k = mix(1.0, 1.55, step(0.01, v_custom.b));
		float d2 = (m.x * m.x + (m.y * m.y) / (along_k * along_k)) / (hr * hr);
		float e = pow(1.0 + d2, -1.5);
		// The cut-off: nothing at the quad's rim, eased in from 60 % of it.
		float rim = 1.0 - smoothstep(0.6, 1.0, length(q));
		// A cobra's house-side shield: less light behind the pole line (toward -x).
		float back = 1.0 - v_custom.b * smoothstep(-0.05, -0.75, q.x);
		a = e * rim * back * lamp_factor * mix(1.0, lamp_factor, lamp_ease) * strength;
	}
	// A headlight beam (PropFactory.vehicle_lights() shifts its UVs to 2..3): a fan that starts
	// at the bumper, widens and dies away down the road. Drawn as a round pool it was a white
	// oval on the asphalt - at dusk, as bright as the sky - and from beside the car a smear.
	if (UV.y > 1.5) {
		vec2 b = vec2(UV.x, UV.y - 2.0); // x across the beam, y from the car (0) to its end (1)
		float half_w = 0.16 + 0.34 * b.y;
		float across = 1.0 - smoothstep(half_w * 0.45, half_w, abs(b.x - 0.5));
		float along = smoothstep(0.06, 0.30, b.y) * pow(1.0 - b.y, 2.0);
		a = across * along * lamp_factor * strength * 0.30;
	}
	// COLOR carries the per-part tint, so one mesh can hold a car's white headlights, its red
	// tail lights and its beam on the road and still be a single draw.
	ALBEDO = tint * COLOR.rgb;
	ALPHA = a * COLOR.a;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	// A street lamp's broad pool on Forward+: added in display numbers (fwd-review-e: in linear HDR
	// it was a flat beige carpet), and only the share the real OmniLight does not already give.
	if (v_custom.a > 0.5) {
		vec3 t = mix(tint * 12.92, 1.055 * pow(max(tint, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), tint));
		ALBEDO = lp_to_linear(t * COLOR.rgb * clamp(ALPHA * street_forward, 0.0, 1.0));
		ALPHA = 1.0;
	} else if (display_add) {
		// tint arrives decoded here (source_color): back to display numbers, the add, then decoded.
		vec3 t = mix(tint * 12.92, 1.055 * pow(max(tint, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), tint));
		ALBEDO = lp_to_linear(t * COLOR.rgb * clamp(ALPHA, 0.0, 1.0));
		ALPHA = 1.0;
	}
#endif
}
