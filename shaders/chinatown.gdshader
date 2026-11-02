shader_type spatial;
// Chinatown (ChinatownKit): every building, the gate, the plaza hall, the lanterns and the goods
// of a block in ONE material and one draw. What a face is rides in the vertex alpha (kind / 16,
// ChinatownKit.K_*); its paint in COLOR.rgb as written (sRGB: vertex colours arrive raw on both
// renderers, so they are decoded here). UV is in METRES along each face unless a kind says
// otherwise. Worked in linear (color_space.gdshaderinc), handed over with cs_out().
//
//   0 paint    lacquered paint: columns, piers, railings, brackets
//   1 tile     glazed barrel tiles (u along the eave, v up the slope), COLOR the glaze
//   2 eave     the painted underside of an eave (v >= 0: metres in from the eave edge): rafters in
//              teal and blue on red boards, their ends ringed; v < 0: a painted beam or fascia
//              (-v is 0..1 across it): red borders, gold lines, cartouches every 2.4 m
//   3 ridge    glazed ridge and hip caps, COLOR the glaze
//   4 gold     gilding (ornaments, lantern caps, the hall's finial)
//   5 silk     a lantern (u 0..1 round it, v 0..1 up it): ribs, gold bands, lit at night
//   6 wall     stucco (v = metres above the pavement): grime toward the foot, streaks
//   7 window   an upper-floor window (UV metres in it): lattice muntins in COLOR, glass, a room
//              lit at night by a hash of where it is
//   8 shop     shop glass (UV metres): shelves of goods behind it, lit warm at night
//   9 stone    granite (plinths, steps, the plaza hall's platform)
//  10 sign     an enamel sign board, COLOR the paint
//  11 ink      letters (gilt or painted), lit at night like the real neon-and-gilt signs
//  12 produce  the top of a crate or bucket (UV metres): fruit, greens or flowers by COLOR
//  13 wire     dark cable and iron
//  14 lattice  a timber lattice screen (UV metres), COLOR the timber, dark (or lit) behind
//  15 water    the plaza's pond (only on its own small faces)
// Lanterns sway (UV2.x metres below their hanging point, UV2.y their phase) with wind_factor.
// Shader files use // comments, never #.
#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float wind_factor;
global uniform vec4 sky_tint;

uniform float lantern_night = 6.5;
// After dark the street-level faces carry the light of the shops, lanterns and floods round
// them (a wash fading out with height over the pavement: UV.y is metres up on walls, columns and
// boards), and the enamel sign boards glow as the lit boards they are.
uniform float street_wash = 0.55;
uniform float wash_top = 11.0;
uniform float sign_night = 0.55;
uniform float lantern_day = 0.25;
uniform float window_night = 1.6;
uniform float shop_night = 2.4;
uniform float ink_night = 2.2;
uniform float sway = 0.035;

// The Chinatown refcam (rc3, Rc3Chinatown): 0 = the look as it was, bit for bit. 1 = the shop glass
// traces a room behind it (shelves of goods, a counter, the ceiling's lights; true parallax), the
// lanterns' silk takes a ribbed bulge and a hot core, the eaves' rafters catch the lantern light.
uniform float rc3 = 0.0;
// How deep the traced shop is (metres behind the glass) and how wide one bay of it.
uniform float shop_depth = 4.2;
uniform float shop_bay = 3.0;
// How much of the street wash the lacquer keeps (rc3: less, so a red wall is a wall in the dark, not
// a flat lit red sheet).
uniform float lacquer_wash = 1.0;

varying flat float v_kind;
varying vec3 v_paint;
varying vec3 v_world;
varying flat float v_lit;

void vertex() {
	v_kind = floor(COLOR.a * 16.0 + 0.5);
	v_paint = cs_srgb_to_linear(COLOR.rgb);
	// A lattice face with UV2 (0, Rc3Chinatown.LIT_FLAG) is lit inside every night (the hall).
	v_lit = (UV2.x < 0.0005 && UV2.y > 1.5) ? 1.0 : 0.0;
	if (UV2.x > 0.001) {
		float w = 0.6 + wind_factor * 1.4;
		float t = TIME * (1.1 + fract(UV2.y * 7.3) * 0.5) + UV2.y * 6.2831853;
		vec2 d = vec2(sin(t), sin(t * 0.73 + 1.7)) * sway * w * UV2.x;
		VERTEX.x += d.x;
		VERTEX.z += d.y;
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 1 inside [a, b] along x, antialiased by w.
float band(float x, float a, float b, float w) {
	return smoothstep(a - w, a + w, x) - smoothstep(b - w, b + w, x);
}

// A shop behind the glass, traced (rc3): p = the glass point (u metres along the face, v metres
// over the pavement), d = the view ray in (u, v, out-of-the-wall) with d.z < 0 going in. Rooms are
// `shop_bay` wide along u; shelves line the back and side walls, a counter stands across the
// front third, a ceiling of light panels. Returns the room's colour (light already in it: emitted)
// in .rgb and how far in the ray went (0..1 of the depth) in .a.
vec4 shop_room(vec2 p, vec3 d, float seed, float lit, float px) {
	float depth = shop_depth;
	float bay = shop_bay;
	float floor_v = 0.05;
	float ceil_v = 3.35;
	float cell = floor(p.x / bay);
	float x0 = cell * bay;
	float x1 = x0 + bay;
	vec3 o = vec3(p, 0.0);
	vec3 dd = vec3(abs(d.x) < 1e-4 ? 1e-4 : d.x, abs(d.y) < 1e-4 ? 1e-4 : d.y, min(d.z, -1e-3));
	d = dd;
	vec3 id = 1.0 / dd;
	float tx = d.x > 0.0 ? (x1 - o.x) * id.x : (x0 - o.x) * id.x;
	float ty = d.y > 0.0 ? (ceil_v - o.y) * id.y : (floor_v - o.y) * id.y;
	float tz = (-depth - o.z) * id.z;
	float t = min(tx, min(ty, tz));
	vec3 h = o + d * t;
	float rh = hash21(vec2(cell, seed));
	vec3 wall = mix(vec3(0.20, 0.15, 0.11), vec3(0.28, 0.24, 0.20), rh);
	vec3 lightc = mix(vec3(1.0, 0.78, 0.52), vec3(0.92, 0.95, 1.0), step(0.72, rh));
	vec3 c;
	float avg = smoothstep(0.25, 0.8, px * (1.0 + t * 0.4));
	if (t == ty && d.y > 0.0) {
		// The ceiling: rows of light panels (a lit shop's whole look from the street).
		vec2 g = vec2(h.x / 1.2, h.z / 1.1);
		vec2 f = abs(fract(g) - 0.5);
		float panel = (1.0 - smoothstep(0.30, 0.34, f.x)) * (1.0 - smoothstep(0.18, 0.22, f.y));
		panel = mix(panel, 0.18, avg);
		c = vec3(0.30, 0.28, 0.26) * 0.5 + lightc * panel * (0.9 + 0.9 * lit);
	} else if (t == ty) {
		// The floor: tiles, darker toward the back.
		vec2 g = vec2(h.x, h.z) / 0.45;
		vec2 f = abs(fract(g) - 0.5);
		float joint = max(1.0 - smoothstep(0.44, 0.48, f.x), 0.0) * max(1.0 - smoothstep(0.44, 0.48, f.y), 0.0);
		c = mix(vec3(0.20, 0.19, 0.17), vec3(0.36, 0.33, 0.28), mix(joint, 0.85, avg)) * (0.5 + 0.5 * hash21(floor(g) + seed));
		c *= 1.0 - 0.35 * clamp(-h.z / depth, 0.0, 1.0);
	} else {
		// A wall lined with shelves of goods (back wall or the bay's sides).
		float along = t == tz ? h.x : -h.z;
		float shelf = fract(h.y / 0.42);
		vec2 gc = floor(vec2(along / 0.24, h.y / 0.42));
		float g1 = hash21(gc + seed * 1.7);
		vec3 goods = mix(vec3(0.55, 0.06, 0.03), vec3(0.75, 0.48, 0.10), g1);
		goods = mix(goods, vec3(0.12, 0.40, 0.22), step(0.72, hash21(gc * 1.3 + 2.0)));
		goods = mix(goods, vec3(0.75, 0.74, 0.70), step(0.88, hash21(gc * 0.7 + 5.0)));
		float item = step(0.22, shelf) * step(shelf, 0.86) * step(0.16, g1) * step(h.y, 2.3) * step(0.35, h.y);
		float board = 1.0 - smoothstep(0.0, 0.07, shelf);
		c = mix(wall, goods, mix(item, 0.55 * step(h.y, 2.3) * step(0.35, h.y), avg));
		c = mix(c, vec3(0.09, 0.07, 0.06), board * step(h.y, 2.4) * (1.0 - avg));
		// The sides darker than the back (no light falls on them straight).
		c *= t == tz ? 1.0 : 0.72;
		// Light falling from the ceiling panels, brighter high up.
		c *= 0.45 + 0.55 * smoothstep(0.0, 3.0, h.y);
		// Further in is further from the panels near the glass.
		c *= 1.0 - 0.4 * clamp(-h.z / depth, 0.0, 1.0);
	}
	// A counter across the front third of some bays, its lit front toward the glass.
	float cz = -1.3;
	float tc = (cz - o.z) * id.z;
	vec3 hc = o + d * tc;
	if (tc > 0.0 && tc < t && hc.y < 1.0 && hash21(vec2(cell, seed + 3.1)) < 0.6
			&& hc.x > x0 + 0.5 && hc.x < x1 - 0.9) {
		c = mix(vec3(0.30, 0.10, 0.06), vec3(0.55, 0.42, 0.20), step(0.5, rh)) * (0.6 + 0.4 * smoothstep(0.0, 1.0, hc.y));
		c = mix(c, vec3(0.86, 0.66, 0.30), band(hc.y, 0.88, 0.96, 0.01));
		t = tc;
	}
	return vec4(c, clamp(t * -d.z / depth, 0.0, 1.0));
}

void fragment() {
	// Rounded: an interpolated 3.0 can read 2.9999 (stripes; see lot_ground.gdshader).
	int k = int(v_kind + 0.5);
	vec3 col = v_paint;
	vec3 emit = vec3(0.0);
	float rough = 0.6;
	float spec = 0.5;
	float metal = 0.0;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	vec2 uv = UV;
	float night = clamp(lamp_factor, 0.0, 1.0);
	if (k == 1 || k == 3) {
		// Glazed tiles: barrels across u, courses up v; glossy covers, duller pans.
		float pitch = k == 1 ? 0.27 : 0.42;
		float course = k == 1 ? 0.30 : 0.42;
		float across = (k == 1 ? uv.x : uv.y) / pitch;
		float along_v = (k == 1 ? uv.y : uv.x) / course;
		float ci = floor(along_v);
		float f = fract(across);
		float px = max(fwidth(across), 0.001);
		float fade = smoothstep(0.35, 0.9, px);
		float prof = mix(cos((f - 0.5) * 6.2831853), 0.0, fade);
		float along = fract(along_v);
		float pl = max(fwidth(along_v), 0.001);
		float lip = mix(smoothstep(0.0, 0.12, along), 0.85, smoothstep(0.3, 0.9, pl));
		float tid = floor(across);
		col *= 0.86 + 0.22 * hash21(vec2(tid, ci));
		col *= mix(0.62, 1.12, prof * 0.5 + 0.5);
		col *= mix(0.55, 1.0, lip);
		// Weather: dust in the pans, a little lichen low on the slope.
		col = mix(col, vec3(0.16, 0.15, 0.13), (1.0 - (prof * 0.5 + 0.5)) * 0.18 * noise2(uv * 0.7));
		rough = mix(0.42, 0.18, prof * 0.5 + 0.5);
		spec = 0.6;
		float dx = -sin((f - 0.5) * 6.2831853) * 0.9 * (1.0 - fade);
		float dy = (1.0 - lip) * 1.3;
		nm = normalize(vec3(dx * 0.5, dy * 0.5, 1.0)) * 0.5 + 0.5;
		if (k == 3) {
			nm = vec3(0.5, 0.5, 1.0);
		}
	} else if (k == 2) {
		float px = max(fwidth(uv.x), 0.002);
		if (uv.y >= 0.0) {
			// Rafters across u, their ends ringed along the eave edge.
			float rp = 0.26;
			float ri = floor(uv.x / rp);
			float rf = fract(uv.x / rp);
			float rafter = band(rf, 0.2, 0.8, px / rp);
			vec3 teal = vec3(0.035, 0.26, 0.19);
			vec3 blue = vec3(0.04, 0.11, 0.34);
			vec3 board = vec3(0.42, 0.04, 0.02);
			vec3 r_col = mod(ri, 2.0) < 0.5 ? teal : blue;
			// A gold band and a white line a little in from the end.
			r_col = mix(r_col, vec3(0.62, 0.42, 0.10), band(uv.y, 0.16, 0.22, 0.01));
			r_col = mix(r_col, vec3(0.75, 0.73, 0.66), band(uv.y, 0.25, 0.27, 0.008));
			// The round ends on the edge.
			vec2 d = vec2((rf - 0.5) * rp, uv.y - 0.07);
			float r = length(d);
			float disc = 1.0 - smoothstep(0.065, 0.075, r);
			vec3 end_col = mix(vec3(0.72, 0.70, 0.62), blue, smoothstep(0.035, 0.042, 0.075 - r));
			end_col = mix(end_col, vec3(0.62, 0.42, 0.10), 1.0 - smoothstep(0.015, 0.02, r));
			col = mix(board, r_col, rafter);
			col = mix(col, end_col, disc * step(uv.y, 0.16));
			float avg = smoothstep(0.2, 0.7, px / rp);
			col = mix(col, mix(board, (teal + blue) * 0.5, 0.6), avg);
			// Darker further in under the roof.
			col *= mix(1.15, 0.7, smoothstep(0.3, 1.6, uv.y));
			nm = normalize(vec3((1.0 - avg) * (smoothstep(0.1, 0.2, rf) - smoothstep(0.8, 0.9, rf)) * 0.6 * sign(0.5 - rf), 0.0, 1.0)) * 0.5 + 0.5;
		} else {
			// A painted beam: -v 0..1 across it.
			float a = -uv.y;
			float cp = 2.4;
			float cf = fract(uv.x / cp + 0.5) - 0.5;
			vec3 field = col;
			vec3 red = vec3(0.32, 0.025, 0.015);
			vec3 gold = vec3(0.62, 0.42, 0.10);
			vec3 blue = vec3(0.025, 0.07, 0.22);
			float border = 1.0 - band(a, 0.14, 0.86, 0.01);
			col = mix(field, red, border);
			col = mix(col, gold, band(a, 0.12, 0.16, 0.008) + band(a, 0.84, 0.88, 0.008));
			// The cartouche: a gold-edged lozenge of blue every cp metres.
			float lz = abs(cf * cp) / 0.9 + abs(a - 0.5) / 0.34;
			col = mix(col, blue, 1.0 - smoothstep(0.92, 0.96, lz));
			col = mix(col, gold, band(lz, 0.92, 1.0, 0.02));
			// Small gold dots between cartouches.
			float dots = 1.0 - smoothstep(0.03, 0.04, length(vec2(fract(uv.x / 0.3) - 0.5, (a - 0.5) * 2.0) * vec2(0.3, 0.25)));
			col = mix(col, gold, dots * step(0.95, lz) * band(a, 0.2, 0.8, 0.01));
			float avg = smoothstep(0.15, 0.6, px);
			col = mix(col, mix(field, red, 0.35), avg * 0.7);
			rough = 0.45;
			metal = (band(a, 0.12, 0.16, 0.008) + band(a, 0.84, 0.88, 0.008)) * 0.6 * (1.0 - avg);
		}
		rough = max(rough, 0.5);
	} else if (k == 4) {
		metal = 0.9;
		rough = 0.3 + 0.15 * noise2(uv * 9.0);
		col = v_paint;
		spec = 0.5;
	} else if (k == 5) {
		// A silk lantern: ribs round it, gold bands at both ends, lit from inside.
		float ribs = 10.0;
		float rf = fract(uv.x * ribs);
		float px = max(fwidth(uv.x * ribs), 0.001);
		float rib = (1.0 - smoothstep(0.0, 0.06 + px, rf)) + smoothstep(0.94 - px, 1.0, rf);
		rib *= 1.0 - smoothstep(0.3, 0.8, px);
		float bands = band(uv.y, 0.05, 0.11, 0.01) + band(uv.y, 0.89, 0.95, 0.01);
		float bulge = sin(clamp(uv.y, 0.0, 1.0) * 3.14159);
		vec3 silk = col * (0.85 + 0.15 * noise2(uv * vec2(40.0, 8.0)));
		col = mix(silk, vec3(0.30, 0.03, 0.02), rib * 0.6);
		col = mix(col, vec3(0.62, 0.42, 0.10), clamp(bands, 0.0, 1.0));
		// Deep red through the silk, a warmer core where the lamp inside is nearest (a lantern
		// glowing pale peach all over read as a paper ball, not silk).
		float core = pow(bulge, 3.0) * pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		vec3 glow = mix(v_paint * vec3(1.0, 0.32, 0.18), v_paint * vec3(1.0, 0.62, 0.32) + vec3(0.12, 0.04, 0.0), core);
		float lit = mix(lantern_day, lantern_night, night) * (0.35 + 0.65 * bulge) * (1.0 - rib * 0.6) * (1.0 - clamp(bands, 0.0, 1.0) * 0.8);
		emit = glow * lit;
		if (rc3 > 0.5) {
			// rc3: a silk lantern through AgX. Bright and red-heavy it went salmon-white (every
			// lantern a pale ball); held under ~1.6 in red with green at ~0.4 of it in the core it
			// stays the deep red-orange of lit silk, the ribs and the ends dark against it.
			float gold = step(0.3, v_paint.g / max(v_paint.r, 0.01));
			vec3 rim = gold > 0.5 ? vec3(1.0, 0.30, 0.03) : vec3(1.0, 0.05, 0.02);
			vec3 hot = gold > 0.5 ? vec3(1.0, 0.48, 0.10) : vec3(1.0, 0.24, 0.06);
			float view_c = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
			float c2 = pow(bulge, 1.5) * view_c;
			vec3 glow2 = mix(rim * 0.6, hot, c2);
			float lit2 = mix(0.08, 0.85, night) * (0.3 + 0.7 * bulge) * (1.0 - rib * 0.75) * (1.0 - clamp(bands, 0.0, 1.0) * 0.85);
			emit = glow2 * lit2;
			col = mix(col, col * 0.7, rib);
		}
		BACKLIGHT = cs_out(col * 0.6);
		rough = 0.55;
		spec = 0.3;
	} else if (k == 6) {
		float n = noise2(uv * vec2(2.3, 2.3)) * 0.6 + noise2(uv * 9.0) * 0.4;
		col *= 0.9 + 0.16 * n;
		float streak = noise2(vec2(uv.x * 1.7, uv.y * 0.12));
		col *= 1.0 - 0.12 * smoothstep(0.55, 0.9, streak);
		col *= mix(0.72, 1.0, smoothstep(0.0, 1.4, uv.y));
		rough = 0.88;
		spec = 0.35;
	} else if (k == 7 || k == 14) {
		// Lattice: muntins on a grid (a window's or a screen's), glass or dark behind.
		float g = k == 7 ? 0.28 : 0.16;
		vec2 c = uv / g;
		vec2 f = abs(fract(c) - 0.5);
		vec2 px = max(fwidth(c), vec2(0.001));
		float bar_w = k == 7 ? 0.09 : 0.16;
		float bars = max(1.0 - smoothstep(bar_w - px.x, bar_w + px.x, 0.5 - f.x), 1.0 - smoothstep(bar_w - px.y, bar_w + px.y, 0.5 - f.y));
		// A screen's fretwork: every other cell is split again (the alternating T pattern).
		if (k == 14) {
			vec2 cell = floor(c);
			float alt = mod(cell.x + cell.y, 2.0);
			float mid = 1.0 - smoothstep(0.06 - px.x, 0.06 + px.x, abs(fract(c.x) - 0.5));
			bars = max(bars, mid * alt);
		}
		float avg = smoothstep(0.3, 0.8, max(px.x, px.y));
		bars = mix(bars, 0.45, avg);
		vec3 frame = col;
		float cell_h = hash21(floor(v_world.xz * 0.45) + floor(v_world.y / 3.0) * 7.1);
		float lit = max(step(0.42, cell_h), v_lit * rc3) * night;
		vec3 room = vec3(1.0, 0.72, 0.42) * (0.5 + 0.5 * hash21(vec2(cell_h, 3.0)));
		vec3 glass = k == 7 ? mix(vec3(0.03, 0.035, 0.04), cs_srgb_to_linear(sky_tint.rgb) * 0.3, 0.3) : vec3(0.025, 0.02, 0.018);
		col = mix(glass, frame, bars);
		emit = room * (k == 7 ? window_night : window_night * 0.5) * lit * (1.0 - bars) * (k == 7 ? 1.0 : 0.6);
		if (rc3 > 0.5 && k == 7) {
			// rc3: a lit flat upstairs, not a cream panel - a lamp's warm pool high in the pane,
			// falling off toward the sill, and drawn curtains (thin, backlit) in half the rooms.
			float wv = clamp((fract((uv.y - 4.4) / 3.4) - 0.28) / 0.51, 0.0, 1.0);
			float ch = hash21(floor(v_world.xz * 0.45) + floor(v_world.y / 3.0) * 3.3);
			vec3 tone = mix(vec3(1.0, 0.55, 0.24), vec3(1.0, 0.72, 0.45), ch);
			float grad = 0.35 + 0.65 * smoothstep(0.0, 1.0, wv);
			vec3 curtain = mix(vec3(0.75, 0.18, 0.08), vec3(0.85, 0.70, 0.45), step(0.5, fract(ch * 7.0)));
			vec3 inside = mix(tone * grad, curtain * 0.55, step(0.55, ch));
			emit = inside * 0.85 * lit * (1.0 - bars);
		}
		if (rc3 > 0.5 && v_lit > 0.5) {
			// The hall's screens: a warm hall behind the fretwork, brighter low (lamps inside),
			// the timber itself catching a little of it.
			// Lamps inside hang at about head height: the screen is brightest round them and falls
			// off up and down it, the fretwork itself dark against the glow.
			float lamp = exp(-pow((fract(uv.y / 3.6) - 0.45) * 2.6, 2.0));
			vec3 hall = vec3(1.0, 0.36, 0.10) * (0.7 + 0.5 * noise2(v_world.xz * 0.9 + uv.y * 0.3));
			emit = hall * (0.25 + 0.75 * lamp) * 0.55 * night * (1.0 - bars * 0.9);
			col = mix(vec3(0.02, 0.012, 0.008), frame * 0.5, bars);
		}
		rough = mix(0.1, 0.5, bars);
		spec = mix(0.6, 0.4, bars);
	} else if (k == 8) {
		// Shop glass: shelves of goods behind it, lit warm after dark.
		vec2 cell = floor(uv / vec2(0.22, 0.42));
		float shelf = fract(uv.y / 0.42);
		float px = max(fwidth(uv.y / 0.42), 0.001);
		float h = hash21(cell + floor(v_world.xz * 0.2));
		vec3 goods = mix(vec3(0.5, 0.08, 0.05), vec3(0.75, 0.55, 0.15), h);
		goods = mix(goods, vec3(0.1, 0.35, 0.18), step(0.7, hash21(cell * 1.7)));
		float item = step(0.25, shelf) * step(shelf, 0.85) * step(0.18, h);
		float shelves = 1.0 - smoothstep(0.0, 0.05 + px, shelf);
		vec3 inside = mix(vec3(0.20, 0.17, 0.13), goods, item * (1.0 - smoothstep(0.3, 0.9, px)) + 0.25 * smoothstep(0.3, 0.9, px));
		inside = mix(inside, vec3(0.08, 0.07, 0.06), shelves);
		float open_ = step(0.18, hash21(floor(v_world.xz * 0.12)));
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		col = vec3(0.02);
		emit = inside * (0.18 + shop_night * night * open_) + cs_srgb_to_linear(sky_tint.rgb) * (0.05 + 0.4 * fres) * (1.0 - night * 0.7);
		if (rc3 > 0.5) {
			vec3 ray = -VIEW;
			vec3 d3 = vec3(dot(ray, TANGENT), dot(ray, BINORMAL), dot(ray, NORMAL));
			float pxs = max(fwidth(uv.x), fwidth(uv.y)) / 0.24;
			float sd = floor(hash21(floor(v_world.xz * 0.12)) * 97.0);
			vec4 room = shop_room(uv, d3, sd, night * open_, pxs);
			// Glass: the room through it (dimmed by Fresnel), the street's sky mirrored on top.
			emit = room.rgb * (0.12 + shop_night * 0.42 * night * open_) * (1.0 - 0.6 * fres)
				+ cs_srgb_to_linear(sky_tint.rgb) * (0.04 + 0.45 * fres) * (1.0 - night * 0.6);
		}
		rough = 0.05;
		spec = 0.6;
	} else if (k == 9) {
		float n = hash21(floor(uv * 90.0)) * 0.5 + noise2(uv * 6.0) * 0.5;
		col *= 0.82 + 0.3 * n;
		rough = 0.62;
		spec = 0.45;
	} else if (k == 10) {
		col *= 0.95 + 0.08 * noise2(uv * 4.0);
		rough = 0.32;
		spec = 0.55;
		emit += col * sign_night * night;
	} else if (k == 11) {
		float gilt = step(0.45, col.r) * step(col.b * 2.5, col.g + 0.02);
		metal = 0.85 * gilt;
		rough = mix(0.45, 0.25, gilt);
		emit = col * ink_night * night * (gilt > 0.5 ? 0.55 : 1.0);
	} else if (k == 12) {
		// The goods: fruit in a hex pack (or greens, or flowers) by the crate's colour.
		float r = 0.052;
		vec2 p = uv / vec2(r * 2.0, r * 1.732);
		float row = floor(p.y);
		p.x += mod(row, 2.0) * 0.5;
		vec2 cell = floor(p);
		vec2 f = fract(p) - 0.5;
		f.y *= 0.866;
		float d = length(f) * 2.0;
		float px = max(fwidth(p.x), 0.001);
		float fruit = 1.0 - smoothstep(0.86 - px * 2.0, 0.86 + px * 2.0, d);
		float h = hash21(cell);
		bool leafy = col.g > col.r * 1.2 && col.b < col.g;
		bool flowers = col.b > 0.25 && col.r > 0.25;
		vec3 fc = col * (0.75 + 0.45 * h);
		if (flowers) {
			fc = mix(vec3(0.75, 0.08, 0.20), vec3(0.85, 0.65, 0.05), step(0.5, h));
			fc = mix(fc, vec3(0.80, 0.78, 0.74), step(0.82, h));
		}
		vec3 between = flowers ? vec3(0.04, 0.12, 0.03) : vec3(0.06, 0.04, 0.025);
		if (leafy) {
			float leaf = noise2(uv * 30.0) * 0.6 + noise2(uv * 80.0) * 0.4;
			col = col * (0.55 + 0.75 * leaf);
			nm = normalize(vec3(dFdx(leaf) * 8.0, dFdy(leaf) * 8.0, 1.0)) * 0.5 + 0.5;
			rough = 0.6;
		} else {
			float avg = smoothstep(0.25, 0.7, px);
			col = mix(mix(between, fc, fruit), mix(between, col, 0.75), avg);
			vec2 sn = f * 2.0 * (1.0 - avg) * fruit;
			nm = normalize(vec3(sn * 1.4, 1.0)) * 0.5 + 0.5;
			rough = flowers ? 0.6 : 0.35;
			spec = 0.5;
		}
	} else if (k == 13) {
		col *= 1.0;
		rough = 0.5;
		metal = 0.3;
	} else if (k == 15) {
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		col = vec3(0.02, 0.05, 0.045);
		emit = cs_srgb_to_linear(sky_tint.rgb) * (0.08 + 0.55 * fres) * (1.0 - night * 0.85);
		float rip = noise2(uv * 3.0 + TIME * 0.2) - noise2(uv * 3.0 - TIME * 0.17 + 4.0);
		nm = normalize(vec3(rip * 0.4, rip * 0.3, 1.0)) * 0.5 + 0.5;
		rough = 0.05;
		spec = 0.7;
	} else {
		// Lacquer: a faint grain and a little wear.
		col *= 0.92 + 0.12 * noise2(uv * vec2(1.5, 14.0));
		rough = 0.34;
		spec = 0.5;
	}
	// The street wash: walls, lacquer, stone and painted beams near the pavement.
	if (k == 0 || k == 6 || k == 9 || (k == 2 && uv.y < 0.0)) {
		float h = (k == 2) ? 4.0 : uv.y;
		float wash = street_wash * night * (1.0 - smoothstep(2.5, wash_top, h)) * step(-1.0, h);
		wash *= (k == 0) ? lacquer_wash : 1.0;
		emit += col * vec3(1.0, 0.72, 0.48) * wash;
	}
	ALBEDO = cs_out(col);
	EMISSION = cs_out(emit);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.0;
}
