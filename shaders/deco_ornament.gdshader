shader_type spatial;

// Everything a Wilshire deco building wears that is not its windowed walls (DecoBuild: the walls
// are shaders/building.gdshader in its outline mode, so the windows keep their traced rooms): the
// piers, spandrel panels, friezes, finials and crowns, the streamline corners' glass block and
// speed lines, canopies, the theatre's marquee, readerboards and blade sign, the neon, the
// courtyard apartments' clay roofs, tile and fountain. ONE material for a chunk's deco buildings.
//
// COLOR.rgb is the paint in display (sRGB) numbers; COLOR.a is the kind in 64ths, plus 32 for a
// surface the night floodlights reach (a crown). UV is metres in the face's own frame (x along the
// face, y up it - for a floodlit surface, metres above the floodlights' foot); UV2 is a panel's
// size in metres (chevrons, sunbursts, readerboards), 0 elsewhere. TANGENT is the face's +UV.x.
//    0 cast stone / matte terracotta   1 glazed terracotta   2 chevron panel   3 sunburst panel
//    4 zigzag frieze   5 fluting   6 metal (bronze, gold leaf, aluminium)   7 glass block
//    8 neon   9 marquee bulbs   10 enamel sign panel   11 canopy soffit with downlights
//   12 clay barrel tile   13 stucco   14 glazed Spanish tile   15 flat roof (gravel)
//   16 readerboard   17 polished granite   18 fountain water   19 dark (an opening's depth)
//   20 gilt letters (gold leaf by day, lit as neon after dark)
// Every pattern is invented here (abstract deco geometry), and every lettering is real geometry
// from DecoBuild, so nothing here spells anything.

global uniform float lamp_factor;
global uniform float night_factor;
global uniform vec4 sky_tint;

// Night floodlights on the crowns: warm white, washing up from the setback ledges.
uniform vec3 flood_color = vec3(1.0, 0.86, 0.66);
uniform float flood_energy = 2.4;
uniform float flood_reach = 16.0;
// Neon after dark (and the little it shows by day, under the sun).
uniform float neon_energy = 5.5;
uniform float neon_day = 0.35;
uniform float bulb_energy = 4.0;
uniform float glass_block_glow = 0.9;
// Detail under a pixel fades to its average.
uniform float detail_fade = 1.0;

varying float kind_v;
varying float flood_v;
varying vec3 world_p;
varying vec3 world_n;

#include "res://shaders/color_space.gdshaderinc"

vec3 disp(vec3 c) {
	return cs_linear_renderer() ? cs_linear_to_srgb(c) : c;
}

vec3 to_lit(vec3 c) {
	return cs_linear_renderer() ? cs_srgb_to_linear(c) : c;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A joint line of width w (metres) at every multiple of `period`, box-filtered by the pixel size.
float joint(float x, float period, float w, float px) {
	float d = abs(fract(x / period + 0.5) - 0.5) * period;
	float aa = max(px, 1e-4);
	return 1.0 - smoothstep(w * 0.5 - aa * 0.5, w * 0.5 + aa * 0.5, d);
}

void vertex() {
	float k = COLOR.a * 64.0 + 0.5;
	flood_v = step(32.0, k);
	kind_v = floor(mod(k, 32.0));
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	int kind = int(kind_v + 0.5);
	vec3 paint = COLOR.rgb;
	vec2 uv = UV;
	vec2 panel = UV2;
	float px = max(length(fwidth(uv)), 1e-4);
	// 1 while a pattern of this size (metres) is resolved, 0 once it is under a pixel.
	float sharp = 1.0;
	vec3 col = paint;
	float rough = 0.75;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	// Relief as a height gradient in the face's (u, v): the normal leans against it.
	vec2 grad = vec2(0.0);
	float ao = 1.0;
	float mottle = vnoise(uv * 1.7 + world_p.xz * 0.05) * 0.6 + vnoise(uv * 7.0) * 0.4;

	if (kind == 0 || kind == 1 || kind == 5) {
		// Terracotta blocks: 0.9 x 0.45 m courses in running bond, each block its own shade.
		float course = floor(uv.y / 0.45);
		float bu = uv.x + mod(course, 2.0) * 0.45;
		float jt = max(joint(uv.y, 0.45, 0.012, px), joint(bu, 0.9, 0.012, px));
		float blk = hash12(vec2(floor(bu / 0.9), course) + paint.rg * 37.0);
		col = paint * (0.93 + 0.11 * blk) * (0.94 + 0.08 * mottle);
		if (kind == 1) {
			// Glaze: deeper and glossier, pooled darker at the block edges, a fine craquelure.
			col = paint * (0.88 + 0.16 * blk);
			float edge = 1.0 - smoothstep(0.0, 0.05, min(min(fract(bu / 0.9), 1.0 - fract(bu / 0.9)) * 0.9, min(fract(uv.y / 0.45), 1.0 - fract(uv.y / 0.45)) * 0.45));
			col *= 1.0 - 0.18 * edge;
			float craq = smoothstep(0.93, 1.0, vnoise(uv * 23.0 + blk * 9.0)) * clamp(1.0 - px * 30.0, 0.0, 1.0);
			col *= 1.0 - 0.12 * craq;
			rough = mix(0.22, 0.34, blk);
			spec = 0.62;
		} else {
			rough = 0.78;
		}
		if (kind == 5) {
			// Fluting: concave channels 0.16 m apart running up the face.
			float f = fract(uv.x / 0.16);
			float fade = clamp(1.0 - px / 0.05, 0.0, 1.0);
			grad.x += -cos(f * TAU) * 0.9 * fade;
			ao *= mix(1.0, 0.82 + 0.18 * sin(f * PI), fade);
		}
		col = mix(col, col * 0.55, jt * 0.8);
	} else if (kind == 2) {
		// Chevron spandrel: nested V's pointing down, stepped in relief, two tones.
		vec2 c = uv - vec2(panel.x * 0.5, 0.0);
		float rows = max(2.0, floor(panel.y / 0.22));
		float t = (uv.y - abs(c.x) * 0.9) / (panel.y / rows);
		float band = fract(t);
		float which = mod(floor(t), 2.0);
		float fade = clamp(1.0 - px / 0.04, 0.0, 1.0);
		col = mix(paint, paint * 0.62, which * fade + 0.5 * (1.0 - fade) * 0.4);
		// The step's face catches the light: the gradient points up the V.
		float rim = smoothstep(0.0, 0.12, band) * (1.0 - smoothstep(0.88, 1.0, band));
		grad += vec2(-sign(c.x) * 0.9, 1.0) * (1.0 - rim) * 0.8 * fade;
		// A raised border round the panel.
		float b = min(min(uv.x, panel.x - uv.x), min(uv.y, panel.y - uv.y));
		float bord = 1.0 - smoothstep(0.035, 0.035 + px, b);
		col = mix(col, paint * 1.08, bord);
		ao *= mix(0.86, 1.0, bord);
		rough = 0.5;
		spec = 0.58;
	} else if (kind == 3) {
		// Sunburst: rays fanning up from the bottom centre over a half disc, with a rising sun.
		vec2 c = uv - vec2(panel.x * 0.5, 0.0);
		float r = length(c) / max(panel.y, 0.01);
		float a = atan(c.x, max(c.y, 1e-4));
		float rays = 15.0;
		float ray = fract(a / PI * rays + 0.5);
		float fade = clamp(1.0 - px * rays / max(panel.y, 0.3) * 2.0, 0.0, 1.0);
		float stripe = step(0.5, ray);
		col = mix(paint, paint * 0.66, stripe * fade + 0.25 * (1.0 - fade));
		grad += vec2(cos(ray * TAU), 0.0) * 0.7 * fade;
		float sun = 1.0 - smoothstep(0.24, 0.24 + px / max(panel.y, 0.01), r);
		col = mix(col, paint * 1.15, sun);
		float ring = 1.0 - smoothstep(0.012, 0.012 + px, abs(r - 0.32) * panel.y);
		col = mix(col, paint * 0.5, ring);
		rough = 0.45;
		spec = 0.6;
	} else if (kind == 4) {
		// Zigzag frieze: a band of saw teeth along the face with a fillet top and bottom.
		float h = max(panel.y, 0.6);
		float period = h * 0.8;
		float x = fract(uv.x / period);
		float tooth = abs(x - 0.5) * 2.0;
		float yy = uv.y / h;
		float zz = abs(yy - 0.5 - (tooth - 0.5) * 0.45);
		float line = 1.0 - smoothstep(0.08, 0.08 + px / h, zz);
		float fade = clamp(1.0 - px / (h * 0.08), 0.0, 1.0);
		col = mix(paint * 0.68, paint * 1.08, mix(0.45, line, fade));
		grad += vec2(sign(x - 0.5) * 0.45, sign(yy - 0.5 - (tooth - 0.5) * 0.45)) * line * fade;
		float fillet = step(yy, 0.08) + step(0.92, yy);
		col = mix(col, paint * 1.1, clamp(fillet, 0.0, 1.0));
		rough = 0.5;
		spec = 0.58;
	} else if (kind == 6) {
		// Metal: bronze, gold leaf or aluminium, brushed along the face.
		float brush = vnoise(vec2(uv.x * 40.0, uv.y * 1.5));
		col = paint * (0.9 + 0.15 * brush);
		metal = 0.9;
		rough = 0.32 + 0.12 * mottle;
	} else if (kind == 7) {
		// Glass block: 0.2 m blocks in grey mortar, each a cushion of rippled glass.
		vec2 g = fract(uv / 0.2);
		vec2 cell = floor(uv / 0.2);
		float m = max(joint(uv.x, 0.2, 0.014, px), joint(uv.y, 0.2, 0.014, px));
		float fade = clamp(1.0 - px / 0.03, 0.0, 1.0);
		vec2 cush = (g - 0.5) * 2.0;
		grad += cush * 0.9 * fade;
		float ripple = vnoise(uv * 38.0 + cell * 3.1);
		vec3 glassc = mix(vec3(0.62, 0.70, 0.70), vec3(0.80, 0.84, 0.82), ripple * 0.6 + 0.2);
		vec3 sky = disp(sky_tint.rgb);
		glassc = mix(glassc, sky * 0.9 + 0.1, 0.25);
		col = mix(glassc, vec3(0.55, 0.55, 0.53), m);
		rough = mix(0.12, 0.85, m);
		spec = 0.7;
		// Lit from inside after dark: a stairwell's or a lobby's warm glow, blotchy through the glass.
		float inside = 0.55 + 0.45 * vnoise(uv * 0.6 + cell.yx * 0.07);
		emit = to_lit(vec3(1.0, 0.82, 0.58)) * glass_block_glow * lamp_factor * inside * (1.0 - m * 0.85) * (0.6 + 0.4 * ripple);
	} else if (kind == 8) {
		// Neon: the tube's own colour, a white-hot core where it is brightest.
		col = paint * 0.25;
		rough = 0.3;
		float on = neon_day + (1.0 - neon_day) * lamp_factor;
		emit = to_lit(paint) * neon_energy * on;
	} else if (kind == 9) {
		// Marquee bulbs on a dark sheet: a chase runs round them after dark.
		vec2 cell = floor(uv / 0.3);
		vec2 g = fract(uv / 0.3) - 0.5;
		float d = length(g) * 0.3;
		float bulb = 1.0 - smoothstep(0.045, 0.045 + px, d);
		float fade = clamp(1.0 - px / 0.06, 0.0, 1.0);
		bulb = mix(0.2, bulb, fade);
		float chase = step(0.34, fract((cell.x + cell.y) / 3.0 - TIME * 1.6));
		col = mix(paint * 0.3, vec3(1.0, 0.94, 0.8), bulb);
		rough = 0.35;
		float lit = mix(0.25, 1.0, chase);
		emit = to_lit(vec3(1.0, 0.80, 0.52)) * bulb * bulb_energy * (0.06 + lamp_factor * lit);
	} else if (kind == 10) {
		// Porcelain enamel sign panel: smooth, faintly rippled.
		col = paint * (0.96 + 0.06 * mottle);
		rough = 0.28;
		spec = 0.6;
	} else if (kind == 11) {
		// Canopy soffit: painted plaster with a downlight every 1.2 m, lit after dark.
		vec2 g = fract(uv / 1.2) - 0.5;
		float d = length(g) * 1.2;
		float can = 1.0 - smoothstep(0.08, 0.08 + px, d);
		col = mix(paint * (0.95 + 0.06 * mottle), vec3(0.95, 0.92, 0.85), can);
		rough = 0.85;
		emit = to_lit(vec3(1.0, 0.85, 0.62)) * can * 6.0 * lamp_factor;
		emit += to_lit(paint) * 0.25 * lamp_factor * (1.0 - smoothstep(0.0, 0.5, d));
	} else if (kind == 12) {
		// Clay barrel tile: courses up the slope, each tile a half round, sun-faded and patched.
		float course = floor(uv.y / 0.34);
		float tu = uv.x / 0.24 + mod(course, 2.0) * 0.5;
		float f = fract(tu);
		float fade = clamp(1.0 - px / 0.05, 0.0, 1.0);
		float barrel = sin(f * PI);
		grad.x += cos(f * PI) * 1.4 * fade;
		float lip = smoothstep(0.80, 1.0, fract(uv.y / 0.34));
		grad.y += lip * 0.9 * fade;
		float tile = hash12(vec2(floor(tu), course));
		vec3 clay = mix(vec3(0.62, 0.30, 0.18), vec3(0.74, 0.42, 0.26), tile);
		clay = mix(clay, vec3(0.46, 0.28, 0.20), step(0.9, tile) * 0.6);
		col = mix(clay * mix(0.75, 1.0, barrel * fade + (1.0 - fade) * 0.7), paint, 0.0) * (0.92 + 0.12 * mottle);
		ao *= mix(1.0, 0.65 + 0.35 * barrel, fade) * (1.0 - lip * 0.25);
		rough = 0.8;
	} else if (kind == 13) {
		// Stucco: troweled, a little patchy.
		col = paint * (0.9 + 0.12 * mottle);
		float fade = clamp(1.0 - px / 0.03, 0.0, 1.0);
		grad += (vec2(vnoise(uv * 11.0), vnoise(uv * 11.0 + 7.3)) - 0.5) * 0.5 * fade;
		rough = 0.92;
	} else if (kind == 14) {
		// Glazed tile, 0.15 m, blue and yellow quatrefoils on white.
		vec2 g = fract(uv / 0.15) - 0.5;
		float m = max(joint(uv.x, 0.15, 0.006, px), joint(uv.y, 0.15, 0.006, px));
		float petal = smoothstep(0.24, 0.20, min(length(g - vec2(0.0, 0.18)), min(length(g + vec2(0.0, 0.18)), min(length(g - vec2(0.18, 0.0)), length(g + vec2(0.18, 0.0))))));
		float star = smoothstep(0.12, 0.08, length(g));
		float fade = clamp(1.0 - px / 0.02, 0.0, 1.0);
		vec3 t = mix(vec3(0.90, 0.88, 0.80), vec3(0.12, 0.26, 0.56), petal * fade);
		t = mix(t, vec3(0.86, 0.62, 0.16), star * fade);
		t = mix(t, mix(vec3(0.90, 0.88, 0.80), vec3(0.4, 0.45, 0.6), 0.5), 1.0 - fade);
		col = mix(t, vec3(0.7, 0.68, 0.62), m);
		rough = mix(0.18, 0.8, m);
		spec = 0.65;
	} else if (kind == 15) {
		// Flat roof: tar and gravel.
		col = paint * (0.8 + 0.3 * hash12(floor(uv * 2.0))) * (0.9 + 0.2 * mottle);
		rough = 0.95;
	} else if (kind == 16) {
		// Readerboard: rows of black letters on a lit white board (invented blocks, not text).
		float rowh = max(panel.y / 3.0, 0.3);
		float row = floor(uv.y / rowh);
		float fy = fract(uv.y / rowh);
		float lw = 0.34;
		float li = floor(uv.x / lw);
		float fx = fract(uv.x / lw);
		float glyph = step(0.18, fy) * step(fy, 0.82) * step(0.12, fx) * step(fx, 0.82);
		float h = hash12(vec2(li, row) + paint.rb * 11.0);
		// Each letter a few strokes from its hash; a word break now and then.
		float strokes = max(step(fx, 0.3) * step(h, 0.7), max(step(abs(fy - 0.5), 0.08) * step(0.3, h), step(0.82 - 0.12, fy) * step(0.5, fract(h * 7.0))));
		float letter = glyph * strokes * step(0.12, fract(h * 13.0)) * step(0.4, uv.x) * step(uv.x, panel.x - 0.4);
		float fade = clamp(1.0 - px / 0.05, 0.0, 1.0);
		col = mix(vec3(0.92, 0.91, 0.86), vec3(0.05), letter * fade + 0.12 * (1.0 - fade));
		rough = 0.4;
		emit = to_lit(vec3(1.0, 0.95, 0.85)) * (1.0 - letter * fade) * 1.6 * lamp_factor;
	} else if (kind == 17) {
		// Polished black granite with mica.
		float speck = step(0.92, hash12(floor(uv * 90.0)));
		col = paint * (0.85 + 0.2 * mottle) + vec3(0.25) * speck * clamp(1.0 - px * 60.0, 0.0, 1.0);
		rough = 0.12;
		spec = 0.7;
	} else if (kind == 18) {
		// Fountain water: dark, the sky in it.
		float rip = vnoise(uv * 6.0 + vec2(TIME * 0.6, TIME * 0.4));
		col = vec3(0.05, 0.10, 0.11);
		rough = 0.06;
		spec = 0.8;
		grad += (vec2(rip, vnoise(uv * 6.0 - TIME * 0.5)) - 0.5) * 0.8;
	} else if (kind == 20) {
		// Gilt letters: gold leaf by day; after dark the neon tubes behind them light up.
		col = paint * (0.92 + 0.12 * mottle);
		metal = 0.85 * (1.0 - lamp_factor);
		rough = 0.3;
		emit = to_lit(paint) * neon_energy * 0.6 * lamp_factor;
	} else {
		col = paint * 0.2;
		rough = 1.0;
	}

	// Floodlights from the ledge below wash a crown up its face after dark.
	if (flood_v > 0.5) {
		float wash = exp(-max(uv.y, 0.0) / flood_reach) * (0.75 + 0.25 * mottle);
		float facing = clamp(1.0 - abs(world_n.y), 0.0, 1.0);
		emit += to_lit(clamp(col, vec3(0.0), vec3(1.0)) * flood_color) * flood_energy * lamp_factor * wash * facing;
	}

	ALBEDO = to_lit(clamp(col * ao, vec3(0.0), vec3(1.0)));
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
	if (dot(grad, grad) > 0.0) {
		NORMAL = normalize(NORMAL - (TANGENT * grad.x + BINORMAL * grad.y) * 0.35);
	}
}
