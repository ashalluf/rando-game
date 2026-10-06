shader_type spatial;
render_mode cull_back;

// Window glass on the replica's houses (ReplicaBuilder). A pane is a quad with UV 0..1 across it
// and a per-window random in COLOR.a (COLOR.rgb is the blind / curtain colour).
//
// What a house window looks like from the street is mostly two things: the sky and the street
// mirrored in it, strongest at a grazing angle, and a dark room behind it with a blind or a
// curtain drawn to some height. So: a Schlick fresnel mirror whose sky part is EMITTED (a
// reflection does not depend on the light falling on the pane - carried in the albedo, a pane in
// shade went black, the same lesson as building.gdshader), a cheap one-plane parallax room, a
// blind at its own height, and at night a share of the rooms lit warm.

global uniform float night_factor;
global uniform vec4 sky_tint;

// Share of windows lit after dark.
uniform float lit_share = 0.42;
uniform vec3 lit_color : source_color = vec3(1.0, 0.80, 0.52);
uniform float lit_energy = 1.1;
// How deep the fake room is behind the pane (metres of parallax), and its dim colour.
uniform float room_depth = 2.6;
uniform vec3 room_color : source_color = vec3(0.10, 0.09, 0.08);
// How much of the mirror is emitted rather than lit.
uniform float reflect_emit = 0.55;
// The street half of the mirror (below the horizon): warm grey.
uniform vec3 street_color : source_color = vec3(0.32, 0.31, 0.29);

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 wtan;


void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wtan = normalize((MODEL_MATRIX * vec4(TANGENT.xyz, 0.0)).xyz);
}


void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 N = normalize(wnrm);
	float ndv = clamp(dot(N, V), 0.0, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	vec3 R = reflect(-V, N);
	// The mirror: sky above the horizon, the street under it.
	vec3 sky = sky_tint.rgb * mix(0.9, 1.25, clamp(R.y, 0.0, 1.0));
	vec3 mirror = mix(street_color, sky, smoothstep(-0.08, 0.12, R.y));
	// The room: step the view ray back by room_depth and read where it lands on the back wall,
	// in the pane's own UV. Floor darker than ceiling, a blind across the top.
	float rnd = COLOR.a;
	vec3 T = normalize(wtan - N * dot(wtan, N));
	vec3 B = cross(N, T);
	vec2 into = vec2(dot(-V, T), dot(-V, B)) / max(ndv, 0.2);
	vec2 back = UV + into * (room_depth / 2.2) * vec2(0.5, -0.5);
	float inside = step(0.0, back.x) * step(back.x, 1.0) * step(0.0, back.y) * step(back.y, 1.0);
	vec3 room = room_color * mix(0.55, 1.3, clamp(1.0 - back.y, 0.0, 1.0)) * mix(0.6, 1.0, inside);
	float blind = 0.15 + 0.6 * fract(rnd * 7.31);
	float under_blind = step(UV.y, blind);
	room = mix(room, COLOR.rgb * 0.45, under_blind);
	float lit = step(rnd, lit_share) * clamp(night_factor, 0.0, 1.0);
	vec3 lit_room = lit_color * mix(0.7, 1.2, fract(rnd * 13.7)) * mix(1.0, 0.8, under_blind);
	ALBEDO = mix(room, vec3(0.0), fres) * (1.0 - lit);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	EMISSION = mirror * fres * reflect_emit * (1.0 - 0.7 * night_factor) + lit_room * lit_energy * lit * (1.0 - fres * 0.6);
}
