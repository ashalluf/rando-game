shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

// A film shoot's lights after dark (FilmShootNight, refcam5 "film_shoot_night"): the air and the
// ground round the HMIs, the balloon and the basecamp's work lights. One mesh a chunk, additive and
// fog-free (CLAUDE.md: a blend_add shader left in the fog adds the fog colour over its quad).
//   UV2.x 0  a BLOOM: a camera-facing glow over a lamp (UV the quad's corner, UV2.y its size in
//            metres; NORMAL the way the lamp faces - an HMI seen from in front blazes, from behind
//            it is a soft glow; never drawn smaller than `min_angle` of the view).
//   UV2.x 1  a SHAFT: the HMI's beam as lit haze, a ribbon from the lens (UV.y 0) toward the action
//            (UV.y 1), turned to face the eye about its axis (NORMAL); UV.x -1..1 across, UV2.y its
//            width at the far end.
//   UV2.x 2  a POOL: the light a lamp lays on the ground, a flat quad (UV -1..1, the ellipse's own
//            frame), illuminance off a source UV2.y metres up (1 + d^2/h^2)^-1.5, cut to zero at the
//            rim. Added in DISPLAY numbers on both renderers (fh_display: Forward+ adds in linear
//            HDR, where a broad pool's faint tail is a flat white disc on the Mac).
// COLOR.rgb the light's colour (sRGB numbers), COLOR.a its strength. Nothing by day but a faint
// bloom (the lamps run by day too, nobody sees their light).
// Shader files use // comments.

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/fwd_review_h.gdshaderinc"

global uniform float lamp_factor;

uniform float bloom_energy = 0.55;
uniform float shaft_energy = 0.05;
uniform float pool_energy = 0.42;
// The smallest a bloom is drawn, in radians of view: an HMI 60 m off is still a lamp.
uniform float min_angle = 0.02;
// A shaft fades out where the eye is inside it (the beam reaching the lens would fill the frame).
uniform float shaft_near = 4.0;

varying float v_kind;
varying float v_face;
varying vec2 v_uv;

void vertex() {
	v_kind = UV2.x;
	v_uv = UV;
	vec3 wc = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_eye = CAMERA_POSITION_WORLD - wc;
	float dist = max(length(to_eye), 0.1);
	vec3 axis = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_face = 1.0;
	if (v_kind < 0.5) {
		float f = dot(axis, to_eye / dist);
		v_face = 0.18 + 0.82 * pow(max(f, 0.0), 1.5);
		vec3 centre = (VIEW_MATRIX * vec4(wc, 1.0)).xyz;
		float size = max(UV2.y, dist * min_angle);
		vec2 corner = (UV - vec2(0.5)) * size;
		// Pulled toward the eye so the lamp's own housing and barn doors do not cut it.
		centre += normalize(-centre) * min(size * 0.5, 2.0);
		VERTEX = centre + vec3(corner.x, -corner.y, 0.0);
	} else if (v_kind < 1.5) {
		vec3 side = normalize(cross(axis, to_eye / dist));
		float w = mix(0.35, UV2.y, UV.y);
		vec3 p = wc + side * UV.x * w;
		// End-on a shaft is short and thick in the view, side-on long and thin: about the same light.
		v_face = (1.0 - 0.7 * abs(dot(axis, to_eye / dist))) * smoothstep(shaft_near, shaft_near * 2.5, dist);
		VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	} else {
		VERTEX = (VIEW_MATRIX * vec4(wc, 1.0)).xyz;
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float night = smoothstep(0.15, 0.75, lamp_factor);
	float k = COLOR.a;
	vec3 tint = COLOR.rgb;
	if (v_kind < 0.5) {
		float r = length(v_uv - vec2(0.5)) * 2.0;
		// A tight hot core over the lens and a wide soft skirt; zero at the quad's edge.
		float core = exp(-r * r * 26.0);
		float skirt = exp(-r * r * 5.0) * 0.25;
		float a = (core + skirt) * (1.0 - smoothstep(0.7, 1.0, r)) * v_face * k * bloom_energy * mix(0.12, 1.0, night);
		ALBEDO = cs_out(cs_srgb_to_linear(tint) * a);
	} else if (v_kind < 1.5) {
		float across = 1.0 - abs(v_uv.x);
		float t = v_uv.y;
		float a = across * across * smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.6, 1.0, t)) * v_face * k * shaft_energy * night;
		if (a < 0.0005) {
			discard;
		}
		ALBEDO = cs_out(cs_srgb_to_linear(tint) * a);
	} else {
		float d2 = dot(v_uv, v_uv);
		if (d2 >= 1.0) {
			discard;
		}
		// v_uv is the ellipse's own -1..1 frame; the falloff of a source `h` radii up.
		float h = 0.55;
		float e = pow(1.0 + d2 / (h * h), -1.5);
		float rim = 1.0 - smoothstep(0.55, 1.0, d2);
		float a = e * rim * k * pool_energy * night;
		ALBEDO = fh_display(tint * a);
	}
}
