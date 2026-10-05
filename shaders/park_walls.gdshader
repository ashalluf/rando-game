shader_type spatial;
render_mode cull_back;

// Everything upright in the rec parks and schools (Parks, ParkKit) as ONE material: a chunk's
// fences, nets, hoops, goals, bleachers, playgrounds, floodlights and buildings are one mesh and
// one draw. Each box says what it is in COLOR.a (ParkKit.K_*, in 32nds) and carries its paint in
// COLOR.rgb (display numbers); UV is metres in the face's own frame (x along the face from its left
// corner seen from outside, y up from the box's foot), UV2.x the box's height, UV2.y a parameter.
//    0 painted steel   1 galvanised   2 chain-link (cut out)   3 windscreen fabric
//    4 net (cut out; UV2.y the mesh pitch)   5 basketball net (cut out; UV2.y 1 chain)
//    6 backboard (white, the shooter's square)   7 playground plastic   8 rubber
//    9 aluminium planks   10 concrete block   11 stucco (UV2.y what its faces carry: 1 classroom
//      windows, 2 with doors, 3 a clerestory band, 4 a bungalow's windows and door)
//   12 roof membrane   13 glass   14 lamp lens (lit after dark)   15 wood   16 concrete
//   17 chalk white   18 metal deck canopy (standing seams)   19 door

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D planks_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float lamp_factor;
global uniform float night_factor;
global uniform float road_wetness;
global uniform vec4 sky_tint;

varying float kind;
varying vec3 world_n;
varying vec3 world_p;

#include "res://shaders/color_space.gdshaderinc"

vec3 disp(vec3 c) {
	return cs_linear_renderer() ? cs_linear_to_srgb(c) : c;
}

vec3 to_lit(vec3 c) {
	return cs_linear_renderer() ? cs_srgb_to_linear(c) : c;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

// 1 on lines every `spacing` along v, `w` wide, box-filtered.
float lines(float v, float spacing, float w) {
	float g = abs(fract(v / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(v), 0.0005);
	float cov = clamp((0.5 * (w + fw) - g) / fw, 0.0, 1.0) * min(1.0, w / fw);
	return cov;
}

float box_in(vec2 p, vec2 lo, vec2 hi) {
	vec2 fw = max(fwidth(p), vec2(0.0005));
	vec2 a = clamp((p - lo) / fw + 0.5, 0.0, 1.0) * clamp((hi - p) / fw + 0.5, 0.0, 1.0);
	return a.x * a.y;
}

// A mesh of wires (`pitch` apart, `wire` thick in cells) cut out of the face; dithered to its
// average cover once a cell is a few pixels.
void cutout(vec2 d, float wire, float avg_scale, vec2 frag) {
	vec2 f = abs(fract(d) - 0.5);
	float dist = 0.5 - max(f.x, f.y);
	float fw = max(fwidth(d.x), fwidth(d.y));
	float line = 1.0 - smoothstep(wire, wire + fw, dist);
	float avg = 1.0 - (1.0 - 2.0 * wire) * (1.0 - 2.0 * wire);
	float cover = mix(line, avg * avg_scale, smoothstep(0.25, 0.7, fw));
	if (cover < bayer4(frag)) {
		discard;
	}
}

// A window: dark glass mirroring the sky (emitted), its frame, a blind, a lit room at night.
void window(vec2 cell, vec2 size, vec2 id, vec3 viewdir, vec3 n, inout vec3 albedo, inout vec3 emit, inout float rough, inout float metal) {
	float frame = 1.0 - box_in(cell, vec2(0.05), size - vec2(0.05));
	float mull = lines(cell.x - size.x * 0.5, 100.0, 0.05) * step(1.6, size.x);
	float r = hash12(id * 1.37 + 3.1);
	float blind = step(size.y * (0.55 + 0.4 * r), cell.y) * step(0.35, r);
	vec3 glass = vec3(0.10, 0.13, 0.15);
	float fres = pow(1.0 - clamp(dot(viewdir, n), 0.0, 1.0), 3.0);
	vec3 sky = disp(sky_tint.rgb);
	vec3 g_emit = sky * (0.12 + 0.6 * fres);
	vec3 room = mix(vec3(0.85, 0.80, 0.62), vec3(0.75, 0.85, 0.95), step(0.5, hash12(id + 9.0)));
	float lit = step(0.45, hash12(id + 17.0)) * lamp_factor;
	g_emit += room * lit * 0.9 * (blind > 0.5 ? 0.5 : 1.0);
	vec3 a = mix(glass, vec3(0.86, 0.84, 0.78) * 0.5, blind * 0.6);
	float fm = max(frame, mull);
	albedo = mix(a, vec3(0.62, 0.64, 0.66), fm);
	emit = mix(g_emit, vec3(0.0), fm);
	rough = mix(0.08, 0.45, fm);
	metal = mix(0.0, 0.6, fm);
}

void vertex() {
	kind = floor(COLOR.a * 32.0);
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float h = max(UV2.x, 0.01);
	float param = UV2.y;
	bool top = world_n.y > 0.5;
	vec3 paint = COLOR.rgb;
	vec3 albedo = paint;
	float rough = 0.8;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float glow = 0.0;
	int k = int(kind + 0.5);
	float foot = 1.0 - smoothstep(0.0, 0.35, uv.y);
	if (k == 0 || k == 19) {
		// Painted steel: scuffed, a little rust at the edges and foot.
		float rust = smoothstep(0.72, 0.92, vnoise(uv * 3.1 + paint.rg * 9.0)) * 0.5 + foot * 0.15;
		albedo = mix(paint * (0.93 + 0.1 * vnoise(uv * 7.0)), vec3(0.36, 0.22, 0.14), clamp(rust, 0.0, 0.5));
		rough = mix(0.45, 0.85, rust);
		metal = 0.25;
		if (k == 19) {
			albedo *= 1.0 - 0.25 * (1.0 - box_in(uv, vec2(0.12), vec2(0.78, h - 0.12)));
		}
	} else if (k == 1) {
		// Galvanised: spangled, dulled to grey with age.
		albedo = paint * (0.85 + 0.2 * vnoise(uv * vec2(9.0, 2.0)) + 0.08 * (hash12(floor(uv * 30.0)) - 0.5));
		metal = 0.7;
		rough = 0.42;
	} else if (k == 2) {
		vec2 q = uv / 0.055;
		cutout(vec2(q.x + q.y, q.x - q.y), 0.09, 0.8, FRAGCOORD.xy);
		albedo = paint * (0.85 + 0.25 * vnoise(uv * 3.0));
		metal = 0.6;
		rough = 0.45;
	} else if (k == 3) {
		// Windscreen: a woven polyester mesh, nearly opaque, a sheen of the weave, grommets.
		vec2 q = uv / 0.004;
		float weave = 0.5 + 0.5 * sin(q.x) * sin(q.y);
		float fine = 1.0 - smoothstep(0.0008, 0.003, fwidth(uv.x));
		albedo = paint * (0.92 + 0.12 * weave * fine) * (0.95 + 0.1 * vnoise(uv * 0.8));
		float grommet = 1.0 - smoothstep(0.015, 0.02, length(vec2(fract(uv.x / 0.6) - 0.5, (uv.y - h + 0.05) / 0.6) * 0.6));
		albedo = mix(albedo, vec3(0.75), grommet);
		if (0.88 < bayer4(FRAGCOORD.xy) && fine > 0.5 && weave < 0.25) {
			discard;
		}
		rough = 0.75;
	} else if (k == 4) {
		float pitch = max(param, 0.02);
		vec2 q = uv / pitch;
		cutout(q, 0.06, 0.55, FRAGCOORD.xy);
		rough = 0.8;
	} else if (k == 5) {
		// A hoop's net: cord diamonds narrowing to the bottom, or galvanised chain links.
		vec2 q = vec2(uv.x / 0.09, uv.y / 0.075);
		cutout(vec2(q.x + q.y, q.x - q.y), param > 0.5 ? 0.14 : 0.1, 0.6, FRAGCOORD.xy);
		albedo = paint;
		metal = param > 0.5 ? 0.7 : 0.0;
		rough = param > 0.5 ? 0.4 : 0.9;
	} else if (k == 6) {
		// Backboard: white with the black (orange on some) border and the shooter's square.
		vec2 b = uv;
		float border = 1.0 - box_in(b, vec2(0.05), vec2(1.75, 1.0));
		float sq = max(1.0 - box_in(b, vec2(0.6, 0.15), vec2(1.2, 0.6)), box_in(b, vec2(0.65, 0.2), vec2(1.15, 0.55)));
		sq = 1.0 - box_in(b, vec2(0.6, 0.15), vec2(1.2, 0.6)) + box_in(b, vec2(0.65, 0.2), vec2(1.15, 0.55));
		float mark = max(border, (1.0 - sq) * box_in(b, vec2(0.55, 0.1), vec2(1.25, 0.65)));
		albedo = mix(paint * (0.9 + 0.08 * vnoise(b * 4.0)), vec3(0.06, 0.06, 0.07), mark);
		rough = 0.5;
	} else if (k == 7) {
		// Playground plastic: rotomoulded, a soft gloss, faded by the sun on its tops.
		albedo = paint * (top ? 0.88 : 1.0) * (0.95 + 0.06 * vnoise(uv * 2.0));
		rough = 0.45;
	} else if (k == 8) {
		albedo = paint * (0.9 + 0.1 * vnoise(uv * 5.0));
		rough = 0.92;
	} else if (k == 9) {
		// Aluminium planks: extruded ribs along their length.
		float rib = lines(top ? uv.y : uv.y, 0.04, 0.012);
		albedo = paint * (0.9 + 0.1 * vnoise(uv * vec2(0.5, 9.0))) * (1.0 - 0.15 * rib);
		metal = 0.75;
		rough = 0.38;
	} else if (k == 10) {
		// Concrete block: 40 x 20 cm courses, running bond, mortar joints.
		vec2 b = uv / vec2(0.40, 0.20);
		b.x += floor(b.y) * 0.5;
		float j = max(lines(b.x * 0.40, 0.40, 0.01), lines(uv.y, 0.20, 0.01));
		vec3 t = disp(texture(concrete_tex, uv / 3.0).rgb);
		albedo = paint * (0.85 + 0.25 * dot(t, vec3(0.33))) * (0.92 + 0.12 * hash12(floor(b))) * (1.0 - 0.25 * j);
		rough = 0.9;
	} else if (k == 11 || k == 12 || k == 16) {
		// Stucco (a sand finish), the roof membrane, plain concrete.
		vec3 t = disp(texture(concrete_tex, (uv + world_p.xz * 0.0) / 3.5).rgb);
		float l = dot(t, vec3(0.33)) / 0.55;
		albedo = paint * mix(0.9, 1.06, clamp(l - 0.3, 0.0, 1.0)) * (0.96 + 0.06 * vnoise(uv * 0.6));
		// Dirt down from the top and splash up at the foot.
		albedo *= 1.0 - 0.08 * foot - 0.06 * smoothstep(0.6, 1.0, vnoise(vec2(uv.x * 1.3, 0.5))) * smoothstep(h - 1.5, h, uv.y);
		rough = k == 12 ? 0.75 : 0.9;
		if (k == 11 && !top && abs(world_n.y) < 0.5 && param > 0.5) {
			vec3 vd = normalize(VIEW);
			vec3 n = NORMAL;
			int pk = int(param + 0.5);
			if (pk == 1 || pk == 2) {
				float storey = 3.9;
				float fl = floor(uv.y / storey);
				vec2 cell = vec2(mod(uv.x, 3.6), uv.y - fl * storey);
				vec2 id = vec2(floor(uv.x / 3.6), fl) + floor(world_p.xz * 0.1);
				bool door = pk == 2 && fl < 0.5 && mod(floor(uv.x / 3.6), 3.0) < 0.5;
				if (door) {
					vec2 dc = cell - vec2(1.25, 0.0);
					if (dc.x > 0.0 && dc.x < 1.1 && dc.y < 2.2) {
						albedo = vec3(0.16, 0.30, 0.48) * (1.0 - 0.3 * (1.0 - box_in(dc, vec2(0.08), vec2(1.02, 2.12))));
						albedo = mix(albedo, vec3(0.2, 0.25, 0.3), box_in(dc, vec2(0.3, 1.2), vec2(0.8, 1.9)));
						rough = 0.5;
					}
				} else if (cell.x > 0.5 && cell.x < 3.1 && cell.y > 1.0 && cell.y < 2.75 && uv.x > 0.3 && uv.y < h - 0.3) {
					window(cell - vec2(0.5, 1.0), vec2(2.6, 1.75), id, vd, n, albedo, emit, rough, metal);
				}
			} else if (pk == 3) {
				float y0 = h - 2.0;
				if (uv.y > y0 && uv.y < h - 0.8 && uv.x > 0.6) {
					vec2 cell = vec2(mod(uv.x, 1.5), uv.y - y0);
					window(cell, vec2(1.5, 1.2), vec2(floor(uv.x / 1.5), 0.0) + floor(world_p.xz * 0.1), vd, n, albedo, emit, rough, metal);
				}
			} else if (pk == 4) {
				vec2 cell = vec2(mod(uv.x, 3.0), uv.y);
				if (cell.x > 0.9 && cell.x < 2.1 && cell.y > 1.0 && cell.y < 2.0) {
					window(cell - vec2(0.9, 1.0), vec2(1.2, 1.0), vec2(floor(uv.x / 3.0), 0.0) + floor(world_p.xz * 0.1), vd, n, albedo, emit, rough, metal);
				}
			}
		}
	} else if (k == 13) {
		float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.0);
		albedo = vec3(0.08, 0.10, 0.12);
		emit = disp(sky_tint.rgb) * (0.15 + 0.6 * fres) + vec3(0.9, 0.85, 0.7) * lamp_factor * 0.8;
		rough = 0.06;
	} else if (k == 14) {
		// A floodlight's lens: pale by day, blazing after dark.
		albedo = vec3(0.78, 0.80, 0.80);
		emit = vec3(1.0, 0.97, 0.9);
		glow = lamp_factor * 8.0;
		rough = 0.2;
	} else if (k == 15) {
		vec3 t = disp(texture(planks_tex, uv * vec2(0.6, 1.0) / 2.0).rgb);
		albedo = paint * (0.75 + 0.5 * dot(t, vec3(0.33)));
		rough = 0.85;
	} else if (k == 17) {
		albedo = paint;
		rough = 0.85;
	} else if (k == 18) {
		// A metal deck canopy: standing seams every 0.6 m (across its width).
		float seam = lines(uv.x, 0.6, 0.04);
		albedo = paint * (1.0 - 0.18 * seam) * (0.94 + 0.08 * vnoise(uv * 1.5));
		metal = 0.45;
		rough = 0.45;
	}
	albedo *= 1.0 - 0.2 * road_wetness * (top ? 1.0 : 0.4);
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = to_lit(clamp(emit, vec3(0.0), vec3(1.0))) * (1.0 + glow);
}
