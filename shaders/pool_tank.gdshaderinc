// A swimming pool's tank as seen from INSIDE the water (PoolUnder, scripts/world/pool_under.gd;
// docs/HANDOFF.md "Under the water of a hill home's pool"). Shared by the tank's own walls
// (pool_tank.gdshader) and the underside of the surface (water_underside.gdshader), which mirrors
// the tank by total internal reflection and sees the sky and the house through Snell's window - so
// both draw the same tiles, the same caustics and the same shadows of the walls.
//
// The tank is a box in its pool's frame (HillHomeKit's: u across, v toward the view, metres; y
// true world): [u0, u1] x [v0, v1] x [floor, surface]. v1 is the water's far end; on an infinity
// pool (pt_weir 1) the wall there stops WEIR_DROP under the surface and the water runs over it.
// Everything is lit here by hand from the published sun (tree_sun, sun_direction): the pad the
// pool is cut into is a solid box over the tank, and the renderer's shadow map would black it out.
// Linear light; the caller hands the result through cs_out().

global uniform vec3 tree_sun;
global uniform vec3 sun_direction;
global uniform vec4 sky_tint;
global uniform float night_factor;
global uniform float lamp_factor;
global uniform vec3 origin_shift;

uniform vec2 pt_o = vec2(0.0);
uniform vec2 pt_fu = vec2(1.0, 0.0);
uniform vec2 pt_fv = vec2(0.0, 1.0);
// u0, v0, u1, v1.
uniform vec4 pt_rect = vec4(0.0, 0.0, 1.0, 1.0);
// The surface and the floor (true world y).
uniform vec2 pt_y = vec2(0.0, -1.7);
uniform float pt_weir = 0.0;
// Red, green, blue taken out per metre of pool water (clearer than the sea's).
uniform vec3 pt_absorb = vec3(0.22, 0.04, 0.03);
// The tile: the glass mosaic's colour and the waterline band's (linear).
uniform vec3 pt_tile = vec3(0.30, 0.56, 0.62);
uniform vec3 pt_band = vec3(0.025, 0.09, 0.16);
uniform float pt_seed = 0.0;

const float PT_WEIR_DROP = 0.06;
const float PT_MOSAIC = 0.05;
const float PT_BAND = 0.16;
const float PT_IOR = 1.333;

vec3 pt_frame(vec3 tw) {
	vec2 d = tw.xz - pt_o;
	return vec3(dot(d, pt_fu), dot(d, pt_fv), tw.y);
}

vec3 pt_dir(vec3 wd) {
	return vec3(dot(wd.xz, pt_fu), dot(wd.xz, pt_fv), wd.y);
}

float pt_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// The caustic net (an iterated warp, after the classic tileable water-caustic): bright folded
// lines over a dim field, mean about 1. `fw` the footprint in the net's own units: once a line is
// under a pixel it fades to its mean, never to sequins.
float pt_caustic(vec2 p, float t, float fw) {
	vec2 q = mod(p * 6.2831853, 6.2831853) - 250.0;
	vec2 i = q;
	float c = 1.0;
	float inten = 0.005;
	for (int n = 0; n < 4; n++) {
		float tt = t * (1.0 - 3.5 / float(n + 1));
		i = q + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(q.x / (sin(i.x + tt) / inten), q.y / (cos(i.y + tt) / inten)));
	}
	c /= 4.0;
	c = 1.17 - pow(c, 1.4);
	float v = pow(abs(c), 8.0);
	return mix(0.35 + v * 2.6, 1.0, smoothstep(0.08, 0.35, fw));
}

// Coverage of grout lines `w` wide every `p` metres, box filtered over the footprint `fw`.
float pt_lines(float x, float p, float w, float fw) {
	float f = max(fw, p * 1.0e-3);
	float a = x - f * 0.5;
	float b = x + f * 0.5;
	float sa = a / p + 0.5 * w / p;
	float sb = b / p + 0.5 * w / p;
	float ia = floor(sa) * w + min(fract(sa) * p, w);
	float ib = floor(sb) * w + min(fract(sb) * p, w);
	return clamp((ib - ia) / f, 0.0, 1.0);
}

// The tiles at `st` (metres in the face), `depth` metres under the surface on a wall (-1 the floor).
vec3 pt_albedo(vec2 st, float depth, float fw) {
	bool band = depth >= 0.0 && depth < PT_BAND;
	float p = band ? 0.152 : PT_MOSAIC;
	vec2 cell = floor(st / p);
	float h = pt_hash(cell + pt_seed * 17.0);
	vec3 tile = band ? pt_band : pt_tile;
	// Glass mosaic: each chip a little off its neighbours in tone and hue.
	tile *= band ? (0.85 + 0.3 * h) : (0.82 + 0.36 * h);
	tile.g *= band ? 1.0 : (0.94 + 0.12 * pt_hash(cell.yx + 3.1));
	vec3 mean = band ? pt_band : pt_tile;
	float detail = 1.0 - smoothstep(p * 0.35, p * 0.9, fw);
	tile = mix(mean, tile, detail);
	float g = max(pt_lines(st.x, p, 0.004, fw), pt_lines(st.y, p, 0.004, fw));
	vec3 grout = vec3(0.55, 0.58, 0.56);
	vec3 c = mix(tile, grout, g);
	// A dark line of grime at the waterline on the band's top.
	if (depth >= 0.0) {
		c *= mix(0.72, 1.0, smoothstep(0.0, 0.03, depth));
	}
	return c;
}

// The light reaching a point of the tank (frame position `f`, frame normal `nf`), linear: the sun
// through the surface - refracted, focused into caustics, shadowed where its way up leaves the
// pool through a wall, absorbed on the way - and the sky's light through the surface.
vec3 pt_light(vec3 f, vec3 nf, float fw, float t) {
	vec3 s = pt_dir(normalize(sun_direction));
	vec3 sd = refract(-s, vec3(0.0, 0.0, 1.0), 1.0 / PT_IOR);
	vec3 L = -sd; // toward the light, upward (frame: x u, y v, z up)
	L = vec3(L.x, L.y, max(L.z, 0.15));
	float up = max(pt_y.x - f.z, 0.0);
	float tl = up / L.z;
	vec2 entry = f.xy + L.xy * tl;
	// The way up must come out of the water inside the pool (else a wall shades it), softly.
	float sh = smoothstep(-0.04, 0.06, entry.x - pt_rect.x) * smoothstep(-0.04, 0.06, pt_rect.z - entry.x)
		* smoothstep(-0.04, 0.06, entry.y - pt_rect.y) * smoothstep(-0.04, 0.06, pt_rect.w - entry.y);
	float ndl = max(dot(nf, L), 0.0);
	// The caustics focus with depth: none at the surface, full a metre and more down.
	float focus = smoothstep(0.05, 1.1, up);
	vec2 cq = (entry + vec2(pt_seed * 3.7, pt_seed * 1.3)) * 0.42;
	float caus = mix(1.0, pt_caustic(cq, t * 0.55, fw * 0.42 * 6.0), focus);
	vec3 sun = tree_sun * ndl * sh * caus * 0.96 * exp(-pt_absorb * tl);
	vec3 sky = cs_srgb_to_linear(sky_tint.rgb) * (1.0 - 0.85 * night_factor);
	float skyw = mix(0.25, 0.85, clamp(nf.z * 0.5 + 0.5, 0.0, 1.0));
	vec3 amb = sky * skyw * 0.55 * exp(-pt_absorb * up * 1.4);
	return sun + amb;
}

// One point of the tank shaded (linear).
vec3 pt_shade(vec3 f, vec3 nf, vec2 st, float depth, float fw, float t) {
	return pt_albedo(st, depth, fw) * pt_light(f, nf, fw, t);
}

// From frame point `f` along frame direction `d` (going DOWN or sideways, inside the tank): the
// first face hit. Returns the distance in .w and fills the hit's frame normal, face coordinates and
// depth under the surface; `out_open` is set when the ray leaves over the vanishing edge instead.
vec4 pt_trace(vec3 f, vec3 d, out vec3 nf, out vec2 st, out float depth, out bool out_open) {
	float tbest = 1.0e6;
	nf = vec3(0.0, 0.0, 1.0);
	st = vec2(0.0);
	depth = -1.0;
	out_open = false;
	if (d.z < -1.0e-4) {
		float t = (pt_y.y - f.z) / d.z;
		if (t < tbest) { tbest = t; nf = vec3(0.0, 0.0, 1.0); }
	}
	if (d.x < -1.0e-4) {
		float t = (pt_rect.x - f.x) / d.x;
		if (t < tbest) { tbest = t; nf = vec3(1.0, 0.0, 0.0); }
	}
	if (d.x > 1.0e-4) {
		float t = (pt_rect.z - f.x) / d.x;
		if (t < tbest) { tbest = t; nf = vec3(-1.0, 0.0, 0.0); }
	}
	if (d.y < -1.0e-4) {
		float t = (pt_rect.y - f.y) / d.y;
		if (t < tbest) { tbest = t; nf = vec3(0.0, 1.0, 0.0); }
	}
	if (d.y > 1.0e-4) {
		float t = (pt_rect.w - f.y) / d.y;
		if (t < tbest) { tbest = t; nf = vec3(0.0, -1.0, 0.0); }
	}
	vec3 h = f + d * tbest;
	if (nf.z > 0.5) {
		st = h.xy;
	} else {
		depth = pt_y.x - h.z;
		st = vec2(abs(nf.x) > 0.5 ? h.y : h.x, depth);
		if (pt_weir > 0.5 && nf.y < -0.5 && depth < PT_WEIR_DROP) {
			out_open = true;
		}
	}
	return vec4(h, tbest);
}
