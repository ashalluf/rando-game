shader_type spatial;
// A car brand's sign face (CarDealers): the pylon's lightbox, the portal's badge, the showroom's
// brand wall. A geometric mark worked out per pixel from the brand's index - six invented
// marks, none of them a real maker's - on a panel, lit from inside after dark.
//
// UV 0..1 over the face (u across, v up). `mark` picks the mark, `panel` / `ink` are sRGB as
// written (plain uniforms set as Vector3, so neither renderer decodes them), `lit` how much the
// face glows at full night, `day_glow` by day.
#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

uniform int mark = 0;
uniform vec3 panel = vec3(0.95, 0.95, 0.93);
uniform vec3 ink = vec3(0.7, 0.05, 0.05);
uniform float lit = 2.2;
uniform float day_glow = 0.12;
// Where the mark sits on the face: centre (uv) and size (fraction of the face's height).
uniform vec2 centre = vec2(0.5, 0.5);
uniform float size = 0.8;
uniform float aspect = 1.0;

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sd_poly(vec2 p, float r, float n, float rot) {
	float a = atan(p.x, p.y) + rot;
	float s = 6.2831853 / n;
	return cos(floor(0.5 + a / s) * s - a) * length(p) - r;
}

// Signed distance to the mark (negative inside), p in -1..1.
float mark_sd(vec2 p) {
	if (mark == 0) {
		// A hexagon ring with a vertical slot through its middle.
		float hex = abs(sd_poly(p, 0.78, 6.0, 0.0)) - 0.13;
		float slot = sd_box(p, vec2(0.08, 0.5));
		return min(hex, slot);
	} else if (mark == 1) {
		// Three bars stepping shorter, left aligned, slanted forward.
		vec2 q = vec2(p.x - p.y * 0.25, p.y);
		float b1 = sd_box(q - vec2(-0.05, 0.48), vec2(0.8, 0.12));
		float b2 = sd_box(q - vec2(-0.2, 0.0), vec2(0.65, 0.12));
		float b3 = sd_box(q - vec2(-0.35, -0.48), vec2(0.5, 0.12));
		return min(b1, min(b2, b3));
	} else if (mark == 2) {
		// A ring with its lower-left half filled, split on the diagonal.
		float ring = abs(length(p) - 0.78) - 0.11;
		float half_disc = max(length(p) - 0.62, (p.x + p.y) * 0.7071 + 0.05);
		return min(ring, half_disc);
	} else if (mark == 3) {
		// A square ring set on its point, with a dot at the centre.
		vec2 q = vec2(p.x + p.y, p.y - p.x) * 0.7071;
		float ring = abs(sd_box(q, vec2(0.62))) - 0.1;
		return min(ring, length(p) - 0.18);
	} else if (mark == 4) {
		// A rising half sun over two lines.
		float sun = max(length(p - vec2(0.0, -0.12)) - 0.62, -(p.y + 0.12));
		float l1 = sd_box(p - vec2(0.0, -0.32), vec2(0.85, 0.07));
		float l2 = sd_box(p - vec2(0.0, -0.58), vec2(0.6, 0.07));
		return min(max(sun, -sd_box(p - vec2(0.0, -0.32), vec2(2.0, 0.14))), min(l1, l2));
	}
	// A pentagon ring with a short bar under it.
	float pent = abs(sd_poly(p - vec2(0.0, 0.12), 0.62, 5.0, 0.0)) - 0.12;
	float bar = sd_box(p - vec2(0.0, -0.78), vec2(0.5, 0.08));
	return min(pent, bar);
}

void fragment() {
	vec2 uv = (UV - centre) / size * vec2(aspect, 1.0) * 2.0;
	uv.y = -uv.y;
	float d = mark_sd(uv);
	float aa = max(fwidth(d), 0.002);
	float m = 1.0 - smoothstep(-aa, aa, d);
	vec3 p = cs_srgb_to_linear(panel);
	vec3 k = cs_srgb_to_linear(ink);
	vec3 col = mix(p, k, m);
	// The lightbox's diffuser is a touch brighter in its middle.
	float hot = 1.0 - 0.25 * length(UV - 0.5);
	float glow = mix(day_glow, lit, clamp(lamp_factor, 0.0, 1.0)) * hot;
	ALBEDO = cs_out(col);
	ROUGHNESS = 0.25;
	SPECULAR = 0.5;
	EMISSION = cs_out(col * glow);
}
