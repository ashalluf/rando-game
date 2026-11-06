// Shared by the downtown civic landmark shaders (landmark_facade, curtain_glass, brushed_steel,
// clay_roof, led_screen, fountain_water): the globals DayNight publishes, a hash, and what a
// mirror-like surface reflects.
//
// The reflection is the same idea as building.gdshader's glass, kept in step with it so a glass
// landmark does not read brighter or darker than the towers round it: the sky above the
// horizon, a skyline of blocks keyed on the reflected ray's heading, the street below, and most
// of it EMITTED rather than lit - what a pane or a steel sail mirrors does not depend on the
// light falling on it, and carried in the albedo alone the shaded side of every landmark came
// out black (see building.gdshader, "Most of the mirror is EMITTED").
//
// Shader files use // comments. A # line is a syntax error and Godot falls back to a blank
// white material, which looks like a missing texture rather than a broken shader.

global uniform float night_factor;
global uniform float lamp_factor;
// Arrives VERBATIM (sRGB numbers), see building.gdshader's note on sky_tint.
global uniform vec4 sky_tint;
global uniform vec3 sun_direction;

float lm_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// How bright the sky is right now against a clear noon, from DayNight's published horizon.
float lm_sky_now() {
	return clamp(dot(sky_tint.rgb, vec3(0.299, 0.587, 0.114)) / 0.74, 0.0, 1.5);
}

// What a mirror at world direction `refl` sees, in linear light (before lm_sky_now()).
// `zenith` / `horizon` / `street` are the sky and ground colours (linear), `city` how much of the
// fake skyline to mirror.
vec3 lm_reflection(vec3 refl, vec3 zenith, vec3 horizon, vec3 street, float city) {
	vec3 sky_ref = mix(horizon, zenith, smoothstep(0.0, 0.55, refl.y));
	if (city > 0.0) {
		float heading = atan(refl.x, refl.z) * 0.159155;
		float near_slot = heading * 26.0;
		float far_slot = heading * 70.0;
		float near_roof = mix(0.05, 0.42, lm_hash21(vec2(floor(near_slot), 3.7)));
		float far_roof = mix(0.10, 0.70, lm_hash21(vec2(floor(far_slot), 8.3))) * step(0.55, lm_hash21(vec2(floor(far_slot), 1.9)));
		float soft = 0.012;
		float in_near = 1.0 - smoothstep(near_roof - soft, near_roof + soft, refl.y);
		float in_far = (1.0 - smoothstep(far_roof - soft, far_roof + soft, refl.y)) * (1.0 - in_near);
		float rows_f = refl.y * 30.0;
		float bays_f = near_slot * 5.0;
		float fine = 1.0 - smoothstep(0.25, 0.7, max(fwidth(rows_f), fwidth(bays_f)));
		float panes = step(0.42, fract(rows_f)) * step(0.30, fract(bays_f));
		vec3 near_wall = mix(vec3(0.16, 0.15, 0.14), vec3(0.09, 0.10, 0.12), lm_hash21(vec2(floor(near_slot), 9.1)));
		near_wall = mix(near_wall, near_wall * 0.5 + horizon * 0.12, panes * fine * 0.85);
		vec3 far_wall = mix(horizon * 0.55, near_wall, 0.35);
		sky_ref = mix(sky_ref, far_wall, in_far * city);
		sky_ref = mix(sky_ref, near_wall, in_near * city);
	}
	return mix(street, sky_ref, smoothstep(-0.22, 0.10, refl.y));
}

// A tight sun glint on a mirror, for the blinding flash off glass and polished steel.
float lm_glint(vec3 refl, float power) {
	return pow(max(dot(normalize(refl), normalize(sun_direction)), 0.0), power) * (1.0 - night_factor);
}
