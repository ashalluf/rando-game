shader_type spatial;

// The oil refinery (Refinery, RefineryKit) as ONE material: a chunk's tanks, berms, columns,
// structures, pipe racks, heaters, cooling towers, spheres, flare stacks, buildings and lamps are
// one mesh and one draw. Each face says what it is in COLOR.a (RefineryKit.K_*, in 32nds - the
// IndustrialKit / FilmStudioKit writers) and carries its paint in COLOR.rgb (display numbers). UV is
// metres in the face's own frame (x along it, y up from the piece's foot), UV2.x the piece's height
// and UV2.y a per-piece parameter (a seed, a band count, a lamp's colour).
//    0 tank shell (welded courses, rust runs, the floodlit foot)    1 aluminium-jacketed insulation
//    2 painted structural steel     3 steel grating (decks, treads)  4 concrete (fireproofing, plinths)
//    5 earth berm                   6 handrail (cut out: rails, posts, toe board)
//    7 lamp (lit with the lamps; UV2.y 0 sodium, 1 LED white, 2 red)  8 floating roof deck
//    9 painted pipe                10 control-room glass (lit at night)  11 ribbed metal siding
//   12 sign paint                  13 cooling-tower louvres            14 dark (fan throats, voids)
//   15 red / white aviation bands (UV2.y the band count)               16 heater steel (peep doors
//      glow)                       17 gravel                           18 sphere shell
//   19 soot (a flare tip, a stack's crown)
// Night: the place is a city of lights - the lamps themselves are billboards (aircraft_lights);
// here the steel near them is lit warm and the tanks are floodlit from their feet.

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D corrugated_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
/// How bright the steel round the platform lamps glows after dark (display numbers x lamp_factor).
uniform float flood = 0.24;
/// The tanks' floodlit feet after dark.
uniform float tank_flood = 0.42;

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

// 1 on a line every `spacing`, `w` wide, faded once the spacing is under a few pixels.
float lines(float v, float spacing, float w) {
	float g = abs(fract(v / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(v), 0.0005);
	float fade = 1.0 - smoothstep(0.03, 0.12, fw / spacing * 4.0);
	return (1.0 - smoothstep(w * 0.5, w * 0.5 + fw, g)) * fade;
}

float band(float v, float c, float w) {
	float fw = max(fwidth(v), 0.0005);
	return 1.0 - smoothstep(w, w + fw, abs(v - c));
}

// Rain-run dirt down a wall from its top: vertical streaks, stronger toward the foot.
float streaks(vec2 uv, float h, float seed) {
	float s = vnoise(vec2(uv.x * 1.3 + seed, 0.5)) * 0.6 + vnoise(vec2(uv.x * 4.7 + seed * 3.0, 1.5)) * 0.4;
	float from_top = clamp((h - uv.y) / max(h, 0.5), 0.0, 1.0);
	return smoothstep(0.5, 0.92, s) * (0.3 + 0.7 * (1.0 - from_top * 0.7)) * (0.7 + 0.3 * vnoise(uv * vec2(3.0, 0.35)));
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
	bool bottom = world_n.y < -0.5;
	vec3 paint = COLOR.rgb;
	vec3 albedo = paint;
	float rough = 0.8;
	float metal = 0.0;
	float wet_k = 0.5;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	vec3 nrm_world = world_n;
	float foot = top ? 0.0 : 1.0 - smoothstep(0.0, 0.8, uv.y);
	// The "this part of the plant has a lamp on it" field: 7 m cells of the world, two in three lit.
	vec3 cellp = floor(world_p / 7.0);
	float lamp_cell = step(0.34, hash12(cellp.xz + cellp.y * 3.1));
	vec3 sodium = vec3(1.0, 0.62, 0.3);
	float lit_steel = 0.0;
	if (kind < 0.5) {
		// A tank shell: courses of plate 2.4 m high welded round, the vertical joints staggered
		// course to course, paint chalking in patches, rust run down from the wind girder and the
		// roof seal, the oily foot and the dirt splashed up at the base. Floodlit from below at night.
		float course = floor(uv.y / 2.4);
		float joint_u = uv.x + mod(course, 2.0) * 4.8;
		float weld = max(lines(uv.y, 2.4, 0.03), lines(joint_u, 9.6, 0.03));
		float chalk = fbm(uv * vec2(0.08, 0.2) + param * 3.1);
		albedo = paint * (0.9 + 0.12 * (chalk - 0.5)) * (1.0 - 0.08 * weld);
		if (top) {
			albedo = paint * 0.8 * (0.85 + 0.25 * vnoise(uv * 0.3));
		} else {
			float run = streaks(uv * vec2(0.6, 1.0), h, param * 7.0);
			albedo = mix(albedo, vec3(0.42, 0.27, 0.16), 0.28 * run * smoothstep(0.55, 0.95, vnoise(vec2(uv.x * 0.7, 0.3) + param)));
			albedo *= 1.0 - 0.12 * run;
			albedo = mix(albedo, vec3(0.18, 0.16, 0.13), 0.55 * foot * (0.6 + 0.4 * vnoise(uv * vec2(1.5, 2.0))));
			// Each floodlight a bright fan up the shell from its foot, every ~14 m round it.
			float fan = 0.35 + 0.65 * pow(abs(cos(uv.x / 14.0 * 3.14159 + param)), 3.0);
			emit += to_lit(sodium) * tank_flood * lamp_factor * exp(-uv.y / max(h * 0.8, 1.0)) * fan;
		}
		metal = 0.2;
		rough = 0.62;
		wet_k = 1.0;
	} else if (kind < 1.5) {
		// Aluminium jacketing over insulation: sheets lapped every 1.2 m with a band at each lap,
		// a vertical seam, gently dented, a dull metallic sheen dirtied low down and under drips.
		float lap = lines(uv.y, 1.2, 0.035);
		float seam = lines(uv.x, max(param, 3.1), 0.03);
		// One tone per sheet (1.2 m courses, staggered seams), a faint dent, run-down grime.
		float sheet = hash12(vec2(floor(uv.x / max(param, 3.1)), floor(uv.y / 1.2)) + param);
		float dent = vnoise(uv * vec2(0.9, 1.4) + param);
		albedo = vec3(0.6, 0.61, 0.6) * (0.9 + 0.1 * sheet + 0.05 * dent) * (1.0 - 0.18 * lap) * (1.0 - 0.12 * seam);
		albedo *= 1.0 - 0.14 * streaks(uv * vec2(1.5, 1.0), h, param * 3.0);
		albedo = mix(albedo, vec3(0.3, 0.28, 0.25), 0.4 * foot);
		metal = 0.6;
		rough = 0.42 + 0.12 * sheet;
		lit_steel = 1.0;
	} else if (kind < 2.5) {
		// Painted structural steel: the paint scuffed, rust at the joints, dirt at the foot.
		float rust = smoothstep(0.82, 0.97, vnoise(uv * vec2(1.6, 0.25) + paint.rg * 9.0)) * 0.35 + foot * 0.2;
		albedo = mix(paint * (0.92 + 0.12 * vnoise(uv * vec2(3.0, 0.8))), vec3(0.34, 0.21, 0.13), clamp(rust, 0.0, 0.45));
		rough = mix(0.5, 0.85, rust);
		metal = 0.25;
		lit_steel = 1.0;
	} else if (kind < 3.5) {
		// Grating: bearing bars 30 mm apart across cross bars every 100 mm, painted or galvanised,
		// the gaps dark (seen from below the deck is the bars' shadowed undersides).
		float bars = lines(uv.x, 0.03, 0.006);
		float cross_b = lines(uv.y, 0.1, 0.008);
		float solid = max(bars, cross_b);
		vec3 steel = paint * (0.9 + 0.15 * vnoise(uv * 2.0));
		albedo = mix(vec3(0.05, 0.05, 0.05), steel, mix(0.55, 1.0, solid));
		if (bottom) {
			albedo = steel * 0.35;
		}
		metal = 0.45;
		rough = 0.6;
		lit_steel = 1.0;
	} else if (kind < 4.5) {
		// Concrete: fireproofing round the column feet, plinths, the pads.
		vec3 c = disp(texture(concrete_tex, uv / 2.4).rgb);
		albedo = paint * (0.62 + 0.48 * dot(c, vec3(0.333))) * (1.0 - 0.25 * foot);
		albedo *= 1.0 - 0.15 * streaks(uv, h, paint.r * 9.0) * (top ? 0.0 : 1.0);
		rough = 0.9;
		lit_steel = 0.6;
	} else if (kind < 5.5) {
		// An earth berm round a tank: packed dirt, dry grass in the gentle parts, erosion runnels.
		vec3 d = disp(texture(dirt_tex, uv / 4.0).rgb);
		float grass = smoothstep(0.45, 0.75, fbm(uv * 0.12 + 3.0)) * (top ? 1.0 : 0.6);
		albedo = mix(paint * (0.6 + 0.6 * dot(d, vec3(0.333))), vec3(0.52, 0.45, 0.26) * (0.8 + 0.4 * vnoise(uv * 3.0)), grass * 0.7);
		albedo *= 1.0 - 0.12 * lines(uv.x, 1.7, 0.08) * (top ? 0.0 : 1.0);
		rough = 0.95;
		spec = 0.3;
		wet_k = 1.0;
	} else if (kind < 6.5) {
		// A handrail run (one quad, both faces): top rail, knee rail, toe board and posts every
		// 1.8 m; the rest of the quad is not there.
		float hy = uv.y;
		float rail = band(hy, 1.07, 0.03) + band(hy, 0.55, 0.022);
		float toe = 1.0 - step(0.12, hy);
		float post = 1.0 - smoothstep(0.025, 0.025 + max(fwidth(uv.x), 0.0005), abs(fract(uv.x / 1.8 + 0.5) - 0.5) * 1.8);
		float keep = clamp(rail + toe + post * step(hy, 1.09), 0.0, 1.0);
		// Under a pixel the rails are kept by their coverage (about a fifth of the quad), dithered
		// per pixel - kept whole, a far rail was a solid yellow band round every platform.
		float far_k = smoothstep(0.02, 0.07, fwidth(uv.y));
		float dither = hash12(FRAGCOORD.xy);
		if (keep < 0.5 && (far_k < 0.5 || dither > 0.22)) {
			discard;
		}
		albedo = paint * (0.85 + 0.2 * vnoise(uv * vec2(2.0, 8.0)));
		rough = 0.55;
		metal = 0.2;
		lit_steel = 1.0;
	} else if (kind < 7.5) {
		// A lamp: a dark housing, its lens lit with the lamps.
		vec3 lc = param < 0.5 ? vec3(1.0, 0.66, 0.32) : (param < 1.5 ? vec3(0.95, 0.97, 1.0) : vec3(1.0, 0.08, 0.04));
		albedo = mix(vec3(0.16, 0.16, 0.17), lc * 0.7, bottom ? 1.0 : 0.2);
		emit += to_lit(lc) * (bottom ? 9.0 : 2.0) * lamp_factor;
		rough = 0.4;
		metal = 0.3;
	} else if (kind < 8.5) {
		// A floating roof seen from above: steel deck plates lapped in strips, the pontoon ring's
		// joints, drain sumps, puddles of rainwater and dark oily stains; the seal a black ring.
		float strip = lines(uv.x, 1.83, 0.03);
		float ring_r = length(uv - vec2(h * 0.5));
		float pont = band(ring_r, h * 0.5 - 4.5, 0.06) + band(ring_r, h * 0.5 - 0.35, 0.18);
		float stain = smoothstep(0.55, 0.8, fbm(uv * 0.07 + param * 5.0));
		albedo = vec3(0.34, 0.34, 0.33) * (0.85 + 0.2 * vnoise(uv * 0.5));
		albedo *= 1.0 - 0.18 * strip;
		albedo = mix(albedo, vec3(0.08, 0.08, 0.08), clamp(pont * 0.8 + stain * 0.45, 0.0, 1.0));
		float puddle = smoothstep(0.7, 0.78, vnoise(uv * 0.11 + param * 2.0)) * (0.4 + 0.6 * clamp(road_wetness * 2.0, 0.0, 1.0));
		rough = mix(0.65, 0.08, puddle);
		metal = 0.35;
		wet_k = 1.0;
	} else if (kind < 9.5) {
		// A painted pipe: the line's colour, a dull sheen, rust at the supports, dirt underneath.
		float shoe = lines(uv.y, 6.0, 0.25);
		albedo = paint * (0.9 + 0.12 * vnoise(uv * vec2(0.6, 3.0)));
		albedo = mix(albedo, vec3(0.36, 0.22, 0.13), 0.35 * shoe * smoothstep(0.6, 0.9, vnoise(uv * 2.0 + paint.rg * 7.0)));
		rough = 0.48;
		metal = 0.35;
		lit_steel = 1.0;
	} else if (kind < 10.5) {
		// The control room's glass: dark, the sky by fresnel, lit pane by pane after dark (it is
		// manned round the clock: most panes stay lit).
		float pitch = max(param, 0.6);
		float mull = lines(uv.x, pitch, 0.06);
		float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.0);
		albedo = mix(vec3(0.05, 0.06, 0.07), vec3(0.2, 0.2, 0.21), mull);
		emit += to_lit(disp(sky_tint.rgb)) * (0.15 + 0.5 * fres) * (1.0 - mull) * (1.0 - night_factor * 0.8);
		float lit = step(0.2, hash12(vec2(floor(uv.x / pitch), floor(world_p.y / 3.8)) + floor(world_p.xz / 50.0))) * lamp_factor;
		emit += vec3(0.95, 0.9, 0.78) * 0.7 * lit * (1.0 - mull);
		rough = mix(0.06, 0.5, mull);
		metal = 0.4;
		spec = 0.7;
		wet_k = 0.0;
	} else if (kind < 11.5) {
		// Ribbed metal siding: 200 mm box ribs swing the normal, laps every 0.9 m, rain streaks.
		float rib = fract(uv.x / 0.2);
		float lap = lines(uv.x, 0.9, 0.012);
		albedo = paint * (0.9 + 0.12 * vnoise(uv * vec2(0.5, 3.0))) * (1.0 - 0.15 * lap);
		albedo *= 1.0 - 0.22 * streaks(uv, h, paint.g * 7.0);
		metal = 0.45;
		rough = 0.5;
		if (!top && !bottom) {
			vec3 t = normalize(cross(world_n, vec3(0.0, 1.0, 0.0)) + vec3(1e-4));
			float fade = 1.0 - smoothstep(0.01, 0.06, fwidth(uv.x));
			nrm_world = normalize(world_n + t * (smoothstep(0.0, 0.08, rib) - smoothstep(0.42, 0.5, rib) - 0.5) * 0.7 * fade);
		}
		lit_steel = 0.5;
	} else if (kind < 12.5) {
		// Sign paint and lettering: matte, chipped back here and there; lit from the front at night.
		float chip = smoothstep(0.78, 0.84, fbm(world_p.xy * 1.7 + world_p.zz * 1.3));
		albedo = mix(paint, paint * 0.6 + 0.25, chip * 0.5);
		emit += to_lit(paint) * 0.35 * lamp_factor;
		rough = 0.8;
	} else if (kind < 13.5) {
		// A cooling tower's louvres: dark slats sloping in, wet and green-streaked under the deck.
		float slat = fract(uv.y / 0.32);
		albedo = mix(vec3(0.07, 0.08, 0.08), paint, smoothstep(0.55, 0.75, slat));
		albedo = mix(albedo, vec3(0.16, 0.22, 0.16), 0.3 * streaks(uv, h, 4.0));
		albedo *= 1.0 - 0.3 * lines(uv.x, 3.6, 0.12);
		rough = 0.7;
		wet_k = 1.0;
	} else if (kind < 14.5) {
		albedo = paint * 0.4;
		rough = 0.9;
	} else if (kind < 15.5) {
		// Red and white aviation bands (UV2.y of them up the height), sooted toward the top.
		float n = max(param, 1.0);
		float b = mod(floor(uv.y / h * n), 2.0);
		albedo = mix(vec3(0.82, 0.8, 0.77), vec3(0.62, 0.1, 0.07), b);
		albedo = mix(albedo, vec3(0.06, 0.05, 0.05), smoothstep(0.82, 1.0, uv.y / h) * 0.8);
		albedo *= 1.0 - 0.15 * streaks(uv, h, 2.0);
		rough = 0.6;
		metal = 0.2;
	} else if (kind < 16.5) {
		// A fired heater's casing: dark heat-stained steel, a row of peep doors glowing orange.
		albedo = paint * (0.8 + 0.25 * vnoise(uv * vec2(0.5, 2.0)));
		albedo = mix(albedo, vec3(0.2, 0.14, 0.1), 0.4 * smoothstep(0.4, 1.0, uv.y / h));
		float peep = (1.0 - smoothstep(0.08, 0.1, abs(fract(uv.x / 2.4) - 0.5) * 2.4)) * band(uv.y, 1.6, 0.09) * (top || bottom ? 0.0 : 1.0);
		emit += vec3(1.0, 0.35, 0.06) * 3.0 * peep * (0.55 + 0.45 * vnoise(vec2(uv.x, TIME * 2.0)));
		rough = 0.75;
		metal = 0.3;
		lit_steel = 0.7;
	} else if (kind < 17.5) {
		vec3 d = disp(texture(dirt_tex, uv / 3.0).rgb);
		albedo = paint * (0.55 + 0.6 * dot(d, vec3(0.333))) * (0.85 + 0.3 * vnoise(uv * 9.0));
		rough = 0.95;
		wet_k = 1.0;
	} else if (kind < 18.5) {
		// A sphere's shell: welded petals (meridians and the equator band), white paint, rust run.
		albedo = paint * (0.92 + 0.1 * vnoise(uv * 0.2 + param));
		float weld = max(lines(uv.x, 4.2, 0.03), lines(uv.y, 3.0, 0.03));
		albedo *= 1.0 - 0.08 * weld;
		albedo = mix(albedo, vec3(0.42, 0.27, 0.16), 0.2 * streaks(uv * vec2(0.5, 1.0), h, param));
		emit += to_lit(sodium) * tank_flood * 0.7 * lamp_factor * exp(-uv.y / max(h * 0.5, 1.0));
		metal = 0.2;
		rough = 0.55;
		wet_k = 1.0;
	} else {
		// Soot: a flare's tip, a stack's crown.
		albedo = vec3(0.05, 0.045, 0.04) * (0.8 + 0.4 * vnoise(uv * 4.0));
		rough = 0.9;
	}
	// After dark the steel round the platform lamps is lit warm (two cells in three have one).
	emit += to_lit(sodium * albedo) * flood * lit_steel * lamp_cell * lamp_factor * (bottom ? 1.6 : 1.0);
	float wet = clamp(road_wetness, 0.0, 1.0) * wet_k * (top ? 1.0 : 0.4);
	albedo *= 1.0 - 0.25 * wet;
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	EMISSION = emit;
	ROUGHNESS = mix(rough, 0.18, wet * 0.7);
	METALLIC = metal;
	SPECULAR = spec;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm_world, 0.0)).xyz);
}
