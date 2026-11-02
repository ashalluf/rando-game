shader_type spatial;

// The hill roads' surface (CanyonRoad, scripts/world/canyon_road.gd): a two-lane canyon road the
// way the front range's are - old asphalt chip-sealed grey, a worn double yellow down the middle,
// white edge lines, the lanes polished by the tyres and darkened by oil in their centres, crack
// sealant snakes, patches, the edge crumbling away into a strip of gravel and dirt that the road
// mesh carries out past the asphalt (the shoulder), its outer edge torn ragged into the bank.
//
// The mesh carries UV.x = metres across from the centre line (signed), UV.y = 0, UV2.x = the
// asphalt's half width, UV2.y = the shoulder's outer half width. Everything along the road is
// read off true world XZ (`origin_shift`), so chunks meet and nothing moves on a re-centre.
// Colours are linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
// The asphalt's grey (linear): the photo is taken to its luminance first (StreetNoonReview: the
// asphalt set is brown and read as a dirt road).
uniform vec3 asphalt = vec3(0.105, 0.104, 0.102);
uniform float tex_scale = 6.0;
// The shoulder: decomposed granite and grit (linear), and how far into it the asphalt crumbles.
uniform vec3 gravel = vec3(0.235, 0.205, 0.165);
uniform vec3 dirt = vec3(0.175, 0.142, 0.105);
uniform float ravel = 0.35;
// Paint (linear): a faded traffic yellow and a dusty white, 10 cm lines.
uniform vec3 paint_yellow = vec3(0.52, 0.36, 0.06);
uniform vec3 paint_white = vec3(0.58, 0.58, 0.55);
uniform float line_width = 0.11;
uniform float line_gap = 0.09;
// The white edge line's distance in from the asphalt's edge.
uniform float edge_inset = 0.35;
uniform float paint_wear = 0.45;
// Lanes: the tyre tracks' polish and the oil down each lane's middle.
uniform float track_polish = 0.10;
uniform float oil = 0.35;
uniform float crack_amount = 0.6;
uniform float patch_amount = 0.35;

global uniform vec3 origin_shift;
global uniform float road_wetness;

varying vec3 world_pos;
varying vec2 lat;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.07 + 13.1) * 0.3 + vnoise(p * 4.31 - 7.7) * 0.2;
}

// A box-filtered band: 1 inside |x - c| < w / 2, faded by the pixel's footprint.
float band(float x, float c, float w, float fw) {
	float d = abs(x - c) - w * 0.5;
	return 1.0 - smoothstep(-fw, fw, d);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_shift;
	lat = vec2(UV.x, UV2.x);
}

void fragment() {
	vec2 w = world_pos.xz;
	float x = lat.x;
	float ax = abs(x);
	float half_w = lat.y;
	float fw = max(fwidth(x), 1e-4);
	float px = length(fwidth(w));

	// The asphalt's edge, crumbled: a ragged line round half_w, eaten in by `ravel`.
	float rag = (fbm(w * 1.3) - 0.5) * 0.5 + (vnoise(w * 6.0) - 0.5) * 0.18;
	float edge = half_w - ravel * fbm(w * 0.35) + rag;
	float on_asphalt = 1.0 - smoothstep(edge - max(fw, 0.03), edge + max(fw, 0.03), ax);

	// The textures, laid from above in world metres, the asphalt photo at its luminance.
	vec2 uv = w / tex_scale;
	vec3 tex = cs_in(texture(albedo_tex, uv).rgb);
	vec3 tex2 = cs_in(texture(albedo_tex, uv * 0.37 + vec2(0.31, 0.77)).rgb);
	float tl = dot(mix(tex, tex2, 0.5), vec3(0.2126, 0.7152, 0.0722));
	float tl_mean = 0.19;
	float grain = tl / tl_mean;
	vec3 nt = texture(normal_tex, uv).rgb;
	float rough_t = texture(rough_tex, uv).r;

	float lane_c = half_w * 0.5;
	// Asphalt: slow mottling, patches (a darker, smoother rectangle along the road), the tyre
	// tracks polished, oil down each lane's middle.
	vec3 a = asphalt * mix(0.82, 1.18, fbm(w * 0.06)) * mix(0.9, 1.1, vnoise(w * 0.8));
	vec2 pc = floor(w / vec2(9.0, 9.0));
	float ph = hash12(pc + 17.0);
	float patch = step(1.0 - patch_amount, ph) * (1.0 - smoothstep(0.38, 0.45, max(abs(fract(w.x / 9.0) - 0.5), abs(fract(w.y / 9.0) - 0.5)) + (vnoise(w * 2.0) - 0.5) * 0.06));
	a *= mix(1.0, mix(0.62, 0.78, hash12(pc)), patch);
	float tracks = band(ax, lane_c - 0.85, 0.55, 0.25) + band(ax, lane_c + 0.85, 0.55, 0.25);
	float oil_band = band(ax, lane_c, 0.8, 0.3) * oil * smoothstep(0.35, 0.7, fbm(w * vec2(0.4, 0.4) + 3.0));
	a *= 1.0 - oil_band * 0.45;
	a *= 1.0 + tracks * track_polish;
	// Crack sealant (tar snakes): the longitudinal joint by the centre line and one down each
	// wheel path, wandering a hand either way, sealed in broken runs; and in some stretches a
	// sparse net of finer snakes (folded, domain-warped noise, only where a slow mask lets it).
	// All faded to nothing once a snake is under a pixel.
	float seal_w = 0.035 + px * 0.5;
	float wander = (vnoise(w * vec2(0.35, 0.35) + 3.1) - 0.5) * 0.5;
	float joint = band(x, 0.35 + wander, seal_w, fw) + band(ax, lane_c + 0.85 + wander * 0.6, seal_w * 0.8, fw) * 0.7;
	joint *= step(0.45, vnoise(w * 0.12 + 11.0));
	vec2 wq = w + vec2(vnoise(w * 0.7), vnoise(w * 0.7 + 5.2)) * 1.6;
	float cr = abs(vnoise(wq * 0.8 + 41.0) - 0.5);
	float net = (1.0 - smoothstep(0.0, 0.01 + px * 0.02, cr)) * smoothstep(0.62, 0.75, vnoise(w * 0.05 + 29.0));
	float crack = clamp(joint + net, 0.0, 1.0) * crack_amount * (1.0 - smoothstep(0.06, 0.3, px));
	a = mix(a, vec3(0.035, 0.034, 0.033), crack * 0.85);
	a *= mix(0.7, 1.3, clamp(grain, 0.0, 2.0) * 0.5 + 0.25);

	// Paint: the double yellow down the centre, the white edge lines, worn by the tyres and by age.
	float wear = smoothstep(paint_wear - 0.25, paint_wear + 0.25, fbm(w * 1.7 + 5.0)) * (1.0 - tracks * 0.4);
	float offc = (line_width + line_gap) * 0.5;
	float yl = (band(x, offc, line_width, fw) + band(x, -offc, line_width, fw)) * step(2.4, half_w);
	float wl = band(ax, half_w - edge_inset - line_width * 0.5, line_width * 1.3, fw) * step(2.4, half_w);
	// Speckled where it is thinning (the aggregate through the paint), faded to its mean under a pixel.
	float speck = mix(step(0.35, vnoise(w * 40.0)), 0.65, smoothstep(0.01, 0.04, px));
	float paint_y = yl * wear * speck;
	float paint_w = wl * wear * speck * on_asphalt;
	a = mix(a, paint_yellow * (0.85 + 0.15 * grain), paint_y);
	a = mix(a, paint_white * (0.85 + 0.15 * grain), paint_w);

	// The shoulder: gravel by the asphalt, dirt farther out, darker grit along the edge.
	float out_t = smoothstep(edge, edge + 1.2, ax);
	vec3 g = mix(gravel, dirt, clamp(out_t + (fbm(w * 0.9) - 0.5) * 0.6, 0.0, 1.0));
	g *= mix(0.78, 1.18, vnoise(w * 7.0)) * mix(0.9, 1.1, fbm(w * 0.3));
	g = mix(g * 0.72, g, smoothstep(edge, edge + 0.35, ax));
	vec3 col = mix(g, a, on_asphalt);

	// Wet: darker and much smoother.
	float wet = clamp(road_wetness, 0.0, 1.0);
	col *= mix(1.0, mix(0.55, 0.7, 1.0 - on_asphalt), wet);
	float rough = mix(mix(0.93, 0.78, on_asphalt), 0.12, wet * on_asphalt) - (paint_y + paint_w) * 0.08;
	rough = mix(rough, rough * mix(0.85, 1.05, rough_t), on_asphalt) - tracks * 0.06 * on_asphalt - oil_band * 0.12;

	// The shoulder's outer edge is torn into the bank.
	float outer = UV2.y;
	float tear = outer - 0.15 - fbm(w * 1.1 + 9.0) * 0.7;
	if (ax > tear) {
		discard;
	}

	ALBEDO = cs_out(col);
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.45;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nt, mix(0.35, 0.6, on_asphalt));
	NORMAL_MAP_DEPTH = 0.8;
}
