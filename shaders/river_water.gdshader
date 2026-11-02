shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// The Los Angeles River's low-flow water (RiverBuild, LaRiver): a thin sheet a hand deep running
// down the notch in the middle of the concrete bed. Not the ocean and not the park lake: what this
// water is, is a fast shallow film over algae and silt - riffles where it runs over the concrete,
// streaks of foam and scum drawn out downstream, bright green-brown algae mats along its edges,
// and over all of it the sky and the bridges mirrored at a grazing angle.
//
// UV.x is metres down the river (s), UV.y metres across it from the centre line (o), so the flow
// runs along +UV.x. Works on the web: no depth or screen texture, the sky is emitted from the
// `sky_tint` global (Compatibility has no screen-space reflections to carry it).

global uniform vec4 sky_tint;
global uniform float night_factor;
global uniform float lamp_factor;
global uniform float ground_detail;
global uniform float rain_intensity;
global uniform vec3 sun_direction;
global uniform float river_look;

#include "res://shaders/color_space.gdshaderinc"

// LINEAR colours. The water over clean concrete, over the algae, and the algae mats themselves.
uniform vec3 water_color = vec3(0.012, 0.015, 0.011);
uniform vec3 algae_color = vec3(0.020, 0.026, 0.010);
uniform vec3 algae_bright = vec3(0.040, 0.050, 0.016);
uniform vec3 foam_color = vec3(0.26, 0.26, 0.23);
// Half the sheet's width (metres; LaRiver's water edge) and how wide the algae fringe is.
uniform float half_width = 2.45;
uniform float algae_fringe = 0.75;
// Flow speed (m/s) the ripples and the foam are carried down at.
uniform float flow_speed = 0.9;
uniform float ripple = 0.65;
uniform float sky_emit = 0.12;

varying vec2 v_uv;
varying vec4 v_chan;


float rw_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float rw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(rw_hash(i), rw_hash(i + vec2(1.0, 0.0)), f.x),
		mix(rw_hash(i + vec2(0.0, 1.0)), rw_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Height of the riffles at `p` (s, o) and its gradient: noise advected down the flow, stretched
// across (a shallow sheet's wavelets stand across the current).
vec3 riffles(vec2 p, float t) {
	vec2 q = vec2(p.x - t * flow_speed, p.y);
	float e = 0.08;
	vec2 sc = vec2(0.9, 2.2);
	float h = rw_noise(q * sc);
	float hx = rw_noise((q + vec2(e, 0.0)) * sc);
	float hy = rw_noise((q + vec2(0.0, e)) * sc);
	vec3 r = vec3(h, (hx - h) / e, (hy - h) / e);
	// Standing riffles where the sheet runs over the concrete's joints and grit (not carried).
	vec2 sq = p * vec2(0.5, 1.6);
	float g = rw_noise(sq);
	float gx = rw_noise(sq + vec2(e * 0.5, 0.0));
	float gy = rw_noise(sq + vec2(0.0, e * 1.6));
	r += vec3(g, (gx - g) / e, (gy - g) / e) * 0.6;
	return r;
}

// rc2-river (RiverLook, river_look global 1): what the low flow mirrors. At eye height on the bed the
// reflected rays mostly meet the channel's own banks, not the sky - a pale sky sheet read as a strip of
// mint plastic. The banks are the trapezoid LaRiver builds (bed half width and bank height in COLOR,
// the +o direction in world xz in COLOR.rg), lit here by the sun and the sky by hand; the sky above
// them; the renderer's own specular kept small so it does not paint the sky over everything again.
uniform vec3 bank_albedo = vec3(0.19, 0.18, 0.16);
uniform vec3 sun_light = vec3(2.9, 2.55, 2.0);
uniform float sky_light = 0.6;
uniform vec3 murk_color = vec3(0.020, 0.024, 0.012);
// Must match LaRiver: SLOPE (bank run per metre of rise) and the toe's height over the water
// (BED_FALL + LF_DEPTH - WATER_DEPTH).
const float RW_SLOPE = 1.6;
const float RW_TOE = 0.57;

vec3 rw_mirror(vec3 r, float o0, float s0, vec3 sky) {
	vec2 lat = v_chan.rg * 2.0 - 1.0;
	float bh = v_chan.b * 40.0;
	float dep = v_chan.a * 10.0;
	float a = dot(r.xz, lat);
	float up = max(r.y, 0.0005);
	float sg = a >= 0.0 ? 1.0 : -1.0;
	float aa = max(abs(a), 1e-4);
	float o_top = bh + dep * RW_SLOPE;
	float t_top = (o_top - sg * o0) / aa;
	float h_top = RW_TOE + dep;
	if (up * t_top >= h_top + 2.2) {
		return sky;
	}
	// Where the ray meets the bank face (or the fence band over the coping).
	float denom = up - aa / RW_SLOPE;
	float t_hit = denom > 1e-4 ? (RW_TOE + (sg * o0 - bh) / RW_SLOPE) / denom : t_top;
	t_hit = clamp(t_hit, 0.0, t_top);
	float y_hit = up * t_hit;
	if (up * t_top >= h_top) {
		// Over the coping: sky through the chain-link, a little darker.
		return sky * 0.82;
	}
	vec2 rd = vec2(lat.y, -lat.x);
	float s_hit = s0 + dot(r.xz, rd) * t_hit;
	vec3 lat3 = vec3(lat.x, 0.0, lat.y);
	vec3 n = normalize(vec3(0.0, 1.0, 0.0) - lat3 * (sg / RW_SLOPE));
	vec3 sn = normalize(sun_direction);
	float sun = max(dot(n, sn), 0.0) * smoothstep(0.0, 0.12, sn.y) * (1.0 - night_factor);
	vec3 alb = bank_albedo * (0.82 + 0.3 * rw_noise(vec2(s_hit * 0.11, y_hit * 0.5)));
	// The streaks run down the bank, the wet dark band and algae at its foot.
	alb *= 1.0 - 0.35 * smoothstep(0.5, 0.85, rw_noise(vec2(s_hit * 1.2, y_hit * 0.08)));
	alb = mix(alb, vec3(0.035, 0.05, 0.02), 1.0 - smoothstep(0.55, 1.3, y_hit));
	return alb * (sun_light * sun + sky * sky_light) + vec3(0.05, 0.03, 0.012) * lamp_factor * 0.2;
}

void vertex() {
	v_uv = UV;
	v_chan = COLOR;
}

void fragment() {
	vec2 p = v_uv;
	float t = TIME;
	float across = abs(p.y) / max(half_width, 0.1);
	vec3 rf = riffles(p, t);
	vec2 grad = rf.yz * ripple * 0.12;
	if (ground_detail > 0.5) {
		vec3 r2 = riffles(p * 2.9 + vec2(5.3, 1.7), t * 1.6);
		grad += r2.yz * ripple * 0.04;
	}
	// Rain rings would be lost in this; a little more roughness instead.
	float rain = clamp(rain_intensity, 0.0, 1.0);
	// Foam and scum drawn out in streaks down the current, thickest in the middle.
	vec2 fq = vec2((p.x - t * flow_speed * 1.05) * 0.18, p.y * 2.4);
	float streak = rw_noise(fq) * rw_noise(fq * vec2(1.0, 2.3) + 3.1);
	float foam = smoothstep(0.42, 0.7, streak) * (1.0 - smoothstep(0.55, 1.0, across)) * 0.22;
	// The algae fringe along both edges, in clumps.
	float clump = rw_noise(p * vec2(0.35, 1.2) + 11.0);
	float edge = smoothstep(1.0 - algae_fringe / max(half_width, 0.1) * (0.6 + 0.8 * clump), 1.0, across);
	// UV runs along the flow, not along world x/z: turn the gradient into the mesh's frame with
	// the tangents the builder wrote.
	vec3 nrm_view = normalize(NORMAL + (TANGENT * -grad.x + BINORMAL * -grad.y) * (1.0 - edge));
	NORMAL = nrm_view;
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = min(0.02 + 0.98 * pow(1.0 - nv, 5.0), 0.55);
	vec3 bed = mix(water_color, algae_color, 0.35 + 0.4 * rw_noise(p * 0.21));
	vec3 mats = mix(algae_color, algae_bright, clump);
	vec3 body = mix(bed, mats, edge);
	body = mix(body, foam_color, foam * (1.0 - edge));
	// sky_tint is raw sRGB numbers on both renderers (fwd-review-d): decoded, then handed over.
	vec3 sky = cs_srgb_to_linear(sky_tint.rgb * (1.0 - 0.9 * night_factor) + vec3(0.05, 0.03, 0.012) * lamp_factor);
	if (river_look > 0.5) {
		// Turbid: the sheet over the concrete is a murky green-brown; the mirror is emitted by
		// Fresnel and the renderer's specular is kept small.
		body = mix(mix(murk_color, body, 0.45), foam_color * 0.6, foam * 0.5 * (1.0 - edge));
		vec3 r = reflect(-(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz));
		float f2 = min(0.02 + 0.98 * pow(1.0 - nv, 5.0), 0.62);
		ALBEDO = cs_out(body * (1.0 - f2));
		ROUGHNESS = mix(mix(0.05, 0.12, clamp(length(grad) * 4.0, 0.0, 1.0) + rain * 0.4), 0.8, edge);
		SPECULAR = 0.12;
		METALLIC = 0.0;
		EMISSION = cs_out(rw_mirror(r, p.y, p.x, sky)) * f2 * (1.0 - edge) * (1.0 - foam * 0.7);
	} else {
		ALBEDO = cs_out(body);
		ROUGHNESS = mix(mix(0.06, 0.16, clamp(length(grad) * 4.0, 0.0, 1.0) + rain * 0.4), 0.75, edge);
		SPECULAR = 0.5;
		METALLIC = 0.0;
		// The sky mirrored at a grazing angle (the web's only reflection; a floor under SSR on
		// Forward+), dark at night but for a little of the city's sodium glow.
		EMISSION = cs_out(sky) * fres * sky_emit * (1.0 - edge) * (1.0 - foam);
	}
}
