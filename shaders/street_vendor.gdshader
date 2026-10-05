shader_type spatial;
render_mode cull_back;

// Street vendors (scripts/world/street_vendors.gd): taco trucks, fruit and elote carts, bacon-
// wrapped hot dog carts, paleta push carts, flower and balloon sellers. One material for all of
// it, so each kind is one MultiMesh draw a chunk.
//
// * Vertex colour alpha says what a face is (StreetVendors.A_*): 0 the vertex colour is the
//   colour, 1 the instance's paint (INSTANCE_CUSTOM.rgb), and in between brushed stainless,
//   umbrella canvas (stripes of INSTANCE_CUSTOM.rgb and CANVAS2[INSTANCE_CUSTOM.a * 8], by the
//   angle round the pole), a lightbox face (lit after dark), printed food pictures, the lit inside of a truck,
//   bulbs, glass, food, an LED strip. The codes sit 0.05 apart so 8-bit vertex colours keep them.
// * UV2 is (roughness, metallic) per part. UV is metres on solid parts and 0..1 (plus a whole
//   number that picks the picture) on printed faces.
// * Colour space: vertex colours and instance data arrive raw on both renderers and are authored
//   sRGB; everything is worked in linear and handed over with cs_out() (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

// How bright a lightbox (menu board, truck sign) burns at full night, and by day.
uniform float glow_night = 2.4;
uniform float glow_day = 0.18;
// The lit inside of a truck seen through its serving window.
uniform float interior_night = 3.2;
uniform float interior_day = 0.55;
// Bulb strings and LED strips.
uniform float bulb_night = 9.0;
uniform float bulb_day = 0.35;
uniform float led_night = 5.0;
// Brushed stainless: how strong the grain is in the roughness.
uniform float steel_grain = 0.35;
// Road grime creeping up from the pavement (metres) and how dark it gets.
uniform float grime_height = 0.35;
uniform float grime = 0.3;

// StreetVendors.CANVAS[i][1], sRGB.
const vec3 CANVAS2[6] = vec3[](vec3(0.95, 0.93, 0.86), vec3(0.96, 0.94, 0.88), vec3(0.1, 0.45, 0.25),
	vec3(0.97, 0.88, 0.3), vec3(0.95, 0.5, 0.12), vec3(0.1, 0.35, 0.75));

varying vec3 v_local;
varying float v_mode;
varying vec3 v_paint;
varying vec3 v_paint2;
varying float v_seed;

float sv_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float sv_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(sv_hash(i), sv_hash(i + vec2(1.0, 0.0)), f.x),
		mix(sv_hash(i + vec2(0.0, 1.0)), sv_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_local = VERTEX;
	v_mode = COLOR.a;
	v_paint = INSTANCE_CUSTOM.rgb;
	v_seed = INSTANCE_CUSTOM.a;
	// The canvas's second stripe: one of CANVAS2, picked by the umbrella's INSTANCE_CUSTOM.a
	// (StreetVendors.CANVAS's second colours; the instance COLOR multiplies every vertex colour,
	// so it cannot carry it).
	v_paint2 = CANVAS2[clamp(int(INSTANCE_CUSTOM.a * 8.0 + 0.5), 0, 5)];
}

// A printed food picture, uv 0..1, `pick` which one: a plate shot on a coloured ground (the way
// a truck's menu shows its tacos, a paleta cart its flavours).
vec3 sv_photo(vec2 uv, float pick) {
	float h = sv_hash(vec2(pick, 3.7));
	vec3 ground = mix(vec3(0.95, 0.88, 0.62), vec3(0.85, 0.25, 0.12), step(0.5, h));
	ground = mix(ground, vec3(0.16, 0.42, 0.24), step(0.8, h));
	vec2 p = uv - vec2(0.5, 0.55);
	float n = sv_noise(uv * 9.0 + pick * 5.0);
	// A plate or a tortilla, and the food heaped on it.
	float plate = 1.0 - smoothstep(0.36, 0.4, length(p * vec2(1.0, 1.6)));
	vec3 food = mix(vec3(0.55, 0.26, 0.1), vec3(0.85, 0.62, 0.3), n);
	food = mix(food, vec3(0.2, 0.55, 0.15), step(0.78, sv_noise(uv * 23.0 + pick)));
	food = mix(food, vec3(0.8, 0.12, 0.08), step(0.85, sv_noise(uv * 19.0 + pick * 2.0)));
	float heap = 1.0 - smoothstep(0.18, 0.26, length(p * vec2(1.0, 2.2) + vec2(0.0, 0.03)));
	vec3 col = mix(ground, vec3(0.92, 0.9, 0.84), plate);
	col = mix(col, food, heap);
	// A white price flash in the corner.
	float flash = step(0.68, uv.x) * step(uv.y, 0.26);
	return mix(col, vec3(0.97, 0.95, 0.9), flash * 0.9);
}

// A paleta cart's side: rows of ice pops on sticks in their flavours' colours.
vec3 sv_paletas(vec2 uv, float pick) {
	vec3 bg = vec3(0.93, 0.93, 0.9);
	vec2 cell = vec2(uv.x * 6.0, uv.y * 2.0);
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	float h = sv_hash(id + pick * 3.1);
	vec3 flavour = h < 0.2 ? vec3(0.85, 0.12, 0.2) : (h < 0.4 ? vec3(0.95, 0.75, 0.15) :
		(h < 0.6 ? vec3(0.35, 0.7, 0.25) : (h < 0.8 ? vec3(0.55, 0.32, 0.18) : vec3(0.95, 0.55, 0.65))));
	float pop = step(0.3, f.x) * step(f.x, 0.7) * step(0.12, f.y) * step(f.y, 0.7);
	float round_top = 1.0 - smoothstep(0.17, 0.2, length((f - vec2(0.5, 0.2)) * vec2(1.0, 1.3)));
	pop = max(pop, round_top * step(f.y, 0.3));
	float stick = step(0.46, f.x) * step(f.x, 0.54) * step(0.7, f.y) * step(f.y, 0.92);
	vec3 col = mix(bg, flavour, pop);
	col = mix(col, vec3(0.8, 0.68, 0.48), stick);
	// A painted band along the top with the cart's colour.
	return mix(col, v_paint, step(uv.y, 0.06) + step(0.96, uv.y));
}

void fragment() {
	int code = int(round(v_mode * 20.0));
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float rough = UV2.x;
	float metal = UV2.y;
	vec3 emit = vec3(0.0);
	float lamp = clamp(lamp_factor, 0.0, 1.0);
	if (code == 20) {
		base = cs_srgb_to_linear(v_paint);
		// Paint gets a faint orange-peel and a little chalking on the upper panels.
		base *= 0.94 + 0.06 * sv_noise(UV * 7.0 + v_seed * 31.0);
	} else if (code == 2) {
		// Brushed stainless: grain running along the panel, a few scuffs.
		// Fine grain fades to its mean once a streak is under a pixel (it aliased into bands).
		float fw = fwidth(UV.y) * 60.0;
		float g = mix(sv_noise(vec2(UV.x * 1.2, UV.y * 60.0) + v_seed * 11.0), 0.5, smoothstep(0.3, 1.0, fw));
		float scuff = smoothstep(0.75, 0.95, sv_noise(UV * 5.0 + 3.0 + v_seed * 7.0));
		rough = clamp(rough + (g - 0.5) * steel_grain * 0.5 + scuff * 0.2, 0.08, 0.9);
		base *= 0.95 + 0.06 * g;
	} else if (code == 4) {
		// Umbrella canvas: eight panels round the pole, alternating the two colours, a lighter
		// edge band at the rim (the valance).
		float a = atan(v_local.z, v_local.x);
		float panel = floor((a + 3.14159265) / 6.2831853 * 8.0 + 0.5);
		vec3 c1 = cs_srgb_to_linear(v_paint);
		vec3 c2 = cs_srgb_to_linear(v_paint2);
		base = mod(panel, 2.0) < 0.5 ? c1 : c2;
		float weave = sv_noise(UV * 140.0);
		base *= 0.93 + 0.1 * weave;
		// Sun bleaching toward the top.
		base = mix(base, vec3(dot(base, vec3(0.33))), 0.12 * smoothstep(0.0, 0.5, v_local.y - 2.0));
		rough = 0.85;
	} else if (code == 6) {
		// A lightbox face: printed by day, lit from behind after dark.
		emit = base * mix(glow_day, glow_night, lamp);
		rough = 0.35;
	} else if (code == 7) {
		float pick = floor(UV.x);
		vec2 uv = fract(UV);
		base = cs_srgb_to_linear(pick >= 40.0 ? sv_paletas(uv, pick) : sv_photo(uv, pick));
		emit = base * mix(glow_day, glow_night, lamp) * (pick >= 40.0 ? 0.0 : 1.0);
		rough = 0.3;
	} else if (code == 9) {
		// The lit inside of a truck: fluorescent tubes on stainless, always a little lit (the
		// day outside is brighter than it, so it reads dim), bright after dark.
		emit = base * mix(interior_day, interior_night, lamp);
	} else if (code == 11) {
		emit = base * mix(bulb_day, bulb_night, lamp);
		rough = 0.2;
	} else if (code == 13) {
		base = cs_srgb_to_linear(COLOR.rgb);
		rough = 0.06;
	} else if (code == 15) {
		// Food: fresh and a little wet; a broken tone so a heap is not one flat colour.
		base *= 0.85 + 0.3 * sv_noise(UV * 37.0 + v_local.xz * 11.0);
	} else if (code == 17) {
		emit = base * mix(0.2, led_night, lamp);
	}
	// Grime from the pavement, on everything but the lights and the canvas up in the air.
	if (code != 11 && code != 17 && code != 4) {
		float gh = clamp(1.0 - v_local.y / grime_height, 0.0, 1.0);
		float n = sv_noise(v_local.xz * 4.0 + v_local.y * 3.0 + v_seed * 13.0);
		base *= 1.0 - grime * gh * (0.5 + 0.5 * n);
	}
	ALBEDO = cs_out(base);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
	if (code == 4) {
		// Canvas lets the sun through: lit from above, a striped glow from below.
		BACKLIGHT = cs_out(base * 0.5);
	}
}
