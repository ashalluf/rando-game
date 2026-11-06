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
// The rain seen from inside (DriverRain, driver_rain refcam; 0 = the old dry pane): the beads and
// runs of car_glass_wet.gdshaderinc, each bead a little lens refracting (and flipping) the street
// behind it out of the screen texture, the film between them blurring it, the wipers' arcs clear.
uniform float rain_inside = 0.0;
uniform float bead_refract = 0.008;
// Seen from the seat the beads are drawn this much bigger (the glass is an arm's length from the
// eye: at 720 lines a real 3 mm bead is two pixels and the rain on the screen read as nothing).
uniform float bead_scale = 1.8;
uniform float film_blur = 2.2;
uniform sampler2D open_screen : hint_screen_texture, filter_linear_mipmap;

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
		if (rain_inside > 0.5 && ws_on() && who.a < 0.5) {
			float ms = length(MODEL_MATRIX[0].xyz);
			float px = max(length(fwidth(lp)) * ms, 1e-5);
			bool screen = i >= 0 && pane_hi[i].w > 0.5 && pane_hi[i].w < 1.5;
			// The water on the pane: glass_wet's beads, runs and wiper arcs, read for cover and slope.
			vec3 wa = vec3(0.0);
			float wr = 0.0;
			vec3 we = vec3(1.0);
			vec3 slope = glass_wet(lp, n, screen, ms / bead_scale, px / bead_scale, TIME, wa, wr, we);
			float cover = clamp((1.0 - we.x) / 0.45, 0.0, 1.0);
			float wet = ws_wet(0.25);
			vec3 sv = (VIEW_MATRIX * (MODEL_MATRIX * vec4(slope, 0.0))).xyz;
			// A bead is a lens: the street behind it seen refracted and upside down, a little out of
			// focus (the eye is focused down the road); the film between the beads softens it all.
			vec2 off = sv.xy * bead_refract * vec2(1.0, -1.0) * cover;
			float lod = film_blur * wet * (0.35 + 0.65 * cover);
			vec3 behind = textureLod(open_screen, SCREEN_UV + off, lod).rgb;
			// A bead's rim bends the light away from the eye: a dark ring round a bright core.
			float rim = smoothstep(0.7, 1.4, length(slope)) * cover;
			behind *= 1.0 - 0.55 * rim;
			float own = clamp(cover * 0.9 + wet * 0.25, 0.0, 0.95) * (1.0 - smoothstep(0.6, 1.0, f));
			// The bright lights behind (signals, lamps, shop fronts) bloom in the water film.
			vec3 hot = max(textureLod(open_screen, SCREEN_UV, 4.0).rgb - vec3(0.5), vec3(0.0));
			float hot_l = dot(hot, vec3(0.333));
			behind += hot * 1.4 * wet;
			own = max(own, clamp(hot_l * 2.0 * wet, 0.0, 0.55));
			// What the water shows is EMITTED (the screen colour as it is), over the dry pane.
			EMISSION = mix(EMISSION, behind * mix(0.92, 0.8, cover), own);
			ALBEDO *= 1.0 - own;
			ALPHA = mix(ALPHA, 1.0, own);
			// The beads' rims catch a little of the sky as a glint.
			EMISSION += sky_tint.rgb * wa * 0.5;
			ROUGHNESS = mix(glass_roughness, 0.18, cover * 0.4);
			if (length(sv) > 1e-4) {
				NORMAL = normalize(NORMAL + normalize(sv) * min(length(slope), 1.2) * 0.6);
			}
		}
	}
}
