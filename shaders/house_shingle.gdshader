shader_type spatial;
render_mode cull_back;

// Asphalt shingles on the suburbs' and the beach town's pitched roofs (HouseKit). Most of Los
// Angeles' ranch houses, bungalows and stucco boxes wear them, and from the street or the air a
// shingle roof is three things: COURSES (a dark shadow line under every butt edge, 14 cm apart),
// TABS that are each a slightly different shade (three-tab strips, or the ragged laminated
// "architectural" kind, which reads as a mottle of dark patches), and WEATHER (granules worn off
// in streaks down the slope, a paler band along the ridge and the eaves). All of it is worked out
// from the UV - metres along the eave and up the slope (HouseKit._roof_plane()) - so a roof of any
// size and pitch has courses of the same real size and no texture repeats.
//
// COLOR.rgb is the shingle colour (sRGB, as written: vertex colours arrive raw on both renderers),
// COLOR.a picks the kind: below 0.5 three-tab, above it laminated.

#include "res://shaders/color_space.gdshaderinc"

// Course exposure and three-tab width (metres).
uniform float course = 0.143;
uniform float tab = 0.333;
// How dark the shadow line under each course is, and how far the tab shades spread.
uniform float shadow_line = 0.42;
uniform float tab_spread = 0.16;
// Granule speckle and the streaks of worn granules down the slope.
uniform float granule = 0.10;
uniform float streaks = 0.14;
// How much the courses tilt the normal (each course is thicker at its butt).
uniform float relief = 0.55;

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


void fragment() {
	vec2 uv = UV;
	// Metres a pixel covers: the stand-in for a mip level, so the pattern fades to its own average
	// before it can alias.
	float mpp = max(length(dFdx(uv)), length(dFdy(uv)));
	float row = floor(uv.y / course);
	float fy = fract(uv.y / course);
	bool laminated = COLOR.a > 0.5;
	// Tabs: three-tab strips are offset by half a tab each course; laminated ones are cut at random.
	float tw = laminated ? mix(0.16, 0.42, h21(vec2(row, 3.1))) : tab;
	float shift = laminated ? h21(vec2(row, 7.7)) * 2.0 : mod(row, 2.0) * 0.5;
	float tx = uv.x / tw + shift;
	float tab_id = floor(tx);
	float fx = fract(tx);
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	// Each tab its own shade; laminated shingles also have the dark "shadow band" pieces.
	float shade = 1.0 + tab_spread * (h21(vec2(tab_id, row)) * 2.0 - 1.0);
	if (laminated && h21(vec2(tab_id * 1.7, row + 11.0)) < 0.28) {
		shade *= 0.72;
	}
	// The course and tab detail fade out as a course shrinks under a few pixels.
	float course_detail = 1.0 - smoothstep(course * 0.18, course * 0.45, mpp);
	float tab_detail = 1.0 - smoothstep(tw * 0.12, tw * 0.35, mpp);
	shade = mix(1.0, shade, tab_detail);
	// The shadow under the butt edge of the course above (the top of this one), and the keyway
	// slots between tabs on a three-tab roof.
	float aa = clamp(mpp / course, 0.02, 0.5);
	float line = 1.0 - smoothstep(0.0, 0.10 + aa, 1.0 - fy);
	line += (1.0 - smoothstep(0.0, 0.08 + aa, fy)) * 0.35;
	float key = laminated ? 0.0 : (1.0 - smoothstep(0.0, 0.025 + aa * 0.3, min(fx, 1.0 - fx) * tw)) * step(0.45, fy);
	float dark = clamp(line * shadow_line + key * 0.5, 0.0, 0.9) * course_detail;
	// Granules, and streaks down the slope where they have washed off.
	float g = (h21(floor(uv * 160.0)) - 0.5) * granule * (1.0 - smoothstep(0.004, 0.012, mpp));
	float streak = smoothstep(0.55, 0.9, vnoise(vec2(uv.x * 1.6, uv.y * 0.12)));
	float weather = 1.0 - streaks * streak + 0.06 * (vnoise(uv * 0.35) - 0.5);
	vec3 albedo = base * shade * (1.0 - dark) * (1.0 + g) * weather;
	// The average a far roof fades to keeps the courses' darkening, so the tone does not jump.
	ALBEDO = cs_out(clamp(albedo, vec3(0.0), vec3(1.0)));
	ROUGHNESS = mix(0.82, 0.95, h21(vec2(tab_id, row) + 0.5));
	SPECULAR = 0.35;
	// Each course is a wedge, thicker at its butt (fy 0), so its face leans up the slope; the
	// butt itself is a small step facing down it.
	float butt = 1.0 - smoothstep(0.0, 0.1, fy);
	float ny = (0.16 - butt * 0.95) * relief * course_detail;
	NORMAL_MAP = normalize(vec3(0.0, ny, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
