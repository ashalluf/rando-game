shader_type spatial;
render_mode cull_back;

// The reservoir's dam, its towers, spillway, lamps and trail (LandmarkReservoir). One material for
// the whole structure; what each face is rides in its vertex colour (reservoir_concrete.gdshaderinc,
// which has the conventions and the concrete). Works in LINEAR on both renderers.

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/reservoir_concrete.gdshaderinc"

// How bright the lanterns burn after dark (linear emission).
uniform float lamp_energy = 5.0;
uniform vec3 lamp_color = vec3(1.0, 0.62, 0.28);


void fragment() {
	int kind = int(round(COLOR.a * 16.0));
	vec2 uv = UV;
	float face = COLOR.g;
	vec3 tint = vec3(COLOR.r, 1.0, COLOR.b);
	vec3 alb;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	if (kind == K_FACE || kind == K_TRIM) {
		vec4 c = rc_concrete(uv, face, kind == K_TRIM ? 1.0 : 0.0);
		alb = c.rgb;
		rough = c.a;
	} else if (kind == K_ROAD) {
		// Old patched asphalt between kerbs, oil down the middle of the lane, dust at the edges.
		float n = rc_fbm(uv * 0.35);
		alb = vec3(0.085, 0.08, 0.072) * mix(0.8, 1.2, n) * mix(0.9, 1.1, rc_noise(uv * 3.0));
		float patch = smoothstep(0.62, 0.66, rc_noise(uv * 0.08 + 4.0));
		alb = mix(alb, vec3(0.035, 0.035, 0.036), patch);
		alb *= 1.0 - 0.45 * road_wetness;
		rough = mix(0.88, 0.25, road_wetness);
	} else if (kind == K_DARK) {
		alb = vec3(0.012, 0.012, 0.011);
		rough = 0.9;
	} else if (kind == K_METAL) {
		// Cast iron painted a deep green-black, chipped and rusty on the edges of the bases.
		float chip = smoothstep(0.7, 0.8, rc_noise(uv * 6.0));
		alb = mix(vec3(0.018, 0.026, 0.02), vec3(0.09, 0.05, 0.03), chip * 0.6);
		rough = mix(0.45, 0.8, chip);
		metal = 0.35;
	} else if (kind == K_LAMP) {
		// Ribbed glass: milky by day, the lamp after dark.
		float rib = 0.85 + 0.15 * sin(uv.x * 60.0);
		alb = vec3(0.55, 0.52, 0.45) * rib;
		rough = 0.25;
		emit = lamp_color * lamp_energy * smoothstep(0.05, 0.6, lamp_factor) * rib;
	} else if (kind == K_ROOF) {
		// Copper gone to verdigris, darker in the ribs' shade and streaked.
		float s = rc_fbm(vec2(uv.x * 2.0, uv.y * 0.4));
		alb = mix(vec3(0.07, 0.17, 0.13), vec3(0.13, 0.25, 0.19), s) * mix(0.75, 1.05, rc_noise(uv * 4.0));
		rough = 0.6;
	} else if (kind == K_GAUGE) {
		// A staff gauge: white enamel, a black tick every 0.1 m and a long one every metre, and
		// E-shaped blocks of the old pattern every half metre.
		float y = uv.y;
		float tick = rc_lines(y, 0.1, 0.012);
		float metre = rc_lines(y, 1.0, 0.05);
		float block = step(0.5, fract(y * 2.0)) * step(abs(uv.x - 0.25), 0.08) * step(fract(y * 10.0), 0.5);
		float mark = max(max(tick * step(uv.x, 0.18), metre), block);
		alb = mix(vec3(0.75, 0.74, 0.7), vec3(0.01), mark);
		// Below the water a green slime.
		alb = mix(alb, vec3(0.04, 0.08, 0.04), smoothstep(res_level + 0.05, res_level - 0.15, y));
		rough = 0.4;
	} else if (kind == K_TRAIL) {
		// Decomposed granite, compacted: tan, gritty, darker in the wheel ruts of service trucks.
		float g = rc_noise(uv * 7.0) * 0.5 + rc_noise(uv * 23.0) * 0.5;
		float across = abs(fract(uv.y) - 0.5);
		alb = vec3(0.30, 0.25, 0.18) * mix(0.82, 1.12, g) * mix(0.9, 1.05, rc_fbm(uv * 0.2));
		alb *= 1.0 - 0.1 * smoothstep(0.3, 0.2, across) * smoothstep(0.1, 0.18, across);
		alb *= 1.0 - 0.35 * road_wetness;
		rough = 0.95;
	} else if (kind == K_CHUTE) {
		vec4 c = rc_concrete(uv, 0.5, 0.0);
		// Dark water stains and algae in patches down the chute.
		alb = c.rgb * mix(1.0, 0.5, smoothstep(0.4, 0.8, rc_fbm(uv * vec2(0.4, 0.05))) * 0.8);
		rough = c.a;
	} else if (kind == K_GLASS) {
		alb = vec3(0.02, 0.025, 0.028);
		rough = 0.12;
		metal = 0.2;
		emit = vec3(1.0, 0.7, 0.4) * 0.8 * smoothstep(0.3, 0.9, lamp_factor) * step(0.55, rc_hash(floor(uv * 0.8)));
	} else {
		// Brass: the gauge house's plaques and the tower's finial.
		alb = vec3(0.35, 0.25, 0.1) * mix(0.7, 1.0, rc_noise(uv * 8.0));
		rough = 0.4;
		metal = 0.8;
	}
	ALBEDO = cs_out(alb * tint);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
