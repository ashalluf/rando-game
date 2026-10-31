shader_type spatial;
render_mode cull_disabled;

// Everything flat on a freeway (FreewayKit's `paint` mesh): lane paint, Botts' dots and raised
// retroreflective markers, the carpool diamond, expansion joints, scupper grates, and the
// overhead signs' faces, borders, lettering, shields and arrows. What a vertex is rides in its
// colour's alpha (FreewayKit.P_*, alpha * 32), its colour (sRGB) in the rgb. Deck strips carry
// UV = (0..1 across the strip, metres along the route); signs UV = the point on the board
// (0..1). UV2 is the direction (xz) a retroreflector faces - back at the traffic it serves.
//
// Retroreflection is the night look: lane markers, bead-glass paint and sign sheeting send
// headlight back toward the light, so to a driver they light up in a cone ahead and nowhere
// else. The headlights are taken to be at the camera, aimed along its heading (a chase camera or
// the driver's eye), lit by `lamp_factor`; a marker that the cone reaches never draws smaller
// than a pixel or so, so the dashed line of glints runs on up the road.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
// FreewayLook: the expansion joints as dull, dusty steel.
uniform bool joint_steel = false;
global uniform float road_wetness;

// The Botts' dot pattern (FreewayKit.BOTTS_CYCLE): four dots DOT_STEP apart, then a marker.
uniform float botts_cycle = 7.32;
uniform float dot_step = 0.914;
uniform float dot_radius = 0.05;
uniform float marker_at = 4.57;
// Dashed lines (LOD chunks): dash every cycle.
uniform float dash_cycle = 14.63;
uniform float dash_len = 3.66;
// The yellow edge markers' spacing.
uniform float edge_marker_cycle = 14.63;
// How much paint is worn through (0 = new).
uniform float wear = 0.22;
// Headlight glint: energy, the headlights' reach (metres) and half-angle (cosine).
uniform float glint_energy = 9.0;
uniform float glint_reach = 70.0;
uniform float glint_cone = 0.955;
// Sign sheeting: lit by the sign lights below each board at night, plus headlights.
uniform float sign_light = 0.55;
uniform float sign_retro = 1.6;
// Paint's own glass beads (dim, wide).
uniform float paint_retro = 0.6;
// The close-up pass (FreewayCloseup; FREEWAY_CLOSEUP=0 is the A/B): sign boards built of 12 in
// extruded aluminium panels with their seams, clip bolts on the stringers and road grime, the
// raised markers' housings, lenses (red seen from the wrong way) and black adhesive pads, dirt
// rings round the Botts' dots, tyre grime on the paint.
uniform bool closeup = true;
uniform float panel_pitch = 0.305;
uniform float stringer_pitch = 1.22;

varying vec3 obj_pos;


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


void vertex() {
	obj_pos = VERTEX;
}


// How strongly the headlights at the camera light a retroreflector at `wp` facing `face`.
float headlit(vec3 wp, vec2 face, vec3 cam, vec3 fwd) {
	vec3 to_cam = cam - wp;
	float dist = length(to_cam);
	vec2 vh = to_cam.xz / max(length(to_cam.xz), 0.001);
	float facing = length(face) > 0.5 ? dot(normalize(face), vh) : 0.7;
	vec2 fh = fwd.xz / max(length(fwd.xz), 0.001);
	float cone = dot(fh, -vh);
	float reach = 1.0 / (1.0 + pow(dist / glint_reach, 2.0));
	return smoothstep(glint_cone, 1.0, cone) * smoothstep(0.1, 0.6, facing) * reach * smoothstep(1.5, 6.0, dist);
}


void fragment() {
	int kind = int(round(COLOR.a * 32.0));
	vec3 col = cs_srgb_to_linear(COLOR.rgb);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
	float night = clamp(lamp_factor, 0.0, 1.0);
	float lit = headlit(wp, UV2, cam, fwd) * night;
	float along = UV.y;
	float across = UV.x;
	// Metres a pixel covers along the route here.
	float foot = max(fwidth(along), 0.0005);
	vec3 alb = col;
	float rough = 0.6;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	vec3 nrm_w = vec3(0.0, 1.0, 0.0);
	bool dome = false;
	// Worn paint: patches of the line gone to the asphalt, grit in what is left.
	float worn = vnoise(obj_pos.xz * 2.3) * 0.65 + vnoise(obj_pos.xz * 9.0) * 0.35;

	if (kind == 1 || kind == 2) {
		if (kind == 2 && mod(along, dash_cycle) > dash_len) {
			discard;
		}
		// Ragged edges, and holes where it has worn through (only while a hole is over a pixel).
		float edge = abs(across - 0.5) * 2.0;
		if (foot < 0.08 && (worn < wear * 0.9 || edge > 0.9 + 0.1 * vnoise(obj_pos.xz * 31.0))) {
			discard;
		}
		alb = col * mix(0.62, 1.0, smoothstep(wear, wear + 0.35, worn)) * (0.9 + 0.1 * vnoise(obj_pos.xz * 40.0));
		rough = 0.68;
		emit = col * lit * paint_retro;
		if (closeup) {
			// Tyre grime: where wheels cross a line it greys, in smudges a metre or two long.
			float smudge = smoothstep(0.55, 0.85, vnoise(vec2(along * 0.45, across * 2.0)) * 0.7 + vnoise(vec2(along * 3.0, 9.0)) * 0.3);
			alb = mix(alb, alb * 0.45 + vec3(0.02), smudge * 0.55);
		}
	} else if (kind == 3 || kind == 4) {
		// Botts' dots and markers (3), or the yellow edge markers alone (4).
		float x = (across - 0.5) * (kind == 3 ? 0.16 : 0.12);
		float y = mod(along, kind == 3 ? botts_cycle : edge_marker_cycle);
		float mk_at = kind == 3 ? marker_at : edge_marker_cycle * 0.5;
		// The marker: a raised 10 cm square whose faces are retroreflective; never under about
		// a pixel and a half while the headlights reach it, so the line of glints runs on.
		float mh = max(0.05, foot * (lit > 0.01 ? 0.75 : 0.0));
		bool marker = abs(x) < min(mh, 0.06) && abs(y - mk_at) < mh;
		// The black adhesive pad a marker is glued down on, a little proud of it.
		bool pad = closeup && !marker && foot < 0.05 && length(vec2(x, (y - mk_at) * 0.85)) < 0.085;
		bool dot_hit = false;
		vec2 rel = vec2(0.0);
		if (kind == 3 && !marker) {
			float k = clamp(round(y / dot_step), 0.0, 3.0);
			rel = vec2(x, y - k * dot_step);
			// Never under about a pixel across, so a line of dots still reads as one up the road.
			dot_hit = length(rel) < min(max(dot_radius, foot * 0.55), 0.08) && foot < 0.12;
		}
		if (!marker && !dot_hit && !pad) {
			discard;
		}
		if (pad) {
			alb = vec3(0.012, 0.012, 0.013);
			rough = 0.5;
		} else if (marker) {
			alb = col * 0.8;
			rough = 0.3;
			emit = col * lit * glint_energy;
			if (closeup) {
				// The housing: a low dome of white or yellow ABS, the lens faces at its two ends
				// (along the road), tilted 30 degrees; a white marker's back lens is red, so the
				// wrong way glints red.
				vec2 fdir = length(UV2) > 0.5 ? normalize(UV2) : vec2(0.0, 1.0);
				vec2 vh = normalize((cam - wp).xz + vec2(0.0001));
				bool from_behind = dot(fdir, vh) < -0.1;
				float ly = (y - mk_at) / mh;
				float lens = smoothstep(0.55, 0.7, abs(ly));
				bool white = col.r > 0.6 && col.b > 0.6;
				vec3 lens_col = (white && from_behind) ? vec3(0.55, 0.03, 0.02) : col * 0.55;
				alb = mix(alb * (0.92 + 0.08 * (1.0 - abs(ly))), lens_col, lens);
				rough = mix(0.38, 0.08, lens);
				if (white && from_behind) {
					emit = vec3(0.9, 0.02, 0.01) * headlit(wp, -UV2, cam, fwd) * night * glint_energy * 0.7;
				}
				vec3 along_w = vec3(-fdir.x, 0.0, -fdir.y);
				nrm_w = normalize(vec3(0.0, 1.0, 0.0) + along_w * clamp(ly, -1.0, 1.0) * 0.6);
				dome = true;
			}
		} else {
			// A ceramic dome: glossy white, its normal bulging out of the deck.
			alb = vec3(0.80, 0.80, 0.77);
			rough = 0.22;
			vec2 d = rel / max(dot_radius, foot * 0.55);
			vec2 fdir = length(UV2) > 0.5 ? normalize(UV2) : vec2(0.0, 1.0);
			vec3 along_w = vec3(-fdir.x, 0.0, -fdir.y);
			vec3 across_w = vec3(along_w.z, 0.0, -along_w.x);
			nrm_w = normalize(vec3(0.0, 1.0, 0.0) * sqrt(max(1.0 - dot(d, d), 0.05)) + across_w * d.x * 0.9 + along_w * d.y * 0.9);
			dome = true;
			emit = alb * lit * 0.4;
			if (closeup) {
				// Road dirt ground into the dome's foot.
				alb *= 1.0 - smoothstep(0.55, 1.0, length(d)) * 0.45;
			}
		}
	} else if (kind == 5) {
		// Carpool diamond: an elongated diamond outline on a quad (UV 0..1 both ways).
		vec2 q = abs(UV - 0.5) * 2.0;
		float dd = q.x + q.y;
		if (dd > 1.0 || dd < 0.84 || (foot < 0.08 && worn < wear)) {
			discard;
		}
		alb = col * mix(0.65, 1.0, smoothstep(wear, wear + 0.35, worn));
		rough = 0.68;
		emit = col * lit * paint_retro;
	} else if (kind == 6) {
		// Expansion joint: a steel finger plate across the deck (UV.x metres across, UV.y 0..1).
		float tooth = abs(fract(UV.x / 0.14) - 0.5) * 2.0;
		float gap = 1.0 - smoothstep(0.0, 0.06, abs(UV.y - 0.5 - (tooth - 0.5) * 0.5) - 0.03);
		alb = mix(col * (0.85 + 0.3 * vnoise(obj_pos.xz * 7.0)), vec3(0.01), gap);
		alb = mix(alb, vec3(0.18, 0.08, 0.03), smoothstep(0.55, 0.9, vnoise(obj_pos.xz * 3.0)) * 0.5);
		metal = 0.75 * (1.0 - gap);
		rough = 0.45;
		if (joint_steel) {
			// Traffic-polished, dusty steel (FreewayLook): a dull metal reads as the band it is on
			// both renderers; at 0.75 metal the Compatibility renderer drew a black line.
			// The fingers' seam, antialiased: its zig-zag flattens and it fades to its coverage once
			// the band is a few pixels deep (a thin zig-zag aliased into broken dashes).
			float fy = max(fwidth(UV.y), 0.001);
			float zig = (tooth - 0.5) * 0.5 * (1.0 - smoothstep(0.04, 0.12, fy));
			float hw = 0.03;
			float ww = max(hw, fy * 0.75);
			float seam = (1.0 - smoothstep(ww - fy * 0.5, ww + fy * 0.5, abs(UV.y - 0.5 - zig))) * (hw / ww);
			alb = mix(vec3(0.30, 0.29, 0.27) * (0.85 + 0.3 * vnoise(obj_pos.xz * 7.0)), vec3(0.015), seam * 0.85);
			gap = seam;
			metal = 0.35 * (1.0 - gap);
			rough = 0.55;
		}
	} else if (kind == 9) {
		// Scupper grate: cast iron bars over a dark drain.
		float bars = step(0.45, fract(UV.x * 7.0));
		alb = mix(vec3(0.004), col * (0.8 + 0.4 * vnoise(obj_pos.xz * 12.0)), bars);
		alb = mix(alb, vec3(0.16, 0.07, 0.03), bars * smoothstep(0.5, 0.85, vnoise(obj_pos.xz * 6.0)) * 0.6);
		metal = 0.5 * bars;
		rough = 0.55;
	} else if (kind == 8) {
		// Sign sheeting: green, white, black, blue or yellow. Lit from the sign lights under the
		// board (brighter toward its foot) and by headlights.
		alb = col;
		rough = 0.42;
		float wash = sign_light * (0.55 + 0.45 * (1.0 - clamp(UV.y, 0.0, 1.0)));
		float retro = headlit(wp, UV2, cam, fwd) * sign_retro;
		if (closeup) {
			// The board in metres: the board's UV is 0..1, so solve the screen Jacobian for the
			// metres per UV unit both ways.
			vec3 dpx = dFdx(wp);
			vec3 dpy = dFdy(wp);
			vec2 dux = dFdx(UV);
			vec2 duy = dFdy(UV);
			float det = dux.x * duy.y - duy.x * dux.y;
			if (abs(det) > 1e-14) {
				vec3 dpdu = (dpx * duy.y - dpy * dux.y) / det;
				vec3 dpdv = (dpy * dux.x - dpx * duy.x) / det;
				vec2 bm = vec2(length(dpdu), length(dpdv));
				// Round to the centimetre, so the panel grid does not crawl with the derivatives.
				bm = round(bm * 100.0) / 100.0;
				vec2 m = UV * bm;
				float pxm = max(length(dpx), length(dpy));
				// Panel seams: a dark hairline with a bright lip over it.
				float pv = m.y / panel_pitch;
				float sw = 1.0 - smoothstep(0.0, 1.0, pxm / 0.02);
				float sdist = (0.5 - abs(fract(pv) - 0.5)) * panel_pitch;
				float seam = (1.0 - smoothstep(0.003, 0.003 + pxm, sdist)) * sw;
				// The lip: the panel above's edge, just over the seam, catches the light.
				float lip = (1.0 - smoothstep(0.004, 0.012 + pxm, abs(sdist - 0.008))) * sw * (1.0 - step(0.5, fract(pv)));
				alb = alb * (1.0 - seam * 0.6) + lip * 0.04;
				// Clip bolts: two on every panel at every stringer.
				float sx = m.x - stringer_pitch * 0.5;
				vec2 bp = vec2(mod(sx, stringer_pitch) - stringer_pitch * 0.5, (fract(pv) - 0.5) * panel_pitch);
				float bd = length(vec2(bp.x, abs(bp.y) - panel_pitch * 0.3));
				float bolt = (1.0 - smoothstep(0.011, 0.011 + pxm, bd)) * (1.0 - smoothstep(0.004, 0.012, pxm));
				alb = mix(alb, vec3(0.38, 0.38, 0.37), bolt);
				rough = mix(rough, 0.35, bolt);
				// Grime: streaks from the top edge down, a dirty band along the foot, sun fade high.
				float streak = smoothstep(0.55, 0.85, vnoise(vec2(m.x * 2.2, m.y * 0.25))) * smoothstep(0.3, 1.0, UV.y);
				float foot_b = 1.0 - smoothstep(0.0, 0.35, m.y);
				alb = mix(alb, alb * 0.55 + vec3(0.012, 0.011, 0.009), clamp(streak * 0.45 + foot_b * 0.35, 0.0, 0.7));
				alb *= 0.94 + 0.12 * vnoise(m * 1.3);
				// Microprismatic sheeting: retroreflection in fine cells that sparkle.
				float cell = hash12(floor(m / 0.004));
				retro *= mix(1.0, 0.6 + 0.8 * cell, 1.0 - smoothstep(0.002, 0.006, pxm));
			}
		}
		emit = col * night * (wash + retro);
	}

	// Rain: the deck's paint darkens and glosses with the road.
	float wet = clamp(road_wetness, 0.0, 1.0) * step(0.5, abs(nrm_w.y)) * (kind == 8 ? 0.0 : 1.0);
	alb *= mix(1.0, 0.75, wet);
	rough = mix(rough, 0.18, wet * 0.8);

	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
	if (dome) {
		NORMAL = normalize((VIEW_MATRIX * vec4(nrm_w, 0.0)).xyz);
	}
}
