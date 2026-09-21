shader_type spatial;
render_mode cull_disabled;

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
/// Weather's wet-surface amount, 0 dry to 1 soaked. Wet fronds go glossy.
global uniform float road_wetness;
/// Points TOWARDS the sun (published by DayNight). Drives the frond-glow lobe.
global uniform vec3 sun_direction;

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

varying float leaf_out;


void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.31 + origin.z * 0.23;
	float w = clamp(max(wind_factor, 0.25), 0.0, 3.0);
	// The travelling gust envelope.
	w *= 1.0 - gust_depth + gust_depth * (0.5 + 0.5 * sin(TIME * gust_speed + (origin.x + origin.z) * 0.013));

	// Distance from the trunk axis, and a CONTINUOUS direction around it. atan() would be the
	// obvious way to get an azimuth and it would tear the mesh along the -X axis where it wraps;
	// the normalised offset has no seam, and where it is undefined (on the axis) the amplitude it
	// feeds is zero anyway.
	float radial = length(VERTEX.xz);
	vec2 around = VERTEX.xz / max(radial, 1e-4);
	leaf_out = radial;

	// 1. Trunk and frond ribs: slow, wide, growing with the square of height, phase-shifted by
	//    which side of the trunk the frond leaves from.
	float t = TIME * speed;
	float p = phase + around.x * frond_lag + around.y * frond_lag * 0.7;
	// Two frequencies so the sway wanders instead of ticking like a metronome.
	float gust_x = sin(t + p) * 0.72 + sin(t * 1.73 + p * 2.1) * 0.28;
	float gust_z = sin(t * 0.87 + p * 1.4 + 2.1) * 0.72 + sin(t * 1.51 + p) * 0.28;
	float h = max(VERTEX.y, 0.0);
	float bend = h * h * bend_scale * w;
	VERTEX.x += bend * gust_x;
	VERTEX.z += bend * gust_z;

	// 2. Leaflets: quick, tiny, keyed to how far out along the frond the vertex sits, so the tips
	//    shiver while the rib carrying them is still halfway through its swing.
	float ft = TIME * flutter_speed;
	VERTEX.y += sin(ft + p + radial * 1.7) * radial * flutter * w * 0.25;
	VERTEX.xz += around.yx * vec2(1.0, -1.0) * cos(ft * 0.79 + p) * radial * flutter * w * 0.12;
}


void fragment() {
	float wet = clamp(road_wetness, 0.0, 1.0);
	vec3 albedo = COLOR.rgb * mix(1.0, 0.86, wet);
	ALBEDO = albedo;
	ROUGHNESS = mix(leaf_roughness, wet_roughness, wet);
	SPECULAR = mix(leaf_specular, 0.85, wet);

	// Translucency. BACKLIGHT is Godot's transmission term and works on both renderers: the light
	// loop adds it on the side facing away from each light, so a crown only glows when something
	// is actually shining through it and nothing glows at night. Tinted by the frond's own colour,
	// and strongest out at the leaflets, where a frond is one cell thick.
	vec3 through = albedo * translucency * clamp(0.3 + leaf_out * 0.35, 0.0, 1.2);
	// Forward scattering on top: a crown between the camera and the sun lights up far harder than
	// one off to the side.
	vec3 to_cam = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float facing = clamp(dot(to_cam, -normalize(sun_direction)), 0.0, 1.0);
	BACKLIGHT = through * (1.0 + scatter_gain * pow(facing, scatter_sharpness));
}
