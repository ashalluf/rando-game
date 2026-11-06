shader_type spatial;
render_mode cull_disabled;

// Windows of the places of worship (Worship / WorshipBuild). UV is metres in the pane's own plane
// (u across, v up), as WorshipBuild lays every pane. `mode`:
//   0 stained glass: lead cames round irregular pieces (a jittered cell net) in jewel tones, a
//     medallion of rings in the middle of a tall light;
//   1 leaded clear glass: diamond quarries, warm where it is lit from inside;
//   2 modern dalle de verre: thick slabs of coloured glass in a concrete grid;
//   3 plain warm glass (a storefront's, blinds half down).
// By day from the street a stained window is dark and mirrors the sky a little - the colour is
// only a hint; after dark (lamp_factor) the hall is lit and the colour glows out. Linear on both
// renderers (color_space.gdshaderinc).
//
// Shader files use // comments, never #.

#include "res://shaders/landmark_common.gdshaderinc"
#include "res://shaders/color_space.gdshaderinc"

uniform int mode = 0;
uniform float cell_size = 0.32;
uniform float lead_width = 0.022;
uniform float glow = 2.2;
uniform float day_glow = 0.10;
uniform float seed = 0.0;
// The palette's bias: 0 the full jewel set, 1 blues, 2 reds and golds, 3 greens and ambers.
uniform int palette = 0;
uniform vec3 warm : source_color = vec3(1.0, 0.78, 0.48);

varying vec3 wpos;
varying vec3 wnrm;

vec3 jewel(float h, int pal) {
	vec3 c;
	float k = fract(h * 7.31);
	if (pal == 1) {
		c = k < 0.55 ? vec3(0.05, 0.16, 0.62) : (k < 0.8 ? vec3(0.12, 0.42, 0.85) : (k < 0.92 ? vec3(0.85, 0.62, 0.12) : vec3(0.62, 0.06, 0.08)));
	} else if (pal == 2) {
		c = k < 0.4 ? vec3(0.66, 0.05, 0.06) : (k < 0.7 ? vec3(0.92, 0.6, 0.08) : (k < 0.88 ? vec3(0.08, 0.2, 0.62) : vec3(0.15, 0.45, 0.12)));
	} else if (pal == 3) {
		c = k < 0.4 ? vec3(0.18, 0.5, 0.16) : (k < 0.75 ? vec3(0.95, 0.66, 0.16) : (k < 0.9 ? vec3(0.85, 0.35, 0.06) : vec3(0.1, 0.3, 0.7)));
	} else {
		c = k < 0.3 ? vec3(0.06, 0.18, 0.66) : (k < 0.52 ? vec3(0.7, 0.06, 0.08) : (k < 0.7 ? vec3(0.95, 0.68, 0.12) : (k < 0.84 ? vec3(0.12, 0.46, 0.16) : (k < 0.93 ? vec3(0.45, 0.12, 0.52) : vec3(0.85, 0.85, 0.75)))));
	}
	return c * (0.75 + 0.5 * fract(h * 13.7));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV;
	float aa = max(fwidth(uv.x), fwidth(uv.y));
	vec3 col = vec3(0.5);
	float lead = 0.0;
	float shade = 1.0;
	if (mode == 0) {
		// A jittered cell net: the nearest and second-nearest seed give the came between pieces.
		vec2 p = uv / cell_size;
		vec2 ip = floor(p);
		float d1 = 9.0;
		float d2 = 9.0;
		vec2 best = vec2(0.0);
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 c = ip + vec2(float(i), float(j));
				vec2 o = c + 0.2 + 0.6 * vec2(lm_hash21(c + seed), lm_hash21(c.yx + seed * 1.3 + 7.0));
				float d = length(p - o);
				if (d < d1) { d2 = d1; d1 = d; best = c; } else if (d < d2) { d2 = d; }
			}
		}
		float edge = (d2 - d1) * cell_size * 0.5;
		lead = 1.0 - smoothstep(lead_width * 0.5, lead_width * 0.5 + aa, edge);
		col = jewel(lm_hash21(best + seed * 3.1), palette);
		// A medallion: rings round the light's centre line, every 1.1 m up.
		float mc = length(vec2(fract(uv.x / 0.9 + 0.5) - 0.5, (fract(uv.y / 1.1) - 0.5) * 0.82));
		float ring = abs(mc - 0.3);
		lead = max(lead, 1.0 - smoothstep(lead_width * 0.6 / 0.9, lead_width * 0.6 / 0.9 + aa, ring));
		if (mc < 0.3) {
			col = mix(col, jewel(lm_hash21(floor(uv / vec2(0.9, 1.1)) + seed + 3.0), palette) * 1.15, 0.6);
		}
		// Painted shading inside each piece (the grisaille), darker toward its edge.
		shade = mix(0.65, 1.0, smoothstep(0.0, 0.08, edge));
	} else if (mode == 1) {
		vec2 q = vec2(uv.x / 0.18 + uv.y / 0.26, uv.x / 0.18 - uv.y / 0.26);
		vec2 f = abs(fract(q) - 0.5);
		float e = (0.5 - max(f.x, f.y)) * 0.15;
		lead = 1.0 - smoothstep(lead_width * 0.35, lead_width * 0.35 + aa, e);
		col = vec3(0.92, 0.9, 0.82) * (0.92 + 0.12 * lm_hash21(floor(q) + seed));
	} else if (mode == 2) {
		vec2 g = vec2(0.42, 0.36);
		vec2 c = floor(uv / g);
		vec2 f = abs(fract(uv / g) - 0.5) * g;
		float e = min(g.x * 0.5 - f.x, g.y * 0.5 - f.y);
		lead = 1.0 - smoothstep(0.035, 0.035 + aa, e);
		col = jewel(lm_hash21(c + seed), palette) * mix(0.7, 1.15, smoothstep(0.0, 0.12, e));
	} else {
		// Plain glass with a blind or curtain down to a height that varies window to window.
		float bl = mix(0.35, 0.8, lm_hash21(vec2(floor(wpos.x * 0.4 + wpos.z * 0.4), seed)));
		float vv = fract(uv.y / 2.6);
		col = vv > bl ? vec3(0.95, 0.85, 0.68) : vec3(0.95, 0.9, 0.82) * 0.8;
	}
	// Under a pixel the lead net becomes its average darkening.
	float fine = smoothstep(lead_width * 0.6, lead_width * 3.0, aa);
	lead = mix(lead, 0.28, fine);
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 N = normalize(wnrm);
	if (dot(N, V) < 0.0) {
		N = -N;
	}
	vec3 refl = reflect(-V, N);
	float fres = pow(1.0 - clamp(dot(V, N), 0.0, 1.0), 4.0);
	vec3 sky = lm_reflection(refl, vec3(0.30, 0.46, 0.76), vec3(0.46, 0.50, 0.56), vec3(0.10, 0.10, 0.11), 0.6);
	float lit = lamp_factor;
	vec3 glass = col * shade;
	vec3 albedo = mix(glass * 0.16, vec3(0.03, 0.028, 0.026), lead);
	float mirror = mix(0.08, 0.5, fres) * (1.0 - lead) * (1.0 - 0.7 * night_factor);
	vec3 emission = sky * mirror * lm_sky_now();
	// Daylight through from the far side (a hint of the colour), and the hall lit at night.
	vec3 through = (mode == 3 || mode == 1) ? warm * mix(vec3(1.0), glass, 0.4) : glass;
	emission += through * (1.0 - lead) * (day_glow * (1.0 - night_factor) + glow * lit);
	ALBEDO = cs_out(albedo);
	ROUGHNESS = mix(0.1, 0.8, lead);
	METALLIC = 0.0;
	EMISSION = cs_out(emission);
}
