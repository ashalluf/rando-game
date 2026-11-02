shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Fireworks' smoke (scripts/world/fireworks.gd): every break leaves a few puffs that grow, thin
// and drift down the wind for FW_SMOKE_LIFE seconds. ONE mesh of FW_SMOKE_SLOTS x puffs quads,
// placed here from the show clock through the same plan as the stars (fireworks.gdshaderinc), so
// the smoke hangs exactly where each shell broke. UV2.x the slot, UV2.y the puff. Lit by hand: a
// dim night grey, the colour of its own shell while that is still burning inside it, and the
// show's current flash (`flash`, Fireworks' light colour x energy) - that is what makes a smoky
// finale glow. Linear colours, color_space.gdshaderinc for each renderer.

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/fireworks.gdshaderinc"

global uniform vec3 sky_tint;

uniform float now = 0.0;
uniform int show_seed = 1;
uniform vec2 line_dir = vec2(0.0, 1.0);
uniform float spread = 180.0;
uniform float h_min = 150.0;
uniform float h_max = 280.0;
uniform vec2 wind = vec2(2.0, 0.6);
uniform float strength = 1.0;
uniform float puffs = 4.0;
uniform sampler2D puff_tex : source_color, filter_linear_mipmap;
/// The show's light this frame (linear colour x level) and where it is (site frame).
uniform vec3 flash = vec3(0.0);
uniform vec3 flash_at = vec3(0.0, 200.0, 0.0);
/// The smoke's own colour and its opacity when fresh.
uniform vec3 smoke_color = vec3(0.020, 0.021, 0.024);
uniform float density = 0.30;

varying vec3 v_light;
varying float v_alpha;
varying float v_rot;


void vertex() {
	int s = int(UV2.x + 0.5);
	int p = int(UV2.y + 0.5);
	int now_bin = int(floor(now / FW_BIN));
	int b = fw_slot_bin(now_bin, s, FW_SMOKE_SLOTS);
	vec2 tm;
	vec3 off;
	vec3 burst;
	int type;
	int c1;
	int c2;
	float size;
	bool live = fw_shell(show_seed, b, normalize(line_dir), spread, h_min, h_max, tm, off, burst, type, c1, c2, size);
	float a = now - tm.y;
	uint k = fw_key(show_seed, b);
	if (!live || a < 0.0 || a > FW_SMOKE_LIFE || strength <= 0.001) {
		VERTEX = vec3(0.0, -1e5, 0.0);
		v_alpha = 0.0;
		v_light = vec3(0.0);
		v_rot = 0.0;
	} else {
		float u = a / FW_SMOKE_LIFE;
		vec3 d = normalize(vec3(fw_roll(k, 300u + uint(p)), fw_roll(k, 310u + uint(p)), fw_roll(k, 320u + uint(p))) - 0.5);
		// The puffs spread over the break's own size, then sink a little and go with the wind.
		float reach = FW_V0[type] / FW_DRAG[type] * size * 0.55;
		vec3 centre = burst + d * reach * (1.0 - exp(-a * 1.5)) + vec3(wind.x, -0.6, wind.y) * a;
		float r = (10.0 + 30.0 * sqrt(u)) * size;
		vec2 corner = UV * 2.0 - 1.0;
		vec3 right = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[0].xyz, 0.0)).xyz;
		vec3 up = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[1].xyz, 0.0)).xyz;
		VERTEX = centre + (right * corner.x + up * corner.y) * r;
		v_alpha = density * strength * smoothstep(0.0, 0.08, u) * pow(1.0 - u, 1.6) * (type == FW_WILLOW ? 1.4 : 1.0);
		vec3 own = type == FW_WILLOW ? FW_WILLOW_COLOR : (type == FW_STROBE ? FW_STROBE_COLOR : FW_COLORS[c1]);
		float burn = exp(-a * 1.3) * 1.6;
		float lit = 1.0 / (1.0 + pow(distance(centre, flash_at) / 140.0, 2.0));
		v_light = smoke_color + cs_srgb_to_linear(sky_tint) * 0.05 + own * burn * 0.35 + flash * lit * 0.05;
		v_rot = fw_roll(k, 330u + uint(p)) * 6.2832 + a * 0.05;
	}
}


void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float cr = cos(v_rot);
	float sr = sin(v_rot);
	vec2 uv = vec2(c.x * cr - c.y * sr, c.x * sr + c.y * cr) * 0.5 + 0.5;
	vec4 tex = texture(puff_tex, uv);
	float edge = 1.0 - smoothstep(0.55, 1.0, length(c));
	float shade = cs_in(tex.rgb).r * 1.6;
	ALBEDO = cs_out(v_light * shade);
	ALPHA = clamp(v_alpha * tex.a * edge, 0.0, 1.0);
}
