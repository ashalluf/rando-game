// The facade detail kit (tools/facade_kit.py -> assets/models/facade_kit.glb, placed by
// scripts/world/building.gd, materials from PropFactory.kit_material()). Shared by
// facade_kit.gdshader (solid pieces) and facade_kit_2side.gdshader (awning canvas).
//
// Three things happen in vertex() that the geometry is built for (see the header of
// tools/facade_kit.py for the rules on the Blender side):
//
// * MITRE (`mitre`, the roofline runs). A run is 2 m of moulding, x -1..1, scaled along x to fit
//   its wall. INSTANCE_CUSTOM.r / .g are how far the -x / +x end ring slides along x per metre
//   out of the wall (tan of half the corner's turn, already divided by the run's x scale and
//   multiplied by its profile scale). So the two runs at a corner end on the same bisecting
//   plane and meet in a true mitre, at a square corner (1.0), a chamfer (0.41) or anything else,
//   with no corner pieces and no extra draw calls.
// * THREE-SLICE (`slice`, everything else). A window surround is built round a 1 x 1 m opening.
//   INSTANCE_CUSTOM.b / .a are how much bigger than that the real opening is on each side, in x
//   and y. The middle of the piece stretches, anything outside the opening only moves out with
//   its edge - so lugs, lintels, jambs and the awning's cheeks keep their real size on every
//   window and shop width, in one mesh and one draw call per building.
// * UV in metres follows both, so the stone does not stretch with the piece.
// * ANCHORS (the code-built storefront and curtain-wall pieces, scripts/world/shopfront_kit.gd).
//   UV2.y - 1 is a per-vertex code: bits 0-1 the x mode, bits 2-3 the y mode, where mode 0 is the
//   three-slice above, 1 moves with the low edge (-0.5 - extra), 2 with the high edge and 3 stays
//   where it is (a centre member). So a door's meeting stiles stay at the middle, its handles at
//   hand height above the threshold and a transom bar at door-head height whatever the opening,
//   and a bar can stretch between two anchors. Bit 4 keeps a vertex only on instances whose
//   INSTANCE_CUSTOM.g is over 0.5, bit 5 only on the others (bits 6 and 7 the same on .r), so one
//   mesh holds two layouts (a display bay with and without its centre mullion, a pair of doors or
//   one with a sidelight). ShopfrontKit.place() is this in GDScript, for the tests.
//   The glTF pieces carry UV2.y = 1 (code 0), so none of this touches them.
// * DISTANCE (`cull_distance`, the curtain-wall caps): an instance whose origin is further than
//   this from the main camera collapses, in the shadow passes too, so a tower's caps are one draw
//   and still stop drawing floor by floor up it.
//
// Colour: the texture is detail (divided by its own mean), the tint is the colour, and where the
// tint comes from is `tint_source`: 0 the instance COLOR (the building's trim, a shop's awning),
// 1 `base_tint`, 2 one of four ironwork paints picked by INSTANCE_CUSTOM.r. UV2.x is the
// occlusion Blender baked (0 open, 1 fully occluded).
//
// Colour space: Forward+ decodes `source_color` uniforms and textures to linear and does NOT
// decode a MultiMesh instance colour (see shaders/building_lod.gdshader's header for the probe
// that proved it). The walls this sits on get their colour through a decoded uniform, so the
// instance colour is decoded here on Forward+ - or the trim would be 1.4x (cream) to 2.6x (a
// dark paint) brighter than intended - and left alone on Compatibility, where nothing is
// decoded. `color_space_probe` is how the shader tells which one it is running on.

uniform bool mitre = false;
uniform bool slice = true;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_textures = true;
// Metres per texture tile.
uniform float tile_m = 1.5;
// Turns the texture a quarter: the plank set runs its boards across, tank staves stand up.
uniform bool swap_uv = false;
// Mean of the albedo map: linear (what Forward+ samples) and raw sRGB (Compatibility).
uniform vec3 tex_mean_linear = vec3(0.5);
uniform vec3 tex_mean_srgb = vec3(0.73);
// How much of the texture's own variation shows through the tint (0 flat, 1 all of it).
uniform float detail = 1.0;
uniform int tint_source = 0;
uniform vec3 base_tint : source_color = vec3(0.5);
uniform vec3 iron0 : source_color = vec3(0.09, 0.09, 0.10);
uniform vec3 iron1 : source_color = vec3(0.10, 0.17, 0.13);
uniform vec3 iron2 : source_color = vec3(0.33, 0.34, 0.35);
uniform vec3 iron3 : source_color = vec3(0.32, 0.14, 0.09);
uniform float roughness = 0.8;
// How far the roughness map moves it either way.
uniform float rough_detail = 0.4;
uniform float metallic = 0.0;
uniform float normal_strength = 0.8;
uniform float ao_strength = 0.85;
// Dirt that settles on what faces up (sills, cornice tops, balcony slabs).
uniform float grime = 0.35;
// Canvas stripes (awnings): INSTANCE_CUSTOM.g > 0.5 asks for them, in this second colour.
uniform bool stripes = false;
uniform vec3 stripe_color : source_color = vec3(0.86, 0.83, 0.76);
uniform float stripe_width = 0.24;
// Instances whose origin is further than this from the main camera collapse (0 = never).
uniform float cull_distance = 0.0;
// A lightbox (the blade signs): after the street lamps come on, vertex alpha times
// INSTANCE_CUSTOM.r (the shop is lit) glows in the tint at this strength.
uniform float night_glow = 0.0;
global uniform float lamp_factor;
// Never set from script: 0.5 authored as sRGB decodes to 0.214 on Forward+ and stays 0.5 on
// Compatibility (shaders/foliage_tex.gdshader has the probe this copies).
uniform vec3 color_space_probe : source_color = vec3(0.5, 0.5, 0.5);

varying vec3 v_tint;
varying vec3 v_world_normal;
varying vec3 v_world_pos;
varying float v_stripe;
varying float v_glow;

float kit_slice(float x, float extra) {
	return abs(x) < 0.5 ? x * (1.0 + 2.0 * extra) : x + sign(x) * extra;
}

// One coordinate of an anchored vertex (see ANCHORS in the header).
float kit_anchor(float x, float extra, int mode) {
	if (mode == 1) {
		return x - extra;
	}
	if (mode == 2) {
		return x + extra;
	}
	if (mode == 3) {
		return x;
	}
	return kit_slice(x, extra);
}

vec3 kit_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	if (mitre) {
		// Only the end rings: nothing else in a run reaches |x| = 1.
		if (VERTEX.x > 0.999) {
			VERTEX.x += VERTEX.z * c.g;
		} else if (VERTEX.x < -0.999) {
			VERTEX.x -= VERTEX.z * c.r;
		}
	} else if (slice) {
		int code = int(clamp(UV2.y - 0.5, 0.0, 255.0));
		int mx = code % 4;
		int my = (code / 4) % 4;
		VERTEX.x = kit_anchor(VERTEX.x, c.b, mx);
		UV.x = kit_anchor(UV.x, c.b, mx);
		// Front faces carry v = 1 + y (the glTF V flip on Blender's v = -y).
		VERTEX.y = kit_anchor(VERTEX.y, c.a, my);
		UV.y = kit_anchor(UV.y - 1.0, c.a, my) + 1.0;
		// The optional layouts: bits 4 and 5 on INSTANCE_CUSTOM.g, 6 and 7 on .r.
		if (code >= 16) {
			bool g_on = (code / 16) % 2 == 1;
			bool g_off = (code / 32) % 2 == 1;
			bool r_on = (code / 64) % 2 == 1;
			bool r_off = (code / 128) % 2 == 1;
			if ((g_on && c.g < 0.5) || (g_off && c.g >= 0.5) || (r_on && c.r < 0.5) || (r_off && c.r >= 0.5)) {
				VERTEX = vec3(0.0);
			}
		}
	}
	if (cull_distance > 0.0 && MAIN_CAM_INV_VIEW_MATRIX != mat4(1.0)) {
		if (distance(MAIN_CAM_INV_VIEW_MATRIX[3].xyz, MODEL_MATRIX[3].xyz) > cull_distance) {
			VERTEX = vec3(0.0);
		}
	}
	// Instances scale runs along x and balconies / fire escapes a little in every axis; keep
	// the texture in metres through that.
	UV *= vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec3 tint = COLOR.rgb;
	if (color_space_probe.r < 0.35) {
		tint = kit_to_linear(tint);
	}
	if (tint_source == 1) {
		tint = base_tint;
	} else if (tint_source == 2) {
		int k = int(clamp(c.r * 4.0, 0.0, 3.0));
		tint = k == 0 ? iron0 : (k == 1 ? iron1 : (k == 2 ? iron2 : iron3));
	}
	v_tint = tint;
	v_stripe = c.g;
	v_glow = COLOR.a * c.r;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float kit_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = (swap_uv ? UV.yx : UV) / tile_m;
	vec3 tint = v_tint;
	if (stripes && v_stripe > 0.5) {
		// Stripes run down the slope, so they are bands across x (UV.x is metres along it).
		float s = fract(UV.x / (2.0 * stripe_width));
		tint = mix(tint, stripe_color, smoothstep(0.47, 0.53, s) * (1.0 - smoothstep(0.97, 1.0, s)));
	}
	vec3 albedo = tint;
	float rough = roughness;
	if (use_textures) {
		vec3 tex = texture(albedo_tex, uv).rgb;
		vec3 mean = color_space_probe.r < 0.35 ? tex_mean_linear : tex_mean_srgb;
		albedo *= mix(vec3(1.0), tex / max(mean, vec3(0.02)), detail);
		rough += (texture(rough_tex, uv).r - 0.5) * rough_detail;
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	float occ = clamp(UV2.x, 0.0, 1.0) * ao_strength;
	// Dirt settles on the tops of things, patchily, and not on anything that faces down.
	float up = smoothstep(0.55, 0.95, v_world_normal.y);
	float patch = kit_hash(floor(v_world_pos.xz * 1.7) + floor(v_world_pos.y * 0.5));
	albedo *= 1.0 - grime * up * (0.25 + 0.35 * patch);
	ALBEDO = clamp(albedo * (1.0 - occ * 0.55), vec3(0.0), vec3(1.0));
	AO = 1.0 - occ;
	AO_LIGHT_AFFECT = 0.25;
	ROUGHNESS = clamp(rough + up * grime * 0.1, 0.04, 1.0);
	METALLIC = metallic;
	if (night_glow > 0.0) {
		// Normalised to the brightest channel, so a deep red board still reaches the bloom.
		vec3 box = v_tint / max(max(v_tint.r, max(v_tint.g, v_tint.b)), 0.02);
		EMISSION = box * night_glow * clamp(lamp_factor, 0.0, 1.0) * clamp(v_glow, 0.0, 1.0);
	}
}
