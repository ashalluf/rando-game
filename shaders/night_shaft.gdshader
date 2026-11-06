shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// The cone of light under a street lamp in mist and rain (NightAtmos): one open cone per lamp in
// the chunk's batch, from the head (the instance origin) down to the pavement (a unit cone: top
// at y 0, the floor at y -1, scaled per instance). Drawn, not marched, so the Compatibility
// renderer (the web) has it too; NightAtmos sets night_atmos.y to 0 where Forward+'s volumetric
// fog already lights the air round the lamps, so the two never stack. Brightest where the eye
// looks through the cone's middle (the longest path through the lit air), soft at its rim,
// fading toward the ground, stirred by slow drifting mist and, in rain, lit streaks falling
// through it. Faded out by `reach` metres; collapsed by day.

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/night_halo.gdshaderinc"

global uniform float lamp_factor;
global uniform float rain_intensity;
global uniform vec3 origin_shift;

uniform float gain = 0.028;
uniform float reach = 70.0;
uniform float rain_streaks = 0.9;
// RainStreetNight (the street_night refcam review; set by RainStreetNight.dress_wet()): 1 draws the
// rain in the lamp's light as what the eye really picks out of a rainy night - longer, brighter
// streaks of lit drops, still there where Forward+'s volumetric fog has taken the cone's glow over
// (night_atmos.y 0) - and fades the cone's top in over a longer run so its rim is no hard sail edge.
// 0 the old cone exactly.
uniform float look2 = 0.0;
uniform float rain2_gain = 5.0;

varying float v_face;
varying float v_h;
varying vec3 v_w;
varying float v_amp;
varying float v_ramp;
// look2: where the fragment lies across the cone as the eye sees it (metres off the axis, along the
// horizontal perpendicular to the view), and which face (+1 near, -1 far).
varying vec2 v_across;
varying vec3 v_col;

float sh_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float sh_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(sh_hash(i), sh_hash(i + vec2(1.0, 0.0)), f.x), mix(sh_hash(i + vec2(0.0, 1.0)), sh_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 top = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = length(cam - top);
	float haze = clamp(night_atmos.x, 0.0, 1.0);
	float amp0 = lamp_factor * night_atmos.z * INSTANCE_CUSTOM.r * pow(haze, 1.5) * (1.0 - smoothstep(reach * 0.6, reach, dist));
	float amp = amp0 * night_atmos.y;
	float ramp = look2 > 0.5 && rain_intensity > 0.02 ? amp0 : 0.0;
	if (amp < 0.001 && ramp < 0.001) {
		VERTEX = vec3(0.0);
	}
	v_ramp = ramp;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 axis = cam.xz - top.xz;
	axis /= max(length(axis), 1e-4);
	vec2 rel = w.xz - top.xz;
	v_across = vec2(dot(rel, vec2(-axis.y, axis.x)), dot(rel, axis) >= 0.0 ? 1.0 : -1.0);
	vec2 radial = w.xz - top.xz;
	vec2 tocam = cam.xz - w.xz;
	v_face = abs(dot(radial / max(length(radial), 1e-4), tocam / max(length(tocam), 1e-4)));
	v_h = clamp(-VERTEX.y, 0.0, 1.0);
	v_w = w;
	v_amp = amp;
	v_col = cs_srgb_to_linear(COLOR.rgb);
}

void fragment() {
	// Through the middle of the cone the eye crosses the most lit air.
	float body = pow(v_face, 3.0);
	float along = smoothstep(0.0, 0.07, v_h) * pow(1.0 - v_h, 0.6) * (1.0 - smoothstep(0.82, 1.0, v_h)) * mix(1.3, 0.35, v_h);
	// True world for the drift, so it does not jump on an origin shift.
	vec3 tw = mod(v_w + origin_shift, 997.0);
	float mist = 0.62 + 0.75 * sh_noise(tw.xz * 0.55 + vec2(tw.y * 0.35, 0.0) + vec2(TIME * 0.21, TIME * 0.07));
	float rain = 0.0;
	if (rain_intensity > 0.02) {
		// Lit drops falling through the cone: thin vertical streaks in columns round it.
		float col = floor((tw.x + tw.z) * 9.0);
		float fall = fract(tw.y * 0.45 + TIME * 2.6 + sh_hash(vec2(col, 7.0)) * 9.0);
		float lane = step(0.72, sh_hash(vec2(col, 3.0)));
		rain = lane * smoothstep(0.86, 0.97, fall) * (1.0 - smoothstep(0.97, 1.0, fall)) * rain_intensity * rain_streaks;
	}
	// A pixel close to the eye (inside or brushing the cone) fades, never a flat screen wash.
	float near = smoothstep(0.6, 3.0, length(v_w - INV_VIEW_MATRIX[3].xyz));
	float a = gain * v_amp * near * along * (body * mist + rain);
	if (look2 > 0.5) {
		// Lit drops in longer streaks (a drop falls ~12 m/s: a 0.6 m smear in an eye's glance), half
		// the columns, brightest through the cone's middle and round its upper part.
		// Columns across the cone as the eye sees it, so a streak stands vertical on either face.
		float cx = v_across.x * 24.0;
		float col2 = floor(cx) + (v_across.y > 0.0 ? 0.0 : 101.0) + floor(tw.x * 0.05) * 13.0 + floor(tw.z * 0.05) * 29.0;
		float fall2 = fract(tw.y * 0.3 + TIME * 3.6 + sh_hash(vec2(col2, 11.0)) * 9.0);
		float lane2 = step(0.72, sh_hash(vec2(col2, 5.0)));
		float line = 1.0 - smoothstep(0.15, 0.5, abs(fract(cx) - 0.5));
		float streak = lane2 * line * smoothstep(0.78, 0.94, fall2) * (1.0 - smoothstep(0.94, 1.0, fall2));
		float along2 = smoothstep(0.0, 0.2, v_h) * pow(1.0 - v_h, 0.8) * (1.0 - smoothstep(0.82, 1.0, v_h)) * mix(1.3, 0.35, v_h);
		float rain2 = streak * rain_intensity * rain2_gain * (0.35 + 0.65 * body);
		a = gain * near * along2 * (v_amp * body * mist + v_ramp * rain2);
	}
	vec3 col = v_col;
	if (look2 > 0.5) {
		// A lit drop is water, not glass of the lamp's colour: its streak runs paler than the cone.
		col = mix(v_col, vec3(max(max(v_col.r, v_col.g), v_col.b)) * vec3(1.0, 0.95, 0.88), 0.35);
	}
	ALBEDO = cs_out(col * a);
}
