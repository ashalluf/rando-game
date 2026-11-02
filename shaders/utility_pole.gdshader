// The overhead utilities' hardware (UtilityPoles, scripts/world/utility_poles.gd): the wooden
// pole, the fir crossarm, galvanised steel, porcelain and polymer insulators, the transformer
// can's paint, black plastics, the yellow guy guard, the aluminium pole tag, the street light's
// lens (lit after dark by lamp_factor) and the meter's glass.
// The surface kind rides in COLOR.a (kind + 0.5) / 16, its paint in COLOR.rgb as sRGB numbers
// (vertex colours arrive raw on both renderers); UV is metres (round and along a part, or along
// and across a box face). INSTANCE_CUSTOM.x is the pole's age (weathering), .y a tone.
// Works in linear on both renderers (color_space.gdshaderinc).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

// The silver-grey a sunbaked pole weathers to (linear).
uniform vec3 weathered = vec3(0.27, 0.255, 0.235);
// How bright the street light's lens burns at night.
uniform float lens_energy = 3.2;

varying flat float v_kind;
varying vec3 v_paint;
varying vec2 v_inst;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), u.x), mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_kind = floor(COLOR.a * 16.0);
	v_paint = cs_srgb_to_linear(COLOR.rgb);
	v_inst = INSTANCE_CUSTOM.xy;
}

void fragment() {
	vec3 alb = v_paint;
	float rough = 0.8;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	vec2 uv = UV;
	float age = v_inst.x;
	float tone = v_inst.y;
	// Fine detail fades to its mean under a pixel.
	float px = max(length(fwidth(uv)), 1e-4);
	float fine = 1.0 - smoothstep(0.004, 0.02, px);
	if (v_kind < 0.5) {
		// The pole: grain running up it, checks (drying cracks) as long dark lines, a creosote
		// brown weathering to silver grey in patches, darker and stained round the ground line.
		float grain = vnoise(vec2(uv.x * 38.0, uv.y * 0.7)) * 0.55 + vnoise(vec2(uv.x * 150.0, uv.y * 2.5)) * 0.45;
		grain = mix(0.5, grain, fine);
		float check = smoothstep(0.03, 0.0, abs(vnoise(vec2(uv.x * 7.0 + tone * 13.0, uv.y * 0.22)) - 0.5));
		check *= smoothstep(0.3, 0.7, vnoise(vec2(uv.x * 3.0, uv.y * 0.5 + 7.0)));
		vec3 brown = v_paint * mix(0.78, 1.12, tone);
		float silver = clamp(age * 0.9 - 0.15 + (vnoise(uv * vec2(2.0, 0.35) + tone * 5.0) - 0.5) * 0.6, 0.0, 1.0);
		alb = mix(brown, weathered, silver);
		alb *= 0.8 + 0.4 * grain;
		alb *= 1.0 - 0.6 * check * mix(0.4, 1.0, fine);
		float ground = 1.0 - smoothstep(0.05, 0.6, uv.y);
		alb *= 1.0 - 0.5 * ground;
		// Old staples and flyer paper scraps at hand height.
		float band = step(1.0, uv.y) * step(uv.y, 2.6);
		float staple = step(0.994, h12(floor(uv * vec2(90.0, 70.0)))) * band * fine;
		alb = mix(alb, vec3(0.12, 0.1, 0.08), staple);
		metal = staple * 0.5;
		rough = mix(0.88, 0.75, silver * 0.2);
	} else if (v_kind < 1.5) {
		// The crossarm: Douglas fir, grain along it, weathered paler than the pole.
		float grain = vnoise(vec2(uv.x * 1.5, uv.y * 90.0)) * 0.5 + vnoise(vec2(uv.x * 4.0, uv.y * 300.0)) * 0.5;
		alb = v_paint * (0.78 + 0.4 * mix(0.5, grain, fine)) * mix(0.85, 1.05, tone);
		rough = 0.85;
	} else if (v_kind < 2.5) {
		// Galvanised steel: dull spangle, a little white rust.
		float sp = vnoise(uv * 160.0);
		alb = v_paint * (0.8 + 0.3 * mix(0.5, sp, fine));
		metal = 0.7;
		rough = 0.42 + 0.2 * vnoise(uv * 23.0);
	} else if (v_kind < 3.5) {
		// Glazed porcelain: glossy, a little dust on what faces up.
		alb = v_paint;
		rough = 0.16;
		spec = 0.6;
	} else if (v_kind < 4.5) {
		alb = v_paint;
		rough = 0.55;
	} else if (v_kind < 5.5) {
		// Painted steel (the transformer can, the luminaire, the meter): grime streaks.
		float streak = vnoise(vec2(uv.x * 18.0, uv.y * 0.8));
		alb = v_paint * (0.86 + 0.18 * streak);
		rough = 0.42 + 0.15 * streak;
		metal = 0.15;
	} else if (v_kind < 6.5) {
		alb = v_paint;
		rough = 0.55;
	} else if (v_kind < 7.5) {
		// The guy guard: yellow plastic, dirtier near the ground.
		alb = v_paint * (0.75 + 0.25 * smoothstep(0.0, 1.0, uv.y));
		rough = 0.45;
	} else if (v_kind < 8.5) {
		// The aluminium tag, with embossed digit rows.
		float rows = step(0.5, fract(uv.y * 30.0)) * step(0.3, fract(uv.x * 40.0));
		alb = v_paint * (0.85 + 0.15 * rows * fine);
		metal = 0.85;
		rough = 0.35;
	} else if (v_kind < 9.5) {
		// The street light's lens: frosted glass, lit at night.
		alb = v_paint * 0.6;
		rough = 0.25;
		emit = vec3(1.0, 0.72, 0.42) * lens_energy * smoothstep(0.2, 0.6, lamp_factor);
	} else {
		// Glass (the meter's dome).
		alb = vec3(0.05);
		rough = 0.05;
		spec = 0.7;
	}
	// Rain darkens and glosses what is out in it.
	float wet = clamp(road_wetness, 0.0, 1.0);
	alb *= 1.0 - 0.3 * wet * (1.0 - metal);
	rough = mix(rough, rough * 0.45, wet);
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = cs_out(emit);
}
