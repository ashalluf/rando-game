shader_type spatial;
render_mode cull_back;

// The land beyond the streamed chunks. The ground follower is one plane 14 km across shaded
// from a small image of the whole basin baked by MacroMap.bake(): ocean to the west, the
// mountains to the north, the airport, the city sprawl.
//
// That image is 256 px across 16 km, which is 62 metres a texel: every detail smaller than a
// city block has already been thrown away before this shader ever runs, and forty per cent of
// a wide shot is this plane. So the job here is not to display the bake, it is to SYNTHESIZE
// everything between 62 m and about a metre back out of it - a ridged fractal with analytic
// derivatives for the shape, a real surface normal from that fractal, slope-aware rock, scree,
// chaparral and dry grass, drainage that runs downhill, a block-and-street grain over the
// built-up ground, terrain that shadows itself toward the sun, and cloud shadows crawling
// over all of it. The bake decides WHAT is where; this decides what it looks like.


// The land height, its crags and the uniforms they read (macro_tex, macro_centre, macro_span,
// macro_height, lift_start, lift_end, world_offset, relief_*, flats_amplitude, detail_lod) live
// in the include, so Skyline's far planting sits on exactly this surface.
#include "res://shaders/macro_relief.gdshaderinc"

// Close to the camera the plane is the ground the player is standing on, so a real texture
// takes over, tinted by whatever the macro map says is there.
uniform sampler2D near_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D near_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float near_scale = 6.0;
uniform float near_fade_start = 60.0;
uniform float near_fade_end = 340.0;

// Aerial perspective: the far land washes out into the sky's own horizon colour, which DayNight
// keeps in step with the weather and the hour.
uniform vec3 haze_color : source_color = vec3(0.70, 0.78, 0.88);
// Only a last touch at the very edge of the plane, to hide its rim. The Environment's own
// aerial-perspective fog does the real distance wash, and doing it twice turned the whole basin
// into milk: at the settings this scene uses, 3 km of air is already half haze.
uniform float haze_start = 4500.0;
uniform float haze_end = 7400.0;
uniform float haze_strength : hint_range(0.0, 1.0) = 0.45;
// Golden-hour smog (DayNight, through CityStreamer.set_ground_smog; 0 outside golden hour, which
// skips it): lit haze under the basin's inversion lid. Far land low down goes into it and peaks
// above `smog_lid` metres stand clear of it, which is how the mountains round Los Angeles look
// on an evening. Depth fog alone greys a mountain evenly from foot to crest.
uniform float smog = 0.0;
uniform vec3 smog_color : source_color = vec3(0.64, 0.54, 0.47);
uniform float smog_lid = 380.0;
uniform float smog_reach = 3200.0;
// The plane's own rim. It is 14 km across and the camera now draws to 12 km, so from any height
// its edge was a hard line with the sky's under-horizon colour beyond it - seen from the hills as
// a pale slab laid across the sea. Between these two horizontal distances from the camera it
// hands over completely to the sky's horizon colour (the `sky_tint` global, which is what the
// sky shows just under the horizon), and so do the far city's boxes and planting, on the same
// numbers (building_lod.gdshader, far_canopy.gdshader). CityStreamer sets all three from
// ground_size.
uniform float edge_start = 5040.0;
uniform float edge_end = 6860.0;

uniform vec3 sun_dir = vec3(0.45, 0.72, 0.28);
global uniform float night_factor;
// Cleared by Quality on the web and below MEDIUM: gates the expensive half of this shader.
global uniform float ground_detail;
// The sky's own colour this hour, which is what actually fills the shadows outdoors.
global uniform vec4 sky_tint;
// Drives how fast the cloud shadows cross the basin.
global uniform float wind_factor;


// ---- synthesized relief -------------------------------------------------------------------
// How many octaves the fragment shader runs. 9 reaches about 2.5 m.
uniform int relief_octaves : hint_range(1, 10) = 9;
// How many metres of ground one screen pixel covers per metre of distance (tan(fov/2)/height).
uniform float pixel_angle = 0.0016;

// ---- lighting -----------------------------------------------------------------------------
// Direct sunlight on this plane. It is lit by hand past the near band: see the ALBEDO/EMISSION
// split at the bottom for why.
// The far plane is EMITTED past near_fade_end * 1.8, so the scene's DirectionalLight never
// touches it and this IS its sun. Keep it equal to DayNight.day_sun_energy or the land past
// 600 m runs darker than the streamed chunks it butts against.
uniform float sun_strength = 1.30;
// Sky fill, the light a slope facing away from the sun actually gets.
uniform float ambient_strength = 0.30;
// Warm light bounced back up off the ground in front of a slope.
uniform float bounce_strength = 0.12;
uniform vec3 sun_color : source_color = vec3(1.0, 0.955, 0.88);
// Steps of the ray march that asks whether this point can see the sun. 0 turns it off.
uniform int shadow_steps : hint_range(0, 16) = 10;
// How far along the sun direction that march looks, in metres.
uniform float shadow_reach = 3400.0;
// How dark a shadowed slope gets. 1.0 is the full geometric answer.
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.9;

// ---- cloud shadows --------------------------------------------------------------------------
// How much of the sun a cloud takes away. Nothing else out there moves, so these are also the
// only thing that tells the player the horizon is a place and not a painting.
uniform float cloud_shadow_strength : hint_range(0.0, 1.0) = 0.55;
// Metres across one cloud.
uniform float cloud_scale = 1500.0;
// How much of the sky the shadowing clouds cover; higher leaves fewer, smaller shadows.
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.52;
// Metres the cloud deck sits above the ground, which is what offsets the shadow from the cloud.
uniform float cloud_height = 900.0;
// Metres a second the deck drifts.
uniform float cloud_speed = 7.0;

// ---- natural ground -------------------------------------------------------------------------
// These are LINEAR values, not what a colour picker would show, because that is what the
// baked map decodes to: `macro_tex` is a source_color sampler, so MacroMap's Color(0.216, ...)
// arrives here as 0.038. Writing these the way they look in a picker makes the synthesized
// hillsides four or five times brighter than the basin they stand in, with a hard bright line
// along the foot of every range. The numbers below sit inside the range MacroMap's own palette
// decodes to - see the comment on BAKE_GRASS there.
uniform vec3 rock_color : source_color = vec3(0.100, 0.096, 0.088);
uniform vec3 scree_color : source_color = vec3(0.150, 0.130, 0.100);
uniform vec3 scrub_color : source_color = vec3(0.042, 0.047, 0.029);
uniform vec3 dry_grass_color : source_color = vec3(0.092, 0.078, 0.044);
uniform vec3 snow_color : source_color = vec3(0.58, 0.60, 0.66);
// The light the ground in front of a slope bounces back up into it. A hue, not an albedo.
uniform vec3 bounce_color : source_color = vec3(0.62, 0.52, 0.34);
// Slope at which bare rock starts and finishes taking over from the scrub.
uniform float rock_slope_start : hint_range(0.0, 1.0) = 0.24;
uniform float rock_slope_end : hint_range(0.0, 1.0) = 0.60;
// How much of a hillside the chaparral covers.
uniform float scrub_amount : hint_range(0.0, 1.0) = 0.85;
// How much more of it the north-facing slopes carry, and how much less the south ones: the shaded
// side of a Californian hill is brush and the sunny side grass (terrain.gdshader's north_brush,
// which the near hills and their planting use).
uniform float north_scrub : hint_range(0.0, 0.5) = 0.3;
// How strongly the drainage lines green up and darken the gullies.
uniform float gully_amount : hint_range(0.0, 1.0) = 0.55;
// Metres above sea level the snow line sits.
uniform float snow_line = 1150.0;

// ---- built-up ground --------------------------------------------------------------------------
// Metres across one city block, which sets the grain of the distant sprawl.
uniform float city_block = 104.0;
// Metres across a street.
uniform float city_street = 13.0;
// One block in this many is an avenue, in each direction.
uniform float city_avenue_every = 6.0;
uniform vec3 city_street_color : source_color = vec3(0.0125, 0.0125, 0.0143);
// A flat white single-ply roof. Six times the district's own value, which is why a real city
// sparkles from the air.
uniform vec3 white_roof_color : source_color = vec3(0.22, 0.22, 0.21);
// How much the roofs vary block to block. This is most of what makes sprawl read as sprawl.
uniform float roof_variation : hint_range(0.0, 1.0) = 0.62;
// How far a block throws its shadow into the street behind it, as a fraction of a block.
uniform float block_shadow : hint_range(0.0, 1.0) = 0.55;
uniform vec3 canopy_color : source_color = vec3(0.022, 0.030, 0.012);
// At night the built-up ground out there is not dark ground, it is a field of orange points.
uniform vec3 city_light_color : source_color = vec3(1.0, 0.70, 0.36);
uniform float city_light_strength : hint_range(0.0, 3.0) = 0.30;
// How leafy the leafier districts get.
uniform float canopy_amount : hint_range(0.0, 1.0) = 0.55;
// Metres the far city's ground was stood proud of the basin floor, to fake a downtown as a
// raised mass when nothing was drawn out there. Nothing is faked any more: the far city
// (scripts/world/skyline.gd) draws every block of the basin as its real buildings, on the real
// ground height, and a lifted plane only buried them - 42 m swallowed every suburb past 2.6 km.
uniform float urban_lift = 0.0;
// That lift only starts past the streamed chunks, or it would cut their feet off.
uniform float urban_lift_start = 1400.0;
uniform float urban_lift_end = 2600.0;
// How far the roof grain slides against the street grid with the view angle. Fake parallax,
// but it is what stops a distant city reading as a pattern printed on the floor.
uniform float urban_parallax : hint_range(0.0, 1.0) = 0.42;

// ---- sea --------------------------------------------------------------------------------------
// How bright the glitter path along the line to the sun burns.
uniform float sea_glitter : hint_range(0.0, 4.0) = 1.6;
// Metres across one swell out here, where the real ocean chunks have long since stopped.
uniform float sea_swell = 46.0;

varying vec3 world_pos;

// Is this texel built-up ground? MacroMap bakes every district and apron as a near-neutral
// grey (a city from three kilometres up is roofs, asphalt and dust, and it is the one thing
// out there with no colour in it) and every natural cover - grass, chaparral, rock, sand - with
// real chroma in it, so saturation alone separates them. Brightness keeps the airport's pale
// concrete and the snowfields out of it, and slope keeps the grey rock faces out: nobody builds
// a grid on a 30-degree hillside. Keep this in step with the BAKE_* colours in macro_map.gd.
float built_amount(vec3 c, float slope, float height_m) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = (mx - mn) / max(mx, 0.0008);
	float lum = dot(c, vec3(0.3333));
	// Linear values: a district decodes to 0.083..0.180 with a saturation under 0.16, pale
	// concrete to 0.27, port to 0.22, chaparral to 0.07 at saturation 0.76, bare rock to 0.12 at
	// saturation 0.53, snow to 0.62. The window has moved twice as the districts were lifted out
	// of near-black; if you change MacroMap's BAKE_* district colours, these two numbers move
	// with them, and tests/smoke_test.gd reads them straight out of this line to check it.
	return (1.0 - smoothstep(0.17, 0.30, sat))
		* (1.0 - smoothstep(0.175, 0.215, lum))
		* (1.0 - smoothstep(0.10, 0.30, slope))
		* (1.0 - smoothstep(420.0, 700.0, height_m));
}


void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec4 m;
	vec2 mg;
	float wet;
	float d;
	float lift = far_ground_lift(wp, cam, m, mg, wet, d);
	if (smoothstep(lift_start, lift_end, d) > 0.002) {
		// A distant downtown is a raised mass, not a grey patch on the floor. Past the streamed
		// chunks the plane stands the built-up ground up by a few storeys, which is what gives
		// the far city an edge against the hills behind it.
		float slope = clamp(length(mg) * macro_height, 0.0, 1.0);
		lift += urban_lift * built_amount(m.rgb, slope, m.a * macro_height)
			* smoothstep(urban_lift_start, urban_lift_end, d) * (1.0 - wet);
	}
	float off = lift - far_ground_sink(d, wet);
	VERTEX.y += off;
	world_pos = wp + vec3(0.0, off, 0.0);
}


// One block-and-street grid. Returns 1 on a street. `aa` is the pixel footprint in cell units,
// which widens the edges until the whole grid averages out to a tint instead of sparkling.
float street_grid(vec2 cell, float half_width, float aa) {
	vec2 g = abs(fract(cell) - vec2(0.5));
	float e = 0.5 - half_width;
	return max(smoothstep(e - aa, e + aa, g.x), smoothstep(e - aa, e + aa, g.y));
}


// How much of the sun a cloud is taking away here. The point is projected up the sun direction
// onto the cloud deck, so the shadow lies where a cloud at that height would actually put it,
// and the whole deck drifts with the wind. Two octaves; it is a shadow, not a cloud.
float cloud_shade(vec2 w, vec3 L) {
	vec2 p = w + (L.xz / max(L.y, 0.20)) * cloud_height;
	p += vec2(1.0, 0.35) * (TIME * cloud_speed * clamp(wind_factor, 0.2, 3.0));
	float c = vnoise(p / cloud_scale) * 0.65 + vnoise(p / (cloud_scale * 0.37) + 19.0) * 0.35;
	return 1.0 - cloud_shadow_strength * smoothstep(cloud_cover, cloud_cover + 0.22, c);
}


void fragment() {
	vec2 w = world_pos.xz + world_offset;
	vec2 uv = macro_uv(w);
	vec2 mg = vec2(0.0);
	vec4 m = macro_sample(uv, mg);

	vec3 eye = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 view = normalize(world_pos - eye);
	float dist = length(world_pos - eye);
	// Metres one screen pixel covers here. Everything finer than this has to be averaged away
	// rather than drawn, or the far hills boil. A plane seen at a grazing angle - which is what
	// the whole far half of this one is - covers far more ground per pixel along the view than
	// across it, so the isotropic estimate under-blurs exactly where the aliasing is worst.
	// The square root of it, not all of it: taking the full long axis is what a non-anisotropic
	// filter would do and it blurs the ground across the view as much as along it, which at a
	// nine-degree pitch leaves no texture anywhere in the frame. Half the exponent is the usual
	// compromise and keeps detail where the eye actually reads it.
	float graze = sqrt(clamp(1.0 / max(abs(view.y), 0.06), 1.0, 12.0));
	float fp = max(dist * pixel_angle * graze, 0.02);
	bool rich = ground_detail > 0.5;
	vec3 L = normalize(sun_dir);
	vec3 sky = mix(sky_tint.rgb, vec3(1.0), 0.12);
	float water = 1.0 - step(0.0005, m.a);
	float near = (1.0 - smoothstep(near_fade_start, near_fade_end, dist)) * (1.0 - water);

	// `base` is the unlit surface colour and `lit` the light falling on it. They are kept apart
	// because this plane is lit two different ways at once: see the ALBEDO/EMISSION split below.
	vec3 base;
	vec3 lit = vec3(1.0);
	// Light the far city makes itself, which is all there is to see out there after dark.
	vec3 glow = vec3(0.0);
	vec3 n = vec3(0.0, 1.0, 0.0);
	float rough = 0.95;

	if (water > 0.5) {
		// The sea is not a flat blue field. Looked down on it is nearly black and takes its
		// colour from the sky it reflects; there is a glare path burning along the line to the
		// sun, and out here - well past where the real ocean chunks stop - the swell still has
		// to break that path up into glitter rather than leave one clean mirror streak.
		float fres = pow(1.0 - clamp(-view.y, 0.0, 1.0), 5.0);
		// A swell normal, faded out as soon as one wave is smaller than a pixel.
		float wl = max(fp / sea_swell, 0.0001);
		float chop = clamp(1.0 - wl * 1.6, 0.0, 1.0);
		vec2 sp = w / sea_swell + vec2(TIME * 0.09, TIME * 0.05);
		vec3 s1 = noised(sp);
		vec3 s2 = noised(sp * 2.7 + 11.0);
		vec2 sg = (s1.yz * 0.75 + s2.yz * 0.30) * chop * 0.55;
		n = normalize(vec3(-sg.x, 1.0, -sg.y));
		vec3 refl = reflect(view, n);
		float glare = pow(max(dot(refl, L), 0.0), 70.0);
		float glint = pow(max(dot(refl, L), 0.0), 900.0) * chop;
		base = mix(m.rgb, haze_color, clamp(0.10 + 0.78 * fres, 0.0, 0.92));
		base += vec3(1.0, 0.94, 0.82) * (glare * sea_glitter + glint * sea_glitter * 6.0)
			* (1.0 - night_factor) * cloud_shade(w, L);
		rough = 0.22;
	} else {
		// ---- the surface, at every scale between the bake's 62 m and about a metre ----------
		// The derivative comes out of the same evaluation, so this is ONE fractal, not four.
		float amp_m = relief_scale(w, m.a, mg);
		int octaves = rich ? relief_octaves : 4;
		vec3 fb = relief_fbm(w, octaves, fp);
		// The crags only exist in the geometry past `lift_start`, so the normal only carries
		// its full share of them past it too - a normal describing a surface the vertices never
		// built is a surface that lights one way and silhouettes another.
		float far = mix(0.35, 1.0, smoothstep(lift_start, lift_end, dist));
		vec2 grad = mg * macro_height + fb.yz * (amp_m * far);
		n = normalize(vec3(-grad.x, 1.0, -grad.y));
		float slope = 1.0 - clamp(n.y, 0.0, 1.0);
		float height_m = m.a * macro_height + (fb.x - 0.5) * amp_m;
		float built = built_amount(m.rgb, slope, height_m);

		// ---- natural ground -------------------------------------------------------------
		// Start from the baked district colour so the map still reads as the map, then put the
		// slope-aware material on top. Before this everything was shaded as if it were level.
		base = m.rgb;
		float land = 1.0 - built;
		if (land > 0.004) {
			// Chaparral: one dominant scrub patch per hillside rather than an even sprinkle,
			// over parched grass. Southern California, so gold and olive over grey rock.
			float clump = vnoise(w * 0.0042) * 0.65 + vnoise(w * 0.019) * 0.35;
			float north = -n.z / max(length(n.xz), 0.001) * smoothstep(0.02, 0.12, slope);
			// Chaparral is the dominant cover, the grass the exception: on the gentle sunny ground.
			float gentle = 1.0 - smoothstep(0.06, 0.22, slope);
			float scrub = smoothstep(0.26, 0.60, clump + north * north_scrub - gentle * 0.25) * scrub_amount;
			vec3 nat = mix(dry_grass_color, scrub_color, scrub);
			// Individual bushes, but only once they are bigger than a couple of pixels.
			float bush = smoothstep(7.0, 2.0, fp) * smoothstep(0.45, 0.85, vnoise(w * 0.33));
			nat = mix(nat, scrub_color * 0.8, bush * 0.45);
			// Drainage. The fractal's LOW values are its valleys, so they are already where the
			// water would run; streak a noise that is six times longer downhill than across
			// along the fall line, and green up what it finds.
			vec2 fall = normalize(grad + vec2(0.0001, 0.0));
			vec2 across = vec2(-fall.y, fall.x);
			float streak = vnoise(vec2(dot(w, fall) * 0.0032, dot(w, across) * 0.021));
			float gully = smoothstep(0.42, 0.10, fb.x) * smoothstep(0.35, 0.72, streak) * gully_amount;
			nat = mix(nat, scrub_color * 0.85, gully);
			// Rock on the steep faces, with bedding planes picked out by world height, and a
			// scree fan in the band just below where the rock takes over.
			float rocky = smoothstep(rock_slope_start, rock_slope_end, slope);
			float strata = vnoise(vec2(dot(w, across) * 0.006, height_m * 0.055));
			float scree = smoothstep(rock_slope_start * 0.45, rock_slope_start, slope) * (1.0 - rocky);
			nat = mix(nat, scree_color * (0.82 + 0.36 * vnoise(w * 0.05)), scree * 0.7);
			// Faint: bedding picked out by height at full strength drew every range as a stack
			// of contour lines.
			nat = mix(nat, rock_color * (0.88 + 0.24 * strata), rocky);
			// Snow above the treeline, and not on the near-vertical faces, where it slides off.
			float snow = smoothstep(snow_line, snow_line + 270.0, height_m)
				* (1.0 - smoothstep(0.45, 0.8, slope));
			nat = mix(nat, snow_color, snow);
			// Keep some of the baked map's own colour so beaches, the port apron and the
			// district tints still show through rather than every flat becoming the same gold.
			float natural_mix = smoothstep(0.004, 0.06, m.a) * 0.88 + 0.12;
			base = mix(base, nat, land * natural_mix);
		}

		// ---- built-up ground ------------------------------------------------------------
		if (built > 0.004) {
			float aa = clamp(fp / city_block, 0.0015, 0.5);
			vec2 cell = w / city_block;
			float street = street_grid(cell, city_street * 0.5 / city_block, aa);
			vec2 acell = cell / city_avenue_every;
			float avenue = rich
				? street_grid(acell, city_street * 0.9 / (city_block * city_avenue_every), aa / city_avenue_every)
				: 0.0;
			// The roof grain is read at an offset that grows with how obliquely this ground is
			// being looked at, so the roofs slide against the street grid as the camera moves.
			// It is fake parallax, but it is what stops a distant city reading as a pattern
			// printed on the floor.
			vec2 par = (view.xz / max(-view.y, 0.25)) * (urban_parallax * city_block * 0.35) / city_block;
			vec2 bc = floor(cell + par);
			float roof = hash12(bc);
			float lot = vnoise((w + par * city_block) * 0.22)
				* smoothstep(3.0, 9.0, city_block * 0.25 / max(fp, 0.001));
			float tone = 1.0 + roof_variation * (roof - 0.5) * 1.5 + (lot - 0.5) * 0.34 * roof_variation;
			// A few flat white single-ply roofs in every district; they are what makes a real
			// city sparkle from the air.
			float white = smoothstep(0.93, 0.985, roof) * smoothstep(0.10, 0.03, slope);
			vec3 city = m.rgb * tone;
			city = mix(city, white_roof_color, white * 0.75);
			// Tree canopy between the houses. MacroMap bakes the leafier districts a shade
			// greener than downtown, so the leafiness follows the district on its own.
			// Linear again: the difference between a leafy district and downtown is four
			// thousandths, which is exactly what MacroMap's palette was chosen to encode.
			float green = clamp((m.g - m.r) * 250.0, 0.0, 1.0);
			float canopy = smoothstep(0.42, 0.78, vnoise(w * 0.021) * 0.7 + vnoise(w * 0.09) * 0.3);
			city = mix(city, canopy_color, canopy * canopy_amount * green * (1.0 - street));
			// The buildings' own shadows falling into the street. Sampling the street mask again,
			// pushed toward the sun, leaves a band on the far side of every block - which is the
			// cheapest way to make a grid of blocks read as solid rather than as printing.
			vec2 sd2 = L.xz;
			float sl = max(length(sd2), 0.001);
			vec2 push = (sd2 / sl) * (city_block * block_shadow * 0.42) / city_block;
			float lit_mask = street_grid(cell + push, city_street * 0.5 / city_block, aa);
			float band = clamp(lit_mask - street, 0.0, 1.0) * (1.0 - smoothstep(0.35, 0.9, night_factor));
			city = mix(city, city_street_color, street * 0.85 + avenue * 0.5);
			city *= 1.0 - band * 0.45;
			base = mix(base, city, built);
			// Street lights on the grid, windows on the blocks, brighter downtown than out in
			// the suburbs. One noise tap decides which lots are lit at all, so the field reads
			// as a scatter of points rather than as an even orange wash.
			float windows = smoothstep(0.35, 0.80, vnoise(w * 0.09)) * (1.0 - street);
			float lamps = street * 0.55 + avenue * 0.25;
			// MacroMap bakes the denser districts darker, so the darker the ground the more
			// lit it gets: downtown blazes, the far suburbs are a sparse orange dust.
			float density = clamp((0.042 - dot(m.rgb, vec3(0.3333))) / 0.013, 0.30, 1.0);
			glow = city_light_color * (city_light_strength * built * density
				* (lamps + windows * 0.85) * smoothstep(0.08, 0.55, night_factor));
		}

		// ---- lighting ------------------------------------------------------------------
		// Does this point see the sun? March the baked height field toward it. A range shading
		// its own flank, and throwing a shadow across the ground behind it, is most of what
		// makes a mountain look like a mountain rather than a painted cut-out.
		float sun_vis = 1.0;
		if (rich && shadow_steps > 0 && m.a > 0.0005) {
			float horiz = max(length(L.xz), 0.05);
			float climb = L.y / horiz;
			vec2 step_dir = L.xz / horiz;
			float ray_h = m.a * macro_height;
			for (int i = 1; i <= 16; i++) {
				if (i > shadow_steps) {
					break;
				}
				// Geometric spacing: fine near the point, coarse out where only a whole range
				// can still block the sun.
				float t = shadow_reach * pow(float(i) / float(shadow_steps), 2.0);
				float hs = texture(macro_height_tex, macro_uv(w + step_dir * t)).r * macro_height;
				sun_vis = min(sun_vis, smoothstep(-8.0, 42.0, ray_h + climb * t - hs));
			}
			sun_vis = mix(1.0, sun_vis, shadow_strength);
		}
		sun_vis *= cloud_shade(w, L);
		float ndl = max(dot(n, L), 0.0);
		// Sky fill from above, warm bounce from below: a slope facing away from the sun is lit
		// by the sky and by the ground in front of it, not by a flat grey constant.
		lit = sun_color * mix(vec3(1.0), sky, 0.18) * (sun_strength * ndl * sun_vis)
			+ sky * (ambient_strength * (0.55 + 0.45 * n.y))
			+ bounce_color * (bounce_strength * max(-dot(n, vec3(L.x, -L.y, L.z)), 0.0));
	}

	// Under the player's feet this is just ground, so the real texture takes over, tinted by
	// whatever the macro map says is down there (sand on a beach, green on a hillside).
	// Never blend the grass detail over open water.
	vec3 nm = vec3(0.5, 0.5, 1.0);
	if (near > 0.002) {
		// Use the detail texture for its light and shade only, not its colour: it is a grass
		// photograph, and letting its green through painted a green verge along the beach and
		// over the sea. The synthesized ground colour stays in charge.
		vec3 detail = texture(near_albedo, w / near_scale).rgb;
		float lum = dot(detail, vec3(0.3333));
		base = mix(base, base * (0.70 + 0.62 * lum), near);
		nm = mix(nm, texture(near_normal, w / near_scale).rgb, near);
	}

	float hz = smoothstep(haze_start, haze_end, dist) * haze_strength;
	float dim = mix(1.0, 0.16, night_factor);
	vec3 albedo = mix(base, haze_color, hz) * dim;
	vec3 emitted = mix(base * lit, haze_color, hz) * dim + glow * (1.0 - hz);
	if (smog > 0.002) {
		float under = 1.0 - smoothstep(smog_lid * 0.35, smog_lid, world_pos.y);
		float sm = smog * under * (1.0 - exp(-dist / smog_reach));
		albedo = mix(albedo, smog_color * dim, sm);
		emitted = mix(emitted, smog_color * dim, sm);
	}

	// Beyond the detail band this plane is a painted horizon, not a surface: past the near band
	// it is EMITTED at face value, so the sun, sky, self-shadow and cloud terms computed above
	// are the final answer and a blue midday ambient cannot wash grass, sand and tarmac into
	// one grey-blue. The Environment's aerial-perspective fog still does the distance wash on
	// top of it. Inside the near band it goes through ALBEDO instead and the renderer lights it,
	// so it matches the streamed chunks it is butted up against. Splitting the colour into an
	// unlit `base` and a `lit` term is what lets one shader do both without double-lighting the
	// near ground or leaving the far ground at the mercy of the ambient.
	float painted = smoothstep(near_fade_end * 0.6, near_fade_end * 1.8, dist);
	float rim = smoothstep(edge_start, edge_end, length(world_pos.xz - eye.xz));
	ALBEDO = albedo * (1.0 - painted) * (1.0 - rim);
	EMISSION = mix(emitted * painted, sky_tint.rgb, rim);
	ROUGHNESS = mix(rough, 1.0, (1.0 - near) * 0.25);
	METALLIC = 0.0;
	SPECULAR = mix(0.15, 0.55, water);
	NORMAL = normalize((VIEW_MATRIX * vec4(mix(vec3(0.0, 1.0, 0.0), n, 1.0 - near * 0.85), 0.0)).xyz);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = near * 0.7;
}
