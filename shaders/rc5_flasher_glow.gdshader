// The glow round a lit crossing flasher (RcRailCrossing.add_glow(), one quad a lamp, shown only
// while its lamp is lit): turned to face the camera, never under `min_px` across so a flasher a
// block away still reads as a flashing red point, its light a tight core and a soft skirt that
// reaches ZERO at the quad's edge (an additive tail would draw the quad on Forward+). Deep red,
// green held at 0.1 of red (AgX turns a bright red-heavy colour salmon pink). Brighter after dark
// (`lamp_factor`). Additive, so it writes a coverage alpha (additive_fog.gdshaderinc).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/additive_fog.gdshaderinc"

global uniform float lamp_factor;

uniform vec3 glow_color = vec3(1.0, 0.1, 0.02);
uniform float day_gain = 0.55;
uniform float night_gain = 1.3;
uniform float min_px = 9.0;
// Pulled toward the camera so the lamp's own hood never cuts it (metres).
uniform float pull = 0.25;
// The lens's radius as a share of the quad's half size.
uniform float lens_r = 0.27;

void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float depth = max(-c.z, 0.05);
	float vh = VIEWPORT_SIZE.y > 120.0 ? VIEWPORT_SIZE.y : 1080.0;
	float px = 2.0 * depth / (max(abs(PROJECTION_MATRIX[1][1]), 0.1) * vh);
	float size = length(MODEL_MATRIX[0].xyz);
	float grow = max(1.0, min_px * px / max(size, 1e-4));
	vec3 toc = normalize(-c);
	VERTEX = c + toc * pull + vec3(VERTEX.xy * size * min(grow, 6.0), 0.0);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	// The lens itself (r under ~0.27 of the quad) is the material's: the glow is the light round it,
	// so it rises from a faint fill over the lens to its peak at the lens's rim and falls away.
	float rim = max(r - lens_r, 0.0);
	float core = exp(-rim * rim * 40.0) * mix(0.25, 1.0, smoothstep(0.0, lens_r, r));
	float skirt = pow(max(1.0 - r, 0.0), 2.4) * 0.35;
	float g = (core + skirt) * mix(day_gain, night_gain, clamp(lamp_factor, 0.0, 1.0));
	// The hot centre leans toward orange (still red-heavy, never white).
	vec3 col = mix(glow_color, vec3(1.0, 0.22, 0.05), core * 0.3) * g;
	vec4 a = af_cover(cs_out(col));
	ALBEDO = a.rgb;
	ALPHA = a.a;
}
