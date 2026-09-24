shader_type spatial;
render_mode cull_back;

// Far buildings: one MultiMesh of unit boxes scaled to each part. Everything here has to come
// out of the fragment shader - there is no geometry to spend - so the job is to give a box the
// four things that make a real skyline read at 300-900 m: a FACADE TYPOLOGY (a curtain-wall
// tower and a brick low-rise look nothing like each other), GLAZING THAT CATCHES LIGHT (a sky
// reflection by fresnel and a sun glare lobe - glass flaring is most of what a city at distance
// actually is), VALUE CONTRAST between buildings, and STRUCTURE instead of noise (spandrel
// bands, mullions, corner piers, a crown, a parapet) so the eye reads floors and columns rather
// than a printed grid.
//
// Instance COLOR is the facade colour; INSTANCE_CUSTOM is
// (window style / 4, lit ratio, seed, plain flag: 1 = no windows, e.g. a plinth).
// The facade colour is also the typology signal: Building picks it from a palette per finish
// (GLASS_COLORS are dark, BRICK_COLORS warm, PANEL_COLORS mid grey, FLAT_COLORS bright), so the
// finish can be recovered from the colour plus the window style without any extra instance data.
// Per-chunk dissolve, driven by CityChunk.begin_fade_out(). 1.0 is solid, 0.0 is gone.
// A hash dither + discard rather than alpha: this keeps the boxes in the OPAQUE pass, so a
// dissolving chunk costs no sorting and cannot draw through the detailed buildings behind it.
// That is how a LOD swap is hidden in a big open-world game - the coarse version thins out
// over a few frames instead of vanishing between two.
// NOTE the material carrying this is shared by every LOD chunk (PropFactory caches it), so a
// chunk that is fading gets its OWN duplicate - see CityChunk.begin_fade_out().
uniform float chunk_fade : hint_range(0.0, 1.0) = 1.0;

global uniform float night_factor;
// Points TOWARDS the sun (DayNight publishes the sun's +Z). Drives the glare lobe on glazing
// and the direction rooftop plant throws its shadow.
global uniform vec3 sun_direction;
// The sky colour DayNight is currently showing. What the glazing mirrors.
global uniform vec4 sky_tint;
// Whether this renderer needs the instance colour decoded from sRGB. PropFactory sets it from
// has_reflections(): true on Forward+ and Mobile, false on Compatibility (web, opengl3 shots).
// (It was declared for months and never set or read - the far city was drawn 1.4-4.3x brighter
// than the same buildings up close on the Mac, and changed value as each block crossed the LOD
// line. Set and applied since the distance pass, 2026-09-24.)
// Godot sRGB-decodes a `source_color` uniform but NOT a MultiMesh instance colour - the repo's
// own two-renderer probe (header of shaders/foliage_tex.gdshader) found COLOR arriving identical
// in both renderers, which is what proves it skips the decode. So on Forward+ this shader is
// handed the palette entry raw while shaders/building.gdshader gets the same entry decoded, and
// the two paint the same wall apart by the palette's own ratio: FLAT_COLORS' 0.80/0.76/0.68
// arrives here at luminance 0.763 against the decoded 0.544 (1.4x), PANEL 1.5x, BRICK 2.6x and
// GLASS_COLORS' 0.18/0.28/0.42 4.3x, because the decode bites hardest on dark colours. On
// Compatibility neither shader decodes, they already agree, and decoding here would break that -
// hence the flag rather than an unconditional convert.
// Apply it where `c` is used as albedo, NOT before the typology test below: that test's
// thresholds (maxc 0.44 - 0.56, lum > 0.60) are tuned to the raw palette numbers, and decoded
// first, BRICK_COLORS' 0.62/0.30/0.22 has maxc 0.342 and every brick low-rise classifies as a
// curtain-wall tower.
uniform bool instance_color_is_srgb = false;

// --- Facade grid ---
// Storey height in metres. Floors are measured up from the part's own bottom.
uniform float floor_height = 3.4;
// Window bay spacing in metres for punched and precast facades.
uniform float window_pitch = 2.6;
// Mullion spacing on a curtain wall (metres). Curtain walls are gridded far finer than a
// punched facade, and that difference in rhythm is half of what tells the two apart.
uniform float curtain_pitch = 1.55;
// How far the window glass sits behind the wall face (metres). Drives the parallax shift.
uniform float recess = 0.35;

// --- Glazing ---
uniform vec3 lit_color : source_color = vec3(1.0, 0.85, 0.55);
// Reflectivity of glass head-on and at a grazing angle. Capped well short of a mirror: at
// 900 m every tower face is near-grazing, and at 0.9 the whole skyline turns into sky and
// the buildings vanish (this is the "see-through cage" the old shader gave up specular over).
uniform float glass_mirror_min = 0.26;
uniform float glass_mirror_max = 0.62;
// How much of the mirror is EMITTED rather than painted into the albedo, and how bright, as in
// building.gdshader (keep the two level or a tower changes brightness at the LOD line). A
// reflection does not depend on the light falling on the pane: carried in the albedo alone, a
// far glass tower on the shaded side came out a black slab against a lit sky.
uniform float reflect_emit = 0.7;
uniform float reflect_energy = 1.6;
// The sun glare path across the glazing, in two lobes. The tight one is the mirror flash a
// tower throws when its face happens to bisect the eye and the sun; the broad one is the sheen
// every pane on that side of the building carries. This is the single thing that makes a
// distant tower read as glass rather than as a painted box, and one lobe is not enough: a tight
// lobe alone fires on maybe one facade in twenty and the rest of the skyline stays matte.
uniform float glass_glare = 3.4;
uniform float glass_glare_tightness = 64.0;
uniform float glass_glare_broad = 0.85;
uniform float glass_glare_broad_tightness = 2.6;
// How dark the shadow a mullion or a projecting sun fin throws across the pane next to it. This
// is the cheapest depth cue on a glass facade and the one that reads furthest away.
uniform float fin_shadow = 0.24;
// How bright the room behind the glass is against daylight. Rooms read dark from outside, but
// not black: pure black openings make a facade read as perforated sheet, and they are also a
// long way from the value shaders/building.gdshader puts in the same window, which is what a
// LOD swap must not do.
uniform float glass_interior = 0.60;

// --- Value and variety ---
// Per-building brightness spread on the opaque wall (0 = every facade the palette value).
// A skyline is made of value contrast; the palette alone does not give enough.
uniform float value_spread = 0.26;
// How much darker a curtain-wall tower and how much brighter a stone one read than the palette
// alone says. Value contrast BETWEEN buildings is what a skyline is made of; spent inside one
// facade it just reads as a barcode, so it goes here and the bands below are kept gentle.
uniform float typology_value = 0.17;
// Width in metres of the solid corner pier, and how much lighter it reads than the wall face.
uniform float corner_pier = 0.95;
uniform float corner_light = 1.16;
// Width in metres of the bright arris line right on the box edge. This is what draws a tower's
// silhouette out of the haze; below about 0.08 m it disappears into the mip at distance.
uniform float arris_width = 0.16;
// How many storeys the crown band covers, and how much lighter or darker it is than the shaft.
uniform float crown_floors = 1.7;
uniform float crown_shade = 0.86;
// Height in metres of the heavier base course at the bottom of each part.
uniform float base_height = 6.4;
// Grime: soot at the bottom of the wall and streaks running down from the window sills.
uniform float grime = 0.55;

// --- Roof ---
// Parapet width in metres around the roof edge.
uniform float parapet_width = 0.85;
// Rooftop plant printed on the roof: cell size in metres, how many cells get a unit, and how
// long a shadow it throws. Roofs are most of what a flying player sees and half of any wide
// shot taken from above, so the clutter is worth the instructions.
uniform float clutter_cell = 7.0;
uniform float clutter_density = 0.62;
uniform float clutter_shadow = 0.22;

// --- Detail fade ---
// A feature is drawn only once its period spans this many pixels; below it the detail would
// alias into static. Everything here is sized in metres, so this is the stand-in for a mipmap.
uniform float detail_px_min = 1.2;
uniform float detail_px_full = 3.2;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 box_size;
varying vec4 custom;
varying vec4 tint;
varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 world_tangent;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float hash31(vec3 p) {
	return hash21(vec2(hash21(p.xy), p.z));
}


// How much of a feature of this period (metres) survives at the current pixel footprint.
float detail(float period, float mpp) {
	return smoothstep(detail_px_min, detail_px_full, period / max(mpp, 1e-5));
}


void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	box_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	custom = INSTANCE_CUSTOM;
	tint = COLOR;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Matches how `u` is measured below: local Z on the +-X faces, local X on the +-Z faces.
	vec3 t_local = abs(NORMAL.x) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	world_tangent = normalize((MODEL_MATRIX * vec4(t_local, 0.0)).xyz);
}


void fragment() {
	// NOTE: named chunk_fade, not fade - this shader already uses a local `fade` for the
	// close-up detail blend further down, and a second one silently killed the WHOLE shader
	// compile ("Redefinition of 'fade'"), which falls back to blank white on every far
	// building. The headless gate passed 210/210 while that was true.
	float dissolve = chunk_fade * tint.a;
	if (dissolve < 0.999) {
		// Interleaved-gradient noise: cheap, stable per pixel, and it breaks into a fine grain
		// rather than the banding a plain ordered matrix gives on a big flat facade.
		float d = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (dissolve < d) {
			discard;
		}
	}
	vec3 n = normalize(local_normal);
	// The palette entry as Building picked it (the typology test below is tuned to these numbers),
	// and the same colour in the space this renderer lights in - see instance_color_is_srgb. The
	// far city's ground plates already carry linear colours (CityChunk.far_tint), like the LOD
	// chunks' merged ground, and are left alone.
	vec3 c_raw = tint.rgb;
	vec3 c = (instance_color_is_srgb && custom.a < 1.5)
		? mix(c_raw / 12.92, pow((c_raw + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c_raw))
		: c_raw;
	float bseed = custom.b;
	vec3 albedo = c;
	float rough = 0.85;
	vec3 emission = vec3(0.0);
	float spec = 0.25;

	// Wall space, computed branch-free so the derivatives below are well defined.
	float side = step(0.5, abs(n.x));
	float wall_w = mix(box_size.x, box_size.z, side);
	float u = mix(local_pos.x, local_pos.z, side) * wall_w + 0.5 * wall_w;
	float v = (local_pos.y + 0.5) * box_size.y;
	// Metres per pixel on this fragment: the stand-in for a mip level.
	float mpp = max(fwidth(u), fwidth(v));

	vec3 to_frag = normalize(world_pos - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	vec3 sun_n = normalize(sun_direction);
	float day = 1.0 - night_factor;

	if (abs(n.y) > 0.5) {
		// ---------------------------------------------------------------- Roof ------------
		// Metres from the roof centre, and how far in from the nearest edge.
		vec2 p = local_pos.xz * box_size.xz;
		vec2 e = box_size.xz * 0.5 - abs(p);
		float edge = min(e.x, e.y);
		float parapet = 1.0 - step(parapet_width, edge);

		// Covering, drawn from the same odds Building rolls (42 % membrane, 34 % gravel,
		// 24 % bitumen) so the skyline seen from above has the same mix of bright and dark
		// roofs as the detailed chunks do.
		float rr = hash21(vec2(bseed * 91.0, 5.7));
		vec3 surface;
		if (rr < 0.42) {
			// White single-ply membrane, rolled in strips and welded, grey where water ponds.
			surface = vec3(0.80, 0.80, 0.77);
			float strip = fract(p.x * 0.5 + hash21(vec2(bseed, 2.0)));
			surface *= 1.0 - 0.10 * smoothstep(0.06, 0.0, min(strip, 1.0 - strip)) * detail(2.0, mpp);
			surface *= 0.86 + 0.20 * hash21(floor(p * 0.32) + bseed);
			rough = 0.80;
		} else if (rr < 0.76) {
			vec3 gravel = mix(vec3(0.40, 0.39, 0.37), c, 0.22);
			gravel *= 0.90 + 0.20 * hash21(floor(p * 1.1) + bseed) * detail(0.9, mpp);
			gravel *= 0.92 + 0.16 * hash21(floor(p * 0.22) + bseed * 3.0);
			surface = gravel;
			rough = 0.95;
		} else {
			// Patched bitumen. Kept off the floor: a roof that renders at 0.10 reads as a hole
			// punched in the building rather than as a dark deck.
			surface = vec3(0.155, 0.150, 0.142);
			float patch = hash21(floor(p * 0.45) + bseed);
			surface *= 0.86 + 0.55 * patch;
			rough = mix(0.5, 0.95, patch);
		}

		// Rooftop plant: air handlers, cooling towers, duct runs and stair bulkheads, printed
		// as boxes with a cast shadow toward the sun's far side. A flat grey roof is the
		// loudest tell that a mid-distance city is a set of extruded rectangles.
		vec2 sun_xz = sun_n.xz;
		float sun_len = length(sun_xz);
		vec2 sh_dir = sun_len > 1e-3 ? -sun_xz / sun_len : vec2(0.7, 0.7);
		vec2 cellf = p / clutter_cell;
		vec2 cell = floor(cellf);
		vec2 f = fract(cellf);
		float ch = hash21(cell * 1.7 + bseed * 57.0);
		if (ch < clutter_density && edge > parapet_width + 0.6) {
			vec2 c0 = vec2(hash21(cell + 1.3), hash21(cell + 7.7)) * 0.30 + 0.35;
			float wide = step(0.74, hash21(cell + 4.1));
			vec2 hs = vec2(0.07 + 0.10 * hash21(cell + 3.3), 0.07 + 0.10 * hash21(cell + 9.1));
			// One in four is a long duct run rather than a unit.
			hs = mix(hs, vec2(0.26, 0.045), wide);
			vec2 sh_off = sh_dir * clutter_shadow;
			vec2 ds = abs(f - c0 - sh_off);
			float shadow = step(ds.x, hs.x) * step(ds.y, hs.y);
			vec2 d = abs(f - c0);
			float inside = step(d.x, hs.x) * step(d.y, hs.y);
			float fade = detail(clutter_cell * 0.30, mpp);
			// Galvanised plant reads brighter than membrane and far brighter than bitumen: it
			// is the sparkle on a roof deck, so it must not end up darker than what it sits on.
			vec3 unit = mix(vec3(0.62, 0.62, 0.60), vec3(0.80, 0.79, 0.76), hash21(cell + 11.3));
			// A darker lip round the unit reads as its shaded side without cutting the box in
			// half on a diagonal, which looked like a hole punched in the roof.
			float lip = 1.0 - step(max(d.x - hs.x * 0.72, d.y - hs.y * 0.72), 0.0);
			surface = mix(surface, unit * mix(1.0, 0.76, lip), inside * fade);
			surface *= mix(1.0, 0.62, clamp(shadow - inside, 0.0, 1.0) * fade);
			rough = mix(rough, 0.52, inside * fade);
		}

		// Parapet cap, and the shade it throws on the deck just inside it.
		vec3 cap = mix(c, vec3(0.72, 0.71, 0.69), 0.5) * 1.04;
		surface = mix(surface, cap, parapet);
		surface *= mix(1.0, 0.86, (1.0 - parapet) * (1.0 - smoothstep(parapet_width, parapet_width + 1.4, edge)));
		albedo = surface;
		spec = 0.15;
	} else if (custom.a > 0.5) {
		// ---------------------------------------------------------- Plinth / plain -------
		// Board-formed concrete: horizontal form lines, a tie-hole grid, and street soot.
		float band = fract(v / 1.2);
		albedo = c * (0.94 + 0.12 * hash21(vec2(floor(u / 2.4), floor(v / 1.2)) + bseed));
		albedo *= 1.0 - 0.13 * smoothstep(0.09, 0.0, min(band, 1.0 - band)) * detail(1.2, mpp);
		float tie = step(hash21(vec2(floor(u / 1.2), floor(v / 1.2)) + bseed * 7.0), 0.30);
		albedo *= 1.0 - 0.10 * tie * detail(1.2, mpp);
		albedo *= mix(0.72, 1.0, smoothstep(0.0, 3.0, v));
		rough = 0.92;
	} else {
		// ------------------------------------------------------------- Facade ------------
		float style = custom.r * 4.0;
		float maxc = max(c_raw.r, max(c_raw.g, c_raw.b));
		float minc = min(c_raw.r, min(c_raw.g, c_raw.b));
		float lum = dot(c_raw, vec3(0.299, 0.587, 0.114));
		float warm = c_raw.r - c_raw.b;
		float sat = maxc - minc;

		// Typology. 0 curtain wall, 1 precast panel, 2 stone / stucco punched, 3 brick.
		// Recovered from the palette the facade colour came out of plus the window style: a
		// dark facade or a curtain grid means glass, a warm saturated one means brick, a
		// bright one means stone or stucco, and what is left is precast.
		float glassy = (1.0 - smoothstep(0.44, 0.56, maxc)) + (abs(style - 2.0) < 0.5 ? 0.55 : 0.0);
		int typ;
		if (glassy > 0.80) {
			typ = 0;
		} else if (warm > 0.14 && sat > 0.15 && lum < 0.58) {
			typ = 3;
		} else if (lum > 0.60) {
			typ = 2;
		} else {
			typ = 1;
		}

		// Per-building value shift, so two stone towers side by side are not the same grey,
		// plus a push apart by typology: glass towers sit dark in the frame and masonry ones
		// bright, which is the value structure a real skyline has.
		float vshift = 1.0 + value_spread * (hash21(vec2(bseed * 13.0, 3.3)) * 2.0 - 1.0);
		vshift *= 1.0 + typology_value * (typ == 0 ? -1.0 : (typ == 2 ? 1.0 : (typ == 3 ? -0.35 : 0.15)));

		// The sky in the glass and the glare path to the sun, computed once: the glazing needs
		// them, the spandrel and metal panels need a weaker version, and the distance blend at
		// the bottom of this branch needs the average of glass and wall.
		vec3 refl = reflect(to_frag, world_normal);
		vec3 sky_hi = sky_tint.rgb * 1.05;
		vec3 sky_lo = sky_tint.rgb * 0.50 + vec3(0.05, 0.05, 0.06);
		vec3 sky_ref = mix(sky_lo, sky_hi, smoothstep(0.0, 0.50, refl.y));
		sky_ref = mix(vec3(0.055, 0.055, 0.065), sky_ref, smoothstep(-0.22, 0.08, refl.y));
		float fres = pow(1.0 - clamp(-dot(to_frag, world_normal), 0.0, 1.0), 4.0);
		float mirror = mix(glass_mirror_min, glass_mirror_max, fres) * (1.0 - 0.85 * night_factor);
		float sky_now = clamp(dot(sky_tint.rgb, vec3(0.299, 0.587, 0.114)) / 0.74, 0.0, 1.5);
		vec3 refl_emit = sky_ref * mirror * reflect_emit * reflect_energy * sky_now;
		float to_sun = max(dot(refl, sun_n), 0.0);
		float facing = max(dot(world_normal, sun_n), 0.0);
		vec3 glare = vec3(1.0, 0.96, 0.88)
			* (pow(to_sun, glass_glare_tightness) * glass_glare
				+ pow(to_sun, glass_glare_broad_tightness) * glass_glare_broad) * day;
		// Storey height varies building to building the way Building's does (3.1 - 4.0 m).
		float fh = floor_height * (0.92 + 0.22 * hash21(vec2(bseed * 29.0, 1.1)));
		float bay = (typ == 0) ? curtain_pitch : window_pitch * (typ == 3 ? 0.85 : 1.0);
		float face_id = abs(n.x) > 0.5 ? (n.x > 0.0 ? 1.0 : 2.0) : (n.z > 0.0 ? 3.0 : 4.0);

		// Parallax: shift where the grid is sampled by the view direction, as if the glass sat
		// `recess` metres behind the wall. Not full interior mapping - too expensive for a
		// whole skyline - but it is what stops far windows reading as stickers.
		vec3 tan_dir = normalize(world_tangent - world_normal * dot(world_tangent, world_normal));
		float into = max(-dot(to_frag, world_normal), 0.08);
		vec2 shift = vec2(dot(to_frag, tan_dir), dot(to_frag, vec3(0.0, 1.0, 0.0))) * (recess / into);
		float pu = u + shift.x;
		float pv = v + shift.y;

		float col = floor(pu / bay);
		float row = floor(pv / fh);
		float fu = fract(pu / bay);
		float fv = fract(pv / fh);
		float top_d = box_size.y - v;
		float edge_u = min(u, wall_w - u);

		// Corner pier and crown are solid on every typology: a real tower turns the corner in
		// wall, not in glass, and almost all of them change material at the top. All three
		// bands are capped as a fraction of the part, because most LOD boxes in the outer
		// districts are eight-metre houses, not towers, and a fixed 5.8 m crown on one of
		// those leaves a blank box with two rows of windows at its feet.
		float pier_w = min(corner_pier, wall_w * 0.16);
		bool pier = edge_u < pier_w;
		float crown_h = min(crown_floors * fh, box_size.y * 0.20);
		bool crown = top_d < crown_h;
		float base_h = min(base_height, box_size.y * 0.26);
		bool basec = v < base_h;
		// A mechanical floor two storeys down from the crown on anything tall: a solid louvred
		// band. It is the horizontal accent that stops a tall box being one texture top to
		// bottom.
		bool mech = box_size.y > 46.0 && top_d > crown_h && top_d < crown_h + 1.25 * fh;

		float glass = 0.0;       // 1 where the pane is
		float mullion = 0.0;     // 1 on the framing
		float colline = 0.0;     // 1 on a structural column line (shaded in wall, not in metal)
		float reveal = 0.0;      // 0..1 shading in the jamb / head of a punched opening
		float win_top = 0.95;    // fv of the head of the opening, for the transom shadow
		// How much of the storey-scale and bay-scale structure a pixel can still resolve.
		float band_fade = detail(fh, mpp);

		if (!pier && !crown && !mech && !basec) {
			if (typ == 0) {
				// Curtain wall: a vision band with a spandrel panel between floors and a
				// mullion every bay. How much of the storey is glass is taken from the window
				// style the near shader will use when this chunk swaps to FULL - a curtain
				// grid there is glass almost wall to wall, a ribbon is a band, a punched
				// facade is a hole - so a tower does not gain or lose half its glazing at the
				// chunk boundary. The spandrel is still half a metre, which is plenty to read
				// as a horizontal rhythm at a kilometre.
				float vis_lo = 0.22;
				float vis_hi = 0.72;
				if (abs(style - 2.0) < 0.5) {
					vis_lo = 0.08;
					vis_hi = 0.93;
				} else if (abs(style - 1.0) < 0.5) {
					vis_lo = 0.17;
					vis_hi = 0.78;
				}
				win_top = vis_hi;
				glass = step(vis_lo, fv) * step(fv, vis_hi);
				float mw = 0.10 * detail(bay, mpp);
				mullion = step(fu, mw) + step(1.0 - mw, fu);
				// A heavier column line every fourth bay, where the structure is. It stops the
				// glazing like a mullion does, but it is shaded in wall rather than in dark
				// metal below: at mullion darkness these read as black scratches ruled down
				// the tower instead of as a structural bay rhythm.
				colline = step(abs(fract(col / 4.0)), 0.001) * step(fu, 0.20) * detail(bay * 4.0, mpp);
				mullion = clamp(mullion + colline, 0.0, 1.0);
				glass *= 1.0 - mullion;
			} else if (typ == 1) {
				// Precast panel: one panel per bay per floor with a recessed joint all round,
				// and either a ribbon window or a punched one inside it.
				float jw = 0.055 * detail(bay, mpp);
				float jh = 0.05 * detail(fh, mpp);
				mullion = clamp(step(fu, jw) + step(1.0 - jw, fu) + step(fv, jh), 0.0, 1.0);
				if (abs(style - 1.0) < 0.5) {
					glass = step(0.30, fv) * step(fv, 0.76) * step(0.10, fu) * step(fu, 0.90);
					win_top = 0.76;
				} else {
					glass = step(abs(fu - 0.5), 0.29) * step(abs(fv - 0.56), 0.24);
					reveal = (1.0 - glass) * step(abs(fu - 0.5), 0.36) * step(abs(fv - 0.56), 0.31);
					win_top = 0.80;
				}
				glass *= 1.0 - mullion;
			} else if (typ == 2) {
				// Stone or stucco, punched: a lot of wall, a deep reveal, a sill.
				float hw = abs(style - 3.0) < 0.5 ? 0.15 : 0.25;
				glass = step(abs(fu - 0.5), hw) * step(abs(fv - 0.56), 0.26);
				reveal = (1.0 - glass) * step(abs(fu - 0.5), hw + 0.075) * step(abs(fv - 0.56), 0.335);
				win_top = 0.82;
			} else {
				// Brick: smaller openings again, plus a string course every fourth floor.
				float hw = 0.21;
				glass = step(abs(fu - 0.5), hw) * step(abs(fv - 0.58), 0.23);
				reveal = (1.0 - glass) * step(abs(fu - 0.5), hw + 0.06) * step(abs(fv - 0.58), 0.30);
				win_top = 0.81;
				float band = step(abs(fract(row / 4.0)), 0.001) * step(fv, 0.10);
				mullion = band * detail(fh * 4.0, mpp);
			}
		}
		// Nothing glazes below the first metre or above the last.
		glass *= step(1.2, v) * step(1.0, top_d);

		if (glass > 0.5) {
			// ----------------------------------------------------------- Glazing ----------
			float k = hash31(vec3(col, row, face_id * 17.0 + bseed * 41.0));
			// The room behind the pane, dark against daylight and varying floor to floor.
			vec3 room = (c * 0.30 + vec3(0.09, 0.10, 0.12)) * glass_interior;
			room *= 0.55 + 0.90 * hash31(vec3(col * 1.7, row, bseed * 31.0));
			// Blinds: a pale panel over the top of some rooms. At distance the only thing that
			// survives of an interior is that some panes are pale and most are not.
			float blind = step(0.68, hash31(vec3(row, col, bseed * 19.0)));
			// Halved and faded on the same schedule as everything else. At 2.6 a blind was a
			// five-fold value step against the room behind it, on a third of the bays, and it
			// was the one feature in this shader with no detail() gate - so it ran at full
			// contrast out to where a bay is two pixels wide and the tower turned into noise.
			room = mix(room, vec3(0.30, 0.29, 0.27) * glass_interior * 1.3, blind * step(0.42, fv) * detail(bay, mpp));

			// The sky in the glass, computed from the reflected ray rather than by raising
			// METALLIC: a metallic pane picks up the real environment map and whole
			// curtain-wall towers turn into see-through cages. Then the glare path to the sun -
			// a skyline photographed at any hour but noon has a handful of towers burning and
			// the rest in shade, and no amount of albedo detail substitutes for that.
			albedo = mix(room, sky_ref, mirror * (1.0 - reflect_emit)) + glare;

			// Shadows thrown ONTO the glass by the frame in front of it: the mullion (or a
			// projecting sun fin, which a third of curtain-wall towers wear) shades the pane
			// beside it, and the transom shades the top of it. Which side the shadow falls on
			// comes from the sun, so it swings round the building through the day. A pane with
			// nothing in front of it is the reason flat glazing reads as a printed grid: real
			// glass is always sitting behind something.
			float shade_side = sign(dot(tan_dir, sun_n));
			float su = shade_side > 0.0 ? fu : 1.0 - fu;
			float fin = mix(fin_shadow, fin_shadow * 2.1, step(0.62, hash21(vec2(bseed * 67.0, 4.4))));
			albedo *= 1.0 - fin * (1.0 - smoothstep(0.0, 0.22, su)) * day * detail(bay, mpp);
			albedo *= 1.0 - fin * 0.7 * (1.0 - smoothstep(0.0, 0.11, win_top - fv)) * day * detail(fh, mpp);
			emission += glare * 0.20 * facing;

			rough = 0.18;
			if (k < custom.g) {
				// Lit rooms. Whole floors light up as well as single rooms, which is what an
				// office tower at dusk looks like - but only after dark: by day that read as a
				// handful of floors glowing under full sun.
				// See building.gdshader: no daytime floor, or every tower a few hundred metres
				// out keeps the gold-and-black checkerboard after the near one loses it.
				float on = night_factor;
				float whole = step(hash21(vec2(row, bseed * 77.0)), 0.10) * night_factor;
				on = min(1.0, on * (1.0 + whole));
				float glow = 0.55 + 0.45 * hash31(vec3(row + 7.0, col + 3.0, bseed));
				albedo = mix(albedo, lit_color, 0.70 * on);
				// 2.9, not 1.15. This lit_color is a source_color uniform too: (1.0, 0.85, 0.55)
				// decodes to (1.000, 0.692, 0.263), and on and glow both peak at 1.0, so a lit
				// window peaked at exactly 1.15 - under the Environment's glow_hdr_threshold of
				// 1.3 (glow_hdr_scale 2.0), so smoothstep(1.3, 3.3, 1.15) is 0 and the whole far
				// skyline only ever got the 0.06 glow_bloom floor, never the bloom.
				// This has to stay level with building.gdshader's lit_strength, whose lit_color
				// peaks at 1.0 after the decode for every entry in Building.LIT_COLORS: if the
				// two drift apart, a tower steps brightness the moment it crosses the LOD line.
				// Scaled with building.gdshader's lit_strength (1.2 -> 0.8): 2.9 -> 1.9, still over the
				// 1.3 glow threshold so the far skyline keeps its bloom.
				emission += lit_color * on * glow * 1.9;
				rough = 0.45;
			}
			spec = 0.42;
		} else {
			// ----------------------------------------------------------- Opaque wall ------
			vec3 wall = c * vshift;
			rough = 0.85;

			if (typ == 0) {
				// The spandrel is the panel that gives a curtain-wall tower its banding. Some
				// are a pale metal panel against dark glass, some a darker one: that choice
				// alone makes two towers of the same colour read as different buildings. Kept
				// well short of black-and-white - at full contrast a tall tower is a barcode.
				// Both options are kept near the value shaders/building.gdshader gives a glass
				// facade (facade_color * 0.6), so a banded LOD tower does not jump in
				// brightness the moment the chunk swaps to FULL.
				float pale = step(0.55, hash21(vec2(bseed * 53.0, 7.9)));
				wall = mix(c * 0.62 + vec3(0.012), c * 1.02 + vec3(0.075), pale) * vshift;
				wall *= 0.95 + 0.10 * hash21(vec2(col * 0.5, row) + bseed);
				rough = 0.42;
				spec = 0.34;
			} else if (typ == 1) {
				wall *= 0.93 + 0.14 * hash21(vec2(col, row) + bseed) * detail(bay, mpp);
				rough = 0.80;
			} else if (typ == 2) {
				// Ashlar: a coursed stone grid, wide and shallow, fading out with distance.
				float cy = floor(v / 1.15);
				float bu = fract((u + mod(cy, 2.0) * 0.9) / 1.8);
				float bv = fract(v / 1.15);
				float joint = clamp(step(bu, 0.03) + step(bv, 0.05), 0.0, 1.0) * detail(1.15, mpp);
				wall *= 0.94 + 0.12 * hash21(vec2(floor(u / 1.8), cy) + bseed);
				wall = mix(wall, wall * 0.74, joint);
				rough = 0.88;
			} else {
				// Brick coursing. 25 cm courses are gone by 300 m, so they are faded out and
				// the per-bay shade variation carries the wall after that.
				float brow = floor(v / 0.26);
				float bu = fract((u + mod(brow, 2.0) * 0.31) / 0.62);
				float bv = fract(v / 0.26);
				float mortar = clamp(step(bu, 0.07) + step(bv, 0.15), 0.0, 1.0) * detail(0.26, mpp);
				wall *= 0.86 + 0.30 * hash21(vec2(floor((u + mod(brow, 2.0) * 0.31) / 0.62), brow) + bseed);
				wall = mix(wall, wall * 0.62 + vec3(0.03), mortar * 0.8);
				wall *= 0.96 + 0.08 * hash21(vec2(col, row) + bseed * 5.0);
				rough = 0.94;
			}

			// Mullions, panel joints and string courses. A column line is wall, not metal.
			wall = mix(wall, wall * mix(0.42, 0.86, colline) + vec3(0.02, 0.02, 0.022) * (1.0 - colline), mullion * 0.85);
			// The reveal around a punched opening: the head and one jamb fall into shade, the
			// sill catches light. This is what makes a small window read as a HOLE from 500 m,
			// and flat windows are the single loudest tell of a fake city.
			if (reveal > 0.5) {
				float side_u = step(0.5, fu) * 2.0 - 1.0;
				float lit_jamb = 0.5 + 0.5 * side_u * sign(dot(tan_dir, sun_n));
				float head = 1.0 - smoothstep(0.0, 0.10, abs(fv - 0.84));
				wall *= mix(0.72, 1.08, lit_jamb);
				wall *= 1.0 - 0.26 * head;
				wall *= 1.0 + 0.22 * (1.0 - smoothstep(0.0, 0.07, abs(fv - 0.30)));
				rough = min(1.0, rough + 0.05);
			}

			// The slab edge at every floor: a faint band that gives a tower its horizontal
			// rhythm even where the windows are too small to resolve.
			wall *= 1.0 - 0.09 * smoothstep(0.09, 0.0, fv) * detail(fh, mpp);

			// Base course: a heavier material for the bottom storeys, with deep joints. Granite
			// on a pale facade, dark polished stone on a dark one - a bright stone plinth
			// pasted under a navy tower reads as a second, whiter building at its feet.
			if (basec) {
				float cy = floor(v / 0.95);
				float joint = clamp(step(fract(v / 0.95), 0.055) + step(fract((u + mod(cy, 2.0) * 0.47) / 1.9), 0.02), 0.0, 1.0);
				vec3 stone = mix(c * 0.66 + vec3(0.03), mix(c, vec3(0.58, 0.56, 0.52), 0.40), step(0.40, lum));
				stone *= vshift * (0.90 + 0.16 * hash21(vec2(cy, floor(u / 1.9)) + bseed));
				stone = mix(stone, stone * 0.58, joint * detail(0.95, mpp));
				// A shadow line where the base course stops.
				stone *= 1.0 - 0.30 * smoothstep(0.6, 0.0, base_h - v);
				wall = stone;
				rough = 0.90;
			}
			// Mechanical floor: a louvred band, dark, with fine vertical blades.
			if (mech) {
				float blade = step(0.45, fract(u / 0.34)) * detail(0.34, mpp);
				wall = mix(c * 0.34, c * 0.52, blade) + vec3(0.01);
				rough = 0.55;
				spec = 0.3;
			}
			// Crown: a shade change over the top storeys plus a parapet cap, so the tower has
			// a top instead of just stopping.
			if (crown) {
				wall *= mix(1.0, crown_shade, smoothstep(crown_h, crown_h * 0.35, top_d));
				float cap = 1.0 - smoothstep(0.0, 0.9, top_d);
				wall = mix(wall, mix(c, vec3(0.70, 0.69, 0.66), 0.45) * 1.06, cap);
				wall *= 1.0 - 0.22 * (1.0 - smoothstep(0.9, 1.7, top_d)) * (1.0 - cap);
			}
			// Corner pier, and the bright arris right on the edge that draws the silhouette.
			if (pier) {
				wall *= mix(1.0, corner_light, smoothstep(pier_w, pier_w * 0.3, edge_u));
			}
			// Widened to at least a pixel and a half: a fixed 16 cm highlight is a fifth of a
			// pixel at 800 m, and the thing it is there to do - draw the tower's edge out of the
			// haze - is exactly what is needed most at 800 m.
			float aw = max(arris_width, mpp * 1.5);
			wall *= 1.0 + 0.45 * (1.0 - smoothstep(0.0, aw, edge_u));

			// Weathering. Soot at street level, and rain drawing dirt down from every sill.
			float ground_dirt = (1.0 - smoothstep(0.0, 7.5, v)) * (0.6 + 0.4 * hash21(vec2(floor(u * 1.3), face_id) + bseed));
			float sill_y = floor(v / fh) * fh + 0.30 * fh;
			float below = v < sill_y ? sill_y - v : sill_y + fh - v;
			float run = (1.0 - smoothstep(0.0, 2.4, below)) * smoothstep(0.0, 0.14, below);
			float across = 1.0 - smoothstep(0.20, 0.46, abs(fu - 0.5));
			float drips = step(0.40, hash21(vec2(col, row + face_id * 3.0) + bseed));
			float streak = run * across * drips * (0.45 + 0.55 * hash21(vec2(floor(u * 9.0), face_id) + bseed))
				* detail(bay * 0.5, mpp);
			float dirt = grime * clamp(0.55 * ground_dirt + 0.70 * streak, 0.0, 1.0);
			wall = mix(wall, wall * vec3(0.47, 0.45, 0.43), dirt);
			rough = min(1.0, rough + 0.16 * dirt);

			// A weak glare on the panel work too: spandrel and metal cladding catch the sun
			// just after the glass does, which is what keeps a banded tower from going flat.
			wall += glare * (typ <= 1 ? 0.16 : 0.05);
			albedo = wall;
		}

		// Walls pick up more sky light higher up.
		albedo *= mix(0.88, 1.07, clamp(v / max(box_size.y, 1.0), 0.0, 1.0));

		// Distance blend. Under about three pixels a storey the bands, panes and mortar stop
		// being structure and become static, so the facade is faded toward its own average -
		// the glazing fraction of the glass tone over the wall tone. This is the mipmap the
		// procedural grid does not have, and without it every far tower buzzes.
		float glaze_frac = (typ == 0) ? (abs(style - 2.0) < 0.5 ? 0.80 : (abs(style - 1.0) < 0.5 ? 0.55 : 0.45))
			: (typ == 1 ? 0.26 : (typ == 2 ? 0.15 : 0.12));
		vec3 mean_glass = mix((c * 0.30 + vec3(0.09, 0.10, 0.12)) * glass_interior, sky_ref, mirror * (1.0 - reflect_emit)) + glare;
		vec3 mean_wall = c * vshift * (typ == 0 ? 0.95 : 0.97) + glare * (typ <= 1 ? 0.16 : 0.05);
		vec3 mean = mix(mean_wall, mean_glass, glaze_frac) * mix(0.88, 1.07, clamp(v / max(box_size.y, 1.0), 0.0, 1.0));
		albedo = mix(mean, albedo, mix(0.30, 1.0, band_fade));
		// The emitted mirror, faded to its facade average on the same schedule, or the panes
		// would buzz at distance in emission after the albedo had stopped.
		emission += refl_emit * mix(glaze_frac, glass, mix(0.30, 1.0, band_fade));
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	// Dielectric only, and tamed: with metal the sky reflection at grazing angles turned whole
	// towers see-through (a cage of wall strips). The glazing gets its reflection painted into
	// ALBEDO above instead, which is also the only version the web renderer sees.
	SPECULAR = spec;
	EMISSION = emission;
}
