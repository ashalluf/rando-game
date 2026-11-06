// A car's windscreen wipers (CarWipers, scripts/vehicles/car_wipers.gd), shared by the blades
// themselves (car_wiper.gdshader, which turns them) and the glass (car_glass.gdshader /
// car_glass_damage.gdshader via car_glass_wet.gdshaderinc, which clears the beads where they last
// passed). Both work out the same angle from TIME, so the arc the blade sweeps is the arc the beads
// are gone from. Everything is in the BODY MESH's space (the blades are a child of the glass mesh
// with no transform of their own); the frame, pivots and reach are per body type, the phase per
// car (four shared buckets, CarWipers.PHASES), `wipers_on` 1 on a car somebody drives.
//
// Needs wet_surface.gdshaderinc included first (ws_rain()).

uniform float wipers_on = 0.0;
uniform float wiper_phase = 0.0;
// The windscreen's frame in mesh space: across (u), up the glass (v), out of it (n).
uniform vec3 wiper_u = vec3(1.0, 0.0, 0.0);
uniform vec3 wiper_v = vec3(0.0, 1.0, 0.0);
uniform vec3 wiper_n = vec3(0.0, 0.0, -1.0);
uniform vec3 wiper_pivot_a = vec3(0.0);
uniform vec3 wiper_pivot_b = vec3(0.0);
// The radii the rubber covers (mesh units: inner, outer), and the sweep (radians).
uniform vec2 wiper_reach = vec2(0.0);
uniform float wiper_sweep = 1.7;

// One sweep up (or down) takes this long (s); a cycle is two sweeps and a rest.
const float WIPER_STROKE = 0.48;


// The cycle's length at this rain: fast in a downpour, intermittent in a drizzle.
float wiper_period() {
	return mix(3.6, 1.12, smoothstep(0.25, 0.7, ws_rain()));
}


// Seconds into this car's cycle.
float wiper_clock(float t) {
	float p = wiper_period();
	return mod(t + wiper_phase * p, p);
}


// The blades' angle up from parked (0 .. wiper_sweep), eased in and out at both ends.
float wiper_angle(float t) {
	if (wipers_on < 0.5 || ws_rain() < 0.02) {
		return 0.0;
	}
	float c = wiper_clock(t);
	float up = smoothstep(0.0, WIPER_STROKE, c);
	float down = smoothstep(WIPER_STROKE, 2.0 * WIPER_STROKE, c);
	return wiper_sweep * (up - down);
}


// How long ago (s) a blade last passed over mesh point `p` (a large number where none reaches or the
// wipers are off). The stroke is eased, so the time it passes an angle comes from the inverse of
// smoothstep (solved by two Newton steps from the linear guess).
float wiper_since(vec3 p, float t) {
	if (wipers_on < 0.5 || ws_rain() < 0.02 || wiper_reach.y <= 0.0) {
		return 1e4;
	}
	float best = 1e4;
	for (int k = 0; k < 2; k++) {
		vec3 d = p - (k == 0 ? wiper_pivot_a : wiper_pivot_b);
		vec2 q = vec2(dot(d, wiper_u), dot(d, wiper_v));
		float r = length(q);
		if (r < wiper_reach.x || r > wiper_reach.y) {
			continue;
		}
		// The angle up from parked (-u), 0 .. PI.
		float th = 3.14159265 - atan(q.y, q.x);
		if (q.y < 0.0) {
			th = q.x < 0.0 ? 0.0 : 3.14159265;
		}
		if (th > wiper_sweep) {
			continue;
		}
		float a = th / wiper_sweep;
		float x = a;
		for (int i = 0; i < 2; i++) {
			float f = x * x * (3.0 - 2.0 * x) - a;
			float df = max(6.0 * x * (1.0 - x), 0.15);
			x = clamp(x - f / df, 0.0, 1.0);
		}
		float tu = x * WIPER_STROKE;
		float td = (2.0 - x) * WIPER_STROKE;
		float c = wiper_clock(t);
		float since = c >= td ? c - td : (c >= tu ? c - tu : c + wiper_period() - td);
		best = min(best, since);
	}
	return best;
}
