// The decorated oil islands in the bay (OilIslands, OilIslandBuild): every surface of an island -
// revetment, pad, berm, sound wall, the rig towers' screens and panels, the derrick tops, the
// waterfall, the lamps - on ONE shader, so an island is one material. What a vertex is rides in
// COLOR.a as a code (kind + 16 x wash) / 128 (OilIslandBuild.code()): 8-bit safe, decoded with a
// quarter step of margin.
//   kind 0 concrete pad    1 rock (revetment, boulders)    2 groundcover (the berm)
//        3 white screen    4 pastel panel (COLOR)          5 steel (the derricks, the pipework)
//        6 falling water   7 still water (the falls' pools) 8 lamp (COLOR the lamp's colour)
//        9 sound wall (COLOR the band's colour)            10 foam    11 corrugated metal (COLOR)
//   wash 0..7 the gel of the floods that colour that face after dark (WASHES, mirrored in
//        OilIslands.WASHES - the smoke test reads this copy back).
// COLOR.rgb is sRGB paint, decoded here; everything is worked in LINEAR and handed back with
// cs_out(). UV is in METRES (along a wall / round the outline, then world height or the slope),
// which is what puts the boulders, joints, streaks and the water's run where they belong.
// Lights follow lamp_factor; the falls and the sea's edge run off TIME.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;
global uniform vec4 sky_tint;

uniform float wash_energy = 2.6;
uniform float lamp_energy = 6.0;
uniform float falls_glow = 0.9;
uniform float pad_y = 4.5;
uniform float boulder_cell = 1.7;

const vec3 WASHES[8] = vec3[8](
	vec3(1.0, 0.25, 0.62), vec3(0.55, 0.28, 1.0), vec3(0.15, 0.55, 1.0), vec3(0.1, 0.9, 0.62),
	vec3(1.0, 0.62, 0.18), vec3(1.0, 0.38, 0.3), vec3(0.78, 0.55, 1.0), vec3(0.2, 0.95, 0.95));

varying vec3 v_world;
varying flat int v_kind;
varying flat int v_wash;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 h22(vec2 p) {
	float n = h21(p);
	return vec2(n, h21(p + n + 17.0));
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1.0, 0.0));
	float c = h21(i + vec2(0.0, 1.0));
	float d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	return 0.5 * vnoise(p) + 0.3 * vnoise(p * 2.07 + 3.1) + 0.2 * vnoise(p * 4.3 + 7.7);
}

// Voronoi boulders: x the distance to the cell's own centre (0 at the crown, ~1 at the gap), y the
// cell's id hash, zw the vector from the centre (for a domed normal).
vec4 boulders(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	float second = 8.0;
	vec2 bv = vec2(0.0);
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = 0.15 + 0.7 * h22(i + g);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < best) {
				second = best;
				best = d;
				bv = r;
				id = h21(i + g + 0.5);
			} else if (d < second) {
				second = d;
			}
		}
	}
	float edge = sqrt(second) - sqrt(best);
	return vec4(edge, id, -bv);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float code = floor(COLOR.a * 128.0);
	v_kind = int(mod(code, 16.0));
	v_wash = int(code / 16.0);
}

void fragment() {
	vec3 paint = cs_srgb_to_linear(COLOR.rgb);
	vec2 uv = UV;
	float y = v_world.y;
	float lit = smoothstep(0.05, 0.55, lamp_factor);
	vec3 alb = paint;
	vec3 emit = vec3(0.0);
	float rough = 0.85;
	float metal = 0.0;
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	float wash_gain = 0.0;
	float px = max(length(fwidth(uv)), 1e-4);

	if (v_kind == 1) {
		// Granite and basalt quarry stone, laid as a revetment: a crown per cell, dark voids
		// between, each stone its own tone; wet, weed and barnacles near the water, foam at it.
		vec4 b = boulders(uv / boulder_cell);
		float far = smoothstep(0.25, 0.9, px / boulder_cell);
		float gap = smoothstep(0.02, 0.22, b.x);
		float tone = mix(0.7, 1.15, b.y) * mix(0.92, 1.06, vnoise(uv * 3.1));
		vec3 stone = mix(vec3(0.16, 0.15, 0.135), vec3(0.24, 0.215, 0.18), b.y);
		stone = mix(stone, vec3(0.11, 0.11, 0.115), step(0.82, b.y));
		alb = mix(stone * tone * mix(0.35, 1.0, gap), stone * 0.82, far);
		vec2 slope = b.zw * 0.9 * (1.0 - far);
		nmap = vec3(0.5 + slope.x * 0.5, 0.5 + slope.y * 0.5, 1.0);
		float wet = 1.0 - smoothstep(0.5, 1.9, y);
		alb *= mix(1.0, 0.55, wet);
		rough = mix(0.88, 0.32, wet);
		float weed = (1.0 - smoothstep(-0.2, 0.9, y)) * smoothstep(-1.6, -0.3, y);
		alb = mix(alb, vec3(0.05, 0.07, 0.035), weed * 0.7 * smoothstep(0.35, 0.65, vnoise(uv * 1.3)));
		float barn = smoothstep(0.9, 1.0, h21(floor(uv * 14.0))) * (1.0 - smoothstep(0.4, 1.3, y)) * smoothstep(-0.6, 0.0, y);
		alb = mix(alb, vec3(0.55, 0.53, 0.48), barn * (1.0 - far));
		// The swell runs up and back on the stones: a lace of foam at the sea's edge.
		float swell = 0.28 * sin(TIME * 0.9 + v_world.x * 0.035 + v_world.z * 0.02) + 0.12 * sin(TIME * 1.7 + v_world.x * 0.09);
		float band = 1.0 - smoothstep(0.0, 0.45, abs(y - 0.15 - swell));
		float lace = smoothstep(0.45, 0.75, fbm(uv * 1.6 + vec2(TIME * 0.25, 0.0)));
		alb = mix(alb, vec3(0.82, 0.86, 0.86), band * lace * gap);
	} else if (v_kind == 0) {
		// Poured concrete: slab joints every 6 m, tyre and oil stains, a little aggregate.
		vec2 j = abs(fract(uv / 6.0) - 0.5);
		float joint = 1.0 - smoothstep(0.0, max(0.006, px * 0.2), min(j.x, j.y) * 6.0 - 0.02);
		float stain = smoothstep(0.55, 0.85, fbm(uv * 0.11));
		alb = paint * mix(0.92, 1.05, vnoise(uv * 2.3)) * mix(1.0, 0.72, stain) * mix(1.0, 0.6, joint);
		rough = mix(0.86, 0.3, road_wetness);
	} else if (v_kind == 2) {
		// Ice plant and lantana over the berm: green mats with magenta and gold flower patches.
		float m = fbm(uv * 0.35);
		vec3 g = mix(vec3(0.035, 0.07, 0.025), vec3(0.075, 0.12, 0.04), m);
		float fl = smoothstep(0.62, 0.72, fbm(uv * 0.9 + 11.0));
		float which = step(0.5, vnoise(uv * 0.08));
		g = mix(g, mix(vec3(0.5, 0.06, 0.22), vec3(0.55, 0.36, 0.03), which), fl * 0.7);
		alb = g * mix(0.75, 1.1, vnoise(uv * 4.0));
		vec2 bump = vec2(vnoise(uv * 5.0) - 0.5, vnoise(uv * 5.0 + 9.0) - 0.5);
		nmap = vec3(0.5 + bump * 0.5, 1.0);
		rough = 0.92;
	} else if (v_kind == 3 || v_kind == 4 || v_kind == 9) {
		// The screens and panels: board-formed white concrete or painted panels, streaked under
		// their tops; the sound wall has panel joints and a painted band.
		float boards = smoothstep(0.42, 0.5, abs(fract(uv.x / 0.3) - 0.5)) * (1.0 - smoothstep(0.02, 0.06, px));
		float streak = vnoise(vec2(uv.x * 1.3, uv.y * 0.04)) * smoothstep(0.4, 1.0, vnoise(vec2(uv.x * 0.4, 0.0)));
		if (v_kind == 3) {
			alb = vec3(0.78, 0.77, 0.73) * mix(1.0, 0.93, boards) * mix(1.0, 0.86, streak * 0.6);
			rough = 0.8;
		} else if (v_kind == 4) {
			alb = paint * mix(1.0, 0.9, streak * 0.4);
			rough = 0.55;
		} else {
			float h = y - pad_y;
			vec2 j = abs(fract(vec2(uv.x / 4.0, h / 3.0)) - 0.5);
			float joint = 1.0 - smoothstep(0.0, max(0.004, px * 0.25), min(j.x * 4.0, j.y * 3.0) - 0.02);
			float band = step(5.2, h) * step(h, 6.3);
			float band2 = step(6.7, h) * step(h, 6.95);
			alb = vec3(0.7, 0.68, 0.63) * mix(1.0, 0.75, joint) * mix(1.0, 0.85, streak * 0.5);
			alb = mix(alb, paint, max(band, band2));
			rough = 0.85;
		}
		wash_gain = 1.0;
	} else if (v_kind == 5) {
		alb = paint * mix(0.85, 1.05, vnoise(uv * 3.0));
		metal = 0.35;
		rough = 0.6;
	} else if (v_kind == 6) {
		// A sheet of falling water: streaks running down (v is metres down the fall), foam
		// thickest at the lip and the foot, the sky in its face.
		float run = fbm(vec2(uv.x * 2.6, uv.y * 0.55 - TIME * 2.4));
		float fine = vnoise(vec2(uv.x * 9.0, uv.y * 1.6 - TIME * 4.0));
		float foam = clamp(0.35 + 0.7 * run + 0.25 * fine, 0.0, 1.0);
		vec3 deep = vec3(0.07, 0.2, 0.22);
		alb = mix(deep, vec3(0.85, 0.9, 0.9), foam);
		rough = mix(0.08, 0.5, foam);
		vec3 sky = cs_srgb_to_linear(sky_tint.rgb);
		emit = sky * 0.12 * (1.0 - foam);
		emit += vec3(0.55, 0.85, 1.0) * falls_glow * lit * foam;
		nmap = vec3(0.5 + (run - 0.5) * 0.6, 0.5, 1.0);
	} else if (v_kind == 7) {
		// Still water in the falls' pools: dark, glassy, the sky by Fresnel; lit from below at night.
		float ripple = vnoise(uv * 2.0 + TIME * 0.4) - 0.5;
		nmap = vec3(0.5 + ripple * 0.15, 0.5 + ripple * 0.1, 1.0);
		alb = vec3(0.01, 0.035, 0.04);
		rough = 0.04;
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		emit = cs_srgb_to_linear(sky_tint.rgb) * (0.06 + 0.5 * fres) + vec3(0.1, 0.55, 0.65) * lit * 0.7;
	} else if (v_kind == 8) {
		// A lamp lens: dim glass by day; at night its own colour, the red aviation lights
		// pulsing slowly in turn.
		alb = paint * 0.25 + vec3(0.05);
		rough = 0.2;
		float pulse = 1.0;
		if (paint.r > 0.5 && paint.g < 0.2) {
			pulse = 0.25 + 0.75 * smoothstep(0.2, 0.8, sin(TIME * 1.6 + v_world.x * 0.07));
			emit = paint * lamp_energy * 1.6 * pulse * max(lit, 0.15);
		} else {
			emit = paint * lamp_energy * lit;
		}
	} else if (v_kind == 10) {
		float f = fbm(uv * 0.8 + vec2(TIME * 0.3, -TIME * 0.2));
		alb = vec3(0.86, 0.9, 0.9) * smoothstep(0.35, 0.65, f) + vec3(0.06, 0.12, 0.13) * (1.0 - smoothstep(0.35, 0.65, f));
		rough = 0.3;
		emit = vec3(0.4, 0.75, 0.9) * lit * falls_glow * 0.4 * f;
	} else if (v_kind == 11) {
		float rib = 0.5 + 0.5 * cos(uv.x * TAU / 0.2);
		float fade = 1.0 - smoothstep(0.03, 0.1, px);
		alb = paint * mix(1.0, mix(0.82, 1.0, rib), fade) * mix(0.9, 1.04, vnoise(uv * 0.7));
		nmap = vec3(0.5 + 0.25 * sin(uv.x * TAU / 0.2) * fade, 0.5, 1.0);
		metal = 0.25;
		rough = 0.55;
	}

	if (wash_gain > 0.0 && lit > 0.0) {
		// The floods stand at the foot of each face, gelled one colour a face, so a tower glows
		// from its base up in pools that fade with height; a little spill reaches the top.
		vec3 gel = WASHES[clamp(v_wash, 0, 7)];
		float h = max(y - pad_y, 0.0);
		float rise = exp(-h / 30.0) * 0.85 + 0.15;
		float pools = 0.55 + 0.45 * cos(uv.x * TAU / 7.5);
		pools = mix(pools, 1.0, smoothstep(5.0, 25.0, h));
		// The sound wall's floods are fewer and lower: pools along it, not a lit band.
		if (v_kind == 9) {
			rise = exp(-h / 6.0);
			pools = pow(max(cos(uv.x * TAU / 24.0), 0.0), 3.0);
		}
		emit += alb * gel * wash_energy * lit * rise * pools;
	}

	ALBEDO = cs_out(alb);
	EMISSION = cs_out(emit);
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = nmap;
}
