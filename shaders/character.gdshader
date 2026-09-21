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
//
// The body is then cut into three bands by height, so one texture yields a separate top, a
// separate pair of trousers and a separate hair colour. Real people almost never wear one colour
// from collar to ankle, and a crowd where everybody does is the loudest remaining tell that they
// came out of the same file.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
// The upper garment (shirt, jacket) for this character, as hue in turns and saturation.
uniform float cloth_hue = 0.0;
uniform float cloth_sat = 0.35;
// Brightness multiplier for clothing, so the same shirt reads as a lighter or darker garment.
uniform float cloth_value = 1.0;
// How strongly the garment takes the new colour. 0 leaves the original outfit alone.
uniform float cloth_strength = 0.7;
// The lower garment (trousers, skirt), the same three knobs again. Rolled independently of the
// top, and weighted toward denim, black and khaki the way a street actually looks.
uniform float pants_hue = 0.60;
uniform float pants_sat = 0.22;
uniform float pants_value = 0.70;
uniform float pants_strength = 0.7;
// Hair, taken outright rather than tinted: the source hair is nearly black, so a tint of it
// stays nearly black and every pedestrian keeps the same head.
uniform vec3 hair_color : source_color = vec3(0.09, 0.07, 0.06);
uniform float hair_strength = 0.0;
// The rig's own height in its own units. Skinning happens before vertex(), so VERTEX is the
// posed vertex in skeleton space, which for these models is centimetres (the skeleton is in cm
// under a 0.01 armature) with 0 at the soles and about 175 at the crown.
uniform float body_height = 175.0;
// Waistband height as a fraction of that, and how far the seam is feathered. The forearms hang
// just above it once fix_arm_pose() has brought the arms down, and the hands that do drop below
// it are skin, so no arm takes the trouser colour.
uniform float waist = 0.50;
uniform float waist_blend = 0.035;
// Chin height as a fraction. Above it, anything that is not skin is hair, a beard or an eyebrow,
// all of which want the same colour. The head is rigid, so this band does not swim while walking.
uniform float hair_line = 0.885;
uniform float hair_blend = 0.025;
// Hue of skin, in turns. Pixels within cloth_guard of it are never recoloured.
uniform float skin_hue = 0.06;
// How far from the skin hue a pixel must sit before it counts as dyed fabric.
uniform float cloth_guard = 0.055;
uniform float skin_roughness = 0.52;
uniform float cloth_roughness = 0.88;
uniform float hair_roughness = 0.58;
// How much light bleeds through skin. Keeps faces and hands from reading as plastic.
uniform float skin_subsurface = 0.35;
// Per-character skin tone, as a multiplier on whatever the source texture has. Three models
// with one complexion each is the second loudest tell (after everyone walking in step) that a
// crowd is three people copied a thousand times.
uniform vec3 skin_tint : source_color = vec3(1.0, 1.0, 1.0);

// Height up the body, 0 at the soles and 1 at the crown.
varying float v_height;


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


void vertex() {
	// Skeleton space, not world space: a ragdoll tumbling through the air keeps its trousers on
	// its legs, and a taller or wider pedestrian still has its waistband in the same place.
	v_height = VERTEX.y / body_height;
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

	float head = smoothstep(hair_line - hair_blend, hair_line + hair_blend, v_height);
	// Hair is darker than the cloth gate lets through, so it gets its own, much lower one.
	float is_hair = head * (1.0 - is_skin) * smoothstep(0.015, 0.06, hsv.z);
	// Below the waistband is the lower garment, above it the top. Feathered, because a hard
	// plane across the hips reads as a seam in the wrong place on a body of the wrong height.
	float lower = 1.0 - smoothstep(waist - waist_blend, waist + waist_blend, v_height);

	// Recolour rather than hue-rotate. The source outfits are mostly grey and olive, and
	// rotating the hue of a desaturated pixel changes nothing, so a rotation left every
	// character wearing the same clothes.
	vec3 top_target = hsv_to_rgb(vec3(cloth_hue, cloth_sat, hsv.z * cloth_value));
	vec3 low_target = hsv_to_rgb(vec3(pants_hue, pants_sat, hsv.z * pants_value));
	vec3 garment = mix(top_target, low_target, lower);
	// The head is excluded: without this the hair takes the shirt colour, and everybody in the
	// city walks around with hair that matches what they are wearing.
	float garment_mix = is_cloth * mix(cloth_strength, pants_strength, lower) * (1.0 - head);

	vec3 albedo = mix(base, garment, garment_mix);
	albedo = mix(albedo, hair_color * (0.35 + 1.30 * hsv.z), is_hair * hair_strength);
	ALBEDO = albedo * mix(vec3(1.0), skin_tint, is_skin);

	ROUGHNESS = mix(mix(cloth_roughness, skin_roughness, is_skin), hair_roughness, is_hair * hair_strength);
	METALLIC = 0.0;
	SPECULAR = mix(0.45, 0.32, is_skin);
	// Thin extremities catch light from behind the way real skin does.
	BACKLIGHT = vec3(skin_subsurface * is_skin * 0.5);
}
