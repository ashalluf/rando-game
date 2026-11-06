shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// The steam off a taco truck's extractor stack (TacoTruckNight.add_steam, fleet wave 8 rc5
// `taco_truck_night`): twelve camera-facing puffs placed here from TIME, rising off the stack,
// leaning down the breeze, widening and thinning. The plancha never stops while the truck works,
// so it always shows. Lit by hand like backyard_smoke.gdshader (sun and sky by day; after dark
// the truck's window and the street lamps from below, warm), so both renderers draw it alike.
// Linear colours (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform vec3 sun_direction;
global uniform float night_factor;
global uniform float lamp_factor;
global uniform vec3 sky_tint;
global uniform float wind_factor;

uniform sampler2D puff : source_color, filter_linear_mipmap;
uniform float height = 2.6;
uniform float rise_seconds = 4.5;
uniform float radius_base = 0.12;
uniform float radius_top = 0.6;
uniform float density = 0.34;
uniform vec3 steam_color = vec3(0.78, 0.78, 0.8);
// The window's and the street's warm light on the plume's underside after dark.
uniform float under_light = 0.55;

varying float v_alpha;
varying float v_rot;
varying float v_h;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float seed = fract(sin(dot(floor(origin.xz * 0.5), vec2(12.9898, 78.233))) * 43758.5453);
	float slot = UV2.x;
	float rnd = fract(slot * 7.13 + seed * 13.7);
	float age = fract(TIME / rise_seconds + slot + seed);
	float y = height * (1.0 - pow(1.0 - age, 1.6));
	float h01 = y / height;
	float r = mix(radius_base, radius_top, sqrt(h01));
	vec3 wind_w = normalize(vec3(1.0, 0.0, -0.4)) * (0.5 + wind_factor * 2.0);
	vec3 wind = (inverse(MODEL_MATRIX) * vec4(wind_w, 0.0)).xyz;
	vec3 c = vec3(0.0, y, 0.0) + wind * h01 * h01 * height * 0.35;
	float w = TIME * 0.9 + rnd * 6.28;
	c.xz += vec2(sin(w), cos(w * 0.8)) * r * 0.35;
	vec2 corner = UV * 2.0 - 1.0;
	vec3 right = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[0].xyz, 0.0)).xyz;
	vec3 upv = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[1].xyz, 0.0)).xyz;
	float size = r * (1.2 + 0.5 * rnd);
	VERTEX = c + (right * corner.x + upv * corner.y) * size;
	v_alpha = smoothstep(0.0, 0.1, age) * (1.0 - smoothstep(0.35, 1.0, age)) * density;
	v_rot = rnd * 6.28 + TIME * (rnd - 0.5) * 0.4;
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
	float shade = cs_in(tex.rgb).r * 1.5;
	vec3 sky = max(cs_srgb_to_linear(sky_tint), vec3(0.004));
	vec3 col = steam_color * shade * (sky * 0.6 + vec3(1.0, 0.95, 0.88) * 1.4 * lit * day);
	// After dark: lit from below by the window and the lamps, strongest near the stack.
	float under = (1.0 - n.y * 0.5) * mix(1.0, 0.35, v_h);
	col += steam_color * shade * vec3(1.0, 0.78, 0.55) * under_light * under * lamp_factor;
	ALBEDO = cs_out(col);
	ALPHA = clamp(a, 0.0, 1.0);
}
