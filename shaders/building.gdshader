shader_type spatial;
render_mode cull_back;

// Makes a plain BoxMesh look like a building. Windows are laid out on a grid that the
// Building script fits exactly to the box size, so nothing straddles an edge.
// Floors are counted from world Y (buildings sit on flat ground), columns from the
// box's local axes, so rotated buildings still look right.

// --- Facade ---
uniform vec3 facade_color : source_color = vec3(0.62, 0.60, 0.58);
// Mortar, panel joints, mullions, awnings.
uniform vec3 accent_color : source_color = vec3(0.30, 0.29, 0.28);
// 0 flat, 1 brick, 2 concrete panels, 3 glass curtain (spandrel panels)
uniform int facade_finish = 0;

// --- Windows ---
// 0 punched, 1 ribbon bands, 2 curtain wall grid, 3 tall narrow slots
uniform int window_style = 0;
uniform vec3 window_tint : source_color = vec3(0.35, 0.50, 0.65);
uniform vec3 lit_color : source_color = vec3(1.0, 0.82, 0.50);
// Fraction of windows that are lit (0..1).
uniform float lit_ratio = 0.3;
// How bright lit windows glow.
uniform float lit_strength = 1.2;
// Column spacing for faces whose normal is +-Z (columns run along local X), and +-X.
uniform float window_pitch_x = 2.5;
uniform float window_pitch_z = 2.5;
uniform float floor_height = 3.5;
// World Y where regular floors start. Below it is the storefront (if has_storefront).
uniform float ground_floor_height = 4.5;
uniform bool has_storefront = true;
// Size of this box part (meters). Needed to find the face edges and the roof parapet.
uniform vec3 part_size = vec3(10.0, 20.0, 10.0);
uniform float seed = 0.0;
// 0 by day, 1 at night (set by DayNight). Windows only glow after dark.
global uniform float night_factor;
// Wall texture set (albedo, normal, roughness), sampled in wall space: meters per tile.
uniform sampler2D wall_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wall_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wall_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float wall_texture_scale = 4.0;
uniform bool use_wall_texture = false;
uniform float wall_normal_depth = 0.7;
// Grime: darkening near the ground, streaks running down from window sills (0 clean, 1 dirty).
uniform float weathering = 0.5;

varying vec3 local_pos;
varying vec3 local_normal;
varying float world_y;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float hash31(vec3 p) {
	return hash21(vec2(hash21(p.xy), p.z));
}


void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}


void fragment() {
	vec3 n = normalize(local_normal);
	vec3 albedo = facade_color;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emission = vec3(0.0);
	vec3 wall_nm = vec3(0.5, 0.5, 1.0);
	float wall_nm_weight = 0.0;

	if (abs(n.y) > 0.5) {
		// Roof: gravel grey with a lighter parapet ring around the edge.
		vec2 edge = part_size.xz * 0.5 - abs(local_pos.xz);
		float parapet = 1.0 - step(0.7, min(edge.x, edge.y));
		vec3 gravel = mix(vec3(0.38, 0.37, 0.36), facade_color, 0.25);
		gravel *= 0.92 + 0.16 * hash21(floor(local_pos.xz * 1.5) + seed);
		albedo = mix(gravel, facade_color * 0.9, parapet);
		rough = 0.95;
	} else {
		// Which wall are we on, and how far along it (u) and up it (v)?
		float u;
		float pitch;
		float face_id;
		if (abs(n.x) > 0.5) {
			u = local_pos.z * sign(n.x) + part_size.z * 0.5;
			pitch = window_pitch_z;
			face_id = n.x > 0.0 ? 1.0 : 2.0;
		} else {
			u = local_pos.x * sign(-n.z) + part_size.x * 0.5;
			pitch = window_pitch_x;
			face_id = n.z > 0.0 ? 3.0 : 4.0;
		}
		float v = world_y;
		float col = floor(u / pitch);
		float fu = fract(u / pitch);
		bool storefront = has_storefront && v < ground_floor_height;
		float row;
		float fv;
		if (storefront) {
			row = -1.0;
			fv = v / ground_floor_height;
		} else {
			float vv = v - ground_floor_height;
			row = floor(vv / floor_height);
			fv = fract(vv / floor_height);
		}

		// Window mask for this style.
		bool glass = false;
		bool frame = false;
		if (storefront) {
			glass = fv > 0.12 && fv < 0.78 && abs(fu - 0.5) < 0.44;
			frame = fv >= 0.78 && fv < 0.90; // awning band
		} else if (window_style == 0) {
			glass = abs(fu - 0.5) < 0.27 && abs(fv - 0.52) < 0.25;
		} else if (window_style == 1) {
			glass = abs(fv - 0.55) < 0.27;
			frame = glass && abs(fu - 0.5) > 0.47;
			glass = glass && !frame;
		} else if (window_style == 2) {
			frame = fu < 0.05 || fv < 0.06;
			glass = !frame;
		} else {
			glass = abs(fu - 0.5) < 0.16 && abs(fv - 0.5) < 0.40;
		}

		// Reveal: the wall band right around a punched or slot window (sill, jambs, lintel).
		bool reveal = false;
		if (!storefront && (window_style == 0 || window_style == 3)) {
			float hw = window_style == 0 ? 0.27 : 0.16;
			float hh = window_style == 0 ? 0.25 : 0.40;
			float cy = window_style == 0 ? 0.52 : 0.5;
			reveal = !glass && abs(fu - 0.5) < hw + 0.05 && abs(fv - cy) < hh + 0.05;
		}
		if (glass) {
			float k = hash31(vec3(col, row, face_id * 17.0 + seed));
			bool lit = k < lit_ratio;
			albedo = window_tint * (0.30 + 0.15 * hash31(vec3(row, col, face_id + seed)));
			// Darker toward the frame so the pane reads as set into the wall.
			float du = abs(fu - 0.5);
			float dv = abs(fv - (storefront ? 0.45 : 0.52));
			float inset = smoothstep(0.0, 0.06, max(du - 0.2, dv - 0.18));
			albedo *= mix(1.0, 0.45, inset * (storefront ? 0.5 : 1.0));
			// Fake interior: a soft vertical gradient behind the glass.
			albedo *= 0.85 + 0.3 * fv;
			rough = 0.12;
			metal = 0.6;
			if (lit) {
				float glow = 0.55 + 0.45 * hash31(vec3(col + 3.0, row + 7.0, face_id + seed));
				float on = 0.12 + 0.88 * night_factor;
				albedo = mix(albedo, lit_color, 0.7 * on);
				emission = lit_color * glow * lit_strength * on;
				metal = mix(metal, 0.0, on);
				rough = mix(rough, 0.5, on);
			}
		} else if (frame) {
			albedo = accent_color;
			rough = 0.6;
			metal = 0.2;
		} else if (reveal) {
			albedo = mix(facade_color, accent_color, 0.35) * 0.9;
			rough = 0.8;
		} else {
			// Wall finish.
			vec2 wuv = vec2(u, v) / wall_texture_scale;
			vec3 tex = use_wall_texture ? texture(wall_albedo, wuv).rgb : vec3(1.0);
			float tex_rough = use_wall_texture ? texture(wall_roughness, wuv).r : 1.0;
			if (use_wall_texture) {
				wall_nm = texture(wall_normal, wuv).rgb;
				wall_nm_weight = 1.0;
			}
			if (facade_finish == 1 && use_wall_texture) {
				// Real brick texture, tinted by the facade color.
				albedo = tex * facade_color * 1.35;
				rough = 0.95 * tex_rough;
			} else if (facade_finish == 1) {
				float brick_row = floor(v / 0.25);
				float offset = mod(brick_row, 2.0) * 0.3;
				float bu = fract((u + offset) / 0.6);
				float bv = fract(v / 0.25);
				float mortar = step(bu, 0.06) + step(bv, 0.14);
				float shade = 0.85 + 0.3 * hash21(vec2(floor((u + offset) / 0.6), brick_row) + seed);
				albedo = mix(facade_color * shade, accent_color, clamp(mortar, 0.0, 1.0));
				rough = 0.95;
			} else if (facade_finish == 2) {
				float joint = step(fu, 0.03) + step(fv, 0.04);
				float shade = 0.9 + 0.2 * hash21(vec2(col, row) + seed);
				albedo = mix(facade_color * shade * tex * (use_wall_texture ? 1.3 : 1.0), accent_color, clamp(joint, 0.0, 1.0));
				rough = 0.8 * tex_rough;
			} else if (facade_finish == 3) {
				float joint = step(fu, 0.04) + step(fv, 0.05);
				albedo = mix(facade_color * 0.6 * tex * (use_wall_texture ? 1.3 : 1.0), accent_color, clamp(joint, 0.0, 1.0));
				rough = 0.35;
				metal = 0.35;
				wall_nm_weight *= 0.3;
			} else {
				albedo = facade_color * tex * (use_wall_texture ? 1.3 : 1.0);
				rough = 0.85 * tex_rough;
			}
			// Grime near the ground and streaks below the windows.
			float ground_dirt = 1.0 - smoothstep(0.0, 5.0, v);
			float streak = hash21(vec2(floor(u * 3.0), row + face_id) + seed) * (1.0 - fv);
			float dirt = weathering * (0.45 * ground_dirt + 0.35 * streak * step(0.5, hash21(vec2(col, row + face_id * 3.0) + seed)));
			albedo *= 1.0 - 0.5 * dirt;
			rough = min(1.0, rough + 0.1 * dirt);
		}
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emission;
	NORMAL_MAP = wall_nm;
	NORMAL_MAP_DEPTH = wall_normal_depth * wall_nm_weight;
}
