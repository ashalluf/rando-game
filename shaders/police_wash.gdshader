shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// What a police light bar does to the night round it (PoliceNightLook), one shader for every
// piece of a cruiser's glow, each piece's kind in COLOR.a (x 4: 0 glare, 1 the pool on the road,
// 2 a wash on a wall, 3 the lens streak):
//   glare   a camera-facing flare on each lit bank, never under `min_px` pixels, so a strobe a
//           block away still blooms (the bar's lenses are 20 cm boxes);
//   streak  a thin horizontal line through the flare, the lens's anamorphic flare;
//   pool    red and blue thrown on the road, pushed toward the lit side, plus on a wet road the
//           bar mirrored in it: a streak from the bar's mirror point toward the camera, the
//           puddle reflection every night chase has (the road's own SSR only mirrors what is on
//           screen, and the web has none);
//   wall    the same light on the facade beside the car (PoliceNightLook rays for it).
// Which bank is lit is PoliceCar.flash_side() of `clock` (PoliceNightLook.clock, the one clock
// the lenses, the real lights and this all read): COLOR.r is the bank (0.5 red, 1 blue) on the
// glare and streak, and the side of the car a wall is on (0.5 the red side, 1 the blue).
// Linear colours (plain uniforms) written out through cs_out(); red held at a tenth green, or AgX
// turns it salmon (CLAUDE.md, the car fire).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;
global uniform float rain_intensity;

uniform float clock = 0.0;
uniform float rate = 1.6;
uniform float phase = 0.0;
uniform float lights_on = 1.0;
// 1 while a real OmniLight3D is lighting this car's street (Forward+): the pool and walls step
// back, the light does that work.
uniform float real_light = 0.0;
uniform vec3 red = vec3(4.0, 0.36, 0.22);
uniform vec3 blue = vec3(0.30, 0.75, 5.2);
uniform float glare_size = 0.55;
uniform float min_px = 5.0;
uniform vec2 viewport_px = vec2(1280.0, 720.0);
uniform float glare_gain = 1.0;
uniform float glare_day = 0.25;
uniform float pool_gain = 0.42;
uniform float wall_gain = 0.30;
uniform float mirror_gain = 0.9;
// The bar's height over the pool's plane (m), for the mirrored streak.
uniform float bar_height = 1.6;
uniform float pool_shift = 0.22;

varying float v_kind;
varying float v_bank;
varying vec3 v_cam;

float strobe(float t, float start) {
	float a = step(start, t) * step(t, start + 0.09);
	float b = step(start + 0.15, t) * step(t, start + 0.24);
	return max(a, b);
}

// 1 red, -1 blue, 0 dark: PoliceCar.flash_side().
float side_lit(float t) {
	float f = fract(t * rate + phase);
	return strobe(f, 0.0) - strobe(f, 0.5);
}

void vertex() {
	v_kind = floor(COLOR.a * 4.0 + 0.5);
	v_bank = COLOR.r;
	v_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	if (v_kind < 0.5 || v_kind > 2.5) {
		// Billboards: VERTEX is the lens centre, UV the corner (0..1).
		vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float dist = max(-vp.z, 0.05);
		float px = 2.0 * dist / (abs(PROJECTION_MATRIX[1][1]) * max(viewport_px.y, 1.0));
		float s = max(glare_size, px * min_px);
		vec2 c = UV * 2.0 - 1.0;
		vec2 span = v_kind > 2.5 ? vec2(s * 7.0, s * 0.16) : vec2(s, s);
		vp.xy += c * span;
		// Pulled toward the camera so the roof and the bar's own housing never cut it.
		vp.z += min(s * 1.5, dist * 0.5);
		POSITION = PROJECTION_MATRIX * vp;
	}
}

void fragment() {
	float side = side_lit(clock) * lights_on;
	float night = clamp(lamp_factor, 0.0, 1.0);
	vec3 col = vec3(0.0);
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	if (v_kind < 0.5 || v_kind > 2.5) {
		float bank = v_bank > 0.75 ? -1.0 : 1.0;
		float lit = max(side * bank, 0.0);
		vec3 c = bank > 0.0 ? red : blue;
		float gain = mix(glare_day, 1.0, night) * glare_gain * lit;
		if (v_kind < 0.5) {
			// A hot white core in a coloured halo that reaches zero at the quad's edge (an additive
			// tail draws the quad on Forward+; CLAUDE.md, fwd-review-d).
			float core = exp(-r * r * 40.0);
			float halo = exp(-r * r * 5.0) - exp(-5.0);
			col = (vec3(1.6) + c * 0.6) * core + c * max(halo, 0.0) * 0.30;
		} else {
			float across = exp(-q.y * q.y * 6.0) - exp(-6.0);
			float along = pow(max(1.0 - abs(q.x), 0.0), 2.2);
			col = c * max(across, 0.0) * along * 0.16;
		}
		col *= gain;
	} else {
		float lit = abs(side);
		vec3 c = side > 0.0 ? red : blue;
		float gain = night * lit * (1.0 - 0.6 * real_light);
		if (v_kind < 1.5) {
			// The pool: the quad is 1 x 1 in the car's XZ, the bar over its centre; the red bank is
			// on the car's -x, so the lit side's light sits that way.
			vec2 p = UV - 0.5;
			vec2 lean = vec2(-side * pool_shift, 0.0);
			float d = length((p - lean) * vec2(1.0, 1.35)) * 2.0;
			float pool = pow(max(1.0 - d, 0.0), 2.2);
			// Grows a little in the rain: the light carries in the wet air and on the wet road.
			col = c * pool * pool_gain * (1.0 + 0.6 * road_wetness);
			// The bar in the wet road: its mirror image at (0, -h, 0) seen from the camera lands on
			// the road at m; a reflection on rough water stretches from m toward the viewer.
			vec3 cam = v_cam;
			if (road_wetness > 0.02 && cam.y > 0.1) {
				vec2 pw = vec2(p.x, p.y) * vec2(1.0, 1.0);
				// UV -> pool local metres: the instance's scale is in MODEL_MATRIX; the streak is
				// worked in UV units of the quad, the camera brought into them by the same scale.
				vec2 cp = cam.xz;
				float t = cam.y / (cam.y + bar_height);
				vec2 m = cp * (1.0 - t);
				vec2 toward = normalize(cp - m + vec2(1e-4));
				vec2 rel = pw - m;
				float along = dot(rel, toward);
				float across = dot(rel, vec2(-toward.y, toward.x));
				float len = 0.06 + 0.32 * road_wetness;
				float w = 0.010 + 0.012 * (1.0 - road_wetness);
				float streak = exp(-across * across / (w * w)) * exp(-max(along, 0.0) / len) * smoothstep(-0.03, 0.0, along);
				float glint = exp(-dot(rel, rel) / (w * w * 2.0));
				col += c * (streak * 0.55 + glint * 0.9) * mirror_gain * road_wetness;
			}
		} else {
			// A wall: brightest at the middle of the quad (level with the car), fading up and out;
			// the side of the car it faces gets its own colour harder.
			float wall_side = v_bank > 0.75 ? -1.0 : 1.0;
			float facing = side * wall_side > 0.0 ? 1.0 : 0.45;
			float fall = pow(max(1.0 - length(q * vec2(1.0, 1.25)), 0.0), 2.0);
			col = c * fall * facing * wall_gain * (1.0 + 0.4 * rain_intensity);
		}
	}
	ALBEDO = cs_out(col);
}
