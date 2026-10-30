shader_type spatial;
// Broadway's street clock and the palace clock tower (BroadwayStreet.clock_material()): a cream
// enamel dial with a minute track, twelve hour batons (heavier at the quarters), spade hands set
// to the game's hour (`hour`, 0..24, BroadwayStreet.ClockSync sets it once a second from
// DayNight), a brass boss; backlit after dark like the old opal-glass dials. UV 0..1 across the
// dial, v down.
#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
uniform float hour = 9.0;

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - w;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	float r = length(p);
	float px = max(fwidth(p.x), 0.002);
	vec3 enamel = vec3(0.86, 0.83, 0.74);
	vec3 ink = vec3(0.03, 0.03, 0.035);
	float ink_m = 0.0;
	// Minute track and the batons.
	float ang = atan(p.x, p.y);
	float m = fract(ang / 6.28318 * 60.0 + 0.5) - 0.5;
	float minute = step(0.80, r) * step(r, 0.88) * (1.0 - smoothstep(0.06, 0.06 + px * 8.0, abs(m)));
	float h = fract(ang / 6.28318 * 12.0 + 0.5) - 0.5;
	float quarter = step(0.5, 1.0 - abs(fract(ang / 6.28318 * 4.0 + 0.5) - 0.5) * 4.0 * 3.0);
	float baton = step(0.62, r) * step(r, 0.86) * (1.0 - smoothstep(0.035 + 0.03 * quarter, 0.035 + 0.03 * quarter + px * 4.0, abs(h)));
	float rings = (1.0 - smoothstep(0.0, px * 1.5, abs(r - 0.90) - 0.008)) + (1.0 - smoothstep(0.0, px * 1.5, abs(r - 0.78) - 0.004));
	ink_m = max(ink_m, max(minute, max(baton, rings)));
	// Hands.
	float hh = mod(hour, 12.0);
	float a_h = hh / 12.0 * 6.28318;
	float a_m = fract(hour) * 6.28318;
	vec2 dh = vec2(sin(a_h), cos(a_h));
	vec2 dm = vec2(sin(a_m), cos(a_m));
	float hand_h = seg(p, -dh * 0.12, dh * 0.50, 0.035);
	float hand_m = seg(p, -dm * 0.15, dm * 0.74, 0.022);
	float spade = length(p - dh * 0.46) - 0.07;
	float hands = 1.0 - smoothstep(0.0, px * 1.5, min(min(hand_h, hand_m), spade));
	ink_m = max(ink_m, hands);
	float boss = 1.0 - smoothstep(0.0, px * 1.5, r - 0.06);
	vec3 col = mix(enamel, ink, clamp(ink_m, 0.0, 1.0));
	col = mix(col, vec3(0.78, 0.60, 0.30), boss);
	// Age: a faint craze and yellowing toward the rim.
	col *= 1.0 - 0.08 * smoothstep(0.5, 0.95, r);
	ALBEDO = cs_out(col);
	ROUGHNESS = mix(0.18, 0.35, ink_m);
	METALLIC = boss * 0.9;
	EMISSION = cs_out(col * vec3(1.0, 0.92, 0.75) * (1.0 - ink_m) * (1.0 - boss) * lamp_factor * 1.6);
}
