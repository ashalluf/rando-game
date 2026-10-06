shader_type spatial;
render_mode cull_back;

// Curtain-wall glass for the curved, leaning and tilted glass of the civic landmarks: the
// arena's sloped glass ring, the convention centre's green-glass pavilions, the theatre lobby,
// the concert hall's glazing. building.gdshader's glass only works on the faces of a box; this
// one reads everything from the mesh's UV, which LandmarkGeo writes in METRES (u along the wall,
// v the world height), so the mullions follow any curve and stay a fixed real size.
//
// What it draws: mullions and transoms (with an optional opaque spandrel every few rows), tinted
// glass that mirrors the sky and a fake skyline by fresnel - mostly EMITTED, like building's
// glass, so the shaded side is not black - a sun glint, and behind it a traced interior: floor
// slabs, a ceiling of light panels and a back wall, in parallax, dim by day and lit after dark.
//
// Shader files use // comments, never #.

#include "res://shaders/landmark_common.gdshaderinc"

uniform vec3 glass_tint : source_color = vec3(0.20, 0.27, 0.30);
uniform vec3 frame_color : source_color = vec3(0.72, 0.74, 0.77);
// Mullion pitch across (u) and transom pitch up (v), metres.
uniform vec2 grid = vec2(1.5, 3.0);
uniform float frame_width = 0.07;
// Every Nth row of panes is an opaque spandrel panel (0 = none), and its colour.
uniform float spandrel_every = 0.0;
uniform vec3 spandrel_color : source_color = vec3(0.30, 0.32, 0.34);
uniform float reflect_energy = 1.35;
// Share of the mirror emitted rather than lit.
uniform float reflect_emit = 0.7;
uniform float reflect_city = 1.0;
uniform vec3 sky_zenith : source_color = vec3(0.30, 0.46, 0.76);
uniform vec3 sky_horizon : source_color = vec3(0.46, 0.50, 0.56);
uniform vec3 street_reflect : source_color = vec3(0.10, 0.10, 0.11);
// How far behind the glass the interior's back wall is, the storey height inside, and where the
// floors start (world y).
uniform float room_depth = 8.0;
uniform float storey = 4.5;
uniform float floor_y = 0.0;
uniform vec3 interior_color : source_color = vec3(1.0, 0.84, 0.62);
// Interior brightness by day (against daylight outside) and after dark.
uniform float interior_day = 0.10;
uniform float interior_night = 1.5;
// Pane-to-pane wobble of the reflection, so a facade is not one sheet of plastic.
uniform float pane_bow = 0.03;
uniform float seed = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 cell = UV / grid;
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	vec2 to_edge = min(f, 1.0 - f) * grid;
	float aa = max(fwidth(UV.x), fwidth(UV.y));
	float fw = frame_width * 0.5;
	float frame = 1.0 - smoothstep(fw, fw + aa, min(to_edge.x, to_edge.y));
	// Thin frames fade into the glass once they are under a pixel instead of shimmering.
	frame *= 1.0 - smoothstep(frame_width * 0.8, frame_width * 3.0, aa);
	bool spandrel = spandrel_every > 0.5 && mod(id.y, spandrel_every) < 0.5;

	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 N = normalize(wnrm);
	vec2 bow = vec2(lm_hash21(id + seed), lm_hash21(id.yx + seed * 3.1)) - 0.5;
	vec3 refl = normalize(reflect(-V, N) + vec3(bow.x, bow.y * 0.6, -bow.x) * pane_bow);
	float fres = pow(1.0 - clamp(dot(V, N), 0.0, 1.0), 4.0);
	float mirror = mix(0.24, 0.92, fres) * (1.0 - 0.8 * night_factor);
	vec3 sky = lm_reflection(refl, sky_zenith, sky_horizon, street_reflect, reflect_city);

	// The interior, traced: the ray goes in through the glass and meets a floor slab, a ceiling
	// or the back wall, whichever comes first.
	vec3 dir = -V;
	float into = max(dot(dir, -N), 0.05);
	float t_back = room_depth / into;
	float ly = mod(wpos.y - floor_y, storey);
	float t = t_back;
	int surface = 0;
	if (dir.y > 0.001) {
		float tc = (storey - 0.35 - ly) / dir.y;
		if (tc < t) { t = tc; surface = 1; }
	} else if (dir.y < -0.001) {
		float tf = -ly / dir.y;
		if (tf < t) { t = tf; surface = 2; }
	}
	vec3 hit = wpos + dir * t;
	float depth = clamp(t * into / room_depth, 0.0, 1.0);
	vec3 room;
	float lamp;
	if (surface == 1) {
		vec2 g = hit.xz / vec2(2.4, 2.4);
		vec2 q = abs(fract(g) - 0.5);
		float panel = (1.0 - smoothstep(0.18, 0.24, q.x)) * (1.0 - smoothstep(0.18, 0.24, q.y));
		room = vec3(0.62, 0.60, 0.57);
		lamp = 0.5 + 2.8 * panel;
	} else if (surface == 2) {
		room = vec3(0.20, 0.18, 0.16);
		lamp = 0.35;
	} else {
		// The back wall: doors, counters and people as darker shapes in a warm field.
		float hy = mod(hit.y - floor_y, storey) / storey;
		float slot = lm_hash21(floor((hit.x + hit.z) / 3.0) + vec2(seed, id.y));
		room = mix(vec3(0.55, 0.50, 0.44), vec3(0.18, 0.17, 0.16), step(0.62, slot) * step(hy, 0.45));
		lamp = 0.45 + 0.55 * hy;
	}
	room *= mix(1.0, 0.45, depth);
	float lit = mix(interior_day, interior_night, lamp_factor);
	vec3 inside = room * interior_color * lamp * lit;

	vec3 albedo = glass_tint * 0.35;
	vec3 emission = sky * mirror * reflect_emit * reflect_energy * lm_sky_now() + inside * (1.0 - mirror * 0.6);
	albedo = mix(albedo, sky, mirror * (1.0 - reflect_emit) * 0.5);
	emission += vec3(1.0, 0.95, 0.85) * lm_glint(refl, 900.0) * 6.0;
	float rough = 0.05;
	float metal = 0.15;
	if (spandrel) {
		albedo = spandrel_color;
		emission = sky * mirror * 0.25 * lm_sky_now();
		rough = 0.35;
		metal = 0.5;
	}
	albedo = mix(albedo, frame_color, frame);
	emission *= 1.0 - frame;
	ALBEDO = albedo;
	ROUGHNESS = mix(rough, 0.35, frame);
	METALLIC = mix(metal, 0.7, frame);
	SPECULAR = 0.5;
	EMISSION = emission;
}
