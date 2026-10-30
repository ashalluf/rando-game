shader_type spatial;
// The bed of a dry creek (Arroyos, ArroyoBuild): the hill tile's own triangles near a wash, drawn
// again a few centimetres over the terrain and cut to the bed. Pale granite sand and gravel, the
// low-flow thread down the middle a little darker and finer, gravel bars and cobbles, debris lines
// along the flow, ragged edges where the bank's soil and brush take over. Wet after rain.
//
// Per vertex (ArroyoBuild._bed_mesh):
//   UV.x   metres from the bed's edge (negative inside the bed), UV.y the bed's half width;
//   COLOR  .rg the flow's direction (x, z) * 0.5 + 0.5, .b a per-line hash, .a 1;
//   UV2.x  metres across from the centre line (signed).
// Works in linear on both renderers (color_space.gdshaderinc).
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Linear albedos (plain uniforms: see color_space.gdshaderinc).
uniform vec3 sand_color = vec3(0.30, 0.27, 0.22);
uniform vec3 thread_color = vec3(0.24, 0.215, 0.18);
uniform vec3 debris_color = vec3(0.12, 0.10, 0.075);
uniform float sand_scale = 2.6;
uniform float gravel_scale = 1.7;
// Mean luma of the two textures (their tone is taken off and ours put on).
uniform float sand_mean_luma = 0.33;
uniform float gravel_mean_luma = 0.22;
// Metres over which the edge breaks up.
uniform float edge_rag = 0.9;
// The draw stops here (LOD tiles out to the far city).
uniform float fade_far = 1400.0;

global uniform float road_wetness;
global uniform vec3 origin_shift;

varying vec3 v_world;
varying float v_dist;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.7 - 3.3) * 0.15;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Rounded cobbles on a jittered grid in the flow's frame (q, metres): .x coverage (0..1), .yz
// the dome's slope, .w the stone's tone hash.
vec4 cobbles(vec2 q, float cell, float density) {
	vec2 g = q / cell;
	vec2 b = floor(g);
	vec4 best = vec4(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = b + vec2(float(i), float(j));
			float h = hash12(c);
			if (h > density) {
				continue;
			}
			float h2 = hash12(c + 17.3);
			vec2 ctr = c + 0.5 + (vec2(h, h2) - 0.5) * 0.5;
			vec2 r = vec2(0.32 + 0.16 * h2, 0.22 + 0.12 * h);
			float ang = h * 6.2832;
			vec2 d = g - ctr;
			d = vec2(d.x * cos(ang) - d.y * sin(ang), d.x * sin(ang) + d.y * cos(ang));
			vec2 e = d / r;
			float k = 1.0 - dot(e, e);
			if (k > best.x) {
				vec2 sl = -e / r * 0.6;
				sl = vec2(sl.x * cos(-ang) - sl.y * sin(-ang), sl.x * sin(-ang) + sl.y * cos(-ang));
				best = vec4(k, sl, hash12(c + 3.7));
			}
		}
	}
	return best;
}

void vertex() {
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_dist = length(view);
	// Over the terrain it was cut from: a few centimetres near, more with distance (depth
	// precision), along the normal so a bank keeps its shape.
	VERTEX += NORMAL * (0.035 + v_dist * 0.0012);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_shift;
}

void fragment() {
	float edge = UV.x;
	float half_w = max(UV.y, 0.5);
	vec2 flow = normalize(COLOR.rg * 2.0 - 1.0 + vec2(0.0001));
	vec2 side = vec2(-flow.y, flow.x);
	vec2 w = v_world.xz;
	// The flow's frame, metres: along (s) and across (t) - a slow drift across keeps any
	// interpolation seam of the direction out of sight.
	vec2 q = vec2(dot(w, flow), dot(w, side));
	float px = max(fwidth(w.x) + fwidth(w.y), 0.002);

	// The ragged edge: the bank's soil eats in, and the bed spills out in fans.
	float rag = (fbm(w * 0.45) - 0.5) * 2.0 * edge_rag + (vnoise(w * 2.3) - 0.5) * 0.45;
	float e = edge + rag;
	// Dither the last few centimetres (TAA resolves it; it keeps the cut from a ruler line).
	float dith = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
	if (e + dith * 0.25 > 0.0 || v_dist > fade_far * (0.92 + 0.08 * dith)) {
		discard;
	}
	// How far in from the edge (0 at it, 1 at the middle).
	float inside = clamp(-e / half_w, 0.0, 1.0);

	// Sand, re-toned to ours.
	vec3 sand = cs_in(texture(sand_albedo, w / sand_scale).rgb);
	sand = sand / max(sand_mean_luma, 0.01) * sand_color;
	// The low-flow thread: a narrower meander down the middle, finer and a little darker.
	float wander = (fbm(vec2(q.x * 0.04, COLOR.b * 37.0)) - 0.5) * half_w * 1.1;
	float thread = 1.0 - smoothstep(0.25, 0.9, abs(UV2.x - wander) / max(half_w * 0.45, 0.6));
	thread *= smoothstep(0.15, 0.5, inside);
	vec3 col = mix(sand, sand / max(luma(sand_color), 0.01) * luma(thread_color) * (thread_color / max(luma(thread_color), 0.01)), thread * 0.7);
	// Ripples and streaks along the flow in the thread (fine sand left by the last flood).
	float ripple = sin(q.x * 9.0 + vnoise(q * vec2(0.6, 3.0)) * 6.0) * 0.5 + 0.5;
	float ripple_fade = 1.0 - smoothstep(0.02, 0.06, px);
	col *= 1.0 - thread * ripple * 0.08 * ripple_fade;

	// Gravel bars: patches of the gravel texture, more toward the edges and in drifts along the
	// flow, thinning where the thread runs.
	float bars = fbm(vec2(q.x * 0.12, q.y * 0.45) + COLOR.b * 13.0);
	float gravel = smoothstep(0.42, 0.62, bars + (1.0 - inside) * 0.35 - thread * 0.4);
	vec3 grv = cs_in(texture(gravel_albedo, w / gravel_scale).rgb);
	grv = grv / max(gravel_mean_luma, 0.01) * sand_color * vec3(0.95, 0.96, 1.0);
	col = mix(col, grv, gravel);

	// Cobbles: two sizes, on the bars and along the thread's banks; faded to their mean under a
	// few pixels (a ten-centimetre stone at sixty metres is a speck).
	float cob_fade = 1.0 - smoothstep(0.03, 0.09, px);
	vec4 c1 = cobbles(q, 0.55, 0.35 + gravel * 0.45);
	vec4 c2 = cobbles(q * 1.0 + 31.7, 0.24, 0.25 + gravel * 0.5);
	vec4 cb = c1.x > 0.0 ? c1 : c2;
	float stone = smoothstep(0.0, 0.18, cb.x) * cob_fade * (0.35 + 0.65 * max(gravel, 1.0 - thread));
	// Granite greys, a tan, now and then a rose or a dark diorite.
	vec3 rock = mix(vec3(0.27, 0.26, 0.245), vec3(0.33, 0.29, 0.23), step(0.55, cb.w));
	rock = mix(rock, vec3(0.30, 0.22, 0.19), step(0.86, cb.w));
	rock = mix(rock, vec3(0.10, 0.10, 0.095), step(0.94, cb.w));
	// Each stone lit as a dome: light from above-ish, shade at its foot.
	rock *= 0.82 + 0.3 * sqrt(clamp(cb.x, 0.0, 1.0));
	col = mix(col, rock, stone);
	// The stones' mean where they are too small to see: a speckled grey over the sand.
	col = mix(col, col * 0.93 + vec3(0.012), (1.0 - cob_fade) * gravel * 0.6);

	// Debris lines: twigs, leaves and dried algae left along the flood's edges.
	float drift = abs(fract((-e) / max(half_w * 0.6, 0.8) + vnoise(q * vec2(0.08, 0.5)) * 0.8) - 0.5);
	float debris = smoothstep(0.06, 0.0, drift) * smoothstep(0.6, 0.75, vnoise(q * vec2(0.5, 2.0)));
	col = mix(col, debris_color, debris * 0.45 * (1.0 - stone));
	// The edge darkens a touch into the bank's soil.
	col *= mix(0.86, 1.0, smoothstep(0.0, 0.8, -e));

	// Normal: the sand and gravel maps in the flow-free world frame, the cobbles' domes.
	vec3 nsand = texture(sand_normal, w / sand_scale).rgb * 2.0 - 1.0;
	vec3 ngrv = texture(gravel_normal, w / gravel_scale).rgb * 2.0 - 1.0;
	vec2 tex = mix(nsand.xy * 0.6, ngrv.xy, gravel) * 0.5;
	vec2 dome = (flow * cb.y + side * cb.z) * stone * 0.9;
	// World-space bend of the vertex normal (the mesh has no UV tangents: the maps are laid on
	// world x and z, so their tilt is a world tilt).
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	nw = normalize(nw + vec3(tex.x + dome.x, 0.0, -tex.y + dome.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// Wet after rain: darker, glossier, the thread holding water longest.
	float wet = clamp(road_wetness * (0.7 + thread * 0.6), 0.0, 1.0);
	col *= mix(1.0, 0.55, wet);
	ALBEDO = cs_out(col);
	ROUGHNESS = mix(mix(0.93, 0.62, stone * 0.5), 0.18, wet * (1.0 - gravel * 0.5));
	SPECULAR = 0.5;
}
