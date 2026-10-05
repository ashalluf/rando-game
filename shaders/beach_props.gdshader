shader_type spatial;
render_mode cull_back;

// The beach (scripts/world/beach_life.gd): towels, umbrellas, low chairs, coolers, bags, boards,
// the volleyball net and court tapes, the lifeguard tower, the bike path and the cruisers baked
// with their riders. One material for all of it, so each kind is one MultiMesh draw a chunk.
//
// * Vertex colour alpha says what a face is (BeachLife.A_*, round(alpha * 20)): 0 the vertex
//   colour is the colour; 1 the instance's paint (INSTANCE_CUSTOM.rgb); 2 a towel or a chair's
//   sling (bold stripes across it in the paint and CANVAS2[INSTANCE_CUSTOM.a * 8], terry); 3 an
//   umbrella's canvas (panels round the pole, the same two colours); 4 the volleyball net (cut
//   out); 5 the ball's panels; 6 a board (deck in the paint, a stringer, a rail band); 7 the bike
//   path's concrete (joints, the yellow centre line, sand blown over its edges); 9 dark glass;
//   10 the court's tape.
// * UV2 is (roughness, metallic) per part. UV is metres on solid parts; on the path it is
//   (metres along it, metres across from its centre line).
// * Colour space: vertex colours and instance data arrive raw on both renderers and are authored
//   sRGB; everything is worked in linear and handed over with cs_out() (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

// BeachLife.CANVAS2, sRGB.
const vec3 CANVAS2[6] = vec3[](vec3(0.97, 0.96, 0.92), vec3(0.98, 0.84, 0.25), vec3(0.1, 0.32, 0.6),
	vec3(0.9, 0.2, 0.2), vec3(0.2, 0.62, 0.55), vec3(0.99, 0.62, 0.7));
// The sand's colour (sRGB) where it has blown over the path and dusts the bottom of things.
uniform vec3 sand_tint = vec3(0.80, 0.71, 0.56);
// The path's expansion joints (m) and its centre line's dash and gap (m).
uniform float joint_spacing = 3.0;
uniform vec2 centre_dash = vec2(3.0, 3.0);
// How strong the terry and canvas weaves are.
uniform float weave = 0.1;

varying vec3 v_local;
varying float v_mode;
varying vec3 v_paint;
varying vec3 v_paint2;
varying float v_seed;

float bp_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float bp_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bp_hash(i), bp_hash(i + vec2(1.0, 0.0)), f.x),
		mix(bp_hash(i + vec2(0.0, 1.0)), bp_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_local = VERTEX;
	v_mode = COLOR.a;
	v_paint = INSTANCE_CUSTOM.rgb;
	v_seed = INSTANCE_CUSTOM.a;
	v_paint2 = CANVAS2[clamp(int(INSTANCE_CUSTOM.a * 8.0 + 0.5), 0, 5)];
}

void fragment() {
	int code = int(round(v_mode * 20.0));
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float rough = UV2.x;
	float metal = UV2.y;
	vec3 c1 = cs_srgb_to_linear(v_paint);
	vec3 c2 = cs_srgb_to_linear(v_paint2);
	vec3 sand = cs_srgb_to_linear(sand_tint);
	vec3 backlight = vec3(0.0);
	if (code == 1) {
		base = c1 * (0.94 + 0.08 * bp_noise(v_local.xz * 9.0 + v_seed * 17.0));
	} else if (code == 2) {
		// Bold stripes across the towel (its long side is local x), a border band, the pile.
		float u = v_local.x;
		float fw = max(fwidth(u) * 6.0, 1e-4);
		float pattern = floor(fract(v_seed * 7.3) * 3.0);
		float s;
		if (pattern < 0.5) {
			s = smoothstep(0.5 - fw, 0.5 + fw, abs(fract(u * 3.0) - 0.5) * 2.0);
		} else if (pattern < 1.5) {
			s = smoothstep(0.35 - fw, 0.35 + fw, abs(fract(u * 1.2 + 0.25) - 0.5) * 2.0);
		} else {
			// A wide centre panel with a border.
			s = 1.0 - step(abs(u), 0.62) * step(abs(v_local.z), 0.3);
		}
		base = mix(c1, c2, s);
		float pile = bp_noise(v_local.xz * 180.0);
		base *= 1.0 - weave + 2.0 * weave * mix(pile, 0.5, smoothstep(0.002, 0.01, fwidth(v_local.x)));
		rough = 0.96;
	} else if (code == 3) {
		float a = atan(v_local.z, v_local.x);
		float panel = floor((a + 3.14159265) / 6.2831853 * 8.0 + 0.5);
		base = mod(panel, 2.0) < 0.5 ? c1 : c2;
		base *= 0.95 + 0.08 * bp_noise(UV * 120.0);
		// Sun-bleached toward the top.
		base = mix(base, vec3(dot(base, vec3(0.33))), 0.1 * smoothstep(1.9, 2.3, v_local.y));
		rough = 0.85;
		backlight = base * 0.6;
	} else if (code == 4) {
		// The net: 10 cm squares of cord, cut out; a solid grey once a square is under a pixel.
		vec2 g = fract(UV / 0.1);
		vec2 d = min(g, 1.0 - g);
		float px = max(fwidth(UV.x), fwidth(UV.y)) / 0.1;
		float cord = 1.0 - smoothstep(0.06, 0.06 + px * 1.5, min(d.x, d.y));
		float keep = mix(cord, 0.35, smoothstep(0.08, 0.3, px));
		if (keep < 0.5 && px < 0.3) {
			discard;
		}
		rough = 0.9;
	} else if (code == 5) {
		// A beach volleyball: white with yellow and blue panels.
		vec3 n = normalize(v_local);
		float k = atan(n.z, n.x) * 1.909 + n.y * 2.0;
		float band = fract(k);
		base = band < 0.33 ? vec3(0.95, 0.94, 0.9) : (band < 0.66 ? vec3(0.95, 0.8, 0.1) : vec3(0.08, 0.3, 0.75));
		base = cs_srgb_to_linear(base);
		rough = 0.45;
	} else if (code == 6) {
		// A board: the deck in the paint, a darker rail band, the wooden stringer down the middle,
		// wax on the deck where it is ridden.
		base = c1;
		float rail = smoothstep(0.035, 0.03, v_local.y) * step(0.008, v_local.y);
		base = mix(base, base * 0.75, rail);
		float stringer = (1.0 - smoothstep(0.004, 0.008, abs(v_local.z))) * step(0.03, v_local.y);
		base = mix(base, cs_srgb_to_linear(vec3(0.62, 0.45, 0.28)), stringer);
		float wax = bp_noise(v_local.xz * 40.0) * step(0.03, v_local.y);
		base *= 0.92 + 0.12 * wax;
		rough = 0.28 + 0.3 * wax;
	} else if (code == 7) {
		// The path: broom-finished concrete in slabs, the yellow centre line, sand drifting over
		// its edges and in the joints.
		float along = UV.x;
		float across = UV.y;
		vec3 conc = base * (0.9 + 0.12 * bp_noise(vec2(along, across) * 3.0) + 0.05 * bp_noise(vec2(along, across) * 23.0));
		float fw = max(fwidth(along), 1e-4);
		float joint = 1.0 - smoothstep(0.004, 0.012 + fw, abs(fract(along / joint_spacing + 0.5) - 0.5) * joint_spacing);
		conc *= 1.0 - 0.35 * joint;
		float dash = step(fract(along / (centre_dash.x + centre_dash.y)), centre_dash.x / (centre_dash.x + centre_dash.y));
		float line = (1.0 - smoothstep(0.05, 0.05 + fwidth(across) * 1.5, abs(across))) * dash;
		conc = mix(conc, cs_srgb_to_linear(vec3(0.9, 0.72, 0.15)) * (0.85 + 0.15 * bp_noise(vec2(along * 8.0, across * 40.0))), line * 0.92);
		float edge = smoothstep(1.2, 1.9, abs(across) + 0.35 * bp_noise(vec2(along * 0.7, across)));
		float drift = clamp(edge + 0.5 * joint * bp_noise(vec2(along * 4.0, 0.0)) + 0.25 * smoothstep(0.7, 0.95, bp_noise(vec2(along * 0.25, across * 0.6))), 0.0, 1.0);
		base = mix(conc, sand, drift);
		rough = 0.88;
	} else if (code == 9) {
		rough = 0.08;
		metal = 0.0;
	} else if (code == 10) {
		rough = 0.6;
	}
	// Sand dust on whatever stands in it.
	if (code != 7 && code != 4) {
		float low = 1.0 - smoothstep(0.0, 0.12, v_local.y);
		base = mix(base, sand, low * 0.35 * bp_noise(v_local.xz * 6.0 + 1.3));
	}
	ALBEDO = cs_out(base);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = code == 9 ? 0.6 : 0.5;
	if (code == 3) {
		BACKLIGHT = cs_out(backlight);
	}
}
