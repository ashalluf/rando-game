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
// PoliceNightLook's shared flash clock (s), so the light on the street is the lens that is lit;
// below 0, shader TIME (POLICE_NIGHT_LOOK=0, the A/B).
uniform float clock = -1.0;
// How much hotter a lit lens burns after dark (x lamp_factor): an HDR source the glow blooms,
// with a white-hot middle. 0 is the old bar.
uniform float night_gain = 0.0;
global uniform float lamp_factor;
// The police pursuit (PursuitLook; 0 = the old bar): `pattern` 1 is a modern LED triple flash, three
// pulses a side over 0.42 of each half (a bank lit 72 % of the time, not 36 %: most frames were
// dark), mirrored by police_wash.gdshader and PoliceCar.flash_side(); `led` 1 shades
// PursuitLook.light_bar_mesh(): a clear tinted dome over rows of LED pods (UV metres along the bar,
// UV2.y the way round the dome's profile; UV2.x < 0 is the housing), shaded by a view-space sheen.
uniform float pattern = 0.0;
uniform float led = 0.0;

varying vec4 part;

void vertex() {
	part = COLOR;
}

float strobe(float t, float start) {
	if (pattern > 0.5) {
		float u = t - start;
		return step(0.0, u) * step(u, 0.42) * step(mod(u, 0.15), 0.12);
	}
	float a = step(start, t) * step(t, start + 0.09);
	float b = step(start + 0.15, t) * step(t, start + 0.24);
	return max(a, b);
}

void fragment() {
	float t = fract((clock >= 0.0 ? clock : TIME) * rate + phase);
	float bank = part.a;
	float lit = 0.0;
	if (bank > 0.75) {
		lit = strobe(t, 0.5);
	} else if (bank > 0.25) {
		lit = strobe(t, 0.0);
	}
	float housing = 1.0 - step(0.25, bank);
	float on = lit * lights_on;
	float hot = energy * (1.0 + night_gain * clamp(lamp_factor, 0.0, 1.0));
	vec3 lens = part.rgb * mix(idle, hot, on);
	// A lit lens burns toward white: an LED array saturates the camera.
	lens += vec3(1.0) * on * night_gain * clamp(lamp_factor, 0.0, 1.0) * 0.6 * energy * 0.25;
	ALBEDO = mix(lens, part.rgb, housing);
	if (led > 0.5) {
		float night = clamp(lamp_factor, 0.0, 1.0);
		vec3 n = normalize(NORMAL);
		float fres = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 4.0);
		// A sheen off the top of the dome / housing: the sky and the street lights in it.
		float sheen = 0.04 + 0.5 * fres + 0.12 * pow(clamp(n.y, 0.0, 1.0), 6.0);
		if (UV2.x < 0.0) {
			// Housing and feet: black satin.
			ALBEDO = vec3(0.012) + vec3(0.07) * sheen;
		} else {
			// The pods: round LEDs every 4.5 cm along the bar in three rows round the dome.
			vec2 g = vec2(UV.x / 0.045, UV2.y * 3.0);
			vec2 cell = fract(g) - 0.5;
			float r = length(cell * vec2(1.0, 0.75));
			float px = max(fwidth(g.x), fwidth(g.y));
			float dot_m = 1.0 - smoothstep(0.26 - px, 0.26 + px, r);
			// Under a pixel the pods are their average.
			dot_m = mix(dot_m, 0.21, smoothstep(0.35, 0.9, px));
			float row_ok = step(0.08, UV2.y) * step(UV2.y, 0.92);
			dot_m *= row_ok;
			float is_lens = step(0.25, bank);
			vec3 c = part.rgb;
			// Off: dark tinted polycarbonate, the chips faintly coloured, the chrome reflectors grey.
			vec3 off_col = c * 0.035 + vec3(0.05) * (1.0 - dot_m) * 0.3 + c * dot_m * 0.22;
			// On: the chips burn white-hot in the middle, the dome glows the colour around them.
			float hot_k = energy * (1.0 + 2.2 * night);
			vec3 on_col = c * hot_k * (0.18 + 0.82 * dot_m) + vec3(1.0) * dot_m * hot_k * 0.18 * night;
			vec3 lens_col = mix(off_col, on_col, on) + vec3(0.6, 0.65, 0.7) * sheen * 0.18;
			// The takedown / alley lamps in the middle (bank 0): clear, dark.
			vec3 clear_col = vec3(0.012) + vec3(0.05) * dot_m + vec3(0.6) * sheen * 0.12;
			ALBEDO = mix(clear_col, lens_col, is_lens);
		}
	}
}
