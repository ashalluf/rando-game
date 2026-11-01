shader_type spatial;
// Heat haze behind a hot exhaust (DrivingFX, Forward+ desktop only): a camera-facing quad that
// bends the picture behind it with a rising, wavering noise, strongest at the pipe and gone at
// its edges - WeaponFX's blast shimmer, small and steady. It reads the screen, which Godot copies
// before transparent things are drawn, so its material sits at RENDER_PRIORITY_MIN (CLAUDE.md,
// Effects: drawn in its sorted place it would paint a smoke-less street over the car's smoke).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// How far the haze bends the picture (fraction of the screen at full heat).
uniform float strength = 0.004;
// 0..1: how hot the pipe is (DrivingFX sets it from the throttle).
uniform float heat = 0.0;

varying vec3 v_world;

void vertex() {
	// Billboard about the quad's own origin.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_world = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	// A plume: widest low down near the pipe (UV.y 1), thinning as it rises.
	float mask = (1.0 - smoothstep(0.35, 1.0, abs(c.x) * (0.7 + 0.5 * (1.0 - UV.y)))) * smoothstep(0.0, 0.5, UV.y) * (1.0 - smoothstep(0.85, 1.0, UV.y));
	float t = TIME * 6.0;
	vec2 p = UV * vec2(5.0, 9.0) + v_world.xz;
	vec2 wob = vec2(sin(p.y * 2.3 + t * 1.7 + sin(p.x * 3.1)), cos(p.x * 2.9 - t * 2.3 + p.y * 0.7));
	vec2 off = wob * strength * mask * heat;
	ALBEDO = texture(screen_tex, clamp(SCREEN_UV + off, vec2(0.002), vec2(0.998))).rgb;
	ALPHA = mask * clamp(heat * 3.0, 0.0, 1.0);
}
