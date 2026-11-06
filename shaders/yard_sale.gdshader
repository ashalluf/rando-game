shader_type spatial;
render_mode cull_back;

// Weekend yard sales (YardSales / YardSaleKit, scripts/world/yard_sales.gd and yard_sale_kit.gd):
// folding tables and what is on them, the clothes rack, the sofa, boxes, lamps, the hand-lettered
// signs and the balloons, all on this one shader (a MultiMesh draw a kind a chunk).
//
// Vertex data (written by YardSaleKit):
//   COLOR.rgb  an sRGB colour (most codes) or a shade multiplying the palette (FABRIC, CLOTH)
//   COLOR.a    what the face is: floor(a * 16), YardSaleKit.K_*
//   UV         metres along the face (grain, weave, fibre)
//   UV2.x      a part id: the garment on the rack, 1 for tape on cardboard
//   UV2.y      how free the vertex is to move in the wind (garments, balloons and their strings)
//   INSTANCE_CUSTOM.a  the household's palette pick ((index + 0.5) / 8): the sofa's fabric, the
//              rack's garments
// Colours arrive raw on both renderers (vertex colours, instance custom), so they are decoded
// from sRGB here, the arithmetic runs in linear and color_space.gdshaderinc hands it over.

#include "res://shaders/color_space.gdshaderinc"

global uniform float wind_factor;
global uniform float road_wetness;

/// Garment and balloon sway (metres at the free end).
uniform float sway = 0.045;

varying flat int v_code;
varying float v_pal;
varying vec3 v_local;

// Upholstery: oatmeal, navy, rust, olive, grey, brown corduroy, mustard, teal.
const vec3 FABRIC[8] = vec3[8](vec3(0.66, 0.6, 0.5), vec3(0.15, 0.19, 0.3), vec3(0.52, 0.24, 0.15), vec3(0.36, 0.38, 0.24),
	vec3(0.45, 0.45, 0.44), vec3(0.34, 0.24, 0.17), vec3(0.72, 0.55, 0.18), vec3(0.14, 0.36, 0.38));
// Clothes on the rack: whites, denim, black, a red, khaki, greys, florals' ground, pastels.
const vec3 CLOTH[14] = vec3[14](vec3(0.9, 0.9, 0.88), vec3(0.25, 0.33, 0.48), vec3(0.1, 0.1, 0.11), vec3(0.62, 0.14, 0.13),
	vec3(0.64, 0.58, 0.44), vec3(0.5, 0.5, 0.5), vec3(0.82, 0.62, 0.66), vec3(0.55, 0.7, 0.82), vec3(0.2, 0.32, 0.22),
	vec3(0.86, 0.78, 0.5), vec3(0.4, 0.2, 0.36), vec3(0.32, 0.32, 0.34), vec3(0.75, 0.42, 0.2), vec3(0.6, 0.66, 0.6));

float ys_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float ys_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(ys_hash(i), ys_hash(i + vec2(1.0, 0.0)), f.x), mix(ys_hash(i + vec2(0.0, 1.0)), ys_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}


void vertex() {
	v_code = int(floor(COLOR.a * 16.0));
	v_pal = INSTANCE_CUSTOM.a;
	if (UV2.y > 0.001) {
		// A garment or a balloon in the breeze: a slow swing and a quicker flutter, phased by
		// where the instance stands and the part, more in a Santa Ana.
		vec3 inst = MODEL_MATRIX[3].xyz;
		float w = sway * (0.6 + wind_factor * 1.8);
		float ph = dot(inst.xz, vec2(0.41, 0.67)) + UV2.x * 0.9;
		VERTEX.x += UV2.y * w * (sin(TIME * 1.3 + ph) + 0.3 * sin(TIME * 3.7 + ph * 2.1));
		VERTEX.z += UV2.y * w * 0.7 * sin(TIME * 1.05 + ph * 1.4);
		VERTEX.y += UV2.y * w * 0.25 * sin(TIME * 0.8 + ph);
	}
	v_local = VERTEX;
}


void fragment() {
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	int pal = int(floor(fract(v_pal) * 8.0 + 0.001)) & 7;
	vec3 alb = base;
	float rough = 0.72;
	float metal = 0.0;
	float spec = 0.5;
	int code = v_code;
	if (code == 1) {
		// Painted wood or metal, satin.
		rough = 0.5 + ys_noise(UV * 40.0) * 0.1;
	} else if (code == 2) {
		// Upholstery: the household's colour, a coarse weave, worn paler on the seat.
		vec3 f = cs_srgb_to_linear(FABRIC[pal]) * base;
		vec2 w = UV * 260.0;
		float weave = 0.88 + 0.12 * sin(w.x) * sin(w.y);
		float wear = ys_noise(UV * 3.0) * clamp(up, 0.0, 1.0);
		alb = f * weave * (1.0 + 0.18 * wear);
		rough = 0.92;
		spec = 0.35;
	} else if (code == 3) {
		rough = 0.38 + ys_noise(UV * 10.0) * 0.2;
		metal = 0.85;
	} else if (code == 4) {
		// Glazed ceramic, moulded plastic, an appliance's enamel.
		rough = 0.18 + ys_noise(UV * 25.0) * 0.08;
		spec = 0.55;
	} else if (code == 5) {
		// Kraft cardboard: short fibres, scuffs; a strip of packing tape (UV2.x 1), glossy.
		float fib = ys_noise(vec2(UV.x * 90.0, UV.y * 30.0)) * 0.6 + ys_noise(UV * 260.0) * 0.4;
		alb = base * (0.86 + 0.22 * fib) * (0.92 + 0.12 * ys_noise(UV * 4.0));
		rough = 0.88;
		spec = 0.3;
		if (UV2.x > 0.5) {
			alb = base * 1.08;
			rough = 0.16;
			spec = 0.6;
		}
	} else if (code == 6) {
		// Poster board: smooth, a little dirt and a crease or two.
		alb = base * (0.95 + 0.05 * ys_noise(UV * 30.0)) * (1.0 - 0.06 * smoothstep(0.92, 1.0, ys_noise(UV * 3.5)));
		rough = 0.78;
		spec = 0.35;
	} else if (code == 7) {
		// Marker ink: satin, the colour soaking unevenly into the board.
		alb = base * (0.85 + 0.25 * ys_noise(UV * 400.0));
		rough = 0.5;
		spec = 0.45;
	} else if (code == 8) {
		// A garment: its colour by the household and the piece, cotton or knit.
		float h = ys_hash(vec2(UV2.x * 1.37 + 3.0, v_pal * 91.7 + 1.0));
		int i = int(floor(h * 14.0)) % 14;
		alb = cs_srgb_to_linear(CLOTH[i]) * base;
		vec2 w = UV * 320.0;
		alb *= 0.9 + 0.1 * sin(w.x) * sin(w.y);
		// Now and then a stripe.
		if (ys_hash(vec2(UV2.x * 5.1, v_pal * 13.0)) < 0.25) {
			alb *= 0.75 + 0.25 * step(0.5, fract(UV.y * 12.0));
		}
		rough = 0.93;
		spec = 0.3;
		BACKLIGHT = cs_out(alb * 0.3);
	} else if (code == 9) {
		// The folding table's moulded HDPE top: off-white, a fine speckle, scuffed.
		float sp = ys_hash(floor(UV * 900.0));
		alb = base * (0.94 + 0.06 * sp) * (1.0 - 0.07 * ys_noise(UV * 6.0));
		rough = 0.62;
		spec = 0.4;
	} else if (code == 10) {
		float grain = ys_noise(vec2(UV.x * 3.0, UV.y * 90.0 + UV.x * 2.0));
		alb = base * (0.82 + 0.3 * grain) * (0.9 + 0.2 * ys_noise(UV * 2.0));
		rough = 0.7;
	} else if (code == 11) {
		rough = 0.12;
		metal = 1.0;
	} else if (code == 12) {
		// A latex balloon: glossy, lit through.
		rough = 0.22;
		spec = 0.6;
		BACKLIGHT = cs_out(alb * 0.6);
	} else if (code == 13) {
		rough = 0.85;
		spec = 0.3;
	} else if (code == 14) {
		// A lamp shade: pleated paper or linen, lit through.
		alb = base * (0.9 + 0.1 * sin(UV.x * 380.0));
		rough = 0.9;
		BACKLIGHT = cs_out(alb * 0.5);
	} else if (code == 15) {
		// A fluorescent price sticker.
		rough = 0.55;
		alb = min(base * 1.15, vec3(1.0));
	}
	// Garden dust low down on what stands on the ground.
	if (code != 12 && code != 15) {
		float g = (1.0 - smoothstep(0.0, 0.2, v_local.y)) * (0.5 + 0.5 * ys_noise(v_local.xz * 6.0));
		alb *= 1.0 - 0.15 * g;
	}
	rough = mix(rough, rough * 0.5, clamp(road_wetness, 0.0, 1.0) * clamp(up + 0.3, 0.0, 1.0));
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
}
