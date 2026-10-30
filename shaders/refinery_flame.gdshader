shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

// The refinery's flare flames (RefineryFx.flame_mesh()): every flare of a piece in ONE mesh of
// camera-facing quads, every quad placed here from TIME - nothing per flame runs on the CPU. All
// four corners of a quad sit at its flare's tip (VERTEX); UV is the corner, UV2.x the quad's slot
// (0..1 along the flame's loop; 2 for the glow sprite) and UV2.y a random number.
// A puff of burning gas leaves the tip, rises and swells while the wind bends it over, burning
// white-yellow at the root, orange, then deep red and sooty at the tips; the glow sprite is a soft
// orange halo round the root that pulses with it. Additive and HDR (the glow pass blooms it), lit
// by nothing; brighter after dark only because everything round it is darker.

uniform sampler2D puff_tex : source_color, filter_linear_mipmap;
/// The flame's length (metres) and its width at the root and at the tip.
uniform float flame_len = 13.0;
uniform float root_w = 2.6;
uniform float tip_w = 7.5;
/// Where the wind takes it (metres at the tip, xz).
uniform vec2 lean = vec2(5.0, 2.0);
/// How hard it burns (0 is out).
uniform float strength = 1.0;
/// Seconds for a puff to burn out.
uniform float life = 1.4;
/// The halo's radius (metres) and strength.
uniform float glow_r = 26.0;
uniform float glow_gain = 0.35;
/// A flame never shrinks under this angle of the view (radians; a flare reads across the basin).
uniform float min_angle = 0.004;

varying float v_t;
varying float v_rnd;
varying float v_glow;
varying float v_far;

void vertex() {
	vec3 tip = VERTEX;
	float rnd = UV2.y;
	v_glow = UV2.x >= 1.5 ? 1.0 : 0.0;
	float t = fract(TIME / life + UV2.x);
	v_t = t;
	v_rnd = rnd;
	vec3 centre;
	float size;
	vec3 tip_v = (MODELVIEW_MATRIX * vec4(tip, 1.0)).xyz;
	float depth = max(-tip_v.z, 0.5);
	if (v_glow > 0.5) {
		float pulse = 0.85 + 0.15 * sin(TIME * 7.0 + rnd * 6.0) * sin(TIME * 3.1);
		centre = tip + vec3(lean.x * 0.15, flame_len * 0.25, lean.y * 0.15);
		size = glow_r * pulse * (0.6 + 0.4 * strength);
	} else {
		// Rise fast at first, then slow; the wind bends the top over.
		float rise = flame_len * (1.0 - pow(1.0 - t, 1.6));
		vec3 drift = vec3(lean.x, 0.0, lean.y) * pow(t, 1.5);
		float w = TIME * (2.0 + rnd * 1.5) + rnd * 6.28;
		drift.xz += vec2(sin(w), cos(w * 1.3)) * (0.4 + t * 1.6);
		centre = tip + vec3(0.0, rise, 0.0) + drift;
		size = mix(root_w, tip_w, sqrt(t)) * (0.7 + 0.6 * rnd) * strength;
	}
	// Never under min_angle of the view, so a flare a few kilometres off is still a bright point.
	float cd = max(-(MODELVIEW_MATRIX * vec4(centre, 1.0)).z, 0.5);
	v_far = smoothstep(500.0, 4000.0, cd);
	size = max(size, cd * min_angle * (v_glow > 0.5 ? 3.0 : 1.0));
	vec3 cv = (MODELVIEW_MATRIX * vec4(centre, 1.0)).xyz;
	vec2 corner = (UV - vec2(0.5)) * size;
	VERTEX = cv + vec3(corner.x, -corner.y, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	if (v_glow > 0.5) {
		float a = exp(-r * r * 3.2) * glow_gain * strength * (1.0 + 0.6 * v_far);
		ALBEDO = vec3(1.0, 0.45, 0.12) * a;
		ALPHA = 1.0;
	} else {
		float rot = v_rnd * 6.2832 + TIME * (v_rnd - 0.5) * 2.0;
		vec2 uv = vec2(c.x * cos(rot) - c.y * sin(rot), c.x * sin(rot) + c.y * cos(rot)) * 0.5 + 0.5;
		float d = texture(puff_tex, uv).a * (1.0 - smoothstep(0.6, 1.0, r));
		// Temperature: hot at the root and in the dense core, cooling out and up.
		float heat = clamp((1.0 - v_t * 1.15) * (0.55 + 0.6 * d), 0.0, 1.0);
		vec3 col = mix(vec3(0.6, 0.06, 0.01), vec3(2.6, 0.95, 0.22), smoothstep(0.1, 0.6, heat));
		col = mix(col, vec3(5.5, 4.2, 2.2), smoothstep(0.7, 0.95, heat));
		float fade = smoothstep(0.0, 0.06, v_t) * (1.0 - smoothstep(0.55, 1.0, v_t));
		// Far off, the flame is a point: hotter-looking and steadier, no billows to resolve.
		float a = mix(d, 1.0 - smoothstep(0.2, 1.0, r), v_far) * fade * 0.55 * strength;
		ALBEDO = col * a;
		ALPHA = 1.0;
	}
}
