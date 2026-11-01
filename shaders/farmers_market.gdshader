shader_type spatial;
render_mode cull_disabled;

// The farmers' market (scripts/world/farmers_market_kit.gd, farmers_market_build.gd): canopies,
// tables, crates and their produce, flowers, bread, jars, the bollards, signs, banners, stall
// marks and string lights. One material, so each piece is one MultiMesh draw a chunk.
//
// * Vertex colour alpha x 20 says what a face is (FarmersMarketKit.C_*): 0 the vertex colour, 2
//   aluminium / steel, 4 canopy canvas (INSTANCE_CUSTOM.rgb, sRGB), 6 produce skin, 7 glass (jars,
//   bottles), 8 wood, 9 cardboard, 10 cloth (UV2.y 1: gingham), 12 a lamp (bulbs, a scale's
//   display, reflective tape), 14 leaves and petals, 16 a chalk board, 18 bread crust, 20 paint.
// * UV2 is (roughness, metallic). UV is metres off the face's dominant axis (an ellipsoid's runs
//   0..1 round and down it).
// * Colour space: vertex colours and instance data arrive raw on both renderers and are authored
//   sRGB; everything is worked in linear and handed over with cs_out() (color_space.gdshaderinc).
// * Double-sided (the canvas is seen from under the canopy); Godot turns the normal for a back face.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

// String-light bulbs by day (a little: they are on for the market) and at night.
uniform float bulb_day = 0.6;
uniform float bulb_night = 7.0;
// How much sun the canvas lets through to its underside.
uniform float canvas_through = 0.55;
// Road grime creeping up from the asphalt (metres) and how dark it gets.
uniform float grime_height = 0.3;
uniform float grime = 0.22;

varying vec3 v_local;
varying vec3 v_paint;
varying float v_code;

float fm_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fm_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fm_hash(i), fm_hash(i + vec2(1.0, 0.0)), f.x),
		mix(fm_hash(i + vec2(0.0, 1.0)), fm_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fm_noise3(vec3 p) {
	return fm_noise(p.xz + p.y * 1.7) * 0.6 + fm_noise(p.yx * 1.9 + p.z) * 0.4;
}

void vertex() {
	v_local = VERTEX;
	v_code = COLOR.a * 20.0;
	v_paint = INSTANCE_CUSTOM.rgb;
	// A batch without custom data (or a plain mesh) hands over black: that is white canvas.
	if (dot(v_paint, v_paint) < 0.0001) {
		v_paint = vec3(0.93, 0.93, 0.91);
	}
}

void fragment() {
	int code = int(round(v_code));
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float rough = UV2.x;
	float metal = UV2.y;
	vec3 emit = vec3(0.0);
	float lamp = clamp(lamp_factor, 0.0, 1.0);
	// How fine a pixel is on this surface (detail below a pixel fades to its mean).
	float px = length(fwidth(v_local));
	if (code == 2) {
		// Aluminium and steel: a fine brushed grain, a few scuffs.
		float g = mix(fm_noise(vec2(v_local.y * 90.0, v_local.x * 4.0 + v_local.z * 4.0)), 0.5, smoothstep(0.004, 0.02, px));
		rough = clamp(rough + (g - 0.5) * 0.2, 0.15, 0.9);
		base *= 0.94 + 0.08 * g;
	} else if (code == 4) {
		// Canopy canvas: polyester weave, a faint grubbiness toward the hems, seams down the faces.
		base = cs_srgb_to_linear(v_paint);
		float weave = mix(fm_noise(UV * 260.0), 0.5, smoothstep(0.002, 0.01, px));
		float dirt = fm_noise3(v_local * 2.3) * 0.5 + fm_noise3(v_local * 7.0) * 0.5;
		float hem = smoothstep(2.05, 1.94, v_local.y);
		base *= (0.94 + 0.08 * weave) * (1.0 - 0.1 * dirt - 0.12 * hem * dirt);
		rough = 0.82;
		metal = 0.0;
	} else if (code == 6) {
		// Produce: a broken tone and fine speckle (lenticels, dimples), the wet sheen of the skin.
		float n = fm_noise3(v_local * 70.0);
		float spot = smoothstep(0.72, 0.9, fm_noise3(v_local * 160.0 + 3.0));
		spot = mix(spot, 0.15, smoothstep(0.002, 0.006, px));
		base *= (0.86 + 0.26 * n) * (1.0 - 0.18 * spot);
		// Toward the stem a fruit is a little darker and duller.
		rough = clamp(rough + 0.25 * (1.0 - UV.y) * 0.4, 0.15, 0.85);
	} else if (code == 7) {
		// Glass jars and bottles: a deep tone (what is in them), glossy, a little light through.
		base *= 0.9;
		emit = base * 0.05;
	} else if (code == 8) {
		// Wood: grain along the plank, darker rings, weathered grey on the faces up top.
		vec2 g = UV * vec2(3.0, 40.0);
		float grain = fm_noise(g) * 0.6 + fm_noise(g * 3.1) * 0.4;
		grain = mix(grain, 0.5, smoothstep(0.004, 0.02, px));
		base *= 0.78 + 0.38 * grain;
		base = mix(base, vec3(dot(base, vec3(0.33))) * 1.05, 0.15 * fm_noise3(v_local * 1.3));
		rough = 0.85;
	} else if (code == 9) {
		// Cardboard: kraft fibres and a print smudge now and then.
		float f = mix(fm_noise(UV * 120.0), 0.5, smoothstep(0.003, 0.012, px));
		base *= 0.9 + 0.15 * f;
		rough = 0.95;
	} else if (code == 10) {
		// Cloth: a weave and, on a gingham cloth, the check.
		float w = mix(fm_noise(UV * 300.0), 0.5, smoothstep(0.002, 0.008, px));
		base *= 0.92 + 0.12 * w;
		if (metal > 0.5) {
			vec2 c = step(0.5, fract(UV * 9.0));
			float check = (c.x + c.y) * 0.5;
			check = mix(check, 0.5, smoothstep(0.01, 0.05, px));
			base = mix(vec3(0.85, 0.84, 0.8), base, 0.35 + 0.65 * check);
		}
		metal = 0.0;
	} else if (code == 12) {
		// A lamp: the string's bulbs, a scale's display, a bollard's reflective band.
		emit = base * mix(bulb_day, bulb_night, lamp);
		rough = 0.15;
		metal = 0.0;
	} else if (code == 14) {
		// Leaves and petals: veins and a lighter tip.
		float n = fm_noise3(v_local * 90.0);
		base *= 0.82 + 0.3 * n;
		rough = clamp(rough, 0.55, 0.9);
	} else if (code == 16) {
		// A chalk board: dark slate with the price chalked on it in a couple of strokes.
		vec2 q = fract(UV * vec2(8.0, 10.0));
		float chalk = smoothstep(0.85, 0.95, fm_noise(UV * vec2(60.0, 14.0))) * step(0.25, q.y) * step(q.y, 0.75);
		chalk = mix(chalk, 0.12, smoothstep(0.004, 0.012, px));
		base = mix(base, vec3(0.8, 0.8, 0.76), chalk);
		rough = 0.9;
	} else if (code == 18) {
		// Bread crust: darker on top where it baked, a dusting of flour, a fine bubbly texture.
		float n = fm_noise3(v_local * 55.0);
		float top = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
		base *= (0.82 + 0.3 * n) * mix(1.08, 0.85, top);
		float flour = smoothstep(0.62, 0.85, fm_noise3(v_local * 30.0 + 7.0)) * top;
		base = mix(base, vec3(0.8, 0.76, 0.68), flour * 0.45);
		rough = 0.85;
	} else if (code == 20) {
		base = cs_srgb_to_linear(v_paint);
	}
	// Grime from the road on what stands on it (not the lamps or the canvas up in the air).
	if (code != 12 && code != 4 && code != 6 && code != 14 && code != 18) {
		float gh = clamp(1.0 - v_local.y / grime_height, 0.0, 1.0);
		float n = fm_noise(v_local.xz * 4.0 + v_local.y * 3.0);
		base *= 1.0 - grime * gh * (0.5 + 0.5 * n);
	}
	ALBEDO = cs_out(base);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
	if (code == 4) {
		BACKLIGHT = cs_out(base * canvas_through);
	} else if (code == 14) {
		BACKLIGHT = cs_out(base * 0.25);
	}
}
