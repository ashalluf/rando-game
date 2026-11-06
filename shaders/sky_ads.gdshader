shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// The aerial advertising (SkyAds, scripts/world/sky_ads.gd): the FIZZLY blimp, the banner tow
// planes and their banners, all code-built by SkyAdMesh in ONE material. What a vertex is rides
// in COLOR.a as kind / 16 (SkyAdMesh.K_*), its paint in COLOR.rgb as sRGB (vertex colours arrive
// raw on both renderers, so they are decoded here and the shader works in linear; cs_out() hands
// the result over: shaders/color_space.gdshaderinc).
//   K_PAINT    gloss paint (fuselage, struts, wheels' hubs): the plane's skin
//   K_ENVELOPE the blimp's fabric: livery worked out from UV (u metres from the nose, v the
//              angle round the hull / TAU, 0 at the top, 0.25 the +X side): white over a hot
//              orange swoosh that rises toward the tail, bubbles in it, gore seams, nose battens
//   K_LETTER   lettering (paint in COLOR.rgb), a satin vinyl
//   K_LED      the blimp's night sign: UV = panel 0..1 (u along the reading direction), text
//              from `led_text` (one text pixel = a 3 x 3 cluster of LEDs), scrolling
//   K_GLASS    windows: dark, glossy
//   K_DARK     rubber, the duct liners, the cockpit inside
//   K_METAL    satin metal (props' hubs, struts, the lead pole)
//   K_PROP     a spinning prop: a disc dithered to the blades' coverage, faint rings
//   K_CLOTH    the banner's ground (paint in COLOR.rgb); UV2.x = metres from the lead pole
//   K_ROPE     the tow rope (a braided line)
//   K_LAMP     a lamp lens: lit by `lamp_factor`
// The banner (K_CLOTH, K_LETTER on a banner, the lead pole) flutters in the vertex stage when
// UV2.y is 1: a travelling wave across the cloth that grows toward the tail.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

const float K_PAINT = 0.0;
const float K_ENVELOPE = 1.0;
const float K_LETTER = 2.0;
const float K_LED = 3.0;
const float K_GLASS = 4.0;
const float K_DARK = 5.0;
const float K_METAL = 6.0;
const float K_PROP = 7.0;
const float K_CLOTH = 8.0;
const float K_ROPE = 9.0;
const float K_LAMP = 10.0;

// The night sign's text, one text pixel a texel (SkyAds.led_texture()), and how many of them
// the panel shows across its width and height.
uniform sampler2D led_text : filter_nearest, repeat_enable;
uniform vec2 led_size = vec2(64.0, 9.0);
uniform float led_strip = 256.0;
// Text pixels a second the text scrolls by.
uniform float led_scroll = 6.0;
// The sign's brightness by day (it is a night sign: by day the LEDs barely read).
uniform float led_day = 0.06;
uniform float led_energy = 4.5;
// The banner's flutter: amplitude at the tail (m), wavelength (m), waves a second, its length.
uniform float flutter_amp = 0.55;
uniform float flutter_wave = 8.5;
uniform float flutter_rate = 1.7;
uniform float banner_length = 30.0;
// Seconds of shader TIME a prop turns once in (only its shimmer; the disc stands still).
uniform float prop_spin = 0.04;
// 1 while the craft is a wreck: everything charred.
uniform float charred = 0.0;

varying flat float v_kind;
varying vec2 v_uv;
varying vec2 v_uv2;
varying vec3 v_col;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_kind = floor(COLOR.a * 16.0 + 0.5);
	v_uv = UV;
	v_uv2 = UV2;
	v_col = cs_srgb_to_linear(COLOR.rgb);
	if (UV2.y > 0.5) {
		// The banner lies in its local YZ plane, trailing along +Z from the lead pole at z 0.
		float s = max(UV2.x, 0.0);
		float grow = pow(clamp(s / max(banner_length, 1.0), 0.0, 1.0), 1.3);
		float ph = TAU * (s / flutter_wave - TIME * flutter_rate);
		float amp = flutter_amp * (0.12 + grow);
		VERTEX.x += amp * sin(ph);
		// A little heave up and down, out of step with the wave.
		VERTEX.y += amp * 0.18 * sin(ph * 0.5 + 1.3) * grow;
		float slope = amp * cos(ph) * TAU / flutter_wave;
		NORMAL = normalize(NORMAL + vec3(0.0, 0.0, -slope * sign(NORMAL.x)));
	}
}

vec3 envelope_livery(vec2 uv, out float rough, out float metal) {
	float u = uv.x;
	float a = uv.y * TAU;
	// Height on the hull, -1 the keel .. 1 the top.
	float h = cos(a);
	vec3 white = vec3(0.80, 0.80, 0.78);
	vec3 orange = cs_srgb_to_linear(vec3(0.95, 0.40, 0.10));
	vec3 red = cs_srgb_to_linear(vec3(0.80, 0.12, 0.08));
	// The swoosh: its top edge runs low at the nose and climbs toward the tail, waving.
	float t = clamp(u / 60.0, 0.0, 1.0);
	float edge = -0.62 + 0.75 * smoothstep(0.15, 0.95, t) + 0.05 * sin(u * 0.21);
	float fw = fwidth(h) * 1.5 + 0.002;
	float in_band = 1.0 - smoothstep(edge - fw, edge + fw, h);
	float pin = smoothstep(edge + 0.035 - fw, edge + 0.035, h) * (1.0 - smoothstep(edge + 0.06, edge + 0.06 + fw, h));
	vec3 c = mix(white, orange, in_band);
	c = mix(c, red, pin);
	// Bubbles in the orange: rings on a jittered grid in metres of hull.
	vec2 m = vec2(u, a * 7.5);
	vec2 cell = floor(m / 1.7);
	vec2 f = m / 1.7 - cell;
	vec2 o = vec2(hash12(cell), hash12(cell + 17.3)) * 0.6 + 0.2;
	float r = 0.08 + 0.22 * pow(hash12(cell + 5.1), 3.0);
	float d = length(f - o);
	float ring = smoothstep(r + 0.06, r + 0.02, d) * smoothstep(r - 0.06, r - 0.02, d);
	float bubbles = ring * step(0.35, hash12(cell + 9.7)) * in_band * smoothstep(edge - 0.02, edge - 0.25, h);
	c = mix(c, vec3(0.93, 0.80, 0.62), bubbles * 0.85);
	// Gore seams (24 round the hull) and panel seams every 3 m, faint, faded under a pixel.
	float gore = abs(fract(uv.y * 24.0) - 0.5) * 2.0;
	float gw = fwidth(uv.y * 24.0) * 2.0;
	float seam = (1.0 - smoothstep(0.0, gw + 0.02, 1.0 - gore)) * clamp(1.0 - gw * 4.0, 0.0, 1.0);
	c *= 1.0 - 0.10 * seam;
	// The nose cone: a darker cap and its battens.
	float bat = smoothstep(0.92, 0.98, abs(cos(a * 6.0))) * (1.0 - smoothstep(3.0, 5.2, u));
	c = mix(c, c * 0.7, bat * clamp(1.0 - fwidth(a * 6.0) * 3.0, 0.0, 1.0));
	c = mix(c, vec3(0.20, 0.20, 0.21), 1.0 - smoothstep(0.9, 1.3, u));
	// Grime under the keel and streaks from the gondola back.
	c *= 1.0 - 0.12 * smoothstep(-0.6, -1.0, h);
	rough = mix(0.42, 0.55, in_band);
	metal = 0.0;
	return c;
}

void fragment() {
	float k = v_kind;
	vec3 albedo = v_col;
	float rough = 0.45;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	if (k == K_ENVELOPE) {
		albedo = envelope_livery(v_uv, rough, metal);
	} else if (k == K_LETTER) {
		rough = 0.38;
	} else if (k == K_LED) {
		// Text pixels across the panel, each a 3 x 3 cluster of round LEDs.
		vec2 px = vec2(v_uv.x * led_size.x, (1.0 - v_uv.y) * led_size.y);
		float sx = floor(px.x + TIME * led_scroll);
		vec4 t = texelFetch(led_text, ivec2(int(mod(sx, led_strip)), clamp(int(floor(px.y)), 0, int(led_size.y) - 1)), 0);
		vec2 dot_uv = fract(px * 3.0) - 0.5;
		float px_size = max(fwidth(px.x * 3.0), fwidth(px.y * 3.0));
		float dot_shape = 1.0 - smoothstep(0.30, 0.30 + px_size, length(dot_uv));
		// Under a pixel a dot is its coverage (about 0.28 of a cell).
		dot_shape = mix(dot_shape, 0.28, smoothstep(0.4, 1.2, px_size));
		vec3 led = cs_srgb_to_linear(t.rgb) * t.a;
		float on = mix(led_day, 1.0, lamp_factor);
		albedo = vec3(0.035);
		rough = 0.25;
		emit = led * dot_shape * led_energy * on;
		// A faint grid of the dark LEDs.
		albedo += vec3(0.02) * dot_shape;
	} else if (k == K_GLASS) {
		albedo = vec3(0.02, 0.025, 0.03);
		rough = 0.06;
		spec = 0.9;
		// The cabin lit after dark.
		emit = vec3(0.5, 0.42, 0.3) * 0.08 * lamp_factor;
	} else if (k == K_DARK) {
		rough = 0.85;
		spec = 0.2;
	} else if (k == K_METAL) {
		metal = 0.8;
		rough = 0.35;
	} else if (k == K_PROP) {
		// A blurred prop: two blades sweep a disc; the eye sees about a sixth of it, with a
		// brighter tip ring.
		float r = length(v_uv - 0.5) * 2.0;
		if (r > 1.0) {
			discard;
		}
		float cover = 0.16 + 0.22 * smoothstep(0.85, 0.98, r) * (1.0 - smoothstep(0.98, 1.0, r));
		float n = hash12(floor(FRAGCOORD.xy) + vec2(fract(TIME / prop_spin) * 37.0, 0.0));
		if (n > cover) {
			discard;
		}
		albedo = mix(vec3(0.05), vec3(0.6, 0.55, 0.15), smoothstep(0.9, 0.97, r));
	} else if (k == K_CLOTH) {
		rough = 0.8;
		spec = 0.3;
		// The weave and the hems along the top and bottom.
		float hem = smoothstep(0.06, 0.0, min(v_uv.y, 1.0 - v_uv.y));
		albedo *= 1.0 - 0.15 * hem;
		// Dirt toward the tail, where it drags through the air hardest.
		albedo *= 1.0 - 0.08 * smoothstep(0.4, 1.0, v_uv2.x / max(banner_length, 1.0));
	} else if (k == K_ROPE) {
		rough = 0.9;
		albedo *= 0.85 + 0.15 * sin(v_uv.x * 40.0);
	} else if (k == K_LAMP) {
		rough = 0.1;
		emit = albedo * 6.0 * lamp_factor;
	}
	if (charred > 0.5) {
		albedo = vec3(0.035, 0.032, 0.03);
		emit = vec3(0.0);
		rough = 0.95;
		metal = 0.0;
	}
	ALBEDO = cs_out(albedo);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = cs_out(emit);
}
