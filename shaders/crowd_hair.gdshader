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

#include "res://shaders/wet_surface.gdshaderinc"
// 1 under an open umbrella (WetWorld.shelter()).
uniform float rain_shelter = 0.0;

// crowd-closeup-3: the card edges. Up close every hair read as a helmet with a clean outline:
// the cards are near-opaque to their geometric edge, and the cut ran as a smooth curve. Three
// things break it into hair, each faded to nothing once it is under a texel (no shimmer far off):
//  - strands: the cut threshold and the shading ride a noise of thin streaks along the strands
//    (V runs along the MakeHuman cards), so an edge ends in strand tips, not a curve
//  - silhouettes: a card seen edge-on (the sides of a sheet of hair, the crown against the sky)
//    thins out, dithered, instead of drawing a hard rim
//  - the dither itself is interleaved-gradient noise, stepped per frame on Forward+ (TAA turns it
//    into a soft edge) and held still on Compatibility (no temporal pass: it would crawl)
uniform float strand_cut = 0.32;       // how far the strand noise moves the cut
uniform float strand_shade = 0.22;     // streaks in the colour
uniform float strand_freq = 260.0;     // streaks across the atlas (U), per unit
uniform float silhouette_fade = 0.75;  // how much an edge-on card thins
uniform float closeup = 1.0;           // 0: the shader as it was (CROWD_HAIR_EDGES=0)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

float strand_noise(vec2 uv) {
	// value noise stretched along V: thin streaks across U, long along the strand
	vec2 q = vec2(uv.x * strand_freq, uv.y * strand_freq * 0.06);
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i), b = hash(i + vec2(1.0, 0.0)), c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	float lum = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	vec3 recol = hair_color * clamp(lum / max(atlas_mean, 0.01), 0.35, 1.8);
	vec3 col = mix(t.rgb, recol, hair_strength);
	float a = t.a;
	float dith = hash(FRAGCOORD.xy);
	if (closeup > 0.5) {
		// how many streak periods one pixel spans: the strands fade out before they alias
		float span = max(length(dFdx(UV.x)), length(dFdy(UV.x))) * strand_freq;
		float near_k = 1.0 - smoothstep(0.35, 0.9, span);
		float sn = strand_noise(UV) - 0.5;
		col *= 1.0 + strand_shade * sn * near_k;
		a = clamp(a + strand_cut * sn * near_k * smoothstep(0.05, 0.6, a) * (1.0 - smoothstep(0.85, 1.0, a)), 0.0, 1.0);
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		a *= 1.0 - silhouette_fade * (1.0 - smoothstep(0.08, 0.42, facing));
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		dith = ign(FRAGCOORD.xy);
#else
		dith = ign(FRAGCOORD.xy + vec2(5.588238, 3.3) * float(int(TIME * 60.0) % 16));
#endif
	}
	ALBEDO = col * (1.0 - 0.25 * grime);
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = clamp(alpha_cut + (dith - 0.5) * dither, 0.05, 0.95);
	ROUGHNESS = min(roughness + 0.3 * grime, 1.0);
	SPECULAR = specular * (1.0 - 0.6 * grime);
	ANISOTROPY = anisotropy * (1.0 - grime);
	ANISOTROPY_FLOW = vec2(0.0, 1.0);
	BACKLIGHT = vec3(0.12) * col;
	if (ws_on()) {
		// Rain (wet_surface.gdshaderinc): wet hair is darker, clumped and glossy.
		float wet = ws_wet(0.6) * (1.0 - rain_shelter);
		ALBEDO *= mix(1.0, 0.62, wet);
		ROUGHNESS = mix(ROUGHNESS, 0.2, wet);
		SPECULAR = mix(SPECULAR, 0.5, wet);
	}
}
