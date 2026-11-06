shader_type spatial;
render_mode cull_back;

// Everything upright on the city's vacant lots and gravel car parks (VacantLots, VacantKit) as ONE
// material: a chunk's fences, privacy screens, gates, signs and lettering, the broken foundation,
// rubble, dumped furniture, tyres, shopping carts and the attendant's booth are one mesh and one
// draw. The vertex layout is IndustrialKit's (its box / cylinder writers): COLOR.rgb the paint as
// written (sRGB numbers), COLOR.a the kind (VacantKit.K_*, in 32nds), UV metres in the face's own
// frame (x along it, y up from the box's foot), UV2.x the box's height, UV2.y a per-box parameter.
//    0 galvanised steel (posts, rails, gate frames)    1 chain-link (cut out; UV2.y > 0.5 rusty)
//    2 privacy screen: knit polyethylene with grommets, wind slits and tears (cut out)
//    3 concrete (broken slabs, stem walls, rubble, wheel stops)   4 brick rubble
//    5 rust (rebar, scrap)   6 upholstery (a dumped sofa or chair: weave, stains, sun fade)
//    7 mattress ticking (quilted, stained)   8 tyre rubber (tread on the crown)
//    9 timber (sign posts, plywood, pallets)   10 sign sheeting (printed board, weathered)
//   11 ink (lettering)   12 hand-painted plywood (a brushed wash, drips)   13 plastic
//   14 glass (the booth's windows: dark, the sky mirrored, a lamp inside after dark)
//   15 wire grid (a shopping cart's basket, cut out)   16 painted sheet metal (the booth)
//   17 earth (a rubble pile's mound)   18 lamp (a bulb, lit after dark)

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cracked_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D planks_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fabric_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ticking_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float road_wetness;
global uniform float lamp_factor;
global uniform float night_factor;
global uniform vec4 sky_tint;

varying float kind;
varying vec3 world_n;
varying vec3 world_p;

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
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.3) * 0.2;
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

float lines(float v, float spacing, float w) {
	float g = abs(fract(v / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(v), 0.0005);
	float fade = 1.0 - smoothstep(0.03, 0.12, fw / spacing * 4.0);
	return (1.0 - smoothstep(w * 0.5, w * 0.5 + fw, g)) * fade;
}

void vertex() {
	kind = floor(COLOR.a * 32.0);
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float h = max(UV2.x, 0.01);
	float param = UV2.y;
	bool top = world_n.y > 0.5;
	vec3 paint = COLOR.rgb;
	vec3 albedo = paint;
	float rough = 0.85;
	float metal = 0.0;
	float spec = 0.5;
	float wet_k = 0.5;
	vec3 emit = vec3(0.0);
	float seedv = hash12(floor(world_p.xz / 23.0));
	float fw = max(fwidth(uv.x), fwidth(uv.y));
	// Splash dirt up the foot of anything standing in the lot.
	float foot = top ? 0.0 : 1.0 - smoothstep(0.0, 0.35, uv.y);
	if (kind < 0.5) {
		// Galvanised steel: spangle, white rust where it has weathered, dirt at the foot.
		albedo = paint * (0.88 + 0.16 * vnoise(uv * vec2(3.0, 18.0)));
		albedo = mix(albedo, vec3(0.78, 0.78, 0.74), smoothstep(0.6, 0.85, vnoise(uv * 5.0 + seedv * 7.0)) * 0.35);
		metal = 0.6;
		rough = 0.48;
	} else if (kind < 1.5) {
		// Chain-link: 5 cm diamonds of 9-gauge wire, dithered to their average under a few pixels;
		// an old run rusts brown in streaks.
		vec2 q = uv / 0.05;
		vec2 d = vec2(q.x + q.y, q.x - q.y);
		vec2 f = abs(fract(d) - 0.5);
		float dist = 0.5 - max(f.x, f.y);
		float dw = max(fwidth(d.x), fwidth(d.y));
		float wire = 0.05;
		float line = 1.0 - smoothstep(wire, wire + dw, dist);
		float avg = 1.0 - (1.0 - 2.0 * wire) * (1.0 - 2.0 * wire);
		float cover = mix(line, avg * 0.8, smoothstep(0.25, 0.7, dw));
		// A sagging, cut corner at the foot of some panels (a way in).
		float cut = step(0.82, hash12(floor(vec2(uv.x / 3.0, 0.5)) + seedv * 13.0)) * step(uv.y, 0.7) * step(fract(uv.x / 3.0), 0.22);
		if (cover * (1.0 - cut) < bayer4(FRAGCOORD.xy)) {
			discard;
		}
		albedo = paint * (0.82 + 0.3 * fract(d.x * 0.5));
		float rust = param > 0.5 ? smoothstep(0.35, 0.75, fbm(uv * vec2(1.0, 3.0) + seedv * 9.0)) : 0.0;
		albedo = mix(albedo, vec3(0.38, 0.22, 0.12), rust * 0.8);
		metal = mix(0.6, 0.1, rust);
		rough = mix(0.45, 0.9, rust);
	} else if (kind < 2.5) {
		// Privacy screen: an 85 % knit shade cloth zip-tied to the chain-link, its grommets along the
		// hems, half-moon wind slits cut in rows, sun-faded on top, torn here and there.
		vec2 q = uv;
		float hem = max(1.0 - smoothstep(0.04, 0.05 + fw, q.y), 1.0 - smoothstep(0.04, 0.05 + fw, h - q.y));
		float knit = 0.82 + 0.18 * sin(q.x * 380.0) * sin(q.y * 300.0) * (1.0 - smoothstep(0.004, 0.01, fw));
		albedo = paint * knit;
		albedo = mix(albedo, albedo * 1.35 + vec3(0.04), smoothstep(0.2, 1.0, q.y / h) * 0.35);
		albedo = mix(albedo, paint * 0.8, hem);
		// Grommets every 0.6 m on both hems.
		vec2 g = vec2(abs(fract(q.x / 0.6) - 0.5) * 0.6, min(abs(q.y - 0.025), abs(h - 0.025 - q.y)));
		float grom = 1.0 - smoothstep(0.008, 0.012 + fw, length(g));
		albedo = mix(albedo, vec3(0.7, 0.7, 0.66), grom);
		metal = grom * 0.7;
		// Wind slits: half-moons in staggered rows.
		vec2 sl = vec2(fract(q.x / 1.2 + floor(q.y / 0.7) * 0.5) - 0.5, fract(q.y / 0.7) - 0.5);
		float slit = step(length(sl * vec2(1.2, 0.7) * vec2(6.0, 9.0)) , 0.6) * step(sl.y, 0.0) * step(0.15, q.y) * step(q.y, h - 0.15);
		// Tears: a few panels ripped from a grommet, ragged-edged (warped noise), the old runs more.
		float panel = floor(q.x / 3.0);
		float torn = step(0.62 - param * 0.3, hash12(vec2(panel, seedv * 17.0)));
		vec2 tc = vec2(panel * 3.0 + 0.6 + 1.8 * hash12(vec2(panel, 3.0)), mix(h - 0.1, 0.25, step(0.5, hash12(vec2(panel, 7.0)))));
		vec2 w = q + (vec2(fbm(q * 3.1 + 2.0), fbm(q * 3.1 + 9.0)) - 0.5) * 0.45;
		float rad = (0.18 + 0.4 * hash12(vec2(panel, 11.0))) * (0.75 + 0.5 * fbm(q * 7.0));
		float tear = torn * step(length((w - tc) * vec2(0.8, 1.3)), rad);
		if (max(slit, tear) > 0.5) {
			discard;
		}
		rough = 0.8;
		spec = 0.35;
		wet_k = 0.3;
	} else if (kind < 3.5) {
		// Concrete: the broken slabs, stem walls, chunks and wheel stops. Rough fractured faces.
		vec3 c = disp(texture(concrete_tex, uv / 2.2).rgb);
		vec3 cr = disp(texture(cracked_tex, (uv + world_p.xz * 0.1) / 3.0).rgb);
		albedo = paint * mix(c, cr, 0.45) * 1.05;
		albedo *= 0.8 + 0.32 * fbm(uv * 2.5 + world_p.xz);
		albedo *= 1.0 - 0.25 * foot;
		rough = 0.92;
	} else if (kind < 4.5) {
		// Brick rubble: the photographed courses, broken, dusty.
		vec3 b = disp(texture(brick_tex, uv / 1.4).rgb);
		albedo = paint * b * (0.85 + 0.3 * vnoise(uv * 4.0 + world_p.xz));
		albedo = mix(albedo, vec3(0.62, 0.56, 0.48), smoothstep(0.5, 0.9, vnoise(uv * 2.0 + 5.0)) * 0.4);
		rough = 0.92;
	} else if (kind < 5.5) {
		// Rust: rebar and scrap, orange-brown with darker scale.
		float n = fbm(uv * 6.0 + world_p.xz * 3.0);
		albedo = mix(vec3(0.36, 0.2, 0.11), vec3(0.55, 0.3, 0.14), n) * (0.8 + 0.3 * vnoise(uv * 20.0));
		rough = 0.9;
		metal = 0.2;
	} else if (kind < 6.5) {
		// Upholstery: the weave scan in the cloth's colour, sun-bleached on top, water-stained in
		// tide marks, grimed at the foot.
		vec3 fb = disp(texture(fabric_tex, uv / 0.6).rgb);
		float l = dot(fb, vec3(0.333));
		albedo = paint * (0.55 + 0.75 * l);
		albedo = mix(albedo, albedo * 0.7 + vec3(0.18, 0.17, 0.15), (top ? 0.45 : 0.15) * smoothstep(0.3, 0.8, fbm(uv * 0.8 + seedv)));
		float tide = fbm(uv * 1.3 + seedv * 17.0);
		albedo *= 1.0 - 0.3 * smoothstep(0.55, 0.6, tide) + 0.12 * smoothstep(0.6, 0.62, tide) * (1.0 - smoothstep(0.62, 0.64, tide));
		albedo *= 1.0 - 0.35 * foot;
		rough = 0.95;
		spec = 0.3;
		wet_k = 0.9;
	} else if (kind < 7.5) {
		// Mattress ticking: the striped scan, quilted in a diamond, yellowed and stained.
		vec3 tk = disp(texture(ticking_tex, uv / 0.9).rgb);
		vec2 qd = uv / 0.22;
		vec2 dq = abs(fract(vec2(qd.x + qd.y, qd.x - qd.y)) - 0.5);
		float quilt = 1.0 - smoothstep(0.0, 0.08, 0.5 - max(dq.x, dq.y));
		albedo = paint * tk * (1.0 - 0.18 * quilt * (1.0 - smoothstep(0.01, 0.03, fw)));
		albedo = mix(albedo, vec3(0.6, 0.5, 0.3), smoothstep(0.55, 0.75, fbm(uv * 0.9 + seedv * 5.0)) * 0.5);
		albedo *= 1.0 - 0.3 * foot;
		rough = 0.95;
		spec = 0.3;
		wet_k = 0.9;
	} else if (kind < 8.5) {
		// Tyre rubber: near black, the tread blocks across the crown (the cylinder's side), dusty.
		float tread = step(0.5, fract(uv.x / 0.05)) * (1.0 - smoothstep(0.004, 0.012, fw));
		albedo = vec3(0.055, 0.055, 0.058) * (1.0 - 0.3 * tread) + vec3(0.06, 0.05, 0.04) * vnoise(uv * 8.0);
		rough = 0.82;
		spec = 0.35;
	} else if (kind < 9.5) {
		// Timber: the planks scan along the grain, greyed by the sun.
		vec3 w = disp(texture(planks_tex, vec2(uv.x * 0.6, uv.y * 0.15)).rgb);
		float l = dot(w, vec3(0.333));
		albedo = paint * mix(vec3(l), w, 0.5) * 1.15;
		albedo *= 1.0 - 0.2 * foot;
		rough = 0.88;
	} else if (kind < 10.5) {
		// Printed sign sheeting: clean paint gone chalky, dirt collecting toward the bottom edge.
		albedo = paint * (0.94 + 0.06 * vnoise(uv * 3.0));
		albedo = mix(albedo, albedo * 0.82 + vec3(0.04, 0.035, 0.025), smoothstep(0.4, 0.0, uv.y / h) * 0.3 + 0.12 * smoothstep(0.6, 0.85, fbm(uv * 2.0 + seedv * 3.0)));
		rough = 0.55;
	} else if (kind < 11.5) {
		// Ink.
		albedo = paint;
		rough = 0.5;
	} else if (kind < 12.5) {
		// Hand-painted plywood: the grain under a brushed wash of paint, runs from the top.
		vec3 w = disp(texture(planks_tex, vec2(uv.x * 0.4, uv.y * 0.4) + 0.3).rgb);
		float brush = vnoise(vec2(uv.x * 2.0, uv.y * 22.0)) * 0.5 + vnoise(vec2(uv.x * 7.0, uv.y * 60.0)) * 0.5;
		albedo = mix(paint, paint * dot(w, vec3(0.45)) * 1.4, 0.25 + 0.2 * brush);
		float drip = step(0.86, hash12(vec2(floor(uv.x / 0.07), 2.0))) * smoothstep(h, h - 0.25 - 0.4 * hash12(vec2(floor(uv.x / 0.07), 5.0)), uv.y);
		albedo *= 1.0 - 0.1 * drip;
		rough = 0.8;
	} else if (kind < 13.5) {
		// Plastic.
		albedo = paint * (0.92 + 0.1 * vnoise(uv * 5.0));
		albedo *= 1.0 - 0.25 * foot;
		rough = 0.45;
		spec = 0.45;
	} else if (kind < 14.5) {
		// The booth's windows: dark glass, the sky mirrored by fresnel (emitted), the booth's own
		// lamp inside after dark.
		float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.0);
		albedo = vec3(0.05, 0.06, 0.065);
		emit += sky_tint.rgb * (0.18 + 0.6 * fres) * (1.0 - night_factor * 0.7);
		emit += vec3(1.0, 0.82, 0.58) * 0.9 * lamp_factor * (0.6 + 0.4 * smoothstep(0.2, 0.9, uv.y / h));
		rough = 0.12;
		spec = 0.7;
	} else if (kind < 15.5) {
		// A shopping cart's wire basket: a 3 cm grid of chromed wire, dithered under a pixel.
		float g = max(lines(uv.x, 0.035, 0.006), lines(uv.y, 0.035, 0.006));
		float cov = mix(g, 0.32, smoothstep(0.004, 0.02, fw));
		if (cov < bayer4(FRAGCOORD.xy)) {
			discard;
		}
		albedo = paint * (0.85 + 0.2 * vnoise(uv * 9.0));
		metal = 0.85;
		rough = 0.32;
	} else if (kind < 16.5) {
		// Painted sheet metal: ribs every 0.15 m, paint chalked and chipped to primer.
		float rib = lines(uv.x, 0.15, 0.02);
		albedo = paint * (1.0 - 0.15 * rib);
		float chip = smoothstep(0.7, 0.75, fbm(uv * 4.0 + seedv * 7.0));
		albedo = mix(albedo, vec3(0.5, 0.42, 0.36), chip * 0.7);
		albedo *= 1.0 - 0.3 * foot;
		rough = 0.6;
		metal = 0.2;
	} else if (kind < 17.5) {
		// Earth: a rubble pile's mound, dry dirt with stones.
		vec3 d = disp(texture(dirt_tex, (uv + world_p.xz) / 2.5).rgb);
		float l = dot(d, vec3(0.333));
		albedo = paint * mix(vec3(l), d, 0.6) * 1.1;
		albedo *= 0.8 + 0.3 * vnoise(uv * 9.0 + world_p.xz * 2.0);
		rough = 0.97;
	} else {
		// A bulb.
		albedo = vec3(0.9, 0.86, 0.75);
		emit += vec3(1.0, 0.78, 0.5) * 3.0 * lamp_factor;
		rough = 0.3;
	}
	float wet = clamp(road_wetness, 0.0, 1.0) * wet_k * (top ? 1.0 : 0.5);
	albedo *= 1.0 - 0.3 * wet;
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	EMISSION = emit;
	ROUGHNESS = mix(rough, 0.2, wet * 0.7);
	METALLIC = metal;
	SPECULAR = spec;
}
