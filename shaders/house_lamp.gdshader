shader_type spatial;

// A house's night fixtures (HouseNights): the frosted lenses of a porch lantern, a pair of
// garage carriage lamps and the path lights down the front walk, and the backlit house number
// by the door. One surface per chunk ("h_lamp", HouseKit.commit()). COLOR.rgb is the lamp's
// tint (LINEAR), COLOR.a the kind x 0.25 plus 0.125 when the lamp is on: 0 a lens, 1 the number
// plaque, 2 a path light, 3 a housing (COLOR.rgb its paint, never lit). UV runs 0..1 across a face; the plaque carries the house's number in
// UV.x's integer part (three digits, HouseNights.house_number()).

global uniform float lamp_factor;
#include "res://shaders/color_space.gdshaderinc"

uniform float lens_energy = 4.5;
uniform float plaque_energy = 1.6;

// A seven-segment digit's ink at p (0..1 in its cell).
float seg7(int d, vec2 p) {
	// Segments a (top) b (top right) c (bottom right) d (bottom) e (bottom left) f (top left) g.
	int m = 0;
	if (d == 0) m = 0x3f; else if (d == 1) m = 0x06; else if (d == 2) m = 0x5b; else if (d == 3) m = 0x4f;
	else if (d == 4) m = 0x66; else if (d == 5) m = 0x6d; else if (d == 6) m = 0x7d; else if (d == 7) m = 0x07;
	else if (d == 8) m = 0x7f; else m = 0x6f;
	float t = 0.16;
	float ink = 0.0;
	float hx = step(0.12, p.x) * step(p.x, 0.88);
	float vl = step(abs(p.x - 0.12), t * 0.5);
	float vr = step(abs(p.x - 0.88), t * 0.5);
	float top = step(p.y, 0.5);
	float bot = 1.0 - top;
	if ((m & 1) != 0) ink = max(ink, hx * step(abs(p.y - 0.08), t * 0.5));
	if ((m & 2) != 0) ink = max(ink, vr * top);
	if ((m & 4) != 0) ink = max(ink, vr * bot);
	if ((m & 8) != 0) ink = max(ink, hx * step(abs(p.y - 0.92), t * 0.5));
	if ((m & 16) != 0) ink = max(ink, vl * bot);
	if ((m & 32) != 0) ink = max(ink, vl * top);
	if ((m & 64) != 0) ink = max(ink, hx * step(abs(p.y - 0.5), t * 0.5));
	return ink;
}

void fragment() {
	float a4 = COLOR.a * 4.0 + 0.01;
	int kind = int(floor(a4));
	float on = step(0.4, fract(a4)) * clamp(lamp_factor, 0.0, 1.0);
	vec3 tint = COLOR.rgb;
	vec3 albedo;
	vec3 em = vec3(0.0);
	float rough = 0.35;
	if (kind >= 3) {
		albedo = tint;
		rough = 0.45;
	} else if (kind == 1) {
		// The house number: a pale backlit panel with dark digits.
		vec2 uv = vec2(fract(UV.x), UV.y);
		int num = int(floor(UV.x));
		vec2 cell = vec2(uv.x * 3.0, uv.y);
		int k = int(min(floor(cell.x), 2.0));
		int digit = k == 0 ? (num / 100) % 10 : (k == 1 ? (num / 10) % 10 : num % 10);
		vec2 p = vec2(fract(cell.x), (uv.y - 0.18) / 0.64);
		float ink = (p.y > 0.0 && p.y < 1.0) ? seg7(digit, vec2((p.x - 0.18) / 0.64, p.y)) * step(0.18, p.x) * step(p.x, 0.82) : 0.0;
		albedo = mix(vec3(0.70, 0.68, 0.62), vec3(0.03), ink);
		em = tint * plaque_energy * on * (1.0 - ink);
		rough = 0.5;
	} else {
		// A frosted lens: pale by day, the lamp after dark (brighter in the middle of the face).
		float c = 1.0 - smoothstep(0.15, 0.55, length(UV - vec2(0.5)));
		albedo = vec3(0.78, 0.74, 0.62);
		em = tint * lens_energy * on * (0.55 + 0.45 * c) * (kind == 2 ? 0.8 : 1.0);
		rough = 0.2;
	}
	ALBEDO = cs_out(albedo);
	EMISSION = cs_out(em);
	ROUGHNESS = rough;
	SPECULAR = 0.4;
}
