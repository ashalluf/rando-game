shader_type spatial;
render_mode cull_back;

// The kerb and gutter up close (scripts/world/street_closeup.gd): what a pedestrian's eye finds
// first at the edge of a downtown pavement. Three surfaces on one shader:
//   * mode 0 (UV2.x 0): the kerb FACE, which Kerbs used to draw in the pavement's material - a
//     flat grey band, because that material is projected from above and has nothing to show on a
//     vertical face. UV is (metres along the kerb, metres over the road top).
//   * mode 1 (UV2.x 1): the ARRIS, a 2.5 cm strip over the kerb's top edge whose normal turns from
//     the face to up across it, so the edge reads as the rounded one a kerb form leaves, not a
//     razor. UV is (metres along, 0 at the edge .. 1 inward).
//   * mode 2 (the `gutter` uniform): the concrete GUTTER PAN Los Angeles pours with its kerb (curb
//     and gutter), in place of the dark strip on the asphalt it was. A MultiMesh box: across from
//     the box's own x (INSTANCE_CUSTOM.r says which side the kerb is), along from true world.
// All three share the kerb's 10 ft joints, so the joints run on from face to pan. Works in linear
// on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.95, 0.94, 0.92);
uniform float tex_scale = 3.0;
uniform bool gutter = false;
// The joint pitch (10 ft) and the pan's width (m).
uniform float joint_pitch = 3.05;
uniform float pan_width = 0.6;
// Kerb height over the road (CityChunk.SIDEWALK_TOP - ROAD_TOP).
uniform float kerb_h = 0.15;
// How far the arris strip draws (it lies 2 mm over the pavement: past this it would z-fight).
uniform float arris_reach = 28.0;

global uniform float road_wetness;
global uniform vec3 origin_shift;

varying vec3 v_world;
varying vec3 v_local;
varying float v_side;
varying vec3 v_along;

float kc_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float kc_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(kc_hash(i), kc_hash(i + vec2(1.0, 0.0)), f.x),
		mix(kc_hash(i + vec2(0.0, 1.0)), kc_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float kc_fbm(vec2 p) {
	return 0.5 * kc_noise(p) + 0.3 * kc_noise(p * 2.13 + 7.1) + 0.2 * kc_noise(p * 4.41 + 3.3);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX;
	v_side = 1.0;
	v_along = normalize(MODEL_MATRIX[2].xyz);
	if (gutter) {
		v_side = INSTANCE_CUSTOM.r > 0.5 ? 1.0 : -1.0;
	}
}

// A joint across the kerb at every `joint_pitch` of `along`: 0 in the joint's 6 mm, 1 clear of it,
// faded to its average once the joint is under a pixel.
float kc_joint(float along, float px) {
	float d = abs(fract(along / joint_pitch + 0.5) - 0.5) * joint_pitch;
	float w = 0.004 + px * 0.5;
	float j = smoothstep(w, w + px + 0.002, d);
	return mix(j, 1.0, smoothstep(0.02, 0.08, px));
}

void fragment() {
	vec3 tw = v_world + origin_shift;
	float px = length(fwidth(tw));
	float mode = gutter ? 2.0 : floor(UV2.x + 0.5);
	vec3 n_geo = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 n_w = n_geo;
	float along;
	vec2 tuv;
	float shade = 1.0;
	float rough = 0.86;
	if (mode < 0.5) {
		// The face: UV (along, height over road).
		along = UV.x;
		float h = UV.y;
		tuv = vec2(along, h * 1.0 + 0.37) / tex_scale;
		// The rounded top edge: over the top 2.5 cm the normal turns up a quarter circle.
		float r = clamp((h - (kerb_h - 0.025)) / 0.025, 0.0, 1.0);
		float ang = asin(r) * 0.5;
		n_w = normalize(n_geo * cos(ang) + up * sin(ang));
		// Grime at the foot, where the gutter's water and grit sit; road splash up to 7 cm.
		float foot = 1.0 - smoothstep(0.0, 0.035 + 0.02 * kc_noise(vec2(along * 3.0, 1.0)), h);
		float splash = (1.0 - smoothstep(0.01, 0.075, h)) * kc_fbm(vec2(along * 6.0, h * 30.0));
		shade *= mix(1.0, 0.42, foot) * mix(1.0, 0.8, splash);
		// Tyre scuffs: black rubber streaks where a wheel rubbed the kerb parking, now and then.
		float cell = floor(along / 2.3);
		float hit = kc_hash(vec2(cell, 17.0));
		if (hit < 0.32) {
			float c0 = (cell + 0.15 + 0.4 * kc_hash(vec2(cell, 3.0))) * 2.3;
			float len = 0.4 + 1.1 * kc_hash(vec2(cell, 5.0));
			float hy = 0.035 + 0.06 * kc_hash(vec2(cell, 9.0));
			float in_span = smoothstep(c0, c0 + 0.25, along) * (1.0 - smoothstep(c0 + len - 0.3, c0 + len, along));
			float band = 1.0 - smoothstep(0.012, 0.03, abs(h - hy) + 0.01 * kc_noise(vec2(along * 9.0, 0.0)));
			float streak = 0.55 + 0.45 * kc_noise(vec2(along * 40.0, h * 200.0));
			shade *= 1.0 - 0.78 * in_span * band * streak;
		}
		// Chips knocked out of the arris by bumpers and boards: darker, rough, flat-faced.
		float chip_cell = floor(along / 0.37);
		float chip = kc_hash(vec2(chip_cell, 41.0));
		if (chip < 0.18 && h > kerb_h - 0.04) {
			float cx = (chip_cell + 0.3 + 0.4 * kc_hash(vec2(chip_cell, 2.0))) * 0.37;
			float size = 0.012 + 0.03 * kc_hash(vec2(chip_cell, 8.0));
			float d = length(vec2((along - cx) * 0.6, (kerb_h - h) * 1.2));
			float in_chip = 1.0 - smoothstep(size, size + 0.004, d);
			shade *= 1.0 - 0.32 * in_chip;
			n_w = normalize(mix(n_w, normalize(n_geo + up * 0.4), in_chip));
		}
	} else if (mode < 1.5) {
		// The arris strip on top of the kerb.
		float dist = length(tw - (CAMERA_POSITION_WORLD + origin_shift));
		if (dist > arris_reach) {
			discard;
		}
		along = UV.x;
		float s = clamp(UV.y, 0.0, 1.0);
		tuv = vec2(along, kerb_h + 0.37 + s * 0.025) / tex_scale;
		// The outward direction is the strip's own across-gradient's opposite; the vertex
		// normal carries it (Kerbs writes the face's outward normal on the strip's outer edge).
		vec3 outw = normalize(vec3(n_geo.x, 0.0, n_geo.z) + vec3(1e-5, 0.0, 0.0));
		// From 45 degrees at the edge to up inward: the rest of the quarter circle the face's
		// own top band starts.
		float ang = (1.0 - s) * 0.785398;
		n_w = normalize(up * cos(ang) + outw * sin(ang));
		shade *= 0.97;
	} else {
		// The gutter pan: across 0 at the kerb face, `pan_width` at the asphalt.
		float half_w = pan_width * 0.5;
		float across = half_w - v_local.x * v_side;
		along = dot(tw.xz, normalize(v_along.xz));
		tuv = vec2(along, across + 11.3) / tex_scale;
		// Dished toward the kerb (the flow line): a 1:12 fall in the normal.
		// The kerb lies toward -across, which is +v_side along the box's local x.
		vec3 lx = normalize(vec3(MODEL_MATRIX[0].x, 0.0, MODEL_MATRIX[0].z)) * v_side;
		n_w = normalize(up + lx * 0.08 * (1.0 - smoothstep(0.0, pan_width, across)) - lx * 0.04 * smoothstep(pan_width - 0.08, pan_width, across));
		// The flow line: silt, leaves' tea stain and old water marks along the kerb.
		float wob = kc_fbm(vec2(along * 0.7, 3.0));
		float flow = 1.0 - smoothstep(0.04, 0.16 + 0.12 * wob, across);
		float tide = (1.0 - smoothstep(0.004, 0.012, abs(across - (0.18 + 0.1 * wob)))) * 0.5;
		float silt = kc_fbm(vec2(along * 2.3, across * 9.0)) * flow;
		shade *= mix(1.0, 0.55, flow * 0.85) * (1.0 - tide * 0.3) * mix(1.0, 0.82, silt);
		// Oil and tyre grime where parked cars stand over its outer half.
		float oil = smoothstep(0.55, 0.85, kc_fbm(vec2(along * 0.35, across * 1.5 + 5.0))) * smoothstep(0.2, 0.5, across);
		shade *= 1.0 - 0.35 * oil;
		// The seam with the asphalt: a dark sealed line, the asphalt's ravelled edge over it.
		float seam = 1.0 - smoothstep(0.006 + px, 0.014 + px * 2.0, pan_width - across);
		shade *= 1.0 - 0.6 * seam;
		rough = mix(0.84, 0.92, silt);
	}
	// The concrete: the pavement's own texture and tint, sampled across the face.
	vec3 base = cs_in(texture(albedo_tex, tuv).rgb) * cs_in(tint);
	// Kerbs and gutters are poured, not paved: a smoother, slightly warmer grey than the slabs,
	// mottled by the pour and weathered.
	float mott = kc_fbm(vec2(along * 0.45, 2.0 + mode * 9.0));
	base *= mix(0.86, 1.04, mott);
	base = mix(base, base * vec3(1.02, 1.0, 0.96), 0.5);
	// The joints, which run on from face to arris to pan.
	float j = kc_joint(along, px);
	shade *= mix(0.35, 1.0, j);
	vec3 col = base * shade;
	// Wet: darker, glossier, the flow line wettest.
	float wet = clamp(road_wetness, 0.0, 1.0);
	col *= 1.0 - 0.35 * wet;
	rough = mix(rough, 0.25, wet * 0.8);
	// Fine relief from the texture's normal map (no tangents here: a small tilt in world space).
	vec3 tn = texture(normal_tex, tuv).rgb * 2.0 - 1.0;
	float fine = 1.0 - smoothstep(0.004, 0.02, px);
	if (mode > 1.5) {
		vec3 t1 = normalize(vec3(v_along.x, 0.0, v_along.z));
		vec3 t2 = normalize(cross(up, t1));
		n_w = normalize(n_w + (t1 * tn.x + t2 * tn.y) * 0.35 * fine);
	} else {
		vec3 t1 = normalize(cross(up, n_geo) + vec3(1e-5, 0.0, 0.0));
		n_w = normalize(n_w + (t1 * tn.x + up * tn.y) * 0.25 * fine);
	}
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_w, 0.0)).xyz);
}
