shader_type spatial;
// The tank of a hill home's pool, seen from inside the water (PoolUnder, scripts/world/pool_under.gd):
// the floor and the four walls, facing in, under the water sheet that hides them from above (the
// sheet is opaque: hill_pool.gdshader still paints the tank for a camera in the air). Glass mosaic
// with a waterline band, the caustic net and the walls' shadows, lit by hand (pool_tank.gdshaderinc).
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/pool_tank.gdshaderinc"

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 f = pt_frame(wpos + origin_shift);
	vec3 nf = pt_dir(normalize(wnrm));
	bool floor_face = nf.z > 0.5;
	vec2 st = floor_face ? f.xy : vec2(abs(nf.x) > 0.5 ? f.y : f.x, pt_y.x - f.z);
	float depth = floor_face ? -1.0 : pt_y.x - f.z;
	float fw = length(fwidth(wpos));
	ALBEDO = cs_out(pt_shade(f, nf, st, depth, fw, TIME));
}
