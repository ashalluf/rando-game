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
// Strength of the clear lacquer over the basecoat.
uniform float clearcoat_amount = 0.85;
uniform float clearcoat_roughness_value = 0.035;
// Metallic flake: fine sparkle in the basecoat, only visible up close.
uniform float flake_strength = 0.045;
uniform float flake_scale = 190.0;
// Flake is only resolvable up close; past this many meters it is dropped, otherwise the
// sub-pixel grid aliases into crawling glitter over the whole panel.
uniform float flake_fade_distance = 9.0;

varying vec3 world_pos;


float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec4 base = texture(albedo_tex, UV);
	float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float body = smoothstep(dark_below, body_above, lum);
	vec3 painted = paint * (0.55 + 0.45 * lum * paint_brightness);
	vec3 dark = base.rgb * 0.6;
	ALBEDO = mix(dark, painted, body);

	float glass = 1.0 - smoothstep(0.02, dark_below, lum);
	float rough = mix(mix(0.6, 0.08, glass), paint_roughness, body);
	float metal = mix(mix(0.1, 0.5, glass), paint_metallic, body);

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
	if (near > 0.0) {
		float flake = hash13(floor(world_pos * flake_scale));
		flake = smoothstep(0.90, 1.0, flake);
		ALBEDO += vec3(flake * flake_strength * body * near);
	}

	// The lacquer: a second, much sharper specular lobe over everything painted, and over glass.
	CLEARCOAT = clearcoat_amount * max(body, glass);
	CLEARCOAT_ROUGHNESS = clearcoat_roughness_value;
}
