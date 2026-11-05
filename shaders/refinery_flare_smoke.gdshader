shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

// The smoke off the refinery's flares (rc4-refinery-road; Refinery.add_fx(), RcRefineryRoad): every
// flare of a piece in ONE mesh of camera-facing puffs placed here from TIME (refinery_plume's way).
// All four corners of a puff sit at its flare's tip (VERTEX); UV is the corner, UV2.x the puff's
// slot along its loop, UV2.y a random number. A flare burning heavy gas never burns clean: a
// ribbon of soot leaves the top of the flame, swells and leans down the wind. At night it is seen
// only where the flame under it lights it - orange-brown low, going to dark grey against the sky -
// and by day it is a brown-grey trail. Colours linear (color_space).

#include "res://shaders/color_space.gdshaderinc"

global uniform vec3 sun_direction;
global uniform float night_factor;
global uniform vec4 sky_tint;

uniform sampler2D puff_tex : source_color, filter_linear_mipmap;
/// Where the smoke leaves the flame (metres over the tip: the flame's length) and how high it rises.
uniform float start = 12.0;
uniform float height = 90.0;
uniform float rise_speed = 6.0;
/// Puff radius where it leaves the flame and at the top.
uniform float radius_base = 3.5;
uniform float radius_top = 22.0;
/// Where the wind carries the top (metres, xz; the flame's own lean is (5, 2)).
uniform vec2 lean = vec2(60.0, 22.0);
uniform float density = 0.42;
/// The flame's light on the smoke's underside (linear) and how high up it reaches (share of height).
uniform vec3 flame_light = vec3(1.0, 0.42, 0.12);
uniform float flame_gain = 0.9;
uniform float flame_reach = 0.32;
/// The soot's own colour (linear).
uniform vec3 soot = vec3(0.10, 0.09, 0.085);

varying float v_alpha;
varying float v_h01;
varying float v_rot;

void vertex() {
	float slot = UV2.x;
	float rnd = UV2.y;
	float age = fract(TIME * rise_speed / max(height, 1.0) * 0.8 + slot);
	float y = height * (1.0 - pow(1.0 - age, 1.4));
	float h01 = y / max(height, 1.0);
	float r = mix(radius_base, radius_top, sqrt(h01));
	vec3 centre = VERTEX + vec3(5.0, start, 2.0) + vec3(lean.x, 0.0, lean.y) * pow(h01, 1.25);
	centre.y += y;
	float w = TIME * 0.35 + rnd * 6.2832 + y * 0.06;
	centre.xz += vec2(sin(w), cos(w * 0.83)) * r * 0.35;
	float size = r * (1.2 + 0.5 * rnd);
	vec3 cv = (MODELVIEW_MATRIX * vec4(centre, 1.0)).xyz;
	vec2 corner = (UV - vec2(0.5)) * size * 2.0;
	VERTEX = cv + vec3(corner.x, -corner.y, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	float fade = smoothstep(0.0, 0.1, age) * (1.0 - smoothstep(0.3, 1.0, age));
	v_alpha = fade * density;
	v_h01 = h01;
	v_rot = rnd * 6.2832 + TIME * (rnd - 0.5) * 0.12;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	vec2 uv = vec2(c.x * cos(v_rot) - c.y * sin(v_rot), c.x * sin(v_rot) + c.y * cos(v_rot)) * 0.5 + 0.5;
	vec4 tex = texture(puff_tex, uv);
	float a = tex.a * v_alpha;
	if (a < 0.004) {
		discard;
	}
	float rr = dot(c, c);
	vec3 n_view = normalize(vec3(c.x, c.y, sqrt(max(1.0 - rr, 0.0)) + 0.4));
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(n_view, 0.0)).xyz);
	vec3 to_sun = normalize(sun_direction);
	float day = clamp(1.0 - night_factor, 0.0, 1.0) * smoothstep(-0.05, 0.12, to_sun.y);
	float lit = clamp(dot(n, to_sun) * 0.5 + 0.5, 0.0, 1.0);
	float lum = clamp(dot(cs_in(tex.rgb), vec3(0.2126, 0.7152, 0.0722)) * 1.6, 0.3, 1.3);
	vec3 sky = max(cs_srgb_to_linear(sky_tint.rgb), vec3(0.003));
	// Soot: dark, taking a little of the sky and, by day, the sun.
	vec3 col = soot * lum * (sky * 1.2 + vec3(1.0, 0.95, 0.88) * 1.2 * lit * day);
	// The flame under it: hot orange low down, mostly on the faces turned down toward it.
	float under = pow(1.0 - clamp(v_h01 / max(flame_reach, 0.05), 0.0, 1.0), 2.0) * (0.75 - 0.35 * n.y);
	col += flame_light * flame_gain * under * lum * (0.35 + 0.65 * night_factor);
	// Thicker low down, thinning as it mixes.
	a *= 1.0 - 0.45 * v_h01;
	ALBEDO = cs_out(col);
	ALPHA = clamp(a, 0.0, 1.0);
}
