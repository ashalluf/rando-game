// The hills' ground, the part two shaders share: which patch of hillside is dry grass, a stand
// of chaparral, bare dirt or rock, from the slope, which way it faces, the drainage and a few
// octaves of world-space value noise. terrain.gdshader paints it; hill_shells.gdshader grows
// the grass and the brush understory out of it, so every blade stands on painted straw and
// every clump of brush on a painted stand. HillPlanting (scripts/world/hill_planting.gd) is the
// same maths on the CPU and plants the shrubs and oaks by it; the smoke test reads the numbers
// below back out of this file and checks they still match HillPlanting.MIRRORED.
// macro_ground.gdshader keeps its own copy for the band where it meets the tiles (`tile_*`).
//
// Everything takes TRUE world XZ (`world_pos.xz + world_offset`). Colours are LINEAR.
// Shader includes use // comments, like any shader file.

// Straw on a pale, burnt hillside and on a greener, later-drying one (LINEAR albedo).
uniform vec3 straw_color = vec3(0.150, 0.124, 0.074);
uniform vec3 straw_green_color = vec3(0.106, 0.100, 0.064);
// Chaparral: the brush with the shade between the bushes (LINEAR).
uniform vec3 chaparral_color = vec3(0.050, 0.056, 0.036);
// The sage and buckwheat dotted through the grass: grey-green and paler than the chaparral
// (LINEAR). Painted in the chaparral's colour they were dark polka dots across the straw.
uniform vec3 sage_color = vec3(0.082, 0.086, 0.064);
// How much of the ground is chaparral, and how much more of it the north-facing slopes carry.
// Chaparral is the hills' DOMINANT cover (the grass is the exception, on gentle south slopes).
uniform float chaparral_amount : hint_range(0.0, 1.0) = 0.8;
uniform float north_brush : hint_range(0.0, 1.0) = 0.3;
// How much more brush the gullies carry and how much less the spur crests (the drainage the
// height field was cut with, MacroMap.last_drain, in COLOR.g), and how much less the gentle
// ground carries - benches and saddles are where the grass is.
uniform float drain_brush : hint_range(0.0, 1.0) = 0.45;
uniform float gentle_grass : hint_range(0.0, 1.0) = 0.55;
// How much brush the sunny side loses (south faces are grass and sage between the stands).
uniform float south_grass : hint_range(0.0, 1.0) = 0.08;
// Scree and dirt down the steep gullies, and rock breaking out along the spur crests.
uniform float gully_scree : hint_range(0.0, 1.0) = 0.5;
uniform float crest_rock : hint_range(0.0, 1.0) = 0.8;
// How much the land (aspect, drainage, gentle ground) decides where the stands are, against the
// patch noise. At 0.45 the noise had as much say as the land and the stands came out as blobs
// laid over the hill regardless of its shape - camouflage. The noise now only rags the edges.
uniform float topo_weight : hint_range(0.0, 1.0) = 0.8;
// Single shrubs (sage, buckwheat) dotted through the open grass.
uniform float sage_amount : hint_range(0.0, 1.0) = 0.5;
// Slope (1 - normal.y) where bare dirt starts and has taken over, and where rock does. The
// ranges are steep (median slope 0.14, 31 degrees; 0.30 is the steepest quarter, 0.45 the
// steepest tenth), so most of a hillside stays grass and brush, as the real ones do.
uniform float dirt_slope_start : hint_range(0.0, 1.0) = 0.42;
uniform float dirt_slope_end : hint_range(0.0, 1.0) = 0.62;
uniform float rock_slope_start : hint_range(0.0, 1.0) = 0.5;
uniform float rock_slope_end : hint_range(0.0, 1.0) = 0.72;
// Fire roads and foot trails across the open slopes; 0 turns them off.
uniform float trail_amount : hint_range(0.0, 1.0) = 0.8;
// How far the shrub crowns (hill_crowns()) push a stand's edge in and out, in stand-noise units
// (the edge itself is 0.09 wide): the edge runs round the crowns, scalloped, instead of along a
// smooth noise contour - the rounded blobs that read as camouflage from across a canyon.
uniform float crown_edge : hint_range(0.0, 0.3) = 0.06;

// Metres between the shrub crowns of a stand, and the crown field's mean (hill_crowns().x over
// the plane), which the edge push is centred on so the stands keep their share of the ground.
const float CROWN_CELL = 2.6;
const float CROWN_MEAN = 0.35;
// The stand noise's octaves (hill_stand_noise()): the patch octaves (90 and 27 m), the 8 m
// clumps and the single bushes (3 m), and the bias that keeps its mean at 0.5. The clumps had
// 0.3 and the bushes 0.35: wherever the threshold sat in the middle of the noise (every sunny
// face, every edge of a stand) the ground split into 8-20 m rounded blobs, and from across a
// canyon the hills wore leopard-spot camouflage. With the weight at the scale of one shrub the
// same edge is a scatter of single bushes thinning out into the grass, as a real one is. But a
// 3 m value noise cut by a threshold is itself a field of smooth round blobs, and from 150 m (the
// shrub crowns gone) that WAS the leopard: a 1.1 m octave (`fine`, the leaf clumps' noise) rags
// every edge into a fractal one.
const float STAND_PATCH_W = 0.2;
const float STAND_MID_W = 0.1;
const float STAND_BUSH_W = 0.4;
const float STAND_FINE_W = 0.3;
const float STAND_BIAS = 0.35;


float hash12t(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoiset(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12t(i), hash12t(i + vec2(1.0, 0.0)), f.x),
		mix(hash12t(i + vec2(0.0, 1.0)), hash12t(i + vec2(1.0, 1.0)), f.x), f.y);
}


// Value noise with its derivative: .x the value, .yz d(value)/d(p) (see macro_relief).
vec3 noisedt(vec2 x) {
	vec2 i = floor(x);
	vec2 f = x - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = hash12t(i);
	float b = hash12t(i + vec2(1.0, 0.0));
	float c = hash12t(i + vec2(0.0, 1.0));
	float d = hash12t(i + vec2(1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k3 = a - b - c + d;
	return vec3(a + k1 * u.x + k2 * u.y + k3 * u.x * u.y, du.x * (k1 + k3 * u.y), du.y * (k2 + k3 * u.x));
}


// Slope (1 - normal.y) and which way it faces (+1 north, -1 south, 0 on the flat) of a unit
// world normal.
vec2 hill_aspect(vec3 wn) {
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	return vec2(slope, -wn.z / max(length(wn.xz), 0.001) * smoothstep(0.02, 0.12, slope));
}


// The hillside-scale and patch-scale noises: .x `hill` (357 m), .y `patchy` (90 m and 27 m).
vec2 hill_broad(vec2 w) {
	return vec2(vnoiset(w * 0.0028), vnoiset(w * 0.011) * 0.65 + vnoiset(w * 0.037 + 13.1) * 0.35);
}


// Where the stand noise must fall for the ground to be brush: the share of the ground the brush
// takes here (thicker on the shaded side, in the gullies and on the steep ground, thinner on
// the gentle ground and the sunny side), pulled toward 0.5 by `topo_weight`.
float hill_stand_threshold(float slope, float north, float drain, float hill) {
	// The sunny side loses less brush than the shaded side gains: from the basin the south
	// faces are what you see, and they are brush with grass between, not grass with brush.
	float gentle = 1.0 - smoothstep(0.06, 0.22, slope);
	float south = max(-north, 0.0);
	float coverage = chaparral_amount + max(north, 0.0) * north_brush - south * south_grass
		+ drain * drain_brush - gentle * gentle_grass + (hill - 0.5) * 0.2;
	return 0.5 + (coverage - 0.5) * topo_weight;
}


// The stand noise: the patch octaves, the 8 m clumps (`mid`, vnoiset(w * 0.12 + 17.0)) and the
// single bushes (`bush`, the 3 m octave), which rag a stand's edge at the scale of one shrub.
float hill_stand_noise(float patchy, float mid, float bush, float fine) {
	return patchy * STAND_PATCH_W + mid * STAND_MID_W + (bush - 0.5) * STAND_BUSH_W
		+ (fine - 0.5) * STAND_FINE_W + STAND_BIAS;
}


// Half the width of a stand's edge, in stand noise: its own 0.045 plus a share of the spread of
// every octave that has faded to its average (`fine_fade`, `bush_fade`, `mid_fade`: 1 resolved,
// 0 gone). A hillside too far off to resolve an octave then draws the SHARE of brush it would
// have left, as a tone, not the coarser octaves' blobs with a hard rim.
float hill_stand_edge(float fine_fade, float bush_fade, float mid_fade) {
	return 0.045 + (1.0 - fine_fade) * STAND_FINE_W * 0.3 + (1.0 - bush_fade) * STAND_BUSH_W * 0.3
		+ (1.0 - mid_fade) * STAND_MID_W * 0.3;
}


// The 3 m bushes' fade: from ~11 pixels a cell to gone at ~3 (it ran out to 1.7, and the cells
// showed as squares on the way).
float hill_bush_fade(float fw) {
	return 1.0 - smoothstep(0.3, 1.2, fw);
}


// The 1.1 m octave's fade: gone once a cell is under ~4 pixels. Faded like the leaf clumps'
// relief (0.12..0.5) it aliased into a field of square blocks at a stand's edge from the air.
float hill_fine_fade(float fw) {
	return 1.0 - smoothstep(0.08, 0.3, fw);
}


// The 8 m clumps' fade: gone to their average once a cell is a couple of pixels across.
float hill_mid_fade(float fw) {
	return 1.0 - smoothstep(1.5, 5.0, fw);
}


// The chaparral stand alone, with the gaps between its bushes where the straw shows through.
// The edge also widens by how fast the stand noise changes from one pixel to the next, so where an
// octave is on its way out the threshold blurs instead of cutting the noise's cells into squares.
float hill_stand(float th, float stand, float bush, float edge) {
	float e = edge + fwidth(stand) * 0.7;
	return smoothstep(th + e, th - e, stand) * smoothstep(0.12, 0.3, bush);
}


// The single shrubs (sage, buckwheat) out in the open grass alone.
float hill_sage(float bush, float bush_fade) {
	return mix(0.05, smoothstep(0.76, 0.84, bush), bush_fade) * sage_amount;
}


// How much of the ground is brush: the stand, the gaps between its bushes where the straw shows
// through, and the single shrubs out in the open grass. `bush_fade` is how resolved the single
// bushes are (0 once they are under a pixel).
float hill_brush(float th, float stand, float bush, float fine_fade, float bush_fade, float mid_fade) {
	return max(hill_stand(th, stand, bush, hill_stand_edge(fine_fade, bush_fade, mid_fade)), hill_sage(bush, bush_fade));
}


// The trails: one contour of a slow noise (`tn`, vnoiset(w * 0.0065 + 41.0)) about a metre wide,
// only on some hillsides (`zone`, vnoiset(w * 0.0021 + 7.0)) and off the steep ground. `tn_fw`
// is fwidth(tn), which keeps it a line rather than a stair of pixels from far off.
float hill_trail(float tn, float tn_fw, float zone, float slope) {
	float trail = 1.0 - smoothstep(0.0035, 0.0035 + tn_fw * 1.5, abs(tn - 0.5));
	return trail * smoothstep(0.55, 0.7, zone) * (1.0 - smoothstep(0.18, 0.30, slope)) * trail_amount;
}


// Bare dirt: the steep cuts and road banks, the odd bare patch, scree fans down the steep
// gullies, and the trails.
float hill_bare(float slope, float patchy, float drain, float trail) {
	float bare = smoothstep(dirt_slope_start, dirt_slope_end, slope + (patchy - 0.5) * 0.3);
	bare = max(bare, smoothstep(0.3, 0.8, drain) * smoothstep(0.32, 0.48, slope) * gully_scree);
	return max(bare, trail * 0.9);
}


// Rock outcrops: the steepest faces, a few breaking through on the ridges, and rock along the
// spur crests broken into outcrops. `crag` is vnoiset(w * 0.021 + 29.0).
float hill_rocky(float slope, float crag, float patchy, float drain, float bush) {
	float rocky = smoothstep(rock_slope_start, rock_slope_end, slope + (crag - 0.5) * 0.22);
	rocky = max(rocky, smoothstep(0.78, 0.86, crag * 0.7 + patchy * 0.3) * smoothstep(0.10, 0.22, slope));
	return max(rocky, smoothstep(0.2, 0.7, -drain) * smoothstep(0.14, 0.3, slope)
		* smoothstep(0.42, 0.62, crag * 0.6 + bush * 0.4) * crest_rock);
}


// Shrub crowns: a dome per jittered CROWN_CELL cell (0.64-1.24 of a cell across, big and small
// shrubs mixed, touching here and leaving gaps there), the tallest of the four nearest. .x the
// dome's height (0 in a gap, 0.55-1 at a crown's top), .yz where `w` sits on it (0 at the top, length 1 at the rim, in
// the direction away from its centre) - the slope a crown turns to the light.
vec3 hill_crowns(vec2 w) {
	vec2 q = w / CROWN_CELL;
	vec2 b = floor(q - 0.5);
	float best = 0.0;
	vec2 off = vec2(0.0);
	for (int j = 0; j <= 1; j++) {
		for (int i = 0; i <= 1; i++) {
			vec2 c = b + vec2(float(i), float(j));
			float hx = hash12t(c);
			float hy = hash12t(c + vec2(41.7, 17.3));
			// Radius 0.32-0.62 of a cell and jitter 0.3 each way: no crown reaches past the
			// four cells searched, so none is ever cut off straight.
			vec2 dv = (q - (c + 0.5 + (vec2(hx, hy) - 0.5) * 0.6)) / (0.32 + 0.3 * fract(hx * 7.13 + hy * 3.71));
			float h = sqrt(max(1.0 - dot(dv, dv), 0.0)) * (0.55 + 0.45 * hy);
			if (h > best) {
				best = h;
				off = dv;
			}
		}
	}
	return vec3(best, off);
}


// The stand noise with a stand's edge pushed out round the crowns and in between them. `fade`
// is how resolved the crowns are (0 once one is under a couple of pixels: then this is the plain
// stand noise, which is what the far ground and its average share assume).
float hill_stand_crowned(float stand, float crown, float fade) {
	return stand - (crown - CROWN_MEAN) * crown_edge * fade;
}
