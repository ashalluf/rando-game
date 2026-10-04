shader_type spatial;

// Everything upright in the industrial district (Industrial, IndustrialKit) as ONE material: a
// chunk's walls, roofs, docks and fences are one mesh and one draw, and the repeated props
// (trailers, tractors, boxcars, tank cars, pallets, drums, bins, tanks, the water tower) are its
// MultiMesh batches on the same material. Each box says what it is in COLOR.a (IndustrialKit.K_*,
// in 32nds) and carries its paint in COLOR.rgb (a batch's instance colour multiplies it). UV is
// metres in the face's own frame (x along the face from its left corner seen from outside, y up
// from the box's foot), UV2.x the box's height and UV2.y a per-box parameter.
//    0 tilt-up concrete (UV2.y the panel width)      1 roof membrane (UV2.y a seed)
//    2 brick with steel windows (UV2.y the bay)       3 roll-up door (UV2.y the slat pitch)
//    4 rubber   5 painted steel   6 chain-link (cut out)   7 barbed wire (cut out)
//    8 glass (UV2.y the mullion pitch)   9 corrugated metal   10 mural (UV2.y its width)
//   11 lamp (lit after dark)   12 trailer skin   13 boxcar (UV2.y its length)   14 tank
//   15 concrete   16 timber / pallets   17 stretch wrap   18 plastic   19 galvanised   20 skylight
// The murals are invented here, abstract on purpose: no artist's work, no lettering, no brand.

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cracked_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D corrugated_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D planks_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float road_wetness;
global uniform float lamp_factor;
global uniform float night_factor;
global uniform vec4 sky_tint;

varying float kind;
varying vec3 world_n;
varying vec3 obj_n;
varying vec3 world_p;

#include "res://shaders/color_space.gdshaderinc"

// Tuned in display (sRGB) numbers - what Compatibility hands a shader, and what the paint in
// COLOR is on both renderers. Forward+ decodes the textures first, so they go back to display
// numbers (disp()) and the result goes out in the renderer's own space (to_lit()).
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

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

// 1 in a line every `spacing` (offset so a line sits at 0, spacing, ...), `w` wide, faded once
// the spacing is under a few pixels.
float lines(float v, float spacing, float w) {
	float g = abs(fract(v / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(v), 0.0005);
	float fade = 1.0 - smoothstep(0.03, 0.12, fw / spacing * 4.0);
	return (1.0 - smoothstep(w * 0.5, w * 0.5 + fw, g)) * fade;
}

// 1 in a band of half width `w` round v = c.
float band(float v, float c, float w) {
	float fw = max(fwidth(v), 0.0005);
	return 1.0 - smoothstep(w, w + fw, abs(v - c));
}

// Dirt that runs down a wall from its top: vertical streaks, stronger toward the foot.
float streaks(vec2 uv, float h, float seed) {
	float s = vnoise(vec2(uv.x * 1.7 + seed, 0.5)) * 0.6 + vnoise(vec2(uv.x * 5.3 + seed * 3.0, 1.5)) * 0.4;
	float from_top = clamp((h - uv.y) / max(h, 0.5), 0.0, 1.0);
	return smoothstep(0.45, 0.9, s) * (0.35 + 0.65 * (1.0 - from_top * 0.6)) * (0.7 + 0.3 * vnoise(uv * vec2(3.0, 0.4)));
}

// The mural palettes: six sets of five, picked by the seed in the paint.
vec3 palette(int p, int i) {
	vec3 c[30] = vec3[](
		vec3(0.10, 0.16, 0.38), vec3(0.86, 0.22, 0.46), vec3(0.98, 0.55, 0.16), vec3(0.99, 0.84, 0.30), vec3(0.96, 0.92, 0.84),
		vec3(0.05, 0.42, 0.45), vec3(0.62, 0.84, 0.22), vec3(0.08, 0.08, 0.09), vec3(0.96, 0.46, 0.62), vec3(0.95, 0.95, 0.92),
		vec3(0.72, 0.32, 0.20), vec3(0.88, 0.66, 0.28), vec3(0.45, 0.70, 0.86), vec3(0.12, 0.17, 0.32), vec3(0.93, 0.88, 0.78),
		vec3(0.38, 0.16, 0.62), vec3(0.18, 0.82, 0.86), vec3(0.98, 0.25, 0.60), vec3(0.98, 0.90, 0.20), vec3(0.06, 0.05, 0.10),
		vec3(0.38, 0.42, 0.18), vec3(0.66, 0.24, 0.12), vec3(0.92, 0.86, 0.70), vec3(0.16, 0.16, 0.17), vec3(0.86, 0.62, 0.12),
		vec3(0.02, 0.30, 0.52), vec3(0.20, 0.62, 0.70), vec3(0.95, 0.42, 0.30), vec3(0.99, 0.78, 0.55), vec3(0.98, 0.97, 0.94));
	return c[clamp(p, 0, 5) * 5 + clamp(i, 0, 4)];
}

// An invented, abstract mural over a w x h wall: a sky gradient cut by a wave, big ringed discs,
// a band of diagonal stripes, organic blobs with dark outlines, a field of dots, a zig-zag. Every
// placement from `seed`; the result in display numbers, its outline mask in `ink`.
vec3 mural(vec2 m, vec2 size, vec2 seed, out float ink) {
	int pal = int(floor(seed.x * 6.0));
	vec2 q = m / size;
	float s1 = seed.y * 17.0 + seed.x * 5.0;
	// Ground: two colours split by a long wave.
	float wave = 0.45 + 0.18 * sin(q.x * (3.0 + seed.y * 4.0) + s1) + 0.06 * sin(q.x * 11.0 + s1 * 2.0);
	vec3 col = mix(palette(pal, 0), palette(pal, 3), smoothstep(0.0, 1.0, q.y * 0.8));
	float lower = step(q.y, wave);
	col = mix(col, palette(pal, 1) * (0.8 + 0.25 * q.y), lower);
	ink = band(q.y, wave, 0.006 * size.y);
	// Rays from a sun-like disc.
	vec2 sc = vec2(0.2 + 0.6 * fract(seed.y * 7.3), 0.55 + 0.25 * fract(seed.x * 3.1));
	vec2 dm = (q - sc) * vec2(size.x / size.y, 1.0);
	float ang = atan(dm.y, dm.x);
	float rays = step(0.5, fract(ang * (3.0 + floor(seed.x * 4.0)) / 6.2831 + s1));
	float r = length(dm);
	col = mix(col, mix(col, palette(pal, 4), 0.35), rays * (1.0 - lower) * smoothstep(0.9, 0.2, r));
	// Ringed discs.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 c = vec2(fract(seed.y * (3.7 + fi * 2.1) + fi * 0.37), 0.25 + 0.5 * fract(seed.x * (5.3 + fi) + fi * 0.21));
		float rad = 0.12 + 0.14 * fract(seed.x * 9.1 + fi * 0.6);
		float dd = length((q - c) * vec2(size.x / size.y, 1.0));
		float ring = floor(dd / (rad * 0.34));
		if (dd < rad) {
			col = palette(pal, int(mod(ring + fi + 2.0, 5.0)));
		}
		ink = max(ink, band(dd, rad, 0.004 * size.y));
		ink = max(ink, band(fract(dd / (rad * 0.34)), 0.0, 0.035) * step(dd, rad) * 0.6);
	}
	// A band of diagonal stripes across the lower third.
	float bc = 0.2 + 0.15 * fract(seed.y * 11.0);
	float in_band = step(abs(q.y - bc - (q.x - 0.5) * 0.25), 0.07);
	float stripe = step(0.5, fract((q.x * size.x + q.y * size.y) / 1.4));
	col = mix(col, mix(palette(pal, 2), palette(pal, 4), stripe), in_band);
	ink = max(ink, band(abs(q.y - bc - (q.x - 0.5) * 0.25), 0.07, 0.0045 * size.y));
	// Blobs: an organic layer from noise, outlined.
	float n = fbm(m * 0.18 + seed * 40.0);
	float blob = smoothstep(0.62, 0.64, n) * step(q.y, 0.92);
	col = mix(col, palette(pal, int(mod(floor(seed.y * 5.0) + 3.0, 5.0))), blob);
	ink = max(ink, band(n, 0.63, 0.012) * step(q.y, 0.92));
	// Dots in a corner region.
	vec2 dg = fract(m / 0.55) - 0.5;
	float dots = (1.0 - smoothstep(0.16, 0.2, length(dg))) * step(0.7, fract(q.x + seed.x)) * step(q.y, 0.85) * step(0.6, q.y);
	col = mix(col, palette(pal, 4), dots);
	// A zig-zag line across.
	float zz = abs(fract(q.x * size.x / 3.0) - 0.5) * 2.0;
	float zy = 0.75 + 0.06 * zz;
	ink = max(ink, band(q.y, zy, 0.06 / size.y * 6.0) * step(0.4, fract(seed.x * 13.0)));
	return col;
}

void vertex() {
	kind = floor(COLOR.a * 32.0);
	obj_n = NORMAL;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float h = max(UV2.x, 0.01);
	float param = UV2.y;
	float v = clamp(uv.y / h, 0.0, 1.0);
	bool top = world_n.y > 0.5;
	bool bottom = world_n.y < -0.5;
	vec3 paint = COLOR.rgb;
	vec3 albedo = paint;
	float rough = 0.85;
	float metal = 0.0;
	float wet_k = 0.5;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	vec3 nrm_world = world_n;
	float foot = top ? 0.0 : 1.0 - smoothstep(0.0, 0.5, uv.y);
	float seedv = hash12(floor(world_p.xz / 37.0));
	if (kind < 0.5) {
		// Tilt-up concrete: cast panels, their 2 cm joints, a reveal band at 1.25 m (the wainscot,
		// in an accent below it) and one under the parapet, form marks, dirt run down from the top.
		vec3 c = disp(texture(concrete_tex, uv / 3.2).rgb);
		vec3 cr = disp(texture(cracked_tex, uv / 5.0).rgb);
		float tone = dot(mix(c, cr, 0.35), vec3(0.333));
		float pw = max(param, 1.0);
		float panel = floor(uv.x / pw);
		float ptone = 0.95 + 0.1 * hash12(vec2(panel, seedv * 31.0));
		albedo = paint * (0.72 + 0.5 * tone) * ptone;
		float accent_pick = hash12(floor(paint.rg * 64.0));
		vec3 accent = accent_pick < 0.25 ? vec3(0.32, 0.34, 0.36) : (accent_pick < 0.5 ? vec3(0.17, 0.24, 0.38) : (accent_pick < 0.75 ? vec3(0.62, 0.6, 0.55) : vec3(0.2, 0.36, 0.38)));
		if (top) {
			// Parapet coping: a galvanised cap.
			albedo = vec3(0.72, 0.73, 0.72) * (0.9 + 0.1 * vnoise(uv * 3.0));
			metal = 0.5;
			rough = 0.45;
		} else {
			if (uv.y < 1.25) {
				albedo = mix(albedo, accent * (0.75 + 0.4 * tone), 0.85);
			}
			float stripe = step(abs(uv.y - (h - 1.75)), 0.18);
			albedo = mix(albedo, accent * (0.8 + 0.3 * tone), stripe * 0.9 * step(6.0, h));
			float joint = lines(uv.x, pw, 0.022);
			float reveal = max(band(uv.y, 1.25, 0.02), band(uv.y, h - 1.55, 0.02) * step(6.0, h));
			albedo *= 1.0 - 0.45 * max(joint, reveal);
			// Lifting-insert patches and form-tie dots, faint.
			vec2 pl = vec2(fract(uv.x / pw) * pw, uv.y);
			float insert = 1.0 - smoothstep(0.05, 0.07, length(pl - vec2(pw * 0.25, h - 2.6)));
			insert = max(insert, 1.0 - smoothstep(0.05, 0.07, length(pl - vec2(pw * 0.75, h - 2.6))));
			albedo *= 1.0 - 0.12 * insert * step(6.0, h);
			// Buffed-out patches low on some panels: graffiti painted over in a near-match.
			float pr = hash12(vec2(panel, seedv * 71.0 + 3.0));
			vec2 pc = vec2(fract(uv.x / pw), uv.y);
			vec2 lo = vec2(0.1 + 0.4 * hash12(vec2(panel, 9.0)), 0.3);
			vec2 hi = lo + vec2(0.25 + 0.3 * hash12(vec2(panel, 4.0)), 1.6 + 1.4 * hash12(vec2(panel, 5.0)) / pw * pw);
			float buff = step(pr, 0.35) * step(lo.x, pc.x) * step(pc.x, hi.x) * step(lo.y, pc.y) * step(pc.y, hi.y);
			albedo = mix(albedo, albedo * mix(vec3(0.9, 0.9, 0.88), vec3(1.06, 1.04, 1.0), step(0.5, hash12(vec2(panel, 2.0)))), buff);
			float dirt = streaks(uv, h, seedv * 13.0);
			albedo *= 1.0 - 0.3 * dirt;
			// Grime under the coping where the rain runs off the parapet.
			albedo *= 1.0 - 0.18 * smoothstep(h - 1.2, h, uv.y) * (0.6 + 0.4 * vnoise(uv * vec2(2.0, 0.5)));
			albedo *= 1.0 - 0.32 * foot * (0.7 + 0.3 * vnoise(uv * 2.0));
			rough = 0.88;
		}
	} else if (kind < 1.5) {
		// The roof membrane: white or grey TPO with welded seams every 3 m, dirt pooled in shallow
		// blotches, walk pads round the units.
		float s = param * 0.013;
		vec3 base = mix(vec3(0.86, 0.86, 0.84), vec3(0.62, 0.62, 0.6), step(0.6, fract(s * 7.1)));
		float seam = lines(uv.x, 3.05, 0.04);
		float pond = smoothstep(0.55, 0.85, fbm(uv * 0.09 + s));
		float grime = fbm(uv * 0.35 + s * 3.0);
		albedo = base * (0.88 + 0.16 * grime) * (1.0 - 0.18 * pond) * (1.0 - 0.08 * seam);
		rough = mix(0.8, 0.55, pond);
		wet_k = 1.0;
	} else if (kind < 2.5) {
		// Brick: the photographed courses, sooted up the wall, and steel multi-pane windows in
		// every bay at each 4.6 m floor (factory sash: 4 x 5 panes, a few painted out or broken).
		vec3 b = disp(texture(brick_tex, uv / 2.6).rgb);
		albedo = paint * b * 1.18;
		if (top) {
			albedo = vec3(0.55, 0.53, 0.5) * (0.85 + 0.2 * vnoise(uv * 4.0));
		} else {
			float soot = fbm(uv * vec2(0.4, 0.15) + seedv * 9.0) * (0.4 + 0.6 * v);
			albedo *= 1.0 - 0.3 * soot;
			albedo *= 1.0 - 0.25 * foot;
			float bay = max(param, 2.0);
			float bx = fract(uv.x / bay) * bay - bay * 0.5;
			float fl = floor((uv.y - 1.3) / 4.6);
			float fy = uv.y - 1.3 - fl * 4.6;
			float ww = bay * 0.56;
			float wh = 3.0;
			bool in_win = abs(bx) < ww * 0.5 && fy > 0.0 && fy < wh && uv.y > 1.3 && uv.y < h - 1.7;
			if (in_win) {
				vec2 wq = vec2((bx + ww * 0.5) / ww, fy / wh);
				vec2 pane = vec2(wq.x * 4.0, wq.y * 5.0);
				vec2 pf = fract(pane);
				float bar = max(step(pf.x, 0.06) + step(0.94, pf.x), step(pf.y, 0.06) + step(0.94, pf.y));
				float pid = hash12(floor(pane) + vec2(floor(uv.x / bay), fl) * 7.0 + seedv * 50.0);
				vec3 glass = vec3(0.10, 0.12, 0.11) + disp(sky_tint.rgb) * 0.12 * (0.6 + 0.4 * wq.y);
				if (pid < 0.08) {
					glass = vec3(0.72, 0.72, 0.68);
				} else if (pid < 0.12) {
					glass = vec3(0.02);
				}
				// Lit lofts after dark, warm, a third of the windows.
				float lit = step(0.66, hash12(vec2(floor(uv.x / bay), fl) + seedv * 13.0)) * lamp_factor;
				emit += vec3(1.0, 0.72, 0.42) * 0.55 * lit * (1.0 - bar) * step(0.12, pid);
				albedo = mix(glass, vec3(0.13, 0.13, 0.12), clamp(bar, 0.0, 1.0));
				rough = mix(0.15, 0.6, clamp(bar, 0.0, 1.0));
				metal = 0.3 * clamp(bar, 0.0, 1.0);
				spec = 0.6;
			}
			// A lintel over each window: a soldier course of darker brick.
			float lintel = step(abs(bx), ww * 0.5 + 0.12) * step(wh, fy) * step(fy, wh + 0.3) * step(1.3, uv.y) * step(uv.y, h - 1.4);
			albedo *= 1.0 - 0.25 * lintel;
		}
	} else if (kind < 3.5) {
		// A roll-up door: horizontal slats with their shadowed grooves, the bottom bar, grime.
		float pitch = max(param, 0.03);
		float slat = fract(uv.y / pitch);
		float groove = smoothstep(0.0, 0.12, slat) * (1.0 - smoothstep(0.86, 1.0, slat));
		albedo = paint * (0.62 + 0.38 * groove) * (0.92 + 0.12 * vnoise(uv * vec2(0.7, 9.0)));
		albedo *= 1.0 - 0.35 * smoothstep(0.35, 0.0, uv.y);
		albedo *= 1.0 - 0.18 * streaks(uv, h, seedv * 5.0);
		metal = 0.35;
		rough = 0.55;
	} else if (kind < 4.5) {
		albedo = paint * (0.85 + 0.25 * vnoise(uv * 6.0));
		rough = 0.92;
		spec = 0.3;
	} else if (kind < 5.5) {
		// Painted steel: scuffed, rusting at the edges and foot.
		float rust = smoothstep(0.66, 0.9, vnoise(uv * 2.7 + paint.rg * 9.0)) * 0.7 + foot * 0.3;
		albedo = mix(paint * (0.92 + 0.12 * vnoise(uv * 7.0)), vec3(0.36, 0.2, 0.12), clamp(rust, 0.0, 0.75));
		rough = mix(0.5, 0.9, rust);
		metal = 0.3;
	} else if (kind < 6.5) {
		// Chain-link: 6 cm galvanised diamonds, dithered to their average once under a few pixels.
		vec2 q = uv / 0.06;
		vec2 d = vec2(q.x + q.y, q.x - q.y);
		vec2 f = abs(fract(d) - 0.5);
		float dist = 0.5 - max(f.x, f.y);
		float fw = max(fwidth(d.x), fwidth(d.y));
		float wire = 0.09;
		float line = 1.0 - smoothstep(wire, wire + fw, dist);
		float avg = 1.0 - (1.0 - 2.0 * wire) * (1.0 - 2.0 * wire);
		float cover = mix(line, avg * 0.8, smoothstep(0.25, 0.7, fw));
		if (cover < bayer4(FRAGCOORD.xy)) {
			discard;
		}
		albedo = paint * (0.8 + 0.3 * fract(d.x * 0.5));
		metal = 0.6;
		rough = 0.45;
	} else if (kind < 7.5) {
		// Barbed wire: three strands with barbs every 10 cm.
		float fw = fwidth(uv.y) + 0.002;
		float strand = 0.0;
		for (int i = 0; i < 3; i++) {
			float c = h * (0.18 + 0.32 * float(i));
			strand = max(strand, 1.0 - smoothstep(0.004, 0.004 + fw, abs(uv.y - c)));
			float barb = (1.0 - smoothstep(0.012, 0.012 + fw, abs(fract(uv.x / 0.1 + float(i) * 0.3) - 0.5) * 0.1)) * (1.0 - smoothstep(0.02, 0.02 + fw, abs(uv.y - c)));
			strand = max(strand, barb);
		}
		float pxs = smoothstep(0.02, 0.06, fw);
		if (mix(strand, 0.25, pxs) < bayer4(FRAGCOORD.xy)) {
			discard;
		}
		albedo = paint;
		metal = 0.6;
		rough = 0.5;
	} else if (kind < 8.5) {
		// Office glass: dark tinted panes between mullions, the sky mirrored by fresnel (emitted:
		// a reflection does not depend on the light on the pane), lit rooms after dark.
		float pitch = max(param, 0.5);
		float mull = max(lines(uv.x, pitch, 0.07), band(uv.y, h * 0.62, 0.035));
		float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.0);
		vec3 mirror = disp(sky_tint.rgb) * (0.25 + 0.7 * fres) * (0.85 + 0.3 * vnoise(vec2(uv.x / pitch, 0.5) * 3.0));
		albedo = mix(paint * 0.35, vec3(0.16, 0.17, 0.18), mull);
		emit += mirror * 0.55 * (1.0 - mull) * (1.0 - night_factor * 0.7);
		float lit = step(0.35, hash12(vec2(floor(uv.x / pitch), floor(uv.y / (h * 0.62)) + seedv * 9.0))) * lamp_factor;
		emit += vec3(1.0, 0.86, 0.66) * 0.5 * lit * (1.0 - mull);
		rough = mix(0.08, 0.5, mull);
		metal = 0.6 * mull;
		spec = 0.7;
		wet_k = 0.0;
	} else if (kind < 9.5) {
		// Corrugated metal: 76 mm ribs (the normal swings across each), galvanised or painted,
		// rust running down from the laps and up from the foot.
		float rib = sin(uv.x / 0.076 * 6.2831);
		vec3 tex = disp(texture(corrugated_tex, uv / 2.5).rgb);
		albedo = paint * (0.75 + 0.35 * dot(tex, vec3(0.333))) * (0.9 + 0.1 * rib);
		float rust = smoothstep(0.5, 0.85, fbm(vec2(uv.x * 0.9, uv.y * 0.25) + paint.gb * 7.0)) * (0.5 + 0.5 * v);
		rust = max(rust, smoothstep(0.55, 0.0, uv.y) * 0.6 * vnoise(uv * vec2(4.0, 1.0)));
		rust *= top ? 0.4 : 1.0;
		albedo = mix(albedo, vec3(0.42, 0.22, 0.12) * (0.7 + 0.5 * vnoise(uv * 8.0)), clamp(rust, 0.0, 0.85));
		metal = mix(0.55, 0.05, rust);
		rough = mix(0.45, 0.9, rust);
		if (!top && !bottom) {
			vec3 t = normalize(cross(world_n, vec3(0.0, 1.0, 0.0)));
			nrm_world = normalize(world_n + t * rib * 0.35);
		}
	} else if (kind < 10.5) {
		// A mural on the wall, its paint chipped back to the concrete, faded toward the foot.
		vec2 size = vec2(max(param, 1.0), h);
		float ink;
		vec3 m = mural(uv, size, COLOR.rg, ink);
		m = mix(m, vec3(0.06, 0.05, 0.07), ink * 0.92);
		vec3 c = disp(texture(concrete_tex, uv / 3.2).rgb);
		float chip = smoothstep(0.7, 0.78, fbm(uv * 1.3 + 4.0)) * 0.8 + smoothstep(0.85, 0.0, uv.y) * 0.25 * vnoise(uv * 6.0);
		float brush = 0.92 + 0.12 * vnoise(uv * vec2(9.0, 2.0));
		albedo = mix(m * brush, vec3(0.7, 0.69, 0.66) * (0.7 + 0.5 * dot(c, vec3(0.333))), clamp(chip, 0.0, 1.0));
		albedo *= 1.0 - 0.15 * streaks(uv, h, 3.0);
		rough = 0.82;
	} else if (kind < 11.5) {
		// A lamp: a dark housing by day, its lens lit after dark (the pool on the ground is the
		// light_pool batch).
		albedo = mix(vec3(0.16, 0.16, 0.17), paint * 0.8, bottom ? 1.0 : 0.15);
		emit += paint * (bottom ? 9.0 : 1.2) * lamp_factor;
		rough = 0.5;
		metal = 0.2;
	} else if (kind < 12.5) {
		// A trailer: aluminium skin between posts every 1.2 m, rivet rows top and bottom, the
		// rear doors (split, lock rods, hinges) on the back face, road grime low down.
		float side = abs(obj_n.x);
		float rear = step(0.5, -obj_n.z);
		vec3 skin = paint * (0.92 + 0.08 * vnoise(uv * vec2(0.3, 2.0)));
		if (top) {
			albedo = vec3(0.78, 0.79, 0.8) * (0.8 + 0.25 * vnoise(uv * 0.5));
			metal = 0.6;
		} else if (side > 0.5) {
			float post = lines(uv.x, 1.22, 0.06);
			float rivet = (band(uv.y, 0.12, 0.05) + band(uv.y, h - 0.12, 0.05)) * step(0.5, fract(uv.x / 0.1));
			albedo = skin * (1.0 - 0.18 * post) * (1.0 - 0.1 * rivet);
			albedo = mix(albedo, vec3(0.48, 0.5, 0.52), band(uv.y, 0.06, 0.06) + band(uv.y, h - 0.05, 0.05));
			albedo *= 1.0 - 0.35 * smoothstep(1.4, 0.0, uv.y) * vnoise(uv * vec2(0.8, 3.0));
			albedo *= 1.0 - 0.18 * streaks(uv, h, paint.r * 30.0);
			metal = 0.04;
			rough = 0.62;
		} else if (rear > 0.5) {
			float w = 2.59;
			float split = band(uv.x, w * 0.5, 0.012);
			float rods = band(uv.x, w * 0.22, 0.02) + band(uv.x, w * 0.36, 0.02) + band(uv.x, w * 0.64, 0.02) + band(uv.x, w * 0.78, 0.02);
			float frame = 1.0 - step(0.08, uv.x) * step(uv.x, w - 0.08) * step(0.08, uv.y) * step(uv.y, h - 0.1);
			albedo = mix(skin * 0.95, vec3(0.3, 0.31, 0.32), clamp(rods + frame * 0.8, 0.0, 1.0));
			albedo *= 1.0 - 0.5 * split;
			albedo = mix(albedo, vec3(0.9, 0.1, 0.06), band(uv.y, 0.25, 0.04) * step(0.12, uv.x) * step(uv.x, w - 0.12) * 0.8);
			albedo *= 1.0 - 0.25 * smoothstep(1.0, 0.0, uv.y);
			metal = 0.2;
			rough = 0.5;
		} else {
			albedo = skin;
			rough = 0.5;
		}
	} else if (kind < 13.5) {
		// A boxcar: exterior posts every 0.9 m, a sliding door mid-side, rust bleeding from every
		// seam, a block of invented marks in white low on the left (shapes, not letters).
		float side = abs(obj_n.x);
		float len = max(param, 8.0);
		albedo = paint * (0.85 + 0.2 * vnoise(uv * vec2(0.6, 2.0)));
		if (side > 0.5) {
			float post = lines(uv.x, 0.9, 0.09);
			float door = step(abs(uv.x - len * 0.5), 1.85);
			float door_edge = band(abs(uv.x - len * 0.5), 1.85, 0.05);
			albedo *= 1.0 - 0.22 * post * (1.0 - door);
			albedo *= 1.0 - 0.18 * door * (0.5 + 0.5 * lines(uv.x, 0.45, 0.04));
			albedo *= 1.0 - 0.4 * door_edge;
			vec2 mk = (uv - vec2(1.2, 0.5)) / vec2(2.8, 0.9);
			if (mk.x > 0.0 && mk.x < 1.0 && mk.y > 0.0 && mk.y < 1.0 && door < 0.5) {
				vec2 cell = floor(mk * vec2(7.0, 2.0));
				vec2 cf = fract(mk * vec2(7.0, 2.0));
				float glyph = step(0.15, cf.x) * step(cf.x, 0.8) * step(0.15, cf.y) * step(cf.y, 0.85);
				glyph *= step(0.25, hash12(cell + floor(cf * 3.0) * 1.7 + paint.rg * 10.0));
				albedo = mix(albedo, vec3(0.86, 0.85, 0.8), glyph * 0.85);
			}
		}
		float rust = smoothstep(0.55, 0.9, fbm(uv * vec2(1.2, 0.3) + paint.rb * 9.0)) * (0.4 + 0.6 * (1.0 - v));
		albedo = mix(albedo, vec3(0.36, 0.18, 0.1), clamp(rust, 0.0, 0.8));
		if (top) {
			albedo = paint * 0.7 * (0.8 + 0.3 * vnoise(uv * 2.0));
		}
		rough = 0.8;
		metal = 0.15;
	} else if (kind < 14.5) {
		// A tank (storage tanks, tank cars, the water tower): smooth paint, grime streaks down it,
		// a darker foot.
		albedo = paint * (0.9 + 0.1 * vnoise(uv * 0.8));
		float s = smoothstep(0.5, 0.9, vnoise(vec2(uv.x * 1.4, uv.y * 0.12)) * 0.7 + vnoise(vec2(uv.x * 5.0, 0.3)) * 0.3);
		albedo *= 1.0 - 0.25 * s * (top ? 0.3 : 1.0);
		albedo *= 1.0 - 0.2 * smoothstep(1.0, 0.0, uv.y);
		rough = 0.55;
		metal = 0.2;
	} else if (kind < 15.5) {
		vec3 c = disp(texture(concrete_tex, uv / 2.4).rgb);
		albedo = paint * (0.6 + 0.5 * dot(c, vec3(0.333))) * (1.0 - 0.25 * foot);
		rough = 0.88;
	} else if (kind < 16.5) {
		// Timber: pallet boards with their gaps (UV2.y the course), else planks.
		vec3 w = disp(texture(planks_tex, uv / 1.2).rgb);
		albedo = paint * (0.6 + 0.6 * dot(w, vec3(0.333)));
		if (param > 0.01 && !top) {
			float c = fract(uv.y / param);
			float gap = step(0.2, c) * step(c, 0.38) + step(0.6, c) * step(c, 0.72) * step(0.3, fract(uv.x / 0.4));
			albedo *= 1.0 - 0.75 * clamp(gap, 0.0, 1.0);
		} else if (top) {
			albedo *= 1.0 - 0.6 * lines(uv.x, 0.15, 0.04);
		}
		rough = 0.9;
	} else if (kind < 17.5) {
		// Stretch wrap over cartons: pale and glossy, banded where the film overlaps, the boxes
		// showing through in blocks.
		float bandw = 0.5 + 0.5 * sin((uv.y + uv.x * 0.18) * 14.0);
		float boxes = step(0.5, fract(uv.x / 0.4 + 0.5 * floor(uv.y / 0.3))) * 0.1 + lines(uv.y, 0.3, 0.02) * 0.2;
		albedo = mix(paint, vec3(0.62, 0.5, 0.36), 0.25 + boxes) * (0.92 + 0.08 * bandw);
		rough = 0.28;
		spec = 0.6;
	} else if (kind < 18.5) {
		albedo = paint * (0.9 + 0.1 * vnoise(uv * 4.0));
		albedo *= 1.0 - 0.2 * foot;
		rough = 0.4;
	} else if (kind < 19.5) {
		albedo = paint * (0.9 + 0.12 * vnoise(uv * vec2(1.0, 6.0)));
		metal = 0.7;
		rough = 0.38;
	} else {
		// A skylight: a milky acrylic dome on a galvanised curb.
		if (top) {
			albedo = vec3(0.78, 0.82, 0.84);
			rough = 0.22;
			spec = 0.7;
			emit += vec3(1.0, 0.9, 0.7) * 0.25 * lamp_factor;
		} else {
			albedo = vec3(0.6, 0.61, 0.6);
			metal = 0.6;
			rough = 0.45;
		}
	}
	float wet = clamp(road_wetness, 0.0, 1.0) * wet_k * (top ? 1.0 : 0.4);
	albedo *= 1.0 - 0.28 * wet;
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	// Emission is written as linear light on both (lamps are HDR).
	EMISSION = emit;
	ROUGHNESS = mix(rough, 0.18, wet * 0.7);
	METALLIC = metal;
	SPECULAR = spec;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm_world, 0.0)).xyz);
}
