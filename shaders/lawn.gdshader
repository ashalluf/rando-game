shader_type spatial;

// Lawns and park grass. The block interiors fill a huge share of any wide shot, and a single
// tiled grass texture mips down to one flat green rectangle from thirty metres up - which is
// exactly what a park looked like from the air. The grass blade multimesh only covers the
// first few dozen metres, so past that the ground itself has to carry the detail.
//
// Everything here is generated from world position, so it tiles seamlessly across chunks and
// never repeats visibly, and all of it survives mipping because it works at metres rather than
// at texel scale:
//   - slow patchiness between watered green and dry straw, the single most recognisable thing
//     about real grass and the thing a flat tint cannot fake
//   - mower stripes: wide alternating bands, angled per lawn, lighter one way than the other
//     because bent blades reflect differently. Parks and verges are cut, so they have them.
//   - worn dirt where feet go: thin along the edges of the lawn and in sparse desire paths
//   - the same second rotated texture fetch the road shader uses to kill the visible tile grid,
//     gated on the `ground_detail` global so the web and the low quality levels skip it.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
// Watered and parched. A lawn is a blend of the two, not one colour.
uniform vec3 tint : source_color = vec3(0.42, 0.56, 0.24);
uniform vec3 dry_tint : source_color = vec3(0.62, 0.58, 0.30);
uniform vec3 dirt_tint : source_color = vec3(0.34, 0.28, 0.20);
// Metres per texture tile.
uniform float tex_scale = 5.0;
uniform float seed = 0.0;
// How parched this lawn is overall: 0 a watered green, 1 mostly straw.
uniform float dryness : hint_range(0.0, 1.0) = 0.30;
// Mower stripe width in metres, and how strongly they show. 0 width turns them off.
uniform float stripe_width = 3.4;
uniform float stripe_amount : hint_range(0.0, 1.0) = 0.075;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.30;
uniform float normal_depth = 0.7;

global uniform float ground_detail;
// Night. Roads and pavements are lit by street lamps; open grass is not - it gets skylight only,
// which is dim and blue. The engine's ambient does not know that, so an untouched lawn stays a
// vivid green after dark and ends up the brightest thing in the frame, brighter than the lit
// shopfronts. This darkens and desaturates unlit grass toward what a lawn actually looks like at
// night. DayNight publishes night_factor; the same value drives the street lamps.
global uniform float night_factor;
uniform float night_darken : hint_range(0.0, 1.0) = 0.72;

varying vec3 world_pos;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


float fbm(vec2 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.3 + 11.0) * 0.28 + vnoise(p * 5.1 + 31.0) * 0.12;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 wp = world_pos.xz;
	vec2 uv = wp / tex_scale;

	vec3 alb = texture(albedo_tex, uv).rgb;
	vec3 nrm = texture(normal_tex, uv).rgb;
	float rough = texture(rough_tex, uv).r;

	// Second fetch, rotated and at a different scale, cross-faded on slow noise. Without it the
	// texture's own tile grid is the first thing the eye finds on a big lawn.
	if (ground_detail > 0.5) {
		vec2 rot = vec2(uv.x * 0.7071 - uv.y * 0.7071, uv.x * 0.7071 + uv.y * 0.7071) * 0.63;
		float blend = smoothstep(0.35, 0.65, vnoise(wp * 0.035 + seed));
		alb = mix(alb, texture(albedo_tex, rot).rgb, blend);
		nrm = mix(nrm, texture(normal_tex, rot).rgb, blend);
		rough = mix(rough, texture(rough_tex, rot).r, blend);
	}

	// Watered vs parched, in patches a few metres across. Kept gentle: at full contrast whole
	// blocks came out solid straw, which is just the flat-rectangle problem in another colour.
	float dry = clamp(fbm(wp * 0.055 + seed * 1.7) * 0.9 + (dryness - 0.5) * 0.8, 0.0, 1.0);
	vec3 col = mix(tint, dry_tint, dry);

	// Mower stripes. Angled per lawn off the seed so neighbouring lawns are not cut the same way.
	// The whole band is one smooth sine, NOT sign() with a soft edge: sign() steps between two
	// tones and the lawn comes out candy-striped, which is louder than the flat green it
	// replaced. This is a change of sheen you notice only once you look for it.
	if (stripe_width > 0.01) {
		float a = seed * 0.9;
		vec2 dir = vec2(cos(a), sin(a));
		float band = sin(dot(wp, dir) * 3.14159 / stripe_width);
		col *= 1.0 + band * stripe_amount;
		rough *= 1.0 - band * 0.06;
	}

	// Worn dirt: sparse bald patches where the grass has been walked off.
	float wear = smoothstep(0.62, 0.86, fbm(wp * 0.09 + 57.0 + seed)) * wear_amount;
	col = mix(col, dirt_tint, wear);
	rough = mix(rough, 0.95, wear);

	// No boost. The road shader next to it writes its albedo straight, and a lawn lit 15% hotter
	// than the road it borders is what made the grass the brightest thing in a night frame: the
	// camera's auto exposure opens up after dark, and the most saturated surface then dominates.
	// Real grass is about twice the albedo of asphalt, which the tint already carries.
	vec3 lit = alb * col;
	// Toward a dim desaturated blue-grey as night comes in.
	float nf = clamp(night_factor, 0.0, 1.0) * night_darken;
	float grey = dot(lit, vec3(0.299, 0.587, 0.114));
	lit = mix(lit, mix(vec3(grey), vec3(grey * 0.78, grey * 0.84, grey * 1.05), 0.7) * 0.30, nf);
	ALBEDO = lit;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - wear * 0.6);
	ROUGHNESS = clamp(rough, 0.35, 1.0);
	SPECULAR = 0.22;
}
