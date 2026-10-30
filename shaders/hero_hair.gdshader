shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// The hero's hair cards (hero.glb, material hero_hair; HeroLook puts it on). tools/hero/hair.py
// grows the cards along a combed-back flow; prep_textures.py draws the strand atlas.
//  - colour: root to tip (UV.y runs root 0 -> tip 1 after the glTF flip), a per-card tint and the
//    card's own occlusion - how deep in the hair it lies (UV2.x) - so the under-layers are dark
//    and the top layer carries the shine
//  - coverage: alpha scissor, its threshold jittered per pixel so the edge of every strand
//    dithers instead of stepping; TAA resolves that into a soft edge on desktop
//  - shine: an anisotropic lobe along the strands. A round highlight on hair cards is what made
//    the old hair read as a plastic helmet; hair throws a band ACROSS the strands.
// Brows use the same shader with the MakeHuman brow texture (strands_from_texture = 1).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 root_color : source_color = vec3(0.030, 0.025, 0.022);
uniform vec3 tip_color : source_color = vec3(0.075, 0.062, 0.052);
// 1: take the colour from the texture (brows); 0: from the strand atlas' shading + the colours.
uniform float strands_from_texture = 0.0;
uniform float alpha_cut = 0.32;
// Width of the dithered band round alpha_cut.
uniform float dither = 0.22;
uniform float roughness = 0.36;
uniform float specular = 0.42;
uniform float anisotropy = 0.8;
// Which way the strands run in the card's tangent space (x along U, y along V).
uniform vec2 strand_flow = vec2(0.0, 1.0);
// How dark the buried layers get (UV2.x is 0.4 for the under-layer, 1 for the top).
uniform float occlusion = 1.0;

varying vec2 hairdata;

void vertex() {
	hairdata = UV2;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	float tip = clamp(UV.y, 0.0, 1.0);
	vec3 col = mix(root_color, tip_color, smoothstep(0.25, 1.0, tip)) * (0.7 + 0.6 * t.r);
	col *= 0.88 + 0.24 * fract(hairdata.y * 7.31);
	col = mix(col, t.rgb, strands_from_texture);
	float ao = mix(1.0, clamp(hairdata.x, 0.0, 1.0), occlusion * (1.0 - strands_from_texture));
	ALBEDO = col * ao;
	AO = ao;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = clamp(alpha_cut + (hash(FRAGCOORD.xy) - 0.5) * dither, 0.02, 0.98);
	ROUGHNESS = roughness;
	SPECULAR = specular * ao;
	ANISOTROPY = anisotropy;
	ANISOTROPY_FLOW = strand_flow;
}
