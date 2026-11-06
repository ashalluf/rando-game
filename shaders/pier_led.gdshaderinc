// The pier wheel's LED patterns (PierPark's Ferris wheel), shared by pier_park.gdshader (the LEDs
// themselves) and pier_wheel_glow.gdshader (the light they throw into the air round the wheel),
// so the glow is always the colour the LEDs are. Shader includes use // comments.

float h11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

vec3 hue(float h) {
	vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return k * k;
}

// Brightness and colour of an LED at radius r (0..1 of the rim) on spoke s of n, pattern p.
vec3 led_pattern(int p, float s, float r, float t, float n) {
	if (p == 0) {
		// Runs of light racing out along every spoke, a colour per spoke round the wheel.
		float run = fract(r * 1.6 - t * 0.55);
		float b = smoothstep(0.0, 0.08, run) * smoothstep(0.42, 0.18, run);
		return hue(s / n + t * 0.03) * b;
	} else if (p == 1) {
		// A sweep going round: the spokes light one after another, with a fading tail.
		float a = fract(s / n - t * 0.12);
		float b = pow(1.0 - a, 6.0) + 0.06;
		return mix(vec3(1.0, 0.25, 0.55), vec3(0.3, 0.6, 1.0), r) * b;
	} else if (p == 2) {
		// A spiral: the phase runs round and out together.
		float ph = fract(s / n * 2.0 + r * 1.2 - t * 0.35);
		float b = smoothstep(0.5, 0.0, abs(ph - 0.5) * 2.0 - 0.35);
		return hue(ph * 0.5 + 0.55) * (0.15 + b);
	}
	// The whole wheel in one slow colour with a sparkle running through it.
	float sp = step(0.93, h11(floor(t * 7.0) * 13.1 + s * 3.7 + floor(r * 22.0) * 1.3));
	vec3 base = hue(t * 0.02 + 0.6) * 0.55;
	return base + vec3(1.0) * sp;
}

// The wheel's lights at time t: the crossfade between patterns every `period` seconds, plus the
// faint glow every LED keeps in the wheel's colour (so the whole wheel draws its outline).
vec3 led_wheel(float s, float r, float t, float n, float period) {
	float cyc = t / period;
	int p0 = int(mod(floor(cyc), 4.0));
	int p1 = int(mod(floor(cyc) + 1.0, 4.0));
	float fade = smoothstep(0.85, 1.0, fract(cyc));
	vec3 c = mix(led_pattern(p0, s, r, t, n), led_pattern(p1, s, r, t, n), fade);
	return c + hue(t * 0.015 + 0.55) * 0.08;
}
