shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/color_space.gdshaderinc"

// The waypoint's beacon (scripts/ui/world_map.gd): a violet beam standing on the waypoint and a
// pulsing ring on the ground round its foot, both additive and fog-free, and both widened with
// distance so the beam never draws thinner than a couple of pixels across the basin.
//
//   kind 0  the beam: an open cylinder of radius 1 (scaled here), centred on its node, `height`
//           tall. Brightest down its middle, fading out toward the top, light rising up it.
//   kind 1  the ring: a 2 x 2 quad lying flat (scaled here).

uniform int kind = 0;
uniform float height = 420.0;
// The beam's radius near and the fraction of the distance it never gets thinner than (about
// 4 px at 1080 lines with a 75 degree lens).
uniform float beam_radius = 0.9;
uniform float beam_widen = 0.006;
uniform float ring_radius = 8.0;
uniform float ring_widen = 0.012;
// Linear colour and energy (the HDR overshoot is what glows).
uniform vec3 tint = vec3(0.46, 0.18, 1.0);
uniform float energy = 1.8;

varying float v_y;
varying float v_dist;

void vertex() {
	float dist = distance(CAMERA_POSITION_WORLD, NODE_POSITION_WORLD);
	v_dist = dist;
	if (kind == 0) {
		float r = max(beam_radius, dist * beam_widen);
		VERTEX.xz *= r;
		v_y = VERTEX.y / height + 0.5;
	} else {
		float r = max(ring_radius, dist * ring_widen);
		VERTEX.xz *= r;
		v_y = 0.0;
	}
}

void fragment() {
	vec3 col = tint;
	float a;
	if (kind == 0) {
		float core = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
		float fade = pow(1.0 - clamp(v_y, 0.0, 1.0), 1.4);
		float rise = 0.75 + 0.25 * sin((v_y * height * 0.08 - TIME * 3.0));
		a = core * fade * rise;
		col = mix(col, vec3(0.85, 0.75, 1.0), core * core * 0.25);
	} else {
		float r = length(UV * 2.0 - 1.0);
		float ring = smoothstep(0.7, 0.8, r) * (1.0 - smoothstep(0.88, 0.97, r));
		float wave = fract(TIME * 0.6);
		float pulse = smoothstep(wave - 0.06, wave, r) * (1.0 - smoothstep(wave, wave + 0.04, r)) * (1.0 - wave);
		float disc = (1.0 - smoothstep(0.0, 0.7, r)) * 0.18;
		a = ring + pulse * 0.8 + disc;
	}
	ALBEDO = cs_out(col * energy * a);
}
