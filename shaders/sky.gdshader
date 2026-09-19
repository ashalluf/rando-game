shader_type sky;
// Picturesque sky: deep zenith to hazy horizon, a real sun disc with glow, drifting FBM clouds
// lit by the sun, a moon and stars at night. DayNight sets the colors per hour; the shader
// works on the Compatibility (web) renderer too.

global uniform float night_factor;

uniform vec3 sky_top : source_color = vec3(0.12, 0.32, 0.75);
uniform vec3 sky_horizon : source_color = vec3(0.70, 0.82, 0.95);
uniform vec3 ground_color : source_color = vec3(0.30, 0.32, 0.36);
/// Sun disc radius (radians) and halo strength.
uniform float sun_size : hint_range(0.0, 0.1) = 0.014;
uniform float sun_glow : hint_range(0.0, 3.0) = 0.9;
uniform vec3 sun_tint : source_color = vec3(1.0, 0.96, 0.88);
/// Cloud amount (0 = clear, 1 = overcast), edge softness and drift speed.
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_softness : hint_range(0.02, 1.0) = 0.35;
uniform float cloud_speed = 0.006;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.58, 0.63, 0.74);
/// Extra horizon haze (0..1) and star brightness (night).
uniform float haze : hint_range(0.0, 1.0) = 0.55;
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform float moon_size : hint_range(0.0, 0.1) = 0.02;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	float t = clamp(up, 0.0, 1.0);
	vec3 col = mix(sky_horizon, sky_top, pow(t, 0.5));
	// Haze piles up at the horizon.
	col = mix(col, sky_horizon, haze * exp(-max(up, 0.0) * 8.0));

	vec3 sun_dir = LIGHT0_DIRECTION;
	float cos_sun = dot(dir, sun_dir);
	float ang = acos(clamp(cos_sun, -1.0, 1.0));
	vec3 light_col = LIGHT0_COLOR * sun_tint;
	if (LIGHT0_ENABLED) {
		// By day LIGHT0 is the sun, by night DayNight turns the same light into the moon.
		float disc_size = mix(sun_size, moon_size, night_factor);
		float disc = 1.0 - smoothstep(disc_size * 0.75, disc_size, ang);
		float glow = pow(max(cos_sun, 0.0), 48.0) * 0.8 + pow(max(cos_sun, 0.0), 6.0) * 0.18;
		glow *= sun_glow * (1.0 - night_factor * 0.7);
		vec3 disc_col = mix(light_col * 6.0, vec3(0.95, 0.97, 1.0) * 2.0, night_factor);
		col += glow * light_col * float(up > -0.15);
		col = mix(col, disc_col, disc * float(up > -0.05));
	}

	// Stars, fading in with the night and out toward the horizon.
	if (stars > 0.0 && up > 0.0) {
		vec3 cell = floor(dir * 340.0);
		float h = hash12(cell.xz * 1.7 + cell.y * 13.1);
		float twinkle = 0.7 + 0.3 * sin(TIME * 2.0 + h * 40.0);
		float star = smoothstep(0.992, 1.0, h) * twinkle * stars * smoothstep(0.0, 0.25, up);
		col += vec3(star);
	}

	// Clouds on a plane above the camera, drifting with time.
	if (up > 0.0) {
		vec2 uv = dir.xz / (up + 0.12) * 2.2 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		// fbm sits around 0.3..0.75; stretch it to 0..1 so coverage means what it says.
		float d = clamp((fbm(uv) - 0.3) * 2.2, 0.0, 1.0);
		float detail = clamp((fbm(uv * 3.5 + 3.7) - 0.3) * 2.2, 0.0, 1.0);
		float shape = d * 0.8 + detail * 0.2;
		float density = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + cloud_softness, shape);
		density *= smoothstep(0.0, 0.22, up);
		float thick = clamp((shape - (1.0 - cloud_coverage)) / max(cloud_softness, 0.02), 0.0, 1.0);
		vec3 cloud = mix(cloud_color, cloud_shadow, thick * 0.8);
		float lit = pow(max(cos_sun, 0.0), 3.0) * (1.0 - night_factor * 0.8);
		cloud += light_col * lit * 0.35;
		cloud = mix(cloud, cloud * 0.12 + vec3(0.02, 0.025, 0.04), night_factor);
		col = mix(col, cloud, density * 0.92);
	} else {
		col = mix(sky_horizon, ground_color, clamp(-up * 6.0, 0.0, 1.0));
	}
	COLOR = col;
}
