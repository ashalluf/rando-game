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
	col = mix(col, native_color * (0.78 + 0.44 * mid), nativ);
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
		float scar = step(0.93, hash12(floor(wp * 3.0))) * smoothstep(-0.5, -3.0, tee_d);
		tc = mix(tc, soil_color * 1.2, scar * 0.8);
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
	col *= 1.0 + stripe_amount * stripe_k * sheen;
	col *= detail * 0.55 + 0.45;

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
}
