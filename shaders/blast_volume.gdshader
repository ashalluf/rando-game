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
// Blast4 (fleet wave 5, "explosions-4"): 1 runs the fourth pass's field and light (every block it
// adds is behind `v4 > 0.5`, so 0 is the third pass bit for bit). The fireball lives on as the
// mushroom (`life` seconds: the cap rolls as a vortex ring, the stem feeds it, the smoke thins and
// pales), the noise is advected by a curl field and rolled round the ring's core, the soot is
// lit through three shadow taps, a dust ring runs out along the ground, and `gas` is a propane /
// petrol-vapour fireball (rounder, brighter, cleaner). `life` is the volume's whole life.
uniform float v4 = 0.0;
uniform float gas = 0.0;
uniform float life = 10.0;
// The vortex ring's roll (radians it has turned the noise by the end) and the curl warp (radii).
uniform float roll = 2.4;
uniform float curl = 0.14;
// The smoke's albedo once it has cooled and spread (linear), and the dust ring's.
uniform vec3 smoke_grey = vec3(0.10, 0.092, 0.084);
uniform vec3 dust = vec3(0.21, 0.19, 0.16);
// Light through thin smoke toward the sun, and the multiple-scattering lift in shadow.
uniform float forward = 0.6;
uniform float ms_lift = 0.3;
// The fires burning round it now (Blast3.push_fires(): xyz world, w = reach + strength / 2), so
// the smoke over a burning wreck or a fuel pool is lit orange from below long after the fireball
// is out - the look of a night blast - and the street lamps' glow on its underside after dark.
uniform vec4 fires[4];
uniform int fire_count = 0;
uniform vec3 fire_col = vec3(2.6, 0.9, 0.22);
uniform float fire_gain = 0.32;
uniform vec3 city_glow = vec3(0.0);
global uniform float lamp_factor;

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


// ---- Blast4 ---------------------------------------------------------------------------------

// The cap's centre height and the ball's radius at time tt (radii).
float cap_y4(float tt, float big) {
	return (0.3 + 1.05 * (1.0 - exp(-tt / 1.1)) + 0.13 * tt * (1.0 + 0.4 * gas)) * big;
}

float ball_r4(float tt, float big) {
	float grow = 1.0 - exp(-tt / (0.06 + 0.03 * fuel - 0.015 * gas));
	return (0.6 * grow + 0.1 * min(tt, 1.0) + 0.24 * (1.0 - exp(-tt / 3.5)) + 0.12 * gas * grow) * big;
}

// The mushroom's shape at q: x > 0 inside, y the core weight (for the heat), z the dust share.
vec3 shape4(vec3 q) {
	float big = 1.0 + 0.3 * fuel + 0.25 * gas;
	float R = ball_r4(t, big);
	float cy = cap_y4(t, big);
	vec3 d = q - vec3(0.0, cy, 0.0);
	// It flattens as it rises (squashed in y, spread in xz) and rolls into a ring: the top's middle
	// thins and the cap is a fat torus over its stem. A gas ball stays round longer.
	float flat_ = 1.0 + (0.6 - 0.3 * gas) * smoothstep(0.25, 2.4, t);
	float wide = 1.0 + 0.55 * smoothstep(0.6, 6.0, t);
	vec3 e = d * vec3(1.0 / wide, flat_, 1.0 / wide);
	float ball = 1.0 - length(e) / max(R, 0.02);
	float rr = 0.52 * R * wide;
	float tor = 1.0 - length(vec2(length(d.xz) - rr, d.y * flat_ * 1.05)) / max(0.7 * R, 0.02);
	float ringk = smoothstep(0.5, 2.6, t) * (1.0 - 0.6 * gas);
	ball = mix(ball, max(tor, ball - 0.3), ringk);
	// The skirt of the first instant, and the dust ring that runs out along the ground after it.
	float sk = mix(-1.0, 1.0 - length(q * vec3(1.0 / (1.25 * R + 0.05), 1.0 / (0.32 * R + 0.02), 1.0 / (1.25 * R + 0.05))), 1.0 - smoothstep(0.08, 0.45, t));
	float rg = (1.05 * (1.0 - exp(-t / 0.35)) + 0.07 * t) * big;
	float dth = 0.18 + 0.09 * min(t, 5.0);
	float dring = 1.0 - length(vec2((length(q.xz) - rg * 0.75) / (rg * 0.55 + 0.1), (q.y - dth * 0.6) / dth));
	dring = mix(-1.0, dring * 0.6, smoothstep(0.03, 0.15, t) * (1.0 - smoothstep(life * 0.3, life * 0.7, t)));
	// The stem: a wavering column from the ground up into the cap, thinning as it ages.
	vec2 sxz = q.xz + vec2(sin(q.y * 1.7 + t * 0.6 + seed.x), cos(q.y * 1.4 - t * 0.5 + seed.y)) * 0.06 * q.y;
	float sr = (0.3 + 0.08 * sqrt(t)) * R * (1.0 + 0.35 * smoothstep(0.0, 0.5, q.y) * (1.0 - smoothstep(0.5, cy, q.y))) + 0.04;
	float stem_on = step(0.0, q.y) * step(q.y, cy) * smoothstep(0.2, 0.55, t) * (1.0 - smoothstep(life * 0.6, life * 0.95, t));
	float stem = mix(-1.0, (1.0 - length(sxz) / sr) * (0.85 - 0.35 * gas), stem_on);
	float s = max(max(ball, sk), max(stem, dring));
	float dusty = smoothstep(0.0, 0.2, dring - max(ball, stem));
	return vec3(s, clamp(ball, 0.0, 1.0), dusty);
}

// The noise lookup, advected: rolled round the ring's core (the cap turns over: rising in the
// middle, out over the top, down its outside), then warped by the curl of a sinusoid potential
// (divergence-free, so the billows swirl rather than swell), riding up with the buoyant gas.
vec3 advect4(vec3 q) {
	float big = 1.0 + 0.3 * fuel + 0.25 * gas;
	float R = ball_r4(t, big);
	float cy = cap_y4(t, big);
	float rho = length(q.xz);
	vec2 dir = q.xz / max(rho, 1e-3);
	float rr = 0.52 * R * (1.0 + 0.55 * smoothstep(0.6, 6.0, t));
	vec2 v = vec2(rho - rr, q.y - cy);
	float spin = roll * (1.0 - exp(-t / 2.2)) * exp(-dot(v, v) / max(0.36 * R * R, 1e-3)) * smoothstep(0.0, 0.3 * R, rho);
	float cs = cos(spin);
	float sn = sin(spin);
	// Advected BACKWARD: the lookup turns against the flow.
	v = vec2(cs * v.x + sn * v.y, -sn * v.x + cs * v.y);
	vec3 qr = vec3(dir.x * (rr + v.x), cy + v.y, dir.y * (rr + v.x));
	float k1 = 2.3;
	float k2 = 5.1;
	float ph = t * 0.55;
	vec3 c1 = -k1 * vec3(cos(qr.z * k1 + seed.y + ph), cos(qr.x * k1 + seed.z - ph), cos(qr.y * k1 + seed.x + ph));
	vec3 c2 = -k2 * vec3(cos(qr.z * k2 + seed.z - ph * 1.7), cos(qr.x * k2 + seed.x + ph * 1.3), cos(qr.y * k2 + seed.y - ph * 1.5));
	float amt = curl * (0.25 + 0.75 * smoothstep(0.05, 1.5, t));
	return qr + (c1 / k1 * 0.7 + c2 / k2 * 0.3) * amt;
}

// Density (0..1), temperature (0..1) and dust share at q.
vec3 field4(vec3 q) {
	vec3 sh = shape4(q);
	if (sh.x < -0.75) {
		return vec3(0.0);
	}
	vec3 qa = advect4(q);
	float grow = 0.6 + 0.1 * min(t, 4.0);
	vec3 p = qa / grow * 0.62 + seed + vec3(0.0, -t * 0.32, 0.0);
	float n1 = noise_at(p);
	float n2 = noise_at(p * 2.6 + vec3(0.0, -t * 0.5, 0.0));
	float age = smoothstep(1.5, life, t);
	// Crisp cauliflower billows while it burns; softer as it spreads, but never a blur: a third
	// octave, curl-advected and sliding over time, cuts turrets into the silhouette only.
	float f = sh.x * 1.3 + (n1 - 0.5) * (1.7 - 0.25 * gas) + (n2 - 0.5) * (0.32 + 0.12 * age);
	float rim = 1.0 - smoothstep(0.05, 0.45, abs(f - 0.1));
	if (rim > 0.01) {
		float n3 = noise_at(p * 6.3 + vec3(t * 0.21, -t * 0.7, -t * 0.13));
		f += (n3 - 0.5) * 0.34 * rim * smoothstep(0.15, 1.0, t);
	}
	float crisp = mix(0.07, 0.24, smoothstep(0.4, 4.0, t));
	float dens = smoothstep(0.0, crisp, f) * mix(1.0, 0.45, age) * mix(1.0, 0.11, sh.z);
	float heat = heat_at(t) * (1.0 + 0.35 * gas);
	// A wide spread of temperature (white-hot crowns, orange, dull red, black soot in the creases):
	// a fireball reads by its contrast. As it cools its skin goes first: the fire is seen deeper in.
	float temp = clamp(heat * (0.5 + sh.y * 0.5 - 0.12 * gas + (n1 - 0.5) * (2.2 - 0.3 * gas) + (n2 - 0.5) * 1.4), 0.0, 1.0);
	temp *= mix(1.0, 0.25 + 0.75 * smoothstep(0.0, 0.55 + 0.25 * fuel, f), smoothstep(0.1, 0.55, t) * (1.0 - 0.5 * gas));
	// Fire still burning deep in the core while the cap rolls (a fuel ball's longer), seen in gaps.
	float deep = clamp(sh.y * 1.6 - 0.35, 0.0, 1.0) * exp(-max(t - 0.6, 0.0) / (0.9 + 1.3 * fuel)) * (0.55 + 0.6 * n1);
	temp = max(temp, deep * (1.0 - sh.z));
	return vec3(dens, temp * (1.0 - sh.z), sh.z);
}

// The density alone, coarse octave only (the shadow taps).
float field4_lo(vec3 q) {
	vec3 sh = shape4(q);
	if (sh.x < -0.75) {
		return 0.0;
	}
	vec3 qa = advect4(q);
	float grow = 0.6 + 0.1 * min(t, 4.0);
	vec3 p = qa / grow * 0.62 + seed + vec3(0.0, -t * 0.32, 0.0);
	float f = sh.x * 1.3 + (noise_at(p) - 0.5) * (1.7 - 0.5 * gas);
	float age = smoothstep(1.5, life, t);
	return smoothstep(0.0, mix(0.1, 0.26, smoothstep(0.4, 4.0, t)), f) * mix(1.0, 0.45, age);
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
	// Blast4: a forward-scattering lobe toward the sun (silver edges on thin smoke against it).
	float fwd_lobe = 0.0;
	if (v4 > 0.5) {
		float cv = dot(normalize(VERTEX * mat3(VIEW_MATRIX)), L);
		fwd_lobe = forward * pow(max(cv, 0.0), 6.0);
	}
	vec3 col = vec3(0.0);
	vec3 glow = vec3(0.0);
	float tr = 1.0;
	for (int i = 0; i < n; i++) {
		float f = f0 + (f1 - f0) * (float(i) + jit) / float(n);
		vec3 q = (o + dl * f) * half_r + centre_r;
		if (v4 > 0.5) {
			vec3 f4 = field4(q);
			float dens4 = f4.x * fade;
			if (dens4 <= 0.002) {
				continue;
			}
			float a4 = 1.0 - exp(-sigma * dens4 * ds_m);
			// Three taps toward the sun, further each time: a billow's sunny shoulder, its dark
			// belly, and the whole cap shading its stem.
			float od = field4_lo(q + L * 0.12) * 0.12 + field4_lo(q + L * 0.36) * 0.26 + field4_lo(q + L * 0.85) * 0.5;
			float t_sun4 = exp(-sigma * od * radius * 1.25);
			// What hangs over this point shades it from the sky (the cap's underside, the stem's
			// core): one tap straight up.
			float occ4 = exp(-sigma * field4_lo(q + vec3(0.0, 0.45, 0.0)) * radius * 0.35);
			// Multiple scattering: the shadowed side is not black, it is lit by the cloud itself.
			float lift = ms_lift * (1.0 - t_sun4) * (1.0 - 0.5 * f4.x);
			float up4 = clamp((q.y - 0.2) * 0.45 + 0.35, 0.0, 1.0);
			// The fire inside lights the soot round it from below while it burns.
			vec3 inner4 = blackbody(clamp(heat_now * 0.85, 0.0, 1.0)) * (0.1 + 0.22 * (1.0 - up4)) * heat_now;
			// Burnt fuel stays black (a car's smoke is the darkest there is); a rocket's greys out.
			vec3 alb4 = mix(soot * (1.0 - 0.35 * fuel), smoke_grey * (1.0 - 0.45 * fuel), smoothstep(0.8, 5.0, t) + 0.5 * gas * smoothstep(0.4, 2.0, t));
			alb4 = mix(alb4, dust, f4.z);
			// A sooty dark core and paler thin edges; warm brown low down near the fire, cooler grey
			// up in the cap.
			alb4 *= mix(1.45, 0.62, smoothstep(0.15, 0.95, f4.x)) * mix(vec3(1.1, 0.97, 0.84), vec3(0.94, 0.98, 1.05), up4);
			// The sky's light on smoke is mostly its brightness: the blue only tints the shadow side.
			vec3 sky4 = mix(vec3(dot(sky, vec3(0.2126, 0.7152, 0.0722))), sky, 0.45);
			// Sky from above (shaded by what hangs over it), the sunlit ground's bounce from below.
			vec3 ground4 = vec3(0.30, 0.27, 0.23) * 0.22 * sun * clamp(L.y * 1.5, 0.0, 1.0);
			vec3 amb4 = sky4 * sky_gain * mix(0.25, 1.0, up4) * mix(0.35, 1.0, occ4) * mix(0.6, 1.0, t_sun4) + (sky4 * 0.08 + ground4) * (1.0 - up4);
			vec3 wp = (MODEL_MATRIX * vec4(o + dl * f, 1.0)).xyz;
			vec3 fl = city_glow * lamp_factor * (1.0 - up4) / 6.0;
			for (int k = 0; k < 4; k++) {
				if (k >= fire_count) {
					break;
				}
				vec4 fr = fires[k];
				float reach = floor(fr.w);
				float fd = distance(fr.xyz, wp);
				// Lit from below: a puff over the fire takes more of it than one beside it.
				float below = clamp((wp.y - fr.y) / max(fd, 0.01) * 0.5 + 0.55, 0.1, 1.0);
				below *= below;
				fl += fire_col * fire_gain * mix(0.22, 1.0, night_factor) * fract(fr.w) * 2.0 * below / (1.0 + fd * fd / max(reach * reach * 0.3, 1.0));
			}
			fl = min(fl, vec3(2.4, 0.9, 0.25));
			vec3 lit4 = alb4 * (fl + sun * sun_gain * 1.35 * (t_sun4 + lift * 0.6 + fwd_lobe * (1.0 - f4.x) * t_sun4) + amb4 + inner4) * (1.0 - 0.85 * smoothstep(0.15, 0.5, f4.y));
			col += tr * a4 * lit4;
			glow += tr * a4 * blackbody(f4.y) * heat_gain * (1.0 + 0.4 * gas * smoothstep(0.04, 0.25, t));
			tr *= 1.0 - a4;
			if (tr < 0.01) {
				break;
			}
			continue;
		}
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
