// The far ground's height, shared by everything that has to sit on it.
//
// shaders/macro_ground.gdshader lifts the 14 km ground follower into the basin's mountains from
// a 62 m-a-texel bake of the whole map, then adds zero-mean crags on top. That surface is NOT
// MacroMap.height_at(): the bake is an average over each texel, so a ridge draws lower than the
// real ridge, and the crags move it again by tens of metres either way. Anything placed at the
// real height out there - the far hill planting in Skyline, first of all - floats above the
// ridge line against the sky or sinks into the slope. So the height is computed HERE, once,
// and both the ground and whatever stands on it include this file, which is the only way the
// two can never disagree.
//
// Shader includes use // comments, like any shader file.

// RGB is the ground colour, A is land height / macro_height (exactly 0 on water).
uniform sampler2D macro_tex : filter_linear, source_color;
// The same height as a float (MacroMap.bake_height). The alpha above is 8 bits - 6.3 m a step -
// and every step came out as a contour line across the far ranges; heights come from here, and
// the alpha only still says where the water is (exactly 0).
uniform sampler2D macro_height_tex : filter_linear;
// World XZ the baked image is centred on, and how many metres across it covers.
uniform vec2 macro_centre = vec2(0.0);
uniform float macro_span = 16000.0;
// Metres that alpha 1.0 in the baked map stands for (MacroMap.BAKE_HEIGHT_SCALE). The plane
// lifts its own vertices by this, which is the whole reason the basin reads as a bowl with
// mountains round it instead of a flat field with mountain-coloured paint on it.
uniform float macro_height = 1600.0;
// The lift fades in over this range, so near the player - where the streamed chunks build the
// real ground - the plane stays flat and out of their way.
uniform float lift_start = 500.0;
uniform float lift_end = 1600.0;
// The scene's origin has been shifted this far; local + offset is the true world position.
uniform vec2 world_offset = vec2(0.0);
// Metres of crag the fractal adds on the mountains, on top of the baked shape.
uniform float relief_amplitude = 70.0;
// Wavelength of its first octave, in metres; every octave after is half of it.
uniform float relief_wavelength = 900.0;
// How hard a slope damps the octaves under it, which is what turns noise into eroded land.
uniform float relief_erosion : hint_range(0.0, 4.0) = 1.4;
// Metres of undulation out on the flats, so the basin floor is not a dead level sheet.
uniform float flats_amplitude = 6.0;
// Octaves finer than this many screen pixels fade out instead of aliasing.
uniform float detail_lod : hint_range(0.5, 8.0) = 2.0;
// Where the crags are held down: an ellipse (centre, semi-axes, unit major axis) inside which
// only `calm_keep` of the crag amplitude is drawn, easing back to all of it over `calm_fade` of
// its size. A replica area's hills are shaped to a photograph's skyline (the Palos Verdes crest,
// MacroMap.peninsula_crest), and seventy metres of noise on top put jagged crags where the photo
// has a smooth rolling ridge. Semi-axes of zero turn it off.
uniform vec2 calm_centre = vec2(0.0);
uniform vec2 calm_axes = vec2(0.0);
uniform vec2 calm_dir = vec2(1.0, 0.0);
uniform float calm_keep : hint_range(0.0, 1.0) = 0.2;
uniform float calm_fade = 0.35;


const int MAX_OCTAVES = 10;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}


// Value noise WITH its analytic derivative: .x is the value, .yz is d(value)/d(p). Getting the
// derivative out of the same four corner samples is what makes a proper terrain normal
// affordable - finite-differencing a nine-octave fractal would cost three evaluations of it.
vec3 noised(vec2 x) {
	vec2 i = floor(x);
	vec2 f = x - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k3 = a - b - c + d;
	return vec3(a + k1 * u.x + k2 * u.y + k3 * u.x * u.y,
		du.x * (k1 + k3 * u.y),
		du.y * (k2 + k3 * u.x));
}


// Ridged, erosion-damped fractal with analytic derivatives, in world metres. .x is roughly
// 0..1, .yz is d(value)/d(metre). `fp` is how many metres one screen pixel covers here:
// octaves finer than `detail_lod` pixels fade out instead of aliasing, and the running total is
// normalised against ALL the octaves rather than the ones that survived, so the coarse shape
// does not change as the camera moves and the hills do not swim.
vec3 relief_fbm(vec2 p, int octaves, float fp) {
	float f = 1.0 / relief_wavelength;
	float wl = relief_wavelength;
	float amp = 1.0;
	float sum = 0.0;
	vec2 dsum = vec2(0.0);
	// Sum of the whole amplitude series, so dropping fine octaves cannot change the coarse shape.
	float norm = 2.0 * (1.0 - pow(0.5, float(octaves)));
	mat2 rot = mat2(vec2(0.86, 0.51), vec2(-0.51, 0.86));
	mat2 acc = mat2(vec2(f, 0.0), vec2(0.0, f));
	vec2 q = p * f;
	for (int i = 0; i < MAX_OCTAVES; i++) {
		if (i >= octaves) {
			break;
		}
		float lod = smoothstep(detail_lod, detail_lod * 3.0, wl / max(fp, 0.0005));
		if (lod <= 0.001) {
			break;
		}
		vec3 n = noised(q);
		float v = n.x * 2.0 - 1.0;
		float r = 1.0 - abs(v);
		vec2 dr = (-sign(v) * 2.0) * (n.yz * acc);
		// Erosion: damp this octave wherever the slope built up so far is already steep. The
		// gradient is per metre, so scaling by the wavelength makes the test dimensionless.
		float damp = 1.0 / (1.0 + relief_erosion * dot(dsum, dsum) * wl * wl);
		float k = amp * lod * damp;
		sum += k * r;
		dsum += k * dr;
		amp *= 0.5;
		wl *= 0.5;
		q = (rot * q) * 2.03;
		acc = (rot * acc) * 2.03;
	}
	return vec3(sum, dsum) / norm;
}


// The baked map, reconstructed smoothly. The hardware's bilinear filter is only C0, so every
// 62 m texel came out as a flat facet with a crease round it and the derivative of the height
// was a staircase. Interpolating the same four texels with smoothstep weights is C1, and the
// same weights differentiate analytically, which is where the macro half of the normal comes
// from. Returns the colour in .rgb and the height (0..1) in .a; `grad` gets d(height)/d(metre).
vec4 macro_sample(vec2 uv, out vec2 grad) {
	vec2 ts = vec2(textureSize(macro_tex, 0));
	vec2 t = uv * ts - vec2(0.5);
	vec2 i = floor(t);
	vec2 f = t - i;
	vec2 wt = f * f * (3.0 - 2.0 * f);
	vec2 dw = 6.0 * f * (1.0 - f);
	ivec2 hi = ivec2(ts) - ivec2(1);
	ivec2 b = ivec2(i);
	ivec2 b10 = clamp(b + ivec2(1, 0), ivec2(0), hi);
	ivec2 b01 = clamp(b + ivec2(0, 1), ivec2(0), hi);
	ivec2 b11 = clamp(b + ivec2(1, 1), ivec2(0), hi);
	b = clamp(b, ivec2(0), hi);
	vec4 c00 = vec4(texelFetch(macro_tex, b, 0).rgb, texelFetch(macro_height_tex, b, 0).r);
	vec4 c10 = vec4(texelFetch(macro_tex, b10, 0).rgb, texelFetch(macro_height_tex, b10, 0).r);
	vec4 c01 = vec4(texelFetch(macro_tex, b01, 0).rgb, texelFetch(macro_height_tex, b01, 0).r);
	vec4 c11 = vec4(texelFetch(macro_tex, b11, 0).rgb, texelFetch(macro_height_tex, b11, 0).r);
	float k1 = c10.a - c00.a;
	float k2 = c01.a - c00.a;
	float k3 = c00.a - c10.a - c01.a + c11.a;
	vec2 mpt = vec2(macro_span) / ts;
	grad = vec2(dw.x * (k1 + k3 * wt.y), dw.y * (k2 + k3 * wt.x)) / mpt;
	return mix(mix(c00, c10, wt.x), mix(c01, c11, wt.x), wt.y);
}


vec2 macro_uv(vec2 w) {
	return (w - macro_centre) / macro_span + vec2(0.5);
}


// 1 outside the calm ellipse, calm_keep inside it (see the uniforms).
float crag_calm(vec2 w) {
	if (calm_axes.x <= 0.0 || calm_axes.y <= 0.0) {
		return 1.0;
	}
	vec2 q = w - calm_centre;
	vec2 minor = vec2(-calm_dir.y, calm_dir.x);
	float r = length(vec2(dot(q, calm_dir) / calm_axes.x, dot(q, minor) / calm_axes.y));
	return mix(calm_keep, 1.0, smoothstep(1.0, 1.0 + calm_fade, r));
}


// How much synthesized relief belongs at this point, in metres: crags on the mountains, a few
// metres of undulation out on the flat. It keys off the SLOPE of the baked map, never off how
// high the ground is: the inland valley is a city floor 130 metres up, so anything that reads
// height as mountain puts fifty metres of rock lumps through the middle of it - and through the
// normal, which then tells `built_amount` the blocks are on a hillside and the city stops being
// drawn at all. Steepness is also simply what tells a range from a plain at this resolution.
float relief_scale(vec2 w, float baked, vec2 macro_grad) {
	float sm = length(macro_grad) * macro_height;
	return flats_amplitude + relief_amplitude * smoothstep(0.05, 0.28, sm) * crag_calm(w);
}


// The ground follower's lift over world point `wp` (the plane's own, unlifted vertex position)
// seen from `cam`: the baked land plus the crags. Not the urban lift - that needs built_amount(),
// which stays in macro_ground.gdshader because the smoke test reads its thresholds from there -
// and not the sink (far_ground_sink). `m` is the baked sample, `mg` its gradient per metre,
// `wet` 1 over water, `d` the distance to the camera.
float far_ground_lift(vec3 wp, vec3 cam, out vec4 m, out vec2 mg, out float wet, out float d) {
	vec2 w = wp.xz + world_offset;
	mg = vec2(0.0);
	m = macro_sample(macro_uv(w), mg);
	float baked = m.a;
	// Drop the plane right out from under the sea. The water chunks put their surface 15 cm
	// above it and their troughs a metre or more BELOW it, so this plane kept drawing through
	// the waves in smooth grey patches, and a kilometre out the 15 cm is below depth precision
	// and the two z-fight as well. Wherever the baked map says water (alpha exactly zero), the
	// plane goes 24 m down, which is under the deepest storm trough. Over land it does not
	// move, so the coast keeps its shape.
	wet = 1.0 - step(0.0005, baked);
	d = distance(wp, cam);

	// Stand the land up, everywhere, not just in the distance. Fading the lift in with distance
	// works only while the ground the player is on is at sea level: over the inland valley, which
	// is a city 130 m up, it left this plane down at zero and the valley was ringed by a grey
	// wall where the plane's surface cut across the hillsides.
	float lift = baked * macro_height;
	// The crags. The mesh is 70 m a vertex, so only the coarse end of the fractal can move
	// geometry at all - asking for detail finer than that just aliases, and the rest of it comes
	// back in the fragment shader as a normal, which is what really lights a mountain. Faded in
	// with distance, because near the camera the streamed chunks are the ground and this has to
	// stay smoothly beneath them rather than poking crags through them.
	float far = smoothstep(lift_start, lift_end, d);
	if (far > 0.002) {
		// Zero-mean, or the crags would also RAISE every range by half their amplitude, and the
		// step from flat to cragged would put a sixty-metre cliff along the foot of each one.
		lift += relief_scale(w, baked, mg) * (relief_fbm(w, 4, 150.0).x - 0.5) * far * (1.0 - wet);
	}
	return lift;
}


// Sink. The bake is one texel per 62 m, so close up it can read tens of metres above the real
// ground; drop the plane well under the streamed chunks near the camera and ease back to a few
// centimetres of clearance out where it is the ground itself. The whole transition happens
// inside the streamed radius, so the step never shows.
float far_ground_sink(float d, float wet) {
	float near = 1.0 - smoothstep(300.0, 900.0, d);
	return wet * 24.0 + (1.0 - wet) * (near * 30.0 + 5.0);
}
