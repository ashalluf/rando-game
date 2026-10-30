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

// The model's own glass material.
uniform vec3 glass_albedo : source_color = vec3(0.14, 0.155, 0.175);
uniform float glass_roughness = 0.05;
uniform float glass_metallic = 0.0;

// Road dust dried on the windscreen outside the two wipers' sweeps (CarDetail; 0 is clean).
uniform float screen_dust = 0.0;
global uniform float road_wetness;

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
	int pi = find_pane(lp, n);
	EMISSION = glass_view(lp, to / max(dist, 1e-5), n, pi, dist);
	ALBEDO = glass_albedo;
	ROUGHNESS = glass_roughness;
	METALLIC = glass_metallic;
	SPECULAR = 0.5;
	if (screen_dust > 0.0 && pi >= 0 && pane_hi[pi].w > 0.5 && pane_hi[pi].w < 1.5) {
		// The windscreen in its own plane: u across, v up the glass from its foot.
		vec3 lo = pane_lo[pi].xyz;
		vec3 hi = pane_hi[pi].xyz;
		// The foot is the low edge at the end the pane faces (its normal leans forward).
		float foot_z = pane_n[pi].z < 0.0 ? lo.z : hi.z;
		float top_z = pane_n[pi].z < 0.0 ? hi.z : lo.z;
		vec3 up = normalize(vec3(0.0, hi.y - lo.y, top_z - foot_z));
		float tall = length(vec2(hi.y - lo.y, top_z - foot_z));
		float wide = hi.x - lo.x;
		vec2 p = vec2(lp.x - lo.x, dot(lp - vec3(lp.x, lo.y, foot_z), up));
		// Two blades parked along the foot, pivots at a quarter and three fifths of the width,
		// sweeping up through about 150 degrees; what they reach is wiped, the rest keeps a film.
		float wiped = 0.0;
		for (int k = 0; k < 2; k++) {
			vec2 pv = vec2(wide * (k == 0 ? 0.24 : 0.62), -0.03);
			float reach = min(tall * 0.95, wide * 0.46);
			vec2 d = p - pv;
			float r = length(d);
			float an = atan(d.y, k == 0 ? d.x : -d.x);
			float arc = smoothstep(-0.05, 0.08, an) * (1.0 - smoothstep(2.55, 2.75, an));
			wiped = max(wiped, arc * smoothstep(reach + 0.01, reach - 0.03, r) * smoothstep(0.06, 0.12, r));
		}
		float dn = fract(sin(dot(floor(lp * 260.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float edge = smoothstep(0.0, 0.06, min(p.y, tall - p.y));
		// The dust the blades push ahead of them piles up in a thin ridge along each sweep's edge.
		float film = screen_dust * (1.0 - wiped * 0.9 + 0.6 * wiped * (1.0 - wiped) * 4.0) * (0.75 + 0.25 * dn) * (1.0 - 0.8 * road_wetness);
		film *= 0.6 + 0.4 * (1.0 - edge);
		film = clamp(film, 0.0, 1.0);
		ALBEDO = mix(ALBEDO, vec3(0.42, 0.39, 0.34), film * 0.7);
		ROUGHNESS = mix(ROUGHNESS, 0.6, film);
		SPECULAR = 0.5 * (1.0 - film * 0.5);
		EMISSION *= 1.0 - film * 0.7;
	}
}
