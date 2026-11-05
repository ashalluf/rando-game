shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, shadows_disabled, unshaded, fog_disabled;

// The hot core of a fuel blast and of each secondary pop (Blast4, fleet wave 8 "explosions-4",
// round 19, after the lead's review of a chain at golden hour): the volume rolls into brown soot
// within ~0.2 s, so a chain's later cars and pops read as muted brown clouds with a few orange
// dots. A chain blast must FLASH: a lumpy black-body mass, white-yellow at its heart, through
// orange to red, blooming, for its first ~0.3-0.5 s, inside the volume. A camera-facing card,
// additive (HDR numbers raw on both renderers, as the fire shaders hand them), fog-free, zero at
// its edge (CLAUDE.md, additive shaders and fog). `age` 0..1 over its life from the script.

uniform sampler3D noise3d : filter_linear, repeat_enable;
uniform float age = 0.0;
uniform float seed = 0.0;
uniform float gain = 1.0;

vec3 bb(float k) {
	// blast_volume.gdshader's blackbody4: green held near half of red once bright (AgX's rule).
	vec3 c = vec3(0.14, 0.02, 0.0) * smoothstep(0.0, 0.3, k) * smoothstep(0.0, 0.3, k);
	c = mix(c, vec3(0.75, 0.26, 0.03), smoothstep(0.25, 0.55, k));
	c = mix(c, vec3(2.3, 1.2, 0.22), smoothstep(0.5, 0.8, k));
	c = mix(c, vec3(7.5, 6.0, 3.9), smoothstep(0.84, 1.0, k));
	return c;
}

void vertex() {
	// Faces the camera, keeping its node's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	// Lumps: the billows of a burning ball, rolling out as it grows.
	float n1 = texture(noise3d, vec3(q * 0.42 + seed, age * 0.6 + seed * 0.3)).r;
	float n2 = texture(noise3d, vec3(q * 1.05 + seed * 1.7, age * 1.1 + 0.4)).r;
	float lump = n1 * 0.65 + n2 * 0.35;
	// Lumpy enough never to be a disc (on Forward+ a round edge bloomed into a white sun).
	float edge = 0.38 + 0.62 * smoothstep(0.25, 0.8, lump);
	float body = 1.0 - smoothstep(edge * 0.45, edge, r);
	// Heat: the heart hottest, falling with the radius and the age; the lumps hotter than the folds.
	float k = clamp((1.0 - r * 0.9) * (1.15 - age * 1.05) + (lump - 0.5) * 0.6, 0.0, 1.0);
	vec3 c = bb(k) * body * gain;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	// Forward+ adds these numbers in linear HDR over a volume that is already white-hot at first
	// (the Mac): a fifth of them, and never the white plateau, or the first frames bloom into a
	// flat white disc (fwd-review-e's rule for additive quads). Compatibility tonemaps them raw.
	c = bb(min(k, 0.86)) * body * gain * 0.18;
#endif
	// It flares up in a few frames and goes in the last third of its life.
	c *= smoothstep(0.0, 0.06, age) * (1.0 - smoothstep(0.6, 1.0, age));
	c *= 1.0 - smoothstep(0.85, 0.99, r);
	if (max(c.r, max(c.g, c.b)) < 0.003) {
		discard;
	}
	ALBEDO = c;
}
