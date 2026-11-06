shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The light a house's night lamps throw (HouseNights): pools on the walk and the drive, the
// scallop a porch lantern or a carriage lamp paints on the wall, the cone of a landscape uplight
// grazing the facade, the turquoise of a pool light on its coping, and the lamp's own halo seen
// from the street and the air. One unit quad (facing +Z) per instance, laid by the transform;
// the instance COLOR is the tint in DISPLAY numbers, its alpha the strength. All of it is zero by
// day (lamp_factor), so it costs a draw a kind and nothing else.
//
// Added as Compatibility does, in display numbers, on both renderers: Forward+ adds in linear
// HDR, where a broad 0.3 pool over dark ground is a flat white disc (light_pool.gdshader's
// display_add, fwd-review-e).

global uniform float lamp_factor;
// 0 a pool on the ground, 1 an uplight's cone up a wall, 2 a lantern's scallop on a wall,
// 3 a lamp's halo (a camera-facing sprite never drawn smaller than `halo_px` pixels).
uniform int shape = 0;
uniform float halo_px = 3.4;
// SuburbNight (refcam5 suburb_night): 1 draws a lantern's scallop as a point source's falloff on
// the wall with the cap's cut above the lamp; 0 the old soft disc.
uniform float suburb_night = 0.0;

varying vec2 quad_m;

varying float halo_scale;

vec3 hg_to_linear(vec3 c) {
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	if (shape == 3) {
		// The instance basis is a uniform scale: the halo's size in metres.
		float size = length(MODEL_MATRIX[0].xyz);
		vec4 c = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
		float depth = max(-c.z, 0.05);
		// One pixel at 1080 lines (VIEWPORT_SIZE is not reliable in this stage).
		float px = 2.0 * depth / (abs(PROJECTION_MATRIX[1][1]) * 1080.0);
		float s = max(size, halo_px * px);
		halo_scale = size / s;
		// Pulled toward the camera so the wall behind it does not cut it.
		vec3 p = c.xyz + vec3(VERTEX.xy * s, 0.0);
		p += normalize(-c.xyz) * min(0.35, depth * 0.5);
		POSITION = PROJECTION_MATRIX * vec4(p, 1.0);
	} else {
		halo_scale = 1.0;
		quad_m = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
		POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	}
}

void fragment() {
	vec2 q = UV - vec2(0.5);
	float a = 0.0;
	if (shape == 0) {
		float r = clamp(1.0 - length(q) * 2.0, 0.0, 1.0);
		a = pow(r, 2.0);
	} else if (shape == 1) {
		// Up from the foot (UV.y 1) to the top (0): narrow and hot at the lamp, fanning out and
		// fading up the wall.
		float up = 1.0 - UV.y;
		float half_w = 0.10 + 0.38 * up;
		float across = 1.0 - smoothstep(half_w * 0.35, half_w, abs(q.x));
		a = across * pow(1.0 - up, 1.4) * smoothstep(0.0, 0.06, up);
	} else if (shape == 2 && suburb_night > 0.5) {
		// A lantern at (0.5, 0.29) of the quad (the lens, HouseNights.dress()), off the wall: the wall's light falls off as
		// a point source's (d0 / (d0^2 + r^2)^1.5, d0 the lamp's effective size off the wall), the
		// cap shades everything over the lamp's top but a faint glow, and the light spreads wider
		// going down. In metres from the quad's own size, so a carriage lamp and a porch lantern
		// keep the same falloff.
		vec2 p = vec2(q.x, 0.29 - UV.y) * quad_m;
		float d0 = 0.42;
		float r2 = dot(p, p);
		float fall = pow(d0 * d0 / (d0 * d0 + r2), 1.5);
		float cap = mix(0.12, 1.0, smoothstep(0.16, -0.06, p.y - abs(p.x) * 0.35));
		float tail = exp(-abs(p.x) / (0.35 + max(-p.y, 0.0) * 0.45)) * smoothstep(-2.4, -0.2, p.y) * step(p.y, 0.0) * 0.4;
		float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x) * smoothstep(0.0, 0.06, UV.y) * smoothstep(1.0, 0.94, UV.y);
		a = (fall * 1.5 + tail) * cap * edge;
	} else if (shape == 2) {
		// A lantern at (0.5, 0.22): a bright scallop under it, a faint one over it.
		vec2 d = vec2(q.x, (UV.y - 0.22) * (UV.y > 0.22 ? 0.62 : 1.6));
		float r = clamp(1.0 - length(d) * 2.1, 0.0, 1.0);
		a = pow(r, 1.8);
	} else {
		float r = length(q) * 2.0;
		float core = 1.0 - smoothstep(0.0, 0.18 * halo_scale + 0.05, r);
		a = max(core, pow(clamp(1.0 - r, 0.0, 1.0), 3.0) * 0.45);
	}
	a *= lamp_factor * COLOR.a;
	ALBEDO = COLOR.rgb;
	ALPHA = a;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	ALBEDO = hg_to_linear(COLOR.rgb * clamp(a, 0.0, 1.0));
	ALPHA = 1.0;
#endif
}
