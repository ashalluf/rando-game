// The spray of the life in the water (scripts/world/sea_life.gd): a dolphin breaking the
// surface, a pelican's plunge, a sea lion going in off the buoy, a whale's blow. One mesh of 14
// camera-facing quads (SeaLifeMesh._spray: UV the corner, COLOR.r a seed, COLOR.g the index / 16),
// each a clump the vertex stage flies from the instance's origin by its age; nothing per clump
// on the CPU.
// Per instance, INSTANCE_CUSTOM: .x age (seconds), .y kind (0 a splash, 1 a big plunge, 2 a
// whale's blow, a V of two plumes), .z size (1 a dolphin's), .w the wind's lean (m/s across).
// Unshaded: white water lit by the day, dimmed at night. Linear (color_space.gdshaderinc).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, skip_vertex_transform;

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;

uniform float brightness = 0.92;

varying float v_fade;
varying vec2 v_uv;
varying float v_seed;

void vertex() {
	float age = INSTANCE_CUSTOM.x;
	float k = floor(INSTANCE_CUSTOM.y + 0.5);
	float size = INSTANCE_CUSTOM.z;
	float r = COLOR.r;
	float idx = COLOR.g * 16.0;
	float r2 = fract(r * 7.13 + 0.31);
	float r3 = fract(r * 3.71 + 0.57);
	vec3 off = vec3(0.0);
	float rad = 0.3;
	float fade = 0.0;
	if (k < 1.5) {
		// A splash: clumps thrown up and out, falling back.
		float big = k;
		float ang = r * 6.2831853 + idx * 2.4;
		float h = (0.5 + r2 * 1.3) * (1.0 + big * 0.6) * size;
		float v0 = (2.4 + r3 * 2.8) * (1.0 + big * 0.7) * sqrt(size);
		float t = age * (0.85 + r2 * 0.3);
		off = vec3(cos(ang) * h * t * 1.4, v0 * t - 4.9 * t * t, sin(ang) * h * t * 1.4);
		float life = 0.9 + r3 * 0.5 + big * 0.4;
		rad = (0.18 + 0.55 * t + r * 0.2) * size * (1.0 + big * 0.5);
		fade = smoothstep(0.0, 0.04, age) * (1.0 - smoothstep(life * 0.5, life, age)) * step(-0.2, off.y);
	} else {
		// A whale's blow: two plumes leaning out in a V, rising fast, spreading, drifting down
		// the wind and thinning away.
		float side = mod(idx, 2.0) * 2.0 - 1.0;
		float f = (floor(idx / 2.0) + r * 0.6) / 7.0;
		float rise = smoothstep(0.0, 0.9, age);
		float height = 6.5 * size * pow(f, 0.8) * (0.4 + 0.6 * rise);
		off = vec3(side * height * 0.32 + INSTANCE_CUSTOM.w * age * 0.8, height, (r2 - 0.5) * 0.6 * size);
		off.y -= 0.3 * age * age * f;
		rad = (0.35 + 1.4 * f) * size * (0.6 + 0.35 * age);
		fade = smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(1.5, 5.0, age)) * (0.55 + 0.45 * (1.0 - f));
	}
	vec3 centre = (MODEL_MATRIX * vec4(off, 1.0)).xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = centre + (right * UV.x + up * UV.y) * rad;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_fade = fade;
	v_uv = UV;
	v_seed = r;
}

void fragment() {
	vec2 q = v_uv;
	float d = length(q);
	// A lumpy clump: the edge pushed in and out by a few lobes.
	float a = atan(q.y, q.x);
	float lobe = 0.12 * sin(a * 5.0 + v_seed * 20.0) + 0.08 * sin(a * 9.0 - v_seed * 13.0);
	float body = 1.0 - smoothstep(0.35 + lobe, 1.0 + lobe * 0.5, d);
	float alpha = body * v_fade * 0.75;
	if (alpha < 0.01) {
		discard;
	}
	float day = 1.0 - 0.85 * night_factor;
	vec3 col = vec3(brightness) * day * (0.85 + 0.15 * (1.0 - d));
	ALBEDO = cs_out(col);
	ALPHA = alpha;
}
