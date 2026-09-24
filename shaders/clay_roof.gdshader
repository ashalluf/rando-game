shader_type spatial;
render_mode cull_back;

// Mission-style barrel tiles for the railway station's roofs, drawn in the roof's UV (metres:
// u along the eave, v up the slope, as LandmarkGeo lays a sloped quad). Alternate cover and pan
// tiles make ridges running down the slope; each course overlaps the one below it with a shadow
// line; every tile has its own fired colour, and the pans hold the dirt. A flat terracotta plane
// is what made a tiled roof read as a painted one.
//
// Shader files use // comments, never #.

#include "res://shaders/landmark_common.gdshaderinc"

uniform vec3 tile_color : source_color = vec3(0.64, 0.33, 0.20);
// Tile pitch across (one cover + one pan) and course length down the slope, metres.
uniform float pitch = 0.42;
uniform float course = 0.38;
uniform float depth = 0.9;

void fragment() {
	vec2 uv = UV;
	float across = uv.x / pitch;
	float ci = floor(uv.y / course);
	// Each course is shifted a little so the rows do not line up like a grid.
	float ph = across + lm_hash21(vec2(ci, 2.0)) * 0.08;
	float tid = floor(ph);
	float f = fract(ph);
	// Barrel profile: the cover tile is the ridge (f near 0.5), the pan the trough either side.
	float prof = cos((f - 0.5) * 6.2831853);
	float along = fract(uv.y / course);
	// Each course laps over the one below: a lip at its lower end, shadowed underneath.
	float lip = smoothstep(0.0, 0.10, along);
	vec3 col = tile_color * (0.82 + 0.3 * lm_hash21(vec2(tid, ci)));
	// Pans are darker (dirt and shade), covers catch the light.
	col *= mix(0.72, 1.08, prof * 0.5 + 0.5);
	col *= mix(0.55, 1.0, lip);
	// Lichen and soot patches, sparse.
	col *= 1.0 - 0.18 * step(0.93, lm_hash21(vec2(floor(uv.x / 3.0), floor(uv.y / 2.0))));
	// Normal: tipped across by the barrel's slope, and down the slope at the lap.
	float dx = -sin((f - 0.5) * 6.2831853) * depth;
	float dy = (1.0 - lip) * depth * 1.5;
	NORMAL_MAP = normalize(vec3(dx * 0.5, dy * 0.5, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	ALBEDO = col * COLOR.rgb;
	ROUGHNESS = 0.78;
	SPECULAR = 0.35;
}
