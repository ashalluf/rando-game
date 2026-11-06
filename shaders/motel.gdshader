shader_type spatial;
// The Googie motor court motel (Motels, scripts/world/motels.gd / motel_kit.gd): ONE material for
// the whole building. What a face is rides in COLOR.a (kind / 16, MotelKit.K_*), its paint in
// COLOR.rgb (sRGB, raw on both renderers: decoded here), UV in metres on the face (along the wing,
// up the wall - or out from the facade on a floor), UV2.x a light mode (1 + storey: a facade wall
// the sconces of that storey wash; 10 + storey: a walk / soffit those sconces light, UV.y then the
// distance out from the facade; 20 + storey: a soffit over it), UV2.y the room's key for the windows' night rolls.
// Linear on both renderers (color_space.gdshaderinc).
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float city_hour;
global uniform float road_wetness;

// The room grid MotelKit lays its bays on (change both: tests/rc5_googie_motel_checks.gd reads them).
const float ROOM_W = 4.0;
const float STOREY = 2.95;
const float SCONCE_U = 1.75;
const float SCONCE_H = 2.1;
uniform float sconce_gain = 0.14;
uniform float floor_gain = 5.0;
uniform vec3 sconce_color = vec3(1.0, 0.62, 0.30);
uniform float window_gain = 0.45;
uniform float neon_gain = 5.0;

varying flat float v_kind;
varying vec3 v_paint;

float h11(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

float h21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_kind = floor(COLOR.a * 16.0 + 0.5);
	v_paint = cs_srgb_to_linear(COLOR.rgb);
}

// The light the sconces of storey `f` throw on a facade point (u along, h up) or on a floor
// point `d` metres out from the facade at height `h` over that storey's floor.
float sconce_light(float u, float h, float d) {
	float bu = floor(u / ROOM_W);
	float best = 0.0;
	for (int k = -1; k <= 1; k++) {
		float su = (bu + float(k)) * ROOM_W + SCONCE_U;
		float du = u - su;
		float dh = h - SCONCE_H;
		float r2 = du * du + dh * dh + d * d + 0.08;
		// A shaded fitting: most of it goes down and out.
		float down = clamp(0.35 - dh * 0.55, 0.12, 1.0);
		best += down / r2;
	}
	return best;
}

void fragment() {
	float kind = v_kind;
	vec3 base = v_paint;
	float rough = 0.8;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float mode = UV2.x;
	float night = clamp(lamp_factor, 0.0, 1.0);
	vec2 uv = UV;
	if (kind < 0.5) {
		// Stucco: a fine trowel grain and a few repaint patches, dirt splashed up the foot.
		float g = vnoise(uv * vec2(9.0, 9.0)) * 0.5 + vnoise(uv * 31.0) * 0.5;
		float patch = smoothstep(0.55, 0.62, vnoise(uv * 0.45 + 7.3));
		base *= 0.93 + g * 0.1;
		base *= mix(1.0, 1.04, patch);
		float foot = fract(uv.y / STOREY);
		base *= mix(0.78, 1.0, smoothstep(0.0, 0.5, uv.y)) * mix(0.96, 1.0, smoothstep(0.0, 0.25, foot));
		rough = 0.92;
	} else if (kind < 1.5) {
		// Painted trim: semi-gloss with chips at the edges.
		base *= 0.95 + vnoise(uv * 14.0) * 0.08;
		rough = 0.42;
	} else if (kind < 2.5) {
		// Window: glass over a curtain; after dark the room behind is lit or not by its own roll.
		// The key is rounded: interpolated it wanders by a hair across the pane, and the hash turns
		// that into per-pixel static.
		float room = floor(UV2.y + 0.5);
		float r = h11(room);
		// Fewer rooms lit after midnight.
		float late = smoothstep(0.0, 3.0, mod(city_hour + 24.0, 24.0)) * step(mod(city_hour + 24.0, 24.0), 6.0);
		float lit = step(r, mix(0.62, 0.25, late));
		// Curtain folds across the pane, a gap in the middle on some.
		float folds = 0.75 + 0.25 * sin(uv.x * 22.0 + h11(room + 3.0) * 6.0);
		float gap = (1.0 - smoothstep(0.03, 0.09, abs(fract(uv.x / 1.6) - 0.5 - (h11(room + 5.0) - 0.5) * 0.3))) * step(0.5, h11(room + 7.0));
		vec3 cur = mix(vec3(0.42, 0.31, 0.2), vec3(0.55, 0.47, 0.35), h11(room + 1.0));
		base = mix(vec3(0.02, 0.025, 0.03), cur * folds * 0.45, 0.6);
		rough = 0.08;
		metal = 0.0;
		// A TV's blue flicker in a few rooms.
		float tv = step(0.72, h11(room + 11.0)) * lit;
		float flick = 0.55 + 0.45 * sin(TIME * (3.0 + h11(room + 13.0) * 4.0) + room) * sin(TIME * 1.7 + room * 3.1);
		vec3 warm = mix(vec3(1.0, 0.62, 0.32), vec3(1.0, 0.74, 0.48), h11(room + 17.0));
		vec3 room_light = warm * cur * 3.2 * folds * (1.0 - gap) + vec3(1.0, 0.8, 0.55) * gap * 1.6;
		room_light = mix(room_light, vec3(0.35, 0.5, 1.0) * (0.6 + flick) * 1.4, tv * 0.6);
		emit = room_light * lit * night * window_gain * mix(0.6, 1.0, h11(room + 19.0));
	} else if (kind < 3.5) {
		// Concrete: walks, slabs, stair treads; joints every 1.5 m.
		float j = 1.0 - smoothstep(0.0, 0.025, abs(fract(uv.x / 1.5 + 0.5) - 0.5) * 1.5);
		base *= (0.9 + vnoise(uv * 6.0) * 0.12) * (1.0 - j * 0.25);
		float stain = smoothstep(0.6, 0.75, vnoise(uv * 0.8 + 3.0));
		base *= 1.0 - stain * 0.15;
		rough = mix(0.86, 0.3, road_wetness);
	} else if (kind < 4.5) {
		// Painted steel: rails, posts, stair stringers.
		rough = 0.5;
		metal = 0.25;
	} else if (kind < 5.5) {
		// A sconce's glass: lit after dark.
		base = vec3(0.8, 0.75, 0.62);
		rough = 0.3;
		emit = sconce_color * 9.0 * night;
	} else if (kind < 6.5) {
		// Door: painted steel, a panel line and the kick plate.
		float panel = 1.0 - smoothstep(0.0, 0.015, abs(abs(uv.x - 0.45) - 0.3)) * step(0.35, uv.y) * step(uv.y, 1.9);
		base *= mix(0.8, 1.0, panel);
		base = mix(base, vec3(0.5, 0.5, 0.48), step(uv.y, 0.22) * 0.7);
		rough = 0.38;
	} else if (kind < 7.5) {
		// Neon tube: the office sign and the roof's accent line.
		base = base * 0.4;
		rough = 0.3;
		emit = v_paint * neon_gain * (0.15 + 0.85 * night);
	} else if (kind < 8.5) {
		// The office's glass front: the lobby behind it - the counter's front low down, the back
		// wall lit warm above it, a row of ceiling lights, the dark glass mirroring a little.
		base = vec3(0.03, 0.035, 0.04);
		rough = 0.06;
		float y = uv.y;
		vec3 lobby = vec3(0.85, 0.7, 0.52) * 0.22 * (0.8 + 0.2 * sin(uv.x * 1.7));
		lobby = mix(lobby, vec3(0.32, 0.17, 0.09) * 0.55, step(y, 1.15) * step(0.5, fract(uv.x / 6.0 + 0.25)));
		float ceil_l = smoothstep(0.12, 0.0, abs(y - 3.15)) * (0.5 + 0.5 * step(0.5, fract(uv.x / 1.4)));
		lobby += vec3(1.0, 0.88, 0.7) * ceil_l * 0.9;
		emit = lobby * mix(0.15, 1.0, night);
	} else if (kind < 9.5) {
		// Stone veneer: rubble courses.
		vec2 c = uv * vec2(3.2, 5.5);
		c.x += floor(c.y) * 0.5;
		vec2 f = fract(c);
		float m = smoothstep(0.0, 0.06, min(min(f.x, 1.0 - f.x) / 3.2 * 5.5, min(f.y, 1.0 - f.y)));
		base *= mix(0.5, 0.85 + h21(floor(c)) * 0.3, m);
		rough = 0.95;
	} else if (kind < 10.5) {
		// Roof membrane / gravel: only seen from above.
		base *= 0.85 + vnoise(uv * 3.0) * 0.2;
		rough = 0.95;
	} else if (kind > 11.5) {
		// A vending machine's lit front: rows of cans behind the glass, the selection panel.
		vec2 q = uv;
		float rows = step(0.25, fract(q.y * 6.0)) * step(q.x, 0.62);
		float cans = 0.6 + 0.4 * step(0.5, fract(q.x * 9.0));
		vec3 front = mix(vec3(0.9, 0.95, 1.0), base * 2.0, 0.35) * mix(0.35, 1.0, rows * cans);
		base = vec3(0.05);
		rough = 0.1;
		emit = front * mix(0.08, 0.9, night);
	} else {
		// AC sleeves: weathered beige plastic with a grille.
		float gr = step(0.5, fract(uv.x * 18.0));
		base *= mix(0.72, 1.0, gr);
		rough = 0.6;
	}
	// The sconces' wash on the facade and on the walks and soffits beside it.
	if (mode > 0.5 && night > 0.0) {
		float wash = 0.0;
		if (mode < 9.5) {
			float f = mode - 1.0;
			wash = sconce_light(uv.x, uv.y - f * STOREY, 0.25);
		} else if (mode < 19.5) {
			// A walk at storey f's floor: the fitting's light falls on it more than across the wall.
			wash = sconce_light(uv.x, 0.0, uv.y + 0.15) * floor_gain;
		} else {
			// A soffit over storey f (the next walk's underside, the roof's overhang).
			wash = sconce_light(uv.x, STOREY - 0.2, uv.y + 0.15) * 0.8;
		}
		emit += base * sconce_color * wash * sconce_gain * night;
	}
	ALBEDO = cs_out(base);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
