shader_type spatial;
render_mode cull_disabled;

// A mattress lying on the freeway (FreewayIncidentKit.mattress_mesh()): COLOR.rgb the cover
// (sRGB), COLOR.a the part - 1 the quilted top, 0.5 the border panel, 0 the underside. UV in
// metres. The top's quilting is a diamond grid of stitch lines pulling the cover down, a tuft at
// each crossing; the border has its piping and a vent stripe; road grime and a tyre's print
// darken it. The normal is built as a slope in world-ish metres (no tangents needed).

#include "res://shaders/color_space.gdshaderinc"

varying vec4 col;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	col = COLOR;
}

void fragment() {
	vec3 base = cs_srgb_to_linear(col.rgb);
	float part = col.a;
	vec2 uv = UV;
	float shade = 1.0;
	vec2 slope = vec2(0.0);
	if (part > 0.75) {
		// Diamond quilt: two families of stitch lines 0.16 m apart.
		vec2 q = vec2(uv.x + uv.y, uv.x - uv.y) / 0.16;
		vec2 fq = fract(q) - 0.5;
		float lx = abs(fq.x);
		float ly = abs(fq.y);
		float dip = smoothstep(0.08, 0.0, 0.5 - lx) + smoothstep(0.08, 0.0, 0.5 - ly);
		shade *= 1.0 - 0.12 * clamp(dip, 0.0, 1.0);
		// Puffed between the stitches.
		slope += vec2(fq.x + fq.y, fq.x - fq.y) * 0.35;
		float tuft = smoothstep(0.08, 0.0, length(fq - 0.5 * sign(fq)));
		shade *= 1.0 - 0.18 * tuft;
		// A woven damask pattern, very faint.
		shade *= 0.97 + 0.03 * sin(uv.x * 160.0) * sin(uv.y * 160.0);
	} else if (part > 0.25) {
		// The border: piping top and bottom, a vent stripe band in the middle.
		float v = uv.y;
		float pipe = smoothstep(0.012, 0.0, abs(v - 0.012)) + smoothstep(0.012, 0.0, abs(v - 0.228));
		shade *= 1.0 - 0.25 * pipe;
		float band = step(0.09, v) * step(v, 0.15);
		base = mix(base, base * vec3(0.55, 0.6, 0.72), band * 0.6);
		shade *= 0.96 + 0.04 * sin(uv.x * 220.0);
	} else {
		base *= 0.7;
	}
	// Road grime and the print of a tyre that went over it.
	float grime = vnoise(uv * 3.0) * 0.6 + vnoise(uv * 11.0) * 0.4;
	shade *= 1.0 - 0.28 * smoothstep(0.45, 0.95, grime);
	float tyre = smoothstep(0.14, 0.11, abs(uv.x * 0.8 + uv.y * 0.35 - 0.2)) * (0.6 + 0.4 * step(0.5, fract(uv.y * 14.0)));
	shade *= 1.0 - 0.45 * tyre * step(0.75, part);
	ALBEDO = cs_out(base * shade);
	ROUGHNESS = 0.92;
	SPECULAR = 0.3;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(slope.x * 0.25, 0.0, slope.y * 0.25, 0.0)).xyz);
}
