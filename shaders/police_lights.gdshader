shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

// A police light bar (PoliceCar.light_bar_mesh()): a dark housing and two banks of lenses in one
// mesh. The vertex colour carries each part's colour and its alpha which bank it is in - 0 the
// housing, 0.5 the red bank, 1.0 the blue bank - so the whole bar is one draw call per car.
// Each bank strobes twice, then the other side does: the pattern PoliceCar.flash_side() mirrors
// for the light it throws on the street at night. Lit lenses are HDR so the glow blooms them.

// Flash cycles per second, and where in the cycle this car is (so a row is not in step).
uniform float rate = 1.6;
uniform float phase = 0.0;
// Brightness of a lit lens, and of an unlit one: lenses are coloured plastic and read red and
// blue in daylight even between flashes (at 0.16 an unlit bar vanished into a black roof).
uniform float energy = 4.0;
uniform float idle = 0.45;
// 0 switches the bar off (an abandoned cruiser).
uniform float lights_on = 1.0;

varying vec4 part;

void vertex() {
	part = COLOR;
}

float strobe(float t, float start) {
	float a = step(start, t) * step(t, start + 0.09);
	float b = step(start + 0.15, t) * step(t, start + 0.24);
	return max(a, b);
}

void fragment() {
	float t = fract(TIME * rate + phase);
	float bank = part.a;
	float lit = 0.0;
	if (bank > 0.75) {
		lit = strobe(t, 0.5);
	} else if (bank > 0.25) {
		lit = strobe(t, 0.0);
	}
	float housing = 1.0 - step(0.25, bank);
	vec3 lens = part.rgb * mix(idle, energy, lit * lights_on);
	ALBEDO = mix(lens, part.rgb, housing);
}
