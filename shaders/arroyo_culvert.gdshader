shader_type spatial;
// A culvert where a hill road crosses a wash (ArroyoKit.culvert_mesh): a cast concrete headwall
// with wing walls, coping and apron round one or two corrugated steel pipes.
// COLOR.a is the part (x 4): 0 concrete, 1 the pipe's galvanised outside and rim, 2 its inside.
// UV is metres: along a wall and up it on the concrete; round the pipe and along its axis
// (negative into the bank) on the steel. Linear on both renderers.
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D concrete_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 concrete_color = vec3(0.34, 0.325, 0.30);
uniform float concrete_mean_luma = 0.42;
uniform vec3 steel_color = vec3(0.42, 0.42, 0.40);
uniform vec3 rust_color = vec3(0.16, 0.075, 0.035);

global uniform float road_wetness;

varying vec3 v_obj;

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
	return vnoise(p) * 0.55 + vnoise(p * 2.07 + 5.3) * 0.3 + vnoise(p * 4.3 - 1.7) * 0.15;
}

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float part = floor(COLOR.a * 4.0 + 0.5);
	vec2 uv = UV;
	vec3 col;
	float rough = 0.9;
	float metal = 0.0;
	float wet = clamp(road_wetness, 0.0, 1.0);
	if (part < 0.5) {
		// Board-formed concrete: the texture re-toned, form lines every 0.3 m, tie holes, water
		// stains running down from under each pipe and from the coping, dirt splashed up the foot.
		vec3 t = cs_in(texture(concrete_albedo, uv * 0.5).rgb);
		col = t / max(concrete_mean_luma, 0.01) * concrete_color;
		float board = smoothstep(0.012, 0.0, abs(fract(uv.y / 0.3) - 0.5) - 0.48);
		col *= 1.0 - board * 0.12;
		vec2 tie = fract(uv / vec2(0.6, 0.6)) - 0.5;
		col *= 1.0 - smoothstep(0.035, 0.02, length(tie)) * 0.45;
		float streak = smoothstep(0.55, 0.85, vnoise(vec2(uv.x * 3.1, uv.y * 0.25))) * smoothstep(-0.2, 0.9, v_obj.y);
		col *= 1.0 - streak * 0.35;
		float splash = smoothstep(0.55, 0.0, v_obj.y + (fbm(uv * 3.0) - 0.5) * 0.3);
		col = mix(col, col * vec3(0.62, 0.55, 0.46), splash * 0.75);
		float lichen = smoothstep(0.66, 0.8, fbm(uv * 1.7 + 9.0));
		col = mix(col, vec3(0.20, 0.20, 0.12), lichen * 0.35);
		rough = 0.92;
		vec3 n = texture(concrete_normal, uv * 0.5).rgb * 2.0 - 1.0;
		NORMAL = normalize(NORMAL + (TANGENT * n.x - BINORMAL * n.y) * 0.4);
	} else if (part < 1.5) {
		// Galvanised corrugated steel, 68 mm pitch, rusted where the water runs along the invert.
		float ph = uv.y / 0.068 * 6.2832;
		NORMAL = normalize(NORMAL + BINORMAL * cos(ph) * 0.35);
		col = steel_color * (0.85 + 0.25 * fbm(uv * vec2(2.0, 8.0)));
		float low = smoothstep(0.25, 0.0, abs(fract(uv.x) - 0.5) - 0.25);
		float rust = smoothstep(0.35, 0.75, fbm(uv * vec2(4.0, 1.5)) + low * 0.4);
		col = mix(col, rust_color, rust * 0.85);
		metal = mix(0.65, 0.0, rust);
		rough = mix(0.45, 0.9, rust);
	} else {
		// The pipe's inside: the steel going dark with depth into the bank, silt along the floor.
		float ph = uv.y / 0.068 * 6.2832;
		NORMAL = normalize(NORMAL + BINORMAL * cos(ph) * 0.3);
		float depth = clamp(-uv.y / 2.2, 0.0, 1.0);
		col = mix(steel_color * 0.7, rust_color, 0.4) * mix(1.0, 0.05, depth);
		float silt = smoothstep(0.18, 0.05, abs(fract(uv.x) - 0.5) - 0.32);
		col = mix(col, vec3(0.22, 0.19, 0.15) * mix(1.0, 0.1, depth), silt);
		rough = 0.85;
		metal = 0.2 * (1.0 - depth);
	}
	col *= mix(1.0, 0.6, wet);
	ALBEDO = cs_out(col);
	ROUGHNESS = mix(rough, 0.3, wet);
	METALLIC = metal;
}
