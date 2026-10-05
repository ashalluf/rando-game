shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// The ballpark's structure (BallparkBuild): the tiers' concrete, fascias and end walls, the
// exterior facade, roofs, the outfield wall, foul poles, the scoreboards' frames and screens,
// bridges and the lot's light poles. ONE material: what a face is rides in the vertex colour's
// alpha (kind / 16, K_* below), its paint in COLOR.rgb (sRGB numbers), UV in metres along and up
// the face (a screen's UV is 0..1 across it). Works in linear (ballpark_common / color_space).
//
// Kinds: 0 exterior concrete (the facade: columns, concourse openings lit warm at night),
// 1 interior concrete (floodlit), 2 paint (floodlit), 3 steel (floodlit from below), 4 roof
// membrane, 5 dark (openings, dugouts), 6 padded outfield wall (yellow line on top), 7 screen,
// 8 concourse band (lit warm at night), 9 foul-pole yellow, 10 a floodlight's lens, 11 a
// tier's open concourse seen from outside (UV.y metres over its parapet).

#include "res://shaders/ballpark_common.gdshaderinc"

uniform float flood_energy = 0.26;
uniform float screen_energy = 1.6;
uniform float concourse_energy = 1.2;
uniform float lens_energy = 14.0;
uniform float bay = 8.4;
uniform float storey = 6.2;

varying flat int kind;
varying vec3 paint;
varying vec3 wpos;

void vertex() {
	kind = int(round(COLOR.a * 16.0));
	paint = bp_vcol(COLOR.rgb);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// A filtered line pattern: 1 on a line `w` wide every `p`.
float lines(float x, float p, float w) {
	float fw = max(fwidth(x), 1e-4);
	float d = abs(fract(x / p + 0.5) - 0.5) * p;
	return 1.0 - smoothstep(w * 0.5 - fw, w * 0.5 + fw, d);
}

// A line score: rows of 7-segment-ish digits on a dark board.
float digit(vec2 g, int n) {
	// 3 x 5 cells, a bitmask per digit (row-major from the top).
	int masks[10] = int[](31599, 11415, 29671, 29647, 23497, 31183, 31215, 29330, 31727, 31695);
	ivec2 c = ivec2(floor(g * vec2(3.0, 5.0)));
	if (c.x < 0 || c.x > 2 || c.y < 0 || c.y > 4) {
		return 0.0;
	}
	int bit = (4 - c.y) * 3 + (2 - c.x);
	return float((masks[n] >> bit) & 1);
}

void fragment() {
	vec3 alb = paint;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float flood = bp_flood();
	vec2 uv = UV;
	float n = vnoise(wpos.xz * 0.35 + wpos.y * 0.21) * 0.6 + vnoise(wpos.xz * 2.1 + wpos.y * 1.7) * 0.4;
	if (kind == 0 || kind == 1) {
		// Board-formed concrete: mottled, lift lines every 1.2 m, bay joints, streaks down.
		alb *= 0.9 + 0.18 * n;
		alb *= 1.0 - 0.10 * lines(uv.y, 1.2, 0.03);
		alb *= 1.0 - 0.16 * lines(uv.x, bay, 0.05);
		alb *= 1.0 - 0.10 * smoothstep(0.5, 1.0, vnoise(vec2(uv.x * 1.3, uv.y * 0.08))) ;
		if (kind == 0) {
			// The facade: columns every bay, the concourse decks behind open bands every storey.
			float col = lines(uv.x, bay, 1.1);
			float band = smoothstep(0.42, 0.46, fract(uv.y / storey)) * (1.0 - smoothstep(0.86, 0.9, fract(uv.y / storey)));
			float open = band * (1.0 - col) * step(3.0, uv.y);
			vec3 inside = vec3(0.05, 0.05, 0.055);
			alb = mix(alb, inside, open * 0.9);
			// Lit concourses after dark: warm, dimmer toward the deck's back.
			float lit = open * lamp_factor * (0.7 + 0.3 * vnoise(vec2(floor(uv.x / bay) * 3.1, floor(uv.y / storey))));
			emit += vec3(1.0, 0.78, 0.5) * lit * concourse_energy * 0.6;
		} else {
			emit += alb * flood * flood_energy * 0.55;
		}
	} else if (kind == 2) {
		alb *= 0.94 + 0.08 * n;
		rough = 0.6;
		emit += alb * flood * flood_energy;
	} else if (kind == 3) {
		alb *= 0.92 + 0.1 * n;
		rough = 0.45;
		metal = 0.55;
		emit += alb * flood * flood_energy * 0.5;
	} else if (kind == 4) {
		// Roof membrane / standing-seam metal: pale, seams across the fold.
		alb *= 0.93 + 0.08 * n;
		alb *= 1.0 - 0.08 * lines(uv.x, 0.6, 0.04);
		rough = 0.5;
		metal = 0.2;
		emit += alb * flood * flood_energy * 0.25;
	} else if (kind == 5) {
		alb = vec3(0.03, 0.03, 0.035);
		rough = 0.95;
		emit += vec3(1.0, 0.85, 0.65) * 0.05 * lamp_factor;
	} else if (kind == 6) {
		// Padded wall: panels a metre and a half wide, the yellow home-run line along the top.
		alb *= 0.9 + 0.12 * n;
		alb *= 1.0 - 0.25 * lines(uv.x, 1.52, 0.04);
		float top = smoothstep(0.12, 0.08, abs(uv.y - 2.48));
		alb = mix(alb, cs_srgb_to_linear(vec3(0.95, 0.8, 0.12)), top);
		rough = 0.9;
		emit += alb * flood * flood_energy;
	} else if (kind == 7) {
		// A screen: COLOR.r 1 the video board, 0 the line score.
		vec3 c;
		if (COLOR.r > 0.5) {
			vec2 p = uv * vec2(16.0, 6.0);
			float t = TIME * 0.05;
			vec3 a = vec3(0.10, 0.35, 0.85);
			vec3 b = vec3(0.95, 0.55, 0.12);
			float w = vnoise(p * 0.35 + vec2(t, -t * 0.7));
			c = mix(a, b, smoothstep(0.35, 0.75, w));
			c = mix(c, vec3(0.92, 0.94, 0.96), step(0.86, uv.y) * 0.85);
			c *= 0.75 + 0.25 * vnoise(p * 1.7 + t * 3.0);
		} else {
			// Two rows of nine innings, then runs, hits and errors.
			vec2 g = vec2(uv.x * 13.0, (1.0 - uv.y) * 3.0);
			ivec2 cell = ivec2(floor(g));
			vec2 f = fract(g);
			c = vec3(0.02, 0.05, 0.03);
			if (cell.y >= 1 && cell.x >= 1 && cell.x <= 12) {
				int inning = cell.x;
				int row = cell.y;
				int val = int(bp_hash01(inning * 3 + row, 77) * 3.2);
				if (inning >= 10) {
					val = int(bp_hash01(inning * 5 + row, 91) * 9.9);
				}
				float on = digit((f - vec2(0.25, 0.15)) / vec2(0.5, 0.7), val);
				float played = step(float(inning), 7.0) + step(10.0, float(inning));
				c = mix(c, vec3(1.0, 0.86, 0.45), on * min(played, 1.0));
			}
			float frame = 1.0 - step(0.06, f.y) * step(f.y, 0.94) * step(0.04, f.x) * step(f.x, 0.96);
			c = mix(c, vec3(0.08, 0.1, 0.09), frame * 0.6);
		}
		// LED pixels.
		vec2 px = fract(uv * vec2(420.0, 160.0));
		float dot_mask = 1.0 - 0.35 * smoothstep(0.3, 0.5, length(px - 0.5));
		alb = vec3(0.02);
		rough = 0.35;
		emit += cs_srgb_to_linear(c) * dot_mask * screen_energy * mix(0.55, 1.0, night_factor);
	} else if (kind == 8) {
		alb *= 0.9;
		emit += vec3(1.0, 0.8, 0.55) * lamp_factor * concourse_energy;
	} else if (kind == 9) {
		rough = 0.4;
		emit += alb * flood * flood_energy * 1.2;
	} else if (kind == 11) {
		// A tier's open concourse seen from outside: a column every bay, the lintel over it, and
		// between them the concourse in shade, its stands lit warm after dark.
		float col = lines(uv.x, bay, 1.0);
		float lintel = smoothstep(2.0, 2.05, uv.y);
		float open = (1.0 - col) * (1.0 - lintel);
		alb *= 0.9 + 0.18 * n;
		vec3 inside = vec3(0.07, 0.068, 0.065) * (0.6 + 0.6 * smoothstep(0.0, 2.0, uv.y));
		alb = mix(alb, inside, open);
		emit += vec3(1.0, 0.8, 0.55) * open * lamp_factor * concourse_energy * 0.35 * (0.6 + 0.4 * vnoise(vec2(uv.x * 0.37, 2.0)));
		emit += alb * flood * flood_energy * 0.2 * (1.0 - open);
	} else if (kind == 10) {
		// A floodlight's lens: pale glass by day, blazing after dark.
		alb = vec3(0.55, 0.57, 0.6);
		rough = 0.15;
		metal = 0.3;
		emit += vec3(1.0, 0.97, 0.9) * lens_energy * flood;
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
