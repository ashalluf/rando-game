shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// The smoke off a backyard grill at dinner time (BackyardKit._smoke): a handful of camera-facing
// puffs, all placed here from TIME, rising off the grill, drifting down the wind, widening and
// thinning. The whole plume shows only while that household cooks: INSTANCE_CUSTOM.a is the
// household's seed, and the window is the same one backyard.gdshader's embers use (cooking()).
// Lit by hand like smoke_column.gdshader (the sun from the side, the sky as fill, the patio's
// warm light from below after dark), so both renderers draw it alike. Linear colours.

#include "res://shaders/color_space.gdshaderinc"

global uniform vec3 sun_direction;
global uniform float night_factor;
global uniform float lamp_factor;
global uniform vec3 sky_tint;
global uniform float city_hour;
global uniform float wind_factor;

uniform sampler2D puff : source_color, filter_linear_mipmap;
uniform float cook_share = 0.55;
uniform float height = 3.4;
uniform float rise_seconds = 7.0;
uniform float radius_base = 0.14;
uniform float radius_top = 0.85;
uniform float density = 0.5;
uniform vec3 smoke_color = vec3(0.55, 0.56, 0.58);

varying float v_alpha;
varying float v_rot;
varying float v_h;

float cooking(float seed) {
	if (seed >= cook_share) {
		return 0.0;
	}
	float s = seed / max(cook_share, 0.001);
	float start = 17.1 + s * 1.2;
	float len = 1.5 + fract(s * 7.31) * 1.6;
	float h = city_hour;
	return smoothstep(start, start + 0.15, h) * (1.0 - smoothstep(start + len - 0.2, start + len, h));
}

void vertex() {
	float seed = INSTANCE_CUSTOM.a;
	float on = cooking(seed);
	float slot = UV2.x;
	float rnd = fract(slot * 7.13 + seed * 13.7);
	float age = fract(TIME / rise_seconds + slot);
	float y = height * (1.0 - pow(1.0 - age, 1.5));
	float h01 = y / height;
	float r = mix(radius_base, radius_top, sqrt(h01));
	// Down the wind (world +x/-z, a breeze off the sea), more the higher it is.
	vec3 wind_w = normalize(vec3(1.0, 0.0, -0.4)) * (0.6 + wind_factor * 2.5);
	vec3 wind = (inverse(MODEL_MATRIX) * vec4(wind_w, 0.0)).xyz;
	vec3 c = vec3(0.0, 0.95 + y, 0.0) + wind * h01 * h01 * height * 0.6;
	float w = TIME * 0.7 + rnd * 6.28;
	c.xz += vec2(sin(w), cos(w * 0.8)) * r * 0.3;
	vec2 corner = UV * 2.0 - 1.0;
	vec3 right = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[0].xyz, 0.0)).xyz;
	vec3 upv = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[1].xyz, 0.0)).xyz;
	float size = r * (1.2 + 0.5 * rnd) * step(0.001, on);
	VERTEX = c + (right * corner.x + upv * corner.y) * size;
	v_alpha = smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.55, 1.0, age)) * density * on;
	v_rot = rnd * 6.28 + TIME * (rnd - 0.5) * 0.3;
	v_h = h01;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float cr = cos(v_rot);
	float sr = sin(v_rot);
	vec2 uv = vec2(c.x * cr - c.y * sr, c.x * sr + c.y * cr) * 0.5 + 0.5;
	vec4 tex = texture(puff, uv);
	float a = tex.a * v_alpha;
	if (a < 0.004) {
		discard;
	}
	float rr = dot(c, c);
	vec3 n_view = normalize(vec3(c.x, c.y, sqrt(max(1.0 - rr, 0.0)) + 0.35));
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(n_view, 0.0)).xyz);
	vec3 to_sun = normalize(sun_direction);
	float day = clamp(1.0 - night_factor, 0.0, 1.0) * smoothstep(-0.05, 0.12, to_sun.y);
	float lit = clamp(dot(n, to_sun) * 0.6 + 0.4, 0.0, 1.0);
	float shade = cs_in(tex.rgb).r * 1.6;
	vec3 sky = max(cs_srgb_to_linear(sky_tint), vec3(0.004));
	vec3 col = smoke_color * shade * (sky * 0.6 + vec3(1.0, 0.95, 0.88) * 1.4 * lit * day);
	// After dark: the patio's warm light from below, the fire's glow at the foot.
	col += smoke_color * shade * vec3(1.0, 0.62, 0.32) * 0.25 * lamp_factor * (1.0 - n.y * 0.5);
	col += vec3(1.0, 0.4, 0.12) * 0.25 * exp(-v_h * 6.0) * night_factor;
	ALBEDO = cs_out(col);
	ALPHA = clamp(a, 0.0, 1.0);
}
