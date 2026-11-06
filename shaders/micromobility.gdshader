shader_type spatial;
render_mode cull_back;

// The street's micromobility (scripts/world/micro_mesh.gd): shared e-scooters, share bikes and
// their docks and solar kiosk, bike racks, delineator posts, and the riders' own bikes. One
// material for all of it, so a chunk's parked fleet of one kind is one MultiMesh draw.
//
// * Vertex colour alpha says what a face is (MicroMesh.A_*, round(a * 20)): 0 the vertex colour,
//   2 metal, 4 rubber (tyres, grips), 6 a head lamp, 8 a tail lamp, 9 a printed QR plate, 10 a
//   screen or status light, 12 solar cells, 14 the station map, 16 a reflector, 17 grip tape,
//   18 / 19 paint (pure white = the bike's own paint: INSTANCE_CUSTOM.rgb on a parked one,
//   `paint_uniform` on a rider's).
// * UV2 is (roughness, metallic) per part. UV is metres on solid parts, 0..1 on printed faces.
// * INSTANCE_CUSTOM.a is the parked one's wear (0 new .. 1 beaten up); a rider's is `wear`.
// * Colour space: vertex colours, instance data and the Vector3 paint uniform arrive raw on both
//   renderers and are authored sRGB; everything is worked in linear and handed over with
//   cs_out() (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

// A rider's bike: its paint (sRGB, set as a Vector3) and whether the lamps are on.
uniform vec3 paint_uniform = vec3(0.5);
uniform bool use_uniform_paint = false;
uniform float lights_on = 0.0;
uniform float wear = 0.2;
// Lamp brightness: a lit head lamp after dark and by day, the tail, screens.
uniform float head_night = 7.0;
uniform float head_day = 1.2;
uniform float tail_night = 4.0;
uniform float tail_day = 0.8;
uniform float screen_glow = 1.6;
uniform float map_night = 1.4;
// Retroreflectors: how bright they flash back toward the camera at night.
uniform float reflect_night = 1.8;

varying vec3 v_local;
varying float v_mode;
varying vec3 v_paint;
varying float v_wear;

float mm_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float mm_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mm_hash(i), mm_hash(i + vec2(1.0, 0.0)), f.x),
		mix(mm_hash(i + vec2(0.0, 1.0)), mm_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_local = VERTEX;
	v_mode = COLOR.a;
	v_paint = use_uniform_paint ? paint_uniform : INSTANCE_CUSTOM.rgb;
	v_wear = use_uniform_paint ? wear : INSTANCE_CUSTOM.a;
}

// The station map: pale paper, the street grid, a park, the Coral Line, the stations, a dot.
vec3 mm_map(vec2 uv) {
	vec3 paper = vec3(0.93, 0.92, 0.88);
	vec2 g = uv * vec2(9.0, 16.0);
	vec2 f = abs(fract(g) - 0.5);
	float street = smoothstep(0.44, 0.47, max(f.x, f.y));
	float avenue = step(0.47, abs(fract(uv.x * 3.0) - 0.5)) + step(0.475, abs(fract(uv.y * 4.0) - 0.5));
	vec3 col = mix(paper, vec3(1.0), street * 0.8);
	col = mix(col, vec3(0.98, 0.86, 0.45), clamp(avenue, 0.0, 1.0) * 0.8);
	float park = step(0.55, uv.x) * step(uv.x, 0.72) * step(0.25, uv.y) * step(uv.y, 0.38);
	col = mix(col, vec3(0.62, 0.8, 0.55), park);
	float line = 1.0 - smoothstep(0.006, 0.012, abs(uv.x - 0.32 - 0.08 * sin(uv.y * 5.0)));
	col = mix(col, vec3(0.93, 0.36, 0.28), line);
	vec2 st_id = floor(uv * vec2(5.0, 7.0));
	float stn = step(0.72, mm_hash(st_id)) * (1.0 - smoothstep(0.012, 0.02, length(fract(uv * vec2(5.0, 7.0)) / vec2(5.0, 7.0) - vec2(0.1, 0.07))));
	col = mix(col, vec3(0.93, 0.36, 0.28), stn);
	float you = 1.0 - smoothstep(0.018, 0.026, length((uv - vec2(0.5, 0.52)) * vec2(1.0, 1.8)));
	col = mix(col, vec3(0.1, 0.35, 0.85), you);
	// A header band in the scheme's dark, the legend at the foot.
	col = mix(col, vec3(0.13, 0.14, 0.15), step(uv.y, 0.08));
	col = mix(col, vec3(0.85, 0.84, 0.8), step(0.9, uv.y));
	return col;
}

void fragment() {
	int code = int(round(v_mode * 20.0));
	vec3 vc = COLOR.rgb;
	float rough = UV2.x;
	float metal = UV2.y;
	vec3 base;
	vec3 emit = vec3(0.0);
	float lamp = clamp(lamp_factor, 0.0, 1.0);
	bool own_paint = (code == 18 || code == 19) && vc.r > 0.995 && vc.g > 0.995 && vc.b > 0.995;
	base = cs_srgb_to_linear(own_paint ? v_paint : vc);
	if (code == 18 || code == 19) {
		// Paint: a faint orange peel, chips and scuffs with wear (the bare alloy under them).
		float n = mm_noise(UV * 37.0 + v_wear * 13.0);
		base *= 0.95 + 0.06 * n;
		float chip = step(0.93 - v_wear * 0.18, mm_noise(UV * 61.0 + 7.0)) * step(0.05, v_wear);
		base = mix(base, vec3(0.42, 0.43, 0.44), chip);
		metal = mix(metal, 0.9, chip);
		rough = clamp(rough + v_wear * 0.18 * mm_noise(UV * 9.0), 0.08, 0.95);
	} else if (code == 2) {
		float g = mm_noise(vec2(UV.x * 3.0, UV.y * 40.0));
		rough = clamp(rough + (g - 0.5) * 0.12, 0.05, 0.95);
	} else if (code == 4) {
		// Rubber: a little tread and dust on it.
		float t = mm_noise(UV * 140.0);
		base *= 0.85 + 0.3 * t;
		base = mix(base, vec3(0.16, 0.15, 0.14), 0.2 * mm_noise(UV * 11.0));
		rough = 0.9;
		metal = 0.0;
	} else if (code == 17) {
		// Grip tape: black grit, sparkling a little.
		float s = mm_hash(floor(UV * 900.0));
		base = vec3(0.012 + 0.02 * s);
		rough = 0.95;
		// Boot marks wear the tape grey where the feet go.
		base = mix(base, vec3(0.06), smoothstep(0.4, 0.9, mm_noise(UV * 14.0)) * 0.5);
	} else if (code == 6) {
		base = vec3(0.85);
		float on = clamp(lights_on, 0.0, 1.0);
		emit = vec3(1.0, 0.97, 0.9) * on * mix(head_day, head_night, lamp);
		rough = 0.1;
	} else if (code == 8) {
		base = vec3(0.45, 0.02, 0.01);
		float on = clamp(lights_on, 0.0, 1.0);
		emit = vec3(1.0, 0.05, 0.02) * on * mix(tail_day, tail_night, lamp);
		rough = 0.15;
	} else if (code == 9) {
		// A QR code on a white plate.
		vec2 q = floor(UV * 17.0);
		float bit = step(0.5, mm_hash(q + 3.1));
		vec2 c = UV * 17.0;
		float finder = 0.0;
		for (int k = 0; k < 3; k++) {
			vec2 o = k == 0 ? vec2(3.5) : (k == 1 ? vec2(13.5, 3.5) : vec2(3.5, 13.5));
			vec2 d = abs(c - o);
			float m = max(d.x, d.y);
			finder = max(finder, step(m, 3.5) * (1.0 - step(2.5, m) * step(m, 2.5 + 0.99)) * (step(m, 1.5) + step(2.5, m)));
		}
		float edge = step(0.5, UV.x * 17.0) * step(UV.x * 17.0, 16.5) * step(0.5, UV.y * 17.0) * step(UV.y * 17.0, 16.5);
		base = mix(vec3(0.92), vec3(0.03), max(bit * edge, finder));
		rough = 0.4;
	} else if (code == 10) {
		emit = base * screen_glow * mix(0.6, 1.4, lamp);
		base *= 0.2;
		rough = 0.08;
	} else if (code == 12) {
		// Solar cells: dark blue squares under glass, silver busbars between.
		vec2 cell = fract(UV * vec2(6.0, 10.0));
		float gap = step(0.94, max(cell.x, cell.y));
		float finger = step(0.97, fract(UV.y * 10.0 * 4.0)) * 0.6;
		base = mix(vec3(0.02, 0.035, 0.08), vec3(0.6, 0.62, 0.65), max(gap, finger));
		rough = 0.12;
		metal = 0.2;
	} else if (code == 14) {
		base = cs_srgb_to_linear(mm_map(UV));
		emit = base * map_night * lamp * lamp;
		rough = 0.18;
	} else if (code == 16) {
		vec3 v = normalize(VIEW);
		float facing = pow(clamp(dot(NORMAL, v), 0.0, 1.0), 3.0);
		emit = base * reflect_night * lamp * facing;
		rough = 0.3;
	}
	// Road dust on everything near the ground, more on the worn ones.
	float dust = (1.0 - smoothstep(0.02, 0.32, v_local.y)) * (0.15 + 0.35 * v_wear) * (code == 6 || code == 8 || code == 10 ? 0.0 : 1.0);
	base = mix(base, vec3(0.2, 0.18, 0.15), dust * mm_noise(UV * 23.0 + 5.0));
	ALBEDO = cs_out(base);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
