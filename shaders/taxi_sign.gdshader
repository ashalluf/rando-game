shader_type spatial;
render_mode cull_back;

// The taxi's roof sign (road_taxi.glb's `taxi_sign` slot, Vehicle._part_material(): one material
// shared by every taxi). A translucent lightbox: "TAXI" in dark stroked capitals on the face to the
// front and the face to the back (read the right way round from either end), plain ends and top.
// By day the face is a warm cream plastic with a faint glow (on duty); after dark it is lit from
// inside by lamp_factor, the letters standing dark against it. The mesh has no UVs: everything is
// laid out in the body mesh's own space from the box tools/make_more_cars.py prints (TAXI SIGN).
// Colours in linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

// The lightbox in the body mesh's space (x across, y up, z along with the nose at -z).
uniform vec3 sign_center = vec3(0.0, 1.577, 0.42);
uniform vec3 sign_size = vec3(0.60, 0.165, 0.15);
// Linear albedos.
uniform vec3 face_color = vec3(0.80, 0.68, 0.36);
uniform vec3 letter_color = vec3(0.012, 0.011, 0.010);
// Emission: the face's light by day (on duty) and at night (times lamp_factor), linear.
uniform vec3 glow_color = vec3(1.0, 0.80, 0.42);
uniform float glow_day = 0.35;
uniform float glow_night = 3.2;
// Letter height and the stroke, as fractions of the box's height.
uniform float letter_height = 0.74;
uniform float stroke = 0.17;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Distance to "TAXI" in letter units: each letter 0.6 wide and 1 tall, 0.25 apart, the word
// centred on the origin.
float word(vec2 p) {
	p.x += 1.575;
	float d = 1e3;
	// T
	d = min(d, seg(p, vec2(0.0, 0.93), vec2(0.6, 0.93)));
	d = min(d, seg(p, vec2(0.3, 0.93), vec2(0.3, 0.0)));
	// A
	vec2 q = p - vec2(0.85, 0.0);
	d = min(d, seg(q, vec2(0.02, 0.0), vec2(0.3, 0.97)));
	d = min(d, seg(q, vec2(0.3, 0.97), vec2(0.58, 0.0)));
	d = min(d, seg(q, vec2(0.13, 0.36), vec2(0.47, 0.36)));
	// X
	q = p - vec2(1.7, 0.0);
	d = min(d, seg(q, vec2(0.03, 0.0), vec2(0.57, 1.0)));
	d = min(d, seg(q, vec2(0.03, 1.0), vec2(0.57, 0.0)));
	// I
	q = p - vec2(2.55, 0.0);
	d = min(d, seg(q, vec2(0.3, 0.0), vec2(0.3, 1.0)));
	return d;
}

void fragment() {
	vec3 q = lp - sign_center;
	vec3 n = normalize(ln);
	float letters = 0.0;
	if (abs(n.z) > 0.7) {
		// Facing the front (-z) the viewer's right is -x; facing the rear, +x.
		float u = n.z > 0.0 ? q.x : -q.x;
		float unit = sign_size.y * letter_height;
		vec2 p = vec2(u, q.y + unit * 0.5) / unit;
		float d = word(p) - stroke * 0.5;
		float aa = max(fwidth(d), 1e-4);
		letters = 1.0 - smoothstep(-aa, aa, d);
	}
	// The faces glow; the top less (it is the sign's lid), and a little darker toward the edges
	// where the box's bevel rolls off the light.
	float face = abs(n.y) > 0.7 ? 0.45 : 1.0;
	float edge = 1.0 - 0.35 * smoothstep(0.30, 0.5, max(abs(q.x) / sign_size.x, abs(q.y) / sign_size.y));
	vec3 albedo = mix(face_color, letter_color, letters);
	float lit = (glow_day + glow_night * lamp_factor) * face * edge * (1.0 - letters);
	ALBEDO = cs_out(albedo);
	EMISSION = cs_out(glow_color * lit);
	ROUGHNESS = 0.32;
	SPECULAR = 0.45;
}
