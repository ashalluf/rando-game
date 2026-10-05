// The city's birds (scripts/world/birds.gd, meshes from scripts/world/bird_mesh.gd): one MultiMesh
// per species and level of detail. Each vertex carries two poses - VERTEX in flight, CUSTOM0.xyz
// on the ground (CUSTOM1.xyz its normal) - which this blends by the instance's spread, then flaps
// the spread wings, bends the hand on the upstroke, pecks and bobs the head and walks the legs.
//
// Per instance (written by Birds every frame it moves them):
//   INSTANCE_CUSTOM.x spread 0 ground .. 1 flight, .y phase (wingbeat or stride, 0..1), .z peck,
//   .w walk (stride amplitude); COLOR.rgb the plumage morph (sRGB, black = the painted bird),
//   COLOR.a flap amplitude (0 a glide or a bird on the ground).
// Works in linear on both renderers (color_space.gdshaderinc). Shader files use // comments.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_disable;

// Pivots in the bird's space (BirdMesh.pivots()): shoulder and wrist on the right side (x > 0),
// the neck's base and the hip.
uniform vec3 shoulder = vec3(0.022, 0.138, -0.035);
uniform vec3 wrist = vec3(0.085, 0.138, -0.027);
uniform vec3 neck = vec3(0.0, 0.143, -0.07);
uniform vec3 hip = vec3(0.017, 0.075, 0.0);
uniform vec3 tail_base = vec3(0.0, 0.113, 0.072);
// Wingbeat: the arm's half stroke in radians and how far the stroke sits above level, the hand's
// own bend, how far the hand sweeps back on the upstroke (radians).
uniform float flap_angle = 0.95;
uniform float flap_bias = 0.18;
uniform float hand_flex = 0.45;
uniform float hand_sweep = 0.5;
// The glide: the arm's and the hand's angle when the wings are held out (a gull's crook).
uniform float glide_arm = 0.08;
uniform float glide_hand = -0.05;
// The head: how far a peck pitches the neck (radians), how far a pigeon's head bobs (metres).
uniform float peck_angle = 1.15;
uniform float bob_amount = 0.016;
// The legs' swing on a stride (radians).
uniform float stride_angle = 0.55;
// Iridescence (mask R): the two colours of the sheen, linear, by the angle to the eye.
uniform vec3 irid_a = vec3(0.04, 0.22, 0.10);
uniform vec3 irid_b = vec3(0.22, 0.05, 0.20);
uniform float irid_strength = 0.75;
// The luminance a morph is measured against (the painted bird's main grey, linear).
uniform float morph_ref = 0.33;
// Light through the thin flight and tail feathers.
uniform float feather_backlight = 0.2;

varying vec3 v_tint;
varying float v_morph;
varying float v_thin;

vec3 rot_x(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

vec3 rot_y(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

vec3 rot_z(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

void vertex() {
	float spread = INSTANCE_CUSTOM.x;
	float phase = INSTANCE_CUSTOM.y;
	float peck = INSTANCE_CUSTOM.z;
	float walk = INSTANCE_CUSTOM.w;
	float amp = COLOR.a;
	float part = CUSTOM0.w;
	float wgt = CUSTOM1.w;
	vec3 fp = VERTEX;
	vec3 fn = NORMAL;
	vec3 gp = CUSTOM0.xyz;
	vec3 gn = CUSTOM1.xyz;
	float bsign = dot(BINORMAL, cross(NORMAL, TANGENT)) < 0.0 ? -1.0 : 1.0;
	v_thin = 0.0;
	if (part > 0.5 && part < 1.5) {
		// A wing: the hand bends and sweeps about the wrist, then the whole wing beats about the
		// shoulder. Flight pose only; the folded wing does not move.
		v_thin = 1.0;
		float side = sign(fp.x);
		float s = sin(TAU * phase);
		float arm = amp * (flap_bias + s) * flap_angle + (1.0 - amp) * glide_arm;
		float hand = amp * hand_flex * sin(TAU * phase - 0.9) + (1.0 - amp) * glide_hand;
		float sweep = amp * hand_sweep * max(0.0, cos(TAU * phase));
		vec3 wp = vec3(side * wrist.x, wrist.y, wrist.z);
		vec3 hp = rot_z(rot_y(fp - wp, sweep * side), hand * side) + wp;
		vec3 hn = rot_z(rot_y(fn, sweep * side), hand * side);
		fp = mix(fp, hp, wgt);
		fn = mix(fn, hn, wgt);
		vec3 sp = vec3(side * shoulder.x, shoulder.y, shoulder.z);
		fp = rot_z(fp - sp, arm * side) + sp;
		fn = rot_z(fn, arm * side);
	} else if (part > 1.5 && part < 2.5) {
		v_thin = 1.0;
		// The tail tips down a little with each downstroke.
		float tilt = amp * 0.12 * sin(TAU * phase + 1.2);
		fp = rot_x(fp - tail_base, tilt) + tail_base;
		fn = rot_x(fn, tilt);
	} else if (part > 2.5 && part < 3.5) {
		// A leg on the ground swings with the stride, the two legs half a stride apart; the
		// lifted foot comes up off the ground.
		float side = wgt;
		float ph = TAU * phase + (side > 0.0 ? 0.0 : PI);
		float a = walk * stride_angle * sin(ph);
		vec3 hp = vec3(side * hip.x, hip.y, hip.z);
		gp = rot_x(gp - hp, -a) + hp;
		gp.y += walk * 0.25 * hip.y * max(0.0, cos(ph)) * smoothstep(hip.y * 0.6, 0.0, CUSTOM0.y);
		gn = rot_x(gn, -a);
	}
	vec3 p = mix(gp, fp, spread);
	vec3 n = normalize(mix(gn, fn, spread));
	if (part < 0.5 || part > 3.5) {
		// The neck bends by the head's share: a peck pitches it down, a pigeon's stride throws the
		// head forward and holds it while the body walks under it.
		float hw = wgt;
		float f = fract(phase);
		float bob = f < 0.3 ? mix(-1.0, 1.0, f / 0.3) : mix(1.0, -1.0, (f - 0.3) / 0.7);
		p = rot_x(p - neck, -peck * peck_angle * hw) + neck;
		n = rot_x(n, -peck * peck_angle * hw);
		p.z -= bob * bob_amount * walk * hw * (1.0 - spread);
	}
	VERTEX = p;
	NORMAL = n;
	TANGENT = normalize(TANGENT - n * dot(n, TANGENT));
	BINORMAL = cross(n, TANGENT) * bsign;
	v_morph = step(0.001, max(max(COLOR.r, COLOR.g), COLOR.b));
	v_tint = cs_srgb_to_linear(COLOR.rgb);
}

void fragment() {
	vec4 alb = texture(albedo_tex, UV);
	vec3 base = cs_in(alb.rgb);
	vec3 m = texture(mask_tex, UV).rgb;
	// A colour morph keeps the painted pattern as a ratio to the main grey, flattened toward a
	// white bird's faint bars.
	float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
	float tl = dot(v_tint, vec3(0.2126, 0.7152, 0.0722));
	float k = mix(0.75, 0.22, smoothstep(0.15, 0.7, tl));
	vec3 morphed = v_tint * pow(max(lum, 1e-4) / morph_ref, k);
	base = mix(base, morphed, m.g * v_morph);
	// Structural colour: green to purple on a pigeon's neck, a blue-violet gloss on a crow.
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 irid = mix(irid_b, irid_a, smoothstep(0.15, 0.85, ndv));
	// Thin-film colour rides on a darkened base, strongest toward grazing angles.
	float sheen = m.r * irid_strength * (0.55 + 0.45 * (1.0 - ndv)) * mix(1.0, 0.55, v_morph * step(0.4, tl));
	base = mix(base, base * 0.55 + irid, sheen);
	// Cut-out: a texel's alpha thins in the mips, so lift it with the mip level or a far feather
	// dissolves to nothing.
	vec2 px = UV * 1024.0;
	vec2 dx = dFdx(px);
	vec2 dy = dFdy(px);
	float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	ALPHA = alb.a * (1.0 + mip * 0.3);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = cs_out(base);
	ROUGHNESS = m.b;
	SPECULAR = 0.4;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.7;
	BACKLIGHT = cs_out(base * feather_backlight * v_thin);
}
