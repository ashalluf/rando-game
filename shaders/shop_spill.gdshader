shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The light an open shop throws on the pavement after dark (Building.shop_pools, one additive batch
// a chunk: CityChunk._add_shop_spill()). It was light_pool.gdshader's soft round dot; with the
// glass at arm's length on (InteriorsGlass, the `interiors_glass` global) it is the WINDOW the
// light comes through, laid on the paving: dark for the half metre the stallriser shades, then a
// bright band that fades out across the pavement, the shop's width fanning out from the room, and
// a soft shadow of every mullion running out from the glass. The quad is laid in the wall's frame
// (x along the front, y out from the wall; Building: centred on the foot of the glass, 2 x reach
// deep, so half of it is inside the building). INSTANCE_CUSTOM: r the bay pitch (metres), g the
// shop's bays, b the reach (metres), a 1. Off (or a pool without the custom), the old dot exactly.

global uniform float lamp_factor;
global uniform float lamp_ease;
global uniform float interiors_glass;
uniform vec3 tint : source_color = vec3(1.0);
uniform float strength = 1.0;
uniform float falloff = 1.7;
// The window pattern's brightness against the old dot, and where its light comes from: metres
// behind the glass and up from the floor (the room's ceiling lights).
uniform float window_gain = 1.6;
uniform float source_back = 2.6;
uniform float source_up = 2.9;
// The stallriser's top (metres): the glass starts there.
uniform float riser = 0.48;

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
}

vec3 sp_to_linear(vec3 c) {
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	float r = clamp(1.0 - length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	float a = pow(r, falloff);
	bool window = interiors_glass > 0.5 && v_custom.a > 0.5 && v_custom.r > 0.05;
	if (window) {
		float pitch = v_custom.r;
		float bays = max(v_custom.g, 1.0);
		float reach = max(v_custom.b, 1.0);
		float W = pitch * bays;
		// Metres out from the wall and along it from the shop's middle.
		float t = (0.5 - UV.y) * 2.0 * reach;
		float s = (UV.x - 0.5) * W * 1.2;
		// Back to the glass along the line to the light: where along the front and how high up the
		// ray to this point crossed the glass.
		float k = source_back / (t + source_back);
		float sg = s * k;
		float yg = source_up * t / (t + source_back);
		// How soft the shadows' edges are: the light is the whole lit room, so they widen outward.
		float pen = 0.05 + 0.10 * t;
		float through = smoothstep(riser - pen * 0.6, riser + pen * 0.6, yg);
		// The shop's width (the piers either side shade it).
		through *= 1.0 - smoothstep(W * 0.5 - pen * 1.5, W * 0.5 + pen * 1.5, abs(sg));
		// The mullions: a frame member at every bay line.
		float m = abs(fract((sg + W * 0.5) / pitch + 0.5) - 0.5) * pitch;
		float bar = 1.0 - smoothstep(0.035, 0.035 + pen * 0.9, m);
		through *= 1.0 - 0.55 * bar;
		// Brightest near the glass, falling off with the distance from the room's light.
		vec2 d = vec2(t + source_back, source_up);
		float e = source_up / pow(dot(d, d), 1.5);
		vec2 d0 = vec2(0.6 + source_back, source_up);
		e /= source_up / pow(dot(d0, d0), 1.5);
		float edge = 1.0 - smoothstep(reach * 0.7, reach, t);
		a = through * e * edge * window_gain * step(0.0, t);
	}
	a *= lamp_factor * mix(1.0, lamp_factor, lamp_ease) * strength;
	ALBEDO = tint * COLOR.rgb;
	ALPHA = a * COLOR.a;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	if (window) {
		// Added in display numbers on Forward+, as Compatibility adds it (light_pool's display_add:
		// in linear HDR a broad pool over dark paving is a flat white sheet).
		vec3 tc = mix(tint * 12.92, 1.055 * pow(max(tint, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), tint));
		ALBEDO = sp_to_linear(tc * COLOR.rgb * clamp(ALPHA, 0.0, 1.0));
		ALPHA = 1.0;
	}
#endif
}
