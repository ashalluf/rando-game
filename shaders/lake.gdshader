shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// A park lake (MacArthur Park, scripts/world/landmark_macarthur_park.gd): still, murky, spring-fed
// water in a concrete basin. Deliberately NOT the ocean shader: that one draws Gerstner swells
// sized by the weather, a tsunami wall and a hand-over to the far sea along the coastline, none
// of which belongs in a basin two hundred metres across in the middle of the city. What a lake
// like this looks like is almost entirely what it reflects - the palms, the towers, the sky - with
// a dark green-brown body under it, wind ruffle in patches, and rings running out from the
// fountain jet in the middle.
//
// Everything is worked out in the mesh's LOCAL space, which for a chunk child is true world
// space (the chunk node sits at -WorldState.world_offset): the ripples and the fountain rings stay
// put across an origin re-centering instead of jumping.
//
// Runs on the web renderer too: no depth or screen texture, the sky term is emitted from the
// `sky_tint` global because Compatibility has no screen-space reflections to carry it.

global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform float night_factor;
global uniform float wind_factor;
global uniform float ground_detail;

// The body of the water, LINEAR: dark, a little green (algae and a clay bottom).
uniform vec3 deep_color = vec3(0.0105, 0.0200, 0.0150);
// The shallow margin along the basin wall, where the bottom shows through.
uniform vec3 edge_color = vec3(0.030, 0.042, 0.028);
// Where the fountain stands (local x, z) and how far its rings and churned water reach (m).
uniform vec2 fountain_at = vec2(0.0, 0.0);
uniform float fountain_reach = 26.0;
uniform float fountain_foam = 5.5;
// Ruffle: wave height in the normal (dimensionless) and its scale in metres.
uniform float ruffle = 0.55;
uniform float ruffle_scale = 3.2;
// How much of the sky the surface emits at grazing angles (the web build's reflection; on
// Forward+ SSR and the sky radiance do most of it and this is a floor under them).
uniform float sky_emit = 0.22;
uniform float roughness_calm = 0.035;
uniform float roughness_ruffled = 0.12;

varying vec3 v_local;

float lake_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float lake_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(lake_hash(i), lake_hash(i + vec2(1.0, 0.0)), f.x),
		mix(lake_hash(i + vec2(0.0, 1.0)), lake_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Height of a few travelling wavelets and its gradient (x, z) at `p`.
vec3 wavelets(vec2 p, float t) {
	vec3 acc = vec3(0.0);
	vec2 dirs[4] = vec2[](vec2(0.94, 0.34), vec2(-0.41, 0.91), vec2(0.72, -0.69), vec2(-0.99, -0.12));
	float lens[4] = float[](1.0, 0.61, 0.37, 0.23);
	for (int i = 0; i < 4; i++) {
		float k = 6.2831853 / (ruffle_scale * lens[i]);
		float w = sqrt(9.81 * k) * 0.55;
		float ph = dot(dirs[i], p) * k - w * t;
		float a = lens[i];
		acc.x += a * sin(ph);
		acc.yz += a * k * cos(ph) * dirs[i];
	}
	return acc * 0.25;
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 p = v_local.xz;
	float t = TIME;
	// Wind comes and goes over the water in patches: calm glassy stretches between ruffled ones.
	float patch = lake_noise(p * 0.035 + vec2(t * 0.012, -t * 0.008));
	float wind = clamp(0.25 + wind_factor, 0.2, 2.0) * smoothstep(0.25, 0.8, patch);
	vec3 w = wavelets(p, t);
	vec2 grad = w.yz * ruffle * wind * 0.08;
	if (ground_detail > 0.5) {
		// A finer chop, only where the renderer can afford the extra taps.
		vec3 w2 = wavelets(p * 2.7 + vec2(13.1, 7.7), t * 1.4);
		grad += w2.yz * ruffle * wind * 0.02;
	}
	// Rings running out from the fountain, and the churned water at its foot.
	vec2 rel = p - fountain_at;
	float r = length(rel);
	float ring_env = 1.0 - smoothstep(fountain_foam, fountain_reach, r);
	float ring = cos(r * 3.1 - t * 5.5) * ring_env;
	grad += (r > 0.01 ? rel / r : vec2(0.0)) * ring * 0.07;
	float churn = 1.0 - smoothstep(fountain_foam * 0.5, fountain_foam, r);
	churn *= 0.6 + 0.4 * lake_noise(p * 2.3 + vec2(t * 1.7, t * 1.3));
	vec3 n_local = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_local, 0.0)).xyz);

	// Fresnel against the view: nearly all reflection at a grazing angle, the dark body head on.
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - nv, 5.0);
	vec3 body = mix(deep_color, edge_color, 0.25 * lake_noise(p * 0.08));
	vec3 foam = vec3(0.55, 0.58, 0.58);
	ALBEDO = mix(body, foam, churn * 0.7);
	ROUGHNESS = mix(roughness_calm, roughness_ruffled, clamp(wind * 0.6 + churn, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.5;
	// The sky seen in it, dimmed at night (the lamps and the lit towers are what a lake at night
	// shows, and the renderer's own reflections carry those).
	vec3 sky = sky_tint.rgb * (1.0 - 0.85 * night_factor);
	EMISSION = sky * fres * sky_emit * (1.0 - churn * 0.6);
}
