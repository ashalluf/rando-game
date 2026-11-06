shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled;

// A spinning rotor as the eye sees it: a faint translucent disc with the blur of the blades in
// it, not four sharp blades. At 400 rpm a four-blade rotor turns about 40 degrees a frame at 60
// fps, so real blade geometry strobes - it jumps, stands still or runs backwards. Helicopter
// swaps its blades for this above `disc_rpm`. Drawn on a flat quad (UV 0..1 across the rotor
// diameter); everything outside the tip circle is discarded.

uniform vec3 blade_color : source_color = vec3(0.05, 0.05, 0.055);
// How many blades, and how wide each one's smear is as a share of the gap between blades.
uniform float blades = 4.0;
uniform float smear = 0.34;
// Opacity of the swept disc between the smears, and at the centre of each smear.
uniform float base_alpha : hint_range(0.0, 1.0) = 0.07;
uniform float blade_alpha : hint_range(0.0, 1.0) = 0.22;
// The smears turn slowly - a camera's view of a real rotor, not the rotor itself.
uniform float apparent_speed = 1.7;
// Hub radius as a share of the rotor radius: nothing is drawn inside it.
uniform float hub = 0.07;
// Fade the whole disc (the script sets it from the rotor speed, so it crossfades with the
// blades as a rotor spins up or winds down).
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	if (r > 1.0 || r < hub) {
		discard;
	}
	float a = atan(p.y, p.x) + TIME * apparent_speed;
	float sector = fract(a * blades / 6.2831853);
	// 1 on a blade's line, 0 half way to the next one; the smear trails off either side of it.
	float d = abs(sector - 0.5) * 2.0;
	float b = smoothstep(1.0 - smear, 1.0, d);
	// The blade tips sweep the most air: a slightly darker ring just inside the tip.
	float tip = smoothstep(0.90, 0.97, r) * (1.0 - smoothstep(0.97, 1.0, r));
	float inner = smoothstep(hub, hub + 0.12, r);
	float alpha = (base_alpha + blade_alpha * b + 0.10 * tip) * inner * fade;
	ALBEDO = blade_color;
	ROUGHNESS = 0.6;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
