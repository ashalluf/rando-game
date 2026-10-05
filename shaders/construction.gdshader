shader_type spatial;
render_mode cull_disabled;

// Everything on a building site (Construction, ConstructionKit) as ONE material: a chunk's tower
// frame, core, slabs, formwork, rebar, safety netting, guardrails, hoist, hoarding with its
// developer graphics and covered walkway, site cabins, skips, timber house frames, road works
// (cones, drums, the arrow board, trench plates, the excavator) and the ground are one mesh and
// one draw (the ground a second, shadowless instance of the same material). A tower crane is its
// own node on the same shader with `crane` on: its slewing parts turn about the node's origin,
// the trolley runs out along the jib and the hook rises and falls, all from TIME here - nothing
// per crane runs on the CPU.
//
// Vertex layout (ConstructionKit's writers):
//   COLOR.rgb  the paint as written (display numbers; vertex colours arrive raw on both renderers)
//   COLOR.a    the kind (K_* below / ConstructionKit.K_*), in 32nds
//   UV         metres in the face's own frame (x along the face from its left corner seen from
//              outside, y up from the box's foot; a top face: x and z from the box's corner)
//   UV2.x      the box's height, or a per-part parameter (a kind's comment says which)
//   UV2.y      the crane animation code (0 static, 1 slews, 2 the trolley, 3 the hook block,
//              4 the hoist rope) - only read with `crane` on
// Kinds:
//    0 concrete          1 formwork plywood    2 rebar           3 painted steel
//    4 galvanised        5 safety net (cut)    6 lattice (cut)   7 hoarding (UV2.x the panel run)
//    8 lumber            9 OSB                10 house wrap      11 curtain-wall glass
//   12 lamp (red at night, the paint's colour) 13 plastic        14 traffic cone (UV2.x height)
//   15 drum (UV2.x height)                     16 rubber         17 arrow board LEDs
//   18 matte paint      19 site dirt          20 gravel          21 lettering
//   22 steel plate      23 site cabin (UV2.x the window pitch)    24 sign face (retro)
//   25 rebar mat (cut)  26 lit strip (warm white at night)        27 tinted cab glass
// Developer names and graphics are invented; nothing here is a real company's.

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D planks_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// The tower crane (ConstructionKit.crane_mesh(); constants mirrored there and checked).
uniform bool crane = false;
// Height of the jib's underside over the node's origin (the slewing ring), metres.
uniform float jib_y = 1.6;
// Seconds for one full swing cycle (pick to drop and back), and the swing's half angle.
uniform float slew_period = 150.0;
uniform float slew_amp = 1.25;
// Seconds for a trolley run out and back, and a hook drop and lift.
uniform float trolley_period = 74.0;
uniform float hook_period = 52.0;
// Aviation lights after dark, and the arrow board's flash.
uniform float lamp_energy = 4.0;
uniform float arrow_energy = 3.0;

global uniform float road_wetness;
global uniform float lamp_factor;
global uniform float night_factor;
global uniform vec4 sky_tint;
global uniform vec3 origin_shift;

varying float kind;
varying vec3 world_n;
varying vec3 world_p;

#include "res://shaders/color_space.gdshaderinc"

// Tuned in display (sRGB) numbers - what Compatibility hands a shader and what the paint in
// COLOR is on both renderers; Forward+'s decoded textures go back to display numbers (disp())
// and the result goes out in the renderer's own space (to_lit()), as industrial_walls does.
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

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.3) * 0.2;
}

// 1 in a line every `spacing`, `w` wide, faded to its average once under a few pixels.
float lines(float v, float spacing, float w) {
	float g = abs(fract(v / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(v), 0.0005);
	float fade = 1.0 - smoothstep(0.05, 0.2, fw / spacing * 2.0);
	return mix(w / spacing, 1.0 - smoothstep(w * 0.5, w * 0.5 + fw, g), fade);
}

float band(float v, float c, float w) {
	float fw = max(fwidth(v), 0.0005);
	return 1.0 - smoothstep(w, w + fw, abs(v - c));
}

// Screen-space ordered dither, for the cut-out kinds once their strands are under a pixel.
float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

// A strand pattern with `spacing` between strands `w` wide: 1 on a strand. Past a pixel it is
// kept by its coverage, dithered (TAA resolves it on Forward+).
float strands(vec2 v, vec2 spacing, float w, vec2 frag) {
	vec2 fw = max(fwidth(v), vec2(0.0005));
	vec2 g = abs(fract(v / spacing + 0.5) - 0.5) * spacing;
	vec2 on = 1.0 - smoothstep(vec2(w * 0.5), vec2(w * 0.5) + fw, g);
	float sharp = max(on.x, on.y);
	float cover = clamp(w / spacing.x + w / spacing.y, 0.0, 1.0);
	float blur = smoothstep(0.25, 0.7, max(fw.x / spacing.x, fw.y / spacing.y));
	float keep = mix(sharp, step(bayer4(frag), cover), blur);
	return keep;
}

// The crane's angles at time t for a crane standing at true world `at` (its phase from there, so
// two cranes never swing together): x the slew, y the trolley's run 0..1, z the hook's drop 0..1.
// After dark it settles (the operator has gone home; a parked crane weathervanes slowly).
vec3 crane_state(vec2 at, float t) {
	float ph = hash12(floor(at * 0.37)) * 6.2831;
	float work = 1.0 - smoothstep(0.35, 0.85, lamp_factor);
	// A swing out and back with dwells at each end (smoothstep of a sine).
	float s = sin(t * 6.2831 / slew_period + ph);
	float slew = ph * 3.0 + slew_amp * (s * (1.5 - 0.5 * s * s)) * work + 0.25 * sin(t * 0.004 + ph) * (1.0 - work);
	float tr = 0.5 + 0.5 * sin(t * 6.2831 / trolley_period + ph * 2.0);
	tr = mix(0.35, tr, work);
	float hk = 0.5 + 0.5 * sin(t * 6.2831 / hook_period + ph * 5.0);
	hk = mix(0.1, hk, work);
	return vec3(slew, tr, hk);
}

void vertex() {
	kind = floor(COLOR.a * 32.0);
	if (crane) {
		int code = int(UV2.y + 0.5);
		if (code > 0) {
			vec2 at = MODEL_MATRIX[3].xz + origin_shift.xz;
			vec3 st = crane_state(at, TIME);
			vec3 v = VERTEX;
			vec3 n = NORMAL;
			if (code >= 2) {
				// The trolley rig rides out along +x: UV2.x packs the jib's length (whole metres,
				// times 1000) and the hook's longest drop (metres).
				float jib = floor(UV2.x / 1000.0);
				float drop_max = UV2.x - jib * 1000.0;
				float x = mix(7.0, jib - 4.0, st.y);
				v.x += x;
				float drop = mix(4.0, max(drop_max, 4.5), st.z);
				if (code == 3) {
					v.y -= drop - 1.0;
				} else if (code == 4) {
					// Built 1 m long hanging from the jib: stretched to the drop.
					v.y = jib_y - (jib_y - v.y) * drop;
				}
			}
			float c = cos(st.x);
			float s = sin(st.x);
			v.xz = vec2(c * v.x - s * v.z, s * v.x + c * v.z);
			n.xz = vec2(c * n.x - s * n.z, s * n.x + c * n.z);
			VERTEX = v;
			NORMAL = n;
		}
	}
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float h = max(UV2.x, 0.01);
	vec3 paint = COLOR.rgb;
	vec3 albedo = paint;
	float rough = 0.85;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	bool top = world_n.y > 0.5;
	vec2 tw = world_p.xz + origin_shift.xz;
	float wet = road_wetness;
	int k = int(kind + 0.5);
	if (k == 0) {
		// Concrete: the texture as detail, pour lines every storey, form-tie holes in a grid on
		// walls, darker fresh concrete near the top of the pour, dust on top faces.
		vec2 t2 = top ? tw : uv;
		vec3 c = disp(texture(concrete_tex, t2 / 3.0).rgb);
		float tone = dot(c, vec3(0.333));
		albedo = paint * (0.62 + 0.62 * tone);
		if (!top) {
			float pour = lines(uv.y, 3.6, 0.03);
			albedo *= 1.0 - 0.18 * pour;
			vec2 tg = abs(fract(uv / vec2(0.6, 0.9) + 0.5) - 0.5) * vec2(0.6, 0.9);
			float tie = 1.0 - smoothstep(0.012, 0.022, length(tg));
			albedo *= 1.0 - 0.45 * tie * step(0.3, h);
			albedo *= 0.9 + 0.1 * vnoise(uv * vec2(0.6, 3.0));
			// Rust and water streaks down from the slab edges.
			float st = smoothstep(0.55, 0.9, vnoise(vec2(uv.x * 1.3, uv.y * 0.12)));
			albedo *= 1.0 - 0.12 * st;
		} else {
			albedo *= 0.92 + 0.12 * fbm(tw * 0.7);
		}
		rough = 0.9;
	} else if (k == 1) {
		// Formwork: film-faced plywood panels in the paint (the forms' own colour), 1.22 x 2.44
		// sheets with dark joints, wear and concrete splash.
		float j = max(lines(uv.x, 1.22, 0.012), lines(uv.y, 2.44, 0.012));
		albedo = paint * (0.85 + 0.2 * fbm(uv * vec2(1.5, 6.0))) * (1.0 - 0.35 * j);
		float splash = smoothstep(0.6, 0.8, fbm(uv * 0.9 + 3.0));
		albedo = mix(albedo, vec3(0.62, 0.61, 0.58), splash * 0.6);
		rough = 0.55;
	} else if (k == 2 || k == 25) {
		// Rebar: rusted steel, a rib every 8 cm; the mat (25) is a grid of bars cut out of a quad.
		if (k == 25) {
			if (strands(uv, vec2(0.2, 0.2), 0.016, FRAGCOORD.xy) < 0.5) {
				discard;
			}
		}
		float rib = lines(uv.x + uv.y, 0.08, 0.02);
		albedo = mix(vec3(0.28, 0.15, 0.08), vec3(0.42, 0.26, 0.15), vnoise(tw * 3.0 + uv * 4.0)) * (1.0 - 0.25 * rib);
		metal = 0.5;
		rough = 0.8;
	} else if (k == 3) {
		// Painted steel: the paint, chipped on edges to dark steel, a little dirt.
		float chip = smoothstep(0.72, 0.78, fbm(uv * 4.0 + tw * 0.1));
		albedo = mix(paint * (0.9 + 0.1 * vnoise(uv * 2.0)), vec3(0.12, 0.11, 0.10), chip * 0.7);
		rough = 0.5;
		metal = 0.25;
	} else if (k == 4 || k == 22) {
		// Galvanised steel (scaffold, props) or a trench plate (dark, worn bright by tyres).
		if (k == 4) {
			albedo = vec3(0.62, 0.63, 0.62) * (0.85 + 0.2 * fbm(uv * 3.0));
			metal = 0.7;
			rough = 0.45;
		} else {
			float worn = smoothstep(0.35, 0.8, fbm(uv * 1.2 + tw * 0.2));
			albedo = mix(vec3(0.16, 0.15, 0.14), vec3(0.42, 0.41, 0.39), worn) * (1.0 - 0.3 * smoothstep(0.6, 0.9, vnoise(uv * 6.0)));
			metal = 0.6;
			rough = mix(0.55, 0.3, worn);
		}
	} else if (k == 5) {
		// Safety netting: knotted mesh in the paint, 10 cm squares; see-through.
		vec2 d = uv * mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071));
		if (strands(d, vec2(0.1, 0.1), 0.012, FRAGCOORD.xy) < 0.5) {
			discard;
		}
		albedo = paint * (0.8 + 0.2 * vnoise(uv * 0.5));
		rough = 0.9;
	} else if (k == 6) {
		// A lattice face (crane mast, jib, hoist mast): chords along both edges, horizontals at
		// each panel and a diagonal through every panel, cut out between them. UV2.x is the
		// face's width (the box writer gives its height; the crane writer the width).
		float wdt = max(UV2.x, 0.3);
		float pitch = wdt * 1.15;
		float py = fract(uv.y / pitch);
		float fwx = max(fwidth(uv.x), 0.0005);
		float edge = 1.0 - smoothstep(0.07, 0.07 + fwx, min(uv.x, wdt - uv.x));
		float horiz = band(py * pitch, 0.0, 0.05);
		float diag_d = abs(uv.x / wdt - (mod(floor(uv.y / pitch), 2.0) < 0.5 ? py : 1.0 - py)) * wdt;
		float diag = 1.0 - smoothstep(0.045, 0.045 + fwx * 1.5, diag_d);
		float on = max(edge, max(horiz, diag));
		// Once the lacing is under a pixel or two the face is drawn solid, darkened to what a
		// lattice face averages (the sky through it, the steel's shadowed inner faces): a far mast
		// dithered to a third of its pixels without TAA read as a faint dotted line.
		float ratio = fwx / wdt;
		float solid = smoothstep(0.025, 0.07, ratio);
		if (on < 0.5 && solid < 0.5) {
			discard;
		}
		float chip = smoothstep(0.75, 0.8, fbm(uv * 5.0));
		albedo = mix(paint, vec3(0.2, 0.18, 0.16), chip * 0.5) * (0.88 + 0.12 * vnoise(uv * 3.0));
		albedo *= mix(1.0, 0.62, solid * (1.0 - on));
		rough = 0.5;
		metal = 0.2;
	} else if (k == 7) {
		// Site hoarding: painted plywood in the developer's colourway (UV2.x picks it), sheet
		// joints, a band of the second colour, a rendering of the tower to come on the long
		// runs (a sunset sky, the tower's glass, its window grid), flyposting low on it.
		int way = int(mod(floor(h + 0.5), 4.0));
		vec3 base[4] = vec3[](vec3(0.08, 0.14, 0.24), vec3(0.12, 0.20, 0.17), vec3(0.17, 0.16, 0.16), vec3(0.88, 0.86, 0.80));
		vec3 accent[4] = vec3[](vec3(0.86, 0.62, 0.30), vec3(0.78, 0.86, 0.80), vec3(0.88, 0.34, 0.20), vec3(0.14, 0.32, 0.46));
		vec3 b = base[way];
		vec3 ac = accent[way];
		albedo = b;
		float stripe = band(uv.y, 2.05, 0.06);
		albedo = mix(albedo, ac, stripe);
		// The rendering: one panel per 18 m of run.
		float cell = floor(uv.x / 18.0);
		vec2 q = vec2(fract(uv.x / 18.0), uv.y / 2.4);
		float show = step(0.42, hash12(vec2(cell, floor(h * 7.0))));
		if (show > 0.5 && q.x > 0.1 && q.x < 0.48 && q.y > 0.12 && q.y < 0.92) {
			vec2 r = vec2((q.x - 0.1) / 0.38, (q.y - 0.12) / 0.8);
			vec3 sky = mix(vec3(0.98, 0.70, 0.45), vec3(0.32, 0.46, 0.70), r.y);
			albedo = sky;
			float tower = step(abs(r.x - 0.5), 0.16 + 0.04 * step(r.y, 0.3)) * step(r.y, 0.92 - 0.06 * abs(r.x - 0.5));
			vec3 glass = mix(vec3(0.20, 0.30, 0.42), vec3(0.85, 0.66, 0.50), smoothstep(0.35, 0.65, r.x)) * (0.85 + 0.15 * r.y);
			float grid = max(lines(r.x * 30.0, 1.0, 0.12), lines(r.y * 48.0, 1.0, 0.18));
			albedo = mix(albedo, glass * (1.0 - 0.3 * grid), tower);
			albedo = mix(albedo, vec3(0.16, 0.24, 0.14), step(r.y, 0.07));
			float frame = 1.0 - step(0.02, min(min(r.x, 1.0 - r.x), min(r.y, 1.0 - r.y)));
			albedo = mix(albedo, ac, frame);
		}
		float j = lines(uv.x, 1.22, 0.006);
		albedo *= 1.0 - 0.25 * j;
		albedo *= 0.9 + 0.12 * vnoise(uv * vec2(0.4, 1.0));
		// Fly posters and tags low on the boards.
		vec2 pc = floor(uv / vec2(0.75, 0.6));
		float poster = step(0.86, hash12(pc + 11.0)) * step(uv.y, 1.8) * step(0.35, uv.y);
		vec3 pcol = mix(vec3(0.92, 0.88, 0.80), vec3(0.85, 0.25, 0.2), step(0.5, hash12(pc + 3.0)));
		albedo = mix(albedo, pcol * (0.8 + 0.2 * vnoise(uv * 9.0)), poster * (1.0 - stripe));
		albedo *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.35, uv.y));
		rough = 0.75;
	} else if (k == 8) {
		// Lumber: Douglas fir studs and joists, grain along the piece, a grade stamp now and then.
		float g = fbm(vec2(uv.x * 0.8 + uv.y * 0.8, (uv.x - uv.y) * 14.0));
		albedo = paint * (0.78 + 0.32 * g);
		vec2 piece = floor(tw * 0.8);
		albedo *= 0.9 + 0.15 * hash12(piece);
		rough = 0.8;
	} else if (k == 9) {
		// OSB sheathing: pressed flakes, 1.22 x 2.44 sheets with nail lines on the studs.
		vec2 f = uv * vec2(9.0, 22.0);
		float fl = vnoise(f) * 0.5 + vnoise(f * 1.9 + 4.0) * 0.3 + vnoise(uv * 40.0) * 0.2;
		albedo = paint * (0.72 + 0.45 * fl);
		float j = max(lines(uv.x, 1.22, 0.006), lines(uv.y, 2.44, 0.006));
		albedo *= 1.0 - 0.3 * j;
		float nails = lines(uv.x, 0.406, 0.01) * step(0.7, fract(uv.y / 0.15));
		albedo *= 1.0 - 0.2 * nails;
		rough = 0.85;
	} else if (k == 10) {
		// House wrap: white spun-bonded sheet, its maker's (invented, wordless) mark printed in
		// rows, seams with tape, a little sag between the studs.
		albedo = vec3(0.90, 0.91, 0.90);
		vec2 m = vec2(uv.x / 1.6, uv.y / 0.55);
		vec2 mc = fract(m + vec2(0.5 * mod(floor(m.y), 2.0), 0.0)) - 0.5;
		float mark = (1.0 - smoothstep(0.30, 0.33, abs(mc.x))) * (1.0 - smoothstep(0.18, 0.22, abs(mc.y)));
		float ring = band(length(mc * vec2(1.0, 2.6)), 0.24, 0.025);
		albedo = mix(albedo, vec3(0.30, 0.42, 0.66), max(mark * 0.15, ring * 0.6));
		float tape = band(uv.y, 2.74, 0.04) * 0.6;
		albedo = mix(albedo, vec3(0.92, 0.92, 0.9), tape);
		albedo *= 0.88 + 0.12 * (1.0 - lines(uv.x, 0.406, 0.08));
		rough = 0.6;
	} else if (k == 11) {
		// Curtain-wall glass on the finished floors: what it mirrors (the sky above the horizon,
		// the street and the city below it, by the reflected ray), each unit a hair off true so the
		// wall is not one sheet, mullions on a 1.5 m module and the slab line, the odd unit still in
		// its blue protective film.
		vec3 v = normalize(world_p - CAMERA_POSITION_WORLD);
		vec2 pnl = floor(uv / vec2(1.5, 3.6));
		vec3 nb = normalize(world_n + vec3(hash12(pnl) - 0.5, hash12(pnl + 3.1) - 0.5, hash12(pnl + 7.7) - 0.5) * 0.06);
		vec3 r = reflect(v, nb);
		float fres = 0.08 + 0.92 * pow(1.0 - clamp(abs(dot(v, nb)), 0.0, 1.0), 5.0);
		vec3 sky = sky_tint.rgb * mix(1.15, 0.75, clamp(r.y, 0.0, 1.0));
		vec3 city = mix(vec3(0.16, 0.16, 0.17), vec3(0.32, 0.31, 0.30), vnoise(vec2(atan(r.x, r.z) * 9.0, 0.5))) * (0.35 + 0.65 * (1.0 - night_factor));
		float above = smoothstep(-0.02, 0.12, r.y + 0.08 * vnoise(vec2(atan(r.x, r.z) * 6.0, 2.0)));
		vec3 mirror = mix(city, sky, above);
		float mull = max(lines(uv.x, 1.5, 0.06), lines(uv.y, 3.6, 0.14));
		float film = step(0.965, hash12(pnl + 5.0));
		albedo = mix(vec3(0.03, 0.045, 0.05), vec3(0.36, 0.48, 0.56), film);
		emit = mix(mirror * (0.25 + 0.75 * fres), vec3(0.0), film);
		albedo = mix(albedo, vec3(0.30, 0.31, 0.32), mull);
		emit *= 1.0 - mull;
		rough = mix(0.06, 0.6, max(mull, film));
		metal = mix(0.2, 0.4, mull);
		spec = 0.8;
	} else if (k == 12) {
		// A lamp: the aviation obstruction lights (red), work lights; dim by day, lit after dark.
		albedo = paint * 0.3;
		emit = paint * (0.6 + lamp_energy * max(lamp_factor, night_factor));
		rough = 0.3;
	} else if (k == 13) {
		// Moulded plastic (the toilet, barricades): the paint, glossy, a little sun fade.
		albedo = paint * (0.9 + 0.12 * vnoise(uv * 2.0));
		rough = 0.35;
	} else if (k == 14 || k == 15) {
		// A traffic cone (14) or a channelising drum (15): orange with retroreflective white bands.
		float v = uv.y / h;
		float white;
		if (k == 14) {
			white = step(0.48, v) * step(v, 0.62) + step(0.70, v) * step(v, 0.78);
		} else {
			white = step(0.10, fract(v * 2.0 + 0.04)) * step(fract(v * 2.0 + 0.04), 0.28) * step(v, 0.95);
		}
		vec3 orange = vec3(0.98, 0.36, 0.06);
		albedo = mix(orange, vec3(0.92, 0.92, 0.9), white);
		albedo *= 0.85 + 0.15 * vnoise(uv * vec2(3.0, 8.0) + tw);
		// Scuffs and road grime toward the base.
		albedo *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.25, v));
		rough = mix(0.45, 0.3, white);
		// The bands give back the headlights (and the camera's) at night.
		vec3 vd = normalize(CAMERA_POSITION_WORLD - world_p);
		emit = vec3(0.9) * white * lamp_factor * 0.6 * pow(clamp(dot(vd, world_n), 0.0, 1.0), 4.0);
	} else if (k == 16) {
		albedo = vec3(0.045, 0.045, 0.05) * (0.85 + 0.3 * vnoise(uv * 8.0));
		rough = 0.85;
	} else if (k == 17) {
		// The arrow board: a black panel of amber LED lamps (UV in metres across it) laid out as
		// a left arrow, flashing; the panel is self-lit day and night.
		vec2 g = uv / 0.16;
		vec2 cellc = floor(g) + 0.5;
		vec2 dd = (fract(g) - 0.5);
		float lamp = 1.0 - smoothstep(0.24, 0.34, length(dd));
		// The panel is 2.4 x 1.2 m: the arrow's shaft and head in lamp cells.
		vec2 c = cellc * 0.16;
		float shaft = step(0.5, c.x) * step(c.x, 2.2) * step(abs(c.y - 0.6), 0.1);
		float head = step(abs(c.y - 0.6), (c.x - 0.18) * 0.9) * step(c.x, 0.62) * step(0.18, c.x);
		float on = max(shaft, head);
		float flash = step(0.45, fract(TIME * 0.9));
		albedo = vec3(0.03);
		emit = vec3(1.0, 0.55, 0.08) * lamp * on * flash * arrow_energy * (0.7 + 0.6 * lamp_factor);
		albedo = mix(albedo, vec3(0.25, 0.2, 0.1), lamp * 0.3);
		rough = 0.4;
	} else if (k == 18) {
		// Matte paint (machines, cabins' frames, skips): the paint, worn, dirt toward the foot.
		albedo = paint * (0.88 + 0.14 * vnoise(uv * 1.5));
		float chip = smoothstep(0.78, 0.82, fbm(uv * 3.5 + tw * 0.07));
		albedo = mix(albedo, albedo * 0.45, chip);
		albedo *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.6, uv.y)) * step(0.3, h);
		rough = 0.6;
		metal = 0.1;
	} else if (k == 19 || k == 20) {
		// Site ground: compacted dirt with tyre tracks (19), crushed gravel (20).
		vec3 d = disp(texture(dirt_tex, tw / 4.0).rgb);
		float tracks = band(fract(tw.x / 7.0 + 0.2 * sin(tw.y * 0.05)), 0.5, 0.06) * 0.25;
		if (k == 19) {
			albedo = mix(vec3(dot(d, vec3(0.333))), d, 0.55) * vec3(0.78, 0.71, 0.62) * (0.8 + 0.2 * fbm(tw * 0.2)) * (1.0 - tracks);
			rough = 0.95;
		} else {
			float stones = vnoise(tw * 9.0) * 0.5 + vnoise(tw * 23.0) * 0.5;
			albedo = mix(vec3(0.46, 0.45, 0.43), vec3(0.62, 0.60, 0.56), stones) * (0.85 + 0.15 * d.r);
			rough = 0.9;
		}
		albedo *= paint;
	} else if (k == 21) {
		albedo = paint;
		rough = 0.6;
	} else if (k == 23) {
		// A site cabin: white ribbed panels, a window every UV2.x metres with a dark pane, a
		// frame and blinds; lit at night where somebody stayed late.
		float pitch = max(h, 1.0);
		float ribs = lines(uv.x, 0.3, 0.04);
		albedo = paint * (0.9 - 0.12 * ribs);
		vec2 w = vec2(fract(uv.x / pitch), uv.y);
		float win = step(0.25, w.x) * step(w.x, 0.75) * step(1.05, w.y) * step(w.y, 2.0);
		float frame = win * (1.0 - step(0.27, w.x) * step(w.x, 0.73) * step(1.08, w.y) * step(w.y, 1.97));
		albedo = mix(albedo, vec3(0.06, 0.07, 0.08), win);
		albedo = mix(albedo, vec3(0.75, 0.75, 0.74), frame);
		float lit = step(0.7, hash12(floor(tw * 0.13) + floor(uv.x / pitch)));
		emit = vec3(1.0, 0.85, 0.6) * win * (1.0 - frame) * lit * lamp_factor * 1.2;
		rough = mix(0.6, 0.15, win);
	} else if (k == 24) {
		// A sign face: retroreflective sheeting, the paint, glinting back toward the camera.
		albedo = paint;
		vec3 vd = normalize(CAMERA_POSITION_WORLD - world_p);
		emit = paint * lamp_factor * 0.8 * pow(clamp(dot(vd, world_n), 0.0, 1.0), 6.0);
		rough = 0.35;
	} else if (k == 26) {
		// A lit strip (the covered walkway's lamps): warm white, dim by day.
		albedo = vec3(0.8);
		emit = vec3(1.0, 0.86, 0.66) * (0.2 + 2.6 * lamp_factor);
		rough = 0.3;
	} else if (k == 27) {
		// Tinted cab glass: dark, the sky in it.
		vec3 v = normalize(world_p - CAMERA_POSITION_WORLD);
		float fres = pow(1.0 - clamp(abs(dot(v, world_n)), 0.0, 1.0), 4.0);
		albedo = vec3(0.03, 0.04, 0.045);
		emit = sky_tint.rgb * (0.12 + 0.4 * fres);
		rough = 0.08;
		spec = 0.8;
	}
	// Rain darkens and glosses what is out in it.
	if (k != 11 && k != 12 && k != 17 && k != 26 && k != 27) {
		float w2 = wet * (top ? 1.0 : 0.55);
		albedo *= 1.0 - 0.35 * w2;
		rough = mix(rough, 0.25, w2 * 0.7);
	}
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	EMISSION = to_lit(emit);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
}
