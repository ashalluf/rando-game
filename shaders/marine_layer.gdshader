shader_type spatial;
// The marine layer (MarineLayer, scripts/world/marine_layer.gd): one shader, three meshes.
//   mode 0  the deck's underside, a plane at LaWeather.DECK_BASE facing down: the low grey
//           ceiling of June gloom, thick and even, lit from below by the city after dark.
//   mode 1  the deck's top, a plane at DECK_TOP facing up: a sunlit white sea of stratus seen
//           from the hills and the air.
//   mode 2  the evening fog bank: a ribbon standing on the water along the deck's edge, billowed
//           in the vertex shader, its top rolling into the deck (LaWeather.bank_amount()).
// Where the deck is comes from one number, `edge_x` (true world X; the deck is WEST of it),
// wobbled along the coast exactly as LaWeather.edge_wobble() does. Everything is worked out in
// true world XZ (`world_offset`), so nothing swims when the origin re-centres.
// Colours are LINEAR, set from script as Vector3 (plain uniforms: no decode on either renderer),
// and handed to the renderer through cs_out() (color_space.gdshaderinc).
// The deck fogs itself (fog_disabled): Godot's height fog thickens UP into the deck, and on the
// deck it would leave nothing but the fog colour - no rolls, no cells, no edge.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

#include "res://shaders/color_space.gdshaderinc"

uniform int mode = 0;
uniform float amount = 0.0;
uniform float bank = 0.0;
uniform float edge_x = 1.0e6;
uniform float edge_soft = 320.0;
uniform vec3 world_offset = vec3(0.0);
uniform float deck_base = 255.0;
uniform float deck_top = 520.0;
// The view's rim: the planes fade out over the last stretch of their radius.
uniform float rim_start = 5200.0;
uniform float rim_end = 7600.0;
uniform vec3 lit_col = vec3(0.80, 0.81, 0.83);
uniform vec3 shade_col = vec3(0.42, 0.45, 0.49);
// The city's sodium light on the underside after dark (added, linear).
uniform vec3 glow_col = vec3(0.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float drift = 0.0;
// How opaque the deck is in its middle (mode 0 and 1) and the bank at its foot (mode 2).
uniform float density = 0.97;
// The underside's look (MarineMorning.deck_look()): 0 the old soft rolls, 1 stratocumulus cells -
// darker thick bases, lighter thin seams, brighter toward the sun - that read from the street.
uniform float look = 0.0;
// Its own distance fog: the scene's fog colour (linear) and a density per metre.
uniform vec3 fog_col = vec3(0.4, 0.42, 0.45);
uniform float fog_k = 0.00022;

varying vec3 wpos;
varying float bank_h;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return s;
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Distance to the nearest of a jittered point per cell (Worley F1), in cell units.
float worley(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + 0.15 + 0.7 * hash22(i + o) - f;
			d = min(d, dot(r, r));
		}
	}
	return sqrt(d);
}

// The stratocumulus underside (look 1), linear: x brightness factor on the shaded colour, y how
// thin the deck is there (0 a thick core, 1 a seam) for the sun's glow through it. `fw` metres a
// pixel spans there: every scale fades to its mean once it is under a few pixels.
vec2 strato(vec2 p, float fw) {
	// Warped so the cells are not a grid, and stretched down the wind (the rolls run east-west).
	vec2 q = p + 220.0 * (vec2(fbm(p * 0.0009), fbm(p * 0.0009 + vec2(7.3, 2.1))) - 0.5);
	float cell = worley(q * vec2(1.0 / 430.0, 1.0 / 250.0));
	float sub = worley(q * vec2(1.0 / 150.0, 1.0 / 95.0) + vec2(3.7, 1.1));
	float k_cell = 1.0 - smoothstep(30.0, 140.0, fw);
	float k_sub = 1.0 - smoothstep(12.0, 50.0, fw);
	float k_fine = 1.0 - smoothstep(4.0, 16.0, fw);
	// Seams: lighter where a cell runs out (F1 large), the core darker.
	float seam = mix(0.45, smoothstep(0.25, 0.85, cell), k_cell);
	float seam2 = mix(0.5, smoothstep(0.2, 0.8, sub), k_sub);
	float broad = fbm(vec2(p.x * 0.0011 + p.y * 0.0003, p.y * 0.0036));
	float lumps = mix(0.5, fbm(q * 0.021), k_fine);
	float thin = clamp(0.62 * seam + 0.25 * seam2 + 0.35 * (broad - 0.5) + 0.12 * (lumps - 0.5), 0.0, 1.0);
	return vec2(mix(0.74, 1.46, thin), thin);
}

// LaWeather.edge_wobble(), line for line.
float edge_wob(float z) {
	return 260.0 * sin(z * 0.0011 + 1.3) + 140.0 * sin(z * 0.0029 + 0.4);
}

// How much deck there is over true world (x, z): the edge line, softened and ragged.
float cover(vec2 w) {
	float e = edge_x + edge_wob(w.y);
	float rag = (fbm(w * 0.0021 + vec2(drift * 0.6, 0.0)) - 0.5) * edge_soft * 2.2;
	return 1.0 - smoothstep(-edge_soft, edge_soft, w.x - e + rag);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	bank_h = 0.0;
	if (mode == 2) {
		// The ribbon is laid along Z at x 0 in its own space; stand it on the edge line, and
		// billow it toward the land by height (domes along the top, bulges down the face).
		vec3 t = w + world_offset;
		float e = edge_x + edge_wob(t.z);
		// The ribbon is built DECK_TOP (520 m) tall; the bank stands `deck_top` tall.
		float h01 = clamp(VERTEX.y / 520.0, 0.0, 1.0);
		float billow = (fbm(vec2(t.z * 0.004, h01 * 3.0 + drift * 0.3)) - 0.45) * 0.5 * deck_top;
		float lean = h01 * h01 * 0.35 * deck_top;
		w.x = e - world_offset.x + billow * (0.4 + 0.6 * h01) + lean - 60.0;
		// The top edge of the bank: rounded domes along its length.
		float dome = fbm(vec2(t.z * 0.0017, 3.7)) * 0.55 + 0.6;
		w.y = h01 * deck_top * dome;
		bank_h = h01;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	}
	wpos = w;
}

void fragment() {
	// Each deck plane shows one face: the underside from below, the top from above (a camera
	// between them is inside the cloud, which the height fog draws).
	if (mode != 2 && !FRONT_FACING) {
		discard;
	}
	vec3 t = wpos + world_offset;
	vec2 tw = t.xz;
	float rim = 1.0 - smoothstep(rim_start, rim_end, length(wpos.xz - CAMERA_POSITION_WORLD.xz));
	vec3 col;
	float a;
	if (mode == 2) {
		// The bank: dense on the water, thinning and broken toward its domed top, which rolls
		// into the deck behind it.
		float n = fbm(vec2(tw.y * 0.006, t.y * 0.008 - drift * 0.5));
		float n2 = fbm(vec2(tw.y * 0.019, t.y * 0.03 + drift));
		// A rounded, fairly crisp top (the domes come from the vertex shader), not a fade.
		float top = 1.0 - smoothstep(0.78, 0.98, bank_h + (n - 0.5) * 0.22);
		float foot = smoothstep(0.0, 0.015, bank_h);
		// Solid low down where it sits on the water, broken into billows toward the top.
		float body = mix(1.0, smoothstep(0.18, 0.5, n * 0.7 + n2 * 0.5), smoothstep(0.25, 0.8, bank_h));
		a = density * top * foot * body;
		a = clamp(a, 0.0, density) * bank;
		// Lit by the low sun: the face toward the land is in the bank's own shade when the sun
		// is behind it (an evening), with a bright fringe along the top where light gets through.
		float facing = clamp(dot(normalize(vec3(1.0, 0.25, 0.0)), sun_dir) * 0.5 + 0.5, 0.0, 1.0);
		col = mix(shade_col, lit_col, facing * 0.8 + n2 * 0.2);
		// Seen against the twilight the bank is a darker mass than the sky behind it, its top
		// fringe caught by the light from the west.
		col *= 0.78;
		float behind = clamp(-sun_dir.x, 0.0, 1.0) * smoothstep(-0.25, 0.1, sun_dir.y);
		col += lit_col * behind * smoothstep(0.7, 1.0, bank_h + n2 * 0.2) * 0.9;
		col *= 0.88 + 0.24 * n2;
		col += glow_col * (1.0 - bank_h) * 0.6;
	} else {
		float c = cover(tw);
		// Stratus is even but not flat: long rolls along the wind, thicker cells between thinner.
		vec2 p = tw + vec2(drift * 40.0, drift * 11.0);
		float rolls = fbm(vec2(p.x * 0.0012 + p.y * 0.0004, p.y * 0.0042));
		float cells = fbm(p * 0.0061);
		float fine = vnoise(p * 0.027);
		float thick = clamp(rolls * 0.6 + cells * 0.4, 0.0, 1.0);
		// Thinning toward the edge breaks into holes before it goes.
		a = density * smoothstep(0.0, 0.45, c * 1.15 - (1.0 - thick) * 0.45 * (1.0 - c));
		if (mode == 0) {
			// The underside: grey, darker where the deck is thicker, in long soft rolls with finer
			// lumps between them (seen from under it, stratus is never one flat sheet).
			float lumps = fbm(p * 0.016 + vec2(0.0, drift * 2.0));
			col = shade_col * (1.26 - 0.55 * thick - 0.16 * lumps + 0.06 * fine);
			if (look > 0.5) {
				float fw = length(fwidth(tw));
				vec2 st = strato(p, fw);
				// Light coming through the deck toward the eye: brighter toward the sun, most of
				// all through the thin seams (the deck's mean brightness kept near the old one).
				vec3 view = normalize(wpos - CAMERA_POSITION_WORLD);
				float fwd = pow(clamp(dot(view, sun_dir) * 0.5 + 0.5, 0.0, 1.0), 3.0);
				col = shade_col * st.x * (0.92 + 0.1 * thick);
				col += lit_col * fwd * (0.06 + 0.14 * st.y) * clamp(sun_dir.y * 4.0 + 0.2, 0.0, 1.0);
			}
			col += glow_col * (0.75 + 0.5 * thick);
		} else {
			// The top: sunlit stratus with low relief, lit from the sun's side of each swell.
			float hgt = thick * 0.7 + cells * 0.3;
			vec2 grad = vec2(
				fbm(vec2((p.x + 40.0) * 0.0012 + p.y * 0.0004, p.y * 0.0042)) - rolls,
				fbm((p + vec2(0.0, 40.0)) * 0.0061) - cells);
			vec3 n = normalize(vec3(-grad.x * 9.0, 1.0, -grad.y * 9.0));
			float lit = clamp(dot(n, sun_dir) * 0.6 + 0.4, 0.0, 1.0);
			col = mix(shade_col, lit_col, lit) * (0.9 + 0.14 * hgt + 0.04 * fine);
		}
	}
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	// The bank stands in its own clear air on the water: half the scene's haze over it.
	// Under the new look the deck takes half the haze: the scene's fog is the low air's (the
	// morning mist with it), and seen from the street a cloud base 255 m up keeps its texture.
	float fogk = fog_k * ((mode == 2 || (mode == 0 && look > 0.5)) ? 0.45 : 1.0);
	col = mix(col, fog_col, 1.0 - exp(-dist * fogk));
	ALBEDO = cs_out(col);
	ALPHA = clamp(a * amount * rim, 0.0, 1.0);
}
