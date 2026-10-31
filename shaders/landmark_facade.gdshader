shader_type spatial;
render_mode cull_back;

// Walls of the hand-modelled civic landmarks (city hall's stone, the station's stucco, the
// convention hall's white panels, the arena's banded metal drum, the theatre's cladding).
// Unlike building.gdshader it assumes nothing about boxes: everything is laid out in the mesh's
// UV, which LandmarkGeo writes in METRES - u along the wall, v the world height - so it works on
// a leaning elliptical drum as well as on a box, and the geometry and the pattern agree.
//
// Layers, each off unless asked for: a photographed wall texture turned into pure detail around
// `tint` (divided by its own measured mean, like building.gdshader), panel joints, horizontal
// bands (the arena drum's reveals), punched windows with a recess and glass that mirrors the
// sky, lit windows after dark, grime at the foot of the wall, and FLOODLIGHTING: the wall washed
// from fittings at its foot after dark, in scallops, which is what a civic building at night is.
//
// Shader files use // comments, never #.

#include "res://shaders/landmark_common.gdshaderinc"

uniform sampler2D wall_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
// Metres per texture tile.
uniform float tex_scale = 4.0;
// The texture's own linear mean (Building.WALL_TEXTURE_MEAN), so the sample becomes detail.
uniform vec3 wall_texture_mean = vec3(0.30);
// How much of the texture's contrast to keep (1 all of it).
uniform float texture_contrast = 1.0;
uniform vec3 tint : source_color = vec3(0.80, 0.78, 0.74);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float normal_depth = 0.6;

// Panel joints in metres (0 = none): x across the wall, y up it.
uniform vec2 joint_spacing = vec2(0.0, 0.0);
uniform float joint_width = 0.025;
uniform float joint_dark = 0.45;

// Horizontal bands: every band_spacing metres a band_reveal-metre dark reveal, and every panel
// between a slightly different tone, which is how a banded metal drum reads from the street.
uniform float band_spacing = 0.0;
uniform float band_reveal = 0.10;
uniform float band_tone = 0.06;

// Punched windows. win_pitch: metres across (u) and storey height (v); 0 = no windows.
// win_size: the opening as a fraction of the pitch. Only between world heights win_band.
uniform vec2 win_pitch = vec2(0.0, 0.0);
uniform vec2 win_size = vec2(0.45, 0.55);
uniform vec2 win_band = vec2(-10000.0, 10000.0);
// Where a storey starts inside the pitch (0..1), so the window sits high in its storey.
uniform float win_sill = 0.25;
// Metres of reveal shadow round the glass.
uniform float win_reveal = 0.18;
uniform vec3 glass_color : source_color = vec3(0.07, 0.08, 0.09);
uniform float lit_ratio = 0.35;
uniform vec3 lit_color : source_color = vec3(1.0, 0.80, 0.52);
uniform float lit_strength = 1.4;
uniform float reflect_energy = 1.3;
uniform vec3 sky_zenith : source_color = vec3(0.30, 0.46, 0.76);
uniform vec3 sky_horizon : source_color = vec3(0.46, 0.50, 0.56);
uniform vec3 street_reflect : source_color = vec3(0.10, 0.10, 0.11);
uniform float seed = 0.0;

// Grime rising from the foot of the wall (world y base_y), 0 clean.
uniform float grime = 0.25;
uniform float base_y = 0.0;

// Floodlighting after dark (lamp_factor): fittings at world y flood_base_y wash the wall up to
// flood_reach metres with a floor of flood_floor everywhere, in scallops flood_spacing metres
// apart; and a second wash down from flood_top_y (a lit crown).
uniform vec3 flood_color : source_color = vec3(1.0, 0.90, 0.74);
uniform float flood_strength = 0.0;
uniform float flood_base_y = 0.0;
uniform float flood_reach = 25.0;
uniform float flood_floor = 0.2;
uniform float flood_spacing = 6.0;
uniform float flood_top_y = -10000.0;
uniform float flood_top_reach = 12.0;
// A little emission of its own at night on every lit wall, so a floodlit facade does not read
// as a flat card in the Compatibility renderer.
uniform float night_self = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV;
	vec3 base = tint * COLOR.rgb;
	float rough = roughness;
	float metal = metallic;
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	if (use_texture) {
		vec2 tuv = uv / tex_scale;
		vec3 t = texture(wall_albedo, tuv).rgb / max(wall_texture_mean, vec3(0.02));
		t = mix(vec3(1.0), t, texture_contrast);
		base *= clamp(t, vec3(0.0), vec3(2.2));
		nmap = texture(wall_normal, tuv).rgb;
		rough = clamp(texture(wall_roughness, tuv).r * roughness * 1.25, 0.05, 1.0);
	}
	bool wall = abs(wnrm.y) < 0.5;
	// Joints.
	if (joint_spacing.x > 0.0 || joint_spacing.y > 0.0) {
		float jx = joint_spacing.x > 0.0 ? abs(fract(uv.x / joint_spacing.x + 0.5) - 0.5) * joint_spacing.x : 1e3;
		float jy = joint_spacing.y > 0.0 ? abs(fract(uv.y / joint_spacing.y + 0.5) - 0.5) * joint_spacing.y : 1e3;
		float j = min(jx, jy);
		float aa = max(fwidth(uv.x), fwidth(uv.y)) * 0.7;
		float line = 1.0 - smoothstep(joint_width * 0.5, joint_width * 0.5 + aa, j);
		// Fade the joints out once they are finer than a pixel, or a wall shimmers.
		line *= 1.0 - smoothstep(joint_width * 0.6, joint_width * 2.5, aa);
		base *= 1.0 - joint_dark * line;
		// Per-panel tone, the way no two real panels are exactly the same.
		vec2 pid = floor(vec2(joint_spacing.x > 0.0 ? uv.x / joint_spacing.x : 0.0, joint_spacing.y > 0.0 ? uv.y / joint_spacing.y : 0.0));
		base *= 0.965 + 0.07 * lm_hash21(pid + seed);
	}
	// Bands.
	if (band_spacing > 0.0 && wall) {
		float b = fract(uv.y / band_spacing);
		float d = min(b, 1.0 - b) * band_spacing;
		float aa = fwidth(uv.y) * 0.8;
		float reveal = 1.0 - smoothstep(band_reveal * 0.5, band_reveal * 0.5 + aa, d);
		base *= 1.0 - 0.55 * reveal;
		base *= 1.0 + band_tone * (lm_hash21(vec2(floor(uv.y / band_spacing), seed)) - 0.5) * 2.0;
		rough = mix(rough, 0.6, reveal);
	}
	// Grime.
	float gh = wpos.y - base_y;
	base *= 1.0 - grime * 0.35 * (1.0 - smoothstep(0.0, 3.5, gh));

	vec3 emission = vec3(0.0);
	float window = 0.0;
	if (wall && win_pitch.x > 0.0 && wpos.y > win_band.x && wpos.y < win_band.y) {
		vec2 cell = vec2(uv.x / win_pitch.x, (wpos.y - win_band.x) / win_pitch.y);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		vec2 centre = vec2(0.5, win_sill + win_size.y * 0.5);
		vec2 d = abs(f - centre) * win_pitch;
		vec2 half_w = win_size * win_pitch * 0.5;
		vec2 edge = half_w - d;
		if (edge.x > 0.0 && edge.y > 0.0) {
			window = 1.0;
			vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
			vec3 N = normalize(wnrm);
			vec3 refl = reflect(-V, N);
			float fres = pow(1.0 - clamp(dot(V, N), 0.0, 1.0), 4.0);
			vec3 sky = lm_reflection(refl, sky_zenith, sky_horizon, street_reflect, 1.0);
			float mirror = mix(0.22, 0.85, fres) * (1.0 - 0.85 * night_factor);
			// The reveal: head and jambs shade the glass, most at the top.
			float rv = smoothstep(0.0, win_reveal, min(edge.x, edge.y * 0.8));
			vec3 g = glass_color * mix(0.45, 1.0, rv);
			base = mix(g, sky, mirror * 0.3);
			emission += sky * mirror * 0.7 * reflect_energy * lm_sky_now() * mix(0.6, 1.0, rv);
			rough = 0.12;
			metal = 0.0;
			float h = lm_hash21(id + vec2(seed * 1.7, seed));
			if (h < lit_ratio) {
				float glow = 0.55 + 0.45 * lm_hash21(id * 1.3 + seed);
				// A lit room is brightest up at its ceiling.
				float up = clamp((f.y - win_sill) / max(win_size.y, 0.01), 0.0, 1.0);
				emission += lit_color * lit_strength * glow * night_factor * mix(0.6, 1.1, up) * rv;
				base *= 1.0 - 0.6 * night_factor;
			}
			nmap = vec3(0.5, 0.5, 1.0);
		}
	}
	// Floodlight.
	if (flood_strength > 0.0 && window < 0.5) {
		float up = max(wpos.y - flood_base_y, 0.0);
		float wash = flood_floor + (1.0 - flood_floor) * exp(-up / max(flood_reach, 0.1));
		if (wpos.y < flood_top_y) {
			wash += exp(-(flood_top_y - wpos.y) / max(flood_top_reach, 0.1)) * 0.9;
		}
		// Scallops: each fitting throws a cone, brightest straight up from it.
		float sc = 0.72 + 0.28 * cos(uv.x / max(flood_spacing, 0.5) * 6.2831853);
		float grazing = wall ? 1.0 : 0.55;
		emission += base * flood_color * flood_strength * lamp_factor * wash * mix(1.0, sc, smoothstep(0.0, 8.0, up)) * grazing;
	}
	emission += base * night_self * lamp_factor;
	ALBEDO = base;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = normal_depth;
	EMISSION = emission;
}
