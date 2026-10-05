shader_type spatial;
render_mode cull_back;

// The hillside estates past the FULL chunks (EstateFar, scripts/world/estate_far.gd): the far
// city's (Skyline) and the LOD chunks' copy of every HillRoads estate, as a handful of unit boxes
// each - the pad on its retaining walls with a lawn, a paved court, hedges, the house and its
// roof, the pool - plus the lamps a lit estate shows at night across the basin: garden lights,
// the pool's underwater light, the lamps on the gate piers, the porch.
//
// Each instance is one part. INSTANCE_CUSTOM (half floats on Compatibility, so no positions):
//   .r  the part's origin above the estate's deck (metres)
//   .g  kind (EstateFar.K_*) + 8 when the part stands on the real terrain (a LOD chunk) + a
//       variant in the fraction (0..0.99: window rolls, lamp colour)
//   .ba the part's origin minus the estate's centre, world XZ metres
// so every part of an estate seated on the far plane moves by the one amount: the plane's drawn
// height under the estate's centre minus its deck. COLOR is the part's LINEAR tint, its alpha
// Skyline's dissolve.
#include "res://shaders/macro_relief.gdshaderinc"
#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/window_lights.gdshaderinc"

// The ground follower's vertices (CityStreamer sets these as it does far_canopy's; the same
// plane_height() below, copied from far_canopy.gdshader - EstateFar's check keeps them equal).
uniform float plane_y = 0.0;
uniform vec2 plane_origin = vec2(0.0);
uniform float plane_half = 7000.0;
uniform float plane_step = 43.61;
uniform float edge_start = 5040.0;
uniform float edge_end = 6860.0;
// Smallest angular size a lamp is drawn at (radians of view): about 1.5 pixels on a 720-line
// frame at 55 degrees. Its brightness falls by the area it grew, but never under lamp_floor.
uniform float lamp_min_angle = 0.0022;
uniform float lamp_floor = 0.25;
// Lamp, window and pool light (linear, before lamp_factor).
uniform float lamp_energy = 10.0;
uniform float window_energy = 1.2;
uniform float pool_energy = 1.6;
// Share of the house's windows lit early in the evening (scaled by the hour as the city's are).
uniform float lit_ratio = 0.36;
// What the windows' glow keeps once they are under a pixel: spread over the whole wall at full
// strength, a far estate was a lit bar; a house that far is a few warm points, the lamps.
uniform float far_window_mean = 0.3;
global uniform vec4 sky_tint;
global uniform float lamp_factor;

varying vec3 tint;
varying float fade;
varying float rim;
varying flat int kind;
varying float variant;
varying vec3 local_pos;
varying vec3 box_size;
varying float lamp_gain;


float corner_height(vec2 xz, vec3 cam) {
	vec4 m;
	vec2 mg;
	float wet;
	float d;
	float lift = far_ground_lift(vec3(xz.x, plane_y, xz.y), cam, m, mg, wet, d);
	return lift - far_ground_sink(d, wet);
}


float plane_height(vec2 xz, vec3 cam) {
	vec2 g = (xz - (plane_origin - vec2(plane_half))) / plane_step;
	vec2 i = clamp(floor(g), vec2(0.0), vec2(round(2.0 * plane_half / plane_step) - 1.0));
	vec2 f = clamp(g - i, vec2(0.0), vec2(1.0));
	vec2 c0 = plane_origin - vec2(plane_half) + i * plane_step;
	float h01 = corner_height(c0 + vec2(0.0, plane_step), cam);
	float h10 = corner_height(c0 + vec2(plane_step, 0.0), cam);
	if (f.x + f.y < 1.0) {
		float h00 = corner_height(c0, cam);
		return h00 + f.x * (h10 - h00) + f.y * (h01 - h00);
	}
	float h11 = corner_height(c0 + vec2(plane_step), cam);
	return h11 + (1.0 - f.x) * (h01 - h11) + (1.0 - f.y) * (h10 - h11);
}


void vertex() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float code = INSTANCE_CUSTOM.g;
	float whole = floor(code + 0.002);
	variant = clamp(code - whole, 0.0, 0.999);
	int k = int(whole + 0.5);
	float real = k >= 8 ? 1.0 : 0.0;
	kind = k - (k >= 8 ? 8 : 0);
	float shift = 0.0;
	if (real < 0.5) {
		// The estate's centre and deck, from this part's origin and its offsets.
		vec2 centre = origin.xz - INSTANCE_CUSTOM.ba;
		float deck = origin.y - INSTANCE_CUSTOM.r;
		shift = plane_y + plane_height(centre, cam) - deck;
	}
	tint = COLOR.rgb;
	fade = COLOR.a;
	local_pos = VERTEX;
	box_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	// A MultiMesh instance's normals are turned by its basis, not its inverse transpose: divide
	// by the scale squared first so a flat slab's top still faces up (far_canopy.gdshader).
	NORMAL = normalize(NORMAL / max(box_size * box_size, vec3(1e-4)));
	lamp_gain = 1.0;
	rim = smoothstep(edge_start, edge_end, length(origin.xz - cam.xz));
	if (kind == 4) {
		// A lamp: nothing by day, and never smaller than lamp_min_angle of the view.
		float size = max(box_size.x, box_size.y);
		float depth = max(-(VIEW_MATRIX * vec4(origin + vec3(0.0, shift, 0.0), 1.0)).z, 0.1);
		float grow = max(1.0, depth * lamp_min_angle / max(size, 0.01));
		VERTEX *= grow;
		lamp_gain = max(1.0 / (grow * grow), lamp_floor);
		if (lamp_factor < 0.02) {
			fade = 0.0;
		}
	}
	if (fade < 0.004) {
		VERTEX = vec3(0.0);
	} else {
		VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(0.0, shift, 0.0);
	}
}


// 0..1 from two numbers (a window's or a cell's roll).
float roll(float a, float b) {
	return fract(sin(a * 12.9898 + b * 78.233 + variant * 437.585) * 43758.5453);
}


void fragment() {
	if (fade < 0.999) {
		float d = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (fade < d) {
			discard;
		}
	}
	vec3 albedo = tint;
	vec3 emit = vec3(0.0);
	float rough = 0.9;
	float spec = 0.3;
	// The face this fragment is on, in the box's own frame.
	vec3 an = abs(local_pos) * 2.0;
	bool top = local_pos.y > 0.499;
	bool side = !top && local_pos.y > -0.499;
	if (kind == 0) {
		// The pad: its top the garden (tint), its sides the retaining wall it stands on.
		if (side) {
			albedo = vec3(0.30, 0.28, 0.25);
			float course = fract(local_pos.y * box_size.y / 0.6);
			albedo *= mix(0.85, 1.0, smoothstep(0.0, 0.12, course));
		} else {
			// Mower stripes and a darker edge bed, faded to their mean under a pixel.
			vec2 m = local_pos.xz * box_size.xz;
			float px = max(fwidth(m.x), fwidth(m.y));
			float stripe = mix(step(0.5, fract(m.x / 3.2)) * 2.0 - 1.0, 0.0, smoothstep(0.6, 1.6, px));
			float edge = 1.0 - smoothstep(1.0, 2.2, min(box_size.x * (0.5 - abs(local_pos.x)), box_size.z * (0.5 - abs(local_pos.z))));
			albedo *= (1.0 + 0.07 * stripe) * mix(1.0, 0.55, edge);
		}
	} else if (kind == 1) {
		// The house: windows on the walls, lit in the evening.
		if (side) {
			bool along_x = an.z > an.x;
			float u = (along_x ? local_pos.x * box_size.x : local_pos.z * box_size.z);
			float v = (local_pos.y + 0.5) * box_size.y;
			float face = along_x ? (local_pos.z > 0.0 ? 0.0 : 1.0) : (local_pos.x > 0.0 ? 2.0 : 3.0);
			float col = floor(u / 2.6);
			float row = floor(v / 3.1);
			vec2 cell = vec2(fract(u / 2.6), fract(v / 3.1));
			float px = max(fwidth(u), fwidth(v));
			// Tall glass on the ground floor, punched windows above.
			float glass = step(0.14, cell.x) * step(cell.x, 0.86) * step(row < 0.5 ? 0.04 : 0.28, cell.y) * step(cell.y, 0.86);
			float share = row < 0.5 ? 0.62 : 0.4;
			float detail = 1.0 - smoothstep(0.35, 1.0, px / 2.6);
			float g = mix(share, glass, detail);
			// Some houses all lit, some nearly dark: a row of estates is not a row of identical bars.
			float ratio = lit_ratio * window_hour_scale() * mix(0.2, 1.7, fract(variant * 7.13 + 0.31));
			float lit = roll(col + face * 31.0, row) < ratio ? 1.0 : 0.0;
			lit = mix(ratio, lit, detail);
			vec3 warm = mix(vec3(1.0, 0.62, 0.30), vec3(1.0, 0.80, 0.55), roll(col, row + 7.0));
			albedo = mix(albedo, vec3(0.05, 0.06, 0.07), g * 0.85);
			rough = mix(rough, 0.2, g);
			emit = warm * window_energy * g * lit * lamp_factor * mix(far_window_mean, 1.0, detail);
		}
	} else if (kind == 3) {
		// The pool: turquoise by day, its underwater light after dark.
		albedo = vec3(0.04, 0.32, 0.42);
		rough = 0.06;
		spec = 0.6;
		emit = vec3(0.10, 0.62, 0.78) * pool_energy * lamp_factor;
	} else if (kind == 4) {
		albedo = vec3(0.0);
		vec3 c = mix(vec3(1.0, 0.68, 0.36), vec3(1.0, 0.86, 0.66), variant);
		emit = c * lamp_energy * lamp_gain * lamp_factor;
	}
	ALBEDO = cs_out(albedo) * (1.0 - rim);
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = cs_out(emit) * (1.0 - rim) + cs_out(cs_srgb_to_linear(sky_tint.rgb)) * rim;
}
