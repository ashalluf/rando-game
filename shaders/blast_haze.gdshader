shader_type spatial;
// The heat over a blast's fire (Blast3's BlastHaze): a quad stood upright over the seat of the
// blast, turned about its own vertical to the camera, that reads the screen and bends it with
// noise rising through it - a column of wavering air for as long as the fire burns, strongest
// just over the flames and gone a few metres up. It bends only what is BEHIND it: the scene's
// depth is read and a pixel whose surface stands in front of the quad is left alone (WeaponFX's
// old sphere bent the car in front of the fire as much as the street behind it). Drawn first
// among the transparents (render_priority MIN, WeaponFX._shimmer's rule: the screen texture is
// captured before them). Desktop only.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler3D noise3d : filter_linear, repeat_enable;
// Bend at the base, as a share of the screen (fades with the fire, set by Blast3).
uniform float strength = 0.012;
uniform float fade = 1.0;
// How fast the shimmer rises (noise tiles a second) and its scale across the column.
uniform float rise = 0.9;
uniform vec2 tiles = vec2(2.2, 3.5);

void vertex() {
	// Turn about the node's own up to face the camera (a cylinder billboard).
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	vec3 side = normalize(cross(up, to_cam));
	vec3 world = origin + side * VERTEX.x * w + up * (VERTEX.y + 0.5) * h;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	// UV.y 0 is the top of the quad.
	float height = 1.0 - UV.y;
	float mask = smoothstep(0.0, 0.6, across) * (1.0 - smoothstep(0.15, 1.0, height)) * smoothstep(0.0, 0.06, height);
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 behind = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, depth) * 2.0 - 1.0, 1.0);
#else
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
#endif
	behind.xyz /= behind.w;
	// Only what stands behind the column (soft over half a metre).
	mask *= smoothstep(0.0, 0.5, VERTEX.z - behind.z);
	vec3 p = vec3(UV.x * tiles.x, UV.y * tiles.y + TIME * rise, TIME * 0.17);
	vec2 off = vec2(texture(noise3d, p).r - 0.5, texture(noise3d, p + vec3(0.37, 0.11, 0.53)).r - 0.5);
	// Farther fires bend fewer pixels.
	off *= strength * mask * fade * 2.0 / max(1.0, -VERTEX.z * 0.04);
	ALBEDO = textureLod(screen_tex, clamp(SCREEN_UV + off, vec2(0.002), vec2(0.998)), 0.0).rgb;
	ALPHA = clamp(mask * fade * 4.0, 0.0, 1.0);
}
