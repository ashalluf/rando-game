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
#include "res://shaders/pattern_aa.gdshaderinc"

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

// The roof at eye level (RcCarParkRoof, 0 = the old roof bit for bit): the precast double tees'
// joints every `rc5_tee` m along u with their sealant, each tee its own pour, ponding stains and
// drains on the drives' centre lines, a traffic coating's sheen. In the structure's own frame
// (VERTEX: x along u, z along v), so the joints run straight across every band.
uniform float rc5 = 0.0;
uniform float rc5_tee = 3.66;

global uniform float road_wetness;

varying vec2 info;
varying vec3 frame_pos;

void vertex() {
	info = UV2;
	frame_pos = VERTEX;
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
		if (paa_on()) {
			dash = paa_stripes(m.x - 3.0, 6.0, 0.5, px);
		}
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
		// A 6 cm groove aliases from a 3 cm footprint (two pixels a period): gone by then.
		if (paa_on()) {
			fade = paa_keep(0.06, px);
		}
		nrm_add = vec3(0.0, 0.0, (groove - 0.5) * 0.35 * fade);
		col *= 1.0 - 0.06 * fade * groove;
		float t = 0.0;
		for (int i = 0; i < 4; i++) {
			float c = (i < 2 ? 1.7 : -1.7) + ((i % 2 == 0) ? 0.82 : -0.82);
			t += smoothstep(0.45, 0.05, abs(y - c));
		}
		polish = t * 0.8;
		col *= 1.0 - 0.18 * t;
		paint = line(y, 0.1, px) * (paa_on() ? paa_stripes(m.x - 2.0, 4.0, 0.5, px) : step(0.5, fract(m.x / 4.0)));
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
	if (roof && rc5 > 0.5) {
		vec2 fp = frame_pos.xz;
		float fpx = max(fwidth(fp.x), 1e-4);
		float ti = floor(fp.x / rc5_tee);
		float tx = fp.x - (ti + 0.5) * rc5_tee;
		// Each tee its own pour: a tone and a roughness of its own.
		float th = hash12(vec2(ti, 4.7));
		col *= (0.9 + 0.17 * th) * mix(vec3(1.0), vec3(1.03, 1.0, 0.95), hash12(vec2(ti, 9.1)));
		rough = mix(rough, rough * (0.85 + 0.25 * th), 1.0 - paint);
		// The joint: a sealant band 4-7 cm wide (overbanded, its edge wandering), dark and satin,
		// a hairline of shadow in the middle; filtered to its mean under a pixel.
		float jd = rc5_tee * 0.5 - abs(tx);
		float sw = 0.022 + 0.012 * vnoise(vec2(fp.y * 1.7, ti));
		float seal = clamp((sw - jd) / fpx + 0.5, 0.0, 1.0);
		float core = clamp((0.004 - jd) / fpx + 0.5, 0.0, 1.0);
		vec3 sealc = vec3(0.11, 0.11, 0.115) * (0.85 + 0.3 * vnoise(fp * vec2(0.5, 3.0)));
		col = mix(col, sealc, seal * 0.85);
		col *= 1.0 - 0.5 * core;
		rough = mix(rough, 0.42, seal);
		// Water stands along the joints and dries in tide lines: a soft darker band either side.
		float tide = smoothstep(0.55, 0.0, jd) * (0.4 + 0.6 * vnoise(vec2(fp.y * 0.6, ti * 3.1)));
		col *= 1.0 - 0.07 * tide;
		// Ponding: low blotches where the deck sags, ringed by a darker, dried edge.
		float pond = fbm(fp * 0.09 + 21.0);
		float ring = smoothstep(0.58, 0.62, pond) * (1.0 - smoothstep(0.64, 0.7, pond));
		col *= 1.0 - 0.05 * smoothstep(0.6, 0.75, pond) - 0.06 * ring;
		// Drains on a drive's centre line every other tee, a stain spreading round each.
		if (kind < 0.5) {
			float di = floor(fp.x / (rc5_tee * 2.0));
			vec2 dc = vec2((di + 0.5) * rc5_tee * 2.0, 0.0);
			vec2 dd = vec2(fp.x - dc.x, m.y);
			float grate = step(abs(dd.x), 0.17) * step(abs(dd.y), 0.17);
			float slot = step(0.5, fract(dd.x * 14.0 + 0.25));
			float stain2 = smoothstep(1.4, 0.15, length(dd * vec2(1.0, 1.3)) + (vnoise(fp * 2.3) - 0.5) * 0.5);
			col *= 1.0 - 0.14 * stain2 * (1.0 - grate);
			col = mix(col, vec3(0.04, 0.04, 0.045) * (0.6 + 0.8 * slot), grate);
			rough = mix(rough, 0.35, grate);
			// Rubber laid by a car swung round the empty roof: a pair of streaks 1.6 m apart,
			// swaying, now and then along the drive.
			float sway = 1.1 * sin(fp.x * 0.11 + 1.7) + 0.4 * sin(fp.x * 0.37);
			float on = smoothstep(0.55, 0.7, vnoise(vec2(fp.x * 0.04, floor(fp.y / 12.0) + 3.0)));
			float sk = line(m.y - sway - 0.8, 0.16, fpx) + line(m.y - sway + 0.8, 0.16, fpx);
			col *= 1.0 - 0.28 * on * sk * (0.5 + 0.5 * vnoise(vec2(fp.x * 1.3, m.y)));
		}
		// The traffic coating: a faint satin sheen and the dust of the day.
		rough = mix(rough, rough * 0.82, 0.5 * (1.0 - paint));
	}
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
