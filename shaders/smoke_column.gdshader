shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// A big fire's smoke column (SmokeColumn, built by TreeFire's manager): a few dozen camera-facing
// puffs on ONE mesh, every one of them placed here from TIME - nothing per puff runs on the CPU.
// Each quad carries its slot in UV2 (x: its phase along the column, y: a random number); a puff
// rises the column on a loop, decelerating as it goes (a plume loses its heat), drifts down the
// wind more the higher it is (the lean grows with the square of the height), widens and thins.
// Lit by hand, so it reads the same on both renderers: the puff texture's own billows, a fake
// round normal per puff turned to the sun, the sky's colour as the fill, and the fire's glow on
// the column's foot (far stronger after dark, when the glow is most of what shows of it).
// Colours are linear; color_space.gdshaderinc hands each renderer its own space.

#include "res://shaders/color_space.gdshaderinc"

global uniform vec3 sun_direction;
global uniform float night_factor;
global uniform vec3 sky_tint;

uniform sampler2D puff_tex : source_color, filter_linear_mipmap;
/// How tall the column climbs (metres) and how fast its puffs rise (m/s at the foot).
uniform float height = 220.0;
uniform float rise_speed = 9.0;
/// Puff radius at the foot and at the top (metres).
uniform float radius_base = 4.0;
uniform float radius_top = 38.0;
/// How far the wind carries the top of the column (metres, xz).
uniform vec2 lean = vec2(60.0, 20.0);
/// 0..1: fades the whole column in as the fire grows and out once it is gone.
uniform float strength = 1.0;
/// 0..1: how hard the fire under it is burning (its foot glows).
uniform float glow = 1.0;
/// The smoke's own colour (linear): burning cars and trees give a dark, oily brown-black.
uniform vec3 smoke_color = vec3(0.030, 0.027, 0.025);
/// Light it takes from the sun and from the sky.
uniform float sun_gain = 1.6;
uniform float sky_gain = 0.55;
/// Opacity at the foot and at the top.
uniform float density_base = 0.95;
uniform float density_top = 0.38;

varying float v_alpha;
varying float v_y;
varying float v_rot;
varying float v_age;


void vertex() {
	float slot = UV2.x;
	float rnd = UV2.y;
	// Its place on the loop: a fixed share of the column per puff, so the column is always full.
	float age = fract(TIME * rise_speed / max(height, 1.0) * 0.6 + slot);
	float y = height * (1.0 - pow(1.0 - age, 1.7));
	float h01 = y / max(height, 1.0);
	float r = mix(radius_base, radius_top, sqrt(h01));
	// The plume bends over: the wind takes it more the higher it is, and near the top it
	// spreads out downwind into a long flattened sheet.
	vec3 centre = vec3(lean.x, 0.0, lean.y) * pow(h01, 1.6);
	centre.xz += lean * smoothstep(0.6, 1.0, h01) * (0.25 + 0.5 * rnd);
	centre.y = y;
	// The plume wanders: a slow sideways swing that grows with the puff, phase per puff.
	float w = TIME * 0.21 + rnd * 6.2832 + y * 0.013;
	centre.xz += vec2(sin(w), cos(w * 0.83)) * r * 0.32;
	float size = r * (1.35 + 0.55 * rnd) * (1.0 + 0.5 * smoothstep(0.6, 1.0, h01));
	vec2 corner = UV * 2.0 - 1.0;
	// Billboard in the node's own space (TreeFire keeps it unrotated and unscaled).
	vec3 right = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[0].xyz, 0.0)).xyz;
	vec3 up = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[1].xyz, 0.0)).xyz;
	VERTEX = centre + (right * corner.x + up * corner.y) * size;
	float fade = smoothstep(0.0, 0.05, age) * (1.0 - smoothstep(0.8, 1.0, age));
	v_alpha = fade * mix(density_base, density_top, h01) * strength;
	v_y = y;
	v_rot = rnd * 6.2832 + TIME * (rnd - 0.5) * 0.06;
	v_age = age;
}


void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float cr = cos(v_rot);
	float sr = sin(v_rot);
	vec2 uv = vec2(c.x * cr - c.y * sr, c.x * sr + c.y * cr) * 0.5 + 0.5;
	vec4 tex = texture(puff_tex, uv);
	float a = tex.a * v_alpha;
	if (a < 0.004) {
		discard;
	}
	// A round puff's normal, turned into the world, lit by the sun from its side.
	float rr = dot(c, c);
	vec3 n_view = normalize(vec3(c.x, c.y, sqrt(max(1.0 - rr, 0.0)) + 0.35));
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(n_view, 0.0)).xyz);
	vec3 to_sun = normalize(sun_direction);
	float day = clamp(1.0 - night_factor, 0.0, 1.0) * smoothstep(-0.05, 0.12, to_sun.y);
	float lit = clamp(dot(n, to_sun) * 0.6 + 0.4, 0.0, 1.0);
	// The billows' own shade (the texture is grey with its bumps in it), as linear light.
	float shade = cs_in(tex.rgb).r * 1.6;
	vec3 sky = max(sky_tint, vec3(0.02));
	vec3 col = smoke_color * shade * (sky * sky_gain + vec3(1.0, 0.96, 0.9) * sun_gain * lit * day);
	// At night the city's sodium light from below.
	col += smoke_color * shade * vec3(0.9, 0.55, 0.3) * 0.5 * night_factor * (1.0 - n.y * 0.5);
	// The fire's glow on the foot of the column, from underneath.
	float g = glow * exp(-v_y / 22.0) * mix(0.35, 1.0, night_factor) * (0.6 - 0.4 * n.y);
	col += vec3(1.0, 0.36, 0.08) * g * 0.9;
	ALBEDO = cs_out(col);
	ALPHA = clamp(a, 0.0, 1.0);
}
