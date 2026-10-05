shader_type spatial;
// A hospital's lit channel letters and light boxes (HospitalBuild): the EMERGENCY sign over the
// ambulance bay, the name on the tower crown and the monument, the entrance words on the
// canopies. By day a letter is its painted face with a faint glow (a lit sign still shows at
// noon), after dark it burns with the lamps (lamp_factor). Colours are LINEAR, set as Vector3
// from script (color_space.gdshaderinc: never decoded twice). The red stays at a tenth of green:
// through AgX a red-heavy HDR colour turns salmon pink (CLAUDE.md, Car damage), so a lit red
// letter is held to ~2.6x and the bloom does the rest.
#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
uniform vec3 face_color = vec3(0.70, 0.04, 0.03);
uniform vec3 glow_color = vec3(1.0, 0.10, 0.05);
uniform float night_energy = 2.6;
uniform float day_energy = 0.35;
// A light box's face (1): brighter towards its middle, the tubes behind the diffuser.
uniform float box_face = 0.0;

void fragment() {
	vec3 face = face_color;
	float e = mix(day_energy, night_energy, clamp(lamp_factor, 0.0, 1.0));
	if (box_face > 0.5) {
		vec2 d = abs(UV - 0.5) * 2.0;
		e *= 0.75 + 0.25 * (1.0 - max(d.x * d.x, d.y * d.y));
	}
	ALBEDO = cs_out(face);
	ROUGHNESS = 0.35;
	SPECULAR = 0.5;
	EMISSION = cs_out(glow_color * e);
}
