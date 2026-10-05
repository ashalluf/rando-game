shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Road wear stamps (RoadWear, scripts/world/road_wear.gd): potholes, cracks, tar snakes, patches,
// ruts, shoving, edge break-up, stains, tyre marks and paint ghosts, from ONE atlas of 25 stamps
// (tools/make_road_wear.py) multiplied into thousands of looks per instance. Each instance is a
// flat unit quad a few millimetres over the road (local x across the road, z along it, the
// instance scale the stamp's real size), ONE MultiMesh a chunk.
//
// Per instance (all integers or small fractions, exact in the half floats Compatibility uses):
//   INSTANCE_CUSTOM.r  stamp A + 32 * (stamp B + 1)        (B 0 = no pair)
//   INSTANCE_CUSTOM.g  flags: 1 / 2 mirror A in u / v, 4 / 8 mirror B, 16 x (0..3) B's quarter
//                      turns, 64 surface stain (fades with age), 128 deep (parallax)
//   INSTANCE_CUSTOM.b  A's wear threshold q * 32 + B's (q 0..31; threshold = q / THR_DIV)
//   INSTANCE_CUSTOM.a  B's zoom q (0..7: B's sample is 1 + q / 8 times smaller in the quad)
//   COLOR.rgb          the road's own tint (as authored, sRGB), COLOR.a the age 0 fresh .. 1 old
// A texel of a stamp draws while its erosion order (data.a) is above the threshold, so the same
// pothole erodes into a smaller, more ragged one and a crack network loses its weaker branches;
// the pair lays a second stamp over the first at its own turn, mirror, zoom and threshold.

uniform sampler2D wear_color : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D wear_nrm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D wear_data : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
// The atlas: GRID x GRID cells, a stamp STAMP_PX of each CELL px (RoadWearTable).
uniform float grid = 5.0;
uniform float span = 0.9765625;
uniform float height_range = 0.12;
// How hard the threshold erodes: threshold = q / thr_div.
uniform float thr_div = 52.0;
// The road tint the stamps were authored against (sRGB): a road's own tint pulls them toward it.
uniform vec3 ref_tint = vec3(0.81, 0.80, 0.82);
uniform float tint_pull = 0.75;
// Fades out between these distances (metres from the camera).
uniform float fade_start = 70.0;
uniform float fade_end = 105.0;
// Potholes with depth: parallax occlusion inside this distance (steps), Forward+ and desktop
// Compatibility alike (`ground_detail` off - the web, the low levels - takes one offset step).
uniform float pom_distance = 28.0;
uniform int pom_steps = 14;
// Water: how dark the bed under it goes, and the sky it mirrors by day (emitted, scaled on
// Forward+ where the renderer's own reflections add to it).
uniform float water_dark = 0.45;
uniform float sky_mirror = 0.55;
uniform float sky_mirror_forward = 0.25;

global uniform float road_wetness;
global uniform float rain_intensity;
global uniform float ground_detail;
global uniform float lamp_factor;
global uniform vec4 sky_tint;

#include "res://shaders/wet_drying.gdshaderinc"
#include "res://shaders/color_space.gdshaderinc"

varying vec3 local_pos;
varying vec3 cam_local;
varying vec3 world_pos;
varying flat vec4 inst;
varying vec4 inst_col;


void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The camera in the instance's own frame: x and z in stamp units (the scale is the stamp's
	// size), y in metres, so a ray through the quad marches straight into the stamp's height.
	cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	inst = INSTANCE_CUSTOM;
	inst_col = COLOR;
}


vec2 cell_uv(float stamp, vec2 p) {
	float col = mod(stamp, grid);
	float row = floor(stamp / grid + 0.001);
	return (vec2(col, row) + vec2((1.0 - span) * 0.5) + clamp(p, 0.0, 1.0) * span) / grid;
}


// The quad's 0..1 point as stamp B samples it: turned, zoomed and mirrored about the middle.
vec2 b_point(vec2 p, float turns, float zoom, vec2 mirror) {
	vec2 q = p - 0.5;
	if (turns > 0.5) { q = vec2(-q.y, q.x); }
	if (turns > 1.5) { q = vec2(-q.y, q.x); }
	if (turns > 2.5) { q = vec2(-q.y, q.x); }
	q *= zoom;
	q = mix(q, -q, mirror);
	return q + 0.5;
}


// A slope read in stamp B's texture frame, back into the quad's frame.
vec2 b_slope(vec2 s, float turns, vec2 mirror) {
	s = mix(s, -s, mirror);
	if (turns > 0.5) { s = vec2(s.y, -s.x); }
	if (turns > 1.5) { s = vec2(s.y, -s.x); }
	if (turns > 2.5) { s = vec2(s.y, -s.x); }
	return s;
}


float inside01(vec2 p) {
	return step(0.0, p.x) * step(p.x, 1.0) * step(0.0, p.y) * step(p.y, 1.0);
}


void fragment() {
	float ra = inst.r;
	float stamp_a = mod(ra, 32.0);
	float stamp_b = floor(ra / 32.0 + 0.001) - 1.0;
	float fl = inst.g;
	vec2 mir_a = vec2(mod(fl, 2.0), mod(floor(fl / 2.0), 2.0));
	vec2 mir_b = vec2(mod(floor(fl / 4.0), 2.0), mod(floor(fl / 8.0), 2.0));
	float turns_b = mod(floor(fl / 16.0), 4.0);
	float surface = mod(floor(fl / 64.0), 2.0);
	float deep = mod(floor(fl / 128.0), 2.0);
	float thr_a = floor(inst.b / 32.0 + 0.001) / thr_div;
	float thr_b = mod(inst.b, 32.0) / thr_div;
	float zoom_b = 1.0 + inst.a / 8.0;
	float age = clamp(inst_col.a, 0.0, 1.0);
	bool has_b = stamp_b >= 0.0;

	vec2 p = local_pos.xz + 0.5;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	// Derivatives once, in uniform control flow; every fetch below reuses them (the parallax
	// moves the point but not the footprint).
	vec2 pa0 = mix(p, 1.0 - p, mir_a);
	vec2 dxa = dFdx(cell_uv(stamp_a, pa0));
	vec2 dya = dFdy(cell_uv(stamp_a, pa0));
	vec2 pb0 = b_point(p, turns_b, zoom_b, mir_b);
	vec2 dxb = dFdx(cell_uv(max(stamp_b, 0.0), pb0));
	vec2 dyb = dFdy(cell_uv(max(stamp_b, 0.0), pb0));

	// Parallax occlusion for the deep stamps (potholes, the broken kerb edge): march the view ray
	// down through the stamp's height field and draw what it reaches.
	if (deep > 0.5 && dist < pom_distance) {
		vec3 d = local_pos - cam_local;
		if (d.y < -1.0e-4) {
			float depth_max = height_range * 0.95;
			vec2 per_m = d.xz / -d.y;
			// Grazing: never slide more than a third of the stamp.
			float slide = length(per_m) * depth_max;
			per_m *= min(1.0, 0.33 / max(slide, 1.0e-4));
			int steps = ground_detail > 0.5 ? pom_steps : 1;
			float fade = 1.0 - smoothstep(pom_distance * 0.6, pom_distance, dist);
			float prev_y = 0.0;
			float prev_h = 0.0;
			vec2 hit = p;
			for (int i = 1; i <= 24; i++) {
				if (i > steps) {
					break;
				}
				float y = -depth_max * float(i) / float(steps);
				vec2 q = p + per_m * -y;
				vec4 da = textureGrad(wear_data, cell_uv(stamp_a, mix(q, 1.0 - q, mir_a)), dxa, dya);
				float h = (da.r - 0.5) * 2.0 * height_range * smoothstep(thr_a, thr_a + 0.2, da.a) * inside01(q);
				if (h >= y) {
					// Between the last step above the surface and this one.
					float t = (prev_h - prev_y) / max((prev_h - prev_y) - (h - y), 1.0e-5);
					hit = p + per_m * -mix(prev_y, y, t);
					break;
				}
				prev_y = y;
				prev_h = h;
				hit = q;
			}
			p = mix(p, hit, fade);
		}
	}

	// Stamp A.
	vec2 pa = mix(p, 1.0 - p, mir_a);
	vec2 uva = cell_uv(stamp_a, pa);
	vec4 ca = textureGrad(wear_color, uva, dxa, dya);
	vec4 na = textureGrad(wear_nrm, uva, dxa, dya);
	vec4 da = textureGrad(wear_data, uva, dxa, dya);
	float in_a = inside01(pa);
	float cov_a = ca.a * smoothstep(thr_a, thr_a + 0.06, da.a) * in_a;
	float keep_a = smoothstep(thr_a, thr_a + 0.2, da.a) * in_a;
	vec2 sa = (na.rg * 2.0 - 1.0) * keep_a;
	sa = mix(sa, -sa, mir_a);
	vec3 alb = ca.rgb;
	float h = (da.r - 0.5) * 2.0 * height_range * keep_a;
	float rough = da.g;
	float water = da.b * keep_a;
	float ao = mix(1.0, na.b, keep_a);
	float cov = cov_a;
	vec2 slope = sa;
	// Stamp B, over A.
	if (has_b) {
		vec2 pb = b_point(p, turns_b, zoom_b, mir_b);
		vec2 uvb = cell_uv(stamp_b, pb);
		vec4 cb = textureGrad(wear_color, uvb, dxb, dyb);
		vec4 nb = textureGrad(wear_nrm, uvb, dxb, dyb);
		vec4 db = textureGrad(wear_data, uvb, dxb, dyb);
		float in_b = inside01(pb);
		float cov_b = cb.a * smoothstep(thr_b, thr_b + 0.06, db.a) * in_b;
		float keep_b = smoothstep(thr_b, thr_b + 0.2, db.a) * in_b;
		float total = cov_b + cov_a * (1.0 - cov_b);
		float wb = cov_b / max(total, 1.0e-4);
		alb = mix(alb, cb.rgb, wb);
		rough = mix(rough, db.g, wb);
		h += (db.r - 0.5) * 2.0 * height_range * keep_b;
		water = max(water, db.b * keep_b);
		ao *= mix(1.0, nb.b, keep_b);
		slope += b_slope((nb.rg * 2.0 - 1.0) * keep_b, turns_b, mir_b);
		cov = total;
	}

	// Toward the road it lies on: a stamp was authored on the average road, this road is lighter
	// or warmer.
	vec3 tint = cs_as_uniform(inst_col.rgb) / max(cs_as_uniform(ref_tint), vec3(1.0e-3));
	alb *= mix(vec3(1.0), tint, tint_pull);
	// Age: fresh black tar and new patches grey toward a dusty version of themselves; a stain
	// fades into the road.
	float lum = dot(alb, vec3(0.3, 0.55, 0.15));
	vec3 dusty = vec3(lum) * vec3(1.32, 1.28, 1.2) + (cs_linear_renderer() ? vec3(0.006) : vec3(0.05));
	alb = mix(alb, dusty, age * 0.55);
	rough = mix(rough, max(rough, 0.9), age * 0.7);
	cov *= 1.0 - surface * age * 0.55;
	alb *= mix(1.0, ao, 0.7);

	// Far away the stamp fades out (the road's own procedural wear carries the distance).
	cov *= 1.0 - smoothstep(fade_start, fade_end, dist);
	if (cov < 0.004) {
		discard;
	}

	// Wet: darker and glossy like the road under it, and water standing in what is low.
	float wet = clamp(road_wetness, 0.0, 1.0);
	vec2 fd = vec2(wet);
	if (wet > 0.01 && ground_detail > 0.5 && road_drying > 0.0) {
		fd = wet_film_damp(wet, wet_hold_noise(world_pos.xz) + water * 0.5);
	}
	// Water a pothole holds: the more the stamp holds (data.b), the less rain it takes; drying,
	// the deepest hold it longest. 1.0 holds it even on a dry day.
	float drying = clamp(road_drying, 0.0, 1.0);
	float pw = mix(wet, sqrt(wet) * smoothstep(0.01, 0.1, wet), drying);
	float standing = smoothstep(1.0 - pw * 0.9, 1.06 - pw * 0.9, water) * step(0.01, wet);
	standing = max(standing, smoothstep(0.96, 0.99, water));
	alb *= mix(1.0, 0.62, fd.y);
	alb *= mix(1.0, water_dark, standing);
	rough = mix(mix(rough, 0.07, fd.x), 0.02, standing);
	slope *= 1.0 - 0.9 * standing;
	// Raindrops ring the water: one layer of cells, as on the road's puddles.
	float rain_now = clamp(rain_intensity, 0.0, 1.0);
	if (rain_now > 0.01 && standing > 0.01 && dist < 25.0) {
		vec2 w = world_pos.xz * 2.6;
		vec2 c = floor(w);
		float hsh = wet_hash(c);
		vec2 centre = 0.5 + (vec2(wet_hash(c + 3.1), wet_hash(c + 7.7)) - 0.5) * 0.5;
		float phase = fract(TIME * 1.3 * (0.8 + 0.4 * hsh) + hsh * 7.0);
		vec2 dd = fract(w) - centre;
		float r = length(dd);
		float x = (r - phase * 0.42) * 38.0;
		float wave = sin(x) * exp(-x * x * 0.08) * (1.0 - phase) * (1.0 - phase);
		slope += dd / max(r, 1.0e-3) * wave * 0.5 * standing * sqrt(rain_now);
	}

	// The stamp's slope, in the instance's frame (x across, y up, z along) and on to view space.
	slope *= min(1.0, 0.95 / max(length(slope), 1.0e-4));
	vec3 n_local = vec3(slope.x, sqrt(max(1.0 - dot(slope, slope), 0.0)), slope.y);
	vec3 tx = normalize(MODEL_MATRIX[0].xyz);
	vec3 ty = normalize(MODEL_MATRIX[1].xyz);
	vec3 tz = normalize(MODEL_MATRIX[2].xyz);
	vec3 n_world = normalize(tx * n_local.x + ty * n_local.y + tz * n_local.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	ALBEDO = alb;
	ALPHA = clamp(max(cov, standing * step(0.5, cov)), 0.0, 1.0);
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = mix(0.5, 0.85, max(fd.x, standing));
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	// The water mirrors the sky (emitted by Fresnel: the web and the low levels have no screen-
	// space reflections, and a pothole is mostly below the frame's reflected view anyway).
	if (standing > 0.01) {
		vec3 to_frag = normalize(world_pos - CAMERA_POSITION_WORLD);
		float fres = 0.02 + 0.98 * pow(1.0 - clamp(-to_frag.y, 0.0, 1.0), 5.0);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		float k = sky_mirror;
#else
		float k = sky_mirror_forward;
#endif
		vec3 sky = cs_srgb_to_linear(sky_tint.rgb) * (1.0 - 0.85 * clamp(lamp_factor, 0.0, 1.0)) + vec3(0.9, 0.55, 0.25) * 0.08 * clamp(lamp_factor, 0.0, 1.0);
		EMISSION = cs_out(sky * fres * standing * k);
	}
}
