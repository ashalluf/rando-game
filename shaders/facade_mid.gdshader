shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// What FacadeMid hangs on a Building's storeys between the street and the roof (balcony life,
// sleeve ACs, vents, satellite dishes, open windows, roof flashing, painted wall signs): one mesh a
// building, one draw. What a face is rides in the vertex alpha (kind / 16, FacadeMid.K_*), its
// colour in COLOR.rgb as written (sRGB, decoded here: vertex colours arrive raw on both renderers),
// UV in metres along the piece (0..1 on leaf cards and rooms, the card's seed in the integer part),
// UV2.x 1 on a room that is lit after dark. Linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

varying flat float kind;
varying vec3 wpos;

float fm_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fm_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fm_hash(i), fm_hash(i + vec2(1.0, 0.0)), f.x),
		mix(fm_hash(i + vec2(0.0, 1.0)), fm_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	kind = floor(COLOR.a * 16.0 + 0.5);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = cs_srgb_to_linear(COLOR.rgb);
	float rough = 0.6;
	float metal = 0.0;
	float spec = 0.4;
	vec3 em = vec3(0.0);
	float px = length(fwidth(wpos));
	float mott = fm_noise(UV * vec2(6.0, 3.0));
	if (kind < 0.5) {
		// Painted metal: a little chalky.
		c *= 0.9 + 0.2 * mott;
		rough = 0.5 + 0.15 * mott;
		metal = 0.1;
	} else if (kind < 1.5) {
		// Galvanised steel.
		c = vec3(0.40, 0.41, 0.40) * (0.82 + 0.3 * fm_noise(UV * 22.0));
		rough = 0.48;
		metal = 0.7;
	} else if (kind < 2.5) {
		// Cloth: a weave under a pixel fades to its mean, folds as slow bands.
		float weave = 0.5 + 0.5 * sin(UV.x * 900.0) * sin(UV.y * 900.0);
		weave = mix(weave, 0.5, smoothstep(0.0005, 0.002, px));
		float folds = 0.82 + 0.18 * sin(UV.x * 21.0 + fm_noise(UV * 3.0) * 4.0);
		c *= folds * (0.94 + 0.12 * weave);
		rough = 0.88;
		spec = 0.25;
	} else if (kind < 3.5) {
		// A leaf card: leaves cut out of it (blobs of noise thinning to the top and the sides),
		// the seed in the integer part of UV.x.
		vec2 q = fract(UV);
		float sd = floor(UV.x);
		float n1 = fm_noise(q * vec2(6.0, 5.0) + sd * 3.1);
		float n2 = fm_noise(q * vec2(19.0, 17.0) + sd * 1.7);
		float n3 = fm_noise(q * vec2(41.0, 37.0) + sd * 0.9);
		// A rounded crown: fullest a little under the middle, its rim torn into leaves and gaps.
		float shape = 1.0 - length((q - vec2(0.5, 0.42)) * vec2(2.1, 1.9));
		float cover = n1 * 0.45 + n2 * 0.35 + n3 * 0.2 + shape * 0.9 - 0.62;
		if (cover < 0.0) {
			discard;
		}
		// Leaves in light and shade; a flowering card (UV2.x) is dark foliage with blooms of its colour.
		vec3 foliage = c;
		if (UV2.x > 0.5) {
			foliage = vec3(0.035, 0.07, 0.025);
			foliage = mix(foliage, c, step(0.6, n3) * step(0.45, n2));
		}
		c = foliage * (0.45 + 0.7 * n2 * n3 + 0.25 * smoothstep(0.0, 0.25, cover));
		rough = 0.7;
		spec = 0.35;
		BACKLIGHT = cs_out(c * 0.12);
	} else if (kind < 4.5) {
		// Terracotta or glazed pot.
		c *= 0.88 + 0.22 * fm_noise(UV * vec2(20.0, 8.0));
		rough = 0.8;
	} else if (kind < 5.5) {
		// Moulded plastic: a little gloss, dulled where it faces up.
		c *= 0.95 + 0.08 * mott;
		rough = 0.42;
		spec = 0.45;
	} else if (kind < 6.5) {
		// The room behind an open window: a dark warm interior, a ceiling lit from the window, a
		// curtain (the vertex colour) drawn to the sides, a lamp after dark on some.
		vec2 q = UV;
		float room_v = mix(0.05, 0.13, q.y);
		vec3 room = vec3(0.10, 0.075, 0.055) * room_v * 6.0;
		float folds = 0.75 + 0.25 * sin(q.x * 60.0 + fm_noise(q * 4.0) * 3.0);
		float curtain = 1.0 - smoothstep(0.16, 0.24, min(q.x, 1.0 - q.x));
		curtain *= 0.85 + 0.15 * q.y;
		c = mix(room, cs_srgb_to_linear(COLOR.rgb) * 0.55 * folds, curtain);
		rough = 0.95;
		spec = 0.1;
		float night = clamp(lamp_factor, 0.0, 1.0) * UV2.x;
		vec3 lamp = vec3(1.0, 0.72, 0.42);
		em = mix(lamp * 0.9 * (0.6 + 0.4 * q.y), cs_srgb_to_linear(COLOR.rgb) * lamp * 1.6 * folds, curtain) * night;
	} else if (kind < 7.5) {
		// The glass of a casement swung out: dark, glossy, mirroring the sky.
		c = vec3(0.025, 0.03, 0.035);
		rough = 0.05;
		spec = 0.6;
	} else if (kind < 8.5) {
		// Hand-painted sign paint: brush streaks, chalked by the sun, flaking off to the wall.
		vec2 w = vec2(dot(wpos.xz, vec2(0.7071, 0.7071)), wpos.y);
		float flake = fm_noise(w * 5.0) * 0.6 + fm_noise(w * 19.0) * 0.4;
		float wear = fm_noise(w * 0.7);
		if (flake < 0.16 + 0.22 * wear && px < 0.03) {
			discard;
		}
		float streak = 0.92 + 0.08 * fm_noise(vec2(UV.x * 40.0, UV.y * 2.0));
		c = mix(c, vec3(0.62, 0.60, 0.56) * dot(c, vec3(0.3, 0.6, 0.1)) + c * 0.4, 0.25 * wear) * streak;
		rough = 0.85;
		spec = 0.3;
	} else if (kind < 9.5) {
		// Wood or a reed screen: slats run up it.
		float slat = 0.85 + 0.15 * sin(UV.x * 160.0);
		slat = mix(slat, 0.92, smoothstep(0.003, 0.01, px));
		c *= slat * (0.9 + 0.2 * fm_noise(vec2(UV.x * 60.0, UV.y * 2.0)));
		rough = 0.85;
		spec = 0.3;
	} else if (kind < 10.5) {
		// A louvred grille: dark slots between lit blades, their average under a pixel.
		float blade = smoothstep(0.35, 0.5, fract(UV.y / 0.025)) * (1.0 - smoothstep(0.85, 1.0, fract(UV.y / 0.025)));
		blade = mix(blade, 0.45, smoothstep(0.004, 0.012, px));
		c *= 0.25 + 0.95 * blade;
		rough = 0.6;
		metal = 0.2;
	} else if (kind < 11.5) {
		// Rubber, a line, a cable.
		rough = 0.75;
	} else if (kind < 12.5) {
		// A dish: painted steel or white plastic, dirt in the bowl's bottom, a sheen.
		c *= 0.9 + 0.1 * fm_noise(UV * 30.0);
		c *= 1.0 - 0.18 * smoothstep(0.5, 0.0, UV.x);
		rough = 0.38;
		spec = 0.5;
	} else {
		// Potting soil.
		c *= 0.8 + 0.3 * fm_noise(UV * 80.0);
		rough = 0.95;
		spec = 0.2;
	}
	// Rain darkens what is out in it.
	float wet = clamp(road_wetness, 0.0, 1.0) * step(kind, 9.5) * (1.0 - step(5.5, kind) * step(kind, 7.5));
	c *= 1.0 - 0.25 * wet;
	rough = mix(rough, rough * 0.55, wet);
	ALBEDO = cs_out(c);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = cs_out(em);
}
