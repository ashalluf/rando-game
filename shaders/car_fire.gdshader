shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// A burning car's flames (CarDamage): each particle is one tongue of flame drawn procedurally on
// an upright quad - it turns to face the camera about the vertical only, so a flame never lies
// down when seen from above - with its shape licking upward through two octaves of scrolling
// noise. A dozen overlapping make one fire. Puffs (the blast's fireball material) read as
// popcorn over a car: a fire is flames and smoke, not billows. The yellow-white root is HDR so
// it blooms; the thin tips cool through orange and red to soot. Reads no screen or depth, so the
// web draws it the same.

// Brightness of the whole flame.
uniform float heat = 1.0;

varying float seed;


float fh(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}


float fn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fh(i), fh(i + vec2(1.0, 0.0)), f.x), mix(fh(i + vec2(0.0, 1.0)), fh(i + vec2(1.0, 1.0)), f.x), f.y);
}


float fbm(vec2 p) {
	return fn(p) * 0.6 + fn(p * 2.1 + 3.7) * 0.28 + fn(p * 4.3 - 1.9) * 0.12;
}


void vertex() {
	vec3 pos = MODEL_MATRIX[3].xyz;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - pos;
	to_cam.y = 0.0;
	to_cam = length(to_cam) > 1e-4 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = cross(up, to_cam);
	float s = length(MODEL_MATRIX[0].xyz);
	mat4 world = mat4(vec4(right * s, 0.0), vec4(up * s, 0.0), vec4(to_cam * s, 0.0), vec4(pos, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	seed = fract(INSTANCE_CUSTOM.x * 0.159 + 0.5);
}


void fragment() {
	// x across the flame (-1..1), y up it (0 root .. 1 tip).
	vec2 uv = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);
	float t = TIME * 2.1 + seed * 17.0;
	float n = fbm(vec2(uv.x * 1.8 + seed * 9.0, uv.y * 2.4 - t));
	float n2 = fbm(vec2(uv.x * 4.2 - seed * 5.0, uv.y * 4.4 - t * 1.6));
	// Licking sideways more the higher it gets.
	float x = uv.x + (n - 0.5) * 0.9 * uv.y + (n2 - 0.5) * 0.25 * (0.3 + uv.y);
	// The quad is wider than the flame, so a tongue licking sideways is never cut at its edge.
	float width = 0.36 * pow(max(1.0 - uv.y, 0.0), 0.55) * (0.65 + 0.7 * n);
	float body = 1.0 - smoothstep(width * 0.2, width, abs(x));
	// It breaks up into tongues toward the top.
	float tongues = smoothstep(0.2, 0.55, n2 + 0.55 - uv.y * 0.75);
	float tip = 1.0 - smoothstep(0.3, 0.9, uv.y + (n2 - 0.5) * 0.6 + (n - 0.5) * 0.35);
	float root = smoothstep(0.0, 0.15, uv.y);
	float dens = body * tip * root * tongues;
	// Hottest low in the middle of the flame; orange through most of it, red and soot at the tips.
	float h = clamp(dens * (1.1 - uv.y) - 0.12, 0.0, 1.0);
	vec3 c = mix(vec3(0.45, 0.05, 0.008), vec3(1.5, 0.36, 0.035), smoothstep(0.04, 0.3, h));
	// Held under ~2: AgX takes anything much brighter toward a pale pink-white.
	c = mix(c, vec3(1.75, 0.72, 0.1), smoothstep(0.45, 0.8, h));
	c = mix(c, vec3(2.0, 1.2, 0.38), smoothstep(0.9, 1.0, h));
	c = mix(vec3(0.03, 0.024, 0.02), c, smoothstep(0.02, 0.15, h));
	ALBEDO = c * heat * COLOR.rgb;
	ALPHA = smoothstep(0.0, 0.7, dens) * 0.92 * COLOR.a;
}
