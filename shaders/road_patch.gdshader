shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Everything StreetDetail lays flat on the carriageway rides the one "patch" batch: resurfacing
// patches, oil where cars park, the polished wheel tracks, braking polish at the stop lines and
// the utility locate paint by the kerb. Each is a unit box scaled per instance, and the
// instance colour says what it is: a grey is a SHADE of the road (1.0 the road itself, below
// darker fresh asphalt or oil, above bleached), anything saturated is spray paint.
//
// It used to be a flat untextured grey box with hard edges, and on a textured, mottled street
// every patch read as a square hole cut in the road. Now it is the same asphalt texture
// scaled by the shade, with a ragged, feathered edge blended over the road underneath.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
// Metres per texture tile; the roads use 7 and 9.
uniform float tex_scale = 7.0;
// The roads' average tint (CityChunk.ROAD_TINTS), so a shade of 1.0 lands on the road's colour.
uniform vec3 road_tint = vec3(0.81, 0.80, 0.82);
// How far in from the rim the edge fades, and how ragged it is (fractions of the half-size).
uniform float feather = 0.22;
uniform float ragged = 0.18;

global uniform float road_wetness;

varying vec3 world_pos;
varying vec2 local_pos;
// Only with it on does the street dry unevenly (road.gdshader); off, everything dries evenly.
global uniform float ground_detail;

#include "res://shaders/wet_drying.gdshaderinc"

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The unit box's own -0.5..0.5 footprint, whatever the instance's scale.
	local_pos = VERTEX.xz * 2.0;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float hi = max(c.r, max(c.g, c.b));
	float lo = min(c.r, min(c.g, c.b));
	float paint = step(0.25, (hi - lo) / max(hi, 0.001));

	// A rounded rectangle (superellipse) with its rim pushed in and out by noise in world
	// space, so no two patches share an outline and none is a ruler-straight box.
	vec2 q = abs(local_pos);
	float e = pow(pow(q.x, 6.0) + pow(q.y, 6.0), 1.0 / 6.0);
	float n = value_noise(world_pos.xz * 1.7) * 0.65 + value_noise(world_pos.xz * 5.3) * 0.35;
	e += (n - 0.5) * ragged * 2.0;
	// Oil and drips (the dark shades) soak in: a wide soft rim and a blotchy, see-through body.
	// Opaque, a stain was a black puck on the road.
	float dark = (1.0 - paint) * smoothstep(0.6, 0.2, c.r);
	float soft = mix(mix(feather, 0.65, dark), 0.06, paint);
	float a = 1.0 - smoothstep(1.0 - soft, 1.0, e);
	float blotch = smoothstep(0.2, 0.8, value_noise(world_pos.xz * 2.3 + 11.0) * 0.6 + value_noise(world_pos.xz * 7.1) * 0.4);
	a *= mix(1.0, 0.2 + 0.55 * blotch, dark);
	if (a < 0.01) {
		discard;
	}

	vec2 uv = world_pos.xz / tex_scale;
	vec3 tex = texture(albedo_tex, uv).rgb;
	vec3 base = paint > 0.5 ? c * (0.8 + 0.4 * value_noise(world_pos.xz * 9.0)) : tex * road_tint * c.r;
	// Oil and fresh tar are glossier than the grey road round them.
	float shade = paint > 0.5 ? 1.0 : c.r;
	float rough = mix(0.62, 0.9, smoothstep(0.2, 0.9, shade));

	float wet = clamp(road_wetness, 0.0, 1.0);
	// Drying after the rain, in step with the tarmac round it (wet_drying.gdshaderinc). Most of
	// what rides this batch lies where the wheels run, so it holds a little less water.
	vec2 fd = vec2(wet);
	if (wet > 0.01 && ground_detail > 0.5 && road_drying > 0.0) {
		fd = wet_film_damp(wet, wet_hold_noise(world_pos.xz) - 0.1);
	}
	base *= mix(1.0, 0.62, fd.y);
	ALBEDO = base;
	ALPHA = a;
	ROUGHNESS = clamp(mix(rough, 0.07, fd.x), 0.02, 1.0);
	SPECULAR = mix(0.5, 0.85, fd.x);
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = 0.8 * (1.0 - 0.6 * fd.x);
}
