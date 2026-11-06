shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// A lighthouse's rotating beam as a drawn shaft (Lighthouses, LighthouseKit.beam_mesh()): an open
// cone from the lens out along the rotor's +X, turned by LighthouseBeacon. What makes a beam in
// haze read is that it is bright down its middle and fades to nothing at its edges and its far
// end, so the cone is lit by how squarely the eye sees its surface (|N.V|: the cone's silhouette
// edge is edge-on and dark, the face toward the eye is the shaft's middle) times a falloff along
// its length (UV.x, 0 at the lens). It fades out close to the camera (a cone you stand in would
// be two flat walls of light) and with lamp_factor (LighthouseBeacon hides it by day). Additive,
// no fog: it IS the fog, lit. Works the same on both renderers (cs_out()).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
// Linear colour of the light, and how bright the shaft's core is.
uniform vec3 beam_color = vec3(1.0, 0.93, 0.78);
uniform float strength = 0.16;
// The shaft's falloff along its length (power of 1 - t) and how sharply it fades to its edges.
uniform float length_falloff = 2.6;
uniform float edge_power = 5.0;
// Metres from the camera over which the shaft fades in.
uniform float near_fade = 18.0;
// Extra brightness close to the lens (the hot core of the beam).
uniform float core_boost = 2.2;

// RcLighthouse (look 1, docs/HANDOFF.md "The lighthouse from the breakwater at night"): the light
// scattered by the air in a Gaussian pencil round the beam's axis, integrated along the view ray
// in closed form - one back face per ray, the ray's closest approach to the axis - rather than
// the cone's surface lit by |N.V|, which drew a solid tube of one brightness with a hard rim.
// UV2 is the beam's axis in the mesh (x, z). 0 = the shaft exactly as it was.
uniform float look = 0.0;
// Gaussian half-width at the lens (m) and its growth per metre (tan of the half angle).
uniform float waist = 0.35;
uniform float spread = 0.0084;
// Henyey-Greenstein asymmetry: bright looking back up the beam toward the lens.
uniform float phase_g = 0.5;
// Brightness of the look (the old `strength` is the old look's), metres over which the air
// dims the beam, and the haze patches' depth.
uniform float scatter = 0.045;
uniform float extinction = 650.0;
uniform float haze_patches = 0.75;
// The shaft's length (m: Lighthouses.LIGHTS' "length").
uniform float beam_length = 1700.0;

varying float v_along;
varying vec3 v_origin;
varying vec3 v_axis;

void vertex() {
	v_along = UV.x;
	v_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_axis = (MODEL_MATRIX * vec4(UV2.x, 0.0, UV2.y, 0.0)).xyz;
}

float lb_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float lb_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(lb_hash(i), lb_hash(i + vec2(1.0, 0.0)), f.x), mix(lb_hash(i + vec2(0.0, 1.0)), lb_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The look: in-scattered light along the eye ray through the pencil.
vec3 lb_scattered(vec3 cam, vec3 wp, float length_m, float time) {
	vec3 r = normalize(wp - cam);
	vec3 a = normalize(v_axis);
	vec3 w0 = cam - v_origin;
	float b = dot(r, a);
	float d = dot(r, w0);
	float e = dot(a, w0);
	float den = max(1.0 - b * b, 1e-4);
	float u = (b * e - d) / den;
	float s = (e - b * d) / den;
	// The closest approach behind the eye: take the eye's own place on the axis.
	if (u < 0.0) {
		u = 0.0;
		s = e;
	}
	vec3 pr = cam + r * u;
	vec3 pa = v_origin + a * s;
	float dist = length(pr - pa);
	float sigma = waist + spread * max(s, 0.0);
	float sin_phi = max(sqrt(den), 0.06);
	float core = exp(-(dist * dist) / (sigma * sigma));
	// Power spread over the pencil's section: per unit length of view through it, ~ 1 / sigma.
	float dens = core * (2.5 / sigma) / sin_phi;
	float g = phase_g;
	float cos_t = dot(a, -r);
	float ph = pow(1.0 + g * g, 1.5) / pow(max(1.0 + g * g - 2.0 * g * cos_t, 1e-4), 1.5);
	float along = smoothstep(-1.0, 3.0, s) * (1.0 - smoothstep(length_m * 0.55, length_m, s)) * exp(-max(s, 0.0) / extinction);
	float haze = 1.0 - haze_patches * 0.5 + haze_patches * (lb_noise(vec2(s * 0.018 - time * 0.06, dist * 0.08)) * 0.7 + lb_noise(vec2(s * 0.07 + time * 0.11, 3.0)) * 0.3);
	float nearf = smoothstep(near_fade * 0.25, near_fade, u);
	return beam_color * (dens * ph * along * haze * nearf * scatter);
}

void fragment() {
	if (look > 0.5) {
		if (FRONT_FACING) {
			discard;
		}
		vec3 col = lb_scattered((INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, beam_length, TIME) * clamp(lamp_factor, 0.0, 1.0);
		ALBEDO = cs_out(min(col, vec3(6.0)));
	} else {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float shaft = pow(facing, edge_power);
	float t = clamp(v_along, 0.0, 1.0);
	float fall = pow(1.0 - t, length_falloff) * (1.0 + core_boost * exp(-t * 60.0));
	float depth = length(VERTEX);
	float nearf = smoothstep(near_fade * 0.25, near_fade, depth);
	float a = shaft * fall * nearf * strength * clamp(lamp_factor, 0.0, 1.0);
	ALBEDO = cs_out(beam_color * a);
	}
}
