// Crash deformation (scripts/vehicles/crash_deform.gd): crumple zones, panels sprung off their
// catches and scrapes along a contact. Included by every damaged car shader that draws part of
// the body - the paint (car_paint.gdshaderinc under CAR_DAMAGE), the glass, the lamps and the
// trim / chrome / far-twin parts - so a crushed nose carries its lamps, grille and glass with it.
// All of it is in the body model's own mesh space, like the dents. Needs car_damage.gdshaderinc
// (cd_noise3) first. Nothing here runs unless a crash put something in it (the counts are 0).

// Crumple zones: xyz the contact on the skin, w the lateral radius (mesh units);
// crumple_push xyz the crush - the way into the car times how far the front of the zone moved -,
// w a seed; crumple_shape x how deep into the car the crush reaches, y the fold pitch, z how much
// a top panel tents up in the middle of a crush from the front or back (bonnet buckling).
uniform int crumple_count = 0;
uniform vec4 crumples[6];
uniform vec4 crumple_push[6];
uniform vec4 crumple_shape[6];
// The body's up in mesh space.
uniform vec3 crumple_up = vec3(0.0, 1.0, 0.0);
// Panels sprung open or torn loose (a bonnet ajar, a boot lid up, a bumper hanging off one
// corner): a box region (centre, three half-extent vectors, w of the centre a soft margin) turned
// about a hinge (pivot, w the angle; axis unit).
uniform int panel_count = 0;
uniform vec4 panel_c[4];
uniform vec4 panel_u[4];
uniform vec4 panel_v[4];
uniform vec4 panel_w[4];
uniform vec4 panel_pivot[4];
uniform vec4 panel_axis[4];

vec3 cr_rot(vec3 v, vec3 k, float a) {
	float c = cos(a);
	float s = sin(a);
	return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

// 1 inside the half extent `a` (a vector), easing to 0 over `m` past it.
float cr_slab(vec3 d, vec3 a, float m) {
	float h = max(length(a), 1e-4);
	float t = abs(dot(d, a)) / h;
	return 1.0 - smoothstep(h, h + max(m, 1e-4), t);
}

// How hard a point was crushed (0..1, the crush's share of the depth that reached it) and the
// phase of the folds there - for the paint to crack along the ridges.
float cr_stress(vec3 p, out float ridge) {
	float st = 0.0;
	ridge = 0.0;
	for (int i = 0; i < crumple_count && i < 6; i++) {
		vec3 push = crumple_push[i].xyz;
		float D = length(push);
		if (D < 1e-4) {
			continue;
		}
		vec3 dir = push / D;
		vec3 rel = p - crumples[i].xyz;
		float s = dot(rel, dir);
		float L = max(crumple_shape[i].x, D * 1.3);
		float R = max(crumples[i].w, 0.05);
		vec3 lat = rel - dir * s;
		float lr2 = dot(lat, lat) / (R * R);
		if (s > L || lr2 >= 1.0) {
			continue;
		}
		float wl = 1.0 - smoothstep(0.35, 1.0, sqrt(lr2));
		float k = clamp(1.0 - s / L, 0.0, 1.0);
		float pitch = max(crumple_shape[i].y, 0.04);
		float seed = crumple_push[i].w;
		float wob = cd_noise3(p * (0.7 / pitch) + seed * 13.0);
		float ph = (s / pitch + wob * 0.9 + seed * 7.0) * 6.2832;
		float here = wl * sin(3.1416 * clamp(k * 1.1, 0.0, 1.0)) * clamp(D * 6.0, 0.0, 1.0);
		if (here > st) {
			st = here;
			ridge = abs(cos(ph));
		}
	}
	return st;
}

// Where the crash moved rest point `p` (normal `n`, both mesh space).
vec3 cr_move(vec3 p, vec3 n) {
	vec3 q = p;
	vec3 nn = normalize(n);
	for (int i = 0; i < crumple_count && i < 6; i++) {
		vec3 push = crumple_push[i].xyz;
		float D = length(push);
		if (D < 1e-4) {
			continue;
		}
		vec3 dir = push / D;
		vec3 rel = p - crumples[i].xyz;
		float s = dot(rel, dir);
		float L = max(crumple_shape[i].x, D * 1.3);
		if (s > L) {
			continue;
		}
		float R = max(crumples[i].w, 0.05);
		vec3 lat = rel - dir * s;
		float lr2 = dot(lat, lat) / (R * R);
		if (lr2 >= 1.0) {
			continue;
		}
		float wl = 1.0 - smoothstep(0.35, 1.0, sqrt(lr2));
		float k = clamp(1.0 - s / L, 0.0, 1.0);
		// The front of the zone goes back by D; the metal behind it folds up to take it, so the
		// crushed length shortens like an accordion (smooth where the crush runs out).
		float crush = D * k * k * (3.0 - 2.0 * k) * wl;
		// The face that took it is not pushed back flat: it caves in unevenly, deepest where it
		// met the obstacle, a bumper corner standing proud of a buckled middle.
		crush *= 1.0 + (cd_noise3(p * (0.9 / max(crumple_shape[i].y, 0.04)) + crumple_push[i].w * 5.0) - 0.5) * 0.7 * k;
		// Sheet metal folds across the push: ridges `pitch` apart, wandering, strongest in the
		// middle of the crushed length, out along the skin's own normal on faces that run
		// along the push (wings, sills, a door) and hardly at all on a face square to it.
		float pitch = max(crumple_shape[i].y, 0.04);
		float seed = crumple_push[i].w;
		float wob = cd_noise3(p * (0.7 / pitch) + seed * 13.0);
		float fold = sin((s / pitch + wob * 0.9 + seed * 7.0) * 6.2832);
		float amp = D * 0.2 * sin(3.1416 * clamp(k * 1.1, 0.0, 1.0)) * wl;
		fold *= amp * (0.55 + 0.9 * cd_noise3(p * (0.45 / pitch) + seed * 3.0));
		float across = 1.0 - abs(dot(nn, dir));
		// A bonnet or a boot lid crushed from its end buckles UP into a tent.
		float top = smoothstep(0.35, 0.8, dot(nn, crumple_up)) * (1.0 - abs(dot(dir, crumple_up)));
		float tent = crumple_shape[i].z * D * sin(3.1416 * k) * wl * top;
		q += dir * crush + nn * (fold * across) + crumple_up * tent;
	}
	for (int i = 0; i < panel_count && i < 4; i++) {
		vec3 d = p - panel_c[i].xyz;
		float m = panel_c[i].w;
		float w = cr_slab(d, panel_u[i].xyz, m) * cr_slab(d, panel_v[i].xyz, m) * cr_slab(d, panel_w[i].xyz, m);
		if (w > 0.0) {
			vec3 pv = panel_pivot[i].xyz;
			q = pv + cr_rot(q - pv, panel_axis[i].xyz, panel_pivot[i].w * w);
		}
	}
	return q;
}

bool cr_any() {
	return crumple_count > 0 || panel_count > 0;
}

// For the parts / glass / lamp shaders: moves VERTEX and turns NORMAL by the same amount.
void cr_apply(inout vec3 v, inout vec3 n) {
	vec3 t;
	vec3 b;
	cd_frame(normalize(n), t, b);
	float e = 0.02;
	vec3 o0 = cr_move(v, n);
	vec3 nt = cr_move(v + t * e, n) - o0;
	vec3 nb = cr_move(v + b * e, n) - o0;
	vec3 nn = cross(nb, nt);
	if (dot(nn, n) < 0.0) {
		nn = -nn;
	}
	n = normalize(nn);
	v = o0;
}

// Scrapes: where the car slid along something. xyz the start, w the half width; scrape_dir xyz
// the way it ran times its length, w a seed. Paint only.
uniform int scrape_count = 0;
uniform vec4 scrapes[8];
uniform vec4 scrape_dir[8];

// x: scuffed (the clear coat dulled), y: scored through to primer, z: through to bare steel.
vec3 cr_scrape(vec3 p, vec3 n, float px) {
	vec3 r = vec3(0.0);
	for (int i = 0; i < scrape_count && i < 8; i++) {
		vec3 v = scrape_dir[i].xyz;
		float len = length(v);
		if (len < 1e-4) {
			continue;
		}
		vec3 u = v / len;
		vec3 d = p - scrapes[i].xyz;
		float t = dot(d, u);
		float w = max(scrapes[i].w, 0.01);
		vec3 side = cross(u, n);
		float sl = length(side);
		if (sl < 0.2) {
			continue;
		}
		side /= sl;
		float x = dot(d, side) / w;
		float off = abs(dot(d, normalize(n)));
		if (abs(x) > 1.3 || off > w * 1.5 || t < -w || t > len + w) {
			continue;
		}
		float seed = scrape_dir[i].w;
		// Ragged ends and a ragged edge, the band wider where it pressed harder.
		float edge = 0.75 + 0.35 * cd_noise3(vec3(t * 3.0, seed * 5.0, 1.0));
		float ends = smoothstep(-w * 0.4, w * 0.8, t + (cd_noise3(vec3(x * 2.0, seed, 3.0)) - 0.5) * w)
			* (1.0 - smoothstep(len - w * 1.2, len + w * 0.3, t + (cd_noise3(vec3(x * 2.0, seed, 7.0)) - 0.5) * w * 2.0));
		float band = (1.0 - smoothstep(edge - 0.2, edge, abs(x))) * ends * (1.0 - smoothstep(w * 0.6, w * 1.5, off));
		// Score lines along the slide: thin streaks of different depths, faded to their average
		// once a streak is under a pixel.
		float q = x * w;
		float lanes = cd_noise3(vec3(q * 160.0, t * 0.6, seed * 9.0)) * 0.7 + cd_noise3(vec3(q * 420.0, t * 1.4, seed * 3.0)) * 0.3;
		float res = clamp(0.0045 / max(px, 1e-5), 0.0, 1.0);
		float primer = mix(0.35, smoothstep(0.55, 0.7, lanes), res);
		float steel = mix(0.12, smoothstep(0.78, 0.86, lanes), res) * smoothstep(0.2, 0.9, 1.0 - abs(x));
		r = max(r, vec3(band, primer * band, steel * band));
	}
	return r;
}
