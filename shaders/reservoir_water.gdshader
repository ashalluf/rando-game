shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// The reservoir's water (LandmarkReservoir, Reservoir): a still mountain lake whose look is what
// it mirrors - the ridge all round it, the dam, the sky - over a dark, deep, green-black body that
// shoals to silt at the shore. The mirror is traced, not left to SSR: the ridge round the lake is
// a table of (distance, height over the water, is-it-the-dam) per azimuth from the lake's middle
// (Reservoir.ridge_profile()), and a reflected ray from each fragment is walked out to that ridge
// with its own parallax, so a hill across a cove sits where it should in the water from anywhere on
// the shore. It is EMITTED by Fresnel (the web build has no SSR; on Forward+ it runs at
// `mirror_forward`, with SSR and the sky radiance on top). After dark the sky in it carries the
// basin's sodium glow over the dam (the city is south), and the crest's lanterns stand in it as
// streaks. Mesh vertices are in true world space (the landmark's node sits at -world_offset);
// COLOR.r is the water's depth / 40 m. Works in LINEAR on both renderers.

global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform float night_factor;
global uniform float lamp_factor;
global uniform float wind_factor;
global uniform float ground_detail;
global uniform float rain_intensity;

#include "res://shaders/color_space.gdshaderinc"

const int N_RIDGE = 48;
uniform float level = 265.0;
uniform vec2 lake_centre = vec2(0.0);
uniform float ridge_dist[N_RIDGE];
uniform float ridge_height[N_RIDGE];
uniform float ridge_dam[N_RIDGE];
// The body, linear: deep water, and the silty margin.
uniform vec3 deep_color = vec3(0.004, 0.012, 0.012);
uniform vec3 shallow_color = vec3(0.035, 0.042, 0.028);
// The mirrored ridge: grass and brush in the sun, in shade, and the dam's concrete.
uniform vec3 hill_sun = vec3(0.16, 0.13, 0.07);
uniform vec3 hill_shade = vec3(0.035, 0.04, 0.026);
uniform vec3 dam_color = vec3(0.30, 0.29, 0.27);
// The city's glow on the sky over the basin at night (linear, emitted) and which way it lies.
uniform vec3 city_glow = vec3(0.16, 0.075, 0.03);
uniform vec2 city_dir = vec2(0.0, 1.0);
// The crest's lanterns: the dam's arc (centre, radius, end angles) and their height and colour.
uniform vec2 dam_centre = vec2(0.0);
uniform float dam_radius = 160.0;
uniform vec2 dam_span = vec2(-0.8, 0.8);
uniform float lamp_y = 273.0;
uniform float lamp_spacing = 11.2;
uniform vec3 lamp_color = vec3(1.0, 0.6, 0.26);
uniform float ruffle = 0.5;
uniform float ruffle_scale = 3.6;
uniform float mirror_gain = 1.0;
uniform float mirror_forward = 0.55;

varying vec3 v_local;
varying vec3 v_cam;
varying float v_depth;


float wh(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float wn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(wh(i), wh(i + vec2(1.0, 0.0)), f.x), mix(wh(i + vec2(0.0, 1.0)), wh(i + vec2(1.0, 1.0)), f.x), f.y);
}


// The gradient (x, z) of a few travelling wavelets.
vec2 wavelets(vec2 p, float t, float sc) {
	vec2 acc = vec2(0.0);
	vec2 dirs[4] = vec2[](vec2(0.94, 0.34), vec2(-0.41, 0.91), vec2(0.72, -0.69), vec2(-0.99, -0.12));
	float lens[4] = float[](1.0, 0.61, 0.37, 0.23);
	for (int i = 0; i < 4; i++) {
		float k = 6.2831853 / (sc * lens[i]);
		float w = sqrt(9.81 * k) * 0.55;
		acc += lens[i] * k * cos(dot(dirs[i], p) * k - w * t) * dirs[i];
	}
	return acc * 0.25;
}


// Raindrop rings on a jittered 0.6 m grid, the gradient they add.
vec2 rain_rings(vec2 p, float t) {
	vec2 g = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 q = p / 0.6 + vec2(float(k) * 0.37, float(k) * 0.71);
		vec2 c = floor(q);
		float ph = fract(t * 1.3 + wh(c + 3.1 * float(k)));
		vec2 o = c + 0.5 + (vec2(wh(c), wh(c + 7.0)) - 0.5) * 0.6;
		vec2 d = q - o;
		float r = length(d);
		float wave = sin((r - ph * 0.6) * 40.0) * (1.0 - ph) * smoothstep(0.6 * ph + 0.05, 0.6 * ph - 0.05, r) * smoothstep(0.0, 0.05, r);
		g += (r > 0.001 ? d / r : vec2(0.0)) * wave;
	}
	return g * 0.25;
}


// The ridge table sampled at azimuth `az` (0 north, toward +x): distance, height, dam.
vec3 ridge_at(float az) {
	float f = fract(az / 6.2831853) * float(N_RIDGE);
	int i0 = int(floor(f)) % N_RIDGE;
	int i1 = (i0 + 1) % N_RIDGE;
	float t = fract(f);
	return vec3(mix(ridge_dist[i0], ridge_dist[i1], t), mix(ridge_height[i0], ridge_height[i1], t),
		mix(ridge_dam[i0], ridge_dam[i1], t));
}


void vertex() {
	v_local = VERTEX;
	v_depth = COLOR.r * 40.0;
	v_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}


void fragment() {
	vec2 p = v_local.xz;
	float t = TIME;
	float day = 1.0 - night_factor;
	// Mountain air: glassy in the mornings and at night, the afternoon breeze in patches.
	float patch = wn(p * 0.025 + vec2(t * 0.01, -t * 0.007));
	float wind = clamp(0.15 + wind_factor * 0.8, 0.1, 2.0) * smoothstep(0.35, 0.85, patch);
	vec2 grad = wavelets(p, t, ruffle_scale) * ruffle * wind * 0.06;
	if (ground_detail > 0.5) {
		grad += wavelets(p * 2.9 + vec2(13.1, 7.7), t * 1.4, ruffle_scale) * ruffle * wind * 0.015;
		// Cat's paws: little gusts darkening the water in passing.
		grad += (vec2(wn(p * 0.9 + t * 0.6), wn(p * 0.9 - t * 0.5 + 9.0)) - 0.5) * 0.04 * smoothstep(0.72, 0.9, wn(p * 0.05 + vec2(-t * 0.03, t * 0.02)));
	}
	grad += rain_rings(p, t) * rain_intensity;
	// Calmer in the shallows and still in the last metre.
	grad *= smoothstep(0.0, 1.5, v_depth);
	vec3 n = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n, 0.0)).xyz);

	vec3 d = normalize(v_local - v_cam);
	vec3 r = reflect(d, n);
	r.y = max(r.y, 0.0005);
	float rl = max(length(r.xz), 1e-4);
	vec2 rn = r.xz / rl;
	float el = r.y / rl;
	// Walk the reflected ray out to the ridge: a circle of the table's distance round the lake's
	// middle, then once more with the azimuth of the point it hit.
	vec2 rc = p - lake_centre;
	float az = atan(rn.x, -rn.y);
	vec3 rg = ridge_at(az);
	float b = dot(rc, rn);
	float hit = -b + sqrt(max(b * b - (dot(rc, rc) - rg.x * rg.x), 0.0));
	vec2 hp = rc + rn * hit;
	rg = ridge_at(atan(hp.x, -hp.y));
	hit = -b + sqrt(max(b * b - (dot(rc, rc) - rg.x * rg.x), 0.0));
	hit = max(hit, 4.0);
	float ridge_el = (rg.y - (v_local.y - level)) / hit;
	vec3 sky_h = cs_srgb_to_linear(sky_tint.rgb);
	// The sky: the horizon colour, deeper overhead, dark at night but for the city's glow over
	// the basin, which hangs low in the south.
	// (sky_tint already carries the hour: it is the drawn sky's horizon colour.)
	vec3 sky = mix(sky_h, sky_h * vec3(0.55, 0.7, 1.05), smoothstep(0.0, 0.8, el));
	float toward_city = smoothstep(-0.2, 0.8, dot(rn, city_dir));
	sky += city_glow * lamp_factor * toward_city * (1.0 - smoothstep(0.0, 0.35, el));
	vec3 mir = sky;
	if (el < ridge_el) {
		// The hills: the face toward the lake, lit by the sun from where it stands, hazier with
		// distance and toward the crest line.
		vec2 out_dir = normalize(hp + rn * 1e-3);
		vec3 face_n = normalize(vec3(-out_dir.x, 0.9, -out_dir.y));
		float lit = clamp(dot(face_n, sun_direction), 0.0, 1.0) * smoothstep(-0.05, 0.15, sun_direction.y);
		vec3 hill = mix(hill_shade, hill_sun, lit) * mix(0.05, 1.0, day) + sky_h * 0.12;
		// Brush in dark bands down the slope, from the same azimuth.
		hill *= mix(0.7, 1.15, wn(vec2(atan(hp.x, -hp.y) * 30.0, el * 40.0)));
		hill = mix(hill, dam_color * mix(0.08, 1.0, day) * (0.55 + 0.45 * lit), step(0.5, rg.z) * smoothstep(ridge_el - 0.02, ridge_el - 0.002, el + 0.02));
		float haze = clamp(hit / 3000.0, 0.0, 0.8) + 0.25 * smoothstep(ridge_el * 0.6, ridge_el, el);
		mir = mix(hill, sky, clamp(haze, 0.0, 0.85));
	}
	// The crest's lanterns, mirrored: the reflected ray against the dam's arc, near lamp height.
	if (lamp_factor > 0.02) {
		vec2 q = rc + lake_centre - dam_centre;
		float qb = dot(q, rn);
		float disc = qb * qb - (dot(q, q) - dam_radius * dam_radius);
		if (disc > 0.0) {
			float th = -qb - sqrt(disc);
			if (th < 0.0) {
				th = -qb + sqrt(disc);
			}
			vec2 at = q + rn * th;
			float a = atan(at.x, -at.y);
			if (th > 0.0 && a > dam_span.x && a < dam_span.y) {
				float y = v_local.y + el * th;
				float s = a * dam_radius / lamp_spacing;
				float near_lamp = 1.0 - smoothstep(0.03, 0.12, abs(fract(s) - 0.5) - 0.38);
				// Long streaks: the ruffle smears each lamp down the water toward the viewer.
				float spread = 0.3 + 18.0 * length(grad);
				float glow = exp(-abs(y - lamp_y) / spread) * near_lamp;
				mir += lamp_color * glow * 3.0 * smoothstep(0.05, 0.6, lamp_factor);
			}
		}
	}
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - nv, 5.0);
	float shoal = smoothstep(2.5, 0.0, v_depth);
	vec3 body = mix(deep_color, shallow_color, shoal) * mix(0.25, 1.0, day);
	// A thin lap of foam and wet sheen at the waterline.
	float lap = smoothstep(0.25, 0.0, v_depth) * (0.5 + 0.5 * sin(t * 1.3 + wn(p * 0.5) * 6.0));
	body = mix(body, vec3(0.3, 0.3, 0.27) * mix(0.15, 1.0, day), lap * 0.35);
	ALBEDO = cs_out(body);
	ROUGHNESS = mix(0.03, 0.09, clamp(wind + rain_intensity * 0.5, 0.0, 1.0));
	SPECULAR = 0.5;
	METALLIC = 0.0;
	float gain = mirror_gain;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	gain *= mirror_forward;
#endif
	EMISSION = cs_out(mir * mix(0.2, 0.95, fres) * gain * (1.0 - lap * 0.5));
}
