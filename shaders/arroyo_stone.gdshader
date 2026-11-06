shader_type spatial;
// The washes' cobbles (ArroyoKit.pebble): the rock scan projected in the stone's own space at a
// cobble's grain, re-toned by luma to a worn granite and tinted per instance (COLOR, the
// MultiMesh's colour: greys, tan, rose, a dark stone), a little darker and glossier where the
// stone sits in the sand. Linear on both renderers.
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_mean_luma = 0.3;
// Linear albedo of an average stone.
uniform vec3 stone_color = vec3(0.3, 0.29, 0.27);

global uniform float road_wetness;

varying vec3 v_local;
varying vec3 v_nrm;

void vertex() {
	v_local = VERTEX;
	v_nrm = NORMAL;
}

void fragment() {
	// Triplanar in the stone's space (it moves with the stone, a quarter metre a tile at scale 1).
	vec3 w = abs(v_nrm);
	w = w / max(w.x + w.y + w.z, 0.001);
	vec3 t = cs_in(texture(rock_albedo, v_local.zy * 1.7).rgb) * w.x
		+ cs_in(texture(rock_albedo, v_local.xz * 1.7).rgb) * w.y
		+ cs_in(texture(rock_albedo, v_local.xy * 1.7).rgb) * w.z;
	float l = dot(t, vec3(0.2126, 0.7152, 0.0722)) / rock_mean_luma;
	vec3 col = stone_color * mix(1.0, clamp(l, 0.4, 1.6), 0.5) * COLOR.rgb;
	// The foot, sunk in the sand: damp and dusty.
	float foot = 1.0 - smoothstep(0.05, 0.3, v_local.y);
	col *= mix(1.0, 0.8, foot);
	float wet = clamp(road_wetness, 0.0, 1.0);
	col *= mix(1.0, 0.6, wet);
	ALBEDO = cs_out(col);
	ROUGHNESS = mix(0.82, 0.25, wet);
	SPECULAR = 0.35;
}
