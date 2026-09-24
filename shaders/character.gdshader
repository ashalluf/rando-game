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
// TARGET brightness for the upper garment, 0 black to 1 white, in gamma space. It used to be a
// multiplier on the source texture's own value, which cannot work: the source garments are dark
// (0.30-0.40, and the trousers nearer 0.10), so a multiplier can darken a garment but can never
// lift one to a white shirt, and the whole city walked around in black. The source's brightness
// is kept as SHADING around this target instead - see the `shade` term in fragment().
uniform float cloth_value = 0.45;
// How strongly the garment takes the new colour. 0 leaves the original outfit alone.
uniform float cloth_strength = 0.7;
// The lower garment (trousers, skirt), the same three knobs again - pants_value is a target
// brightness too. Rolled independently of the top, and weighted toward denim, black and khaki
// the way a street actually looks.
uniform float pants_hue = 0.60;
uniform float pants_sat = 0.22;
uniform float pants_value = 0.22;
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
// Baked tangent-space surface detail for this rig (tools/make_character_maps.py): cloth weave
// and seams, skin pores and the brow, hair strands. The source models ship one flat 1K colour
// photo and nothing else, so with no normal map a whole crowd reflects light like billiard
// balls. The committed maps carry a tangent slope of std 0.146, about 8 degrees, which is the
// difference between knit and vinyl.
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
// 0 keeps the mesh normal, which is what a rig with no baked map gets. Set from pedestrian.gd.
uniform float normal_strength = 0.0;
// Per-character skin tone, as a multiplier on whatever the source texture has. Three models
// with one complexion each is the second loudest tell (after everyone walking in step) that a
// crowd is three people copied a thousand times.
uniform vec3 skin_tint : source_color = vec3(1.0, 1.0, 1.0);
// The player's tracksuit (Pedestrian.tracksuit_material). `velour` is the sheen of the pile:
// velour and velvet are brighter at a grazing angle than head on, which is the whole look of
// the fabric - without it a matching jacket and trousers read as a boiler suit. `piping` draws
// two stripes down the outside of each sleeve and leg from the per-vertex data
// Pedestrian.add_piping() bakes into CUSTOM0 (signed distance round the limb from its outer
// line in metres, how much of the vertex follows an arm or leg bone, and how far it faces
// outward); a mesh without that data reads zero there and gets no stripes.
uniform float velour = 0.0;
uniform float piping = 0.0;
uniform vec3 piping_color : source_color = vec3(0.95, 0.95, 0.93);
// Centre of each stripe from the outer line, and its width, in metres.
uniform float piping_offset = 0.011;
uniform float piping_width = 0.010;
// How much of the source texture's value shading a recoloured garment keeps (1 all of it). The
// source garments are patterned - panels, patches, pockets - and a plain tracksuit keeps only
// its folds.
uniform float cloth_shade_keep = 1.0;
// With piping on, only vertices the rig's head and hands move can be skin, and the head is where
// the head bone moves the mesh rather than a height band (CUSTOM1, from add_piping): the hero's
// source jacket has tan leather yokes that pass every colour test for skin, and the height band
// - set for the crowd's average build - took in his collar and shoulders.
// Blood soaking through the clothes round a gunshot (Ragdoll._place_stain). Up to four wounds,
// each a point on the posed body in skeleton space (the same space as VERTEX here, centimetres on
// these rigs) with its radius in w; the ragdoll moves each one with the bone it landed on and
// grows it as it soaks. Only a shot body's own copy of its look's material carries any: every
// living pedestrian has wound_count 0, so the whole crowd skips the branch.
uniform float wound_count = 0.0;
uniform vec4 wound_0 = vec4(0.0);
uniform vec4 wound_1 = vec4(0.0);
uniform vec4 wound_2 = vec4(0.0);
uniform vec4 wound_3 = vec4(0.0);
// Soaked blood, in gamma space like the garment colours: a dark wet red, darker still on dark cloth.
uniform vec3 wound_blood = vec3(0.34, 0.022, 0.018);
// Clothes worn for months outdoors (RoughSleeper.worn_material): grime through the cloth, heaviest
// at the cuffs, the knees and the seat, patchy rather than a flat darkening. 0 for everyone else,
// so the crowd skips the branch. The person's skin, face and hair are left as they are.
uniform float grime = 0.0;
uniform vec3 grime_color = vec3(0.22, 0.18, 0.13);

// Height up the body, 0 at the soles and 1 at the crown.
varying float v_height;
varying vec3 v_pipe;
varying vec3 v_bind;
// The posed vertex in skeleton space, for the wound stains.
varying vec3 v_skel;


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


float stain_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}


float stain_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(stain_hash(i), stain_hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(stain_hash(i + vec3(0.0, 1.0, 0.0)), stain_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(stain_hash(i + vec3(0.0, 0.0, 1.0)), stain_hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(stain_hash(i + vec3(0.0, 1.0, 1.0)), stain_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}


// How soaked the point `p` is by one wound: a patch whose edge wanders by two octaves of noise,
// so it reads as blood that spread through the weave rather than a painted circle.
float wound_soak(vec4 w, vec3 p) {
	if (w.w <= 0.0) {
		return 0.0;
	}
	float d = length(p - w.xyz) / w.w;
	float n = stain_noise(p * 0.16) * 0.65 + stain_noise(p * 0.45) * 0.35;
	return 1.0 - smoothstep(0.55, 0.92, d + (n - 0.5) * 0.55);
}


vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}


void vertex() {
	// Skeleton space, not world space: a ragdoll tumbling through the air keeps its trousers on
	// its legs, and a taller or wider pedestrian still has its waistband in the same place.
	v_height = VERTEX.y / body_height;
	v_pipe = CUSTOM0.xyz;
	v_bind = CUSTOM1.xyz;
	v_skel = VERTEX;
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
	if (piping > 0.0) {
		is_skin *= smoothstep(0.04, 0.2, v_bind.x + v_bind.y);
	}
	// Very dark pixels are seams, folds and shadow; leave them their own colour.
	float is_cloth = (1.0 - is_skin) * smoothstep(cloth_value_lo, cloth_value_hi, hsv.z);

	float head = smoothstep(hair_line - hair_blend, hair_line + hair_blend, v_height);
	if (piping > 0.0) {
		head = smoothstep(0.35, 0.75, v_bind.x);
	}
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
	// Worked in gamma space, so the shading term below behaves the same on both renderers: the
	// Compatibility one hands back raw sRGB texels and Forward+ linearises them, and a fold that
	// is a 20 % dip in gamma is a 45 % dip in linear.
	// cloth_value / pants_value are the garment's own brightness, not a multiplier on the
	// source's. The source's value becomes SHADING around it: `shade` is 1.0 where the texture
	// sits at its garment value (~0.35) and falls toward 0.55 in the folds and the shadow under
	// a hem, so the cloth keeps its creases while the colour is genuinely chosen here. A
	// multiplier could not do that - the trousers on these rigs are nearly black in the texture,
	// so no multiplier reaches a pale chino, and every pedestrian in the city wore black.
	float gz = value_is_linear > 0.5 ? to_gamma(hsv.z) : hsv.z;
	float shade = mix(1.0, clamp(0.55 + 1.30 * gz, 0.35, 1.35), cloth_shade_keep);
	vec3 top_target = hsv_to_rgb(vec3(cloth_hue, cloth_sat, min(cloth_value * shade, 0.96)));
	vec3 low_target = hsv_to_rgb(vec3(pants_hue, pants_sat, min(pants_value * shade, 0.96)));
	vec3 garment = mix(top_target, low_target, lower);
	if (value_is_linear > 0.5) {
		garment = to_linear(garment);
	}
	// The head is excluded: without this the hair takes the shirt colour, and everybody in the
	// city walks around with hair that matches what they are wearing.
	float garment_mix = is_cloth * mix(cloth_strength, pants_strength, lower) * (1.0 - head);
	if (piping > 0.0) {
		// The shoes are not part of the tracksuit.
		garment_mix *= 1.0 - smoothstep(0.55, 0.85, v_bind.z);
	}

	vec3 albedo = mix(base, garment, garment_mix);
	// The replacement hair keeps the source's own shading so it still reads as strands.
	float hair_shade = clamp(hair_shade_bias + hair_shade_gain * gz, 0.0, 1.5);
	albedo = mix(albedo, hair_color * hair_shade, is_hair * hair_strength);
	if (piping > 0.0) {
		// Distance from the nearer stripe's centre line, anti-aliased by the screen rate of the
		// interpolated distance. v_pipe.z keeps it on the outer half of the limb: the signed
		// distance wraps from +pi r to -pi r on the inner side, and a triangle across the wrap
		// would otherwise interpolate through zero and draw a stripe down the inside leg.
		float a = v_pipe.x;
		float off = abs(abs(a) - piping_offset);
		float fw = max(fwidth(a), 1e-4);
		float stripe = 1.0 - smoothstep(piping_width * 0.5 - fw, piping_width * 0.5 + fw, off);
		stripe *= smoothstep(0.55, 0.85, v_pipe.y) * smoothstep(0.3, 0.6, v_pipe.z) * (1.0 - is_skin) * (1.0 - head) * piping;
		albedo = mix(albedo, piping_color * clamp(0.62 + 0.55 * gz, 0.6, 1.05), stripe);
	}
	ALBEDO = albedo * mix(vec3(1.0), skin_tint, is_skin);
	float grimed = 0.0;
	if (grime > 0.0) {
		float gn = stain_noise(v_skel * 0.07) * 0.6 + stain_noise(v_skel * 0.23) * 0.4;
		float low = 1.0 - smoothstep(0.04, 0.55, v_height);
		grimed = grime * (0.3 + 0.7 * gn) * mix(0.5, 1.0, low) * (1.0 - is_skin) * (1.0 - head);
		vec3 dirt = value_is_linear > 0.5 ? to_linear(grime_color) : grime_color;
		ALBEDO = mix(ALBEDO, ALBEDO * 0.5 + dirt * 0.35, clamp(grimed, 0.0, 0.85));
	}
	float soak = 0.0;
	if (wound_count > 0.5) {
		soak = max(max(wound_soak(wound_0, v_skel), wound_soak(wound_1, v_skel)),
			max(wound_soak(wound_2, v_skel), wound_soak(wound_3, v_skel)));
		// Dark wet red over whatever it soaked into: nearly black on dark cloth, red on pale.
		vec3 soaked = wound_blood * (0.4 + 0.6 * clamp(gz * 1.6, 0.0, 1.0));
		if (value_is_linear > 0.5) {
			soaked = to_linear(soaked);
		}
		ALBEDO = mix(ALBEDO, soaked, soak * 0.92);
	}

	ROUGHNESS = mix(mix(cloth_roughness, skin_roughness, is_skin), hair_roughness, is_hair * hair_strength);
	ROUGHNESS = min(ROUGHNESS + grimed * 0.08, 1.0);
	// Soaked cloth is wet, and wet is glossy.
	ROUGHNESS = mix(ROUGHNESS, 0.24, soak);
	METALLIC = 0.0;
	// Godot builds a dielectric's F0 as 0.16 * SPECULAR^2, so the old 0.45 / 0.32 meant F0 0.032
	// for cloth and 0.016 for skin - skin reflected less than water does (0.020), which is what
	// left faces reading as matte cardboard. Measured F0 is 0.040 for a generic dielectric
	// (IOR 1.5) and 0.028 for skin (IOR 1.4); those are SPECULAR 0.50 and 0.42. Skin stays the
	// lower of the two, as it should be - it was just far too low.
	SPECULAR = mix(0.50, 0.42, is_skin);
	// Velour's pile scatters rather than mirrors; its shine is the rim below, not a hot spot.
	SPECULAR = mix(SPECULAR, 0.28, clamp(velour * 2.0, 0.0, 1.0) * garment_mix);
	// The baked relief. normal_strength is 0 for any rig with no map, and at 0 Godot blends
	// straight back to the geometric normal, so an unbound sampler here is harmless rather
	// than a white wall of noise. Declaring these two uniforms without ever sampling them -
	// which is how this landed the first time - renders exactly the flat mannequin it was
	// meant to fix, and looks from the outside like the feature is in.
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	// Thin extremities catch light from behind the way real skin does.
	BACKLIGHT = vec3(skin_subsurface * is_skin * 0.5);
	// Velour pile: Godot's rim lobe is exactly the brighter-at-grazing sheen, tinted mostly by
	// the fabric's own colour.
	RIM = velour * garment_mix;
	RIM_TINT = 0.6;
}
