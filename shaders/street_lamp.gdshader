shader_type spatial;

// The city's street lights (tools/make_street_lamps.py -> assets/models/street_lamps.glb, placed by
// StreetLamps / CityChunk._add_lamp). ONE material for every lamp type: what a face is rides in
// UV2.x = (part + 0.5) / 8 - 0 galvanised steel, 1 painted cast iron (the instance colour is the
// paint), 2 die-cast aluminium, 3 spun concrete, 4 drop-glass lens, 5 diffuser (globes, lantern
// glass, prismatic refractor), 6 dark (gaskets, bolts, photocell), 7 LED array - and UV2.y is where
// a lit face sits in its diffuser (0 bottom .. 1 top). UV is metres.
//
// Instance data (MultiMesh, CityChunk._add_lamp): COLOR the paint (sRGB, raw on both renderers);
// INSTANCE_CUSTOM.r 1 for an LED lamp, 0 sodium (NightCity.lamp_led(), the same roll the far
// streets' glow and the lamp's OmniLight use), .g a per-lamp 0..1 for wear and age.
//
// Works in linear on both renderers (color_space.gdshaderinc): every colour constant below is
// linear. Lit parts follow lamp_factor (DayNight: the lamps come on in a storm too).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

// The lamp's own light, emitted by the lens / globes / LEDs at lamp_factor 1 (linear, HDR).
uniform vec3 sodium_glow = vec3(1.0, 0.34, 0.055);
uniform vec3 led_glow = vec3(0.86, 0.92, 1.0);
uniform float lens_energy = 5.0;
uniform float diffuser_energy = 1.9;
uniform float led_energy = 6.0;
// Daylight albedos (linear).
uniform vec3 galv_color = vec3(0.42, 0.43, 0.43);
uniform vec3 alu_color = vec3(0.50, 0.51, 0.51);
uniform vec3 concrete_color = vec3(0.33, 0.315, 0.29);
uniform vec3 diffuser_color = vec3(0.62, 0.61, 0.58);
// The daylight a globe passes through itself (an emitted share of its albedo).
uniform float diffuser_day = 0.22;
// How much wear and grime there is at most (INSTANCE_CUSTOM.g scales it per lamp).
uniform float wear = 1.0;

varying flat int part;
varying float glow_y;
varying vec3 obj;
varying vec3 paint;
varying flat float is_led;
varying float age;

float h31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1) * 0.3 + vnoise(p * 4.3) * 0.15;
}

// Galvanising's spangle: a cell per few centimetres, each crystal its own shade.
float spangle(vec3 p) {
	vec3 c = floor(p * 22.0);
	return h31(c) * 0.6 + h31(floor(p * 9.0)) * 0.4;
}

void vertex() {
	part = int(clamp(UV2.x * 8.0, 0.0, 7.999));
	glow_y = UV2.y;
	obj = VERTEX;
	paint = cs_srgb_to_linear(COLOR.rgb);
	is_led = INSTANCE_CUSTOM.r;
	age = INSTANCE_CUSTOM.g;
}

void fragment() {
	vec3 seed = obj + vec3(age * 37.0, 0.0, age * 11.0);
	float big = fbm(seed * 1.6);
	float fine = vnoise(seed * 38.0);
	float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);
	// Grime: low on the post (splash, dogs, the street) and in patches.
	float foot = 1.0 - smoothstep(0.05, 0.9, obj.y);
	float grime = clamp(foot * 0.7 + smoothstep(0.55, 0.85, big) * 0.35, 0.0, 1.0) * wear * (0.45 + 0.55 * age);
	vec3 lamp = is_led > 0.5 ? led_glow : sodium_glow;
	float on = clamp(lamp_factor, 0.0, 1.0);

	vec3 alb = galv_color;
	float rough = 0.45;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float spec = 0.5;

	if (part == 0) {
		// Hot-dip galvanised: spangle, dull white zinc oxide in patches, a darker weathered foot.
		float sp = spangle(seed);
		float oxide = smoothstep(0.5, 0.8, fbm(seed * 3.3 + 7.0)) * (0.4 + 0.6 * age);
		alb = galv_color * (0.86 + 0.24 * sp);
		alb = mix(alb, vec3(0.56, 0.56, 0.54), oxide * 0.55);
		alb = mix(alb, vec3(0.13, 0.12, 0.11), grime * 0.75);
		metal = mix(0.85, 0.35, max(oxide, grime));
		rough = mix(0.32 + 0.14 * sp, 0.7, max(oxide * 0.8, grime));
	} else if (part == 1) {
		// Painted cast iron: a semi-gloss coat, dust settled on what faces up, chips and rust
		// showing through low on the post.
		alb = paint * (0.92 + 0.12 * fine);
		float chip = smoothstep(0.78, 0.86, fbm(seed * 7.0)) * (0.35 + 0.65 * foot) * wear * age;
		alb = mix(alb, vec3(0.07, 0.035, 0.02), chip);
		alb = mix(alb, vec3(0.22, 0.2, 0.17), up * 0.22 * (0.4 + big));
		alb = mix(alb, vec3(0.05, 0.045, 0.04), grime * 0.6);
		rough = mix(0.36 + 0.1 * big, 0.75, max(chip, grime * 0.8));
		metal = 0.0;
	} else if (part == 2) {
		// Die-cast aluminium housing, painted silver-grey, a little dirt on top.
		alb = alu_color * (0.95 + 0.08 * fine);
		alb = mix(alb, vec3(0.16, 0.15, 0.13), up * smoothstep(0.35, 0.8, big) * 0.5 * wear);
		metal = 0.55;
		rough = 0.38 + 0.12 * big;
	} else if (part == 3) {
		// Spun concrete with exposed aggregate: pale cement, darker and lighter stones.
		float agg = vnoise(seed * 90.0);
		float stones = smoothstep(0.62, 0.7, agg);
		alb = concrete_color * (0.9 + 0.2 * big);
		alb = mix(alb, mix(vec3(0.16, 0.15, 0.14), vec3(0.5, 0.48, 0.44), h31(floor(seed * 90.0))), stones * 0.7);
		alb = mix(alb, vec3(0.1, 0.095, 0.085), grime * 0.7);
		rough = 0.88;
	} else if (part == 4) {
		// The drop-glass refractor: clear glass with prism ribs by day, the lamp at night.
		float rib = 0.5 + 0.5 * sin(UV.x * 220.0);
		alb = vec3(0.06, 0.06, 0.065) + vec3(0.04) * rib;
		rough = 0.06 + 0.06 * rib;
		spec = 0.6;
		float core = 0.55 + 0.45 * (1.0 - glow_y);
		emit = lamp * lens_energy * on * core * (0.8 + 0.2 * rib);
	} else if (part == 5) {
		// Frosted acrylic / seeded glass / prismatic: milky by day, glowing round its hot spot
		// at night (the lamp sits low in it).
		float hot = exp(-pow((glow_y - 0.38) * 2.6, 2.0));
		alb = diffuser_color * (0.92 + 0.08 * fine);
		alb = mix(alb, vec3(0.3, 0.29, 0.26), smoothstep(0.7, 1.0, glow_y) * 0.4 * wear);
		rough = 0.42;
		emit = lamp * diffuser_energy * on * (0.35 + 0.65 * hot);
		// Opal acrylic carries daylight through itself: it never goes as dark as paint does on
		// its shaded side.
		emit += alb * diffuser_day * (1.0 - on);
		// Lit from inside, the body takes less of the street's light.
		alb *= 1.0 - 0.7 * on;
	} else if (part == 6) {
		alb = vec3(0.028, 0.028, 0.03);
		rough = 0.55;
	} else {
		// The LED array: rows of lenses on a dark board. UV is metres in the panel's plane.
		vec2 g = fract(UV * vec2(28.0, 28.0)) - 0.5;
		float dot_ = 1.0 - smoothstep(0.18, 0.3, length(g));
		float px = fwidth(UV.x) * 28.0;
		dot_ = mix(dot_, 0.25, clamp(px * 1.5 - 0.5, 0.0, 1.0));
		alb = mix(vec3(0.03), vec3(0.22), dot_);
		rough = 0.15;
		emit = lamp * led_energy * on * (0.2 + 0.8 * dot_);
	}
	// Rain: the metal and paint go glossy and a touch darker.
	if (part <= 3) {
		float w = clamp(road_wetness, 0.0, 1.0) * (0.4 + 0.6 * up);
		alb *= 1.0 - 0.25 * w;
		rough = mix(rough, 0.12, w * 0.8);
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = cs_out(emit);
}
