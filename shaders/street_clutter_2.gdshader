shader_type spatial;
render_mode cull_disabled;

// The street's second clutter pass (scripts/world/street_clutter_2.gd): trash bags, flattened
// cardboard, shopping carts, cones, a hand truck, weeds in the cracks, butts and gum, puddles in
// the road's dips, flyers on the poles, newspaper pages blowing, pigeon droppings. One material;
// one MultiMesh a kind a chunk.
//
// * COLOR.a x 16 is what a face is (C_* below = StreetClutter2.C_*, checked by the smoke test);
//   COLOR.rgb its colour, sRGB (vertex colours arrive raw on both renderers). UV is metres, or
//   0..1 over a printed face (its whole part picks the design); UV2 = (roughness, metallic).
// * INSTANCE_CUSTOM: r a seed / tone, g a second number per kind (wear, freshness, depth, the
//   cart's rust), b the page's run (/ 32 m).
// * Works in linear on both renderers (color_space.gdshaderinc).
// * Animated: the newspaper page (slides, hops and flutters down the gutter with wind_factor),
//   the weeds (sway), the puddles (gone on a dry street: collapsed in the vertex stage).

#include "res://shaders/color_space.gdshaderinc"

global uniform float road_wetness;
global uniform float rain_intensity;
global uniform float wind_factor;
global uniform float lamp_factor;
global uniform float night_factor;
global uniform vec4 sky_tint;

const int C_FIXED = 0;
const int C_BAG = 1;
const int C_CARD = 2;
const int C_WIRE = 3;
const int C_PLASTIC = 4;
const int C_CONE = 5;
const int C_WEED = 6;
const int C_BUTT = 7;
const int C_GUM = 8;
const int C_DROP = 9;
const int C_POSTER = 10;
const int C_PAPER = 11;
const int C_PUDDLE = 12;
const int C_RUBBER = 13;
const int C_STEEL = 14;
const int C_CRACK = 15;

// Below this road wetness no puddle is drawn; it reaches full size by puddle_full.
uniform float puddle_from = 0.02;
uniform float puddle_full = 0.4;
// The puddle's mirror of the sky (emitted by Fresnel); Forward+ adds its SSR on top.
uniform float mirror_compat = 0.85;
uniform float mirror_forward = 0.4;
// The page's speed (m/s) at no wind and per unit of wind_factor.
uniform float paper_speed = 0.6;
uniform float paper_speed_wind = 2.2;

varying flat float v_code;
varying vec3 v_local;
varying vec4 v_custom;
varying float v_move;

float h1(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h1(i), h1(i + vec2(1.0, 0.0)), f.x), mix(h1(i + vec2(0.0, 1.0)), h1(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return n2(p) * 0.55 + n2(p * 2.3 + 7.1) * 0.3 + n2(p * 5.1 + 3.7) * 0.15;
}

// How much of a pattern with `per_unit` cycles per UV unit survives at this pixel (1 crisp).
float keep(vec2 uv, float per_unit) {
	float fw = max(fwidth(uv.x), fwidth(uv.y)) * per_unit;
	return 1.0 - smoothstep(0.35, 0.9, fw);
}

// Where the page is along its run (metres) and how much it is moving (0 resting .. 1), for a
// ping-pong cycle: rest, blow down the run, rest, blow back.
vec2 paper_state(float run, float phase) {
	float speed = paper_speed + paper_speed_wind * clamp(wind_factor, 0.0, 1.5);
	float travel = run / speed;
	float rest = 3.0 + 4.0 * phase;
	float period = 2.0 * (travel + rest);
	float t = mod(TIME + phase * 97.0, period);
	float s;
	float moving;
	if (t < rest) {
		s = 0.0;
		moving = 0.0;
	} else if (t < rest + travel) {
		float k = (t - rest) / travel;
		s = run * smoothstep(0.0, 1.0, k) * 0.6 + run * k * 0.4;
		moving = sin(k * PI);
	} else if (t < 2.0 * rest + travel) {
		s = run;
		moving = 0.0;
	} else {
		float k = (t - 2.0 * rest - travel) / travel;
		s = run * (1.0 - (smoothstep(0.0, 1.0, k) * 0.6 + k * 0.4));
		moving = sin(k * PI);
	}
	return vec2(s, moving);
}

void vertex() {
	v_code = floor(COLOR.a * 16.0 + 0.5);
	v_custom = INSTANCE_CUSTOM;
	v_move = 0.0;
	int code = int(v_code);
	if (code == C_PUDDLE) {
		if (road_wetness < puddle_from) {
			VERTEX = vec3(0.0);
		}
	} else if (code == C_PAPER) {
		float run = INSTANCE_CUSTOM.b * 32.0;
		vec2 st = paper_state(run, INSTANCE_CUSTOM.r);
		float m = st.y;
		v_move = m;
		float t = TIME * 6.0 + INSTANCE_CUSTOM.r * 40.0;
		// Rolling over and lifting off as it goes: the page tips about its long edge and bows.
		float tilt = m * (0.5 + 0.5 * sin(t * 0.37)) * 1.1;
		vec3 v = VERTEX;
		float lift = m * (0.18 + 0.35 * abs(sin(t * 0.21 + INSTANCE_CUSTOM.r * 9.0)));
		float bow = (m * 0.08 + 0.015) * sin(v.x * 7.0 + t) + m * 0.06 * sin(v.z * 9.0 - t * 1.3);
		float cz = cos(tilt);
		float sz = sin(tilt);
		vec3 r = vec3(v.x, v.z * sz + bow, v.z * cz);
		VERTEX = r + vec3(st.x, lift + 0.004, 0.0);
		VERTEX.y = max(VERTEX.y, 0.002);
		NORMAL = normalize(vec3(-0.6 * m * cos(v.x * 7.0 + t), cz, -sz));
	} else if (code == C_WEED) {
		float h = max(VERTEX.y, 0.0);
		float sway = (0.3 + clamp(wind_factor, 0.0, 1.5)) * h * h * 3.0;
		float ph = dot(MODEL_MATRIX[3].xz, vec2(1.3, 0.7));
		VERTEX.xz += vec2(sin(TIME * 2.3 + ph), cos(TIME * 1.7 + ph)) * sway;
	}
	v_local = VERTEX;
}

void fragment() {
	int code = int(v_code);
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float rough = UV2.x;
	float metal = UV2.y;
	vec3 emit = vec3(0.0);
	float wet = clamp(road_wetness, 0.0, 1.0);
	float porous = 0.0;
	float seed = v_custom.r;

	if (code == C_BAG) {
		// Thin black plastic: glossy creases and dull stretched panels, the odd grey haze.
		float cr = fbm(v_local.xz * 9.0 + v_local.y * 6.0 + seed * 13.0);
		float crease = smoothstep(0.45, 0.8, abs(fbm(v_local.xy * 14.0 + seed * 3.0) - 0.5) * 2.0);
		rough = mix(0.18, 0.55, cr) * mix(1.0, 0.7, crease);
		base *= mix(0.8, 1.35, cr) * (0.9 + 0.2 * seed);
		base += vec3(0.012) * crease;
	} else if (code == C_CARD) {
		// Kraft board: mottle, the flutes showing on the cut edges, ink stamps, a tape strip,
		// dirt and wet rising from the pavement.
		vec2 uv = UV;
		base *= 0.88 + 0.22 * fbm(uv * 6.0 + seed * 5.0);
		float flutes = 0.5 + 0.5 * sin(uv.x * 2.0 * PI / 0.008);
		float k = keep(uv, 1.0 / 0.008);
		base *= mix(1.0, mix(0.97, 1.05, flutes), k * 0.6);
		vec2 cell = floor(uv / vec2(0.55, 0.45) + seed * 7.0);
		vec2 f = fract(uv / vec2(0.55, 0.45) + seed * 7.0);
		float stamp = step(0.4, h1(cell)) * step(0.15, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.48);
		float rows = step(0.5, fract(f.y * 18.0)) * step(0.25, h1(cell + floor(f.x * 14.0)));
		base = mix(base, vec3(0.04, 0.04, 0.045), stamp * mix(0.5, rows, keep(uv, 30.0)) * 0.8);
		float tape = step(abs(f.y - 0.85), 0.03) * step(0.55, h1(cell + 3.0));
		base = mix(base, base * vec3(1.12, 1.05, 0.9), tape);
		rough = mix(rough, 0.45, tape);
		float low = 1.0 - smoothstep(0.0, 0.25, v_local.y);
		base *= 1.0 - 0.3 * low * (0.5 + v_custom.g);
		porous = 1.0;
	} else if (code == C_WIRE) {
		// A grid of 3.5 mm wire at 25 mm; cut out, dithered to its cover once it is under a pixel.
		vec2 g = UV / 0.025;
		vec2 fw = fwidth(g);
		vec2 d = min(fract(g), 1.0 - fract(g));
		float w = 0.07;
		float line = max(1.0 - smoothstep(w - fw.x, w + fw.x, d.x), 1.0 - smoothstep(w - fw.y, w + fw.y, d.y));
		float far = smoothstep(0.25, 0.6, max(fw.x, fw.y));
		float cover = mix(line, 0.3, far);
		float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (cover < mix(0.5, dither, far)) {
			discard;
		}
		float rust = v_custom.g * smoothstep(0.6, 0.0, v_local.y) * fbm(UV * 20.0);
		base = mix(base, vec3(0.32, 0.17, 0.08), clamp(rust * 1.5, 0.0, 1.0));
		metal = mix(1.0, 0.2, rust);
		rough = mix(0.28, 0.8, rust);
	} else if (code == C_PLASTIC) {
		base *= 0.9 + 0.15 * fbm(UV * 30.0);
		rough = 0.45;
	} else if (code == C_CONE) {
		// Two reflective collars; scuffs and road grime from the base up.
		float y = v_local.y;
		float band = step(0.3, y) * step(y, 0.4) + step(0.47, y) * step(y, 0.52);
		base = mix(base, vec3(0.86, 0.86, 0.84), band);
		float grime = (1.0 - smoothstep(0.03, 0.3, y)) * 0.5 + v_custom.r * 0.35 * fbm(v_local.xz * 25.0 + y * 8.0);
		base *= 1.0 - clamp(grime, 0.0, 0.7);
		rough = mix(0.5, 0.35, band);
		emit = vec3(1.0, 0.95, 0.85) * band * lamp_factor * 0.35;
	} else if (code == C_WEED) {
		float dry = v_custom.g;
		base = mix(base, vec3(0.42, 0.36, 0.2), dry * dry * 0.8);
		base *= mix(0.6, 1.05, smoothstep(0.0, 0.12, v_local.y));
		BACKLIGHT = cs_out(base * 0.35);
	} else if (code == C_BUTT || code == C_GUM) {
		base *= 0.85 + 0.25 * h1(floor(v_local.xz * 60.0));
	} else if (code == C_DROP) {
		// White splashes with a grey-green heart, specks round them; cut out elsewhere.
		vec2 uv = UV;
		float m = 0.0;
		float heart = 0.0;
		for (int i = 0; i < 6; i++) {
			vec2 c = vec2(h1(vec2(seed * 31.0, float(i))), h1(vec2(float(i), seed * 17.0))) * 0.7 + 0.15;
			float r = 0.025 + 0.05 * h1(vec2(float(i) * 3.1, seed));
			float d = length(uv - c) + (n2(uv * 40.0 + float(i)) - 0.5) * 0.03;
			m = max(m, 1.0 - smoothstep(r * 0.85, r, d));
			heart = max(heart, 1.0 - smoothstep(r * 0.15, r * 0.45, d));
		}
		float specks = step(0.93, h1(floor(uv * 90.0) + seed)) * step(length(uv - 0.5), 0.45);
		m = max(m, specks);
		if (m < 0.5) {
			discard;
		}
		float fresh = v_custom.g;
		base = mix(vec3(0.52, 0.51, 0.47), vec3(0.85, 0.84, 0.8), fresh);
		base = mix(base, vec3(0.18, 0.2, 0.14), heart * 0.8);
		rough = mix(0.85, 0.45, fresh);
	} else if (code == C_POSTER) {
		// Photocopied flyers: a coloured or white sheet, a bold title, a photo on the lost-pet
		// ones, body lines, tear-off phone tabs along the bottom (some taken); faded and torn with age.
		float sheet = floor(UV.x);
		vec2 uv = vec2(fract(UV.x), UV.y);
		float s = sheet * 1.7 + seed * 11.0;
		float age = v_custom.g;
		float hue = h1(vec2(s, 2.0));
		vec3 paper = hue < 0.45 ? vec3(0.9, 0.89, 0.85) : (hue < 0.65 ? vec3(0.95, 0.88, 0.45) : (hue < 0.8 ? vec3(0.95, 0.66, 0.72) : (hue < 0.9 ? vec3(0.6, 0.85, 0.65) : vec3(0.62, 0.78, 0.92))));
		vec3 ink = h1(vec2(s, 5.0)) < 0.8 ? vec3(0.05) : vec3(0.55, 0.08, 0.06);
		vec3 col = paper;
		float kk = keep(UV, 60.0);
		// Tabs: the bottom 18 %, cut into strips, some torn off.
		if (uv.y > 0.82) {
			float tab = floor(uv.x * 9.0);
			float gap = step(0.88, fract(uv.x * 9.0));
			if (gap > 0.5 || h1(vec2(tab, s)) < 0.35 + 0.4 * age) {
				discard;
			}
			float ln = step(0.35, fract(uv.y * 30.0)) * step(0.3, fract(uv.x * 9.0)) * step(fract(uv.x * 9.0), 0.75);
			col = mix(col, ink, ln * mix(0.4, 0.85, kk));
		} else if (uv.y < 0.2) {
			float word = step(0.25, h1(vec2(floor(uv.x * 6.0), s))) * step(0.1, fract(uv.x * 6.0));
			float lt = step(0.04, uv.y) * step(uv.y, 0.17) * step(0.06, uv.x) * step(uv.x, 0.94);
			col = mix(col, ink, lt * word * mix(0.55, 0.95, keep(UV, 20.0)));
		} else {
			bool photo = h1(vec2(s, 9.0)) < 0.55;
			vec2 ph = (uv - vec2(0.15, 0.22)) / vec2(0.7, 0.33);
			if (photo && ph.x > 0.0 && ph.x < 1.0 && ph.y > 0.0 && ph.y < 1.0) {
				float n = fbm(ph * vec2(4.0, 3.0) + s);
				col = mix(vec3(0.12), vec3(0.62), n) * (0.8 + 0.25 * smoothstep(0.3, 0.6, length(ph - 0.5)));
			} else {
				float row = floor(uv.y * 26.0);
				float on = step(0.45, fract(uv.y * 26.0)) * step(0.08, uv.x) * step(uv.x, 0.92 - 0.3 * h1(vec2(row, s)));
				on *= step(0.2, h1(vec2(floor(uv.x * 22.0), row + s)));
				col = mix(col, ink, on * mix(0.25, 0.8, kk));
			}
		}
		// Age: faded toward the paper, yellowed, torn in from the edges.
		col = mix(col, vec3(0.78, 0.74, 0.62), age * 0.5);
		float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		if (fbm(uv * 9.0 + s) * 0.35 > edge + 0.12 * (1.0 - age) + 0.02) {
			discard;
		}
		base = cs_srgb_to_linear(col);
		porous = 1.0;
	} else if (code == C_PAPER) {
		// A page of newsprint: columns of grey type, a headline, a photo; grubby round its edges.
		vec2 uv = UV;
		vec3 col = vec3(0.8, 0.79, 0.74);
		float k = keep(uv, 120.0);
		if (uv.y < 0.14) {
			float on = step(0.03, uv.y) * step(0.05, uv.x) * step(uv.x, 0.9) * step(0.3, h1(vec2(floor(uv.x * 10.0), seed * 9.0)));
			col = mix(col, vec3(0.08), on * mix(0.5, 1.0, keep(uv, 20.0)));
		} else {
			vec2 ph = (uv - vec2(0.55, 0.2)) / vec2(0.38, 0.36);
			if (ph.x > 0.0 && ph.x < 1.0 && ph.y > 0.0 && ph.y < 1.0) {
				col = mix(vec3(0.22, 0.23, 0.26), vec3(0.6, 0.57, 0.5), fbm(ph * 4.0 + seed * 11.0));
			} else {
				float colm = fract(uv.x * 5.0);
				float line = step(0.4, fract(uv.y * 60.0)) * step(0.06, colm) * step(colm, 0.94);
				col = mix(col, vec3(0.3), line * mix(0.35, 0.7, k));
			}
		}
		float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		col *= mix(0.75, 1.0, smoothstep(0.0, 0.12, edge + 0.05 * fbm(uv * 12.0)));
		base = cs_srgb_to_linear(col);
		rough = 0.9;
		porous = 1.0 - v_move;
	} else if (code == C_PUDDLE) {
		// The water's outline grows with the road's wetness and shrinks as it dries: a noisy
		// blob, deepest in its middle, a damp dark ring round it.
		vec2 p = (UV - 0.5) * 2.0;
		float amount = smoothstep(puddle_from, puddle_full, road_wetness) * (0.55 + 0.45 * v_custom.g);
		float d = length(p) + (fbm(UV * 3.5 + seed * 17.0) - 0.5) * 0.7;
		float edge = 0.2 + 0.75 * amount;
		if (d > edge + 0.12) {
			discard;
		}
		float water = 1.0 - smoothstep(edge - 0.02, edge, d);
		base = mix(vec3(0.03, 0.03, 0.032), vec3(0.012, 0.012, 0.014), water);
		rough = mix(0.35, 0.02, water);
		// Rain rings on the surface.
		vec3 nrm = vec3(0.0, 0.0, 1.0);
		if (rain_intensity > 0.01 && water > 0.0) {
			vec2 w = (MODEL_MATRIX * vec4(UV.x - 0.5, 0.0, UV.y - 0.5, 1.0)).xz * 6.0;
			vec2 cell = floor(w);
			vec2 f = fract(w) - 0.5;
			float ph = fract(TIME * 1.3 + h1(cell));
			float ring = sin((length(f) - ph * 0.5) * 60.0) * (1.0 - ph) * smoothstep(0.5, 0.2, length(f));
			NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(f.x, 0.0, f.y, 0.0)).xyz * ring * 0.4 * rain_intensity * water);
		}
		float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
		vec3 sky = cs_srgb_to_linear(sky_tint.rgb);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		float mirror = mirror_compat;
#else
		float mirror = mirror_forward;
#endif
		emit = sky * fres * mirror * water * (1.0 - 0.85 * night_factor);
		// The lamps' warm light lying in the water after dark.
		emit += vec3(1.0, 0.62, 0.3) * fres * water * lamp_factor * 0.06;
		SPECULAR = 0.5;
	} else if (code == C_RUBBER) {
		rough = 0.85;
	} else if (code == C_STEEL) {
		float pick = floor(seed * 4.0);
		vec3 paint = pick < 1.0 ? vec3(0.62, 0.1, 0.07) : (pick < 2.0 ? vec3(0.85, 0.6, 0.08) : (pick < 3.0 ? vec3(0.12, 0.25, 0.55) : vec3(0.4, 0.41, 0.42)));
		base = cs_srgb_to_linear(paint) * (0.85 + 0.2 * fbm(v_local.xy * 18.0));
	} else if (code == C_CRACK) {
		rough = 1.0;
	}

	// The street's wetness soaks what lies on it: darker, and glossier where it does not soak in.
	if (code != C_PUDDLE && wet > 0.01) {
		float low = 1.0 - smoothstep(0.0, 0.5, v_local.y);
		base *= 1.0 - wet * (0.18 + 0.3 * porous) * mix(0.6, 1.0, low);
		rough = mix(rough, porous > 0.5 ? rough : 0.12, wet * 0.6);
	}
	ALBEDO = cs_out(base);
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
