shader_type canvas_item;

// Raindrops on the camera's glass (Weather's RainLens layer, -1, under the HUD), RainStreetNight's
// version (the street_night refcam review; RAIN_STREET_NIGHT=0 is Weather's old inline shader, pale
// flat discs). A drop on a lens is a tiny lens itself: it shows the frame behind it turned upside
// down and blurred, darker toward its edge, with a thin bright meniscus where it catches the light.
// So at night a drop shows a lamp as a small inverted spark and is otherwise nearly invisible, and
// by day a faint lensed patch - never a pale disc of dust. Few of them, toward the frame's edges.

uniform float strength = 0.0;
uniform vec3 tint : source_color = vec3(0.80, 0.86, 0.95);
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
// The blur inside a drop (a mip level of the screen) and how far it lenses (screen UV).
uniform float blur = 2.2;
uniform float lens = 0.022;
// The meniscus rim's brightness, and how much of the frame behind shows through the drop.
uniform float rim = 0.28;
uniform float show = 0.85;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float cover = 0.0;
	vec2 off = vec2(0.0);
	float ring = 0.0;
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		vec2 cells = vec2(18.0 + fi * 10.0, 10.0 + fi * 6.0);
		vec2 c = uv * cells;
		// SCREEN_UV.y runs downward here: subtracting time walks a drop down the glass.
		c.y -= TIME * (0.25 + fi * 0.3);
		float r = hash12(floor(c) + fi * 23.1);
		if (r < 0.9) {
			continue;
		}
		vec2 f = fract(c) - vec2(0.5) + (vec2(hash12(floor(c) + 7.7), hash12(floor(c) + 3.1)) - 0.5) * 0.4;
		f.y *= 0.6;
		float rad = mix(0.1, 0.19, hash12(floor(c) + 5.3));
		float d = length(f) / rad;
		float inside = 1.0 - smoothstep(0.82, 1.0, d);
		if (inside > cover) {
			cover = inside;
			// Inverted: the drop shows what lies on the far side of its centre.
			off = -f / cells * (1.0 + lens * 40.0) * 1.6;
			ring = exp(-pow((d - 0.86) / 0.07, 2.0)) * (0.6 + 0.4 * smoothstep(0.0, -0.5, f.y / rad));
		}
	}
	float edge = smoothstep(0.28, 0.72, length((uv - vec2(0.5)) * vec2(1.3, 1.0)));
	float a = clamp(cover * edge, 0.0, 1.0) * strength;
	if (a < 0.002) {
		COLOR = vec4(0.0);
	} else {
		vec3 seen = textureLod(screen, clamp(uv + off, vec2(0.002), vec2(0.998)), blur).rgb;
		vec3 behind = textureLod(screen, uv, blur * 0.6).rgb;
		// Darker toward the edge of the drop (the light bent away out of the frame).
		vec3 col = seen * show * mix(1.0, 0.55, smoothstep(0.3, 1.0, 1.0 - cover));
		col += ring * rim * (tint * 0.25 + behind * 1.5);
		COLOR = vec4(col, a);
	}
}
