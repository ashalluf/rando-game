shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

// Fireworks on the water (scripts/world/fireworks.gd): a flat sheet a hair over the sea round a
// beach show that adds what the rippled sea mirrors of the bursts in the air - the long broken
// column of glints under each break, reaching toward the viewer. Fireworks pushes the brightest
// FW_WATER_LIGHTS breaks of the frame (site frame position + level, linear colour). The slope
// spread of the wind ripples (`ripple`) decides how long and wide the column is; a hash of the
// ripple cell and the clock breaks it into glints. Faded before the waterline (`shore_x`, the
// coast's x in the site frame) so it never lands on the sand. The crests of the real swell cover
// it where they stand higher; that only breaks it up more.

#include "res://shaders/color_space.gdshaderinc"

uniform vec4 burst_pos[4];
uniform vec3 burst_col[4];
uniform float now = 0.0;
uniform float ripple = 0.11;
uniform float gain = 0.5;
uniform float shore_x = 400.0;
uniform float strength = 1.0;

varying vec3 v_pos;
varying vec3 v_cam;


void vertex() {
	v_pos = VERTEX;
	v_cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
}


float wh(vec2 c) {
	return fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453);
}


void fragment() {
	vec3 e = normalize(v_cam - v_pos);
	vec3 sum = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		float lvl = burst_pos[i].w;
		if (lvl <= 0.0) {
			continue;
		}
		vec3 l = normalize(burst_pos[i].xyz - v_pos);
		vec3 h = normalize(e + l);
		// The slope a ripple needs to send this burst into the eye, against how many have it.
		vec2 slope = h.xz / max(h.y, 0.05);
		float p = exp(-dot(slope, slope) / (2.0 * ripple * ripple));
		float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(e, vec3(0.0, 1.0, 0.0)), 0.0, 1.0), 5.0);
		sum += burst_col[i] * lvl * p * fres;
	}
	// Glints: the column is made of ripples catching the light, flickering as the water moves.
	vec2 cell = floor(v_pos.xz * vec2(0.9, 1.6));
	float g = wh(cell + floor(now * 7.0 + wh(cell) * 7.0));
	float glint = 0.25 + 2.2 * smoothstep(0.55, 0.95, g);
	float shore = 1.0 - smoothstep(shore_x - 60.0, shore_x - 8.0, v_pos.x);
	ALBEDO = cs_out(sum * gain * glint * shore * strength);
}
