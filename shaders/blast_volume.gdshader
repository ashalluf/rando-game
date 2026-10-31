shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled;

// The fireball as a VOLUME (Blast3, fleet wave 4 "explosions-3"). The old fireball was forty
// billboarded cards: from any angle a pile of flat discs, every billow the same size, the edges of
// the cards showing as soft circles. This marches the view ray through a box round the blast and
// integrates a density field made of the blast's shape (a ball growing in 70 ms, rising and
// flattening into a rolling cap, a skirt on the ground for the first instant, a stem under the
// cap) carved by two octaves of a tiling 3D noise that scrolls up through it, so the billows have
// real depth and parallax. Every sample is both LIGHT and SOOT: its temperature (the shape and the
// noise, cooling with time) emits a black-body colour - white-yellow in the core, orange, dull red,
// nothing - and what does not glow is sooty smoke lit by the sun (one tap of self-shadow toward
// it), the sky, and the fire inside it. Colours are linear on both renderers
// (color_space.gdshaderinc); the march stops at the scene's depth, so the road and the walls cut
// the volume where they really stand. The box is drawn by its back faces with no depth test, so
// it works with the camera inside it. Not on the web (Blast3 keeps the cards there).

#include "res://shaders/color_space.gdshaderinc"

global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform float night_factor;

uniform sampler3D noise3d : filter_linear, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

// The blast's clock (seconds since it went off) and how far it has faded (1 drawn, 0 gone).
uniform float t = 0.0;
uniform float fade = 1.0;
// Blast radius in metres; the field is laid out in radii.
uniform float radius = 9.0;
// 1 for a fuel (car) fireball: bigger, hotter for longer.
uniform float fuel = 0.0;
// The box in radii: its half extents and its centre over the blast point (the node's scale and
// offset, set by Blast3).
uniform vec3 half_r = vec3(1.5, 1.6, 1.5);
uniform vec3 centre_r = vec3(0.0, 1.3, 0.0);
// Where this blast reads the noise (a different place for every blast).
uniform vec3 seed = vec3(0.0);
// Steps through the box.
uniform int steps = 26;
// Extinction per metre at density 1, and the soot's albedo (linear).
uniform float sigma = 1.6;
uniform vec3 soot = vec3(0.045, 0.036, 0.03);
// Emission gain on the black-body colour.
uniform float heat_gain = 1.0;
// How long the fire glows (seconds, 1/e) before it is smoke.
uniform float cool_time = 0.85;
// Sun and sky on the soot.
uniform float sun_gain = 2.0;
uniform float sky_gain = 0.8;
// 1 draws the opacity as grey (tuning).
uniform int debug = 0;

varying vec3 v_local;
varying vec3 v_cam;


void vertex() {
	v_local = VERTEX;
	v_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}


// Black body from 0 (nothing) to 1 (white-hot), linear HDR. Green held at about half of red while
// bright: AgX turns a bright red-heavy colour salmon pink (CLAUDE.md, car fire).
vec3 blackbody(float k) {
	// Brightness climbs steeply with heat (a dull red flame is dim; the core is blinding): the
	// cooling stages must be DARK or AgX turns a bright red into salmon pink.
	vec3 c = vec3(0.16, 0.014, 0.0) * smoothstep(0.0, 0.3, k) * smoothstep(0.0, 0.3, k);
	c = mix(c, vec3(0.95, 0.27, 0.035), smoothstep(0.25, 0.55, k));
	c = mix(c, vec3(2.6, 1.1, 0.2), smoothstep(0.5, 0.8, k));
	c = mix(c, vec3(6.5, 4.8, 2.9), smoothstep(0.82, 1.0, k));
	return c;
}


// How hot the fire still is at time `tt`: held for its first instant, then cooling.
float heat_at(float tt) {
	float ct = cool_time * (1.0 + 0.8 * fuel);
	return exp(-max(tt - 0.06 - 0.15 * fuel, 0.0) / ct) * (1.0 + 0.5 * exp(-tt / 0.05));
}


float noise_at(vec3 p) {
	return texture(noise3d, p).r;
}


// The blast's shape at q (radii, origin at the blast point, y up): > 0 inside. Also returns the
// shape-only "core" weight (1 at the heart of the ball) for the temperature.
vec2 shape(vec3 q) {
	float grow = 1.0 - exp(-t / (0.07 + 0.03 * fuel));
	float big = 1.0 + 0.3 * fuel;
	float R = (0.6 * grow + 0.1 * t) * big;
	// The ball rises and flattens into a cap as the vortex ring forms.
	float cy = (0.3 + 1.05 * (1.0 - exp(-t / 1.15))) * big;
	vec3 c = vec3(0.0, cy, 0.0);
	vec3 d = q - c;
	float flat_ = 1.0 + 0.45 * smoothstep(0.2, 1.6, t);
	float ball = 1.0 - length(d * vec3(1.0, flat_, 1.0)) / max(R, 0.02);
	// The cap's doughnut: the middle of the top thins as the ring rolls (only once it has risen).
	float ring = smoothstep(0.35, 1.5, t) * 0.35 * exp(-dot(d.xz, d.xz) / max(R * R * 0.12, 1e-3)) * smoothstep(-0.1, 0.4, d.y / max(R, 0.02));
	ball -= ring;
	// The skirt: a flat disc on the ground for the first instant.
	float sk = mix(-1.0, 1.0 - length(q * vec3(1.0 / (1.25 * R + 0.05), 1.0 / (0.32 * R + 0.02), 1.0 / (1.25 * R + 0.05))), 1.0 - smoothstep(0.08, 0.45, t));
	// The stem under the cap: a narrow column from the ground up into it.
	float sr = 0.26 * R + 0.04;
	// (Every term is -1 where its gate is shut: a gate of 0 times the term would be 0, "on the edge",
	// everywhere, and the noise would fill the whole box.)
	float stem_on = step(0.0, q.y) * step(q.y, cy) * smoothstep(0.15, 0.5, t) * (1.0 - smoothstep(1.4, 2.6 + fuel, t));
	float stem = mix(-1.0, (1.0 - length(q.xz) / sr) * 0.8, stem_on);
	float s = max(max(ball, sk), stem);
	return vec2(s, clamp(ball, 0.0, 1.0));
}


// Density (0..1) and temperature (0..1) at q.
vec2 field(vec3 q) {
	vec2 sh = shape(q);
	if (sh.x < -0.75) {
		return vec2(0.0);
	}
	// The noise rides up with the fire and turns over: billows grow as the ball does.
	float grow = 0.6 + 0.12 * t;
	vec3 p = q / grow * 0.62 + seed + vec3(0.0, -t * 0.4, 0.0);
	float n1 = noise_at(p);
	float n2 = noise_at(p * 2.6 + vec3(0.0, -t * 0.55, 0.0));
	// Billows: the field pushed out where the noise is high, crisp at its edge (a fireball's
	// cauliflower surface is sharp, its smoke's is not).
	// Big billows from the coarse octave; the fine one only roughens their edges.
	float f = sh.x * 1.3 + (n1 - 0.5) * 1.7 + (n2 - 0.5) * 0.22;
	float crisp = mix(0.08, 0.3, smoothstep(0.5, 2.2, t));
	float dens = smoothstep(0.0, crisp, f);
	float heat = heat_at(t);
	// The whole surface burns at first (what you see of a young fireball is fire), hottest on the
	// billows' crowns and in the heart, sooty in the creases; as it cools the creases go first.
	float temp = clamp(heat * (0.57 + sh.y * 0.4 + (n1 - 0.5) * 1.5 + (n2 - 0.5) * 1.2), 0.0, 1.0);
	return vec2(dens, temp);
}


void fragment() {
	vec3 o = v_cam;
	vec3 dl = v_local - o;
	// Entry into the box [-1, 1]^3 along the fraction f of the segment camera -> back face.
	vec3 inv = 1.0 / dl;
	vec3 t1 = (-1.0 - o) * inv;
	vec3 t2 = (1.0 - o) * inv;
	vec3 tmin = min(t1, t2);
	float f0 = max(max(max(tmin.x, tmin.y), tmin.z), 0.0);
	float f1 = 1.0;
	// Stop at the scene (VERTEX is the back face in view space; the scene's depth on the same ray).
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 behind = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, depth) * 2.0 - 1.0, 1.0);
#else
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
#endif
	behind.xyz /= behind.w;
	f1 = min(f1, behind.z / min(VERTEX.z, -1e-4));
	if (f1 <= f0 || fade <= 0.001) {
		discard;
	}
	int n = max(steps, 4);
	float seg = (f1 - f0) * length(VERTEX);
	float ds_m = seg / float(n);
	// Interleaved gradient noise on the start, so the steps' bands become grain (TAA resolves it).
	float jit = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)) + float(int(TIME * 60.0) % 64) * 0.618));
	vec3 L = normalize(sun_direction);
	float day = 1.0 - night_factor;
	vec3 sun = mix(vec3(1.0, 0.55, 0.3), vec3(1.0, 0.95, 0.88), smoothstep(0.0, 0.35, L.y)) * smoothstep(-0.05, 0.08, L.y) * day;
	vec3 sky = cs_srgb_to_linear(sky_tint.rgb);
	float heat_now = heat_at(t);
	vec3 col = vec3(0.0);
	vec3 glow = vec3(0.0);
	float tr = 1.0;
	for (int i = 0; i < n; i++) {
		float f = f0 + (f1 - f0) * (float(i) + jit) / float(n);
		vec3 q = (o + dl * f) * half_r + centre_r;
		vec2 dt = field(q);
		float dens = dt.x * fade;
		if (dens <= 0.002) {
			continue;
		}
		float a = 1.0 - exp(-sigma * dens * ds_m);
		// Soot lit by the sun through the rest of the cloud (one tap toward it), the sky from
		// above, and the fire inside it on the side toward the core.
		float sh_d = field(q + L * 0.32).x;
		float t_sun = exp(-sigma * sh_d * 0.32 * radius * 1.4);
		float up = clamp(q.y * 0.5 + 0.3, 0.0, 1.0);
		vec3 inner = blackbody(clamp(heat_now * 0.85, 0.0, 1.0)) * 0.35 * heat_now;
		// Burning gas shows its own light, not the sun's: the soot's lit share goes as it heats,
		// or a dim red flame plus sunlit grey soot came out salmon pink.
		vec3 lit = soot * (sun * sun_gain * t_sun + sky * sky_gain * mix(0.45, 1.0, up) + inner) * (1.0 - 0.85 * smoothstep(0.15, 0.5, dt.y));
		vec3 emit = blackbody(dt.y) * heat_gain;
		col += tr * a * lit;
		glow += tr * a * emit;
		tr *= 1.0 - a;
		if (tr < 0.01) {
			break;
		}
	}
	float alpha = 1.0 - tr;
	if (alpha < 0.002) {
		discard;
	}
	// The soot is an albedo (handed over in the renderer's space); the fire's light is HDR numbers
	// taken raw on both renderers, as fire_puff.gdshader's ramp is: through the sRGB curve on
	// Compatibility its weak channels were lifted and every orange went salmon.
	ALBEDO = cs_out(col / alpha) + glow / alpha;
	ALPHA = clamp(alpha, 0.0, 1.0);
	if (debug == 1) {
		ALBEDO = vec3(alpha);
		ALPHA = 1.0;
	}
}
