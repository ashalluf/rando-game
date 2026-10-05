shader_type spatial;
render_mode cull_back;

// Memorial park stonework (scripts/world/cemetery_build.gd): flat markers, upright headstones,
// obelisks, family monuments, the gate's lanterns and ironwork. One material for all of it, so
// each kind of marker is one MultiMesh draw a chunk.
//
// * Vertex colour alpha says what a face is (k = round(alpha * 16)):
//     0 polished granite   1 sawn / rock-pitched granite   2 marble   3 bronze plaque
//     4 polished granite with engraved lettering   5 flowers (vertex colour)   6 lantern glass
//     7 black iron   8 plain (vertex colour, matte: soil, vase)
// * The instance COLOR is the stone's colour (sRGB) and multiplies the vertex colour (Godot does
//   that for a MultiMesh), so bronze, flowers, glass and iron ignore it and use their own.
// * INSTANCE_CUSTOM: (weathering 0..1, lichen 0..1, seed 0..1, -). A merged mesh (the gate) has none.
// * UV is metres on the face (u across, v up), origin at the face's centre: the lettering and
//   the plaque's border are laid out in it. Everything finer than a pixel fades to its average.
// * Colour space: linear on both renderers (color_space.gdshaderinc); vertex and instance colours
//   arrive raw (sRGB) on both and are decoded here.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

uniform float speckle = 0.55;
uniform float engrave_contrast = 0.55;
uniform vec3 bronze_color = vec3(0.30, 0.17, 0.07);
uniform vec3 patina_color = vec3(0.08, 0.13, 0.09);
uniform vec3 lichen_color = vec3(0.42, 0.40, 0.25);
uniform vec3 lamp_color = vec3(1.0, 0.62, 0.30);
uniform float lamp_energy = 7.0;

varying vec3 v_local;
varying float v_kind;
varying vec4 v_custom;
varying vec3 v_color;

float cs_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float cs_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cs_hash(i), cs_hash(i + vec2(1.0, 0.0)), f.x),
		mix(cs_hash(i + vec2(0.0, 1.0)), cs_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float cs_fbm(vec2 p) {
	return cs_noise(p) * 0.5 + cs_noise(p * 2.03 + 7.1) * 0.3 + cs_noise(p * 4.1 + 3.3) * 0.2;
}

void vertex() {
	v_local = VERTEX;
	v_kind = floor(COLOR.a * 16.0 + 0.5);
	v_custom = INSTANCE_CUSTOM;
	v_color = COLOR.rgb;
}

// Rows of carved letters in a face's (u, v) metres: `rows` lines of `h` tall letters centred on
// v0, the text `w` metres wide at most. Returns coverage 0..1, faded to its mean under a pixel.
float lettering(vec2 uv, float v0, float rows, float h, float w, float seed) {
	float pitch = h * 1.7;
	float row = floor((uv.y - v0) / pitch + rows * 0.5);
	if (row < 0.0 || row >= rows) {
		return 0.0;
	}
	float rv = fract((uv.y - v0) / pitch + rows * 0.5);
	// Each line its own length, centred; the first line (the family name) the widest.
	float len = w * (row < 0.5 ? 1.0 : mix(0.45, 0.85, cs_hash(vec2(row, seed))));
	if (abs(uv.x) > len * 0.5 || rv > h / pitch) {
		return 0.0;
	}
	float cw = h * 0.62;
	vec2 cell = vec2((uv.x + len * 0.5) / cw, rv * pitch / h);
	vec2 id = vec2(floor(cell.x), row + seed * 31.0);
	vec2 f = fract(cell);
	// A gap between words now and then.
	if (cs_hash(id + 0.5) < 0.12) {
		return 0.0;
	}
	// A letter as three of its five strokes (two uprights, three bars), serif-free.
	float s = 0.0;
	float r = cs_hash(id);
	float t = 0.16;
	if (r > 0.2) s = max(s, step(abs(f.x - 0.18), t * 0.5));
	if (fract(r * 7.0) > 0.35) s = max(s, step(abs(f.x - 0.78), t * 0.5));
	if (fract(r * 13.0) > 0.4) s = max(s, step(abs(f.y - 0.9), t * 0.5) * step(0.1, f.x) * step(f.x, 0.86));
	if (fract(r * 29.0) > 0.5) s = max(s, step(abs(f.y - 0.5), t * 0.5) * step(0.1, f.x) * step(f.x, 0.86));
	if (fract(r * 53.0) > 0.45) s = max(s, step(abs(f.y - 0.1), t * 0.5) * step(0.1, f.x) * step(f.x, 0.86));
	s *= step(f.x, 0.88);
	return s;
}

void fragment() {
	int k = int(v_kind);
	vec3 inst = cs_srgb_to_linear(clamp(v_color, 0.0, 1.0));
	vec2 uv = UV;
	float px = max(length(fwidth(uv)), 1e-4);
	float weather = v_custom.r;
	float lichen = v_custom.g;
	float seed = v_custom.b;
	// Grain: granite's crystals, at ~4 mm, faded to their mean when a grain is under a pixel.
	vec2 g = v_local.xz * 230.0 + v_local.y * 170.0;
	float grain_fade = 1.0 - smoothstep(0.004, 0.02, px);
	float grain = mix(0.5, cs_noise(g) * 0.6 + cs_noise(g * 2.7) * 0.4, grain_fade);
	float flecks = step(0.86, cs_noise(g * 1.3 + 11.0)) * grain_fade;
	vec3 alb = vec3(0.5);
	float rough = 0.5;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	if (k == 0 || k == 1 || k == 4) {
		vec3 base = inst;
		alb = base * mix(1.0 - speckle * 0.5, 1.0 + speckle * 0.35, grain);
		alb = mix(alb, vec3(0.02), flecks * 0.5 * speckle);
		alb = mix(alb, base * 1.6 + 0.04, step(0.93, cs_noise(g * 0.8 + 5.0)) * grain_fade * 0.5);
		rough = k == 1 ? 0.78 : 0.18;
		if (k == 1) {
			// Rock-pitched or sawn: paler (the polish is what darkens granite) and pitted.
			alb = alb * 1.35 + 0.02;
			alb *= 0.85 + 0.3 * cs_fbm(v_local.xz * 9.0 + v_local.y * 7.0);
		}
		if (k == 4) {
			float cut = lettering(uv, -0.05, 4.0, 0.05, 0.62, seed);
			float mean = 0.18;
			float c = mix(mean, cut, 1.0 - smoothstep(0.004, 0.012, px));
			alb = mix(alb, base * 1.9 + 0.08, c * engrave_contrast);
			rough = mix(rough, 0.7, c);
		}
	} else if (k == 2) {
		// Marble: white with grey veins, sugared by weather.
		float vein = abs(sin(v_local.y * 9.0 + cs_fbm(v_local.xz * 3.0 + v_local.y * 2.0) * 7.0));
		vein = smoothstep(0.0, 0.08, vein);
		alb = inst * mix(0.62, 1.0, vein) * (0.92 + 0.12 * grain);
		rough = 0.45;
		float cut = lettering(uv, 0.0, 3.0, 0.045, 0.45, seed);
		float c = mix(0.15, cut, 1.0 - smoothstep(0.004, 0.012, px));
		alb *= 1.0 - c * 0.45;
	} else if (k == 3) {
		// A bronze plaque: patina in the field, the border and raised letters rubbed bright.
		vec2 half_size = vec2(0.22, 0.12);
		vec2 d = abs(uv) - half_size;
		float border = step(-0.018, max(d.x, d.y));
		float txt = lettering(vec2(uv.x, uv.y), 0.0, 3.0, 0.03, 0.34, seed);
		float raised = max(border, mix(0.2, txt, 1.0 - smoothstep(0.003, 0.009, px)));
		float pat = cs_fbm(uv * 40.0 + seed * 9.0);
		vec3 field = mix(bronze_color * 0.45, patina_color, smoothstep(0.3, 0.8, pat) * 0.8);
		vec3 bright = bronze_color * 1.7 + vec3(0.06, 0.03, 0.0);
		alb = mix(field, bright, raised);
		metal = mix(0.35, 0.9, raised);
		rough = mix(0.62, 0.32, raised);
	} else if (k == 5) {
		alb = inst * 0.0 + cs_srgb_to_linear(v_color);
		alb *= 0.8 + 0.4 * cs_noise(v_local.xz * 60.0);
		rough = 0.7;
	} else if (k == 6) {
		alb = vec3(0.6, 0.55, 0.45);
		rough = 0.15;
		emit = lamp_color * lamp_energy * lamp_factor;
	} else if (k == 7) {
		alb = vec3(0.025);
		rough = 0.45;
		metal = 0.6;
	} else {
		alb = inst;
		rough = 0.85;
	}
	// Weather on stone: soot and rain streaks down from the top, lichen low and on the tops.
	if (k <= 2 || k == 4) {
		float streak = cs_noise(vec2(v_local.x * 22.0 + v_local.z * 19.0, v_local.y * 1.4)) * weather;
		alb *= 1.0 - streak * 0.35;
		float lich = smoothstep(0.55, 0.85, cs_fbm(v_local.xz * 6.0 + v_local.y * 5.0 + seed * 17.0) + lichen * 0.35 - 0.25)
			* lichen;
		alb = mix(alb, lichen_color * (0.8 + 0.3 * grain), lich * 0.85);
		rough = mix(rough, 0.9, lich + weather * 0.3);
	}
	// Rain on polished stone.
	rough = mix(rough, rough * 0.4, road_wetness);
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	EMISSION = cs_out(emit);
}
