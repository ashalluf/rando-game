shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Ocean: Gerstner waves in the vertex shader (three swells plus one long tsunami-scale wave),
// foam on the crests, fresnel toward the horizon. Runs on the web renderer too (no depth or
// screen textures). wave_scale is a shader global the Weather node drives (1 calm, 6 storm);
// tsunami_scale is a second global for the big one (0 off, 1 a 30 m wall).
global uniform float wave_scale;
global uniform float tsunami_scale;
// Published by DayNight: the colour the sky meets the horizon with, and the direction back
// toward the sun. Water is mostly the sky seen in it, and without this the sea was a flat
// blue-green field whatever the hour.
global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform float night_factor;
uniform vec3 deep_color : source_color = vec3(0.015, 0.085, 0.155);
uniform vec3 shallow_color : source_color = vec3(0.05, 0.26, 0.32);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 0.98);
uniform float base_height = 1.2;
uniform float tsunami_height = 30.0;
uniform float tsunami_length = 420.0;
uniform vec2 tsunami_dir = vec2(1.0, 0.15);
uniform float speed = 1.0;

varying float crest;
varying vec3 world_pos;


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


// The whole wave sum at one point: the offset to add, and the height it contributed.
vec3 wave_sum(vec2 p, float t, float amp, out float h) {
	h = 0.0;
	vec3 d = vec3(0.0);
	d += gerstner(p, normalize(vec2(1.0, 0.3)), 38.0, amp * 0.55, 0.35, t, h);
	d += gerstner(p, normalize(vec2(0.7, -0.6)), 23.0, amp * 0.3, 0.3, t, h);
	d += gerstner(p, normalize(vec2(-0.2, 1.0)), 11.0, amp * 0.15, 0.25, t, h);
	if (tsunami_scale > 0.001) {
		d += gerstner(p, normalize(tsunami_dir), tsunami_length, tsunami_height * tsunami_scale, 0.6, t * 0.9, h);
	}
	return d;
}


void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz;
	float t = TIME * speed;
	float amp = base_height * max(wave_scale, 0.05);
	float h = 0.0;
	vec3 d = wave_sum(p, t, amp, h);
	VERTEX += d;

	// The normal, from the displaced surface itself. Without this the sea moved but was lit as
	// a flat sheet, so all you saw was a painted pattern sliding about on a pale plane - which
	// is exactly what it looked like.
	float e = 1.6;
	float hx = 0.0;
	float hz = 0.0;
	vec3 dx = wave_sum(p + vec2(e, 0.0), t, amp, hx);
	vec3 dz = wave_sum(p + vec2(0.0, e), t, amp, hz);
	vec3 p0 = vec3(p.x, 0.0, p.y) + d;
	vec3 px = vec3(p.x + e, 0.0, p.y) + dx;
	vec3 pz = vec3(p.x, 0.0, p.y + e) + dz;
	NORMAL = normalize(cross(pz - p0, px - p0));

	crest = clamp(h / max(amp + tsunami_height * tsunami_scale * 0.6, 0.2), -1.0, 1.0);
	world_pos = wp + d;
}


void fragment() {
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(deep_color, shallow_color, clamp(0.45 + 0.35 * crest, 0.0, 1.0));
	// Foam only on the real crests, and only when there is a sea running. `crest` is a
	// per-vertex varying on a coarse plane, so a wide threshold turned whole facets white and
	// the sea read as a cartoon.
	float sea = clamp(wave_scale / 3.0, 0.0, 1.0);
	float foam = smoothstep(0.80, 0.98, crest) * sea * 0.85;
	// Ripple detail: two moving noise-ish sines so calm water is not flat-shaded.
	float rip = sin(world_pos.x * 1.7 + TIME * 1.3) * sin(world_pos.z * 1.3 - TIME * 0.9);
	foam += 0.05 * smoothstep(0.78, 1.0, rip) * sea;
	// Slow shimmer across the surface, in fragment space, so calm water still lives even where
	// the mesh is too coarse to carry a wave.
	float shimmer = sin(world_pos.x * 0.33 + TIME * 0.6) * sin(world_pos.z * 0.26 - TIME * 0.45);
	col *= 0.93 + 0.14 * (0.5 + 0.5 * shimmer);

	// The sky in the water, and the glare path to the sun. Computed here rather than left to
	// reflections, so it reads the same on the web renderer as it does on desktop.
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 view_dir = normalize(world_pos - eye);
	vec3 refl = reflect(view_dir, world_n);
	vec3 sky_ref = mix(sky_tint.rgb * 0.42, sky_tint.rgb * 1.22, smoothstep(-0.10, 0.42, refl.y));
	// Capped well short of a mirror: at a grazing angle with a flat normal the fresnel runs to
	// one, and at 0.93 the whole sea turned into pale sky.
	float mirror = clamp(0.08 + 0.45 * fres, 0.0, 0.52) * (1.0 - 0.72 * night_factor);
	col = mix(col, sky_ref, mirror);
	float glint = pow(max(dot(refl, normalize(sun_direction)), 0.0), 180.0);
	col += vec3(1.0, 0.95, 0.84) * glint * 2.4 * (1.0 - night_factor);

	col = mix(col, foam_color, clamp(foam, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.12, 0.6, clamp(foam, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.7 + 0.3 * fres;
	// Fine chop on top of the real wave normal, at two scales: without it the faces of the big
	// swells that happen to point away from you are a flat sheet of sky colour.
	float nx = 0.10 * sin(world_pos.x * 2.1 + TIME * 1.7) + 0.06 * sin(world_pos.x * 7.3 - world_pos.z * 3.1 + TIME * 2.9);
	float nz = 0.10 * cos(world_pos.z * 1.9 - TIME * 1.2) + 0.06 * cos(world_pos.z * 6.7 + world_pos.x * 2.7 - TIME * 2.3);
	NORMAL_MAP = vec3(0.5 + nx, 0.5 + nz, 1.0);
	NORMAL_MAP_DEPTH = 0.85;
}
