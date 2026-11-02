shader_type spatial;
// Both faces: the cage's chain-link and the tag decals are single quads, and a closed box's back
// faces never reach the screen past the depth pre-pass.
render_mode cull_disabled;

// Footbridges (FootbridgeKit): ONE material for a whole bridge - structure, deck, stairs, the
// chain-link cage, lamps and the graffiti on its fascias - so a bridge is one draw.
// What a face is rides in the vertex alpha (kind / 16, FootbridgeKit.K_*):
//   0 painted steel   COLOR.rgb the paint (sRGB): grime from below, rust weeping from joints.
//   1 concrete        COLOR.rgb a tint: form-board lines, stains, a little speckle.
//   2 galvanised      rails, posts, conduit, the cage's hoops.
//   3 chain-link      cut out of a quad, UV in metres; COLOR.rgb the wire (galvanised or vinyl).
//   4 walkway         broom-finished concrete, darker in the wheel line, wet with road_wetness.
//   5 lamp lens       lit by lamp_factor.
//   6 dark            rubber, bearings, shadow gaps.
//   7 nosing          the stairs' grit nosing strips.
//   8 tag             UV = the street wear tag atlas (4 x 4 cells), COLOR.rgb the fill.
// Colours are worked in linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

uniform sampler2D tag_atlas : filter_linear_mipmap_anisotropic, repeat_disable;
// Diamond size of the chain-link weave (metres) and its wire's share of a diamond.
uniform float diamond = 0.055;
uniform float wire = 0.085;
uniform vec3 lamp_color = vec3(1.0, 0.86, 0.66);
uniform float lamp_energy = 9.0;

varying flat float v_kind;
varying vec3 v_world;
varying vec3 v_col;

float fb_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fb_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(fb_hash(i), fb_hash(i + vec2(1.0, 0.0)), u.x),
		mix(fb_hash(i + vec2(0.0, 1.0)), fb_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fb_bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void vertex() {
	v_kind = floor(COLOR.a * 16.0 + 0.5);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR.rgb;
}

void fragment() {
	vec3 col = cs_srgb_to_linear(v_col);
	vec3 alb = col;
	float rough = 0.6;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	float wet = clamp(road_wetness, 0.0, 1.0);
	vec2 wp = v_world.xz;
	float big = fb_noise(wp * 0.35 + v_world.y * 0.2);
	if (v_kind < 0.5) {
		// Painted steel: the paint's own unevenness, road grime from below, rust weeping down from
		// the bolted joints (UV.x metres along a member, so streaks start at the panel points).
		float grime = (1.0 - smoothstep(0.0, 7.0, UV.y)) * 0.22;
		float streak = fb_noise(vec2(UV.x * 3.2, UV.y * 0.25)) * smoothstep(0.62, 0.9, fb_noise(vec2(UV.x * 0.9, 3.1)));
		alb = col * (0.9 + 0.12 * big) * (1.0 - grime);
		alb = mix(alb, vec3(0.20, 0.10, 0.05), streak * 0.45);
		rough = 0.48 + 0.2 * big + streak * 0.25;
		spec = 0.45;
	} else if (v_kind < 1.5) {
		// Concrete: horizontal form-board lines, blotches, dark stains from the drips.
		float board = smoothstep(0.02, 0.0, abs(fract(UV.y / 0.3) - 0.5) - 0.48) * 0.06;
		float spk = fb_hash(floor(wp * 40.0 + UV * 40.0)) * 0.05;
		float stain = smoothstep(0.55, 0.85, fb_noise(vec2(UV.x * 1.4, UV.y * 0.18) + 7.0)) * 0.25;
		alb = col * vec3(0.52, 0.51, 0.49) * (0.88 + 0.18 * big - board + spk) * (1.0 - stain);
		rough = 0.86;
		spec = 0.4;
	} else if (v_kind < 2.5) {
		// Galvanised: spangle and the dull spots where it has weathered.
		float spang = fb_noise(UV * 18.0 + wp);
		alb = vec3(0.50, 0.52, 0.53) * (0.82 + 0.25 * spang) * (0.9 + 0.12 * big);
		metal = 0.7;
		rough = 0.38 + 0.25 * spang;
	} else if (v_kind < 3.5) {
		// Chain-link: wires woven in diamonds, cut out; under a couple of pixels a dithered haze
		// of the weave's average cover (TAA resolves it).
		vec2 p = UV / diamond;
		vec2 d = vec2(p.x + p.y, p.x - p.y);
		vec2 f = abs(fract(d) - 0.5);
		float dist = 0.5 - max(f.x, f.y);
		float fw = max(fwidth(d.x), fwidth(d.y));
		float line = 1.0 - smoothstep(wire, wire + fw, dist);
		float avg = 1.0 - (1.0 - 2.0 * wire) * (1.0 - 2.0 * wire);
		float cover = mix(line, avg * 0.85, smoothstep(0.25, 0.7, fw));
		if (cover < fb_bayer4(FRAGCOORD.xy)) {
			discard;
		}
		alb = col * (0.78 + 0.3 * fract(d.x * 0.5));
		metal = 0.45;
		rough = 0.5;
	} else if (v_kind < 4.5) {
		// The walkway: broom finish across it, darker and smoother down the middle where the feet go,
		// joints, wet in the rain.
		float broom = fb_noise(vec2(UV.x * 0.6, UV.y * 90.0)) * 0.08;
		float wear = smoothstep(1.0, 0.0, abs(fract(UV.y) - 0.5) * 2.0) * 0.0;
		float joint = smoothstep(0.03, 0.0, abs(fract(UV.x / 3.0) - 0.5) - 0.48);
		alb = col * vec3(0.42, 0.41, 0.40) * (0.86 + 0.18 * big + broom - wear) * (1.0 - joint * 0.4);
		rough = 0.9 - wet * 0.55;
		alb *= 1.0 - wet * 0.35;
	} else if (v_kind < 5.5) {
		alb = vec3(0.85, 0.83, 0.78);
		rough = 0.25;
		emit = lamp_color * lamp_energy * clamp(lamp_factor, 0.0, 1.0);
	} else if (v_kind < 6.5) {
		alb = vec3(0.04, 0.04, 0.045);
		rough = 0.8;
	} else if (v_kind < 7.5) {
		float grit = fb_hash(floor(UV * 120.0));
		alb = vec3(0.12, 0.12, 0.11) * (0.8 + 0.4 * grit);
		metal = 0.3;
		rough = 0.85;
	} else {
		// A tag from the street wear atlas: R the fill, G its outline, B the shine.
		vec4 m = texture(tag_atlas, UV);
		float cover = 1.0 - (1.0 - m.r) * (1.0 - m.g);
		float weathered = 0.75 + 0.25 * fb_noise(wp * 3.0 + v_world.y);
		if (cover * weathered < 0.35 + 0.3 * fb_bayer4(FRAGCOORD.xy)) {
			discard;
		}
		vec3 line = vec3(0.02);
		alb = (line * m.g * (1.0 - m.r) + col * m.r) / max(cover, 0.001);
		alb = mix(alb, vec3(0.9), m.b * 0.8);
		rough = 0.62;
	}
	// Rain: everything outside darkens and shines a little.
	if (v_kind < 1.5 || v_kind > 5.5) {
		alb *= 1.0 - wet * 0.2;
		rough = mix(rough, rough * 0.55, wet);
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = cs_out(emit);
}
