shader_type spatial;
render_mode cull_back;

// The hills' scatter clumps (HillScatter, hill-planting-2): three lumpy domes a few metres
// across on the painted chaparral stands, so from the air and along a ridge a stand reads as a
// mass of lit shrub tops and shaded sides rather than paint. The mesh is a handful of
// triangles; everything leafy is drawn here from world-space noise: leaf clumps, dark pockets
// between them, a few dead twigs, the base in shade (vertex colour R). Detail that shrinks under
// a pixel fades to its average, so a clump far off is its mean colour, not sparkle.
//
// Colours are LINEAR plain uniforms (the hill splat's way; color_space.gdshaderinc hands the
// albedo to the renderer in its own space), a little lighter than the painted stand
// (hill_splat.gdshaderinc chaparral_color 0.046, 0.058, 0.040 holds the shade between bushes),
// close to the code-built shrub's leaves (HillShrub.LEAF).
#include "res://shaders/color_space.gdshaderinc"

uniform vec3 leaf_dark = vec3(0.026, 0.036, 0.021);
uniform vec3 leaf_light = vec3(0.080, 0.094, 0.054);
uniform vec3 dead_color = vec3(0.150, 0.128, 0.090);
// Leaf clumps per metre, and how much they tilt the normal.
uniform float leaf_scale = 2.2;
uniform float leaf_relief = 0.55;
// Camera distances (metres) between which a clump is dithered in: 0, 0 never fades (the LOD
// chunks' clumps). HillScatter.FULL_FADE on the FULL chunks' material.
uniform vec2 near_fade = vec2(0.0, 0.0);
uniform float roughness = 0.86;
uniform float specular = 0.24;
global uniform float wind_factor;

varying vec3 wpos;
varying float base_light;
varying vec2 tone;

void vertex() {
	base_light = COLOR.r;
	tone = INSTANCE_CUSTOM.rg;
	// A stiff shrub's wind: the top a few centimetres, phased by where it stands.
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = sin(TIME * 1.3 + o.x * 0.21 + o.z * 0.17) * 0.04 * (0.4 + wind_factor);
	VERTEX.x += sway * max(VERTEX.y, 0.0) * 0.5;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vn3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(h3(i), h3(i + vec3(1.0, 0.0, 0.0)), f.x), mix(h3(i + vec3(0.0, 1.0, 0.0)), h3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y);
	float b = mix(mix(h3(i + vec3(0.0, 0.0, 1.0)), h3(i + vec3(1.0, 0.0, 1.0)), f.x), mix(h3(i + vec3(0.0, 1.0, 1.0)), h3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y);
	return mix(a, b, f.z);
}

void fragment() {
	float dist = length(VERTEX);
	if (near_fade.y > 0.0) {
		float a = smoothstep(near_fade.x, near_fade.y, dist);
		// Interleaved gradient noise: TAA resolves it into a fade.
		float d = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (a <= d) {
			discard;
		}
	}
	vec3 p = wpos * leaf_scale;
	float fw = length(fwidth(p));
	// Leaf clumps resolved (a clump over ~2 pixels), the finer octave sooner.
	float amp = 1.0 - smoothstep(0.35, 1.2, fw);
	float amp2 = 1.0 - smoothstep(0.18, 0.6, fw);
	float n1 = vn3(p);
	float n2 = vn3(p * 2.7 + vec3(7.1, 3.3, 5.9));
	float leaf = mix(0.5, n1, amp) * 0.7 + mix(0.5, n2, amp2) * 0.3;
	// Lit tops and shaded sides come from the renderer; the clumps and pockets from the noise.
	float lit = clamp(0.25 + tone.x * 0.45 + (leaf - 0.5) * 1.3, 0.0, 1.0);
	vec3 c = mix(leaf_dark, leaf_light, lit);
	// A few dead twigs on some clumps (chamise goes grey-brown in patches).
	float dead = smoothstep(0.72, 0.86, vn3(p * 0.55 + vec3(19.0, 2.0, 11.0))) * step(0.55, tone.y) * mix(0.35, 1.0, amp);
	c = mix(c, dead_color, dead * 0.7);
	// The pockets between the leaf clumps are dark; under a pixel their share is a mean.
	c *= mix(1.0, 0.6 + 0.4 * smoothstep(0.28, 0.62, leaf), amp) * mix(1.0, 0.9, 1.0 - amp);
	// The base in its own shade.
	c *= mix(0.5, 1.0, base_light);
	ALBEDO = cs_out(c);
	ROUGHNESS = roughness;
	SPECULAR = specular;
	// The leaf clumps tilt the normal, so a dome lights as a heap of clumps.
	float e = 0.35;
	vec3 gw = vec3(vn3(p + vec3(e, 0.0, 0.0)) - n1, vn3(p + vec3(0.0, e, 0.0)) - n1, vn3(p + vec3(0.0, 0.0, e)) - n1) / e;
	NORMAL = normalize(NORMAL - mat3(VIEW_MATRIX) * gw * leaf_relief * amp);
	// A little light through the outer leaves.
	BACKLIGHT = cs_out(c * 0.35);
}
