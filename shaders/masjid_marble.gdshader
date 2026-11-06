shader_type spatial;

// Grey-veined white marble for the entrance stairs, the porch and the lobby floor: the stairs in
// the owner's photo are pale grey marble with darker veins and a black anti-slip strip near each
// nosing, which the geometry lays as a separate strip. World-space, so every tread shows a
// different part of the slab and neighbouring stones do not repeat.

uniform vec3 base : source_color = vec3(0.80, 0.80, 0.79);
uniform vec3 vein : source_color = vec3(0.42, 0.43, 0.45);
uniform float scale = 0.9;

varying vec3 wpos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i), n100 = hash(i + vec3(1, 0, 0)), n010 = hash(i + vec3(0, 1, 0)), n110 = hash(i + vec3(1, 1, 0));
	float n001 = hash(i + vec3(0, 0, 1)), n101 = hash(i + vec3(1, 0, 1)), n011 = hash(i + vec3(0, 1, 1)), n111 = hash(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = wpos * scale;
	// Veins: thin ridges of a warped noise field.
	float w = fbm(p * 1.3);
	float v = abs(sin((p.x * 0.7 + p.z * 0.5 + p.y * 0.3 + w * 5.0) * 3.1));
	float veins = pow(1.0 - v, 9.0);
	float cloud = fbm(p * 0.6);
	vec3 col = base * (0.93 + 0.10 * cloud);
	col = mix(col, vein, veins * 0.75);
	ALBEDO = col;
	ROUGHNESS = 0.18 + 0.10 * cloud;
	SPECULAR = 0.55;
}
