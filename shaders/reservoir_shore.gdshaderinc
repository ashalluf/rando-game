// The reservoir's shore on the hill ground (scripts/world/reservoir.gd; the uniforms are set on
// the shared terrain material by LandmarkReservoir.apply_ground()): the BATHTUB RING - a band of
// pale, sun-bleached rock and dried silt from the waterline up `lake_ring` metres, where the water
// stood in wetter years and nothing grows - with faint old waterlines across it and a ragged top
// edge, and the dark wet silt and algae under the water. Off (lake_box.z 0) everywhere else.
//
// Included by terrain.gdshader. Colours are LINEAR (the terrain works in linear on both renderers,
// see color_space.gdshaderinc). Shader includes use // comments, like any shader file.

// 1 on the water and fading out round it (Reservoir.mask_image()), over lake_box.
uniform sampler2D lake_mask : filter_linear, repeat_disable;
// x0, z0, size x, size z of the mask in true world XZ. A zero size turns all of it off.
uniform vec4 lake_box = vec4(0.0);
uniform float lake_level = -1000.0;
// How far over the waterline the ring reaches (m).
uniform float lake_ring = 3.6;
uniform vec3 lake_ring_color = vec3(0.205, 0.188, 0.162);
uniform vec3 lake_silt_color = vec3(0.045, 0.048, 0.034);


float lake_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float lake_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(lake_hash(i), lake_hash(i + vec2(1.0, 0.0)), f.x),
		mix(lake_hash(i + vec2(0.0, 1.0)), lake_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}


// .x the ring (0..1), .y the drowned ground (0..1), .z the ring's tone (old waterlines, stains)
// at true world `w` and height `y`.
vec3 lake_shore(vec2 w, float y) {
	if (lake_box.z <= 0.0) {
		return vec3(0.0, 0.0, 1.0);
	}
	vec2 uv = (w - lake_box.xy) / lake_box.zw;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return vec3(0.0, 0.0, 1.0);
	}
	float m = texture(lake_mask, uv).r;
	if (m <= 0.02) {
		return vec3(0.0, 0.0, 1.0);
	}
	float h = y - lake_level;
	// A ragged top: the ring reaches higher up the gullies and lower on the spurs.
	float rag = (lake_vnoise(w * 0.09) - 0.5) * 1.6 + (lake_vnoise(w * 0.45) - 0.5) * 0.6;
	float top = lake_ring + rag;
	float ring = smoothstep(top + 0.35, top - 0.35, h) * smoothstep(-0.25, 0.05, h);
	float under = smoothstep(0.05, -0.4, h);
	float k = smoothstep(0.02, 0.4, m);
	// Old waterlines: thin darker lines at the levels the water stood at for a while, and the
	// ring paler near its top where it has been dry longest.
	float lines = 0.0;
	float hl = h + (lake_vnoise(w * 0.02) - 0.5) * 0.25;
	lines += smoothstep(0.07, 0.0, abs(fract(hl / 1.37) - 0.5) - 0.43) * 0.5;
	lines += smoothstep(0.05, 0.0, abs(fract(hl / 0.53 + 0.3) - 0.5) - 0.46) * 0.25;
	float tone = mix(0.82, 1.12, smoothstep(0.0, max(top, 0.5), h)) * (1.0 - 0.18 * lines)
		* mix(0.88, 1.1, lake_vnoise(w * 0.7));
	// Streaks running down the ring where rain has washed the slope above over it.
	tone *= 1.0 - 0.14 * smoothstep(0.6, 0.9, lake_vnoise(vec2(w.x * 0.8 + w.y * 0.3, h * 0.15)));
	return vec3(ring * k, under * k, tone);
}
