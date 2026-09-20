shader_type spatial;
render_mode cull_disabled;

// Shared material for the rigged characters (pedestrians, ragdolls, the player's avatar).
//
// The source models carry one flat colour texture and nothing else: no normal map, no roughness
// map, and a glTF material that sets full white emission plus double specular, which renders a
// shiny self-lit mannequin. This shader throws that away and rebuilds sensible surface response,
// and it recolours clothing per character so a city built from three models does not read as
// three people copied a thousand times.
//
// Skin and clothes are told apart by saturation: skin sits in a narrow low-saturation band of
// warm tones, while dyed fabric is more saturated. Only the fabric gets hue-rotated, so nobody
// ends up with green arms.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
// The garment colour for this character, as hue in turns and saturation.
uniform float cloth_hue = 0.0;
uniform float cloth_sat = 0.35;
// Brightness multiplier for clothing, so the same shirt reads as a lighter or darker garment.
uniform float cloth_value = 1.0;
// How strongly the garment takes the new colour. 0 leaves the original outfit alone.
uniform float cloth_strength = 0.7;
// Hue of skin, in turns. Pixels within cloth_guard of it are never recoloured.
uniform float skin_hue = 0.06;
// How far from the skin hue a pixel must sit before it counts as dyed fabric.
uniform float cloth_guard = 0.055;
uniform float skin_roughness = 0.52;
uniform float cloth_roughness = 0.88;
// How much light bleeds through skin. Keeps faces and hands from reading as plastic.
uniform float skin_subsurface = 0.35;
// Per-character skin tone, as a multiplier on whatever the source texture has. Three models
// with one complexion each is the second loudest tell (after everyone walking in step) that a
// crowd is three people copied a thousand times.
uniform vec3 skin_tint : source_color = vec3(1.0, 1.0, 1.0);


vec3 rgb_to_hsv(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float d = mx - mn;
	float h = 0.0;
	if (d > 1e-5) {
		if (mx == c.r) {
			h = mod((c.g - c.b) / d, 6.0);
		} else if (mx == c.g) {
			h = (c.b - c.r) / d + 2.0;
		} else {
			h = (c.r - c.g) / d + 4.0;
		}
		h /= 6.0;
	}
	return vec3(h, mx <= 1e-5 ? 0.0 : d / mx, mx);
}


vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}


void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb_to_hsv(base);

	// Skin is warm AND reasonably saturated. Both tests are needed: hue alone lets washed-out
	// grey fabric pass as skin (grey has an arbitrary hue), and saturation alone rejects skin
	// that is strongly lit or deep in shadow, which is what turned faces and hands pink.
	float hue_dist = abs(fract(hsv.x - skin_hue + 0.5) - 0.5);
	float warm = 1.0 - smoothstep(cloth_guard, cloth_guard * 2.0, hue_dist);
	float is_skin = warm * smoothstep(0.10, 0.19, hsv.y);
	// Very dark pixels are hair, shoes and shadow; leave them their own colour.
	float is_cloth = (1.0 - is_skin) * smoothstep(0.10, 0.24, hsv.z);

	// Recolour rather than hue-rotate. The source outfits are mostly grey and olive, and
	// rotating the hue of a desaturated pixel changes nothing, so a rotation left every
	// character wearing the same clothes.
	vec3 target = hsv_to_rgb(vec3(cloth_hue, cloth_sat, hsv.z * cloth_value));
	ALBEDO = mix(base, target, is_cloth * cloth_strength) * mix(vec3(1.0), skin_tint, is_skin);

	ROUGHNESS = mix(cloth_roughness, skin_roughness, is_skin);
	METALLIC = 0.0;
	SPECULAR = mix(0.45, 0.32, is_skin);
	// Thin extremities catch light from behind the way real skin does.
	BACKLIGHT = vec3(skin_subsurface * is_skin * 0.5);
}
