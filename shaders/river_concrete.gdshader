shader_type spatial;
render_mode cull_back;

// The Los Angeles River's concrete (RiverBuild, RiverBridges): the channel's banks and bed, the
// low-flow notch, the coping, the ramps' walls, the outfalls' headwalls, and the bridges' cast
// concrete. ONE material a chunk; what a face is rides in COLOR.r (kind / 8, see below), which
// bank it is in COLOR.g (0 west, 1 east), UV is metres in the surface's own frame (UV.x down the
// river - s - on the channel, along the member on a bridge; UV.y down the slope from the top edge
// on a bank, across on the bed, up on a wall), UV2.x the height over the bed's edge (the tide line,
// the algae) and UV2.y metres from the centre line (the bed's algae by the low flow).
//
// Kinds:  0 bank slope   1 bed   2 low-flow notch   3 coping and kerbs   4 walls (ramps,
//         headwalls)   5 bridge concrete   6 piers   7 dark (pipe and culvert mouths)
//
// What it paints, all from the coordinates (no decals, no extra draws): the form-panel and
// construction joints, the weathering streaks run down the slope, the tide line and the algae at
// the foot, white efflorescence under the joints, the drain outfalls' rust and wet trails (the
// same slots LaRiver.outfall_at() puts the pipes in: ihash() is the script's arithmetic), and
// graffiti - original throw-ups, handstyles and roller letters from the street wear atlas, with
// grey buff patches over older ones. Works on both renderers (color_space.gdshaderinc).

global uniform float road_wetness;
global uniform float ground_detail;

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tag_atlas : filter_linear_mipmap, repeat_disable;

// LINEAR albedos. The channel's concrete reads pale and warm in the sun, the bridges paler still.
uniform vec3 bank_color = vec3(0.190, 0.180, 0.160);
uniform vec3 bed_color = vec3(0.150, 0.142, 0.126);
uniform vec3 bridge_color = vec3(0.300, 0.285, 0.255);
uniform vec3 stain_color = vec3(0.07, 0.065, 0.055);
uniform vec3 algae_color = vec3(0.035, 0.050, 0.020);
uniform vec3 rust_color = vec3(0.22, 0.10, 0.04);
uniform vec3 efflor_color = vec3(0.42, 0.41, 0.39);
// Joint pitches (metres): panels along the channel, the construction lifts down a bank.
uniform float panel_pitch = 9.2;
uniform float lift_pitch = 3.4;
// Outfall slots (LaRiver.OUTFALL_PITCH / OUTFALL_ODDS) and where the pipe stands down the bank.
uniform float outfall_pitch = 46.0;
uniform float outfall_odds = 0.42;
uniform float outfall_v = 1.8;
// Graffiti: one piece slot every `tag_pitch` metres a bank, taken at `tag_odds`.
uniform float tag_pitch = 15.0;
uniform float tag_odds = 0.72;
uniform float tag_strength = 0.95;

varying vec4 v_kind;
varying vec2 v_uv2;

uint ihash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float ihash01(uint x) {
	return float(ihash(x) & 0xFFFFFFu) / 16777216.0;
}

float rc_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float rc_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(rc_hash(i), rc_hash(i + vec2(1.0, 0.0)), f.x),
		mix(rc_hash(i + vec2(0.0, 1.0)), rc_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float rc_fbm(vec2 p) {
	return rc_noise(p) * 0.5 + rc_noise(p * 2.07 + 3.1) * 0.3 + rc_noise(p * 4.3 + 7.7) * 0.2;
}

// A joint line every `pitch` along `x`: 1 on the joint, falling off over `w` metres, faded out as
// the pixel grows past it (`px` metres a pixel).
float joint(float x, float pitch, float w, float px) {
	float d = abs(fract(x / pitch + 0.5) - 0.5) * pitch;
	float a = 1.0 - smoothstep(w, w + px * 1.5, d);
	return a * (1.0 - smoothstep(0.08, 0.3, px));
}

const vec3 PAINTS[10] = vec3[](
	vec3(0.70, 0.70, 0.66), vec3(0.04, 0.04, 0.045), vec3(0.62, 0.08, 0.05), vec3(0.06, 0.18, 0.55),
	vec3(0.75, 0.55, 0.06), vec3(0.08, 0.40, 0.18), vec3(0.55, 0.12, 0.45), vec3(0.85, 0.30, 0.05),
	vec3(0.30, 0.62, 0.78), vec3(0.62, 0.62, 0.62)
);

void vertex() {
	v_kind = COLOR;
	v_uv2 = UV2;
}

void fragment() {
	int kind = int(floor(v_kind.r * 8.0));
	float side = v_kind.g;
	vec2 uv = UV;
	float height = v_uv2.x;
	float lateral = v_uv2.y;
	float px = max(length(dFdx(uv)), length(dFdy(uv)));

	vec3 tex = cs_in(texture(concrete_tex, uv * 0.3).rgb);
	float tex_l = dot(tex, vec3(0.299, 0.587, 0.114));
	// The texture as relief on the base colour, its own mean taken out.
	float detail = clamp(tex_l / 0.36, 0.78, 1.22);
	vec3 base = bank_color;
	if (kind == 1 || kind == 2) {
		base = bed_color;
	} else if (kind == 5 || kind == 6) {
		base = bridge_color;
	} else if (kind == 3 || kind == 4) {
		base = mix(bank_color, bridge_color, 0.4);
	}
	// Large-scale tone: pours and patches never matched.
	float pour = rc_noise(uv * vec2(0.035, 0.09) + side * 17.0);
	base *= 0.86 + 0.26 * pour;
	vec3 col = base * detail;
	float rough = 0.86;
	float dark = 0.0;

	if (kind == 0) {
		// Form panels along the river and lifts down the bank.
		float j = max(joint(uv.x, panel_pitch, 0.012, px), joint(uv.y, lift_pitch, 0.01, px) * 0.8);
		col *= 1.0 - 0.28 * j;
		// Efflorescence weeping out of the lift joints, a little way down the slope.
		float lj = fract(uv.y / lift_pitch);
		float weep = smoothstep(0.0, 0.03, lj) * (1.0 - smoothstep(0.03, 0.22, lj)) * smoothstep(0.55, 0.8, rc_noise(vec2(uv.x * 0.7, floor(uv.y / lift_pitch))));
		col = mix(col, efflor_color * detail, weep * 0.45);
		// Streaks down the slope: long in v, narrow in s.
		float streak = rc_fbm(vec2(uv.x * 1.3, uv.y * 0.07 + side * 9.0));
		col *= 1.0 - 0.42 * smoothstep(0.42, 0.85, streak) * smoothstep(0.0, 2.0, uv.y);
		// Old water lines in bands across the lower bank, and broad grime patches.
		float band = smoothstep(0.55, 0.9, rc_noise(vec2(uv.x * 0.05, height * 3.2)));
		col *= 1.0 - 0.18 * band * (1.0 - smoothstep(1.5, 3.5, height));
		col *= 1.0 - 0.22 * smoothstep(0.5, 0.85, rc_fbm(uv * vec2(0.04, 0.12) + 11.0));
		// The tide line and the dark wet band under it; the algae at the toe.
		float tide = smoothstep(0.7, 1.0, height) * (1.0 - smoothstep(1.2, 1.6, height + 0.25 * rc_noise(uv * vec2(0.3, 1.0))));
		dark = max(dark, tide * 0.35);
		float low = 1.0 - smoothstep(0.0, 0.75, height + 0.25 * rc_noise(uv * 0.8));
		col = mix(col, algae_color * (0.8 + 0.6 * detail), low * 0.75);
	} else if (kind == 1) {
		float j = max(joint(uv.x, panel_pitch, 0.015, px), joint(uv.y + 0.5, 6.0, 0.012, px) * 0.6);
		col *= 1.0 - 0.22 * j;
		// Old water stains in broad blotches, silt washed into fans, the dark wet margin by the
		// low-flow notch with algae in long streaks down the current.
		float blot = rc_fbm(uv * vec2(0.025, 0.06) + 2.0);
		col *= 1.0 - 0.38 * smoothstep(0.45, 0.8, blot);
		float silt = rc_fbm(uv * vec2(0.05, 0.22) + 5.0);
		col = mix(col, vec3(0.12, 0.10, 0.072) * detail, smoothstep(0.5, 0.85, silt) * 0.65);
		float reach = 1.8 + 3.5 * rc_noise(vec2(uv.x * 0.03, 3.0));
		float wet = 1.0 - smoothstep(0.2, reach, lateral - 4.0 + 0.8 * rc_noise(uv * 0.4));
		float strand = smoothstep(0.45, 0.8, rc_noise(vec2(uv.x * 0.08, uv.y * 2.2)));
		col = mix(col, algae_color * (0.8 + 0.6 * detail), wet * (0.55 + 0.35 * strand));
		dark = max(dark, wet * 0.3);
		// Tyre tracks: the channel is a road for the maintenance trucks (and for chases).
		float track = rc_noise(vec2(uv.x * 0.04, uv.y * 1.6)) * smoothstep(0.3, 0.0, abs(fract(lateral / 9.0) - 0.5) - 0.35);
		col *= 1.0 - 0.15 * track;
		rough = 0.88;
	} else if (kind == 2) {
		// The notch: wet, slimy and green.
		col = mix(col * 0.5, algae_color * (0.6 + 0.6 * detail), 0.85);
		rough = 0.3;
		dark = 0.3;
	} else if (kind == 3) {
		col *= 1.0 - 0.3 * joint(uv.x, 3.05, 0.01, px);
	} else if (kind == 4) {
		col *= 1.0 - 0.35 * joint(uv.x, 4.0, 0.012, px);
		col *= 1.0 - 0.25 * smoothstep(0.5, 0.9, rc_fbm(vec2(uv.x * 1.5, uv.y * 0.1)));
	} else if (kind == 5) {
		// Board-formed cast concrete: the boards' grain and their joints; age streaks under the
		// deck edges and dirt rising at the foot.
		float boards = rc_noise(vec2(uv.x * 0.15, uv.y * 7.0)) * 0.08;
		col *= 1.0 - boards - 0.3 * joint(uv.y, 0.15, 0.004, px) * 0.4;
		col *= 1.0 - 0.28 * smoothstep(0.5, 0.9, rc_fbm(vec2(uv.x * 1.1, uv.y * 0.12 + 4.0)));
	} else if (kind == 6) {
		// Piers: the flow's dirt and algae up to the flood line.
		float wetline = 1.0 - smoothstep(0.8, 1.8, height + 0.4 * rc_noise(uv * 0.6));
		col = mix(col, algae_color * 1.4, wetline * 0.55);
		col *= 1.0 - 0.25 * smoothstep(0.5, 0.9, rc_fbm(vec2(uv.x * 1.4, uv.y * 0.1)));
	} else if (kind == 7) {
		col = vec3(0.012, 0.012, 0.011);
		rough = 0.9;
	}

	if (kind == 0 || kind == 1) {
		// The drain outfalls (LaRiver.outfall_at()): rust and a wet trail down the bank from the
		// pipe, and across the bed to the low flow.
		float sk = floor(uv.x / outfall_pitch);
		uint key = uint(max(sk, 0.0)) * 2u + uint(side + 0.5) + 7919u;
		if (ihash01(key) < outfall_odds) {
			float centre = (sk + 0.5) * outfall_pitch;
			float ds = abs(uv.x - centre);
			float wob = 0.35 * rc_noise(vec2(uv.y * 0.6, sk));
			if (kind == 0) {
				float below = smoothstep(outfall_v - 0.2, outfall_v + 0.6, uv.y);
				float trail = (1.0 - smoothstep(0.35, 1.3 + wob, ds)) * below;
				col = mix(col, rust_color * (0.7 + 0.6 * detail), trail * (0.55 + 0.3 * rc_noise(uv * 3.0)) * smoothstep(9.0, 2.0, uv.y));
				dark = max(dark, trail * 0.35);
			} else {
				float trail = (1.0 - smoothstep(0.5, 1.6 + wob, ds));
				col = mix(col, algae_color * 1.3, trail * 0.55);
				dark = max(dark, trail * 0.3);
			}
		}
	}

	if (kind == 0) {
		// Graffiti on the bank: a piece slot every tag_pitch, a piece in half of them, in its own
		// two colours, sized to the bank (big pieces low and long; handstyles small and high).
		float slot = floor(uv.x / tag_pitch);
		uint tk = uint(slot + 4096.0) * 2u + uint(side + 0.5) + 104729u;
		if (ihash01(tk) < tag_odds) {
			// Mostly throw-ups and roller letters (cells 8-15): the river's walls carry big pieces.
			uint cell = ihash(tk + 1u) % 16u;
			if (ihash01(tk + 8u) < 0.7) {
				cell = 8u + cell % 8u;
			}
			float h = mix(3.0, 5.5, ihash01(tk + 2u));
			if (cell < 8u) {
				h *= 0.55;
			}
			float w = h * 2.0;
			float s0 = slot * tag_pitch + ihash01(tk + 3u) * max(tag_pitch - w, 0.5);
			float v0 = mix(0.4, max(0.5, 9.0 - h), ihash01(tk + 4u));
			vec2 local = vec2((uv.x - s0) / w, (uv.y - v0) / h);
			if (local.x > 0.0 && local.x < 1.0 && local.y > 0.0 && local.y < 1.0) {
				vec2 cxy = vec2(float(cell % 4u), float(cell / 4u));
				// The atlas reads left to right as the piece reads looking at the bank; the west
				// bank's s runs the other way under the viewer.
				float lx = side < 0.5 ? 1.0 - local.x : local.x;
				vec2 auv = (cxy + vec2(lx, local.y)) / vec2(4.0, 4.0);
				vec3 m = texture(tag_atlas, auv).rgb;
				vec3 fill = PAINTS[ihash(tk + 5u) % 10u];
				vec3 outline = PAINTS[ihash(tk + 6u) % 10u];
				// Old pieces fade and flake; a few are buffed out in a grey that never matches.
				float age = ihash01(tk + 7u);
				float wear = smoothstep(0.35, 0.75, rc_noise(uv * 2.5) + age * 0.45);
				float a = tag_strength * (1.0 - wear * 0.6);
				if (age > 0.86) {
					vec2 bl = abs(local - 0.5);
					float buff = 1.0 - smoothstep(0.42, 0.5, max(bl.x * 0.9, bl.y));
					col = mix(col, vec3(0.33, 0.32, 0.31) * (0.9 + 0.2 * detail), buff * 0.9);
				} else {
					col = mix(col, outline * (0.8 + 0.3 * detail), m.g * a);
					col = mix(col, fill * (0.8 + 0.3 * detail), m.r * a);
					col = mix(col, vec3(0.9), m.b * a * 0.8);
				}
			}
		}
	}

	// Rain: the concrete darkens and its sheen comes up.
	float wet = clamp(road_wetness, 0.0, 1.0);
	col *= 1.0 - 0.38 * wet;
	rough = mix(rough, 0.3, wet * 0.7);
	col *= 1.0 - dark;
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	if (ground_detail > 0.5 && kind != 7) {
		NORMAL_MAP = texture(concrete_nrm, uv * 0.3).rgb;
		NORMAL_MAP_DEPTH = 0.6;
	}
}
