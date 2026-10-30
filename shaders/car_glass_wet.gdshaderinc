// Rain on a car's glass (wet-world): beads that build up while it rains, runs of water down the
// side glass, and on the windscreen the arcs the wipers keep clear (car_wipers.gdshaderinc).
// Included by car_glass.gdshader and car_glass_damage.gdshader after car_cabin.gdshaderinc.

#include "res://shaders/wet_surface.gdshaderinc"
#include "res://shaders/car_wipers.gdshaderinc"


// Water on the pane at mesh point `lp` (mesh normal `n`, `screen` the windscreen), `ms` metres a
// mesh unit, `px` metres a pixel, at time `t`. Darkens what is seen through it (`emission`),
// scatters the reflection a little (`rough`, `albedo`), and returns the beads' and runs' slope in
// mesh space for the caller to bend NORMAL by (xyz) and how much of the pane is water (w). Call only
// when ws_on().
vec4 glass_wet(vec3 lp, vec3 n, bool screen, float ms, float px, float t, inout vec3 albedo, inout float rough, inout vec3 emission) {
	float wet = ws_wet(0.25);
	vec3 tt;
	vec3 bb;
	ws_frame(n, tt, bb);
	vec3 pm = lp * ms;
	vec2 q = vec2(dot(pm, tt), dot(pm, bb));
	// How upright the pane is: on side glass the water runs and fewer beads sit.
	float upright = 1.0 - smoothstep(0.35, 0.8, abs(n.y));
	float clear = 1.0;
	if (screen) {
		float since = wiper_since(lp, t);
		// The beads come back over the cycle; a hard rain fills a swept arc in about a second.
		clear = smoothstep(0.0, 1.0, since * (0.35 + 1.1 * ws_rain()));
	}
	vec3 bead = ws_beads(q, 1.7, wet * mix(1.0, 0.7, upright) * clear, px);
	vec2 run = ws_runs(vec2(q.x, -q.y), 0.03, t, ws_rain() * mix(0.25, 0.85, upright) * clear, px);
	float cover = clamp(bead.x + run.x * 0.7, 0.0, 1.0);
	// A wet pane scatters what is behind it: the cabin seen through the beads is dimmer and
	// greyer, the water itself picks up a little of the sky.
	emission *= 1.0 - 0.45 * cover;
	// Each bead is a lens: the sky above it shows upside down in its lower half, the rim dark.
	float lens = clamp(0.55 - bead.z * 0.9, 0.0, 1.0) * bead.x;
	albedo += vec3(0.05, 0.055, 0.06) * lens + vec3(0.012) * run.x;
	rough = mix(rough, 0.16, cover * 0.4);
	return vec4(tt * (bead.y + run.y * 0.7) + bb * bead.z, cover);
}
