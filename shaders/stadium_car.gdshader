shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// The ballpark lot's far cars (StadiumNight.far_cars): a box car per filled stall past the 3D cars.
// Paint is the instance colour (sRGB numbers, arriving raw on both renderers); COLOR.a says the
// face: 0 flank, 0.25 bonnet / boot, 0.5 glass, 0.75 roof. After dark the car is lit by the same
// lot-pole pools ballpark_lot.gdshader paints on the ground (Ballpark.pole_at()'s grid, copied),
// tops more than flanks, so a car sits IN the pool instead of on top of it.

#include "res://shaders/ballpark_common.gdshaderinc"

global uniform vec3 origin_shift;

uniform float pool_energy = 0.22;
// Ballpark's copies (as ballpark_lot.gdshader).
uniform vec2 home = vec2(2008.0, -2778.0);
uniform vec2 fwd = vec2(-0.1117, -0.9937);
uniform vec2 right = vec2(0.9937, -0.1117);
uniform float lot_v0 = -260.0;
uniform float lot_u0 = -290.0;
uniform float module = 18.6;
uniform float stall_d = 5.7;
uniform float block_u = 84.0;

varying vec3 wpos;
varying float ly;
varying vec3 paint;
varying float face;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_shift;
	ly = VERTEX.y;
	// The instance colour multiplies the vertex colour; the vertex colour is white (rgb) here.
	paint = cs_srgb_to_linear(clamp(COLOR.rgb, vec3(0.0), vec3(1.0)));
	face = COLOR.a;
}

void fragment() {
	vec3 alb = paint;
	float rough = 0.3;
	float metal = 0.2;
	bool glass = face > 0.4 && face < 0.6;
	if (glass) {
		alb = vec3(0.012, 0.014, 0.018);
		rough = 0.08;
		metal = 0.0;
	}
	// The rocker, the bumpers' lower band and the wheels: dark.
	float low = 1.0 - smoothstep(0.34, 0.42, ly);
	alb = mix(alb, vec3(0.012), low);
	vec2 q = vec2(dot(wpos.xz - home, right), dot(wpos.xz - home, fwd));
	float pm = floor((q.y - lot_v0 - stall_d) / (module * 2.0) + 0.5);
	vec2 pole = vec2(lot_u0 + (floor((q.x - lot_u0 - block_u * 0.5) / block_u + 0.5) + 0.5) * block_u, lot_v0 + pm * module * 2.0 + stall_d);
	float d = length(q - pole);
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float up = mix(0.35, 1.0, clamp(wn.y, 0.0, 1.0));
	float pool = pool_energy * lamp_factor * exp(-d * d / 110.0);
	vec3 emit = vec3(1.0, 0.88, 0.7) * pool * (0.04 + alb * 1.5) * up;
	// The glass mirrors the pool's light as a sheen on the slope facing the pole.
	if (glass) {
		emit += vec3(1.0, 0.88, 0.7) * pool * 0.25 * up;
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
