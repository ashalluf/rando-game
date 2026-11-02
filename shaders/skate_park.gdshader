shader_type spatial;
render_mode cull_back;

// THE PIT, the boardwalk's skate park (SkatePark, scripts/world/skate_park.gd): every surface of
// it is ONE mesh on this material. What a face is rides in COLOR.a (kind / 16, rounded here), a
// tint in COLOR.rgb (linear: steel's paint, the ledges' paint), UV metres in the face's own frame
// (along a wall or round a bowl's rim in x, height in y; plan x / z on a flat face), and the
// model-space position (the park's own frame, which never moves with the origin) for the noise.
//
// Kinds:  0 deck (trowelled slab, saw-cut joints)   1 bowl and transition (smooth shotcrete)
//         2 pool coping (bullnose blocks)           3 pool tile band (mosaic)
//         4 steel (galvanised or painted)           5 board-formed retaining wall (graffiti)
//         6 stairs                                  7 planter soil
//         8 concrete cap                            9 painted   10 ledge (painted concrete)
//
// What it paints from the coordinates, with no decals and no extra draws: the slab joints and the
// pours that never matched; urethane - the dark arcs carved round a bowl's transition, densest
// where the riding is, the black of wheels and wax along every coping and ledge edge; shoe scuffs
// and board scrapes; the bowl's tile band; the wall's form boards and tie holes; and graffiti -
// original pieces from the street wear tag atlas, more of them on the outer walls than inside.
// Works on both renderers (color_space.gdshaderinc).

global uniform float road_wetness;
global uniform float ground_detail;
global uniform float lamp_factor;

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tag_atlas : filter_linear_mipmap, repeat_disable;

// LINEAR albedos: a beach park's concrete is pale and warm, the bowls a little darker and greyer
// (polished by wheels), the walls the colour of old form-poured concrete.
uniform vec3 deck_color = vec3(0.205, 0.196, 0.18);
uniform vec3 bowl_color = vec3(0.19, 0.186, 0.176);
uniform vec3 wall_color = vec3(0.15, 0.144, 0.132);
uniform vec3 cap_color = vec3(0.25, 0.243, 0.225);
uniform vec3 coping_color = vec3(0.30, 0.292, 0.27);
uniform vec3 soil_color = vec3(0.05, 0.035, 0.022);
uniform vec3 urethane = vec3(0.025, 0.024, 0.024);
uniform vec3 tile_blue = vec3(0.012, 0.09, 0.30);
uniform vec3 tile_light = vec3(0.30, 0.55, 0.70);
uniform float joint_pitch = 3.0;
// Graffiti: one piece slot every `tag_pitch` metres of wall, taken at `tag_odds`.
uniform float tag_pitch = 6.5;
uniform float tag_odds = 0.8;
uniform float tag_strength = 0.94;

varying vec4 v_kind;
varying vec3 v_local;
varying vec3 v_nrm;

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

float sp_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sp_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(sp_hash(i), sp_hash(i + vec2(1.0, 0.0)), f.x),
		mix(sp_hash(i + vec2(0.0, 1.0)), sp_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float sp_fbm(vec2 p) {
	return sp_noise(p) * 0.5 + sp_noise(p * 2.07 + 3.1) * 0.3 + sp_noise(p * 4.3 + 7.7) * 0.2;
}

// A line every `pitch` along `x`: 1 on it, gone over `w` metres, faded out once a pixel is past it.
float joint(float x, float pitch, float w, float px) {
	float d = abs(fract(x / pitch + 0.5) - 0.5) * pitch;
	return (1.0 - smoothstep(w, w + px * 1.5, d)) * (1.0 - smoothstep(0.06, 0.25, px));
}

const vec3 PAINTS[12] = vec3[](
	vec3(0.70, 0.70, 0.66), vec3(0.03, 0.03, 0.035), vec3(0.62, 0.06, 0.04), vec3(0.05, 0.16, 0.55),
	vec3(0.78, 0.55, 0.04), vec3(0.06, 0.40, 0.16), vec3(0.55, 0.10, 0.45), vec3(0.85, 0.28, 0.04),
	vec3(0.25, 0.62, 0.80), vec3(0.62, 0.62, 0.62), vec3(0.90, 0.20, 0.42), vec3(0.45, 0.80, 0.18)
);

void vertex() {
	v_kind = COLOR;
	v_local = VERTEX;
	v_nrm = NORMAL;
}

// Graffiti on a wall: a piece in a slot every tag_pitch along u, its height and place from a hash.
vec3 graffiti(vec3 col, vec2 uv, float detail, float odds, float max_h, float salt) {
	float slot = floor(uv.x / tag_pitch);
	uint tk = uint(slot + 8192.0) * 3u + uint(salt) + 7919u;
	if (ihash01(tk) >= odds) {
		return col;
	}
	uint cell = ihash(tk + 1u) % 16u;
	float h = mix(0.9, max_h, ihash01(tk + 2u));
	if (cell < 8u) {
		h *= 0.6;
	}
	float w = h * 2.0;
	float s0 = slot * tag_pitch + ihash01(tk + 3u) * max(tag_pitch - w, 0.2);
	float v0 = mix(0.05, max(0.1, max_h - h + 0.2), ihash01(tk + 4u));
	vec2 local = vec2((uv.x - s0) / w, (uv.y - v0) / h);
	if (local.x <= 0.0 || local.x >= 1.0 || local.y <= 0.0 || local.y >= 1.0) {
		return col;
	}
	vec2 cxy = vec2(float(cell % 4u), float(cell / 4u));
	vec3 m = texture(tag_atlas, (cxy + vec2(local.x, local.y)) / 4.0).rgb;
	vec3 fill = PAINTS[ihash(tk + 5u) % 12u];
	vec3 outline = PAINTS[ihash(tk + 6u) % 12u];
	float age = ihash01(tk + 7u);
	float wear = smoothstep(0.4, 0.8, sp_noise(uv * 3.0) + age * 0.4);
	float a = tag_strength * (1.0 - wear * 0.55);
	if (age > 0.9) {
		vec2 bl = abs(local - 0.5);
		float buff = 1.0 - smoothstep(0.42, 0.5, max(bl.x * 0.9, bl.y));
		return mix(col, vec3(0.30, 0.29, 0.28) * (0.9 + 0.2 * detail), buff * 0.9);
	}
	col = mix(col, outline * (0.85 + 0.25 * detail), m.g * a);
	col = mix(col, fill * (0.85 + 0.25 * detail), m.r * a);
	col = mix(col, vec3(0.88), m.b * a * 0.8);
	return col;
}

void fragment() {
	int kind = int(floor(v_kind.a * 16.0));
	vec3 tint = v_kind.rgb;
	vec2 uv = UV;
	vec2 plan = v_local.xz;
	float px = max(length(dFdx(v_local)), length(dFdy(v_local)));

	vec3 tex = cs_in(texture(concrete_tex, (kind == 0 || kind == 6 || kind == 8) ? plan * 0.3 : uv * 0.3).rgb);
	float tex_l = dot(tex, vec3(0.299, 0.587, 0.114));
	float detail = clamp(tex_l / 0.36, 0.8, 1.2);
	float pour = sp_noise(plan * 0.09 + 3.0);
	vec3 col = deck_color;
	float rough = 0.82;
	float metal = 0.0;
	float spec = 0.4;
	float nm_depth = 0.55;
	float lamp = 0.0;

	if (kind == 0 || kind == 6) {
		col = deck_color * (0.88 + 0.22 * pour) * detail;
		// Saw-cut joints on a square grid; the stairs keep their own lines.
		if (kind == 0 && abs(v_nrm.y) > 0.9) {
			float j = max(joint(plan.x, joint_pitch, 0.006, px), joint(plan.y, joint_pitch, 0.006, px));
			col *= 1.0 - 0.45 * j;
		}
		// Trowel swirls (a lighter, smoother sheen) and footprints of grime.
		float swirl = sp_fbm(plan * vec2(1.3, 1.1));
		col *= 0.95 + 0.1 * swirl;
		rough = 0.78 - 0.1 * swirl;
		// Board scrapes and rubber: short dark streaks on a random heading per patch.
		float ang = sp_hash(floor(plan * 0.5)) * 6.28;
		vec2 dir = vec2(cos(ang), sin(ang));
		float streak = sp_noise(vec2(dot(plan, dir) * 0.6, dot(plan, vec2(-dir.y, dir.x)) * 14.0));
		float scuff = smoothstep(0.78, 0.93, streak) * smoothstep(0.35, 0.7, sp_noise(plan * 0.4 + 9.0));
		col = mix(col, urethane * 2.5, scuff * 0.45 * (1.0 - smoothstep(0.03, 0.12, px)));
	} else if (kind == 1) {
		col = bowl_color * (0.9 + 0.18 * pour) * mix(1.0, detail, 0.6);
		rough = 0.62;
		// Wheels carve dark arcs round the transition, along u at their own heights.
		float h = uv.y;
		float lane = sp_noise(vec2(uv.x * 0.08, h * 3.5 + 1.0));
		float arc = smoothstep(0.62, 0.86, sp_noise(vec2(uv.x * 0.35, h * 22.0)) * (0.7 + 0.5 * lane));
		float band = smoothstep(0.3, 1.0, h) * (1.0 - smoothstep(2.4, 3.1, h));
		float broken = smoothstep(0.35, 0.75, sp_noise(vec2(uv.x * 0.9, h * 2.0 + 5.0)));
		col = mix(col, urethane * 3.0, arc * 0.16 * band * broken);
		// Polished where it is ridden most: a faint sheen low on the wall.
		rough -= 0.12 * band;
		// Water stain from the drain at the floor's lowest point; old leaves in the corners.
		col *= 1.0 - 0.18 * smoothstep(0.55, 0.85, sp_fbm(plan * 0.6)) * (1.0 - smoothstep(0.0, 0.6, v_local.y - 0.25));
		// A few small tags low on the walls inside, and the odd one on the flat.
		if (v_nrm.y < 0.6 && v_local.y < 1.8) {
			col = graffiti(col, uv * vec2(1.0, 1.0), detail, 0.18, 0.8, 11.0);
		}
	} else if (kind == 2) {
		// Bullnose pool coping, a block every 0.6 m with a mortar joint; dark wax and metal-grey
		// grind marks along the nose where every truck has gone.
		col = coping_color * mix(1.0, detail, 0.5) * (0.92 + 0.12 * sp_noise(vec2(floor(uv.x / 0.6) * 7.3, 1.0)));
		float jn = joint(uv.x, 0.6, 0.004, px);
		col *= 1.0 - 0.5 * jn;
		float nose = smoothstep(2.5, 4.5, uv.y);
		float grind = sp_noise(vec2(uv.x * 4.0, uv.y * 0.5)) * 0.6 + 0.4;
		col = mix(col, urethane * 2.0, nose * grind * 0.65);
		rough = mix(0.75, 0.38, nose * grind);
	} else if (kind == 3) {
		// The tile band: 2.5 cm mosaic, a blue field with a lighter key every few tiles.
		vec2 t = vec2(uv.x / 0.025, uv.y / 0.025);
		vec2 ti = floor(t);
		vec2 tf = fract(t);
		float grout = max(1.0 - smoothstep(0.0, 0.12, tf.x), 1.0 - smoothstep(0.0, 0.12, tf.y));
		grout *= 1.0 - smoothstep(0.004, 0.012, px);
		float key = step(0.8, sp_hash(ti + 3.0));
		float band = step(5.0, mod(ti.y, 7.0));
		col = mix(tile_blue, tile_light, max(key * 0.6, band * 0.0)) * (0.85 + 0.3 * sp_hash(ti));
		col = mix(col, vec3(0.32, 0.31, 0.29), grout * 0.85);
		// Chipped where boards hit, scrubbed by wheels.
		col = mix(col, bowl_color, smoothstep(0.82, 0.95, sp_noise(uv * vec2(3.0, 9.0))));
		rough = mix(0.12, 0.7, grout);
		spec = 0.5;
	} else if (kind == 4) {
		// Steel: galvanised or painted, worn bright on top where it is ground.
		vec3 base = tint;
		float galv = step(0.4, tint.r) * step(abs(tint.r - tint.b), 0.05);
		float spangle = sp_noise(uv * 18.0);
		base *= 0.9 + 0.2 * spangle * galv;
		float top = smoothstep(0.3, 0.9, v_nrm.y);
		float worn = top * smoothstep(0.35, 0.65, sp_noise(vec2(uv.x * 2.5, 3.0)));
		col = mix(base, vec3(0.62, 0.62, 0.63), worn);
		metal = mix(galv * 0.6, 0.95, worn);
		rough = mix(galv > 0.5 ? 0.48 : 0.55, 0.22, worn);
		spec = 0.5;
		nm_depth = 0.0;
	} else if (kind == 5) {
		// Board-formed concrete: horizontal form boards 0.15 m high with the grain, tie holes on a
		// grid, efflorescence weeping from the joints, damp at the foot; then the graffiti.
		col = wall_color * (0.85 + 0.25 * pour) * detail;
		float board = floor(uv.y / 0.15);
		col *= 0.96 + 0.07 * sp_hash(vec2(board, floor(uv.x / 2.4)));
		float grain = sp_noise(vec2(uv.x * 9.0, uv.y * 0.6 + board * 13.0));
		col *= 0.97 + 0.05 * grain;
		col *= 1.0 - 0.1 * joint(uv.y, 0.15, 0.002, px);
		// Lifts of the pour every 1.2 m, a darker line with a weep of lime under it.
		col *= 1.0 - 0.3 * joint(uv.y, 1.2, 0.006, px);
		vec2 tie = abs(fract(uv / vec2(0.9, 0.6) + 0.5) - 0.5) * vec2(0.9, 0.6);
		col *= 1.0 - 0.6 * (1.0 - smoothstep(0.012, 0.012 + px * 1.5, length(tie))) * (1.0 - smoothstep(0.05, 0.2, px));
		col *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.45, uv.y)) * sp_noise(vec2(uv.x * 0.8, 2.0));
		col = graffiti(col, uv, detail, tag_odds, 2.1, 0.0);
		// A second, smaller layer: handstyles over and between the pieces.
		col = graffiti(col, uv + vec2(tag_pitch * 0.37, 0.0), detail, 0.45, 1.1, 101.0);
		rough = 0.9;
	} else if (kind == 7) {
		col = soil_color * (0.7 + 0.6 * sp_fbm(plan * 6.0));
		rough = 0.95;
		spec = 0.2;
	} else if (kind == 8) {
		col = cap_color * (0.9 + 0.18 * pour) * detail;
		// Waxed and blackened along the edge riders grind (the caps over the walls are ledges too).
		float wax = smoothstep(0.55, 0.85, sp_noise(vec2(uv.x * 1.5, 2.0)));
		col = mix(col, urethane * 3.0, wax * 0.4 * smoothstep(0.0, 0.5, v_nrm.y));
		col *= 1.0 - 0.4 * joint(uv.x, 2.0, 0.004, px) * step(0.5, v_nrm.y);
		rough = 0.72;
	} else if (kind == 14) {
		// A floodlight's LED panel: a grid of emitters, lit after dark.
		vec2 cell = fract(uv * 9.0);
		float dot_ = 1.0 - smoothstep(0.25, 0.42, length(cell - 0.5));
		col = vec3(0.12) + vec3(0.25) * dot_;
		lamp = lamp_factor * (0.55 + 0.45 * dot_);
		rough = 0.3;
		nm_depth = 0.0;
	} else if (kind == 11) {
		// Grip tape: black sandpaper, scuffed grey where the feet go.
		col = vec3(0.018, 0.018, 0.02) * (0.85 + 0.3 * sp_hash(floor(uv * 400.0)));
		col = mix(col, vec3(0.08), smoothstep(0.55, 0.9, sp_noise(uv * 9.0)) * 0.6);
		rough = 0.97;
		spec = 0.2;
		nm_depth = 0.0;
	} else if (kind == 12) {
		// The deck's plies at its edge.
		float ply = fract(v_local.y * 140.0);
		col = mix(vec3(0.42, 0.28, 0.14), vec3(0.18, 0.11, 0.05), step(0.8, ply));
		rough = 0.75;
		nm_depth = 0.0;
	} else if (kind == 13) {
		// Urethane wheels: off-white, a little translucent-looking, dirty where they roll.
		col = vec3(0.70, 0.66, 0.52) * (0.9 + 0.1 * sp_noise(uv * 40.0));
		rough = 0.5;
		spec = 0.45;
		nm_depth = 0.0;
	} else {
		// Painted concrete (a ledge's paint over the slab): chipped back to concrete on the edges and
		// under wax, the paint dulled and blotched by sun and sand.
		vec3 conc = cap_color * detail;
		float chip = smoothstep(0.55, 0.8, sp_fbm(uv * vec2(2.0, 6.0) + plan * 0.5));
		col = mix(tint * (0.85 + 0.2 * sp_noise(uv * 1.7)), conc, chip * 0.75);
		float wax = smoothstep(0.55, 0.85, sp_noise(vec2(uv.x * 2.0 + plan.y * 1.3, 5.0))) * smoothstep(0.5, 1.0, v_nrm.y);
		col = mix(col, urethane * 2.0, wax * 0.45);
		rough = mix(0.7, 0.4, wax);
	}

	// Sand blown onto the flats, thickest at the foot of anything standing up.
	if (v_nrm.y > 0.9 && kind != 3 && kind != 4) {
		float drift = smoothstep(0.62, 0.9, sp_fbm(plan * 0.35 + 4.0));
		col = mix(col, vec3(0.42, 0.36, 0.26), drift * 0.35);
	}

	// Rain: the concrete darkens and its sheen comes up.
	float wet = clamp(road_wetness, 0.0, 1.0);
	col *= 1.0 - 0.35 * wet * (1.0 - metal);
	rough = mix(rough, 0.25, wet * 0.7);
	ALBEDO = cs_out(col);
	if (lamp > 0.0) {
		EMISSION = cs_out(vec3(1.0, 0.98, 0.92)) * lamp * 9.0;
	}
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = metal;
	SPECULAR = spec;
	if (ground_detail > 0.5 && nm_depth > 0.0) {
		NORMAL_MAP = texture(concrete_nrm, (kind == 0 || kind == 6 || kind == 8) ? plan * 0.3 : uv * 0.3).rgb;
		NORMAL_MAP_DEPTH = nm_depth;
	}
}
