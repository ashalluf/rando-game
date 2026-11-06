shader_type spatial;
render_mode cull_back;

// The signs of the commercial boulevards (scripts/world/boulevard_signs.gd, meshes in
// scripts/world/sign_kit.gd): tall pole signs (strip-mall tenant pylons, Googie motel signs with
// chasing bulbs and VACANCY neon, liquor, check-cashing and tyre shops), window vinyl, banners
// over the sign bands, lamp-post banners and the street plates. One material for all of it, so
// each kind is one MultiMesh draw a chunk.
//
// * Vertex colour alpha says what a face is (SignKit.A_*, codes 0.05 apart): fixed colour, a lit
//   lightbox face, a neon tube (the "NO" of NO VACANCY only when the instance's flag says so),
//   a chasing bulb (UV.x its place in the chase), a printed plate, window vinyl (cut out by the
//   atlas alpha), banner fabric (COLOR.r the sway weight), a small lamp.
// * Printed faces carry UV 0..1 plus an even whole number in UV.x that names the SLOT, and the
//   slot says which atlas family and which of INSTANCE_CUSTOM.r (A) / .g (B) picks the cell
//   (sg_cell()). INSTANCE_CUSTOM.b holds flags (1 NO VACANCY lit, 2 a failing neon tube),
//   .a a 0..1 seed. All small integers: exact as half floats on Compatibility.
// * UV2 is (roughness, metallic) on solid parts.
// * The atlas is assets/textures/boulevard_signs/sign_atlas.png (tools/make_sign_art.py); its
//   families are FAMS below, BoulevardSigns.FAMILIES and SignArtTable.FAMILIES (checked).
// * Colour space: vertex colours arrive raw and are authored sRGB; the atlas is a source_color
//   texture (cs_in()); everything is worked in linear and handed over with cs_out().

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float wind_factor;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;

// A lightbox face at full night, and by day (they are lit by day too, faintly).
uniform float box_night = 1.25;
uniform float box_day = 0.12;
// Neon tubes: lit, and how much of their colour an unlit tube shows.
uniform float neon_night = 2.6;
uniform float neon_day = 0.6;
uniform float neon_glass = 0.18;
// Chasing bulbs: brightness lit at night / by day, chase steps a second.
uniform float bulb_night = 4.0;
uniform float bulb_day = 1.2;
uniform float chase_rate = 6.0;
// Retroreflective sheeting on the plates, toward the camera at night.
uniform float plate_retro = 0.35;
// Window vinyl seen against a lit shop at night.
uniform float vinyl_night = 0.22;
// Banner sway (metres at the free edge per unit wind).
uniform float sway = 0.07;

// Atlas size and the families: (origin y, cell w, cell h, columns), in pixels.
const vec2 ATLAS = vec2(2048.0, 3072.0);
const vec4 FAMS[6] = vec4[](
	vec4(0.0, 512.0, 128.0, 4.0),     // 0 TENANT
	vec4(768.0, 512.0, 256.0, 4.0),   // 1 NAME
	vec4(1536.0, 256.0, 256.0, 8.0),  // 2 VINYL
	vec4(2048.0, 512.0, 128.0, 4.0),  // 3 BANNER
	vec4(2304.0, 128.0, 384.0, 16.0), // 4 LAMPB
	vec4(2688.0, 128.0, 192.0, 16.0)  // 5 PLATE
);

varying flat vec4 v_custom;
varying vec3 v_world;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	int code = int(round(COLOR.a * 20.0));
	if (code == 14) {
		// Fabric: the free edge sways about the instance's own z (the banner's normal), phased by
		// where the instance stands so a street of banners does not move in step.
		vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float ph = o.x * 0.37 + o.z * 0.51 + COLOR.g * 6.28;
		float w = 0.35 + clamp(wind_factor, 0.0, 2.0);
		float s = sin(TIME * 1.6 + ph) + 0.45 * sin(TIME * 3.3 + ph * 1.7) + 0.2 * sin(TIME * 7.1 + ph * 2.3);
		VERTEX.z += COLOR.r * sway * w * s;
		NORMAL = normalize(NORMAL + vec3(-COLOR.r * sway * w * s * 0.8, 0.0, 0.0));
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// The family and cell index a slot names.
ivec2 sg_cell(int slot, vec4 c) {
	int a = int(c.r + 0.5);
	int b = int(c.g + 0.5);
	if (slot == 1) return ivec2(0, a % 4);
	if (slot >= 2 && slot <= 7) return ivec2(0, 4 + (b + (slot - 2) * 7) % 20);
	if (slot == 8) return ivec2(1, a % 12);
	if (slot == 9) return ivec2(5, b % 32);
	if (slot == 10) return ivec2(5, (b + 1) % 32);
	if (slot == 11) return ivec2(2, a % 16);
	if (slot == 12) return ivec2(3, a % 8);
	if (slot == 13) return ivec2(4, a % 16);
	if (slot == 14) return ivec2(5, a % 32);
	return ivec2(3, b % 8);
}

// The atlas texel of a printed face: its slot's cell, the face's 0..1 kept a filter's footprint
// inside the cell so mips do not reach the next one.
vec4 sg_sample(vec2 uv) {
	int slot = int(floor(uv.x * 0.5 + 0.0005));
	vec2 f = vec2(uv.x - float(slot) * 2.0, uv.y);
	ivec2 fc = sg_cell(slot, v_custom);
	vec4 fam = FAMS[fc.x];
	float col = mod(float(fc.y), fam.w);
	float row = floor(float(fc.y) / fam.w);
	vec2 size = fam.yz;
	vec2 px = f * size;
	vec2 foot = max(fwidth(px), vec2(1.0));
	vec2 margin = min(foot * 0.6, size * 0.25);
	px = clamp(px, margin, size - margin);
	vec2 a = (vec2(col, row) * size + vec2(0.0, fam.x) + px) / ATLAS;
	return texture(atlas, a);
}

void fragment() {
	int code = int(round(COLOR.a * 20.0));
	float lamp = clamp(lamp_factor, 0.0, 1.0);
	vec3 albedo = cs_srgb_to_linear(COLOR.rgb);
	vec3 emit = vec3(0.0);
	float rough = UV2.x;
	float metal = UV2.y;
	float alpha = 1.0;
	int flags = int(v_custom.b + 0.5);
	if (code == 4) {
		// A lightbox: the acrylic's print, lit from behind (brighter in the middle of the box).
		vec4 t = sg_sample(UV);
		vec3 c = cs_in(t.rgb);
		float vy = UV.y;
		float hot = 0.85 + 0.15 * sin(clamp(vy, 0.0, 1.0) * 3.14159);
		albedo = c * 0.85;
		emit = c * hot * mix(box_day, box_night, lamp);
		rough = 0.28;
		metal = 0.0;
	} else if (code == 6 || code == 7) {
		bool lit = code == 6 || (flags % 2) == 1;
		float on = lit ? 1.0 : 0.0;
		if (lit && (flags / 2) % 2 == 1) {
			// A failing tube: mostly on, dropping out in bursts.
			float t = TIME * 9.0 + v_custom.a * 50.0;
			on = step(0.18, fract(sin(floor(t)) * 43758.5)) * step(0.3, fract(sin(floor(TIME * 0.7 + v_custom.a * 9.0)) * 1373.1) + 0.5);
		}
		albedo = albedo * neon_glass;
		emit = cs_srgb_to_linear(COLOR.rgb) * on * mix(neon_day, neon_night, lamp);
		rough = 0.15;
		metal = 0.0;
	} else if (code == 8) {
		// A chasing bulb: two of every three lit, the gap running along the arrow.
		float idx = floor(UV.x + 0.5);
		float step_n = floor(TIME * chase_rate + v_custom.a * 7.0);
		float on = mod(idx - step_n, 3.0) < 0.5 ? 0.0 : 1.0;
		albedo = vec3(0.9, 0.85, 0.7) * 0.4;
		emit = cs_srgb_to_linear(COLOR.rgb) * on * mix(bulb_day, bulb_night, lamp);
		rough = 0.2;
	} else if (code == 10 || code == 12 || code == 14) {
		vec4 t = sg_sample(UV);
		vec3 c = cs_in(t.rgb);
		albedo = c;
		if (code == 10) {
			// Plates: reflective sheeting, a glint back toward the camera at night.
			rough = 0.45;
			metal = 0.0;
			float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
			emit = c * plate_retro * lamp * pow(facing, 6.0);
		} else if (code == 12) {
			alpha = t.a;
			rough = 0.22;
			metal = 0.0;
			emit = c * vinyl_night * lamp;
		} else {
			rough = 0.82;
			metal = 0.0;
			// A little light through the fabric when the sun is behind it.
			BACKLIGHT = cs_out(c * 0.25);
		}
	} else if (code == 16) {
		// A small fixture: the gooseneck lamps over a pole sign, a lit LED strip.
		albedo = vec3(0.6);
		emit = cs_srgb_to_linear(COLOR.rgb) * mix(0.05, 4.0, lamp);
		rough = 0.3;
	} else if (code == 2) {
		// Galvanised or painted steel with streaks running down it.
		float n = fract(sin(dot(floor(v_world.xz * 3.0 + v_world.y * 0.4), vec2(12.9898, 78.233))) * 43758.5453);
		albedo *= 0.88 + 0.16 * n;
	}
	ALBEDO = cs_out(albedo);
	EMISSION = cs_out(emit);
	ROUGHNESS = rough;
	METALLIC = metal;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
