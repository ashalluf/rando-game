shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Street-level wear (scripts/world/street_wear.gd): spray-painted tags, the buff-out patches
// where tags were painted over, wheat-paste posters and stickers, laid a few millimetres proud of
// walls, shop piers, poles, signal cabinets and freeway columns. One material for all of it, so a
// chunk's wear is ONE MultiMesh draw, drawn in instance order (a buff over the tag it covers, a
// fresh tag over the buff, a new poster over the torn ones under it).
//
// * Instance COLOR: rgb the main colour (a tag's fill, a buff's paint), a its age (0 fresh, 1
//   faded almost away). sRGB; `color_space_probe` says whether to decode it (Forward+ decodes
//   source_color uniforms but not instance data, Compatibility decodes nothing), the same trick as
//   street_clutter.gdshader.
// * INSTANCE_CUSTOM: r = mode * 100 + atlas cell (mode 0 tag, 1 buff, 2 poster, 3 sticker),
//   g = a per-instance seed 0..1, b = the bend (width / radius, 0 = flat: wrapped round a pole by
//   the vertex shader), a = second-colour palette index + 16 * tear level (0..7). All small
//   integers or 0..1, so they survive half-float instance data.
//   Mode 4 is grime along the foot of a wall (COLOR a = strength) and mode 5 a pavement patch
//   lying flat (cell 0 gum, 1 a stain; COLOR a = density / strength): both are procedural and
//   measured in metres (v_size, the instance's scale), so a 40 m wall or a 3 m patch keeps the
//   grain of a real one.
// * The mesh is a unit strip (x -0.5..0.5, y -0.5..0.5, facing +Z) of a few columns so it can bend;
//   the instance basis is (right * w, up * h, normal * w).
// * The paint takes on the grain of what it is painted on: the wall's own luminance detail is
//   read off the screen texture (captured before the transparent pass, so it is the wall) and
//   multiplied in, so a tag on brick follows the mortar and paper on stucco shows the bumps.
// * Depth: the view-space position is pulled toward the eye by `depth_pull` (screen position
//   unchanged), so a decal a few millimetres off a wall never z-fights with it at 120 m.

uniform sampler2D tag_atlas : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D paper_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform bool use_screen = true;
uniform float depth_pull = 0.0025;
// Distance (m) the batch stops drawing at (StreetWear.DRAW_DISTANCE): everything thins out over
// the last quarter of it, so nothing pops when the batch's own visibility range ends.
uniform float fade_end = 120.0;
uniform vec3 color_space_probe : source_color = vec3(0.5, 0.5, 0.5);

// Second colours: outlines, and the colours tags come in. sRGB.
const vec3 PALETTE[12] = vec3[12](
	vec3(0.05, 0.05, 0.06), vec3(0.9, 0.9, 0.88), vec3(0.7, 0.71, 0.73), vec3(0.66, 0.08, 0.07),
	vec3(0.1, 0.18, 0.55), vec3(0.08, 0.34, 0.16), vec3(0.85, 0.3, 0.58), vec3(0.88, 0.7, 0.1),
	vec3(0.38, 0.16, 0.52), vec3(0.4, 0.66, 0.86), vec3(0.9, 0.42, 0.08), vec3(0.3, 0.2, 0.14));

varying flat vec4 v_col;
varying flat vec4 v_custom;
varying flat float v_fwd;
varying flat vec2 v_size;

vec3 sw_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 sw_col(vec3 srgb) {
	return v_fwd > 0.5 ? sw_linear(srgb) : srgb;
}

float sw_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float sw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(sw_hash(i), sw_hash(i + vec2(1.0, 0.0)), f.x),
		mix(sw_hash(i + vec2(0.0, 1.0)), sw_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float sw_fbm(vec2 p) {
	return sw_noise(p) * 0.55 + sw_noise(p * 2.13 + 7.1) * 0.3 + sw_noise(p * 4.7 + 3.3) * 0.15;
}

void vertex() {
	v_col = COLOR;
	v_custom = INSTANCE_CUSTOM;
	v_fwd = color_space_probe.r < 0.35 ? 1.0 : 0.0;
	v_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	float k = INSTANCE_CUSTOM.b;
	if (k > 0.001) {
		// Round a pole: the strip's x becomes an arc of k radians (x runs in units of the width,
		// and so does z, which the basis scales by the width too).
		float th = VERTEX.x * k;
		VERTEX = vec3(sin(th) / k, VERTEX.y, (cos(th) - 1.0) / k);
		NORMAL = vec3(sin(th), 0.0, cos(th));
		TANGENT = vec3(cos(th), 0.0, -sin(th));
	}
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = PROJECTION_MATRIX * vec4(vp.xyz * (1.0 - depth_pull), 1.0);
}

void fragment() {
	float mode = floor(v_custom.r / 100.0 + 0.01);
	float cell = floor(v_custom.r - mode * 100.0 + 0.5);
	float seed = v_custom.g * 97.0;
	float pal = mod(floor(v_custom.a + 0.5), 16.0);
	float tear = floor(floor(v_custom.a + 0.5) / 16.0) / 7.0;
	float age = v_col.a;
	vec3 main_c = sw_col(v_col.rgb);
	vec2 uv = UV;
	vec3 alb = main_c;
	float a = 0.0;
	float rough = 0.75;
	float spec = 0.4;
	float grain = 1.0;
	float lum_w = 0.0;
	if (mode < 0.5) {
		// A tag: masks from the atlas, fill over outline, shine over both.
		vec2 c = vec2(mod(cell, 4.0), floor(cell / 4.0));
		vec4 m = texture(tag_atlas, (c + clamp(uv, 0.004, 0.996)) / 4.0);
		vec3 line = sw_col(PALETTE[int(pal)]);
		float cover = 1.0 - (1.0 - m.r) * (1.0 - m.g);
		alb = (line * m.g * (1.0 - m.r) + main_c * m.r) / max(cover, 0.001);
		alb = mix(alb, sw_col(vec3(0.95)), m.b * 0.85);
		a = cover;
		// Old paint chalks and thins: lighter, greyer, see-through in patches.
		float wear = age * (0.6 + 0.8 * sw_noise(uv * vec2(9.0, 5.0) + seed));
		alb = mix(alb, vec3(dot(alb, vec3(0.3, 0.55, 0.15))) * 1.1 + 0.04, clamp(wear * 0.55, 0.0, 1.0));
		a *= 1.0 - clamp(wear * 0.5, 0.0, 0.7);
		rough = 0.62;
		grain = 1.0;
	} else if (mode < 1.5) {
		// A buff: roller strokes of mismatched wall paint, each band ending where the roller did.
		float nb = 3.0 + floor(sw_hash(vec2(seed, 3.1)) * 4.0);
		float band = floor(uv.y * nb);
		float ragged = (sw_noise(vec2(uv.y * 60.0, seed)) - 0.5) * 0.025;
		float end_l = 0.015 + 0.08 * sw_hash(vec2(band, seed));
		float end_r = 0.985 - 0.08 * sw_hash(vec2(band + 7.0, seed));
		a = smoothstep(end_l - 0.008, end_l + 0.008, uv.x + ragged) * (1.0 - smoothstep(end_r - 0.008, end_r + 0.008, uv.x - ragged));
		float ty = (sw_noise(vec2(uv.x * 50.0, seed + 5.0)) - 0.5) * 0.02;
		a *= smoothstep(0.0, 0.02, uv.y + ty) * smoothstep(0.0, 0.02, 1.0 - uv.y + ty);
		// Thin passes where the roller ran dry.
		a *= mix(0.8, 1.0, smoothstep(0.2, 0.6, sw_noise(vec2(uv.x * 6.0, uv.y * nb * 5.0) + seed)));
		float tone = 0.96 + 0.07 * sw_hash(vec2(band, seed + 11.0)) + 0.04 * (sw_noise(uv * vec2(90.0, 40.0)) - 0.5);
		alb = main_c * tone;
		rough = 0.82;
		grain = 0.85;
	} else if (mode < 2.5) {
		// A poster: the sheet from the atlas, torn, sun-bleached, wrinkled by the paste.
		vec2 c = vec2(mod(cell, 8.0), floor(cell / 8.0));
		vec2 auv = (c * vec2(256.0, 384.0) + clamp(uv, 0.002, 0.998) * vec2(256.0, 384.0)) / vec2(2048.0, 1024.0);
		vec4 t = texture(paper_atlas, auv);
		alb = t.rgb;
		a = t.a;
		float e = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		float keep = sw_fbm(uv * vec2(3.0, 4.5) + seed) * 0.75 + e * 1.1 + (1.0 - uv.y) * 0.2;
		float thr = tear * 0.95;
		if (tear > 0.0) {
			// Where it is torn away, patches of the paper's back stay stuck to the wall.
			float rim = smoothstep(thr, thr + 0.035, keep);
			float residue = smoothstep(0.5, 0.62, sw_noise(uv * vec2(7.0, 9.0) + seed * 3.0)) * 0.55;
			vec3 back = vec3(0.8, 0.78, 0.72);
			float fibre = 1.0 - smoothstep(thr + 0.005, thr + 0.03, keep);
			alb = mix(alb, back, fibre * rim);
			alb = mix(back * 0.9, alb, rim);
			a *= max(rim, residue);
		}
		vec3 grey = vec3(dot(alb, vec3(0.3, 0.55, 0.15)));
		// Sun: inks fade (reds and magentas first) and the sheet yellows.
		alb = mix(alb, grey * vec3(0.95, 1.0, 1.03) * 0.85 + vec3(0.13, 0.12, 0.09), age * 0.6);
		float wrinkle = sw_fbm(uv * vec2(14.0, 18.0) + seed);
		float wx = sw_fbm(uv * vec2(14.0, 18.0) + seed + vec2(0.02, 0.0)) - wrinkle;
		float wy = sw_fbm(uv * vec2(14.0, 18.0) + seed + vec2(0.0, 0.02)) - wrinkle;
		NORMAL_MAP = vec3(0.5 - wx * 4.0, 0.5 + wy * 4.0, 1.0);
		alb *= 0.93 + 0.1 * wrinkle;
		// The paste: glossier where it soaked through.
		rough = mix(0.88, 0.55, smoothstep(0.55, 0.8, sw_noise(uv * 5.0 + seed * 2.0)));
		grain = 0.35;
	} else if (mode > 3.5 && mode < 4.5) {
		// Grime: splash-back and soot at the foot of the wall, darkest at the pavement, running up
		// in streaks, its top edge ragged, faded in at both ends.
		vec2 m = vec2(uv.x * v_size.x, (1.0 - uv.y) * v_size.y);
		float streak = sw_fbm(vec2(m.x * 1.7, m.y * 0.35) + seed);
		float blotch = sw_fbm(m * vec2(0.45, 0.9) + seed * 1.7);
		float top = v_size.y * (0.45 + 0.75 * blotch);
		float body = 1.0 - smoothstep(top * 0.3, top, m.y + (streak - 0.5) * 0.25 * v_size.y);
		float splash = 1.0 - smoothstep(0.0, 0.18, m.y);
		float ends = smoothstep(0.0, 1.2, m.x) * smoothstep(0.0, 1.2, v_size.x - m.x);
		a = age * ends * clamp(body * (0.45 + 0.8 * streak) + splash * 0.5 * (0.6 + 0.8 * blotch), 0.0, 1.0);
		alb = main_c * (0.8 + 0.4 * blotch);
		rough = 0.9;
		spec = 0.3;
		grain = 1.0;
	} else if (mode > 4.5) {
		// Lying on the pavement, measured in metres from the patch's centre.
		vec2 m = (uv - 0.5) * v_size;
		// The patch has no edge: its density falls off toward the rim.
		float rim = 1.0 - smoothstep(0.25, 0.5, max(abs(uv.x - 0.5), abs(uv.y - 0.5)) + (sw_noise(m * 1.3 + seed) - 0.5) * 0.2);
		float px = max(length(fwidth(m)), 1e-4);
		if (cell < 0.5) {
			// Gum: flattened discs, black with age, a few fresh pale ones, on a 0.22 m jittered grid.
			// A disc under a pixel fades to the faint smudge the field makes from a distance,
			// or the pavement would sparkle.
			vec2 gc = m / 0.22 + seed;
			vec2 id = floor(gc);
			float h = sw_hash(id);
			vec2 at = id + 0.2 + 0.6 * vec2(sw_hash(id + 7.3), sw_hash(id + 3.1));
			float r = (0.011 + 0.017 * sw_hash(id + 1.7)) / 0.22;
			// Trodden flat into a blob, not a coin: the outline wanders with the angle, and the
			// edge is thin enough to let the slab through. Perfect round black discs at 0.95
			// read as a pavement full of drilled holes.
			vec2 dv = gc - at;
			float ang = atan(dv.y, dv.x);
			float wob = 0.78 + 0.22 * sin(ang * 3.0 + h * 40.0) + 0.12 * sin(ang * 5.0 + h * 17.0);
			float d = length(dv) / wob;
			float disc = 1.0 - smoothstep(r * 0.45, r * 1.05, d);
			float present = step(h, age * rim * 0.7);
			float sharp = clamp(r * 0.22 / px * 2.0 - 0.5, 0.0, 1.0);
			a = mix(0.06 * age * rim, disc * present * mix(0.55, 0.85, sw_hash(id + 5.2)), sharp);
			float fresh = step(0.93, sw_hash(id + 9.9));
			// Most of it weathers to a grey a little darker than the slab; some stays black.
			vec3 old_gum = mix(main_c, sw_col(vec3(0.30, 0.29, 0.28)), sw_hash(id + 4.4) * 0.8);
			alb = mix(old_gum, sw_col(vec3(0.62, 0.55, 0.56)), fresh * sharp);
			rough = mix(0.8, 0.45, disc * sharp);
			grain = 0.5;
		} else {
			// A stain: a soaked blotch, a darker tide mark at its rim, splash drops round it.
			float n = sw_fbm(m * 1.6 + seed) + sw_noise(m * 6.0 + seed * 2.0) * 0.18;
			float r = length(m / (v_size * 0.5));
			// Falls to nothing well inside the quad, so no stain is cut off by its edge.
			float f = n * 0.9 - r * 1.15 + 0.3;
			float blot = smoothstep(0.0, 0.05, f);
			float tide = smoothstep(0.0, 0.03, f) * (1.0 - smoothstep(0.03, 0.12, f));
			vec2 dc = m / 0.12 + seed;
			float drop = (1.0 - smoothstep(0.1, 0.22, length(fract(dc) - 0.5))) * step(0.85, sw_hash(floor(dc))) * (1.0 - smoothstep(0.3, 0.7, r));
			a = age * clamp(blot * 0.75 + tide * 0.5 + drop * 0.7, 0.0, 1.0);
			alb = main_c * (1.0 - tide * 0.35);
			rough = mix(0.85, 0.6, blot);
			grain = 0.8;
		}
		a *= cell < 0.5 ? rim : 1.0;
	} else {
		// A sticker: vinyl, a little scuffed, sometimes half scraped off.
		vec2 c = vec2(mod(cell, 16.0), floor(cell / 16.0));
		vec2 auv = (vec2(c.x * 128.0, 768.0 + c.y * 128.0) + clamp(uv, 0.004, 0.996) * 128.0) / vec2(2048.0, 1024.0);
		vec4 t = texture(paper_atlas, auv);
		alb = t.rgb;
		a = t.a;
		if (tear > 0.0) {
			float keep = sw_fbm(uv * 3.0 + seed) + uv.x * 0.4;
			float gone = 1.0 - smoothstep(tear * 0.9, tear * 0.9 + 0.03, keep);
			alb = mix(alb, vec3(0.86, 0.85, 0.82), gone);
			a *= 1.0 - gone * 0.35;
		}
		alb = mix(alb, vec3(dot(alb, vec3(0.3, 0.55, 0.15))) * 0.8 + 0.15, age * 0.55);
		rough = 0.35 + age * 0.3;
		spec = 0.5;
		grain = 0.1;
	}
	if (use_screen && grain > 0.0) {
		// The wall's own grain, relative to its surroundings (so light and shadow are not doubled).
		vec2 px = 5.0 / VIEWPORT_SIZE;
		vec3 w = vec3(0.3, 0.55, 0.15);
		float under = dot(texture(screen_tex, SCREEN_UV).rgb, w);
		float around = 0.25 * (dot(texture(screen_tex, SCREEN_UV + vec2(px.x, px.y)).rgb, w)
			+ dot(texture(screen_tex, SCREEN_UV + vec2(-px.x, px.y)).rgb, w)
			+ dot(texture(screen_tex, SCREEN_UV + vec2(px.x, -px.y)).rgb, w)
			+ dot(texture(screen_tex, SCREEN_UV + vec2(-px.x, -px.y)).rgb, w));
		float ratio = clamp(under / max(around, 0.01), 0.65, 1.35);
		alb *= mix(1.0, ratio, grain);
	}
	float dist = length(VERTEX);
	a *= 1.0 - smoothstep(fade_end * 0.75, fade_end, dist);
	ALBEDO = alb;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = rough;
	SPECULAR = spec;
}
