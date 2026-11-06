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
// 1 while the camera is down in the underground station (MetroLook.saloon()): the saloon is lit by
// its own LED strips, never by the sky's colour (at golden hour that drew it peach), and the glass
// mirrors the lit station, not a sky. 0 everywhere else: the old shader exactly.
uniform float underground = 0.0;
uniform vec3 led_color = vec3(0.90, 0.95, 1.0);
uniform vec3 station_color = vec3(0.16, 0.155, 0.15);
// 1 (RcRailCrossing, wave 8's rail_crossing refcam): tinted laminated glass (`look5_tint` of the
// saloon through it, at least `look5_f0` mirrored), the saloon lit NEUTRAL by its windows and
// strips (the golden sky's colour drew every window a flat tan panel) and people in it: seated
// passengers both sides and a few standees in the aisle. 0: the old shader exactly.
uniform float look5 = 0.0;
uniform float look5_tint = 0.14;
uniform float look5_f0 = 0.085;

varying vec3 mpos;
varying vec3 mnrm;
varying vec3 mcam;


void vertex() {
	mpos = VERTEX;
	mnrm = NORMAL;
	mcam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}


float l5_hash(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}


// A person seated (stand 0) or standing (1) in the plane x = xp, crossed at q (model space):
// rgb the colour, a 1 where the ray meets them. `row` picks who (or nobody) is there.
vec4 l5_person(vec3 q, float zm, float row, float stand, vec3 light) {
	float h = l5_hash(row);
	float h2 = l5_hash(row + 31.7);
	float base = stand > 0.5 ? box_min.y : seat_y;
	float rise = stand > 0.5 ? 0.82 : 0.0;
	float y = q.y - base - rise;
	// Shoulders to hips (rounded at the top), the neck, the head.
	float tw = 0.21 + 0.04 * h2;
	float torso = step(abs(zm), tw) * step(0.02, y) * step(y, 0.62 - 0.35 * pow(abs(zm) / tw, 4.0));
	float neck = step(abs(zm), 0.05) * step(0.6, y) * step(y, 0.7);
	float face = step(length(vec2(zm, y - 0.79)), 0.105);
	float legs = stand > 0.5 ? step(abs(abs(zm) - 0.08), 0.065) * step(-0.82, y) * step(y, 0.02) : 0.0;
	float any_hit = max(max(torso, neck), max(face, legs));
	if (any_hit < 0.5) {
		return vec4(0.0);
	}
	vec3 shirt = mix(vec3(0.05, 0.06, 0.09), vec3(0.32, 0.28, 0.22), h2);
	shirt = mix(shirt, vec3(0.36, 0.08, 0.06), step(0.82, h2));
	vec3 skin = mix(vec3(0.07, 0.04, 0.025), vec3(0.42, 0.27, 0.19), l5_hash(row + 7.3));
	vec3 hair = mix(vec3(0.015), vec3(0.09, 0.06, 0.035), l5_hash(row + 2.9));
	vec3 col = shirt;
	if (face > 0.5) {
		col = (y - 0.79 > 0.035 || abs(zm) > 0.075) ? hair : skin;
	} else if (neck > 0.5) {
		col = skin;
	} else if (legs > 0.5) {
		col = vec3(0.03, 0.035, 0.05);
	}
	return vec4(col * light, 1.0);
}


// The nearest person on the ray before t (seated rows by both side walls, standees in the aisle).
vec4 l5_people(vec3 p, vec3 d, float t, vec3 light) {
	vec4 best = vec4(0.0);
	float bt = t;
	for (int k = 0; k < 3; k++) {
		float xp = k == 0 ? -0.62 : (k == 1 ? 0.62 : 0.0);
		if (abs(d.x) < 1e-4) {
			continue;
		}
		float tp = (xp - p.x) / d.x;
		if (tp <= 0.0 || tp >= bt) {
			continue;
		}
		vec3 q = p + d * tp;
		float stand = k == 2 ? 1.0 : 0.0;
		float pitch = k == 2 ? 2.3 : seat_pitch;
		float cell = floor(q.z / pitch);
		float row = cell * 3.0 + float(k) * 101.0;
		float odds = k == 2 ? 0.72 : 0.42;
		if (l5_hash(row + 0.5) < odds) {
			continue;
		}
		float zm = (fract(q.z / pitch) - 0.5) * pitch;
		vec4 hit = l5_person(q, zm, row, stand, light);
		if (hit.a > 0.5) {
			best = hit;
			bt = tp;
		}
	}
	return best;
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
	vec3 strip_c = underground > 0.0 ? mix(strip_color, led_color, underground) : strip_color;
	vec3 light = lit_day + lit_night * strip_c;
	vec3 col;
	if (look5 > 0.5) {
		// Daylight through the windows is neutral inside, and the strips burn by day too.
		float lum = dot(day, vec3(0.2126, 0.7152, 0.0722));
		light = vec3(lum) * day_light * 1.25 + strip_c * (0.08 + night * night_light);
		vec4 who = l5_people(p, d, t, light);
		if (who.a > 0.5) {
			return who.rgb;
		}
	}
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
			col = wall_color * 0.8 * light + strip_c * strip * (0.25 + night * 2.2);
		} else {
			col = floor_color * light;
		}
	} else if (t == t3.x) {
		// The far side: its windows show the day (or the dark street), seat backs under them.
		if (h.y > sill && h.y < head) {
			float pillar = step(0.88, fract(h.z / 1.05));
			// Seen through the far pane too: the day out there is a second tint down.
			vec3 out_day = look5 > 0.5 ? mix(day, vec3(dot(day, vec3(0.2126, 0.7152, 0.0722))), 0.6) * 0.3 : day * 0.38;
			col = mix(mix(out_day, street_color * 0.4, night), wall_color * 0.3 * light, pillar);
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
	vec3 day = cs_srgb_to_linear(max(sky_tint.rgb, vec3(0.0))) * (1.0 - night_factor * 0.92);
	float night = clamp(night_factor, 0.0, 1.0);
	// The mirror (world-space reflected ray: up is model +y, the cars stay level enough).
	vec3 R = reflect(d, N);
	vec3 mirror = mix(street_color * (0.6 + 0.6 * (1.0 - night)), day * mix(0.9, 1.2, clamp(R.y, 0.0, 1.0)) + vec3(0.02) * night, smoothstep(-0.08, 0.12, R.y));
	if (underground > 0.0) {
		day *= 1.0 - underground;
		night = mix(night, 1.0, underground);
		mirror = mix(mirror, station_color * mix(0.7, 1.3, clamp(R.y * 0.5 + 0.5, 0.0, 1.0)), underground);
	}
	vec3 inside = saloon(mpos - N * 0.02, d, night, day);
	float tint = glass_tint;
	if (look5 > 0.5) {
		tint = look5_tint;
		fres = max(fres, look5_f0);
	}
	vec3 emit = inside * tint * (1.0 - fres) + mirror * fres * reflect_emit;
	ALBEDO = cs_out(vec3(0.01));
	ROUGHNESS = 0.06;
	SPECULAR = 0.5;
	METALLIC = 0.0;
	EMISSION = cs_out(emit);
}
