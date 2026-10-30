shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

// Steam off the refinery's cooling towers (RefineryFx.plume_mesh()): every fan stack of a piece in
// ONE mesh of camera-facing puffs placed here from TIME. All four corners of a puff sit at its
// stack's top (VERTEX); UV is the corner, UV2.x the puff's slot along its loop, UV2.y a random
// number. A puff leaves the stack as dense white vapour, swells and drifts down the wind and
// evaporates as it mixes - so a plume is thick at the stack and gone a few dozen metres up, never
// a smoke column. Lit by hand (it reads the same on both renderers): the sun from its side, the sky
// as its fill, and after dark the plant's sodium lights from below. Colours linear (color_space).

#include "res://shaders/color_space.gdshaderinc"

global uniform vec3 sun_direction;
global uniform float night_factor;
global uniform float lamp_factor;
global uniform vec3 sky_tint;

uniform sampler2D puff_tex : source_color, filter_linear_mipmap;
/// How high the steam rises before it is gone (metres) and its puffs' rise speed (m/s at the stack).
uniform float height = 55.0;
uniform float rise_speed = 4.0;
/// Puff radius at the stack and at the top.
uniform float radius_base = 3.0;
uniform float radius_top = 16.0;
/// Where the wind carries the top (metres, xz).
uniform vec2 lean = vec2(30.0, 10.0);
uniform float density = 0.75;
/// The plant's light on the plume's underside after dark.
uniform float glow = 0.22;

varying float v_alpha;
varying float v_h01;
varying float v_rot;

void vertex() {
	float slot = UV2.x;
	float rnd = UV2.y;
	float age = fract(TIME * rise_speed / max(height, 1.0) * 0.8 + slot);
	float y = height * (1.0 - pow(1.0 - age, 1.5));
	float h01 = y / max(height, 1.0);
	float r = mix(radius_base, radius_top, sqrt(h01));
	vec3 centre = VERTEX + vec3(lean.x, 0.0, lean.y) * pow(h01, 1.4);
	centre.y += y;
	float w = TIME * 0.3 + rnd * 6.2832 + y * 0.05;
	centre.xz += vec2(sin(w), cos(w * 0.87)) * r * 0.3;
	float size = r * (1.3 + 0.5 * rnd);
	vec3 cv = (MODELVIEW_MATRIX * vec4(centre, 1.0)).xyz;
	vec2 corner = (UV - vec2(0.5)) * size * 2.0;
	VERTEX = cv + vec3(corner.x, -corner.y, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	float fade = smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.25, 1.0, age));
	v_alpha = fade * density;
	v_h01 = h01;
	v_rot = rnd * 6.2832 + TIME * (rnd - 0.5) * 0.1;
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
	float lit = clamp(dot(n, to_sun) * 0.55 + 0.45, 0.0, 1.0);
	float shade = cs_in(tex.rgb).r * 1.5;
	vec3 sky = max(cs_srgb_to_linear(sky_tint), vec3(0.004));
	// Steam is white: it takes the sky and the sun almost as they are.
	vec3 col = vec3(0.82, 0.84, 0.86) * shade * (sky * 0.75 + vec3(1.0, 0.97, 0.92) * 1.4 * lit * day);
	// After dark: the plant's lights from below, strongest at the foot of the plume.
	col += vec3(1.0, 0.7, 0.45) * glow * lamp_factor * shade * (1.0 - v_h01 * 0.7) * (0.65 - 0.35 * n.y);
	ALBEDO = cs_out(col);
	ALPHA = clamp(a, 0.0, 1.0);
}
