shader_type spatial;
render_mode cull_back;

// The bus's destination signs (the `sign` slot of road_bus.glb, BigVehicles.sign_material()):
// three flush panels - over the windscreen, in the first window behind the front door, and over
// the rear window - each an amber LED matrix behind dark glass. The text is a small L8 texture
// per route (5 x 7 glyphs from LedScreen.GLYPHS, one texel a LED); which panel a fragment is on
// comes from its normal in the body mesh's own space, and its place on the panel from that
// panel's box (measured by tools/make_big_vehicles.py, which prints SIGN lines). LEDs are bright
// enough to read by day and glow at night; a dark texel is an unlit LED you can just see.

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;

uniform sampler2D front_text : filter_nearest, repeat_disable;
uniform sampler2D rear_text : filter_nearest, repeat_disable;
// LEDs across and down each text texture (its size in texels).
uniform vec2 front_cells = vec2(96.0, 9.0);
uniform vec2 rear_cells = vec2(24.0, 9.0);
// Panel boxes in mesh space: front (x0, x1, y0, y1), side (z0, z1, y0, y1), rear (x0, x1, y0, y1).
uniform vec4 front_rect = vec4(-1.1, 1.1, 2.73, 2.97);
uniform vec4 side_rect = vec4(-4.48, -3.38, 2.2, 2.5);
uniform vec4 rear_rect = vec4(-0.42, 0.42, 2.68, 2.90);
// Linear colours.
uniform vec3 led_color = vec3(1.0, 0.42, 0.04);
uniform float led_day = 2.2;
uniform float led_night = 1.6;
// Scrolling: a long destination slides through the side sign.
uniform float scroll_speed = 0.0;
// 0: the sign is off (a parked or wrecked bus).
uniform float lit = 1.0;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 n = normalize(ln);
	vec2 uv;
	bool rear = false;
	if (n.z < -0.5) {
		uv = vec2((front_rect.y - lp.x) / (front_rect.y - front_rect.x), (front_rect.w - lp.y) / (front_rect.w - front_rect.z));
	} else if (n.z > 0.5) {
		uv = vec2((lp.x - rear_rect.x) / (rear_rect.y - rear_rect.x), (rear_rect.w - lp.y) / (rear_rect.w - rear_rect.z));
		rear = true;
	} else {
		uv = vec2((side_rect.y - lp.z) / (side_rect.y - side_rect.x), (side_rect.w - lp.y) / (side_rect.w - side_rect.z));
	}
	uv = clamp(uv, vec2(0.0), vec2(0.9999));
	vec2 cells = rear ? rear_cells : front_cells;
	vec2 c = uv * cells;
	vec2 cell = floor(c);
	vec2 f = fract(c) - 0.5;
	float on = rear ? texture(rear_text, (cell + 0.5) / cells).r : texture(front_text, (cell + 0.5) / cells).r;
	// Round LEDs, anti-aliased by the cell's own footprint on screen.
	float w = max(fwidth(c.x), 1e-4);
	float d = length(f);
	float dot_m = 1.0 - smoothstep(0.36 - w, 0.36 + w, d);
	// Past a pixel per LED the dots merge into the glow they average to.
	float far = smoothstep(0.35, 0.9, w);
	dot_m = mix(dot_m, 0.40, far);
	float energy = mix(led_day, led_night, night_factor) * lit;
	vec3 glass = vec3(0.010, 0.010, 0.012);
	ALBEDO = cs_out(glass);
	ROUGHNESS = 0.12;
	SPECULAR = 0.5;
	EMISSION = cs_out(led_color * (on * dot_m * energy + 0.012 * dot_m * lit));
}
