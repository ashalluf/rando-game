shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// The muzzle flash as a volume of burning gas (GunplayFeel.flash). The old flash was a ball and a
// billboarded star: from the side - which is how a third-person camera sees every shot - a
// round sprite reads as a light bulb on the barrel, not as gas leaving it. A real flash is a
// cone of flame along the bore with tongues off its sides and a disc of fire at the crown.
//
// The mesh (GunplayFeel.flash_mesh) is built in the flash's own frame, -Z down the bore:
//   * PETALS: four quads crossed round the bore axis, each a lance of flame along it. Every one
//     fades out as it turns edge-on to the eye, so any view sees two or three of them at a
//     slant and they add into a volume rather than reading as cards;
//   * the CROWN: one quad facing down the bore at the muzzle, the disc seen from the front,
//     faded as it turns edge-on (from the side the petals carry the shape);
//   * TONGUES: four short quads swept out sideways from the muzzle, the gas leaving a muzzle
//     brake.
// UV.x runs from the muzzle (0) to the tip (1); UV.y across, -1..1. UV2.x is the piece (0 petal,
// 1 crown, 2 tongue), UV2.y its index (each gets its own breakup).
// No textures: a few hashed value-noise octaves, so it costs nothing to load and every shot
// breaks up differently (`seed`).
//
// Colours are LINEAR (plain uniforms, written as linear numbers) and handed to the renderer with
// cs_out(): additive in linear HDR on Forward+, so the core blooms; Compatibility gets the same
// look in its own space. Every piece reaches zero at its quad's edge (an additive tail draws the
// quad - CLAUDE.md, fwd-review-d).

#include "res://shaders/color_space.gdshaderinc"

// 0 at the instant the round leaves, 1 when the flash is gone.
uniform float age = 0.0;
// Per shot, so no two flashes break up alike.
uniform float seed = 0.0;
// Brightness of the hot core (HDR) and of the cooled edges, linear.
uniform float heat = 7.0;
uniform vec3 core_color = vec3(1.0, 0.78, 0.46);
uniform vec3 edge_color = vec3(1.0, 0.36, 0.07);
// How far the flame grows along the bore over its life (1 = not at all).
uniform float stretch = 1.45;
// How ragged the flame is (0 smooth lances, 1 torn tongues).
uniform float breakup = 0.75;

varying vec3 v_view_n;


float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1.0, 0.0));
	float c = h21(i + vec2(0.0, 1.0));
	float d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


void vertex() {
	// The flame lengthens as the gas leaves and slows: stretch the pieces along the bore.
	float grow = mix(0.75, stretch, sqrt(clamp(age, 0.0, 1.0)));
	VERTEX.z *= grow;
	// Tongues sweep out a little further as they go.
	if (UV2.x > 1.5) {
		VERTEX.xy *= mix(0.8, 1.35, age);
	}
	v_view_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	float u = UV.x;
	float v = UV.y;
	float piece = UV2.x;
	float idx = UV2.y;
	float s = seed + idx * 7.31;
	// How square-on the card is to the eye: 1 face-on, 0 edge-on.
	float facing = abs(dot(normalize(v_view_n), normalize(VIEW)));
	float shape;
	float hot;
	float vis;
	if (piece < 0.5) {
		// A lance: widest a third of the way out, pinched at the muzzle, torn at the tip.
		float prof = pow(sin(3.14159 * pow(clamp(u, 0.0, 1.0), 0.55)), 0.8) * (1.0 - 0.35 * u);
		float wob = (vnoise(vec2(u * 5.0 + s, s * 1.7)) - 0.5) * 0.55 * breakup;
		float edge = abs(v + wob * u) / max(prof, 1e-3);
		shape = 1.0 - smoothstep(0.35, 1.0, edge);
		// Torn into tongues toward the tip.
		float tear = vnoise(vec2(u * 7.0 - s * 3.0, v * 2.5 + s));
		shape *= mix(1.0, smoothstep(0.25 + 0.5 * u, 0.85, tear + 0.35), breakup * smoothstep(0.25, 1.0, u));
		shape *= 1.0 - smoothstep(0.82, 1.0, u);
		hot = (1.0 - smoothstep(0.0, 0.7, u)) * (1.0 - smoothstep(0.0, 0.9, abs(v)));
		vis = smoothstep(0.08, 0.55, facing);
	} else if (piece < 1.5) {
		// The crown: a disc of fire with a ragged rim and a white-hot centre.
		vec2 c = vec2(u * 2.0 - 1.0, v);
		float r = length(c);
		float ang = atan(c.y, c.x);
		float rim = 0.62 + 0.38 * vnoise(vec2(ang * 2.2 + s, s * 0.5));
		shape = 1.0 - smoothstep(rim * 0.45, rim, r);
		hot = 1.0 - smoothstep(0.0, 0.45, r);
		vis = smoothstep(0.15, 0.75, facing);
	} else {
		// A tongue: a short jet out of the side of the muzzle, thinning to a point.
		float prof = (1.0 - u) * smoothstep(0.0, 0.18, u);
		float edge = abs(v) / max(prof, 1e-3);
		shape = (1.0 - smoothstep(0.3, 1.0, edge)) * (1.0 - smoothstep(0.7, 1.0, u));
		shape *= 0.55 + 0.45 * vnoise(vec2(u * 6.0 + s, s));
		hot = (1.0 - smoothstep(0.0, 0.55, u)) * 0.6;
		vis = smoothstep(0.1, 0.6, facing);
	}
	// It cools from white-hot through orange to nothing: the core goes first.
	float life = clamp(age, 0.0, 1.0);
	float fade = pow(1.0 - life, 1.6);
	hot *= 1.0 - smoothstep(0.0, 0.6, life);
	vec3 col = mix(edge_color * 0.55, core_color * 1.15, hot) * (0.35 + 0.65 * hot);
	float glow = shape * vis * fade;
	ALBEDO = cs_out(col * heat * glow);
}
