shader_type spatial;
render_mode cull_back;

// ISO shipping containers (scripts/world/port_kit.gd). One mesh with a hand-built LOD ladder;
// everything that is not the frame's shape is drawn here, so it costs no triangles:
//
// * Sizes. The instance transform scales the 40 ft box to 20 ft (x) or high-cube (y). Every
//   vertex within 1.3 m of an end (or 0.42 m of the top or bottom) is moved back to its own
//   distance from that end, so castings, doors, rails and posts keep their real size. `v_pos`
//   is the point in the TRUE container frame, in metres, which is what every pattern reads.
// * Parts (UV2.x): 0 side panel, 1 roof, 2 front end wall, 3 door leaf, 4 frame steel, 5 corner
//   casting, 6 door hardware, 7 rubber gasket, 8 underside. The plain far box carries panel ids
//   on its faces, and the frame zones of a panel (where posts and rails stand at the nearer
//   levels) are drawn as frame, so the LOD step keeps its look.
// * Corrugation: the ISO trapezoidal profile (side walls 278 mm pitch, 36 mm deep; end walls
//   and doors a wider one, the roof shallow) as a normal tilt along the panel. The mesh has no
//   tangents, so the tilt is applied to NORMAL directly (view space, from an axis worked out in
//   vertex()). It fades out once a flute is under about a pixel.
// * Liveries (INSTANCE_CUSTOM.r * 16 = livery index, the same index as PortKit.LIVERY_PAINT):
//   the instance COLOR is the paint; the ink is INK below, and the big name on the sides, the
//   mark and the owner code come from port_lettering.gdshaderinc (shared with the ship's hull).
//   Every name and mark is invented - no real shipping line. Letters are a stroke font
//   (segments, a distance field), bold and chamfered like stencilled type.
// * Weathering (INSTANCE_CUSTOM.g 0..1): sun fade, rust weeping from the top rail, castings and
//   hinges, a rusty foot, road dirt, repaint patches in a slightly different shade, dents.
//   INSTANCE_CUSTOM.b is the box's own seed (serial number, where the streaks fall).
// * Colour space: Forward+ decodes source_color uniforms but not vertex or instance colours,
//   Compatibility decodes nothing; `color_space_probe` tells them apart (street_clutter's
//   trick). Every colour written here is sRGB and goes through col().

uniform vec3 color_space_probe : source_color = vec3(0.5, 0.5, 0.5);
// 0 turns each layer off (A/B, or a cheaper look).
uniform float corrugation : hint_range(0.0, 2.0) = 1.0;
uniform float weathering : hint_range(0.0, 2.0) = 1.0;
uniform float lettering : hint_range(0.0, 1.0) = 1.0;

global uniform float road_wetness;

const float HL = 6.096;
const float HH = 1.2955;
const float HW = 1.219;

varying vec3 v_pos;
varying vec3 v_nrm;
varying vec3 v_pat;
varying vec3 v_paint;
varying vec4 v_inst;
varying float v_part;
varying vec2 v_size;
varying float v_fwd;

// --- Livery tables (index = livery). Ink is sRGB. Name and owner rows index TEXT; -1 none. -----
const vec3 INK[9] = vec3[](
	vec3(0.93, 0.93, 0.9), vec3(0.93, 0.92, 0.88), vec3(0.93, 0.93, 0.9), vec3(0.1, 0.1, 0.12),
	vec3(0.1, 0.24, 0.47), vec3(0.93, 0.92, 0.9), vec3(0.2, 0.2, 0.22), vec3(0.93, 0.93, 0.92),
	vec3(0.85, 0.8, 0.7));
#include "res://shaders/port_lettering.gdshaderinc"

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 col(vec3 srgb) {
	return v_fwd > 0.5 ? to_linear(srgb) : srgb;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// One digit of the box serial, hashed from its seed.
int digit_of(float seed, int k) {
	return int(floor(hash12(vec2(seed * 97.13 + float(k) * 7.31, float(k) * 3.7 + 11.0)) * 9.999));
}

// The glyph in cell `c` of the ID line "OWNR 123456 7" for livery `lv` and box seed.
int id_glyph(int lv, float seed, int c) {
	if (c < 4) {
		return TEXT[OWNER_AT[lv] + c];
	}
	if (c == 4 || c == 11) {
		return -1;
	}
	if (c < 11) {
		return 16 + digit_of(seed, c);
	}
	return 16 + digit_of(seed, 12);
}

// The size-type code: 20 ft "22G1", 40 ft "42G1", high-cube "45G1".
int code_glyph(float len, float hgt, int c) {
	if (c == 0) {
		return len > 9.0 ? 16 + 4 : 16 + 2;
	}
	if (c == 1) {
		return hgt > 2.75 ? 16 + 5 : 16 + 2;
	}
	if (c == 2) {
		return 15;
	}
	return 16 + 1;
}

float id_line(int lv, float seed, vec2 q, float h) {
	float unit = h / 6.0;
	float cell = floor(q.x / (unit * ADVANCE));
	if (cell < 0.0 || cell > 12.0 || q.y < -unit || q.y > h + unit) {
		return 0.0;
	}
	int c = int(cell);
	return ink(id_glyph(lv, seed, c), q - vec2(cell * unit * ADVANCE, 0.0), h);
}

float code_line(vec2 q, float h) {
	float unit = h / 6.0;
	float cell = floor(q.x / (unit * ADVANCE));
	if (cell < 0.0 || cell > 3.0 || q.y < -unit || q.y > h + unit) {
		return 0.0;
	}
	return ink(code_glyph(v_size.x, v_size.y, int(cell)), q - vec2(cell * unit * ADVANCE, 0.0), h);
}

// Depth of the ISO trapezoid at t (0 on the outer flats, 1 on the inner ones): outer flat to
// 0.26, falling slope to 0.5, inner flat to 0.75, rising slope to 1.
float flute_depth(float t) {
	return clamp((t - 0.26) / 0.24, 0.0, 1.0) * (1.0 - clamp((t - 0.75) / 0.25, 0.0, 1.0));
}

// ISO trapezoidal corrugation along `coord` (metres; `pitch` apart, `depth` deep; `k` is the
// view ray's run along coord per metre it goes in): the facet's tilt (+1 facing +coord, -1
// facing -coord, 0 on the flats, rounded over the bends) and how deep the point seen is
// (0..1), both faded to their average once a flute is under a pixel or two. The ray is
// marched into the profile a few times, so at a grazing angle the near slopes hide the
// grooves the way a real corrugated wall does.
vec2 flute(float coord, float pitch, float depth, float k) {
	float w = fwidth(coord) / pitch;
	float keep = 1.0 - smoothstep(0.12, 0.4, w);
	float c = coord;
	float d = 0.0;
	for (int i = 0; i < 3; i++) {
		c = coord + d * k;
		d = depth * flute_depth(fract(c / pitch));
	}
	float t = fract(c / pitch);
	float e = 0.035;
	float fall = smoothstep(0.26 - e, 0.26 + e, t) * (1.0 - smoothstep(0.5 - e, 0.5 + e, t));
	float rise = smoothstep(0.75 - e, 0.75 + e, t) * (1.0 - smoothstep(1.0 - e, 1.0 + e, t)) + (1.0 - smoothstep(-e, e, t));
	return vec2((fall - rise) * keep, mix(0.5, flute_depth(t), keep));
}

void vertex() {
	v_fwd = color_space_probe.r < 0.35 ? 1.0 : 0.0;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 p = VERTEX;
	float ax = abs(p.x);
	if (ax > HL - 1.3) {
		p.x = sign(p.x) * (HL * sx - (HL - ax)) / sx;
	}
	float ay = abs(p.y);
	if (ay > HH - 0.42) {
		p.y = sign(p.y) * (HH * sy - (HH - ay)) / sy;
	}
	VERTEX = p;
	v_pos = p * vec3(sx, sy, 1.0);
	v_size = vec2(2.0 * HL * sx, 2.0 * HH * sy);
	v_nrm = NORMAL;
	v_part = UV2.x;
	v_inst = INSTANCE_CUSTOM;
	vec3 c = COLOR.rgb;
	v_paint = v_fwd > 0.5 ? to_linear(c) : c;
	vec3 axis = abs(NORMAL.x) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	v_pat = normalize((MODELVIEW_MATRIX * vec4(axis, 0.0)).xyz);
}

void fragment() {
	int part = int(v_part + 0.5);
	int lv = clamp(int(v_inst.r * 16.0), 0, 8);
	float wear = clamp(v_inst.g * weathering, 0.0, 1.0);
	float seed = v_inst.b;
	float hl = v_size.x * 0.5;
	float hh = v_size.y * 0.5;
	vec3 p = v_pos;
	vec3 paint = v_paint;
	vec3 albedo = paint;
	float rough = 0.58;
	float metal = 0.0;
	float slope = 0.0;
	float slope_gain = 0.0;
	float shade = 1.0;
	float edge_line = 0.0;
	bool panel = part <= 3;
	// The far box's faces reach into the frame: draw posts and rails there as frame steel.
	if (panel) {
		bool frame = false;
		float inner = 1e3;
		if (part == 0) {
			inner = min(min(hl - 0.17 - abs(p.x), hh - 0.1 - p.y), p.y + hh - 0.165);
		} else if (part == 1) {
			inner = min(hl - 0.2 - abs(p.x), HW - 0.1 - abs(p.z));
		} else if (part == 2) {
			inner = min(min(HW - 0.15 - abs(p.z), hh - 0.13 - p.y), p.y + hh - 0.15);
		} else {
			inner = min(min(HW - 0.16 - abs(p.z), hh - 0.2 - p.y), p.y + hh - 0.19);
		}
		frame = inner < 0.0;
		// A dark line where the panel meets the frame: the recess at the far level, a little
		// contact shadow at the near ones.
		float fwp = max(fwidth(inner), 0.004);
		edge_line = (1.0 - smoothstep(0.0, 0.03 + fwp, abs(inner))) * (frame ? 0.25 : 0.55);
		if (frame) {
			part = 4;
			panel = false;
		}
	}
	float face_z = v_nrm.z;
	// --- Corrugation.
	if (panel && corrugation > 0.0) {
		vec2 f = vec2(0.0);
		// The view ray's run along the flutes' axis per metre into the wall (parallax).
		float k = clamp(-dot(VIEW, v_pat) / max(dot(VIEW, NORMAL), 0.08), -6.0, 6.0);
		if (part == 0) {
			f = flute(p.x + seed * 3.0, 0.278, 0.036, k);
			slope_gain = 0.95;
			// The last flute at each end runs out into a flat strip by the post.
			f *= step(abs(p.x), hl - 0.3);
		} else if (part == 1) {
			f = flute(p.x, 0.25, 0.02, k);
			slope_gain = 0.32;
		} else if (part == 2) {
			f = flute(p.z + 0.08, 0.30, 0.04, k);
			slope_gain = 0.85;
		} else {
			// Door leaves: a flat border round a panel of four wide flutes.
			float lz = abs(p.z);
			float border = min(min(lz - 0.07, HW - 0.15 - 0.08 - lz), min(p.y + hh - 0.19 - 0.09, hh - 0.2 - 0.1 - p.y));
			f = flute(lz - 0.07, 0.235, 0.03, k * sign(p.z)) * step(0.0, border);
			f.x *= sign(p.z);
			slope_gain = 0.8;
		}
		slope = f.x * corrugation;
		shade = mix(1.0, 0.84, f.y * min(corrugation, 1.0));
	}
	// --- Paint, livery and lettering on the panels.
	vec3 ink_col = col(INK[lv]);
	if (part == 0 && lettering > 0.0) {
		// Viewer's u: +x on the +z side, -x on the -z side.
		float u = face_z > 0.0 ? p.x : -p.x;
		int n = NAME_LEN[lv];
		if (n > 0) {
			float h = min(0.95, v_size.y * 0.36);
			if (v_size.x < 9.0) {
				h = 0.72;
			}
			float wdt = name_width(lv, h);
			float mark_r = h * 0.62;
			float total = wdt + mark_r * 2.0 + h * 0.45;
			float u0 = -total * 0.5 + mark_r * 2.0 + h * 0.45;
			float v0 = 0.12 - h * 0.5 + (v_size.y - 2.591) * 0.3;
			float cov = name_line(lv, vec2(u - u0, p.y - v0), h);
			vec2 mc = vec2(u - (-total * 0.5 + mark_r), p.y - (v0 + h * 0.5)) / mark_r;
			float fw = max(fwidth(mc.x), fwidth(mc.y));
			if (abs(mc.x) < 1.2 && abs(mc.y) < 1.2) {
				cov = max(cov, mark(MARK[lv], mc, fw));
			}
			albedo = mix(albedo, ink_col, cov * lettering);
		}
		// The ID in the top corner by the doors.
		float id_h = 0.1;
		float du = face_z > 0.0 ? (hl - 0.45) - 13.0 * id_h / 6.0 * ADVANCE : -(hl - 0.45);
		float cov_id = id_line(lv, seed, vec2(u - du, p.y - (hh - 0.42)), id_h);
		albedo = mix(albedo, ink_col, cov_id * 0.9 * lettering);
	} else if (part == 3 && lettering > 0.0) {
		// Door end, seen from outside (+x): u runs along -z. The ID and size code top right,
		// the mark and name top left, the CSC plate low on the left.
		float u = -p.z;
		float id_h = 0.085;
		float cov = id_line(lv, seed, vec2(u - 0.12, p.y - (hh - 0.52)), id_h);
		cov = max(cov, code_line(vec2(u - 0.12, p.y - (hh - 0.72)), 0.075));
		if (MARK[lv] >= 0) {
			vec2 mc = (vec2(u, p.y) - vec2(-0.62, hh - 0.62)) / 0.24;
			float fw = max(fwidth(mc.x), fwidth(mc.y));
			if (abs(mc.x) < 1.2 && abs(mc.y) < 1.2) {
				cov = max(cov, mark(MARK[lv], mc, fw));
			}
			float nh = 0.1;
			cov = max(cov, name_line(lv, vec2(u - (-0.62 - name_width(lv, nh) * 0.5), p.y - (hh - 1.02)), nh));
		}
		albedo = mix(albedo, ink_col, cov * lettering);
		// CSC safety approval plate: a small riveted grey plate on the left leaf.
		vec2 pc = vec2(u + 0.72, p.y - (-0.72));
		if (abs(pc.x) < 0.16 && abs(pc.y) < 0.1) {
			albedo = col(vec3(0.42, 0.42, 0.4));
			rough = 0.45;
			metal = 0.3;
		}
		// Where the locking bars stand: at the far level they are drawn, at the near ones this
		// reads as their shadow on the leaf.
		float bz = abs(p.z);
		float bar = max(1.0 - smoothstep(0.012, 0.03, abs(bz - 0.24)), 1.0 - smoothstep(0.012, 0.03, abs(bz - 0.66)));
		bar *= step(abs(p.y), hh - 0.2);
		shade *= mix(1.0, 0.72, bar);
	} else if (part == 2 && lettering > 0.0) {
		float u = p.z;
		float cov = id_line(lv, seed, vec2(u - 0.1, p.y - (hh - 0.5)), 0.085);
		albedo = mix(albedo, ink_col, cov * lettering);
	}
	// --- Materials that are not paint.
	if (part == 8) {
		albedo = col(vec3(0.05, 0.045, 0.04));
		rough = 0.9;
	} else if (part == 7) {
		albedo = col(vec3(0.03, 0.03, 0.03));
		rough = 0.7;
	} else if (part == 6) {
		// Locking gear: galvanised on a third of the boxes, painted with the box on the rest.
		if (hash12(vec2(seed * 31.0, 5.0)) < 0.33) {
			albedo = col(vec3(0.48, 0.48, 0.46));
			metal = 0.55;
			rough = 0.45;
		} else {
			albedo = paint * 0.82;
		}
	} else if (part == 5) {
		albedo = paint * 0.8;
		rough = 0.78;
		// The castings' openings: an oval slot on the side and the end, a long one on top.
		vec3 cn = abs(v_nrm);
		vec3 q = vec3(hl - abs(p.x), hh - abs(p.y), HW - abs(p.z));
		float hole = 1e3;
		if (cn.z > 0.5) {
			hole = length((vec2(q.x, q.y) - vec2(0.089, 0.059)) / vec2(0.055, 0.03)) - 1.0;
		} else if (cn.x > 0.5) {
			hole = length((vec2(q.z, q.y) - vec2(0.081, 0.059)) / vec2(0.04, 0.03)) - 1.0;
		} else {
			hole = length((vec2(q.x, q.z) - vec2(0.089, 0.081)) / vec2(0.062, 0.03)) - 1.0;
		}
		albedo *= mix(0.12, 1.0, smoothstep(-0.1, 0.1, hole));
	}
	// --- Weathering.
	bool painted = part <= 6 && part != 7;
	if (painted && weathering > 0.0) {
		float h_up = p.y + hh;
		vec3 rust = col(vec3(0.33, 0.15, 0.07));
		vec3 dirt = col(vec3(0.22, 0.19, 0.15));
		// Sun fade, strongest on the roof.
		float fade = wear * (part == 1 ? 0.45 : 0.2);
		vec3 bleached = mix(albedo, vec3(dot(albedo, vec3(0.3, 0.55, 0.15))) * 1.25 + col(vec3(0.05)), 0.6);
		albedo = mix(albedo, bleached, fade);
		// Repaint patches: blocks of the side in a slightly different shade of the livery.
		if (part == 0 || part == 3) {
			vec2 cell = floor(vec2(p.x / 1.35 + seed * 13.0, p.y / 0.95 + face_z * 2.0));
			float hp = hash12(cell + seed * 7.0);
			if (hp < 0.05 + wear * 0.08) {
				float tone = mix(0.84, 1.1, hash12(cell * 1.3 + 2.0));
				albedo *= vec3(tone, tone * 0.98, tone * 1.02);
				edge_line *= 0.5;
			}
		}
		// Rust weeping down from the top rail and hinge points: thin vertical streaks, denser
		// near the top, where water runs off the roof.
		if (part == 0 || part == 2 || part == 3) {
			float along = part == 0 ? p.x : p.z;
			float lane = floor(along * 9.0 + seed * 40.0);
			float start = hash12(vec2(lane, seed * 3.0 + face_z));
			float streak_len = mix(0.15, 1.6, hash12(vec2(lane, 7.0 + seed))) * (0.4 + wear);
			float from_top = hh - 0.1 - p.y;
			float streak = step(1.0 - wear * 0.45 - 0.04, start) * (1.0 - smoothstep(0.0, streak_len, from_top));
			streak *= smoothstep(0.35, 0.65, noise(vec2(along * 40.0, p.y * 2.0 + seed * 9.0)));
			albedo = mix(albedo, rust, streak * 0.6);
			rough = mix(rough, 0.85, streak);
		}
		// A rusty, dirty foot: the bottom rail, the panel's lower edge, the castings.
		float foot = 1.0 - smoothstep(0.0, 0.18 + 0.3 * noise(vec2(p.x * 3.0 + p.z * 3.0, seed * 10.0)), h_up);
		float pits = smoothstep(0.55, 0.8, noise(p.xz * 11.0 + p.y * 7.0 + seed * 20.0));
		albedo = mix(albedo, rust, clamp(foot * (0.25 + wear * 0.55) + pits * wear * 0.35 * foot, 0.0, 0.85));
		if (part == 5) {
			albedo = mix(albedo, rust, 0.25 + wear * 0.5 * noise(p.xy * 30.0));
		}
		// Road dirt thrown up the lowest half metre, and grime everywhere a little.
		float grime = (1.0 - smoothstep(0.0, 0.55, h_up)) * 0.35 + 0.08;
		albedo = mix(albedo, albedo * 0.55 + dirt * 0.3, grime * (0.35 + wear * 0.5) * noise(vec2(p.x * 1.7 + p.z, p.y * 5.0 + seed * 5.0)));
		// Dents: slow wobbles in the panels.
		if (panel) {
			float dn = noise(vec2(p.x * 1.3 + p.z * 1.3 + seed * 17.0, p.y * 1.9));
			float dn2 = noise(vec2(p.x * 1.3 + p.z * 1.3 + seed * 17.0 + 0.4, p.y * 1.9));
			slope += (dn2 - dn) * wear * 1.8 * float(part != 1);
		}
	}
	albedo *= shade * (1.0 - edge_line);
	// Rain sheen: wet paint is darker and glossier, and the roofs hold water.
	float wet = clamp(road_wetness, 0.0, 1.0) * (part == 1 ? 1.0 : 0.6);
	albedo *= 1.0 - wet * 0.25;
	rough = mix(rough, 0.18, wet);
	// Tilt the normal along the flutes (view space; see the header).
	if (slope != 0.0 && panel) {
		NORMAL = normalize(NORMAL + v_pat * slope * slope_gain);
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.45;
}
