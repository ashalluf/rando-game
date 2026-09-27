// Erosion noise, the GPU half. MacroMap._erosion_filter() cuts the mountains' main canyons and
// their first tributaries into the height itself (440 m and 220 m apart); the orders finer than
// that - gullies 110 m and 55 m apart - are drawn here, as shading only, on the near terrain
// (terrain.gdshader) and the far ground (macro_ground.gdshader). Each order is a sum of cosine
// stripes running DOWN the local slope over a jittered grid of cells, blended by closeness, so
// they meander and merge like gullies; the slope they run down includes the walls of the orders
// above, so each branches off the last. After Fewes's "terrain erosion noise".
//
// Shader includes use // comments, like any shader file.

vec2 erosion_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}


// One order at `p` (in cells), stripes varying along `dir` (unit, along the contour). .x the
// value (-1..1), .yz its derivative per cell.
vec3 erosion_cells(vec2 p, vec2 dir) {
	vec2 ip = floor(p);
	vec2 fp = p - ip;
	vec3 va = vec3(0.0);
	float wt = 0.0;
	for (int j = -2; j <= 1; j++) {
		for (int i = -2; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 pp = fp + o - erosion_hash(ip - o) * 0.5;
			float d2 = dot(pp, pp);
			float w = max(exp(-d2 * 2.0) - 0.0889, 0.0);
			float mag = dot(pp, dir) * 6.2831853;
			va += vec3(cos(mag), -sin(mag) * 6.2831853 * dir) * w;
			wt += w;
		}
	}
	return va / max(wt, 0.0001);
}


// The gullies finer than the height's own, as a slope (metres per metre) to add to the surface
// normal, and in .z how deep in a gully the point is (-1 crest .. +1 gully floor). `w` true
// world XZ, `slope` the surface's own fall (d height / dx, dz), `amp` metres for the first order
// (each finer one half of it, at half the spacing), `cell` metres between the first order's
// gullies, `fp` metres a screen pixel covers (orders under a few pixels fade out).
vec3 erosion_detail(vec2 w, vec2 slope, float amp, float cell, float fp) {
	vec3 acc = vec3(0.0);
	float a = amp;
	float c = cell;
	float wsum = 0.0;
	for (int o = 0; o < 2; o++) {
		float vis = smoothstep(3.0, 9.0, c / max(fp, 0.001));
		if (vis <= 0.001) {
			break;
		}
		vec2 d = slope + acc.xy * 1.6;
		vec2 dir = vec2(d.y, -d.x);
		float l = length(dir);
		dir = l > 0.00001 ? dir / l : vec2(1.0, 0.0);
		vec3 e = erosion_cells(w / c, dir);
		acc.xy += e.yz * (a / c) * vis;
		acc.z += -e.x * vis * a;
		wsum += a;
		a *= 0.5;
		c *= 0.5;
	}
	acc.z /= max(wsum, 0.0001);
	return acc;
}
