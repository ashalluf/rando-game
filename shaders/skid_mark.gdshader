shader_type spatial;
// Skid marks and tyre tracks (DrivingFX): one MultiMesh of flat quads laid along the path of a
// sliding tyre, each instance one short segment. The mark MULTIPLIES what is under it (blend_mul),
// so rubber darkens the lit road whatever the light - noon, a street lamp's pool, a headlight -
// and costs no lighting at all. Instance COLOR is the tint (rubber black, a darker sand, damp
// dirt, linear) and its alpha the strength; INSTANCE_CUSTOM.x is the minute it was laid, mod 30, .y
// 1 while it is alive (0 once swept), .z 1 for a lone patch, .w 0.5 for a print in dirt and 1 in sand;
// (half floats on Compatibility: 0.015 min resolution is plenty), and the mark fades out over
// `life_min`. A wet road shows the rubber far less: the water film lies over it.
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/color_space.gdshaderinc"

global uniform float road_wetness;
// The current minute, mod 30 (DrivingFX sets it each frame).
uniform float now_min = 0.0;
// How long a mark takes to fade out completely, in minutes.
uniform float life_min = 4.0;
// Marks fade out between these distances from the camera (m): a dark line on a far road at a
// grazing angle is a hairline that crawls.
uniform float fade_start = 80.0;
uniform float fade_end = 140.0;
// How far a print in sand is pulled toward the camera (m), over the beach's stepped collision.
uniform float sand_pull = 0.35;
// How much of the mark a soaking road still shows.
uniform float wet_keep = 0.35;

varying vec4 v_col;
varying float v_fade;
// 1 for a lone patch (a burnout on the spot): its ends fade, a chain's segments meet edge to edge.
varying float v_patch;
varying float v_soft;
varying vec3 v_world;

void vertex() {
	v_col = COLOR;
	v_patch = INSTANCE_CUSTOM.z;
	v_soft = step(0.25, INSTANCE_CUSTOM.w);
	// Sand (w 1): the beach's collision is a few stepped boxes up to 30 cm off the drawn sand, so
	// a print laid where the tyre touched can be under the visible surface. Pulled toward the
	// camera by `sand_pull` it draws on top; on the road and the hills (w <= 0.5) it stays put.
	float pull = step(0.75, INSTANCE_CUSTOM.w) * sand_pull;
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - wpos);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wpos + to_cam * pull, 1.0)).xyz;
	float age = mod(now_min - INSTANCE_CUSTOM.x + 30.0, 30.0);
	// Fresh rubber is darkest; it greys out quickly at first, then lingers.
	float t = clamp(age / max(life_min, 0.01), 0.0, 1.0);
	v_fade = (1.0 - t) * (1.0 - 0.35 * sqrt(t)) * step(0.0005, INSTANCE_CUSTOM.y);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	v_fade *= 1.0 - smoothstep(fade_start, fade_end, distance(v_world, cam));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// Across the tyre: soft shoulders and a faint tread of lines along the mark.
	float across = UV.x * 2.0 - 1.0;
	// A print in sand or dirt (INSTANCE_CUSTOM.w 1) is a shallow groove: soft right across.
	float edge = 1.0 - smoothstep(mix(0.7, 0.15, v_soft), 1.0, abs(across));
	float tread = 0.82 + 0.18 * sin(UV.x * 34.0);
	// Patchy along the road: rubber goes down in smears, not as a printed stripe.
	vec2 w = v_world.xz * 1.7;
	vec2 i = floor(w);
	vec2 f = fract(w);
	f = f * f * (3.0 - 2.0 * f);
	float n = mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
	float ends = mix(1.0, smoothstep(0.0, 0.35, UV.y) * (1.0 - smoothstep(0.65, 1.0, UV.y)), v_patch);
	float a = v_col.a * edge * ends * tread * (0.7 + 0.3 * n) * v_fade;
	a *= mix(1.0, wet_keep, clamp(road_wetness * 1.6, 0.0, 1.0));
	vec3 mul = mix(vec3(1.0), v_col.rgb, clamp(a, 0.0, 1.0));
	ALBEDO = cs_out(mul);
}
