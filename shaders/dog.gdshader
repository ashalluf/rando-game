// A dog's skin (DogMesh / DogRig): the coat's undercoat where fur shells grow over it, or the
// whole coat's average where none are drawn (the FAR level: `shells` 0), the wet nose leather,
// glossy eyes, foot pads, the thin inner ear lit from behind, lips and claws.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/dog_common.gdshaderinc"

// 1 while shells are drawn over this skin (it is then the undercoat), 0 at FAR.
uniform float shells = 1.0;

varying vec3 v_tan;

void vertex() {
	v_tan = TANGENT;
}

void fragment() {
	int part = dog_part(COLOR);
	vec3 coat = dog_coat(UV);
	float ao = COLOR.b;
	vec3 alb = coat;
	float rough = 0.8;
	float spec = 0.35;
	vec2 cell = UV2 / strand_cell;
	float px = max(length(fwidth(cell)), 1e-4);
	if (part == 0 || part == 4) {
		// Strands drawn as fine streaks along the hair: they fade to their average below a pixel.
		float streak = dog_hash(floor(cell * vec2(0.25, 1.0)));
		float detail = mix(streak * 0.36 + 0.82, 1.0, smoothstep(0.6, 2.2, px));
		float under = mix(1.0, root_dark * 0.85 + 0.12, shells);
		alb = coat * under * detail;
		RIM = fur_rim * (1.0 - shells * 0.7);
		RIM_TINT = 0.7;
		ANISOTROPY = fur_aniso;
		rough = 0.9;
		spec = mix(0.25, 0.1, shells);
		if (part == 4) {
			// The inner ear: thin skin, pinkish grey, a few hairs.
			vec3 skin = vec3(0.30, 0.17, 0.15);
			alb = mix(skin, coat, 0.35);
			BACKLIGHT = cs_out(ear_glow);
			rough = 0.6;
		}
	} else if (part == 1) {
		// Nose leather: cobbled, wet.
		vec2 c = UV2 / 0.0011;
		vec2 id = floor(c);
		vec2 f = fract(c) - 0.5;
		vec2 j = dog_hash2(id) - 0.5;
		vec2 d = f - j * 0.4;
		float bump = smoothstep(0.55, 0.0, length(d));
		alb = coat * (0.8 + 0.25 * bump);
		NORMAL = normalize(NORMAL + (v_tan * d.x + BINORMAL * d.y) * 0.5 * smoothstep(3.0, 0.8, px));
		rough = mix(0.32, 0.18, bump);
		spec = 0.55;
	} else if (part == 2) {
		// The eye: a dark pupil, the iris to most of what shows, a wet clearcoat.
		vec2 e = (UV - vec2(0.78125, 0.53125)) / 0.03125;
		float r = length(e);
		float ang = atan(e.y, e.x);
		float streaks = 0.75 + 0.25 * dog_hash(vec2(floor(ang * 9.0), 3.0));
		vec3 iris = eye_color * streaks * mix(1.15, 0.55, smoothstep(0.3, 0.72, r));
		alb = mix(vec3(0.004), iris, smoothstep(0.26, 0.31, r));
		alb = mix(alb, vec3(0.02, 0.012, 0.01), smoothstep(0.72, 0.8, r));
		rough = 0.04;
		spec = 0.65;
		CLEARCOAT = 1.0;
		CLEARCOAT_ROUGHNESS = 0.02;
		ao = 1.0;
	} else if (part == 3) {
		vec2 c = UV2 / 0.0016;
		float bump = dog_hash(floor(c));
		alb = vec3(0.028, 0.024, 0.022) * (0.85 + 0.3 * bump);
		rough = 0.82;
	} else if (part == 5) {
		alb = vec3(0.018, 0.012, 0.012);
		rough = 0.45;
	} else {
		alb = vec3(0.05, 0.045, 0.04);
		rough = 0.38;
		spec = 0.5;
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	SPECULAR = spec;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
}
