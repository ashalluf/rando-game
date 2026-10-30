shader_type spatial;
render_mode cull_disabled;

// The power plant (PowerPlant, PowerPlantKit) as ONE material: every hall, stack, duct, boiler,
// transformer, tank, rack, gantry, fence and the seawall of a chunk is one mesh and one draw. What
// a face is rides in COLOR.a (PowerPlantKit.K_*, in 32nds), its paint in COLOR.rgb (sRGB numbers,
// raw on both renderers); UV is metres in the face's frame (x along, y up; a cylinder x round, y
// along), UV2.x the piece's height (a stack's bands), UV2.y a seed / a flag.
//    0 ribbed cladding   1 concrete   2 painted steel   3 galvanised (lattice)   4 concrete stack
//    5 window glass (lit after dark)   6 flood lamp lens   7 aviation red   8 aluminium jacket /
//    steel stack   9 roof   10 grating   11 louvre   12 tank shell   13 radiator fins   14 dark
//    15 sign board   16 letters   17 rock   18 porcelain   19 chain-link (cut out)   20 roll-up door
// Culling is off (the lattice angles are single faces); the normal is turned to the viewer on a
// back face here, because this shader writes its own.

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D corrugated_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float road_wetness;
global uniform float lamp_factor;
global uniform float night_factor;
global uniform vec4 sky_tint;

varying float kind;
varying vec3 world_n;
varying vec3 world_p;

#include "res://shaders/color_space.gdshaderinc"

// Tuned in display numbers (what Compatibility hands a shader and what COLOR is on both);
// Forward+'s decoded textures go back to display numbers and the result out in the renderer's own.
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

// 1 on a line every `spacing`, `w` wide; faded once the spacing is under a few pixels.
float lines(float v, float spacing, float w) {
	float g = abs(fract(v / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(v), 0.0005);
	float fade = 1.0 - smoothstep(0.03, 0.12, fw / spacing * 4.0);
	return (1.0 - smoothstep(w * 0.5, w * 0.5 + fw, g)) * fade;
}

// Dirt run down a wall from its top and splashed up its foot.
float grime(vec2 uv, float h, float seed) {
	float s = vnoise(vec2(uv.x * 1.3 + seed, 0.5)) * 0.6 + vnoise(vec2(uv.x * 4.7 + seed * 3.0, 1.5)) * 0.4;
	float from_top = clamp((h - uv.y) / max(h, 0.5), 0.0, 1.0);
	float run = smoothstep(0.5, 0.92, s) * (1.0 - from_top * 0.55) * (0.6 + 0.4 * vnoise(uv * vec2(2.0, 0.3)));
	float foot = (1.0 - smoothstep(0.0, 1.4, uv.y)) * 0.6;
	return clamp(run * 0.55 + foot, 0.0, 1.0);
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
	vec3 wn = FRONT_FACING ? world_n : -world_n;
	bool top = wn.y > 0.5;
	vec3 paint = COLOR.rgb;
	vec3 albedo = paint;
	float rough = 0.7;
	float metal = 0.0;
	float spec = 0.5;
	float wet_k = 0.5;
	vec3 emit = vec3(0.0);
	vec3 nrm = wn;
	vec3 tangent_u = normalize(cross(vec3(0.0, 1.0, 0.0), wn) + vec3(1e-4));
	float seedv = hash12(floor(world_p.xz / 23.0) + param * 0.37);
	vec3 V = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float fres = pow(1.0 - clamp(abs(dot(V, wn)), 0.0, 1.0), 4.0);
	if (kind < 0.5) {
		// Ribbed metal cladding: trapezoidal ribs every 0.3 m (the normal turns on their flanks),
		// panel laps every 6 m up, sheets a shade apart, chalked by the sun, streaked from the top.
		float r = fract(uv.x / 0.305);
		float flank = smoothstep(0.0, 0.08, r) - smoothstep(0.2, 0.28, r);
		float slope = (smoothstep(0.0, 0.08, r) * (1.0 - smoothstep(0.08, 0.1, r)) - smoothstep(0.2, 0.28, r) * (1.0 - smoothstep(0.28, 0.3, r)));
		float fw = fwidth(uv.x / 0.305);
		float keep = 1.0 - smoothstep(0.15, 0.5, fw);
		if (!top) {
			nrm = normalize(wn + tangent_u * slope * 1.6 * keep);
		}
		float sheet = floor(uv.x / 1.0);
		float course = floor(uv.y / 6.0);
		float st = 0.94 + 0.1 * hash12(vec2(sheet, course) + seedv * 7.0);
		vec3 tex = disp(texture(corrugated_tex, uv / 3.0).rgb);
		albedo = paint * st * (0.88 + 0.2 * dot(tex, vec3(0.333))) * (1.0 - 0.06 * flank * keep);
		float lap = lines(uv.y, 6.0, 0.05);
		albedo *= 1.0 - 0.25 * lap;
		float g = grime(uv, h, param);
		albedo = mix(albedo, albedo * vec3(0.62, 0.6, 0.56), g * 0.55);
		albedo = mix(albedo, vec3(dot(albedo, vec3(0.333))) * 1.06, 0.12 * smoothstep(0.4, 1.0, uv.y / h));
		metal = 0.35;
		rough = 0.48;
	} else if (kind < 1.5) {
		// Concrete: the texture at its size, form panels 2.4 x 1.2 m with tie holes, a seed's tone.
		vec3 c = disp(texture(concrete_tex, uv / 3.0).rgb);
		float tone = dot(c, vec3(0.333));
		float pnl = lines(uv.x, 2.4, 0.03) * 0.6 + lines(uv.y, 1.2, 0.025) * 0.4;
		vec2 tie = fract(uv / vec2(0.6, 0.6)) - 0.5;
		float hole = (1.0 - smoothstep(0.03, 0.05, length(tie))) * (1.0 - smoothstep(0.02, 0.08, fwidth(uv.x)));
		albedo = paint * (0.62 + 0.52 * tone) * (0.95 + 0.1 * hash12(floor(uv / vec2(2.4, 1.2)) + seedv));
		albedo *= 1.0 - 0.18 * pnl - 0.25 * hole;
		albedo = mix(albedo, albedo * vec3(0.66, 0.64, 0.6), grime(uv, h, param + 3.0) * 0.6);
		rough = 0.9;
		wet_k = 0.9;
	} else if (kind < 2.5) {
		// Painted steel: the paint chalked and stained, darker where it collects dirt low down.
		float n = fbm(uv * vec2(1.2, 0.6) + seedv * 9.0);
		albedo = paint * (0.9 + 0.16 * n);
		albedo = mix(albedo, albedo * vec3(0.6, 0.54, 0.48), grime(uv, h, param + 1.0) * 0.45);
		metal = 0.25;
		rough = 0.55;
	} else if (kind < 3.5) {
		// Galvanised steel: spangled zinc, dulled.
		float sp = vnoise(uv * 14.0 + seedv * 5.0);
		albedo = paint * (0.86 + 0.18 * sp);
		metal = 0.75;
		rough = 0.42;
	} else if (kind < 4.5) {
		// A concrete stack: slipform lifts every 1.5 m, darker staining down from the top's soot,
		// and on the tall pair (UV2.y 1) the aviation marking - red and white bands over its top
		// third - with the paint weathered.
		vec3 c = disp(texture(concrete_tex, uv / vec2(2.5, 4.0)).rgb);
		float y = uv.y + 1.2;
		float lift = lines(y, 1.5, 0.04);
		albedo = paint * (0.7 + 0.42 * dot(c, vec3(0.333))) * (1.0 - 0.12 * lift);
		float soot = smoothstep(h * 0.75, h, y) * (0.6 + 0.4 * vnoise(vec2(uv.x * 0.6, y * 0.2)));
		if (param > 0.5) {
			float bands_from = h * 0.62;
			if (y > bands_from) {
				float bw = (h - bands_from) / 5.0;
				float k = floor((y - bands_from) / bw);
				vec3 red = vec3(0.72, 0.16, 0.10);
				vec3 white = vec3(0.86, 0.84, 0.8);
				vec3 band_col = mod(k, 2.0) < 0.5 ? red : white;
				float edge = smoothstep(0.0, fwidth(y) * 1.5, abs(fract((y - bands_from) / bw) - 0.5) * bw - 0.0);
				albedo = mix(albedo, band_col * (0.86 + 0.18 * dot(c, vec3(0.333))), 0.92 * edge + 0.0);
				soot *= 0.8;
			}
		}
		float streak = smoothstep(0.55, 0.9, vnoise(vec2(uv.x * 0.9 + seedv * 11.0, 0.5))) * smoothstep(h * 0.4, h, y);
		albedo = mix(albedo, vec3(0.12, 0.11, 0.1), clamp(soot * 0.7 + streak * 0.35, 0.0, 0.85));
		rough = 0.88;
		wet_k = 0.8;
	} else if (kind < 5.5) {
		// Windows: a band of panes between mullions, the sky mirrored by fresnel (emitted), rooms
		// lit warm after dark, most of them.
		float pitch = 1.5;
		float mull = max(lines(uv.x, pitch, 0.08), lines(uv.y, max(h, 1.0), 0.1));
		vec3 mirror = disp(sky_tint.rgb) * (0.28 + 0.65 * fres) * (0.85 + 0.3 * vnoise(vec2(floor(uv.x / pitch), 0.5) * 3.0));
		albedo = mix(paint * 0.4, vec3(0.2, 0.21, 0.22), mull);
		emit += cs_srgb_to_linear(mirror) * 0.55 * (1.0 - mull) * (1.0 - night_factor * 0.75);
		float lit = step(0.3, hash12(vec2(floor(uv.x / (pitch * 3.0)), param) + seedv));
		emit += vec3(1.0, 0.82, 0.55) * 0.9 * lit * lamp_factor * (1.0 - mull);
		rough = mix(0.08, 0.5, mull);
		metal = 0.5 * mull;
		spec = 0.7;
		wet_k = 0.0;
	} else if (kind < 6.5) {
		// A flood lamp's lens: HDR after dark.
		albedo = vec3(0.85, 0.85, 0.82);
		emit += cs_srgb_to_linear(paint) * 7.0 * lamp_factor;
		rough = 0.2;
	} else if (kind < 7.5) {
		// An aviation red lamp: steady, dim by day.
		albedo = vec3(0.5, 0.06, 0.04);
		emit += vec3(1.0, 0.05, 0.02) * (0.4 + 5.0 * lamp_factor);
		rough = 0.25;
	} else if (kind < 8.5) {
		// Aluminium jacket (insulated pipe, drums) or a steel stack: sheets lapped every 1.2 m with
		// a bright band at each lap, faint dents; brighter, glossier on the jackets.
		float lap = lines(uv.y, 1.2, 0.03);
		float dent = vnoise(uv * vec2(1.5, 0.7) + seedv * 13.0);
		albedo = paint * (0.86 + 0.14 * dent) * (1.0 + 0.12 * lap);
		albedo = mix(albedo, albedo * vec3(0.55, 0.5, 0.45), smoothstep(h * 0.82, h, uv.y) * 0.5);
		metal = 0.7;
		rough = 0.36;
	} else if (kind < 9.5) {
		// Roof: membrane with seams and ponding stains, or gravel; walls of a roof piece read as
		// the parapet's flashing.
		float seam = lines(uv.x, 3.0, 0.04);
		float pond = smoothstep(0.55, 0.8, fbm(uv * 0.11 + seedv * 5.0));
		albedo = paint * (0.92 + 0.12 * vnoise(uv * 0.8)) * (1.0 - 0.12 * seam) * (1.0 - 0.22 * pond);
		rough = 0.88;
		wet_k = 1.0;
	} else if (kind < 10.5) {
		// Grating: bars every 3 cm one way, every 10 cm the other, dark between; its average far.
		float fw = max(fwidth(uv.x), fwidth(uv.y));
		float bars = max(lines(uv.x, 0.033, 0.006), lines(uv.y, 0.1, 0.006));
		float avg = 0.45;
		float cover = mix(bars, avg, smoothstep(0.005, 0.03, fw));
		albedo = mix(vec3(0.06), paint, cover);
		metal = 0.6 * cover;
		rough = 0.55;
	} else if (kind < 11.5) {
		// Louvres: horizontal blades every 10 cm, the normal tilted up on each, a dark gap below it.
		float b = fract(uv.y / 0.1);
		float fw = fwidth(uv.y / 0.1);
		float keep = 1.0 - smoothstep(0.2, 0.6, fw);
		nrm = normalize(wn + vec3(0.0, 0.8 * keep, 0.0) * (1.0 - smoothstep(0.0, 0.75, b)));
		albedo = paint * mix(1.0, 0.3 + 0.7 * smoothstep(0.0, 0.25, b), keep);
		metal = 0.4;
		rough = 0.5;
	} else if (kind < 12.5) {
		// A tank shell: welded courses every 2.4 m, plates staggered, rust weeping from the roof
		// edge and the foot; the roof (UV2.y 1) a shade darker.
		float course = lines(uv.y, 2.4, 0.03);
		float pl = floor(uv.y / 2.4);
		float vert = lines(uv.x + pl * 3.0, 6.0, 0.025);
		albedo = paint * (0.94 + 0.08 * vnoise(uv * vec2(0.5, 0.3) + seedv * 3.0)) * (1.0 - 0.14 * course - 0.1 * vert);
		float rust = smoothstep(0.62, 0.9, vnoise(vec2(uv.x * 1.3, 0.5) + seedv * 9.0)) * smoothstep(h * 0.6, h, uv.y) * (0.5 + 0.5 * vnoise(uv * vec2(4.0, 0.4)));
		rust += (1.0 - smoothstep(0.0, 1.0, uv.y)) * 0.4;
		albedo = mix(albedo, vec3(0.42, 0.26, 0.15), clamp(rust * 0.6, 0.0, 0.7));
		metal = 0.3;
		rough = 0.5;
	} else if (kind < 13.5) {
		// Radiator fins: thin vertical plates 0.1 m apart, the normal swinging across them.
		float f = fract(uv.x / 0.1);
		float keep = 1.0 - smoothstep(0.2, 0.6, fwidth(uv.x / 0.1));
		nrm = normalize(wn + tangent_u * (f - 0.5) * 2.0 * keep);
		albedo = paint * mix(1.0, 0.55 + 0.45 * sin(f * 3.14159), keep);
		metal = 0.3;
		rough = 0.55;
	} else if (kind < 14.5) {
		albedo = paint;
		rough = 0.9;
	} else if (kind < 15.5) {
		// A sign board: enamelled, lit faintly at night from below.
		albedo = paint * (0.95 + 0.05 * vnoise(uv * 2.0));
		rough = 0.35;
		emit += cs_srgb_to_linear(paint) * 0.15 * lamp_factor;
	} else if (kind < 16.5) {
		// Letters: their paint, lit after dark like a backlit sign.
		albedo = paint;
		rough = 0.4;
		emit += cs_srgb_to_linear(paint) * 0.9 * lamp_factor;
	} else if (kind < 17.5) {
		// Rip-rap: granite blocks, flecked, wet and dark at the foot.
		vec3 c = disp(texture(concrete_tex, world_p.xz / 1.7 + world_p.y * 0.3).rgb);
		albedo = paint * (0.7 + 0.5 * dot(c, vec3(0.333))) * (0.85 + 0.3 * vnoise(world_p.xz * 3.0 + world_p.y));
		albedo *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.5, world_p.y - 0.1));
		rough = 0.82;
	} else if (kind < 18.5) {
		// Glazed porcelain (insulators, bushings): glossy.
		albedo = paint;
		rough = 0.12;
		spec = 0.65;
	} else if (kind < 19.5) {
		// Chain-link: 6 cm diamonds, dithered to their average once under a few pixels.
		vec2 q = uv / 0.06;
		vec2 d = vec2(q.x + q.y, q.x - q.y);
		vec2 f = abs(fract(d) - 0.5);
		float dist = 0.5 - max(f.x, f.y);
		float fw = max(fwidth(d.x), fwidth(d.y));
		float wire = 0.09;
		float line = 1.0 - smoothstep(wire, wire + fw, dist);
		float avg = 1.0 - (1.0 - 2.0 * wire) * (1.0 - 2.0 * wire);
		float cover = mix(line, avg * 0.8, smoothstep(0.25, 0.7, fw));
		if (cover < bayer4(FRAGCOORD.xy)) {
			discard;
		}
		albedo = paint * (0.8 + 0.3 * fract(d.x * 0.5));
		metal = 0.6;
		rough = 0.45;
	} else {
		// A roll-up door: slats every 8 cm, a darker bottom rail, scuffs.
		float sl = fract(uv.y / 0.08);
		float keep = 1.0 - smoothstep(0.2, 0.6, fwidth(uv.y / 0.08));
		nrm = normalize(wn + vec3(0.0, (sl - 0.5) * 0.9 * keep, 0.0));
		albedo = paint * (0.9 + 0.1 * vnoise(uv * vec2(0.6, 3.0))) * (1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.25, uv.y)));
		metal = 0.4;
		rough = 0.5;
	}
	float wet = clamp(road_wetness, 0.0, 1.0) * wet_k * (top ? 1.0 : 0.35);
	albedo *= 1.0 - 0.25 * wet;
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	EMISSION = emit;
	ROUGHNESS = mix(rough, 0.2, wet * 0.6);
	METALLIC = metal;
	SPECULAR = spec;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}
