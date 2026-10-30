shader_type spatial;
render_mode cull_disabled;

// The glass slot of every generated car body (CarCabin.glass_material(): one material per body
// model, shared by every car with nobody in it). Still opaque - no transparent pass, nothing to
// sort - but no longer a sealed dark shell: the model's own dark tinted glass reflects exactly as
// it did (the renderer's specular, the same albedo, roughness and metal), and over it the cabin
// behind the pane is emitted (car_cabin.gdshaderinc), traced in the body's own space so it has
// true parallax, dimmed by the pane's tint (the windscreen clearest, privacy glass in the back of
// a crossover, pickup or van dark) and by what Fresnel sends back as reflection. Whoever sits in
// the front is in the occupant uniforms (CarCabin.seat()): a car nobody is in wears the shared
// material, an occupied one its own copy. A damaged car swaps this for car_glass_damage.gdshader,
// which draws the same cabin.

#include "res://shaders/car_cabin.gdshaderinc"
#include "res://shaders/car_glass_wet.gdshaderinc"

// The model's own glass material.
uniform vec3 glass_albedo : source_color = vec3(0.14, 0.155, 0.175);
uniform float glass_roughness = 0.05;
uniform float glass_metallic = 0.0;

varying vec3 lp;
varying vec3 ln;
varying vec3 cam_local;


void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	cam_local = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
}


void fragment() {
	vec3 n = normalize(ln);
	vec3 to = lp - cam_local;
	float dist = length(to);
	int pane = find_pane(lp, n);
	vec3 emission = glass_view(lp, to / max(dist, 1e-5), n, pane, dist);
	vec3 albedo = glass_albedo;
	float rough = glass_roughness;
	if (ws_on()) {
		// Rain on the glass (car_glass_wet.gdshaderinc): beads, runs, the wipers' arcs.
		float ms = length(MODEL_MATRIX[0].xyz);
		float px = max(length(fwidth(lp)) * ms, 1e-5);
		bool screen = pane >= 0 && pane_hi[pane].w > 0.5 && pane_hi[pane].w < 1.5;
		vec3 slope = glass_wet(lp, n, screen, ms, px, TIME, albedo, rough, emission).xyz;
		vec3 sv = (VIEW_MATRIX * (MODEL_MATRIX * vec4(slope, 0.0))).xyz;
		float sl = length(slope);
		if (sl > 1e-4) {
			NORMAL = normalize(NORMAL + normalize(sv) * min(sl, 1.2) * 0.6);
		}
	}
	EMISSION = emission;
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = glass_metallic;
	SPECULAR = 0.5;
}
