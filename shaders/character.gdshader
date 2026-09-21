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
// Skin and clothes are told apart by hue, saturation AND brightness. Hue and saturation alone
// are not enough on these rigs: pedestrian_c wears a warm brown jacket and warm brown trousers
// over warm brown skin, so a hue test called every pixel on it skin and left the whole model in
// one colour. Brightness is what actually separates them - on both rigs lit skin sits at a
// texture value of 0.65-0.95 while every garment and the hair sit at 0.30-0.40.
//
// The body is then cut into three bands by height, so one texture yields a separate top, a
// separate pair of trousers and a separate hair colour. Real people almost never wear one colour
// from collar to ankle, and a crowd where everybody does is the loudest remaining tell that they
// came out of the same file.
//
// IMPORTANT: every threshold below that is compared against a *texture value* is set from
// pedestrian.gd in the colour space the current renderer hands `source_color` textures back in.
// Forward+ and Mobile linearise them; the Compatibility renderer (the web build) does not. The
// defaults here are the Compatibility (raw sRGB) numbers - the ones you read off the texture
// file in an image viewer. See Pedestrian._texture_value().

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
// The source hair's own shading (strands, roots, the shadow where it meets the ear) mapped onto
// whatever colour replaces it, as `bias + gain * value`. Fitted in pedestrian.gd across
// HAIR_SHADE_BAND and applied to the gamma-space value, so a head shades the same on both
// renderers instead of going flat on the one that linearises.
uniform float hair_shade_gain = 1.667;
uniform float hair_shade_bias = 0.25;
// 1 when this renderer hands `source_color` textures back already linearised (Forward+, Mobile),
// 0 on the Compatibility renderer, which returns the raw sRGB texels. Set from pedestrian.gd.
// The garment colours are built in gamma space either way, because that is the space cloth_sat
// and cloth_value were tuned in: mixing them against a linear source value instead dropped every
// shirt in the city to the same dark grey.
uniform float value_is_linear = 0.0;
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
// Skin has to be bright as well as warm. This is the band a pixel's value crosses to count as
// lit skin rather than cloth; it is the one test that works on a rig whose clothes are the same
// hue as its skin. Measured across both rigs: garments and hair top out near 0.40, skin starts
// near 0.65, so the band sits in the gap with room either side.
uniform float skin_value_lo = 0.44;
uniform float skin_value_hi = 0.62;
// Hair is the dark part of the head band and the face is the bright part, so hair is found by
// darkness, not by failing the skin test - dark warm brown hair passes a hue-and-saturation
// skin test outright, which is why the hair colour used to change nothing at all.
uniform float hair_value_lo = 0.32;
uniform float hair_value_hi = 0.55;
// Below cloth_value_lo a pixel is a seam, a deep fold or the shadow under a hem, where hue is
// meaningless; recolouring it makes the fabric look printed on. Kept low enough that dark denim
// still recolours, which at the old 0.10-0.24 it only half did.
uniform float cloth_value_lo = 0.045;
uniform float cloth_value_hi = 0.13;
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


// sRGB transfer curve, both ways. Only used on the garment path, and only on the renderers that
// need it (the branch is on a uniform, so it is coherent and costs nothing where it is false).
float to_gamma(float c) {
	return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(max(c, 0.0), 1.0 / 2.4) - 0.055;
}


vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow(max((c + 0.055) / 1.055, vec3(0.0)), vec3(2.4)), step(vec3(0.04045), c));
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

	// Skin is warm AND reasonably saturated AND bright. All three are needed: hue alone lets
	// washed-out grey fabric pass as skin (grey has an arbitrary hue), saturation alone rejects
	// skin that is strongly lit or deep in shadow, which is what turned faces and hands pink,
	// and hue plus saturation alone lets a brown garment on brown skin pass, which left one of
	// the two rigs - half the crowd - in a single colour from soles to crown.
	float hue_dist = abs(fract(hsv.x - skin_hue + 0.5) - 0.5);
	float warm = 1.0 - smoothstep(cloth_guard, cloth_guard * 2.0, hue_dist);
	float is_skin = warm * smoothstep(0.10, 0.19, hsv.y) * smoothstep(skin_value_lo, skin_value_hi, hsv.z);
	// Very dark pixels are seams, folds and shadow; leave them their own colour.
	float is_cloth = (1.0 - is_skin) * smoothstep(cloth_value_lo, cloth_value_hi, hsv.z);

	float head = smoothstep(hair_line - hair_blend, hair_line + hair_blend, v_height);
	// On the head, hair is the dark half and the face is the bright half. Testing for darkness
	// directly is the only thing that finds it: hair is warm and saturated, so it passes the
	// skin test, and a gate of the form (1.0 - is_skin) on its own collapses to nothing.
	float is_hair = head * (1.0 - is_skin) * (1.0 - smoothstep(hair_value_lo, hair_value_hi, hsv.z));
	// Below the waistband is the lower garment, above it the top. Feathered, because a hard
	// plane across the hips reads as a seam in the wrong place on a body of the wrong height.
	float lower = 1.0 - smoothstep(waist - waist_blend, waist + waist_blend, v_height);

	// Recolour rather than hue-rotate. The source outfits are mostly grey and olive, and
	// rotating the hue of a desaturated pixel changes nothing, so a rotation left every
	// character wearing the same clothes.
	//
	// Built from the source's brightness in gamma space, so the garment keeps the folds and the
	// shading of the cloth underneath it, and so cloth_sat / cloth_value / pants_value land where
	// they were tuned. Against a linear source value the same numbers give a much narrower and
	// much darker spread, which is what put the whole crowd back in one dark grey outfit.
	// Clamped, because the value multipliers now run past 2 so that a pale garment is reachable
	// at all (the source cloth sits at about 0.35), and hsv_to_rgb() of a value over 1 followed
	// by to_linear() runs away fast. The ceiling is just under white so a shirt keeps a little
	// of its own shading at the top end.
	float gz = value_is_linear > 0.5 ? to_gamma(hsv.z) : hsv.z;
	vec3 top_target = hsv_to_rgb(vec3(cloth_hue, cloth_sat, min(gz * cloth_value, 0.96)));
	vec3 low_target = hsv_to_rgb(vec3(pants_hue, pants_sat, min(gz * pants_value, 0.96)));
	vec3 garment = mix(top_target, low_target, lower);
	if (value_is_linear > 0.5) {
		garment = to_linear(garment);
	}
	// The head is excluded: without this the hair takes the shirt colour, and everybody in the
	// city walks around with hair that matches what they are wearing.
	float garment_mix = is_cloth * mix(cloth_strength, pants_strength, lower) * (1.0 - head);

	vec3 albedo = mix(base, garment, garment_mix);
	// The replacement hair keeps the source's own shading so it still reads as strands.
	float hair_shade = clamp(hair_shade_bias + hair_shade_gain * gz, 0.0, 1.5);
	albedo = mix(albedo, hair_color * hair_shade, is_hair * hair_strength);
	ALBEDO = albedo * mix(vec3(1.0), skin_tint, is_skin);

	ROUGHNESS = mix(mix(cloth_roughness, skin_roughness, is_skin), hair_roughness, is_hair * hair_strength);
	METALLIC = 0.0;
	SPECULAR = mix(0.45, 0.32, is_skin);
	// Thin extremities catch light from behind the way real skin does.
	BACKLIGHT = vec3(skin_subsurface * is_skin * 0.5);
}
