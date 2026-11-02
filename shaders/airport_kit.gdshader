shader_type spatial;
render_mode cull_back;

// The airport's small hardware (AirportKit): ground service vehicles, masts, light fixtures,
// navaids, cones, blast fences. One material for all of it; what each vertex is rides in its
// vertex colour's alpha, and the vehicles' livery in the instance's INSTANCE_CUSTOM:
//   a 1.0   painted body: albedo = INSTANCE_CUSTOM.rgb when one is set (not black), else the vertex colour
//   a 0.75  lamp lens: the vertex colour, emitting at night (beacons, cab lamps, fixture lenses)
//   a 0.5   glass: dark, glossy
//   a 0.25  rubber / black plastic: rough
//   a 0.0   anything else: the vertex colour, painted metal
// Colours are LINEAR on both renderers (color_space.gdshaderinc); vertex colours and instance
// data arrive raw on both, so they are written linear in AirportKit.
// Shader files use // comments.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
// Working dirt (AirportApron): road grime up the lower body from the tyres, the paint mottled and
// chalky where the sun has had it for years. 0 (AIRPORT_APRON=0) is the old clean finish.
uniform float grime = 0.0;

varying vec3 v_col;
varying float v_kind;
varying vec3 v_model;
varying vec3 v_world;

void vertex() {
	v_model = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR.rgb;
	v_kind = COLOR.a;
	// MultiMeshBatch's default custom is opaque black: only a colour that is set counts.
	if (COLOR.a > 0.9 && INSTANCE_CUSTOM.a > 0.5 && dot(INSTANCE_CUSTOM.rgb, vec3(1.0)) > 0.001) {
		v_col = INSTANCE_CUSTOM.rgb;
	}
}

void fragment() {
	vec3 col = v_col;
	float rough = 0.62;
	float metal = 0.15;
	vec3 emit = vec3(0.0);
	if (v_kind > 0.9) {
		rough = 0.42;
		metal = 0.05;
	} else if (v_kind > 0.6) {
		emit = col * (0.15 + 3.5 * lamp_factor);
		rough = 0.2;
	} else if (v_kind > 0.4) {
		col = col * 0.35;
		rough = 0.08;
		metal = 0.3;
	} else if (v_kind > 0.15) {
		rough = 0.92;
		metal = 0.0;
	}
	if (grime > 0.0 && (v_kind < 0.4 || v_kind > 0.9)) {
		// Metres over the ground the vehicle stands on (every kit mesh has its ground at y 0).
		float low = 1.0 - smoothstep(0.12, 1.15, v_model.y);
		vec2 q = v_world.xz * 1.7 + v_world.y * 0.9;
		float n = fract(sin(dot(floor(q), vec2(12.9898, 78.233))) * 43758.5453);
		float n2 = fract(sin(dot(floor(q * 3.1 + 5.0), vec2(39.3468, 11.135))) * 24634.6345);
		float mottle = mix(n, n2, 0.5);
		col *= 1.0 - grime * (0.34 * low + 0.08 * mottle);
		// Chalky sun-faded paint on the tops.
		if (v_kind > 0.9) {
			col = mix(col, vec3(dot(col, vec3(0.3, 0.55, 0.15))) * 1.05, grime * 0.12 * (1.0 - low));
			rough = mix(rough, 0.68, grime * (0.4 * low + 0.25 * mottle));
		}
	}
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	EMISSION = cs_out(emit);
}
