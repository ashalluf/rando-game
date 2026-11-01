shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/heli_downwash.gdshaderinc"
#include "res://shaders/tree_wind.gdshaderinc"
#include "res://shaders/tree_light.gdshaderinc"
#include "res://shaders/camera_fade.gdshaderinc"

// Wind sway and light for the generated foliage (palms). Nothing in this city moved except the
// grass, and a street of palms standing dead still is one of the things that reads as "model"
// rather than "place".
//
// The wind runs at TWO rates, which is the difference between a tree and a texture on a stick:
// the trunk and frond ribs swing slowly through a wide arc (the bend grows with the square of
// height above the instance's own origin, so the foot barely moves and the crown swings), and the
// leaflets hanging off them shiver quickly through a tiny one. On top of both sits a gust
// envelope that travels across the world, so a street breathes instead of every palm holding a
// constant amplitude forever.
//
// The phase comes from the instance's world position, so a row of palms does not sway in step,
// and each frond is phase-shifted by which side of the trunk it leaves from, so the crown never
// slides sideways as one piece.
//
// Colours are vertex colours (PropFactory builds the mesh), so there is nothing here that depends
// on how a renderer decodes a texture: this shader looks the same on Forward+ and on the
// Compatibility renderer the web build uses.

global uniform float wind_factor;
// A steady wind blowing one way (Weather: the Santa Ana), world XZ, length its strength 0..1.
global uniform vec2 wind_lean;
/// Weather's wet-surface amount, 0 dry to 1 soaked. Wet fronds go glossy.
global uniform float road_wetness;
/// Points TOWARDS the sun (published by DayNight). Drives the frond-glow lobe.
global uniform vec3 sun_direction;
/// The sky's horizon colour (DayNight), raw sRGB numbers on both renderers.
global uniform vec4 sky_tint;

// --- Wind ---------------------------------------------------------------------------------
/// Metres of sideways bend per metre-squared of height. 0.0015 puts a 15 m palm's crown through
/// about a third of a metre.
uniform float bend_scale : hint_range(0.0, 0.01) = 0.0015;
/// Trunk and rib sway rate. Slow on purpose - a real palm crown moves at well under 1 Hz.
uniform float speed : hint_range(0.0, 3.0) = 0.6;
/// How far fronds on opposite sides of the trunk lag each other, in radians of phase.
uniform float frond_lag : hint_range(0.0, 4.0) = 1.9;
/// Leaflet flutter as a fraction of the vertex's distance from the trunk axis, and its rate.
/// Small and quick: this is the shiver at the tips, not the swing of the frond.
uniform float flutter : hint_range(0.0, 0.2) = 0.045;
uniform float flutter_speed : hint_range(0.0, 8.0) = 2.6;
/// Rate of the travelling gust envelope, and how deep it cuts.
uniform float gust_speed : hint_range(0.0, 1.0) = 0.17;
uniform float gust_depth : hint_range(0.0, 1.0) = 0.45;

// --- Light ---------------------------------------------------------------------------------
/// How much light a frond passes through. A palm crown with the sun behind it is the single most
/// recognisable light in this city, and it is worth more than any amount of extra polygons.
uniform float translucency : hint_range(0.0, 1.0) = 0.40;
/// Extra transmission when the camera looks straight through the crown at the sun, and how tight
/// that lobe is. Forward scattering: light that carries on in the direction it was going.
uniform float scatter_gain : hint_range(0.0, 4.0) = 1.8;
uniform float scatter_sharpness : hint_range(1.0, 16.0) = 5.0;
/// Frond gloss dry, and the roughness a soaked frond falls to.
uniform float leaf_roughness : hint_range(0.0, 1.0) = 0.74;
uniform float leaf_specular : hint_range(0.0, 1.0) = 0.34;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.22;

// --- Fire (TreeFire's charred copy; 0 on every living palm) ----------------------------------
/// 1 = burnt out: the fronds are burnt back to stubs and black ribs, the trunk charred.
uniform float burnt : hint_range(0.0, 1.0) = 0.0;

// --- Close up (trees-closeup, 2026-10-30; TreesCloseup). 0 = the shader as it was (the A/B) ---
uniform float closeup : hint_range(0.0, 1.0) = 1.0;
/// How much of each frond's own lag survives: a palm sways as ONE tree on its trunk, the fronds
/// only trailing it a little at their tips (a full lag per frond read as fronds flapping).
uniform float frond_follow : hint_range(0.0, 1.0) = 0.3;
/// The crown's lean downwind as a gust front passes (multiples of its sway bend).
uniform float gust_push : hint_range(0.0, 4.0) = 1.6;
/// How dark the fronds at the heart of the crown go, against the tips out in the light.
uniform float inner_shade : hint_range(0.0, 1.0) = 0.42;
/// The trunk's leaf-scar rings and fibre as a bump (no texture: the trunk is vertex colours).
uniform float bark_relief : hint_range(0.0, 3.0) = 1.0;

varying float leaf_out;
varying vec3 rest_pos;

// --- Trees under light (tree-light-2; TreeLight, tree_light.gdshaderinc). 0 = as it was -------
uniform float tree_light : hint_range(0.0, 1.0) = 1.0;
/// A palm's height at scale 1 (metres): sets its sway rate and how late it answers a gust.
uniform float sway_height : hint_range(0.0, 40.0) = 14.0;
/// Metres the fronds step back along the light's axis in a directional shadow pass (the
/// shadow twin's coarse fronds otherwise shade the real ones in front of them).
uniform float self_shadow_slack : hint_range(0.0, 3.0) = 0.45;
/// Sky light through a frond seen from below (fronds are one leaf thick: it is most of what
/// a palm's underside is in the shade).
uniform float sky_through : hint_range(0.0, 2.0) = 0.2;


void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.31 + origin.z * 0.23;
	float w = clamp(max(wind_factor, 0.25), 0.0, 3.0);
	// The travelling gust envelope.
	float old_env = 1.0 - gust_depth + gust_depth * (0.5 + 0.5 * sin(TIME * gust_speed + (origin.x + origin.z) * 0.013));
	float g = tw_gust(origin.xz + origin_shift.xz, TIME, wind_lean);
	float rate = 1.0;
	if (tree_light > 0.5 && sway_height > 0.5) {
		float tall_m = sway_height * length(MODEL_MATRIX[1].xyz);
		rate = tl_rate(tall_m);
		g = tl_load(origin.xz + origin_shift.xz, TIME, wind_lean, tall_m);
	}
	w *= mix(old_env, 0.55 + 0.95 * max(g, 0.0), closeup);

	// Distance from the trunk axis, and a CONTINUOUS direction around it. atan() would be the
	// obvious way to get an azimuth and it would tear the mesh along the -X axis where it wraps;
	// the normalised offset has no seam, and where it is undefined (on the axis) the amplitude it
	// feeds is zero anyway.
	float radial = length(VERTEX.xz);
	vec2 around = VERTEX.xz / max(radial, 1e-4);
	leaf_out = radial;
	rest_pos = VERTEX;

	// 1. Trunk and frond ribs: slow, wide, growing with the square of height, phase-shifted by
	//    which side of the trunk the frond leaves from.
	float t = TIME * speed * rate;
	float lag = frond_lag * mix(1.0, frond_follow * smoothstep(0.4, 3.0, radial), closeup);
	float p = phase + around.x * lag + around.y * lag * 0.7;
	// Two frequencies so the sway wanders instead of ticking like a metronome.
	float gust_x = sin(t + p) * 0.72 + sin(t * 1.73 + p * 2.1) * 0.28;
	float gust_z = sin(t * 0.87 + p * 1.4 + 2.1) * 0.72 + sin(t * 1.51 + p) * 0.28;
	float h = max(VERTEX.y, 0.0);
	float bend = h * h * bend_scale * w;
	VERTEX.x += bend * gust_x;
	VERTEX.z += bend * gust_z;
	// The front bows the whole palm downwind as it passes; the fronds' tips stream further.
	if (closeup > 0.5) {
		float stream = 1.0 + 0.5 * smoothstep(1.0, 4.0, radial);
		VERTEX.xz += tw_dir_model(MODEL_MATRIX, wind_lean) * h * h * bend_scale * gust_push * g * stream * clamp(w, 0.0, 3.0);
	}
	// The steady wind lays the crown over downwind, breathing with the gusts (model space: the
	// instance may be turned and scaled).
	if (dot(wind_lean, wind_lean) > 1e-6) {
		vec3 lean_dir = transpose(mat3(MODEL_MATRIX)) * vec3(wind_lean.x, 0.0, wind_lean.y);
		float lean = h * h * bend_scale * 4.0 * length(wind_lean) * (0.75 + 0.25 * sin(TIME * 0.7 + phase));
		VERTEX.xz += normalize(lean_dir.xz + vec2(1e-6)) * lean;
	}

	// The rotor wash of a helicopter low overhead (heli_downwash.gdshaderinc).
	VERTEX += heli_wash_offset(MODEL_MATRIX, h, radial, around, bend_scale * 10.0, TIME, phase);

	// 2. Leaflets: quick, tiny, keyed to how far out along the frond the vertex sits, so the tips
	//    shiver while the rib carrying them is still halfway through its swing.
	float ft = TIME * flutter_speed;
	ft *= 1.0 + 0.3 * closeup * g;
	VERTEX.y += sin(ft + p + radial * 1.7) * radial * flutter * w * 0.25 * (1.0 + closeup * g);
	VERTEX.xz += around.yx * vec2(1.0, -1.0) * cos(ft * 0.79 + p) * radial * flutter * w * 0.12;
	// Fronds are heavy: out along each one it dips and rises on its own, later than the crown.
	if (tree_light > 0.5) {
		float droop = sin(t * 1.9 + p * 2.7) * 0.6 + sin(t * 3.1 + p * 1.1) * 0.4;
		VERTEX.y += droop * smoothstep(0.8, 4.0, radial) * radial * 0.025 * w * (0.6 + 0.7 * max(g, 0.0));
	}
	// Directional shadow pass (orthographic): step back along the light's axis.
	if (tree_light > 0.5 && PROJECTION_MATRIX[3][3] > 0.5) {
		VERTEX += inverse(mat3(MODEL_MATRIX)) * (-normalize(INV_VIEW_MATRIX[2].xyz) * self_shadow_slack);
	}
}


void fragment() {
	if (cf_gone(VERTEX, FRAGCOORD.xy, PROJECTION_MATRIX)) {
		discard;
	}
	float wet = clamp(road_wetness, 0.0, 1.0);
	vec3 albedo = COLOR.rgb * mix(1.0, 0.86, wet);
	if (burnt > 0.0) {
		// Burnt back from the tips: a leaflet out past the crown's first metre goes in 25 cm
		// cells, the further out the likelier, leaving black ribs and stubs round the head.
		vec3 cell = floor(rest_pos * 4.0);
		float n = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float out_of = clamp((leaf_out - 0.7) / 3.5, 0.0, 1.0);
		if (leaf_out > 0.7 && n < burnt * (0.55 + 0.45 * out_of)) {
			discard;
		}
		// Charcoal, with a little of the old colour left in the ribs: never pure black, which
		// reads as a hole in the picture.
		vec3 coal = vec3(0.028, 0.025, 0.022) * (0.7 + 0.6 * n);
		albedo = mix(albedo, coal, burnt * mix(0.9, 0.97, step(0.7, leaf_out)));
	}
	float occl = 1.0;
	bool frond = COLOR.g > COLOR.r * 0.95;
	bool trunk = !frond && length(rest_pos.xz) < 0.5 && COLOR.r - COLOR.b < 0.2;
	if (closeup > 0.5) {
		if (frond) {
			// The heart of the crown is in the shade of every frond round it.
			occl = 1.0 - inner_shade * (1.0 - smoothstep(0.5, 3.2, leaf_out));
			albedo *= mix(1.0, occl, 0.6);
		} else if (trunk && bark_relief > 0.0) {
			// Leaf-scar rings (the old boots' bases) and vertical fibre, bumped from their own
			// height field by screen derivatives: the mesh has no tangents.
			float ring = fract(rest_pos.y * 4.2 + 0.15 * sin(atan(rest_pos.z, rest_pos.x) * 3.0 + rest_pos.y));
			float hgt = smoothstep(0.0, 0.18, ring) * (1.0 - smoothstep(0.55, 1.0, ring));
			hgt += 0.15 * sin(atan(rest_pos.z, rest_pos.x) * 37.0 + rest_pos.y * 3.0);
			// Gone before the rings are under a pixel or two, or they alias into moire.
			hgt *= 0.012 * bark_relief * (1.0 - smoothstep(0.12, 0.35, fwidth(rest_pos.y * 4.2)));
			vec3 dpx = dFdx(VERTEX);
			vec3 dpy = dFdy(VERTEX);
			vec3 r1 = cross(dpy, NORMAL);
			vec3 r2 = cross(NORMAL, dpx);
			float det = dot(dpx, r1);
			float hx = dFdx(hgt);
			float hy = dFdy(hgt);
			if (abs(det) > 1e-10) {
				NORMAL = normalize(abs(det) * NORMAL - sign(det) * (hx * r1 + hy * r2));
			}
			albedo *= 0.82 + 0.3 * smoothstep(0.0, 0.012 * bark_relief, hgt);
		}
	}
	ALBEDO = albedo;
	AO = mix(1.0, occl, 0.8);
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = mix(leaf_roughness, wet_roughness, wet);
	SPECULAR = mix(leaf_specular, 0.85, wet);

	// Translucency. BACKLIGHT is Godot's transmission term and works on both renderers: the light
	// loop adds it on the side facing away from each light, so a crown only glows when something
	// is actually shining through it and nothing glows at night. Tinted by the frond's own colour,
	// and strongest out at the leaflets, where a frond is one cell thick.
	vec3 through = albedo * translucency * (1.0 - burnt) * clamp(0.3 + leaf_out * 0.35, 0.0, 1.2);
	// Forward scattering on top: a crown between the camera and the sun lights up far harder than
	// one off to the side.
	vec3 to_cam = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float facing = clamp(dot(to_cam, -normalize(sun_direction)), 0.0, 1.0);
	BACKLIGHT = through * (1.0 + scatter_gain * pow(facing, scatter_sharpness)) * mix(1.0, occl, closeup * 0.7);
	// Sky light through a frond seen from below (tree_light.gdshaderinc; renderer space).
	if (tree_light > 0.5 && !IN_SHADOW_PASS) {
		vec3 sky = sky_tint.rgb;
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
		sky = sky * sky * (sky * 0.305306 + 0.682171) + 0.012523 * sky;
#endif
		float below = clamp(-to_cam.y * 1.6 + 0.2, 0.0, 1.0);
		EMISSION = albedo * vec3(1.05, 1.2, 0.55) * sky * sky_through * below * (1.0 - burnt) * mix(1.0, occl, 0.6) * clamp(0.3 + leaf_out * 0.35, 0.0, 1.0) * (frond ? 1.0 : 0.0);
	}
}
