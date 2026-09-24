shader_type spatial;
render_mode cull_back, shadows_disabled;

// The giant LED screens of the arena and the entertainment plaza. Everything on them is
// original: abstract motion graphics, and adverts for invented brands whose names come from a
// small dot-matrix atlas LedScreen.atlas() builds at load (never a real brand). A screen cycles
// through slides every slide_seconds with a wipe between them; each slide is a moving background
// (colour sweeps, rings, an equaliser, sparkles, plasma, chevrons) with or without a name on it.
//
// It is drawn as what it is: a grid of LEDs. Up close you see the diodes; once one is smaller
// than a couple of pixels the grid fades out and the picture is solid, so it never moires.
// Emissive day and night - a real stadium screen is readable in full sun - and brighter after
// dark. UV runs 0..1 across the screen, (0, 0) at its top left.
//
// Shader files use // comments, never #.

#include "res://shaders/landmark_common.gdshaderinc"

uniform sampler2D slides : filter_nearest, repeat_disable;
// Atlas layout (LedScreen.SLIDE_H rows of pixels per slide, ATLAS_W wide).
uniform float atlas_w = 256.0;
uniform float slide_h = 11.0;
uniform int slide_count = 12;
// Text width in atlas pixels per slide; 0 = a slide of pure motion.
uniform float slide_w[16];
uniform float slide_seconds = 6.0;
uniform float seed = 0.0;
// Screen width over height, and LEDs across it.
uniform float aspect = 2.0;
uniform float res = 160.0;
uniform float day_brightness = 2.2;
uniform float night_brightness = 1.6;

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

vec3 background(int style, vec2 uv, float t, vec3 c1, vec3 c2) {
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	if (style == 0) {
		return mix(c1, c2, 0.5 + 0.5 * sin((uv.x * 0.8 + uv.y * 0.35 - t * 0.18) * 6.2831853));
	} else if (style == 1) {
		float r = length(p);
		return mix(c1 * 0.25, c2, 0.5 + 0.5 * sin(r * 22.0 - t * 5.0)) * (1.0 - 0.4 * r);
	} else if (style == 2) {
		float bars = 18.0;
		float bx = floor(uv.x * bars);
		float h = 0.25 + 0.7 * abs(sin(t * (1.3 + lm_hash21(vec2(bx, 3.0)) * 2.2) + bx));
		float on = step(1.0 - uv.y, h) * step(0.18, fract(uv.x * bars));
		return mix(c1 * 0.12, mix(c2, c1, 1.0 - uv.y), on);
	} else if (style == 3) {
		vec2 g = floor(uv * vec2(aspect, 1.0) * 26.0);
		float tw = lm_hash21(g + floor(t * 3.0));
		return mix(c1 * 0.15, c2, step(0.93, tw)) + c1 * 0.2 * (1.0 - uv.y);
	} else if (style == 4) {
		float v = sin(p.x * 4.0 + t) + sin(p.y * 6.0 - t * 1.3) + sin(length(p) * 7.0 - t * 1.7);
		return mix(c1, c2, 0.5 + 0.25 * v);
	}
	float ch = fract((abs(p.y) * 1.2 + p.x) * 2.2 - t * 0.9);
	return mix(c1 * 0.2, c2, step(0.5, ch));
}

void fragment() {
	vec2 uv = UV;
	float ry = max(1.0, floor(res / aspect + 0.5));
	vec2 cells = vec2(res, ry);
	vec2 cell = floor(uv * cells);
	vec2 cuv = (cell + 0.5) / cells;
	float clock = TIME + seed * 17.0;
	float slot = floor(clock / slide_seconds);
	int k = int(mod(slot + seed * 5.0, float(slide_count)));
	float since = clock - slot * slide_seconds;
	vec3 c1 = hue(lm_hash21(vec2(float(k), seed + 1.0)));
	vec3 c2 = hue(lm_hash21(vec2(float(k) + 7.0, seed + 2.0)));
	c2 = mix(c2, vec3(1.0), 0.25);
	int style = int(mod(float(k) * 7.0 + seed * 3.0, 6.0));
	vec3 col = background(style, cuv, clock, c1, c2);
	// The name, drawn in whole LEDs from the atlas. On a portrait screen (a column on a corner)
	// it runs up the screen instead, the way a tall LED pylon reads.
	float tw = slide_w[k];
	bool tall = cells.y > cells.x * 1.2;
	vec2 tcells = tall ? cells.yx : cells;
	vec2 tcell = tall ? vec2(cells.y - 1.0 - cell.y, cell.x) : cell;
	if (tw > 0.5 && tw <= tcells.x * 0.98) {
		float s = max(1.0, floor(min(0.86 * tcells.x / tw, 0.55 * tcells.y / 7.0)));
		vec2 box = vec2(tw, 7.0) * s;
		vec2 o = floor((tcells - box) * 0.5);
		vec2 tp = floor((tcell - o) / s);
		if (tp.x >= 0.0 && tp.y >= 0.0 && tp.x < tw && tp.y < 7.0) {
			float atlas_x = floor((atlas_w - tw) * 0.5) + tp.x;
			float atlas_y = float(k) * slide_h + 2.0 + tp.y;
			float m = texelFetch(slides, ivec2(int(atlas_x), int(atlas_y)), 0).r;
			// A dark keyline under the letters so they read over any background.
			col = mix(col * 0.35, vec3(1.0), m);
		} else {
			col *= 0.8;
		}
	}
	// The wipe to the next slide.
	float wipe = smoothstep(0.0, 0.5, since);
	col *= step(cuv.x, wipe * 1.2 - 0.1) + 0.12;
	// The diodes, fading to a solid picture once they are finer than a few pixels.
	vec2 lf = fract(uv * cells) - 0.5;
	float diode = 1.0 - smoothstep(0.28, 0.48, length(lf));
	float px = max(fwidth(uv.x * cells.x), fwidth(uv.y * cells.y));
	float grid_vis = 1.0 - smoothstep(0.25, 0.7, px);
	col *= mix(1.0, diode * 1.5 + 0.04, grid_vis);
	float bright = mix(day_brightness, night_brightness, night_factor);
	ALBEDO = vec3(0.02);
	ROUGHNESS = 0.25;
	SPECULAR = 0.4;
	EMISSION = col * bright;
}
