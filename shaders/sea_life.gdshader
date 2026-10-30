// The life in the water (scripts/world/sea_life.gd, meshes from scripts/world/sea_life_mesh.gd):
// dolphins, sea lions, pelicans, a grey whale and the harbour buoy, one MultiMesh per kind and
// level of detail, one material per kind (`kind`). The motion is here, in the vertex stage, from
// the instance's numbers; SeaLife only places and turns each animal.
//
// What a vertex is: COLOR.a * 16 (SeaLifeMesh.P_*: 0 body, 1 fin, 2 jaw, 3 wing, 4 bill, 5 paint,
// 6 lamp, 7 deck, 8 metal). COLOR.rgb is the linear albedo, times the instance colour (a tint;
// its alpha stays 1, or the part code is lost). UV.x the fraction of the body's length from the
// nose; UV.y a wing vertex's span fraction from the shoulder.
// Per instance, INSTANCE_CUSTOM:
//   dolphin, whale: .x tail beat phase (0..1), .y beat amplitude (0..1), .z the whale's fluke lift
//   sea lion: .x head lift (0 lying .. 1 head up), .y head turn (-1..1), .z bark (jaw open 0..1),
//             .w breathing phase
//   pelican: .x wingbeat phase, .y flap amplitude (0 a glide), .z wing fold (0 spread .. 1 folded)
//   buoy: .x the lantern's flash phase
// Works in linear on both renderers (color_space.gdshaderinc). Shader files use // comments.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;

// 0 dolphin, 1 sea lion, 2 pelican, 3 whale, 4 buoy.
uniform int kind = 0;
// The tail beat: where the stock starts to move (z), where the flukes end, how far the tip
// travels at full amplitude (metres), and how many radians of phase per metre down the body.
uniform float hinge = 0.15;
uniform float tail_end = 1.35;
uniform float beat_reach = 0.16;
uniform float beat_wave = 1.4;
// The sea lion's neck pivot and the jaw's hinge.
uniform vec3 neck = vec3(0.0, 0.2, -0.5);
uniform vec3 jaw_hinge = vec3(0.0, 0.2, -0.75);
// The pelican's shoulder (right side), its wrist's x, the wingbeat (radians) and its bias.
uniform vec3 shoulder = vec3(0.1, 0.07, -0.12);
uniform float wrist_x = 0.55;
uniform float flap_angle = 0.6;
uniform float flap_bias = 0.05;
// The eye (right side, mirrored), its radius.
uniform vec3 eye_pos = vec3(0.13, 0.03, -0.98);
uniform float eye_r = 0.018;
// Surfaces.
uniform float body_roughness = 0.24;
uniform float body_specular = 0.6;
uniform vec3 lamp_color = vec3(0.1, 1.0, 0.25);

varying vec3 v_model;
varying float v_part;
varying vec3 v_col;
varying float v_lamp;

vec3 rot_x(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

vec3 rot_y(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

vec3 rot_z(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

// The tail beat's vertical displacement at z (the body bends as a travelling wave, growing to
// the flukes).
float beat(float z, float phase, float amp) {
	float w = smoothstep(hinge, tail_end, z);
	return amp * beat_reach * w * w * sin(6.2831853 * phase - (z - hinge) * beat_wave);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 p = VERTEX;
	vec3 n = NORMAL;
	float part = floor(COLOR.a * 16.0 + 0.5);
	v_model = VERTEX;
	v_part = part;
	v_col = COLOR.rgb;
	vec4 ic = INSTANCE_CUSTOM;
	v_lamp = ic.x;
	if (kind == 0 || kind == 3) {
		float d = beat(p.z, ic.x, ic.y);
		float slope = (beat(p.z + 0.05, ic.x, ic.y) - beat(p.z - 0.05, ic.x, ic.y)) / 0.1;
		if (kind == 3) {
			// The whale's terminal dive: the tail stock bends up and the flukes come out.
			float w = smoothstep(hinge, tail_end, p.z);
			d += ic.z * 2.2 * w * w;
			slope += ic.z * 4.4 * w * (1.0 / max(tail_end - hinge, 0.1)) * step(hinge, p.z);
		}
		p.y += d;
		n = normalize(vec3(n.x, n.y, n.z - n.y * slope));
	} else if (kind == 1) {
		// Breathing: the barrel swells and settles.
		float torso = smoothstep(neck.z, neck.z + 0.3, p.z) * (1.0 - smoothstep(0.4, 0.8, p.z));
		p.xy = mix(p.xy, vec2(p.x * 1.025, neck.y * 0.6 + (p.y - neck.y * 0.6) * 1.02), torso * (0.5 + 0.5 * sin(6.2831853 * ic.w)));
		// Propped up on the fore flippers: the chest rises as the head lifts.
		float chest = smoothstep(0.15, -0.35, p.z);
		p.y += ic.x * 0.13 * chest * step(part, 2.5);
		if (part == 2.0) {
			vec3 q = rot_x(p - jaw_hinge, -ic.z * 0.55);
			p = jaw_hinge + q;
			n = rot_x(n, -ic.z * 0.55);
		}
		float head = smoothstep(neck.z + 0.1, neck.z - 0.1, p.z) * step(part, 2.5);
		vec3 pv = neck + vec3(0.0, ic.x * 0.13, 0.0);
		vec3 q = rot_x(p - pv, ic.x * 0.75 + ic.z * 0.25);
		q = rot_y(q, ic.y * 0.7);
		p = mix(p, pv + q, head);
		n = normalize(mix(n, rot_y(rot_x(n, ic.x * 0.75 + ic.z * 0.25), ic.y * 0.7), head));
	} else if (kind == 2 && part == 3.0) {
		// The wing: the hand folds back at the wrist, the arm sweeps back and down at the
		// shoulder as the wing folds; spread, the arm beats about the shoulder and the hand
		// follows it a little late.
		float s = sign(p.x);
		vec3 q = vec3(abs(p.x), p.y, p.z);
		vec3 m = vec3(abs(n.x) * sign(n.x) * s, n.y, n.z);
		float beat_a = flap_bias + ic.y * flap_angle * sin(6.2831853 * ic.x);
		float hand_a = ic.y * flap_angle * 0.55 * sin(6.2831853 * ic.x - 0.9);
		float fold = ic.z;
		if (q.x > wrist_x) {
			vec3 w0 = vec3(wrist_x, shoulder.y, q.z);
			float hand_w = smoothstep(wrist_x, wrist_x + 0.08, q.x);
			q = w0 + rot_y(rot_z(q - w0, hand_a * hand_w), -fold * 2.6 * hand_w);
			m = rot_y(rot_z(m, hand_a * hand_w), -fold * 2.6 * hand_w);
		}
		vec3 sq = q - shoulder;
		sq = rot_z(sq, beat_a * (1.0 - fold) - fold * 0.3);
		sq = rot_y(sq, -fold * 1.3);
		m = rot_y(rot_z(m, beat_a * (1.0 - fold) - fold * 0.3), -fold * 1.3);
		q = shoulder + sq;
		p = vec3(q.x * s, q.y, q.z);
		n = normalize(vec3(m.x * s, m.y, m.z));
	}
	VERTEX = p;
	NORMAL = n;
}

void fragment() {
	vec3 alb = v_col;
	float rough = body_roughness;
	float spec = body_specular;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float part = floor(v_part + 0.5);
	vec3 m = v_model;
	if (kind == 0) {
		// A dolphin: faint mottling and the pale rake scars of other dolphins' teeth.
		float mot = noise3(m * vec3(9.0, 9.0, 3.0));
		alb *= 0.9 + 0.2 * mot;
		float rake = smoothstep(0.93, 0.99, sin(m.z * 140.0 + noise3(m * 11.0) * 6.0)) * smoothstep(0.55, 0.8, noise3(m * vec3(3.0, 3.0, 1.5)));
		alb = mix(alb, alb * 1.9 + 0.03, rake * 0.6);
	} else if (kind == 1) {
		// A sea lion's short fur: a fine streak along the body, wet and glossy where it drips.
		float fur = noise3(m * vec3(60.0, 60.0, 14.0));
		alb *= 0.82 + 0.3 * fur;
		rough = 0.42 - 0.12 * fur;
		spec = 0.45;
	} else if (kind == 2) {
		rough = 0.82;
		spec = 0.3;
		if (part == 3.0) {
			// Feathers: the shafts and vanes as streaks along the chord.
			float vane = 0.5 + 0.5 * sin((m.z * 3.0 + UV.y * 1.5) * 90.0);
			float px = fwidth(m.z * 270.0);
			alb *= mix(0.88 + 0.2 * vane, 0.98, clamp(px, 0.0, 1.0));
		} else if (part == 4.0) {
			rough = 0.5;
		} else {
			alb *= 0.85 + 0.3 * noise3(m * 70.0);
		}
	} else if (kind == 3) {
		// A grey whale's skin: mottled, with white barnacle clusters and orange whale lice on the
		// head and back, pale scars.
		float mot = noise3(m * 0.9) * 0.6 + noise3(m * 3.1) * 0.4;
		alb *= 0.65 + 0.8 * mot;
		float barn = smoothstep(0.66, 0.74, noise3(m * vec3(1.6, 2.0, 1.2)) * 0.7 + noise3(m * 7.0) * 0.3) * smoothstep(-0.2, 0.6, m.y);
		alb = mix(alb, vec3(0.5, 0.49, 0.45), barn * 0.8);
		alb = mix(alb, vec3(0.42, 0.2, 0.08), barn * smoothstep(0.6, 0.8, noise3(m * 13.0)) * 0.5);
		rough = mix(0.28, 0.7, barn);
	} else if (kind == 4) {
		rough = 0.55;
		spec = 0.4;
		float up = clamp(NORMAL.y, 0.0, 1.0);
		if (part == 5.0) {
			// Paint, faded and run with rust from every joint and edge, streaking down.
			float streak = noise3(vec3(m.x * 9.0, m.y * 0.6, m.z * 9.0));
			alb = mix(alb, vec3(0.13, 0.05, 0.02), smoothstep(0.55, 0.85, streak) * 0.75);
			alb *= 0.85 + 0.25 * noise3(m * 4.0);
			// Guano on the tower's ledges and the rim.
			alb = mix(alb, vec3(0.62, 0.6, 0.53), smoothstep(0.45, 0.8, noise3(m * 6.0)) * smoothstep(0.75, 1.0, m.y) * 0.5);
		} else if (part == 7.0) {
			// The deck: a crust of guano over the steel.
			float g = noise3(m * 3.0) * 0.6 + noise3(m * 17.0) * 0.4;
			alb = mix(vec3(0.16, 0.15, 0.13), vec3(0.6, 0.58, 0.5), smoothstep(0.35, 0.6, g));
			rough = 0.85;
		} else if (part == 8.0) {
			metal = 0.5;
			rough = 0.5;
			alb *= 0.8 + 0.4 * noise3(m * 12.0);
		} else if (part == 6.0) {
			// The lantern: a green flash every four seconds (a second of it), seen properly once
			// it is dark.
			float f = step(fract(TIME / 4.0 + v_lamp), 0.25);
			rough = 0.1;
			alb = vec3(0.12, 0.2, 0.13);
			emit = lamp_color * f * (0.3 + 5.0 * night_factor);
		}
		alb *= 1.0 - 0.12 * up * (1.0 - float(part == 7.0));
	}
	if (kind != 4 && kind != 2 && distance(vec3(abs(m.x), m.y, m.z), eye_pos) < eye_r) {
		alb = vec3(0.006);
		rough = 0.08;
		spec = 0.8;
	}
	if (!FRONT_FACING) {
		// Inside the mouth (the sea lion's open jaw) or a wet fin's underside seen through a seam.
		alb = kind == 1 ? vec3(0.09, 0.02, 0.02) : alb * 0.6;
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
