// A dog's fur (DogMesh's shell mesh, drawn over dog.gdshader's skin): the coat's surfaces copied
// a few times, each lifted further along the normal (COLOR.g times coat_len at the top layer),
// combed along the hair (TANGENT, which the skinning turns with the body) and drooping a little,
// and every fragment kept only where a strand reaches that layer - the hill shells' technique on a
// skinned mesh. Strands taper to their tips and carry their own tone; where a strand's cell is
// under a pixel a layer is kept by its average cover, dithered, so a dog across the street is a
// soft coat rather than a sparkle of hairs. No shadow (the skin casts).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/dog_common.gdshaderinc"

// How far the top layer is combed along the hair (share of its height) and how far it droops.
uniform float comb = 0.9;
uniform float droop = 0.25;
// Share of the cells that carry a strand, and strands thinner than this share of a cell.
uniform float density : hint_range(0.0, 1.0) = 0.92;
uniform float strand_width : hint_range(0.05, 0.6) = 0.42;
// How many times longer than wide a strand's cell is, along the surface's run (UV2.x).
uniform float stretch = 4.0;

varying float v_layer;
varying float v_fur;

void vertex() {
	float l = CUSTOM0.x;
	float fur = coat_len * COLOR.g * 2.0;
	vec3 down = normalize(transpose(mat3(MODEL_MATRIX)) * vec3(0.0, -1.0, 0.0));
	VERTEX += NORMAL * fur * l + TANGENT * fur * comb * l * l + down * fur * droop * l * l;
	v_layer = l;
	v_fur = fur;
}

float strand(vec2 cell, float l, out float tone) {
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	vec2 h = dog_hash2(id);
	float ht = 0.55 + 0.45 * dog_hash(id + 5.7);
	tone = dog_hash(id + 2.3);
	float present = step(dog_hash(id + 9.1), density);
	float r = strand_width * (0.75 + 0.5 * h.y) * pow(max(1.0 - l / ht, 0.0), 0.65);
	float d = length(f - (0.22 + 0.56 * h));
	return present * step(d, r) * step(l, ht);
}

void fragment() {
	float l = v_layer;
	vec2 cell = UV2 / (strand_cell * vec2(stretch, 1.0));
	float px = max(max(fwidth(cell).x * stretch, fwidth(cell).y), 1e-4);
	float t1;
	float t2;
	float a = strand(cell, l, t1);
	float b = strand(cell * 1.31 + vec2(0.5, 0.37), l, t2);
	float keep = max(a, b);
	float tone = a > 0.5 ? t1 : t2;
	// Under a pixel: the layer's mean cover, dithered per pixel and layer.
	float mean_r = strand_width * pow(max(1.0 - l / 0.8, 0.0), 0.65);
	float cover = clamp(density * 3.14159 * mean_r * mean_r * 1.8, 0.0, 1.0);
	float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)) + l * 3.7));
	float far_keep = step(ign, cover);
	float far = smoothstep(0.55, 1.4, px);
	if (mix(keep, far_keep, far) < 0.5) {
		discard;
	}
	tone = mix(tone, 0.5, far);
	vec3 coat = dog_coat(UV);
	float shade = mix(root_dark, 1.0, smoothstep(0.0, 0.85, l)) * (1.0 + tip_light * smoothstep(0.55, 1.0, l));
	vec3 alb = coat * shade * (0.84 + 0.32 * tone);
	// Sun-browned tips: what keeps a black coat from reading as black plastic.
	alb += vec3(0.024, 0.017, 0.011) * l * l * (0.4 + tone);
	if (dog_part(COLOR) == 4) {
		alb = mix(vec3(0.30, 0.17, 0.15), coat, 0.6) * shade;
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = 0.88;
	SPECULAR = 0.12 + 0.3 * tone * l;
	RIM = fur_rim * 0.6;
	RIM_TINT = 0.85;
	ANISOTROPY = fur_aniso;
	BACKLIGHT = cs_out(alb * 0.25 * l);
	AO = mix(COLOR.b, 1.0, l);
	AO_LIGHT_AFFECT = 0.2;
}
