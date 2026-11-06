// The hero's hair cards and brows (hero.glb, materials hero_hair / hero_brows; HeroLook puts
// them on). tools/hero/hair.py grows the cards along a combed-back flow; prep_textures.py draws
// the strand atlas. Two shaders include this:
//  - hero_hair.gdshader, the opaque core: alpha scissor, its threshold jittered per pixel so the
//    edge of every strand dithers instead of stepping (TAA resolves it on desktop)
//  - hero_hair_fringe.gdshader (#define HAIR_FRINGE), the material's next pass (hero-closeup-2):
//    alpha blended, no depth write, drawing only the soft part of each strand under the cut - the
//    fine tips and edges the scissor throws away, which on the Compatibility renderer (no TAA)
//    were a hard dithered fringe round every card.
//  - colour: root to tip (UV.y runs root 0 -> tip 1 after the glTF flip), a per-card tint and the
//    card's own occlusion - how deep in the hair it lies (UV2.x) - so the under-layers are dark
//    and the top layer carries the shine
//  - shine (hero-closeup-2, HAIR_LIGHT: hero_hair.gdshader and the fringe): its own light() - a Kajiya-Kay pair along the strands, a
//    white primary shifted toward the root and a coloured, sparkling secondary toward the tip,
//    broken up strand by strand. Godot's anisotropic GGX on cards, with the strands rounded across
//    them, blew whole cards at the crown out to flat white planks against the sun, and the sky's
//    reflection drew the dark hair blue-white. hero_hair_base.gdshader (HERO_CLOSEUP_2=0) has
//    no light(): the renderer's own lobes, as before.
// Brows use the same shader with their strand texture (strands_from_texture = 1).

#include "res://shaders/wet_surface.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 root_color : source_color = vec3(0.030, 0.025, 0.022);
uniform vec3 tip_color : source_color = vec3(0.075, 0.062, 0.052);
// 1: take the colour from the texture (brows); 0: from the strand atlas' shading + the colours.
uniform float strands_from_texture = 0.0;
uniform float alpha_cut = 0.32;
// How far up the card (UV.y, root 0 .. tip 1) the roots fade in. Every card's root end was a hard
// straight cut, which at the hairline and the temples drew rows of black rectangles.
uniform float root_fade = 0.0;
// Width of the dithered band round alpha_cut.
uniform float dither = 0.22;
uniform float roughness = 0.36;
uniform float specular = 0.42;
uniform float anisotropy = 0.8;
// Which way the strands run in the card's tangent space (x along U, y along V).
uniform vec2 strand_flow = vec2(0.0, 1.0);
// How dark the buried layers get (UV2.x is 0.4 for the under-layer, 1 for the top).
uniform float occlusion = 1.0;
// How round the strands are across a card (0: a flat card, the old look) and how many strand
// columns the atlas has across U (the hair atlas 8, the brows 8).
uniform float strand_round = 0.0;
uniform float strand_columns = 8.0;
// hero-closeup-2 (HERO_CLOSEUP_2=0 sets 0): the strand light, the brows' colour, the fringe.
uniform float closeup2 = 0.0;
// The two highlights: strength (times the light), sharpness, and how far along the strand each
// is shifted (toward the root negative).
uniform float primary_gain = 0.035;
uniform float primary_power = 150.0;
uniform float primary_shift = -0.08;
uniform float secondary_gain = 0.035;
uniform float secondary_power = 48.0;
uniform float secondary_shift = 0.12;
// The sky's reflection on the hair (the renderer's own, from SPECULAR and ROUGHNESS): dark hair
// mirrored the blue sky as a blue-white sheen.
uniform float sky_specular = 0.3;
uniform float sky_roughness = 0.55;
// Forward+ lights the linear albedo (root_color decodes to ~0.002 there, 0.03 raw on
// Compatibility), so the same lobes stand thirteen times brighter against the hair: held down.
uniform float forward_spec = 0.45;
// The brows' own colour (dark brown, lighter and finer at the tips) instead of the texture's
// near-black, which read as one painted bar.
uniform vec3 brow_color : source_color = vec3(0.16, 0.12, 0.095);
// The fringe pass: where under alpha_cut a strand still shows (as a share of the cut).
uniform float fringe_low = 0.22;

varying vec2 hairdata;
varying vec3 strand_t; // the strand's direction (view space), for light()
varying float strand_noise;
varying float spec_amt;
varying vec3 hair_col;

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
	// Brows: the texture's colour, or (closeup2) a brown that varies hair to hair and lightens to
	// the tip, where a real brow hair is fine enough to let the light through.
	float col_hash = hash(vec2(floor(UV.x * strand_columns * 3.0), floor(hairdata.y * 97.0)));
	vec3 brow = brow_color * (0.75 + 0.5 * col_hash) * mix(1.0, 1.7, smoothstep(0.35, 1.0, tip));
	col = mix(col, mix(t.rgb, brow, closeup2), strands_from_texture);
	float ao = mix(1.0, clamp(hairdata.x, 0.0, 1.0), occlusion * (1.0 - strands_from_texture));
	ALBEDO = col * ao;
	AO = ao;
	float a = t.a * (root_fade > 0.0 ? smoothstep(0.0, root_fade, tip) * 0.6 + 0.4 * smoothstep(0.0, root_fade * 0.35, tip) : 1.0);
	// A card seen edge-on packs its strands into a solid plank (the grey slabs at the temples):
	// thin it there (closeup2), the layers behind fill in.
	a *= mix(1.0, mix(0.45, 1.0, smoothstep(0.06, 0.38, abs(dot(NORMAL, VIEW)))), closeup2);
#ifdef HAIR_FRINGE
	// Only what the core's scissor left out, faded in from fringe_low of the cut; the core's own
	// dithered edge is filled in under it.
	if (a >= alpha_cut + dither * 0.5) {
		discard;
	}
	ALPHA = smoothstep(alpha_cut * fringe_low, alpha_cut, a) * 0.85;
#else
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = clamp(alpha_cut + (hash(FRAGCOORD.xy) - 0.5) * dither, 0.02, 0.98);
#endif
	ROUGHNESS = mix(roughness, sky_roughness, closeup2);
	SPECULAR = mix(specular, specular * sky_specular / 0.42, closeup2) * ao;
	// Round the strands across the card (hero-face-2): a card is flat, and its whole width
	// caught one highlight as a white plank. Each strand column's normal is bent across it, so
	// the shine breaks up strand by strand as it does on real hair.
	if (strand_round > 0.0) {
		float cu = fract(UV.x * strand_columns) * 2.0 - 1.0;
		float wob = sin(UV.x * 1931.0 + hairdata.y * 37.0) * 0.5;
		NORMAL = normalize(NORMAL + TANGENT * (cu * 0.9 + wob) * strand_round * mix(1.0, 0.2, closeup2));
	}
	ANISOTROPY = anisotropy * (1.0 - closeup2);
	ANISOTROPY_FLOW = strand_flow;
	strand_t = normalize(TANGENT * strand_flow.x + BINORMAL * strand_flow.y);
	strand_noise = 0.55 + 0.9 * t.r * hash(vec2(floor(UV.x * 160.0), floor(hairdata.y * 53.0)));
	spec_amt = specular * ao;
	hair_col = col;
	if (ws_on()) {
		// Rain: wet hair is darker and glossier.
		float wet = ws_wet(0.6);
		ALBEDO *= mix(1.0, 0.62, wet);
		ROUGHNESS = mix(ROUGHNESS, 0.2, wet);
		spec_amt *= 1.0 + 0.8 * wet;
	}
}

#ifdef HAIR_LIGHT
void light() {
	// Diffuse: half wrapped - a card lit edge-on is not black on one side, light passes
	// between the strands.
	float ndl = dot(NORMAL, LIGHT);
	float diff = mix(max(ndl, 0.0), clamp((ndl + 0.45) / 1.45, 0.0, 1.0), 0.55);
	DIFFUSE_LIGHT += diff * ATTENUATION * LIGHT_COLOR / PI;
	// Kajiya-Kay along the strand: sin(T, H)^p, the strand's direction shifted along the normal.
	vec3 h = normalize(LIGHT + VIEW);
	vec3 t1 = normalize(strand_t + NORMAL * primary_shift);
	vec3 t2 = normalize(strand_t + NORMAL * secondary_shift);
	float th1 = dot(t1, h);
	float th2 = dot(t2, h);
	float s1 = pow(max(1.0 - th1 * th1, 0.0), primary_power * 0.5);
	float s2 = pow(max(1.0 - th2 * th2, 0.0), secondary_power * 0.5);
	// No shine from behind the hair (the strand's far side), faded softly.
	float facing = smoothstep(-0.25, 0.35, ndl);
	vec3 tint = hair_col / max(max(hair_col.r, max(hair_col.g, hair_col.b)), 1e-4);
	tint *= tint;
	vec3 spec = LIGHT_COLOR * (s1 * primary_gain + s2 * secondary_gain * tint);
	float rgain = (CURRENT_RENDERER == RENDERER_COMPATIBILITY) ? 1.0 : forward_spec;
	SPECULAR_LIGHT += spec * spec_amt / 0.42 * facing * ATTENUATION * strand_noise * rgain;
}
#endif
