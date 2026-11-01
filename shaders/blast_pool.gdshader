shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// A pool of burning fuel on the road (BlastPool, Blast4: fleet wave 5 "explosions-4"). One quad
// laid on the ground: a dark, wet, glossy puddle with a ragged outline (the tiling 3D noise read
// as a 2D slice), spreading out over its first second; the burning surface as flickering patches
// of flame-light that roll over it; and soot scorched onto the road round its rim that stays
// when the fire is out. Colours linear on both renderers (color_space.gdshaderinc); the burn's
// light is HDR numbers handed over raw, as the fire shaders do (through the sRGB curve on
// Compatibility its weak channels were lifted and the orange went pink).

#include "res://shaders/color_space.gdshaderinc"

uniform sampler3D noise3d : filter_linear, repeat_enable;
uniform vec2 seed = vec2(0.0);
// Its radius in metres (the quad is 2.6 radii across), how far it has spread (0..1), how much
// is burning (0..1) and its age in seconds.
uniform float radius = 3.0;
uniform float spread = 1.0;
uniform float burn = 1.0;
uniform float age = 0.0;
// The burning surface's light (linear HDR) and the wet fuel's / the soot's albedo.
uniform vec3 flame = vec3(2.2, 0.78, 0.12);
uniform vec3 wet = vec3(0.016, 0.014, 0.013);
uniform vec3 soot = vec3(0.022, 0.02, 0.018);

float n2(vec2 p, float z) {
	return texture(noise3d, vec3(p, z)).r;
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.6;
	float r = length(q);
	float ang = atan(q.y, q.x);
	// A ragged outline: fingers of fuel run out further in some directions.
	float edge = n2(vec2(cos(ang), sin(ang)) * 0.22 + seed * 0.1, 0.37) ;
	float lobes = n2(q * 0.19 + seed, 0.71);
	float reach = spread * (0.62 + 0.55 * edge + 0.25 * (lobes - 0.5));
	float rr = r / max(reach, 0.02);
	float puddle = 1.0 - smoothstep(0.86, 1.0, rr);
	// Islands of dry road inside it, near its edge.
	puddle *= smoothstep(0.32, 0.4, n2(q * 0.55 + seed * 0.3, 0.13) + 0.25 * (1.0 - rr));
	// Soot scorched out past the rim (it grows as it burns, it stays when the fire is out).
	float scorch = 1.0 - smoothstep(0.95, 1.35 + 0.15 * lobes, rr * (0.9 + 0.2 * n2(q * 0.8 + seed, 0.5)));
	scorch *= smoothstep(0.0, 2.5, age) * 0.85;
	// The burning surface: patches of flame that roll and flicker over the fuel.
	float fp = n2(q * 0.42 + seed + vec2(age * 0.07, -age * 0.05), age * 0.12);
	float ff = n2(q * 1.3 + seed * 1.7 - vec2(age * 0.21, age * 0.17), age * 0.35 + 0.5);
	float patch = smoothstep(0.42, 0.68, fp * 0.65 + ff * 0.45) * puddle;
	float flick = 0.75 + 0.25 * sin(age * 23.0 + ff * 12.0);
	// Thin fuel near the edge burns out first.
	float depth = clamp(1.0 - rr, 0.0, 1.0);
	float lit = patch * burn * flick * smoothstep(0.0, 0.25 + 0.6 * (1.0 - burn), depth);
	float wetness = puddle * clamp(burn * 1.6 + 0.15, 0.0, 1.0);
	vec3 alb = mix(soot, wet, wetness);
	ALBEDO = cs_out(alb);
	ROUGHNESS = mix(0.92, 0.12, wetness);
	SPECULAR = 0.5;
	// The flame-light on the fuel, and a dull red glow from the hot fuel under it.
	EMISSION = flame * lit + vec3(0.35, 0.06, 0.008) * puddle * burn * burn * (0.4 + 0.6 * fp);
	ALPHA = clamp(max(wetness, scorch) + lit, 0.0, 1.0) * smoothstep(1.3, 1.2, r);
}
