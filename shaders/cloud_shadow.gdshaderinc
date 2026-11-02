// Cloud shadows from the clouds the sky really draws (CloudShadows, scripts/world/cloud_shadows.gd).
// The cumulus volume in sky.gdshader is a field of columns read from a weather map; this is the
// same field at the clouds' lower body (where most of their mass is), seen from a point on the
// ground up the sun's direction. Change cumulus() in sky.gdshader and change this with it: the
// warp, the map's tiling and offsets, the field term, the column and fragment thresholds are its
// lines, word for word (tests/sky_clouds_3_checks.gd reads both files).
//
// Inputs are plain uniforms (CloudShadows copies them off the sky material every frame).

uniform sampler2D cs_weather : filter_linear_mipmap, repeat_enable;
uniform sampler3D cs_shape : filter_linear, repeat_enable;
// The sky's cloud_coverage, cloud_wind (km/s), weather_tile and billow_tile (km).
uniform float cs_coverage = 0.42;
uniform vec2 cs_wind = vec2(0.0075, 0.0028);
uniform float cs_weather_tile = 30.0;
uniform float cs_billow_tile = 2.0;
// The deck: base and depth (km), and the height above the base (share of the depth) the shadow
// is taken at.
uniform float cs_base = 1.45;
uniform float cs_depth = 1.7;
uniform float cs_body = 0.18;
// day_fragments x sky_day: the sky's daytime thinning of the fragments.
uniform float cs_fragments = 0.0;
// The envelope's values over which a shadow comes in (its penumbra).
uniform vec2 cs_edge = vec2(0.3, 0.72);
// The map's mip: a little softer than its texels (a real shadow edge is a penumbra ~100 m wide).
uniform float cs_lod = 1.2;

// The share of the sun a cloud takes away over a TRUE-world point (metres), the sun along L.
// 0 = full sun, 1 = a cloud's full shadow.
float cs_shadow(vec3 world_m, vec3 L) {
	float ly = max(L.y, 0.12);
	float h = cs_base + cs_body * cs_depth - world_m.y / 1000.0;
	vec2 p = world_m.xz / 1000.0 + (L.xz / ly) * h + cs_wind * TIME;
	// The crown's lean downwind, at the body's height (cumulus()).
	vec2 lean = normalize(cs_wind + vec2(1e-5)) * cs_body * cs_body * 0.22;
	vec2 pxz = p - lean;
	vec3 wn = textureLod(cs_shape, vec3(pxz / (cs_billow_tile * 2.6), 0.37), 0.0).rgb;
	vec2 wv = wn.rb - 0.5;
	vec2 wuv = (pxz + wv * 0.9) / cs_weather_tile;
	vec3 w = textureLod(cs_weather, wuv, cs_lod).rgb;
	float field = textureLod(cs_weather, wuv * 0.27 + vec2(0.37, 0.71), cs_lod).b;
	float cov = cs_coverage + (field - 0.5) * 0.46 * (1.0 - smoothstep(0.7, 0.9, cs_coverage));
	float thr = 1.0 - cov;
	float col = smoothstep(thr, thr + 0.26, w.r);
	float top = mix(0.16, 1.0, w.g * w.g) * (0.4 + 0.6 * col) * mix(0.6, 1.35, field);
	top = min(top * mix(0.72, 1.12, smoothstep(0.25, 0.75, wn.r)), 0.97);
	vec2 fr = textureLod(cs_weather, wuv * 4.3 + vec2(0.61, 0.23), cs_lod + 1.0).rg;
	float fthr = thr + 0.16 + 0.12 * col + cs_fragments;
	float fcol = smoothstep(fthr, fthr + 0.34, fr.x);
	float ftop = mix(0.05, 0.2, fr.y);
	// The body as cumulus() draws it at the shadow's height: the heap's envelope (as wide as its
	// base up to its skirt) and the fragments'. The billows then keep the part of an envelope over
	// about a half, so that is where the cloud is; the edge is a short ramp either side (the
	// penumbra). A field-wide optical depth instead put half the ground in a grey wash.
	float rel = cs_body / max(top, 0.05);
	float rr = smoothstep(0.22, 1.0, rel);
	rr = rr * rr * (1.0 + 0.4 * rr);
	float d_big = rel < 1.0 ? clamp((sqrt(col) - rr) / max(1.0 - rr, 0.05), 0.0, 1.0) : 0.0;
	float frel = cs_body * 0.5 / ftop;
	float fr2 = smoothstep(0.1, 1.0, frel);
	float d_frag = frel < 1.0 ? clamp((sqrt(fcol) * 0.7 - fr2 * fr2) / max(1.0 - fr2 * fr2, 0.05), 0.0, 1.0) : 0.0;
	float body = smoothstep(cs_edge.x, cs_edge.y, d_big);
	// A fragment is thin: it takes less of the sun.
	body = max(body, smoothstep(cs_edge.x, cs_edge.y, d_frag) * 0.55);
	// A thick heap is darker under its middle than a thin one.
	return body * mix(0.7, 1.0, smoothstep(0.25, 0.7, top));
}
