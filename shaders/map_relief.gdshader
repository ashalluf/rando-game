shader_type canvas_item;
render_mode unshaded;

// The ground under the minimap and the full-screen map (scripts/ui/map_painter.gd): the sea, the
// beaches and the mountains painted from the basin bake (MacroMap.bake(): RGB the ground colour,
// alpha 0 on water; bake_height R the land height / height_scale), hill-shaded from the north-west
// with faint 100 m contours, in the map's own dark palette. The streets, blocks and everything
// else are drawn over it as vectors. The rect is the map's canvas; every pixel is turned back into
// world XZ with the same centre, scale and rotation the vectors use.

uniform sampler2D color_tex : filter_linear, repeat_disable;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec2 macro_centre = vec2(0.0);
uniform float macro_span = 16000.0;
uniform float height_scale = 1600.0;
uniform float bake_res = 512.0;
// World XZ at the canvas centre, screen pixels per metre, the canvas size and its rotation (the
// minimap turns with the camera).
uniform vec2 view_center = vec2(0.0);
uniform float ppm = 1.0;
uniform vec2 rect_px = vec2(260.0);
uniform float yaw = 0.0;
// How strong the hill shading and the contours are.
uniform float relief = 1.0;
uniform float contour = 0.13;

const vec3 DEEP = vec3(0.045, 0.105, 0.19);
const vec3 SHALLOW = vec3(0.10, 0.22, 0.33);
const vec3 SURF = vec3(0.24, 0.38, 0.47);
const vec3 LOWLAND = vec3(0.16, 0.17, 0.18);
const vec3 GRASS = vec3(0.21, 0.245, 0.165);
const vec3 BRUSH = vec3(0.17, 0.215, 0.15);
const vec3 SCREE = vec3(0.31, 0.285, 0.23);
const vec3 ROCK = vec3(0.36, 0.35, 0.33);
const vec3 SNOW = vec3(0.70, 0.72, 0.76);
const vec3 SAND = vec3(0.46, 0.41, 0.29);

float height_at(vec2 uv) {
	return texture(height_tex, uv).r * height_scale;
}

void fragment() {
	vec2 q = UV * rect_px - rect_px * 0.5;
	float c = cos(yaw);
	float s = sin(yaw);
	vec2 m = vec2(c * q.x + s * q.y, -s * q.x + c * q.y);
	vec2 world = view_center + m / max(ppm, 1e-5);
	vec2 uv = (world - macro_centre) / macro_span + 0.5;
	vec4 bake = texture(color_tex, clamp(uv, vec2(0.0), vec2(1.0)));
	float h = height_at(uv);
	float texel = 1.0 / bake_res;
	float step_m = macro_span / bake_res;
	float hx = (height_at(uv + vec2(texel, 0.0)) - height_at(uv - vec2(texel, 0.0))) / (2.0 * step_m);
	float hz = (height_at(uv + vec2(0.0, texel)) - height_at(uv - vec2(0.0, texel))) / (2.0 * step_m);
	vec3 n = normalize(vec3(-hx * 2.2, 1.0, -hz * 2.2));
	vec3 light = normalize(vec3(-0.6, 0.75, -0.6));
	float lambert = dot(n, light);
	float shade = clamp(1.0 + 1.7 * (lambert - light.y), 0.3, 1.75);
	float water = 1.0 - smoothstep(0.0, 0.006, bake.a);
	float lum = dot(bake.rgb, vec3(0.3, 0.5, 0.2));
	vec3 sea = mix(DEEP, SHALLOW, smoothstep(0.02, 0.09, lum));
	sea = mix(sea, SURF, smoothstep(0.16, 0.32, lum) * 0.8);
	// Land by height: lowland (the city, drawn over), grass, brush, scree, rock, snow.
	vec3 land = mix(LOWLAND, GRASS, smoothstep(12.0, 60.0, h));
	land = mix(land, BRUSH, smoothstep(160.0, 420.0, h));
	land = mix(land, SCREE, smoothstep(520.0, 820.0, h));
	land = mix(land, ROCK, smoothstep(820.0, 1150.0, h));
	land = mix(land, SNOW, smoothstep(1330.0, 1500.0, h));
	float sand = step(0.1, bake.r - bake.b) * step(0.4, bake.r) * (1.0 - smoothstep(20.0, 45.0, h));
	land = mix(land, SAND, sand);
	land *= mix(1.0, shade, relief * smoothstep(8.0, 40.0, h));
	// Contours every 100 m on the hills, a heavier one every 500 m.
	float lines = h / 100.0;
	float d = abs(fract(lines + 0.5) - 0.5) / max(fwidth(lines), 1e-4);
	float line = (1.0 - smoothstep(0.4, 1.3, d)) * smoothstep(40.0, 90.0, h);
	float major = step(abs(fract(h / 500.0 + 0.5) - 0.5) * 5.0, 0.5);
	land *= 1.0 - line * contour * (1.0 + major);
	// Past the bake's edge the map ends in a dark margin.
	vec2 out_uv = max(-uv, uv - 1.0);
	float outside = smoothstep(0.0, 0.015, max(out_uv.x, out_uv.y));
	COLOR = vec4(mix(mix(land, sea, water), vec3(0.055, 0.06, 0.07), outside), 1.0);
}
