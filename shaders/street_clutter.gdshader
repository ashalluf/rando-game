shader_type spatial;
render_mode cull_back;

// Street clutter (scripts/world/street_clutter.gd): news boxes, magazine racks, A-frame boards,
// gutter litter. One material for all of it, so each kind is one MultiMesh draw a chunk.
//
// * Vertex colour alpha says what a face is: 0 the vertex colour is the colour, 1 the
//   instance's paint (INSTANCE_CUSTOM.rgb), 0.25 a newspaper front page behind glass, 0.5 a
//   magazine cover, 0.75 chalk on a slate. Printed faces have UV 0..1 over the page; UV.x's
//   whole part picks which cover or which board side, INSTANCE_CUSTOM.a which copy.
// * UV2 is (roughness, metallic) per part. UV elsewhere is metres, for the painted-steel detail
//   map (ambientCG Metal016), which is taken as detail only (its luminance over its mean).
// * Colour space: Forward+ decodes source_color uniforms and textures but not vertex colours or
//   instance data, Compatibility decodes nothing; `color_space_probe` tells them apart (the same
//   trick as facade_kit.gdshaderinc). Every colour written here is sRGB.
// * Weathering: grime creeping up from the pavement, and old stickers on the painted steel.
//   Fine print fades to its average grey once a line is under a pixel, or it shimmers.

uniform sampler2D detail_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_detail = true;
uniform float detail_tile = 0.45;
uniform float tex_mean_linear = 0.73;
uniform float tex_mean_srgb = 0.86;
uniform float detail = 0.3;
uniform float normal_strength = 0.45;
uniform float grime = 0.4;
uniform float grime_height = 0.28;
uniform float stickers = 0.055;
uniform vec3 color_space_probe : source_color = vec3(0.5, 0.5, 0.5);

varying vec3 v_base;
varying vec3 v_local;
varying vec3 v_normal_local;
varying float v_mode;
varying float v_paint;
varying float v_seed;
varying float v_fwd;

vec3 sc_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 sc_col(vec3 srgb) {
	return v_fwd > 0.5 ? sc_linear(srgb) : srgb;
}

float sc_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float sc_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(sc_hash(i), sc_hash(i + vec2(1.0, 0.0)), f.x),
		mix(sc_hash(i + vec2(0.0, 1.0)), sc_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// How much of a pattern with `per_unit` cycles per UV unit survives at this pixel's footprint
// (1 crisp, 0 blurred to its average).
float sc_keep(vec2 uv, float per_unit) {
	float fw = max(fwidth(uv.x), fwidth(uv.y)) * per_unit;
	return 1.0 - smoothstep(0.35, 0.9, fw);
}

// A line of type: words of hashed length along x, `row` picks the line. 1 = ink.
float sc_words(float x, float row, float seed, float chars_per_unit) {
	float cx = x * chars_per_unit;
	float word = floor(cx / 5.0 + sc_hash(vec2(row, seed)) * 3.0);
	float gap = step(0.82, fract(cx / 5.0 + sc_hash(vec2(row, seed)) * 3.0));
	float letter = step(0.25, fract(cx)) * step(0.3, sc_hash(vec2(floor(cx), row + seed)));
	return (1.0 - gap) * mix(1.0, letter, 0.55) * step(0.08, sc_hash(vec2(word, row * 1.7 + seed)));
}

// Newspaper front page, uv 0..1, v down.
vec3 sc_news(vec2 uv, float seed, out float gloss_dim) {
	vec3 paper = vec3(0.83, 0.82, 0.77);
	vec3 ink = vec3(0.1, 0.1, 0.11);
	vec3 col = paper;
	gloss_dim = 0.0;
	float m = step(0.035, uv.x) * step(uv.x, 0.965) * step(0.03, uv.y) * step(uv.y, 0.975);
	// Masthead: a row of heavy letters.
	if (uv.y < 0.17 && m > 0.0) {
		float lx = (uv.x - 0.08) / 0.84;
		float cell = floor(lx * 9.0);
		float fx = fract(lx * 9.0);
		float fy = (uv.y - 0.045) / 0.105;
		float inside = step(0.0, lx) * step(lx, 1.0) * step(0.0, fy) * step(fy, 1.0) * step(0.12, fx) * step(fx, 0.88);
		float hole = step(0.5, sc_hash(vec2(cell, floor(fy * 3.0) + seed))) * step(0.35, fx) * step(fx, 0.65);
		float k = sc_keep(uv, 30.0);
		col = mix(col, ink, inside * mix(0.55, 1.0 - hole, k));
	}
	// Rule under the masthead.
	col = mix(col, ink, step(0.18, uv.y) * step(uv.y, 0.188) * m);
	// Headline: two lines of bold words.
	if (uv.y > 0.205 && uv.y < 0.315 && m > 0.0) {
		float row = floor((uv.y - 0.205) / 0.055);
		float fy = fract((uv.y - 0.205) / 0.055);
		float on = step(0.12, fy) * step(fy, 0.86) * sc_words(uv.x, row + 11.0, seed, 22.0);
		on *= step(uv.x, 0.93 - 0.3 * sc_hash(vec2(row, seed + 3.0)));
		col = mix(col, ink, on * mix(0.5, 1.0, sc_keep(uv, 22.0)));
	}
	// Lead photograph.
	vec2 ph = (uv - vec2(0.05, 0.34)) / vec2(0.56, 0.3);
	if (ph.x > 0.0 && ph.x < 1.0 && ph.y > 0.0 && ph.y < 1.0) {
		float n = sc_noise(ph * vec2(5.0, 4.0) + seed * 7.0) * 0.6 + sc_noise(ph * 13.0 + seed) * 0.4;
		vec3 tone = mix(vec3(0.24, 0.26, 0.3), vec3(0.62, 0.58, 0.5), n);
		tone = mix(tone, vec3(0.2, 0.18, 0.16), smoothstep(0.55, 1.0, ph.y) * 0.6);
		col = tone;
		gloss_dim = 1.0;
	}
	// Columns of body text around it.
	bool in_photo = uv.x < 0.63 && uv.y > 0.33 && uv.y < 0.66;
	if (uv.y > 0.33 && m > 0.0 && !in_photo) {
		float lines = 38.0;
		float row = floor(uv.y * lines);
		float fy = fract(uv.y * lines);
		float col_x = fract(uv.x * 3.0);
		float gutter = step(0.04, col_x) * step(col_x, 0.94);
		float text = step(0.25, fy) * step(fy, 0.72) * sc_words(uv.x, row, seed + floor(uv.x * 3.0) * 5.0, 55.0) * gutter;
		float k = sc_keep(uv, lines);
		col = mix(col, ink, mix(0.28 * gutter, text * 0.85, k));
	}
	return col;
}

// Magazine cover (or a rack's header card), uv 0..1, v down.
vec3 sc_cover(vec2 uv, float seed) {
	float h = sc_hash(vec2(seed, 5.1));
	vec3 bg = mix(vec3(0.85, 0.83, 0.78), vec3(0.72, 0.18, 0.14), step(0.45, h));
	bg = mix(bg, vec3(0.12, 0.3, 0.55), step(0.7, h));
	bg = mix(bg, vec3(0.1, 0.1, 0.1), step(0.88, h));
	float h2 = sc_hash(vec2(seed, 9.7));
	// The photograph: most of the cover, a soft figure or a view.
	vec2 p = (uv - vec2(0.5, 0.62)) / vec2(0.5, 0.42);
	float n = sc_noise(uv * 6.0 + seed * 3.0);
	vec3 photo = mix(vec3(0.62, 0.5, 0.42), vec3(0.3, 0.42, 0.52), step(0.5, h2));
	photo = mix(photo, vec3(0.2, 0.17, 0.15), n * 0.5);
	float fig = 1.0 - smoothstep(0.55, 0.95, length(p * vec2(1.4, 1.0)));
	vec3 col = mix(bg, photo, max(fig, step(0.5, h2) * step(0.25, uv.y)));
	// Title across the top.
	if (uv.y > 0.04 && uv.y < 0.2) {
		float lx = (uv.x - 0.07) / 0.86;
		float fx = fract(lx * 7.0);
		float on = step(0.0, lx) * step(lx, 1.0) * step(0.15, fx) * step(fx, 0.85) * step(0.2, sc_hash(vec2(floor(lx * 7.0), seed)));
		vec3 title = mix(vec3(0.95, 0.94, 0.9), vec3(0.85, 0.12, 0.1), step(0.6, sc_hash(vec2(seed, 2.0))));
		col = mix(col, title, on * mix(0.6, 1.0, sc_keep(uv, 7.0)));
	}
	// Cover lines down the left.
	if (uv.x < 0.5 && uv.y > 0.42 && uv.y < 0.9) {
		float row = floor(uv.y * 16.0);
		float fy = fract(uv.y * 16.0);
		float on = step(0.3, fy) * step(fy, 0.75) * sc_words(uv.x, row, seed, 30.0) * step(uv.x, 0.12 + 0.35 * sc_hash(vec2(row, seed)));
		col = mix(col, vec3(0.95), on * 0.85 * mix(0.3, 1.0, sc_keep(uv, 16.0)));
	}
	return col;
}

// Chalk on a slate, uv 0..1, v down.
vec3 sc_chalk(vec2 uv, float seed) {
	vec3 slate = vec3(0.07, 0.078, 0.078);
	// Old writing wiped off: pale clouds.
	float smear = sc_noise(uv * vec2(4.0, 7.0) + seed * 11.0);
	vec3 col = slate + vec3(0.05) * smoothstep(0.45, 0.9, smear);
	float k = sc_keep(uv, 12.0);
	// A border line.
	float border = (step(0.035, uv.x) - step(0.045, uv.x)) + (step(0.955, uv.x) - step(0.965, uv.x));
	border += (step(0.03, uv.y) - step(0.037, uv.y)) + (step(0.963, uv.y) - step(0.97, uv.y));
	vec3 chalk_w = vec3(0.86, 0.86, 0.82);
	col = mix(col, chalk_w * 0.8, clamp(border, 0.0, 1.0) * 0.8 * k);
	// Rows of hand lettering: a big header, then smaller lines in coloured chalk.
	float y = uv.y;
	float row;
	float fy;
	float size;
	if (y < 0.24) {
		row = 0.0;
		fy = (y - 0.08) / 0.12;
		size = 11.0;
	} else {
		row = 1.0 + floor((y - 0.28) / 0.11);
		fy = fract((y - 0.28) / 0.11) / 0.6;
		size = 18.0;
	}
	float r = sc_hash(vec2(row, seed));
	float len = 0.45 + 0.45 * r;
	float x0 = row == 0.0 ? (1.0 - len) * 0.5 : 0.1;
	float lx = (uv.x - x0) / len;
	if (fy > 0.0 && fy < 1.0 && lx > 0.0 && lx < 1.0 && row < 7.0) {
		float cx = lx * size * len;
		float stroke = sc_noise(vec2(cx * 3.2, fy * 2.6) + vec2(row * 9.0 + seed * 3.0, 0.0));
		float letter = smoothstep(0.52, 0.6, stroke) * step(0.18, fract(cx)) * step(0.18, sc_hash(vec2(floor(cx / 4.0), row + seed)));
		float grain = 0.7 + 0.3 * sc_hash(uv * 400.0);
		vec3 tint = chalk_w;
		float t = sc_hash(vec2(row, seed + 4.0));
		if (row > 0.0 && t > 0.55) {
			tint = mix(vec3(0.95, 0.85, 0.45), vec3(0.95, 0.6, 0.7), step(0.78, t));
			tint = mix(tint, vec3(0.6, 0.85, 0.9), step(0.9, t));
		}
		col = mix(col, tint, letter * grain * mix(0.25, 0.9, k));
	}
	return col;
}

void vertex() {
	v_fwd = color_space_probe.r < 0.35 ? 1.0 : 0.0;
	float a = COLOR.a;
	v_paint = step(0.9, a);
	v_mode = a > 0.9 ? 0.0 : floor(a * 4.0 + 0.5);
	vec3 base = mix(COLOR.rgb, INSTANCE_CUSTOM.rgb, v_paint);
	v_base = v_fwd > 0.5 ? sc_linear(base) : base;
	v_seed = INSTANCE_CUSTOM.a * 61.0;
	v_local = VERTEX;
	v_normal_local = NORMAL;
}

void fragment() {
	int mode = int(v_mode + 0.5);
	float rough = UV2.x;
	float metal = UV2.y;
	vec3 albedo = v_base;
	if (mode == 0) {
		if (use_detail) {
			vec2 duv = UV / detail_tile;
			vec3 tex = texture(detail_albedo, duv).rgb;
			float mean = v_fwd > 0.5 ? tex_mean_linear : tex_mean_srgb;
			float lum = dot(tex, vec3(0.299, 0.587, 0.114)) / max(mean, 0.02);
			albedo *= mix(1.0, lum, detail);
			rough = clamp(rough + (texture(detail_rough, duv).r - 0.5) * 0.3, 0.05, 1.0);
			NORMAL_MAP = texture(detail_normal, duv).rgb;
			NORMAL_MAP_DEPTH = normal_strength;
		}
		// Old stickers and flyer scraps on the painted sides.
		if (v_paint > 0.5 && stickers > 0.0 && abs(v_normal_local.y) < 0.5) {
			vec2 cell_uv = UV / vec2(0.07, 0.05);
			cell_uv.x += floor(cell_uv.y) * 0.37;
			vec2 cell = floor(cell_uv);
			vec2 f = fract(cell_uv);
			float h = sc_hash(cell + v_seed);
			if (h > 1.0 - stickers && f.x > 0.08 && f.x < 0.92 && f.y > 0.1 && f.y < 0.9) {
				float pick = sc_hash(cell * 1.7 + v_seed);
				vec3 s = mix(vec3(0.88, 0.87, 0.82), vec3(0.9, 0.78, 0.2), step(0.6, pick));
				s = mix(s, vec3(0.08), step(0.82, pick));
				s = mix(s, vec3(0.2, 0.4, 0.75), step(0.93, pick));
				// Half peeled, sun-faded.
				float peel = step(0.35, sc_noise(f * 4.0 + cell));
				albedo = mix(albedo, sc_col(s) * 0.9, peel * 0.9);
				rough = mix(rough, 0.6, peel);
			}
		}
		// Grime up from the pavement, ragged at its top edge.
		float n1 = sc_noise(v_local.xz * 14.0 + v_seed);
		float low = 1.0 - smoothstep(0.0, grime_height * (0.5 + n1), v_local.y);
		float streak = sc_noise(vec2(v_local.x * 40.0 + v_local.z * 40.0, v_local.y * 3.0) + v_seed) * 0.15;
		float g = clamp(grime * low + grime * streak * step(0.5, v_paint), 0.0, 0.85);
		albedo = mix(albedo, albedo * vec3(0.32, 0.29, 0.25) + sc_col(vec3(0.06, 0.055, 0.045)), g);
		rough = mix(rough, 0.85, g * 0.7);
	} else {
		vec2 uv = fract(UV);
		float sub = floor(UV.x) * 13.0 + v_seed;
		if (mode == 1) {
			float dim;
			albedo = sc_col(sc_news(uv, sub, dim)) * 0.86;
			// Behind glass: glossy, a touch green, a smear of dust on the pane.
			float dust = sc_noise(uv * vec2(3.0, 5.0) + v_seed);
			albedo *= mix(vec3(0.95, 1.0, 0.97), vec3(1.0), 0.5);
			rough = clamp(rough + dust * 0.12, 0.03, 1.0);
			SPECULAR = 0.55;
		} else if (mode == 2) {
			albedo = sc_col(sc_cover(uv, sub));
		} else {
			albedo = sc_col(sc_chalk(uv, sub));
		}
	}
	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));
	ROUGHNESS = rough;
	METALLIC = metal;
}
