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
uniform float strength = 0.55;
// The shaft's falloff along its length (power of 1 - t) and how sharply it fades to its edges.
uniform float length_falloff = 1.6;
uniform float edge_power = 2.6;
// Metres from the camera over which the shaft fades in.
uniform float near_fade = 18.0;
// Extra brightness close to the lens (the hot core of the beam).
uniform float core_boost = 2.2;

varying float v_along;

void vertex() {
	v_along = UV.x;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float shaft = pow(facing, edge_power);
	float t = clamp(v_along, 0.0, 1.0);
	float fall = pow(1.0 - t, length_falloff) * (1.0 + core_boost * exp(-t * 60.0));
	float depth = length(VERTEX);
	float nearf = smoothstep(near_fade * 0.25, near_fade, depth);
	float a = shaft * fall * nearf * strength * clamp(lamp_factor, 0.0, 1.0);
	ALBEDO = cs_out(beam_color * a);
}
