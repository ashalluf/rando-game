shader_type spatial;
// The underground station (MetroBuild): one material for every opaque surface of it and of its
// street kiosks. What a face is rides in COLOR.a (kind / 32, MetroBuild.K_*), its paint in
// COLOR.rgb (sRGB, decoded here: vertex colours arrive raw on both renderers). Patterns are laid
// out in the STATION's frame (u along the line, h up from the street, v across), worked out from
// the model-space vertex (a chunk's local space is true world), so a wall's tiles and a floor's
// terrazzo never depend on how a box was cut.
//
// Light: underground there is no sun and the sky is 13 m up, so the fixtures' light is worked out
// here and EMITTED (albedo x the fixture field: the ceiling strips over the concourse and the
// platform edges, the wall lamps down the tunnel, a bounce), and the albedo the renderer lights
// is kept at `ambient_keep` below the street - the sky ambient would otherwise light a tunnel
// like a shaded pavement. Real lights (MetroBuild's omnis, the reflection probe's ambient) add to
// it on desktop. Works in linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

uniform vec2 st_origin = vec2(0.0);
uniform vec2 st_dir = vec2(0.0, 1.0);
uniform float st_base = 0.0;
uniform float plat_h = -12.08;
uniform float rail_h = -13.0;
uniform float conc_floor = -6.6;
uniform float conc_ceil = -2.5;
uniform float plat_ceil = -7.2;
uniform float box_u = 38.0;
uniform float conc_u = 34.0;
uniform float light_energy = 1.0;
uniform float ambient_keep = 0.3;
// Linear colours of the light (4000 K LED) and of the bounce.
uniform vec3 light_color = vec3(1.0, 0.93, 0.84);
uniform vec3 bounce_color = vec3(0.80, 0.76, 0.70);

varying vec3 sp;
varying vec3 sn;

const int K_TILE = 1;
const int K_TERRAZZO = 2;
const int K_CONCRETE = 3;
const int K_STEEL = 4;
const int K_LAMP = 5;
const int K_RUBBER = 6;
const int K_ENAMEL = 7;
const int K_TEXT = 8;
const int K_PAINT = 9;
const int K_ESC = 10;
const int K_TRACK = 11;
const int K_RAIL = 12;
const int K_SCREEN = 13;
const int K_TACTILE = 14;
const int K_DARK = 15;
const int K_MAP = 16;
const int K_CEIL = 17;

void vertex() {
	vec2 rel = VERTEX.xz - st_origin;
	vec2 r = vec2(-st_dir.y, st_dir.x);
	sp = vec3(dot(rel, st_dir), VERTEX.y - st_base, dot(rel, r));
	sn = vec3(dot(NORMAL.xz, st_dir), NORMAL.y, dot(NORMAL.xz, r));
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

// A line light along u (from u0 to u1) at (h, v): Lambert from its nearest point, a soft falloff.
float strip(vec3 p, vec3 n, float h, float v, float u0, float u1, float k) {
	vec3 q = vec3(clamp(p.x, u0, u1), h, v);
	vec3 d = q - p;
	float dd = dot(d, d);
	float lam = max(dot(n, d * inversesqrt(max(dd, 1e-4))), 0.0);
	return (lam * 0.85 + 0.15) / (1.0 + dd * k);
}

// The fixtures' light at a station point (u, h, v) with normal n, relative units.
float fixtures(vec3 p, vec3 n) {
	float e = 0.0;
	if (p.y > conc_floor - 0.4) {
		// The concourse: three strips in the ceiling, and the stair shafts lit from their bulkheads.
		float cu = conc_u - 0.5;
		e += strip(p, n, conc_ceil - 0.06, -4.4, -cu, cu, 0.32);
		e += strip(p, n, conc_ceil - 0.06, 4.4, -cu, cu, 0.32);
		e += 0.6 * strip(p, n, conc_ceil - 0.06, 0.0, -cu, cu, 0.4);
		e *= 1.0 - smoothstep(conc_u, conc_u + 2.0, abs(p.x));
		if (p.y > conc_ceil - 0.2) {
			// Up the shafts: a strip down each side wall, fading to daylight at the street.
			e += 0.7 * strip(p, n, p.y + 0.4, 0.0, 20.9, 31.2, 0.25) * step(20.0, abs(p.x));
			e *= 1.0 - smoothstep(-1.5, 0.3, p.y);
		}
	} else {
		// The platform: a strip over each edge, a wash on the track walls, then the tunnel's wall
		// lamps every 15 m fading into the dark.
		float pu = box_u - 6.0;
		e += strip(p, n, plat_ceil - 0.1, -2.7, -pu, pu, 0.22);
		e += strip(p, n, plat_ceil - 0.1, 2.7, -pu, pu, 0.22);
		e += 0.35 * strip(p, n, plat_ceil - 0.2, -6.4, -pu, pu, 0.5);
		e += 0.35 * strip(p, n, plat_ceil - 0.2, 6.4, -pu, pu, 0.5);
		float inside = 1.0 - smoothstep(box_u - 4.0, box_u + 10.0, abs(p.x));
		e *= mix(0.06, 1.0, inside);
		float lu = (fract(p.x / 15.0 + 0.5) - 0.5) * 15.0;
		float side = sign(p.z + 0.0001) * 6.7;
		vec3 lp = vec3(p.x - lu, rail_h + 3.2, side);
		vec3 d = lp - p;
		float dd = dot(d, d);
		float tl = (max(dot(n, d * inversesqrt(max(dd, 1e-4))), 0.0) * 0.8 + 0.2) / (1.0 + dd * 0.35);
		e += 0.5 * tl * smoothstep(box_u - 2.0, box_u + 6.0, abs(p.x)) * (1.0 - smoothstep(70.0, 108.0, abs(p.x)));
	}
	return e;
}

void fragment() {
	int kind = int(round(COLOR.a * 32.0));
	vec3 c = cs_srgb_to_linear(COLOR.rgb);
	vec3 n = normalize(sn);
	float rough = 0.6;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	// Wall coordinates: along the wall (u or v, whichever it runs along) and height.
	float along = abs(n.z) > abs(n.x) ? sp.x : sp.z;
	vec2 wc = vec2(along, sp.y);
	vec2 fc = sp.xz;
	float px = length(fwidth(sp));
	if (kind == K_TILE) {
		// Glazed tile, 30 x 15 cm in running bond: grout lines, each tile its own glaze.
		vec2 t = wc / vec2(0.30, 0.15);
		t.x += 0.5 * mod(floor(t.y), 2.0);
		vec2 f = fract(t);
		vec2 id = floor(t);
		float g = min(min(f.x, 1.0 - f.x) * 0.30, min(f.y, 1.0 - f.y) * 0.15);
		float grout = 1.0 - smoothstep(0.002, 0.004 + px * 0.5, g);
		float glaze = 0.94 + 0.08 * h21(id);
		c *= mix(glaze, 0.55, grout);
		rough = mix(0.08 + 0.06 * h21(id + 7.0), 0.85, grout);
		spec = 0.6;
		// Grime low on the walls.
		float low = 1.0 - smoothstep(0.0, 0.9, sp.y - (sp.y > conc_floor - 0.4 ? conc_floor : plat_h));
		c *= 1.0 - 0.18 * low * vnoise(wc * 3.0);
	} else if (kind == K_TERRAZZO) {
		// Polished terrazzo: chips in a cement ground, divider strips on a 1.5 m grid.
		vec2 cell = floor(fc / 0.018);
		float chip = h21(cell);
		vec3 chipc = chip > 0.82 ? vec3(0.62, 0.30, 0.22) : (chip > 0.6 ? vec3(0.18, 0.18, 0.19) : vec3(0.85, 0.83, 0.79));
		float chip_on = step(0.45, h21(cell + 3.1));
		float fade = smoothstep(0.004, 0.02, px);
		c = mix(c * mix(vec3(1.0), chipc * 1.1, chip_on * 0.55), c * 0.97, fade);
		vec2 gd = abs(fract(fc / 1.5 + 0.5) - 0.5) * 1.5;
		float strip_l = 1.0 - smoothstep(0.004, 0.007 + px, min(gd.x, gd.y));
		c = mix(c, vec3(0.45, 0.42, 0.38), strip_l * (1.0 - fade * 0.7));
		c *= 0.92 + 0.12 * vnoise(fc * 0.6);
		rough = 0.18 + 0.12 * vnoise(fc * 2.3) + strip_l * 0.2;
		metal = strip_l * 0.6;
	} else if (kind == K_CONCRETE) {
		c *= 0.86 + 0.2 * vnoise(wc * 1.7 + fc * 0.9);
		rough = 0.9;
	} else if (kind == K_STEEL) {
		float b = vnoise(vec2(along * 40.0, sp.y * 2.0));
		c *= 0.9 + 0.15 * b;
		metal = 0.9;
		rough = 0.28 + 0.1 * b;
	} else if (kind == K_LAMP) {
		emit = c * 5.0;
		rough = 0.3;
	} else if (kind == K_RUBBER) {
		rough = 0.55;
		spec = 0.35;
	} else if (kind == K_ENAMEL) {
		rough = 0.18;
		spec = 0.55;
	} else if (kind == K_TEXT) {
		emit = c * 2.2;
		rough = 0.3;
	} else if (kind == K_PAINT) {
		rough = 0.45;
	} else if (kind == K_ESC) {
		// Escalator steps: aluminium cleats running down the incline, creeping as the stair runs.
		float cleat = abs(fract(UV.y * 1.0 / 0.009) - 0.5);
		float run = fract(sp.x * 2.5 + TIME * 0.5 * sign(UV2.x + 0.0001));
		c *= mix(0.65, 1.05, smoothstep(0.1, 0.3, cleat)) * mix(1.0, 0.85, step(0.9, run));
		c = mix(c, vec3(0.75, 0.62, 0.1), step(0.94, run) * 0.6);
		metal = 0.75;
		rough = 0.4;
	} else if (kind == K_TRACK) {
		float stain = vnoise(fc * vec2(0.4, 3.0));
		c *= 0.6 + 0.4 * stain;
		c *= 1.0 - 0.5 * (1.0 - smoothstep(0.0, 0.5, abs(abs(sp.z) - 4.9)));
		rough = 0.92;
	} else if (kind == K_RAIL) {
		float headtop = smoothstep(0.9, 0.98, n.y);
		c = mix(c, vec3(0.62, 0.62, 0.63), headtop);
		metal = 0.85;
		rough = mix(0.55, 0.2, headtop);
	} else if (kind == K_SCREEN) {
		// A screen: rows of departure text as dim blocks, a header bar in the line's colour.
		vec2 s = UV;
		float row = fract(s.y / 0.06);
		float word = step(0.5, vnoise(vec2(floor(s.x / 0.03), floor(s.y / 0.06)) * 1.7));
		float ink = step(0.25, row) * step(row, 0.75) * word;
		emit = c * (0.25 + 0.9 * ink);
		rough = 0.15;
	} else if (kind == K_TACTILE) {
		vec2 g = fract(fc / 0.06) - 0.5;
		float dome = 1.0 - smoothstep(0.18, 0.26, length(g));
		c *= 0.82 + 0.25 * dome * (1.0 - smoothstep(0.003, 0.01, px));
		rough = 0.6;
	} else if (kind == K_DARK) {
		c = vec3(0.004);
		rough = 1.0;
		spec = 0.1;
	} else if (kind == K_CEIL) {
		// Suspended metal panels, 1.2 x 0.6 m, dark reveals between them.
		vec2 g = abs(fract(fc / vec2(1.2, 0.6)) - 0.5) * vec2(1.2, 0.6);
		float reveal = 1.0 - smoothstep(0.006, 0.012 + px, min(0.6 - g.x, 0.3 - g.y));
		c *= mix(0.95 + 0.06 * h21(floor(fc / vec2(1.2, 0.6))), 0.35, reveal);
		rough = 0.5;
		metal = 0.3 * (1.0 - reveal);
	} else if (kind == K_MAP) {
		// A lit system map: pale ground, the line as a coral band, station dots, district tints.
		vec2 s = UV;
		float band = 1.0 - smoothstep(0.012, 0.018, abs(s.y - 0.5 - 0.06 * sin(s.x * 5.0)));
		float dots = 1.0 - smoothstep(0.012, 0.02, length(vec2(fract(s.x * 6.0) - 0.5, (s.y - 0.5 - 0.06 * sin(s.x * 5.0)) * 6.0) / 6.0));
		vec3 m = mix(vec3(0.82, 0.81, 0.77), vec3(0.70, 0.76, 0.70), step(0.6, vnoise(s * 9.0)));
		m = mix(m, vec3(0.86, 0.33, 0.24), band);
		m = mix(m, vec3(1.0), dots * band);
		c = m;
		emit = m * 0.8;
	}
	float under = smoothstep(-0.4, -3.0, sp.y);
	float light = fixtures(sp, n) * light_energy * under;
	if (kind == K_DARK || kind == K_LAMP || kind == K_TEXT || kind == K_SCREEN || kind == K_MAP) {
		light *= kind == K_DARK ? 0.0 : 0.3;
	}
	vec3 lit = c * light_color * light * (1.0 - metal * 0.6) + c * bounce_color * 0.04 * under;
	ALBEDO = cs_out(c * mix(1.0, ambient_keep, under));
	EMISSION = cs_out(emit + lit);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec * mix(1.0, 0.5, under);
}
