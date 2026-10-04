shader_type spatial;
// skip_vertex_transform: a coded building part (FarBuilding) is rebuilt from its basis's
// diagonal, because the off-diagonals carry its facade code, not a shear (see vertex()).
render_mode cull_back, skip_vertex_transform;

// Far buildings: one MultiMesh of unit boxes scaled to each part. Everything here has to come
// out of the fragment shader - there is no geometry to spend - so the job is to give a box the
// four things that make a real skyline read at 300-900 m: a FACADE TYPOLOGY (a curtain-wall
// tower and a brick low-rise look nothing like each other), GLAZING THAT CATCHES LIGHT (a sky
// reflection by fresnel and a sun glare lobe - glass flaring is most of what a city at distance
// actually is), VALUE CONTRAST between buildings, and STRUCTURE instead of noise (spandrel
// bands, mullions, corner piers, a crown, a parapet) so the eye reads floors and columns rather
// than a printed grid.
//
// THE FAR CITY'S BUILDINGS (2026-10-04, docs/HANDOFF.md 9az): every Building part is a CODED
// box (INSTANCE_CUSTOM.a -1, FarBuilding): its basis carries the near building's own facade data
// in its off-diagonals - window style, finish, roof covering, the palette entries of its glass
// tint, lit colour and frame paint, storefront and shop runs, bays and storeys (the near walls'
// own grid, Building.part_grid()), base course, crown, plinth and parapet, its seed for the lit
// offices (window_lights.gdshaderinc, shared with building.gdshader) - and is drawn here as the
// near walls draw it, cell for cell, faded to its own average once a cell is under a few pixels.
// Its roof plant is real boxes (INSTANCE_CUSTOM.a 4). Everything below the coded branch is the
// older path, for what is not a Building: the replica houses, the estates, slabs, plates, decks.
//
// Old path: instance COLOR is the facade colour; INSTANCE_CUSTOM is
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
// Colour space. This shader draws what building.gdshader draws, and that one works in each
// renderer's own space, like every StandardMaterial: its colours arrive as `source_color`
// uniforms set from script, decoded on Forward+ and raw on Compatibility. So every colour here
// that stands for one of the near building's goes through cs_as_uniform() (color_space.gdshaderinc,
// the renderer told at compile time) - the instance colour, and the palettes the coded parts
// index (glass tints, lit colours, frame paints, Building's own constants) - and the arithmetic
// on them is the near shader's arithmetic in the same space, so a far wall and a near wall come
// out the same on both renderers. `instance_color_is_srgb` (PropFactory sets it from
// has_reflections()) is the same answer at run time, kept for the material checks.
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

// --- Ground: the far city's block plates and freeway decks (scripts/world/skyline.gd) ---
// INSTANCE_CUSTOM.a 2 is a block plate: one box over the area a chunk owns, its top in the block's
// average far-ground colour, with the chunk's two roads - on its +X and +Z sides, widths in
// .r and .g - painted on here. 3 is a freeway deck (.r its width): an asphalt carriageway.
// These are LINEAR, like the instance colours the plates carry (CityChunk.far_tint(), the same
// numbers the LOD chunks' merged ground is drawn in), so no source_color hint.
uniform vec3 plate_road_color = vec3(0.033, 0.033, 0.040);
// Where the horizon plane hands over to the sky (macro_ground.gdshader edge_start / edge_end,
// set by CityStreamer): the far city goes with it, or its last blocks stand on nothing.
uniform float edge_start = 5040.0;
uniform float edge_end = 6860.0;
uniform vec3 deck_road_color = vec3(0.040, 0.040, 0.044);
#include "res://shaders/street_glow.gdshaderinc"
#include "res://shaders/color_space.gdshaderinc"
// The lit offices and the pale or dark spandrels, rolled exactly as building.gdshader rolls them.
#include "res://shaders/window_lights.gdshaderinc"

// --- Coded parts (FarBuilding) ---
// Building's numbers the code does not carry: its storefront height (Building.storefront_height),
// a parking deck's spandrel and storey (Building.GARAGE_SPANDREL, GARAGE_STOREY).
uniform float storefront_height = 4.5;
uniform float garage_spandrel = 1.1;
uniform float garage_storey = 3.2;
// The far city's copy (PropFactory.building_lod_material(true)) prints the small roof plant on
// the coded roofs - the air handlers, ducts and skylights it does not build (FarBuilding.SILHOUETTE)
// - at this share of the old printed density; the LOD chunks build every unit and print none.
uniform bool print_small_plant = false;
uniform float small_plant_density = 0.45;
// A mast is drawn at least this many pixels wide (its true width is a fifth of one a kilometre
// out), and its aviation beacon glows this bright after dark (the near one is an unshaded red).
uniform float mast_min_px = 0.75;
// How bright a lit office and an open shop glow on a coded part: what building.gdshader's traced
// rooms come to on average (room paint ~0.4 x its lamps ~0.6 x lit_strength 0.8 x 2.0; a shop at
// x 2.5 in its own tone). Measured against it with tools/glshot/far_building_shot.gd NIGHT=1.
uniform float lit_room_level = 0.40;
uniform float lit_shop_level = 0.45;
uniform float beacon_energy = 3.0;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 box_size;
varying vec4 custom;
varying vec4 tint;
varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 world_tangent;
// A coded part's six codes (FarBuilding.codes()), exact integers, flat.
varying flat vec3 codes0;
varying flat vec3 codes1;


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


// --- Building's palettes, as it wrote them (sRGB numbers; cs_as_uniform() them before use).
// tests/far_city_checks.gd reads these back out of this source and compares them with Building.
// Building.WINDOW_TINTS.
vec3 window_tint_srgb(int i) {
	if (i == 0) return vec3(0.35, 0.50, 0.65);
	if (i == 1) return vec3(0.30, 0.55, 0.55);
	if (i == 2) return vec3(0.45, 0.45, 0.50);
	if (i == 3) return vec3(0.60, 0.50, 0.35);
	return vec3(0.40, 0.60, 0.75);
}

// Building.LIT_COLORS.
vec3 lit_srgb(int i) {
	if (i == 0) return vec3(1.0, 0.82, 0.50);
	if (i == 1) return vec3(1.0, 0.92, 0.70);
	return vec3(0.85, 0.90, 1.0);
}

// Building.FRAME_PAINTS[finish][i] (finish 0 flat, 1 brick, 2 panels, 3 glass).
vec3 frame_paint_srgb(int finish, int i) {
	if (finish == 1) {
		if (i == 0) return vec3(0.80, 0.78, 0.73);
		if (i == 1) return vec3(0.84, 0.82, 0.76);
		if (i == 2) return vec3(0.11, 0.12, 0.11);
		if (i == 3) return vec3(0.10, 0.19, 0.14);
		return vec3(0.25, 0.18, 0.13);
	}
	if (finish == 2) {
		if (i == 0) return vec3(0.20, 0.20, 0.22);
		if (i == 1) return vec3(0.25, 0.19, 0.14);
		if (i == 2) return vec3(0.50, 0.51, 0.53);
		return vec3(0.10, 0.10, 0.11);
	}
	if (finish == 3) {
		if (i == 0) return vec3(0.58, 0.59, 0.62);
		if (i == 1) return vec3(0.15, 0.15, 0.16);
		if (i == 2) return vec3(0.29, 0.23, 0.17);
		return vec3(0.45, 0.43, 0.39);
	}
	if (i == 0) return vec3(0.86, 0.85, 0.82);
	if (i == 1) return vec3(0.12, 0.12, 0.13);
	if (i == 2) return vec3(0.28, 0.21, 0.16);
	if (i == 3) return vec3(0.50, 0.51, 0.52);
	return vec3(0.78, 0.75, 0.68);
}

// The mean of a wall texture set's colour map times building.gdshader's gain on it (1.3; 1.35 on
// brick): the near wall is the facade colour times its photographed texture, so its average is
// the facade times this - linear on Forward+, raw on Compatibility, as each renderer hands the
// texture over (Building.WALL_TEXTURE_MEAN, sets in FarBuilding.WALL_SETS order; 15 = none).
vec3 wall_tex_mean(int i) {
	vec3 lin;
	vec3 raw;
	float gain = 1.3;
	if (i == 0) { lin = vec3(0.277, 0.138, 0.086); raw = vec3(0.557, 0.403, 0.315); gain = 1.35; }
	else if (i == 1) { lin = vec3(0.319, 0.176, 0.096); raw = vec3(0.588, 0.435, 0.314); gain = 1.35; }
	else if (i == 2) { lin = vec3(0.155, 0.100, 0.083); raw = vec3(0.417, 0.327, 0.295); gain = 1.35; }
	else if (i == 3) { lin = vec3(0.406, 0.253, 0.200); raw = vec3(0.652, 0.472, 0.391); gain = 1.35; }
	else if (i == 4) { lin = vec3(0.407, 0.366, 0.351); raw = vec3(0.670, 0.638, 0.626); }
	else if (i == 5) { lin = vec3(0.340, 0.262, 0.188); raw = vec3(0.618, 0.549, 0.471); }
	else if (i == 6) { lin = vec3(0.272, 0.246, 0.199); raw = vec3(0.556, 0.531, 0.480); }
	else if (i == 7) { lin = vec3(0.634, 0.499, 0.358); raw = vec3(0.807, 0.722, 0.616); }
	else if (i == 8) { lin = vec3(0.514, 0.444, 0.347); raw = vec3(0.733, 0.684, 0.606); }
	else if (i == 9) { lin = vec3(0.207, 0.196, 0.177); raw = vec3(0.491, 0.479, 0.456); }
	else if (i == 10) { lin = vec3(0.482, 0.482, 0.482); raw = vec3(0.723, 0.723, 0.723); }
	else if (i == 11) { lin = vec3(0.061, 0.068, 0.070); raw = vec3(0.271, 0.286, 0.290); }
	else if (i == 12) { lin = vec3(0.403, 0.451, 0.428); raw = vec3(0.666, 0.701, 0.684); }
	else if (i == 13) { lin = vec3(0.124, 0.185, 0.075); raw = vec3(0.382, 0.464, 0.293); }
	else { return vec3(1.0); }
	return (cs_linear_renderer() ? lin : raw) * gain;
}

// An open shop's light (building.gdshader shop_tone(), the same integer rolls).
vec3 shop_tone_far(uint shop) {
	uint b = wl_hash(shop, 2u) >> 24u;
	if (b < 97u) return vec3(1.0, 0.70, 0.42);
	if (b < 174u) return vec3(1.0, 0.91, 0.78);
	if (b < 230u) return vec3(0.78, 0.90, 1.0);
	return (wl_hash(shop, 3u) >> 24u) < 128u ? vec3(1.0, 0.50, 0.80) : vec3(0.55, 1.0, 0.88);
}


// Rooftop plant printed on a roof: air handlers, cooling towers, duct runs and stair bulkheads as
// boxes with a cast shadow toward the sun's far side. `p` is metres from the roof centre, `edge`
// metres in from its nearest edge, `density` the share of 7 m cells that get a unit.
void print_plant(vec2 p, float edge, float bs, float density, vec3 sun_n, float mpp, inout vec3 surface, inout float rough) {
	vec2 sun_xz = sun_n.xz;
	float sun_len = length(sun_xz);
	vec2 sh_dir = sun_len > 1e-3 ? -sun_xz / sun_len : vec2(0.7, 0.7);
	vec2 cellf = p / clutter_cell;
	vec2 cell = floor(cellf);
	vec2 f = fract(cellf);
	float ch = hash21(cell * 1.7 + bs * 57.0);
	if (ch < density && edge > parapet_width + 0.6) {
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
}


void vertex() {
	// Per-instance dissolve. The far city (Skyline) writes each block's visibility into its
	// instances' colour alpha while a chunk takes the block over or hands it back; the LOD chunks'
	// own boxes always carry 1. At zero the box collapses to a point, so a block that a chunk is
	// standing on costs no fragments at all.
	if (COLOR.a < 0.004) {
		VERTEX = vec3(0.0);
	}
	local_pos = VERTEX;
	local_normal = NORMAL;
	custom = INSTANCE_CUSTOM;
	tint = COLOR;
	// Matches how `u` is measured below: local Z on the +-X faces, local X on the +-Z faces.
	vec3 t_local = abs(NORMAL.x) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	vec3 world;
	vec3 n_world;
	if (INSTANCE_CUSTOM.a < -0.5) {
		// A coded part (FarBuilding): an axis-aligned box whose basis is its size on the diagonal
		// and its facade code off it, each entry code * 2^-28. Rebuilt from the diagonal alone;
		// the code goes to the fragment flat and exact (a power-of-two multiply and a round).
		box_size = vec3(MODEL_MATRIX[0][0], MODEL_MATRIX[1][1], MODEL_MATRIX[2][2]);
		codes0 = vec3(round(MODEL_MATRIX[0][1] * 268435456.0), round(MODEL_MATRIX[0][2] * 268435456.0), round(MODEL_MATRIX[1][0] * 268435456.0));
		codes1 = vec3(round(MODEL_MATRIX[1][2] * 268435456.0), round(MODEL_MATRIX[2][0] * 268435456.0), round(MODEL_MATRIX[2][1] * 268435456.0));
		world = MODEL_MATRIX[3].xyz + VERTEX * box_size;
		n_world = NORMAL;
		world_tangent = t_local;
	} else {
		codes0 = vec3(0.0);
		codes1 = vec3(0.0);
		box_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		vec3 v_local = VERTEX;
		// A mast on a roof (FarBuilding.Plant.MAST, BEACON_MAST: an antenna is 16 cm across, a
		// spire's mast 60) is drawn at least `mast_min_px` wide, or it is gone a few hundred metres
		// out - and a tower's mast against the sky is most of its silhouette from the basin. Only
		// in a perspective view: the shadow maps keep its real width.
		if (INSTANCE_CUSTOM.a > 3.5 && INSTANCE_CUSTOM.r > 0.5 && INSTANCE_CUSTOM.r < 2.5 && PROJECTION_MATRIX[3][3] < 0.5) {
			float d = length(MODEL_MATRIX[3].xyz - INV_VIEW_MATRIX[3].xyz);
			float mpp = 2.0 * d / max(PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y, 1.0);
			float w = mast_min_px * mpp;
			v_local.xz *= vec2(max(box_size.x, w) / max(box_size.x, 1e-4), max(box_size.z, w) / max(box_size.z, 1e-4));
		}
		world = (MODEL_MATRIX * vec4(v_local, 1.0)).xyz;
		// The renderer's own normal transform, as before skip_vertex_transform: a block plate's
		// basis is sheared to its slope, and a sheared box's normals are not its basis times the
		// unit normals.
		n_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
		world_tangent = normalize((MODEL_MATRIX * vec4(t_local, 0.0)).xyz);
	}
	world_pos = world;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (INSTANCE_CUSTOM.a < -0.5) {
		world_normal = NORMAL;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
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
	// Ground plates and decks (.a 2, 3) carry linear colours; everything else is a palette entry
	// in sRGB numbers, decoded as the near building's uniform would be.
	vec3 c = (custom.a < 1.5 || custom.a > 3.5) ? cs_as_uniform(c_raw) : c_raw;
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

	if (custom.a < -0.5) {
		// ================================================== A coded part: the near building ===
		// FarBuilding's six codes; the bit layout is FarBuilding.boxes() / decode().
		uint ca = uint(codes0.x + 0.5);
		uint cb = uint(codes0.y + 0.5);
		uint cc = uint(codes0.z + 0.5);
		uint cd = uint(codes1.x + 0.5);
		uint ce = uint(codes1.y + 0.5);
		uint cf = uint(codes1.z + 0.5);
		// building.gdshader's `seed` (Building.seed % 1000), its finish and window style.
		float sd = float(ca & 1023u);
		int fin = int((ca >> 10u) & 3u);
		int ws = int((ca >> 12u) & 3u);
		int roof_kind = int((ca >> 14u) & 3u);
		int lit_i = int((ca >> 16u) & 3u);
		float crown_mul = ((ca >> 19u) & 1u) == 1u ? 1.09 : 0.92;
		int tint_i = int(cb & 7u);
		float weather = float((cb >> 3u) & 31u) / 31.0;
		bool has_sf = ((cb >> 16u) & 1u) == 1u;
		bool parking = ((cb >> 17u) & 1u) == 1u;
		bool chamfered = ((cb >> 18u) & 1u) == 1u;
		bool has_crown = ((cb >> 19u) & 1u) == 1u;
		float lit_ratio_p = float(cc & 65535u) / 65535.0;
		bool tall = ((cc >> 16u) & 1u) == 1u;
		int frame_i = int((cc >> 17u) & 7u);
		float cols_x = max(float(cd & 127u), 1.0);
		float cols_z = max(float((cd >> 7u) & 127u), 1.0);
		float rows_p = max(float(ce & 127u), 1.0);
		float base_hp = float((ce >> 7u) & 255u) / 10.0;
		float ext = float(cf & 2047u) / 100.0;
		float rise = float((cf >> 11u) & 127u) / 100.0;
		// The part itself inside its box: the plinth under it, the parapet over it.
		float part_h = box_size.y - ext - rise;
		float vp = (local_pos.y + 0.5) * box_size.y - ext;
		float sf_h = has_sf ? storefront_height : 0.0;
		float floor_hp = parking ? garage_storey : (part_h - sf_h) / rows_p;
		// The near walls' other colours, worked out from the facade as Building works them out,
		// in the same space (Building.base_color(), style.accent = facade.darkened(0.55)).
		vec3 accent = cs_as_uniform(c_raw * 0.45);
		vec3 tint_c = cs_as_uniform(window_tint_srgb(tint_i));
		vec3 lit_c = cs_as_uniform(lit_srgb(lit_i));
		vec3 frame_c = cs_as_uniform(frame_paint_srgb(fin, frame_i));
		vec3 base_c = cs_as_uniform(mix(c_raw, vec3(0.62, 0.60, 0.56), 0.6) * 0.92);
		if (n.y > 0.5) {
			// ------------------------------------------------------------------- Roof -------
			// building.gdshader's roof, the same covering (Building.roof_style) on the same deck,
			// its fine pattern faded with distance; the ring is the parapet's top.
			vec2 p = local_pos.xz * box_size.xz;
			vec2 e = box_size.xz * 0.5 - abs(p);
			float edge = min(e.x, e.y);
			float ring = 1.0 - smoothstep(0.7 - mpp * 0.5, 0.7 + mpp * 0.5, edge);
			vec3 surface;
			if (parking) {
				// The top deck: sealed concrete, stall lines in double rows either side of the
				// aisles (their 4 % of the deck kept as its tone once they are under a pixel).
				vec2 q = p + box_size.xz * 0.5;
				float band = mod(q.y - 1.0, 17.8);
				float in_row = step(band, 5.4) + step(12.4, band);
				float line = step(abs(fract(q.x / 2.7 + 0.5) - 0.5) * 2.7, 0.06) * in_row;
				surface = vec3(0.36, 0.36, 0.355) * (0.86 + 0.24 * hash21(floor(q * 0.35) + sd) * detail(2.9, mpp));
				surface = mix(surface, vec3(0.86, 0.85, 0.80), mix(0.027, line, detail(0.6, mpp)));
				surface = mix(surface, c, ring);
				rough = 0.9;
			} else {
				if (roof_kind == 1) {
					// White single-ply membrane in welded strips, grey where water sits.
					surface = vec3(0.78, 0.78, 0.76);
					float strip = fract(p.x * 0.5 + hash21(vec2(sd, 2.0)));
					surface *= 1.0 - 0.10 * smoothstep(0.06, 0.0, min(strip, 1.0 - strip)) * detail(2.0, mpp);
					surface *= mix(0.95, 0.86 + 0.18 * hash21(floor(p * 0.35) + sd), detail(2.9, mpp));
					rough = 0.82;
				} else if (roof_kind == 2) {
					// Bitumen: dark, patched, shinier where it has been resealed.
					surface = vec3(0.14, 0.135, 0.13);
					float patch = hash21(floor(p * 0.6) + sd);
					surface *= mix(1.05, 0.8 + 0.5 * patch, detail(1.7, mpp));
					rough = mix(0.75, mix(0.55, 0.95, patch), detail(1.7, mpp));
				} else {
					vec3 gravel = mix(vec3(0.38, 0.37, 0.36), c, 0.25);
					gravel *= mix(1.0, 0.92 + 0.16 * hash21(floor(p * 1.5) + sd), detail(0.7, mpp));
					surface = gravel;
					rough = 0.95;
				}
				// The far city builds only the plant that makes a silhouette (FarBuilding); the
				// air handlers and duct runs are printed, as before. The LOD chunks build them all.
				if (print_small_plant) {
					print_plant(p, edge, bseed, clutter_density * small_plant_density, sun_n, mpp, surface, rough);
				}
				// The parapet's top, and the shade its inner face throws on the deck.
				surface = mix(surface, c * 0.9, ring);
				surface *= mix(1.0, 0.88, (1.0 - ring) * step(0.05, rise) * (1.0 - smoothstep(0.7, 1.9, edge)));
			}
			albedo = surface;
			spec = 0.15;
		} else if (n.y < -0.5) {
			// The underside: only ever seen from inside the ground.
			albedo = c * 0.3;
		} else {
			// ------------------------------------------------------------------ Walls -------
			// Wall space exactly as building.gdshader measures it (its `u` runs against the
			// tangent on the -X and +Z faces), so cell `col` here is cell `col` there.
			float uq;
			float wall_len;
			float cols;
			float face_id;
			if (abs(n.x) > 0.5) {
				uq = local_pos.z * box_size.z * sign(n.x) + box_size.z * 0.5;
				wall_len = box_size.z;
				cols = cols_z;
				face_id = n.x > 0.0 ? 1.0 : 2.0;
			} else {
				uq = local_pos.x * box_size.x * sign(-n.z) + box_size.x * 0.5;
				wall_len = box_size.x;
				cols = cols_x;
				face_id = n.z > 0.0 ? 3.0 : 4.0;
			}
			float pitch = wall_len / cols;
			float col = floor(uq / pitch);
			float fu = fract(uq / pitch);
			// A cut corner is a solid pier one bay wide (Building.part_grid()'s cut); out here
			// it is that bay of the wall, drawn as the pier.
			bool pier = chamfered && (col < 0.5 || col > cols - 1.5);
			bool plinth = vp < 0.0;
			bool parapet_band = vp > part_h;
			bool storefront = has_sf && vp < sf_h && !plinth;
			float row;
			float fv;
			if (storefront) {
				row = -1.0;
				fv = vp / sf_h;
			} else {
				float vv = vp - sf_h;
				row = floor(vv / floor_hp);
				fv = fract(vv / floor_hp);
			}
			// A window frame's least width in metres: about 0.8 px while a bay is several pixels
			// (the near walls' real frame quads read as a full line there), its painted width once
			// the cells are going to their average anyway.
			float frame_px = mpp * 0.6 * (1.0 - smoothstep(0.3, 0.8, mpp));
			bool glass = false;
			bool frame = false;
			bool spandrel = false;
			bool reveal = false;
			bool fascia = false;
			bool bulkhead = false;
			bool g_open = false;
			bool g_column = false;
			bool shop_open = true;
			bool shutter = false;
			uint shop_key = 0u;
			float shop_seed = 0.0;
			// The share of a cell that is glass, for the cell's average past a few pixels.
			float glaze_frac = 0.0;
			if (plinth || parapet_band || pier) {
				// Solid.
			} else if (parking) {
				// Open between spandrels and columns (building.gdshader's garage).
				float sp = garage_spandrel / floor_hp;
				g_column = min(fu, 1.0 - fu) * pitch < 0.32;
				g_open = fv > sp && fv < 0.965 && !g_column;
				glaze_frac = (0.965 - sp) * (1.0 - 0.64 / pitch);
			} else if (storefront) {
				// Street level: a shop every few bays, its own sign band, a door bay, a bulkhead,
				// and at night open (lit in its own light) or shuttered - the near shader's rolls.
				float span = float(2u + ((cb >> (8u + 2u * uint(face_id - 1.0))) & 3u));
				float shop_id = floor(col / span);
				shop_seed = hash21(vec2(shop_id * 1.7, face_id * 13.0) + sd);
				shop_key = (uint(sd + 0.5) * 8u + uint(face_id)) * 1024u + uint(max(shop_id, 0.0));
				float bay = col - shop_id * span;
				float door_i = float((wl_hash(shop_key, 15u) >> 24u) % uint(span + 0.5));
				bool door_bay = abs(bay - door_i) < 0.5;
				float low = door_bay ? 0.0 : 0.15;
				glass = fv > low && fv < 0.74 && abs(fu - 0.5) < 0.44;
				fascia = fv >= 0.76 && fv < 0.93;
				bulkhead = fv < low - 0.045 / sf_h && abs(fu - 0.5) < 0.46;
				shop_open = (wl_hash(shop_key, 1u) >> 24u) < 158u;
				if (tall) {
					// Building.shop_is_lobby(): the middle unit of a tall tower's face, lit all night.
					float n_shops = max(floor(wall_len / (span * pitch) + 0.001), 1.0);
					if (shop_id == floor((n_shops - 1.0) * 0.5) && (wl_hash(shop_key, 44u) >> 24u) < 192u) {
						shop_open = true;
					}
				}
				if (!shop_open && (wl_hash(shop_key, 8u) >> 24u) < 140u && lamp_factor > 0.5) {
					shutter = fv < 0.745 && abs(fu - 0.5) < 0.46;
					glass = glass && !shutter;
					bulkhead = bulkhead && !shutter;
				}
				glaze_frac = 0.52;
			} else if (ws == 0) {
				glass = abs(fu - 0.5) < 0.27 && abs(fv - 0.52) < 0.25;
				reveal = !glass && abs(fu - 0.5) < 0.32 && abs(fv - 0.52) < 0.30;
				glaze_frac = 0.27;
			} else if (ws == 1) {
				glass = abs(fv - 0.55) < 0.27;
				frame = glass && abs(fu - 0.5) > 0.5 - max(0.03, frame_px / pitch * 0.5);
				glass = glass && !frame;
				glaze_frac = 0.51;
			} else if (ws == 2) {
				// The curtain wall: vision glass between thin transoms, the spandrel panel over
				// each slab edge, a mullion every bay.
				float fw_v = max(0.0125, frame_px / floor_hp * 0.5);
				frame = fu < max(0.05, frame_px / pitch) || abs(fv - 0.08) < fw_v || abs(fv - 0.93) < fw_v;
				spandrel = !frame && (fv < 0.0675 || fv > 0.9425);
				glass = !frame && !spandrel;
				glaze_frac = 0.78;
			} else {
				glass = abs(fu - 0.5) < 0.16 && abs(fv - 0.5) < 0.40;
				reveal = !glass && abs(fu - 0.5) < 0.21 && abs(fv - 0.5) < 0.45;
				glaze_frac = 0.256;
			}
			// How much of the storey- and bay-scale pattern a pixel can still resolve.
			float band_fade = detail(min(floor_hp, pitch * 2.0), mpp);
			float cell_fade = detail(pitch, mpp);

			// What the glass mirrors, as building.gdshader has it: its sky (the material's default
			// zenith and horizon, which nothing sets on a Building), the fake city opposite - two
			// rows of blocks keyed on the reflected ray's heading, their windows at their average -
			// and the street below the horizon. Mostly dark: a near pane at a street's distance is
			// a dark city in a dark room, and the far path's bare sky gradient drew every pane two
			// to five times brighter than the near one it stood for.
			vec3 refl = reflect(to_frag, world_normal);
			vec3 sky_h = cs_as_uniform(vec3(0.42, 0.47, 0.55));
			vec3 sky_ref = mix(sky_h, cs_as_uniform(vec3(0.26, 0.44, 0.80)), smoothstep(0.0, 0.55, refl.y));
			{
				float heading = atan(refl.x, refl.z) * 0.159155;
				float near_slot = heading * 26.0;
				float far_slot = heading * 70.0;
				float near_roof = mix(0.05, 0.42, hash21(vec2(floor(near_slot), 3.7)));
				float far_roof = mix(0.10, 0.70, hash21(vec2(floor(far_slot), 8.3))) * step(0.55, hash21(vec2(floor(far_slot), 1.9)));
				float in_near = 1.0 - smoothstep(near_roof - 0.012, near_roof + 0.012, refl.y);
				float in_far = (1.0 - smoothstep(far_roof - 0.012, far_roof + 0.012, refl.y)) * (1.0 - in_near);
				vec3 near_wall = mix(vec3(0.16, 0.15, 0.14), vec3(0.09, 0.10, 0.12), hash21(vec2(floor(near_slot), 9.1)));
				near_wall = mix(near_wall, near_wall * 0.5 + sky_h * 0.12, 0.35);
				vec3 far_wall = mix(sky_h * 0.55, near_wall, 0.35);
				sky_ref = mix(sky_ref, far_wall, in_far);
				sky_ref = mix(sky_ref, near_wall, in_near);
			}
			sky_ref = mix(cs_as_uniform(vec3(0.09, 0.09, 0.10)), sky_ref, smoothstep(-0.22, 0.10, refl.y));
			float fres = pow(1.0 - clamp(-dot(to_frag, world_normal), 0.0, 1.0), 4.0);
			float mirror = mix(0.26, 0.90, fres) * (1.0 - 0.85 * night_factor) * (storefront ? 0.66 : 1.0);
			float sky_now = clamp(dot(sky_tint.rgb, vec3(0.299, 0.587, 0.114)) / 0.74, 0.0, 1.5);
			vec3 refl_emit = sky_ref * mirror * reflect_emit * reflect_energy * sky_now;
			float to_sun = max(dot(refl, sun_n), 0.0);
			vec3 glare = vec3(1.0, 0.96, 0.88)
				* (pow(to_sun, glass_glare_tightness) * glass_glare
					+ pow(to_sun, glass_glare_broad_tightness) * glass_glare_broad) * day;
			// The room behind the glass as building.gdshader shows it from a distance: an office's
			// traced paint, blinds and desks (about 0.4 on average) at the interior exposure (0.4),
			// seen through the building's own glass tint, darker toward the frame and where the
			// head shades the recess (its 0.45 inset and 0.5 recess shade, about 0.8 over a pane).
			vec3 room = mix(vec3(0.16, 0.155, 0.15), tint_c * 0.19, 0.28) * 0.8 * (0.55 + 0.9 * hash31(vec3(col * 1.7, row, sd * 31.0)));
			if (storefront) {
				room = vec3(0.22, 0.20, 0.17) * (0.7 + 0.6 * shop_seed);
			}
			// No glare lobe: the near glass has none, its flare is the renderer's own specular.
			vec3 glass_col = mix(room, sky_ref, mirror * (1.0 - reflect_emit));
			// The wall's finish (building.gdshader: brick and panels round their mean, a glass
			// building's opaque panels at 0.6 of its colour) and its rows, faded with distance.
			// The near wall is the facade times its photographed texture (building.gdshader), so
			// its average here is the facade times that texture's mean (wall_tex_mean()).
			int set_i = int((cd >> 14u) & 15u);
			vec3 wt = wall_tex_mean(set_i);
			vec3 wall = c * wt;
			if (fin == 1) {
				// Brick: the texture carries its own mortar; without one, the near shader's coursing.
				float brow = floor(vp / 0.25);
				float bu = fract((uq + mod(brow, 2.0) * 0.3) / 0.6);
				float mortar = set_i < 15 ? 0.0 : clamp(step(bu, 0.06) + step(fract(vp / 0.25), 0.14), 0.0, 1.0) * detail(0.25, mpp);
				wall = mix(c * wt * mix(1.0, 0.85 + 0.3 * hash21(vec2(floor((uq + mod(brow, 2.0) * 0.3) / 0.6), brow) + sd), detail(0.6, mpp)), accent, mortar);
				rough = 0.95;
			} else if (fin == 2) {
				float joint = clamp(step(fu, 0.03) + step(fv, 0.04), 0.0, 1.0) * cell_fade;
				wall = mix(c * wt * mix(1.0, 0.9 + 0.2 * hash21(vec2(col, row) + sd), cell_fade), accent, joint);
				rough = 0.8;
			} else if (fin == 3) {
				float joint = clamp(step(fu, 0.04) + step(fv, 0.05), 0.0, 1.0) * cell_fade;
				wall = mix(c * 0.6 * wt, accent, joint);
				rough = 0.35;
				spec = 0.34;
			} else {
				rough = 0.85;
			}
			if (parking) {
				// The deck's precast spandrels, a joint every half bay, the columns standing
				// back in its shadow.
				float span_g = pitch * 0.5;
				wall = c * mix(1.0, 0.92 + 0.14 * hash21(vec2(floor(uq / span_g), row) + sd), cell_fade);
				wall *= 1.0 - 0.12 * step(0.965, fv) * band_fade;
				if (g_column) {
					wall *= fv > garage_spandrel / floor_hp ? 0.7 : 1.0;
				}
				rough = 0.88;
			}
			// Base course, crown.
			if (base_hp > 0.01 && vp < base_hp) {
				float course = fract(vp / 0.92);
				float block = fract((uq + floor(vp / 0.92) * 0.46) / 1.84);
				float joint = clamp(step(course, 0.05) + step(block, 0.018), 0.0, 1.0) * detail(0.92, mpp);
				vec3 stone = base_c * mix(0.99, 0.90 + 0.18 * hash21(vec2(floor(vp / 0.92), floor(uq / 1.84)) + sd), detail(0.92, mpp));
				wall = mix(stone, stone * 0.55, joint);
				rough = 0.9;
			}
			if (has_crown && vp > part_h - 1.6 * floor_hp) {
				wall *= crown_mul;
			}
			// Grime, as building.gdshader lays it (soot at the foot, streaks under the sills),
			// at its average where a streak is under a pixel.
			float ground_dirt = 1.0 - smoothstep(0.0, 6.5, vp);
			float sill_y = sf_h + floor((vp - sf_h) / floor_hp) * floor_hp + 0.22 * floor_hp;
			float below = vp < sill_y ? sill_y - vp : sill_y + floor_hp - vp;
			float run = (1.0 - smoothstep(0.0, 2.6, below)) * smoothstep(0.0, 0.12, below);
			float across = 1.0 - smoothstep(0.22, 0.44, abs(fu - 0.5));
			float drips = step(0.35, hash21(vec2(col, row + face_id * 3.0) + sd));
			float streak = mix(0.09, run * across * drips * 0.5, cell_fade);
			float dirt = weather * clamp(0.55 * ground_dirt + 0.75 * streak, 0.0, 1.0);
			wall = mix(wall, wall * vec3(0.46, 0.44, 0.42), dirt);
			rough = min(1.0, rough + 0.18 * dirt);

			vec3 cell = wall;
			// What this pixel emits as drawn, and what its cell emits on average.
			vec3 e_cell = vec3(0.0);
			if (plinth) {
				// The plinth folded into this part: board-formed concrete down to the ground.
				vec3 conc = cs_as_uniform(vec3(0.66));
				cell = conc * (1.0 - 0.13 * smoothstep(0.09, 0.0, min(fract(vp / 1.2), 1.0 - fract(vp / 1.2))) * detail(1.2, mpp));
				rough = 0.92;
			} else if (parapet_band) {
				// The parapet's face (its cap band is the facade lightened, Building's cap_bands).
				cell = cs_as_uniform(mix(c_raw, vec3(1.0), 0.06));
				cell *= 1.0 - 0.18 * smoothstep(0.12, 0.0, box_size.y - ext - vp) * detail(0.4, mpp);
			} else if (pier) {
				// A cut corner's pier, lit as its own face would be: lighter, it turns to the sky.
				cell = wall * 1.06;
			} else if (g_open) {
				// Inside the deck: dark by day but for the light at the far side, its lamps after dark.
				cell = c * 0.08;
				e_cell += vec3(0.92, 0.97, 1.0) * 0.06 * (0.3 + 0.7 * lamp_factor) + sky_tint.rgb * 0.05 * day;
			} else if (glass) {
				cell = glass_col;
				rough = 0.18;
				spec = 0.42;
				e_cell += refl_emit;
				// After dark: the same windows building.gdshader lights, in the building's own light.
				bool lit = storefront ? shop_open : window_lit(sd, face_id, row, col, lit_ratio_p);
				float on = storefront ? lamp_factor : night_factor;
				if (lit && on > 0.001) {
					vec3 light = storefront ? cs_as_uniform(shop_tone_far(shop_key)) * lit_shop_level : lit_c * window_glow(sd, face_id, row, col) * lit_room_level;
					cell = mix(cell, cell * 0.35, on);
					e_cell += light * on;
				}
			} else if (frame) {
				cell = ws == 2 ? frame_c : accent;
				rough = 0.6;
			} else if (spandrel) {
				float pale = spandrel_pale(sd) ? 1.0 : 0.0;
				cell = mix(c * 0.62 + vec3(0.012), c * 1.02 + vec3(0.075), pale);
				cell *= mix(1.0, 0.95 + 0.10 * hash21(vec2(col * 0.5, row) + sd), cell_fade);
				e_cell += sky_ref * mix(0.10, 0.45, fres) * reflect_emit * reflect_energy * sky_now * (1.0 - 0.85 * night_factor) * mix(0.8, 0.45, pale);
				rough = 0.38;
			} else if (reveal) {
				cell = mix(c, accent, 0.35) * 0.9;
			} else if (fascia) {
				// The sign band: each shop's own board, a lightbox or lit letters after dark.
				vec3 sign_hue = mix(vec3(0.16, 0.18, 0.22), vec3(0.42, 0.20, 0.16), hash21(vec2(shop_seed, 5.3)));
				sign_hue = mix(sign_hue, vec3(0.18, 0.30, 0.26), step(0.66, hash21(vec2(shop_seed, 9.1))));
				sign_hue = mix(sign_hue, vec3(0.22, 0.20, 0.26), step(0.86, hash21(vec2(shop_seed, 2.4))));
				cell = sign_hue;
				vec3 box = sign_hue / max(max(sign_hue.r, max(sign_hue.g, sign_hue.b)), 0.001);
				box = mix(box, vec3(1.0, 0.93, 0.80), step(0.66, hash21(vec2(shop_seed, 41.7))));
				bool sign_off = !shop_open && (wl_hash(shop_key, 9u) >> 24u) < 150u;
				bool channel = (wl_hash(shop_key, 10u) >> 24u) >= 110u;
				if (!sign_off) {
					// Channel letters cover about a third of their board.
					e_cell += (channel ? box * 0.75 : box * 2.4 * (0.75 + 0.5 * hash21(vec2(shop_seed, 29.3)))) * lamp_factor;
				}
				rough = 0.55;
			} else if (bulkhead) {
				vec3 base_col = mix(vec3(0.20, 0.19, 0.18), vec3(0.42, 0.34, 0.28), hash21(vec2(shop_seed, 13.7)));
				cell = mix(base_col, vec3(0.30, 0.33, 0.36), step(0.7, hash21(vec2(shop_seed, 19.3))));
				rough = 0.6;
			} else if (shutter) {
				cell = vec3(0.42, 0.42, 0.40);
				rough = 0.7;
			}
			// Past a few pixels a cell is its own average: the glazing share of the glass over
			// the wall round it, and of the light - a storey's share of its lit offices, not
			// whichever one the pixel's centre landed on. This is the mipmap the grid lacks.
			if (!plinth && !parapet_band && !pier) {
				vec3 mean_glass = parking ? c * 0.08 : glass_col;
				vec3 mean_cell = mix(wall, mean_glass, glaze_frac);
				albedo = mix(mean_cell, cell, mix(0.25, 1.0, band_fade));
				vec3 e_mean;
				if (parking) {
					e_mean = vec3(0.92, 0.97, 1.0) * 0.06 * (0.3 + 0.7 * lamp_factor) * glaze_frac;
				} else if (storefront) {
					// About 62 % of the shops open, in their own light, and their sign boards.
					e_mean = vec3(1.0, 0.92, 0.80) * (lit_shop_level * 0.32 + 0.20) * lamp_factor + refl_emit * glaze_frac;
				} else {
					e_mean = lit_c * 0.78 * lit_room_level * lit_ratio_p * 0.98 * glaze_frac * night_factor + refl_emit * glaze_frac;
				}
				emission += mix(e_mean, e_cell, band_fade);
			} else {
				albedo = cell;
				emission += e_cell;
			}
		}
	} else if (custom.a > 3.5) {
		// ------------------------------------------------------- Roof plant (FarBuilding) ---
		// One box a unit, in the unit's own paint: galvanised and lighter on top, a sign's
		// face, dark glossy glazing, a mast with the aviation beacon the near one carries.
		int kind = int(custom.r + 0.5);
		float top_lit = n.y > 0.5 ? 1.12 : (n.y < -0.5 ? 0.6 : 0.92);
		albedo = c * top_lit;
		rough = 0.6;
		spec = 0.3;
		if (kind == 3) {
			// Glazing: a skylight, a solar array.
			vec3 refl = reflect(to_frag, world_normal);
			float fres = pow(1.0 - clamp(-dot(to_frag, world_normal), 0.0, 1.0), 4.0);
			albedo = mix(c, sky_tint.rgb * 0.6, 0.3 + 0.4 * fres);
			rough = 0.2;
			spec = 0.5;
		} else if (kind == 4) {
			// A billboard: its paint with a band of the advertiser's colour across it.
			float vv = local_pos.y + 0.5;
			albedo = mix(c, c * vec3(0.55, 0.60, 0.70), step(0.45, vv) * step(vv, 0.78)) * top_lit;
			rough = 0.5;
		}
		if (kind == 2 && box_size.y - (local_pos.y + 0.5) * box_size.y < 0.6) {
			// The beacon on the tip, unshaded red like the near one, and brighter after dark.
			albedo = vec3(0.05);
			emission += vec3(1.0, 0.25, 0.2) * (0.9 + beacon_energy * night_factor);
		}
	} else if (custom.a > 1.5) {
		// --------------------------------------------------- Ground: plate / freeway deck ---
		// Far enough away that this is all there is of the streets: a dark carriageway line
		// between the blocks and, after dark, the sodium glow down it (the same pattern and level
		// the LOD chunks' ground and the near roads use, street_glow.gdshaderinc, averaged to its
		// mean once a lamp pool is under a pixel or two, or the far grid sparkles).
		bool deck = custom.a > 2.5;
		float aa = max(mpp * 1.2, 0.05);
		float glow_detail = detail(street_glow_spacing * 0.5, mpp);
		vec3 glow_mean = street_glow_color * (street_glow_base + street_glow_pool * 0.18);
		if (n.y < 0.5) {
			// Kerb face, earth under a plate on a slope, the deck's fascia.
			albedo = c * (deck ? 0.92 : 0.55);
			rough = 0.95;
		} else if (deck) {
			// Asphalt, the median and the two outer shoulders a shade lighter, which is what
			// draws the carriageway's lines from the air.
			float x = abs(local_pos.x) * box_size.x;
			float half_w = 0.5 * box_size.x;
			float line = (1.0 - smoothstep(0.35, 0.35 + aa, x)) + smoothstep(half_w - 1.6 - aa, half_w - 1.6, x);
			albedo = mix(deck_road_color, deck_road_color * 3.2, clamp(line, 0.0, 1.0) * 0.5);
			rough = 0.9;
			if (lamp_factor > 0.001) {
				vec3 g = street_glow(vec2(0.0, (local_pos.z + 0.5) * box_size.z), vec2(local_pos.x + 0.5), 1);
				emission += mix(glow_mean, g, glow_detail) * street_glow_level();
			}
		} else {
			// Metres from the plate's -X,-Z corner; the roads run along its +X and +Z edges.
			vec2 p = (local_pos.xz + 0.5) * box_size.xz;
			float rx = custom.r;
			float rz = custom.g;
			float in_x = rx > 0.01 ? smoothstep(box_size.x - rx - aa, box_size.x - rx + aa, p.x) : 0.0;
			float in_z = rz > 0.01 ? smoothstep(box_size.z - rz - aa, box_size.z - rz + aa, p.y) : 0.0;
			float road = max(in_x, in_z);
			// A faint kerb line where pavement meets carriageway, the edge the eye finds first.
			float kerb_x = rx > 0.01 ? 1.0 - smoothstep(0.0, 0.6 + aa, abs(p.x - (box_size.x - rx))) : 0.0;
			float kerb_z = rz > 0.01 ? 1.0 - smoothstep(0.0, 0.6 + aa, abs(p.y - (box_size.z - rz))) : 0.0;
			vec3 ground = c * (0.94 + 0.12 * hash21(floor(p / 9.0) + bseed));
			albedo = mix(ground, plate_road_color, road);
			albedo = mix(albedo, c * 1.25, max(kerb_x, kerb_z) * 0.35 * detail(1.2, mpp));
			rough = 0.95;
			if (lamp_factor > 0.001 && road > 0.01) {
				// A junction square is lit evenly, a road along its own length.
				int axis = (in_x > 0.5 && in_z > 0.5) ? 0 : (in_x > in_z ? 1 : 2);
				float across = axis == 1 ? (p.x - (box_size.x - rx)) / max(rx, 0.01) : (p.y - (box_size.z - rz)) / max(rz, 0.01);
				vec3 g = street_glow(p, vec2(across), axis);
				emission += mix(glow_mean, g, glow_detail) * street_glow_level() * road;
			}
		}
		spec = 0.12;
	} else if (abs(n.y) > 0.5) {
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

		// Rooftop plant, printed (a flat grey roof is the loudest tell that a mid-distance city is
		// a set of extruded rectangles). The coded parts build theirs instead (FarBuilding).
		print_plant(p, edge, bseed, clutter_density, sun_n, mpp, surface, rough);

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

	float rim = smoothstep(edge_start, edge_end, length(world_pos.xz - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz));
	albedo *= 1.0 - rim;
	// The sky's horizon in this renderer's space: `sky_tint` (a color global) arrives raw on both,
	// and the sky shader's own horizon is decoded on Forward+ - the plane and the far canopy fade
	// to the same (HANDOFF 9au).
	vec3 sky_rim = cs_as_uniform(sky_tint.rgb);
	emission = mix(emission, sky_rim, rim);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	// Dielectric only, and tamed: with metal the sky reflection at grazing angles turned whole
	// towers see-through (a cage of wall strips). The glazing gets its reflection painted into
	// ALBEDO above instead, which is also the only version the web renderer sees.
	SPECULAR = spec;
	EMISSION = emission;
}
