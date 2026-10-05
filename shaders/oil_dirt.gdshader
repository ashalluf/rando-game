shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// The oil field's graded ground laid over its hill (OilFieldBuild): the dirt lease roads, the
// gravel well pads, and the gravel of a single well's lot in the city. One mesh a chunk, no shadow.
//   UV2.x 0 a lease road: UV.x across it (-1 .. 1 at the graded edge), UV.y metres along it -
//         two wheel tracks packed dark and smooth, a crown of loose dirt and dry grass between
//         them, ragged verges where the bank's grass takes over
//   UV2.x 1 a pad: UV.x its radius share (1 at the levelled edge) - crushed rock, oil soaked in
//         round the wellheads (UV.y > 0.5 marks a pad with wells), tyre ruts from the service rigs
//   UV2.x 2 a lot's gravel (no ragged edge: it ends at its fence)
// Textures and noise in TRUE world XZ (origin_shift), so nothing jumps on a re-centre. Tuned in
// display numbers like the industrial ground; handed to the renderer in its own space.

uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 dirt_color = vec3(0.56, 0.47, 0.36);
uniform vec3 track_color = vec3(0.42, 0.36, 0.29);
uniform vec3 gravel_color = vec3(0.5, 0.46, 0.4);
uniform vec3 straw_color = vec3(0.66, 0.58, 0.40);

global uniform vec3 origin_shift;
global uniform float road_wetness;

varying vec3 wpos;

#include "res://shaders/color_space.gdshaderinc"

vec3 disp(vec3 c) {
	return cs_linear_renderer() ? cs_linear_to_srgb(c) : c;
}

vec3 to_lit(vec3 c) {
	return cs_linear_renderer() ? cs_srgb_to_linear(c) : c;
}

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
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = wpos.xz + origin_shift.xz;
	float kind = floor(UV2.x + 0.5);
	float fw = length(fwidth(w));
	float n1 = vnoise(w * 0.35);
	float n2 = vnoise(w * 1.7 + 9.0);
	float n3 = vnoise(w * 0.06 + 3.0);
	vec3 tex = disp(texture(dirt_tex, w / 4.5).rgb);
	float tl = dot(tex, vec3(0.333)) / 0.42;
	vec3 albedo;
	float rough = 0.95;
	float edge_cover = 1.0;
	if (kind < 0.5) {
		float u = abs(UV.x);
		// Two wheel tracks a little over a metre either side of the crown.
		float track = 1.0 - smoothstep(0.1, 0.22, abs(u - 0.42 - 0.03 * sin(UV.y * 0.11)));
		float crown = 1.0 - smoothstep(0.12, 0.26, u);
		albedo = dirt_color * mix(0.85, 1.12, n1) * clamp(tl, 0.6, 1.5);
		albedo = mix(albedo, track_color * mix(0.9, 1.08, n2), track * 0.75);
		// Dry grass tufts on the crown and the verges, faded to their average from the air.
		float tufts = smoothstep(0.55, 0.8, vnoise(w * 2.3) * 0.6 + n1 * 0.4);
		tufts = mix(tufts, 0.3, smoothstep(0.05, 0.25, fw));
		float grassy = max(crown * 0.7, smoothstep(0.62, 0.95, u));
		albedo = mix(albedo, straw_color * mix(0.7, 1.05, n2), tufts * grassy * 0.85);
		// Ragged verges: the ribbon thins out over its last metre into the hillside.
		edge_cover = 1.0 - smoothstep(0.78 + 0.12 * n2, 1.0, u + 0.1 * n1);
		rough = mix(0.97, 0.88, track);
	} else {
		vec3 g = disp(texture(gravel_tex, w / 2.2).rgb);
		float gl = dot(g, vec3(0.333)) / 0.45;
		albedo = gravel_color * clamp(gl, 0.55, 1.5) * mix(0.9, 1.06, n1);
		albedo = mix(albedo, dirt_color * clamp(tl, 0.6, 1.4), smoothstep(0.35, 0.8, n3) * 0.45);
		if (kind < 1.5) {
			float r = UV.x;
			// Oil spilt and soaked in: dark patches with a glossy core on a pad with wells.
			float oil = smoothstep(0.62, 0.86, vnoise(w * 0.22 + 21.0) * 0.7 + n2 * 0.3) * step(0.5, UV.y);
			albedo *= 1.0 - 0.62 * oil;
			rough = mix(0.92, 0.35, oil * 0.8);
			// Ruts from the workover rigs crossing it.
			float rut = 1.0 - smoothstep(0.08, 0.3, abs(sin(dot(w, vec2(0.7, 0.3)) * 0.35)));
			albedo *= 1.0 - 0.12 * rut * n3;
			// Grass creeping in over the edge.
			albedo = mix(albedo, straw_color * mix(0.75, 1.0, n2), smoothstep(0.8, 1.05, r + 0.15 * n1) * 0.8);
			edge_cover = 1.0 - smoothstep(0.98 + 0.06 * n2, 1.12, r + 0.06 * n1);
		} else {
			float oil = smoothstep(0.7, 0.9, vnoise(w * 0.3 + 5.0));
			albedo *= 1.0 - 0.5 * oil;
			rough = 0.9;
		}
	}
	// Ragged up close; from the air (a pixel over ~15 cm) a clean edge, or the dither reads as dots.
	float far_edge = smoothstep(0.08, 0.2, fw);
	edge_cover = mix(edge_cover, step(0.5, edge_cover), far_edge);
	if (edge_cover < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	float wet = clamp(road_wetness, 0.0, 1.0);
	albedo *= 1.0 - 0.35 * wet;
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	ROUGHNESS = mix(rough, 0.45, wet * 0.6);
	SPECULAR = 0.35;
}
