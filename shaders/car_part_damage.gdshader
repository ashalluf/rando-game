shader_type spatial;
render_mode cull_back;

// The trim, chrome and plastic parts of a crashed car (CrashDeform swaps them in on the first
// crumple, in place of the model's own StandardMaterial3D, whose numbers it copies): the same
// plain lit material, moved with the crushed body (car_crumple.gdshaderinc) so a grille, a bumper
// or a mirror does not hang in the air in front of a crumpled nose. `far` is the far twin's folded
// parts surface (albedo in the vertex colour, roughness in its alpha, Vehicle.PARTS_SHADER).

#include "res://shaders/car_damage.gdshaderinc"
#include "res://shaders/car_crumple.gdshaderinc"
#include "res://shaders/wet_surface.gdshaderinc"

uniform vec3 part_albedo : source_color = vec3(0.1);
uniform sampler2D part_tex : source_color, filter_linear_mipmap;
uniform bool has_tex = false;
uniform float part_roughness = 0.5;
uniform float part_metallic = 0.0;
uniform float part_specular = 0.5;
uniform bool far = false;
uniform bool use_vcol = false;


void vertex() {
	if (cr_any()) {
		cr_apply(VERTEX, NORMAL);
	}
}


void fragment() {
	if (far) {
		ALBEDO = COLOR.rgb;
		ROUGHNESS = clamp(COLOR.a, 0.04, 1.0);
		METALLIC = 0.0;
		SPECULAR = 0.5;
	} else {
		vec3 a = part_albedo;
		if (has_tex) {
			a *= texture(part_tex, UV).rgb;
		}
		if (use_vcol) {
			a *= COLOR.rgb;
		}
		ALBEDO = a;
		ROUGHNESS = part_roughness;
		METALLIC = part_metallic;
		SPECULAR = part_specular;
	}
	if (ws_on()) {
		float w = ws_wet(0.3);
		ALBEDO *= mix(1.0, 0.85, w);
		ROUGHNESS = mix(ROUGHNESS, ROUGHNESS * 0.5, w);
	}
}
