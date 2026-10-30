shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;

// The glass of a car that has its real cabin built (CarInterior: the car the player drives, a parked
// car he stands by). The cabin behind it is geometry now, so this glass is TRANSPARENT - tinted by
// the pane's own tint (the windscreen clearest, privacy glass dark), the sky mirrored by Fresnel -
// and of the traced cabin (car_cabin.gdshaderinc) it keeps only the people: whoever sits in the
// front seats is still traced on the pane (the player in a car is hidden; the occupant uniforms say
// who is in), drawn opaque where the ray meets them. Lamp covers and mirrors stay solid dark glass.

#include "res://shaders/car_cabin.gdshaderinc"
#include "res://shaders/car_glass_wet.gdshaderinc"

uniform vec3 glass_albedo : source_color = vec3(0.14, 0.155, 0.175);
uniform float glass_roughness = 0.05;
// How much a clear pane (tint 1) still covers, and the mirrored sky's strength.
uniform float clear_alpha = 0.08;
uniform float sky_mirror = 0.55;

varying vec3 lp;
varying vec3 ln;
varying vec3 cam_local;


void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	cam_local = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
}


// Only the people of cabin_view(): their colour and 1 where the ray meets one before it leaves the
// cabin, 0 elsewhere.
vec4 people_view(vec3 o, vec3 d, float dist) {
	float seats = occupant_top.a;
	if (seats < 0.5) {
		return vec4(0.0);
	}
	bool close_up = dist < cabin_detail;
	vec3 safe = vec3(abs(d.x) < 1e-4 ? 1e-4 : d.x, abs(d.y) < 1e-4 ? 1e-4 : d.y, abs(d.z) < 1e-4 ? 1e-4 : d.z);
	vec3 inv = 1.0 / safe;
	vec3 t1 = (cabin_lo - o) * inv;
	vec3 t2 = (cabin_hi - o) * inv;
	vec3 tf = max(t1, t2);
	float t_exit = max(min(min(tf.x, tf.y), tf.z), 0.0);
	float cx = (cabin_hi.x + cabin_lo.x) * 0.5;
	float half_w = (cabin_hi.x - cabin_lo.x) * 0.5;
	float back = seat_z.y > seat_z.x ? 1.0 : -1.0;
	float front_end = back > 0.0 ? cabin_lo.z : cabin_hi.z;
	float dash_rear = front_end + back * 0.42;
	float sx = cx + driver_side * (half_w + 0.03) * 0.5;
	float zw = mix(seat_z.x - back * 0.7, dash_rear + back * 0.22, 0.5);
	zw = dash_rear + back * max((zw - dash_rear) * back, 0.12);
	vec3 wc = vec3(sx, belt_y - 0.05, zw);
	vec3 wn = normalize(vec3(0.0, 0.42, back * 0.91));
	vec3 wu = vec3(1.0, 0.0, 0.0);
	vec3 wv = normalize(cross(wn, wu));
	wv *= sign(wv.y);
	float wr = 0.185;
	float best = t_exit;
	vec3 best_n = vec3(0.0);
	float best_shade = -1.0;
	int best_mat = CAB_FABRIC;
	vec4 best_aux = vec4(0.0);
	float fs = clamp((side_top - belt_y) / 0.42, 0.8, 1.0) * mix(0.94, 1.04, occupant_hair.a);
	if (mod(seats, 2.0) > 0.5) {
		person(o, d, inv, sx, back, fs, 0.0, true, close_up, wc, wu, wv, wr, seat_z.x, best, best_n, best_shade, best_mat, best_aux);
	}
	float px = cx - driver_side * (half_w + 0.03) * 0.5;
	if (mod(floor(seats * 0.5), 2.0) > 0.5) {
		person(o, d, inv, px, back, fs * 0.97, 1.0, false, close_up, wc, wu, wv, wr, seat_z.x, best, best_n, best_shade, best_mat, best_aux);
	}
	if (seats > 3.5) {
		person(o, d, inv, px, back, fs * 0.95, 1.0, false, close_up, wc, wu, wv, wr, seat_z.y, best, best_n, best_shade, best_mat, best_aux);
	}
	if (best_shade < 0.0) {
		return vec4(0.0);
	}
	vec3 sky = sky_tint.rgb + street_light * lamp_factor;
	float lit = 0.2 + 0.55 * max(best_n.y, 0.0) + 0.3 * max(dot(best_n, -d), 0.0);
	vec3 alb = person_albedo(best_mat, best_aux, back) * people_light;
	return vec4(alb * sky * lit * cabin_light, 1.0);
}


void fragment() {
	vec3 n = normalize(ln);
	vec3 to = lp - cam_local;
	float dist = length(to);
	vec3 d = to / max(dist, 1e-5);
	int i = find_pane(lp, n);
	float t = pane_t(i, lp);
	float c = abs(dot(d, n));
	float f = 0.04 + 0.96 * pow(1.0 - c, 5.0);
	ROUGHNESS = glass_roughness;
	SPECULAR = 0.5;
	// Metres a pixel, outside the branches below (the wet glass needs it).
	float ms = length(MODEL_MATRIX[0].xyz);
	float px_m = max(length(fwidth(lp)) * ms, 1e-5);
	if (i >= 0 && pane_hi[i].w > 1.5 || t <= 0.0) {
		// A lamp cover or a mirror: solid dark glass, as before.
		ALBEDO = glass_albedo;
		ALPHA = 1.0;
	} else {
		vec4 who = people_view(lp, d, dist);
		float cover = mix(1.0, clear_alpha, clamp(t, 0.0, 1.0));
		float a = max(cover, f * 0.9);
		vec3 mirror = sky_tint.rgb * f * sky_mirror;
		// A person seen through the glass: opaque, dimmed by the pane's tint as the cabin was.
		ALBEDO = glass_albedo * (1.0 - who.a);
		EMISSION = mix(mirror, who.rgb * glass_tint * (1.0 - f) * mix(0.35, 1.0, t), who.a);
		ALPHA = mix(a, 1.0, who.a);
		if (ws_on()) {
			// Rain on the glass (car_glass_wet.gdshaderinc): the beads and runs show as water on
			// the pane, the wipers' arcs clear (the player's own car runs them).
			vec3 alb = ALBEDO;
			float rough = ROUGHNESS;
			vec3 em = EMISSION;
			bool screen = i >= 0 && pane_hi[i].w > 0.5 && pane_hi[i].w < 1.5;
			vec4 w = glass_wet(lp, n, screen, ms, px_m, TIME, alb, rough, em);
			ALBEDO = alb;
			ROUGHNESS = rough;
			EMISSION = em + sky_tint.rgb * 0.08 * w.w;
			ALPHA = max(ALPHA, 0.45 * w.w);
			float sl = length(w.xyz);
			if (sl > 1e-4) {
				vec3 sv = (VIEW_MATRIX * (MODEL_MATRIX * vec4(w.xyz, 0.0))).xyz;
				NORMAL = normalize(NORMAL + normalize(sv) * min(sl, 1.2) * 0.6);
			}
		}
	}
}
