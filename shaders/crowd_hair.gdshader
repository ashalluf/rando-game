shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// The crowd's hair cards, brows and lashes (the "Hair" mesh of every tools/crowd rig; the body is
// opaque on character.gdshader, only these few thousand triangles are cut out). One atlas per rig
// (MakeHuman CC0 hair photographed on cards) and one material per look, shared by the crowd
// (Pedestrian.hair_material).
//  - colour: the card's own photograph, or - on a look that recolours the hair - its brightness
//    as shading round the look's hair colour (ratio to the atlas' mean, so strands and roots stay)
//  - coverage: alpha scissor with its threshold jittered per pixel, so a strand edge dithers
//    instead of stepping; TAA resolves that into a soft edge on desktop
//  - shine: an anisotropic lobe along the strands (UV.y runs along the MakeHuman cards), so hair
//    throws a band across itself rather than the round highlight of a plastic helmet

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 hair_color : source_color = vec3(0.05, 0.04, 0.035);
// 0 keeps the photographed colour, 1 takes hair_color with the photo's shading.
uniform float hair_strength = 0.0;
// Mean brightness of the atlas' opaque texels (Pedestrian._hair_mean), what the shading is a ratio to.
uniform float atlas_mean = 0.2;
uniform float alpha_cut = 0.42;
uniform float dither = 0.24;
uniform float roughness = 0.5;
uniform float specular = 0.38;
uniform float anisotropy = 0.55;
// A worn look (RoughSleeper): duller, drier hair.
uniform float grime = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	float lum = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	vec3 recol = hair_color * clamp(lum / max(atlas_mean, 0.01), 0.35, 1.8);
	vec3 col = mix(t.rgb, recol, hair_strength);
	ALBEDO = col * (1.0 - 0.25 * grime);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = clamp(alpha_cut + (hash(FRAGCOORD.xy) - 0.5) * dither, 0.05, 0.95);
	ROUGHNESS = min(roughness + 0.3 * grime, 1.0);
	SPECULAR = specular * (1.0 - 0.6 * grime);
	ANISOTROPY = anisotropy * (1.0 - grime);
	ANISOTROPY_FLOW = vec2(0.0, 1.0);
	BACKLIGHT = vec3(0.12) * col;
}
