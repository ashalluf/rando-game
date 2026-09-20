shader_type spatial;
render_mode cull_back;

// Car paint over a single-material model whose base color was greyscaled: light pixels are
// bodywork and take the paint (metallic, glossy), dark pixels are glass, tires and trim and
// stay dark and glossy. Keeps one texture set per model.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform vec3 paint : source_color = vec3(0.8, 0.1, 0.1);
// Luminance below which a pixel counts as glass or rubber, and above which it is bodywork.
uniform float dark_below = 0.16;
uniform float body_above = 0.38;
uniform float paint_metallic = 0.75;
uniform float paint_roughness = 0.28;
uniform float paint_brightness = 1.35;


void fragment() {
	vec4 base = texture(albedo_tex, UV);
	float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float body = smoothstep(dark_below, body_above, lum);
	vec3 painted = paint * (0.55 + 0.45 * lum * paint_brightness);
	vec3 dark = base.rgb * 0.6;
	ALBEDO = mix(dark, painted, body);
	// Glass and chrome-ish trim are glossy; rubber is matte-ish: split by darkness.
	float glass = 1.0 - smoothstep(0.02, dark_below, lum);
	ROUGHNESS = mix(mix(0.6, 0.12, glass), paint_roughness, body);
	METALLIC = mix(mix(0.1, 0.5, glass), paint_metallic, body);
	SPECULAR = 0.6;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.6;
	}
}
