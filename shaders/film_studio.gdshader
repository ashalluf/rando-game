shader_type spatial;

// The film studio lot (FilmStudio, FilmStudioKit) as ONE material: a chunk's sound stages, the
// perimeter wall, the gate and its arch, the office block, the backlot's false fronts and their
// bracing, the trailers, trucks and golf carts are one mesh and one draw. Each box says what it is
// in COLOR.a (FilmStudioKit.K_*, in 32nds, written by IndustrialKit's box / cyl writers) and
// carries its paint in COLOR.rgb (display numbers). UV is metres in the face's own frame (x along
// the face from its left corner seen from outside, y up from the box's foot), UV2.x the box's
// height and UV2.y a per-box parameter.
//    0 stucco (stage walls, the perimeter wall, the gate)       1 standing-seam roof (UV2.y a seed)
//    2 elephant door (UV2.y the leaf width)    3 painted steel   4 glass (UV2.y the mullion pitch)
//    5 lamp (lit after dark; UV2.y 1 lit by day too: a stage's red light)    6 brick
//    7 stone (ashlar courses)   8 plywood / timber   9 canvas (UV2.y the stripe width)
//   10 sign paint (lettering, matte, chipped)   11 concrete   12 gilt letters (lit after dark)
//   13 rubber   14 chrome   15 trailer skin (UV2.y the stripe colour index)   16 roofing felt
// Everything is invented: no studio's name, mark or livery.

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D planks_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float road_wetness;
global uniform float lamp_factor;
global uniform float night_factor;
global uniform vec4 sky_tint;

varying float kind;
varying vec3 world_n;
varying vec3 world_p;

#include "res://shaders/color_space.gdshaderinc"

// Tuned in display numbers (what COLOR is on both renderers); textures go back to display
// numbers on Forward+ (disp()) and the result out in the renderer's own space (to_lit()).
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
	float rough = 0.85;
	float metal = 0.0;
	float wet_k = 0.5;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	vec3 nrm_world = world_n;
	float foot = top ? 0.0 : 1.0 - smoothstep(0.0, 0.6, uv.y);
	float seedv = hash12(floor(world_p.xz / 23.0));
	if (kind < 0.5) {
		// Stucco: a sand finish troweled on in patches (low-contrast mottle, a fine grain that
		// catches the sun in the normal), the paint chalking unevenly, rain streaks run down from
		// the parapet, splash-back dirt at the foot and old patch repairs in a near-match.
		vec3 c = disp(texture(concrete_tex, uv / 4.5).rgb);
		float tone = dot(c, vec3(0.333));
		float trowel = fbm(uv * 0.45 + seedv * 17.0);
		albedo = paint * (0.9 + 0.16 * (tone - 0.5) + 0.07 * (trowel - 0.5));
		if (top) {
			albedo = paint * 0.82 * (0.85 + 0.25 * vnoise(uv * 2.0));
			rough = 0.9;
		} else {
			float patch_n = vnoise(floor(uv / vec2(3.1, 2.2)) + seedv * 41.0);
			vec2 pf = fract(uv / vec2(3.1, 2.2));
			float patch_m = step(0.86, patch_n) * step(0.12, pf.x) * step(pf.x, 0.8) * step(0.15, pf.y) * step(pf.y, 0.75);
			albedo *= mix(1.0, 1.035 + 0.03 * (patch_n - 0.9) * 10.0, patch_m);
			albedo *= 1.0 - 0.22 * streaks(uv, h, seedv * 11.0);
			albedo *= 1.0 - 0.14 * smoothstep(h - 1.0, h, uv.y) * (0.6 + 0.4 * vnoise(uv * vec2(2.0, 0.5)));
			albedo *= 1.0 - 0.3 * foot * (0.65 + 0.35 * vnoise(uv * vec2(2.5, 1.0)));
			// The grain: a fine bump in the normal from a high-frequency noise slope.
			if (!bottom) {
				float e = 0.02;
				vec2 gp = uv * 9.0;
				float g0 = vnoise(gp);
				float gx = vnoise(gp + vec2(e * 9.0, 0.0)) - g0;
				float gy = vnoise(gp + vec2(0.0, e * 9.0)) - g0;
				vec3 t = normalize(cross(vec3(0.0, 1.0, 0.0), world_n) + vec3(1e-4));
				float fade = 1.0 - smoothstep(0.004, 0.03, fwidth(uv.x));
				nrm_world = normalize(world_n + (t * gx + vec3(0.0, 1.0, 0.0) * gy) * 2.2 * fade);
			}
			rough = 0.9;
		}
	} else if (kind < 1.5) {
		// Standing-seam roof: galvalume or grey-painted pans 0.45 m wide running down the slope,
		// the raised seams lit on one side, rust and dirt running down from the ridge to the eave.
		float s = param * 0.017;
		vec3 base = mix(vec3(0.66, 0.68, 0.69), vec3(0.53, 0.55, 0.55), step(0.55, fract(s * 7.3)));
		float seam = lines(uv.x, 0.45, 0.035);
		float pan = fract(uv.x / 0.45);
		float run = smoothstep(0.55, 0.95, vnoise(vec2(uv.x * 0.9, uv.y * 0.08) + s));
		albedo = base * (0.92 + 0.1 * vnoise(vec2(floor(uv.x / 0.45), uv.y * 0.05))) * (1.0 - 0.18 * run);
		albedo = mix(albedo, vec3(0.42, 0.28, 0.18), 0.35 * run * smoothstep(0.75, 1.0, vnoise(uv * 0.7)));
		albedo *= 1.0 + 0.12 * seam;
		vec3 t = normalize(cross(world_n, vec3(0.0, 0.0, 1.0)) + vec3(1e-4));
		float fade = 1.0 - smoothstep(0.02, 0.12, fwidth(uv.x));
		nrm_world = normalize(world_n + t * (smoothstep(0.85, 1.0, pan) - smoothstep(0.0, 0.15, pan)) * 0.6 * fade);
		metal = 0.65;
		rough = 0.5 + 0.25 * run;
		wet_k = 1.0;
	} else if (kind < 2.5) {
		// An elephant door: two (or three) leaves of painted steel, each a frame round panels of
		// horizontal stiffeners, a seam between leaves, scuffs and rust at the foot where the
		// rollers run, rust streaks from the stiffeners.
		float lw = max(param, 1.0);
		float lu = fract(uv.x / lw) * lw;
		float leaf_edge = 1.0 - step(0.12, lu) * step(lu, lw - 0.12);
		float stiff = lines(uv.y, 1.25, 0.08);
		float panel = lines(lu, lw / 3.0, 0.05);
		float rust = smoothstep(0.62, 0.92, fbm(vec2(uv.x * 1.1, uv.y * 0.35) + paint.rg * 11.0)) * (0.35 + 0.65 * foot);
		albedo = paint * (0.9 + 0.12 * vnoise(uv * vec2(0.5, 4.0)));
		albedo *= 1.0 - 0.2 * max(leaf_edge, max(stiff, panel) * 0.7);
		albedo *= 1.0 - 0.3 * foot * vnoise(uv * vec2(3.0, 1.0));
		albedo = mix(albedo, vec3(0.38, 0.22, 0.13), clamp(rust, 0.0, 0.7));
		albedo *= 1.0 - 0.18 * streaks(uv, h, paint.b * 20.0);
		metal = 0.35;
		rough = mix(0.5, 0.85, rust);
	} else if (kind < 3.5) {
		// Painted steel: scuffed, a little rust run down from the joints and at the foot.
		float rust = smoothstep(0.82, 0.97, vnoise(uv * vec2(1.6, 0.25) + paint.rg * 9.0)) * 0.35 + foot * 0.2;
		albedo = mix(paint * (0.93 + 0.1 * vnoise(uv * vec2(3.0, 0.8))), vec3(0.36, 0.22, 0.14), clamp(rust, 0.0, 0.45));
		rough = mix(0.48, 0.85, rust);
		metal = 0.3;
	} else if (kind < 4.5) {
		// Glass: a dark pane between mullions, the sky mirrored by fresnel (emitted), lit after dark
		// pane by pane.
		float pitch = max(param, 0.4);
		float mull = max(lines(uv.x, pitch, 0.06), band(uv.y, h * 0.66, 0.03));
		float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.0);
		vec3 mirror = disp(sky_tint.rgb) * (0.22 + 0.7 * fres) * (0.85 + 0.3 * vnoise(vec2(uv.x / pitch, 0.5) * 3.0));
		albedo = mix(paint * 0.3, vec3(0.15, 0.15, 0.16), mull);
		emit += mirror * 0.55 * (1.0 - mull) * (1.0 - night_factor * 0.7);
		vec2 pane_id = vec2(floor(uv.x / pitch), floor(world_p.y / 3.6)) + seedv * 9.0;
		float lit = step(0.45, hash12(pane_id)) * lamp_factor;
		// A lit office: brighter toward its ceiling, each its own level and tint, a blind down in some.
		float fy = fract(world_p.y / 3.6);
		float level = 0.55 + 0.6 * hash12(pane_id + 3.7);
		vec3 tint = mix(vec3(1.0, 0.84, 0.62), vec3(0.9, 0.95, 1.0), step(0.7, hash12(pane_id + 8.1)));
		float blind = step(0.75, hash12(pane_id + 5.3)) * step(0.55, fy);
		emit += tint * 0.55 * level * (0.65 + 0.5 * fy) * (1.0 - 0.7 * blind) * lit * (1.0 - mull);
		rough = mix(0.06, 0.5, mull);
		metal = 0.5 * mull;
		spec = 0.7;
		wet_k = 0.0;
	} else if (kind < 5.5) {
		// A lamp: a dark housing, its lens lit after dark - or always (UV2.y 1), the red light
		// over a stage door that says a camera is rolling inside.
		albedo = mix(vec3(0.14, 0.14, 0.15), paint * 0.8, bottom || param > 0.5 ? 1.0 : 0.15);
		float on = param > 0.5 ? (0.55 + 0.45 * lamp_factor) : lamp_factor;
		emit += paint * (bottom || param > 0.5 ? 7.0 : 1.0) * on;
		rough = 0.45;
		metal = 0.2;
	} else if (kind < 6.5) {
		// Brick: the photographed courses at real size, soot run down from the cornice, a darker
		// foot. Windows are geometry here.
		vec3 b = disp(texture(brick_tex, uv / 2.6).rgb);
		albedo = paint * b * 1.2;
		if (top) {
			albedo = vec3(0.5, 0.48, 0.45) * (0.85 + 0.2 * vnoise(uv * 4.0));
		} else {
			float soot = fbm(uv * vec2(0.4, 0.15) + seedv * 9.0) * (0.35 + 0.65 * clamp(uv.y / h, 0.0, 1.0));
			albedo *= 1.0 - 0.28 * soot;
			albedo *= 1.0 - 0.22 * foot;
		}
		rough = 0.9;
	} else if (kind < 7.5) {
		// Stone: brownstone or limestone in ashlar courses (0.55 m) of 1.1 m blocks, every other
		// course offset, each block its own tone, weathered darker in the joints and at the foot.
		vec3 c = disp(texture(concrete_tex, uv / 2.0).rgb);
		float tone = dot(c, vec3(0.333));
		float course = floor(uv.y / 0.55);
		float bx = uv.x / 1.1 + 0.5 * mod(course, 2.0);
		float bt = hash12(vec2(floor(bx), course) + paint.rg * 13.0);
		float joint = max(lines(uv.y, 0.55, 0.012), lines(bx * 1.1, 1.1, 0.012));
		albedo = paint * (0.82 + 0.3 * tone) * (0.93 + 0.12 * bt);
		albedo *= 1.0 - 0.4 * joint * (top ? 0.0 : 1.0);
		albedo *= 1.0 - 0.18 * streaks(uv, h, paint.g * 17.0);
		albedo *= 1.0 - 0.25 * foot;
		rough = 0.88;
	} else if (kind < 8.5) {
		// Plywood and timber: the backs of the false fronts (4 x 8 ft sheets with their joints and
		// the odd stencilled set mark), the struts and the ledgers.
		vec3 w = disp(texture(planks_tex, uv / 1.4).rgb);
		albedo = paint * (0.55 + 0.6 * dot(w, vec3(0.333)));
		if (param > 0.5 && !top && !bottom) {
			float sheet = max(lines(uv.x, 1.22, 0.012), lines(uv.y, 2.44, 0.012));
			albedo *= 1.0 - 0.45 * sheet;
			vec2 sc = vec2(floor(uv.x / 1.22), floor(uv.y / 2.44));
			vec2 sf = fract(uv / vec2(1.22, 2.44));
			albedo *= 0.92 + 0.14 * hash12(sc + paint.rb * 5.0);
			float mark = step(0.82, hash12(sc * 1.7 + 3.0)) * step(0.15, sf.x) * step(sf.x, 0.65) * step(0.4, sf.y) * step(sf.y, 0.5);
			mark *= step(0.5, fract(sf.x * 9.0));
			albedo = mix(albedo, vec3(0.08, 0.08, 0.09), mark * 0.8);
		}
		albedo *= 1.0 - 0.2 * foot;
		rough = 0.9;
	} else if (kind < 9.5) {
		// Canvas: an awning's stripes (UV2.y their width; 0 plain), sun-faded on top, soiled at the
		// valance.
		float sw = param;
		vec3 alt = mix(vec3(0.94, 0.92, 0.86), paint * 0.45, step(0.75, dot(paint, vec3(0.333))));
		float stripe = sw > 0.01 ? step(0.5, fract(uv.x / (sw * 2.0))) : 0.0;
		albedo = mix(paint, alt, stripe) * (0.9 + 0.1 * vnoise(uv * vec2(1.0, 6.0)));
		albedo = mix(albedo, albedo * 1.12 + 0.04, top ? 0.4 : 0.0);
		albedo *= 1.0 - 0.15 * smoothstep(0.3, 0.0, uv.y);
		rough = 0.95;
		spec = 0.3;
	} else if (kind < 10.5) {
		// Sign paint: lettering and painted numbers, matte, chipped back here and there.
		float chip = smoothstep(0.78, 0.84, fbm(world_p.xy * 1.7 + world_p.zz * 1.3));
		albedo = mix(paint * (0.94 + 0.08 * vnoise(world_p.xz * 3.0 + world_p.y)), paint * 0.6 + 0.25, chip * 0.6);
		rough = 0.82;
	} else if (kind < 11.5) {
		vec3 c = disp(texture(concrete_tex, uv / 2.4).rgb);
		albedo = paint * (0.62 + 0.48 * dot(c, vec3(0.333))) * (1.0 - 0.22 * foot);
		rough = 0.88;
	} else if (kind < 12.5) {
		// Gilt letters: brushed brass, warmly lit from behind after dark.
		albedo = paint * (0.85 + 0.2 * vnoise(world_p.xy * 6.0));
		metal = 0.85;
		rough = 0.32;
		emit += vec3(1.0, 0.78, 0.48) * 1.6 * lamp_factor;
	} else if (kind < 13.5) {
		albedo = paint * (0.85 + 0.25 * vnoise(uv * 6.0));
		rough = 0.92;
		spec = 0.3;
	} else if (kind < 14.5) {
		albedo = paint * (0.9 + 0.12 * vnoise(uv * vec2(1.0, 6.0)));
		metal = 0.85;
		rough = 0.25;
	} else if (kind < 15.5) {
		// A production trailer's skin: white gelcoat panels with their seams every 1.5 m, a
		// coloured band (UV2.y picks it) along the side, road grime low down and under the roof.
		vec3 bandc = param < 0.5 ? vec3(0.12, 0.13, 0.15) : (param < 1.5 ? vec3(0.55, 0.12, 0.1) : (param < 2.5 ? vec3(0.1, 0.22, 0.42) : vec3(0.62, 0.62, 0.64)));
		albedo = paint * (0.94 + 0.06 * vnoise(uv * vec2(0.4, 2.0)));
		if (!top && !bottom) {
			float seam = lines(uv.x, 1.5, 0.02);
			albedo *= 1.0 - 0.12 * seam;
			float bnd = step(0.55, uv.y) * step(uv.y, 0.85);
			albedo = mix(albedo, bandc, bnd);
			albedo *= 1.0 - 0.3 * smoothstep(1.2, 0.0, uv.y) * vnoise(uv * vec2(0.8, 3.0));
			albedo *= 1.0 - 0.12 * streaks(uv, h, paint.r * 30.0);
		}
		rough = 0.42;
		spec = 0.6;
	} else {
		// Roofing felt on the bungalows' and booths' flat roofs: dark, gritty.
		albedo = paint * (0.75 + 0.35 * vnoise(uv * 3.0)) * (0.9 + 0.1 * vnoise(uv * 23.0));
		rough = 0.95;
		wet_k = 1.0;
	}
	float wet = clamp(road_wetness, 0.0, 1.0) * wet_k * (top ? 1.0 : 0.4);
	albedo *= 1.0 - 0.28 * wet;
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	EMISSION = emit;
	ROUGHNESS = mix(rough, 0.18, wet * 0.7);
	METALLIC = metal;
	SPECULAR = spec;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm_world, 0.0)).xyz);
}
