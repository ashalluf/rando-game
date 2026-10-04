shader_type spatial;

// Everything upright YardFill puts on a lot - garden walls, timber fences, pickets, the freeway's
// sound walls, clipped hedges, chain-link, k-rails, dumpsters - as ONE material, so a chunk's
// worth is one mesh, one draw and one shadow caster (YardFill.commit()). Each box says what it is
// in COLOR.a (YardFill.W_*, in 16ths) and carries its paint in COLOR.rgb. UV is metres in the
// face's own frame (x along the face, y up from the box's foot), UV2.x the box's height, so a
// course, a rail or a cap lands where it should whatever the box's length.
//   0 painted stucco   1 timber fence (vertical boards)   2 white pickets (cut out)
//   3 sound wall (split-face block in coursing, creeping fig up its foot)   4 clipped hedge
//   5 concrete (k-rail, kerb, pad)   6 brick   7 chain-link (cut out)   8 painted metal
//   9 galvanised post

uniform sampler2D plaster_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D planks_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 fig_tint : source_color = vec3(0.20, 0.32, 0.13);

global uniform float road_wetness;

varying float kind;
varying vec3 world_n;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

// A mortar line every `spacing` metres: 1 in the joint.
float course(float v, float spacing, float w) {
	float g = abs(fract(v / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(v), 0.0005);
	float fade = 1.0 - smoothstep(0.02, 0.07, fw / spacing * 4.0);
	return (1.0 - smoothstep(w * 0.5, w * 0.5 + fw, g)) * fade;
}

void vertex() {
	kind = floor(COLOR.a * 16.0 + 0.5);
	world_n = NORMAL;
}

void fragment() {
	vec2 uv = UV;
	float h = max(UV2.x, 0.01);
	float v = clamp(uv.y / h, 0.0, 1.0);
	bool top = world_n.y > 0.5;
	vec3 paint = COLOR.rgb;
	vec3 albedo = paint;
	float rough = 0.85;
	float metal = 0.0;
	float wet_k = 0.6;
	// The ground's grime and splash at the foot of anything standing in a yard.
	float foot = top ? 0.0 : 1.0 - smoothstep(0.0, 0.35, uv.y);
	if (kind < 0.5) {
		// Painted stucco, sand-floated, the paint chalking and stained by sprinklers at the foot.
		vec3 s = texture(plaster_tex, uv / 2.4).rgb;
		albedo = paint * (0.55 + 0.6 * s) * (top ? 1.06 : 1.0);
		albedo *= 1.0 - 0.25 * foot;
		rough = 0.9;
	} else if (kind < 1.5) {
		// A timber fence: vertical boards (the planks texture turned upright), each a little off
		// its neighbour, gaps between them, weathered grey toward the top.
		float board = floor(uv.x / 0.14);
		vec3 w = texture(planks_tex, vec2(uv.y / 1.8, uv.x / 0.56 + hash12(vec2(board, 3.0)))).rgb;
		float gap = course(uv.x, 0.14, 0.012);
		albedo = paint * (0.6 + 0.8 * w) * (0.9 + 0.2 * hash12(vec2(board, 7.0))) * (1.0 - 0.6 * gap);
		albedo = mix(albedo, vec3(dot(albedo, vec3(0.33))) * 1.05, 0.35 * v);
		rough = 0.86;
	} else if (kind < 2.5) {
		// White pickets cut out of one panel: 9 cm boards on 15 cm centres with pointed tops, two
		// rails across.
		float f = fract(uv.x / 0.15);
		float board = abs(f - 0.3) < 0.3 ? 1.0 : 0.0;
		float point_h = 1.0 - 0.06 / h;
		if (v > point_h) {
			board *= step(abs(f - 0.3) / 0.3, (1.0 - v) / (1.0 - point_h));
		}
		float rail = (abs(v - 0.22) < 0.04 || abs(v - 0.78) < 0.04) ? 1.0 : 0.0;
		if (!top && max(board, rail) < 0.5) {
			discard;
		}
		albedo = paint * (0.85 + 0.15 * vnoise(uv * vec2(3.0, 9.0)));
		albedo *= 1.0 - 0.2 * foot;
		rough = 0.7;
	} else if (kind < 3.5) {
		// A sound wall: split-face block, 20 x 40 cm in running bond, the cap course smoother;
		// creeping fig climbing up the foot in ragged fans.
		float row = floor(uv.y / 0.203);
		float u = uv.x + (mod(row, 2.0) > 0.5 ? 0.203 : 0.0);
		float blk = hash12(vec2(floor(u / 0.406), row));
		vec3 c = texture(concrete_tex, uv / 1.7).rgb;
		float split = vnoise(uv * vec2(11.0, 17.0)) * 0.6 + vnoise(uv * 37.0) * 0.4;
		albedo = paint * (0.6 + 0.5 * c) * (0.86 + 0.18 * blk) * (0.85 + 0.3 * split);
		float j = max(course(uv.y, 0.203, 0.012), course(u, 0.406, 0.012));
		albedo *= 1.0 - 0.35 * j;
		if (!top) {
			float reach = 0.8 + 2.6 * vnoise(vec2(uv.x * 0.35, 1.7)) + 0.9 * vnoise(vec2(uv.x * 1.3, 4.1));
			float leaves = vnoise(uv * 6.0) * 0.6 + vnoise(uv * 15.0) * 0.4;
			float fig = smoothstep(reach, reach - 0.6, uv.y) * smoothstep(0.25, 0.55, leaves + 0.25 * (1.0 - v));
			albedo = mix(albedo, fig_tint * (0.6 + 0.8 * leaves), fig);
			rough = mix(0.92, 0.8, fig);
		}
		albedo *= 1.0 - 0.18 * foot;
	} else if (kind < 4.5) {
		// A clipped hedge: small leaves with dark gaps between them, faint lumps where the shears
		// missed, the normal jittered leaf by leaf so the face breaks up in the light, the sheared
		// top a little lighter. (Kept fine and low in contrast: at 60 cm the lumps read as
		// camouflage paint.)
		float lumps = vnoise(uv * 2.1) * 0.6 + vnoise(uv * 5.3) * 0.4;
		float leaves = vnoise(uv * 31.0) * 0.6 + vnoise(uv * 67.0) * 0.4;
		float px = smoothstep(0.06, 0.015, fwidth(uv.x) * 4.0);
		float gaps = smoothstep(0.42, 0.22, leaves) * px;
		float g = dot(texture(grass_tex, uv / 0.35).rgb, vec3(0.33));
		albedo = paint * (0.7 + 0.6 * g) * (0.82 + 0.3 * lumps) * (1.0 - 0.45 * gaps) * (top ? 1.1 : 1.0);
		vec3 jitter = vec3(vnoise(uv * 27.0 + 3.1), vnoise(uv * 27.0 + 7.7), vnoise(uv * 27.0 + 1.3)) - 0.5;
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(world_n + jitter * 0.7 * px), 0.0)).xyz);
		rough = 0.92;
		wet_k = 0.3;
	} else if (kind < 5.5) {
		// Concrete: k-rail, a kerb, a pad.
		vec3 c = texture(concrete_tex, uv / 2.2).rgb;
		albedo = paint * (0.6 + 0.5 * c) * (1.0 - 0.3 * foot);
		rough = 0.85;
	} else if (kind < 6.5) {
		vec3 b = texture(brick_tex, uv / 1.2).rgb;
		albedo = paint * b * 1.25 * (top ? 0.9 : 1.0);
		rough = 0.85;
	} else if (kind < 7.5) {
		// Chain-link: galvanised wire in 6 cm diamonds, a dithered haze of its own cover once
		// the diamonds are under a couple of pixels (shaders/chain_link.gdshader's way).
		vec2 q = uv / 0.06;
		vec2 d = vec2(q.x + q.y, q.x - q.y);
		vec2 f = abs(fract(d) - 0.5);
		float dist = 0.5 - max(f.x, f.y);
		float fw = max(fwidth(d.x), fwidth(d.y));
		float wire = 0.09;
		float line = 1.0 - smoothstep(wire, wire + fw, dist);
		float avg = 1.0 - (1.0 - 2.0 * wire) * (1.0 - 2.0 * wire);
		float cover = mix(line, avg * 0.8, smoothstep(0.25, 0.7, fw));
		if (cover < bayer4(FRAGCOORD.xy)) {
			discard;
		}
		albedo = paint * (0.8 + 0.3 * fract(d.x * 0.5));
		metal = 0.6;
		rough = 0.45;
	} else if (kind < 8.5) {
		// Painted steel (a dumpster, a container): the paint scuffed and rusting at the edges.
		float rust = smoothstep(0.62, 0.85, vnoise(uv * 2.3 + paint.rg * 9.0)) * 0.7 + foot * 0.4;
		albedo = mix(paint * (0.9 + 0.15 * vnoise(uv * 7.0)), vec3(0.36, 0.2, 0.12), clamp(rust, 0.0, 0.8));
		rough = mix(0.55, 0.9, rust);
		metal = 0.25;
	} else {
		albedo = paint * (0.9 + 0.1 * vnoise(uv * 5.0));
		metal = 0.65;
		rough = 0.4;
	}
	float wet = clamp(road_wetness, 0.0, 1.0) * wet_k * (top ? 1.0 : 0.5);
	albedo *= 1.0 - 0.3 * wet;
	ALBEDO = albedo;
	ROUGHNESS = mix(rough, 0.2, wet * 0.7);
	METALLIC = metal;
}
