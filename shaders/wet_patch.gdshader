shader_type spatial;
// The wet ground round a broken fire hydrant (HydrantGeyser): a flat disc laid a hair over the
// pavement, darkening it the way water darkens concrete and asphalt and turning it to a mirror
// where it stands deep (a puddle in the middle, ragged at its edge), rung by the drops falling
// back out of the geyser. `radius01` is how far it has spread (0..1 of the mesh), `dry` how far it
// has dried back (it shrinks from its edge in noise, as a real wet patch does), `rain` how hard
// the drops are falling. Everything is a blend over what is under it, so it works the same on
// both renderers; the sky it mirrors is emitted (the `sky_tint` global), as the road shader does.
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

#include "res://shaders/color_space.gdshaderinc"

global uniform vec4 sky_tint;
global uniform float lamp_factor;

uniform float radius01 = 1.0;
uniform float dry = 0.0;
uniform float rain = 1.0;
uniform float darken = 0.62;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Rings of falling drops: a jittered grid of drops, each ringing outward on its own clock.
vec2 ripples(vec2 p, float t) {
	vec2 g = floor(p);
	vec2 sum = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = g + vec2(float(i), float(j));
			vec2 o = c + vec2(h21(c), h21(c + 7.1));
			float ph = fract(t * 1.3 + h21(c + 3.3));
			vec2 d = p - o;
			float r = length(d);
			float ring = sin((r - ph * 0.9) * 40.0) * smoothstep(0.0, 0.08, ph * 0.9 - r + 0.08) * smoothstep(0.12, 0.0, abs(r - ph * 0.9)) * (1.0 - ph);
			sum += d / max(r, 1e-3) * ring;
		}
	}
	return sum;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 w = (inverse(mat3(MODEL_MATRIX)) * (wp - MODEL_MATRIX[3].xyz)).xz;
	float n = vnoise(w * 1.3) * 0.6 + vnoise(w * 4.1) * 0.3 + vnoise(w * 11.0) * 0.1;
	// Ragged edge, shrinking inward as it dries; the middle stays wet longest.
	float edge = radius01 * (1.0 - dry) * (0.82 + 0.3 * n);
	float wet = 1.0 - smoothstep(edge - 0.08, edge + 0.02, r);
	float deep = (1.0 - smoothstep(edge * 0.35, edge * 0.75, r + (n - 0.5) * 0.35)) * (1.0 - dry);
	if (wet <= 0.001) {
		discard;
	}
	vec2 rp = ripples(w * 2.2, TIME) * rain * deep;
	NORMAL = normalize(mat3(VIEW_MATRIX) * normalize(vec3(rp.x * 0.35, 1.0, rp.y * 0.35)));
	float fres = pow(1.0 - clamp(dot(NORMAL, normalize(-VERTEX)), 0.0, 1.0), 4.0);
	float night = clamp(lamp_factor, 0.0, 1.0);
	vec3 sky = sky_tint.rgb * mix(1.0, 0.25, night);
	ALBEDO = vec3(0.0);
	ROUGHNESS = mix(0.32, 0.03, deep);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	EMISSION = cs_out(sky * (0.04 + 0.9 * fres) * mix(0.25, 1.0, deep));
	ALPHA = clamp(wet * mix(darken, 0.86, deep), 0.0, 1.0);
}
