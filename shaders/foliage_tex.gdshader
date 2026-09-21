shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

// Wind for the textured leaf cards of the downloaded trees and bushes. Only the leaf surfaces
// use this; the trunk and branches stay on their own opaque material and stay still, which is
// close enough at these amplitudes and keeps the trunks out of the transparent pass.
//
// Same idea as shaders/foliage.gdshader: the bend grows with the square of the height above the
// instance's own origin and the phase comes from the instance's world position, so a row of
// street trees does not move in step.

global uniform float wind_factor;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform bool has_rough = false;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float alpha_cut = 0.45;
// Blossom. Poly Haven's jacaranda is photographed OUT of bloom, so its leaf texture is plain
// green - and a jacaranda that is not violet is just another green tree. Multiplying green by
// violet only gives mud, so instead the leaf is taken to its own luminance and recoloured:
// `blossom_mix` of the canopy becomes `blossom` tinted by that luminance, which keeps every
// leaf's own shading and veining while changing its hue completely. The rest stays green, the
// way a real tree in bloom still carries leaves. 0 turns it off, which is every other tree.
uniform float blossom_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec3 blossom : source_color = vec3(0.42, 0.30, 0.68);
// Which leaves bloom, from a hash of the leaf card's own UV, so it is per-leaf and not a wash.
uniform float blossom_patch : hint_range(0.0, 1.0) = 0.52;

// PER-INSTANCE VARIETY (owner, 2026-09-21: "take your tree and turn it into 50 separate types
// with just different leaf counts and branch positions and different leaf colors").
//
// All of it rides INSTANCE_CUSTOM, so every tree in a batch can differ while still being ONE
// mesh and ONE draw call. Making 50 real meshes would have cost 50 draw calls per chunk, which
// this city cannot pay - a batch is a draw call.
//   x  thinning seed: leaf cards are dropped on a hash of (card, seed), so the canopy genuinely
//      has fewer leaves, not just darker ones.
//   y  canopy shape: >0.5 taller and narrower, <0.5 shorter and broader.
//   z  leaf hue/tone shift.
//   w  blossom scale: 0 leaves this instance unbloomed, 1 full. A street of jacarandas is not
//      uniformly in flower.
varying vec4 inst;
varying float thin_seed;
// How much of the canopy the thinning can take at most, at x = 1.
uniform float thin_max : hint_range(0.0, 0.8) = 0.45;
uniform float shape_amount : hint_range(0.0, 0.6) = 0.30;
uniform float hue_amount : hint_range(0.0, 0.6) = 0.22;

// Small: leaves move relative to the branches they hang off, they do not swing like a crown.
uniform float bend_scale = 0.0009;
uniform float flutter = 0.02;
uniform float speed = 1.15;

void vertex() {
	inst = INSTANCE_CUSTOM;
	thin_seed = inst.x;
	// Canopy shape: stretch up and pull in, or squash down and spread. Scaled by height above
	// the instance origin so the trunk foot stays put and only the crown changes proportion.
	if (shape_amount > 0.001) {
		float tall = (inst.y - 0.5) * 2.0 * shape_amount;
		float h01 = clamp(VERTEX.y * 0.12, 0.0, 1.0);
		VERTEX.y *= 1.0 + tall;
		VERTEX.xz *= 1.0 - tall * 0.55 * h01;
	}
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.31 + origin.z * 0.23;
	float w = clamp(max(wind_factor, 0.25), 0.0, 3.0);
	float t = TIME * speed;
	float gust_x = sin(t + phase) * 0.72 + sin(t * 1.73 + phase * 2.1) * 0.28;
	float gust_z = sin(t * 0.87 + phase * 1.4 + 2.1) * 0.72 + sin(t * 1.51 + phase) * 0.28;
	float h = max(VERTEX.y, 0.0);
	float bend = h * h * bend_scale * w;
	VERTEX.x += bend * gust_x;
	VERTEX.z += bend * gust_z;
	float radial = length(VERTEX.xz);
	VERTEX.y += sin(t * 2.7 + phase + radial * 1.9) * radial * flutter * w * 0.2;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 c = texture(albedo_tex, uv) * base_color * COLOR;
	vec3 albedo = c.rgb;
	// Thin the canopy. Hashing the leaf card's UV cell against this instance's seed drops whole
	// cards rather than nibbling their edges, so the tree really does carry fewer leaves.
	float alpha_bias = 0.0;
	if (thin_seed > 0.001) {
		vec2 cell = floor(uv * 9.0);
		float h = fract(sin(dot(cell, vec2(41.7, 289.1)) + thin_seed * 53.7) * 24634.6345);
		alpha_bias = step(h, thin_seed * thin_max) * 2.0;
	}
	if (blossom_mix > 0.001) {
		float lum = dot(albedo, vec3(0.299, 0.587, 0.114));
		// Per-leaf-card, so a canopy is flowers among leaves rather than a flat violet blob.
		float pick = fract(sin(dot(floor(uv * 9.0), vec2(12.9898, 78.233))) * 43758.5453);
		// w scales this instance's bloom, so a jacaranda street carries trees in full flower,
		// trees half out and trees still green, the way a real one does in spring.
		float on = blossom_mix * step(pick, blossom_patch) * mix(1.0, inst.w, step(0.001, inst.w));
		// Brightness matters more than hue here. The leaf texture is dark green, so scaling the
		// blossom by leaf luminance alone drags it to navy; the constant term is what keeps a
		// flower in shadow still reading as a flower.
		albedo = mix(albedo, blossom * (0.95 + lum * 0.85), on);
	}
	// Leaf tone varies per tree: olive through to a fresh yellow-green.
	if (hue_amount > 0.001) {
		float t = (inst.z - 0.5) * 2.0 * hue_amount;
		albedo *= vec3(1.0 + t * 0.55, 1.0 + t * 0.12, 1.0 - t * 0.45);
	}
	ALBEDO = albedo;
	ALPHA = c.a - alpha_bias;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = has_rough ? texture(rough_tex, uv).r : 0.9;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = 0.6;
	}
	SPECULAR = 0.3;
	// A little light through the leaves, which is most of what makes a canopy read as foliage.
	BACKLIGHT = mix(vec3(0.12, 0.16, 0.09), blossom * 0.35, blossom_mix);
}
