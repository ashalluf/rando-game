shader_type sky;
// Picturesque sky: a gradient with real twilight banding, a sun disc with limb darkening, three
// cloud decks (cirrus, a mid deck and cumulus), crepuscular rays through the gaps in them,
// contrails, a phased moon with maria and craters, stars, the milky way and the city's light dome.
// DayNight (and its SkyExtras child) set the colours, the sun / moon directions per hour, the
// camera, the noise textures and the contrails; everything works on the Compatibility (web)
// renderer too, and the expensive half is gated on `cloud_detail`, which Quality clears on web
// and below MEDIUM.
//
// The cumulus are a VOLUME on Forward+ (`cloud_volume` 1, set once SkyExtras has handed over the
// noise): a short raymarch through a slab 1.5-3.1 km up, run in Godot's half-resolution sky pass
// (dithered per frame, which TAA resolves), with a light march toward the sun or the moon per
// sample - flat bases, cauliflower tops, bright sunlit sides, grey bases. The half pass also
// carries the sky-space crepuscular rays. Compatibility (and Forward+ below MEDIUM) keep the
// painted 2D cumulus, which costs a fraction of it.

#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
render_mode use_half_res_pass;
#endif

global uniform float night_factor;

uniform vec3 sky_top : source_color = vec3(0.12, 0.32, 0.75);
uniform vec3 sky_horizon : source_color = vec3(0.70, 0.82, 0.95);
uniform vec3 ground_color : source_color = vec3(0.30, 0.32, 0.36);
/// Extra horizon haze (0 clear, 1 milky).
uniform float haze : hint_range(0.0, 1.0) = 0.55;
/// Clouds after dark: how much of their lit colour they keep, and the light every cloud base and
/// the air under it carry of their own (linear). A clear night is moonlight and a blue glow; an
/// overcast one is the city's sodium light on the cloud base, which DayNight sets from the
/// weather. At a fixed blue-grey, a rainy night's 88 % cloud came out as a pale grey dusk.
uniform float night_cloud_light = 0.12;
uniform vec3 night_glow = vec3(0.02, 0.025, 0.04);
/// What reflections see below the horizon (the street), as a fraction of the horizon's own
/// brightness, and how far under the horizon it takes over (see the end of sky()).
uniform vec3 reflect_ground = vec3(0.34, 0.32, 0.30);
uniform float reflect_ground_fade = 0.08;
/// A real street under that horizon (Forward+ only; ReflectionProbes hands it over): Poly Haven's
/// CC0 San Giuseppe Bridge HDRI (tools/reflections/make_street_hdri.py), its rgb the scene relative
/// to its street's mean (x 0.5, sRGB), its alpha where something stands. The flat grey takes the
/// HDRI's structure at the same mean brightness, so the sky's ambient barely moves while every
/// car door and puddle out of a probe's reach mirrors facades, kerbs and paving instead of a
/// uniform grey. `street_hdri_rise` is how far over the horizon its skyline is let in (the up
/// component: 0.14 is 8 degrees), `street_hdri_yaw` turns it (turns).
uniform sampler2D street_hdri : source_color, filter_linear_mipmap, repeat_enable;
uniform float street_hdri_amount = 0.0;
uniform float street_hdri_rise = 0.14;
uniform float street_hdri_yaw = 0.0;

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
/// How much of the cool band there is (0..1). It is the earth's shadow, so it only exists once
/// the sun is on or under the horizon: DayNight holds it off while the sun is still well up.
uniform float twilight_band_gain : hint_range(0.0, 1.0) = 1.0;

// --- Smog -------------------------------------------------------------------------------------
/// The basin's smog layer at golden hour (DayNight drives all four; `smog` is 0 by day and night,
/// which skips the whole block). A lid of lit haze from the horizon up to `smog_top` (the sine
/// of its elevation): brown-grey away from the sun, glowing orange-pink toward it and low down.
uniform float smog = 0.0;
uniform vec3 smog_color : source_color = vec3(0.64, 0.54, 0.47);
uniform vec3 smog_glow : source_color = vec3(1.0, 0.58, 0.40);
uniform float smog_top = 0.075;

// --- Moon -------------------------------------------------------------------------------------
/// Direction toward the moon, its tint, its apparent radius in radians (the real moon is about
/// 0.0045) and its halo. The phase is not a uniform: it falls out of where `sun_dir` is, and
/// DayNight puts the moon where its age (the in-game date) says.
uniform vec3 moon_dir = vec3(-0.40, 0.70, -0.59);
uniform vec3 moon_tint : source_color = vec3(0.94, 0.95, 1.0);
uniform float moon_size : hint_range(0.0, 0.05) = 0.012;
uniform float moon_glow : hint_range(0.0, 2.0) = 0.8;
/// How bright the moon's unlit part is from the earth's own light at a new moon (0..1 of the lit
/// part's brightness; it falls to nothing at full moon). Most obvious on a thin crescent.
uniform float earthshine = 0.07;
/// The light the moon puts on the cloud edges and the clear sky round it, at full moon (linear).
uniform float moon_light = 0.05;

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

// --- Volumetric cumulus (Forward+, cloud_detail on) --------------------------------------------
/// 1 once SkyExtras has set the noise below; 0 draws the painted cumulus everywhere.
uniform float cloud_volume = 0.0;
/// The weather map (R where cumulus stand, G how tall, B the mid deck) and the 64^3 billow noise
/// (R Perlin-Worley, G / B Worley fbm), from tools/sky/make_cloud_noise.py.
uniform sampler2D cloud_weather : filter_linear_mipmap, repeat_enable;
uniform sampler3D cloud_shape : filter_linear, repeat_enable;
/// The camera's TRUE world position in km (x, height, z), so the deck stays put across origin
/// re-centres and drifts past a flying player.
uniform vec3 view_km = vec3(0.0);
/// Cloud base and the slab's depth (km above sea level), how big the weather map's tile is (km)
/// and the billows (km per tile of the 3D noise).
uniform float cloud_base = 1.45;
uniform float cloud_depth = 1.7;
uniform float weather_tile = 30.0;
uniform float billow_tile = 2.0;
/// Extinction per km of a fully dense cloud, and how bright the sun's side is (x sun colour).
uniform float cloud_extinction = 22.0;
uniform float cloud_sun = 1.55;
/// How bright the shaded underside stays (x the ambient), and the haze that takes the far deck.
uniform float cloud_ambient = 1.0;
uniform float cloud_haze_km = 38.0;
/// Wind for the deck, km/s (about 8 m/s).
uniform vec2 cloud_wind = vec2(0.0075, 0.0028);
/// The march's step budget: its steps are distance x 0.024 x 48 / this (the more, the finer).
uniform int cloud_steps = 48;

// --- Contrails ---------------------------------------------------------------------------------
/// Up to eight high jets' trails, from SkyExtras' Contrails (camera-relative km):
/// a: head x, height above the camera, head z, trail length; b: direction back along the trail
/// (x, z, the wind already folded in), metres a second the trail ages at (km/s), lifetime (s);
/// c: the jet's own speed along the trail (km/s; 0 hides the glint), width growth, seed.
uniform int trail_count = 0;
uniform vec4 trail_a[8];
uniform vec4 trail_b[8];
uniform vec4 trail_c[8];

// --- Night ------------------------------------------------------------------------------------
/// Star brightness and the milky-way band, both scaled by the night.
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform float milky_way : hint_range(0.0, 1.0) = 0.55;
/// How dark the sky is where the camera stands (1 over the ocean or up a mountain, about a third
/// downtown): how many stars and how much of the milky way survive the light pollution.
uniform float sky_dark = 1.0;
/// The city's light dome: an orange glow climbing from the horizon toward downtown (`city_dir`,
/// a unit xz heading), `city_glow` strong, wrapping `city_wrap` of the way round the horizon
/// (1 standing in the middle of it). SkyExtras sets them from the camera and the lamps.
uniform vec2 city_dir = vec2(1.0, 0.0);
uniform float city_glow = 0.0;
uniform float city_wrap = 0.0;
uniform vec3 city_glow_color : source_color = vec3(1.0, 0.55, 0.26);
/// Lightning flash (0..1), set by Weather.
uniform float flash = 0.0;

const float EARTH_R = 6371.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
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

// --- The volume -----------------------------------------------------------------------------

// Distance along a ray rising at `up` (the sine of its elevation) until it stands `dh` km higher
// than where it started, the ground curving away under it (altitude = t up + t^2 / 2R). The
// smallest positive root, or -1 when it never gets there; written so neither root cancels.
float rise_t(float up, float dh) {
	float disc = up * up + 2.0 * dh / EARTH_R;
	if (disc < 0.0) {
		return -1.0;
	}
	float s = sqrt(disc);
	if (dh >= 0.0) {
		return 2.0 * dh / max(up + s, 1e-6);
	}
	if (up >= 0.0) {
		return -1.0;
	}
	return 2.0 * dh / (up - s);
}

// The cumulus field at a point (km, world xz, altitude y). `detail` adds the fine erosion; the
// light march leaves it out (`fp` 0). Returns density 0..1.
//
// What makes a cumulus read as a photograph rather than a painting (the owner's review: "smooth
// triangular puffs at golden hour, uniform blobs at noon"), each a step below:
//   - a FLAT base at the condensation level the whole field shares, the body as wide as its base
//     for its lower third and only then rounding into a heap; the billows near the base work
//     sideways only (they never round the underside);
//   - footprints that are not discs: the weather map is read through a warp, and the tops lean
//     downwind, so no cloud is mirror-symmetric;
//   - two populations: the weather map's columns (heaps, a few towering) and, four times finer,
//     fragments - humilis and fractus - in the gaps;
//   - edges torn by three octaves of Worley erosion (the finest at about two pixels), swirled by
//     the billow noise, billowy above and wispy below, with ragged fractus hanging under the base.
float column(float w, float thr, float soft) {
	return smoothstep(thr, thr + soft, w);
}

float cumulus(vec3 p, float lod, float detail, float coverage, float fp) {
	float hn = (p.y - cloud_base) / cloud_depth;
	if (hn <= -0.06 || hn >= 1.0) {
		return 0.0;
	}
	float hc = max(hn, 0.0);
	// The tops lean downwind (shear): a heap's crown stands off its base.
	vec2 lean = normalize(cloud_wind + vec2(1e-5)) * hc * hc * 0.22;
	vec2 pxz = p.xz - lean;
	// A warp, a few hundred metres, from a slice of the billow noise: footprints with bays and
	// spurs instead of the weather map's round blots.
	vec3 wn = textureLod(cloud_shape, vec3(pxz / (billow_tile * 2.6), 0.37), 0.0).rgb;
	vec2 wv = wn.rb - 0.5;
	vec2 wuv = (pxz + wv * 0.9) / weather_tile;
	vec3 w = textureLod(cloud_weather, wuv, lod).rgb;
	// Fields: the same map four times bigger moves the coverage up and down by region, so one
	// stretch of sky has a few big heaps, the next a scatter of fragments, the next nothing.
	float field = textureLod(cloud_weather, wuv * 0.27 + vec2(0.37, 0.71), lod).b;
	float cov = coverage + (field - 0.5) * 0.46 * (1.0 - smoothstep(0.7, 0.9, coverage));
	float thr = 1.0 - cov;
	float strat = smoothstep(0.72, 0.95, coverage);
	// The heaps: the weather map's columns. How tall: mostly modest (G squared), towers where
	// the field is rich and the column strong.
	float col = column(w.r, thr, 0.26);
	float g = w.g * w.g;
	float top = mix(0.16, 1.0, g) * (0.4 + 0.6 * col) * mix(0.6, 1.35, field);
	// Turrets: the crown is a cluster of domes of different heights, never one level top (a
	// column that reached the slab's ceiling was cut flat: the boxes seen from the air).
	top = min(top * mix(0.72, 1.12, smoothstep(0.25, 0.75, wn.r)), 0.97);
	// The fragments: the map four times finer, kept in the gaps between the heaps, low and flat.
	vec2 fr = textureLod(cloud_weather, wuv * 4.3 + vec2(0.61, 0.23), lod + 1.0).rg;
	float fcol = column(fr.x, thr + 0.16 + 0.12 * col, 0.34) * (1.0 - strat);
	float ftop = mix(0.05, 0.2, fr.y);
	// Under the base: only the fringe of fractus.
	if (hn < 0.0) {
		if (detail <= 0.0 || fp <= 0.0 || col + fcol <= 0.0) {
			return 0.0;
		}
	}
	// Each population's envelope: as wide as its base up to `skirt` of its height, then a dome.
	float rel = hc / max(top, 0.05);
	float rr = smoothstep(0.22, 1.0, rel);
	rr = rr * rr * (1.0 + 0.4 * rr);
	float d_big = rel < 1.0 ? clamp((sqrt(col) - rr) / max(1.0 - rr, 0.05), 0.0, 1.0) : 0.0;
	float frel = hc / ftop;
	float fr2 = smoothstep(0.1, 1.0, frel);
	float d_frag = frel < 1.0 ? clamp((sqrt(fcol) * 0.7 - fr2 * fr2) / max(1.0 - fr2 * fr2, 0.05), 0.0, 1.0) : 0.0;
	// The crown: however strong the column, its upper part thins toward the top, so the billows
	// decide it (a heap of rounded turrets); without this a strong column was solid to its top
	// and its crown a sloping slab.
	d_big *= 1.0 - 0.8 * smoothstep(0.35, 1.0, rel);
	float env = max(d_big, d_frag);
	float in_frag = step(d_big, d_frag);
	float trel = mix(rel, frel, in_frag);
	env = mix(env, max(env, smoothstep(0.0, 0.3, col)), strat);
	if (env <= 0.0 && hn >= 0.0) {
		return 0.0;
	}
	// Billows. Near the base the noise is read at the base's height (sideways only), so the
	// underside stays flat however the margin is cut; higher up they turn the dome into a heap
	// of turrets. A dense core keeps every billow, so a body's inside is uneven (its shading).
	float qh = max(hc, 0.1 * top);
	vec3 q = vec3(pxz.x, cloud_base + qh * cloud_depth * 1.4, pxz.y) / billow_tile;
	vec4 s0 = textureLod(cloud_shape, q, 0.0);
	float b = s0.r * 0.62
		+ textureLod(cloud_shape, q * 2.3 + vec3(0.13, 0.41, 0.27), 0.0).r * 0.38;
	float b_far = textureLod(cloud_shape, q * 0.22 + vec3(0.5, 0.0, 0.3), 0.0).r;
	b = mix(mix(0.5, b_far, 0.8), b, clamp(detail * 1.5, 0.0, 1.0));
	float nb = mix(b, 1.0, 0.25 * (1.0 - smoothstep(0.0, 0.3, trel)));
	float d = clamp((nb - (1.0 - env)) / max(env, 0.05), 0.0, 1.0);
	d = clamp(d * mix(1.8, 0.9, in_frag), 0.0, 1.0);
	d = mix(d, env, strat * 0.6);
	// The base: cut sharp at the condensation level (a few tens of metres of fade).
	d *= smoothstep(0.0, 0.012, hn);
	// Fractus: ragged scud hanging up to ~100 m under the bases and round their feet, from the
	// finest noise, wherever there is a cloud overhead or beside.
	if (detail > 0.0 && fp > 0.0) {
		float under = (1.0 - smoothstep(0.0, 0.06, abs(hn + 0.02))) * smoothstep(0.15, 0.6, max(col, fcol));
		if (under > 0.0) {
			vec3 qf = q * 1.7 + vec3(0.21, 0.0, 0.67);
			float sc = textureLod(cloud_shape, qf, 0.0).b;
			float fx = smoothstep(0.62, 0.86, sc) * under * 0.5 * detail;
			d = max(d, fx);
		}
	}
	// Ragged edges: three octaves of Worley eat the margin of every cloud, the finest at about
	// two pixels here (fp, km a pixel), swirled by the billow noise so the tears curl. Remapped,
	// not subtracted: the noise's low values cut right through the margin into holes, tatters
	// and wisps. Billowy above (Worley as it is), wispy below (inverted).
	if (d > 0.0 && d < 0.9 && fp > 0.0) {
		float m = clamp(billow_tile / (fp * 8.0 * 2.2), 1.0, 18.0);
		vec3 qe = q * m + (s0.rgb - 0.5) * 0.9 + vec3(0.31, 0.17, 0.53);
		float e = textureLod(cloud_shape, qe, 0.0).g * 0.5
			+ textureLod(cloud_shape, qe * 2.17 + vec3(0.7), 0.0).g * 0.3;
		// The finest octave only where a pixel still holds it.
		float f3 = clamp(m / 6.0, 0.0, 1.0);
		e += mix(0.5, textureLod(cloud_shape, qe * 4.7 + vec3(0.3, 0.9, 0.1), 0.0).b, f3) * 0.2;
		e = mix(1.0 - e, e, smoothstep(0.03, 0.3, hn));
		float k = (1.0 - e) * mix(1.05, 1.35, in_frag) * (1.0 - d / 0.9) * mix(1.0, 0.5, strat);
		d = clamp((d - k) / max(1.0 - k, 0.1), 0.0, 1.0);
	}
	return d;
}

// Henyey-Greenstein, normalised to 1 for an isotropic medium.
float hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5);
}

// The march. Returns premultiplied radiance in rgb and the transmittance left in a.
vec4 cumulus_march(vec3 dir, vec3 ldir, vec3 lcol, vec3 amb_top, vec3 amb_bot, vec3 airlight,
		float coverage, float jitter, float pix) {
	vec3 o = view_km;
	float up = dir.y;
	// From the fractus under the base to the top of the slab.
	float h0 = cloud_base - 0.06 * cloud_depth - o.y;
	float h1 = cloud_base + cloud_depth - o.y;
	float t0 = -1.0;
	float t1 = -1.0;
	if (h0 > 0.0) {
		t0 = rise_t(up, h0);
		t1 = rise_t(up, h1);
	} else if (h1 > 0.0) {
		t0 = 0.0;
		float tb = rise_t(up, h0);
		t1 = tb > 0.0 ? tb : rise_t(up, h1);
	} else {
		t0 = rise_t(up, h1);
		float tb = rise_t(up, h0);
		t1 = tb > 0.0 ? tb : t0 + 6.0;
	}
	if (t0 < 0.0 || t1 <= t0 || t0 > 90.0) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	t1 = min(t1, t0 + 30.0);
	// Steps grow with distance (a pixel spans more out there) and halve inside a cloud, where
	// the shape is: a fixed count across the slab took kilometre steps near the horizon and
	// drew every edge as a comb of aliased spikes.
	float step_k = 0.024 * 48.0 / float(max(cloud_steps, 8));
	float cs = dot(dir, ldir);
	// Forward lobe for the silver lining, a little back-scatter, and a soft middle.
	float ph = mix(hg(cs, 0.72), hg(cs, -0.18), 0.42);
	float ph2 = mix(hg(cs, 0.36), 1.0, 0.5);
	vec2 wind = cloud_wind * TIME;
	float T = 1.0;
	vec3 L = vec3(0.0);
	float tsum = 0.0;
	float wsum = 0.0;
	float t = t0 + clamp(t0 * step_k, 0.04, 0.6) * jitter;
	int fine = 0;
	for (int i = 0; i < 96; i++) {
		if (t > t1 || T < 0.015) {
			break;
		}
		float coarse = clamp(t * step_k, 0.04, 0.6);
		float dt = coarse * (fine > 0 ? 0.3 : 1.0);
		vec3 p = o + dir * t;
		p.y = o.y + t * up + t * t / (2.0 * EARTH_R);
		p.xz += wind;
		// Mip of the weather map: what one pixel covers out there.
		// Half a level softer than that, so a column never peaks sharper than the map's texels.
		float lod = log2(max(t * pix / weather_tile * 256.0, 1.0)) + 0.5;
		// How much of the fine structure a pixel resolves at this distance (1 near, 0 far).
		float detail = 1.0 - smoothstep(0.025, 0.1, t * pix);
		float d = cumulus(p, lod, detail, coverage, t * pix);
		if (d > 0.002 && fine == 0) {
			// Just came into a cloud on a coarse step: back up and come in again finely, or the
			// edge lands wherever this pixel's dither put the step (a comb along every top).
			// Fine steps go on until eight in a row find nothing.
			fine = 8;
			t -= coarse * 0.7;
			continue;
		}
		fine = d > 0.002 ? 8 : max(fine - 1, 0);
		if (d > 0.002) {
			float hn = (p.y - cloud_base) / cloud_depth;
			// Light march toward the sun (or the moon): five taps, each twice further out, no
			// detail - 1.5 km, the depth of a tall heap, so a body's far side is in its own shade.
			float od = 0.0;
			float lt = 0.05;
			float lsum = 0.0;
			for (int j = 0; j < 5; j++) {
				vec3 lp = p + ldir * (lsum + lt * 0.5);
				od += cumulus(lp, lod, 0.67, coverage, 0.0) * lt;
				lsum += lt;
				lt *= 2.0;
			}
			od *= cloud_extinction;
			// Multiple scattering in three octaves (Wrenninge), each softer and less directional;
			// held low enough that a shaded side is a shaded side (the old 0.30 / 0.07 lit every
			// body evenly, the salmon-pink blobs of the review).
			float ls = exp(-od) * ph + exp(-od * 0.3) * 0.2 * ph2 + exp(-od * 0.1) * 0.035;
			// Powder: a cloud's sun side is darker in the first metres it is lit through.
			float powder = 1.0 - exp(-d * cloud_extinction * 0.2);
			ls *= mix(0.5, 1.0, powder);
			// The ambient: the sky's blue from above, the ground's bounce from below. It reaches
			// a dense core far less than a wisp, and the underside of a heap least of all (the
			// cloud above takes the sky away): grey-violet bodies, dark flat bases.
			float up_k = smoothstep(0.0, 0.7, hn);
			vec3 amb = mix(amb_bot, amb_top, up_k) * cloud_ambient;
			amb *= mix(1.0, mix(0.28, 0.7, up_k), smoothstep(0.0, 0.8, d));
			vec3 S = lcol * ls + amb;
			float tr = exp(-d * cloud_extinction * dt);
			vec3 add = T * S * (1.0 - tr);
			L += add;
			float wgt = T * (1.0 - tr);
			tsum += t * wgt;
			wsum += wgt;
			T *= tr;
		}
		t += dt;
	}
	// Aerial perspective: the deck far out goes into the air in front of it.
	float dist = wsum > 1e-4 ? tsum / wsum : t1;
	float hz = 1.0 - exp(-dist / cloud_haze_km);
	L = mix(L, airlight * (1.0 - T), hz);
	return vec4(L, T);
}

// Sky-space crepuscular rays: walk from this direction toward the sun across the sky, asking the
// weather map at the deck whether the sun shines through there; light that got through along the
// way streams down the line. Eight weather fetches.
float sky_rays(vec3 dir, vec3 sdir, float coverage, float jitter) {
	float vis = 0.0;
	float wsum = 0.0;
	float thr = 1.0 - coverage;
	for (int i = 0; i < 8; i++) {
		float f = (float(i) + jitter) / 8.0;
		vec3 sd = normalize(mix(dir, sdir, f * 0.92));
		float upd = max(sd.y, 0.02);
		float tc = rise_t(upd, cloud_base + cloud_depth * 0.3 - view_km.y);
		vec2 xz = view_km.xz + sd.xz * tc + cloud_wind * TIME;
		float c = textureLod(cloud_weather, xz / weather_tile, 3.0).r;
		float open = 1.0 - smoothstep(thr, thr + 0.22, c);
		float w = 0.5 + f;
		vis += open * w;
		wsum += w;
	}
	return vis / wsum;
}

// --- Stars ------------------------------------------------------------------------------------

// One layer of round, antialiased points: a star in `share` of the cells of a grid `res` cells
// across, its brightness drawn from a steep magnitude curve (many faint, few bright).
vec3 star_layer(vec3 dir, float res, float share, float seed, float pix) {
	vec3 c = dir * res;
	vec3 cell = floor(c);
	float h = hash13(cell + seed);
	if (h > share) {
		return vec3(0.0);
	}
	vec3 sp = cell + 0.15 + hash33(cell + seed * 1.7) * 0.7;
	vec3 dv = c - sp;
	dv -= dir * dot(dv, dir);
	float r = max(pix * res * 0.65, 0.06);
	float mag = h / share;
	float flux = pow(mag, 5.0) * 1.6 + 0.04;
	float twinkle = 0.8 + 0.2 * sin(TIME * (2.0 + mag * 3.0) + h * 91.0);
	vec3 tint = mix(vec3(0.70, 0.79, 1.0), vec3(1.0, 0.82, 0.62), fract(h * 57.0 / share));
	return tint * flux * twinkle * exp(-dot(dv, dv) / (r * r)) * (0.0036 / (r * r));
}

// --- The moon's face -----------------------------------------------------------------------------

// The near side's seas as dark ellipses (centre xy, radii zw on the unit disc, screen-right x,
// up y as seen from the northern hemisphere), so the face is the one people know.
const vec4 MARIA[11] = vec4[](
	vec4(-0.30, 0.42, 0.28, 0.24), // Imbrium
	vec4(-0.62, 0.08, 0.24, 0.42), // Procellarum
	vec4(0.24, 0.43, 0.16, 0.15), // Serenitatis
	vec4(0.40, 0.14, 0.21, 0.17), // Tranquillitatis
	vec4(0.74, 0.30, 0.11, 0.09), // Crisium
	vec4(0.66, -0.12, 0.12, 0.17), // Fecunditatis
	vec4(-0.20, -0.36, 0.18, 0.13), // Nubium
	vec4(-0.55, -0.36, 0.09, 0.09), // Humorum
	vec4(0.02, 0.74, 0.40, 0.07), // Frigoris
	vec4(0.45, -0.28, 0.08, 0.08), // Nectaris
	vec4(0.04, 0.24, 0.09, 0.07) // Vaporum
);

// Albedo and a relief normal tilt (xy) for a point on the face.
vec3 moon_face(vec2 p) {
	float m = 0.0;
	float warp = vnoise(p * 5.0 + 3.0) * 0.12 - 0.06;
	for (int i = 0; i < 11; i++) {
		vec2 q = (p - MARIA[i].xy) / MARIA[i].zw;
		m = max(m, 1.0 - smoothstep(0.55, 1.05, length(q) + warp));
	}
	m *= 0.75 + 0.25 * vnoise(p * 9.0 + 7.0);
	float albedo = mix(0.95, 0.42, m) * (0.9 + 0.1 * vnoise(p * 23.0));
	// Craters: one per cell of a jittered grid, bowls with raised rims, plus the bright young
	// ones (Tycho low on the face, Copernicus left of centre) with their rays.
	vec2 tilt = vec2(0.0);
	vec2 g = p * 7.0;
	vec2 gc = floor(g);
	for (int j = 0; j < 4; j++) {
		vec2 cc = gc + vec2(float(j % 2), float(j / 2)) - 0.5;
		vec2 h = vec2(hash12(cc + 4.1), hash12(cc + 9.7));
		float rr = 0.12 + 0.28 * h.x * h.x;
		vec2 dv = (g - cc - h) / rr;
		float dl = length(dv);
		if (dl < 1.25) {
			float bowl = 1.0 - smoothstep(0.0, 1.0, dl);
			float rim = exp(-(dl - 1.0) * (dl - 1.0) * 30.0);
			tilt += -normalize(dv + 1e-4) * (bowl * 0.8 - rim * 0.5) * dl;
			albedo *= 1.0 - 0.10 * bowl * h.y;
		}
	}
	vec2 ty = p - vec2(-0.12, -0.70);
	float tyd = length(ty);
	float ray_ang = atan(ty.y, ty.x);
	float rays = smoothstep(0.55, 1.0, vnoise(vec2(ray_ang * 9.0, 0.0))) * exp(-tyd * 2.2);
	albedo += 0.25 * rays * (1.0 - m) + 0.3 * exp(-tyd * tyd * 900.0);
	vec2 co = p - vec2(-0.30, 0.15);
	albedo += 0.2 * exp(-dot(co, co) * 700.0);
	return vec3(clamp(albedo, 0.0, 1.25), tilt.x, tilt.y);
}

// --- The painted cumulus (Compatibility, and Forward+ below MEDIUM) ---------------------------
// The old 2D deck: one fbm layer at a sliding scale, the sun side sculpted by stepping the field
// toward the sun. Returns the deck's colour in rgb and its opacity in a; `shaft` gets the rays.
vec4 painted_cumulus(vec3 dir, vec3 sdir, vec3 mdir, vec3 sun_light, float sun_up, float moon_vis,
		float ang, float cos_sun, vec3 airlight, out float shaft) {
	float up = dir.y;
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
	float sunlit = 0.5;
	shaft = 0.0;
	if (cloud_detail > 0.5) {
		vec2 sun_uv = sdir.xz / (max(sdir.y, 0.08) + 0.12) * 2.2;
		// The march runs in the noise field's own space, drift included, so it stays aimed at
		// the sun however long the game runs.
		vec2 to_sun = normalize(sun_uv + drift - uv + vec2(1e-4, 0.0));
		float s1 = cloud_lo(uv + to_sun * 0.30);
		float s2 = cloud_vlo(uv + to_sun * 0.85);
		float s3 = cloud_vlo(uv + to_sun * 1.60);
		sunlit = clamp(0.5 + (shape - (s1 * 0.62 + s2 * 0.38)) * 2.4, 0.0, 1.0);
		float occ = s1 * 0.5 + s2 * 0.3 + s3 * 0.2;
		float blocked = smoothstep(edge0 - 0.06, edge0 + cloud_softness, occ);
		float clear_lane = 1.0 - blocked;
		clear_lane *= clear_lane;
		shaft = clear_lane * exp(-ang * ang * 2.4) * god_rays * sun_up
			* smoothstep(0.04, 0.32, cloud_coverage) * (1.0 - density);
	}
	sunlit = mix(0.5, sunlit, sun_up);
	// Aerial perspective: slant distance to a deck goes as 1 / sin(elevation).
	float deck_haze = 1.0 - exp(-0.11 / (up + 0.06));
	vec3 cloud = mix(cloud_shadow, cloud_color, sunlit);
	cloud = mix(cloud, cloud * mix(vec3(1.0), cloud_shadow, 0.55), thick * 0.55);
	cloud += sun_light * pow(max(cos_sun, 0.0), 3.0) * sun_up * 0.35;
	float rim = density * (1.0 - thick) * pow(max(cos_sun, 0.0), 5.0);
	cloud += sun_light * rim * 1.1 * sun_up;
	float mlit = pow(max(dot(dir, mdir), 0.0), 4.0) * moon_vis;
	vec3 night_cloud = cloud * night_cloud_light + night_glow + moon_tint * mlit * 0.12;
	cloud = mix(cloud, night_cloud, night_factor);
	cloud = mix(cloud, airlight, deck_haze);
	return vec4(cloud, density * mix(0.84, 0.99, thick));
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
	// How much of the moon's face is lit (0 new, 1 full), from the angle between it and the sun.
	float moon_lit = 0.5 - 0.5 * dot(sdir, mdir);
	vec3 sun_light = sun_color * sun_tint;
	float cos_sun = dot(dir, sdir);
	float ang = acos(clamp(cos_sun, -1.0, 1.0));
	// What one pixel spans, in radians (for antialiasing points and lines and the march's mips).
	float pix = max(length(fwidth(dir)), 1e-5);
	// A per-pixel, per-frame dither for the march and the rays (interleaved gradient noise),
	// which TAA resolves into smooth gradients.
	float frame = floor(TIME * 60.0);
	vec2 fc = FRAGCOORD.xy + vec2(frame * 5.588238, frame * 5.588238);
	float jitter = fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715))));

	// --- The airlight the far clouds go into, and the key light that falls on them -------
	vec3 airlight = sky_horizon * (1.0 + 0.6 * haze)
		+ sun_light * pow(max(cos_sun, 0.0), 3.0) * sun_up * 0.5;
	airlight = mix(airlight, night_glow, night_factor);

	bool volume = cloud_volume > 0.5 && cloud_detail > 0.5;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	volume = false;
#endif

#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	// The half-resolution pass carries the expensive part: the cumulus volume and the rays.
	if (AT_HALF_RES_PASS) {
		vec4 res = vec4(0.0, 0.0, 0.0, 1.0);
		if (volume && up > -0.08) {
			float coverage = clamp(cloud_coverage, 0.0, 0.98);
			// The key light: the sun, which at 2 km still lights the deck from under the horizon
			// for a few minutes after the street has lost it (pink bases), then the moon.
			float sun_key = smoothstep(-0.07, 0.02, sdir.y);
			// A sun low in the sky lights the deck through a long path of air: redden it.
			vec3 low_sun = sun_light * mix(vec3(1.0, 0.55, 0.32), vec3(1.0), smoothstep(-0.02, 0.18, sdir.y));
			vec3 ldir = sdir;
			// Cumulus in a high sun are white, not the cream of the light's own tint: the cloud
			// scatters every colour alike, and the blue sky fill on top of it reads as warm.
			vec3 white_sun = mix(low_sun, vec3(dot(low_sun, vec3(0.3333))), 0.85 * smoothstep(0.15, 0.5, sdir.y));
			vec3 lcol = white_sun * cloud_sun * sun_key;
			if (sun_key < 0.01) {
				ldir = mdir;
				lcol = moon_tint * moon_light * moon_lit * moon_lit * moon_vis * 0.9;
			}
			if (ldir.y < 0.0) {
				ldir = normalize(vec3(ldir.x, max(ldir.y, -0.04), ldir.z));
			}
			// The ambient: the sky's own blue above, the ground's bounce and the cloud's own
			// shade below; at night the night glow and the city's light dome under the bases.
			float hl = dot(sky_horizon, vec3(0.299, 0.587, 0.114));
			vec3 amb_top = (sky_top * 0.7 + sky_horizon * 0.5) * (1.0 - 0.6 * night_factor);
			vec3 amb_bot = cloud_shadow * hl * 0.55 + sun_light * 0.05 * sun_key;
			amb_top += night_glow * 0.3;
			amb_bot += night_glow * 0.45 + city_glow_color * city_glow * 0.3;
			res = cumulus_march(dir, ldir, lcol, amb_top, amb_bot, airlight, coverage, jitter, pix);
			// Under the horizon (a flying camera looking down at the deck) the march is the same.
			if (!AT_CUBEMAP_PASS && god_rays > 0.01 && sun_up > 0.01 && up > -0.02) {
				float lane = sky_rays(dir, sdir, coverage, jitter);
				float near_sun = exp(-ang * ang * 1.6);
				float shaft = lane * lane * near_sun * god_rays * sun_up
					* smoothstep(0.1, 0.35, coverage) * smoothstep(0.98, 0.6, coverage);
				// Rays are the air lit between the shadows, so they sit behind any cloud.
				res.rgb += low_sun * shaft * 0.32 * res.a;
			}
		}
		COLOR = res.rgb;
		ALPHA = res.a;
	} else {
#endif

	// Base gradient: zenith to horizon with haze piling up low down, handing over below the
	// horizon to the far ground haze. The ground plane only reaches a few kilometres, so from any
	// height there is a band of that between the land and the true horizon: it has to read as
	// more haze, not as a dark grey stripe across the bottom of the sky.
	float t = clamp(up, 0.0, 1.0);
	vec3 col = mix(sky_horizon, sky_top, pow(t, 0.5));
	col = mix(col, sky_horizon, haze * exp(-max(up, 0.0) * 8.0));
	float below = clamp(-up * 2.2, 0.0, 1.0);
	col = mix(col, ground_color, below);

	// --- Twilight banding ----------------------------------------------------------------
	// A dawn sky is not one vertical gradient. It is warm where the sun is and low down, it
	// cools fast with height, and a violet band stands above the warm one - deepest on the side
	// away from the sun, because that band is the shadow of the earth itself climbing the sky.
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
		col = mix(col, twilight_band, clamp(band * twilight_amount * twilight_band_gain, 0.0, 1.0));
	}

	// --- The city's light dome ---------------------------------------------------------------
	// At night a city lights the air over it: an orange glow standing on the horizon toward
	// downtown, wrapping round the sky the deeper into the city the camera is, a few degrees
	// high, fading up into the night. It is real sky colour, so the reflections get it too.
	if (city_glow > 0.001) {
		float dl = length(dir.xz);
		float az = dl > 1e-4 ? dot(dir.xz / dl, city_dir) : 0.0;
		float lobe = mix(pow(max(az * 0.5 + 0.5, 0.0), 4.0), 1.0, city_wrap);
		float rise = exp(-max(up, 0.0) / 0.075) * 0.75 + exp(-max(up, 0.0) / 0.3) * 0.25;
		vec3 dome = city_glow_color * city_glow * lobe * rise * (1.0 - below * 0.6);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		// Compatibility adds in sRGB numbers: over a dark sky a linear glow L shows as about
		// L^(1/2.2) there, so hand it over that way or the web never sees the dome.
		dome = pow(dome, vec3(0.4545)) * 0.6;
#endif
		col += dome;
	}

	// --- Smog ------------------------------------------------------------------------------
	// A Los Angeles evening is not a clear horizon. The basin sits under an inversion, and with
	// the sun low the air under it is a pale brown-grey lid a few degrees deep - glowing orange
	// and pink toward the sun, densest at the horizon, with a soft but definite top and clear
	// sky above it. Below the horizon it is the same air seen against the far land.
	// Its whole cost is this block, skipped outside golden hour.
	float smog_sun = 0.0;
	if (smog > 0.002) {
		float hup = max(up, 0.0);
		float lid = 1.0 - smoothstep(smog_top * 0.5, smog_top * 1.2, hup);
		float dens = lid * (0.62 + 0.38 * exp(-hup / (smog_top * 0.35)));
		vec2 dh = dir.xz;
		vec2 sh = sdir.xz;
		float azs = dot(dh, sh) * inversesqrt(max(dot(dh, dh) * dot(sh, sh), 1e-8));
		float toward_s = max(azs, 0.0);
		toward_s *= toward_s;
		// Warm at the bottom and toward the sun, brown-grey higher up and round the back.
		float warm_s = exp(-hup / (smog_top * 0.45)) * (0.30 + 0.70 * toward_s);
		vec3 smog_col = mix(smog_color, smog_glow, clamp(warm_s, 0.0, 1.0));
		col = mix(col, smog_col, clamp(dens * smog, 0.0, 1.0));
		// How deep in the layer the sun itself is, for its disc and halo below.
		smog_sun = smog * (1.0 - smoothstep(0.0, smog_top * 1.25, sdir.y));
	}

	// --- Sun -------------------------------------------------------------------------------
	float horizon_cut = smoothstep(-0.11, -0.005, up);
	float glow = pow(max(cos_sun, 0.0), 48.0) * 0.8 + pow(max(cos_sun, 0.0), 6.0) * 0.18;
	col += glow * sun_glow * sun_up * horizon_cut * sun_light;
	// The aureole: real circumsolar scatter lives inside three degrees, so an exponential on a
	// one-degree scale (0.46 of its peak at the limb, 0.14 at two degrees, 0.008 by five).
	col += sun_light * exp(-ang / 0.018) * 1.8 * sun_glow * sun_up * horizon_cut;
	// A sun down in the smog is diffused: a wider, softer glow round it, and the disc itself
	// dimmer and redder (the long path through the haze takes the blue out first).
	col += smog_glow * pow(max(cos_sun, 0.0), 14.0) * 0.55 * smog_sun * sun_up * horizon_cut;
	// Only the disc: the clouds stand above the layer and still see the sun's own colour.
	vec3 disc_light = sun_light * mix(vec3(1.0), vec3(1.0, 0.62, 0.42) * 0.55, smog_sun);
	float disc = 1.0 - smoothstep(sun_size * 0.82, sun_size * 1.02, ang);
	// Limb darkening: the edge of the disc is dimmer than the middle.
	float limb = 1.0 - 0.40 * smoothstep(0.5, 1.0, ang / max(sun_size, 1e-4));
	col = mix(col, disc_light * 7.0 * limb, disc * sun_up * horizon_cut);

	// --- Moonlit air --------------------------------------------------------------------------
	// A bright moon lights the whole night sky a little (blue: it is sunlight scattered again),
	// most round itself, which is also what washes the stars out near it.
	float moon_sky = moon_vis * moon_lit * moon_lit;
	float mcos = dot(dir, mdir);
	if (moon_sky > 0.001) {
		float near_moon = pow(max(mcos, 0.0), 12.0);
		col += vec3(0.05, 0.08, 0.16) * moon_light * moon_sky * (0.25 + 1.5 * near_moon)
			* smoothstep(-0.05, 0.1, up);
	}

	// --- Moon ------------------------------------------------------------------------------
	// Its own body: much smaller and sharper than the sun, with the seas people know, craters
	// whose relief shows along the terminator, earthshine on the dark part of a crescent, and a
	// terminator whose shape comes from the real angle between the moon and the sun.
	if (!AT_CUBEMAP_PASS && moon_vis > 0.002) {
		float mang = acos(clamp(mcos, -1.0, 1.0));
		col += moon_tint * exp(-mang * mang * 230.0) * moon_glow * 0.22 * moon_vis
			* (0.15 + 0.85 * moon_lit);
		if (mang < moon_size * 2.0) {
			vec3 mx = normalize(cross(mdir, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
			vec3 my = cross(mx, mdir);
			vec2 duv = vec2(dot(dir - mdir * mcos, mx), dot(dir - mdir * mcos, my)) / max(moon_size, 1e-4);
			float r = length(duv);
			// The limb over a pixel or so, however big the disc is on screen.
			float aa = clamp(pix / max(moon_size, 1e-4) * 1.2, 0.01, 0.2);
			float edge = 1.0 - smoothstep(1.0 - aa, 1.0, r);
			if (edge > 0.001) {
				vec3 face = moon_face(duv);
				// Surface normal of the sphere here, in the moon's frame (z toward the viewer is
				// -1), tilted by the crater relief.
				vec3 n = vec3(duv, -sqrt(max(1.0 - min(r * r, 1.0), 0.0)));
				n = normalize(n + vec3(face.yz * 0.35, 0.0));
				vec3 l = normalize(vec3(dot(sdir, mx), dot(sdir, my), dot(sdir, mdir)));
				// Lommel-Seeliger, not Lambert: the regolith scatters back, so a full moon is
				// as bright at its limb as in the middle instead of a shaded ball.
				float mu0 = max(dot(n, l), 0.0);
				float mu = max(-n.z, 0.05);
				float ls = mu0 / (mu0 + mu) * 2.0;
				ls *= smoothstep(-0.02, 0.06, dot(n, l));
				// The earth lights the dark part, most at a thin crescent.
				float es = earthshine * (1.0 - moon_lit) * (1.0 - smoothstep(-0.05, 0.1, dot(n, l)));
				vec3 moon = moon_tint * face.x * (ls + es) * 1.6;
				col = mix(col, moon, edge * moon_vis);
			}
		}
	}

	// --- Stars and the milky way -------------------------------------------------------------
	if (!AT_CUBEMAP_PASS && stars > 0.002 && up > -0.02) {
		// Fade in through twilight on the sun's own elevation, out again into the horizon's
		// extinction, under the light dome, and round a bright moon.
		float dl = length(dir.xz);
		float az = dl > 1e-4 ? dot(dir.xz / dl, city_dir) : 0.0;
		float lobe = mix(pow(max(az * 0.5 + 0.5, 0.0), 4.0), 1.0, city_wrap);
		float dome = city_glow * lobe * exp(-max(up, 0.0) / 0.18);
		float wash = clamp(1.0 - dome * 9.0, 0.0, 1.0)
			* (1.0 - 0.7 * moon_sky * pow(max(mcos, 0.0), 6.0));
		float fade = smoothstep(0.0, 0.18, up) * stars * (1.0 - sun_up) * wash;
		if (fade > 0.001) {
			// How many stars: a dark site shows thousands, downtown a few dozen. Three layers so
			// the field has no visible grid, the faint ones the first to go.
			float dark = clamp(sky_dark, 0.0, 1.0) * wash;
			vec3 st = star_layer(dir, 180.0, 0.10, 3.1, pix) * 2.2;
			st += star_layer(dir, 420.0, 0.05 + 0.10 * dark, 11.7, pix) * mix(0.35, 1.0, dark);
			st += star_layer(dir, 900.0, 0.12 * dark * dark, 27.3, pix) * 0.6;
			// The galactic band: a wide gaussian about a fixed plane, clumped and cut by dust
			// lanes, with more faint stars in it; only from somewhere properly dark.
			if (milky_way > 0.002 && dark > 0.05) {
				vec3 gal = normalize(vec3(0.62, 0.45, -0.64));
				float gd = dot(dir, gal);
				float band = exp(-gd * gd * 40.0);
				if (band > 0.004) {
					vec3 ga = normalize(cross(gal, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
					vec3 gb = cross(ga, gal);
					vec2 guv = vec2(dot(dir, ga), dot(dir, gb)) * 4.0;
					float clump = vnoise(guv * 2.4) * 0.55 + vnoise(guv * 6.1 + 5.0) * 0.30
						+ vnoise(guv * 15.0 + 2.0) * 0.15;
					float lane = smoothstep(0.28, 0.6, vnoise(vec2(guv.x * 1.7, guv.y * 0.6 + gd * 9.0) + 19.0));
					// The core, brighter toward one end of the band.
					float core = exp(-pow(dot(dir, normalize(cross(gal, ga))) - 0.5, 2.0) * 3.0);
					clump = smoothstep(0.30, 0.86, clump);
					float glowb = band * (0.05 + 0.95 * clump) * (1.0 - 0.75 * lane) * (0.6 + 0.8 * core);
					col += mix(vec3(0.30, 0.34, 0.48), vec3(0.74, 0.68, 0.58), clump)
						* glowb * milky_way * fade * dark * 0.16;
					st += star_layer(dir, 1300.0, 0.25 * band * dark, 41.9, pix) * 0.5;
				}
			}
			col += st * fade;
		}
	}

	// --- Cirrus, contrails and the mid deck ---------------------------------------------------
	if (up > 0.0) {
		if (cloud_detail > 0.5 && cirrus_amount > 0.01) {
			// High cirrus, drifting faster and sheared out by the wind. It is what stops the
			// upper half of the sky being an empty gradient.
			vec2 cuv = dir.xz / (up + 0.05) * 0.95 + vec2(TIME * cloud_speed * 2.6, 0.0);
			float cir = clamp((fbm3(vec2(cuv.x * 0.55, cuv.y * 2.7)) - 0.42) * 3.0, 0.0, 1.0);
			cir *= smoothstep(0.03, 0.34, up) * cirrus_amount * (1.0 - night_factor * 0.85);
			vec3 ccol = cloud_color * 1.04 + sun_light * 0.10;
			// After dark it is a veil lit by the moon and the city, not a white streak.
			ccol = mix(ccol, ccol * night_cloud_light * 0.5 + night_glow, night_factor);
			col = mix(col, ccol, cir * 0.55);
		}
		// Contrails: the high jets' trails, at ten kilometres a straight line in the sky that
		// spreads and fades behind the jet. The sun still lights them for a while after it has
		// left the street, which turns them pink at dusk.
		if (trail_count > 0) {
			float sun_hi = smoothstep(-0.07, 0.0, sdir.y);
			vec3 tl = sun_light * mix(vec3(1.0, 0.6, 0.42), vec3(1.0), smoothstep(-0.03, 0.15, sdir.y));
			vec3 tcol = tl * (0.85 + 0.9 * pow(max(cos_sun, 0.0), 6.0)) * sun_hi
				+ sky_top * 0.6 + sky_horizon * 0.25 + night_glow;
			for (int i = 0; i < 8; i++) {
				if (i >= trail_count) {
					break;
				}
				vec4 a = trail_a[i];
				vec4 b = trail_b[i];
				vec4 c = trail_c[i];
				float tt = rise_t(up, a.y);
				if (tt <= 0.0 || tt > 160.0) {
					continue;
				}
				vec2 pxz = dir.xz * tt - a.xz;
				float s = dot(pxz, b.xy);
				float e = abs(pxz.x * b.y - pxz.y * b.x);
				float foot = tt * pix;
				if (s < -foot * 2.0 || s > a.w) {
					continue;
				}
				float age = max(s, 0.0) / max(b.z, 1e-4);
				float w = 0.012 + c.y * sqrt(age);
				float we = sqrt(w * w + foot * foot);
				// A trail thins out as it spreads: the same water over a wider band.
				float op = exp(-age / max(b.w, 1.0)) * clamp(0.05 / w, 0.1, 1.0) * (w / we);
				// Breaks along it where the air is drier.
				op *= 0.55 + 0.45 * smoothstep(0.2, 0.7, vnoise(vec2(s * 0.45, c.z * 13.0)));
				// The trail starts a few hundred metres behind the jet, where the vapour freezes.
				op *= smoothstep(0.02, 0.25, s);
				float core = exp(-(e * e) / (we * we));
				float tr = clamp(core * op * 0.95, 0.0, 1.0) * smoothstep(0.01, 0.06, up);
				// Haze takes the far ones.
				tr *= exp(-tt / 140.0);
				// Out of the sun after dark, a trail is all but invisible.
				tr *= mix(1.0, 0.12, night_factor * (1.0 - sun_hi));
				col = mix(col, tcol, tr);
				// The jet itself: a glint, drawn no smaller than a pixel.
				if (c.x > 0.0) {
					vec2 hv = pxz;
					float hd = dot(hv, hv);
					float jr = max(foot * 0.8, 0.02);
					col += (tl * 3.0 * sun_hi + vec3(0.08)) * exp(-hd / (jr * jr)) * 0.5 * (0.02 / jr)
						* smoothstep(0.01, 0.06, up);
				}
			}
		}
		if (cloud_detail > 0.5 && mid_amount > 0.01) {
			// A broken altocumulus sheet, higher up and drifting slower than the cumulus.
			float sunlit = 0.5 + 0.5 * sun_up * pow(max(cos_sun, 0.0), 2.0);
			vec2 muv = dir.xz / (up + 0.30) * 1.3
				+ vec2(TIME * cloud_speed * 0.42, TIME * cloud_speed * 0.20);
			float mv = cloud_lo(muv * 1.7 + 41.0);
			float mth = 1.0 - cloud_coverage * 0.75;
			float mden = smoothstep(mth, mth + 0.28, mv) * mid_amount * smoothstep(0.04, 0.34, up);
			vec3 mcol = mix(cloud_shadow * 1.08, cloud_color * 0.98, 0.45 + 0.55 * sunlit);
			mcol = mix(mcol, mcol * night_cloud_light * 1.15 + night_glow, night_factor);
			// Next to the cumulus volume the painted sheet reads as a smear: keep it thin there.
			col = mix(col, mcol, mden * (volume ? 0.2 : 0.70));
		}
	}

	// --- Cumulus ------------------------------------------------------------------------------
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	if (volume) {
		vec4 cl = HALF_RES_COLOR;
		col = col * cl.a + cl.rgb;
	} else
#endif
	if (up > 0.0) {
		float shaft = 0.0;
		vec4 pc = painted_cumulus(dir, sdir, mdir, sun_light, sun_up, moon_vis, ang, cos_sun, airlight, shaft);
		col += sun_light * shaft * 0.38;
		col = mix(col, pc.rgb, pc.a);
	}
	// What reflections and the sky ambient see below the horizon. The drawn sky fades into haze
	// over 27 degrees under it, because from the air that band is far land seen through air. But
	// the radiance map is also what every car door, shop window and puddle mirrors, and what they
	// face below the horizon is the street a few metres away: a warm grey, darker than the sky
	// and not blue. Left as haze, every car side mirrored the pale-blue horizon, and white,
	// silver and even navy cars all read as ice. The band follows the horizon's brightness, so
	// it dims at dusk and at night.
	if (AT_CUBEMAP_PASS) {
		float street = smoothstep(0.0, -reflect_ground_fade, up);
		vec3 ground = reflect_ground * dot(sky_horizon, vec3(0.299, 0.587, 0.114));
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
		if (street_hdri_amount > 0.0) {
			vec2 huv = vec2(atan(dir.x, -dir.z) * 0.1591549 + 0.5 + street_hdri_yaw, acos(clamp(up, -1.0, 1.0)) * 0.3183099);
			vec4 h = textureLod(street_hdri, huv, 1.0);
			vec3 lit = ground * h.rgb * 2.0;
			// Its skyline just over the horizon, then the street under it.
			float stand = h.a * (1.0 - smoothstep(0.0, street_hdri_rise, up)) * step(0.0, up);
			col = mix(col, lit, stand * street_hdri_amount);
			ground = mix(ground, lit, street_hdri_amount);
		}
#endif
		col = mix(col, ground, street);
	}
	col += flash * vec3(0.8, 0.85, 1.0);
	COLOR = col;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	}
#endif
}
