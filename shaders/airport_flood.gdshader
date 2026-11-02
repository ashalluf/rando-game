shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The light an apron high mast's floods lay on the concrete (AirportNight, refcam3
// "airport_night"). One quad a mast, laid flat round its foot in the mast's frame (its local +y,
// after the flat turn, is where the floods face). The pool is the illuminance of a point source
// `height` metres up, (1 + d^2/h^2)^-1.5 - broad and flat, the stands and the lane in front of
// them lit, darker between masts - cut softly at the quad's rim, and less behind the mast. The old
// pool was a 80 m soft dot 14 m in front of the mast, under the jets and the concourse: from the
// apron the masts lit nothing.
// Added in DISPLAY numbers on both renderers (light_pool.gdshader's display_add, fwd-review-e): a
// broad pool added in linear HDR on Forward+ is a flat white carpet.

global uniform float lamp_factor;
uniform vec3 tint : source_color = vec3(1.0, 0.88, 0.70);
uniform float strength = 0.34;
// The mast's height over the quad's radius (the quad is 2 x radius across).
uniform float h_over_r = 0.25;
// Share behind the mast.
uniform float back = 0.45;

varying vec2 v_q;

void vertex() {
	// The quad runs -0.5..0.5 in x and y: metres over the radius, -1..1.
	v_q = VERTEX.xy * 2.0;
}

vec3 af_lin(vec3 c) {
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	float d = length(v_q);
	float d2 = d * d / (h_over_r * h_over_r);
	float e = pow(1.0 + d2, -1.5);
	// v_q.y > 0 is in front of the mast.
	float fwd = v_q.y / max(d, 1e-3);
	float aim = mix(back, 1.0, smoothstep(-0.3, 0.4, fwd));
	float rim = 1.0 - smoothstep(0.62, 1.0, d);
	float a = e * aim * rim * strength * lamp_factor;
	ALBEDO = tint;
	ALPHA = clamp(a, 0.0, 1.0);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	// tint arrives decoded here (source_color): back to display numbers, the add, then decoded.
	vec3 t = mix(tint * 12.92, 1.055 * pow(max(tint, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), tint));
	ALBEDO = af_lin(t * clamp(a, 0.0, 1.0));
	ALPHA = 1.0;
#endif
}
