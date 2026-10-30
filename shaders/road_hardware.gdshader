shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// The road surface's hardware (RoadHardware, scripts/world/road_hardware.gd): manhole and valve
// covers with their frames and patched collars, kerb inlets, utility cuts, steel road plates,
// raised pavement markers and Botts' dots - every kind on this one shader. What a face is rides
// in the vertex colour's alpha ((kind + 0.5) / 16, the K_* below = RoadHardware's enum), its
// paint in the rgb (sRGB); INSTANCE_CUSTOM is per kind: r the cover's cast pattern / 8 (or a
// marker's colour, a cut's age), g wear (a cut's length / 32), b the cover's height against the
// road (0.5 flush, (b - 0.5) * 0.08 m; a cut's width / 32), a a tone.
//
// Works in linear on both renderers (color_space.gdshaderinc). Wet from `road_wetness`, drying
// with the road (wet_drying.gdshaderinc); water stands in a cover's cast recesses and in the
// inlet's apron. Markers' reflectors glint in the headlights at the camera after dark.

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D asphalt_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap, repeat_enable;
// Metres per asphalt tile (the roads use 7 and 9) and the roads' mean tint.
uniform float tex_scale = 7.0;
uniform vec3 road_tint = vec3(0.81, 0.80, 0.82);
// Cast relief of a cover's pattern (metres) for the normal.
uniform float cast_relief = 0.004;
// Headlight glint on the reflectors: energy, reach (m), cone (cosine of the half-angle).
uniform float glint_energy = 7.0;
uniform float glint_reach = 60.0;
uniform float glint_cone = 0.94;

global uniform float road_wetness;
global uniform float lamp_factor;
global uniform float ground_detail;

#include "res://shaders/wet_drying.gdshaderinc"

const int K_IRON = 0;
const int K_FRAME = 1;
const int K_ASPHALT = 2;
const int K_SEAL = 3;
const int K_CONCRETE = 4;
const int K_STEEL = 5;
const int K_VOID = 6;
const int K_CERAMIC = 7;
const int K_REFLECT = 8;
const int K_PAINT = 9;
const int K_CUT = 10;
const int K_PLATE = 11;

varying vec3 world_pos;
varying vec3 obj;
varying flat int kind;
varying flat vec4 icus;
varying vec3 ax_x;
varying vec3 ax_y;
varying vec3 ax_z;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.3 + 7.1) * 0.3 + vnoise(p * 5.1 + 3.7) * 0.15;
}

// A soft band: 1 inside [a, b], easing over w.
float band(float x, float a, float b, float w) {
	return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x));
}

// The cast pattern's height (0 recess .. 1 raised; -1 a pick hole) at `p` metres from the lid's
// centre, softened over `w` metres. Patterns: 0 sunburst (sewer), 1 diamond (storm), 2 waffle,
// 3 rings, 4 water valve, 5 gas valve.
float lid_height(vec2 p, int pat, float w) {
	float r = length(p);
	float a = atan(p.y, p.x);
	if (pat >= 4) {
		// Valves (radius 0.105): a rim and a small cast field.
		float h = band(r, 0.088, 0.2, w);
		if (pat == 4) {
			vec2 q = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * p / 0.022;
			vec2 c = abs(fract(q) - 0.5);
			h = max(h, (1.0 - smoothstep(0.26 - w * 30.0, 0.26 + w * 30.0, max(c.x, c.y))) * step(r, 0.08));
		} else {
			h = max(h, band(r, 0.045, 0.056, w));
			h = max(h, 1.0 - smoothstep(0.02 - w, 0.02 + w, r));
			float rib = abs(fract(a * 6.0 / 6.2832 + 0.5) - 0.5) * r * 6.2832 / 6.0;
			h = max(h, (1.0 - smoothstep(0.005 - w, 0.005 + w, rib)) * band(r, 0.02, 0.045, w));
		}
		return h;
	}
	float rim = band(r, 0.335, 0.5, w);
	float h = rim;
	if (pat == 0) {
		h = max(h, band(r, 0.095, 0.11, w));
		h = max(h, band(r, 0.205, 0.22, w));
		float n = 24.0;
		float rib = abs(fract(a * n / 6.2832 + 0.5) - 0.5) * r * 6.2832 / n;
		h = max(h, (1.0 - smoothstep(0.006 - w, 0.006 + w, rib)) * band(r, 0.11, 0.335, w));
		h = max(h, 1.0 - smoothstep(0.045 - w, 0.045 + w, r));
		// A band of cast lettering round the boss: blocks in a 3 x 5 cell per letter.
		float n_l = 14.0;
		float la = fract(a / 6.2832 * n_l);
		float lr = (r - 0.058) / 0.032;
		if (lr > 0.0 && lr < 1.0 && la > 0.15 && la < 0.85) {
			vec2 cell = floor(vec2((la - 0.15) / 0.7 * 3.0, lr * 5.0));
			float id = floor(a / 6.2832 * n_l);
			h = max(h, step(0.45, hash12(cell + id * 7.13)));
		}
	} else if (pat == 1) {
		vec2 q = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * p / 0.042;
		vec2 c = abs(fract(q) - 0.5);
		h = max(h, (1.0 - smoothstep(0.3 - w * 24.0, 0.3 + w * 24.0, max(c.x, c.y))) * step(r, 0.335));
	} else if (pat == 2) {
		vec2 c = abs(fract(p / 0.05) - 0.5);
		float lug = 1.0 - smoothstep(0.32 - w * 20.0, 0.32 + w * 20.0, max(c.x, c.y));
		h = max(h, lug * band(r, 0.13, 0.335, w));
		h = max(h, band(r, 0.115, 0.13, w));
		float lr = (r - 0.03) / 0.07;
		if (lr > 0.0 && lr < 1.0) {
			float rows = floor(lr * 4.0);
			float col = floor((p.x + 0.12) / 0.018);
			h = max(h, step(0.55, hash12(vec2(col, rows) + 3.1)) * step(0.2, fract(lr * 4.0)));
		}
	} else {
		float k = fract(r / 0.034);
		h = max(h, band(k, 0.0, 0.32, w / 0.034));
		float cross_d = min(abs(p.x), abs(p.y));
		h = max(h, 1.0 - smoothstep(0.008 - w, 0.008 + w, cross_d));
	}
	// Two pick holes near the rim.
	if (length(abs(p) - vec2(0.3, 0.0)) < 0.013) {
		return -1.0;
	}
	return h;
}

// How strongly the headlights at the camera light a reflector at `wp` facing `n` (world).
float headlit(vec3 wp, vec3 n, vec3 cam, vec3 fwd) {
	vec3 to_cam = cam - wp;
	float dist = length(to_cam);
	vec3 v = to_cam / max(dist, 0.001);
	float facing = dot(n, v);
	float cone = dot(normalize(fwd), -v);
	float reach = 1.0 / (1.0 + pow(dist / glint_reach, 2.0));
	return smoothstep(glint_cone, 1.0, cone) * smoothstep(0.2, 0.8, facing) * reach * smoothstep(1.0, 4.0, dist);
}

void vertex() {
	kind = int(COLOR.a * 16.0);
	icus = INSTANCE_CUSTOM;
	float p = (INSTANCE_CUSTOM.b - 0.5) * 0.08;
	if (kind <= K_SEAL) {
		VERTEX.y += UV2.x * max(p, 0.0) + UV2.y * max(-p, 0.0);
	}
	obj = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ax_x = normalize((MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	ax_y = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ax_z = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
}

// The asphalt texture at a world point, linear, times the road's tint and `shade`.
vec3 asphalt(vec2 wxz, float shade) {
	return cs_in(texture(asphalt_tex, wxz / tex_scale).rgb) * road_tint * shade;
}

void fragment() {
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	vec3 alb = base;
	float rough = 0.7;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	// Object-space normal to perturb (flat mesh normal by default).
	vec3 n_obj = vec3(0.0);
	bool set_n = false;
	// How much a surface is porous (darkens when wet) and holds a film (glosses when wet).
	float porous = 0.0;
	float pool = 0.0;
	vec2 wxz = world_pos.xz;
	float px = max(length(fwidth(obj.xz)), 0.0003);

	if (kind == K_IRON || kind == K_FRAME) {
		int pat = int(icus.r * 8.0);
		float wear = icus.g;
		float h = kind == K_IRON ? lid_height(UV, pat, max(px * 0.7, 0.0015)) : 1.0;
		float detail = 1.0 - smoothstep(0.004, 0.014, px);
		if (h < -0.5) {
			alb = vec3(0.004);
			rough = 0.9;
		} else {
			h = mix(0.45, h, detail);
			// Normal from the cast relief.
			if (kind == K_IRON && detail > 0.01) {
				float e = max(px * 0.8, 0.002);
				float w = max(px * 0.7, 0.0015);
				float hx = lid_height(UV + vec2(e, 0.0), pat, w) - lid_height(UV - vec2(e, 0.0), pat, w);
				float hz = lid_height(UV + vec2(0.0, e), pat, w) - lid_height(UV - vec2(0.0, e), pat, w);
				vec2 g = vec2(max(hx, -1.0), max(hz, -1.0)) / (2.0 * e) * cast_relief * detail;
				n_obj = normalize(vec3(-g.x, 1.0, -g.y));
				set_n = true;
			}
			// Cast iron: dark, rust and road dust in the recesses, worn bright where tyres
			// run over the raised pattern and the frame's top.
			float rust = smoothstep(0.35, 0.8, fbm(wxz * 9.0 + icus.a * 13.0));
			vec3 iron = vec3(0.045, 0.042, 0.04);
			vec3 rusty = vec3(0.12, 0.05, 0.022);
			vec3 dust = asphalt(wxz, 0.55) * 0.9;
			vec3 recess = mix(mix(iron, rusty, rust * 0.7), dust, 0.45 + 0.3 * vnoise(wxz * 23.0));
			float polish = smoothstep(0.35, 0.9, h) * (0.35 + 0.65 * wear) * (0.6 + 0.4 * vnoise(wxz * 31.0));
			vec3 bright = vec3(0.2, 0.195, 0.19);
			alb = mix(recess, mix(iron * 1.4, bright, polish), smoothstep(0.25, 0.7, h));
			metal = mix(0.1, 0.65, polish);
			rough = mix(0.85, 0.42, polish);
			if (kind == K_FRAME) {
				// The frame's ring: worn steel on top, rust on its bevel.
				float up = dot(NORMAL, ax_y);
				float shine = smoothstep(0.9, 0.99, up) * (0.25 + 0.5 * wear) * (0.5 + 0.5 * vnoise(wxz * 40.0));
				alb = mix(mix(iron, rusty * 0.7, 0.2 + 0.4 * rust), vec3(0.16, 0.155, 0.15), shine);
				metal = mix(0.2, 0.6, shine);
				rough = mix(0.8, 0.45, shine);
			}
			pool = kind == K_IRON ? (1.0 - smoothstep(0.15, 0.45, h)) : 0.0;
			porous = 0.25;
		}
		if (pat == 4 || pat == 5) {
			// A dab of locate paint on some valve lids: blue water, yellow gas.
			vec3 dab = pat == 4 ? vec3(0.02, 0.12, 0.55) : vec3(0.75, 0.5, 0.02);
			float d = smoothstep(0.75, 0.55, length(UV - vec2(0.03, -0.02)) / 0.09 + vnoise(wxz * 60.0) * 0.35);
			alb = mix(alb, dab * (0.7 + 0.3 * vnoise(wxz * 80.0)), d * step(0.5, icus.a) * 0.85);
		}
	} else if (kind == K_ASPHALT) {
		// The patched collar round a cover (and a plate's cold-patch ramp): newer, darker asphalt.
		float shade = mix(0.55, 0.95, icus.a) * (0.92 + 0.16 * vnoise(wxz * 3.0));
		alb = asphalt(wxz, shade);
		rough = 0.86;
		porous = 1.0;
		vec3 tn = texture(asphalt_nrm, wxz / tex_scale).rgb * 2.0 - 1.0;
		n_obj = normalize(vec3(tn.x * 0.6, 1.0, -tn.y * 0.6));
		set_n = true;
	} else if (kind == K_SEAL) {
		// Crack sealant on the sawcut: tar, glossy, a little ragged in tone.
		float n = vnoise(wxz * 18.0);
		alb = vec3(0.022 + 0.012 * n);
		rough = 0.62 + 0.2 * n;
		porous = 0.2;
	} else if (kind == K_CONCRETE) {
		bool flat_face = dot(NORMAL, ax_y) > 0.7;
		vec2 tuv = flat_face ? wxz : vec2(world_pos.x + world_pos.z, world_pos.y);
		vec3 tex = cs_in(texture(concrete_tex, tuv / 2.2).rgb);
		alb = tex * base * 0.95;
		// Dirt: tide marks and silt toward the kerb on the apron, grime low on the facing.
		float silt = flat_face ? (1.0 - smoothstep(0.0, 0.55, obj.z)) * step(obj.y, 0.05) : (1.0 - smoothstep(0.0, 0.12, obj.y));
		float blot = fbm(wxz * 3.5 + icus.a * 9.0);
		// Road grime toward the gutter's rim (tyres), silt and tide marks toward the kerb.
		float rim = flat_face ? smoothstep(0.5, 0.95, obj.z) * step(obj.y, 0.05) : 0.0;
		alb = mix(alb, asphalt(wxz, 0.85), rim * (0.35 + 0.3 * blot));
		alb *= mix(1.0, 0.3 + 0.25 * blot, clamp(silt * (0.7 + icus.g * 0.3) + blot * 0.35, 0.0, 1.0));
		// The wet streak the last trickle leaves along the kerb, and leaves and grit in it.
		float streak = flat_face ? (1.0 - smoothstep(0.03, 0.14 + 0.06 * blot, obj.z)) * step(obj.y, 0.05) : 0.0;
		alb = mix(alb, vec3(0.035, 0.032, 0.025), streak * 0.7);
		float tide = flat_face ? band(fract(obj.z * 6.0 + blot * 0.6), 0.45, 0.5, 0.02) * (1.0 - smoothstep(0.0, 0.6, obj.z)) * step(obj.y, 0.05) : 0.0;
		alb *= 1.0 - tide * 0.25;
		rough = 0.9;
		porous = 1.0;
		pool = flat_face ? (1.0 - smoothstep(0.0, 0.4, obj.z)) * step(obj.y, 0.05) * 0.8 : 0.0;
	} else if (kind == K_STEEL) {
		float rust = smoothstep(0.3, 0.75, fbm(wxz * 12.0 + world_pos.y * 30.0));
		alb = mix(vec3(0.06, 0.055, 0.05), vec3(0.14, 0.06, 0.025), rust);
		float up = dot(NORMAL, ax_y);
		alb = mix(alb, vec3(0.22, 0.21, 0.2), smoothstep(0.95, 1.0, up) * 0.6 * (1.0 - rust));
		metal = mix(0.7, 0.2, rust);
		rough = mix(0.45, 0.85, rust);
		porous = 0.2;
	} else if (kind == K_VOID) {
		// Down the drain: nearly black, the throat lit a little at its mouth (the slot's height
		// in obj.y, darkest under the head) and by the grate's bars.
		alb = vec3(0.004 + 0.02 * (1.0 - smoothstep(0.012, 0.07, obj.y)) * step(0.01, obj.z));
		rough = 0.85;
		pool = 1.0;
	} else if (kind == K_CERAMIC || kind == K_REFLECT) {
		bool yellow = icus.r < 0.375;
		vec3 body = yellow ? vec3(0.62, 0.42, 0.03) : vec3(0.72, 0.72, 0.68);
		// Road grime round the foot and in streaks behind.
		float grime = (1.0 - smoothstep(0.0, 0.012, obj.y)) * 0.6 + vnoise(wxz * 70.0 + icus.g * 5.0) * 0.25 * (0.4 + icus.g);
		alb = mix(body, asphalt(wxz, 0.6), clamp(grime, 0.0, 0.8));
		rough = 0.22 + grime * 0.4;
		if (kind == K_REFLECT) {
			bool front = UV.x > 0.0;
			vec3 refl = yellow ? vec3(0.85, 0.5, 0.02) : (front ? vec3(0.85, 0.85, 0.8) : vec3(0.7, 0.02, 0.02));
			// Prismatic cube-corner lens: a fine grid that sparkles.
			float prism = 0.6 + 0.4 * step(0.5, fract(obj.x * 220.0) + fract(obj.y * 220.0) * 0.5);
			alb = refl * 0.35 * prism;
			rough = 0.12;
			vec3 n_w = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
			vec3 cam = CAMERA_POSITION_WORLD;
			vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
			vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
			emit = refl * headlit(wp, n_w, cam, fwd) * clamp(lamp_factor, 0.0, 1.0) * glint_energy;
		}
		porous = 0.0;
	} else if (kind == K_PAINT) {
		// The stencil: worn where feet go, the concrete through it.
		float worn = fbm(wxz * 7.0 + 2.0);
		float gone = smoothstep(0.55 - icus.g * 0.25, 0.75 - icus.g * 0.25, worn);
		vec3 conc = cs_in(texture(concrete_tex, wxz / 2.2).rgb) * 0.7;
		alb = mix(base * (0.85 + 0.15 * vnoise(wxz * 50.0)), conc, gone * 0.85);
		rough = 0.75;
		porous = 0.8;
	} else if (kind == K_CUT) {
		// A utility cut: sawcut edges sealed with tar, the trench's asphalt inside. Age 0.35 is
		// black and fresh, 1.1 bleached paler than the road.
		vec2 size = vec2(icus.g, icus.b) * 32.0;
		vec2 m = (UV - 0.5) * size;
		vec2 dd = size * 0.5 - abs(m);
		float edge = min(dd.x, dd.y);
		float wob = (vnoise(wxz * 9.0) - 0.5) * 0.012;
		float age = icus.r;
		float seal = 1.0 - smoothstep(0.028 + wob, 0.04 + wob, edge);
		float shade = mix(0.5, 1.12, smoothstep(0.35, 1.1, age)) * (0.9 + 0.2 * vnoise(wxz * 2.0 + icus.a * 17.0));
		// Fresh asphalt is coarser: the texture a little larger.
		vec3 a_col = cs_in(texture(asphalt_tex, wxz / (tex_scale * mix(0.6, 1.0, age))).rgb) * road_tint * shade;
		vec3 s_col = vec3(0.025) * (1.0 + 0.6 * smoothstep(0.7, 1.1, age));
		alb = mix(a_col, s_col, seal * (1.0 - smoothstep(0.9, 1.15, age) * 0.5));
		rough = mix(mix(0.92, 0.84, age), 0.66, seal);
		porous = 1.0 - seal * 0.8;
		vec3 tn = texture(asphalt_nrm, wxz / (tex_scale * mix(0.6, 1.0, age))).rgb * 2.0 - 1.0;
		n_obj = normalize(vec3(tn.x * 0.7 * (1.0 - seal), 1.0, -tn.y * 0.7 * (1.0 - seal)));
		set_n = true;
	} else if (kind == K_PLATE) {
		// A steel road plate: mill scale and rust, the two wheel paths polished bright, lifting
		// holes, now and then a crew's spray mark.
		vec2 q = obj.xz;
		float rust = smoothstep(0.35, 0.8, fbm(wxz * 1.6 + icus.a * 5.0) * 0.7 + fbm(wxz * 11.0) * 0.3);
		vec3 steel = mix(vec3(0.034, 0.033, 0.032), vec3(0.075, 0.038, 0.018), rust * 0.85);
		// Road dust ground into it, thickest off the wheel paths.
		steel = mix(steel, asphalt(wxz, 0.45), 0.3 * vnoise(wxz * 4.0 + 3.0));
		float track = band(abs(q.x) - 0.86 + (vnoise(vec2(q.y * 1.5, 3.0)) - 0.5) * 0.1, -0.17, 0.17, 0.1);
		float polish = track * (0.4 + 0.6 * icus.g) * (0.75 + 0.25 * vnoise(vec2(q.x * 9.0, q.y * 0.8)));
		alb = mix(steel, vec3(0.1, 0.098, 0.095), polish);
		metal = mix(0.1, 0.45, polish) * (1.0 - rust * 0.6);
		rough = mix(0.86, 0.5, polish);
		if (length(vec2(abs(q.x) - 1.05, q.y)) < 0.028) {
			alb = vec3(0.004);
			rough = 0.9;
		}
		if (icus.r > 0.65) {
			// A sprayed line and a cross where the crew marked the trench.
			float spray = max(band(q.y, -0.02, 0.02, 0.012) * band(q.x, -0.9, 0.9, 0.05), band(abs(q.x - q.y * 0.6), -0.02, 0.02, 0.012) * band(q.y, -0.4, 0.4, 0.05));
			vec3 sc = icus.r > 0.85 ? vec3(0.9, 0.25, 0.01) : vec3(0.8, 0.8, 0.75);
			alb = mix(alb, sc * (0.7 + 0.3 * vnoise(q * 30.0)), spray * 0.85);
		}
		porous = 0.1;
		pool = 0.15;
	}

	// Wet: the road's water, drying with it.
	float wet = clamp(road_wetness, 0.0, 1.0);
	vec2 fd = vec2(wet);
	if (wet > 0.01 && ground_detail > 0.5 && road_drying > 0.0) {
		fd = wet_film_damp(wet, wet_hold_noise(wxz) + pool * 0.3);
	}
	alb *= mix(1.0, 0.6, fd.y * porous);
	float film = clamp(fd.x * (0.55 + 0.45 * pool), 0.0, 1.0);
	rough = mix(rough, mix(0.12, 0.03, pool), film);
	if (set_n) {
		// Standing water flattens what it covers.
		n_obj = normalize(mix(n_obj, vec3(0.0, 1.0, 0.0), film * pool));
		NORMAL = normalize(ax_x * n_obj.x + ax_y * n_obj.y + ax_z * n_obj.z);
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = metal;
	// Porous ground (asphalt, concrete) reflects little; water on it a lot.
	SPECULAR = mix(mix(0.5, 0.3, porous), 0.8, film);
	EMISSION = cs_out(emit);
}
