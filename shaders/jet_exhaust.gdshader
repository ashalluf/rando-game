shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Heat behind a running jet engine (AmbientJet._build_shimmer()): an open cone laid aft of the
// nozzle, narrow end at the nozzle, that bends whatever is behind it with a noise streaming away
// from the engine, strongest just behind the nozzle and fading to nothing by the far end and at
// the cone's silhouette (so it has no visible edge, only a column of wobbling air). `strength`
// is the engine's level (idle 0.3, take-off 1). It reads the screen texture, which Godot copies
// BEFORE transparent things are drawn, so the material is drawn first among them
// (render_priority MIN, set in code) - drawn in its sorted place it would paint the picture as it
// was without whatever transparent thing is in front of it (CLAUDE.md, effects). Desktop only:
// on the web a screen read is a full back-buffer copy per draw.
// Shader files use // comments.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 0.3;
// How far the air bends the picture, in screen widths at full strength, close to.
uniform float bend = 0.0055;

varying float v_along;
varying vec3 v_world;
varying float v_depth;

void vertex() {
	// The mesh is a unit cylinder along Y: its top (y +0.5) sits at the nozzle.
	v_along = clamp(0.5 - VERTEX.y, 0.0, 1.0);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = smoothstep(0.05, 0.6, facing);
	float along = smoothstep(0.0, 0.06, v_along) * pow(1.0 - v_along, 1.6);
	// A shimmer smaller than a pixel only aliases: fade it with distance.
	float far = 1.0 - smoothstep(140.0, 250.0, v_depth);
	float mask = rim * along * far * strength;
	if (mask < 0.002) {
		discard;
	}
	// Hot air streams away from the engine: the noise runs along the cone's length.
	float t = TIME * (3.0 + 5.0 * strength);
	vec3 p = v_world * 1.9;
	float flow = v_along * 22.0 - t;
	vec2 wob = vec2(
		sin(flow + p.y * 4.1 + p.x * 2.3) + 0.5 * sin(flow * 2.3 + p.z * 5.7),
		cos(flow * 1.3 - p.x * 3.7 + p.z * 1.9) + 0.5 * sin(flow * 2.9 + p.y * 6.1));
	vec2 off = wob * bend * mask * (1.0 + 0.6 * (1.0 - v_along)) / max(v_depth * 0.03, 1.0);
	vec3 col = textureLod(screen_tex, clamp(SCREEN_UV + off, vec2(0.002), vec2(0.998)), 0.0).rgb;
	ALBEDO = col;
	ALPHA = clamp(mask * 2.5, 0.0, 1.0);
}
