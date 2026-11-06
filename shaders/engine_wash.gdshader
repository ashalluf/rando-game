shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/color_space.gdshaderinc"

// The light a fire engine's or an ambulance's warning lights throw at night (EmergencyWash,
// wave 8 rc5-fire-station-night): a pool on the road under the unit and a wash on the facade either
// side of it. The flashing is worked out exactly as shaders/emergency_lights.gdshader flashes the
// lenses (TIME, the unit's `rate` and `phase`, the left / right banks half a cycle apart and the
// front / back a quarter, each lens strobing twice in its half), so the light on the street is the
// lens that is lit. Each bank is a point source `src_h` up at a corner of the body; the pool and
// the wall add up the four as a lamp lights a surface (h / r^3), cut to zero inside the quad's
// edge (an additive tail draws the quad on Forward+). Linear colours (plain uniforms, Vector3 from
// script) out through cs_out(); red held at a tenth green (AgX turns a bright red-heavy colour pink).
//
// kind  0 pool: a quad 1 x 1 in the unit's XZ (x right, z back), UV = (x, z) + 0.5, scaled by
//         its node to `quad_m` metres; the sources at (+-src_x, src_h, +-src_z) in metres.
//       1 wall: a quad 1 x 1 in XY facing the unit, `quad_m` x `wall_h` metres, the unit's centre
//         `wall_d` metres in front of it level with the quad's middle; `wall_side` +1 the unit's
//         +x side, -1 its -x side.

global uniform float lamp_factor;
global uniform float road_wetness;

uniform float kind = 0.0;
uniform float rate = 1.35;
uniform float phase = 0.0;
uniform float lights_on = 1.0;
uniform vec3 red = vec3(4.0, 0.34, 0.20);
uniform vec3 white = vec3(3.0, 2.9, 2.7);
uniform float red_duty = 0.11;
uniform float white_duty = 0.07;
uniform float src_x = 1.2;
uniform float src_z = 4.2;
uniform float src_h = 3.0;
uniform float quad_m = 30.0;
uniform float wall_h = 12.0;
uniform float wall_d = 8.0;
uniform float wall_side = 1.0;
uniform float pool_gain = 0.55;
uniform float wall_gain = 0.42;
// The unit's own OmniLight lights the road on Forward+ too: the pool gives way to it by this much.
uniform float real_light = 0.0;

float strobe(float t, float d) {
	float a = step(0.0, t) * step(t, d);
	float b = step(d * 1.6, t) * step(t, d * 2.6);
	return max(a, b);
}

// What bank (side 0 = -x, 1 = +x; end 0 = back, 1 = front) is lit now, as a colour.
vec3 bank(float side, float end) {
	float t = fract(TIME * rate + phase + side * 0.5 + end * 0.25);
	return red * strobe(t, red_duty) + white * strobe(t, white_duty) * 0.35 * end;
}

void fragment() {
	float night = clamp(lamp_factor, 0.0, 1.0) * lights_on;
	vec3 col = vec3(0.0);
	vec2 q = UV - 0.5;
	if (kind < 0.5) {
		vec2 p = q * quad_m;
		for (int s = 0; s < 2; s++) {
			for (int e = 0; e < 2; e++) {
				vec2 at = vec2((float(s) * 2.0 - 1.0) * src_x, (float(e) * -2.0 + 1.0) * src_z);
				vec2 d = p - at;
				float lit = pow(1.0 + dot(d, d) / (src_h * src_h), -1.5);
				col += bank(float(s), float(e)) * lit;
			}
		}
		float edge = 1.0 - smoothstep(0.30, 0.5, max(abs(q.x), abs(q.y)));
		col *= pool_gain * edge * (1.0 + 0.5 * road_wetness) * (1.0 - 0.5 * real_light);
	} else {
		float x = q.x * quad_m;
		float y = UV.y * wall_h - src_h;
		float near_side = wall_side > 0.0 ? 1.0 : 0.0;
		for (int s = 0; s < 2; s++) {
			for (int e = 0; e < 2; e++) {
				float dz = (float(e) * -2.0 + 1.0) * src_z;
				// The far bank is the body's width further off and half hidden by the body.
				float dd = wall_d + (float(s) == near_side ? -src_x : src_x);
				float shade = float(s) == near_side ? 1.0 : 0.35;
				float r2 = (x - dz) * (x - dz) + y * y;
				float lit = pow(1.0 + r2 / (dd * dd), -1.5) * shade;
				col += bank(float(s), float(e)) * lit;
			}
		}
		// Falls off with the wall's distance from the lamps (a lamp lights a far wall less) and
		// reaches zero at the quad's sides and top; the foot of the wall meets the pavement.
		float fall = 8.0 / (8.0 + wall_d * wall_d * 0.12);
		float edge = (1.0 - smoothstep(0.32, 0.5, abs(q.x))) * (1.0 - smoothstep(0.75, 1.0, UV.y)) * smoothstep(0.0, 0.04, UV.y);
		col *= wall_gain * fall * edge * (1.0 - 0.4 * real_light);
	}
	ALBEDO = cs_out(col * night);
}
