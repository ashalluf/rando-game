shader_type spatial;
render_mode cull_back;
// The civic buildings' windows (CivicKit / CivicGeo): glass that mirrors the sky by Fresnel and,
// behind it, the room TRACED per pixel so it has true parallax - a library's book stacks and wall
// shelving, a post office's wall of boxes and its counter, an office's desks and partitions, a
// hall's sprung floor and its far wall, a lobby. The pane carries its own UV in metres from its
// lower corner, its size in UV2, a random in COLOR.a, how far the room's floor is below the pane in
// COLOR.r (x 4 m) and the room's height in COLOR.g (x 8 m). The pane's frame is worked out per
// pixel from the derivatives (the walls are mirrored per site, so a tangent cannot be baked).
// Lit after dark while the building is open (city_hour), dim night lights otherwise. Works in
// linear on both renderers (color_space.gdshaderinc).
#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float city_hour;
global uniform vec4 sky_tint;

// 0 library, 1 post office, 2 office, 3 hall, 4 entrance lobby.
uniform int room = 0;
// Opening hours (city hour): the lights are on inside them.
uniform vec2 open_hours = vec2(8.5, 20.0);
uniform float night_energy = 1.5;
uniform vec3 tint = vec3(0.012, 0.018, 0.022);
uniform float mirror = 0.5;

float h11(float x) {
	return fract(sin(x * 91.17) * 43758.5453);
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Book spines along a shelf: colour by spine, a dark gap between them.
vec3 books(vec2 p, float px) {
	float shelf = 0.36;
	float row = floor(p.y / shelf);
	float fy = fract(p.y / shelf);
	float w = 0.035 + 0.03 * h11(row * 3.1);
	float col = floor(p.x / w + h11(row) * 7.0);
	float fx = fract(p.x / w + h11(row) * 7.0);
	float r = h21(vec2(col, row));
	vec3 c = mix(vec3(0.42, 0.10, 0.08), vec3(0.10, 0.18, 0.32), step(0.35, r));
	c = mix(c, vec3(0.16, 0.26, 0.14), step(0.62, r));
	c = mix(c, vec3(0.62, 0.52, 0.34), step(0.8, r));
	c = mix(c, vec3(0.75, 0.72, 0.65), step(0.93, r));
	float top = 0.62 + 0.3 * h21(vec2(col, row + 7.0));
	float spine = step(fy, top) * step(0.06, fy);
	// Under a pixel a spine reads as the shelf's mean.
	float fade = smoothstep(0.02, 0.06, px);
	vec3 shelf_col = vec3(0.34, 0.24, 0.15);
	vec3 book = mix(c * (0.75 + 0.25 * step(0.12, fx) * step(fx, 0.9)), vec3(0.24, 0.17, 0.13), fade);
	return fy < 0.06 ? shelf_col : mix(vec3(0.05, 0.04, 0.035), book, spine);
}

void fragment() {
	vec3 P = VERTEX;
	vec3 N = normalize(NORMAL);
	vec3 V = normalize(-P);
	vec2 uv = UV;
	vec2 size = UV2;
	float rnd = COLOR.a;
	float sill = COLOR.r * 4.0;
	float room_h = max(COLOR.g * 8.0, 2.6);
	// The pane's frame from the derivatives: T along +u, B up.
	vec3 dp1 = dFdx(P);
	vec3 dp2 = dFdy(P);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);
	vec3 dp2perp = cross(dp2, N);
	vec3 dp1perp = cross(N, dp1);
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
	float inv = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-12));
	T *= inv;
	B *= inv;
	T = normalize(T - N * dot(N, T));
	B = normalize(B - N * dot(N, B) - T * dot(T, B));
	vec3 d = vec3(dot(-V, T), dot(-V, B), dot(V, N));
	d.z = max(d.z, 0.05);
	// The room in pane space: x along the pane, y up from the pane's bottom, z in.
	float depth = room == 3 ? 12.0 : (room == 4 ? 4.5 : (room == 1 ? 6.5 : 5.8));
	vec3 o = vec3(uv, 0.0);
	float floor_y = -sill;
	float ceil_y = room_h - sill;
	float x0 = -4.0;
	float x1 = size.x + 4.0;
	float t = (depth - o.z) / d.z;
	int hit = 0; // 0 back wall, 1 floor, 2 ceiling, 3 side, 4 furniture face, 5 furniture top
	if (d.y < 0.0) {
		float tf = (floor_y - o.y) / d.y;
		if (tf < t) { t = tf; hit = 1; }
	} else if (d.y > 0.0) {
		float tc = (ceil_y - o.y) / d.y;
		if (tc < t) { t = tc; hit = 2; }
	}
	if (d.x < 0.0) {
		float ts = (x0 - o.x) / d.x;
		if (ts < t) { t = ts; hit = 3; }
	} else if (d.x > 0.0) {
		float ts = (x1 - o.x) / d.x;
		if (ts < t) { t = ts; hit = 3; }
	}
	// Furniture: one plane across the room at fz, fh tall from the floor, with gaps.
	float fz = room == 0 ? 2.6 : (room == 1 ? 3.1 : (room == 2 ? 2.0 : 99.0));
	float fh = room == 0 ? 1.55 : (room == 1 ? 1.05 : (room == 2 ? 1.25 : 0.0));
	float tz = (fz - o.z) / d.z;
	if (tz > 0.0 && tz < t) {
		vec3 q = o + d * tz;
		float gap = room == 0 ? step(fract((q.x + rnd * 9.0) / 4.2), 0.72) : (room == 2 ? step(fract((q.x + rnd * 5.0) / 3.4), 0.8) : 1.0);
		if (q.y < floor_y + fh && gap > 0.5) { t = tz; hit = 4; }
	}
	vec3 h = o + d * t;
	float wy = h.y - floor_y;
	float px = length(vec2(length(dFdx(uv)), length(dFdy(uv)))) * (1.0 + t * 0.4);
	vec3 c;
	if (hit == 1) {
		// Floors: carpet, linoleum, the hall's maple boards and lines, terrazzo.
		if (room == 3) {
			float board = fract(h.x / 0.06);
			c = vec3(0.58, 0.40, 0.22) * (0.88 + 0.12 * h21(vec2(floor(h.x / 0.06), floor(h.z / 1.8))));
			float line = 1.0 - smoothstep(0.03, 0.06 + px, abs(h.z - 6.0));
			c = mix(c, vec3(0.7, 0.12, 0.1), line);
		} else if (room == 4) {
			c = vec3(0.62, 0.6, 0.56) * (0.9 + 0.1 * h21(floor(h.xz / 0.03)));
		} else if (room == 0) {
			c = vec3(0.16, 0.20, 0.26);
		} else {
			c = vec3(0.42, 0.42, 0.40) * (0.92 + 0.08 * step(0.5, fract((h.x + h.z) / 0.6)));
		}
	} else if (hit == 2) {
		// Ceilings: troffers in a grid, or the hall's trusses.
		vec2 g = fract(vec2(h.x / 2.4, h.z / 1.8));
		float panel = step(0.15, g.x) * step(g.x, 0.85) * step(0.35, g.y) * step(g.y, 0.65);
		c = room == 3 ? vec3(0.22, 0.22, 0.24) : vec3(0.78, 0.77, 0.74);
		c = mix(c, vec3(2.5), panel * (room == 3 ? 0.0 : 1.0));
		if (room == 3) {
			c = mix(c, vec3(0.08), step(0.9, fract(h.z / 3.0)));
		}
	} else if (hit == 3) {
		c = room == 0 ? books(vec2(h.z * 1.0 + 3.0, wy), px) : vec3(0.72, 0.70, 0.66);
		if (room == 0 && wy > 2.25) {
			c = vec3(0.80, 0.76, 0.66);
		}
	} else if (hit == 4) {
		if (room == 0) {
			c = books(vec2(h.x, wy), px);
		} else if (room == 1) {
			c = wy > fh - 0.06 ? vec3(0.66, 0.60, 0.52) : vec3(0.40, 0.27, 0.17) * (0.85 + 0.15 * step(0.08, fract(h.x / 1.2)));
		} else {
			c = wy > fh - 0.05 ? vec3(0.62, 0.58, 0.52) : vec3(0.36, 0.40, 0.44);
		}
	} else {
		// The back wall.
		if (room == 0) {
			c = wy < 2.25 ? books(vec2(h.x, wy), px) : vec3(0.82, 0.78, 0.68);
		} else if (room == 1) {
			// A wall of brass-doored boxes, posters above it.
			vec2 b = vec2(h.x / 0.16, (wy - 0.3) / 0.12);
			vec2 f = fract(b);
			float door = step(0.1, f.x) * step(f.x, 0.92) * step(0.12, f.y) * step(f.y, 0.9);
			vec3 brass = vec3(0.62, 0.48, 0.24) * mix(1.0, 0.75, step(0.55, f.x) * step(f.x, 0.7) * step(0.4, f.y) * step(f.y, 0.6));
			c = mix(vec3(0.08, 0.07, 0.06), brass, door);
			c = mix(c, vec3(0.62, 0.48, 0.24) * 0.85, smoothstep(0.03, 0.1, px));
			if (wy < 0.3 || wy > 2.1) {
				c = vec3(0.86, 0.84, 0.78);
				float poster = step(2.4, wy) * step(wy, 3.1) * step(0.55, fract(h.x / 3.0));
				c = mix(c, mix(vec3(0.12, 0.2, 0.46), vec3(0.72, 0.16, 0.14), step(0.5, h21(vec2(floor(h.x / 3.0), 1.0)))), poster);
			}
		} else if (room == 3) {
			c = vec3(0.70, 0.62, 0.52);
			float board = step(abs(h.x - size.x * 0.5), 0.9) * step(3.0, wy) * step(wy, 4.1);
			c = mix(c, vec3(0.92), board);
			c = mix(c, vec3(0.85, 0.32, 0.08), step(abs(h.x - size.x * 0.5), 0.23) * step(abs(wy - 3.05), 0.03));
		} else if (room == 4) {
			c = vec3(0.80, 0.77, 0.70);
			c = mix(c, vec3(0.55, 0.42, 0.28), step(0.9, wy) * step(wy, 2.0) * step(abs(h.x - size.x * 0.5), 0.9));
		} else {
			c = vec3(0.80, 0.79, 0.76);
			c = mix(c, vec3(0.32, 0.24, 0.18), step(wy, 2.1) * step(abs(fract(h.x / 4.5) - 0.5), 0.1));
		}
	}
	// Light in the room: daylight falling off inward, the ceiling lights while it is open, a
	// night light otherwise; a share of the panes' blinds part drawn.
	float sky_l = dot(pow(max(sky_tint.rgb, vec3(0.0)), vec3(2.2)), vec3(0.3333));
	float hr = city_hour;
	float open = step(open_hours.x, hr) * step(hr, open_hours.y);
	float day = (1.0 - lamp_factor) * sky_l * mix(0.32, 0.1, clamp(t / 8.0, 0.0, 1.0));
	vec3 lamp = vec3(1.0, 0.9, 0.76) * (room == 2 || room == 1 ? vec3(0.92, 0.97, 1.05) : vec3(1.0));
	float lights = (open * 0.85 + (1.0 - open) * 0.05 * step(0.6, rnd)) * (0.75 + 0.25 * smoothstep(0.0, room_h, wy + 0.5));
	vec3 room_col = c * (day + lamp * lights * mix(0.18, night_energy, lamp_factor));
	float blind = 1.0 - 0.8 * step(uv.y / max(size.y, 0.1), 1.0) * step(1.0 - fract(rnd * 3.71) * 0.45, uv.y / max(size.y, 0.1)) * step(0.55, fract(rnd * 5.3)) * (room == 4 ? 0.0 : 1.0);
	room_col *= blind;
	// The glass: a sky mirror by Fresnel (emitted: it does not depend on the light on the pane).
	float ndv = clamp(dot(N, V), 0.0, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	vec3 sky = pow(max(sky_tint.rgb, vec3(0.0)), vec3(2.2));
	vec3 emit = room_col * (1.0 - fres) * 0.9 + sky * fres * mirror * (1.0 - 0.75 * lamp_factor);
	ALBEDO = cs_out(tint);
	METALLIC = 0.1;
	ROUGHNESS = 0.06;
	SPECULAR = 0.55;
	EMISSION = cs_out(emit);
}
