// Lime-washed stucco that has stood in the sun (wave 8 refcam5 "church_sunday", RcChurchSunday):
// a Mission church's walls drew as one flat sheet of white, the brightest thing in the frame and
// with nothing on it. A real lime-washed wall is never one colour: the wash goes on in coats that
// dry patchy (soft, metre-sized clouds a few per cent apart), the trowel leaves a gentle undulation
// the low sun picks out, rain carries dust down from every coping and sill in streaks, the foot of
// the wall is darkened by splash-back and rising damp to an uneven tide line, and the newest
// repairs are a brighter coat in rectangles. All of it here, as a factor on the albedo worked out
// in LINEAR light (taken to display numbers on the Compatibility renderer, which lights the raw
// ones) and a tilt of the normal map. `lime_wash` 0 skips it (every other landmark facade).
//
// Inputs: uv in metres on the face (u along, v up), `lh` metres above the building's base (the
// mesh's own y), the face's world normal. Shader files use // comments, never #.

uniform float lime_wash = 0.0;
// The tide line of the damp at the foot of the wall (m) and how dark it is there.
uniform float lime_damp_height = 0.75;
uniform float lime_damp = 0.16;
// Streaks down from copings and sills: how strong, and their spacing (m).
uniform float lime_streaks = 0.10;
// The wash's patchy coats (share up or down) and the trowel's relief.
uniform float lime_patch = 0.07;
uniform float lime_relief = 0.35;

float lw_hash(vec2 p) {
	p = fract(p * vec2(127.13, 311.71));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float lw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = lw_hash(i);
	float b = lw_hash(i + vec2(1.0, 0.0));
	float c = lw_hash(i + vec2(0.0, 1.0));
	float d = lw_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float lw_fbm(vec2 p) {
	return 0.55 * lw_noise(p) + 0.3 * lw_noise(p * 2.13 + 7.1) + 0.15 * lw_noise(p * 4.37 + 3.3);
}

// Returns the albedo factor (linear light) and writes the normal-map tilt into `tilt` (xy).
float lw_factor(vec2 uv, float lh, vec3 nrm, vec2 px, out vec2 tilt) {
	tilt = vec2(0.0);
	if (abs(nrm.y) > 0.5) {
		// Tops (copings, sills, the roof's flat): dust settles, a little darker and even.
		return 1.0 - 0.06 * lime_wash;
	}
	// Coats: soft clouds a metre or two across.
	float coat = lw_fbm(uv * vec2(0.55, 0.7)) - 0.5;
	float f = 1.0 + lime_patch * 2.0 * coat;
	// A newer repair coat in a rectangle here and there (brighter, sharp-ish edges).
	vec2 cell = floor(uv / vec2(3.1, 2.3));
	if (lw_hash(cell + 41.0) < 0.12) {
		vec2 g = fract(uv / vec2(3.1, 2.3));
		vec2 e = min(g, 1.0 - g) * vec2(3.1, 2.3);
		float inside = smoothstep(0.15, 0.4 + px.x * 2.0, min(e.x, e.y));
		f += 0.05 * inside;
	}
	// Streaks: thin vertical runs whose strength wanders along the wall, strongest high up under
	// the coping and fading down (the dust is washed off the lower wall by the splash).
	float col = lw_noise(vec2(uv.x * 2.7, 0.0)) * lw_noise(vec2(uv.x * 0.6 + 5.0, 1.0));
	float run = smoothstep(0.35, 0.8, col) * (0.55 + 0.45 * lw_noise(vec2(uv.x * 1.3, uv.y * 0.25)));
	float sharp = 1.0 - smoothstep(0.02, 0.12, px.x);
	f -= lime_streaks * run * mix(0.5, 1.0, sharp) * smoothstep(0.0, 4.0, lh);
	// The foot: splash-back and rising damp to a ragged tide line.
	float tide = lime_damp_height * (0.75 + 0.5 * lw_fbm(vec2(uv.x * 0.9, 3.0)));
	float damp = 1.0 - smoothstep(tide * 0.7, tide, lh);
	f -= lime_damp * damp * (0.75 + 0.25 * lw_noise(uv * 3.0));
	// The trowel: a gentle undulation, faded once it is under a pixel or two.
	float rel = lime_relief * (1.0 - smoothstep(0.05, 0.3, px.x));
	float e = 0.15;
	float h0 = lw_fbm(uv * 1.7);
	tilt = vec2(lw_fbm((uv + vec2(e, 0.0)) * 1.7) - h0, lw_fbm((uv + vec2(0.0, e)) * 1.7) - h0) * rel;
	return mix(1.0, clamp(f, 0.55, 1.2), lime_wash);
}
