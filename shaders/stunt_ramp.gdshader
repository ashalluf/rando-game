shader_type spatial;
render_mode cull_disabled;

// The stunt features (StuntKit): kickers, the river's quarter-pipe, the freeway ramp pair, the loop
// and the dirt jumps, every one of them ONE mesh on this one material. What a face is rides in
// COLOR.a (StuntKit.K_*, in 16ths), its paint in COLOR.rgb (display numbers); UV is metres in the
// face's own frame (u across, v along the ride or up a wall). Both faces draw (an open frame shows
// the underside of a deck): Godot has already turned NORMAL toward the camera on a back face.
//   0 painted steel: a satin coat, scuffed bright on the edges a ride rubs, chips to primer, rust
//     bleeding from them, dirt low down.
//   1 diamond (tread) plate: galvanised steel with its raised lugs (a normal pattern on a 3 cm
//     staggered grid, faded to the plate's mean under a pixel), tyre rubber in two wheel tracks
//     down the ride, grit.
//   2 hazard paint: yellow and black diagonal bands, weathered.
//   3 cast concrete: the quarter-pipe's trowelled face, form joints every 2 m, skid marks, wax.
//   4 coping: a polished steel bar, ground bright where it is ridden.
//   5 dirt: packed earth (the hill dirt texture), wet darker, two tyre ruts down the jump, loose
//     crumbs on the sides.
//   6 plywood: the launch deck's sheets, joints every 2.44 m, grip paint.
//   7 rubber: black feet and bumpers.
//   8 galvanised frame: dull zinc, white rust in streaks.
// Colours are tuned in display (sRGB) numbers and handed over in the renderer's own space
// (color_space.gdshaderinc), so the Mac draws what the opengl3 stills show.

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paint_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plank_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float road_wetness;

varying float kind;
varying vec3 vcol;
varying vec3 wpos;

#include "res://shaders/color_space.gdshaderinc"

vec3 disp(vec3 c) {
	return cs_linear_renderer() ? cs_linear_to_srgb(c) : c;
}

vec3 to_lit(vec3 c) {
	return cs_linear_renderer() ? cs_srgb_to_linear(c) : c;
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
	return vnoise(p) * 0.5 + vnoise(p * 2.07 + 3.1) * 0.3 + vnoise(p * 4.3 + 7.7) * 0.2;
}

void vertex() {
	kind = floor(COLOR.a * 16.0 + 0.5);
	vcol = COLOR.rgb;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float k = kind;
	// A pixel's size in metres, for fading pattern under it.
	float px = max(length(dFdx(uv)), length(dFdy(uv))) + 1e-4;
	vec3 col = vcol;
	float rough = 0.6;
	float metal = 0.0;
	vec2 bump = vec2(0.0);
	float wet = clamp(road_wetness, 0.0, 1.0);
	float grime = fbm(wpos.xz * 0.6 + wpos.y * 0.3);
	if (k < 0.5) {
		// Painted steel.
		vec3 tex = disp(cs_in(texture(paint_tex, uv * 0.5).rgb));
		col = vcol * mix(0.82, 1.12, tex.g);
		float chip = smoothstep(0.62, 0.7, fbm(uv * 3.1 + 11.0));
		col = mix(col, vec3(0.42, 0.40, 0.38), chip * 0.7);
		col = mix(col, vec3(0.34, 0.17, 0.08), smoothstep(0.66, 0.78, fbm(uv * 2.3 + 4.0)) * 0.6);
		col *= mix(1.0, 0.75, grime * 0.25);
		rough = mix(0.42, 0.75, chip + tex.r * 0.3);
		metal = chip * 0.6;
	} else if (k < 1.5) {
		// Diamond plate: lugs on a 3 cm staggered grid, alternating 45 degrees.
		vec2 g = uv / 0.032;
		vec2 cell = floor(g);
		vec2 f = fract(g) - 0.5;
		float alt = mod(cell.x + cell.y, 2.0);
		vec2 r = alt < 0.5 ? vec2(f.x + f.y, f.x - f.y) : vec2(f.x - f.y, f.x + f.y);
		float lug = smoothstep(0.42, 0.3, length(r * vec2(0.42, 1.35)));
		float fade = smoothstep(0.012, 0.004, px);
		bump = (alt < 0.5 ? vec2(1.0, 1.0) : vec2(1.0, -1.0)) * r.y * lug * 0.9 * fade;
		col = vec3(0.56, 0.57, 0.58) * mix(0.85, 1.08, vnoise(uv * 1.7)) * mix(1.0, 1.15, lug * fade);
		// Two wheel tracks of rubber down the ride (u across, centred).
		float tracks = smoothstep(0.55, 0.15, abs(abs(uv.x) - 0.82)) * (0.5 + 0.5 * vnoise(uv * vec2(3.0, 0.4)));
		col = mix(col, vec3(0.08, 0.08, 0.08), tracks * 0.55);
		col *= mix(1.0, 0.75, grime * 0.4);
		rough = mix(0.34, 0.7, tracks + grime * 0.3);
		metal = mix(0.85, 0.35, tracks);
	} else if (k < 2.5) {
		// Hazard bands.
		float band = step(0.5, fract((uv.x + uv.y) / 0.36));
		col = mix(vec3(0.95, 0.74, 0.06), vec3(0.06, 0.06, 0.06), band);
		col = mix(col, vec3(0.45, 0.42, 0.38), smoothstep(0.6, 0.75, fbm(uv * 4.0)) * 0.6);
		rough = 0.55;
	} else if (k < 3.5) {
		// Cast concrete.
		vec3 tex = disp(cs_in(texture(concrete_tex, uv * 0.35).rgb));
		col = tex * vec3(1.02, 1.0, 0.96) * mix(0.9, 1.08, fbm(uv * 0.8));
		float jd = abs(fract(uv.x / 2.0 + 0.5) - 0.5) * 2.0;
		float joint = smoothstep(0.025, 0.008, jd) * smoothstep(0.04, 0.01, px);
		col *= 1.0 - joint * 0.35;
		// Skid and wax: dark streaks up the ride.
		float skid = smoothstep(0.62, 0.9, vnoise(vec2(uv.x * 2.2, uv.y * 0.25) + 5.0)) * smoothstep(0.0, 1.5, uv.y);
		col = mix(col, vec3(0.16, 0.15, 0.14), skid * 0.45);
		rough = mix(0.82, 0.55, skid);
	} else if (k < 4.5) {
		col = vec3(0.70, 0.70, 0.69) * mix(0.85, 1.1, vnoise(uv * vec2(6.0, 40.0)));
		rough = 0.28;
		metal = 1.0;
	} else if (k < 5.5) {
		// Dirt.
		vec3 tex = disp(cs_in(texture(dirt_tex, uv * 0.3).rgb));
		col = mix(tex, tex * vec3(0.95, 0.86, 0.72), 0.5) * vcol * 1.15;
		float ruts = smoothstep(0.35, 0.05, abs(abs(uv.x) - 0.78)) * (0.6 + 0.4 * vnoise(uv * vec2(2.0, 0.6)));
		col *= mix(1.0, 0.78, ruts);
		bump = vec2(sign(uv.x) * (abs(uv.x) - 0.78) * ruts * 0.8, 0.0);
		col *= mix(1.0, 0.62, wet);
		rough = mix(0.95, 0.55, wet * 0.8) - ruts * 0.08;
	} else if (k < 6.5) {
		vec3 tex = disp(cs_in(texture(plank_tex, uv * vec2(0.25, 0.25)).rgb));
		col = tex * vec3(1.0, 0.95, 0.88);
		float sd = abs(fract(uv.y / 2.44 + 0.5) - 0.5) * 2.44;
		float seam = smoothstep(0.02, 0.005, sd) * smoothstep(0.03, 0.005, px);
		col *= 1.0 - seam * 0.5;
		col = mix(col, vec3(0.16, 0.16, 0.16), smoothstep(0.4, 0.1, abs(abs(uv.x) - 0.85)) * 0.5);
		rough = 0.8;
	} else if (k < 7.5) {
		col = vec3(0.05, 0.05, 0.05);
		rough = 0.85;
	} else {
		col = vec3(0.55, 0.56, 0.55) * mix(0.85, 1.05, fbm(uv * 1.5));
		col = mix(col, vec3(0.78, 0.78, 0.74), smoothstep(0.65, 0.85, vnoise(vec2(uv.x * 9.0, uv.y * 0.7))) * 0.4);
		rough = 0.6;
		metal = 0.6;
	}
	// Rain: everything darker and glossier.
	if (k < 4.5) {
		col *= mix(1.0, 0.8, wet);
	}
	rough = mix(rough, rough * 0.45, wet);
	ALBEDO = to_lit(clamp(col, vec3(0.0), vec3(1.0)));
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = metal;
	NORMAL_MAP = vec3(clamp(bump * 0.5 + 0.5, vec2(0.0), vec2(1.0)), 1.0);
	NORMAL_MAP_DEPTH = 1.0;
}
