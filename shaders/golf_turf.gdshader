shader_type spatial;
render_mode cull_back;

// The golf course's ground (GolfCourse, GolfBuild): ONE mesh per chunk, a grid whose vertices carry
// the course's distance fields (metres, negative inside), thresholded here per pixel so a 1.6 m
// grid still gives crisp edges:
//   COLOR.r fairway, COLOR.g green, COLOR.b bunker, COLOR.a tee     (0.5 + d / 16, clamped)
//   UV.x    water (pond and creek), UV.y the cart path and the paved ground   (metres)
//   UV2     the mowing direction of the nearest hole (unit XZ)
// Surfaces, top first: path and paving, water's edge, bunker sand (raked, with its lip), green
// (cross-cut) and its collar, tee (striped across), fairway (diagonal stripes) and its first cut,
// rough, and native grass out where nobody plays. Mown stripes are a change of sheen: the blades of
// one pass lean one way, and a band reads light when its blades lean away from you and dark when
// they lean toward you - so the stripes swap as the camera goes round, which is what real ones do.
// Works in LINEAR on both renderers (color_space.gdshaderinc).

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Turf colours, LINEAR.
uniform vec3 green_color = vec3(0.030, 0.092, 0.027);
uniform vec3 collar_color = vec3(0.040, 0.104, 0.030);
uniform vec3 fairway_color = vec3(0.050, 0.118, 0.033);
uniform vec3 tee_color = vec3(0.048, 0.112, 0.032);
uniform vec3 rough_color = vec3(0.040, 0.082, 0.026);
uniform vec3 native_color = vec3(0.135, 0.112, 0.055);
uniform vec3 sand_color = vec3(0.50, 0.43, 0.31);
uniform vec3 path_color = vec3(0.25, 0.245, 0.23);
uniform vec3 mud_color = vec3(0.060, 0.050, 0.034);
uniform vec3 soil_color = vec3(0.10, 0.075, 0.048);
// Mown stripes: band widths (m) and how strong the sheen is.
uniform float fairway_stripe = 8.5;
uniform float green_stripe = 3.8;
uniform float tee_stripe = 1.6;
uniform float stripe_amount = 0.2;
// Metres per grass texture tile.
uniform float grass_scale = 1.9;
uniform float rake_spacing = 0.22;
uniform float night_darken = 0.72;

global uniform float ground_detail;
global uniform float night_factor;
global uniform float road_wetness;
global uniform float city_hour;
global uniform vec3 sun_direction;

varying vec3 world_pos;
varying vec4 fields;
varying vec2 wp_fields;
varying vec2 mow_dir;

#include "res://shaders/color_space.gdshaderinc"

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.28 + vnoise(p * 4.7 + 19.3) * 0.17;
}

// A smooth 0..1 band edge `d` (metres) wide `w`, antialiased to the pixel footprint.
float edge(float d, float w) {
	float fw = max(fwidth(d), 1e-4);
	return smoothstep(-w - fw, w + fw, d);
}

// +-1 alternating bands `width` metres across, along `dir`, soft-edged and faded to 0 once a band
// is under a few pixels (the average of a striped lawn is no stripes).
float bands(vec2 p, vec2 dir, float width) {
	float t = dot(p, vec2(-dir.y, dir.x)) / width;
	float fw = max(fwidth(t), 1e-4);
	float s = sin(t * 3.14159265);
	float b = clamp(s / max(fw * 3.2, 0.12), -1.0, 1.0);
	return b * (1.0 - smoothstep(0.25, 0.6, fw));
}

// Wave 6 (golf_morning refcam, GolfMorning): 0 = the turf as it was, bit for bit.
global uniform float golf_morning;

// A tee box's divots as they really lie (golf_morning): small torn scars a hand long, along the
// line of play, packed in rows across the box where the markers have stood (a slow noise picks the
// worn rows, the box's middle wears most), most filled with the sand-and-seed mix (pale tan with a
// green fleck), the fresh ones bare soil with the torn turf's paler rim. Under a couple of pixels a
// cell is its average: a faint tan dusting where the rows are.
vec3 tee_divots(vec3 tc, vec2 wp, vec2 mow, float tee_d, float px) {
	vec2 along = vec2(mow.y, -mow.x);
	vec2 q = vec2(dot(wp, along), dot(wp, mow));
	vec2 cell = vec2(0.17, 0.12);
	vec2 g = q / cell;
	vec2 gi = floor(g);
	vec2 gf = fract(g) - 0.5;
	// How worn this row of the box is: rows across play (q.x) come and go, the middle wears most.
	float row = smoothstep(0.42, 0.78, vnoise(vec2(q.x * 0.55, 3.7)) * 0.75 + vnoise(q * 0.9 + 11.0) * 0.4);
	float inside = smoothstep(-0.4, -1.6, tee_d);
	float use = row * inside;
	float pick = hash12(gi + 17.3);
	float there = step(1.0 - 0.62 * use, pick);
	vec2 j = vec2(hash12(gi + 3.1), hash12(gi + 8.9)) - 0.5;
	vec2 d = (gf - j * 0.45) * cell;
	float ang = (hash12(gi + 5.5) - 0.5) * 0.5;
	vec2 r = vec2(cos(ang) * d.x - sin(ang) * d.y, sin(ang) * d.x + cos(ang) * d.y);
	vec2 hs = vec2(0.065 + 0.035 * hash12(gi + 2.2), 0.024 + 0.012 * hash12(gi + 4.4));
	float e = length(r / hs);
	float fw = px / 0.12;
	float ink = (1.0 - smoothstep(0.75, 1.0 + fw * 3.0, e)) * there;
	float rim = (1.0 - smoothstep(0.95, 1.35 + fw * 3.0, e)) * (1.0 - ink) * there;
	bool filled = hash12(gi + 12.7) < 0.66;
	vec3 mixc = mix(vec3(0.090, 0.080, 0.056), tee_color, 0.25 + 0.3 * hash12(gi + 6.6));
	vec3 fresh = soil_color * (0.65 + 0.25 * hash12(gi + 1.9));
	vec3 dc = filled ? mixc : fresh;
	vec3 sharp = mix(tc, tc * 1.12 + vec3(0.004, 0.003, 0.0), rim * 0.6);
	sharp = mix(sharp, dc, ink);
	// The average once a cell is under ~2 px: the share of the cell the scars cover, in their mix.
	vec3 avg = mix(tc, vec3(0.085, 0.075, 0.052), 0.62 * use * 0.14);
	return mix(sharp, avg, smoothstep(0.25, 0.6, fw));
}

// A bunker as it reads from the tee (golf_morning), not a flat white disc: the sand a shade warmer
// and darker, the lip's shadow and the turf's overhang a band just inside the rim, the raking done
// in passes (a metre-wide band of the rake in one direction, the next across it: a change of sheen
// that holds out to a hundred metres, long after the tines are under a pixel), damp patches where
// the night's irrigation still sits, and a scuffed trail where somebody walked out.
vec3 bunker_morning(vec3 sc, vec2 wp, vec2 across, float bunker_d, float px) {
	sc *= vec3(0.86, 0.84, 0.80);
	float in_lip = 1.0 - smoothstep(-0.05, -0.75, bunker_d);
	sc *= mix(1.0, 0.68, in_lip);
	vec2 along = vec2(across.y, -across.x);
	float pass = floor(dot(wp, along) / 1.15 + 0.6 * vnoise(wp * 0.35));
	float dirn = step(0.5, hash12(vec2(pass, 31.0)));
	sc *= 1.0 + mix(-0.06, 0.06, dirn) * (1.0 - smoothstep(0.08, 0.25, px));
	float damp = smoothstep(0.55, 0.8, fbm(wp * 0.33 + 5.0));
	sc *= 1.0 - 0.16 * damp;
	float scuff = smoothstep(0.6, 0.85, vnoise(wp * 1.7)) * smoothstep(0.45, 0.62, vnoise(wp * 0.21 + 9.0));
	sc *= 1.0 - 0.12 * scuff;
	return sc;
}

// The native areas as bunchgrass (golf_morning), not flat tan ground: clumps a hand or two across,
// their tops straw-bright and leaning down the wind, green at the base and dark between them; past
// a few pixels a clump field's average (darker and greener than the bare tan it was), patchier at
// the scale of metres where the clumps thin out.
vec3 native_grass(vec2 wp, float mid, float px) {
	vec2 g = wp / 0.42;
	vec2 gi = floor(g);
	vec2 f = fract(g) - 0.5 - (vec2(hash12(gi + 2.7), hash12(gi + 7.3)) - 0.5) * 0.5;
	float r = 0.26 + 0.14 * hash12(gi + 4.1);
	// The blades lean along +x: a clump is longer that way, its tips at the lee end.
	vec2 e = vec2(f.x * 0.75, f.y);
	float clump = 1.0 - smoothstep(r * 0.55, r, length(e));
	float tip = clump * smoothstep(-0.1, 0.25, f.x);
	float thin = smoothstep(0.35, 0.7, vnoise(wp * 0.21 + 3.0));
	clump *= 0.55 + 0.45 * thin;
	vec3 base_c = mix(native_color * vec3(0.55, 0.62, 0.55), rough_color * 0.9, 0.45);
	vec3 sharp = mix(base_c * 0.5, native_color * (0.8 + 0.25 * hash12(gi + 9.9)), clump);
	sharp = mix(sharp, native_color * 1.1, tip * 0.5);
	vec3 avg = mix(base_c * 0.5, native_color * 0.85, 0.42 * (0.55 + 0.45 * thin));
	vec3 c = mix(sharp, avg, smoothstep(0.06, 0.2, px));
	return c * (0.82 + 0.36 * mid);
}

// How much dew lies on the course at this hour (golf_morning): on the grass all night and at dawn,
// burnt off by mid-morning.
float dew_amount(float h) {
	return (1.0 - smoothstep(8.6, 10.6, h)) * step(3.0, h) + smoothstep(20.0, 23.5, h);
}

// Morning dew (golf_morning): the beads turn the turf silver-grey, most at a grazing look and
// toward the low sun (they scatter forward), and glint; where feet went through it this morning the
// beads are knocked off and the dark green shows in trails - down the fairway along the line of
// play, wandering, starting and stopping; across a tee; the greens, mown at first light, are dark
// but for a ring round the edge. `along` is the hole's line of play: the mow direction less 45
// degrees (fairway, green), across the tee's own stripes on a tee.
vec3 dew_turf(vec3 col, vec2 wp, vec2 mow, vec3 v_world, float fw_d, float green, float tee, float dew, float px, inout float wet_k) {
	vec2 along = normalize(mix(mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071)) * mow, vec2(mow.y, -mow.x), tee));
	vec2 side = vec2(-along.y, along.x);
	float a = dot(wp, along);
	float l = dot(wp, side) + 1.8 * sin(a * 0.027 + 1.3) + 2.6 * (vnoise(vec2(a * 0.018, 0.0) + wp.yx * 0.004) - 0.5);
	float sp = 6.5;
	float band = floor(l / sp);
	float lf = (fract(l / sp) - 0.5) * sp + (hash12(vec2(band, 7.0)) - 0.5) * 2.4;
	float fwl = max(px, 1e-4);
	float lane = 1.0 - smoothstep(0.22, 0.34 + fwl, abs(lf));
	// A trail runs for a while and stops (a player cut across to their ball); more on the fairway.
	float runs = smoothstep(0.48, 0.62, vnoise(vec2(a * 0.025, band * 3.1)));
	float where = (1.0 - smoothstep(2.0, 6.5, fw_d)) * (1.0 - green) + tee * 0.6;
	float trail = lane * runs * where * (1.0 - smoothstep(0.4, 1.2, fwl));
	// Footfalls along a trail: the beads go in patches a stride apart.
	trail *= 0.7 + 0.3 * smoothstep(0.3, 0.6, vnoise(vec2(a * 1.6, lf * 3.0)));
	// The green mown at dawn: only a ring of dew at its edge (the clean-up pass's turn).
	float cover = 1.0 - trail;
	cover *= 1.0 - green * 0.82;
	// The look: grazing and toward the sun the beads read silver; looking down the sun, less.
	vec3 to_eye = v_world;
	float graze = 1.0 - abs(to_eye.y);
	vec2 sun_xz = normalize(sun_direction.xz + vec2(1e-4, 0.0));
	float fwd = clamp(dot(-to_eye.xz, sun_xz), -1.0, 1.0);
	float k = dew * cover * (0.08 + 0.22 * graze * graze * graze) * (0.6 + 0.5 * max(fwd, 0.0));
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	vec3 silver = mix(col, vec3(lum), 0.6) * 1.32 + vec3(0.002, 0.003, 0.005);
	col = mix(col, silver, clamp(k, 0.0, 0.32));
	// The beads' own gloss: the renderer's sky and sun reflection off a wet film (smoother, more
	// specular), which is what reads silver at a grazing look; the trails stay matte.
	wet_k = dew * cover;
	// Trails: the turf with its dew knocked off, and the bruised blades a shade darker.
	col *= 1.0 - 0.06 * trail * dew;
	return col;
}

void vertex() {
	world_pos = VERTEX;
	fields = (COLOR - 0.5) * 16.0;
	wp_fields = UV;
	mow_dir = UV2;
}

void fragment() {
	vec2 wp = world_pos.xz;
	float fw_d = fields.r;
	float green_d = fields.g;
	float bunker_d = fields.b;
	float tee_d = fields.a;
	float water_d = wp_fields.x;
	float path_d = wp_fields.y;
	vec2 mow = normalize(mow_dir + vec2(1e-4, 0.0));
	// The pixel's footprint in metres, taken here in uniform control flow (golf_morning's patterns).
	vec2 fwp2 = fwidth(wp);
	float px = max(fwp2.x, fwp2.y);

	// The grass texture as detail only: its luminance over its own mean, recoloured per surface.
	vec2 guv = wp / grass_scale;
	vec3 gtex = cs_in(texture(grass_tex, guv).rgb);
	vec3 gn = texture(grass_nrm, guv).rgb;
	if (ground_detail > 0.5) {
		vec2 rot = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * guv * 0.61;
		float bl = smoothstep(0.35, 0.65, vnoise(wp * 0.05));
		gtex = mix(gtex, cs_in(texture(grass_tex, rot).rgb), bl);
		gn = mix(gn, texture(grass_nrm, rot).rgb, bl);
	}
	float glum = dot(gtex, vec3(0.2126, 0.7152, 0.0722));
	float gmean = dot(cs_in(textureLod(grass_tex, vec2(0.5), 11.0).rgb), vec3(0.2126, 0.7152, 0.0722));
	float detail = clamp(glum / max(gmean, 0.01), 0.35, 1.9);

	// The camera's heading over the ground: which way a band's lean reads.
	vec3 v_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec2 view_xz = normalize(v_world.xz + vec2(1e-4, 0.0));

	// --- Turf ------------------------------------------------------------------------------------
	float big = fbm(wp * 0.031);
	float mid = fbm(wp * 0.12 + 3.0);
	// Rough, with native grass taking over far from play (the fields saturate at 8 m).
	vec3 col = rough_color * (0.82 + 0.36 * mid) * mix(vec3(1.0), vec3(1.10, 1.02, 0.86), big);
	float nativ = smoothstep(6.5, 7.9, min(min(fw_d, green_d), min(tee_d, water_d + 4.0))) * smoothstep(0.56, 0.72, fbm(wp * 0.018 + 41.0)) * 0.85;
	vec3 native_c = native_color * (0.78 + 0.44 * mid);
	if (golf_morning > 0.5) {
		native_c = native_grass(wp, mid, px);
	}
	col = mix(col, native_c, nativ);
	if (golf_morning > 0.5) {
		// golf_morning: no two patches of turf the same green - the warm-season grass of an LA
		// course going off-colour in the rough in patches (yellower, toward dormant straw), wetter
		// and bluer in others, at a few to tens of metres.
		float hv = fbm(wp * 0.067 + 5.3);
		float play = 1.0 - smoothstep(0.5, 3.5, min(min(fw_d, green_d), tee_d));
		col *= mix(vec3(1.07, 1.03, 0.84), vec3(0.93, 1.0, 1.08), hv);
		float dormant = smoothstep(0.58, 0.78, fbm(wp * 0.043 + 21.0)) * (1.0 - play) * (1.0 - nativ);
		col = mix(col, mix(col, native_color * 0.82, 0.55), dormant * 0.7);
	}
	float rough_d = 1.0;
	float lean = 0.0;
	float stripe_k = 0.0;
	float nrm_k = 1.0 - 0.3 * nativ;
	float roughness = 0.92;
	float shade = 1.0;
	// Fairway, with a 1.8 m first cut round it (a shade between it and the rough).
	float first_cut = 1.0 - edge(fw_d - 1.8, 0.15);
	float fairway = 1.0 - edge(fw_d, 0.08);
	col = mix(col, mix(rough_color, fairway_color, 0.55) * (0.9 + 0.2 * mid), first_cut * (1.0 - fairway));
	if (fairway > 0.001) {
		// Diagonal stripes, the mower's passes at 45 degrees to the line of play.
		float b = bands(wp, mow, fairway_stripe);
		vec3 fc = fairway_color * (0.92 + 0.16 * mid);
		// Divots in the landing zones: a few dark scars, sand-filled ones paler.
		vec2 dc = floor(wp * 5.0);
		float dv = step(0.9975, hash12(dc)) * (1.0 - smoothstep(0.25, 0.5, length(fract(wp * 5.0) - 0.5)));
		fc = mix(fc, mix(soil_color, sand_color * 0.6, step(0.5, hash12(dc + 3.0))), dv * 0.6 * smoothstep(0.0, -3.0, fw_d) * (1.0 - smoothstep(0.08, 0.2, fwidth(wp.x))));
		col = mix(col, fc, fairway);
		lean = mix(lean, b, fairway);
		stripe_k = mix(stripe_k, 1.0, fairway);
		nrm_k = mix(nrm_k, 0.55, fairway);
		roughness = mix(roughness, 0.86, fairway);
	}
	// Tee boxes: short turf striped across, a few divot scars, a crisp mown edge.
	float tee = 1.0 - edge(tee_d, 0.06);
	if (tee > 0.001) {
		float b = bands(wp, mow, tee_stripe);
		vec3 tc = tee_color * (0.92 + 0.14 * mid);
		if (golf_morning > 0.5) {
			tc = tee_divots(tc, wp, mow, tee_d, px);
		} else {
			float scar = step(0.93, hash12(floor(wp * 3.0))) * smoothstep(-0.5, -3.0, tee_d);
			tc = mix(tc, soil_color * 1.2, scar * 0.8);
		}
		col = mix(col, tc, tee);
		lean = mix(lean, b, tee);
		stripe_k = mix(stripe_k, 0.9, tee);
		nrm_k = mix(nrm_k, 0.5, tee);
	}
	// Green and collar: the collar a ring of fringe, the green cut short both ways (a checker of
	// two passes), its turf finer and a little glossier.
	float collar = 1.0 - edge(green_d - 1.3, 0.06);
	float green = 1.0 - edge(green_d, 0.05);
	if (collar > 0.001) {
		float b = bands(wp, mow, 2.0);
		col = mix(col, collar_color * (0.95 + 0.1 * mid), collar * (1.0 - green));
		lean = mix(lean, b * 0.5, collar * (1.0 - green));
		stripe_k = mix(stripe_k, 0.7, collar * (1.0 - green));
		nrm_k = mix(nrm_k, 0.4, collar);
	}
	if (green > 0.001) {
		float b1 = bands(wp, mow, green_stripe);
		float b2 = bands(wp, vec2(-mow.y, mow.x), green_stripe) * 0.35;
		vec3 gc = green_color * (0.95 + 0.1 * fbm(wp * 0.8));
		// Ball marks and old cup plugs: tiny pale rings, very sparse.
		float plug = 1.0 - smoothstep(0.05, 0.075, length(fract(wp / 3.7 + vec2(hash12(floor(wp / 3.7)))) * 3.7 - 1.85));
		gc *= 1.0 + 0.12 * plug * step(0.86, hash12(floor(wp / 3.7) + 9.0));
		col = mix(col, gc, green);
		lean = mix(lean, b1 + b2, green);
		stripe_k = mix(stripe_k, 0.42, green);
		nrm_k = mix(nrm_k, 0.18, green);
		roughness = mix(roughness, 0.74, green);
	}
	// The sheen: a band leaning away from the eye is lighter.
	float facing = dot(mow, -view_xz);
	float sheen = lean * (0.35 + 0.65 * abs(facing)) * sign(facing + 1e-3);
	// golf_morning: a stripe's sheen fades out as the view turns square to the mower's line and
	// comes back the other way round, never a flip: sign() drew a hard seam down the frame where
	// the view crossed square (a tee seen down the line of play split in two at the screen's middle).
	if (golf_morning > 0.5) {
		sheen = lean * clamp(facing * 2.2, -1.0, 1.0) * (0.55 + 0.45 * abs(facing));
	}
	float dew = golf_morning > 0.5 ? dew_amount(city_hour) * (1.0 - clamp(road_wetness * 2.0, 0.0, 1.0)) : 0.0;
	// Fresh-cut stripes stand out in the dew (the wet blades lie flatter and catch the light).
	col *= 1.0 + stripe_amount * stripe_k * sheen * (1.0 + 0.8 * dew);
	col *= detail * 0.55 + 0.45;
	float dew_k = 0.0;
	if (dew > 0.001) {
		col = dew_turf(col, wp, mow, v_world, fw_d, green, tee, dew, px, dew_k);
	}

	// --- Water's edge: wet mud down to the water, lush darker grass on the bank above it. -------
	float bank = 1.0 - edge(water_d - 1.2, 0.3);
	col = mix(col, col * vec3(0.82, 0.92, 0.80), bank);
	float wet = 1.0 - edge(water_d - 0.35, 0.18);
	col = mix(col, mud_color * (0.8 + 0.4 * mid), wet);
	roughness = mix(roughness, 0.55, wet);

	// --- Bunkers: raked sand in a crisp grass edge, a dark line of soil where the sod is cut. ----
	vec3 nrm_add = vec3(0.0);
	float sand = 1.0 - edge(bunker_d, 0.03);
	float sod_line = (1.0 - smoothstep(0.0, 0.16, abs(bunker_d - 0.06))) * (1.0 - sand);
	col = mix(col, soil_color, sod_line * 0.85);
	if (sand > 0.001) {
		vec3 st = cs_in(texture(sand_tex, wp / 2.6).rgb);
		float sl = dot(st, vec3(0.2126, 0.7152, 0.0722));
		float smean = dot(cs_in(textureLod(sand_tex, vec2(0.5), 11.0).rgb), vec3(0.2126, 0.7152, 0.0722));
		vec3 sc = sand_color * clamp(sl / max(smean, 0.01), 0.6, 1.4);
		// Rake lines along the hole, wavering, and the odd footprint.
		vec2 across = vec2(-mow.y, mow.x);
		float t = dot(wp, across) / rake_spacing + sin(dot(wp, mow) * 0.7) * 0.8 + vnoise(wp * 0.6) * 1.4;
		float fwt = max(fwidth(t), 1e-4);
		float rake = sin(t * 6.2831853) * (1.0 - smoothstep(0.2, 0.5, fwt));
		sc *= 1.0 + 0.06 * rake;
		// Sand flashed up the face on the green side reads paler; the floor's edge damper.
		sc *= mix(0.82, 1.0, smoothstep(0.0, -0.9, bunker_d));
		if (golf_morning > 0.5) {
			sc = bunker_morning(sc, wp, across, bunker_d, px);
		}
		sc = mix(sc, sc * 0.55, road_wetness * 0.8);
		col = mix(col, sc, sand);
		nrm_add += vec3(across.x, 0.0, across.y) * rake * 0.12 * sand;
		roughness = mix(roughness, 0.96, sand);
		nrm_k *= 1.0 - sand;
		shade *= 1.0;
	}

	// --- The cart path and the paved ground: concrete, broom-finished, a darker edge. ----------
	float path = 1.0 - edge(path_d, 0.04);
	if (path > 0.001) {
		vec3 ct = cs_in(texture(concrete_tex, wp / 3.0).rgb);
		vec3 pc = path_color * clamp(dot(ct, vec3(0.333)) / 0.42, 0.65, 1.3);
		pc *= 0.92 + 0.12 * vnoise(wp * 0.4);
		pc *= mix(0.86, 1.0, smoothstep(0.0, -0.35, path_d));
		// Tyre-worn turf beside it.
		col = mix(col, pc, path);
		roughness = mix(roughness, 0.84, path);
		nrm_k *= 1.0 - path;
	}
	float worn = (1.0 - edge(path_d - 0.7, 0.4)) * (1.0 - path) * smoothstep(0.4, 0.7, vnoise(wp * 0.7));
	col = mix(col, mix(col, soil_color * 1.4, 0.55), worn);

	// Night: unlit turf goes dim and blue-grey (as lawn.gdshader).
	float nf = clamp(night_factor, 0.0, 1.0) * night_darken;
	float grey = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(grey * 0.78, grey * 0.84, grey * 1.05) * 0.35, nf);

	// Normal: the mesh's, bent by the grass texture's (world XZ, no tangents needed) and the rakes.
	vec2 nt = (gn.xy * 2.0 - 1.0);
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	n_world = normalize(n_world + vec3(nt.x, 0.0, nt.y) * 0.45 * nrm_k + nrm_add);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	ALBEDO = cs_out(col * shade);
	ROUGHNESS = clamp(roughness - road_wetness * 0.3, 0.3, 1.0);
	SPECULAR = 0.3;
	// golf_morning's dew: the turf (not the sand, path or water) glossier and more specular.
	float dew_turf_k = dew_k * (1.0 - sand) * (1.0 - path) * (1.0 - wet);
	// (Gentle: on Forward+ a 0.7 roughness lit a warm sun hot spot over the whole rough toward the
	// low sun, read as dry straw.)
	ROUGHNESS = mix(ROUGHNESS, 0.8, dew_turf_k * 0.6);
	SPECULAR = mix(SPECULAR, 0.34, dew_turf_k);
}
