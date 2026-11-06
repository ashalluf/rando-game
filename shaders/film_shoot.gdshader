shader_type spatial;
render_mode cull_disabled;

// The film shoot on location (scripts/world/film_shoot_kit.gd, film_shoot_build.gd): trailers,
// the generator, the trucks' tails and carts, the catering tent, the dolly and track, the crane,
// HMIs, the balloon light, C-stands with flags and bounces, video village, barricades, cones,
// the notices and the lettering. One material, so each piece is one MultiMesh draw a chunk.
//
// * Vertex colour alpha x 20 says what a face is (FilmShootKit.C_*): 0 the vertex colour, 2 metal,
//   3 gloss paint, 4 duvetyne (black flag cloth), 5 canvas, 6 rubber, 7 glass (a trailer's rooms
//   lit warm after dark), 8 wood, 9 an HMI's lens, 10 the balloon, 11 a monitor's screen, 12 a
//   small lamp, 13 a paper notice, 14 a bounce board, 15 a sandbag, 16 chrome / diamond plate,
//   17 barricade stripes (orange and white, retroreflective), 18 a trailer's aluminium skin.
// * UV2 is (roughness, metallic). UV is metres off the face's dominant axis.
// * Colour space: vertex colours arrive raw on both renderers and are authored sRGB; everything
//   is worked in linear and handed over with cs_out() (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

// The HMIs and the balloon by day (the shoot is lit) and at night.
uniform float hmi_day = 2.5;
uniform float hmi_night = 16.0;
uniform float balloon_day = 0.9;
uniform float balloon_night = 5.5;
// A trailer's lit windows and the small lamps after dark.
uniform float window_night = 1.4;
uniform float lamp_day = 0.4;
uniform float lamp_night = 5.0;
// Road grime from the asphalt (metres) and how dark it gets.
uniform float grime_height = 0.35;
uniform float grime = 0.25;

varying vec3 v_local;
varying float v_code;
varying vec3 v_wn;

float fs_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fs_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fs_hash(i), fs_hash(i + vec2(1.0, 0.0)), f.x),
		mix(fs_hash(i + vec2(0.0, 1.0)), fs_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fs_noise3(vec3 p) {
	return fs_noise(p.xz + p.y * 1.7) * 0.6 + fs_noise(p.yx * 1.9 + p.z) * 0.4;
}

void vertex() {
	v_local = VERTEX;
	v_code = COLOR.a * 20.0;
	v_wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	int code = int(round(v_code));
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float rough = UV2.x;
	float metal = UV2.y;
	vec3 emit = vec3(0.0);
	float lamp = clamp(lamp_factor, 0.0, 1.0);
	float px = length(fwidth(v_local));
	if (code == 2) {
		float g = mix(fs_noise(vec2(v_local.y * 80.0, (v_local.x + v_local.z) * 4.0)), 0.5, smoothstep(0.004, 0.02, px));
		rough = clamp(rough + (g - 0.5) * 0.2, 0.15, 0.9);
		base *= 0.92 + 0.1 * g;
	} else if (code == 3) {
		// Gloss paint: a little orange peel, scuffs low down.
		float n = fs_noise3(v_local * 3.0);
		base *= 0.95 + 0.08 * n;
		rough = clamp(rough + 0.15 * smoothstep(0.6, 0.9, fs_noise3(v_local * 9.0)), 0.1, 0.9);
	} else if (code == 4) {
		// Duvetyne: dead black, the faint nap.
		float n = mix(fs_noise(UV * 180.0), 0.5, smoothstep(0.002, 0.01, px));
		base = vec3(0.012 + 0.006 * n);
		rough = 0.98;
		metal = 0.0;
	} else if (code == 5) {
		float weave = mix(fs_noise(UV * 260.0), 0.5, smoothstep(0.002, 0.01, px));
		float dirt = fs_noise3(v_local * 2.1);
		base *= (0.94 + 0.08 * weave) * (1.0 - 0.1 * dirt);
		rough = 0.85;
	} else if (code == 6) {
		base *= 0.85 + 0.2 * fs_noise3(v_local * 25.0);
		rough = 0.88;
		metal = 0.0;
	} else if (code == 7) {
		// Tinted glass; after dark the room behind glows (half the trailers have somebody in).
		float on = step(0.45, fs_hash(floor(v_local.xz * 0.9) + floor(v_local.y)));
		emit = vec3(1.0, 0.78, 0.5) * window_night * lamp * on;
		rough = 0.06;
	} else if (code == 8) {
		vec2 g = UV * vec2(3.0, 40.0);
		float grain = mix(fs_noise(g) * 0.6 + fs_noise(g * 3.1) * 0.4, 0.5, smoothstep(0.004, 0.02, px));
		base *= 0.78 + 0.38 * grain;
		rough = 0.82;
	} else if (code == 9) {
		// The HMI's fresnel lens: daylight-balanced, ringed, blown out.
		float rings = 0.85 + 0.15 * sin(length(v_local.xy - vec2(0.0, 3.4)) * 90.0);
		emit = vec3(0.92, 0.96, 1.0) * mix(hmi_day, hmi_night, lamp) * rings;
		base = vec3(0.9);
		rough = 0.1;
		metal = 0.0;
	} else if (code == 10) {
		// The balloon: a glowing diffusion envelope, a seam pattern, brighter toward its middle.
		float seam = smoothstep(0.92, 1.0, abs(sin(atan(v_local.z, v_local.x) * 6.0)));
		emit = vec3(1.0, 0.97, 0.9) * mix(balloon_day, balloon_night, lamp) * (1.0 - 0.25 * seam);
		base = vec3(0.92);
		rough = 0.95;
		metal = 0.0;
	} else if (code == 11) {
		// A monitor: the take playing (soft blocks of colour), a slow flicker.
		float n = fs_noise(UV * vec2(18.0, 12.0) + vec2(floor(TIME * 0.5), 0.0));
		emit = mix(vec3(0.12, 0.18, 0.26), vec3(0.75, 0.55, 0.4), n) * 0.9;
		base = vec3(0.02);
		rough = 0.08;
	} else if (code == 12) {
		emit = base * mix(lamp_day, lamp_night, lamp);
		rough = 0.2;
		metal = 0.0;
	} else if (code == 13) {
		// Paper: a fibre texture, curling and weathered at the edges.
		float f = mix(fs_noise(UV * 140.0), 0.5, smoothstep(0.003, 0.012, px));
		base *= 0.9 + 0.12 * f;
		rough = 0.92;
		metal = 0.0;
	} else if (code == 14) {
		// A silver bounce: crinkled foil.
		float c = fs_noise(UV * 26.0) * 0.6 + fs_noise(UV * 70.0) * 0.4;
		rough = 0.25 + 0.35 * c;
		metal = 0.85;
		base *= 0.85 + 0.2 * c;
	} else if (code == 15) {
		float n = mix(fs_noise(UV * 220.0), 0.5, smoothstep(0.002, 0.01, px));
		base *= 0.85 + 0.25 * n * fs_noise3(v_local * 6.0);
		rough = 0.95;
		metal = 0.0;
	} else if (code == 16) {
		// Chrome and diamond plate.
		float d = abs(fract((UV.x + UV.y) * 18.0) - 0.5) * abs(fract((UV.x - UV.y) * 18.0) - 0.5);
		d = mix(d, 0.1, smoothstep(0.004, 0.015, px));
		rough = clamp(rough + d * 1.2, 0.1, 0.8);
	} else if (code == 17) {
		// Barricade boards: orange and white diagonal stripes, retroreflective sheeting.
		float s = step(0.5, fract((UV.x - UV.y) * 2.6));
		s = mix(s, 0.5, smoothstep(0.03, 0.12, px));
		base = mix(cs_srgb_to_linear(vec3(1.0, 0.38, 0.04)), vec3(0.85), s);
		emit = base * 0.35 * lamp;
		rough = 0.5;
		metal = 0.0;
	} else if (code == 18) {
		// A trailer's aluminium skin: vertical seams every 0.6 m with rivet rows, chalky white,
		// streaks down from the roof.
		float u = (abs(v_wn.x) > abs(v_wn.z)) ? v_local.z : v_local.x;
		float seam = smoothstep(0.012, 0.0, abs(fract(u / 0.61) - 0.5) - 0.488);
		seam = mix(seam, 0.0, smoothstep(0.004, 0.02, px));
		float streak = fs_noise(vec2(u * 6.0, v_local.y * 0.4)) * smoothstep(1.6, 3.9, v_local.y);
		base *= 1.0 - 0.18 * seam - 0.08 * streak;
		rough = clamp(rough + 0.15 * streak, 0.2, 0.7);
	}
	// Grime from the road on what stands on it.
	if (code != 9 && code != 10 && code != 11 && code != 12 && code != 13 && code != 4) {
		float gh = clamp(1.0 - v_local.y / grime_height, 0.0, 1.0);
		float n = fs_noise(v_local.xz * 4.0 + v_local.y * 3.0);
		base *= 1.0 - grime * gh * (0.5 + 0.5 * n);
	}
	ALBEDO = cs_out(base);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
	if (code == 5 || code == 13) {
		BACKLIGHT = cs_out(base * 0.4);
	}
}
