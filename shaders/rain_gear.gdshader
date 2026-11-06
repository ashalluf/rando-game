shader_type spatial;
// The crowd's rain gear (RainGear): umbrellas and hoods. What a vertex is rides in COLOR.a
// (RainGear.P_*: (part + 0.5) / 8): canopy fabric, steel ribs and shaft, the handle, the tips and
// ferrule, the hood's shell, its hem, a strap. UV is the fabric's own coordinates (the canopy:
// x in gores round it, y out along a rib 0..1; the hood: metres).
//
// The canopy is a polyester pongee: a fine plain weave, a satin sheen that goes glossy when it
// is wet, beads of rain standing on it (`road_wetness` / `rain_intensity`, Weather's globals),
// the seams down each rib, a hem band, and light coming THROUGH it from above (BACKLIGHT), which
// is what a lit umbrella looks like from under it. The inside (the back face) is a shade darker.
// The hood is a nylon shell with a softer sheen and its rolled hem.
//
// Colours are linear numbers in plain vec3 uniforms (set from script as Vector3, so neither
// renderer decodes them) and every result goes out through cs_out() (color_space.gdshaderinc).
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://shaders/color_space.gdshaderinc"

global uniform float road_wetness;
global uniform float rain_intensity;

uniform vec3 main_color = vec3(0.012, 0.012, 0.014);
uniform vec3 second_color = vec3(0.012, 0.012, 0.014);
// 0 plain, 1 alternate gores in second_color, 2 a band round the edge in second_color.
uniform int pattern = 0;
// The handle: 1 a varnished wood crook, 0 black plastic / rubber.
uniform float handle_wood = 0.0;
uniform float weave_pitch = 0.0018;
uniform float dry_rough = 0.42;
uniform float wet_rough = 0.16;
uniform float bead_density = 900.0;
uniform float translucency = 0.35;

varying float v_part;
varying vec3 v_obj;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_part = floor(COLOR.a * 8.0);
	v_obj = VERTEX;
}

void fragment() {
	float part = v_part;
	float wet = clamp(max(road_wetness, rain_intensity), 0.0, 1.0);
	vec3 col = main_color;
	float rough = dry_rough;
	float metal = 0.0;
	float spec = 0.5;
	vec3 back = vec3(0.0);
	if (part < 0.5 || part > 3.5 && part < 5.5) {
		// Fabric.
		bool hood = part > 3.5;
		if (!hood) {
			float g = UV.x;
			float s = UV.y;
			if (pattern == 1 && mod(floor(g), 2.0) > 0.5) {
				col = second_color;
			}
			if (pattern == 2 && s > 0.86) {
				col = second_color;
			}
			// The seam down each rib: a stitched fold, a hair darker.
			float seam = abs(fract(g) - 0.5) * 2.0;
			col *= mix(1.0, 0.8, smoothstep(0.93, 0.995, seam));
			// The hem: a turned band 1.5 cm wide.
			col *= mix(1.0, 0.86, smoothstep(0.965, 0.975, s));
			// A plain weave, faded to its average under a pixel.
			vec2 w = vec2(g * 0.42, s * 0.55) / weave_pitch;
			float px = max(fwidth(w.x), fwidth(w.y));
			float weave = sin(w.x * 6.2832) * sin(w.y * 6.2832);
			col *= 1.0 + 0.06 * weave * (1.0 - smoothstep(0.3, 0.8, px));
			// Light through the cloth: the sun and the sky above lighting the underside.
			back = col * translucency * 2.5 + vec3(0.01);
		} else {
			// The hood's shell: nylon with a soft sheen, a little mottling where the cloth creases.
			float crease = sin(v_obj.y * 160.0 + sin(v_obj.x * 90.0) * 2.0) * 0.5 + 0.5;
			col *= 0.92 + 0.12 * crease;
			if (part > 4.5) {
				col *= 0.85;
			}
			rough = 0.55;
		}
		if (!FRONT_FACING) {
			// The inside: the lining or the canopy's underside, a shade darker and duller.
			col *= 0.72;
			rough = min(rough + 0.15, 0.9);
		}
		// Wet: the cloth darkens and its sheen goes glossy, with beads standing on it.
		col *= mix(1.0, 0.82, wet);
		rough = mix(rough, wet_rough, wet);
		vec2 bp = (hood ? v_obj.xz + v_obj.y : v_obj.xz) * sqrt(bead_density);
		vec2 cell = floor(bp);
		vec2 fr = fract(bp) - 0.5;
		float h = hash12(cell);
		vec2 o = vec2(hash12(cell + 7.1), hash12(cell + 3.3)) - 0.5;
		float d = length(fr - o * 0.5);
		float bead = (1.0 - smoothstep(0.08, 0.16 * (0.6 + h), d)) * step(0.45, h) * wet;
		float bpx = fwidth(bp.x);
		bead *= 1.0 - smoothstep(0.4, 1.2, bpx);
		rough = mix(rough, 0.05, bead);
		col *= 1.0 - 0.3 * bead;
	} else if (part < 1.5) {
		// Steel ribs, stretchers and shaft: black-coated, worn bright on the edges.
		col = vec3(0.025, 0.025, 0.027);
		metal = 0.6;
		rough = 0.38;
	} else if (part < 2.5) {
		// The handle: varnished wood or black plastic.
		col = mix(vec3(0.02, 0.02, 0.022), vec3(0.16, 0.07, 0.025), handle_wood);
		rough = mix(0.5, 0.28, handle_wood);
	} else if (part < 3.5) {
		// Tips and the ferrule: nickel or black plastic caps.
		col = vec3(0.35, 0.34, 0.32);
		metal = 0.9;
		rough = 0.3;
	} else {
		// A strap.
		col = main_color * 0.9;
		rough = 0.7;
	}
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	BACKLIGHT = cs_out(back);
}
