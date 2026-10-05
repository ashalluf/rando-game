shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The rooftop kit (Rooftops / RooftopGeo): helipads, pool decks, roof gardens, mechanical
// penthouses, telecom masts and window-washing machines, one mesh per building on this one
// material. What a face is rides in the vertex colour's alpha (kind / 32, K_* below), its paint
// in the rgb as written (sRGB: vertex colours arrive raw on both renderers), UV is metres in the
// face's plane and UV2 a feature parameter (a pad's deck size, a pool's half size). Works in
// linear on both renderers (color_space.gdshaderinc).
//
// Shader includes and shaders use // comments, never ##.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float night_factor;
global uniform vec4 sky_tint;
global uniform vec3 sun_direction;

const int K_PAINT = 0;
const int K_STEEL = 1;
const int K_CONCRETE = 2;
const int K_PAD = 3;
const int K_NET = 4;
const int K_LAMP = 5;
const int K_WATER = 6;
const int K_WOOD = 7;
const int K_CANVAS = 8;
const int K_TILE = 9;
const int K_BULB = 10;
const int K_SIGN = 11;
const int K_LOUVRE = 12;
const int K_LAWN = 13;
const int K_SOIL = 14;
const int K_WINDSOCK = 15;
const int K_GRATING = 16;
const int K_BEACON = 17;
const int K_CUSHION = 18;
const int K_FOLIAGE = 19;
const int K_DISH = 20;

// The pool: how deep the traced tank is (metres), its water's absorption per metre (linear rgb),
// the tile and the night light under the water.
uniform float pool_depth = 1.45;
uniform vec3 pool_absorb = vec3(0.55, 0.10, 0.065);
uniform vec3 pool_tile = vec3(0.70, 0.80, 0.82);
uniform vec3 pool_night = vec3(0.10, 0.55, 0.62);
uniform float pool_night_energy = 2.2;
// Lamps (perimeter lights, string bulbs, lit signs): their glow after dark and the day level.
uniform float lamp_energy = 5.0;
uniform float lamp_day = 0.12;
uniform float sign_energy = 3.2;

varying vec3 lpos;
varying vec3 lnorm;
varying vec3 lcam;
varying flat int kind;
varying vec3 paint;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
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
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.7) * 0.15;
}

// A line of width w at distance d, antialiased over the pixel footprint aa.
float line_mask(float d, float w, float aa) {
	return 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, abs(d));
}

// The helipad's paint at p (metres from its centre), deck size s: the white perimeter of the
// touchdown area, the yellow touchdown circle, the white H, scuffs. Returns rgb paint over the
// deck and how much paint is there (a).
vec4 pad_marks(vec2 p, float s, float aa) {
	float half_s = s * 0.5;
	vec2 ap = abs(p);
	vec4 o = vec4(0.0);
	// Perimeter line, 0.3 m, half a metre in from the deck edge.
	float edge = max(ap.x, ap.y) - (half_s - 0.65);
	float m = line_mask(edge, 0.30, aa);
	// Dashed aiming line inside it (a FATO-style dash), 1.2 m on, 0.9 m off.
	float edge2 = max(ap.x, ap.y) - (half_s - 1.35);
	float along = ap.x > ap.y ? p.y : p.x;
	float dash = step(fract(along / 2.1 + 0.25), 0.57);
	float m2 = line_mask(edge2, 0.15, aa) * dash;
	vec3 white = vec3(0.86, 0.86, 0.84);
	vec3 yellow = vec3(0.86, 0.62, 0.06);
	o = mix(o, vec4(white, 1.0), max(m, m2 * 0.9));
	// Touchdown circle.
	float r = length(p);
	float ring_r = s * 0.31;
	o = mix(o, vec4(yellow, 1.0), line_mask(r - ring_r, max(s * 0.026, 0.35), aa));
	// The H, a third of the deck tall.
	float hh = s * 0.17;
	float hw = hh * 0.6;
	float bar = hh * 0.16;
	float legs = step(ap.y, hh) * (line_mask(ap.x - hw, bar * 2.0, aa));
	float cross = step(ap.x, hw) * line_mask(p.y, bar * 2.0, aa);
	float hmask = clamp(max(legs, cross), 0.0, 1.0);
	// Antialias the H's ends too.
	hmask *= 1.0 - smoothstep(hh - aa, hh + aa, ap.y);
	o = mix(o, vec4(white, 1.0), hmask);
	// Little weight box in the circle's lower right quarter: a white square outline.
	vec2 wb = p - vec2(s * 0.17, s * 0.2);
	float wbox = line_mask(max(abs(wb.x), abs(wb.y)) - s * 0.035, 0.08, aa);
	o = mix(o, vec4(white, 1.0), wbox * 0.9);
	return o;
}

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
	mat4 inv_model = inverse(MODEL_MATRIX);
	lcam = (inv_model * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	kind = int(COLOR.a * 32.0 + 0.5);
	paint = cs_srgb_to_linear(COLOR.rgb);
}

void fragment() {
	vec3 col = paint;
	float rough = 0.7;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	vec3 nm = normalize(lnorm);
	bool set_normal = false;
	vec2 fw = fwidth(UV);
	float aa = max(max(fw.x, fw.y), 0.004);
	vec3 view_l = normalize(lpos - lcam);
	float grime = fbm(lpos.xz * 0.35 + lpos.y * 0.2);

	if (kind == K_STEEL) {
		col *= 0.9 + 0.2 * grime;
		rough = 0.45 + 0.2 * grime;
		metal = 0.55;
	} else if (kind == K_CONCRETE) {
		col *= 0.82 + 0.3 * fbm(UV * 1.7) ;
		// Streaks down vertical faces.
		if (abs(nm.y) < 0.5) {
			col *= 1.0 - 0.18 * smoothstep(0.55, 0.9, vnoise(vec2(UV.x * 3.0, UV.y * 0.15)));
		}
		rough = 0.9;
	} else if (kind == K_PAD) {
		// The deck's non-slip coat: aggregate speckle, a darker worn patch where the skids sit,
		// tyre and skid scuffs, and the markings over it.
		float s = UV2.x;
		vec2 p = UV;
		float speck = h21(floor(p * 40.0));
		float speck_fade = 1.0 - smoothstep(0.01, 0.05, aa);
		col *= 0.9 + 0.12 * fbm(p * 0.6) + (speck - 0.5) * 0.12 * speck_fade;
		float r = length(p);
		col *= 1.0 - 0.18 * smoothstep(s * 0.28, 0.0, r) * fbm(p * 1.3 + 4.0);
		// Oil under where the aircraft stands.
		col *= 1.0 - 0.25 * smoothstep(1.6, 0.0, length(p - vec2(0.3, -0.4)) + 0.8 * vnoise(p * 2.0));
		vec4 m = pad_marks(p, s, aa * 1.2);
		// Paint worn thin in patches.
		float wear = smoothstep(0.35, 0.75, fbm(p * 1.9 + 11.0));
		col = mix(col, cs_srgb_to_linear(m.rgb), m.a * (1.0 - 0.45 * wear));
		rough = mix(0.82, 0.6, m.a);
		// The pad's floods wash the deck after dark.
		emit = col * 0.12 * lamp_factor;
	} else if (kind == K_NET) {
		// Knotted safety netting on a 10 cm diamond mesh; under a pixel it is its coverage,
		// dithered, so a net seen from across the street is a grey haze and not moire.
		vec2 q = vec2(UV.x + UV.y, UV.x - UV.y) * (1.0 / 0.1);
		vec2 g = abs(fract(q) - 0.5);
		float strand = 0.11;
		float on = step(0.5 - strand, max(g.x, g.y));
		float px = aa / 0.1;
		float cover = 1.0 - (1.0 - 2.0 * strand) * (1.0 - 2.0 * strand);
		float dither = h21(FRAGCOORD.xy + fract(TIME) * 0.0);
		float keep = mix(on, step(dither, cover), smoothstep(0.15, 0.45, px));
		if (keep < 0.5) {
			discard;
		}
		col *= 0.8;
		rough = 0.9;
	} else if (kind == K_LAMP) {
		// A perimeter or flood light: its colour glowing after dark, a lens by day.
		col = mix(vec3(0.25), col, 0.4);
		emit = paint * (lamp_day + lamp_energy * lamp_factor);
		rough = 0.25;
	} else if (kind == K_BEACON) {
		col = vec3(0.06);
		float pulse = 0.55 + 0.45 * sin(TIME * 3.1);
		emit = vec3(1.0, 0.12, 0.06) * (0.6 + 5.0 * night_factor * pulse);
	} else if (kind == K_WATER) {
		// A pool traced to its tiled floor and walls: the view ray refracted at the surface, run
		// down to whichever it meets first, the tile there absorbed by the water on the way. The
		// sky is emitted by Fresnel (the renderer adds the sun's glint), and after dark the
		// underwater lights fill it.
		vec2 hs = max(UV2, vec2(0.5));
		vec2 p = UV;
		float t = TIME;
		vec2 w1 = vec2(vnoise(p * 1.7 + vec2(t * 0.35, t * 0.21)), vnoise(p * 1.7 + vec2(4.0 - t * 0.27, 9.0 + t * 0.31)));
		vec2 w2 = vec2(vnoise(p * 4.3 + vec2(-t * 0.6, t * 0.5)), vnoise(p * 4.3 + vec2(2.0 + t * 0.55, 5.0 - t * 0.4)));
		vec2 slope = (w1 - 0.5) * 0.10 + (w2 - 0.5) * 0.05;
		nm = normalize(vec3(-slope.x, 1.0, -slope.y));
		set_normal = true;
		vec3 rd = refract(view_l, nm, 1.0 / 1.333);
		rd.y = min(rd.y, -0.05);
		float tf = pool_depth / -rd.y;
		float tx = rd.x > 0.0 ? (hs.x - p.x) / rd.x : (rd.x < 0.0 ? (-hs.x - p.x) / rd.x : 1e5);
		float tz = rd.z > 0.0 ? (hs.y - p.y) / rd.z : (rd.z < 0.0 ? (-hs.y - p.y) / rd.z : 1e5);
		float th = max(min(min(tf, tx), tz), 0.0);
		vec3 hit = vec3(p.x, 0.0, p.y) + rd * th;
		vec2 tuv;
		bool floor_hit = th >= tf - 0.001;
		if (floor_hit) {
			tuv = hit.xz;
		} else if (th >= tx - 0.001) {
			tuv = vec2(hit.z, hit.y);
		} else {
			tuv = vec2(hit.x, hit.y);
		}
		// Tile grout (12 cm mosaic), the lane lines on the floor, the dark band at the wall top.
		float pxl = aa * (1.0 + th);
		vec2 tg = abs(fract(tuv / 0.12) - 0.5);
		float grout = (1.0 - smoothstep(0.42, 0.47, max(tg.x, tg.y))) ;
		grout = mix(grout, 0.85, smoothstep(0.02, 0.06, pxl));
		vec3 tile = pool_tile * mix(0.72, 1.0, grout);
		if (floor_hit) {
			float lane_w = 0.25;
			float lanes = line_mask(abs(hit.z) - 0.0, lane_w, pxl) * step(abs(hit.x), hs.x - 1.2);
			tile = mix(tile, vec3(0.03, 0.06, 0.16), lanes);
			// Caustics: a moving net of light on the floor in sun.
			vec2 cq = hit.xz * 1.6 + vec2(t * 0.25, t * 0.18);
			float cn = abs(vnoise(cq) - vnoise(cq * 1.3 + 3.0));
			float caus = pow(1.0 - clamp(cn * 2.2, 0.0, 1.0), 6.0);
			tile *= 1.0 + caus * 1.4 * (1.0 - night_factor) * smoothstep(0.0, 0.3, sun_direction.y);
		} else {
			tile = mix(tile, vec3(0.04, 0.12, 0.2), step(-0.18, hit.y));
		}
		float path = th + 0.25;
		vec3 trans = exp(-pool_absorb * path);
		col = tile * trans;
		// The water itself, scattering a little turquoise back.
		col += vec3(0.0, 0.05, 0.06) * (1.0 - trans.g);
		float fres = 0.02 + 0.98 * pow(1.0 - clamp(-dot(view_l, nm), 0.0, 1.0), 5.0);
		vec3 sky = cs_in(sky_tint.rgb);
		col *= 1.0 - fres;
		emit = sky * fres * 0.9;
		// Underwater lights after dark: the tank lit from its walls.
		float wall_d = min(hs.x - abs(hit.x), hs.y - abs(hit.z));
		emit += pool_night * pool_night_energy * lamp_factor * trans * (0.55 + 0.45 * exp(-wall_d * 0.6)) * (1.0 - fres);
		rough = 0.04;
		spec = 0.5;
	} else if (kind == K_WOOD) {
		// Hardwood decking: boards along UV.x, 14 cm, with gaps, grain and a silvered weathering.
		float board = floor(UV.y / 0.145);
		float gap = smoothstep(0.0, 0.08, fract(UV.y / 0.145)) * smoothstep(1.0, 0.92, fract(UV.y / 0.145));
		gap = mix(gap, 0.85, smoothstep(0.01, 0.04, aa));
		float grain = vnoise(vec2(UV.x * 0.8 + board * 17.0, UV.y * 30.0));
		col *= (0.78 + 0.3 * h21(vec2(board, 3.0))) * (0.85 + 0.25 * grain) * mix(0.35, 1.0, gap);
		col = mix(col, vec3(0.32, 0.31, 0.29), 0.25 * fbm(UV * 0.4));
		rough = 0.75;
	} else if (kind == K_TILE) {
		// Pavers on pedestals, 60 cm, a tone each.
		vec2 cell = floor(UV / 0.6);
		vec2 g = abs(fract(UV / 0.6) - 0.5);
		float joint = smoothstep(0.47, 0.49, max(g.x, g.y));
		joint *= 1.0 - smoothstep(0.01, 0.04, aa);
		col *= (0.88 + 0.18 * h21(cell)) * (1.0 - 0.55 * joint) * (0.92 + 0.12 * fbm(UV * 3.0));
		rough = 0.82;
	} else if (kind == K_CANVAS || kind == K_CUSHION) {
		float weave = (vnoise(UV * 60.0) - 0.5) * (1.0 - smoothstep(0.003, 0.02, aa));
		col *= 0.95 + weave * 0.15 + 0.08 * fbm(UV * 2.0);
		rough = 0.9;
		BACKLIGHT = cs_out(col * (kind == K_CANVAS ? 0.35 : 0.0));
	} else if (kind == K_BULB) {
		col = vec3(0.30, 0.29, 0.26);
		emit = vec3(1.0, 0.62, 0.28) * (0.03 + lamp_energy * 1.6 * lamp_factor);
		rough = 0.2;
	} else if (kind == K_SIGN) {
		emit = paint * sign_energy * lamp_factor;
		col = mix(col, col * 0.6, lamp_factor);
		rough = 0.4;
	} else if (kind == K_LOUVRE) {
		// Louvred screen: 15 cm blades tilted down, dark between, the blade lit from above.
		float f = fract(UV.y / 0.15);
		float blade = smoothstep(0.0, 0.12, f) * smoothstep(1.0, 0.75, f);
		float fade = smoothstep(0.01, 0.05, aa);
		blade = mix(blade, 0.62, fade);
		col *= mix(0.18, 1.0, blade) * (0.92 + 0.12 * grime);
		if (abs(nm.y) < 0.5 && fade < 0.99) {
			vec3 down_tilt = vec3(0.0, -(f - 0.45) * 1.4, 0.0) * (1.0 - fade);
			nm = normalize(nm + down_tilt);
			set_normal = true;
		}
		rough = 0.55;
		metal = 0.35;
	} else if (kind == K_LAWN) {
		// Turf: mower stripes a metre wide, dry patches, blades up close.
		float n1 = fbm(UV * 1.3);
		float blades = (vnoise(UV * 80.0) - 0.5) * (1.0 - smoothstep(0.004, 0.02, aa));
		float stripe = step(0.5, fract(UV.x / 1.8)) * 0.08;
		col *= 0.74 + 0.32 * n1 + blades * 0.3 + stripe;
		col = mix(col, vec3(0.20, 0.17, 0.08), 0.35 * smoothstep(0.62, 0.85, fbm(UV * 0.7 + 5.0)));
		rough = 0.95;
		spec = 0.3;
	} else if (kind == K_SOIL) {
		col *= 0.75 + 0.45 * vnoise(UV * 9.0) + 0.2 * fbm(UV * 2.0);
		rough = 1.0;
		spec = 0.2;
	} else if (kind == K_FOLIAGE) {
		float lump = fbm(UV * 3.0 + lpos.y);
		col *= 0.55 + 0.75 * lump;
		rough = 0.85;
		spec = 0.3;
		BACKLIGHT = cs_out(col * 0.4);
	} else if (kind == K_WINDSOCK) {
		// Five bands, orange and white, from the hoop to the tail; faded nylon.
		float band = floor(clamp(UV.y / 0.48, 0.0, 4.99));
		col = mod(band, 2.0) < 0.5 ? vec3(0.85, 0.18, 0.02) : vec3(0.78, 0.78, 0.74);
		col *= 0.92 + 0.1 * vnoise(UV * 6.0);
		rough = 0.85;
		emit = col * 0.25 * lamp_factor;
		BACKLIGHT = cs_out(col * 0.5);
	} else if (kind == K_GRATING) {
		// Bar grating: 3 cm pitch, dark between the bars.
		vec2 g = fract(UV / vec2(0.033, 0.1));
		float bar = step(0.62, g.x) + step(0.92, g.y);
		bar = mix(clamp(bar, 0.0, 1.0), 0.45, smoothstep(0.004, 0.02, aa));
		col *= mix(0.15, 1.0, bar);
		rough = 0.5;
		metal = 0.6;
	} else if (kind == K_DISH) {
		col *= 0.95 + 0.08 * grime;
		rough = 0.5;
	} else {
		// Paint.
		col *= 0.93 + 0.12 * grime;
		rough = 0.6;
	}

	if (set_normal) {
		NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(nm, 0.0))).xyz);
	}
	ALBEDO = cs_out(col);
	EMISSION = cs_out(emit);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
}
