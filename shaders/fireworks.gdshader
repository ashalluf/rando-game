shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

// Fireworks' stars and rising shells (scripts/world/fireworks.gd): ONE mesh of FW_SLOTS x
// (FW_STARS + FW_TRAIL) quads per show site, every one placed HERE from the show clock (`now`)
// and the show's seed through the plan in fireworks.gdshaderinc - nothing per star or shell runs
// on the CPU. UV2.x is the slot, UV2.y the quad in it (a star under FW_STARS, else a piece of the
// rising shell's trail), UV the corner. Each live quad is a streak in view space from where the
// star was `tail` seconds ago to where it is, at least `min_px` pixels wide (thinner stars give
// up brightness instead, so a burst a kilometre off does not shimmer). A quad with nothing to draw
// collapses behind the camera. Additive, unlit, works the same on Compatibility. Colours linear.

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/fireworks.gdshaderinc"

/// Show seconds (Fireworks pushes it every frame; it stops with the game).
uniform float now = 0.0;
uniform int show_seed = 1;
/// The launch line (unit, xz) and its length (metres), and the break heights over the site.
uniform vec2 line_dir = vec2(0.0, 1.0);
uniform float spread = 180.0;
uniform float h_min = 150.0;
uniform float h_max = 280.0;
/// Wind (m/s, xz) the stars drift on.
uniform vec2 wind = vec2(2.0, 0.6);
/// Radians a pixel covers (Fireworks pushes it from the camera; VIEWPORT_SIZE is not
/// dependable in a vertex stage here).
uniform float px_angle = 0.0012;
uniform float min_px = 1.6;
/// Star radius (metres) and brightness.
uniform float star_radius = 1.0;
uniform float brightness = 8.0;
/// 0..1 fades the whole show (in and out at the ends of its window).
uniform float strength = 1.0;
/// Distance (metres) over which the night air takes half the light.
uniform float haze = 6500.0;

const float HALO = 2.4;

varying vec3 v_color;
varying float v_alpha;
varying float v_len;


vec3 fw_hidden() {
	return vec3(0.0, 0.0, 10.0);
}


void vertex() {
	int s = int(UV2.x + 0.5);
	int q = int(UV2.y + 0.5);
	int now_bin = int(floor(now / FW_BIN));
	int b = fw_slot_bin(now_bin, s, FW_SLOTS);
	vec2 tm;
	vec3 off;
	vec3 burst;
	int type;
	int c1;
	int c2;
	float size;
	bool live = fw_shell(show_seed, b, normalize(line_dir), spread, h_min, h_max, tm, off, burst, type, c1, c2, size);
	vec3 head = vec3(0.0);
	vec3 tail = vec3(0.0);
	vec3 col = vec3(0.0);
	float amt = 0.0;
	float radius = star_radius;
	float tail_fade = 1.0;
	uint k = fw_key(show_seed, b);
	if (live && strength > 0.001) {
		float t = now - tm.x;
		float rise = tm.y - tm.x;
		if (q < FW_STARS) {
			float a = now - tm.y;
			float life = FW_LIFE[type] * mix(0.85, 1.12, fw_roll(k, 15u));
			if (a >= 0.0 && a < life) {
				vec3 p;
				vec3 v;
				fw_star(type, q, k, size, a, wind, p, v);
				head = burst + p;
				float tl = min(FW_TAIL[type], a);
				vec3 p0;
				vec3 v0;
				fw_star(type, q, k, size, a - tl, wind, p0, v0);
				tail = burst + p0;
				float u = a / life;
				// Bright at the break, holding, then dying fast; a willow burns down slowly.
				float fade = type == FW_WILLOW ? (1.0 - smoothstep(0.35, 1.0, u)) : (1.0 - smoothstep(0.55, 1.0, u));
				amt = (0.55 + 0.45 * exp(-a * 3.0)) * fade;
				vec3 base = FW_COLORS[c1];
				if (type == FW_WILLOW) {
					base = FW_WILLOW_COLOR;
					// Glitter: the charcoal tail twinkles as it hangs.
					amt *= 0.75 + 0.5 * fw_roll(uint(q) + 977u * uint(floor(a * 18.0)), k & 1023u);
					radius *= 0.8;
				} else if (type == FW_STROBE) {
					base = FW_STROBE_COLOR;
					// Each star blinks on its own beat once the break has spread.
					float beat = fw_roll(uint(q) * 131u + uint(floor(a * 13.0)), k & 4095u);
					amt *= a < 0.35 ? 1.0 : step(0.55, beat) * 1.6;
				} else if (type == FW_PEONY && u > 0.4) {
					// A two-colour peony changes colour half way.
					base = mix(base, FW_COLORS[c2], smoothstep(0.4, 0.5, u));
				}
				if (type == FW_CROSSETTE && a < FW_SPLIT) {
					// Four stars ride as one comet until the split.
					amt *= 0.25;
				}
				// The first instant of a break is white-hot.
				col = mix(vec3(1.0, 0.93, 0.8), base, smoothstep(0.0, 0.18, a));
				radius *= type == FW_PEONY ? 1.15 : 1.0;
			}
		} else {
			int j = q - FW_STARS;
			if (j == FW_TRAIL - 1) {
				// The mortar's flash on the barge or the ground, for an instant.
				if (t >= 0.0 && t < 0.18) {
					head = off + vec3(0.0, 3.0, 0.0);
					tail = off + vec3(0.0, 0.5, 0.0);
					col = vec3(1.0, 0.62, 0.25);
					amt = 2.2 * (1.0 - t / 0.18);
					radius = 4.0;
				}
			} else {
				// The shell climbing: its head, and a falling tail of gold sparks.
				float ts = t - float(j) * 0.07;
				if (t >= 0.0 && t < rise && ts >= 0.0) {
					vec3 p = fw_rise_point(off, burst, rise, ts);
					float age = float(j) * 0.07;
					vec3 jit = (vec3(fw_roll(k, 60u + uint(j)), fw_roll(k, 70u + uint(j)), fw_roll(k, 80u + uint(j))) - 0.5) * 2.5 * float(j);
					head = p + jit + vec3(0.0, -4.9 * age * age, 0.0);
					tail = fw_rise_point(off, burst, rise, max(ts - 0.06, 0.0)) + jit;
					col = j == 0 ? vec3(1.0, 0.75, 0.42) : vec3(1.0, 0.5, 0.14);
					amt = j == 0 ? 1.2 : 0.7 * (1.0 - float(j) / float(FW_TRAIL));
					radius = j == 0 ? 0.6 : 0.35;
				}
			}
		}
	}
	if (amt <= 0.0) {
		VERTEX = fw_hidden();
	} else {
		vec3 hv = (MODELVIEW_MATRIX * vec4(head, 1.0)).xyz;
		vec3 tv = (MODELVIEW_MATRIX * vec4(tail, 1.0)).xyz;
		float dist = max(-hv.z, 0.1);
		float r_min = dist * px_angle * min_px * 0.5;
		float r = max(radius, r_min);
		// What the widening adds, the star gives back in brightness.
		amt *= radius / r;
		// The quad holds the star's glow too: HALO times its radius.
		r *= HALO;
		vec2 ax = hv.xy - tv.xy;
		float len = length(ax);
		ax = len > 1e-4 ? ax / len : vec2(0.0, 1.0);
		vec2 side = vec2(-ax.y, ax.x);
		vec2 c = UV * 2.0 - 1.0;
		// y: -1 the tail end, +1 the head end; both ends rounded off by the radius.
		vec3 base = c.y < 0.0 ? tv : hv;
		VERTEX = base + vec3(side * c.x * r + ax * c.y * r, 0.0);
		v_len = len / r;
		v_color = col;
		v_alpha = amt * brightness * strength * exp(-0.693 * dist / haze);
	}
}


void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	// A capsule round the streak from its tail (0) to its head (v_len), in units of the quad's
	// half width: the star is 1 / HALO of it and a faint glow fills the rest, which is most of
	// what a firework is on a renderer without bloom.
	float y = (c.y + 1.0) * 0.5 * (v_len + 2.0) - 1.0;
	float dy = y - clamp(y, 0.0, v_len);
	float d2 = c.x * c.x + dy * dy;
	float x2 = d2 * HALO * HALO;
	float across = exp(-x2 * 1.4) + 0.10 * exp(-d2 * 3.0);
	// The head burns brightest; the tail fades back along the streak.
	float along = v_len > 0.01 ? mix(0.12, 1.0, clamp(y / v_len, 0.0, 1.0)) : 1.0;
	float core = exp(-x2 * 6.0) * along;
	vec3 col = mix(v_color, vec3(1.0, 0.96, 0.9), core * 0.55);
	ALBEDO = cs_out(col * v_alpha * across * along);
}
