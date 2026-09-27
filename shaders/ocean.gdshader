shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Ocean: Gerstner swells in the vertex shader (five wind swells in wave groups, plus one
// tsunami-scale wave), shoaling and a breaking surf line where the water meets the sand, foam
// where the surface folds, sub-surface glow through backlit wave faces, a fresnel sky reflection
// and a broken glitter path to the sun. Runs on the web renderer too (no depth texture, no
// screen texture, no SSR).
//
// ---------------------------------------------------------------------------------------------
// THE HAND-OVER TO THE FAR SEA - read this before touching any colour in here.
//
// The streamed ocean chunks only reach about 500-800 m from the player. Past that the whole sea
// is one thing: the ground follower, shaded by `shaders/macro_ground.gdshader` from MacroMap's
// baked image. So this shader draws a square of water in the middle of a much larger sea drawn
// by somebody else, and any difference between the two is a hard-edged RECTANGLE around the
// player. It was a glaring one, and for two separate reasons:
//
//   1. Colour space. The bake is an RGBA8 image sampled through `source_color`, so MacroMap's
//      BAKE_OCEAN_DEEP = (0.014, 0.034, 0.062) reaches the far shader DECODED from sRGB, as
//      linear (0.0011, 0.0026, 0.0051) - near black, which is what deep water looked down on
//      actually is. A `source_color` uniform DEFAULT written in shader source gets no such
//      decode: it is used verbatim as linear (verified with
//      RenderingServer.shader_get_parameter_default). The old deep_color = (0.008, 0.042, 0.080)
//      was therefore seven to sixteen times brighter than the same colour on the far plane. The
//      colours below are written in LINEAR and the source_color hints are gone, so what is
//      written is what is used.
//   2. Lighting mode. Beyond `near_fade_end * 1.8` the far plane stops being a surface and is
//      EMITTED at face value, so the renderer's sun and ambient do not touch it. This shader's
//      water went through ALBEDO and was lit. Same colour, two different exposures.
//
// So past `handover_start` this shader cross-fades to the far plane's own water formula and to
// its ALBEDO/EMISSION split, and is fully painted by `handover_end` - which has to stay inside
// the nearest possible chunk edge (7 blocks of 70 m plus roads, so about 570 m).
// ---------------------------------------------------------------------------------------------
//
// wave_scale is a shader global the Weather node drives (1 calm, 6 storm); tsunami_scale is a
// second global for the big one (0 off, 1 a 30 m wall); wind_factor is the same wind the grass
// and the palms bend to, and it drives the chop and the spray; ground_detail is the one Quality
// clears on the web and below MEDIUM, and it gates the extra noise fetches.
global uniform float wave_scale;
global uniform float tsunami_scale;
global uniform float wind_factor;
global uniform float ground_detail;
// Published by DayNight: the colour the sky meets the horizon with, and the direction back
// toward the sun. Water is mostly the sky seen in it, and without this the sea was a flat
// blue-green field whatever the hour.
global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform float night_factor;

// --- Colour (LINEAR, not sRGB - see the hand-over note above) --------------------------------
// The open sea, and the shelf. These two are MacroMap.BAKE_OCEAN_DEEP and BAKE_OCEAN_SHALLOW
// decoded from sRGB, so this shader and the far plane agree on the water by construction.
uniform vec3 deep_color = vec3(0.00108, 0.00263, 0.00511);
uniform vec3 shelf_color = vec3(0.00350, 0.01436, 0.02078);
// MacroMap.BAKE_SURF, likewise decoded: the broken water the bake paints over its last 95 m.
uniform vec3 bake_surf_color = vec3(0.0947, 0.1627, 0.1707);
// The last few tens of metres, over pale sand: sunlight reaches the bottom and comes back green.
// This is the one colour in here with no counterpart on the far plane, because at 62 m a texel
// the bake cannot resolve a shelf this narrow - and it is the colour that makes a coastline read
// as a coastline.
// sRGB (0.26, 0.43, 0.40). The old (0.030, 0.076, 0.068) was sRGB (0.19, 0.31, 0.29), 2-3x under
// bake_surf_color above - and that is this shader's own colour for very nearly the same water.
// The far branch paints it over the last bake_surf_width = 95 m offshore against this one's
// shore_reach = 105 m, and because detail is 1.0 - painted the two cross-fade in the SAME pixel
// across handover_start..handover_end: at the waterline the far branch's water term reaches
// (0.081, 0.140, 0.148) while the near one was (0.030, 0.076, 0.068), so the shore band changed
// colour as the camera backed away from it. It was dark against the sand it laps too - Ground054
// is linear (0.333, 0.259, 0.156) mean, times the pbr tint (1.0, 0.888, 0.687) and the wet
// SAND_TONES[1] 0.56 that is green 0.129 against the water's 0.076. Red stays the lowest channel,
// which is the absorption that makes shallow water read turquoise rather than blue.
uniform vec3 shore_color = vec3(0.055, 0.155, 0.132);
// How far out the sand still tints the water.
uniform float shore_reach = 105.0;
uniform vec3 foam_color = vec3(0.72, 0.78, 0.82);
// Light that has travelled through a thin wave face. Water is a filter, not a mirror: this is
// what makes a swell glow when the sun is behind it.
uniform vec3 sss_color = vec3(0.016, 0.115, 0.082);
// The horizon colour a full storm brings the sky down to: DayNight's own storm_horizon
// Color(0.30, 0.31, 0.34), decoded from sRGB so it matches the one the sky and the far plane use.
uniform vec3 storm_horizon = vec3(0.0732, 0.0782, 0.0953);
// How dark the weather is (0 clear, 1 storm), pushed in by Weather. DayNight publishes the
// *clear* horizon colour as sky_tint whatever the weather, so without this the sea went on
// reflecting a bright blue sky from under a black storm, which is the loudest possible tell
// that water is painted rather than lit.
uniform float weather_dark : hint_range(0.0, 1.0) = 0.0;

// --- Waves -----------------------------------------------------------------------------------
uniform float base_height = 1.2;
// Metres across the longest wind swell. The other four are this over 1.59, 2.62, 4.51 and 7.89 -
// deliberately not whole-number ratios, so the five of them do not come back into step inside
// any distance you can see from the air. That, and the wave groups below, is what stops the open
// sea reading as one tile repeated.
uniform float swell_length = 97.0;
// Wave groups: the long, slow swell in the swell that makes crests arrive in sets of three or
// four with flat water between them. A real sea has them and a sum of sines does not, and from
// the air it is the single loudest difference. Metres across one group, and how deeply the
// groups cut the wave height (0 off, 1 the flat water between sets goes glassy).
uniform float group_length = 310.0;
uniform float group_depth : hint_range(0.0, 1.0) = 0.55;
uniform float speed = 1.0;
uniform float tsunami_height = 30.0;
uniform float tsunami_length = 420.0;
uniform vec2 tsunami_dir = vec2(1.0, 0.15);

// --- The shoreline ---------------------------------------------------------------------------
// The shader has to know where the sand is to break waves on it, so Weather copies MacroMap's
// coast numbers in every time they change (Weather._push_ocean_shape()); the defaults here are
// MacroMap's own, so the surf lands in the right place even if nothing sets them. world_offset
// is the scene's origin shift: local + offset is the true world position, and the coast is
// written in true world coordinates.
uniform vec2 world_offset = vec2(0.0);
uniform float coast_base_x = -900.0;
uniform float coast_wobble = 180.0;
uniform float coast_period = 700.0;
// The Palos Verdes headland, an ellipse (MacroMap.peninsula_*): centre, semi-axes, and the
// compass bearing of its major axis in degrees.
uniform vec2 peninsula_center = vec2(-100.0, 5700.0);
uniform float peninsula_axis_a = 2800.0;
uniform float peninsula_axis_b = 1250.0;
uniform float peninsula_bearing = 100.0;
uniform float bay_z = 6300.0;
uniform float bay_east_x = 4700.0;
// The replica's authored waterline (ReplicaAreas.waterline_table(), Redondo pier to Malaga
// Cove): COAST_TABLE samples of x from coast_table_z0, coast_table_dz apart, eased onto the
// basin's sine over coast_table_blend metres north of it. coast_table_dz 0 means no table.
const int COAST_TABLE = 64;
uniform float coast_table[64];
uniform float coast_table_z0 = 0.0;
uniform float coast_table_dz = 0.0;
uniform float coast_table_blend = 300.0;
// Width of the surf zone: how far out a swell starts to feel the bottom and stand up.
uniform float surf_width = 72.0;
// How far up the sand the wash runs, and how fast it goes up and back.
uniform float swash_width = 14.0;
uniform float swash_period = 9.0;
// Wind direction on the water (Weather sets it from its own rain wind).
uniform vec2 wind_dir = vec2(1.0, 0.3);

// --- Surface response --------------------------------------------------------------------
// Reflectance of water at normal incidence. 0.02 is the real number; everything above it is
// fresnel, which is why water is nearly black underfoot and a mirror at the horizon.
uniform float water_f0 = 0.02;
// Ceiling on the fresnel mix. The far plane clamps its own to 0.92; matching it keeps the
// horizon from being two different mirrors either side of the hand-over.
uniform float fresnel_cap : hint_range(0.0, 1.0) = 0.92;
// Brightness of the glitter path to the sun, and how tight one sparkle is. High exponents plus
// the fine chop below are what break the path into separate points of light instead of one
// smooth blob of bloom.
uniform float glitter = 1.6;
uniform float glitter_sharp = 620.0;
// Fine chop folded into the shading normal: the centimetre-scale ripple the mesh is far too
// coarse to carry. Without it the faces of the big swells are flat sheets of sky colour, and the
// fresnel at a grazing angle runs to 1 over the whole sea at once. Faded out with distance,
// where it turned the sea into crumpled foil.
// From eye level you are ALWAYS looking along the water at a few degrees, so the only thing
// that keeps the sea from being a mirror down there is a surface slope of the same order as the
// view angle. At 0.55 there was not one: the sea from the sand was a flat sheet of sky with the
// horizon painted on it.
uniform float chop_strength = 1.5;
uniform float chop_fade = 260.0;
// Metres across the coarse ripple, and the height of the coarse and the fine one. These are
// NOISE, not crossed sines: sines lay a perfectly regular lattice of highlights over the water
// and from a few metres up that lattice was the loudest "this is one tile" tell in the frame.
uniform float ripple_size = 2.6;
uniform float ripple_height = 0.30;
uniform float ripple_fine_height = 0.055;
// Ripple LOD, in metres from the camera. A wave that is a pixel across cannot be drawn, only
// aliased: past this the short swells are faded out of the GEOMETRY, which is the only place the
// shimmer can be cured, and the long ones carry the shape on alone. It is also what the far
// plane does with its own swell normal, so the two agree about how smooth the sea gets.
uniform vec2 fine_fade = vec2(170.0, 480.0);
// Foam. `fold` is how hard the Gerstner displacement is pinching the surface together - the
// crest of a wave about to break - which is where foam is actually made. Below `foam_fold_lo`
// there is none; by `foam_fold_hi` the crest is white.
// These thresholds are derived, not picked. For one Gerstner wave the horizontal Jacobian
// collapses exactly - jac = 1 - lean*amp*k*cos(phase) - so `fold` is the sum of the five waves'
// lean*amp*k, and those five coefficients add to 0.1548 per metre of `amp`. `lean_k` above is
// 1.6/open, which cancels `open`, so lean_k*amp is pinned at 1.2 m when it is clear and at
// 1.6 m from overcast right through to rain: `fold` cannot pass 0.186 / 0.248, and only the
// 2.52 m of a storm takes it to 0.390. Sampled over 1.2 km of open sea its 99th percentile is
// 0.107 clear, 0.142 overcast and rain, 0.224 in a storm, so at the old 0.16 floor the
// smoothstep never left zero: peak foam alpha was 0.01 when it was clear, and coverage above a
// quarter opacity was 0.00% at every state except the storm, where it was 0.2%. The sea had no
// whitecaps at all. 0.05 / 0.20 sits on that measured distribution instead: 1.3% of the open
// sea foams when it is clear (never past 0.33 alpha there, because `foam` is multiplied by
// `sea`), 7.8% overcast, 10% raining and 21% in a storm, half of that fully white.
uniform float foam_fold_lo : hint_range(0.0, 1.0) = 0.05;
uniform float foam_fold_hi : hint_range(0.0, 1.0) = 0.20;

// --- The hand-over to the far sea --------------------------------------------------------
// Where this shader starts turning into `macro_ground.gdshader`'s water, and where it has
// finished. handover_end must stay below the nearest possible streamed chunk edge (about 570 m)
// or there is a ring of un-handed-over water left at the seam.
uniform float handover_start = 230.0;
uniform float handover_end = 470.0;
// The far plane's own numbers, so the two agree: the shelf-to-deep ramp of the bake
// (MacroMap.bake(), offshore / 600), its surf band (BAKE_SURF_WIDTH), and macro_ground's
// sea_glitter and its ROUGHNESS / SPECULAR over water.
uniform float bake_deep_reach = 600.0;
uniform float bake_surf_width = 95.0;
uniform float far_glitter = 1.6;
uniform float far_roughness = 0.415;
uniform float far_specular = 0.55;
// macro_ground's sea_swell, its pixel_angle, and its cloud-shadow numbers. The far sea's
// sparkle is a noise normal at this scale faded out as one swell drops under a pixel, and its
// brightness is cut where a cloud is over it. Reproducing all of it exactly - same noise, same
// world coordinates, same phase - is the only way the speckle field runs across the seam
// unbroken; approximating it leaves the rectangle there in texture instead of in colour.
uniform float far_swell = 46.0;
uniform float far_pixel_angle = 0.0016;
uniform float cloud_shadow_strength : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_scale = 1500.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.52;
uniform float cloud_height = 900.0;
uniform float cloud_speed = 7.0;

varying float crest;
varying float fold;
varying float shore;
varying float offshore;
varying vec3 world_pos;
varying vec3 world_normal;


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


// Value noise with analytic derivatives, and the cloud shadow over a point: both exactly as
// macro_ground.gdshader has them, because the far sea's surface and its shading are built out
// of them and the two have to agree across the hand-over.
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


float cloud_shade(vec2 w, vec3 L) {
	vec2 p = w + (L.xz / max(L.y, 0.20)) * cloud_height;
	p += vec2(1.0, 0.35) * (TIME * cloud_speed * clamp(wind_factor, 0.2, 3.0));
	float c = vnoise(p / cloud_scale) * 0.65 + vnoise(p / (cloud_scale * 0.37) + 19.0) * 0.35;
	return 1.0 - cloud_shadow_strength * smoothstep(cloud_cover, cloud_cover + 0.22, c);
}


// Metres of water between a true-world XZ and the nearest land (x), and metres west of the main
// shoreline (y, clamped at zero). Both come from the same shapes MacroMap.coast_x() / in_bay()
// use: the bay curve of the main shore, the bulge around the peninsula, and the peninsula's own
// circle. The second one is what MacroMap.bake() colours its water by, so it is what the far
// plane's colour has to be reproduced from. The bay (San Pedro Bay round the headland's south
// and east, which sits east of the main shoreline) measures to its own north and east shores.
// MacroMap._main_coast_x(): the basin's sine, eased onto the replica's waterline table.
float main_coast_x(float z) {
	float x = coast_base_x + coast_wobble * sin(z / coast_period);
	if (coast_table_dz > 0.0) {
		float z1 = coast_table_z0 + coast_table_dz * float(COAST_TABLE - 1);
		float t = smoothstep(coast_table_z0 - coast_table_blend, coast_table_z0, z);
		if (t > 0.0) {
			float f = (clamp(z, coast_table_z0, z1) - coast_table_z0) / coast_table_dz;
			int j = clamp(int(floor(f)), 0, COAST_TABLE - 1);
			int j1 = min(j + 1, COAST_TABLE - 1);
			x = mix(x, mix(coast_table[j], coast_table[j1], clamp(f - float(j), 0.0, 1.0)), t);
		}
	}
	return x;
}


// The headland's axes (MacroMap._headland_axes()).
void headland_axes(out vec2 u, out vec2 v) {
	float b = radians(peninsula_bearing);
	u = vec2(sin(b), -cos(b));
	v = vec2(-u.y, u.x);
}


// MacroMap.headland_west_x(): the headland's west shore at z, or a huge number off it.
float headland_west_x(float z) {
	vec2 u;
	vec2 v;
	headland_axes(u, v);
	float aa = peninsula_axis_a * peninsula_axis_a;
	float bb = peninsula_axis_b * peninsula_axis_b;
	float zz = z - peninsula_center.y;
	float al = u.x * u.x / aa + v.x * v.x / bb;
	float be = u.x * u.y / aa + v.x * v.y / bb;
	float ga = u.y * u.y / aa + v.y * v.y / bb;
	float disc = be * be * zz * zz - al * (ga * zz * zz - 1.0);
	if (disc < 0.0) {
		return 1e9;
	}
	return peninsula_center.x + (-be * zz - sqrt(disc)) / al;
}


// MacroMap.headland_dist(): metres outside the headland's shore, negative inside.
float headland_dist(vec2 p) {
	vec2 u;
	vec2 v;
	headland_axes(u, v);
	vec2 q = p - peninsula_center;
	vec2 ax = vec2(peninsula_axis_a, peninsula_axis_b);
	vec2 l = vec2(dot(q, u), dot(q, v));
	float k0 = length(l / ax);
	float k1 = length(l / (ax * ax));
	return k1 < 0.000001 ? -min(ax.x, ax.y) : k0 * (k0 - 1.0) / k1;
}


vec2 shore_distance(vec2 p) {
	float cx = min(main_coast_x(p.y), headland_west_x(p.y));
	float d = cx - p.x;
	// Signed, and kept signed: the bake only paints its surf band where this is positive, so
	// enclosed water east of the shoreline (the harbour, the bay) gets none either.
	float off = d;
	if (p.y > bay_z && p.x < bay_east_x && p.x > cx) {
		// Inside the bay the land is east and north of the water, not the main shoreline.
		d = min(bay_east_x - p.x, p.y - bay_z);
	}
	if (d < 0.0) {
		d = 300.0;
	}
	float pen = headland_dist(p) - 2.0;
	return vec2(min(d, max(pen, 0.0)), off);
}


// One Gerstner wave. Adds its displacement to `disp` and the partial derivatives of that
// displacement along world x and z to `ddx` / `ddz`, so the surface normal and the fold come out
// of the same evaluation instead of costing two more whole wave sums.
//
// `lean` is how far the crest is dragged forward, AS A FRACTION OF THE WAVE'S OWN HEIGHT: 0 is a
// sine wave, 1 a sharp Gerstner peak. It used to be a fraction of the wavelength instead, which
// meant a 1 m swell on a 97 m wavelength was sheared sideways by four metres - a mush of rolling
// nothing when the sea was calm - and that the shape of the wave changed character as the
// weather raised the amplitude. Above about 1.4 the surface folds through itself.
void gerstner(vec2 p, vec2 dir, float len, float amp, float lean, float t,
		inout vec3 disp, inout vec3 ddx, inout vec3 ddz) {
	float k = TAU / len;
	// Deep-water phase speed. Long swells outrun short chop, which is most of why a real sea
	// never looks like a fixed pattern sliding along.
	float c = sqrt(9.8 / k);
	float f = k * (dot(dir, p) - c * t);
	float sf = sin(f);
	float cf = cos(f);
	disp += vec3(-lean * amp * dir.x * sf, amp * cf, -lean * amp * dir.y * sf);
	float la = lean * amp * k;
	ddx += vec3(-la * dir.x * dir.x * cf, -amp * k * dir.x * sf, -la * dir.y * dir.x * cf);
	ddz += vec3(-la * dir.x * dir.y * cf, -amp * k * dir.y * sf, -la * dir.y * dir.y * cf);
}


void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Waves are built in TRUE world coordinates, not scene-local ones: the streamer re-centres
	// the origin every few hundred metres, and a wave field built in local space jumps by the
	// whole shift when it does.
	vec2 p = wp.xz + world_offset;
	float t = TIME * speed;
	vec2 sd = shore_distance(p);
	// Shoaling. A swell feels the bottom, stands up, and dies where it has already broken.
	// Without the taper a storm's seven-metre swell simply cut through the beach and the
	// waterline was a straight seam between blue and sand.
	// The coefficient is what decides how much it stands UP, and it has to be much bigger than it
	// looks. r + c*r^2*(1-r) peaks at 1.0296 for c = 1.6 - a three per cent gain - so the old
	// curve was a taper and nothing else, and swells walked into the sand the height they were a
	// kilometre out. c = 5.0 peaks at 1.4533 at r = 0.755, which smoothstep(4.2, 72) puts 50 m
	// offshore, and it still falls to zero at r = 0 so the waterline itself does not move.
	// Measured at that band in clear weather the crest fold goes from 0.15 to 0.22, which is the
	// difference between sitting under foam_fold_lo (0.16) and breaking white.
	float reach = smoothstep(swash_width * 0.3, surf_width, sd.x);
	float shoal = reach * (1.0 + 5.0 * reach * (1.0 - reach));
	// Wave groups, drifting slowly across the swell direction. Deliberately a very low
	// frequency: what it has to do is leave wide patches of the sea calmer than their
	// neighbours, so that from the air the surface has a scale bigger than one wave.
	float grp = vnoise(p / group_length + vec2(t * 0.006, -t * 0.004));
	float group = 1.0 - group_depth * (1.0 - grp);
	float open = base_height * max(wave_scale, 0.05);
	float amp = open * shoal * group;

	// Ripple LOD: what is left past `fine_fade` is the two long swells, which is all the far sea
	// can resolve anyway.
	float fine = 1.0 - smoothstep(fine_fade.x, fine_fade.y, distance(wp, INV_VIEW_MATRIX[3].xyz));
	vec3 disp = vec3(0.0);
	vec3 ddx = vec3(0.0);
	vec3 ddz = vec3(0.0);
	float l0 = max(swell_length, 8.0);
	// A Gerstner wave folds through itself once lean * amp * k passes 1, and the five below add
	// up. `lean` is a fraction of the wave's own height, so a storm raising the height six times
	// would take the whole sum past that: pull the lean back as the sea gets big and the crests
	// stay crests instead of turning inside out.
	// The numerator has to be big enough that the pull-back only bites near the top of the range.
	// At 1.6 it bit from wave_scale 1.33 (open = 1.2 * wave_scale) all the way up, and in that
	// whole unclamped band lean_k was exactly 1.6 / open - so the product open * lean_k, which is
	// what every wave's steepness lean * amp * k is proportional to, sat pinned at exactly 1.6
	// from wave_scale 1.33 to 3.81. Overcast (1.8) and rain (3.2) both fall inside that, so the
	// two had bit-identical crests: the sea got 1.8x taller between them and not one bit steeper.
	// 3.6 / 0.55 gives products 1.20, 2.16, 3.60, 3.96 across clear, overcast, rain and storm -
	// monotonic. Worst case measured on open water in a storm is a fold of 0.52, and 0.91 with a
	// full tsunami running at the same time, both still clear of the 1.0 where the surface
	// inverts. Raise either number again and check that tsunami case, it is the binding one.
	float lean_k = clamp(3.6 / max(open, 0.1), 0.55, 1.0);

	gerstner(p, normalize(vec2(1.00, 0.22)), l0, amp * 0.34, 0.75 * lean_k, t, disp, ddx, ddz);
	gerstner(p, normalize(vec2(0.86, -0.51)), l0 / 1.59, amp * 0.26, 0.85 * lean_k, t, disp, ddx, ddz);
	gerstner(p, normalize(vec2(0.62, 0.78)), l0 / 2.62, amp * 0.19 * mix(0.45, 1.0, fine), 0.95 * lean_k, t, disp, ddx, ddz);
	gerstner(p, normalize(vec2(0.97, -0.24)), l0 / 4.51, amp * 0.13 * fine, 1.05 * lean_k, t, disp, ddx, ddz);
	gerstner(p, normalize(vec2(0.34, 0.94)), l0 / 7.89, amp * 0.08 * fine * fine, 1.10 * lean_k, t, disp, ddx, ddz);
	if (tsunami_scale > 0.001) {
		// Not tapered by the shoaling: the whole point of this one is to run up the beach.
		gerstner(p, normalize(tsunami_dir), tsunami_length, tsunami_height * tsunami_scale,
			1.20 * lean_k, t * 0.9, disp, ddx, ddz);
	}
	VERTEX += disp;

	// The normal, out of the same derivatives. Without a real normal the sea moved but was lit
	// as a flat sheet, so all you saw was a painted pattern sliding about on a pale plane -
	// which is exactly what it looked like.
	vec3 tx = vec3(1.0, 0.0, 0.0) + ddx;
	vec3 tz = vec3(0.0, 0.0, 1.0) + ddz;
	vec3 n = normalize(cross(tz, tx));
	NORMAL = n;
	world_normal = n;

	// How hard the horizontal displacement is pinching the surface together. The determinant of
	// the horizontal Jacobian is 1 on undisturbed water and drops toward 0 where the crest is
	// gathering itself up to break - which is exactly where foam belongs, and is why the foam
	// below is keyed off this rather than off height.
	float jac = (1.0 + ddx.x) * (1.0 + ddz.z) - ddx.z * ddz.x;
	fold = clamp(1.0 - jac, 0.0, 1.0);
	// Measured against the open-water swell, not against the tapered one, so the flattened
	// water in the surf zone reads as flat instead of as a field of tiny crests.
	crest = clamp(disp.y / max(open + tsunami_height * tsunami_scale * 0.6, 0.2), -1.0, 1.0);
	shore = sd.x;
	offshore = sd.y;
	world_pos = wp + disp;
}


void fragment() {
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 view_dir = normalize(world_pos - eye);
	float dist = length(world_pos - eye);
	vec2 w = world_pos.xz + world_offset;
	// How much sea is running, how much of a storm it is, and how hard the wind blows.
	float sea = clamp(wave_scale / 3.0, 0.0, 1.0);
	float storm = smoothstep(3.2, 5.6, wave_scale);
	float wind = clamp((wind_factor - 1.0) / 4.0, 0.0, 1.0);
	bool rich = ground_detail > 0.5;
	// How far through the hand-over to the far plane this fragment is. Everything fine - chop,
	// foam, sub-surface - is faded out on the way, so what is left at the far end is the same
	// smooth painted water the ground follower draws beyond the chunk edge.
	float painted = smoothstep(handover_start, handover_end, dist);
	float detail = 1.0 - painted;

	// The sky this water is under, weather and all. Same expression DayNight hands the ground
	// follower as its haze_color (horizon lerped toward the storm horizon), so the far sea and
	// this one wash out into the same colour.
	vec3 haze = mix(sky_tint.rgb, storm_horizon, weather_dark * (1.0 - night_factor * 0.6));
	vec3 sun_n = normalize(sun_direction);
	float dim = mix(1.0, 0.16, night_factor);

	// ---- the shading normal ------------------------------------------------------------
	// The mesh carries the swell; the ripple between the vertices has to be added here or the
	// big wave faces are flat sheets and the fresnel goes to 1 over the whole sea at once.
	// Two octaves of noise, taken as a gradient and folded straight into the normal (rather
	// than through NORMAL_MAP, which would need the mesh's tangents to mean something).
	float chop = chop_strength * (0.55 + 0.75 * wind) * (1.0 - smoothstep(chop_fade * 0.35, chop_fade, dist));
	// The fine octave is a sub-metre ripple, under a pixel well before the coarse one is, so it
	// fades out over a third of the distance rather than alongside it.
	float chop_fine = chop * (1.0 - smoothstep(chop_fade * 0.10, chop_fade * 0.38, dist));
	vec2 grad = vec2(0.0);
	// Past `chop_fade` this is zero anyway, and the far sea is most of an aerial frame: do not
	// pay two noise fetches a pixel out there to multiply them by nothing.
	if (chop > 0.001) {
		float rs = 1.0 / max(ripple_size, 0.05);
		vec2 rp = w * rs + vec2(TIME * 0.13, TIME * -0.10);
		vec3 r1 = noised(rp);
		grad = r1.yz * (rs * ripple_height * chop);
		if (rich && chop_fine > 0.001) {
			vec3 r2 = noised(rp * 2.9 + vec2(17.0, 5.0) - vec2(TIME * 0.21, TIME * 0.17));
			grad += r2.yz * (rs * 2.9 * ripple_fine_height * chop_fine);
		}
	}
	vec3 n = normalize(world_normal + vec3(-grad.x, 0.0, -grad.y));

	// ---- colour by depth ----------------------------------------------------------------
	// There is no bathymetry under the sea - the floor is one flat box - so the distance to the
	// sand stands in for it, which is what it is a proxy for anyway. The shelf-to-deep ramp is
	// the bake's own (offshore / 600), so this shader and the far plane agree on the colour of
	// the open sea at every distance and not just at the deep end. The green shelf over the
	// sand goes on top of it, inside a distance the 62 m bake cannot resolve at all.
	vec3 water = mix(shelf_color, deep_color, clamp(max(offshore, 0.0) / bake_deep_reach, 0.0, 1.0));
	water = mix(water, shore_color, (1.0 - smoothstep(0.0, shore_reach, shore)) * detail);
	// The sea is lit by the sky above it, so it darkens with the weather and the hour exactly
	// as the sky does. Without this a storm sea stayed a bright holiday turquoise under a
	// slate-grey sky, which is the single loudest tell that water is painted on.
	float sky_lum = dot(haze, vec3(0.299, 0.587, 0.114));
	water *= mix(0.55, 1.15, clamp(sky_lum * 3.0, 0.0, 1.0));
	// A trough has more water along the line of sight than a crest, so it is darker.
	vec3 col = water * (0.84 + 0.28 * clamp(0.5 + 0.5 * crest, 0.0, 1.0));

	// Sub-surface: a wave face with the sun behind it glows green where the water is thin.
	float sss = pow(max(dot(view_dir, sun_n), 0.0), 3.0) * clamp(crest, 0.0, 1.0) * sea;
	col += sss_color * sss * (1.0 - night_factor) * detail;

	// ---- the sky in the water ------------------------------------------------------------
	// Schlick, against the real normal. Water reflects two per cent of what is above it head on
	// and nearly all of it at a grazing angle, and that one curve is the whole difference
	// between "dark and see-through at your feet, a mirror at the horizon" and the flat pale
	// blue sheet this used to be. It used to be capped at 0.44 because with a FLAT normal a
	// grazing view turns the whole sea into sky - the chop above is what makes the full curve
	// safe.
	float fres = water_f0 + (1.0 - water_f0) * pow(1.0 - clamp(dot(n, -view_dir), 0.0, 1.0), 5.0);
	fres = clamp(fres, 0.0, fresnel_cap);
	vec3 refl = reflect(view_dir, n);
	// What the water is looking at: the horizon colour along the horizon, a deeper blue as the
	// reflection tips up toward the zenith, and the sea's own colour where a steep wave face
	// reflects something below the horizon.
	vec3 sky_ref = mix(haze, haze * vec3(0.55, 0.72, 1.00), smoothstep(0.0, 0.55, refl.y));
	sky_ref = mix(water * 2.0, sky_ref, smoothstep(-0.12, 0.02, refl.y));
	col = mix(col, sky_ref, fres);

	// ---- the sun path ---------------------------------------------------------------------
	// A broad glare lobe with sparkles inside it. The sparkles come from the chop in the normal,
	// so they sit on real ripples; the noise gate thins them out into a broken path of separate
	// points rather than one smooth blob, which is what a sun path actually looks like.
	vec3 half_v = normalize(sun_n - view_dir);
	float ndh = max(dot(n, half_v), 0.0);
	float glare = pow(ndh, 90.0);
	float spark = pow(ndh, glitter_sharp);
	float broken = 1.0;
	if (rich && detail > 0.01) {
		broken = 0.25 + 1.5 * smoothstep(0.42, 0.92, vnoise(w * 0.85 + vec2(TIME * 0.4, TIME * -0.3)));
	}
	col += vec3(1.0, 0.95, 0.84) * (glare * 0.5 + spark * 3.0 * broken)
		* glitter * (1.0 - night_factor) * (1.0 - weather_dark) * detail;

	// ---- foam --------------------------------------------------------------------------
	// Where the surface is folding, not wherever it happens to be high: a threshold on height
	// turned whole facets of the coarse mesh white and the sea read as a cartoon. All of it is
	// skipped once `detail` has faded it out - the far plane paints its own white water.
	float foam = 0.0;
	if (detail > 0.01) {
	float fn = vnoise(w * 0.32 + vec2(TIME * 0.11, TIME * -0.08));
	foam = smoothstep(foam_fold_lo, foam_fold_hi, fold * (0.75 + 0.5 * fn)) * sea;
	// And a thinner wash over the tops themselves, gated by the same noise, so a crest that is
	// not steep enough to break can still be flecked.
	foam = max(foam, smoothstep(0.55, 1.0, crest) * sea * 0.35 * smoothstep(0.35, 0.8, fn));

	// The shore break. Two or three lines of white riding in toward the sand (the phase runs
	// with +shore, so the bands travel toward the beach), plus the wash sliding up and back
	// over the last few metres. This is the whole difference between a sea and a blue plane
	// that stops at a straight line.
	float breaker = pow(max(sin(shore * 0.085 + TIME * 1.05), 0.0), 8.0);
	breaker *= 1.0 - smoothstep(surf_width * 0.2, surf_width * 1.1, shore);
	float edge = swash_width * (0.55 + 0.45 * sin(TIME * TAU / swash_period));
	float wash = 1.0 - smoothstep(edge * 0.35, edge + 8.0, shore);
	float surf = breaker * (0.5 + 0.6 * sea) + wash * (0.7 + 0.3 * sea);
	if (surf > 0.001) {
		// Broken up along the shore, so the surf is not a drawn stripe: a real break arrives in
		// sections, with gaps where the bottom is deeper. Two noise fetches, inside the `if`
		// because the surf zone is a few per cent of the water on screen and the open sea has
		// no business paying for them.
		surf *= 0.35 + 0.95 * vnoise(vec2(w.y * 0.035, w.x * 0.12 + TIME * 0.35));
		surf *= 0.5 + 0.8 * vnoise(w * 0.55 + vec2(0.0, TIME * 0.8));
		foam = max(foam, clamp(surf, 0.0, 1.0));
	}

	// Spray: in a storm the wind tears the tops off the crests and lays foam out downwind in
	// streaks. One extra noise fetch, so it is gated on the same detail global the ground uses.
	if (rich && storm > 0.01) {
		vec2 wv = normalize(wind_dir + vec2(0.0001, 0.0));
		vec2 sp = vec2(dot(w, wv), dot(w, vec2(-wv.y, wv.x)));
		float streak = vnoise(vec2(sp.x * 0.03 - TIME * (1.2 + 2.0 * wind), sp.y * 0.24));
		streak = smoothstep(0.5, 0.95, streak) * smoothstep(0.3, 0.8, crest);
		foam = max(foam, streak * storm * 0.35);
	}
	}
	foam = clamp(foam, 0.0, 1.0) * detail;
	// Foam is a rough white surface lit by the sky, not a light source: it goes darker at night
	// and under a storm along with everything else.
	col = mix(col, foam_color * mix(0.35, 1.0, clamp(sky_lum * 3.0, 0.0, 1.0)), foam);

	// ---- the far plane's own water, for the hand-over ----------------------------------
	// macro_ground.gdshader, water branch, reproduced: its swell normal faded out as one wave
	// drops under a pixel, MacroMap.bake()'s shelf-to-deep ramp with its surf band, the same
	// view-only fresnel toward the same haze, and the same glare, glint and cloud shadow.
	// Reproduced rather than approximated, because anything else is a rectangle - the first
	// attempt matched the COLOUR and left the far sea covered in sparkles that stopped dead at
	// the chunk edge.
	vec3 shade_n = n;
	if (painted > 0.001) {
		float graze = sqrt(clamp(1.0 / max(abs(view_dir.y), 0.06), 1.0, 12.0));
		float fp = max(dist * far_pixel_angle * graze, 0.02);
		float fwl = max(fp / far_swell, 0.0001);
		float fchop = clamp(1.0 - fwl * 1.6, 0.0, 1.0);
		vec2 sp = w / far_swell + vec2(TIME * 0.09, TIME * 0.05);
		vec3 s1 = noised(sp);
		vec3 s2 = noised(sp * 2.7 + 11.0);
		vec2 sg = (s1.yz * 0.75 + s2.yz * 0.30) * fchop * 0.55;
		vec3 far_n = normalize(vec3(-sg.x, 1.0, -sg.y));
		float rdl = max(dot(reflect(view_dir, far_n), sun_n), 0.0);
		vec3 fb = mix(shelf_color, deep_color, clamp(max(offshore, 0.0) / bake_deep_reach, 0.0, 1.0));
		if (offshore >= 0.0) {
			fb = mix(fb, bake_surf_color, (1.0 - smoothstep(0.0, bake_surf_width, offshore)) * 0.85);
		}
		float ffres = pow(1.0 - clamp(-view_dir.y, 0.0, 1.0), 5.0);
		fb = mix(fb, haze, clamp(0.10 + 0.78 * ffres, 0.0, 0.92));
		fb += vec3(1.0, 0.94, 0.82)
			* (pow(rdl, 70.0) * far_glitter + pow(rdl, 900.0) * fchop * far_glitter * 6.0)
			* (1.0 - night_factor) * cloud_shade(w, sun_n);
		col = mix(col, fb, painted);
		// The far plane shades its sea with THAT normal, so whatever specular the renderer adds
		// on top of the painted colour matches on both sides of the seam.
		shade_n = normalize(mix(n, far_n, painted));
	}

	col *= dim;
	// The far plane is EMITTED at face value past its own near band, so the renderer's sun and
	// ambient never touch it. Hand this water over to the same deal at the same rate: lit while
	// it is near, painted once it is far, and nothing anywhere for the lighting to make differ.
	ALBEDO = col * (1.0 - painted);
	EMISSION = col * painted;
	ROUGHNESS = mix(mix(0.18, 0.72, foam), far_roughness, painted);
	METALLIC = 0.0;
	// Low while the water is near: the sky reflection is already in ALBEDO by fresnel above, and
	// letting the renderer add its own on top of that counted it twice and turned the sea from
	// the beach brighter than the sky over it. The far end has to match the plane's 0.55.
	SPECULAR = mix(0.12, far_specular, painted);
	NORMAL = normalize((VIEW_MATRIX * vec4(shade_n, 0.0)).xyz);
}
