shader_type spatial;
render_mode cull_back;

// Italian cypress (CemeteryKit.cypress()): a tall flame of dense, scale-leaved foliage. The mesh is a
// lumpy spindle of unit height (instances scale it); here the lumps get their sprays: a 3D cell
// noise in the mesh's own space makes clumps, each lit as a little dome (its normal turned out of
// the clump's centre), dark in the crevices between, a few paler young tips, light through the
// edges against the sun. The whole column leans a little with the wind, more toward the top.
// Mesh: COLOR.r = 0 trunk (bark), 1 foliage. Linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float wind_factor;
// Off on the web and the low Quality levels: the clumps' 27-tap cell search is skipped there.
global uniform float ground_detail;

uniform vec3 leaf_color = vec3(0.030, 0.052, 0.024);
uniform vec3 tip_color = vec3(0.075, 0.105, 0.040);
uniform vec3 bark_color = vec3(0.12, 0.08, 0.055);
uniform float clump_scale = 34.0;
uniform float sway = 0.012;

varying vec3 v_obj;
varying float v_leaf;

vec3 cp_hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

// Distance to the nearest clump centre and the offset to it.
vec4 cp_cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float best = 8.0;
	vec3 off = vec3(0.0);
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = cp_hash3(i + g);
				vec3 r = g + o - f;
				float d = dot(r, r);
				if (d < best) {
					best = d;
					off = r;
				}
			}
		}
	}
	return vec4(off, sqrt(best));
}

void vertex() {
	v_obj = VERTEX;
	v_leaf = COLOR.r;
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * (0.7 + 0.3 * fract(world.x * 0.13)) + world.x * 0.07 + world.z * 0.05;
	float bend = VERTEX.y * VERTEX.y * sway * (0.4 + wind_factor) * (sin(t) + 0.4 * sin(t * 2.3));
	VERTEX.x += bend;
	VERTEX.z += bend * 0.5;
}

void fragment() {
	if (v_leaf < 0.5) {
		ALBEDO = cs_out(bark_color);
		ROUGHNESS = 0.9;
	} else {
		vec3 q = v_obj * clump_scale * vec3(1.0, 0.55, 1.0);
		float px = length(fwidth(q));
		float fade = (1.0 - smoothstep(0.5, 1.6, px)) * step(0.5, ground_detail);
		vec4 c = fade > 0.0 ? cp_cells(q) : vec4(0.0, 0.0, 0.0, 0.6);
		// A clump: lit as a dome round its centre, dark at its rim.
		vec3 bump = normalize(-c.xyz) * fade;
		vec3 n = normalize(NORMAL + (VIEW_MATRIX * vec4(bump, 0.0)).xyz * 0.55);
		NORMAL = n;
		float crevice = mix(0.6, smoothstep(0.95, 0.35, c.w), fade);
		float tips = step(0.8, cp_hash3(floor(q) + 3.0).x) * smoothstep(0.6, 0.2, c.w) * fade;
		vec3 col = mix(leaf_color, tip_color, tips * 0.8) * (0.45 + 0.75 * crevice);
		ALBEDO = cs_out(col);
		ROUGHNESS = 0.82;
		SPECULAR = 0.35;
		BACKLIGHT = cs_out(vec3(0.05, 0.08, 0.02));
		AO = mix(1.0, 0.55 + 0.45 * crevice, fade);
	}
}
