shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// A tongue of flame (Blast4, fleet wave 5 "explosions-4", round 6): the car fires, the burning
// fuel pools, the flames up a wreck's sides and the burning debris were the fireball's round
// puffs, which read as orange cotton balls. This is a card that stands upright and turns about
// world up to face the camera (a flame is vertical whatever the view), whose silhouette is cut
// from noise that scrolls UP it - so the tongue licks and splits as it rises - with a hot root
// (yellow-white, green held near half of red so AgX keeps it orange, not salmon), orange flesh,
// red tips that thin and break into smoke. CPUParticles feed it: COLOR is the flame ramp (the
// life's brightness and fade), INSTANCE_CUSTOM.y the life fraction; each card its own noise by
// INSTANCE_ID. Unshaded HDR numbers taken raw on both renderers, as fire_puff.gdshader does.

uniform sampler3D noise3d : filter_linear, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
// How fast the noise climbs the tongue (tongue heights a second) and how far it bends it.
uniform float climb = 1.6;
uniform float bend = 0.75;
// Root heat (1 = the ramp's colour), the colours from hot to spent.
uniform float root_heat = 1.45;
uniform vec3 hot = vec3(1.6, 1.0, 0.32);
uniform vec3 mid = vec3(1.25, 0.56, 0.08);
uniform vec3 cool = vec3(0.6, 0.17, 0.025);
uniform vec3 smoke = vec3(0.045, 0.036, 0.028);
uniform float soft_distance = 0.4;
// Round 18 (look5): from 5 m a row of tongues read as crisp orange paper spikes of one height.
// Each tongue's height now flickers on its own clock, a fine third octave opens holes and wisps
// in its flesh, and the outer flame is thin and see-through round an opaque hot core. 0 is the
// round-6 tongue bit for bit.
uniform float look5 = 0.0;

varying flat float v_seed;
varying float v_life;

void vertex() {
	// Upright, turned about world up toward the camera.
	vec3 pos = MODEL_MATRIX[3].xyz;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - pos;
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam + vec3(1e-4, 0.0, 0.0)));
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 fwd = cross(side, up);
	mat4 world = mat4(vec4(side, 0.0), vec4(up, 0.0), vec4(fwd, 0.0), vec4(pos, 1.0));
	world = world * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_seed = fract(float(INSTANCE_ID) * 0.6180339 + 0.13);
	v_life = INSTANCE_CUSTOM.y;
}

void fragment() {
	float u = UV.x * 2.0 - 1.0;
	// 0 at the root, 1 at the tip; each card's own height (a row of equal tongues is a fence).
	float hs = 0.5 + 0.5 * fract(v_seed * 7.31);
	if (look5 > 0.0) {
		// Each tongue its own height, breathing: lunges up and drops back on its own clock.
		float fl = texture(noise3d, vec3(v_seed * 11.0, TIME * 0.9, 0.3)).r;
		hs = mix(hs, (0.5 + 0.6 * fract(v_seed * 7.31)) * (0.75 + 0.55 * fl), look5);
	}
	float h = (1.0 - UV.y) / hs;
	if (h >= 1.0) {
		discard;
	}
	float tt = TIME * climb;
	// Two octaves climbing the tongue: the big one sways and bends it, the fine one tears its edge.
	float n1 = texture(noise3d, vec3(u * 0.18 + v_seed * 7.0, h * 0.42 - tt * 0.42, v_seed * 3.1)).r;
	float n2 = texture(noise3d, vec3(u * 0.55 + v_seed * 5.0, h * 1.1 - tt * 1.05, v_seed * 1.7 + 0.5)).r;
	float ux = u + (n1 - 0.5) * bend * 2.0 * h * h + (n2 - 0.5) * 0.25 * h;
	// Width: full at the root, narrowing to a point; the fine noise breaks the tip into licks.
	// Full through its lower half, then drawn in: a flame is a lump of fire with a tip, not a spike.
	float w = (1.0 - pow(h, 1.7)) * (0.62 + 0.62 * n1) * (0.85 + 0.3 * sin(h * 6.0 + v_seed * 20.0 - tt * 2.0)) + 0.04;
	w *= smoothstep(-0.02, 0.1, h) * 0.3 + 0.7; // a rounded root
	float body = 1.0 - smoothstep(w * 0.45, w, abs(ux));
	// Torn into licks: the fine noise lifts pieces off as the tongue rises, a lump broken free.
	float tear = smoothstep(0.0, 0.2, n2 * 1.1 + 0.55 - h * 1.15 + 0.35 * (n1 - 0.5));
	float shape = body * tear;
	if (look5 > 0.0) {
		// A finer octave climbing faster: holes and wisps in the flesh, never in the root's core.
		float n3 = texture(noise3d, vec3(u * 1.3 + v_seed * 3.0, h * 2.6 - tt * 2.1, v_seed * 2.3 + 0.8)).r;
		float hole = smoothstep(0.38, 0.62, n3 + 0.55 - h * 0.7 + 0.35 * (1.0 - abs(ux) / max(w, 0.02)));
		shape *= mix(1.0, hole, look5);
	}
	if (shape < 0.003) {
		discard;
	}
	// Heat: hottest in the root's middle, cooling up and out; the card's life cools it too.
	float life = v_life;
	float core = 1.0 - clamp(abs(ux) / max(w, 0.02), 0.0, 1.0);
	float heat = clamp((1.0 - h) * 1.15 * (0.55 + 0.45 * core) * (1.0 - 0.45 * life) + (n2 - 0.5) * 0.25, 0.0, 1.0);
	vec3 col = mix(cool, mid, smoothstep(0.15, 0.5, heat));
	col = mix(col, hot * root_heat, smoothstep(0.55, 0.92, heat));
	// The tips go to smoke.
	float spent = smoothstep(0.55, 0.95, h) * (1.0 - smoothstep(0.2, 0.45, heat));
	col = mix(col, smoke, spent);
	// The ramp's life: its brightness against its brightest key (1.3), and its fade.
	float lum = clamp(dot(COLOR.rgb, vec3(0.30, 0.55, 0.15)) / 0.85, 0.15, 1.2);
	col *= mix(1.0, lum, 1.0 - spent);
	ALBEDO = col;
	ALPHA = clamp(COLOR.a * 1.15, 0.0, 1.0) * shape * mix(1.0, 0.18, spent) * (1.0 - smoothstep(0.7, 1.0, h));
	// The outer flame is thin gas: see-through, the hot core opaque.
	ALPHA *= mix(1.0, 0.62 + 0.38 * smoothstep(0.0, 0.4, core), look5);

	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 behind = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, depth) * 2.0 - 1.0, 1.0);
#else
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
#endif
	behind.xyz /= behind.w;
	ALPHA *= clamp(1.0 - smoothstep(behind.z + soft_distance, behind.z, VERTEX.z), 0.0, 1.0);
}
