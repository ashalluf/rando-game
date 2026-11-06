shader_type spatial;
// The ridge sign's letters as painted sheet metal (RcRidgeSign, HillSignLetters._letters_v2()).
// Built by code: COLOR.rgb a per-letter tone (linear), COLOR.a the part (1 front face, ~0.66 the
// returns round the edges, ~0.33 the back); UV the surface in metres (x along the sign, y up);
// UV2.x the letter's index, UV2.y the height over the letter's foot. Everything is worked in
// linear on both renderers (color_space.gdshaderinc). Detail under a pixel fades to its average.

#include "res://shaders/color_space.gdshaderinc"

// The paint (linear): a warm white, a little off pure so the sun does not clip it flat.
uniform vec3 paint = vec3(0.70, 0.69, 0.64);
// The bare galvanised back of the sheets.
uniform vec3 back_metal = vec3(0.30, 0.31, 0.31);
// Dust blown up from the slope onto the foot of each letter (linear), and how high it reaches.
uniform vec3 dust = vec3(0.42, 0.33, 0.22);
uniform float dust_height = 5.0;
// Rust / grime streaks run down from the fixings at each horizontal seam.
uniform vec3 streak = vec3(0.34, 0.24, 0.15);
uniform float streak_amount = 0.55;
// Sheet size (metres): 4 x 8 ft panels, seams and the bolt rows on them.
uniform vec2 panel = vec2(1.22, 2.44);
uniform float seam_width = 0.025;

varying vec3 tone;
varying float part;
varying vec2 info;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Thin dark lines every `pitch` metres along t, box-filtered by the pixel footprint `w`: under a
// pixel the line becomes its average darkening, never a shimmer.
float lines(float t, float pitch, float width, float w) {
	float f = max(w, 1e-4);
	float c = width / pitch;
	float a = fract((t - 0.5 * f) / pitch);
	float b = fract((t + 0.5 * f) / pitch);
	// Coverage of the line inside the footprint: integrate the step.
	float span = f / pitch;
	float cov = (floor((t + 0.5 * f) / pitch) - floor((t - 0.5 * f) / pitch)) * c + min(b, c) - min(a, c);
	return clamp(cov / max(span, 1e-4), 0.0, 1.0);
}

void vertex() {
	tone = COLOR.rgb;
	part = COLOR.a;
	info = UV2;
}

void fragment() {
	vec2 p = UV;
	vec2 fw = max(fwidth(p), vec2(1e-4));
	vec3 col;
	float rough = 0.62;
	if (part > 0.8) {
		// Each sheet its own age: a touch whiter or yellower, more or less chalky.
		vec2 cell = floor(p / panel);
		float r = h21(cell + info.x * 17.0);
		col = paint * (0.92 + 0.10 * r) * tone;
		col = mix(col, col * vec3(1.0, 0.97, 0.88), h21(cell * 1.7 + 3.1) * 0.5);
		rough = mix(0.55, 0.75, h21(cell + 9.2));
		// Seams: the vertical joints and the laps.
		float sv = lines(p.x, panel.x, seam_width, fw.x);
		float sh = lines(p.y, panel.y, seam_width * 1.6, fw.y);
		// Faint: a 4 ft sheet's joint is a hairline from a hundred metres (at 0.45 the letters read as
		// tiled walls on Forward+); the laps fainter still.
		col *= 1.0 - max(0.16 * sv, 0.08 * sh);
		// Streaks hang under each lap's fixings: a hash per 0.3 m column, a length each, fading.
		float col_i = floor(p.x / 0.3);
		float lap = p.y / panel.y;
		float below = fract(lap);            // 0 at a lap's foot ... 1 just under the next lap
		float hang = 1.0 - below;            // metres-ish share down from the lap above
		float len = mix(0.15, 0.75, h21(vec2(col_i, floor(lap) + 1.0)));
		float on = step(0.62, h21(vec2(col_i * 1.3, floor(lap) + 7.0)));
		float s = on * smoothstep(len, 0.0, hang) * (1.0 - smoothstep(0.0, 0.25, abs(fract(p.x / 0.3) - 0.5) - 0.12));
		// Thin streaks under a pixel: their share of the column, as a faint tint.
		float thin = clamp(0.1 / max(fw.x * 3.3, 0.1), 0.0, 1.0);
		col = mix(col, streak, s * streak_amount * mix(0.3, 1.0, thin));
		// Dust from the slope on the foot, ragged.
		float n = h21(floor(p * vec2(2.0, 3.0))) * 0.6 + h21(floor(p * 7.0)) * 0.4;
		float d = 1.0 - smoothstep(0.0, dust_height * (0.6 + 0.6 * n), info.y);
		col = mix(col, dust * tone, d * 0.75);
		rough = mix(rough, 0.9, d);
	} else if (part > 0.5) {
		// The returns: the sheet edges and the flashing round them, a greyer paint, dustier low.
		col = paint * 0.78 * tone;
		float d = 1.0 - smoothstep(0.0, dust_height, info.y);
		col = mix(col, dust, d * 0.6);
		rough = 0.7;
	} else {
		col = back_metal * (0.85 + 0.3 * h21(floor(p / panel)));
		rough = 0.5;
		METALLIC = 0.4;
	}
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
}
