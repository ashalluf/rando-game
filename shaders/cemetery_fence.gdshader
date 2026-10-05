shader_type spatial;
render_mode cull_disabled;

// The memorial park's iron fence and gate leaves (scripts/world/cemetery_build.gd): ONE quad per
// run of fence, the pickets cut out here. UV is metres: u along the run, v up from its foot.
// Square pickets every `pitch` with a spear finial over the top rail, a bottom and a top rail and a
// mid rail of rings; each picket is shaded as a rounded bar (its normal turned across it), so a
// flat quad reads as round iron from a few metres. Black, satin, a little rust at the feet.
// Past a few pixels a picket would alias: its cut-out widens to its own cover and the colour
// stays, so the run reads as a dark veil, as a real fence does from across the street.

#include "res://shaders/color_space.gdshaderinc"

uniform float pitch = 0.13;
uniform float bar = 0.022;
uniform float height = 1.75;
uniform vec3 iron = vec3(0.022, 0.022, 0.024);
uniform vec3 rust = vec3(0.16, 0.07, 0.03);

void fragment() {
	vec2 uv = UV;
	float px = max(fwidth(uv.x), 1e-4);
	float h = height;
	// The rails.
	float rail_b = step(abs(uv.y - 0.10), 0.025);
	float rail_t = step(abs(uv.y - (h - 0.22)), 0.025);
	float rail_m = step(abs(uv.y - (h - 0.38)), 0.018);
	// A picket: its distance from the nearest picket's centre line.
	float cell = fract(uv.x / pitch) - 0.5;
	float d = abs(cell) * pitch;
	float w = bar * 0.5;
	// The spear: above the top rail the bar narrows to a point.
	float spear = clamp((uv.y - (h - 0.12)) / 0.12, 0.0, 1.0);
	float wp = w * (1.0 + 0.9 * step(h - 0.12, uv.y) * (1.0 - spear) * 1.4) * (1.0 - spear * spear);
	if (uv.y > h) {
		wp = 0.0;
	}
	// Rings between the top and the mid rail (every other gap).
	vec2 rc = vec2((floor(uv.x / pitch) + 1.0) * pitch, h - 0.30);
	float ring = abs(length(vec2(uv.x, uv.y) - rc) - 0.045);
	float rings = step(ring, 0.006) * step(0.5, fract(floor(uv.x / pitch) * 0.5));
	float pick = step(d, max(wp, 0.0));
	// Far: cover instead of bars, so a distant run is a fine veil rather than shimmering moire.
	float far_a = smoothstep(0.004, 0.012, px);
	float cover = clamp(bar / pitch * 1.6, 0.0, 1.0);
	float solid = max(max(pick, rings), max(rail_b, max(rail_t, rail_m)));
	float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	float far_keep = max(step(dither, cover), max(rail_b, rail_t));
	float keep = mix(solid, far_keep, far_a);
	if (keep < 0.5) {
		discard;
	}
	// A rounded bar: turn the normal across the picket.
	float across = clamp(cell * pitch / max(w, 1e-4), -1.0, 1.0) * pick * (1.0 - far_a);
	vec3 nrm = normalize(NORMAL + TANGENT * across * 0.9);
	NORMAL = nrm;
	vec3 c = iron;
	float r = smoothstep(0.35, 0.0, uv.y) * 0.6;
	c = mix(c, rust, r);
	ALBEDO = cs_out(c);
	ROUGHNESS = mix(0.45, 0.85, r);
	METALLIC = 0.5;
}
