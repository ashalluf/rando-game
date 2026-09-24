shader_type spatial;

// The prayer-hall carpet of Masjid Omar ibn Al-Khattab: a deep red field laid in rows, one row
// per line of worshippers, each row bounded by a cream-and-gold band and divided into one
// prayer space per person by a small arch motif pointing to the qibla. UV is metres in the
// hall's own frame, u across the hall and v toward the qibla wall, so rows are lines of
// constant v and the arches point along -v.
//
// Colours are written as the colours they are (source_color); the pile gets its look from a
// fine sheen and a darker nap, not from a texture, so it holds together at any distance.

uniform vec3 field : source_color = vec3(0.50, 0.05, 0.07);
uniform vec3 field_dark : source_color = vec3(0.30, 0.02, 0.04);
uniform vec3 band : source_color = vec3(0.86, 0.78, 0.60);
uniform vec3 gold : source_color = vec3(0.72, 0.52, 0.20);
// Depth of one prayer row front to back, and width of one prayer space along it, in metres.
uniform float row_depth = 1.25;
uniform float space_width = 0.85;
// The band between rows, in metres.
uniform float band_width = 0.10;
// The point the rows are measured from: the qibla wall's inner face, in UV metres.
uniform vec2 origin = vec2(0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV - origin;
	float rv = fract(p.y / row_depth);          // 0 at the qibla side of a row, 1 at its back
	float dv = (1.0 - rv) * row_depth;           // metres forward from the row's back edge
	float su = fract(p.x / space_width) * space_width - space_width * 0.5;  // metres from a space's centre line

	vec3 col = field;
	// Nap: a slow tonal drift plus fine grain, so a hall of red does not read as a flat plane.
	float nap = noise(p * 1.7) * 0.6 + noise(p * 37.0) * 0.4;
	col = mix(field_dark, field, 0.55 + 0.45 * nap);

	// The row band: cream with a thin gold line either side.
	float in_band = step(dv, band_width);
	float gold_line = step(abs(dv - band_width * 0.5), band_width * 0.5) * (1.0 - step(abs(dv - band_width * 0.5), band_width * 0.30));
	col = mix(col, band, in_band);
	col = mix(col, gold, gold_line);

	// One arch per prayer space: a pointed outline near the front of the row, in gold.
	float ay = dv - band_width - 0.10;           // metres above the arch's springing line
	float half_w = 0.24;
	float arch_h = 0.62;
	float x = abs(su);
	// Straight jambs up to the spring, then a two-centred point.
	float inside_jamb = step(x, half_w) * step(0.0, ay) * step(ay, arch_h * 0.55);
	float r = half_w * 1.6;
	float cx = half_w - r;
	float d_arc = length(vec2(x - cx, ay - arch_h * 0.55));
	float inside_arc = step(arch_h * 0.55, ay) * step(d_arc, r) * step(ay, arch_h);
	float inside = max(inside_jamb, inside_arc);
	// Outline 3 cm wide: inside the shape but not inside a copy shrunk by that much.
	float half_i = half_w - 0.03;
	float ay_i = ay - 0.03;
	float jamb_i = step(x, half_i) * step(0.0, ay_i) * step(ay_i, arch_h * 0.55 - 0.03);
	float d_arc_i = length(vec2(x - cx, ay - arch_h * 0.55));
	float arc_i = step(arch_h * 0.55, ay) * step(d_arc_i, r - 0.03) * step(ay, arch_h - 0.04);
	float outline = inside * (1.0 - max(jamb_i, arc_i));
	col = mix(col, gold, outline * 0.9);
	// A darker panel inside the arch, where the forehead goes.
	col = mix(col, field_dark * 0.9, max(jamb_i, arc_i) * 0.35);

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	// Pile sheen: wool throws light back along grazing view directions.
	RIM = 0.35;
	RIM_TINT = 0.6;
}
