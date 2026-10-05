shader_type spatial;
render_mode cull_back;

// The rec parks' and schools' ground (Parks.commit()): ONE mesh a chunk, no shadow. Each piece says
// what it is in COLOR.r (Parks.G_*, in 16ths); UV is the facility's own frame in metres (a along
// its long axis u, b across it; a diamond's origin is home plate, everything else's its centre),
// UV2 the facility's numbers and TANGENT its u axis in the chunk's space, so every line is drawn
// where the regulation puts it, analytically, and fades to its average once it is under a pixel.
//    0 field turf (mow stripes along u)            1 soccer (UV2 the field's half size)
//    2 diamond (UV2 = fence radius, base path)      3 basketball (UV2 half court; COLOR.g palette,
//      COLOR.b 1 painted on a school's asphalt)     4 tennis (UV2 half enclosure; COLOR.g palette)
//    5 track (UV2 = half straight, inside radius; COLOR.g lanes / 10, COLOR.b school colour,
//      COLOR.a the football field's scale, 0 none)   6 poured rubber (COLOR.g palette)
//    7 pool water, traced (UV2 half tank; COLOR.b depth / 4)    8 concrete deck   9 asphalt
//      (COLOR.b 1 the drop-off loop's markings)     10 decomposed granite   11 painted yard games
//   12 park lawn (COLOR.g a tone)
// Colours are tuned in display (sRGB) numbers - what Compatibility hands a shader; Forward+'s
// decoded textures go back to display numbers (disp()) and the result goes out in the renderer's
// own space (to_lit()), as the industrial ground does.

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Field grass and the infield mix (display numbers).
uniform vec3 turf_color = vec3(0.25, 0.37, 0.14);
uniform vec3 lawn_color = vec3(0.25, 0.35, 0.15);
uniform vec3 clay_color = vec3(0.70, 0.44, 0.30);
uniform vec3 track_color = vec3(0.66, 0.27, 0.21);
uniform vec3 deck_color = vec3(0.80, 0.79, 0.75);
uniform vec3 dg_color = vec3(0.76, 0.64, 0.48);
uniform vec3 paint_white = vec3(0.93, 0.93, 0.90);
// How strong the mow stripes are, and how wide.
uniform float stripe_amount = 0.075;
uniform float stripe_width = 4.0;

global uniform float road_wetness;
global uniform float lamp_factor;
global uniform float night_factor;
global uniform vec4 sky_tint;

varying float kind;
varying vec4 col;
varying vec3 wpos;
varying vec3 u_dir;

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

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.3) * 0.2;
}

// A painted line of width w round d = 0, box-filtered by the pixel: crisp up close, its average
// cover once it is thinner than a pixel (never a shimmer).
float aline(float d, float w) {
	float fw = max(fwidth(d), 0.0005);
	float cov = clamp((0.5 * (w + fw) - abs(d)) / fw, 0.0, 1.0);
	return cov * min(1.0, w / fw);
}

// The same along a segment a-b.
float aseg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
	return aline(length(pa - ba * h), w);
}

// A filled region d < 0, anti-aliased.
float fill(float d) {
	float fw = max(fwidth(d), 0.0005);
	return clamp(0.5 - d / fw, 0.0, 1.0);
}

float rect_line(vec2 p, vec2 lo, vec2 hi, float w) {
	float l = aseg(p, lo, vec2(hi.x, lo.y), w);
	l = max(l, aseg(p, vec2(hi.x, lo.y), hi, w));
	l = max(l, aseg(p, hi, vec2(lo.x, hi.y), w));
	return max(l, aseg(p, vec2(lo.x, hi.y), lo, w));
}

// Paint is never perfect: worn thin in patches, a little dirt in it.
vec3 paint(vec3 c, vec3 ink, float cov, vec2 w) {
	float wear = smoothstep(0.25, 0.75, fbm(w * 1.7)) * 0.35;
	return mix(c, ink, cov * (0.95 - wear));
}

// Grass: the lawn texture at two scales (one turned) so it never tiles, its luma kept as detail
// round `tint`. Display numbers.
vec3 grass(vec2 w, vec3 tint) {
	vec3 a = disp(texture(grass_tex, w / 2.6).rgb);
	vec2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * w;
	vec3 b = disp(texture(grass_tex, r / 7.3 + 0.37).rgb);
	float la = dot(a, vec3(0.3, 0.59, 0.11));
	float lb = dot(b, vec3(0.3, 0.59, 0.11));
	float l = mix(la, lb, 0.4) / 0.36;
	vec3 c = tint * mix(0.72, 1.28, clamp(l - 0.5, 0.0, 1.0));
	// Clover and weeds in it, a little burnt yellow.
	c = mix(c, tint * vec3(1.25, 1.12, 0.7), smoothstep(0.62, 0.8, vnoise(w * 0.9 + 4.0)) * 0.35);
	// Broad patches: drier, greener, a worn path or two.
	float patch = fbm(w * 0.045);
	c *= mix(vec3(1.05, 0.98, 0.86), vec3(0.92, 1.04, 1.0), smoothstep(0.3, 0.7, patch));
	return c;
}

// Mown grass: stripes along `s` (the mower's passes), light and dark by which way it went.
vec3 mown(vec2 w, vec3 tint, float s, float width) {
	vec3 c = grass(w, tint);
	float k = sin(s * 3.14159 / width);
	float fw = fwidth(s) * 3.14159 / width;
	float side = clamp(k / max(fw, 0.05), -1.0, 1.0) * (1.0 - smoothstep(0.6, 1.4, fw));
	return c * (1.0 + stripe_amount * side);
}

vec3 dirt(vec2 w, vec3 tint) {
	vec3 t = disp(texture(dirt_tex, w / 3.1).rgb);
	float l = dot(t, vec3(0.3, 0.59, 0.11)) / 0.42;
	return tint * mix(0.8, 1.15, clamp(l - 0.4, 0.0, 1.0)) * (0.94 + 0.12 * vnoise(w * 0.7));
}

vec3 asphalt(vec2 w) {
	vec3 t = disp(texture(asphalt_tex, w / 5.0).rgb);
	return t * 0.95 * (0.92 + 0.16 * fbm(w * 0.1));
}

vec3 concrete(vec2 w, vec3 tint, float joint) {
	vec3 t = disp(texture(concrete_tex, w / 4.0).rgb);
	float l = dot(t, vec3(0.3, 0.59, 0.11)) / 0.55;
	vec3 c = tint * mix(0.88, 1.08, clamp(l - 0.3, 0.0, 1.0));
	vec2 g = abs(fract(w / joint + 0.5) - 0.5) * joint;
	float j = max(aline(g.x, 0.012), aline(g.y, 0.012));
	return c * (1.0 - 0.35 * j);
}

// Acrylic court paint: flat, a faint sand texture, sun-faded in patches.
vec3 acrylic(vec3 c, vec2 w) {
	return c * (0.95 + 0.06 * vnoise(w * 0.35) + 0.03 * (hash12(floor(w * 60.0)) - 0.5) * (1.0 - smoothstep(0.01, 0.03, fwidth(w.x))));
}

vec3 bb_pal(int i, int which) {
	vec3 c[8] = vec3[](vec3(0.20, 0.36, 0.56), vec3(0.16, 0.42, 0.33),
		vec3(0.62, 0.24, 0.20), vec3(0.18, 0.40, 0.30),
		vec3(0.19, 0.30, 0.50), vec3(0.13, 0.20, 0.36),
		vec3(0.36, 0.38, 0.42), vec3(0.20, 0.36, 0.56));
	return c[clamp(i, 0, 3) * 2 + which];
}

vec3 ten_pal(int i, int which) {
	vec3 c[6] = vec3[](vec3(0.19, 0.34, 0.55), vec3(0.20, 0.42, 0.32),
		vec3(0.22, 0.45, 0.33), vec3(0.55, 0.24, 0.20),
		vec3(0.24, 0.47, 0.36), vec3(0.17, 0.35, 0.27));
	return c[clamp(i, 0, 2) * 2 + which];
}

vec3 school_col(int i) {
	vec3 c[8] = vec3[](vec3(0.55, 0.10, 0.12), vec3(0.10, 0.20, 0.45), vec3(0.08, 0.36, 0.20),
		vec3(0.62, 0.40, 0.06), vec3(0.32, 0.12, 0.40), vec3(0.85, 0.42, 0.08),
		vec3(0.10, 0.36, 0.48), vec3(0.45, 0.06, 0.10));
	return c[clamp(i, 0, 7)];
}

// The lower 48 as a schoolyard map paints it: the outline (longitude, latitude), coarse.
const int MAP_N = 46;
const vec2 MAP_PTS[46] = vec2[](
	vec2(-124.7, 48.4), vec2(-123.0, 49.0), vec2(-95.2, 49.0), vec2(-89.6, 48.0), vec2(-84.8, 46.5),
	vec2(-82.5, 45.3), vec2(-82.4, 43.0), vec2(-79.0, 43.3), vec2(-76.0, 44.3), vec2(-74.7, 45.0),
	vec2(-71.5, 45.0), vec2(-69.2, 47.4), vec2(-67.0, 44.8), vec2(-70.7, 43.1), vec2(-70.0, 41.7),
	vec2(-74.0, 40.6), vec2(-75.5, 38.5), vec2(-76.0, 37.0), vec2(-75.5, 35.2), vec2(-78.0, 33.8),
	vec2(-81.0, 31.5), vec2(-80.0, 27.0), vec2(-80.4, 25.2), vec2(-81.8, 26.2), vec2(-82.8, 28.0),
	vec2(-84.0, 30.0), vec2(-88.0, 30.4), vec2(-89.6, 29.2), vec2(-91.5, 29.5), vec2(-94.0, 29.6),
	vec2(-97.2, 26.0), vec2(-99.5, 27.5), vec2(-101.4, 29.8), vec2(-103.0, 29.0), vec2(-104.6, 29.9),
	vec2(-106.5, 31.8), vec2(-108.2, 31.3), vec2(-111.0, 31.3), vec2(-114.8, 32.5), vec2(-117.1, 32.5),
	vec2(-118.5, 34.0), vec2(-120.6, 34.6), vec2(-122.5, 37.7), vec2(-124.2, 40.4), vec2(-124.5, 43.0),
	vec2(-124.0, 46.2));

// Signed distance to the outline (negative inside), in degrees.
float map_sd(vec2 g) {
	float d = 1e9;
	bool inside = false;
	for (int i = 0; i < MAP_N; i++) {
		vec2 a = MAP_PTS[i];
		vec2 b = MAP_PTS[(i + 1) % MAP_N];
		vec2 pa = g - a;
		vec2 ba = b - a;
		float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
		d = min(d, length(pa - ba * h));
		if ((a.y > g.y) != (b.y > g.y) && g.x < (b.x - a.x) * (g.y - a.y) / (b.y - a.y) + a.x) {
			inside = !inside;
		}
	}
	return inside ? -d : d;
}

vec3 rubber_pal(int i, int which) {
	vec3 c[12] = vec3[](vec3(0.52, 0.24, 0.18), vec3(0.18, 0.36, 0.52), vec3(0.85, 0.66, 0.22),
		vec3(0.20, 0.40, 0.26), vec3(0.62, 0.62, 0.58), vec3(0.15, 0.40, 0.55),
		vec3(0.22, 0.30, 0.52), vec3(0.50, 0.68, 0.30), vec3(0.88, 0.52, 0.18),
		vec3(0.38, 0.36, 0.34), vec3(0.62, 0.22, 0.20), vec3(0.24, 0.50, 0.58));
	return c[clamp(i, 0, 3) * 3 + which];
}

void vertex() {
	kind = floor(COLOR.r * 16.0);
	col = COLOR;
	wpos = VERTEX;
	u_dir = vec3(TANGENT.x, 0.0, TANGENT.z);
}

void fragment() {
	vec2 p = UV;
	vec2 dims = UV2;
	vec2 w = wpos.xz;
	vec3 c = vec3(0.5);
	float rough = 0.9;
	float spec = 0.4;
	vec3 emit = vec3(0.0);
	int k = int(kind + 0.5);
	if (k == 0) {
		c = mown(w, turf_color, p.x, stripe_width);
	} else if (k == 12) {
		c = grass(w, lawn_color * (0.94 + 0.12 * col.g));
	} else if (k == 1) {
		// Soccer: regulation markings scaled to the field (a youth field keeps its proportions).
		vec2 h = dims;
		float s = clamp(h.y * 2.0 / 68.0, 0.62, 1.0);
		c = mown(w, turf_color, p.x, h.x * 2.0 / 18.0);
		vec2 q = abs(p);
		float lw = 0.12;
		float l = rect_line(p, -h, h, lw);
		l = max(l, aseg(p, vec2(0.0, -h.y), vec2(0.0, h.y), lw));
		l = max(l, aline(length(p) - 9.15 * s, lw));
		l = max(l, aline(length(p) - 0.2, 0.25));
		float pa_d = 16.5 * s;
		float pa_w = min(20.16 * s, h.y - 1.0);
		float ga_d = 5.5 * s;
		float ga_w = min(9.16 * s, h.y - 1.0);
		vec2 qq = vec2(h.x - q.x, q.y);
		l = max(l, aseg(qq, vec2(0.0, pa_w), vec2(pa_d, pa_w), lw));
		l = max(l, aseg(vec2(qq.x, p.y), vec2(pa_d, -pa_w), vec2(pa_d, pa_w), lw));
		l = max(l, aseg(qq, vec2(0.0, ga_w), vec2(ga_d, ga_w), lw));
		l = max(l, aseg(vec2(qq.x, p.y), vec2(ga_d, -ga_w), vec2(ga_d, ga_w), lw));
		// The penalty spot and the arc outside the area.
		vec2 spot = vec2(h.x - 11.0 * s, 0.0);
		l = max(l, aline(length(vec2(q.x, p.y) - spot) - 0.1, 0.22));
		float arc = aline(length(vec2(q.x, p.y) - spot) - 9.15 * s, lw);
		l = max(l, arc * step(q.x, h.x - pa_d));
		// Corner arcs.
		l = max(l, aline(length(q - h) - 1.0, lw) * step(q.x, h.x) * step(q.y, h.y));
		l *= step(q.x, h.x + 0.1) * step(q.y, h.y + 0.1);
		c = paint(c, paint_white, l, w);
	} else if (k == 2) {
		// The diamond: home plate at the origin, the first-base line down +a, the third down +b.
		float fence = dims.x;
		float base = dims.y;
		vec2 pm = vec2(14.02, 14.02) * 0.70711;
		float r = length(p);
		bool fair = p.x >= 0.0 && p.y >= 0.0;
		vec3 g = mown(w, turf_color, 0.0, 1.0);
		// The outfield's checkerboard: passes on both diagonals.
		float d1 = sin((p.x + p.y) * 0.5);
		float d2 = sin((p.x - p.y) * 0.5);
		float fw = fwidth(p.x) * 0.7;
		float chk = clamp(d1 / max(fw, 0.05), -1.0, 1.0) * clamp(d2 / max(fw, 0.05), -1.0, 1.0) * (1.0 - smoothstep(0.5, 1.2, fw));
		g *= 1.0 + 0.07 * chk;
		if (r > fence) {
			g = grass(w, turf_color * 0.92);
		}
		// The skinned infield (all dirt, as softball's is): out to 60 ft from the pitcher, the
		// home area to the backstop, a strip down each line into foul ground.
		float inf = length(p - pm) - base;
		inf = min(inf, r - 6.4);
		inf = min(inf, max(-p.y - 2.4, max(p.y - 1.0, abs(p.x - base * 0.6) - base * 0.6)));
		inf = min(inf, max(-p.x - 2.4, max(p.x - 1.0, abs(p.y - base * 0.6) - base * 0.6)));
		// The warning track inside the fence.
		float track = (fair ? max(fence - 3.2 - r, r - fence) : 1.0);
		float dmask = max(fill(inf), fill(track));
		vec3 d = dirt(w, clay_color);
		// Dragged rings round the mound, the base paths worn darker, the lip where grass meets it.
		float ring = sin(length(p - pm) * 18.0) * (1.0 - smoothstep(0.02, 0.06, fwidth(length(p - pm))));
		d *= 1.0 + 0.04 * ring;
		float path = min(aseg(p, vec2(0.0), vec2(base, 0.0), 0.9), 1.0);
		path = max(path, aseg(p, vec2(base, 0.0), vec2(base, base), 0.9));
		path = max(path, aseg(p, vec2(base, base), vec2(0.0, base), 0.9));
		path = max(path, aseg(p, vec2(0.0, base), vec2(0.0), 0.9));
		d *= 1.0 - 0.1 * path;
		float lip = aline(inf, 0.25) * fill(-inf + 0.12);
		c = mix(g, d, dmask) * (1.0 - 0.12 * lip);
		rough = mix(0.9, 0.97, dmask);
		// Chalk: the foul lines out to the fence, the batter's boxes, the pitcher's circle.
		float lw = 0.076;
		float l = aseg(p, vec2(0.0), vec2(fence, 0.0), lw);
		l = max(l, aseg(p, vec2(0.0), vec2(0.0, fence), lw));
		vec2 dg = vec2(p.x + p.y, p.x - p.y) * 0.70711;
		for (int s = -1; s <= 1; s += 2) {
			vec2 bc = vec2(0.25, float(s) * 0.69);
			l = max(l, rect_line(dg, bc - vec2(1.07, 0.46), bc + vec2(1.07, 0.46), lw));
		}
		l = max(l, aline(length(p - pm) - 2.44, lw));
		l = max(l, aline(length(p - vec2(-6.5, 8.0)) - 0.76, lw) * step(0.0, 1.0));
		l = max(l, aline(length(p - vec2(8.0, -6.5)) - 0.76, lw));
		c = paint(c, paint_white, l, w);
	} else if (k == 3) {
		// Basketball: FIBA lines on a court of `dims` (half size), the key and centre circle in
		// the second colour; on a school's asphalt only the lines (yellow and white).
		int pal = int(col.g * 8.0);
		bool yard = col.b > 0.5;
		vec2 h = dims;
		vec2 q = abs(p);
		bool in_court = q.x <= h.x && q.y <= h.y;
		float lw = 0.05;
		vec2 bq = vec2(h.x - q.x, p.y);
		float key = max(bq.x - 5.8, q.y - 2.45);
		float centre = length(p) - 1.8;
		if (yard) {
			c = asphalt(w);
			rough = 0.92;
		} else {
			vec3 a = bb_pal(pal, 0);
			vec3 b = bb_pal(pal, 1);
			c = acrylic(mix(b, a, fill(max(q.x - h.x, q.y - h.y))), w);
			c = mix(c, acrylic(b, w), max(fill(key), fill(centre)) * fill(max(q.x - h.x, q.y - h.y)));
			rough = 0.62;
		}
		float l = rect_line(p, -h, h, lw);
		l = max(l, aseg(p, vec2(0.0, -h.y), vec2(0.0, h.y), lw));
		l = max(l, aline(centre, lw));
		l = max(l, rect_line(bq, vec2(0.0, -2.45), vec2(5.8, 2.45), lw));
		l = max(l, aline(length(bq - vec2(5.8, 0.0)) - 1.8, lw) * step(5.8, bq.x));
		// The three-point line: an arc 6.75 m from the basket, straight down to the baseline
		// 0.9 m in from each sideline.
		vec2 basket = vec2(1.575, 0.0);
		float yc = h.y - 0.9;
		float arc = aline(length(bq - basket) - 6.75, lw) * step(yc, -abs(p.y) + yc + 100.0) * step(abs(p.y), yc);
		arc *= step(basket.x, bq.x);
		l = max(l, arc);
		float xs = basket.x + sqrt(max(6.75 * 6.75 - yc * yc, 0.0));
		l = max(l, aseg(vec2(bq.x, abs(p.y)), vec2(0.0, yc), vec2(xs, yc), lw));
		l = max(l, aline(length(bq - basket) - 1.25, lw) * step(basket.x, bq.x));
		l *= step(q.x, h.x + 0.1);
		c = paint(c, yard ? vec3(0.92, 0.80, 0.30) : paint_white, l, w);
	} else if (k == 4) {
		// Tennis: a doubles court in its enclosure, the net along a = 0.
		int pal = int(col.g * 8.0);
		vec2 q = abs(p);
		vec2 h = vec2(11.885, 5.485);
		c = acrylic(mix(ten_pal(pal, 1), ten_pal(pal, 0), fill(max(q.x - h.x, q.y - h.y))), w);
		float l = rect_line(p, -h, h, 0.05);
		l = max(l, aline(q.x - h.x, 0.1) * step(q.y, h.y));
		l = max(l, aline(q.y - 4.115, 0.05) * step(q.x, h.x));
		l = max(l, aline(q.x - 6.40, 0.05) * step(q.y, 4.115));
		l = max(l, aline(p.y, 0.05) * step(q.x, 6.40));
		l = max(l, aline(p.y, 0.05) * step(h.x - 0.1, q.x) * step(q.x, h.x));
		c = paint(c, paint_white, l, w);
		rough = 0.6;
	} else if (k == 5) {
		// The track: lane 1's inside kerb is a stadium of straights 2 * dims.x and radius dims.y.
		float hs = dims.x;
		float R = dims.y;
		int lanes = int(col.g * 10.0 + 0.5);
		float ringw = float(lanes) * 1.22;
		vec2 qd = vec2(max(abs(p.x) - hs, 0.0), p.y);
		float d = length(qd) - R;
		vec3 surf = track_color * (0.92 + 0.1 * vnoise(w * 1.3)) * (1.0 + 0.05 * (hash12(floor(w * 80.0)) - 0.5) * (1.0 - smoothstep(0.005, 0.02, fwidth(w.x))));
		if (d < 0.0) {
			float fb = col.a;
			vec3 g = mown(w, turf_color, p.x, 4.572 * max(fb, 0.6));
			if (fb > 0.01) {
				// American football: 100 yards and two end zones, yard lines every five, hash marks
				// every yard, the end zones in the school's colour.
				float yd = 0.9144 * fb;
				vec2 fh = vec2(54.865, 24.385) * fb;
				vec2 q = abs(p);
				float gl = fh.x - 10.0 * yd;
				vec3 sc = school_col(int(col.b * 8.0));
				float ez = fill(max(gl - q.x, max(q.x - fh.x, q.y - fh.y)));
				g = mix(g, sc * (0.9 + 0.1 * vnoise(w * 0.8)), ez * 0.85);
				float l = rect_line(p, -fh, fh, 0.1);
				float ylin = abs(fract(q.x / (5.0 * yd) + 0.5) - 0.5) * 5.0 * yd;
				l = max(l, aline(ylin, 0.1) * step(q.x, gl + 0.05) * step(q.y, fh.y));
				float tick = abs(fract(q.x / yd + 0.5) - 0.5) * yd;
				float hash_y = fh.y - 16.26 * fb;
				float hm = aline(tick, 0.1) * step(q.x, gl);
				hm *= max(step(abs(q.y - (fh.y - 0.4)), 0.3), step(abs(q.y - hash_y), 0.3));
				l = max(l, hm);
				l = max(l, aline(length(p) - 4.0 * fb, 0.12));
				g = paint(g, paint_white, l, w);
			}
			c = g;
			// The kerb: a raised aluminium edge, light grey.
			c = mix(c, vec3(0.78, 0.79, 0.80), aline(d + 0.03, 0.05));
		} else if (d < ringw + 1.0) {
			c = surf;
			float lane = d / 1.22;
			float l = aline((fract(lane + 0.5) - 0.5) * 1.22, 0.05) * step(d, ringw + 0.03);
			// The finish line across all the lanes at the end of the home straight.
			l = max(l, aline(p.x - hs, 0.05) * step(p.y, 0.0) * step(d, ringw));
			// The 100 m start: staggered blocks, a tick per lane, on the back straight.
			l = max(l, aline(p.x + hs, 0.05) * step(0.0, p.y) * step(d, ringw));
			c = paint(c, paint_white, l, w);
			rough = 0.82;
		} else {
			c = mown(w, turf_color * 0.95, p.x, 4.0);
		}
	} else if (k == 6) {
		// Poured-in-place rubber: a base colour with swirls of two more, granules up close.
		int pal = int(col.g * 8.0);
		// Mostly one colour, with a few designed islands and a path of a second and third.
		float n1 = fbm(w * 0.32);
		float n2 = fbm(w * 0.41 + 11.0);
		vec3 base = rubber_pal(pal, 0);
		base = mix(base, rubber_pal(pal, 1), smoothstep(0.64, 0.66, n1));
		base = mix(base, rubber_pal(pal, 2), smoothstep(0.69, 0.71, n2) * 0.9);
		base *= 0.82;
		float gr = hash12(floor(w * 220.0));
		float fine = 1.0 - smoothstep(0.002, 0.008, fwidth(w.x));
		c = base * (0.9 + 0.2 * (gr - 0.5) * fine);
		rough = 0.93;
	} else if (k == 7) {
		// A pool, traced: the view ray refracted into a tank of tiles, lane lines on its floor,
		// coloured by the water it crosses; the sky's mirror on top, emitted (like the sea's).
		vec2 h = dims;
		float depth = max(col.b * 4.0, 0.5);
		float t_now = TIME;
		vec2 rip = vec2(vnoise(p * 1.7 + t_now * 0.6), vnoise(p * 1.9 - t_now * 0.5 + 7.0)) - 0.5;
		vec3 u3 = normalize(u_dir + vec3(1e-5, 0.0, 0.0));
		vec3 v3 = vec3(-u3.z, 0.0, u3.x);
		vec3 dw = (INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz;
		vec3 rd = normalize(vec3(dot(dw, u3), dw.y, dot(dw, v3)));
		// Snell, water 1.33, with the ripples bending it a little.
		vec3 rr = normalize(vec3(rd.x * 0.75 + rip.x * 0.018, min(rd.y, -0.05), rd.z * 0.75 + rip.y * 0.018));
		vec3 o = vec3(p.x, 0.0, p.y);
		float tf = depth / max(-rr.y, 0.02);
		float tx = rr.x > 0.0 ? (h.x - o.x) / rr.x : (-h.x - o.x) / min(rr.x, -1e-4);
		float tz = rr.z > 0.0 ? (h.y - o.z) / rr.z : (-h.y - o.z) / min(rr.z, -1e-4);
		float t = min(tf, min(tx, tz));
		vec3 hit = o + rr * t;
		vec3 tile = vec3(0.80, 0.90, 0.93);
		vec2 tp;
		if (t == tf) {
			tp = hit.xz;
			float lw = (2.0 * h.y) / 6.0;
			float lc = (fract((hit.z + h.y) / lw) - 0.5) * lw;
			float lane_line = fill(abs(lc) - 0.125) * step(abs(hit.x), h.x - 2.0);
			lane_line = max(lane_line, fill(abs(abs(hit.x) - (h.x - 2.0)) - 0.125) * fill(abs(lc) - 0.5));
			tile = mix(tile, vec3(0.08, 0.10, 0.20), lane_line);
			// Caustics: two moving cell patterns multiplied.
			float c1 = 1.0 - abs(vnoise(hit.xz * 1.6 + t_now * 0.35) - vnoise(hit.xz * 1.6 - t_now * 0.3 + 3.0)) * 3.0;
			tile *= 1.0 + 0.35 * clamp(c1, 0.0, 1.0) * (1.0 - night_factor);
		} else {
			tp = vec2(t == tx ? hit.z : hit.x, hit.y);
			float band = step(-0.18, hit.y);
			tile = mix(tile, vec3(0.10, 0.22, 0.40), band);
		}
		vec2 grout = abs(fract(tp / 0.15 + 0.5) - 0.5) * 0.15;
		tile *= 1.0 - 0.12 * max(aline(grout.x, 0.006), aline(grout.y, 0.006));
		// The water it was seen through: absorbed toward deep turquoise with distance.
		vec3 absorb = exp(-t * vec3(0.55, 0.15, 0.10));
		vec3 body = tile * absorb + vec3(0.03, 0.30, 0.38) * (1.0 - absorb);
		float cosv = clamp(-rd.y, 0.0, 1.0);
		float fres = 0.02 + 0.98 * pow(1.0 - cosv, 5.0);
		// Lane ropes floating on the surface between the lanes: red, white and blue floats.
		float lw2 = (2.0 * h.y) / 6.0;
		float lr = (fract((p.y + h.y) / lw2 + 0.5) - 0.5) * lw2;
		float rope = fill(abs(lr) - 0.06) * step(abs(p.y), h.y - lw2 * 0.5) * step(abs(p.x), h.x - 0.15);
		float seg = fract(p.x / 0.24);
		vec3 floats = abs(p.x) > h.x - 5.0 ? vec3(0.80, 0.12, 0.10) : (seg < 0.5 ? vec3(0.90, 0.90, 0.88) : vec3(0.12, 0.25, 0.65));
		c = mix(body * (1.0 - fres), floats, rope);
		vec3 sky = disp(sky_tint.rgb);
		emit = mix(sky * fres * 0.9, vec3(0.0), rope);
		// After dark the underwater lights.
		emit += body * vec3(0.4, 0.9, 1.0) * lamp_factor * 0.25 * (1.0 - rope);
		rough = mix(0.04, 0.6, rope);
		spec = 0.5;
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(rip.x * 0.08, 0.0, rip.y * 0.08, 0.0)).xyz * (1.0 - rope));
	} else if (k == 8) {
		c = concrete(w, deck_color, 3.0);
		rough = 0.8;
	} else if (k == 9) {
		c = asphalt(w);
		rough = 0.9;
		if (col.b > 0.5) {
			// The drop-off loop: a lane line round the island, chevrons each way, the red kerb.
			vec2 h = dims;
			float l = aline(abs(p.y) - 2.0, 0.1) * step(abs(p.x), h.x - 6.0);
			vec2 ch = vec2(fract(p.x / 6.0) * 6.0 - 3.0, abs(p.y) - h.y * 0.58);
			float dir = p.y > 0.0 ? 1.0 : -1.0;
			float chev = aline(abs(ch.y) * 1.2 - (ch.x * dir) - 0.6, 0.18) * step(abs(ch.y), 0.9) * step(abs(p.x), h.x - 4.0);
			l = max(l, chev);
			c = paint(c, paint_white, l, w);
			c = mix(c, vec3(0.62, 0.14, 0.12), aline(abs(p.y) - (h.y - 0.15), 0.3));
		}
	} else if (k == 10) {
		c = dirt(w, dg_color);
		c *= 0.95 + 0.1 * hash12(floor(w * 40.0)) * (1.0 - smoothstep(0.01, 0.04, fwidth(w.x)));
		rough = 0.96;
	} else if (k == 11) {
		// Yard games painted on the asphalt: a four-square, a hopscotch ladder, a circle.
		c = asphalt(w);
		vec2 h = dims;
		vec3 yellow = vec3(0.92, 0.78, 0.25);
		vec2 fs = p - vec2(-h.x + 4.0, 0.0);
		float l = rect_line(fs, vec2(-3.0), vec2(3.0), 0.08);
		l = max(l, aseg(fs, vec2(0.0, -3.0), vec2(0.0, 3.0), 0.08));
		l = max(l, aseg(fs, vec2(-3.0, 0.0), vec2(3.0, 0.0), 0.08));
		vec2 hp = p - vec2(h.x - 5.2, 0.0);
		for (int i = 0; i < 8; i++) {
			float x0 = -3.6 + 0.6 * float(i);
			bool dbl = i == 2 || i == 4 || i == 6;
			if (dbl) {
				l = max(l, rect_line(hp, vec2(x0, -0.6), vec2(x0 + 0.6, 0.0), 0.05));
				l = max(l, rect_line(hp, vec2(x0, 0.0), vec2(x0 + 0.6, 0.6), 0.05));
			} else {
				l = max(l, rect_line(hp, vec2(x0, -0.3), vec2(x0 + 0.6, 0.3), 0.05));
			}
		}
		l = max(l, aline(length(p - vec2(0.8, 0.0)) - 1.8, 0.08));
		c = paint(c, yellow, l, w);
		rough = 0.9;
	} else if (k == 13) {
		// The painted map (Schools.G_MAP): the lower 48 on the blacktop in patches of colour with
		// white borders, a compass rose, a star where Los Angeles is, the frame round it.
		c = asphalt(w);
		vec2 h = dims;
		vec2 m = p / max(h - vec2(0.6), vec2(0.5));
		vec2 g = vec2(-95.6 + m.x * 30.2, 37.0 - m.y * 13.6);
		float sd = map_sd(g);
		float fw = max(fwidth(g.x), 0.002);
		float in_map = clamp(0.5 - sd / fw, 0.0, 1.0);
		// The states as a jittered lattice of cells, five colours.
		vec2 cell = floor(g / vec2(5.5, 4.2) + vec2(0.13, 0.27) * floor(g.yx / vec2(4.2, 5.5)));
		vec3 pal[5] = vec3[](vec3(0.85, 0.58, 0.32), vec3(0.42, 0.62, 0.40), vec3(0.88, 0.80, 0.42), vec3(0.50, 0.62, 0.80), vec3(0.80, 0.50, 0.55));
		vec3 st = pal[int(hash12(cell) * 4.999)];
		vec2 cf = fract(g / vec2(5.5, 4.2) + vec2(0.13, 0.27) * floor(g.yx / vec2(4.2, 5.5)));
		float border = max(aline((min(cf.x, 1.0 - cf.x)) * 5.5, 0.18), aline((min(cf.y, 1.0 - cf.y)) * 4.2, 0.18));
		vec3 inkc = mix(st, paint_white, border);
		c = mix(c, inkc, in_map * 0.92);
		float l = aline(sd, 0.22);
		l = max(l, aline(length(g - vec2(-118.2, 34.0)) - 0.55, 0.25));
		l = max(l, rect_line(p, -h + vec2(0.25), h - vec2(0.25), 0.08));
		// A compass rose in the corner over the ocean.
		vec2 cr = p - vec2(-h.x + 1.3, h.y - 1.3);
		l = max(l, aline(length(cr) - 0.7, 0.05));
		l = max(l, aseg(cr, vec2(0.0, -0.95), vec2(0.0, 0.95), 0.06));
		l = max(l, aseg(cr, vec2(-0.95, 0.0), vec2(0.95, 0.0), 0.06));
		c = paint(c, paint_white, l, w);
		rough = 0.9;
	}
	// Hard surfaces darken and gloss in the rain.
	float hard = (k == 3 || k == 4 || k == 5 || k == 8 || k == 9 || k == 11 || k == 13) ? 1.0 : 0.0;
	c *= 1.0 - 0.25 * road_wetness * hard;
	rough = mix(rough, 0.25, road_wetness * hard * 0.7);
	ALBEDO = to_lit(clamp(c, vec3(0.0), vec3(1.0)));
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = to_lit(emit);
}
