shader_type spatial;

// The oil field's pumpjacks (OilKit.pumpjack(), batched per chunk by OilFieldBuild): the whole
// unit is one mesh and its moving parts are animated HERE, so a field of them nodding out of step
// costs nothing on the CPU. UV2.x says which part a vertex belongs to (OilKit's header):
//   1 walking beam, horsehead and equalizer - rock about the saddle bearing by `beam`
//   2 crank, counterweights, wrist pins - turn about the crank shaft by `phi`
//   3 pitman arm - rebuilt between the turning wrist pin and the rocking equalizer (UV2.y: 0 at
//     the pin .. 1 at the equalizer), its cross-section turned with it
//   4 bridle - the wire rope leaves the horsehead's arc plumb over the well at the pivot's height
//     (the arc is centred on the pivot) and runs down to the carrier bar, which rides the arc's
//     length: its foot moves FRONT * beam, its top not at all (UV2.y: 0 at the bar .. 1 at the top)
//   5 carrier bar and polished rod - slide FRONT * beam
// The beam follows the wrist pin: the tail's height tracks the pin's (sin(beam) = -R sin(phi) / TAIL),
// so the pitman keeps its length to a few centimetres through the stroke.
// INSTANCE_CUSTOM: r the crank's phase (turns), g strokes per minute / 20 (0 = an idle unit),
// b the unit's wear, a its paint (OilKit.PAINTS index / 8; the copy below - checked). The instance
// colour stays white: a MultiMesh's instance colour multiplies every vertex colour, valves and
// motor included. COLOR.rgb is the vertex's own colour (display numbers); COLOR.a the kind in 16ths:
//   0 paint  1 dark paint (base, arms)  2 bare steel  3 concrete  4 safety yellow  5 polished rod
//   6 wire rope  7 its own colour (motor, valves, wellhead)  8 counterweight (paint, a warning
//   stripe on its edge)

global uniform float road_wetness;

uniform vec2 pivot = vec2(-3.9, 6.3);
uniform vec2 crank = vec2(-7.4, 2.45);
uniform float front = 3.9;
uniform float tail = 3.5;
uniform float crank_r = 1.15;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

varying float kind;
varying vec3 local_p;
varying float wear;
varying vec3 paint_v;
varying vec3 world_p;

// OilKit.PAINTS, display numbers (tests/oil_field_checks.gd holds them equal).
const vec3 PAINTS[7] = vec3[7](vec3(0.52, 0.55, 0.50), vec3(0.62, 0.57, 0.47), vec3(0.36, 0.45, 0.55), vec3(0.38, 0.46, 0.36), vec3(0.56, 0.24, 0.18), vec3(0.74, 0.71, 0.62), vec3(0.47, 0.49, 0.47));

#include "res://shaders/color_space.gdshaderinc"

// Tuned in display numbers (the paint in COLOR is written that way); handed to the renderer in
// its own space at the end (the industrial walls' convention).
vec3 to_lit(vec3 c) {
	return cs_linear_renderer() ? cs_srgb_to_linear(c) : c;
}

vec3 disp(vec3 c) {
	return cs_linear_renderer() ? cs_linear_to_srgb(c) : c;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

void vertex() {
	kind = floor(COLOR.a * 16.0);
	float part = floor(UV2.x + 0.5);
	float t = UV2.y;
	float spm = INSTANCE_CUSTOM.g * 20.0;
	float phi = INSTANCE_CUSTOM.r * TAU + TIME * spm / 60.0 * TAU;
	float beam = asin(clamp(-crank_r * sin(phi) / tail, -1.0, 1.0));
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	if (part > 0.5 && part < 1.5) {
		v.xy = pivot + rot(v.xy - pivot, beam);
		n.xy = rot(n.xy, beam);
	} else if (part > 1.5 && part < 2.5) {
		v.xy = crank + rot(v.xy - crank, phi);
		n.xy = rot(n.xy, phi);
	} else if (part > 2.5 && part < 3.5) {
		vec2 a0 = crank + vec2(crank_r, 0.0);
		vec2 b0 = pivot + vec2(-tail, 0.0);
		vec2 a1 = crank + crank_r * vec2(cos(phi), sin(phi));
		vec2 b1 = pivot + rot(vec2(-tail, 0.0), beam);
		vec2 axis0 = a0 + (b0 - a0) * t;
		vec2 off = v.xy - axis0;
		float turn = atan(b1.y - a1.y, b1.x - a1.x) - atan(b0.y - a0.y, b0.x - a0.x);
		v.xy = a1 + (b1 - a1) * t + rot(off, turn);
		n.xy = rot(n.xy, turn);
	} else if (part > 3.5 && part < 4.5) {
		v.y += (1.0 - t) * front * beam;
	} else if (part > 4.5) {
		v.y += front * beam;
	}
	local_p = v;
	VERTEX = v;
	NORMAL = n;
	wear = INSTANCE_CUSTOM.b;
	float painted = step(kind, 1.5) + step(7.5, kind);
	vec3 paint = PAINTS[clamp(int(INSTANCE_CUSTOM.a * 8.0 + 0.5), 0, 6)];
	paint_v = COLOR.rgb * mix(vec3(1.0), paint, painted);
	world_p = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
}

void fragment() {
	vec3 inst = paint_v;
	vec3 albedo = inst;
	float rough = 0.6;
	float metal = 0.25;
	float spec = 0.5;
	// Weathering in the unit's own frame, so it stays put as the parts move past.
	float n1 = vnoise(UV * 3.1 + local_p.xz * 0.7);
	float n2 = vnoise(UV * 11.0);
	float low = 1.0 - smoothstep(0.0, 1.6, local_p.y);
	if (kind < 1.5) {
		// Paint: chalky where the sun has had it, chipped to rust on the edges and the foot,
		// streaks of grease and oil running down under the bearings.
		float dark = kind > 0.5 ? 0.6 : 1.0;
		albedo = inst * dark * (0.88 + 0.16 * n1);
		float chalk = smoothstep(0.45, 0.9, vnoise(UV * 0.8 + 3.0)) * 0.12 * (1.0 + wear);
		albedo = mix(albedo, vec3(0.78, 0.76, 0.72), chalk);
		// Rust in fine flecks and runs down the faces (streaks: stretched along the face's height),
		// thicker low down and on a worn unit.
		float fleck = smoothstep(0.86 - 0.08 * wear, 0.97, vnoise(UV * 13.0 + 7.0) * 0.7 + n2 * 0.3);
		float run = smoothstep(0.78, 0.96, vnoise(vec2(UV.x * 9.0, UV.y * 1.2) + 3.0)) * (0.35 + 0.4 * wear);
		float rust = fleck + run * 0.6 + low * 0.3 * wear;
		albedo = mix(albedo, vec3(0.34, 0.19, 0.11), clamp(rust, 0.0, 0.8));
		float grease = smoothstep(0.7, 0.95, vnoise(vec2(UV.x * 6.0, UV.y * 0.6) + 11.0)) * 0.5;
		albedo *= 1.0 - grease * 0.55;
		rough = mix(0.55, 0.85, rust) - grease * 0.3;
		metal = 0.15;
	} else if (kind < 2.5) {
		albedo = inst * (0.85 + 0.25 * n1);
		rough = 0.45;
		metal = 0.65;
	} else if (kind < 3.5) {
		vec3 c = disp(texture(concrete_tex, UV / 2.2).rgb);
		albedo = inst * (0.6 + 0.5 * dot(c, vec3(0.333)));
		// Oil soaked into the foundation round the wellhead and under the gearbox.
		float soak = smoothstep(2.4, 0.4, length(local_p.xz)) + smoothstep(1.6, 0.3, length(local_p.xz - vec2(crank.x, 0.0))) * 0.6;
		soak *= 0.55 + 0.45 * n1;
		albedo *= 1.0 - 0.6 * clamp(soak, 0.0, 1.0);
		rough = mix(0.9, 0.45, clamp(soak, 0.0, 1.0));
		metal = 0.0;
	} else if (kind < 4.5) {
		albedo = inst * (0.86 + 0.18 * n1);
		float chip = smoothstep(0.7, 0.92, n2);
		albedo = mix(albedo, vec3(0.3, 0.29, 0.28), chip * 0.7);
		rough = 0.6;
		metal = 0.1;
	} else if (kind < 5.5) {
		// The polished rod: wiped bright by the stuffing box every stroke.
		albedo = vec3(0.82);
		rough = 0.15;
		metal = 1.0;
	} else if (kind < 6.5) {
		albedo = inst * (0.8 + 0.3 * vnoise(vec2(UV.y * 40.0, 0.0)));
		rough = 0.5;
		metal = 0.7;
	} else if (kind < 7.5) {
		albedo = inst * (0.9 + 0.15 * n1);
		rough = 0.55;
		metal = 0.3;
	} else {
		// Counterweight: the paint, with a yellow-and-black warning stripe round its edge.
		albedo = inst * 0.7 * (0.9 + 0.15 * n1);
		float d = length(local_p.xy - crank);
		float edge = smoothstep(0.84, 0.9, d);
		float stripe = step(0.5, fract((local_p.x + local_p.y) * 2.5));
		albedo = mix(albedo, mix(vec3(0.82, 0.64, 0.1), vec3(0.07), stripe), edge * 0.9);
		rough = 0.6;
		metal = 0.15;
	}
	// Dust thrown up from the pad on everything low.
	albedo = mix(albedo, vec3(0.6, 0.53, 0.43), low * 0.35 * (0.5 + 0.5 * n1) * step(kind, 2.5));
	float wet = clamp(road_wetness, 0.0, 1.0) * 0.5;
	albedo *= 1.0 - 0.25 * wet;
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	ROUGHNESS = clamp(mix(rough, 0.2, wet), 0.05, 1.0);
	METALLIC = metal;
	SPECULAR = spec;
}
