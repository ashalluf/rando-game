// The downtown skyline's glass by day (fleet "skyline-glass-day", wave 3): what a curtain wall
// mirrors from 100-600 m - the freeway, the street looking up, a helicopter - is most of what a
// skyline IS, and it used to mirror one fixed noon gradient at every hour, the same in every pane.
// Here, shared by the near walls (building.gdshader), the far boxes (building_lod.gdshader) and the
// lit crowns (tower_crown.gdshader):
//   - the sky of THIS hour (sg_sky_ratio(): the hue of DayNight's own zenith and horizon at the old
//     constants' brightness, warm toward a low sun), so a tower at 17:30 mirrors a golden sky;
//   - the clouds in it (sg_clouds(): a cloud deck projected on the reflected ray, coverage from
//     DayNight), which is what breaks a mirror-glass face into light and dark at a distance;
//   - the real neighbouring towers (sg_towers(): up to eight boxes SkylineGlass picks round the
//     camera - LandmarkDowntown's towers and the tall Buildings near it - each traced as a box with
//     its own glass, floors and mullions, sunlit side, roof and haze), so towers mirror each other
//     with true parallax;
//   - the sun's glint in a pane (sg_glint(), emitted, broken pane by pane by the bow).
// Everything reads the globals SkylineGlass (scripts/world/skyline_glass.gd) pushes; their
// defaults in project.godot are the old look's sky with nothing traced, so a tool with no
// SkylineGlass still draws the glass sensibly. skyline_glass.x 0 (SKYLINE_GLASS=0) is the A/B.
// The includer declares `global uniform vec3 sun_direction;`, `global uniform vec3 origin_shift;`
// and `global uniform float night_factor;` before this file. Shader includes use // comments.

// x on (0 / 1), y cloud coverage (0..1), z the sun's glint gain (0 at night, under overcast),
// w golden hour (DayNight.golden).
global uniform vec4 skyline_glass;
// The sky's zenith and horizon as DayNight sets them on the sky (display numbers, raw on both
// renderers); top.w the sunward glow on the horizon (a low sun), rim.w the light on the clouds.
global uniform vec4 skyline_sky_top;
global uniform vec4 skyline_sky_rim;
// Up to eight boxes: (centre x, centre z in TRUE world, the half sizes packed as
// round(hx * 4) + round(hz * 4) * 1024, top y in true world); a top under -1000 is no box.
global uniform mat4 skyline_towers_a;
global uniform mat4 skyline_towers_b;

// What the old glass mirrored, in display numbers: the sky ratios are taken against these.
const vec3 SG_OLD_TOP = vec3(0.26, 0.44, 0.80);
const vec3 SG_OLD_RIM = vec3(0.42, 0.47, 0.55);


bool sg_on() {
	return skyline_glass.x > 0.5;
}


// A colour written as display (sRGB) numbers, in the renderer's own space: decoded on Forward+,
// as it is on Compatibility (facade_variety's fx_srgb_in(), color_space's cs_as_uniform()).
vec3 sg_srgb_in(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
#endif
}


float sg_luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}


// The hue of `c` at the luminance `target` (display numbers), a fifth of the way to grey: the
// glass's own tint and the haze in front of it take some of the colour out.
vec3 sg_hue(vec3 c, float target) {
	vec3 h = c * (target / max(sg_luma(c), 0.03));
	return clamp(mix(vec3(target), h, 0.8), vec3(0.0), vec3(1.0));
}


// The sky this hour, as a multiplier on what the glass mirrored before (renderer space): the old
// gradient times this is the new one, so a material's own sky tint (the arena district's) and the
// old brightness over the day (sky_now) are kept and only the hue follows DayNight. Toward a low
// sun the horizon warms (skyline_sky_top.w).
vec3 sg_sky_ratio(vec3 refl, vec3 sun) {
	float k = smoothstep(0.0, 0.55, refl.y);
	vec3 now = mix(sg_hue(skyline_sky_rim.rgb, sg_luma(SG_OLD_RIM)), sg_hue(skyline_sky_top.rgb, sg_luma(SG_OLD_TOP)), k);
	vec2 rh = refl.xz / max(length(refl.xz), 1e-4);
	vec2 sh = sun.xz / max(length(sun.xz), 1e-4);
	// A low sun lights a wide fan of the sky round it, not a spot: the golden-hour glass on the
	// faces turned toward the sun is that glow (a hot core near the sun, a broad warm fan to ~70
	// degrees either side), and it dies off with height over the horizon.
	float az = max(dot(rh, sh), 0.0);
	float lowk = 1.0 - smoothstep(0.0, 0.5, refl.y);
	float side = (pow(az, 1.6) * 0.75 + pow(az, 12.0) * 0.45) * lowk * skyline_sky_top.w;
	now += vec3(0.40, 0.21, 0.06) * side;
	vec3 old = mix(SG_OLD_RIM, SG_OLD_TOP, k);
	return sg_srgb_in(now) / max(sg_srgb_in(old), vec3(1e-3));
}


float sg_hash2(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}


float sg_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = sg_hash2(i);
	float b = sg_hash2(i + vec2(1.0, 0.0));
	float c = sg_hash2(i + vec2(0.0, 1.0));
	float d = sg_hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}


// The cloud deck in the glass: the reflected ray meets a plane over the city (in units of its
// height, so it needs no position), three octaves of cumulus whose share is DayNight's coverage,
// thinned to haze near the horizon, lit on top (warm at golden hour), grey underneath. `time` is
// the shader's TIME (the deck drifts). Returns the sky with the clouds over it (renderer space).
vec3 sg_clouds(vec3 refl, vec3 sky, float time) {
	float cov = skyline_glass.y;
	if (refl.y < 0.012 || cov < 0.02) {
		return sky;
	}
	vec2 p = refl.xz / (refl.y + 0.05) * 1.7 + vec2(time * 0.0035, time * 0.0012);
	float n = sg_noise(p) * 0.58 + sg_noise(p * 2.37 + 5.3) * 0.28 + sg_noise(p * 5.11 + 1.7) * 0.14;
	float d = smoothstep(1.0 - cov - 0.10, 1.0 - cov + 0.22, n);
	d *= smoothstep(0.012, 0.16, refl.y);
	// A puff's top catches the sun; its body is grey. Display numbers, then the renderer's space.
	float top = smoothstep(0.45, 0.85, n);
	vec3 lit = mix(vec3(0.86, 0.87, 0.88), vec3(0.95, 0.72, 0.50), skyline_glass.w);
	vec3 base = sg_hue(skyline_sky_rim.rgb, 0.42) * vec3(0.92, 0.94, 1.0);
	vec3 cloud = sg_srgb_in(mix(base, lit, top) * skyline_sky_rim.w);
	if (skyline_glass.x > 1.5) {
		cloud = vec3(0.0, 3.0, 0.0);
	}
	return mix(sky, cloud, d * 0.8);
}


// The towers round the camera, traced: `o` the TRUE world point on the glass, `d` the reflected
// ray, `px` metres a pixel spans on the glass, `cam_d` the distance to the camera, `sky` what is
// behind (for the haze), `sun` the sun. Returns the colour (renderer space) and in .a 1 where a
// tower was hit; `t_hit` how far. A box the ray starts inside is the wall's own tower (skipped).
vec4 sg_towers(vec3 o, vec3 d, float px, float cam_d, vec3 sky, vec3 sun, out float t_hit) {
	t_hit = 1e9;
	int hit_i = -1;
	int hit_kind = 0;
	vec4 hit_tw = vec4(0.0);
	vec2 hit_half = vec2(0.0);
	vec2 inv = vec2(abs(d.x) > 1e-5 ? 1.0 / d.x : 1e5, abs(d.z) > 1e-5 ? 1.0 / d.z : 1e5);
	for (int i = 0; i < 8; i++) {
		vec4 tw = i < 4 ? skyline_towers_a[i] : skyline_towers_b[i - 4];
		if (tw.w < -1000.0) {
			continue;
		}
		float hz4 = floor(tw.z / 1024.0);
		vec2 half_ = vec2(tw.z - hz4 * 1024.0, hz4) * 0.25;
		vec2 lo = tw.xy - half_;
		vec2 hi = tw.xy + half_;
		if (all(greaterThan(o.xz, lo - 0.6)) && all(lessThan(o.xz, hi + 0.6)) && o.y < tw.w + 0.5) {
			continue;
		}
		vec2 t0 = (lo - o.xz) * inv;
		vec2 t1 = (hi - o.xz) * inv;
		vec2 tn = min(t0, t1);
		vec2 tf = max(t0, t1);
		float te = max(tn.x, tn.y);
		float tx = min(tf.x, tf.y);
		if (tx < max(te, 0.5) || te > t_hit) {
			continue;
		}
		float ye = o.y + d.y * te;
		if (te > 0.5 && ye <= tw.w) {
			t_hit = te;
			hit_i = i;
			hit_kind = tn.x > tn.y ? 0 : 1;
			hit_tw = tw;
			hit_half = half_;
		} else if (d.y < 0.0) {
			float tr = (tw.w - o.y) / d.y;
			if (tr >= max(te, 0.5) && tr <= tx && tr < t_hit) {
				t_hit = tr;
				hit_i = i;
				hit_kind = 2;
				hit_tw = tw;
				hit_half = half_;
			}
		}
	}
	if (hit_i < 0) {
		return vec4(sky, 0.0);
	}
	vec3 p = o + d * t_hit;
	// Its look from where it stands (stable whichever slot it is in): glass and a stone parapet.
	float k = sg_hash2(floor(hit_tw.xy * 0.25));
	float k2 = sg_hash2(floor(hit_tw.xy * 0.25) + 17.0);
	vec3 glass = k < 0.3 ? vec3(0.12, 0.15, 0.19) : (k < 0.55 ? vec3(0.11, 0.15, 0.14) : (k < 0.75 ? vec3(0.16, 0.13, 0.10) : vec3(0.21, 0.22, 0.24)));
	vec3 rim = sg_hue(skyline_sky_rim.rgb, 0.469);
	float day = 1.0 - night_factor;
	vec3 col;
	if (hit_kind == 2) {
		// A roof: membrane and plant, lit from above.
		float plant = step(0.55, sg_noise((p.xz - hit_tw.xy) * 0.35 + k * 9.0));
		col = vec3(0.34, 0.33, 0.31) * (0.55 + 0.45 * max(sun.y, 0.0) * day) * (1.0 - 0.3 * plant);
	} else {
		vec3 n = hit_kind == 0 ? vec3(-sign(d.x), 0.0, 0.0) : vec3(0.0, 0.0, -sign(d.z));
		float along = hit_kind == 0 ? p.z : p.x;
		float cosv = abs(hit_kind == 0 ? d.x : d.z);
		// Its own mirror of the sky, a mirror at a glancing angle, and the sun on its face.
		float fres = pow(1.0 - clamp(cosv, 0.0, 1.0), 3.0);
		col = glass + rim * (0.30 + 0.45 * fres);
		col += vec3(0.20, 0.18, 0.15) * max(dot(n, sun), 0.0) * day * (1.0 - 0.6 * fres);
		// Floors (a spandrel band) and mullions, at their average once under a couple of pixels
		// (the pixel at the hit is the glass's pixel grown by how much further the ray went).
		float storey = 3.8 + 0.6 * k2;
		float bay = 1.5 + 0.3 * k;
		float fp = px * (cam_d + t_hit) / max(cam_d, 1.0);
		float sharp = 1.0 - smoothstep(0.35, 1.0, fp / bay);
		float band = step(0.80, fract((p.y - 0.25) / storey));
		float mull = step(0.90, fract(along / bay));
		float pattern = mix(0.20 * 0.9 + 0.10 * 0.4, max(band * 0.9, mull * 0.4), sharp);
		vec3 member = mix(glass * 1.6 + vec3(0.04), vec3(0.30, 0.30, 0.29), k2);
		col = mix(col, member, pattern);
		// The parapet: a lighter band at the top.
		col = mix(col, vec3(0.42, 0.41, 0.39) * (0.6 + 0.4 * day), step(hit_tw.w - 2.2, p.y) * 0.8);
	}
	col = sg_srgb_in(col * (0.2 + 0.8 * day));
	// The air between: the further tower is the hazier one.
	col = mix(col, sky, 1.0 - exp(-t_hit / 1900.0));
	// SKYLINE_GLASS_DEBUG=1 (x 2): a traced tower is magenta.
	if (skyline_glass.x > 1.5) {
		col = vec3(4.0, 0.0, 4.0);
	}
	return vec4(col, 1.0);
}


// The sun in a pane (emitted, renderer space): a hot core where the reflected ray meets the sun's
// disc - wider than the sun, glass is never optically flat - and a halo, warm at golden hour.
// The caller zeroes it where a tower or the street opposite is in the way.
vec3 sg_glint(vec3 refl, vec3 sun) {
	float c = dot(refl, sun);
	if (c < 0.97 || sun.y < -0.02) {
		return vec3(0.0);
	}
	float core = smoothstep(0.99955, 0.99990, c);
	float halo = pow(max((c - 0.97) / 0.03, 0.0), 6.0) * 0.12;
	vec3 col = mix(vec3(1.0, 0.95, 0.86), vec3(1.0, 0.66, 0.34), skyline_glass.w);
	return sg_srgb_in(col) * (core * 5.0 + halo) * skyline_glass.z * smoothstep(-0.02, 0.06, sun.y);
}


// How much a pane mirrors head on and at a glancing angle (Schlick's ends). A curtain wall's
// (or a glass tower's ribbon band's) coated glass mirrors far more than a punched window's plain pane: at the old 26 % head on a
// glass tower from 300 m was the dark room behind it, a grid of near-black panels; reflective
// coatings run 30-45 %. Everything else keeps the old numbers.
vec2 sg_mirror_ends(bool curtain) {
	return (sg_on() && curtain) ? vec2(0.42, 0.95) : vec2(0.26, 0.90);
}


// A line `w` wide every `pitch` from 0 (at x = 0 .. w), box filtered over a pixel `f` wide: its
// coverage of the pixel. For the curtain wall's frame lines at a distance.
float sg_line(float x, float f, float pitch, float w) {
	float base = floor(x / pitch) * pitch;
	float cov = 0.0;
	for (int k = -1; k <= 1; k++) {
		float a = base + float(k) * pitch;
		float lo = max(x - 0.5 * f, a);
		float hi = min(x + 0.5 * f, a + w);
		cov += clamp((hi - lo) / max(f, 1e-4), 0.0, 1.0);
	}
	return mix(min(cov, 1.0), w / max(pitch, 1e-4), smoothstep(0.5 * pitch, pitch, f));
}
