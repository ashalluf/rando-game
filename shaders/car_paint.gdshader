shader_type spatial;
render_mode cull_back;

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
// 3 fleet belt band round the flanks, 4 taxi checker band.
uniform int stripe_mode : hint_range(0, 4) = 0;
uniform vec3 stripe_color : source_color = vec3(0.92, 0.92, 0.93);
// Half width of a stripe / band, as a fraction of the car's width (mode 1) or height (2, 3, 4).
uniform float stripe_width = 0.032;
// Distance of each racing stripe from the centre line, as a fraction of the car's width.
uniform float stripe_gap = 0.055;
// Height of the band or the two-tone split, as a fraction of the car's height.
uniform float stripe_height = 0.42;
// Checks along the length of the car (mode 4).
uniform float checker_repeat = 44.0;
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

varying vec3 world_pos;
// x = along the car, y = up, z = across, all 0..1 over the body's bounding box.
varying vec3 body_uv;
// x = 1 on the flanks, 0 on the roof, nose and tail. y = 1 on horizontal surfaces.
varying vec2 facing;
// The up-component of the body-space normal (signed: 1 roof, 0 door skin, -1 underside).
varying float body_ny;


float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = (VERTEX - body_min) / max(body_size, vec3(0.001));
	vec3 nrm = normalize(NORMAL);
	body_uv = length_is_x ? n : vec3(n.z, n.y, n.x);
	facing = vec2(length_is_x ? abs(nrm.z) : abs(nrm.x), abs(nrm.y));
	body_ny = nrm.y;
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
	vec4 base = texture(albedo_tex, UV);
	float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float body = smoothstep(dark_below, body_above, lum);
	float shape_glass = 0.0;
	if (geo_glass) {
		shape_glass = smoothstep(beltline - 0.02, beltline + 0.02, body_uv.y)
			* smoothstep(glass_slope_min - 0.04, glass_slope_min + 0.04, body_ny)
			* (1.0 - smoothstep(glass_slope_max - 0.04, glass_slope_max + 0.04, body_ny))
			// Not the top of the roof pillars' own panels: the last few percent is roof.
			* (1.0 - smoothstep(0.93, 0.97, body_uv.y));
		body *= 1.0 - shape_glass;
		// Tinted glass reads as dark from outside in daylight, whatever the texture said.
		lum = mix(lum, 0.02, shape_glass);
	}

	float livery = livery_mask();
	vec3 coat = mix(paint, stripe_color, livery);
	// Pearl flip: the second coat only shows where the panel turns away from the eye.
	if (pearl_amount > 0.0) {
		float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), pearl_power);
		coat = mix(coat, pearl_color, fres * pearl_amount * (1.0 - livery));
	}
	vec3 painted = coat * (0.55 + 0.45 * lum * paint_brightness);
	vec3 dark = base.rgb * 0.6;
	ALBEDO = mix(dark, painted, body);

	float glass = max(1.0 - smoothstep(0.02, dark_below, lum), shape_glass);
	ALBEDO = mix(ALBEDO, vec3(0.025, 0.028, 0.03), shape_glass);
	float rough = mix(mix(0.6, 0.06, glass), paint_roughness, body);
	// Glass is not a metal: what it shows is its own specular and the lacquer lobe. At 0.5 metal
	// every dark trim piece mirrored the sky too.
	float metal = mix(mix(0.1, 0.0, glass), paint_metallic, body);
	rough *= mix(1.0, stripe_roughness_mul, livery * body);

	// Panels are never perfectly uniform: a slow ripple in roughness reads as real sheet metal
	// rather than a CG surface.
	rough *= 1.0 + 0.10 * (hash13(floor(world_pos * 6.0)) - 0.5);

	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = metal;
	SPECULAR = 0.55;

	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.6;
	}

	// Aluminium flake in the basecoat: a sparse sparkle that only resolves close up, which is
	// what sells metallic paint in a walk-up shot.
	float near = 1.0 - smoothstep(flake_fade_distance * 0.5, flake_fade_distance, length(VERTEX));
	if (near > 0.0 && flake_strength > 0.0) {
		float flake = hash13(floor(world_pos * flake_scale));
		flake = smoothstep(0.90, 1.0, flake);
		ALBEDO += vec3(flake * flake_strength * body * near);
	}

	// The lacquer: a second, much sharper specular lobe over everything painted, and over glass.
	// Matte paint drops its own coat to zero but the glass keeps one.
	CLEARCOAT = max(clearcoat_amount * body, glass_clearcoat * glass);
	CLEARCOAT_ROUGHNESS = clearcoat_roughness_value;
}
