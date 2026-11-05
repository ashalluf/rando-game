shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// A lit window's light on the yard in front of it (SuburbNight.window_spill(), refcam5 suburb_night).
// One unit quad lying on the ground: UV.y 1 at the wall, 0 at the far end (SuburbNight.SPILL_REACH
// out). Instance COLOR: r the house key (HouseNights.key()), g the pane's 8-bit roll (the alpha the
// pane's vertex colour carries, so it reads back exactly what house_glass.gdshader reads), b the
// near end's share of the far width, a a strength. Whether the room is lit, its lamp tone and the TV
// room's flicker are house_nights.gdshaderinc's own rolls, so a dark window throws nothing.
// Added in DISPLAY numbers on both renderers (house_glow.gdshader's rule, fwd-review-e).

global uniform float lamp_factor;
global uniform float night_factor;
global uniform float city_hour;
#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/house_nights.gdshaderinc"

uniform float spill_gain = 0.32;
uniform float tv_gain = 0.85;

varying flat vec4 inst;

vec3 ss_to_linear(vec3 c) {
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 ss_to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void vertex() {
	inst = COLOR;
}

void fragment() {
	int key = int(inst.r + 0.5);
	float rnd = floor(inst.g + 0.5) / 255.0;
	float share = hn_share(key, city_hour);
	float a = 0.0;
	vec3 tint = vec3(0.0);
	if (rnd < share) {
		bool tv_room = hn_tv(key) && rnd < share * 0.3;
		vec3 tone = hn_tone(hn_tone_index(key));
		tone = mix(tone, hn_tone(int(fract(rnd * 31.7) * 4.0)), 0.25 * fract(rnd * 5.3));
		// What hangs at the glass dims what reaches the yard (house_glass's cover roll).
		float cover = fract(rnd * 11.9);
		float pass = cover < 0.36 ? 0.7 : (cover < 0.56 ? 0.3 : (cover < 0.70 ? 0.45 : (cover < 0.84 ? 0.55 : 1.0)));
		tint = tv_room ? hn_tv_light(key, TIME) * tv_gain : tone;
		// The trapezoid: as wide as the pane at the wall, fanning out to the far end; brightest a
		// little out from the wall, falling off with the distance; soft edges.
		float s = 1.0 - UV.y;
		float half_w = 0.5 * mix(inst.b, 1.0, s);
		float across = 1.0 - smoothstep(half_w * 0.55, half_w, abs(UV.x - 0.5));
		float along = smoothstep(0.0, 0.12, s) * pow(1.0 - s, 1.6);
		a = across * along * pass * inst.a * spill_gain;
	}
	a *= clamp(lamp_factor, 0.0, 1.0) * clamp(night_factor, 0.0, 1.0);
	vec3 disp = ss_to_srgb(tint);
	ALBEDO = disp;
	ALPHA = clamp(a, 0.0, 1.0);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	ALBEDO = ss_to_linear(disp * clamp(a, 0.0, 1.0));
	ALPHA = 1.0;
#endif
}
