shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

// The wanted stars and the health bar (scripts/ui/wanted_hud.gd), in the same smoked frosted
// glass as the weapon wheel (glass_ui.gdshader): the world behind blurred, pulled to a mid grey
// and darkened so white reads over anything, a lens and clearer frost at the rim, a specular
// hairline catching the light on the upper left, a hairline of dark outside the edge and a soft
// shadow. One rect per element; the shapes are signed distance fields computed here.
//
//   mode 0  five glass stars in a row. A lit star is filled with white light (and glows); an
//           unlit one is empty glass with an outline, so the row always shows its length.
//   mode 1  a glass pill with the health filling it from the left, going red when low.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform int mode = 0;
// The rect's size in pixels; shapes are laid out from its centre.
uniform vec2 rect_px = vec2(220.0, 48.0);

// Stars: outer radius, the gap between two, inner radius as a fraction, corner rounding (px).
uniform float star_r = 18.0;
uniform float star_gap = 7.0;
uniform float star_inner = 0.46;
uniform float star_round = 2.5;
// How lit each star is (0 empty glass, 1 full), eased by the script.
uniform float star_fill[5];
// The lost-sight pulse: 0..1, dims and brightens the lit stars as they flash.
uniform float flash = 0.0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.985, 0.95, 1.0);
// Inset of the light from the glass edge, and the outline an empty star keeps (px).
uniform float fill_inset = 2.5;
uniform float outline_px = 1.4;
uniform float outline_alpha = 0.55;
uniform float star_glow_px = 7.0;
uniform float star_glow = 0.45;

// Bar: how full, a red pulse when hit, corner radius and the inset of the fill (px).
uniform float bar_fill = 1.0;
uniform float bar_hurt = 0.0;
uniform float bar_corner = 8.0;
uniform float bar_inset = 3.0;
uniform vec4 bar_color : source_color = vec4(0.93, 0.97, 0.94, 1.0);
uniform vec4 bar_low : source_color = vec4(1.0, 0.28, 0.22, 1.0);

// The glass itself (the weapon wheel's numbers, scaled for small shapes).
uniform float blur_px = 10.0;
uniform float blur_mips = 1.0;
uniform float saturation = 1.5;
uniform float level = 0.34;
uniform float contrast = 0.8;
uniform float body = 0.74;
uniform vec4 tint : source_color = vec4(0.06, 0.07, 0.09, 0.22);
uniform float refract_px = 4.0;
uniform float bevel_px = 6.0;
uniform float rim_clear = 0.4;
uniform float bevel_light = 0.34;
uniform float edge_dark = 0.2;
uniform float rim_px = 1.2;
uniform float rim_strength = 0.9;
uniform vec2 light_dir = vec2(-0.55, -0.83);
uniform vec2 shadow_offset = vec2(0.0, 3.0);
uniform float shadow_px = 8.0;
uniform float shadow_alpha = 0.3;

const int TAPS = 16;

// Inigo Quilez's five-pointed star, y up.
float sd_star5(vec2 p, float r, float rf) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-0.809016994375, -0.587785252292);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float sd_round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

float star_x(int k) {
	return (float(k) - 2.0) * (2.0 * star_r + star_gap);
}

// Distance to the nearest shape, and which star it is (-1 for the bar).
float shapes(vec2 p, out int id) {
	id = -1;
	if (mode == 1) {
		vec2 hs = rect_px * 0.5 - vec2(shadow_px * 0.5 + 2.0);
		return sd_round_box(p, hs, min(bar_corner, min(hs.x, hs.y)));
	}
	float d = 1.0e5;
	for (int k = 0; k < 5; k++) {
		vec2 q = p - vec2(star_x(k), 1.5);
		// Screen y runs down; the star's points go up.
		float dk = sd_star5(vec2(q.x, -q.y), star_r - star_round, star_inner) - star_round;
		if (dk < d) {
			d = dk;
			id = k;
		}
	}
	return d;
}

vec3 blur(vec2 uv, vec2 px, vec2 frag, float radius) {
	float lod = blur_mips * log2(max(radius * 0.32, 1.0));
	float turn = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715)))) * TAU;
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < TAPS; i++) {
		float fi = float(i) + 0.5;
		float r = sqrt(fi / float(TAPS));
		float a = fi * 2.39996323 + turn;
		vec2 o = vec2(cos(a), sin(a)) * r * radius;
		float w = exp(-1.8 * r * r);
		acc += textureLod(screen_tex, clamp(uv + o * px, px, vec2(1.0) - px), lod).rgb * w;
		wsum += w;
	}
	return acc / wsum;
}

void fragment() {
	float fade = COLOR.a;
	vec2 p = (UV - vec2(0.5)) * rect_px;
	vec2 L = normalize(light_dir);
	int sid;
	float ds = shapes(p - shadow_offset, sid);
	float sh = shadow_alpha * (1.0 - smoothstep(-shadow_px * 0.4, shadow_px, ds));
	int id;
	float d = shapes(p, id);
	sh = max(sh, edge_dark * (1.0 - smoothstep(0.0, 1.5, d)));
	vec4 outc = vec4(0.0, 0.0, 0.0, sh);

	// Lit stars glow a little outside their edge.
	if (mode == 0 && id >= 0) {
		float lit = star_fill[id] * (1.0 - 0.55 * flash);
		float g = lit * star_glow * exp(-max(d, 0.0) / star_glow_px) * step(0.0, d);
		outc = vec4(vec3(g), g) + outc * (1.0 - g);
	}

	float aa = max(fwidth(d), 0.0001);
	float cov = clamp(0.5 - d / aa, 0.0, 1.0);
	if (cov > 0.0) {
		vec2 n = vec2(shapes(p + vec2(1.0, 0.0), sid) - d, shapes(p + vec2(0.0, 1.0), sid) - d);
		n = n / max(length(n), 0.0001);
		float inside = max(-d, 0.0);
		float edge = 1.0 - clamp(inside / bevel_px, 0.0, 1.0);
		vec2 px = SCREEN_PIXEL_SIZE;
		vec2 suv = SCREEN_UV + n * refract_px * edge * edge * px;
		vec3 bg = blur(suv, px, FRAGCOORD.xy, blur_px * mix(1.0, rim_clear, edge * edge * edge));
		float l = dot(bg, vec3(0.2126, 0.7152, 0.0722));
		bg = max(mix(vec3(l), bg, saturation), vec3(0.0));
		bg = max(mix(vec3(level), bg, contrast), vec3(0.0));
		vec3 col = mix(bg * body, tint.rgb, tint.a);
		float facing = dot(n, L);
		float lit_side = pow(max(facing, 0.0), 1.5) + 0.35 * pow(max(-facing, 0.0), 2.0);
		col += vec3(1.0) * edge * edge * edge * (0.04 + bevel_light * lit_side);

		if (mode == 0 && id >= 0) {
			// The light inside a lit star, and the outline every star keeps.
			float lit = star_fill[id];
			float pulse = 1.0 - 0.55 * flash;
			float inner = 1.0 - smoothstep(-fill_inset - aa, -fill_inset + aa, d);
			// A faint gradient in the light so it reads as lit glass, not flat paint.
			float shade = 0.9 + 0.1 * clamp(-p.y / star_r + 0.5, 0.0, 1.0);
			col = mix(col, fill_color.rgb * shade, clamp(inner * lit * pulse * 0.94, 0.0, 1.0));
			float line = 1.0 - smoothstep(outline_px - 0.5, outline_px + 0.5, inside);
			col = mix(col, vec3(1.0), line * outline_alpha * (1.0 - lit * 0.6));
		} else if (mode == 1) {
			// The fill, from the left, inset inside the glass, with a brighter top edge.
			vec2 half_size = rect_px * 0.5 - vec2(shadow_px * 0.5 + 2.0);
			float x0 = -half_size.x + bar_inset;
			float x1 = mix(x0, half_size.x - bar_inset, clamp(bar_fill, 0.0, 1.0));
			vec2 fc = vec2((x0 + x1) * 0.5, 0.0);
			vec2 fh = vec2(max((x1 - x0) * 0.5, 0.0), half_size.y - bar_inset);
			float df = sd_round_box(p - fc, fh, min(max(bar_corner - bar_inset, 1.0), min(fh.x, fh.y)));
			float f = (1.0 - smoothstep(-aa, aa, df)) * step(0.001, bar_fill);
			float low = 1.0 - smoothstep(0.2, 0.45, bar_fill);
			vec3 fcol = mix(bar_color.rgb, bar_low.rgb, max(low, bar_hurt));
			fcol *= 0.86 + 0.14 * clamp(-p.y / max(fh.y, 1.0) * 0.5 + 0.5, 0.0, 1.0);
			col = mix(col, fcol, f * 0.9);
		}

		float rim = clamp(1.0 - inside / rim_px, 0.0, 1.0);
		float spec = 0.34 + 0.8 * pow(max(facing, 0.0), 2.0) + 0.4 * pow(max(-facing, 0.0), 3.0);
		col = mix(col, vec3(1.0), clamp(rim * spec * rim_strength, 0.0, 1.0));
		outc = vec4(clamp(col, 0.0, 1.0) * cov, cov) + outc * (1.0 - cov);
	}
	COLOR = outc * fade;
}
