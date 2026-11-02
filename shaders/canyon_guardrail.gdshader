shader_type spatial;
render_mode cull_disabled;

// The hill roads' metal-beam guardrail (CanyonRoad): a galvanised W-beam on timber posts with
// timber blockouts, along the fill side of a canyon road. What a vertex is rides in COLOR.a
// (CanyonRoad.K_*): 0 the galvanised beam, 0.5 the timber, 1 the reflector tab. Colours linear on
// both renderers (color_space.gdshaderinc). UV = (metres along the run, metres up).

#include "res://shaders/color_space.gdshaderinc"

uniform vec3 zinc = vec3(0.30, 0.31, 0.31);
uniform vec3 zinc_dull = vec3(0.17, 0.17, 0.165);
uniform vec3 timber = vec3(0.07, 0.064, 0.057);
uniform vec3 rust = vec3(0.12, 0.05, 0.02);
uniform vec3 reflector = vec3(0.9, 0.55, 0.05);

global uniform vec3 origin_shift;
global uniform float lamp_factor;
global uniform float road_wetness;

varying vec3 world_pos;
varying float kind;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_shift;
	kind = COLOR.a;
}

void fragment() {
	vec2 st = UV;
	float k = kind;
	float wet = clamp(road_wetness, 0.0, 1.0);
	vec3 col;
	float rough;
	float metal;
	if (k < 0.25) {
		// Galvanised steel: spangle in patches, dulled with age, road grime thrown up its face,
		// rust weeping from the splice bolts every 3.81 m.
		float spangle = vnoise(st * vec2(14.0, 14.0)) * 0.5 + vnoise(st * 3.0 + 7.0) * 0.5;
		float age = vnoise(world_pos.xz * 0.05);
		col = mix(zinc, zinc_dull, clamp(age * 0.8 + spangle * 0.3, 0.0, 1.0));
		float grime = (1.0 - smoothstep(0.45, 0.75, st.y)) * 0.5;
		col *= 1.0 - grime * 0.45;
		float splice = 1.0 - smoothstep(0.0, 0.35, abs(fract(st.x / 3.81 + 0.5) - 0.5) * 3.81);
		float streak = splice * smoothstep(0.82, 0.5, st.y) * vnoise(vec2(st.x * 8.0, st.y * 2.0));
		col = mix(col, rust, clamp(streak * 0.7, 0.0, 1.0));
		rough = mix(0.32, 0.6, age) + grime * 0.2;
		metal = mix(0.85, 0.4, grime + streak * 0.6);
	} else if (k < 0.75) {
		// Weathered treated timber: grey-brown, grain down the post.
		float grain = vnoise(vec2(st.x * 30.0, st.y * 2.5) + world_pos.xz);
		col = timber * mix(0.75, 1.3, grain) * mix(0.85, 1.1, vnoise(world_pos.xz * 0.7));
		rough = 0.9;
		metal = 0.0;
	} else {
		col = reflector;
		rough = 0.35;
		metal = 0.0;
		// Retroreflective: lit by the headlights after dark (taken to be at the camera).
		EMISSION = cs_out(reflector * 1.6 * clamp(lamp_factor, 0.0, 1.0) * max(dot(NORMAL, VIEW), 0.0));
	}
	col *= mix(1.0, 0.7, wet);
	ALBEDO = cs_out(col);
	ROUGHNESS = mix(rough, rough * 0.4, wet);
	METALLIC = metal;
}
