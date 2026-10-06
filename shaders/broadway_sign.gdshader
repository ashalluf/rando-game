shader_type spatial;
// Broadway's theatre fronts (BroadwayTheatre): the blade sign, the marquee, the ticket booth, the
// poster cases and the terrazzo entrance, ONE material and one draw a palace. What a face is rides
// in the vertex alpha (kind / 16, BroadwayTheatre.K_*); its paint or light colour in COLOR.rgb as
// written (sRGB: vertex colours arrive raw on both renderers, so they are decoded here). Everything
// is worked in linear (color_space.gdshaderinc) and handed over with cs_out().
//
//   0 enamel   painted sheet steel (the sign's body, the marquee's fascia)
//   1 bulbs    a strip of incandescent bulbs, UV.x metres along, UV.y 0..1 across; three-phase
//              chase (two on, one off, stepping along), COLOR.rgb the strip's paint
//   2 neon     a tube, COLOR.rgb its gas
//   3 letters  lit channel letters studded with bulbs; UV is the letter's own plane in metres,
//              with 100 x its row added to UV.y: the rows light one by one top to bottom, hold,
//              flash three times and go dark (the old blade-sign sequence)
//   4 board    the changeable-letter board, backlit white with its letter rails
//   5 soffit   the marquee's underside, a grid of bulbs in UV metres (all on)
//   6 type     the board's letters (black plastic)
//   7 iron     dark painted metal (brackets, rods, frames)
//   8 brass    polished brass (rails, the booth's trim, door pulls)
//   9 glass    the booth's and the doors' glass, lit behind at night
//  10 poster   a lit poster case: invented one-sheets drawn from the case's UV
//  11 terrazzo the entrance floor: a sunburst from the doors in COLOR and cream, brass strips,
//              chips; UV metres from the entrance's centre line (x along, y out to the street)
// Day: bulbs and neon burn at a fraction (real marquees chase all day), letters read as their
// painted faces. Night (lamp_factor): all of it lit.
#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

uniform float bulb_spacing = 0.30;
uniform float chase_speed = 7.0;
uniform float bulb_day = 0.35;
uniform float bulb_night = 5.0;
uniform float neon_day = 0.6;
uniform float neon_night = 3.0;
uniform float letter_night = 3.2;
uniform float board_night = 1.7;
uniform float soffit_night = 3.6;
uniform float poster_night = 1.3;
// Per palace (BroadwayTheatre sets a material per palace only for this): the sequence's phase.
uniform float seed = 0.0;

varying float v_kind;
varying vec3 v_paint;

void vertex() {
	v_kind = floor(COLOR.a * 16.0 + 0.5);
	v_paint = cs_srgb_to_linear(COLOR.rgb);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A row of bulbs along u (metres), across v in 0..1 of `width` metres: x = how lit this pixel is
// by a bulb (glass, glow), y = the bulb's own on/off.
vec2 bulb_row(float u, float v, float width, float spacing, float phase_speed) {
	float i = floor(u / spacing);
	float f = fract(u / spacing) - 0.5;
	vec2 d = vec2(f * spacing, (v - 0.5) * width);
	float r = length(d);
	float px = max(fwidth(u), 0.001);
	float rad = min(spacing, width) * 0.24;
	float dot_m = 1.0 - smoothstep(rad - px, rad + px, r);
	float halo = exp(-r * r / (rad * rad * 3.5)) * 0.45;
	// Three-phase chase: two of every three bulbs on, the gap stepping along.
	float step_i = floor(TIME * phase_speed + seed * 13.0);
	float on = mod(i + step_i, 3.0) < 0.5 ? 0.0 : 1.0;
	// Under a pixel a bulb is its average: the row glows at two thirds.
	float avg = clamp(px / spacing, 0.0, 1.0);
	float lit = mix(max(dot_m, halo) * on, 0.66 * 0.55, smoothstep(0.25, 0.8, avg));
	return vec2(lit, mix(on, 0.66, smoothstep(0.25, 0.8, avg)));
}

// The old blade-sign sequence for row `row`: 1 lit, 0 dark.
float letter_sequence(float row) {
	float cyc = 9.0;
	float t = mod(TIME + seed * 31.0, cyc);
	float spell = row * 0.32;
	if (t < 4.2) {
		return t > spell ? 1.0 : 0.0;
	}
	if (t < 6.2) {
		return 1.0;
	}
	if (t < 8.4) {
		return mod(floor((t - 6.2) / 0.36), 2.0) < 0.5 ? 0.0 : 1.0;
	}
	return 0.0;
}

void fragment() {
	float k = v_kind;
	vec3 albedo = v_paint;
	vec3 emit = vec3(0.0);
	float rough = 0.45;
	float metal = 0.0;
	float night = clamp(lamp_factor, 0.0, 1.0);
	if (k < 0.5) {
		// Enamel: a little gloss, a faint ripple of the sheet.
		rough = 0.32 + 0.1 * noise2(UV * 3.0);
		metal = 0.15;
	} else if (k < 1.5) {
		vec2 b = bulb_row(UV.x, UV.y, 0.16, bulb_spacing, chase_speed);
		vec3 bulb = vec3(1.0, 0.78, 0.48);
		albedo = mix(v_paint, vec3(0.92, 0.88, 0.80), b.x);
		rough = mix(0.4, 0.08, b.x);
		emit = bulb * b.x * mix(bulb_day, bulb_night, night);
	} else if (k < 2.5) {
		float flick = 0.94 + 0.06 * noise2(vec2(TIME * 9.0, seed * 7.0));
		albedo = mix(v_paint, vec3(1.0), 0.35);
		rough = 0.12;
		emit = v_paint * mix(neon_day, neon_night, night) * flick;
	} else if (k < 3.5) {
		float row = floor(UV.y / 100.0);
		vec2 p = vec2(UV.x, UV.y - row * 100.0);
		float on = letter_sequence(row);
		// Bulbs on a 0.16 m grid inside the letter, the channel glowing between them.
		vec2 g = fract(p / 0.16) - 0.5;
		float r = length(g) * 0.16;
		float px = max(fwidth(p.x), 0.001);
		float bulb = 1.0 - smoothstep(0.035 - px, 0.035 + px, r);
		bulb = mix(bulb, 0.15, smoothstep(0.03, 0.12, px));
		vec3 face = mix(v_paint, vec3(0.95, 0.92, 0.86), 0.55);
		albedo = mix(face, vec3(1.0, 0.95, 0.85), bulb * 0.6);
		rough = 0.35;
		vec3 lit = v_paint * 0.55 + vec3(1.0, 0.86, 0.6) * bulb * 1.4;
		emit = lit * on * mix(0.12, letter_night, night);
	} else if (k < 4.5) {
		float rail = smoothstep(0.012, 0.0, abs(fract(UV.y / 0.42) - 0.5) - 0.47);
		albedo = mix(vec3(0.86, 0.84, 0.78), vec3(0.35), rail);
		rough = 0.3;
		emit = vec3(1.0, 0.95, 0.86) * (1.0 - rail * 0.7) * mix(0.08, board_night, night);
	} else if (k < 5.5) {
		vec2 g = fract(UV / 0.5) - 0.5;
		float r = length(g) * 0.5;
		float px = max(fwidth(UV.x), 0.001);
		float bulb = 1.0 - smoothstep(0.045 - px, 0.045 + px, r);
		float halo = exp(-r * r / 0.012) * 0.5;
		float avg = smoothstep(0.08, 0.35, px);
		float lit = mix(max(bulb, halo), 0.25, avg);
		albedo = mix(v_paint, vec3(0.95, 0.9, 0.8), lit);
		rough = 0.35;
		emit = vec3(1.0, 0.80, 0.52) * lit * mix(0.25, soffit_night, night);
	} else if (k < 6.5) {
		albedo = vec3(0.02);
		rough = 0.25;
	} else if (k < 7.5) {
		rough = 0.55;
		metal = 0.5;
	} else if (k < 8.5) {
		rough = 0.25 + 0.15 * noise2(UV * 6.0);
		metal = 1.0;
	} else if (k < 9.5) {
		// Dark glass: a dielectric (its mirror is the renderer's Fresnel), never a lit slab.
		albedo = vec3(0.012, 0.014, 0.016);
		rough = 0.05;
		metal = 0.0;
		// Lit behind after dark. A shop window's paint carries its shop's light level in red
		// (BroadwayTheatre: 0 closed, else how bright the display is); every other pane (doors,
		// booth, the arched window) keeps the old faint glow. Either way the light comes from
		// the ceiling - bright under the transom, falling to the floor - in pools along the
		// window: one even 0.1 emission was lifted by the night's auto exposure to the
		// floodlit stone's own brightness, and every shop read as a flat warm-grey board.
		float level = v_paint.r > 0.002 ? cs_linear_to_srgb(vec3(v_paint.r)).r : 0.2;
		float fall = mix(0.18, 1.0, smoothstep(0.4, 4.0, UV.y));
		float pools = 0.55 + 0.45 * noise2(vec2(UV.x * 0.9, seed * 5.0));
		float glow = (0.6 + 0.4 * noise2(UV * vec2(0.6, 0.4) + seed * 5.0)) * fall * pools;
		emit = vec3(1.0, 0.74, 0.44) * 0.1 * level * glow * night;
	} else if (k < 10.5) {
		// A one-sheet: a field, a figure block, a title band - all invented shapes.
		float cell = floor(UV.x / 1.3);
		float h = hash21(vec2(cell, seed + 3.0));
		vec2 q = vec2(fract(UV.x / 1.3), fract(UV.y / 1.9));
		vec3 a = 0.5 + 0.5 * cos(6.2831 * (h + vec3(0.0, 0.33, 0.67)));
		vec3 b = 0.5 + 0.5 * cos(6.2831 * (h + 0.4 + vec3(0.0, 0.33, 0.67)));
		vec3 c = mix(a * 0.25, a, smoothstep(0.1, 0.9, q.y));
		float figure = smoothstep(0.03, 0.0, length((q - vec2(0.5, 0.55)) * vec2(1.6, 1.0)) - 0.22);
		c = mix(c, b * 0.8, figure);
		float title = step(0.78, q.y) * step(q.y, 0.9) * step(0.12, q.x) * step(q.x, 0.88);
		c = mix(c, vec3(0.95, 0.92, 0.8), title * step(0.5, noise2(UV * vec2(18.0, 6.0))));
		albedo = c * 0.8;
		rough = 0.15;
		emit = c * mix(0.15, poster_night, night);
	} else {
		// Terrazzo: a sunburst from the doors, brass strips, a border band, chips, a polish.
		vec2 p = UV;
		float ang = atan(p.x, max(p.y + 1.5, 0.01));
		float rays = 14.0;
		float ray = fract(ang / 3.14159 * rays * 0.5 + 0.5);
		float in_ray = step(0.5, ray);
		vec3 cream = vec3(0.80, 0.74, 0.62);
		vec3 base = mix(v_paint, cream, in_ray * 0.85);
		float strip = smoothstep(0.012, 0.0, abs(ray - 0.5) * length(p) * 0.6 - 0.002);
		float ring = smoothstep(0.02, 0.0, abs(length(p + vec2(0.0, 1.5)) - 3.2));
		vec2 cp = p * 22.0;
		float chip = step(0.82, noise2(cp)) * 0.35 + step(0.9, noise2(cp * 1.7 + 4.0)) * 0.3;
		vec3 chips = mix(base, vec3(0.95, 0.92, 0.85), chip);
		chips = mix(chips, chips * 0.6, step(0.88, noise2(cp * 1.3 + 9.0)) * 0.6);
		albedo = mix(chips, vec3(0.75, 0.56, 0.24), max(strip, ring));
		metal = max(strip, ring) * 0.9;
		rough = 0.18 + 0.12 * noise2(p * 2.0);
	}
	ALBEDO = cs_out(albedo);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
