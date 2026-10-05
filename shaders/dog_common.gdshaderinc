// The dogs' shared shading (DogMesh, scripts/npc/dog_mesh.gd; dog.gdshader draws the skin,
// dog_fur.gdshader the fur shells over it). Vertex data:
//   UV      the breed's coat atlas (tools/dogs/make_dog_coats.py)
//   UV2     metres over the surface (the strands' cells)
//   TANGENT the way the hair lies
//   COLOR   r part / 8 (0 fur, 1 nose, 2 eye, 3 pad, 4 inner ear, 5 lip, 6 claw), g fur length
//           factor / 2, b baked occlusion
//   CUSTOM0 x the shell layer (0 the skin)
// Works in linear on both renderers (color_space.gdshaderinc). Shader files use // comments.

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D coat_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// The breed's coat length (metres; COLOR.g scales it by region) and a strand's cell (metres).
uniform float coat_len = 0.02;
uniform float strand_cell = 0.0022;
// Iris colour (linear).
uniform vec3 eye_color = vec3(0.15, 0.06, 0.02);
// How dark the coat is down at the skin, and how much lighter its tips catch the light.
uniform float root_dark : hint_range(0.0, 1.0) = 0.55;
uniform float tip_light : hint_range(0.0, 1.0) = 0.12;
// Fur's soft sheen at grazing angles, and its anisotropic highlight along the hair.
uniform float fur_rim : hint_range(0.0, 1.0) = 0.35;
uniform float fur_aniso : hint_range(-1.0, 1.0) = 0.3;
// Light through thin ears (linear colour).
uniform vec3 ear_glow = vec3(0.32, 0.07, 0.04);

float dog_hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

vec2 dog_hash2(vec2 p) {
	return vec2(dog_hash(p), dog_hash(p + 17.31));
}

int dog_part(vec4 col) {
	return int(col.r * 8.0 + 0.5);
}

vec3 dog_coat(vec2 uv) {
	return cs_in(texture(coat_tex, uv).rgb);
}
