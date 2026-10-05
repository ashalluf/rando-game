shader_type spatial;
render_mode cull_back;

// The ground of the city's vacant lots and gravel car parks (VacantLots.commit()): ONE mesh a
// chunk, no shadow. Each piece says what it is in COLOR.r (VacantLots.G_*, in 8ths); UV is world
// metres (x, z), so nothing tiles to the piece, and UV2 is the piece's own frame:
//   0 bare lot: compacted tan dirt, gravel spread in patches, mats of dry grass, litter and broken
//     glass, and TYRE RUTS - UV2 = (metres across the track from the gate's line, metres in from
//     the street), so two ruts run in from the gate and wander off into the lot, polished and
//     darker, holding water when it rains.  COLOR.g a variant.
//   1 a demolished building's slab: poured concrete in bays with their joints, cracked to pieces
//     with weeds in every wide crack, rust and burn stains, the edge broken back to the dirt.
//     UV2 = metres in the slab's own rect, COLOR.g / COLOR.b its size / 64 m.
//   2 gravel car park: crushed stone, packed dark down the aisles (UV2.y metres in from the street,
//     the aisles every COLOR.b * 32 m), oil under the stalls, potholes that fill in the rain.
// Colours are tuned in display (sRGB) numbers and handed over in the renderer's own space
// (color_space.gdshaderinc), so the Mac draws what the opengl3 stills show.

uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float road_wetness;
global uniform vec4 sky_tint;

varying float kind;
varying vec3 vcol;

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

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.3) * 0.2;
}

// Distance to the nearest edge of a jittered Voronoi tessellation (cells `scale` m across).
float crack_dist(vec2 p, float scale) {
	vec2 q = p / scale;
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 best = vec2(8.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + hash22(i + o) * 0.85 - f;
			float d = dot(r, r);
			if (d < best.x) {
				best.y = best.x;
				best.x = d;
			} else if (d < best.y) {
				best.y = d;
			}
		}
	}
	return (sqrt(best.y) - sqrt(best.x)) * scale * 0.5;
}

float lines(float v, float spacing, float w) {
	float g = abs(fract(v / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(v), 0.0005);
	float fade = 1.0 - smoothstep(0.03, 0.12, fw / spacing * 4.0);
	return (1.0 - smoothstep(w * 0.5, w * 0.5 + fw, g)) * fade;
}

// The lot's own dirt, its dry grass and its scatter: shared by the bare lot and the slab's broken
// edge. `foot` is the pixel's ground footprint (metres), `grass` returns the dry-grass cover.
vec3 lot_dirt(vec2 p, float var, float foot, out float grass) {
	vec3 d = disp(texture(dirt_tex, p / 3.4).rgb);
	vec3 d2 = disp(texture(dirt_tex, p * vec2(0.19, 0.23) + 0.37).rgb);
	d = mix(d, d2, 0.35);
	// A pale, dry, sun-baked tan: the scan desaturated and lifted.
	float l = dot(d, vec3(0.333));
	d = mix(vec3(l), d, 0.7) * vec3(1.06, 0.97, 0.84) * 0.8;
	d *= 0.86 + 0.24 * fbm(p * 0.09 + var * 9.0);
	// Gravel spread in patches (the old fill under a demolished building's parking).
	vec3 g = disp(texture(gravel_tex, p / 1.8).rgb) * vec3(0.82, 0.8, 0.77);
	float peb = vnoise(p * 11.0) * 0.6 + vnoise(p * 27.0) * 0.4;
	g *= 0.82 + 0.3 * peb;
	float gpatch = smoothstep(0.56, 0.68, fbm(p * 0.07 + var * 3.0 + 4.0));
	d = mix(d, g, gpatch * 0.85);
	// Dry grass mats: foxtail, oat and ripgut brome gone straw-coloured, greener in the hollows.
	vec3 gt = disp(texture(grass_tex, p / 1.3).rgb);
	float gl = dot(gt, vec3(0.333));
	vec3 straw = mix(vec3(0.62, 0.53, 0.33), vec3(0.74, 0.66, 0.44), vnoise(p * 0.6 + 2.0));
	vec3 green = vec3(0.36, 0.38, 0.2);
	vec3 gcol = mix(straw, green, smoothstep(0.62, 0.85, vnoise(p * 0.21 + var * 5.0)) * 0.6) * (0.55 + 0.9 * gl);
	float gn = fbm(p * 0.16 + var * 13.0) * 0.75 + vnoise(p * 1.7) * 0.25;
	grass = smoothstep(0.47, 0.6, gn) * (1.0 - gpatch * 0.6);
	d = mix(d, gcol, grass);
	// Scatter: paper and plastic scraps, broken glass glinting, small stones.
	vec2 cell = floor(p / 0.7);
	vec2 off = hash22(cell + 17.0);
	float rnd = hash12(cell + 3.1);
	float spot = 1.0 - smoothstep(0.03, 0.05 + foot, length(fract(p / 0.7) - off * 0.8 - 0.1) * 0.7);
	float fade = 1.0 - smoothstep(0.02, 0.06, foot);
	if (rnd > 0.93) {
		d = mix(d, vec3(0.86, 0.85, 0.8), spot * fade * 0.8);
	} else if (rnd > 0.88) {
		d = mix(d, vec3(0.2, 0.32, 0.22), spot * fade * 0.7);
	} else if (rnd < 0.06) {
		d = mix(d, d * 0.55, spot * fade);
	}
	return d;
}

void vertex() {
	kind = floor(COLOR.r * 8.0);
	vcol = COLOR.rgb;
}

void fragment() {
	vec2 p = UV;
	vec2 q = UV2;
	float var = vcol.g;
	float foot = length(vec2(length(dFdx(p)), length(dFdy(p))));
	vec3 albedo;
	float rough = 0.95;
	float wet_k = 0.6;
	float puddle = 0.0;
	float grass = 0.0;
	if (kind < 0.5) {
		albedo = lot_dirt(p, var, foot, grass);
		// Tyre ruts from the gate: two tracks 1.7 m apart that wander as they go in, fading out
		// past ~30 m where the cars turned round and spread.
		float depth = max(q.y, 0.0);
		float wander = sin(depth * 0.09 + var * 6.0) * 2.4 * smoothstep(4.0, 22.0, depth) + sin(depth * 0.31 + var * 11.0) * 0.35;
		float x = q.x - wander;
		float tw = 0.36 + 0.08 * vnoise(vec2(depth * 0.5, 1.0));
		float rut = 0.0;
		for (int i = 0; i < 2; i++) {
			float c = float(i) * 1.7 - 0.85;
			rut = max(rut, 1.0 - smoothstep(tw * 0.5, tw * 0.5 + 0.12 + foot, abs(x - c)));
		}
		float reach = 1.0 - smoothstep(18.0, 34.0 + 10.0 * var, depth);
		rut *= reach * (0.75 + 0.25 * vnoise(p * 1.3));
		// A turning loop where the tracks fan out.
		float loop = abs(length((vec2(x, depth) - vec2(0.0, 26.0)) * vec2(1.0, 1.4)) - 6.5);
		rut = max(rut, (1.0 - smoothstep(0.25, 0.4 + foot, loop)) * 0.55 * smoothstep(12.0, 20.0, depth) * (1.0 - smoothstep(34.0, 40.0, depth)));
		// Packed and bare in the tracks: no grass, darker, smoother; the centre hump keeps a little.
		vec3 dd = disp(texture(dirt_tex, p / 3.4).rgb);
		vec3 packed = mix(vec3(dot(dd, vec3(0.333))), dd, 0.5) * vec3(0.92, 0.86, 0.74) * 0.82;
		albedo = mix(albedo, packed * (0.9 + 0.2 * vnoise(p * 4.0)), rut * 0.85);
		// Tread marks across the rut.
		float tread = lines(depth + p.x * 0.02, 0.18, 0.06) * rut * (1.0 - smoothstep(0.01, 0.03, foot));
		albedo *= 1.0 - 0.12 * tread;
		puddle = rut * smoothstep(0.55, 0.75, vnoise(p * 0.45 + 3.0));
		rough = mix(0.96, 0.86, rut);
	} else if (kind < 1.5) {
		// The slab of a building that is gone: 4 m pours with joints, cracked to pieces, weeds in the
		// wide cracks, rust from cut columns, a scorch where somebody burned a fire, the edge broken
		// back to the dirt over the last half metre.
		vec2 size = max(vcol.gb * 64.0, vec2(1.0));
		vec3 c = disp(texture(concrete_tex, p / 3.0).rgb);
		vec2 bay = floor(q / 4.0);
		float bt = 0.88 + 0.16 * hash12(bay + var * 7.0);
		albedo = c * vec3(1.0, 0.98, 0.94) * bt * 0.86;
		float age = fbm(p * 0.12 + 9.0);
		albedo *= 0.78 + 0.3 * age;
		float joint = max(lines(q.x, 4.0, 0.02), lines(q.y, 4.0, 0.02));
		albedo *= 1.0 - 0.4 * joint;
		float fade = 1.0 - smoothstep(0.008, 0.03, foot);
		float cd = crack_dist(p + vec2(vnoise(p * 0.7), vnoise(p * 0.7 + 5.0)) * 0.6, 1.6);
		float cw = mix(0.008, 0.05, smoothstep(0.45, 0.9, vnoise(p * 0.25 + 4.0)));
		float crack = (1.0 - smoothstep(cw, cw + foot, cd)) * fade;
		float cd2 = crack_dist(p * vec2(1.0, 0.6), 5.5);
		crack = max(crack, (1.0 - smoothstep(0.012, 0.012 + foot, cd2)) * fade * 0.8);
		albedo *= 1.0 - 0.6 * crack;
		albedo *= 1.0 - 0.05 * (1.0 - fade);
		// Weeds come up through the wider cracks and the joints.
		vec3 weed = mix(vec3(0.36, 0.37, 0.18), vec3(0.62, 0.55, 0.34), vnoise(p * 0.8));
		float tuft = smoothstep(0.42, 0.8, vnoise(p * 5.0)) * (1.0 - smoothstep(cw + 0.04, cw + 0.16, min(cd, cd2 * 2.0)));
		tuft = max(tuft, joint * smoothstep(0.55, 0.85, vnoise(p * 3.0)) * 0.8);
		albedo = mix(albedo, weed * (0.6 + 0.6 * vnoise(p * 19.0)), tuft * mix(0.4, 0.8, fade));
		// Stains: rust rings where columns stood (on the 8 m grid), a burned patch, dark oil.
		vec2 col = abs(fract(q / 8.0 + 0.5) - 0.5) * 8.0;
		float rust = (1.0 - smoothstep(0.15, 0.9, length(col))) * step(0.4, hash12(floor(q / 8.0 + 0.5) + 2.0));
		albedo = mix(albedo, vec3(0.42, 0.24, 0.13), rust * 0.6);
		float burn = smoothstep(0.7, 0.86, fbm(p * 0.18 + var * 21.0));
		albedo *= 1.0 - 0.55 * burn;
		float oil = smoothstep(0.66, 0.82, fbm(p * 0.35 + 31.0));
		albedo *= 1.0 - 0.25 * oil;
		// Painted marks from the old floor: a faded yellow line, now and then.
		float stripe = lines(q.x + 1.3, 9.0 + 4.0 * var, 0.1) * step(0.5, var) * smoothstep(0.3, 0.7, fbm(p * 0.8));
		albedo = mix(albedo, vec3(0.78, 0.66, 0.3), stripe * 0.5);
		// The broken edge: the slab crumbles back to dirt over a jagged half metre.
		float edge = min(min(q.x, size.x - q.x), min(q.y, size.y - q.y));
		float jag = 0.15 + 0.6 * fbm(p * 1.6 + 2.0);
		float g2;
		vec3 dirt = lot_dirt(p, var, foot, g2);
		float broken = 1.0 - smoothstep(jag, jag + 0.06 + foot, edge);
		albedo = mix(albedo, dirt, broken);
		puddle = smoothstep(0.62, 0.8, vnoise(p * 0.3 + 1.0)) * (1.0 - broken);
		rough = mix(0.88, 0.96, broken);
		wet_k = mix(0.9, 0.6, broken);
	} else {
		// Gravel car park.
		vec3 g = disp(texture(gravel_tex, p / 1.8).rgb);
		vec3 d = disp(texture(dirt_tex, p / 3.0).rgb);
		float peb = vnoise(p * 10.0) * 0.6 + vnoise(p * 25.0) * 0.4;
		albedo = mix(g, d, 0.3) * vec3(0.98, 0.95, 0.9) * (0.8 + 0.32 * peb);
		float l = dot(albedo, vec3(0.333));
		albedo = mix(vec3(l), albedo, 0.7) * 0.88;
		// Aisles, packed darker and smoother where the cars drive.
		float pitch = max(vcol.b * 32.0, 4.0);
		float a = abs(fract(q.y / pitch) - 0.5) * pitch;
		float aisle = (1.0 - smoothstep(2.0, 3.6, a)) * (0.7 + 0.3 * vnoise(p * 0.8));
		albedo *= 1.0 - 0.16 * aisle;
		// Oil under the stalls, between the aisles.
		float oil = smoothstep(0.6, 0.78, fbm(p * 0.55 + 41.0)) * (1.0 - aisle);
		albedo *= 1.0 - 0.3 * oil;
		// Weeds where nothing drives: along the edges and in the stall fronts.
		vec3 weed = mix(vec3(0.38, 0.38, 0.2), vec3(0.62, 0.54, 0.34), vnoise(p * 0.7));
		float wd = smoothstep(0.66, 0.82, fbm(p * 0.5 + 6.0)) * (1.0 - aisle);
		albedo = mix(albedo, weed * (0.7 + 0.5 * peb), wd * 0.7);
		// Potholes: darker dishes that hold water.
		float hole = smoothstep(0.76, 0.8, vnoise(p * 0.5 + 11.0)) * aisle;
		albedo *= 1.0 - 0.25 * hole;
		puddle = hole;
		rough = 0.95;
	}
	float wet = clamp(road_wetness, 0.0, 1.0);
	albedo *= 1.0 - 0.34 * wet * wet_k;
	// Standing water in ruts and potholes: a dark mirror of the sky.
	float pool = smoothstep(0.3, 0.7, wet) * puddle;
	albedo = mix(albedo, albedo * 0.35, pool);
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 4.0);
	EMISSION = sky_tint.rgb * fres * pool * 0.25;
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	ROUGHNESS = mix(mix(rough, 0.2, wet * wet_k * 0.7), 0.04, pool);
	SPECULAR = 0.5;
}
