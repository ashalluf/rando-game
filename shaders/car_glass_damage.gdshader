shader_type spatial;
render_mode cull_disabled;

// The glass slot of a damaged car (CarDamage swaps it in the first time a window is hit, in
// place of the body's shared car_glass.gdshader). Opaque, like the intact glass, so a window that
// is gone is not a hole: it is drawn as the cabin seen through the empty frame - traced in the
// body's own space (car_cabin.gdshaderinc, the cabin the intact glass draws), so it has true
// parallax - with the far windows letting the day in above the door line, the seat backs and
// headrests cutting across them. What is still whole draws the cabin through its tint the way
// the intact glass does, under the cracks.
//
// The panes are the glass surface's connected pieces (CarCabin measures them once per model):
// an AABB and a mean normal each, smallest first, so a fragment finds its pane in a few tests.
// Side and rear glass is tempered - it crazes into small cubes on the first round and falls out
// on the next - and the windscreen is laminated, so it only collects spider webs.

#define CABIN_FIRE
#include "res://shaders/car_cabin.gdshaderinc"

// The model's own glass material.
uniform vec3 glass_albedo : source_color = vec3(0.14, 0.155, 0.175);
uniform float glass_roughness = 0.05;
uniform float glass_metallic = 0.0;
// Spider webs: xyz the hit, w the web's radius; crack_n xyz the glass normal there, w a seed.
uniform int crack_count = 0;
uniform vec4 cracks[12];
uniform vec4 crack_n[12];

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
	int pi = find_pane(lp, n);
	float state = 0.0;
	float kind = 0.0;
	if (pi >= 0) {
		state = pane_lo[pi].w;
		kind = pane_hi[pi].w;
	}
	if (burnt > 0.5) {
		state = 2.0;
	}
	float px = max(length(fwidth(lp)), 1e-5);
	vec3 alb = glass_albedo;
	float rough = glass_roughness;
	float metal = glass_metallic;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	vec3 tilt = vec3(0.0);
	// The model's glass has no clearcoat of its own.
	float cc = 0.0;

	if (state > 1.5 && pi >= 0) {
		// Gone. Tempered glass leaves a ragged row of cubes along the bottom seal of the frame.
		float remnant = 0.0;
		if (kind < 0.5) {
			float rim = pane_lo[pi].y + 0.012 + 0.03 * cd_noise3(lp * 55.0);
			remnant = 1.0 - smoothstep(rim - px, rim + px, lp.y);
		}
		if (kind > 1.5) {
			// A lamp cover: the dark, broken reflector behind it.
			alb = vec3(0.06, 0.06, 0.065);
			rough = 0.45;
			metal = 0.5;
			cc = 0.0;
		} else if (remnant > 0.5) {
			vec2 tl;
			vec3 t;
			vec3 b;
			cd_frame(n, t, b);
			float lines = cd_craze(vec2(dot(lp, t), dot(lp, b)), 0.011, px, tl);
			alb = mix(glass_albedo * 1.6 + 0.12, vec3(0.8), lines);
			rough = 0.2;
			tilt = (t * tl.x + b * tl.y) * 0.6;
		} else {
			vec3 to = lp - cam_local;
			float dist = length(to);
			emit = cabin_view(lp, to / max(dist, 1e-5), dist);
			alb = vec3(0.0);
			rough = 1.0;
			metal = 0.0;
			spec = 0.0;
			cc = 0.0;
		}
	} else {
		float lines = 0.0;
		if (state > 0.5) {
			// Crazed tempered glass: a frosted sheet of small cubes each catching the light
			// its own way.
			vec2 tl;
			vec3 t;
			vec3 b;
			cd_frame(n, t, b);
			lines = cd_craze(vec2(dot(lp, t), dot(lp, b)), 0.012, px, tl);
			// Milky where the cubes are too small to see one by one; each cube glints on its
			// own only up close (a tilt per sub-pixel cell is just noise).
			float resolved = smoothstep(2.5, 7.0, 0.012 / px);
			alb = mix(glass_albedo, vec3(0.46, 0.48, 0.5), mix(0.62, 0.42, resolved));
			rough = mix(0.3, 0.14, resolved);
			tilt = (t * tl.x + b * tl.y) * 0.5 * resolved;
		}
		for (int i = 0; i < crack_count && i < 12; i++) {
			vec2 facet;
			float web = cd_crack_web(lp, cracks[i].xyz, crack_n[i].xyz, cracks[i].w, crack_n[i].w, px, facet);
			if (web > 0.0 || dot(facet, facet) > 0.0) {
				vec3 t;
				vec3 b;
				cd_frame(crack_n[i].xyz, t, b);
				tilt += (t * facet.x + b * facet.y) * 0.18;
			}
			lines = max(lines, web);
		}
		// A crack scatters light, so it reads pale against the dark tint by day; at night it
		// only catches whatever lights it.
		alb = mix(alb, vec3(0.7, 0.72, 0.74), lines * 0.85);
		rough = mix(rough, 0.4, lines);
		// The cabin through it, as the intact glass draws it: hardly at all through a crazed
		// sheet, not through the cracks.
		vec3 to = lp - cam_local;
		float dist = length(to);
		emit = glass_view(lp, to / max(dist, 1e-5), n, pi, dist) * (state > 0.5 ? 0.15 : 1.0) * (1.0 - lines)
				* (1.0 - clamp(burnt * 2.0, 0.0, 1.0));
	}
	// Soot on whatever glass survives a fire.
	alb *= 1.0 - 0.8 * clamp(burnt * 2.0, 0.0, 1.0);

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = 0.03;
	float tl2 = length(tilt);
	if (tl2 > 1e-4) {
		vec3 tv = (VIEW_MATRIX * (MODEL_MATRIX * vec4(tilt, 0.0))).xyz;
		NORMAL = normalize(NORMAL + normalize(tv) * tl2);
	}
}
