// The decks and ramps of a multi-storey car park (CarParkBuild): poured concrete, and what a few
// years of cars do to it, worked out from where the quad is rather than painted per car park.
// UV is metres: x along the structure (u), y across the band; UV2.x is the band's kind and UV2.y
// says whether the deck is the roof (open to the weather).
//   kind 0, a drive (aisles, end zones, the ramp strip's lane): y from the lane's centre; two
//           wheel tracks each way polished and darkened, a yellow dashed centre line, rubber at
//           the turns' ends;
//   kind 1, a stall row: y from the row's back wall (0) toward the aisle; x from the first stall
//           line; white stall lines, a wheel stop's shadow, an oil stain under every engine (the
//           cars park nose in, so the engine is over the back of the stall), tyre scuffs at the
//           mouth;
//   kind 2, a ramp: y from its centre; transverse grooves cut for grip (in the normal), the
//           centre line, the wheel tracks.
// Colours are linear plain uniforms; the textures go through cs_in() (color_space.gdshaderinc).
shader_type spatial;
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint = vec3(0.62, 0.61, 0.58);
uniform float tex_scale = 3.2;
uniform float stall_w = 2.7;
uniform float stall_d = 5.2;
uniform vec3 paint_white = vec3(0.72, 0.72, 0.68);
uniform vec3 paint_yellow = vec3(0.62, 0.42, 0.04);
uniform vec3 oil = vec3(0.05, 0.048, 0.045);
uniform float stain_amount = 0.75;

global uniform float road_wetness;

varying vec2 info;

void vertex() {
	info = UV2;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.7 + 3.3) * 0.15;
}

// A painted line `w` wide at distance `d` from its centre, box-filtered over the pixel.
float line(float d, float w, float px) {
	return clamp((w * 0.5 - abs(d)) / max(px, 1e-4) + 0.5, 0.0, 1.0);
}

void fragment() {
	vec2 m = UV;
	float kind = info.x;
	bool roof = info.y > 0.5;
	float px = max(fwidth(m.x), fwidth(m.y));
	vec3 base = cs_in(texture(albedo_tex, m / tex_scale).rgb) * tint;
	float rough = mix(0.62, 0.95, texture(rough_tex, m / tex_scale).r);
	// Pour-to-pour shade and the trowel's swirl: large, quiet.
	float mott = fbm(m * 0.22);
	base *= 0.86 + 0.28 * mott;
	// Grime that gathers where nothing drives (patchy, darker).
	float grime = smoothstep(0.45, 0.85, fbm(m * 0.6 + 11.0));
	vec3 col = base;
	float paint = 0.0;
	vec3 pcol = paint_white;
	float polish = 0.0;
	float stain = 0.0;
	vec3 nrm_add = vec3(0.0);
	if (kind < 0.5) {
		float y = m.y;
		// Wheel tracks: two lanes of 3.4 m, wheels 0.8 m either side of each lane's centre.
		float t = 0.0;
		for (int i = 0; i < 4; i++) {
			float c = (i < 2 ? 1.7 : -1.7) + ((i % 2 == 0) ? 0.82 : -0.82);
			t += smoothstep(0.42, 0.05, abs(y - c));
		}
		t *= 0.65 + 0.35 * vnoise(vec2(m.x * 0.3, y * 2.0));
		polish = t;
		col *= 1.0 - 0.16 * t;
		col *= 1.0 - 0.14 * grime * (1.0 - t);
		// Dashed yellow centre line: 3 m dash, 3 m gap.
		float dash = step(0.5, fract(m.x / 6.0));
		paint = line(y, 0.1, px) * dash * step(2.0, abs(m.x) + 2.0);
		pcol = paint_yellow;
		// Drips of oil now and then where cars wait.
		float spot = smoothstep(0.75, 0.95, fbm(m * vec2(0.45, 0.9) + 3.0));
		stain = spot * 0.35;
	} else if (kind < 1.5) {
		float y = m.y;
		float k = floor(m.x / stall_w);
		float xs = m.x - (k + 0.5) * stall_w;
		// Stall lines: 10 cm, from 0.15 m off the wall to the mouth.
		float dl = m.x - floor(m.x / stall_w + 0.5) * stall_w;
		paint = line(dl, 0.1, px) * step(0.15, y) * step(y, stall_d - 0.05);
		// The oil stain under the engine: a soft blot, its edge pushed about by noise, every
		// stall its own size and darkness.
		float h = hash12(vec2(k, floor(info.y * 7.0) + 0.37));
		vec2 c = vec2(xs, y - (1.15 + 0.4 * h));
		float r = length(c * vec2(1.0, 1.35)) + (fbm(m * 3.1 + k) - 0.5) * 0.35;
		stain = smoothstep(0.35 + 0.35 * h, 0.0, r) * (0.35 + 0.65 * h);
		// A second, fainter one where the gearbox drips.
		stain += smoothstep(0.22, 0.0, length(vec2(xs * 0.9, y - 2.4 - h * 0.3))) * 0.25 * hash12(vec2(k, 3.1));
		// Tyre scuffs at the mouth, where everyone turns in.
		float scuff = smoothstep(1.1, 0.0, stall_d - y) * smoothstep(0.55, 0.15, abs(abs(xs) - 0.8));
		col *= 1.0 - 0.18 * scuff * (0.5 + 0.5 * vnoise(m * vec2(1.0, 5.0)));
		col *= 1.0 - 0.12 * grime;
		// Grime along the back wall.
		col *= 1.0 - 0.18 * smoothstep(0.6, 0.0, y);
	} else {
		float y = m.y;
		// Transverse grooves for grip on the slope: 2 cm cuts every 6 cm, faded under a pixel.
		float g = fract(m.x / 0.06);
		float groove = smoothstep(0.0, 0.25, g) * smoothstep(0.55, 0.3, g);
		float fade = clamp(1.0 - px / 0.05, 0.0, 1.0);
		nrm_add = vec3(0.0, 0.0, (groove - 0.5) * 0.35 * fade);
		col *= 1.0 - 0.06 * fade * groove;
		float t = 0.0;
		for (int i = 0; i < 4; i++) {
			float c = (i < 2 ? 1.7 : -1.7) + ((i % 2 == 0) ? 0.82 : -0.82);
			t += smoothstep(0.45, 0.05, abs(y - c));
		}
		polish = t * 0.8;
		col *= 1.0 - 0.18 * t;
		paint = line(y, 0.1, px) * step(0.5, fract(m.x / 4.0));
		pcol = paint_yellow;
	}
	// Paint is worn through where the wheels go.
	paint *= 1.0 - 0.55 * polish * smoothstep(0.3, 0.7, vnoise(m * 4.0));
	paint *= 0.75 + 0.25 * vnoise(m * 9.0);
	col = mix(col, pcol * (0.9 + 0.1 * mott), paint);
	stain *= stain_amount * (1.0 - paint);
	col = mix(col, oil, clamp(stain, 0.0, 0.85));
	rough = mix(rough, 0.45, clamp(stain, 0.0, 1.0));
	rough = mix(rough, 0.55, polish * 0.4);
	rough = mix(rough, 0.5, paint * 0.5);
	// The roof is out in the rain.
	if (roof) {
		float wet = road_wetness * (0.6 + 0.4 * smoothstep(0.3, 0.7, fbm(m * 0.18 + 5.0)));
		col *= 1.0 - 0.35 * wet;
		rough = mix(rough, 0.08, wet);
	}
	vec3 tn = texture(normal_tex, m / tex_scale).rgb;
	tn = normalize(tn * 2.0 - 1.0 + nrm_add);
	NORMAL_MAP = tn * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	SPECULAR = 0.45;
}
