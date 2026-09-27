// Shared pieces of the car damage shaders (car_paint_damage.gdshader via car_paint.gdshaderinc,
// and car_glass_damage.gdshader). All of it works in the body model's own mesh space, which is
// where Vehicle / CarDamage put every hole, crack, dent and burn, so the marks ride the car.
// Nothing here is compiled into an undamaged car (see car_paint.gdshaderinc).

float cd_hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float cd_hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

vec2 cd_hash22(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.xx + q.yz) * q.zy);
}

// Value noise, 0..1.
float cd_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(cd_hash31(i), cd_hash31(i + vec3(1.0, 0.0, 0.0)), f.x),
		mix(cd_hash31(i + vec3(0.0, 1.0, 0.0)), cd_hash31(i + vec3(1.0, 1.0, 0.0)), f.x), f.y);
	float b = mix(mix(cd_hash31(i + vec3(0.0, 0.0, 1.0)), cd_hash31(i + vec3(1.0, 0.0, 1.0)), f.x),
		mix(cd_hash31(i + vec3(0.0, 1.0, 1.0)), cd_hash31(i + vec3(1.0, 1.0, 1.0)), f.x), f.y);
	return mix(a, b, f.z);
}

float cd_fbm3(vec3 p) {
	return cd_noise3(p) * 0.55 + cd_noise3(p * 2.13 + 7.1) * 0.3 + cd_noise3(p * 4.7 - 3.3) * 0.15;
}

// Two unit vectors across a surface with normal `n`.
void cd_frame(vec3 n, out vec3 t, out vec3 b) {
	vec3 up = abs(n.y) < 0.92 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	t = normalize(cross(up, n));
	b = cross(n, t);
}

// A thin line `d` (metres from it) `w` wide, antialiased over `px` metres (one pixel). Past the
// point where the line is thinner than a pixel it keeps its coverage instead of vanishing, so a
// web of cracks greys the glass evenly at distance rather than shimmering in and out.
float cd_line(float d, float w, float px) {
	float cover = clamp(w / max(px, 1e-5), 0.0, 1.0);
	return (1.0 - smoothstep(0.0, px, d - w * 0.5)) * mix(1.0, cover, step(w, px));
}

// The web a round leaves in laminated glass: radial splits that wander a little and stop at
// their own lengths, polygonal rings chorded between neighbouring splits (broken, not closed),
// and a pulverised white hub. `facet` is a tilt per wedge of the web, which is what makes a
// cracked screen glint in pieces rather than read as lines drawn on it.
float cd_crack_web(vec3 p, vec3 c, vec3 n, float radius, float seed, float px, out vec2 facet) {
	facet = vec2(0.0);
	vec3 t;
	vec3 b;
	cd_frame(n, t, b);
	vec3 d = p - c;
	vec2 q = vec2(dot(d, t), dot(d, b));
	float r = length(q);
	if (r > radius) {
		return 0.0;
	}
	float ang = atan(q.y, q.x);
	float spokes = floor(9.0 + cd_hash21(vec2(seed, 1.7)) * 9.0);
	float wig = (cd_noise3(vec3(r * 22.0, seed * 13.0, 0.5)) - 0.5) * 0.55;
	float a = ang / 6.2831853 * spokes + wig + seed * 3.0;
	float k = floor(a);
	float fa = a - k;
	float sector = 6.2831853 / spokes;
	// Distance to the nearest split, as an arc length.
	float to_spoke = min(fa, 1.0 - fa) * sector * r;
	float near_k = fa < 0.5 ? k : k + 1.0;
	float reach = radius * (0.45 + 0.55 * cd_hash21(vec2(near_k, seed)));
	float w = 0.0009 * (1.0 - 0.6 * r / radius);
	float lines = cd_line(to_spoke, w, px) * (1.0 - smoothstep(reach * 0.8, reach, r));
	// Rings: a chord across this wedge at each ring radius, drawn in some wedges only.
	float mid = (k + 0.5) / spokes * 6.2831853 - (wig + seed * 3.0) / spokes * 6.2831853;
	float along = r * cos(ang - mid);
	for (int j = 0; j < 4; j++) {
		float fj = float(j);
		float h = cd_hash21(vec2(k * 1.31 + fj * 7.7, seed));
		float rj = radius * (0.10 + 0.19 * fj + 0.07 * h);
		if (h > 0.28 && rj < radius * 0.9) {
			lines = max(lines, cd_line(abs(along - rj * cos(sector * 0.5)), 0.0007, px) * step(r, rj * 1.25));
		}
	}
	float hub = 1.0 - smoothstep(radius * 0.035, radius * 0.08, r);
	facet = (vec2(cd_hash21(vec2(k, seed + 3.0)), cd_hash21(vec2(k + 11.0, seed))) - 0.5)
		* (1.0 - smoothstep(radius * 0.4, radius, r));
	return max(lines, hub);
}

// Tempered glass that has crazed: a sheet of small cubes (Voronoi cells `cell` metres across),
// each tilted its own way. Returns the crack lines; `tilt` is the cell's facet.
float cd_craze(vec2 q, float cell, float px, out vec2 tilt) {
	vec2 g = q / cell;
	vec2 i = floor(g);
	vec2 f = g - i;
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id1 = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + cd_hash22(i + o) * 0.8 + 0.1 - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id1 = i + o;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float edge = (sqrt(d2) - sqrt(d1)) * 0.5 * cell;
	tilt = cd_hash22(id1 + 17.0) - 0.5;
	return cd_line(edge, 0.0006, px);
}
