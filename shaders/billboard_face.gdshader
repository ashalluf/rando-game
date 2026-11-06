shader_type spatial;
render_mode cull_back;

// The faces of the city's billboards (Billboards, scripts/world/billboards.gd): bulletins,
// posters, digital boards, supergraphics and bus-shelter lightboxes, all from ONE atlas of
// invented ads (assets/textures/billboards/billboard_ads.jpg, tools/make_billboard_art.py).
// Everything per board is instance data, so a chunk's faces of one kind are one draw:
//   INSTANCE_CUSTOM.r  ad index / 32
//   INSTANCE_CUSTOM.g  format / 4: 0 bulletin (vinyl), 1 poster (paper), 2 portrait (shelter
//                      lightbox or tower supergraphic, told apart by the mesh: a supergraphic is a
//                      unit quad scaled by its instance), 3 digital bulletin (LED slides)
//   INSTANCE_CUSTOM.b  wear seed (fade, tears, dirt)
//   INSTANCE_CUSTOM.a  1 = lit by its fixtures at night
// (all exact as half floats: Compatibility packs instance data that way.)
// UV is 0..1 across the art, v down; UV2 the face's metres from its bottom-left corner (a
// shelter's back face carries UV.x + 2 and shows the next portrait). Colours in linear on both
// renderers (color_space.gdshaderinc). Shader files use // comments.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// The fixtures' wash at night (linear emission per unit albedo at the face's foot).
uniform float lit_energy = 1.25;
// A digital board's LEDs by day and after dark (dimmed at night, as LA's rules ask).
uniform float led_day = 1.5;
uniform float led_night = 0.9;
uniform float slide_seconds = 8.0;
// A shelter lightbox by day (a little: the tubes are on) and at night.
uniform float box_day = 0.22;
uniform float box_night = 1.5;
// LED pitch in metres (a 16 mm freeway board).
uniform float led_pitch = 0.016;
// How much sun and age bleach the art (0..1, times the instance's wear).
uniform float fade_amount = 0.32;

const vec2 ATLAS = vec2(2048.0, 3072.0);

varying flat vec4 v_custom;
varying vec2 v_scale;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	// A supergraphic is a unit quad; its metres come from the instance's scale.
	v_scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 7.3) * 0.3 + vnoise(p * 4.3 + 1.7) * 0.15;
}

// The atlas rect of ad `i` in format `f` (0 bulletin, 1 poster, 2 portrait), in UV, inset by a
// texel and a half so the mips do not bleed the neighbours in.
vec4 cell(int f, int i) {
	vec2 o;
	vec2 s;
	if (f == 1) {
		o = vec2(float(i % 4) * 512.0, 1788.0 + float(i / 4) * 256.0);
		s = vec2(512.0, 256.0);
	} else if (f == 2) {
		o = vec2(float(i % 6) * 341.0, 2556.0);
		s = vec2(341.0, 512.0);
	} else {
		o = vec2(float(i % 2) * 1024.0, float(i / 2) * 298.0);
		s = vec2(1024.0, 298.0);
	}
	return vec4((o + 1.5) / ATLAS, (s - 3.0) / ATLAS);
}

vec3 art(int f, int i, vec2 uv) {
	vec4 r = cell(f, i);
	return cs_in(texture(atlas, r.xy + clamp(uv, 0.0, 1.0) * r.zw).rgb);
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Sun fade: reds and magentas go first (the inks' weakest pigments), everything toward a pale,
// slightly cyan wash.
vec3 bleach(vec3 c, float k) {
	float l = luma(c);
	vec3 faded = mix(vec3(l), c * vec3(0.78, 0.95, 1.0), 0.55) * 0.82 + vec3(0.16, 0.18, 0.19);
	return mix(c, faded, clamp(k, 0.0, 1.0));
}

void fragment() {
	int ad = int(floor(v_custom.r * 32.0 + 0.5));
	int fmt = int(floor(v_custom.g * 4.0 + 0.5));
	float wear = v_custom.b;
	bool lit = v_custom.a > 0.5;
	vec2 uv = UV;
	bool back = uv.x > 1.5;
	if (back) {
		uv.x -= 2.0;
	}
	// Metres across the face; a supergraphic's unit quad is scaled by its instance.
	bool super_q = fmt == 2 && v_scale.x > 4.0;
	vec2 m = super_q ? UV2 * v_scale : UV2;
	vec2 size = super_q ? v_scale : vec2(fmt == 1 ? 7.32 : (fmt == 2 ? 1.19 : 14.63), fmt == 1 ? 3.66 : (fmt == 2 ? 1.76 : 4.27));
	float px = max(fwidth(m.x), fwidth(m.y));
	vec3 col;
	vec3 emit = vec3(0.0);
	float rough = 0.55;
	float spec = 0.4;
	vec2 bump = vec2(0.0);
	float seed = wear * 97.0 + float(ad) * 13.1;

	if (fmt == 3) {
		// ---------------------------------------------------------------- Digital (LED) ---
		// A slide every slide_seconds, offset per board, with a short dip through black.
		float t = TIME / slide_seconds + wear * 9.0;
		int slide = (ad + int(floor(t))) % 12;
		float ph = fract(t);
		float dip = smoothstep(0.0, 0.03, ph) * smoothstep(1.0, 0.97, ph);
		vec3 pic = art(0, slide, uv);
		// The diodes: a dot grid that fades to its mean once a diode is under a couple of pixels.
		vec2 g = m / led_pitch;
		vec2 f = fract(g) - 0.5;
		float dot_mask = 1.0 - smoothstep(0.28, 0.42, length(f));
		float grid = mix(dot_mask * 2.2, 1.0, smoothstep(0.25, 0.6, px / led_pitch));
		float level = mix(led_day, led_night, lamp_factor);
		emit = pic * grid * dip * level;
		col = vec3(0.025);
		rough = 0.3;
		spec = 0.5;
	} else {
		vec2 auv = uv;
		int f = fmt;
		if (fmt == 1) {
			// --------------------------------------------------------------- Paper poster ---
			// Hung in sheets (4 x 2): each sheet a hair off register, a seam where they overlap.
			vec2 sheet = floor(uv * vec2(4.0, 2.0));
			vec2 off = (vec2(hash21(sheet + seed), hash21(sheet + seed + 3.1)) - 0.5) * vec2(0.0035, 0.006) * (0.4 + wear);
			auv = uv + off;
		}
		if (fmt == 2 && back) {
			ad = (ad + 3) % 6;
		}
		col = art(f, ad, auv);
		float age = wear;
		if (fmt == 1) {
			vec2 sp = fract(uv * vec2(4.0, 2.0));
			vec2 sd = min(sp, 1.0 - sp) * vec2(size.x / 4.0, size.y / 2.0);
			float seam = 1.0 - smoothstep(0.0, max(0.006, px * 0.7), min(sd.x, sd.y));
			col *= 1.0 - 0.18 * seam * smoothstep(0.08, 0.02, px);
			bump += vec2(sd.x < sd.y ? 1.0 : 0.0, sd.x < sd.y ? 0.0 : 1.0) * seam * 0.25;
			// A torn patch or two: the top sheet peeled off, the poster under it (or the bare
			// backing paper) showing through a ragged edge with a white fringe.
			float tears = 0.0;
			for (int k = 0; k < 2; k++) {
				float hk = hash21(vec2(seed, float(k) * 7.7));
				if (hk > 0.25 + 0.5 * (1.0 - wear)) {
					continue;
				}
				vec2 c = vec2(hash21(vec2(seed + 1.3, float(k))), hk < 0.15 ? 0.95 : hash21(vec2(seed + 2.9, float(k))) * 0.4 + 0.55);
				vec2 d = (m - c * size) / vec2(1.3 + hk * 2.0, 0.8 + hk);
				float r = length(d) + (fbm(m * 1.7 + seed) - 0.5) * 0.9;
				float under = 1.0 - smoothstep(0.92, 0.98, r);
				float fringe = smoothstep(0.85, 0.95, r) * (1.0 - smoothstep(0.98, 1.06, r));
				vec3 old = hash21(vec2(seed, 5.0 + float(k))) < 0.6 ? art(1, (ad + 5 + k) % 12, auv + vec2(0.13, 0.07)) : vec3(0.62, 0.61, 0.55) * (0.85 + 0.15 * fbm(m * 9.0));
				old = bleach(old, 0.7);
				col = mix(col, old, under);
				col = mix(col, vec3(0.78, 0.77, 0.72), fringe * 0.85);
				bump += vec2(1.0, 0.6) * fringe * 0.5;
				tears += under;
			}
			age = 0.25 + wear * 0.75;
			rough = 0.85;
			spec = 0.25;
		} else if (fmt == 0) {
			// ------------------------------------------------------------- Vinyl bulletin ---
			// One printed sheet laced to the frame: pulled into fine diagonal ripples near the
			// ends where it is ratcheted tight, a soft sheen.
			float edge = smoothstep(1.4, 0.0, min(m.x, size.x - m.x));
			float rip = sin(m.y * 13.0 + m.x * (m.x < size.x * 0.5 ? 3.0 : -3.0));
			bump.x += rip * edge * 0.35 * smoothstep(0.03, 0.01, px);
			age = wear * 0.55;
			rough = 0.38;
			spec = 0.5;
		} else if (super_q) {
			// ------------------------------------------------------ Mesh-vinyl supergraphic ---
			// Perforated (the office behind still sees out): a dot grid of holes darker than
			// the print, faded to its mean under a pixel; welded panels 1.52 m wide; a hem.
			vec2 hp = fract(m / 0.012) - 0.5;
			float hole = 1.0 - smoothstep(0.18, 0.3, length(hp));
			float holes = mix(hole, 0.22, smoothstep(0.004, 0.012, px));
			col *= 1.0 - 0.45 * holes;
			float pw = fract(m.x / 1.52);
			float weld = 1.0 - smoothstep(0.0, max(0.01, px), min(pw, 1.0 - pw) * 1.52);
			col *= 1.0 - 0.12 * weld;
			float hem = 1.0 - smoothstep(0.06, 0.06 + max(0.02, px), min(min(m.x, size.x - m.x), min(m.y, size.y - m.y)));
			col = mix(col, vec3(0.03), hem * 0.8);
			bump.x += sin(m.y * 1.1 + m.x * 0.35) * 0.08;
			age = wear * 0.6;
			rough = 0.7;
			spec = 0.3;
		} else {
			// ---------------------------------------------------- Shelter lightbox (acrylic) ---
			age = wear * 0.2;
			rough = 0.08;
			spec = 0.6;
			float lvl = mix(box_day, box_night, lamp_factor);
			// The tubes behind: a touch brighter down the middle.
			emit = col * lvl * (0.85 + 0.3 * smoothstep(0.5, 0.0, abs(uv.x - 0.5)));
		}
		col = bleach(col, age * fade_amount);
		// Grime: rain run-off streaks from the top edge, dust toward the bottom.
		if (fmt != 2 || super_q) {
			float streak = fbm(vec2(m.x * 1.8, m.y * 0.08) + seed) ;
			float run = smoothstep(0.55, 0.85, streak) * smoothstep(size.y * 0.25, size.y, m.y) * (0.3 + wear);
			col *= 1.0 - 0.22 * run;
			col *= 1.0 - 0.1 * smoothstep(size.y * 0.3, 0.0, m.y) * wear;
		}
		// Night: the fixtures along the foot throw a wash up the face, brightest just over each
		// fixture and fading toward the top.
		if (lit && fmt != 2) {
			float n_fix = fmt == 1 ? 3.0 : 5.0;
			float wash = 0.0;
			for (int k = 0; k < 5; k++) {
				if (float(k) >= n_fix) {
					break;
				}
				float fx = (float(k) + 0.5) / n_fix * size.x;
				float spread = 1.2 + m.y * 0.75;
				wash += exp(-pow((m.x - fx) / spread, 2.0)) * (1.25 - 0.6 * m.y / size.y);
			}
			wash = clamp(wash, 0.0, 1.6) * 0.8 + 0.18;
			emit += col * wash * lit_energy * lamp_factor;
		}
		// Rain wets a face a little darker and glossier.
		col *= 1.0 - 0.15 * road_wetness;
		rough = mix(rough, rough * 0.55, road_wetness);
	}
	ALBEDO = cs_out(col);
	EMISSION = cs_out(emit);
	ROUGHNESS = rough;
	SPECULAR = spec;
	NORMAL_MAP = vec3(clamp(bump * 0.5 + 0.5, 0.0, 1.0), 1.0);
	NORMAL_MAP_DEPTH = 1.0;
}
