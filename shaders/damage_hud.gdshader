shader_type canvas_item;
render_mode unshaded;

// Being hurt (scripts/ui/damage_hud.gd): a dark red bloom at the screen edges on every hit, a
// slow heartbeat of it while health is low, and up to four short red arcs on a ring round the
// crosshair pointing at whoever fired (each fading over its own life). Drawn over the 3D picture,
// under the rest of the HUD; nothing is drawn when all of it is zero.

uniform vec2 rect_px = vec2(1920.0, 1080.0);
// 0..1: the flash of the last hit, and the low-health pulse.
uniform float hurt = 0.0;
uniform float low = 0.0;
// xy the direction on screen (y down), z the arc's strength.
uniform vec4 arcs[4];
uniform vec3 edge_color : source_color = vec3(0.42, 0.015, 0.01);
uniform vec3 arc_color : source_color = vec3(1.0, 0.16, 0.1);
// The arcs' ring radius as a share of the screen height, its thickness and the arc's half-width
// as the cosine of its half-angle.
uniform float ring_radius = 0.2;
uniform float ring_px = 7.0;
uniform float arc_cos = 0.955;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * rect_px;
	vec2 q = (UV - vec2(0.5)) * 2.0;
	// Edges: strongest in the corners, nothing in the middle third.
	float edge = smoothstep(0.45, 1.35, length(q * vec2(0.82, 1.0)));
	float a_edge = edge * clamp(hurt * 0.8 + low * 0.7, 0.0, 0.9);
	// Arcs.
	float R = rect_px.y * ring_radius;
	float d = length(p);
	vec2 dir = p / max(d, 1e-3);
	float ring = exp(-pow((d - R) / ring_px, 2.0));
	float a_arc = 0.0;
	for (int i = 0; i < 4; i++) {
		float c = dot(dir, arcs[i].xy);
		// Tapered ends: full in the middle of the arc, fading to its tips.
		float arc = smoothstep(arc_cos, arc_cos + (1.0 - arc_cos) * 0.6, c);
		a_arc = max(a_arc, ring * arc * arcs[i].z);
	}
	vec3 col = mix(edge_color, arc_color, clamp(a_arc / max(a_arc + a_edge, 1e-4), 0.0, 1.0));
	float a = clamp(a_edge + a_arc * 0.9, 0.0, 1.0);
	COLOR = vec4(col, a);
}
