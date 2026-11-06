shader_type spatial;
render_mode cull_back;
// What a car is made of underneath and inside its arches (CarUnderside; the meshes are
// tools/make_car_undersides.py's road_<name>_under.glb). One surface: the vertex colour's r is
// the kind (kind / 16 + 1 / 32: K_* below, the generator's numbers), g a variant, UV metres
// along / across a part. Linear on both renderers (color_space.gdshaderinc), so the web draws
// what the Mac does.
#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/wet_surface.gdshaderinc"

// Road grime: how far the dust and tar thrown up by the tyres darken and brown everything here.
uniform float grime = 0.55;
// Liner: rib pitch (m) and how much the ribs tilt the normal.
uniform float rib_pitch = 0.024;
uniform float rib_depth = 0.55;

const int K_LINER = 0;
const int K_STEEL = 1;
const int K_EXHAUST = 2;
const int K_TIP = 3;
const int K_RUBBER = 4;
const int K_SPRING = 5;
const int K_ALU = 6;
const int K_TANK = 7;
const int K_SOOT = 8;
const int K_SHIELD = 9;

varying vec3 obj_pos;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	int kind = int(floor(COLOR.r * 16.0));
	float var = COLOR.g;
	vec2 uv = UV;
	vec3 alb = vec3(0.03);
	float rough = 0.7;
	float metal = 0.0;
	float n1 = vnoise(uv * 38.0);
	float n2 = vnoise(uv * 7.0 + 13.0);
	// Pixel footprint in metres: detail under a pixel goes to its average.
	float px = max(length(fwidth(uv)), 1e-5);
	vec3 bump = vec3(0.0);
	if (kind == K_LINER) {
		// Moulded polypropylene / felt: near-black grey, mottled, with ribs across the arc.
		float fade = clamp(1.0 - px / (rib_pitch * 0.6), 0.0, 1.0);
		float ph = uv.x / rib_pitch;
		float rib = sin(ph * 6.2832);
		bump.x = cos(ph * 6.2832) * rib_depth * fade;
		alb = vec3(0.052, 0.052, 0.055) * (0.82 + 0.3 * n1) * (1.0 - 0.10 * rib * fade);
		rough = 0.86;
		if (var > 0.25) {
			// The back wall: a coarser, flatter felt.
			alb = vec3(0.042, 0.042, 0.044) * (0.85 + 0.3 * n1);
			rough = 0.92;
		}
	} else if (kind == K_STEEL) {
		// Black e-coat and underbody seal; a share (var) is zinc-grey galvanised or bare cast.
		alb = mix(vec3(0.022, 0.022, 0.024), vec3(0.11, 0.105, 0.10), var);
		rough = mix(0.55, 0.62, var);
		metal = var * 0.5;
	} else if (kind == K_EXHAUST) {
		// Stainless gone straw and brown from the heat, rust round the welds and the hangers.
		vec3 heat = mix(vec3(0.20, 0.17, 0.12), vec3(0.11, 0.07, 0.045), n2);
		vec3 rust = vec3(0.12, 0.045, 0.018);
		alb = mix(heat, rust, smoothstep(0.55, 0.9, n1 * 0.6 + var * 0.5));
		rough = 0.55;
		metal = 0.6;
	} else if (kind == K_TIP) {
		// Polished stainless: a mirror on Forward+; a satin grey where there is nothing to mirror.
		if (cs_linear_renderer()) {
			alb = vec3(0.80, 0.80, 0.82);
			metal = 1.0;
			rough = 0.16;
		} else {
			alb = vec3(0.62, 0.63, 0.64);
			rough = 0.3;
		}
		// Soot at the lip.
		alb *= mix(1.0, 0.4, smoothstep(0.03, 0.0, uv.x) * 0.8);
	} else if (kind == K_RUBBER) {
		alb = vec3(0.018);
		rough = 0.9;
	} else if (kind == K_SPRING) {
		vec3 c0 = vec3(0.02);
		vec3 c1 = vec3(0.32, 0.02, 0.015);
		vec3 c2 = vec3(0.45, 0.30, 0.01);
		alb = var < 0.25 ? c0 : (var < 0.75 ? c1 : c2);
		rough = 0.4;
	} else if (kind == K_ALU) {
		// Cast aluminium: sump, gearbox, rack.
		alb = vec3(0.30, 0.30, 0.29) * (0.85 + 0.25 * n1);
		rough = 0.5;
		metal = 0.7;
	} else if (kind == K_TANK) {
		alb = vec3(0.025, 0.025, 0.027) * (0.9 + 0.2 * n1);
		rough = 0.65;
	} else if (kind == K_SOOT) {
		alb = vec3(0.012, 0.011, 0.010);
		rough = 0.95;
	} else if (kind == K_SHIELD) {
		// Embossed aluminium heat shield / the plastic splash shield (var 0).
		if (var > 0.25) {
			vec2 d = fract(uv / 0.018) - 0.5;
			float dim = smoothstep(0.35, 0.1, length(d)) * clamp(1.0 - px / 0.012, 0.0, 1.0);
			bump.xy = d * dim * 1.6;
			alb = vec3(0.38, 0.37, 0.35) * (0.8 + 0.3 * n1);
			metal = 0.8;
			rough = 0.45;
		} else {
			alb = vec3(0.03, 0.03, 0.032) * (0.85 + 0.3 * n1);
			rough = 0.8;
		}
	}
	// Road grime from below: brown dust, heavier the lower and the more it faces the road.
	float down = clamp(-dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz), 0.0, 1.0);
	float g = grime * (0.35 + 0.65 * down) * (0.6 + 0.6 * n2);
	if (kind != K_TIP && kind != K_SOOT) {
		alb = mix(alb, vec3(0.085, 0.07, 0.05), clamp(g * 0.55, 0.0, 0.7));
		rough = mix(rough, 0.9, g * 0.5);
	}
	if (ws_on()) {
		float w = ws_wet(0.6);
		alb *= mix(1.0, 0.8, w);
		rough = mix(rough, rough * 0.45, w);
	}
	if (length(bump) > 0.0) {
		NORMAL = normalize(NORMAL + (TANGENT * bump.x + BINORMAL * bump.y) * 0.35);
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = metal;
	SPECULAR = 0.5;
}
