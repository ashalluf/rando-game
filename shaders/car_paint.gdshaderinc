// The body of shaders/car_paint.gdshader, shared with shaders/car_paint_damage.gdshader.
// Everything between `#ifdef CAR_DAMAGE` and its `#endif` only exists in the damage variant, so
// an undamaged car compiles exactly the shader it always did (Vehicle.take_hit swaps a car onto
// the damage variant the first time it is hit; see scripts/vehicles/car_damage.gd).

// Car paint over a single-material model whose base color was greyscaled: light pixels are
// bodywork and take the paint, dark pixels are glass, tires and trim and stay dark. Keeps one
// texture set per model.
//
// Realism pass (owner, 2026-09-20: "look like an industry giant made it"): real automotive
// paint is a metallic basecoat under a clear lacquer. That gives two highlights, not one - a
// broad soft one from the flake layer and a tight bright one from the lacquer - plus a fresnel
// rim that brightens sharply at grazing angles. Flat "metallic + roughness" paint is the main
// reason game cars read as plastic toys.
//
// Colour pass (owner, 2026-09-21: "more color and more gta"): the same shader now also carries
// the finish (gloss / metallic / pearl / deep / matte) and a livery graphic painted in body
// space - racing stripes, a two-tone lower body, a fleet belt band, a taxi checker. All of it
// is uniforms, so a whole city of cars is still one shader and one texture set per model.
#include "res://shaders/lod_blend.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform vec3 paint : source_color = vec3(0.8, 0.1, 0.1);
// Luminance below which a pixel counts as glass or rubber, and above which it is bodywork.
uniform float dark_below = 0.16;
uniform float body_above = 0.38;
uniform float paint_metallic = 0.7;
uniform float paint_roughness = 0.22;
uniform float paint_brightness = 1.35;
// Strength of the clear lacquer over the basecoat. Matte paint sets this to 0; the glass keeps
// its own lacquer through glass_clearcoat so a matte car still has shiny windows.
uniform float clearcoat_amount = 0.85;
uniform float clearcoat_roughness_value = 0.035;
uniform float glass_clearcoat = 0.85;
// Metallic flake: fine sparkle in the basecoat, only visible up close.
uniform float flake_strength = 0.045;
uniform float flake_scale = 190.0;
// Flake is only resolvable up close; past this many meters it is dropped, otherwise the
// sub-pixel grid aliases into crawling glitter over the whole panel.
uniform float flake_fade_distance = 9.0;

// Pearl: a second coat whose colour only shows at grazing angles, which is the whole trick of
// a pearlescent finish. 0 turns it off, so a plain metallic pays nothing but one mix.
uniform vec3 pearl_color : source_color = vec3(1.0);
uniform float pearl_amount = 0.0;
uniform float pearl_power = 2.5;

// Livery graphic, painted in body space so it works on any of the car models without needing
// per-model UV layouts. 0 none, 1 twin racing stripes over the length, 2 two-tone lower body,
// 3 fleet belt band round the flanks, 4 taxi checker band, 5 police black-and-white (the second
// colour over the doors and the roof, the base paint on the nose, the tail and the sills), 6 a
// contrast roof (everything over `stripe_height` - the pillars and the roof - the second colour).
uniform int stripe_mode : hint_range(0, 6) = 0;
uniform vec3 stripe_color : source_color = vec3(0.92, 0.92, 0.93);
// Half width of a stripe / band, as a fraction of the car's width (mode 1) or height (2, 3, 4).
uniform float stripe_width = 0.032;
// Distance of each racing stripe from the centre line, as a fraction of the car's width.
uniform float stripe_gap = 0.055;
// Height of the band or the two-tone split, as a fraction of the car's height.
uniform float stripe_height = 0.42;
// Checks along the length of the car (mode 4).
uniform float checker_repeat = 44.0;
// Police livery (mode 5): the stretch of the car, as fractions of its length, that the doors
// cover, the height the roof starts at, and the sill line below which it stays the base paint.
uniform vec2 door_band = vec2(0.24, 0.70);
uniform float roof_from = 0.84;
uniform float sill_line = 0.20;
// Decals and vinyl are never as glossy as the paint under them.
uniform float stripe_roughness_mul = 1.25;

// The model's untransformed bounding box, so the fragment shader can work in normalised body
// space (0..1 along the car, up, and across it). Set by Vehicle._add_body_model(); the defaults
// are harmless because stripe_mode is 0 unless a livery was asked for.
uniform vec3 body_min = vec3(-1.0);
uniform vec3 body_size = vec3(2.0);
uniform bool length_is_x = true;

// Glass found from the shape, for models whose texture does not mark it. On three of the four
// everyday car models the windows are as light as the doors in the greyscaled texture (the
// pickup's darkest 5 % of texels is 0.33, the van's 0.49), so the paint covered the glass and
// every white car on the street was one pale shape - an ice sculpture. Car glass sits above the
// belt line and is tilted (the screens steeply, the side glass a little inward), where the roof
// and the bonnet face straight up and the door skins stand vertical, so height plus slope finds
// it. `geo_glass` is off for the models with real glass slots or a texture that marks it.
uniform bool geo_glass = false;
// Height of the belt line (the bottom of the side glass) as a fraction of the body's height.
uniform float beltline = 0.56;
// Slope band that counts as glass: the up-component of the body-space normal.
uniform float glass_slope_min = 0.10;
uniform float glass_slope_max = 0.86;
// Where along the body (body_uv.x, 0..1) glass can be. The van is a panel van: behind the cab
// its flanks are sheet metal whose top turns in exactly like side glass, and once the body was
// shaded smooth the slope test painted a dark band the length of it.
uniform vec2 glass_span = vec2(0.0, 1.0);
// How much of the lacquer's reflection survives where it would see the city rather than the sky:
// reflected rays within `canyon_rise` of level. The radiance map is the open sky in every
// direction, but a car door in a street reflects the buildings opposite, which are far darker
// than the pale horizon - with the whole coat there, every car side took a pale-blue sheen.
uniform float canyon_reflect = 0.4;
uniform float canyon_rise = 0.45;
// Inside the reflection probes' reach (ReflectionProbes, Forward+; 0 = none) the radiance a door
// mirrors IS the street, so the coat is handed back in full there: dimming a real reflection of
// dark facades a second time made them black.
global uniform float probe_reach;
global uniform vec3 sun_direction;
global uniform float night_factor;
global uniform vec3 origin_shift;
global uniform float lamp_factor;
global uniform vec4 sky_tint;

#ifdef CAR_DAMAGE
#include "res://shaders/car_damage.gdshaderinc"
#include "res://shaders/car_crumple.gdshaderinc"
// Bullet holes: xyz the centre in mesh space, w the radius (mesh units). The first hole_count
// entries are live; CarDamage recycles the oldest past the cap.
uniform int hole_count = 0;
uniform vec4 holes[40];
// Dents: xyz the centre, w the radius; dent_push xyz is how far and which way the metal moved at
// the centre (mesh units), w a seed for the crumple.
uniform int dent_count = 0;
uniform vec4 dents[8];
uniform vec4 dent_push[8];
// Fire: 0 untouched .. 1 burnt out, the burn front spreading from burn_origin (the engine bay)
// out to burn_reach (mesh units).
uniform float burnt = 0.0;
uniform vec3 burn_origin = vec3(0.0);
uniform float burn_reach = 0.0;
// Blast scorch on the side that faced it: xyz centre, w radius.
uniform int scorch_count = 0;
uniform vec4 scorches[4];
// Soot on the panels round the engine bay while it smokes, 0..1.
uniform float smoke_stain = 0.0;
// Glass on a single-texture body (found by its dark texels): cracks (xyz centre, w radius) and
// which sides have lost theirs (x toward glass_front, y away from it, z toward glass_left, w away).
uniform int crack_count = 0;
uniform vec4 cracks[8];
uniform vec4 glass_gone = vec4(0.0);
uniform vec3 glass_front = vec3(0.0, 0.0, -1.0);
uniform vec3 glass_left = vec3(-1.0, 0.0, 0.0);
// Mesh-space position and normal before any dent, so the marks stay where they were made.
varying vec3 local_rest;
varying vec3 local_nrm;
// How far this vertex is on a panel turned well open (cr_open_w), and where the crash moved it:
// a triangle stretched across the panel's edge is cut (cr_torn()).
varying float cr_gap;
varying vec3 cr_moved;


// How far the dents move a point of the mesh.
vec3 cd_dent_offset(vec3 p) {
	vec3 o = vec3(0.0);
	for (int i = 0; i < dent_count && i < 8; i++) {
		vec3 d = p - dents[i].xyz;
		float r = max(dents[i].w, 0.01);
		float x2 = dot(d, d) / (r * r);
		if (x2 < 1.0) {
			float f = 1.0 - x2;
			f *= f;
			// Sheet metal buckles, it does not dimple: wrinkles a fifth of the dent across.
			float crumple = 0.65 + 0.7 * cd_noise3(p * (5.0 / r) + dent_push[i].w * 17.0);
			o += dent_push[i].xyz * f * crumple;
		}
	}
	return o;
}
#endif

// An old car's wear (the beater: Vehicle.BEATER_*), 0 on every other car, which skips all of it.
// Positions are the body MESH's own space (x across, y up, z along with the nose at -z): a door
// from another car (`wear_door`: z0, z1, y0, y1 on the side whose x has the sign of
// `wear_door_side`, in `wear_door_color`), a patch of grey primer (`wear_primer`: z, y, radius,
// side), the clear coat gone chalky on what faces the sky, and rust low on the sills.
uniform float wear = 0.0;
uniform vec4 wear_door = vec4(0.0);
uniform float wear_door_side = -1.0;
uniform vec3 wear_door_color : source_color = vec3(0.5);
uniform vec4 wear_primer = vec4(0.0, 0.0, 0.0, 1.0);
varying vec3 paint_rest;
#ifdef PAINT_FROM_CUSTOM
// A MultiMesh of static parked bodies (car_park_car.gdshader): the paint per instance, sRGB.
varying vec3 inst_paint;
#endif

// Custom paint (the lowriders: Lowrider.paint()), 0 on every other car, which skips all of it.
// Candy: a tinted lacquer over a bright base, so the colour runs deep where the panel turns away
// (a longer path through the tint, `candy_deep`) and glows face on; big metal flake fixed to the
// body and catching the light flake by flake as you move; hand-laid pinstripes in body MESH space
// (x across, y up, z along with the nose at -z): a double line down each flank at `pin_side`.x
// from z .y to .z, scrolls on the bonnet (`pin_hood`: z at the cowl, z at the nose, the top's
// lowest y, the body's half width) and the deck lid (`pin_deck`), and a patterned roof panel
// (`pin_roof`: z front, z rear, half width, lowest y) in `pattern_color` inside a pinstriped edge.
uniform float custom = 0.0;
uniform vec3 candy_deep : source_color = vec3(0.10, 0.0, 0.02);
uniform vec3 flake_tint : source_color = vec3(1.0);
uniform vec3 pin_color : source_color = vec3(0.95, 0.80, 0.35);
uniform vec3 pattern_color : source_color = vec3(0.75, 0.75, 0.78);
uniform vec4 pin_side = vec4(0.0);
uniform vec4 pin_hood = vec4(0.0);
uniform vec4 pin_deck = vec4(0.0);
uniform vec4 pin_roof = vec4(0.0);
// Which scroll family the painter laid (0..3) and how much of the roof is patterned (0 none).
uniform float pin_style = 0.0;
uniform float pattern_amount = 0.0;

// Road grime, mud and clear-coat scratches (CarDetail, per car on its own paint material; 0
// skips the whole block). grime_arch: the front and rear axles along the body and the hub
// height, then the tyre radius, all in mesh units; grime_frame: the body's bottom (mesh y),
// metres per mesh unit, and which way along is the tail (+1 / -1).
uniform float grime = 0.0;
uniform float mud = 0.0;
uniform float scratches = 0.0;
uniform vec4 grime_arch = vec4(-1.4, 1.4, 0.2, 0.34);
uniform vec3 grime_frame = vec3(-0.2, 1.0, 1.0);

// Paint, second pass (car-paint-2, docs/HANDOFF.md "Car paint that reads as photographed"). 0 on
// every material Vehicle did not set up (CAR_PAINT_2=0 too), which skips all of it, so that path
// is the old shader bit for bit. `peel` is the orange peel in the lacquer (its amplitude: 0 none,
// 1 a factory coat); `sparkle` the strength of the flake glints worked out per pixel-sized cell
// (fixed to the body, so a moving car carries them); `candy_amount` a tinted lacquer over a bright
// base (`candy_deep` the colour the panel runs to where it turns away); `wrap` a satin vinyl wrap
// (a soft broad sheen, no flake); `oxidize` a single-stage paint gone chalky and its clear coat
// peeling on what faces the sun; `dust_film` a film of dust (or pollen: `dust_tint`) settled on
// the roof, bonnet and boot; `skyline` how much the lacquer's mirror is cut where a reflected ray
// would meet a building (a world-fixed skyline per azimuth), which is what puts the hard horizon
// line of a street across a car door.
uniform float paint2 = 0.0;
uniform float peel = 0.0;
uniform float sparkle = 0.0;
uniform float candy_amount = 0.0;
uniform float wrap = 0.0;
uniform float oxidize = 0.0;
uniform float dust_film = 0.0;
uniform vec3 dust_tint : source_color = vec3(0.60, 0.56, 0.49);
uniform float skyline = 0.0;
// (road_wetness comes from wet_surface.gdshaderinc.)

varying vec3 world_pos;
// x = along the car, y = up, z = across, all 0..1 over the body's bounding box.
varying vec3 body_uv;
// x = 1 on the flanks, 0 on the roof, nose and tail. y = 1 on horizontal surfaces.
varying vec2 facing;
// The up-component of the body-space normal (signed: 1 roof, 0 door skin, -1 underside).
varying float body_ny;
// The body mesh's own normal (the rain's beads and runs are laid out in its frame).
varying vec3 wet_nrm;

#include "res://shaders/wet_surface.gdshaderinc"
#include "res://shaders/specular_aa.gdshaderinc"


// A display (sRGB) colour in the space `paint` arrives in (a source_color uniform: decoded on
// Forward+, raw on Compatibility), for the grime's constants.
vec3 grime_col(vec3 srgb) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return srgb;
#else
	return mix(srgb / 12.92, pow((srgb + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), srgb));
#endif
}


float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}


float wear_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}


// Distance (metres) from (u, s) to the curve u = f(s) of a scroll family, s metres along a panel of
// length len from its back edge. Each family is a few curves with a curl at each end.
float lr_curve(float fam, float k, float t, float w) {
	// t 0..1 along the panel (0 the back edge, 1 the front), w the half width there is room for.
	float a = 1.0 - t;
	if (fam < 0.5) {
		// Two long lines sweeping in from the corners to a point.
		return (k < 0.5) ? 0.035 + w * 0.62 * pow(a, 1.25) : 0.018 + w * 0.40 * pow(a, 1.7) + 0.022 * sin(t * 15.7) * a;
	} else if (fam < 1.5) {
		// Waves: the classic flowing double scroll.
		return (k < 0.5) ? 0.05 + w * (0.30 + 0.18 * sin(t * 9.4)) * a : 0.03 + w * (0.20 + 0.12 * sin(t * 9.4 + 1.3)) * a;
	} else if (fam < 2.5) {
		// A long spear with a step.
		return (k < 0.5) ? 0.03 + w * 0.50 * smoothstep(1.0, 0.15, t) : 0.012 + w * 0.32 * smoothstep(0.95, 0.25, t);
	}
	// Fans: three short lines.
	return 0.02 + w * (0.18 + 0.20 * k) * pow(a, 0.9) * (1.0 + 0.3 * sin(t * 12.0 + k));
}


float lr_scroll(vec2 q, float len, float w, float fam, float px) {
	// q.x = |x| across, q.y = metres from the back edge (0..len). The distance to each curve,
	// divided by the slope so the line keeps its width where it runs steeply across.
	if (q.y < 0.0 || q.y > len) {
		return 0.0;
	}
	float t = q.y / max(len, 0.01);
	float cov = 0.0;
	float lw = 0.0024;
	for (int i = 0; i < 2; i++) {
		float k = float(i);
		float e = 0.01;
		float f = lr_curve(fam, k, t, w);
		float d1 = (lr_curve(fam, k, min(t + e, 1.0), w) - lr_curve(fam, k, max(t - e, 0.0), w)) / (2.0 * e * len);
		float d = abs(q.x - f) / sqrt(1.0 + d1 * d1);
		// The line fades in from its two ends (the brush lifting off).
		float ends = smoothstep(0.03, 0.12, t) * smoothstep(0.97, 0.86, t);
		cov = max(cov, (1.0 - smoothstep(lw - px, lw + px, d)) * ends);
	}
	// A teardrop at the point and a curl at each back corner.
	float tip = abs(length(vec2(q.x, (q.y - len * 0.90) * 0.7)) - 0.030);
	cov = max(cov, 1.0 - smoothstep(lw - px, lw + px, tip));
	float curl = abs(length(vec2(q.x - (0.035 + w * 0.62) - 0.035, q.y - len * 0.06)) - 0.035);
	cov = max(cov, (1.0 - smoothstep(lw - px, lw + px, curl)) * step(fam, 0.5));
	return cov * clamp(lw * 2.0 / max(px, 1e-5), 0.0, 1.0) * 1.6;
}


void vertex() {
	vec3 rest_pos = VERTEX;
	vec3 rest_nrm = NORMAL;
#ifdef CAR_DAMAGE
	local_rest = VERTEX;
	local_nrm = NORMAL;
	cr_gap = panel_count > 0 ? cr_open_w(VERTEX) : 0.0;
	cr_moved = VERTEX;
	if (dent_count > 0 || cr_any()) {
		// The normal of the dented (and crushed: car_crumple.gdshaderinc) surface, from where
		// two points either side moved to.
		vec3 t;
		vec3 b;
		cd_frame(normalize(NORMAL), t, b);
		float e = 0.025;
		vec3 n0 = NORMAL;
		vec3 o0 = cr_move(VERTEX, n0) + cd_dent_offset(VERTEX);
		vec3 nt = cr_move(VERTEX + t * e, n0) + cd_dent_offset(VERTEX + t * e) - o0;
		vec3 nb = cr_move(VERTEX + b * e, n0) + cd_dent_offset(VERTEX + b * e) - o0;
		vec3 nn = cross(nb, nt);
		if (dot(nn, NORMAL) < 0.0) {
			nn = -nn;
		}
		NORMAL = normalize(nn);
		VERTEX = o0;
		cr_moved = o0;
	}
#endif
#ifdef PAINT_FROM_CUSTOM
	inst_paint = INSTANCE_CUSTOM.rgb;
#endif
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	paint_rest = rest_pos;
	vec3 n = (rest_pos - body_min) / max(body_size, vec3(0.001));
	vec3 nrm = normalize(rest_nrm);
	body_uv = length_is_x ? n : vec3(n.z, n.y, n.x);
	facing = vec2(length_is_x ? abs(nrm.z) : abs(nrm.x), abs(nrm.y));
	body_ny = nrm.y;
	wet_nrm = nrm;
}


// How much of this fragment is livery rather than base paint.
float livery_mask() {
	if (stripe_mode == 0) {
		return 0.0;
	}
	float feather = 0.004;
	if (stripe_mode == 1) {
		// Twin racing stripes: a band either side of the centre line, wrapping over the nose,
		// the bonnet, the roof and the tail because it is a pure lateral test.
		float lat = abs(body_uv.z - 0.5);
		return 1.0 - smoothstep(stripe_width - feather, stripe_width + feather, abs(lat - stripe_gap));
	}
	if (stripe_mode == 2) {
		// Two-tone: everything below the split line is the second colour.
		return 1.0 - smoothstep(stripe_height - feather, stripe_height + feather, body_uv.y);
	}
	if (stripe_mode == 5) {
		// Black and white: white doors between the wheel arches, white roof, black nose, tail
		// and sills. Pure body-space tests, so it lands on any of the car models.
		float doors = smoothstep(door_band.x - feather, door_band.x + feather, body_uv.x)
			* (1.0 - smoothstep(door_band.y - feather, door_band.y + feather, body_uv.x))
			* smoothstep(sill_line - feather, sill_line + feather, body_uv.y);
		float roof = smoothstep(roof_from - 0.01, roof_from + 0.01, body_uv.y) * smoothstep(0.6, 0.85, facing.y);
		return max(doors, roof);
	}
	if (stripe_mode == 6) {
		// Contrast roof: the glasshouse's pillars and the roof over the belt line, the
		// "floating roof" of a crossover or a city car. Nothing low that faces the sky (the
		// bonnet and the boot sit under the line on every body it is rolled for).
		return smoothstep(stripe_height - feather, stripe_height + feather, body_uv.y);
	}
	float band = 1.0 - smoothstep(stripe_width - feather, stripe_width + feather, abs(body_uv.y - stripe_height));
	if (stripe_mode == 3) {
		// A fleet band wraps the flanks, the nose and the back doors but not anything the sky
		// can see: without this it paints a pickup's bed floor, which happens to sit at exactly
		// the height of the band on the doors.
		// Reviewed 2026-09-21, do not "fix" this by adding a facing.x test: the band is meant to
		// wrap the nose and the back doors, and a flanks-only test would cut both off. It cannot
		// leak into a cabin either, because nothing on a car in this game is see-through - this
		// shader writes no ALPHA and declares no blend mode, and every car .glb is alphaMode
		// OPAQUE with alpha-less JPEG textures, so a window is an opaque dark surface and not a
		// hole. Measured on car_van.glb and car_pickup.glb: two thirds of the band fragments
		// that pass the guard sit on the inner wall of the model's double shell and are never
		// rasterised, and every one visible from outside is bodywork (albedo luminance 0.42 and
		// up, body mask 1.0) on a flank or an end cap.
		return band * (1.0 - smoothstep(0.6, 0.9, facing.y));
	}
	// Taxi checker: two rows of checks along the flanks only, so it reads as a door decal
	// rather than a ribbon wrapped round the whole car.
	float row = floor((body_uv.y - (stripe_height - stripe_width)) / max(stripe_width, 0.0001));
	float col = floor(body_uv.x * checker_repeat);
	float check = mod(row + col, 2.0);
	return band * check * step(0.45, facing.x);
}


void fragment() {
	if (lod_blend_cut(FRAGCOORD.xy, VIEW_MATRIX, MODEL_MATRIX, IN_SHADOW_PASS)) {
		discard;
	}
	// Derivatives for the paint2 blocks, taken here in uniform control flow (llvmpipe returns 0
	// for fwidth inside a branch): metres on the body per pixel.
	float p2_ms = length(MODEL_MATRIX[0].xyz);
	float p2_fp = max(length(fwidth(paint_rest)) * p2_ms, 1e-6);
	// How fast the body's normal turns across a pixel (specular_aa.gdshaderinc), for the lacquer's
	// geometric AA at the end: a 0.035 coat on a wing's curve a few pixels wide is a sun glint
	// that jumps pixel to pixel as the car or the camera moves.
	vec3 saa_dnx = dFdx(NORMAL);
	vec3 saa_dny = dFdy(NORMAL);
#ifdef CAR_DAMAGE
	float cr_stretch = length(cross(dFdx(cr_moved), dFdy(cr_moved))) / max(length(cross(dFdx(local_rest), dFdy(local_rest))), 1e-14);
	if (cr_torn(cr_gap, cr_stretch)) {
		discard;
	}
#endif
#ifdef CAR_DAMAGE
#endif
	vec4 base = texture(albedo_tex, UV);
	float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float body = smoothstep(dark_below, body_above, lum);
	float shape_glass = 0.0;
	if (geo_glass) {
		// The bodies are shaded smooth across bends of up to 45 degrees
		// (tools/smooth_normals.py), so the normal no longer steps from face to face: it drifts
		// slowly through the glass band, and a fixed +-0.04 blend smeared the edge of a window
		// over a hand's width of panel.
		// The blend is one pixel wide instead, so the window edge is a crisp line wherever it
		// falls. (Classifying by the triangle's own normal was tried and brings the facets back
		// as a patchwork of glass triangles.)
		float slope_aa = max(fwidth(body_ny), 0.004);
		shape_glass = smoothstep(beltline - 0.02, beltline + 0.02, body_uv.y)
			* smoothstep(glass_slope_min - slope_aa, glass_slope_min + slope_aa, body_ny)
			* (1.0 - smoothstep(glass_slope_max - slope_aa, glass_slope_max + slope_aa, body_ny))
			* smoothstep(glass_span.x - 0.004, glass_span.x + 0.004, body_uv.x)
			* (1.0 - smoothstep(glass_span.y - 0.004, glass_span.y + 0.004, body_uv.x))
			// Not the top of the roof pillars' own panels: the last few percent is roof.
			* (1.0 - smoothstep(0.93, 0.97, body_uv.y));
		body *= 1.0 - shape_glass;
		// Tinted glass reads as dark from outside in daylight, whatever the texture said.
		lum = mix(lum, 0.02, shape_glass);
	}

	float livery = livery_mask();
#ifdef PAINT_FROM_CUSTOM
	vec3 coat = mix(cs_as_uniform(inst_paint), stripe_color, livery);
#else
	vec3 coat = mix(paint, stripe_color, livery);
#endif
	// Pearl flip: the second coat only shows where the panel turns away from the eye.
	if (pearl_amount > 0.0) {
		float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), pearl_power);
		coat = mix(coat, pearl_color, fres * pearl_amount * (1.0 - livery));
	}
	// Candy (paint2): a tinted lacquer over a bright base, so the colour runs deep where the
	// panel turns away (a longer path through the tint) and glows where it faces the eye.
	if (candy_amount > 0.0) {
		float cndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		coat = mix(coat, mix(candy_deep, coat, pow(cndv, 0.6)), candy_amount * (1.0 - livery));
	}
	// The beater's wear: which of its paint is another car's door, primer, chalky or rusty.
	float worn_rough = 0.0;
	float worn_coat = 0.0;
	if (wear > 0.0) {
		vec3 q = paint_rest;
		float aa = max(fwidth(q.z) + fwidth(q.y), 0.002);
		float door = step(0.0, q.x * wear_door_side)
			* smoothstep(wear_door.x - aa, wear_door.x + aa, q.z) * (1.0 - smoothstep(wear_door.y - aa, wear_door.y + aa, q.z))
			* smoothstep(wear_door.z - aa, wear_door.z + aa, q.y) * (1.0 - smoothstep(wear_door.w - aa, wear_door.w + aa, q.y));
		coat = mix(coat, wear_door_color, door * wear);
		// The rest of the car's own paint has faded toward a chalky pale of itself; the newer
		// door has not.
		float n1 = wear_noise(q * 2.3);
		float n2 = wear_noise(q * 9.0 + 3.1);
		float up = smoothstep(0.35, 0.85, body_ny);
		float chalk = up * smoothstep(0.38, 0.62, n1 * 0.75 + n2 * 0.25) * (1.0 - door) * wear;
		coat = mix(coat, mix(coat, vec3(dot(coat, vec3(0.3, 0.59, 0.11))), 0.5) * 0.85 + 0.12, 0.35 * (1.0 - door) * wear);
		coat = mix(coat, coat * 0.55 + vec3(0.30, 0.29, 0.27), chalk * 0.75);
		// A patch of grey primer with a sanded, feathered rim.
		vec2 pd = vec2(q.z, q.y) - wear_primer.xy;
		float pr = wear_primer.z * (0.8 + 0.4 * wear_noise(q * 6.0));
		float primer = step(0.0, q.x * wear_primer.w) * (1.0 - smoothstep(pr * 0.85, pr, length(pd * vec2(0.8, 1.25)))) * wear;
		float feather = step(0.0, q.x * wear_primer.w) * (1.0 - smoothstep(pr, pr * 1.25, length(pd * vec2(0.8, 1.25)))) * wear;
		coat = mix(coat, coat * 0.7 + 0.08, (feather - primer) * 0.6);
		coat = mix(coat, mix(vec3(0.36, 0.36, 0.34), vec3(0.44, 0.43, 0.41), n2), primer);
		// Rust blooms low on the sills and the arch edges.
		float rust = (1.0 - smoothstep(0.10, 0.20, body_uv.y)) * smoothstep(0.58, 0.78, wear_noise(q * 7.0) * 0.6 + n2 * 0.4) * wear;
		coat = mix(coat, mix(vec3(0.20, 0.08, 0.035), vec3(0.32, 0.15, 0.06), n2), rust);
		worn_rough = max(max(chalk, primer), rust);
		worn_coat = mix(0.55 * (1.0 - door), 1.0, worn_rough) * wear;
	}
	// Oxidised single-stage paint (paint2): what faces the sun has gone chalky and pale, and the
	// clear coat lifts off the roof and the bonnet in ragged sheets with a pale rim of loose
	// lacquer round each. Metres on the body, so it rides with the car.
	float ox_peel = 0.0;
	float ox_chalk = 0.0;
	if (oxidize > 0.0) {
		vec3 q = paint_rest * p2_ms;
		float up = smoothstep(0.25, 0.8, body_ny);
		float n1 = wear_noise(q * 1.7 + 4.2);
		float n2 = wear_noise(q * 6.5 + 1.3);
		float n3 = wear_noise(q * 23.0 + 8.8);
		ox_chalk = clamp(up * (0.55 + 0.45 * n1) + (1.0 - up) * 0.3 * n1, 0.0, 1.0) * oxidize;
		vec3 pale = mix(coat, vec3(dot(coat, vec3(0.3, 0.59, 0.11))), 0.5) * 0.78 + grime_col(vec3(0.42)) * 0.30;
		coat = mix(coat, pale, ox_chalk * 0.85);
		float field = n1 * 0.55 + n2 * 0.33 + n3 * 0.12;
		float th = mix(0.80, 0.52, oxidize);
		float aa = clamp(p2_fp * 8.0, 0.006, 0.2);
		ox_peel = smoothstep(th - aa, th + aa, field) * up * (1.0 - livery);
		float rim = (smoothstep(th - 0.045, th - aa, field) - ox_peel) * up;
		coat = mix(coat, pale * 0.9, ox_peel * 0.65);
		coat = mix(coat, grime_col(vec3(0.70, 0.69, 0.66)), clamp(rim, 0.0, 1.0) * 0.4 * oxidize);
	}
	// The lowriders' paint: candy depth, the patterned roof and the pinstripes.
	float lr_pin = 0.0;
	if (custom > 0.0) {
		vec3 q = paint_rest;
		float px = max(fwidth(q.x) + fwidth(q.z) + fwidth(q.y), 0.0004) * 0.5;
		float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		coat = mix(candy_deep, coat, pow(ndv, 0.75));
		float top = smoothstep(0.55, 0.8, body_ny);
		// The roof panel: a lace pattern faded across it, inside a pinstriped edge.
		if (pattern_amount > 0.0 && q.y > pin_roof.w) {
			vec2 c = vec2(abs(q.x), q.z - (pin_roof.x + pin_roof.y) * 0.5);
			vec2 hs = vec2(pin_roof.z, abs(pin_roof.y - pin_roof.x) * 0.5);
			vec2 dd = c - (hs - vec2(0.06));
			float box = length(max(dd, vec2(0.0))) + min(max(dd.x, dd.y), 0.0) - 0.06;
			float inside = (1.0 - smoothstep(-px, px, box)) * top;
			vec2 lp = vec2(q.x, q.z) / 0.085;
			vec2 lf = fract(lp) - 0.5;
			float lr = length(lf);
			float la = atan(lf.y, lf.x);
			float petal = abs(lr - (0.30 + 0.10 * cos(6.0 * la))) - 0.035;
			float lace = (1.0 - smoothstep(-0.02, 0.03, petal)) + (1.0 - smoothstep(0.0, 0.08, lr)) * 0.8;
			lace *= clamp(0.03 / max(px * 12.0, 1e-4), 0.0, 1.0);
			float fade = 0.35 + 0.65 * smoothstep(0.0, hs.x, c.x);
			coat = mix(coat, mix(coat, pattern_color, 0.55 + 0.45 * lace) , inside * fade * pattern_amount);
			float edge = min(abs(box + 0.012), abs(box + 0.028));
			lr_pin = max(lr_pin, (1.0 - smoothstep(0.0022 - px, 0.0022 + px, edge)) * top * pattern_amount);
		}
		// Scrolls on the bonnet and the deck lid.
		if (q.y > pin_hood.z) {
			float len = abs(pin_hood.y - pin_hood.x);
			lr_pin = max(lr_pin, lr_scroll(vec2(abs(q.x), (pin_hood.x - q.z)), len, pin_hood.w, pin_style, px) * top);
		}
		if (q.y > pin_deck.z) {
			float len = abs(pin_deck.y - pin_deck.x);
			lr_pin = max(lr_pin, lr_scroll(vec2(abs(q.x), (q.z - pin_deck.x)), len, pin_deck.w * 0.8, mod(pin_style + 1.0, 4.0), px) * top);
		}
		// The double line down each flank, tapering to a point at both ends.
		float flank = 1.0 - smoothstep(0.35, 0.6, abs(body_ny));
		float zs = (q.z - pin_side.y) / max(pin_side.z - pin_side.y, 0.01);
		float taper = smoothstep(0.0, 0.08, zs) * smoothstep(1.0, 0.92, zs);
		float rise = 0.012 * smoothstep(0.08, 0.0, zs) + 0.012 * smoothstep(0.92, 1.0, zs);
		float l1 = abs(q.y - pin_side.x - rise);
		float l2 = abs(q.y - pin_side.x - 0.011 + rise);
		float side_line = max(1.0 - smoothstep(0.0018 - px, 0.0018 + px, l1), 1.0 - smoothstep(0.0012 - px, 0.0012 + px, l2) * 1.0);
		lr_pin = max(lr_pin, side_line * flank * taper * step(0.001, pin_side.x) * clamp(0.004 / max(px, 1e-5), 0.0, 1.0));
		lr_pin = clamp(lr_pin, 0.0, 1.0) * custom;
		coat = mix(coat, pin_color, lr_pin);
	}
	// Road grime: a film of dust low on the body that climbs round the wheel arches (thrown up
	// and back by the tyres), dust on the tail, mud on the work trucks, and fine scratches in the
	// clear coat along the flanks. Everything in metres in the mesh's own space, so it rides with
	// the car and lines up with its arches.
	float grime_rough = 0.0;
	float grime_cc = 0.0;
	if (grime > 0.0 || mud > 0.0 || scratches > 0.0) {
		vec3 q = paint_rest;
		float sc = grime_frame.y;
		float along = length_is_x ? q.x : q.z;
		float across = length_is_x ? q.z : q.x;
		float h = (q.y - grime_frame.x) * sc;
		vec3 qm = q * sc;
		float n1 = wear_noise(qm * 3.1);
		float n2 = wear_noise(qm * 13.0 + 7.3);
		float n3 = wear_noise(qm * 47.0 + 2.1);
		// Not on what faces the sky: rain and the wash take that.
		float side = 1.0 - smoothstep(0.30, 0.70, body_ny);
		// Dust runs down the panels in streaks.
		float streak = wear_noise(vec3(along * sc * 26.0, h * 1.4, across * sc * 26.0));
		// The low band: higher on a dirtier car, its top edge ragged and run down in streaks.
		float edge_h = 0.16 + 0.32 * grime + (n1 - 0.5) * 0.20 + (streak - 0.5) * 0.16;
		float low = 1.0 - smoothstep(edge_h - 0.12, edge_h + 0.03, h);
		// Spray round each arch, heavier behind the wheel; a cloud of fine dots past its edge.
		float arch = 0.0;
		float splash = 0.0;
		for (int k = 0; k < 2; k++) {
			float c = k == 0 ? grime_arch.x : grime_arch.y;
			vec2 d = vec2((along - c) * grime_frame.z, q.y - grime_arch.z) * sc;
			float r = length(d);
			float rr = grime_arch.w * sc;
			float behind = smoothstep(-0.4, 0.6, d.x / max(r, 1e-3));
			float reach = rr + 0.12 + 0.30 * behind * grime + (n2 - 0.5) * 0.10;
			float ring = (1.0 - smoothstep(reach - 0.06, reach + 0.02, r)) * smoothstep(rr - 0.04, rr + 0.02, r);
			arch = max(arch, ring * (0.55 + 0.45 * behind));
			splash = max(splash, (1.0 - smoothstep(rr, rr + 0.9, r)) * smoothstep(-0.2, 0.7, d.x / max(r, 1e-3)) * (1.0 - smoothstep(0.2, 0.9, h)));
		}
		// Fine spray dots above the band and round the arches (under a pixel: their average).
		vec3 dc = floor(qm * 160.0);
		float dpx = length(fwidth(qm * 160.0));
		float dots = mix(step(0.88, hash13(dc)), 0.12, smoothstep(0.6, 1.4, dpx));
		dots *= max(1.0 - smoothstep(edge_h, edge_h + 0.28, h), splash) * grime;
		// The tail collects the dust its own wake drops: the rear face, more toward the bottom.
		float tail_u = grime_frame.z > 0.0 ? body_uv.x : 1.0 - body_uv.x;
		float tail = smoothstep(0.90, 0.985, tail_u) * (1.0 - facing.x) * (1.0 - facing.y) * (1.0 - smoothstep(0.25, 1.0, h + (n1 - 0.5) * 0.3));
		float dirt = max(max(low * (0.55 + 0.45 * n2), arch * (0.6 + 0.4 * n3)), tail * (0.25 + 0.4 * n1) * grime);
		dirt = clamp(max(dirt * smoothstep(0.0, 0.35, grime), dots * 0.7) * side, 0.0, 0.95);
		vec3 dust_c = grime_col(mix(vec3(0.50, 0.46, 0.40), vec3(0.62, 0.57, 0.49), n2));
		// A wet road darkens the film to grey-brown sludge.
		dust_c = mix(dust_c, dust_c * 0.45, road_wetness);
		coat = mix(coat, dust_c, dirt * 0.9);
		// Mud: clumps and spatter thrown off the tyres, low and behind the arches.
		float clump = smoothstep(0.52, 0.72, n2 * 0.55 + n3 * 0.45);
		vec3 sp = floor(qm * 38.0);
		float spat = step(0.93, hash13(sp)) * (1.0 - smoothstep(0.18, 0.42, length(fract(qm * 38.0) - 0.5)));
		float mudm = clamp((max(arch, splash) * 1.1 + low * 0.5) * max(clump, spat) * mud * side, 0.0, 1.0);
		coat = mix(coat, grime_col(mix(vec3(0.24, 0.19, 0.14), vec3(0.33, 0.27, 0.20), n3)), mudm);
		// Scratches: fine lines through the clear coat on the flanks at hip height (keys, bags,
		// brushes at the car wash), each a short straight cut at its own angle, lighter than the
		// paint and with no lacquer over it; under a pixel they fade to their average.
		float scr = 0.0;
		if (scratches > 0.0 && h > 0.30 && h < 1.15) {
			vec2 sq = vec2(along, q.y) * sc / 0.22;
			vec2 cell = floor(sq);
			float px = max(length(fwidth(sq)), 1e-4);
			for (int j = 0; j < 4; j++) {
				vec2 ce = cell + vec2(float(j % 2), float(j / 2)) - step(fract(sq), vec2(0.5));
				float hs = hash13(vec3(ce, sign(across) * 3.0 + 1.0));
				if (hs > scratches * 0.4) {
					continue;
				}
				vec2 o = ce + vec2(hash13(vec3(ce, 5.1)), hash13(vec3(ce, 9.3)));
				float an = (hash13(vec3(ce, 2.7)) - 0.5) * 0.7;
				vec2 dir = vec2(cos(an), sin(an));
				float len = 0.2 + 0.7 * hash13(vec3(ce, 4.4));
				vec2 rel = sq - o;
				float t = clamp(dot(rel, dir), -len * 0.5, len * 0.5);
				float dl = length(rel - dir * t);
				float wdt = 0.005;
				scr = max(scr, clamp((wdt * 0.5 + px * 0.5 - dl) / px, 0.0, 1.0) * min(1.0, wdt / px));
			}
			scr *= (1.0 - facing.y) * facing.x;
		}
		coat = mix(coat, coat * 0.55 + grime_col(vec3(0.62)), scr * 0.85);
		grime_rough = max(dirt * 0.85, mudm);
		grime_cc = max(max(dirt, mudm), scr * 0.8);
	}
	// A film of dust or pollen (paint2) settled on what faces the sky - roof, bonnet, boot - with a
	// little on the flanks, thinner where the last rain ran it off in streaks; pollen in grains.
	float dust_m = 0.0;
	if (dust_film > 0.0) {
		vec3 q = paint_rest * p2_ms;
		float up = smoothstep(0.35, 0.85, body_ny);
		float n1 = wear_noise(q * 2.2 + 11.0);
		float n2 = wear_noise(q * 9.0 + 3.7);
		float runs = wear_noise(vec3(q.x * 30.0, q.y * 1.2, q.z * 30.0));
		float grains = mix(step(0.62, hash13(floor(q * 900.0))), 0.38, smoothstep(0.4, 1.2, p2_fp * 900.0));
		dust_m = up * (0.55 + 0.45 * n1) * (0.7 + 0.3 * n2) * (0.75 + 0.25 * grains);
		dust_m += (1.0 - up) * (1.0 - facing.y) * 0.16 * n1 * smoothstep(0.35, 0.75, runs);
		dust_m = clamp(dust_m, 0.0, 1.0) * dust_film;
		coat = mix(coat, dust_tint, dust_m * 0.6);
	}
	vec3 painted = coat * (0.55 + 0.45 * lum * paint_brightness);
	vec3 dark = base.rgb * 0.6;
	ALBEDO = mix(dark, painted, body);

	float glass = max(1.0 - smoothstep(0.02, dark_below, lum), shape_glass);
	ALBEDO = mix(ALBEDO, vec3(0.018, 0.02, 0.022), shape_glass);
	float rough = mix(mix(0.6, 0.06, glass), paint_roughness, body);
	// Glass is not a metal: what it shows is its own specular and the lacquer lobe. At 0.5 metal
	// every dark trim piece mirrored the sky too.
	float metal = mix(mix(0.1, 0.0, glass), paint_metallic, body);
	rough *= mix(1.0, stripe_roughness_mul, livery * body);

	// Panels are never perfectly uniform: a slow ripple in roughness reads as real sheet metal
	// rather than a CG surface.
	rough *= 1.0 + 0.10 * (hash13(floor(world_pos * 6.0)) - 0.5);
	rough = mix(rough, max(rough * 1.6, 0.42), worn_coat * body);
	rough = mix(rough, 0.78, worn_rough * body);
	rough = mix(rough, 0.82, grime_rough * body);
	rough = mix(rough, max(rough, 0.55), ox_chalk * 0.7 * body);
	rough = mix(rough, 0.72, ox_peel * body);
	rough = mix(rough, max(rough, 0.62), dust_m * body);
	metal = mix(metal, 0.0, max(ox_peel, dust_m * 0.6) * body);
	metal = mix(metal, 0.0, worn_rough * body);
	// A pinstripe is enamel laid on the lacquer: no flake under it.
	metal = mix(metal, 0.05, lr_pin * body);
	rough = mix(rough, 0.32, lr_pin * body);

#ifdef CAR_DAMAGE
	// --- Damage (scripts/vehicles/car_damage.gd). Clearcoat and specular are scaled at the end.
	float cc_keep = 1.0;
	float spec_keep = 1.0;
	vec3 dn = vec3(0.0);
	float px = max(length(fwidth(local_rest)), 1e-5);
	float bodywork = body;
	// Fire. Real burnt-out cars read in bands from the hottest part out: bare metal gone to
	// rust brown and ash grey where the paint burnt off, a black ring of carbonised paint round
	// it, then blistered, cooked paint, then paint. Fire burns upward, so the sills keep some.
	float heat = 0.0;
	float stain_n = cd_fbm3(local_rest * 2.3);
	if (burnt > 0.0) {
		float dist = distance(local_rest, burn_origin);
		heat = clamp((burn_reach - dist) / max(burn_reach * 0.35, 0.15) + (stain_n - 0.5) * 0.9, 0.0, 1.0);
		// While it burns the sills stay cooler; burnt out, the whole shell has had it.
		heat *= mix(mix(0.62, 0.9, smoothstep(0.6, 1.0, burnt)), 1.0, smoothstep(0.06, 0.42, body_uv.y + (stain_n - 0.5) * 0.25));
	}
	for (int i = 0; i < scorch_count && i < 4; i++) {
		float r = max(scorches[i].w, 0.05);
		float d = distance(local_rest, scorches[i].xyz) + (stain_n - 0.5) * r * 0.8;
		heat = max(heat, 0.5 * (1.0 - smoothstep(r * 0.25, r, d)));
	}
	if (smoke_stain > 0.0) {
		float d = distance(local_rest, burn_origin);
		ALBEDO *= 1.0 - 0.55 * smoke_stain * (1.0 - smoothstep(0.2, 1.4, d + (stain_n - 0.5) * 0.6));
	}
	if (heat > 0.001) {
		float n2 = cd_noise3(local_rest * 9.0);
		float n3 = cd_fbm3(local_rest * 0.9 + 4.0);
		vec3 soot = vec3(0.026, 0.023, 0.020);
		// Burnt steel: rust brown and dull grey-brown, pale ash where it burnt hottest.
		vec3 rust = mix(vec3(0.17, 0.085, 0.045), vec3(0.30, 0.16, 0.085), n2);
		vec3 ash = mix(vec3(0.30, 0.285, 0.265), vec3(0.50, 0.48, 0.45), n2);
		// Ash greys the roof and the bonnet most (the paint there burns hottest, and it lies on top).
		vec3 bare_c = mix(rust, ash, clamp(smoothstep(0.38, 0.62, n3) + facing.y * 0.4 - 0.1, 0.0, 1.0));
		// Temper colours where the steel got hot but kept its skin: straw to blue.
		vec3 temper = mix(vec3(0.50, 0.38, 0.16), vec3(0.16, 0.20, 0.38), n2);
		vec3 c = ALBEDO;
		c = mix(c, c * 0.42 + soot * 0.3, smoothstep(0.0, 0.28, heat));
		c = mix(c, soot, smoothstep(0.24, 0.48, heat));
		c = mix(c, temper, smoothstep(0.5, 0.58, heat) * (1.0 - smoothstep(0.6, 0.7, heat)) * 0.45);
		c = mix(c, bare_c, smoothstep(0.6, 0.8, heat));
		// Soot left in streaks and blotches over the bare metal.
		c = mix(c, soot, smoothstep(0.55, 0.85, n2 * n3 * 1.9) * smoothstep(0.62, 0.9, heat) * 0.7);
		ALBEDO = c;
		rough = mix(rough, mix(0.72, 0.95, n2), smoothstep(0.08, 0.45, heat));
		metal = mix(metal, 0.12, smoothstep(0.2, 0.6, heat));
		cc_keep *= 1.0 - smoothstep(0.04, 0.3, heat);
		spec_keep = mix(1.0, 0.75, smoothstep(0.3, 0.8, heat));
		// Blistered paint: bumps in the ring where it cooked but did not burn off.
		// (Rotated off the noise lattice, or the blisters line up in a grid.)
		vec3 bp = mat3(vec3(0.8, 0.36, -0.48), vec3(-0.6, 0.48, -0.64), vec3(0.0, 0.8, 0.6)) * local_rest * 38.0;
		vec3 bl = vec3(cd_noise3(bp), cd_noise3(bp + 5.3), cd_noise3(bp + 9.7)) - 0.5;
		dn += bl * 0.22 * smoothstep(0.08, 0.3, heat) * (1.0 - smoothstep(0.45, 0.62, heat)) * (1.0 - smoothstep(0.004, 0.012, px));
	}
	// Bullet holes: a punched black hole, a ring of bright torn steel, primer and flecks of
	// metal where the paint flaked off round it, and the metal pushed in round the hole.
	if (hole_count > 0) {
		float pit = 0.0;
		float bare = 0.0;
		float chip = 0.0;
		vec3 dim = vec3(0.0);
		for (int i = 0; i < hole_count && i < 40; i++) {
			vec3 d = local_rest - holes[i].xyz;
			float r = max(holes[i].w, 0.001);
			float dist = length(d);
			if (dist < r * 3.2) {
				float wob = (cd_noise3(local_rest / r * 1.9 + float(i) * 3.1) - 0.5) * r;
				pit = max(pit, 1.0 - smoothstep(r * 0.55, r * 0.55 + px, dist + wob * 0.2));
				bare = max(bare, 1.0 - smoothstep(r * 0.95, r * 0.95 + px + r * 0.08, dist + wob * 0.35));
				chip = max(chip, 1.0 - smoothstep(r * 2.0, r * 2.0 + px + r * 0.2, dist + wob * 1.4));
				float crater = (1.0 - smoothstep(r * 0.7, r * 2.6, dist)) * smoothstep(r * 0.5, r * 0.8, dist);
				dim += d / max(dist, 1e-5) * crater;
			}
		}
		vec3 primer = mix(vec3(0.34, 0.34, 0.32), vec3(0.52, 0.52, 0.50), cd_noise3(local_rest * 700.0));
		float flake_bits = step(0.72, cd_noise3(local_rest * 1500.0));
		ALBEDO = mix(ALBEDO, mix(primer, vec3(0.58), flake_bits), chip * bodywork);
		rough = mix(rough, mix(0.62, 0.35, flake_bits), chip * bodywork);
		metal = mix(metal, flake_bits, chip * bodywork);
		ALBEDO = mix(ALBEDO, vec3(0.60, 0.60, 0.61), bare * bodywork);
		metal = mix(metal, 1.0, bare * bodywork);
		rough = mix(rough, 0.3, bare * bodywork);
		cc_keep *= 1.0 - chip * bodywork;
		ALBEDO = mix(ALBEDO, vec3(0.005), pit * bodywork);
		rough = mix(rough, 1.0, pit * bodywork);
		metal = mix(metal, 0.0, pit * bodywork);
		spec_keep *= 1.0 - pit * bodywork;
		dn -= dim * 0.9 * bodywork;
	}
	// Crash damage (car_crumple.gdshaderinc): the paint cracks and flakes along the ridges of a
	// crushed panel, grime gathers in the folds, and a slide along something leaves a scuffed
	// band scored through to primer and bare steel.
	if (crumple_count > 0) {
		float ridge;
		float st = cr_stress(local_rest, ridge);
		if (st > 0.01) {
			float flake_n = cd_noise3(local_rest * 260.0);
			float crack = smoothstep(0.82, 0.97, ridge) * smoothstep(0.15, 0.6, st) * step(0.35, flake_n);
			crack = mix(crack, 0.25 * smoothstep(0.15, 0.6, st), 1.0 - smoothstep(0.004, 0.012, px));
			ALBEDO = mix(ALBEDO, ALBEDO * 0.55, smoothstep(0.0, 0.45, 1.0 - ridge) * st * 0.6 * bodywork);
			ALBEDO = mix(ALBEDO, vec3(0.42, 0.42, 0.40), crack * bodywork);
			rough = mix(rough, 0.6, max(crack, st * 0.4) * bodywork);
			cc_keep *= 1.0 - max(crack, st * 0.35) * bodywork;
		}
	}
	if (scrape_count > 0) {
		vec3 sc = cr_scrape(local_rest, normalize(local_nrm), px);
		if (sc.x > 0.001) {
			float sn = cd_noise3(local_rest * 90.0);
			ALBEDO = mix(ALBEDO, mix(ALBEDO, vec3(0.55), 0.35) , sc.x * 0.6 * bodywork);
			rough = mix(rough, 0.55, sc.x * bodywork);
			cc_keep *= 1.0 - 0.85 * sc.x * bodywork;
			ALBEDO = mix(ALBEDO, mix(vec3(0.36, 0.36, 0.34), vec3(0.47, 0.47, 0.45), sn), sc.y * bodywork);
			ALBEDO = mix(ALBEDO, vec3(0.62, 0.62, 0.63), sc.z * bodywork);
			metal = mix(metal, 0.0, sc.y * bodywork);
			metal = mix(metal, 1.0, sc.z * bodywork);
			rough = mix(rough, 0.35, sc.z * bodywork);
		}
	}
	// Glass that the texture marks (the single-texture bodies; the rest have a glass slot and
	// car_glass_damage.gdshader): cracks round each hit, and a side whose glass is gone shows the
	// dark cabin.
	float dglass = max(glass, shape_glass) * (1.0 - body);
	if (dglass > 0.01 && (crack_count > 0 || dot(glass_gone, vec4(1.0)) > 0.0 || burnt > 0.0)) {
		vec3 nl = normalize(local_nrm);
		float fz = dot(nl, glass_front);
		float fx = dot(nl, glass_left);
		float gone = abs(fz) > abs(fx) ? (fz > 0.0 ? glass_gone.x : glass_gone.y) : (fx > 0.0 ? glass_gone.z : glass_gone.w);
		gone = max(gone, step(0.5, burnt));
		float web = 0.0;
		for (int i = 0; i < crack_count && i < 8; i++) {
			vec2 f;
			web = max(web, cd_crack_web(local_rest, cracks[i].xyz, nl, cracks[i].w, float(i) * 1.7 + 0.3, px, f));
		}
		ALBEDO = mix(ALBEDO, vec3(0.62, 0.64, 0.66), web * dglass * (1.0 - gone));
		rough = mix(rough, 0.35, web * dglass * (1.0 - gone));
		ALBEDO = mix(ALBEDO, vec3(0.012, 0.011, 0.010), gone * dglass);
		rough = mix(rough, 1.0, gone * dglass);
		cc_keep *= 1.0 - gone * dglass;
		spec_keep *= 1.0 - 0.85 * gone * dglass;
	}
	float dn_len = length(dn);
	if (dn_len > 1e-4) {
		vec3 dv = (VIEW_MATRIX * (MODEL_MATRIX * vec4(dn, 0.0))).xyz;
		NORMAL = normalize(NORMAL + normalize(dv) * min(dn_len, 1.5));
	}
#endif

	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = metal;
	SPECULAR = 0.55;
#ifdef CAR_DAMAGE
	SPECULAR = 0.55 * spec_keep;
#endif

	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.6;
	}

	// Aluminium flake in the basecoat: a sparse sparkle that only resolves close up, which is
	// what sells metallic paint in a walk-up shot.
	float near = 1.0 - smoothstep(flake_fade_distance * 0.5, flake_fade_distance, length(VERTEX));
	if (near > 0.0 && flake_strength > 0.0 && custom > 0.0) {
		// Candy over flake: fine flakes (about a millimetre) fixed to the body (a moving car carries
		// them), each tilted its own way, so a flake only lights where its own mirror catches the
		// sun - a dense sparkle inside the paint's highlight, tinted by the candy over it, and
		// nothing as separate dots from a couple of metres (it fades to a faint lift of the coat).
		vec3 g = paint_rest * flake_scale;
		vec3 cell = floor(g);
		vec3 jit = vec3(hash13(cell + 3.1), hash13(cell + 7.7), hash13(cell + 11.3)) * 0.6 + 0.2;
		float disc = 1.0 - smoothstep(0.18, 0.32, length(fract(g) - jit));
		vec3 fn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 fv = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 tilt = (vec3(hash13(cell + 1.7), hash13(cell + 5.3), hash13(cell + 9.1)) - 0.5) * 0.30;
		vec3 fr = normalize(reflect(-fv, fn) + tilt);
		float glint = pow(max(dot(fr, normalize(sun_direction)), 0.0), 90.0);
		float day = smoothstep(-0.02, 0.12, sun_direction.y) * (1.0 - night_factor);
		// Under a pixel the flakes are an average: a soft lift of the highlight, not glitter.
		float cell_px = 1.0 / max(length(fwidth(g)), 1e-4);
		float resolved = smoothstep(1.2, 3.0, cell_px);
		vec3 tint = mix(flake_tint, coat * 1.6, 0.55);
		float flake = mix(0.35 * glint, disc * glint * 4.0, resolved);
		EMISSION += tint * (flake * flake_strength * body * near * day * (1.0 - lr_pin));
	} else if (near > 0.0 && sparkle > 0.0) {
		// The flake (paint2): aluminium flakes under a millimetre, each tilted its own way, fixed
		// to the body. Worked out per cell the size of a pixel (two LOD levels blended), so a
		// pixel is one sample of the flakes it covers: a crisp sparkle round the sun's highlight
		// that never crawls, a disc inside its cell once a cell is bigger than a pixel, and past
		// the flakes' reach a broad soft lift of the highlight.
		vec3 q = paint_rest * p2_ms;
		float fp = p2_fp;
		float flake_m = 0.0007 * 190.0 / max(flake_scale, 1.0);
		float lod = log2(max(fp * 1.25 / flake_m, 1.0));
		float l0 = floor(lod);
		float lf = lod - l0;
		vec3 fn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 fv = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 sd = normalize(sun_direction);
		float g = 0.0;
		for (int k = 0; k < 2; k++) {
			float lv = l0 + float(k);
			float cs = flake_m * exp2(lv);
			vec3 gq = q / cs;
			vec3 c = floor(gq) + lv * 37.0;
			vec3 tilt = (vec3(hash13(c + 1.7), hash13(c + 5.3), hash13(c + 9.1)) - 0.5) * 0.62;
			float sp = pow(max(dot(reflect(-fv, normalize(fn + tilt)), sd), 0.0), 260.0);
			float res = clamp(cs / fp - 1.0, 0.0, 1.0);
			vec3 j = vec3(hash13(c + 3.1), hash13(c + 7.7), hash13(c + 11.3)) * 0.5 + 0.25;
			float disc = mix(1.0, 1.0 - smoothstep(0.24, 0.36, length(fract(gq) - j)), res);
			float hosts = step(hash13(c + 13.9), 0.55);
			g += sp * disc * hosts * (k == 0 ? 1.0 - lf : lf);
		}
		float glow = pow(max(dot(reflect(-fv, fn), sd), 0.0), 16.0);
		float day = smoothstep(-0.02, 0.12, sd.y) * (1.0 - night_factor);
		vec3 tint = mix(vec3(1.0), coat * 2.2 + 0.08, 0.5);
		// Only on what faces the sun (the glints have no shadow test of their own).
		float lit_side = smoothstep(0.05, 0.3, dot(fn, sd));
		EMISSION += tint * (g * 1.6 + glow * 0.06) * sparkle * body * near * day * lit_side
			* (1.0 - worn_rough) * (1.0 - ox_peel) * (1.0 - dust_m) * (1.0 - livery * 0.7);
#ifdef CAR_DAMAGE
		EMISSION *= cc_keep;
#endif
	} else if (near > 0.0 && flake_strength > 0.0) {
		float flake = hash13(floor(world_pos * flake_scale));
		flake = smoothstep(0.90, 1.0, flake);
#ifdef CAR_DAMAGE
		flake *= cc_keep;
#endif
		ALBEDO += vec3(flake * flake_strength * body * near * (1.0 - worn_rough));
	}

	// --- Rain (wet_surface.gdshaderinc). The paint goes a shade deeper under its film of water;
	// beads stand on the bonnet, roof and boot (the body mesh's own frame: a moving car carries
	// them), and on the doors and wings the water runs down in threads while it still rains.
	// Unresolved (a few metres off) the beads are only the darker, glossier tone.
	float wet_px = 0.0;
	if (ws_on()) {
		float wet = ws_wet(0.3);
		float ms = length(MODEL_MATRIX[0].xyz);
		vec3 wn = normalize(wet_nrm);
		vec3 wt;
		vec3 wb;
		ws_frame(wn, wt, wb);
		vec3 wp = paint_rest * ms;
		vec2 q = vec2(dot(wp, wt), dot(wp, wb));
		float px = max(length(fwidth(world_pos)), 1e-5);
		float up = smoothstep(-0.1, 0.65, wn.y);
		float paint_part = max(body, glass);
		vec3 bead = ws_beads(q, mix(0.8, 1.15, up), wet * mix(0.35, 1.0, up) * paint_part, px);
		vec2 run = ws_runs(vec2(q.x, -q.y), 0.06, TIME, ws_rain() * (1.0 - up) * 0.6 * paint_part, px);
		ALBEDO *= mix(1.0, 0.8, wet * body);
		ROUGHNESS = mix(ROUGHNESS, ROUGHNESS * 0.6, wet);
		vec3 slope = wt * (bead.y + run.y * 0.6) + wb * bead.z;
		float sl = length(slope);
		if (sl > 1e-4) {
			vec3 sv = (VIEW_MATRIX * (MODEL_MATRIX * vec4(slope, 0.0))).xyz;
			NORMAL = normalize(NORMAL + normalize(sv) * min(sl, 1.2) * 0.55);
		}
		wet_px = wet;
	}

	// The lacquer: a second, much sharper specular lobe over everything painted, and over glass.
	// Matte paint drops its own coat to zero but the glass keeps one.
	// Glass keeps a lacquer-sharp reflection but not a full one: at grazing angles a full coat
	// turned every window into a sheet of sky the same pale blue as the paint around it.
	vec3 w_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 w_view = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float rise = reflect(-w_view, w_normal).y;
	float open_sky = mix(canyon_reflect, 1.0, smoothstep(0.0, canyon_rise, rise));
	vec3 p2_rr = reflect(-w_view, w_normal);
	float p2_az = atan(p2_rr.z, p2_rr.x) / 6.2831853 + 0.5;
	float p2_daz = fwidth(p2_az);
	float p2_dry = fwidth(p2_rr.y);
	if (probe_reach > 0.0) {
		open_sky = mix(open_sky, 1.0, 1.0 - smoothstep(probe_reach * 0.6, probe_reach, length(VERTEX)));
	}
	float cc_rough = clearcoat_roughness_value;
	float cc_extra = 1.0;
	vec3 p2_env = vec3(0.0);
	if (paint2 > 0.0) {
		// The street in the lacquer: a world-fixed skyline per azimuth of the reflected ray
		// (rooftops 3-30 degrees up, a gap now and then) cuts the mirror where a ray meets a
		// building, so a door carries the hard horizon line of the street and the sky above it
		// bends over every curve of the body. Inside the probes' reach the real street is mirrored.
		vec3 rr = p2_rr;
		vec3 tw = world_pos + origin_shift;
		float place = hash13(vec3(floor(tw.xz / 70.0), 5.0));
		float az = p2_az * (22.0 + 14.0 * place) + place * 9.0;
		float daz = min(p2_daz * (22.0 + 14.0 * place), 0.5) * 0.5;
		float sky_h = 0.0;
		for (int k = 0; k < 2; k++) {
			float b = floor(az + (k == 0 ? -daz : daz));
			float hb = hash13(vec3(b, place * 17.0, 2.0));
			float tall = mix(0.05, 0.52, hb * hb) * mix(0.55, 1.0, place);
			sky_h += mix(tall, 0.015, step(0.82, hash13(vec3(b, 3.0, place)))) * 0.5;
		}
		float aa = max(p2_dry, 0.004);
		float building = 1.0 - smoothstep(sky_h - aa, sky_h + aa, rr.y);
		float city_open = mix(canyon_reflect * 0.2, 1.0, 1.0 - building);
		float probe_in = 0.0;
		if (probe_reach > 0.0) {
			probe_in = 1.0 - smoothstep(probe_reach * 0.6, probe_reach, length(VERTEX));
			city_open = mix(city_open, 1.0, probe_in);
		}
		open_sky = mix(open_sky, city_open, skyline);
		// What the mirror shows there instead, EMITTED (the radiance map is the open sky, and the
		// web has no reflections of its own): facades in their own tones with rows of windows -
		// the sky in the panes by day, lit rooms at night - and the street under the horizon, a
		// bright line where the far pavement meets the walls. Faded to the real one in a probe.
		{
			float b = floor(az);
			float tone = hash13(vec3(b, 7.0, place));
			float fu = fract(az) * (4.0 + floor(tone * 7.0));
			float elev = asin(clamp(rr.y, -1.0, 1.0));
			float fv = elev * (28.0 + 20.0 * hash13(vec3(b, 11.0, place)));
			float dpx = max(p2_daz * (22.0 + 14.0 * place) * (4.0 + floor(tone * 7.0)), p2_dry * 40.0);
			float pane = smoothstep(0.18, 0.18 + dpx, fract(fu)) * smoothstep(0.82, 0.82 - dpx, fract(fu))
				* smoothstep(0.25, 0.25 + dpx, fract(fv)) * smoothstep(0.85, 0.85 - dpx, fract(fv));
			pane = mix(pane, 0.36, smoothstep(0.25, 0.6, dpx));
			vec3 sky_l = grime_col(sky_tint.rgb);
			float day_l = (1.0 - night_factor) * 0.85 + 0.03;
			vec3 wall = grime_col(mix(vec3(0.42, 0.40, 0.37), vec3(0.70, 0.66, 0.60), tone)) * (sky_l * 0.55 + vec3(0.18) * smoothstep(-0.05, 0.3, sun_direction.y)) * day_l;
			float lit = step(0.55, hash13(vec3(floor(fu), floor(fv), b + place * 31.0))) * lamp_factor;
			vec3 glass_c = mix(sky_l * 0.35 * day_l, grime_col(vec3(1.0, 0.78, 0.50)) * 0.55, lit);
			vec3 facade = mix(wall, glass_c, pane);
			float under = 1.0 - smoothstep(-aa, aa, rr.y);
			vec3 street = grime_col(vec3(0.26, 0.25, 0.24)) * (sky_l * 0.45 + 0.12) * day_l
				+ grime_col(vec3(0.95, 0.70, 0.40)) * 0.05 * lamp_factor;
			street += (sky_l * 0.5 * day_l + grime_col(vec3(1.0, 0.72, 0.45)) * 0.12 * lamp_factor)
				* (1.0 - smoothstep(0.0, 0.05, abs(rr.y + 0.02)));
			vec3 env = mix(facade, street, under);
			float ndv = clamp(dot(w_normal, w_view), 0.0, 1.0);
			float fr = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
			p2_env = env * fr * building * skyline * (1.0 - probe_in);
		}
		// Orange peel: the lacquer's dimpled skin, a few millimetres across - a crawl in the
		// mirror up close (the normal and the coat's roughness ripple), a slightly softer mirror
		// once it is under a pixel. Crisper lacquer than before on every finish.
		cc_rough *= 0.72;
		if (peel > 0.0) {
			vec3 q = paint_rest * p2_ms;
			float fp = p2_fp;
			float resolve = 1.0 - smoothstep(0.0012, 0.0045, fp);
			float pn = wear_noise(q * 170.0) * 0.65 + wear_noise(q * 430.0 + 3.0) * 0.35;
			cc_rough *= mix(1.0 + 0.6 * peel, 0.75 + 0.9 * pn * peel, resolve);
			cc_extra = mix(1.0, 0.88 + 0.24 * pn, resolve * peel);
			if (resolve > 0.01) {
				float e = 0.0015;
				vec3 nb = normalize(wet_nrm);
				float p0 = wear_noise(q * 170.0);
				vec3 gr = vec3(wear_noise((q + vec3(e, 0.0, 0.0)) * 170.0) - p0,
					wear_noise((q + vec3(0.0, e, 0.0)) * 170.0) - p0,
					wear_noise((q + vec3(0.0, 0.0, e)) * 170.0) - p0) / e;
				gr -= nb * dot(gr, nb);
				vec3 tv = (VIEW_MATRIX * (MODEL_MATRIX * vec4(gr, 0.0))).xyz;
				NORMAL = normalize(NORMAL - tv * (0.00006 * peel * resolve * body));
			}
		}
	}
	CLEARCOAT = max(clearcoat_amount * body, glass_clearcoat * glass * mix(1.0, 0.6, shape_glass)) * open_sky;
	CLEARCOAT *= 1.0 - worn_coat * body;
	CLEARCOAT *= 1.0 - grime_cc * body;
	CLEARCOAT_ROUGHNESS = mix(cc_rough, 0.25, worn_coat);
	if (paint2 > 0.0) {
		CLEARCOAT *= mix(1.0, cc_extra, body);
		// The aged and the dusty: the lacquer goes where it peeled, dulls under chalk and dust.
		CLEARCOAT *= 1.0 - (ox_peel + ox_chalk * 0.45 + dust_m * 0.6) * body;
		CLEARCOAT_ROUGHNESS = mix(CLEARCOAT_ROUGHNESS, 0.3, clamp(ox_chalk + dust_m, 0.0, 1.0) * body);
		// The emitted street, as strong as the lacquer that mirrors it (a wrap's sheen blurs it).
		float coat_k = clamp(clearcoat_amount * body * (1.0 - worn_coat) * (1.0 - grime_cc) * (1.0 - ox_peel) * (1.0 - dust_m * 0.7), 0.0, 1.0);
		EMISSION += p2_env * (coat_k + 0.35 * wrap * body) * mix(1.0, 0.5, wrap);
		// A satin wrap: no lacquer, a soft broad sheen off the vinyl.
		CLEARCOAT = max(CLEARCOAT, 0.4 * wrap * body * open_sky * (1.0 - dust_m));
		CLEARCOAT_ROUGHNESS = mix(CLEARCOAT_ROUGHNESS, 0.36, wrap * body);
	}
	// A wet body is all lacquer: even a dull or worn coat mirrors under its film of water.
	CLEARCOAT = max(CLEARCOAT, 0.9 * wet_px * open_sky * max(body, glass));
	CLEARCOAT_ROUGHNESS = mix(CLEARCOAT_ROUGHNESS, 0.03, wet_px);
#ifdef CAR_DAMAGE
	CLEARCOAT *= cc_keep;
#endif
	// Specular AA: the lacquer lobe never narrower than the pixel's spread of normals. Godot's
	// roughness limiter (Forward+) leaves CLEARCOAT_ROUGHNESS alone, so the coat is done here on
	// both renderers; the base ROUGHNESS only where there is no limiter (Compatibility).
	if (saa_on()) {
		CLEARCOAT_ROUGHNESS = saa_geometric(CLEARCOAT_ROUGHNESS, saa_dnx, saa_dny, 0.5, 0.18);
#if CURRENT_RENDERER != RENDERER_FORWARD_PLUS
		ROUGHNESS = saa_geometric(ROUGHNESS, saa_dnx, saa_dny, 0.25, 0.18);
#endif
	}
#ifdef CAR_OPEN_PANEL
	if (!FRONT_FACING) {
		// The inside of the skin: a lifted bonnet's underside, primer grey with its bracing dark.
		ALBEDO = vec3(0.055, 0.057, 0.06);
		ROUGHNESS = 0.75;
		METALLIC = 0.15;
		CLEARCOAT = 0.0;
		EMISSION = vec3(0.0);
	}
#endif
}
