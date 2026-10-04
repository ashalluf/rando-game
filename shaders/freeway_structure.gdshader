shader_type spatial;
render_mode cull_back;

// Everything structural on a freeway deck (FreewayKit's `body` mesh): the box girder, the New
// Jersey barriers, the bents, the gantries, light standards, roadside furniture. One material for
// all of it; what a vertex IS rides in its colour's alpha (FreewayKit.S_*, alpha * 32), its base
// colour (sRGB) in the rgb. UV is (metres along the route or across a face, metres up the
// feature); UV2.x is a flag (1 = a barrier face the traffic sees; a lens's brightness), UV2.y a
// box's total height.
//
// Concrete is the Concrete034 scan projected triplanar on the mesh's own (true world) position,
// as detail round the vertex colour, plus pours that differ in tone, then the weather: grime at
// the foot of every barrier, black tyre scuffs along the faces the traffic sees, drip streaks
// off every top, rust bleeding down the fascia under each scupper (SCUPPER_SPACING, the grates
// FreewayKit lays at the barrier toe) and down the columns from the bent cap, soot and
// efflorescence on the soffit, splash dirt at the column feet. Steel is galvanised (mottled
// zinc), lenses glow off `lamp_factor`.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D concrete_rough : filter_linear_mipmap, repeat_enable;
// Metres per tile of the concrete scan, and its mean (LINEAR, PropFactory.TEXTURE_MEAN).
uniform float tex_metres = 3.0;
uniform float tex_mean = 0.4818;
// How much of the scan's variation reaches the albedo (0 = flat vertex colour).
uniform float tex_detail = 0.65;
// Linear colours the weathering darkens toward.
uniform vec3 grime_color = vec3(0.075, 0.066, 0.055);
uniform vec3 rust_color = vec3(0.20, 0.085, 0.030);
uniform vec3 scuff_color = vec3(0.018, 0.018, 0.019);
uniform float grime_amount = 0.55;
uniform float scuff_amount = 0.75;
uniform float rust_amount = 0.7;
// Scuppers along the fascia (FreewayKit.SCUPPER_SPACING; grates at along = k * spacing + spacing / 2).
uniform float scupper_spacing = 12.0;
// Contraction joints in the slip-formed barrier, metres apart.
uniform float barrier_joint = 6.1;
// Lamp lenses: emission at full lamp_factor.
uniform float lens_energy = 9.0;

varying vec3 obj_pos;
varying vec3 obj_nrm;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}


float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.11 + 3.3) * 0.2;
}


void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}


void fragment() {
	int kind = int(round(COLOR.a * 32.0));
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float along = UV.x;
	float h = UV.y;
	float flag = UV2.x;
	vec3 an = abs(normalize(obj_nrm));
	vec3 w = pow(an, vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 px = obj_pos.zy / tex_metres;
	vec2 py = obj_pos.xz / tex_metres;
	vec2 pz = obj_pos.xy / tex_metres;
	vec3 tex = cs_in(texture(concrete_tex, px).rgb) * w.x + cs_in(texture(concrete_tex, py).rgb) * w.y
		+ cs_in(texture(concrete_tex, pz).rgb) * w.z;
	float trough = texture(concrete_rough, px).r * w.x + texture(concrete_rough, py).r * w.y + texture(concrete_rough, pz).r * w.z;
	float tl = dot(tex, vec3(0.3333)) / tex_mean;
	// Pours: big soft patches a shade lighter or darker.
	float pour = fbm(obj_pos.xz * 0.06 + obj_pos.y * 0.04);
	vec3 conc = base * mix(1.0, tl, tex_detail) * (0.86 + 0.28 * pour);
	vec3 alb = conc;
	float rough = clamp(0.78 + (trough - 0.5) * 0.3, 0.55, 0.98);
	float metal = 0.0;
	vec3 emit = vec3(0.0);

	if (kind == 2) {
		// Barrier. Joint grooves, grime at the foot, drip streaks off the top.
		float jd = abs(mod(along + 0.3, barrier_joint) - barrier_joint * 0.5) - barrier_joint * 0.5;
		float joint = 1.0 - smoothstep(0.012, 0.03, abs(jd));
		float foot = (1.0 - smoothstep(0.02, 0.4, h)) * (0.6 + 0.4 * vnoise(vec2(along * 0.7, 0.0)));
		float drip = smoothstep(0.55, 0.85, vnoise(vec2(along * 3.1, h * 0.8)) * (0.4 + 0.6 * vnoise(vec2(along * 0.4, 3.0))))
			* smoothstep(0.1, 0.9, h);
		alb = mix(alb, grime_color, clamp(foot * grime_amount + drip * 0.35, 0.0, 1.0));
		alb *= 1.0 - joint * 0.55;
		if (flag > 0.5) {
			// Tyre scuffs: black rubber smeared along the face in long streaks, in runs where
			// cars have rubbed it (a few metres of scuffs, then clean face).
			float run = smoothstep(0.5, 0.75, fbm(vec2(along * 0.09, 1.7)));
			float band = smoothstep(0.04, 0.12, h) * (1.0 - smoothstep(0.38, 0.62, h));
			float streak = smoothstep(0.45, 0.8, vnoise(vec2(along * 0.6, h * 22.0)) * 0.6 + vnoise(vec2(along * 2.5, h * 40.0)) * 0.4);
			float scuff = run * band * streak;
			alb = mix(alb, scuff_color, scuff * scuff_amount);
			rough = mix(rough, 0.6, scuff);
		}
	} else if (kind == 9) {
		// Fascia: rust bleeding down under each scupper, a drip line along the bottom edge.
		float dx = abs(mod(along, scupper_spacing) - scupper_spacing * 0.5);
		float k = floor(along / scupper_spacing);
		float live = step(0.35, hash12(vec2(k, 17.0)));
		float down = clamp(-h / 0.55, 0.0, 1.0);
		float wide = 0.08 + 0.35 * down + 0.1 * vnoise(vec2(along * 6.0, h * 3.0));
		float rust = live * (1.0 - smoothstep(wide * 0.5, wide, dx)) * (0.35 + 0.65 * down)
			* (0.7 + 0.3 * vnoise(vec2(along * 9.0, h * 2.0)));
		float stain = smoothstep(0.55, 0.85, vnoise(vec2(along * 1.7, h * 0.5))) * 0.5;
		alb = mix(alb, grime_color, stain * 0.6 + down * 0.15);
		alb = mix(alb, rust_color, rust * rust_amount);
	} else if (kind == 4) {
		// Soffit: soot and damp, efflorescence where the segments meet.
		// Soft, large: exhaust soot is a haze under the deck, not blotches (a thresholded noise
		// here read as camouflage from the street).
		float soot = fbm(obj_pos.xz * 0.03) * 0.7 + vnoise(obj_pos.xz * 0.25) * 0.3;
		alb = mix(alb * 0.84, grime_color, smoothstep(0.2, 0.95, soot) * 0.32);
		float seam = 1.0 - smoothstep(0.0, 0.5, abs(mod(along, 24.0) - 12.0) - 11.4);
		float eff = seam * smoothstep(0.4, 0.75, vnoise(obj_pos.xz * 1.3));
		alb = mix(alb, vec3(0.62, 0.61, 0.58), eff * 0.5);
		rough = 0.92;
	} else if (kind == 3) {
		// Columns and caps: water and rust streaks from the top, splash dirt at the foot.
		float depth = UV2.y - h;
		float st = smoothstep(0.5, 0.82, vnoise(vec2(along * 2.6 + obj_pos.y * 0.0, 0.0) + vec2(0.0, depth * 0.12))
			* (0.6 + 0.4 * vnoise(vec2(along * 0.5, 9.0))));
		float fade = 1.0 - smoothstep(0.5, 7.0, depth);
		alb = mix(alb, mix(grime_color, rust_color, 0.45), st * fade * 0.75);
		float foot = 1.0 - smoothstep(0.6, 1.9, h);
		alb = mix(alb, grime_color * 1.4, foot * (0.5 + 0.3 * vnoise(vec2(along * 3.0, h * 5.0))));
	} else if (kind == 1) {
		float stain = smoothstep(0.55, 0.85, vnoise(vec2(along * 1.9, h * 0.6)));
		alb = mix(alb, grime_color, stain * 0.35);
	} else if (kind == 5) {
		// Galvanised steel: mottled zinc, darker where the weather sits.
		float m = vnoise(obj_pos.xz * 3.0 + obj_pos.y * 2.0) * 0.6 + vnoise(obj_pos.xy * 11.0) * 0.4;
		alb = base * (0.72 + 0.42 * m);
		metal = 0.7;
		rough = 0.42 + 0.25 * m;
	} else if (kind == 6) {
		alb = base * (0.9 + 0.15 * vnoise(obj_pos.xz * 5.0));
		rough = 0.55;
		metal = 0.15;
	} else if (kind == 7) {
		alb = base * 0.25;
		rough = 0.2;
		emit = base * lens_energy * max(lamp_factor, 0.0) * (flag > 0.0 ? flag : 1.0);
	} else if (kind == 8) {
		alb = base * (0.8 + 0.3 * vnoise(obj_pos.xz * 9.0));
		rough = 0.9;
	}

	// Rain darkens and glosses what faces the sky most.
	float wet = clamp(road_wetness, 0.0, 1.0) * mix(0.35, 1.0, smoothstep(0.3, 0.9, obj_nrm.y));
	alb *= mix(1.0, 0.68, wet);
	rough = mix(rough, 0.3, wet * 0.8);

	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
