shader_type spatial;
render_mode cull_back;

// A bike lane's paint (scripts/world/micromobility.gd), on one piece of the old parking lane:
// the green lane (methyl methacrylate, a grit in it, worn grey where the wheels run), its white
// line, the buffer's diagonal hatching and its outer line, and on some pieces the bike stencil
// and the arrow, drawn for the rider coming up the lane (the bicycle across it, the figure's head
// and the arrow toward the traffic's way, stretched along the lane for the low view).
//
// The quad: UV.x 0..1 across from the kerb, UV.y 0..1 along the lane's traffic; its size in
// metres from the instance's basis. INSTANCE_CUSTOM: r green (1 the whole piece, 0.5 dashes - a
// conflict zone before a crossing -, 0 none), g a stencil on this piece (1), b the buffer hatched.
// Nothing painted is cut out, so the road shows. Colours are linear (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float road_wetness;
global uniform vec3 origin_shift;

// Lane geometry from the kerb (metres): Micromobility.LANE_FROM / LANE_TO / BUFFER_TO.
uniform float lane_from = 0.3;
uniform float lane_to = 1.85;
uniform float buffer_to = 2.48;
uniform float line_width = 0.12;
// The paint (linear).
uniform vec3 green = vec3(0.022, 0.14, 0.045);
uniform vec3 white = vec3(0.72, 0.72, 0.69);
uniform vec3 asphalt = vec3(0.1, 0.1, 0.1);
// How worn: the green down the middle where the wheels run, everything at random.
uniform float wear = 0.16;
uniform float wheel_wear = 0.18;

varying vec3 v_world;
varying vec2 v_size;
varying vec4 v_custom;
varying vec2 v_dir;

float bl_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float bl_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bl_hash(i), bl_hash(i + vec2(1.0, 0.0)), f.x),
		mix(bl_hash(i + vec2(0.0, 1.0)), bl_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float bl_fbm(vec2 p) {
	return 0.55 * bl_noise(p) + 0.3 * bl_noise(p * 2.3 + 7.1) + 0.15 * bl_noise(p * 5.1 + 3.3);
}

// Distance to a segment.
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	v_custom = INSTANCE_CUSTOM;
	v_dir = normalize(MODEL_MATRIX[2].xz);
}

// The stencil: a bicycle and rider (in glyph units: x across the lane, y along it, 1 = about
// 0.62 m across) and the arrow ahead of it. Returns its coverage.
float stencil(vec2 p, float aa) {
	// The bike: two wheels and the frame.
	float d = abs(length(p - vec2(-0.42, 0.0)) - 0.25);
	d = min(d, abs(length(p - vec2(0.42, 0.0)) - 0.25));
	d = min(d, seg(p, vec2(-0.42, 0.0), vec2(0.0, 0.0)));
	d = min(d, seg(p, vec2(0.0, 0.0), vec2(-0.12, 0.38)));
	d = min(d, seg(p, vec2(-0.42, 0.0), vec2(-0.12, 0.38)));
	d = min(d, seg(p, vec2(-0.12, 0.38), vec2(0.28, 0.38)));
	d = min(d, seg(p, vec2(0.0, 0.0), vec2(0.28, 0.38)));
	d = min(d, seg(p, vec2(0.28, 0.38), vec2(0.42, 0.0)));
	d = min(d, seg(p, vec2(0.28, 0.38), vec2(0.24, 0.5)));
	// The rider: leg, torso, arm, head.
	d = min(d, seg(p, vec2(-0.1, 0.46), vec2(0.12, 0.26)));
	d = min(d, seg(p, vec2(0.12, 0.26), vec2(0.02, 0.02)));
	d = min(d, seg(p, vec2(-0.1, 0.46), vec2(0.08, 0.84)));
	d = min(d, seg(p, vec2(0.08, 0.84), vec2(0.26, 0.54)));
	float cover = 1.0 - smoothstep(0.045 - aa, 0.045 + aa, d);
	float head = 1.0 - smoothstep(0.11 - aa, 0.11 + aa, length(p - vec2(0.15, 1.02)));
	return max(cover, head);
}

float arrow(vec2 p, float aa) {
	float shaft = 1.0 - smoothstep(0.06 - aa, 0.06 + aa, seg(p, vec2(0.0, -0.6), vec2(0.0, 0.2)));
	// The head: a triangle pointing along +y.
	vec2 q = vec2(abs(p.x), p.y - 0.2);
	float tri = step(0.0, q.y) * step(q.y, 0.55) * step(q.x, (0.55 - q.y) * 0.62);
	return max(shaft, tri);
}

void fragment() {
	float across = UV.x * v_size.x;
	float along = UV.y * v_size.y;
	vec3 w = v_world + origin_shift;
	// True-world distance along the lane (the dashes and hatching line up piece to piece).
	float run = dot(w.xz, v_dir);
	float px = max(length(fwidth(vec2(across, along))), 1e-4);
	float aa = px * 0.75;
	float paint = 0.0;
	vec3 col = vec3(0.0);
	// The green lane.
	float g = v_custom.r;
	float in_lane = smoothstep(lane_from - aa, lane_from + aa, across) * (1.0 - smoothstep(lane_to - line_width - aa, lane_to - line_width + aa, across));
	if (g > 0.75) {
		paint = in_lane;
		col = green;
	} else if (g > 0.25) {
		// Green dashes through the conflict zone: 2 m on, 1.5 m off.
		float dash = step(fract(run / 3.5), 2.0 / 3.5);
		paint = in_lane * dash;
		col = green;
	}
	// The white lines: the lane's, the buffer's outer one.
	float line1 = smoothstep(lane_to - line_width - aa, lane_to - line_width + aa, across) * (1.0 - smoothstep(lane_to - aa, lane_to + aa, across));
	float line2 = smoothstep(buffer_to - line_width - aa, buffer_to - line_width + aa, across) * (1.0 - smoothstep(buffer_to - aa, buffer_to + aa, across));
	float whites = max(line1, line2);
	// The buffer's hatching: diagonal bars every 3 m.
	if (v_custom.b > 0.5) {
		float bx = (across - lane_to) / (buffer_to - lane_to - line_width);
		float inb = step(0.0, bx) * step(bx, 1.0);
		float diag = fract((run + across * 1.4) / 3.0);
		float bar = smoothstep(0.0, 0.03, diag) * (1.0 - smoothstep(0.1, 0.13, diag));
		whites = max(whites, inb * bar);
	}
	// The stencil and the arrow, in the middle of the green.
	if (v_custom.g > 0.5) {
		float mid = (lane_from + lane_to - line_width) * 0.5;
		float scale = 0.62;
		float stretch = 2.3;
		vec2 p = vec2((across - mid) / scale, (along - v_size.y * 0.5 + 1.15) / (scale * stretch));
		float s = stencil(p, aa / scale);
		vec2 q = vec2((across - mid) / scale, (along - v_size.y * 0.5 - 1.5) / (scale * stretch));
		s = max(s, arrow(q, aa / scale));
		whites = max(whites, s);
	}
	// Wear: the paint thins and breaks up at random, the green most where the wheels run.
	float n = bl_fbm(w.xz * 2.2);
	float grain = bl_noise(w.xz * 31.0);
	float track = exp(-pow((across - 1.05) / 0.22, 2.0)) * wheel_wear;
	float keep_white = smoothstep(wear * 0.9, wear * 0.9 + 0.12, n + grain * 0.15);
	float keep_green = smoothstep(wear + track, wear + track + 0.2, n + grain * 0.2);
	paint *= keep_green;
	whites *= keep_white;
	float cover = max(paint, whites);
	// Worn through is a hole (the road shows); thinning paint goes toward the road's grey first.
	if (cover < 0.5) {
		discard;
	}
	vec3 base = mix(col, white, whites);
	// Grit and tyre grime in the paint, thin paint showing the asphalt's grey.
	base *= 0.86 + 0.2 * grain;
	base = mix(asphalt, base, smoothstep(0.5, 0.85, cover) * 0.6 + 0.4);
	float wet = clamp(road_wetness, 0.0, 1.0);
	ALBEDO = cs_out(base * mix(1.0, 0.85, wet));
	ROUGHNESS = mix(mix(0.62, 0.55, whites), 0.12, wet);
	SPECULAR = 0.5;
}
