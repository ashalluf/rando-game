shader_type spatial;
render_mode cull_disabled;

// The weeds of the city's vacant lots (VacantKit's tufts of dry grass and foxtail, wild mustard,
// fennel), code-built meshes in VacantLots' batches. Colours are vertex colours written as LINEAR
// albedo (a batch's instance colour multiplies them) and handed to the renderer in its own space
// (color_space.gdshaderinc), so the web draws what the Mac does. The wind bends a stalk with the
// square of its height over the instance's foot and shivers the tips; the phase comes from where
// the plant stands, so a lot of weeds never sways in step. Light through the blades and petals is
// BACKLIGHT (both renderers), which is most of what makes a dry lot glow in the low sun.

global uniform float wind_factor;
global uniform float road_wetness;
global uniform vec3 sun_direction;

/// Metres of bend per metre-squared of height (a 1.4 m mustard stalk's head swings ~10 cm).
uniform float bend_scale = 0.05;
uniform float speed = 1.3;
uniform float flutter = 0.03;
uniform float translucency = 0.55;

#include "res://shaders/color_space.gdshaderinc"

varying float height01;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.71 + origin.z * 0.53;
	float w = clamp(max(wind_factor, 0.3), 0.0, 3.0);
	w *= 0.6 + 0.4 * sin(TIME * 0.21 + (origin.x + origin.z) * 0.02);
	float h = max(VERTEX.y, 0.0);
	height01 = clamp(h / 1.2, 0.0, 1.0);
	float t = TIME * speed;
	float bend = h * h * bend_scale * w;
	float p = phase + VERTEX.x * 3.0 + VERTEX.z * 2.0;
	VERTEX.x += bend * (sin(t + p) * 0.7 + sin(t * 1.9 + p * 1.7) * 0.3);
	VERTEX.z += bend * (sin(t * 0.83 + p + 1.7) * 0.7 + sin(t * 1.6 + p * 0.6) * 0.3);
	VERTEX.xz += vec2(sin(TIME * 4.1 + p * 3.0), cos(TIME * 3.7 + p * 2.0)) * flutter * h * w;
}

void fragment() {
	float wet = clamp(road_wetness, 0.0, 1.0);
	vec3 lin = COLOR.rgb * mix(1.0, 0.82, wet);
	// Darker down in the clump, where the stems shade each other.
	lin *= mix(0.55, 1.0, smoothstep(0.0, 0.5, height01));
	ALBEDO = cs_out(lin);
	ROUGHNESS = mix(0.82, 0.3, wet);
	SPECULAR = 0.3;
	vec3 to_cam = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float facing = clamp(dot(to_cam, -normalize(sun_direction)), 0.0, 1.0);
	BACKLIGHT = cs_out(lin * translucency * (1.0 + 2.0 * pow(facing, 5.0)));
}
