// The reservoir dam's materials (LandmarkReservoir), shared by reservoir_dam.gdshader and the
// pierced balustrade panels (reservoir_railing.gdshader). One material a mesh: what a face is
// rides in the vertex alpha (`kind` = round(COLOR.a * 16)), its face in COLOR.g (0 the upstream
// face, 1 the downstream face, 0.5 anything else) and a tint in COLOR.r / COLOR.b (1 is plain).
// UV is in METRES: u along the dam's arc (or along a part), v the WORLD height, so the joints, the
// lifts and every stain sit where the dam is. Works in LINEAR on both renderers
// (color_space.gdshaderinc). Shader includes use // comments.

global uniform float lamp_factor;
global uniform float night_factor;
global uniform float road_wetness;

// The lake's level, the crest and the toe (Reservoir), world metres.
uniform float res_level = 265.0;
uniform float res_crest = 269.0;
uniform float res_toe = 207.0;
// Where the arcade's bays are along the arc (u of the first bay's centre, bay width): the
// drains in each bay are where the streaks come from.
uniform float bay_start = 0.0;
uniform float bay_width = 5.6;
// Lamp posts along the crest (u of the first, spacing): the rust under each.
uniform float lamp_start = 0.0;
uniform float lamp_spacing = 11.2;

const int K_FACE = 0;
const int K_ROAD = 1;
const int K_TRIM = 2;
const int K_DARK = 3;
const int K_METAL = 4;
const int K_LAMP = 5;
const int K_ROOF = 6;
const int K_GAUGE = 7;
const int K_TRAIL = 8;
const int K_CHUTE = 9;
const int K_GLASS = 10;
const int K_BRASS = 11;


float rc_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float rc_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(rc_hash(i), rc_hash(i + vec2(1.0, 0.0)), f.x),
		mix(rc_hash(i + vec2(0.0, 1.0)), rc_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}


float rc_fbm(vec2 p) {
	return rc_noise(p) * 0.55 + rc_noise(p * 2.13 + 7.1) * 0.3 + rc_noise(p * 4.7 + 3.3) * 0.15;
}


// A thin line (0..1) every `period` along x, `width` wide, anti-aliased by the pixel footprint.
float rc_lines(float x, float period, float width) {
	float fw = max(fwidth(x), 1e-4);
	float d = abs(fract(x / period + 0.5) - 0.5) * period;
	return (1.0 - smoothstep(width * 0.5, width * 0.5 + fw, d)) * clamp(width / max(fw, width), 0.0, 1.0);
}


// The concrete of a 1920s dam: warm grey, board-formed in lifts, cast in blocks, weathered.
// `face` 1 on the downstream face (the streaks), 0 upstream (the waterline), 0.5 elsewhere.
// Returns the albedo (linear) in .rgb and the roughness in .a.
vec4 rc_concrete(vec2 uv, float face, float trim) {
	float u = uv.x;
	float v = uv.y;
	vec3 base = mix(vec3(0.33, 0.31, 0.28), vec3(0.37, 0.355, 0.33), trim);
	// Pour to pour, block to block: a slow mottle and a tone per block between the joints.
	float block = rc_hash(vec2(floor(u / 15.2), floor(v / 4.57)));
	float tone = mix(0.9, 1.07, rc_fbm(uv * vec2(0.08, 0.12))) * mix(0.95, 1.04, block);
	// Board grain within each lift, the lift joints every 1.52 m and the contraction joints.
	float grain = rc_noise(vec2(u * 0.6, v * 9.0)) * 0.06;
	float lift = rc_lines(v + 0.2, 1.52, 0.03) * (1.0 - trim);
	float joint = rc_lines(u, 15.2, 0.05) * (1.0 - trim);
	vec3 c = base * (tone - grain) * (1.0 - 0.28 * lift - 0.35 * joint);
	float rough = 0.86;
	if (face > 0.75) {
		// Downstream: streaks from the drains in each bay and from the joints, long dark ones
		// and paler lime ones, running down from the arcade; damp and moss low on the face.
		float bay = u / bay_width - bay_start / bay_width;
		float in_bay = abs(fract(bay) - 0.5);
		float col = floor(u / 0.55);
		float rnd = rc_hash(vec2(col, 7.0));
		float drop = res_crest - v;
		float len = mix(8.0, 40.0, rnd) * (1.0 + 1.5 * smoothstep(0.15, 0.0, in_bay));
		float streak = smoothstep(0.62, 0.95, rnd + 0.35 * smoothstep(0.2, 0.0, in_bay))
			* (1.0 - smoothstep(len * 0.5, len, drop)) * smoothstep(5.0, 7.5, drop)
			* (0.6 + 0.4 * rc_noise(vec2(col, v * 0.4)));
		float lime = smoothstep(0.86, 0.97, rc_hash(vec2(col, 19.0))) * (1.0 - smoothstep(4.0, 18.0, drop - 6.0)) * smoothstep(5.5, 7.0, drop);
		c *= 1.0 - 0.42 * streak;
		c = mix(c, vec3(0.52, 0.51, 0.48), lime * 0.5);
		// Rust under the crest's lamp posts.
		float lamp = abs(fract((u - lamp_start) / lamp_spacing + 0.5) - 0.5) * lamp_spacing;
		float rust = smoothstep(0.35, 0.05, lamp) * (1.0 - smoothstep(1.5, 9.0, drop)) * smoothstep(0.3, 1.2, drop);
		c = mix(c, c * vec3(1.15, 0.78, 0.52), rust * 0.7);
		// Seepage near the toe: dark, damp, green.
		float damp = 1.0 - smoothstep(res_toe + 1.0, res_toe + 9.0 + 4.0 * rc_noise(vec2(u * 0.1, 3.0)), v);
		c = mix(c, c * vec3(0.55, 0.62, 0.5), damp * 0.8);
		rough = mix(rough, 0.6, damp * 0.6);
	} else if (face < 0.25) {
		// Upstream: algae under the water, a pale calcified band from the waterline up where the
		// level stood in wet years, a dark line at today's level.
		float h = v - res_level;
		float band = smoothstep(-0.2, 0.0, h) * (1.0 - smoothstep(2.6, 3.4, h + (rc_noise(vec2(u * 0.3, 1.0)) - 0.5)));
		c = mix(c, vec3(0.50, 0.49, 0.46) * tone, band * 0.6);
		c *= 1.0 - 0.45 * smoothstep(0.25, 0.0, abs(h - 0.05));
		c = mix(c, vec3(0.035, 0.05, 0.03), smoothstep(0.0, -0.3, h));
	}
	// Rain darkens it.
	c *= 1.0 - 0.3 * road_wetness;
	rough = mix(rough, 0.45, road_wetness * 0.6);
	return vec4(c, rough);
}
