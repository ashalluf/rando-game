shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// The hero's eyelashes (hero.glb, material hero_lashes; HeroLook puts it on, HeroFace drives it).
// The upper lashes ride the upper lid: in a blink they swing down about the eyeball's centre
// (lid_rot; centres and frames in world space) with the lid hero_eye.gdshader paints. The lower lashes stay.

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 eye_l = vec4(0.03, 1.6887, 0.1332, 0.0122);
uniform vec4 eye_r = vec4(-0.03, 1.6887, 0.1332, 0.0122);
uniform mat3 head_basis = mat3(1.0);
uniform mat3 lid_rot = mat3(1.0);
uniform vec3 lash_color = vec3(0.012, 0.010, 0.009);
uniform float alpha_cut = 0.35;
// The lower lashes are short and sparse on a real lid; the texture's are as dense as the upper
// ones and read as a thick eyeliner band: only their strongest strands are kept.
uniform float lower_thin = 0.55;

varying float upper_v;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 e = distance(w, eye_l.xyz) < distance(w, eye_r.xyz) ? eye_l : eye_r;
	vec3 o = w - e.xyz;
	// Above the eye's centre (head frame): the upper lid's lashes.
	float upper = smoothstep(-0.05, 0.25, dot(head_basis[1], o) / e.w);
	upper_v = upper;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(e.xyz + mix(o, lid_rot * o, upper), 1.0)).xyz;
	mat3 m = mat3(MODEL_MATRIX);
	NORMAL = normalize(inverse(m) * mix(m * NORMAL, lid_rot * (m * NORMAL), upper));
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	ALBEDO = cs_out(lash_color);
	ALPHA = t.a * mix(lower_thin, 1.0, upper_v);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	// Lashes are matte hair: lit by the sky's reflection they read as a blue line.
	ROUGHNESS = 0.85;
	SPECULAR = 0.04;
}
