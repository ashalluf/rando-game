shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// The ballpark's ground (BallparkBuild): the plaza round the bowl, the ring drive, the terraced
// car parks with their stall rows, cross aisles and planted medians, the planted slope between the
// lot levels, the site's planted edge - and the parked cars, painted into the stalls the same
// integer hash fills with 3D cars up close (Ballpark.stall_car(), bit for bit), so a lot reads as
// full from the hills and the towers. After dark: light pools under every lot pole (the pole grid
// is Ballpark's) and the bowl's spill on the plaza. UV is local (u, v) metres (Ballpark's frame).
// Every number here is a copy of one in Ballpark (LOT_*, PLAZA_*, TERRACE_*): change both.

#include "res://shaders/ballpark_common.gdshaderinc"

uniform float pool_energy = 1.6;
uniform float spill_energy = 0.9;
// Ballpark's copies.
uniform float lot_v0 = -260.0;
uniform float lot_u0 = -290.0;
uniform float module = 18.6;
uniform float stall_d = 5.7;
uniform float stall_w = 2.75;
uniform float block_u = 84.0;
uniform float block_stalls = 77.0;
uniform float plaza_bowl = 108.0;
uniform float plaza_fair = 30.0;
uniform float ring = 16.0;
uniform vec2 terrace_c = vec2(0.0, 15.0);
uniform float terrace_r = 140.0;
uniform float slope_run = 33.0;
uniform float terrace_v0 = -25.0;
uniform float terrace_v1 = 25.0;
uniform float fence_line = 100.6;
uniform float fence_alley = 114.3;
uniform float fence_center = 120.4;

varying float edge;

void vertex() {
	// COLOR.r: metres inside the site's outline (-Ballpark.site_sd), / 16, clamped to 0..1.
	edge = -COLOR.r * 16.0;
}

float fence_r(float deg) {
	float a = clamp(abs(deg), 0.0, 45.0);
	if (a <= 22.5) {
		float t = a / 22.5;
		return mix(fence_center, fence_alley, t * t);
	}
	float t2 = (a - 22.5) / 22.5;
	return mix(fence_alley, fence_line, t2 * (0.6 + 0.4 * t2));
}

float terrace_t(vec2 q) {
	float tr = clamp((length(q - terrace_c) - terrace_r) / slope_run, 0.0, 1.0);
	float tv = clamp((terrace_v1 - q.y) / (terrace_v1 - terrace_v0), 0.0, 1.0);
	return tr * tv;
}

// Ballpark.plaza_r(): the plaza's reach from home at `q`.
float plaza_r(vec2 q) {
	float deg = degrees(atan(q.x, q.y));
	return (abs(deg) <= 45.0 && q.y > 0.0) ? fence_r(deg) + plaza_fair : plaza_bowl;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float line(float d, float w) {
	float fw = max(fwidth(d), 1e-4);
	return clamp((w * 0.5 - abs(d)) / fw + 0.5, 0.0, 1.0);
}

// What the ground is at `q`: 0 lot, 1 plaza, 2 ring drive, 3 planting (Ballpark.ground_kind()).
int ground_kind(vec2 q, float e) {
	if (e > -6.0) {
		return 3;
	}
	float t = terrace_t(q);
	if (t > 0.002 && t < 0.998) {
		return 3;
	}
	float pr = length(q);
	float pz = plaza_r(q);
	if (pr < pz) {
		return 1;
	}
	if (pr < pz + ring) {
		return 2;
	}
	// Kerbs round the slope's top and foot: a strip of planting.
	float tn = terrace_t(q + vec2(3.0, 0.0)) + terrace_t(q - vec2(3.0, 0.0)) + terrace_t(q + vec2(0.0, 3.0)) + terrace_t(q - vec2(0.0, 3.0));
	if ((t < 0.002 && tn > 0.002) || (t > 0.998 && tn < 3.99)) {
		return 3;
	}
	return 0;
}

vec3 car_paint(float h) {
	if (h < 0.22) return vec3(0.82, 0.82, 0.8);
	if (h < 0.40) return vec3(0.02, 0.02, 0.025);
	if (h < 0.55) return vec3(0.18, 0.19, 0.2);
	if (h < 0.70) return vec3(0.42, 0.43, 0.45);
	if (h < 0.78) return vec3(0.25, 0.02, 0.02);
	if (h < 0.86) return vec3(0.02, 0.05, 0.16);
	if (h < 0.92) return vec3(0.1, 0.1, 0.12);
	return vec3(0.35, 0.3, 0.22);
}

void fragment() {
	vec2 q = UV;
	int kind = ground_kind(q, edge);
	float n = vnoise(q * 0.31) * 0.6 + vnoise(q * 2.3) * 0.4;
	vec3 asphalt = vec3(0.075, 0.075, 0.078) * (0.82 + 0.3 * n);
	vec3 col = asphalt;
	float rough = 0.9;
	vec3 emit = vec3(0.0);
	float pr = length(q);
	if (kind == 1) {
		// Plaza: pale pavers in a 1.5 m grid.
		col = vec3(0.42, 0.40, 0.37) * (0.9 + 0.15 * n);
		col *= 1.0 - 0.18 * max(line(fract(q.x / 1.5 + 0.5) - 0.5, 0.03), line(fract(q.y / 1.5 + 0.5) - 0.5, 0.03));
		rough = 0.8;
		emit += col * bp_flood() * spill_energy * smoothstep(plaza_r(q) + 10.0, 60.0, pr);
	} else if (kind == 3) {
		// Ice plant and shrubs, flowering magenta.
		float m = vnoise(q * 0.9);
		col = mix(vec3(0.03, 0.08, 0.025), vec3(0.06, 0.12, 0.03), m);
		float fl = smoothstep(0.78, 0.86, vnoise(q * 3.7 + 9.0));
		col = mix(col, vec3(0.45, 0.04, 0.22), fl * 0.7);
		rough = 0.95;
	} else {
		// Lot: stall rows across u, cross aisles every block, medians every fourth module.
		float mv = (q.y - lot_v0) / module;
		float mi = floor(mv);
		float vin = (mv - mi) * module;
		float ub = (q.x - lot_u0) / block_u;
		float bi = floor(ub);
		float uin = (ub - bi) * block_u;
		bool median = mod(mi, 4.0) == 3.0;
		bool cross = uin >= block_stalls;
		bool stalls = vin < stall_d * 2.0 && !cross && kind == 0;
		if (median && vin < stall_d * 2.0 && !cross) {
			float m = vnoise(q * 0.9);
			col = mix(vec3(0.03, 0.08, 0.025), vec3(0.07, 0.11, 0.035), m);
			rough = 0.95;
			stalls = false;
		}
		if (stalls) {
			int side = vin < stall_d ? 0 : 1;
			float k = floor(uin / stall_w);
			float kin = uin - k * stall_w;
			float vs = side == 0 ? vin : vin - stall_d;
			// Stall lines and the back line.
			float l = max(line(kin, 0.1), line(kin - stall_w, 0.1)) * step(0.4, vs) * step(vs, stall_d - 0.1);
			l = max(l, line(vin - stall_d, 0.1));
			col = mix(col, vec3(0.75, 0.74, 0.7), l * 0.85);
			// A car in it?
			int ki = int(bi) * 28 + int(k);
			int row = int(mi) * 2 + side;
			float fill = clamp(1.05 - (pr - 130.0) / 350.0, 0.3, 0.9);
			if (bp_hash01(ki, row) < fill) {
				vec2 c = vec2(kin - stall_w * 0.5, vs - stall_d * 0.5);
				vec2 e = abs(c) - vec2(0.92, 2.3);
				float body = smoothstep(0.1, -0.05, max(e.x, e.y));
				vec3 p = car_paint(bp_hash01(ki + 7000, row));
				// Glass across the cabin, nose toward the aisle.
				float along = (side == 0 ? -c.y : c.y) / 2.3;
				float glass = smoothstep(-0.55, -0.45, along) * smoothstep(0.45, 0.35, along) * step(abs(c.x), 0.78);
				vec3 cc = mix(p, vec3(0.02, 0.025, 0.03), glass * 0.85);
				col = mix(col, cc, body);
				rough = mix(rough, 0.3, body);
			}
		}
		// Aisle arrows' worth of wear: darker wheel tracks down the aisles.
		if (!stalls && kind != 3) {
			col *= 1.0 - 0.08 * smoothstep(0.5, 0.0, abs(abs(vin - stall_d * 2.0 - 3.6) - 1.4));
		}
		// The pools under the lot poles (Ballpark.pole_at()).
		float pm = floor((q.y - lot_v0 - stall_d) / (module * 2.0) + 0.5);
		vec2 pole = vec2(lot_u0 + (floor((q.x - lot_u0 - block_u * 0.5) / block_u + 0.5) + 0.5) * block_u, lot_v0 + pm * module * 2.0 + stall_d);
		float d = length(q - pole);
		emit += vec3(1.0, 0.88, 0.7) * pool_energy * lamp_factor * exp(-d * d / 160.0) * (0.12 + col.g * 2.0);
	}
	if (kind == 2) {
		// The ring drive: a dashed centre line.
		float pz = plaza_r(q);
		float l = line(pr - pz - ring * 0.5, 0.12) * step(0.5, fract(atan(q.x, q.y) * pz / 6.0));
		col = mix(col, vec3(0.7, 0.62, 0.2), l);
		emit += col * bp_flood() * spill_energy * 0.6;
	}
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	EMISSION = cs_out(emit);
}
