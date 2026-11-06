shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

// The underside of the water's surface, seen from below (Swim): a plane at the surface over the
// camera, drawn only while the camera is under it (the sea, the marina and the lake draw their
// surfaces one-sided, from above). Straight up through it is Snell's window - the whole sky
// squeezed into a bright disc of 48.6 degrees half-angle round the vertical, rippling - and past
// it the surface is a mirror of the dark water below (total internal reflection). Distance veils
// it in the water's colour, as the underwater pass veils everything else.
//
// In a hill home's pool (pt_on 1, PoolUnder): the plane is cut to the pool, the mirror is the
// tank itself (its tiles, caustics and shadows traced along the reflected ray, pool_tank.gdshaderinc)
// and the window shows the sky by elevation, the sun's glare and the house beside the pool (up to
// two boxes in the pool's frame), all bent by the ripples.

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/pool_tank.gdshaderinc"

uniform vec3 deep_color = vec3(0.004, 0.035, 0.045);
uniform vec3 fog_color = vec3(0.012, 0.09, 0.10);
uniform float window_gain = 1.6;
uniform float fog_per_m = 0.0;
uniform vec2 world_offset = vec2(0.0);
// PoolUnder's pool (0: the old surface, the sea and the lakes).
uniform float pt_on = 0.0;
// The water's own colour for the mirrored leg, and metres to half way into it.
uniform vec3 pt_water = vec3(0.02, 0.16, 0.19);
uniform float pt_visibility = 26.0;
// The house: two boxes in the pool's frame (u, v, true world y), min and max; glass share in .w of
// the min (0 a plain wall, 1 a wall of glass).
uniform vec4 pt_box0_min = vec4(0.0);
uniform vec4 pt_box0_max = vec4(0.0);
uniform vec4 pt_box1_min = vec4(0.0);
uniform vec4 pt_box1_max = vec4(0.0);
uniform vec3 pt_wall = vec3(0.70, 0.68, 0.64);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Slab test of a frame ray against a box: the entry distance (or -1), the face normal.
float box_hit(vec3 o, vec3 d, vec3 bmin, vec3 bmax, out vec3 n) {
	vec3 inv = 1.0 / (d + vec3(1.0e-6));
	vec3 t0 = (bmin - o) * inv;
	vec3 t1 = (bmax - o) * inv;
	vec3 tn = min(t0, t1);
	vec3 tf = max(t0, t1);
	float a = max(max(tn.x, tn.y), tn.z);
	float b = min(min(tf.x, tf.y), tf.z);
	n = vec3(0.0);
	if (b < max(a, 0.0)) {
		return -1.0;
	}
	if (a == tn.x) { n = vec3(-sign(d.x), 0.0, 0.0); }
	else if (a == tn.y) { n = vec3(0.0, -sign(d.y), 0.0); }
	else { n = vec3(0.0, 0.0, -sign(d.z)); }
	return a;
}

// The air above the pool along frame direction `d` from frame point `f`: sky, sun, the house.
vec3 air_view(vec3 f, vec3 d, float fw) {
	vec3 sky = cs_srgb_to_linear(sky_tint.rgb) * (1.0 - 0.85 * night_factor);
	float el = clamp(d.z, 0.0, 1.0);
	vec3 c = sky * mix(1.25, 0.75, smoothstep(0.0, 0.7, el));
	vec3 s = pt_dir(normalize(sun_direction));
	float sd = max(dot(normalize(d), s), 0.0);
	c += tree_sun * (pow(sd, 900.0) * 6.0 + pow(sd, 24.0) * 0.12);
	float tb = 1.0e6;
	vec3 nb = vec3(0.0);
	float glass = 0.0;
	float top = 0.0;
	for (int k = 0; k < 2; k++) {
		vec4 bmn = k == 0 ? pt_box0_min : pt_box1_min;
		vec4 bmx = k == 0 ? pt_box0_max : pt_box1_max;
		if (bmx.z <= bmn.z) {
			continue;
		}
		vec3 n;
		float t = box_hit(f, d, bmn.xyz, bmx.xyz, n);
		if (t > 0.0 && t < tb) {
			tb = t;
			nb = n;
			glass = bmn.w;
			top = bmx.z;
		}
	}
	if (tb < 1.0e5) {
		vec3 h = f + d * tb;
		float lit = max(dot(nb, s), 0.0);
		vec3 wall = pt_wall * (tree_sun * lit + sky * 0.55);
		// A glass wall: dark panes mirroring the sky between mullions every 2.3 m, a lit room
		// behind them at night.
		float along = abs(nb.x) > 0.5 ? h.y : h.x;
		float mul = smoothstep(0.0, 0.05, min(fract(along / 2.3), 1.0 - fract(along / 2.3)) * 2.3);
		vec3 pane = sky * 0.32 + vec3(1.0, 0.72, 0.42) * 1.2 * lamp_factor;
		vec3 g = mix(pt_wall * 0.25 * (sky + tree_sun * lit * 0.3), pane, mul);
		float head = step(h.z, top - 0.45);
		c = mix(wall, g, glass * head);
	}
	return c;
}

void fragment() {
	vec3 wdir = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float fw = length(fwidth(wpos));
	if (pt_on > 0.5) {
		vec3 f = pt_frame(wpos + origin_shift);
		// The surface ends at the pool's walls (the far end on an infinity pool: the weir).
		if (f.x < pt_rect.x - 0.01 || f.x > pt_rect.z + 0.01 || f.y < pt_rect.y - 0.01 || f.y > pt_rect.w + 0.01) {
			discard;
		}
		float t = TIME;
		vec2 q = f.xy;
		// Ripples: the same crossing waves the sheet draws from above (hill_pool.gdshader), a
		// little steeper seen from under.
		vec2 g = vec2(0.0);
		g += vec2(0.8, 0.3) * cos(dot(q, vec2(2.1, 0.7)) * 3.0 + t * 1.3);
		g += vec2(-0.4, 0.9) * cos(dot(q, vec2(-0.9, 1.9)) * 3.4 + t * 1.1);
		g += vec2(0.5, -0.6) * cos(dot(q, vec2(1.3, -1.6)) * 5.1 + t * 1.9) * 0.5;
		g += vec2(0.3, 0.2) * (vnoise(q * 3.1 + vec2(t * 0.7, -t * 0.4)) - 0.5) * 2.0;
		float slope = 0.07 * (1.0 - smoothstep(0.02, 0.12, fw));
		vec3 n = normalize(vec3(-g.x * slope, -g.y * slope, 1.0)); // frame: up
		vec3 d = pt_dir(wdir);
		vec3 tr = refract(d, -n, PT_IOR);
		vec3 c;
		if (dot(tr, tr) > 0.0) {
			// Snell's window: what is above, the transmitted share by Fresnel.
			float ci = abs(dot(d, n));
			float r0 = 0.02;
			float fr = r0 + (1.0 - r0) * pow(1.0 - ci, 5.0);
			float edge = smoothstep(0.0, 0.25, tr.z);
			fr = mix(1.0, fr, edge);
			vec3 air = air_view(f, tr, fw);
			vec3 nf;
			vec2 st;
			float dep;
			bool open;
			vec3 rd = reflect(d, -n);
			vec4 hit = pt_trace(f, rd, nf, st, dep, open);
			vec3 m = pt_shade(hit.xyz, nf, st, dep, fw, t);
			m = mix(m, pt_water * (1.0 - 0.85 * night_factor), 1.0 - exp(-hit.w / pt_visibility * 0.6931));
			c = mix(air, m, fr);
		} else {
			// Past the window the surface is a mirror of the tank below it.
			vec3 rd = reflect(d, -n);
			vec3 nf;
			vec2 st;
			float dep;
			bool open;
			vec4 hit = pt_trace(f, rd, nf, st, dep, open);
			if (open) {
				c = air_view(hit.xyz, vec3(rd.xy, abs(rd.z)), fw) * 0.8;
			} else {
				c = pt_shade(hit.xyz, nf, st, dep, fw, t);
			}
			c = mix(c, pt_water * (1.0 - 0.85 * night_factor), 1.0 - exp(-hit.w / pt_visibility * 0.6931));
			// The ripples' crests catch the light coming down: a moving net on the mirror.
			float net = pow(clamp(1.0 - length(g) * 0.55, 0.0, 1.0), 6.0);
			c += tree_sun * 0.02 * net * (1.0 - smoothstep(0.02, 0.12, fw));
		}
		ALBEDO = cs_out(c);
	} else {
		vec2 p = wpos.xz + world_offset;
		float t = TIME;
		// Ripples tilt the window's edge and break the light into a moving net.
		float r = vnoise(p * 0.9 + vec2(t * 0.5, t * 0.3)) + 0.5 * vnoise(p * 2.3 - vec2(t * 0.8, -t * 0.6));
		float up = wdir.y + (r - 0.75) * 0.06;
		float window = smoothstep(0.62, 0.70, up);
		float day = 1.0 - 0.85 * night_factor;
		vec3 sky = cs_srgb_to_linear(sky_tint.rgb) * window_gain * day;
		float net = pow(clamp(1.0 - abs(r - 0.75) * 3.0, 0.0, 1.0), 4.0);
		vec3 c = mix(deep_color * day, sky * (0.85 + 0.35 * net), window);
		float fog = 1.0 - exp(-length(VERTEX) * fog_per_m);
		c = mix(c, fog_color * day, fog * (1.0 - 0.5 * window));
		ALBEDO = cs_out(c);
	}
}
