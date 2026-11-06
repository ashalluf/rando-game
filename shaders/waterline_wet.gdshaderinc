// Where a pile (or anything standing in the sea) meets the water (OceanCloseup): under the water
// line it is dark and glossy with weed and barnacles, the splash zone above it is wet and darkened
// and drying upward in tongues, and the line itself rides the swell. Work in LINEAR; `wy` is the
// world height, `wxz` TRUE world XZ (for the noise), `amp` the swell's amplitude (m).
// wave_scale is the Weather's global; the water rests at y 0.15 (the sea plane).
global uniform float wave_scale;

float wl_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float wl_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(wl_hash(i), wl_hash(i + vec2(1.0, 0.0)), f.x), mix(wl_hash(i + vec2(0.0, 1.0)), wl_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// `around` is a coordinate round the pile (metres), so tongues and weed vary round it.
vec3 wl_wet(vec3 alb, float wy, vec2 wxz, float around, float t, inout float rough) {
	float amp = 1.2 * max(wave_scale, 0.05);
	float sea_y = 0.15;
	// The line at this point rides up and down with the swell (a slow sum, not the real Gerstner:
	// the band is metres tall, its edge is not a measurement).
	float line_y = sea_y + amp * 0.45 * sin(t * 0.65 + wxz.x * 0.031 + wxz.y * 0.027)
		+ amp * 0.2 * sin(t * 1.13 + wxz.y * 0.06);
	float n = wl_noise(vec2(around * 3.0, wy * 2.2));
	float n2 = wl_noise(vec2(around * 11.0, wy * 9.0) + 7.0);
	// Weed and barnacles below the mean low water, up to a ragged edge.
	float weed_top = sea_y + amp * 0.35 + (n - 0.5) * 0.35;
	float weed = 1.0 - smoothstep(weed_top - 0.12, weed_top + 0.05, wy);
	vec3 weed_col = mix(vec3(0.020, 0.028, 0.012), vec3(0.055, 0.060, 0.030), n2);
	float barn = smoothstep(0.62, 0.78, n2) * weed;
	vec3 out_c = mix(alb, weed_col, weed * 0.85);
	out_c = mix(out_c, vec3(0.30, 0.29, 0.26), barn * 0.6);
	// The splash zone: wet up to where the last waves reached, drying in tongues above it.
	float splash_top = sea_y + amp * 1.1 + 0.6 + (wl_noise(vec2(around * 1.2, 0.5)) - 0.5) * 0.6;
	float wet = 1.0 - smoothstep(splash_top - 0.5, splash_top, wy);
	// Freshly washed just over the moving line.
	float fresh = 1.0 - smoothstep(line_y, line_y + 0.35 + 0.15 * n, wy);
	wet = max(wet * 0.75, fresh);
	out_c *= mix(1.0, 0.42, wet);
	// A salt tide mark at the top of the splash zone.
	float salt = smoothstep(0.35, 0.0, abs(wy - splash_top - 0.15)) * (1.0 - wet) * 0.12;
	out_c = mix(out_c, vec3(0.42, 0.41, 0.38), salt);
	rough = mix(rough, 0.12, max(fresh, wet * 0.6));
	return out_c;
}
