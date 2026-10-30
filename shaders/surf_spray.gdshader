shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

// Spray and mist off the breakers (CityChunk._build_surf_spray): one MultiMesh of quads a
// shoreline chunk, one instance every few metres of the waterline, each standing at that
// stretch's break point and puffing when a wave breaks there - the same wave, at the same
// instant, as the ocean shader's lip (shaders/surf.gdshaderinc). Kind 0 is the spray thrown up
// off the lip, tall and quick; kind 1 the low mist the whitewater leaves drifting in over the
// inner surf zone, wide and slow. Between waves a quad is fully transparent, and the whole
// thing is one draw call a chunk. The instance's custom data is (way to the land xz, seed, kind).
//
// Particles would cost a node and a simulation each; these cost four vertices and know where the
// surf is. Judge them on the opengl3 stills (CLAUDE.md: lavapipe smears particles).

#include "res://shaders/surf.gdshaderinc"

global uniform vec3 origin_shift;
global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform float night_factor;
global uniform float wind_factor;

// Peak opacity of the spray and of the mist.
uniform float spray_alpha = 0.55;
uniform float mist_alpha = 0.22;
// Seconds a puff lasts.
uniform float spray_life = 2.6;
uniform float mist_life = 7.0;
uniform float fade_distance = 380.0;

varying float v_alpha;
varying float v_seed;
varying float v_kind;
varying vec3 v_world;


void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	vec2 land = normalize(INSTANCE_CUSTOM.xy + vec2(0.0001, 0.0));
	v_seed = INSTANCE_CUSTOM.z;
	v_kind = INSTANCE_CUSTOM.w;
	bool mist = v_kind > 0.5;
	vec2 tw = inst.xz + origin_shift.xz;
	float brk = max(surf_shape.w, 2.0);
	// This stretch's break point, and the wave breaking there: its phase at the break point grows
	// from 0 as the crest passes it, so (phase - n) * period is how long ago it broke.
	vec2 bp = tw - land * brk;
	float phi = surf_phase(bp, brk, TIME) / TAU;
	float n = floor(phi);
	float g = surf_wave_gain(n, bp);
	float age = (phi - n) * surf_shape.z;
	float life = mist ? mist_life : spray_life;
	float k = clamp(age / life, 0.0, 1.0);
	// Only the bigger waves of a set throw real spray; every broken wave leaves some mist.
	float strength = mist ? (0.5 + 0.5 * smoothstep(0.7, 1.1, g)) : smoothstep(0.80, 1.15, g);
	strength *= 0.7 + 0.3 * clamp(wind_factor - 0.5, 0.0, 1.5);
	v_alpha = strength * smoothstep(0.0, mist ? 0.15 : 0.06, k) * pow(1.0 - k, mist ? 1.2 : 1.8);
	float h0 = surf_shape.x * g;
	// It rides in with the wave and blows inland on the wind.
	float speed = surf_shape.y / max(surf_shape.z, 0.5);
	float travel = age * speed * (mist ? 0.75 : 0.35) + (mist ? brk * 0.15 : 0.0);
	vec2 at = bp + land * (travel + (v_seed - 0.5) * 6.0);
	float w = mist ? (16.0 + 10.0 * k) * (0.8 + 0.4 * v_seed) : (6.0 + 6.0 * k) * (0.7 + 0.6 * v_seed);
	float h = mist ? (1.6 + 2.2 * k) * (0.6 + 0.6 * h0) : (1.5 + 3.5 * k) * (0.6 + 1.1 * h0);
	float base = 0.15 + (mist ? 0.0 : h0 * 0.35);
	vec3 centre = vec3(at.x - origin_shift.x, base, at.y - origin_shift.z);
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z) + vec3(0.0001, 0.0, 0.0));
	vec3 world = centre + right * VERTEX.x * w + vec3(0.0, 1.0, 0.0) * (VERTEX.y + 0.5) * h;
	v_world = world;
	if (v_alpha < 0.002) {
		world = centre;
	}
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}


void fragment() {
	if (v_alpha < 0.002) {
		discard;
	}
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 view_dir = normalize(v_world - eye);
	float dist = length(v_world - eye);
	vec2 q = UV * 2.0 - 1.0;
	bool mist = v_kind > 0.5;
	// A soft lump, bottom-heavy, broken up by two octaves of drifting noise.
	float r = length(q * vec2(1.0, mist ? 1.0 : 0.85) - vec2(0.0, mist ? 0.15 : 0.25));
	vec2 np = UV * vec2(mist ? 3.0 : 4.0, 3.0) + vec2(v_seed * 37.0, -TIME * 0.35);
	float nz = surf_noise(np) * 0.62 + surf_noise(np * 2.7 + 11.0) * 0.38;
	float a = (1.0 - smoothstep(0.25, 1.0, r)) * smoothstep(0.22, 0.70, nz + (mist ? 0.1 : 0.0));
	// Fades into the water at its foot rather than ending on a line.
	a *= smoothstep(1.0, 0.70, UV.y);
	a *= v_alpha * (mist ? mist_alpha : spray_alpha);
	a *= 1.0 - smoothstep(fade_distance * 0.6, fade_distance, dist);
	// Lit by the sky, and glowing when the sun is behind it (most of all low in the sky).
	vec3 sun_n = normalize(sun_direction);
	float day = smoothstep(-0.05, 0.25, sun_n.y);
	float golden = (1.0 - smoothstep(0.06, 0.45, sun_n.y)) * smoothstep(-0.06, 0.02, sun_n.y);
	float back = pow(max(dot(view_dir, sun_n), 0.0), 4.0);
	vec3 base = mix(sky_tint.rgb * 1.1, vec3(0.92, 0.94, 0.95), 0.55) * mix(0.05, 1.0, day);
	vec3 glow = mix(vec3(1.0, 0.95, 0.85), vec3(1.0, 0.62, 0.32), golden) * back * (0.6 + 2.0 * golden) * day;
	ALBEDO = (base + glow) * mix(1.0, 0.3, night_factor);
	ALPHA = clamp(a, 0.0, 1.0);
}
