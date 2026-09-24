shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

// Frosted glass for the weapon wheel, in the manner of Apple's translucent UI: the game behind
// it blurred, a little brighter and more saturated, a faint white body, a lens that bends the
// view at the rim, a thin specular edge that catches the light on the upper left (and, fainter,
// where it leaves on the lower right) and a soft shadow on the world underneath.
//
// The whole wheel is ONE rect: the shapes are signed distance fields computed here (a centre
// disc plus a ring of rounded segments with parallel gaps), so the rims, the rounding, the
// glow and the shadow all come from the same distance and stay crisp at any size.
//
// Works on the Compatibility renderer (web): the blur is a tap loop, read from the screen copy's
// mips (both renderers build them for a `filter_linear_mipmap` screen texture), so it is smooth
// rather than grainy. `blur_mips` 0 reads the full-resolution copy only.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// Geometry in the rect's own pixels, measured from its centre. WeaponWheel sets all of these
// from the viewport height.
uniform vec2 rect_px = vec2(640.0, 640.0);
uniform int seg_count = 3;
uniform float r_in = 170.0;
uniform float r_out = 320.0;
uniform float disc_r = 124.0;
uniform float gap = 12.0;
uniform float corner = 22.0;
// Per-segment highlight, 0..1, eased by the script so one fades out as the next comes in.
uniform float seg_hover[8];
// How far a highlighted segment moves out along its middle, and how much it swells (pixels).
uniform float pop = 8.0;
uniform float grow = 3.0;

// The glass itself.
uniform float blur_px = 22.0;
uniform float blur_mips = 1.0;
uniform float saturation = 1.6;
// The world seen through the pane is pulled toward `level` (contrast < 1), so neither a black
// alley nor a white sky swamps the glyphs, then scaled by `body`. Together with the dark tint
// that makes smoked glass: white text reads on it over anything, the way it does on Apple's
// dark glass.
uniform float level = 0.34;
uniform float contrast = 0.8;
uniform float body = 0.78;
uniform vec4 tint : source_color = vec4(0.06, 0.07, 0.09, 0.12);
uniform vec4 disc_tint : source_color = vec4(0.04, 0.05, 0.07, 0.28);
// Lens at the rim: how far the view is bent (pixels), how wide the bevel is, and how much of
// the frost clears there (0.35 = the blur drops to 35 % at the very edge), so the bent world
// shows through the lip the way it does through the edge of a thick pane.
uniform float refract_px = 12.0;
uniform float bevel_px = 18.0;
uniform float rim_clear = 0.35;
// The centre disc is a lens: it magnifies what is behind it by 1 / disc_zoom.
uniform float disc_zoom = 0.8;
// Light caught inside the bevel on the side facing the light, and a hairline of dark just
// outside every edge, which is what keeps the shape defined over a bright sky.
uniform float bevel_light = 0.34;
uniform float edge_dark = 0.16;
// Specular rim: width in pixels, strength, and where the light comes from (screen space, y down).
uniform float rim_px = 1.5;
uniform float rim_strength = 0.9;
uniform vec2 light_dir = vec2(-0.55, -0.83);
// Diagonal sheen across the whole wheel, brightest toward the light.
uniform float sheen = 0.13;
// Highlighted segment: extra white in the body, and a glow outside its edge.
uniform float hover_lift = 0.38;
uniform float glow_px = 12.0;
uniform float glow_strength = 0.32;
// Soft shadow on the world under the wheel.
uniform vec2 shadow_offset = vec2(0.0, 10.0);
uniform float shadow_px = 28.0;
uniform float shadow_alpha = 0.3;

const int TAPS = 28;

float cross2(vec2 a, vec2 b) {
	return a.x * b.y - a.y * b.x;
}

// One ring segment: a rounded box in (radial, sideways) distance. Segment k is centred on the
// angle k * TAU / n, clockwise from straight up, and its sides are parallel to the dividing
// lines, so every gap is the same width all the way out.
float ring_segment(vec2 p, int k) {
	float n = float(seg_count);
	float step_a = TAU / n;
	float mid = float(k) * step_a;
	float hov = seg_hover[k];
	p -= vec2(sin(mid), -cos(mid)) * pop * hov;
	float r = length(p);
	float d_rad = max(r_in - r, r - r_out);
	float d_side = -1.0e4;
	if (seg_count > 1) {
		float a0 = mid - step_a * 0.5;
		float a1 = mid + step_a * 0.5;
		vec2 u0 = vec2(sin(a0), -cos(a0));
		vec2 u1 = vec2(sin(a1), -cos(a1));
		d_side = max(gap * 0.5 - cross2(u0, p), cross2(u1, p) + gap * 0.5);
	}
	vec2 q = vec2(d_rad, d_side) + corner;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner - grow * hov;
}

float shape_of(vec2 p, int id) {
	return id < 0 ? length(p) - disc_r : ring_segment(p, id);
}

// Distance to the nearest shape (the disc is id -1).
float shapes(vec2 p, out int id) {
	float d = length(p) - disc_r;
	id = -1;
	for (int k = 0; k < 8; k++) {
		if (k >= seg_count) {
			break;
		}
		float dk = ring_segment(p, k);
		if (dk < d) {
			d = dk;
			id = k;
		}
	}
	return d;
}

// Disc blur: TAPS samples on a golden-angle spiral, turned per pixel so the pattern never
// lines up into ghost copies, read from a mip whose texels cover the spacing between taps.
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
	// COLOR arrives as the node's modulate: its alpha is the wheel's fade.
	float fade = COLOR.a;
	vec2 p = (UV - vec2(0.5)) * rect_px;
	vec2 L = normalize(light_dir);

	// Everything below is premultiplied, composited bottom to top.
	int sid;
	float ds = shapes(p - shadow_offset, sid);
	float sh = shadow_alpha * (1.0 - smoothstep(-shadow_px * 0.4, shadow_px, ds));
	int id;
	float d = shapes(p, id);
	sh = max(sh, edge_dark * (1.0 - smoothstep(0.0, 2.0, d)));
	vec4 outc = vec4(0.0, 0.0, 0.0, sh);

	// Glow around whichever segments are highlighted (only one, except mid-handover).
	float glow = 0.0;
	for (int k = 0; k < 8; k++) {
		if (k >= seg_count) {
			break;
		}
		if (seg_hover[k] > 0.001) {
			float dk = ring_segment(p, k);
			glow += seg_hover[k] * exp(-max(dk, 0.0) / glow_px) * step(0.0, dk);
		}
	}
	glow = clamp(glow * glow_strength, 0.0, 1.0);
	outc = vec4(vec3(glow), glow) + outc * (1.0 - glow);

	float aa = max(fwidth(d), 0.0001);
	float cov = clamp(0.5 - d / aa, 0.0, 1.0);
	if (cov > 0.0) {
		float hov = id >= 0 ? seg_hover[id] : 0.0;
		float disc = id < 0 ? 1.0 : 0.0;
		vec2 n = vec2(shape_of(p + vec2(1.0, 0.0), id) - d, shape_of(p + vec2(0.0, 1.0), id) - d);
		n = n / max(length(n), 0.0001);
		float inside = max(-d, 0.0);
		float edge = 1.0 - clamp(inside / bevel_px, 0.0, 1.0);

		// Lens: toward the rim the pane bends the view outward, like the edge of thick glass.
		vec2 px = SCREEN_PIXEL_SIZE;
		vec2 suv = SCREEN_UV + n * refract_px * edge * edge * px;
		// p is measured from the disc's centre, so this pulls the view in toward it.
		suv -= disc * (1.0 - disc_zoom) * p * px;
		vec3 bg = blur(suv, px, FRAGCOORD.xy, blur_px * mix(1.0, rim_clear, edge * edge * edge));

		float l = dot(bg, vec3(0.2126, 0.7152, 0.0722));
		bg = max(mix(vec3(l), bg, saturation), vec3(0.0));
		bg = max(mix(vec3(level), bg, contrast), vec3(0.0));
		vec3 col = bg * body;
		vec4 t = mix(tint, disc_tint, disc);
		col = mix(col, t.rgb, t.a);
		col = mix(col, vec3(1.0), hover_lift * hov);

		// Sheen across the wheel, and the bevel brightening toward the rim that faces the light.
		float facing = dot(n, L);
		col += vec3(1.0) * sheen * (smoothstep(-1.0, 1.0, dot(p / r_out, L)) - 0.35);
		float lit = pow(max(facing, 0.0), 1.5) + 0.35 * pow(max(-facing, 0.0), 2.0);
		col += vec3(1.0) * edge * edge * edge * (0.04 + bevel_light * lit) * (1.0 + 0.6 * hov);

		// The specular rim: a hairline where the light catches the edge.
		float rim = clamp(1.0 - inside / (rim_px * (1.0 + 0.5 * hov)), 0.0, 1.0);
		float spec = 0.34 + 0.8 * pow(max(facing, 0.0), 2.0) + 0.4 * pow(max(-facing, 0.0), 3.0);
		spec = mix(spec, 1.1, 0.6 * hov);
		col = mix(col, vec3(1.0), clamp(rim * spec * rim_strength, 0.0, 1.0));

		outc = vec4(clamp(col, 0.0, 1.0) * cov, cov) + outc * (1.0 - cov);
	}
	COLOR = outc * fade;
}
