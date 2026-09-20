shader_type spatial;
render_mode cull_back;

// Far buildings: one MultiMesh of unit boxes scaled to each part. Windows are drawn on the
// walls from a fixed grid so the skyline reads as buildings, not blocks, and they light up at
// night. Instance COLOR is the facade color; INSTANCE_CUSTOM is (window style / 4, lit ratio,
// seed, plain flag: 1 = no windows, e.g. a plinth).
global uniform float night_factor;
uniform float floor_height = 3.4;
uniform float window_pitch = 2.6;
uniform vec3 lit_color : source_color = vec3(1.0, 0.85, 0.55);

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 box_size;
varying vec4 custom;
varying vec4 tint;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	box_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	custom = INSTANCE_CUSTOM;
	tint = COLOR;
}


void fragment() {
	vec3 n = normalize(local_normal);
	vec3 albedo = tint.rgb;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emission = vec3(0.0);
	if (custom.a < 0.5 && abs(n.y) < 0.5) {
		// Wall: local_pos runs -0.5..0.5 on the unit box; scale to meters.
		float u = (abs(n.x) > 0.5 ? local_pos.z * box_size.z : local_pos.x * box_size.x) + 0.5 * (abs(n.x) > 0.5 ? box_size.z : box_size.x);
		float v = (local_pos.y + 0.5) * box_size.y;
		float style = custom.r * 4.0;
		float col = floor(u / window_pitch);
		float row = floor(v / floor_height);
		float fu = fract(u / window_pitch);
		float fv = fract(v / floor_height);
		bool glass;
		if (style < 0.5) {
			glass = abs(fu - 0.5) < 0.27 && abs(fv - 0.52) < 0.25;
		} else if (style < 1.5) {
			glass = abs(fv - 0.55) < 0.27;
		} else if (style < 2.5) {
			glass = fu > 0.05 && fv > 0.06;
		} else {
			glass = abs(fu - 0.5) < 0.16 && abs(fv - 0.5) < 0.4;
		}
		float face_id = abs(n.x) > 0.5 ? (n.x > 0.0 ? 1.0 : 2.0) : (n.z > 0.0 ? 3.0 : 4.0);
		if (glass && v > 1.0 && v < box_size.y - 0.8) {
			float k = hash21(vec2(col, row) + face_id * 17.0 + custom.b * 100.0);
			// Dark tinted glass: little metal, so far towers do not mirror the sky and vanish.
			albedo = tint.rgb * 0.2 + vec3(0.04, 0.06, 0.09);
			rough = 0.45;
			metal = 0.15;
			if (k < custom.g) {
				float on = 0.1 + 0.9 * night_factor;
				albedo = mix(albedo, lit_color, 0.7 * on);
				emission = lit_color * on * (0.6 + 0.4 * hash21(vec2(row, col) + custom.b));
			}
		} else {
			// Slight weathering and a darker base so far walls are not flat slabs.
			albedo *= 0.9 + 0.1 * hash21(vec2(col, row) + custom.b);
			albedo *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 5.0, v));
		}
	} else if (abs(n.y) > 0.5) {
		albedo = mix(vec3(0.38, 0.37, 0.36), tint.rgb, 0.25);
		rough = 0.95;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	// No specular at all on the far boxes: at grazing angles the sky reflection made whole
	// towers look see-through (a cage of wall strips).
	SPECULAR = 0.0;
	EMISSION = emission;
}
