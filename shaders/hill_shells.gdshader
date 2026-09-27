shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// The hills' near ground as a pile of thin shells (HillShells, scripts/world/hill_shells.gd): the
// terrain tile drawn again LAYERS times, each copy lifted a little further over the ground, and
// every fragment of every shell kept only where a grass blade or a clump of brush reaches that
// high. From standing height the painted ground was smooth plastic with dark and tan blobs on
// it; the shells give it the knee-high dry grass between the stands and a rough, lumpy brush
// understory in them, out to fade_end metres, for the tile's triangles times the layers and no
// instancing at all.
//
// Where is which: hill_splat.gdshaderinc, the maths terrain.gdshader paints the ground with,
// so the grass grows out of painted straw and the understory out of the painted stands, and
// nothing grows on rock, cuts, trails, roads or pads (COLOR.b, worked out per vertex by the
// chunk). The slow parts of that field (the stand threshold, the patch, trail and crag noises)
// are worked out per vertex - the vertices are ~3 m apart and those noises vary over 25 m and
// more - and the ones that rag a stand's edge (the 8 m clumps, the 3 m bushes) per fragment.
//
// Mesh: the terrain tile's own, in a MultiMesh of identity instances. INSTANCE_CUSTOM.r is the
// layer's height as a fraction of the canopy (stored so that any prefix of 2, 4 or 8 instances
// is spread evenly up the canopy, which is what HillShells draws with distance); COLOR is the
// terrain's (r height, g drainage) plus b, over 0.5 where shells may grow and under it on a
// road, pad or landmark, as a distance so the edge interpolates straight.
//
// Nothing here casts a shadow (the painted stands are the shade) and there is no texture fetch:
// under the depth pre-pass (Forward+) the discard test runs once per layer and the colour only
// once per pixel, so the test is kept to two value noises and a few hashes.

#include "res://shaders/hill_splat.gdshaderinc"

// How far the scene's origin has been shifted (CityStreamer sets it, as for the terrain).
uniform vec2 world_offset = vec2(0.0);
// The painted ground's own grass texture and aerial mottle (PropFactory.hill_shell_material()
// hands over the terrain's), at terrain.gdshader's tile sizes and mean lumas: the painted straw
// is straw_color times their light and dark, which averages well over straw_color itself, and
// shells coloured by straw_color alone came out a third as bright as the ground they grow from.
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mottle_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_scale = 3.5;
uniform float mottle_scale = 13.0;
uniform float grass_mean_luma = 0.145;
uniform float mottle_mean_luma = 0.126;
// Metres of the tallest grass (knee-high wild oats and brome) and of the brush understory, the
// low tangle of leaves and litter the 3D shrubs of a stand stand in (kept low: a metre of shells
// seen from the side is a stack of slices, and the shrubs are the canopy).
uniform float grass_height = 0.55;
uniform float brush_height = 0.42;
// The lone sage's height against the understory's.
uniform float sage_height = 1.1;
// Metres across a blade's cell (one blade per cell, tapering to a point), how far (metres, at
// the tips) a patch of grass is laid over, and the thatch mat at the roots (metres deep).
uniform float blade_cell = 0.02;
uniform float blade_lean = 0.16;
// How many times longer than wide a blade's cell is, along its patch's lean.
uniform float blade_stretch = 2.6;
uniform float thatch_height = 0.05;
// Metres across the brush understory's leaf clusters.
uniform float leaf_size = 0.032;
// Share of the cells that carry a blade at all on the thickest grass.
uniform float blade_density : hint_range(0.0, 1.0) = 0.9;
// Metres from the camera where the shells start to thin and where they are gone.
uniform float fade_start = 35.0;
uniform float fade_end = 75.0;
// How much darker the bottom of the grass and the heart of a clump are than the tips and tops.
uniform float root_shadow : hint_range(0.0, 1.0) = 0.38;
// Straw tips: paler and greyer than the stems (sun-bleached seed heads).
uniform float tip_bleach : hint_range(0.0, 1.0) = 0.45;
// Brightness of the grass and the brush against the painted ground's own colours.
uniform float grass_gain = 1.25;
uniform float brush_gain = 1.35;
// Sideways bend at the top of the grass in the wind, metres.
uniform float wind_bend = 0.07;
// Light through the thin blades from behind (see grass.gdshader).
uniform float translucency : hint_range(0.0, 1.0) = 0.3;
uniform float scatter_gain : hint_range(0.0, 4.0) = 1.6;
// No shells above this height (the terrain's snow line).
uniform float top_line = 1100.0;
// For tools/glshot/hill_ground_shot.gd (SHELL_DEBUG / DEBUG_SEQ): 1 draws every layer solid in
// its height (r), where it may grow (g) and the fade (b); 2 solid in the keep tests; 3 shades the
// kept fragments in the painted straw's own colour on the slope's normal (lit like the ground
// under them, or the lighting is off).
uniform int debug_mode = 0;

global uniform float wind_factor;
global uniform vec3 sun_direction;

varying vec3 world_pos;
varying vec3 world_nrm;
// th (stand threshold), patchy, hill, span (metres the top layer stands over the ground here)
varying vec4 v_field;
// tn (trail noise), trail zone, crag, layer (0..1)
varying vec4 v_noise;
// drainage (-1 crest .. +1 gully), clear of roads and pads (0..1)
varying vec2 v_site;


void vertex() {
	world_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vec3 ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 w = ground.xz + world_offset;
	float drain = COLOR.g * 2.0 - 1.0;
	vec2 aspect = hill_aspect(world_nrm);
	vec2 broad = hill_broad(w);
	float th = hill_stand_threshold(aspect.x, aspect.y, drain, broad.x);
	// The canopy's top here: the understory's height where a stand is likely, the grass's
	// elsewhere (the stand noise without its single-bush octave, with a wider edge for it).
	float stand = broad.y * STAND_PATCH_W + vnoiset(w * 0.12 + 17.0) * STAND_MID_W + STAND_BIAS;
	float span = mix(grass_height, brush_height, smoothstep(th + 0.25, th - 0.12, stand));
	// A little lower out where the shells are thinning, so the last of them sink into the ground.
	float dist = distance(ground, INV_VIEW_MATRIX[3].xyz);
	span *= mix(1.0, 0.6, smoothstep(fade_start, fade_end, dist));
	float layer = INSTANCE_CUSTOM.r;
	VERTEX.y += layer * span;
	world_pos = ground + vec3(0.0, layer * span, 0.0);
	v_field = vec4(th, broad.y, broad.x, span);
	v_noise = vec4(vnoiset(w * 0.0065 + 41.0), vnoiset(w * 0.0021 + 7.0), vnoiset(w * 0.021 + 29.0), layer);
	v_site = vec2(drain, COLOR.b);
}


float shell_luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}


// A 2D hash for jittering cells.
vec2 hash22s(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}


void fragment() {
	float layer = v_noise.w;
	float span = v_field.w;
	// Metres this fragment stands over the ground.
	float lh = layer * span;
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	bool shaded = debug_mode == 0 || debug_mode == 3;
	if (shaded && (v_site.y < 0.5 || fade <= 0.0 || world_pos.y < 1.5 || world_pos.y > top_line)) {
		discard;
	}
	vec2 w = world_pos.xz + world_offset;
	vec3 wn = normalize(world_nrm);
	vec2 aspect = hill_aspect(wn);
	float slope = aspect.x;
	float drain = v_site.x;
	float patchy = v_field.y;

	// ---- the painted ground under this fragment (terrain.gdshader's own terms) --------------
	float fw = length(fwidth(w));
	float bush_fade = hill_bush_fade(fw);
	float bush = mix(0.5, vnoiset(w * 0.29 + 3.7), bush_fade);
	float mid_fade = hill_mid_fade(fw);
	float mid = mix(0.5, vnoiset(w * 0.12 + 17.0), mid_fade);
	float fine_fade = hill_fine_fade(fw);
	float fine = mix(0.5, vnoiset(w * 0.9 + 51.0), fine_fade);
	float crown_fade = 1.0 - smoothstep(0.06, 0.2, fw);
	vec3 crowns = hill_crowns(w);
	float stand = hill_stand(v_field.x, hill_stand_crowned(hill_stand_noise(patchy, mid, bush, fine), crowns.x, crown_fade), bush, hill_stand_edge(fine_fade, bush_fade, mid_fade));
	float sage = hill_sage(bush, bush_fade);
	float brush = max(stand, sage);
	float trail = hill_trail(v_noise.x, fwidth(v_noise.x), v_noise.y, slope);
	float bare = hill_bare(slope, patchy, drain, trail);
	float rocky = hill_rocky(slope, v_noise.z, patchy, drain, bush);
	// Nothing grows on the rock and the cuts, and it thins out toward them.
	float cover = (1.0 - smoothstep(0.25, 0.6, bare)) * (1.0 - smoothstep(0.2, 0.5, rocky)) * fade;
	if (shaded && cover <= 0.02) {
		discard;
	}

	// The blades lean: each patch of grass is laid over one way (a slow direction field, as rain
	// and wind leave a hillside), and the wind sways the tops. The pattern a layer is cut from
	// slides that way with the square of the height, so a blade is a curve, not a column.
	float gust = 0.6 + 0.4 * sin(TIME * 0.9 + (w.x + w.y) * 0.05);
	float lean_a = vnoiset(w * 0.35 + 91.0) * 12.0;
	vec2 lean = vec2(cos(lean_a), sin(lean_a)) * blade_lean
		+ vec2(0.8, 0.6) * (sin(TIME * 1.7 + w.x * 0.21 + w.y * 0.13) * 0.5 + 0.5) * wind_bend * max(wind_factor, 0.25) * gust;
	float bend = layer * layer;

	// ---- brush understory: the painted crowns grown into mounds of leaves -----------------
	// Each shrub crown of a stand (hill_crowns(), the domes terrain.gdshader shades) rises to
	// brush_height at its top, filled with small leaves: one per jittered leaf_size cell and
	// height band (the bands staggered per cell, so no two leaves line up into a layer), more of
	// the cells empty toward the surface. The gaps between crowns stay the painted shade under
	// the shrubs. The sage and buckwheat dotted through the grass are the same, lower and paler.
	float keep_brush = 0.0;
	vec2 dome_off = crowns.yz;
	float dome_depth = 0.0;
	float dome_top = 0.0;
	float leaf_rand = 0.0;
	float in_stand = smoothstep(0.35, 0.75, stand);
	// A lone sage is one rounded bush the shape of its painted dot, half the stand's height.
	float in_sage = smoothstep(0.2, 0.45, sage) * (1.0 - in_stand);
	float mound = max(in_stand * crowns.x, in_sage * sage_height * smoothstep(0.74, 0.92, bush));
	if (mound > 0.0) {
		dome_top = brush_height * mix(0.6, 1.05, bush) * mound;
		if (in_sage > in_stand) {
			dome_off = vec2(0.0);
		}
		dome_depth = dome_top - lh;
		if (dome_depth > 0.0) {
			// The leaf grid turns with a slow field, so its rows never line up across a stand.
			float la = vnoiset(w * 0.45 + 33.0) * 6.2832;
			vec2 lp = w - lean * bend * 0.3;
			vec2 lq = vec2(dot(lp, vec2(cos(la), sin(la))), dot(lp, vec2(-sin(la), cos(la)))) / leaf_size;
			vec2 lc = floor(lq);
			float band = floor(lh / (leaf_size * 1.3) + hash12t(lc + 5.3));
			vec2 lh2 = hash22s(lc + band * 13.7);
			leaf_rand = lh2.x;
			vec2 lo = (fract(lq) - 0.5 - (hash22s(lc + band * 3.1 + 0.7) - 0.5) * 0.5) * vec2(1.0, mix(0.6, 1.4, lh2.x));
			float fill = mix(0.4, 0.85, smoothstep(0.0, 0.12, dome_depth));
			bool leaf = lh2.y < fill && length(lo) < mix(0.3, 0.6, fract(lh2.x * 5.3));
			// Leaves under a pixel only alias: past that, kept by their average, dithered.
			float lpx = fw / leaf_size;
			if (smoothstep(0.9, 2.0, lpx) > hash12t(FRAGCOORD.yx + 29.0)) {
				leaf = hash12t(FRAGCOORD.xy + fract(TIME) * 61.0) < fill * 0.55;
			}
			if (leaf) {
				keep_brush = 1.0;
			}
		}
	}

	// ---- grass: a tapering blade per jittered cell, its height from the tufts it stands in ---
	// Down at the roots, a mat of thatch covers the ground wherever the terrain paints grass (and
	// leaves its bare patches between the tufts), so the soil between blades is the grass's own
	// shade, not the painted straw lit as if it were on top.
	float keep_grass = 0.0;
	float blade_t = 0.0;
	float blade_rand = 0.0;
	float grass_amount = (1.0 - max(in_stand, in_sage) * 0.85) * cover;
	if (keep_brush < 0.5 && grass_amount > 0.02) {
		// Tufts and bare ground between them, as the terrain paints them (its `tuft`).
		float leaf_fade = 1.0 - smoothstep(0.12, 0.5, fw);
		float leaf = mix(0.5, vnoiset(w * 0.9 + 51.0), leaf_fade);
		float tuft = bush * 0.6 + leaf * 0.4;
		float thick = smoothstep(0.22, 0.62, tuft);
		float tall = grass_height * thick * mix(0.7, 1.0, patchy) * grass_amount;
		if (lh < thatch_height * thick * grass_amount) {
			keep_grass = 1.0;
			blade_t = 0.0;
			blade_rand = hash12t(floor(w / 0.04));
		} else {
			// Blades in the frame of their patch's lean: long along it, thin across, so a blade
			// laid over reads as a stalk and not a dot, and the grid turns with the lean field
			// (no moire from one grid the size of a pixel).
			vec2 along = vec2(cos(lean_a), sin(lean_a));
			vec2 p = w - lean * bend;
			vec2 q = vec2(dot(p, along), dot(p, vec2(-along.y, along.x))) / vec2(blade_cell * blade_stretch, blade_cell);
			vec2 cell = floor(q);
			vec2 h = hash22s(cell);
			float strand = tall * mix(0.3, 1.0, h.x);
			blade_rand = h.y;
			if (h.y < blade_density && lh < strand) {
				blade_t = lh / max(strand, 0.001);
				vec2 centre = cell + 0.5 + (hash22s(cell + 71.0) - 0.5) * vec2(0.3, 0.6);
				vec2 d = (q - centre) * vec2(1.0, 1.0);
				// Round at the root, a point at the tip.
				float r = 0.48 * pow(1.0 - blade_t, 0.7);
				if (d.x * d.x + d.y * d.y < r * r) {
					keep_grass = 1.0;
				}
			}
			// Under a pixel a cell only aliases: past that, keep this layer by its average cover,
			// dithered per pixel (the temporal pass resolves it; the grid is gone either way).
			float px = fw / blade_cell;
			if (px > 0.9) {
				float rel = clamp(lh / max(tall, 0.001), 0.0, 1.0);
				float avg = blade_density * (1.0 - rel) * 0.7;
				float dither = hash12t(FRAGCOORD.xy + fract(TIME) * 97.0);
				float far_keep = step(dither, avg);
				if (smoothstep(0.9, 2.0, px) > hash12t(FRAGCOORD.yx + 13.0)) {
					keep_grass = far_keep;
					// Coloured by the layer's height in the grass, as a blade there would be (left
					// at the roots' shade, the whole far lawn went dark).
					blade_t = rel;
				}
			}
		}
	}
	if (shaded && keep_brush < 0.5 && keep_grass < 0.5) {
		discard;
	}

	// ---- colour and light ---------------------------------------------------------------------
	// The painted ground's light and dark (terrain.gdshader's `gl`), so the shells carry its tone.
	float gtex = clamp(shell_luma(texture(grass_albedo, w / grass_scale).rgb) / grass_mean_luma, 0.3, 2.0);
	float mot = clamp(shell_luma(texture(mottle_albedo, w / mottle_scale).rgb) / mottle_mean_luma, 0.4, 1.8);
	float gl = gtex * mot;
	// The grass is lit on the slope's own normal, tilted a little per blade: bent toward straight
	// up (as the lawn blades are), a slope facing the sun got a fraction of the light the painted
	// ground under it gets, and the whole hillside went dark brown.
	vec2 bj = (hash22s(floor(w / blade_cell) + 5.0) - 0.5) * 0.35;
	vec3 up_n = normalize(wn + vec3(bj.x, 0.0, bj.y));
	vec3 n;
	vec3 col;
	float ao;
	float through;
	if (keep_brush > 0.5) {
		// Crowns lit as domes (their flanks turn from the light), each leaf tilted its own way.
		vec2 tilt = (hash22s(floor(w / leaf_size) + 9.1) - 0.5) * 0.9;
		n = normalize(wn + vec3(dome_off.x + tilt.x, 0.0, dome_off.y + tilt.y) * 1.1);
		col = mix(chaparral_color, sage_color, step(in_stand, in_sage)) * brush_gain * mix(0.62, 1.4, leaf_rand) * mix(0.8, 1.15, mid) * mix(0.85, 1.12, bush) * (0.65 + 0.35 * gl);
		// Deeper inside the mass is darker: the light gets in only a few centimetres.
		ao = mix(1.0 - root_shadow, 1.0, exp(-dome_depth * 7.0));
		through = 0.1;
	} else {
		n = up_n;
		float green = clamp(smoothstep(0.3, 0.75, v_field.z) * 0.8 + (1.0 - smoothstep(60.0, 260.0, world_pos.y)) * 0.25, 0.0, 1.0);
		col = mix(straw_color, straw_green_color, green * 0.8) * gl * grass_gain * mix(0.78, 1.25, blade_rand);
		// Sun-bleached seed heads at the top of the blade.
		col = mix(col, vec3(dot(col, vec3(0.33))) * 1.3, tip_bleach * smoothstep(0.55, 1.0, blade_t));
		ao = mix(1.0 - root_shadow, 1.0, smoothstep(0.0, 0.7, blade_t));
		through = translucency * (0.3 + 0.9 * blade_t);
	}
	ALBEDO = col * ao;
	AO = mix(0.6, 1.0, ao);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = keep_brush > 0.5 ? 0.82 : 0.93;
	SPECULAR = 0.35;
	vec3 to_cam = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float facing = clamp(dot(to_cam, -normalize(sun_direction)), 0.0, 1.0);
	BACKLIGHT = ALBEDO * through * (1.0 + scatter_gain * pow(facing, 5.0));
	if (debug_mode == 3) {
		// Lighting probe: the painted straw's own colour, the terrain's normal.
		ALBEDO = straw_color * gl;
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		BACKLIGHT = vec3(0.0);
		AO = 1.0;
	} else if (!shaded) {
		ALBEDO = vec3(0.0);
		BACKLIGHT = vec3(0.0);
		EMISSION = debug_mode == 1 ? vec3(layer, v_site.y, fade)
			: vec3(step(0.5, v_site.y), step(0.02, cover), float(keep_brush > 0.5 || keep_grass > 0.5));
	}
}
