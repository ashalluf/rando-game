shader_type spatial;
render_mode cull_back;

// The light rail car's windows (LightRailTrain, on the model's glass and door_glass slots). Like
// the car cabins and the house windows: the pane is opaque, the sky and street it mirrors are
// EMITTED by Fresnel (a reflection does not depend on the light on the pane), and the inside of
// the car is TRACED - the view ray is followed into the saloon, a box in the section's own model
// space (x across, y up from the rail, z along; the windows are on its sides), and shaded where it
// lands: the far side's windows (the day outside, the street at night), seat rows (cushions at
// seat height, backs below the far sill, in the operator's blue), the floor, the ceiling with its
// lit strip, and stanchions by the doors. Lit by daylight from the windows by day and by its own
// strip lights after dark (`night_factor`), with true parallax and no geometry.

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;
global uniform vec4 sky_tint;

// The saloon in model space (metres; the section's centre at z 0, nose at -z).
uniform vec3 box_min = vec3(-1.20, 0.95, -5.55);
uniform vec3 box_max = vec3(1.20, 2.95, 6.45);
// Far-side window band and the seat rows.
uniform float sill = 1.32;
uniform float head = 2.58;
uniform float seat_y = 1.40;
uniform float seat_inner = 0.26;
uniform float seat_pitch = 1.15;
// Linear colours.
uniform vec3 wall_color = vec3(0.42, 0.42, 0.40);
uniform vec3 floor_color = vec3(0.025, 0.025, 0.03);
uniform vec3 seat_color = vec3(0.012, 0.022, 0.09);
uniform vec3 strip_color = vec3(1.0, 0.93, 0.80);
uniform vec3 street_color = vec3(0.10, 0.095, 0.09);
// How bright the saloon is by day (a share of the sky) and at night (its own lights).
uniform float day_light = 0.42;
uniform float night_light = 1.25;
// The pane's own tint and how much of the mirror is emitted.
uniform float glass_tint = 0.36;
uniform float reflect_emit = 0.75;

varying vec3 mpos;
varying vec3 mnrm;
varying vec3 mcam;


void vertex() {
	mpos = VERTEX;
	mnrm = NORMAL;
	mcam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}


vec3 saloon(vec3 p, vec3 d, float night, vec3 day) {
	// Exit point of the ray from p through the box.
	vec3 inv = 1.0 / max(abs(d), vec3(1e-4)) * sign(d + vec3(1e-6));
	vec3 far_b = mix(box_min, box_max, step(0.0, d));
	vec3 t3 = (far_b - p) * inv;
	float t = min(t3.x, min(t3.y, t3.z));
	vec3 h = p + d * max(t, 0.0);
	vec3 lit_day = day * day_light;
	vec3 lit_night = vec3(night * night_light);
	vec3 light = lit_day + lit_night * strip_color;
	vec3 col;
	// Seat cushions: the ray crosses the seat plane on the way down, outboard of the aisle.
	float ts = (seat_y - p.y) / (abs(d.y) > 1e-4 ? d.y : -1e-4);
	if (d.y < 0.0 && ts > 0.0 && ts < t) {
		vec3 q = p + d * ts;
		float row = fract(q.z / seat_pitch);
		if (abs(q.x) > seat_inner && row < 0.72) {
			return seat_color * light * 1.2;
		}
	}
	if (t == t3.y) {
		if (d.y > 0.0) {
			// Ceiling: panels and the lit strip down the middle.
			float strip = 1.0 - smoothstep(0.22, 0.28, abs(h.x));
			col = wall_color * 0.8 * light + strip_color * strip * (0.25 + night * 2.2);
		} else {
			col = floor_color * light;
		}
	} else if (t == t3.x) {
		// The far side: its windows show the day (or the dark street), seat backs under them.
		if (h.y > sill && h.y < head) {
			float pillar = step(0.88, fract(h.z / 1.05));
			// Seen through the far pane too: the day out there is a second tint down.
			col = mix(mix(day * 0.38, street_color * 0.4, night), wall_color * 0.3 * light, pillar);
		} else if (h.y < sill && h.y > seat_y - 0.05) {
			float row = fract(h.z / seat_pitch);
			col = row < 0.72 ? seat_color * light : wall_color * 0.6 * light;
		} else {
			col = wall_color * 0.75 * light;
		}
	} else {
		col = wall_color * 0.55 * light;
	}
	return col;
}


void fragment() {
	vec3 d = normalize(mpos - mcam);
	vec3 N = normalize(mnrm);
	float ndv = clamp(dot(N, -d), 0.0, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	vec3 day = max(sky_tint.rgb, vec3(0.0)) * (1.0 - night_factor * 0.92);
	float night = clamp(night_factor, 0.0, 1.0);
	// The mirror (world-space reflected ray: up is model +y, the cars stay level enough).
	vec3 R = reflect(d, N);
	vec3 mirror = mix(street_color * (0.6 + 0.6 * (1.0 - night)), day * mix(0.9, 1.2, clamp(R.y, 0.0, 1.0)) + vec3(0.02) * night, smoothstep(-0.08, 0.12, R.y));
	vec3 inside = saloon(mpos - N * 0.02, d, night, day);
	vec3 emit = inside * glass_tint * (1.0 - fres) + mirror * fres * reflect_emit;
	ALBEDO = cs_out(vec3(0.01));
	ROUGHNESS = 0.06;
	SPECULAR = 0.5;
	METALLIC = 0.0;
	EMISSION = cs_out(emit);
}
