shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Ocean: Gerstner swells in the vertex shader (three swells plus one long tsunami-scale wave),
// shoaling and a breaking surf line where the water meets the sand, foam on the crests,
// wind-blown spray in a storm, sub-surface glow through backlit wave faces, and the sky mixed
// in by fresnel. Runs on the web renderer too (no depth texture, no screen texture, no SSR).
//
// wave_scale is a shader global the Weather node drives (1 calm, 6 storm); tsunami_scale is a
// second global for the big one (0 off, 1 a 30 m wall); wind_factor is the same wind the grass
// and the palms bend to, and it drives the chop and the spray; ground_detail is the one Quality
// clears on the web and below MEDIUM, and it gates the second noise fetch.
global uniform float wave_scale;
global uniform float tsunami_scale;
global uniform float wind_factor;
global uniform float ground_detail;
// Published by DayNight: the colour the sky meets the horizon with, and the direction back
// toward the sun. Water is mostly the sky seen in it, and without this the sea was a flat
// blue-green field whatever the hour.
global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform float night_factor;
uniform vec3 deep_color : source_color = vec3(0.008, 0.042, 0.080);
uniform vec3 shallow_color : source_color = vec3(0.035, 0.165, 0.215);
// The shallows over the sand: sunlight reaches the bottom and comes back green.
uniform vec3 shore_color : source_color = vec3(0.13, 0.36, 0.37);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 0.98);
// Light that has travelled through a thin wave face. Water is a filter, not a mirror: this is
// what makes a swell glow when the sun is behind it.
uniform vec3 sss_color : source_color = vec3(0.09, 0.40, 0.33);
uniform float base_height = 1.2;
uniform float tsunami_height = 30.0;
uniform float tsunami_length = 420.0;
uniform vec2 tsunami_dir = vec2(1.0, 0.15);
uniform float speed = 1.0;
// How dark the weather is (0 clear, 1 storm), pushed in by Weather. DayNight publishes the
// *clear* horizon colour as sky_tint whatever the weather, so without this the sea went on
// reflecting a bright blue sky from under a black storm, which is the loudest possible tell
// that water is painted rather than lit.
uniform float weather_dark : hint_range(0.0, 1.0) = 0.0;
// The horizon colour a full storm brings the sky down to (DayNight's own storm_horizon).
uniform vec3 storm_horizon : source_color = vec3(0.30, 0.31, 0.34);
// How much of the far water is handed back to the sky. The sea is thousands of metres across
// here, and without it the same bright colour ran all the way to the horizon.
uniform float horizon_blend : hint_range(0.0, 1.0) = 0.25;

// --- The shoreline -------------------------------------------------------------------------
// The shader has to know where the sand is to break waves on it, so Weather copies MacroMap's
// coast numbers in every time they change (Weather._push_ocean_shape()); the defaults here are
// MacroMap's own, so the surf lands in the right place even if nothing sets them. world_offset
// is the scene's origin shift: local + offset is the true world position, and the coast is
// written in true world coordinates.
uniform vec2 world_offset = vec2(0.0);
uniform float coast_base_x = -900.0;
uniform float coast_wobble = 180.0;
uniform float coast_period = 700.0;
uniform vec2 peninsula_center = vec2(-700.0, 1500.0);
uniform float peninsula_radius = 550.0;
uniform float peninsula_bulge = 520.0;
uniform float bay_z = 1000.0;
uniform float bay_east_x = 400.0;
// Width of the surf zone: how far out a swell starts to feel the bottom and stand up.
uniform float surf_width = 72.0;
// How far up the sand the wash runs, and how fast it goes up and back.
uniform float swash_width = 14.0;
uniform float swash_period = 9.0;
// Wind direction on the water (Weather sets it from its own rain wind).
uniform vec2 wind_dir = vec2(1.0, 0.3);

varying float crest;
varying float shore;
varying vec3 world_pos;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


// Metres of water between a true-world XZ and the nearest land, from the same shapes
// MacroMap.coast_x() / in_bay() use: the bay curve of the main shore, the bulge around the
// peninsula, and the peninsula's own circle. Enclosed water (the harbour and port basins, which
// sit east of the shoreline) gets a fixed offshore distance instead, so no surf line is drawn
// across a dock.
float shore_distance(vec2 p) {
	float away = abs(p.y - peninsula_center.y);
	float bulge = (1.0 - smoothstep(0.0, peninsula_radius * 1.2, away)) * peninsula_bulge;
	float cx = coast_base_x + coast_wobble * sin(p.y / coast_period) - bulge;
	float d = cx - p.x;
	if (p.y > bay_z && p.x < bay_east_x && p.x > cx) {
		// Inside the bay the land is east and north of the water, not the main shoreline.
		d = min(bay_east_x - p.x, p.y - bay_z);
	}
	if (d < 0.0) {
		d = 300.0;
	}
	float pen = distance(p, peninsula_center) - peninsula_radius * 1.02;
	return min(d, max(pen, 0.0));
}


// One Gerstner wave: moves the vertex in place, returns the height it added.
vec3 gerstner(vec2 p, vec2 dir, float length, float amp, float steep, float t, inout float h_sum) {
	float k = 6.28318 / length;
	float c = sqrt(9.8 / k);
	float f = k * (dot(dir, p) - c * t);
	float a = amp;
	float q = steep / (k * a + 0.001);
	h_sum += a * cos(f);
	return vec3(q * a * dir.x * sin(f) * -1.0, a * cos(f), q * a * dir.y * sin(f) * -1.0);
}


// The whole wave sum at one point: the offset to add, and the height it contributed. The wind
// swells are tapered by the shoaling factor; the tsunami is not, because the whole point of it
// is to run up the beach.
vec3 wave_sum(vec2 p, float t, float amp, float tsu, out float h) {
	h = 0.0;
	vec3 d = vec3(0.0);
	d += gerstner(p, normalize(vec2(1.0, 0.3)), 38.0, amp * 0.55, 0.35, t, h);
	d += gerstner(p, normalize(vec2(0.7, -0.6)), 23.0, amp * 0.3, 0.3, t, h);
	d += gerstner(p, normalize(vec2(-0.2, 1.0)), 11.0, amp * 0.15, 0.25, t, h);
	if (tsu > 0.001) {
		d += gerstner(p, normalize(tsunami_dir), tsunami_length, tsunami_height * tsu, 0.6, t * 0.9, h);
	}
	return d;
}


void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz;
	vec2 tp = p + world_offset;
	float t = TIME * speed;
	float sd = shore_distance(tp);
	// Shoaling. A swell feels the bottom, stands up, and dies where it has already broken.
	// Without the taper a storm's seven-metre swell simply cut through the beach and the
	// waterline was a straight seam between blue and sand.
	float reach = smoothstep(swash_width * 0.3, surf_width, sd);
	float shoal = reach * (1.0 + 1.6 * reach * (1.0 - reach));
	float open = base_height * max(wave_scale, 0.05);
	float amp = open * shoal;
	float h = 0.0;
	vec3 d = wave_sum(p, t, amp, tsunami_scale, h);
	VERTEX += d;

	// The normal, from the displaced surface itself. Without this the sea moved but was lit as
	// a flat sheet, so all you saw was a painted pattern sliding about on a pale plane - which
	// is exactly what it looked like.
	float e = 1.6;
	float hx = 0.0;
	float hz = 0.0;
	vec3 dx = wave_sum(p + vec2(e, 0.0), t, amp, tsunami_scale, hx);
	vec3 dz = wave_sum(p + vec2(0.0, e), t, amp, tsunami_scale, hz);
	vec3 p0 = vec3(p.x, 0.0, p.y) + d;
	vec3 px = vec3(p.x + e, 0.0, p.y) + dx;
	vec3 pz = vec3(p.x, 0.0, p.y + e) + dz;
	NORMAL = normalize(cross(pz - p0, px - p0));

	// Measured against the open-water swell, not against the tapered one, so the flattened
	// water in the surf zone reads as flat instead of as a field of tiny crests.
	crest = clamp(h / max(open + tsunami_height * tsunami_scale * 0.6, 0.2), -1.0, 1.0);
	shore = sd;
	world_pos = wp + d;
}


void fragment() {
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 view_dir = normalize(world_pos - eye);
	float dist = length(world_pos - eye);
	// How much sea is running, how much of a storm it is, and how hard the wind blows.
	float sea = clamp(wave_scale / 3.0, 0.0, 1.0);
	float storm = smoothstep(3.2, 5.6, wave_scale);
	float wind = clamp((wind_factor - 1.0) / 4.0, 0.0, 1.0);
	// Far water: the fine detail is dropped (it aliases into tinfoil) and the colour is handed
	// over to the sky.
	float far = smoothstep(340.0, 820.0, dist);

	// Colour by depth. There is no bathymetry under the sea - the floor is one flat box - so
	// the distance to the sand stands in for it, which is what it is a proxy for anyway.
	// The ranges are short on purpose: the streamed sea is only about 800 m wide before the
	// ground follower takes over, so the deep colour has to be reached well inside that or the
	// whole visible sea stays the pale green of the shallows and there is a colour seam at the
	// hand-over. deep_color is the macro map's own BAKE_OCEAN_DEEP, so the seam does not show.
	vec3 water = mix(shore_color, shallow_color, smoothstep(6.0, 70.0, shore));
	water = mix(water, deep_color, smoothstep(70.0, 420.0, shore));
	// The sky the water is actually under, weather and all.
	vec3 sky_now = mix(sky_tint.rgb, storm_horizon, weather_dark);
	// The sea is lit by the sky above it, so it darkens with the weather and the hour exactly
	// as the sky does. Without this a storm sea stayed a bright holiday turquoise under a
	// slate-grey sky, which is the single loudest tell that water is painted on.
	float sky_lum = dot(sky_now, vec3(0.299, 0.587, 0.114));
	water *= mix(0.45, 1.1, clamp(sky_lum, 0.0, 1.0));
	// A trough has more water along the line of sight than a crest, so it is darker.
	vec3 col = water * (0.84 + 0.28 * clamp(0.5 + 0.5 * crest, 0.0, 1.0));

	// Foam only on the real crests, and only when there is a sea running. `crest` is a
	// per-vertex varying on a coarse plane, so a wide threshold turned whole facets white and
	// the sea read as a cartoon; the noise breaks the facet up.
	float fn = vnoise(world_pos.xz * 0.32 + vec2(TIME * 0.11, TIME * -0.08));
	float foam = smoothstep(0.82, 1.0, crest * (0.8 + 0.4 * fn)) * sea * 0.62;
	// Ripple detail: two moving noise-ish sines so calm water is not flat-shaded.
	float rip = sin(world_pos.x * 1.7 + TIME * 1.3) * sin(world_pos.z * 1.3 - TIME * 0.9);
	foam += 0.05 * smoothstep(0.78, 1.0, rip) * sea;
	// Slow shimmer across the surface, in fragment space, so calm water still lives even where
	// the mesh is too coarse to carry a wave.
	float shimmer = sin(world_pos.x * 0.33 + TIME * 0.6) * sin(world_pos.z * 0.26 - TIME * 0.45);
	col *= 0.93 + 0.14 * (0.5 + 0.5 * shimmer);

	// The shore break. Two or three lines of white riding in toward the sand (the phase runs
	// with +shore, so the bands travel toward the beach), plus the wash sliding up and back
	// over the last few metres. This is the whole difference between a sea and a blue plane
	// that stops at a straight line.
	float breaker = pow(max(sin(shore * 0.085 + TIME * 1.05), 0.0), 8.0);
	breaker *= 1.0 - smoothstep(surf_width * 0.2, surf_width * 1.1, shore);
	float edge = swash_width * (0.55 + 0.45 * sin(TIME * 6.28318 / swash_period));
	float wash = 1.0 - smoothstep(edge * 0.35, edge + 8.0, shore);
	float surf = breaker * (0.5 + 0.6 * sea) + wash * (0.7 + 0.3 * sea);
	// Broken up, so the surf is not a drawn stripe.
	surf *= 0.5 + 0.8 * vnoise(world_pos.xz * 0.55 + vec2(0.0, TIME * 0.8));
	foam = max(foam, clamp(surf, 0.0, 1.0));

	// Spray: in a storm the wind tears the tops off the crests and lays foam out downwind in
	// streaks. One extra noise fetch, so it is gated on the same detail global the ground uses.
	if (ground_detail > 0.5 && storm > 0.01) {
		vec2 w = normalize(wind_dir + vec2(0.0001, 0.0));
		vec2 sp = vec2(dot(world_pos.xz, w), dot(world_pos.xz, vec2(-w.y, w.x)));
		float streak = vnoise(vec2(sp.x * 0.03 - TIME * (1.2 + 2.0 * wind), sp.y * 0.24));
		streak = smoothstep(0.5, 0.95, streak) * smoothstep(0.3, 0.8, crest);
		foam = max(foam, streak * storm * 0.35 * (1.0 - far));
	}
	foam *= 1.0 - 0.6 * far;

	// Sub-surface: a wave face with the sun behind it glows green where the water is thin.
	vec3 sun_n = normalize(sun_direction);
	float sss = pow(max(dot(view_dir, sun_n), 0.0), 3.0) * clamp(crest, 0.0, 1.0) * sea;
	col += sss_color * sss * 0.6 * (1.0 - night_factor);

	// The sky in the water, and the glare path to the sun. Computed here rather than left to
	// reflections, so it reads the same on the web renderer as it does on desktop.
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 refl = reflect(view_dir, world_n);
	vec3 sky_ref = mix(sky_now * 0.38, sky_now * 1.05, smoothstep(-0.10, 0.42, refl.y));
	// Capped well short of a mirror: at a grazing angle with a flat normal the fresnel runs to
	// one, and at 0.93 the whole sea turned into pale sky.
	float mirror = clamp(0.07 + 0.42 * fres, 0.0, 0.44) * (1.0 - 0.72 * night_factor);
	col = mix(col, sky_ref, mirror);
	float glint = pow(max(dot(refl, sun_n), 0.0), 180.0);
	col += vec3(1.0, 0.95, 0.84) * glint * 2.4 * (1.0 - night_factor) * (1.0 - weather_dark);

	col = mix(col, foam_color, clamp(foam, 0.0, 1.0));
	// Aerial perspective on the water itself. The streamed sea runs for kilometres and the
	// web build has no aerial fog to do this for it.
	col = mix(col, sky_now * (0.72 + 0.3 * (1.0 - night_factor)), far * horizon_blend);
	ALBEDO = col;
	ROUGHNESS = mix(0.28, 0.65, clamp(foam, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = (0.35 + 0.25 * fres) * (1.0 - 0.45 * weather_dark);
	// Fine chop on top of the real wave normal, at two scales: without it the faces of the big
	// swells that happen to point away from you are a flat sheet of sky colour. It grows with
	// the wind and is dropped in the distance, where it turned the sea into crumpled foil.
	float chop = (0.45 + 0.6 * wind) * (1.0 - far);
	float nx = 0.10 * sin(world_pos.x * 2.1 + TIME * 1.7) + 0.06 * sin(world_pos.x * 7.3 - world_pos.z * 3.1 + TIME * 2.9);
	float nz = 0.10 * cos(world_pos.z * 1.9 - TIME * 1.2) + 0.06 * cos(world_pos.z * 6.7 + world_pos.x * 2.7 - TIME * 2.3);
	NORMAL_MAP = vec3(0.5 + nx * chop, 0.5 + nz * chop, 1.0);
	NORMAL_MAP_DEPTH = 0.85;
}
