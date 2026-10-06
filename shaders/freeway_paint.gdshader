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
	} else if (kind == 3 || kind == 4) {
		// Botts' dots and markers (3), or the yellow edge markers alone (4).
		float x = (across - 0.5) * (kind == 3 ? 0.16 : 0.12);
		float y = mod(along, kind == 3 ? botts_cycle : edge_marker_cycle);
		float mk_at = kind == 3 ? marker_at : edge_marker_cycle * 0.5;
		// The marker: a raised 10 cm square whose faces are retroreflective; never under about
		// a pixel and a half while the headlights reach it, so the line of glints runs on.
		float mh = max(0.05, foot * (lit > 0.01 ? 0.75 : 0.0));
		bool marker = abs(x) < min(mh, 0.06) && abs(y - mk_at) < mh;
		bool dot_hit = false;
		vec2 rel = vec2(0.0);
		if (kind == 3 && !marker) {
			float k = clamp(round(y / dot_step), 0.0, 3.0);
			rel = vec2(x, y - k * dot_step);
			// Never under about a pixel across, so a line of dots still reads as one up the road.
			dot_hit = length(rel) < min(max(dot_radius, foot * 0.55), 0.08) && foot < 0.12;
		}
		if (!marker && !dot_hit) {
			discard;
		}
		if (marker) {
			alb = col * 0.8;
			rough = 0.3;
			emit = col * lit * glint_energy;
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
