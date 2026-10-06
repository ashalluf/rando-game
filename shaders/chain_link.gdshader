shader_type spatial;
render_mode cull_disabled;

// Chain-link fencing (LotFill's car parks): galvanised wire woven in 6 cm diamonds, cut out of
// one quad a panel. UV is metres (x along the run, y up), from LotFill.chain_link_panel(). Up
// close the wires are drawn; once a diamond is under a couple of pixels they only shimmer, so
// the mesh turns into a dithered haze of its own average cover (the wire's share of the panel),
// which TAA resolves and a still shows as a fine grain.

uniform vec3 wire_color : source_color = vec3(0.58, 0.59, 0.60);
// Diamond size (metres) and the wire's width as a share of it.
uniform float diamond = 0.06;
uniform float wire = 0.09;

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	vec2 p = UV / diamond;
	vec2 d = vec2(p.x + p.y, p.x - p.y);
	vec2 f = abs(fract(d) - 0.5);
	float dist = 0.5 - max(f.x, f.y);
	float fw = max(fwidth(d.x), fwidth(d.y));
	float line = 1.0 - smoothstep(wire, wire + fw, dist);
	// The wire's share of the panel, for when the diamonds are too small to draw.
	float avg = 1.0 - (1.0 - 2.0 * wire) * (1.0 - 2.0 * wire);
	float cover = mix(line, avg * 0.8, smoothstep(0.25, 0.7, fw));
	if (cover < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	// Brighter where the wire faces up, darker in the weave.
	ALBEDO = wire_color * (0.8 + 0.3 * fract(d.x * 0.5));
	METALLIC = 0.6;
	ROUGHNESS = 0.45;
}
