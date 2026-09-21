shader_type sky;
// Picturesque sky: a gradient with real twilight banding, a sun disc with limb darkening, three
// cloud decks (cirrus, a mid deck and cumulus) lit by stepping the noise field toward the sun,
// crepuscular rays through the gaps in them, a phased moon, stars and a milky way.
// DayNight sets the colours and the sun / moon directions per hour; everything here works on the
// Compatibility (web) renderer too, and the expensive half is gated on `cloud_detail`, which
// Quality clears on web and below MEDIUM.

global uniform float night_factor;

uniform vec3 sky_top : source_color = vec3(0.12, 0.32, 0.75);
uniform vec3 sky_horizon : source_color = vec3(0.70, 0.82, 0.95);
uniform vec3 ground_color : source_color = vec3(0.30, 0.32, 0.36);
/// Extra horizon haze (0 clear, 1 milky).
uniform float haze : hint_range(0.0, 1.0) = 0.55;

// --- Sun --------------------------------------------------------------------------------------
/// Direction toward the sun. DayNight keeps it continuous through the night, so the sun really
/// sets instead of teleporting and the twilight bands stay anchored to it once it has gone.
uniform vec3 sun_dir = vec3(0.35, 0.72, 0.60);
/// The sun's own colour (warm at dusk). Separate from the light, which becomes the moon at night.
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.90);
/// Sun disc radius (radians) and halo strength.
uniform float sun_size : hint_range(0.0, 0.1) = 0.014;
uniform float sun_glow : hint_range(0.0, 3.0) = 0.9;
uniform vec3 sun_tint : source_color = vec3(1.0, 0.96, 0.88);

// --- Twilight ---------------------------------------------------------------------------------
/// Warm band hugging the horizon and the cool band standing above it. `twilight_amount` is how
/// much of the sky they paint (DayNight drives it from the golden hour), `twilight_falloff` is the
/// height the warm band decays over and `twilight_band_height` is where the cool band sits.
uniform vec3 twilight_warm : source_color = vec3(1.0, 0.42, 0.16);
uniform vec3 twilight_band : source_color = vec3(0.44, 0.28, 0.54);
uniform float twilight_amount : hint_range(0.0, 1.0) = 0.0;
uniform float twilight_falloff : hint_range(0.02, 0.6) = 0.16;
uniform float twilight_band_height : hint_range(0.0, 1.0) = 0.26;

// --- Moon -------------------------------------------------------------------------------------
/// Direction toward the moon, its tint, its apparent radius in radians (the real moon is about
/// 0.0045) and its halo. The phase is not a uniform: it falls out of where `sun_dir` is.
uniform vec3 moon_dir = vec3(-0.40, 0.70, -0.59);
uniform vec3 moon_tint : source_color = vec3(0.94, 0.95, 1.0);
uniform float moon_size : hint_range(0.0, 0.05) = 0.012;
uniform float moon_glow : hint_range(0.0, 2.0) = 0.8;

// --- Clouds -----------------------------------------------------------------------------------
/// Cumulus amount (0 = clear, 1 = overcast), edge softness and drift speed.
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_softness : hint_range(0.02, 1.0) = 0.30;
uniform float cloud_speed = 0.006;
/// The decks above the cumulus: a broken mid-altitude sheet and high cirrus. Both, the sun-side
/// sculpting and the crepuscular rays are gated on `cloud_detail`; it costs five noise taps.
uniform float mid_amount : hint_range(0.0, 1.0) = 0.5;
uniform float cirrus_amount : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_detail : hint_range(0.0, 1.0) = 1.0;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.58, 0.63, 0.74);
/// Crepuscular rays streaming through the gaps in the deck (0 off).
uniform float god_rays : hint_range(0.0, 2.0) = 0.8;

// --- Night ------------------------------------------------------------------------------------
/// Star brightness and the milky-way band, both scaled by the night.
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform float milky_way : hint_range(0.0, 1.0) = 0.55;
/// Lightning flash (0..1), set by Weather.
uniform float flash = 0.0;

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

// Three octaves, for the extra taps that only need the cloud's broad shape.
float fbm3(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * vnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return v * 1.15;
}

// Two octaves, for the far ends of the march toward the sun: those only decide whether there is
// a cloud in the way at all, and the far one costs the same as the near one.
float fbm2(vec2 p) {
	float v = vnoise(p) * 0.5;
	v += vnoise(p * 2.03 + vec2(17.3, 9.1)) * 0.25;
	return v * 1.34;
}

// fbm sits around 0.3..0.75; stretch it to 0..1 so coverage means what it says.
float cloud_lo(vec2 p) {
	return clamp((fbm3(p) - 0.3) * 2.2, 0.0, 1.0);
}

float cloud_vlo(vec2 p) {
	return clamp((fbm2(p) - 0.3) * 2.2, 0.0, 1.0);
}


void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;

	vec3 sdir = vec3(0.0, 1.0, 0.0);
	if (length(sun_dir) > 0.001) {
		sdir = normalize(sun_dir);
	}
	vec3 mdir = vec3(0.0, 1.0, 0.0);
	if (length(moon_dir) > 0.001) {
		mdir = normalize(moon_dir);
	}
	// How much of the sun is still up. Everything it lights fades out with it instead of
	// switching off the instant it crosses the horizon.
	float sun_up = smoothstep(-0.16, 0.03, sdir.y);
	float moon_vis = smoothstep(0.02, 0.28, night_factor) * smoothstep(-0.02, 0.07, mdir.y);
	vec3 sun_light = sun_color * sun_tint;

	// Base gradient: zenith to horizon with haze piling up low down, handing over below the
	// horizon to the far ground haze. The ground plane only reaches a few kilometres, so from any
	// height there is a band of that between the land and the true horizon: it has to read as
	// more haze, not as a dark grey stripe across the bottom of the sky.
	float t = clamp(up, 0.0, 1.0);
	vec3 col = mix(sky_horizon, sky_top, pow(t, 0.5));
	col = mix(col, sky_horizon, haze * exp(-max(up, 0.0) * 8.0));
	float below = clamp(-up * 2.2, 0.0, 1.0);
	col = mix(col, ground_color, below);

	float cos_sun = dot(dir, sdir);
	float ang = acos(clamp(cos_sun, -1.0, 1.0));

	// --- Twilight banding ----------------------------------------------------------------
	// A dawn sky is not one vertical gradient. It is warm where the sun is and low down, it
	// cools fast with height, and a violet band stands above the warm one - deepest on the side
	// away from the sun, because that band is the shadow of the earth itself climbing the sky.
	// Colour has to vary with the angle from the sun as well as with height or sunset reads as
	// an orange stripe pasted round the whole horizon.
	if (twilight_amount > 0.002) {
		vec2 dh = dir.xz;
		vec2 sh = sdir.xz;
		float dl = length(dh);
		float sl = length(sh);
		float azi = 0.0;
		if (dl > 1e-4 && sl > 1e-4) {
			azi = dot(dh, sh) / (dl * sl);
		}
		float toward = pow(max(azi, 0.0), 1.6);
		float warm = exp(-max(up, 0.0) / max(twilight_falloff, 0.02)) * (0.20 + 0.80 * toward);
		col = mix(col, twilight_warm, clamp(warm * twilight_amount, 0.0, 1.0) * (1.0 - below * 0.45));
		float bh = (up - twilight_band_height) / 0.24;
		float band = exp(-bh * bh) * (0.26 + 0.46 * (1.0 - toward));
		col = mix(col, twilight_band, clamp(band * twilight_amount, 0.0, 1.0));
	}

	// --- Sun -------------------------------------------------------------------------------
	float horizon_cut = smoothstep(-0.11, -0.005, up);
	float glow = pow(max(cos_sun, 0.0), 48.0) * 0.8 + pow(max(cos_sun, 0.0), 6.0) * 0.18;
	col += glow * sun_glow * sun_up * horizon_cut * sun_light;
	float disc = 1.0 - smoothstep(sun_size * 0.82, sun_size * 1.02, ang);
	// Limb darkening: the edge of the disc is dimmer than the middle, which is most of why a
	// real sun reads as a sphere and a painted circle does not.
	float limb = 1.0 - 0.40 * smoothstep(0.5, 1.0, ang / max(sun_size, 1e-4));
	col = mix(col, sun_light * 7.0 * limb, disc * sun_up * horizon_cut);

	// --- Moon ------------------------------------------------------------------------------
	// Its own body, not the sun's disc redrawn: much smaller, much sharper, with maria and a
	// terminator whose shape comes from the real angle between the moon and the sun.
	if (!AT_CUBEMAP_PASS && moon_vis > 0.002) {
		float mcos = dot(dir, mdir);
		float mang = acos(clamp(mcos, -1.0, 1.0));
		col += moon_tint * exp(-mang * mang * 230.0) * moon_glow * 0.22 * moon_vis;
		if (mang < moon_size * 2.0) {
			vec3 mx = normalize(cross(mdir, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
			vec3 my = cross(mx, mdir);
			vec2 duv = vec2(dot(dir - mdir * mcos, mx), dot(dir - mdir * mcos, my)) / max(moon_size, 1e-4);
			float r = length(duv);
			float edge = 1.0 - smoothstep(0.93, 1.0, r);
			if (edge > 0.001) {
				// Surface normal of the sphere at this point on the disc, in the moon's frame.
				vec3 n = vec3(duv, -sqrt(max(1.0 - min(r * r, 1.0), 0.0)));
				vec3 l = normalize(vec3(dot(sdir, mx), dot(sdir, my), dot(sdir, mdir)));
				float phase = smoothstep(-0.03, 0.15, dot(n, l));
				float m = vnoise(duv * 1.6 + 11.0) * 0.62 + vnoise(duv * 4.3 + 3.0) * 0.38;
				float albedo = mix(0.40, 1.0, smoothstep(0.30, 0.72, m));
				float mlimb = mix(1.0, 0.74, smoothstep(0.5, 1.0, r));
				// Kept just under the clipping point: at 3x this it was a white hole in the sky
				// and the maria went with it. The 0.09 floor is earthshine, which is never black.
				vec3 moon = moon_tint * albedo * mlimb * (0.09 + 0.91 * phase) * 1.7;
				col = mix(col, moon, edge * moon_vis);
			}
		}
	}

	// --- Stars and the milky way -------------------------------------------------------------
	if (!AT_CUBEMAP_PASS && stars > 0.002 && up > 0.0) {
		float fade = smoothstep(0.0, 0.25, up) * stars;
		vec3 cell = floor(dir * 340.0);
		float h = hash12(cell.xz * 1.7 + cell.y * 13.1);
		float twinkle = 0.7 + 0.3 * sin(TIME * 2.0 + h * 40.0);
		float s1 = smoothstep(0.9930, 1.0, h) * twinkle;
		// A second, fainter and denser layer: one layer of equally bright dots reads as a grid.
		vec3 cell2 = floor(dir * 760.0);
		float h2 = hash12(cell2.xz * 2.3 + cell2.y * 7.7);
		float s2 = smoothstep(0.9975, 1.0, h2) * 0.5;
		vec3 star_tint = mix(vec3(0.72, 0.80, 1.0), vec3(1.0, 0.84, 0.66), fract(h * 37.0));
		col += star_tint * (s1 + s2) * fade;

		// The galactic band: a wide gaussian around a fixed plane, clumped and cut by dust lanes.
		if (milky_way > 0.002) {
			vec3 gal = normalize(vec3(0.62, 0.45, -0.64));
			float gd = dot(dir, gal);
			float band = exp(-gd * gd * 52.0);
			if (band > 0.004) {
				vec3 ga = normalize(cross(gal, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
				vec3 gb = cross(ga, gal);
				vec2 guv = vec2(dot(dir, ga), dot(dir, gb)) * 4.0;
				float clump = vnoise(guv * 2.4) * 0.6 + vnoise(guv * 6.1 + 5.0) * 0.4;
				float dust = smoothstep(0.30, 0.62, vnoise(vec2(guv.x * 1.7, guv.y * 0.6) + 19.0));
				// Contrast on the clumps, or the band is a smear of colour over half the sky
				// instead of a structured cloud of stars too faint to resolve.
				clump = smoothstep(0.34, 0.86, clump);
				float glowb = band * (0.06 + 0.94 * clump) * (1.0 - 0.72 * dust);
				col += mix(vec3(0.34, 0.38, 0.52), vec3(0.72, 0.68, 0.60), clump)
					* glowb * milky_way * fade * 0.22;
			}
		}
	}

	// --- Clouds ------------------------------------------------------------------------------
	if (up > 0.0) {
		vec2 drift = vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		vec2 uv = dir.xz / (up + 0.12) * 2.2 + drift;
		float d = clamp((fbm(uv) - 0.3) * 2.2, 0.0, 1.0);
		float shape = d;
		if (cloud_detail > 0.5) {
			shape = d * 0.8 + cloud_lo(uv * 3.5 + 3.7) * 0.2;
		}
		float edge0 = 1.0 - cloud_coverage;
		float density = smoothstep(edge0, edge0 + cloud_softness, shape) * smoothstep(0.0, 0.22, up);
		float thick = clamp((shape - edge0) / max(cloud_softness, 0.02), 0.0, 1.0);

		// Shape the puffs by looking toward the sun. A cloud lit as one flat white field is the
		// thing that gives a sky away: real cumulus are brilliant on the sun side and grey
		// underneath, because the cloud in front of them is in the way. Step across the same
		// noise field toward the sun and see how much of it is; where there is more, this part
		// is in shadow, where there is less, it is a sunlit shoulder. The same march also says
		// whether sunlight reaches this patch of air at all, which is what a crepuscular ray is.
		float sunlit = 0.5;
		float shaft = 0.0;
		if (cloud_detail > 0.5) {
			vec2 sun_uv = sdir.xz / (max(sdir.y, 0.08) + 0.12) * 2.2;
			// The march has to run in the noise field's own space. `uv` carries `drift`, so the
			// sun's position in that space is `sun_uv + drift`; subtracting the undrifted `sun_uv`
			// from a drifted `uv` leaves a -drift error that grows without bound with TIME. At
			// cloud_speed 0.006 that error passes the real sun offset after about five minutes of
			// play, so the shafts stop pointing at the sun and slowly swing round the sky. The
			// drift cancels exactly, which also makes this immune to TIME rolling over.
			vec2 to_sun = normalize(sun_uv + drift - uv + vec2(1e-4, 0.0));
			float s1 = cloud_lo(uv + to_sun * 0.30);
			float s2 = cloud_vlo(uv + to_sun * 0.85);
			float s3 = cloud_vlo(uv + to_sun * 1.60);
			sunlit = clamp(0.5 + (shape - (s1 * 0.62 + s2 * 0.38)) * 2.4, 0.0, 1.0);
			float occ = s1 * 0.5 + s2 * 0.3 + s3 * 0.2;
			float blocked = smoothstep(edge0 - 0.06, edge0 + cloud_softness, occ);
			float clear_lane = 1.0 - blocked;
			// Squared, so the shafts are lanes rather than a general brightening near the sun.
			clear_lane *= clear_lane;
			shaft = clear_lane * exp(-ang * ang * 2.4) * god_rays * sun_up
				* smoothstep(0.04, 0.32, cloud_coverage) * (1.0 - density);
		}
		sunlit = mix(0.5, sunlit, sun_up);

		vec3 cloud = mix(cloud_shadow, cloud_color, sunlit);
		// The densest cores still go grey whichever way the light comes from.
		cloud = mix(cloud, cloud * mix(vec3(1.0), cloud_shadow, 0.55), thick * 0.55);
		cloud += sun_light * pow(max(cos_sun, 0.0), 3.0) * sun_up * 0.35;
		// Silver lining: a thin edge with the sun behind it glows right through.
		float rim = density * (1.0 - thick) * pow(max(cos_sun, 0.0), 5.0);
		cloud += sun_light * rim * 1.1 * sun_up;
		// At night the moon relights them, far dimmer and cooler.
		float mlit = pow(max(dot(dir, mdir), 0.0), 4.0) * moon_vis;
		vec3 night_cloud = cloud * 0.12 + vec3(0.02, 0.025, 0.04) + moon_tint * mlit * 0.12;
		cloud = mix(cloud, night_cloud, night_factor);

		// Painted high deck first, so the decks really overlap instead of faking it: cirrus,
		// then the mid sheet, then the rays in the air under them, then the cumulus in front.
		if (cloud_detail > 0.5 && cirrus_amount > 0.01) {
			// High cirrus, drifting faster and sheared out by the wind. It is what stops the
			// upper half of the sky being an empty gradient.
			vec2 cuv = dir.xz / (up + 0.05) * 0.95 + vec2(TIME * cloud_speed * 2.6, 0.0);
			float cir = clamp((fbm3(vec2(cuv.x * 0.55, cuv.y * 2.7)) - 0.42) * 3.0, 0.0, 1.0);
			cir *= smoothstep(0.03, 0.34, up) * cirrus_amount * (1.0 - night_factor * 0.85);
			col = mix(col, cloud_color * 1.04 + sun_light * 0.10, cir * 0.55);
		}
		if (cloud_detail > 0.5 && mid_amount > 0.01) {
			// A broken altocumulus sheet, higher up and drifting slower than the cumulus. Two
			// decks at different speeds is most of what makes a sky read as weather rather than
			// as one field of cotton wool.
			vec2 muv = dir.xz / (up + 0.30) * 1.3
				+ vec2(TIME * cloud_speed * 0.42, TIME * cloud_speed * 0.20);
			float mv = cloud_lo(muv * 1.7 + 41.0);
			float mth = 1.0 - cloud_coverage * 0.75;
			float mden = smoothstep(mth, mth + 0.28, mv) * mid_amount * smoothstep(0.04, 0.34, up);
			vec3 mcol = mix(cloud_shadow * 1.08, cloud_color * 0.98, 0.45 + 0.55 * sunlit);
			mcol = mix(mcol, mcol * 0.14 + vec3(0.02, 0.025, 0.04), night_factor);
			col = mix(col, mcol, mden * 0.70);
		}
		col += sun_light * shaft * 0.38;
		// Thin edges stay translucent and the cores go nearly opaque, which is what makes a
		// cumulus read as a volume instead of as a patch of fog.
		col = mix(col, cloud, density * mix(0.84, 0.99, thick));
	}
	col += flash * vec3(0.8, 0.85, 1.0);
	COLOR = col;
}
