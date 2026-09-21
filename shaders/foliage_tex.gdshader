shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

// Leaf cards for the downloaded trees, bushes, flowers and grass clumps. Only the leaf surfaces
// use this; the trunk and branches stay on their own opaque material, which keeps them out of the
// transparent pass.
//
// ---------------------------------------------------------------------------------------------
// THE CUT-OUT BUG, 2026-09-21. Read this before touching the alpha path.
//
// Every one of the 26 foliage models in assets/models carries its leaf atlas as a JPEG, and JPEG
// has no alpha channel. `texture(albedo_tex, uv).a` therefore comes back 1.0 for every texel, so
// the black background the leaves were photographed on was being drawn as solid geometry: 72% of
// the jacaranda atlas, 75% of tree_a and tree_b, 88% of the grass clumps. That is what made the
// canopies read as a heap of dark polygons rather than as leaves. The blossom recolour then
// painted those black texels violet, which is where the "dark blue shards" came from - it was
// recolouring the background, not the flowers.
//
// The fix is to recover the cut-out from the only signal the texture still carries: the
// background is black and a leaf is not. `coverage` below is that mask. It is a no-op for the
// atlases that have no black background at all (the shrubs, the fern, the fir), because on those
// nothing is anywhere near the threshold.
//
// ---------------------------------------------------------------------------------------------
// THE TWO RENDERERS DISAGREE ABOUT COLOUR SPACE, verified 2026-09-21 with an isolated two-
// renderer probe (a MultiMesh, one quad per case, read back pixel by pixel):
//   * INSTANCE_CUSTOM and per-instance COLOR arrive IDENTICAL on both. Not the culprit, despite
//     being the obvious suspect - the Compatibility renderer packs them as half floats and
//     unpacks them correctly.
//   * `source_color` uniforms AND `source_color` textures are decoded sRGB -> linear by Forward+
//     and handed over RAW by Compatibility. Each renderer is self-consistent, so anything this
//     shader merely passes through to ALBEDO looks the same in both. What does NOT survive is
//     arithmetic: a threshold is a number, and 0.03 is a different brightness in the two spaces,
//     and a luminance term feeding a multiply lands somewhere else again.
// `color_space_probe` is how the shader finds out which space it is in. It is never set from
// script, so its value is the answer.
// ---------------------------------------------------------------------------------------------

global uniform float wind_factor;
/// Weather's wet-surface amount, 0 dry to 1 soaked. Wet leaves go glossy and a little darker.
global uniform float road_wetness;
/// Points TOWARDS the sun (published by DayNight). Drives the leaf-glow lobe.
global uniform vec3 sun_direction;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
// glTF packs occlusion-roughness-metallic into one map: red is ambient occlusion, GREEN is
// roughness. This used to read red, so every leaf's roughness was actually its AO and the canopy
// had the gloss of whatever the AO bake happened to say.
uniform sampler2D rough_tex : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform bool has_rough = false;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float alpha_cut = 0.45;

// --- Cut-out ---------------------------------------------------------------------------------
/// Never set from script. 0.5 authored as sRGB decodes to 0.2140, so a value that is still near
/// 0.5 means this renderer did not decode and the shader is working in sRGB numbers.
uniform vec3 color_space_probe : source_color = vec3(0.5, 0.5, 0.5);
/// Brightest-channel value where a texel stops being background, in LINEAR light (Forward+).
/// Measured against the jacaranda atlas: its background sits under 0.004 and the darkest 5% of
/// its real leaf pixels sit at 0.047, so the band has a wide margin on both sides.
uniform float cutout_low : hint_range(0.0, 0.2) = 0.006;
uniform float cutout_high : hint_range(0.0, 0.2) = 0.030;
/// The same band in sRGB numbers, for the Compatibility renderer. Wider, because JPEG ringing
/// around a leaf edge on black reaches about 0.05 there and has to be cut too.
uniform float cutout_low_srgb : hint_range(0.0, 0.4) = 0.070;
uniform float cutout_high_srgb : hint_range(0.0, 0.4) = 0.170;
/// How fast the cut-out band relaxes with mip level, and how far it is allowed to go. 0.12 has a
/// canopy at mip 7 testing against 16% of its near-camera threshold, which is roughly what it
/// takes to keep the same amount of leaf on screen.
uniform float mip_fill : hint_range(0.0, 0.5) = 0.12;
uniform float mip_fill_max : hint_range(0.0, 1.0) = 0.84;

// --- Blossom ---------------------------------------------------------------------------------
// Poly Haven's jacaranda is photographed OUT of bloom, so its leaf texture is plain green - and a
// jacaranda that is not violet is just another green tree. Multiplying green by violet only gives
// mud, so instead the leaf is taken to its own luminance and recoloured: `blossom_mix` of the
// canopy becomes `blossom` tinted by that luminance, which keeps every leaf's own shading and
// veining while changing its hue completely. The rest stays green, the way a real tree in bloom
// still carries leaves. 0 turns it off, which is every other tree.
uniform float blossom_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec3 blossom : source_color = vec3(0.42, 0.30, 0.68);
/// Which leaves bloom. Fraction of the canopy that carries flower rather than leaf, and how soft
/// the boundary between a flowering patch and a leafy one is.
uniform float blossom_patch : hint_range(0.0, 1.0) = 0.52;
uniform float blossom_edge : hint_range(0.0, 0.5) = 0.14;

// --- Per-instance variety ----------------------------------------------------------------------
// (owner, 2026-09-21: "take your tree and turn it into 50 separate types with just different leaf
// counts and branch positions and different leaf colors").
//
// All of it rides INSTANCE_CUSTOM, so every tree in a batch can differ while still being ONE mesh
// and ONE draw call. Making 50 real meshes would have cost 50 draw calls per chunk, which this
// city cannot pay - a batch is a draw call.
//   x  thinning seed: canopy patches are dropped on a noise field, so the tree genuinely has
//      fewer leaves, not just darker ones.
//   y  canopy shape: >0.5 taller and narrower, <0.5 shorter and broader.
//   z  leaf hue/tone shift.
//   w  blossom scale: 0 leaves this instance unbloomed, 1 full. A street of jacarandas is not
//      uniformly in flower.
varying vec4 inst;
/// How much of the canopy the thinning can take at most, at x = 1.
uniform float thin_max : hint_range(0.0, 0.8) = 0.26;
uniform float shape_amount : hint_range(0.0, 0.6) = 0.30;
uniform float hue_amount : hint_range(0.0, 0.6) = 0.22;
/// Size of the thinning and blossom patches, in cells across the atlas. This used to be a
/// `floor(uv * 9.0)` grid, and a grid is exactly what it looked like: the canopy broke into
/// axis-aligned rectangles that read as shards at street distance. It is smooth value noise now,
/// so the patches have organic edges.
uniform float patch_scale : hint_range(1.0, 32.0) = 9.0;

// --- Wind ---------------------------------------------------------------------------------
// Two rates, because a tree does not slide: the branch swings slowly through a wide arc and the
// leaves hanging off it shiver quickly through a tiny one. One rate for both is the single thing
// that makes game foliage look like a texture on a stick.
/// Metres of sideways branch bend per metre-squared of height above the instance origin.
uniform float branch_bend : hint_range(0.0, 0.01) = 0.0011;
/// Branch sway rate. Slow on purpose - real canopies move at well under 1 Hz.
uniform float branch_speed : hint_range(0.0, 3.0) = 0.55;
/// How far branches on opposite sides of the trunk lag each other, in radians of phase. Without
/// it every branch reaches the top of its swing at the same instant and the crown slides.
uniform float branch_lag : hint_range(0.0, 4.0) = 1.7;
/// Leaf flutter as a fraction of the vertex's distance from the trunk axis.
uniform float leaf_flutter : hint_range(0.0, 0.1) = 0.008;
uniform float leaf_speed : hint_range(0.0, 6.0) = 2.1;
/// Rate of the travelling gust envelope, and how deep it cuts. A gust crosses the street instead
/// of every tree oscillating at a fixed amplitude forever.
uniform float gust_speed : hint_range(0.0, 1.0) = 0.17;
uniform float gust_depth : hint_range(0.0, 1.0) = 0.45;

// --- Light ---------------------------------------------------------------------------------
/// How much light a leaf passes through. This is what makes a canopy glow when the sun is behind
/// it, and it is most of what separates foliage from painted cardboard.
uniform float translucency : hint_range(0.0, 1.0) = 0.34;
/// Extra transmission when the camera is looking straight through the canopy at the sun, and how
/// tight that lobe is. Forward scattering: light that carries on in the direction it was going.
uniform float scatter_gain : hint_range(0.0, 4.0) = 1.6;
uniform float scatter_sharpness : hint_range(1.0, 16.0) = 5.0;
/// Leaf gloss dry, and the roughness a soaked leaf falls to. Wet foliage is the shiniest thing on
/// a street after the tarmac.
uniform float leaf_specular : hint_range(0.0, 1.0) = 0.32;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.22;
/// How far the leaf normals are rounded toward the canopy's own outward direction. Leaf cards are
/// flat, so without this a crown lights as a pile of planes; with it, it lights as a volume and
/// holds its shape at distance.
uniform float canopy_round : hint_range(0.0, 1.0) = 0.45;
/// How much the rounded direction leans upward rather than straight out from the trunk axis.
uniform float canopy_lift : hint_range(0.0, 2.0) = 0.62;


// Two independent smooth noise fields from one lattice: one set of corners, two values each, so
// the thinning and the blossom patches do not correlate and neither costs a second walk.
vec2 _hash2(vec2 p) {
	vec2 q = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(q) * 43758.5453);
}


vec2 _vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 a = _hash2(i);
	vec2 b = _hash2(i + vec2(1.0, 0.0));
	vec2 c = _hash2(i + vec2(0.0, 1.0));
	vec2 d = _hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


void vertex() {
	inst = INSTANCE_CUSTOM;
	// Canopy shape: stretch up and pull in, or squash down and spread. Scaled by height above the
	// instance origin so the trunk foot stays put and only the crown changes proportion.
	if (shape_amount > 0.001) {
		float tall = (inst.y - 0.5) * 2.0 * shape_amount;
		float h01 = clamp(VERTEX.y * 0.12, 0.0, 1.0);
		VERTEX.y *= 1.0 + tall;
		VERTEX.xz *= 1.0 - tall * 0.55 * h01;
	}

	// Distance from the trunk axis, and a CONTINUOUS direction around it. atan() would be the
	// obvious way to get an azimuth and it would tear the mesh along the -X axis where it wraps;
	// the normalised offset has no seam, and where it is undefined (on the axis) the amplitude it
	// feeds is zero anyway.
	float radial = length(VERTEX.xz);
	vec2 around = VERTEX.xz / max(radial, 1e-4);

	vec3 origin = MODEL_MATRIX[3].xyz;
	// Per-tree phase, so a row of street trees never sways in step.
	float phase = origin.x * 0.31 + origin.z * 0.23;
	float w = clamp(max(wind_factor, 0.25), 0.0, 3.0);
	// A gust that travels: the envelope is a slow wave across the world, so a street breathes
	// rather than every tree holding a constant amplitude.
	w *= 1.0 - gust_depth + gust_depth * (0.5 + 0.5 * sin(TIME * gust_speed + (origin.x + origin.z) * 0.013));

	// 1. Branch sway. Slow, wide, growing with the square of height above the instance origin, and
	//    phase-shifted by which side of the trunk the branch leaves from.
	float bt = TIME * branch_speed;
	float bp = phase + around.x * branch_lag + around.y * branch_lag * 0.7;
	float gust_x = sin(bt + bp) * 0.72 + sin(bt * 1.73 + bp * 2.1) * 0.28;
	float gust_z = sin(bt * 0.87 + bp * 1.4 + 2.1) * 0.72 + sin(bt * 1.51 + bp) * 0.28;
	float h = max(VERTEX.y, 0.0);
	float bend = h * h * branch_bend * w;
	VERTEX.x += bend * gust_x;
	VERTEX.z += bend * gust_z;

	// 2. Leaf flutter. Quick, tiny, and keyed to how far the vertex hangs off the trunk axis, so
	//    leaf tips shiver while the branch carrying them is still halfway through its swing.
	float lt = TIME * leaf_speed;
	float shiver = sin(lt + bp * 2.3 + radial * 1.9);
	VERTEX.y += shiver * radial * leaf_flutter * w;
	VERTEX.xz += around.yx * vec2(1.0, -1.0) * cos(lt * 0.83 + bp) * radial * leaf_flutter * w * 0.5;

	// 3. Round the flat leaf cards toward the canopy's own outward direction, so the crown shades
	//    as a volume. Normalised, so it works for a 2.6 m bush and a 19 m tree alike.
	if (canopy_round > 0.001) {
		vec3 out_dir = normalize(vec3(VERTEX.x, max(VERTEX.y, 0.001) * canopy_lift, VERTEX.z) + vec3(0.0, 1e-4, 0.0));
		vec3 blended = mix(NORMAL, out_dir, canopy_round);
		float nl = length(blended);
		// The blend can only cancel out if the two are exactly opposed at exactly 0.5; guard it
		// rather than hand the light loop a zero normal.
		NORMAL = nl > 1e-4 ? blended / nl : NORMAL;
	}
}


void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 tex = texture(albedo_tex, uv);
	// 1.0 on Forward+ (which decoded the probe to 0.2140), 0.0 on Compatibility (which left it at
	// 0.5). Everything below that has to be a number in a colour space asks this first.
	float lin = step(color_space_probe.r, 0.35);

	// --- Cut-out. See the note at the top: the atlases have no alpha channel, so coverage is
	// recovered from brightness. Brightest channel rather than luminance, because a dark green
	// leaflet still has a green channel far above the background it was shot on.
	float bright = max(max(tex.r, tex.g), tex.b);
	// Distant canopies. The mip chain averages leaf and black background together, so the
	// brightness this cut-out reads from falls away with distance and a tree three blocks off
	// would dissolve into sparkle - the classic way alpha-tested foliage fails. Pulling the band
	// down with the mip level holds the coverage roughly constant instead, which is what
	// "silhouettes that hold at distance" means for leaves. textureQueryLod is not in GLSL ES 3.0,
	// so the level comes from the UV derivatives, which are.
	vec2 texel = vec2(textureSize(albedo_tex, 0));
	vec2 du = dFdx(uv) * texel;
	vec2 dv = dFdy(uv) * texel;
	float lod = 0.5 * log2(max(dot(du, du), dot(dv, dv)) + 1e-6);
	float fade = clamp(lod * mip_fill, 0.0, mip_fill_max);
	float cover = smoothstep(mix(cutout_low_srgb, cutout_low, lin) * (1.0 - fade),
		mix(cutout_high_srgb, cutout_high, lin) * (1.0 - fade), bright);
	// min(), not multiply: a texture that really does carry alpha keeps its own edges.
	float coverage = min(tex.a, cover);

	vec3 albedo = tex.rgb * base_color.rgb * COLOR.rgb;

	// Two noise fields, offset per instance so no two trees carry the same pattern.
	vec2 n = _vnoise2(uv * patch_scale + inst.x * 31.7);

	// Thin the canopy: drop whole patches so the tree really does carry fewer leaves.
	float alpha_bias = step(n.x, inst.x * thin_max) * 2.0;

	// Leaf tone varies per tree: olive through to a fresh yellow-green. It runs BEFORE the
	// blossom, not after: applied afterwards it was dragging the flowers toward olive too, which
	// is most of why a jacaranda came out slate rather than violet.
	if (hue_amount > 0.001) {
		float t = (inst.z - 0.5) * 2.0 * hue_amount;
		albedo *= vec3(1.0 + t * 0.55, 1.0 + t * 0.12, 1.0 - t * 0.45);
	}

	if (blossom_mix > 0.001) {
		// Luminance in linear light in BOTH renderers, so the two agree on which leaves are
		// bright. x*x is a cheap stand-in for the sRGB decode Compatibility did not do.
		float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
		lum = mix(lum * lum, lum, lin);
		// w scales this instance's bloom, so a jacaranda street carries trees in full flower,
		// trees half out and trees still green, the way a real one does in spring. The noise is
		// smoothstepped rather than stepped, so a flowering patch fades into leaf instead of
		// ending on a hard line.
		float patch = smoothstep(blossom_patch + blossom_edge, blossom_patch - blossom_edge, n.y);
		float on = blossom_mix * patch * mix(1.0, inst.w, step(0.001, inst.w));
		// Brightness matters more than hue here. The leaf texture is dark green, so scaling the
		// blossom by leaf luminance alone drags it to navy; the constant term is what keeps a
		// flower in shadow still reading as a flower.
		albedo = mix(albedo, blossom * (0.95 + lum * 0.85), on);
	}

	float wet = clamp(road_wetness, 0.0, 1.0);
	// Wet foliage darkens the same way wet cloth does, and goes glossy.
	ALBEDO = albedo * mix(1.0, 0.84, wet);
	ALPHA = coverage - alpha_bias;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;

	// One fetch: glTF packs occlusion in red and roughness in green in the same map.
	vec3 arm = texture(rough_tex, uv).rgb;
	ROUGHNESS = clamp(mix(has_rough ? arm.g : 0.9, wet_roughness, wet), 0.04, 1.0);
	SPECULAR = mix(leaf_specular, 0.85, wet);
	if (has_rough) {
		AO = arm.r;
		AO_LIGHT_AFFECT = 0.35;
	}
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = 0.6;
	}

	// --- Translucency. BACKLIGHT is Godot's transmission term and it works on both renderers: the
	// light loop adds it on the side of the surface facing away from each light, so a canopy only
	// glows when something is actually shining through it and nothing glows at night. Tinting it
	// with the leaf's own albedo means the jacaranda transmits lavender and a green tree transmits
	// green. `bright` keeps the thick woody parts of a card opaque.
	// `bright` is raw texture brightness, which is a different number in the two colour spaces, so
	// it gets the same treatment as the blossom luminance before it is used as a thickness cue.
	float thin = mix(bright * bright, bright, lin);
	vec3 through = ALBEDO * translucency * (0.35 + 0.65 * thin);
	// Forward scattering on top: light carries on in the direction it was already going, so a
	// canopy between the camera and the sun lights up far harder than one off to the side.
	vec3 to_cam = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float facing = clamp(dot(to_cam, -normalize(sun_direction)), 0.0, 1.0);
	through *= 1.0 + scatter_gain * pow(facing, scatter_sharpness);
	BACKLIGHT = through;
}
