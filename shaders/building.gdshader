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

// --- Base, shaft, crown ---
// Height in meters above base_y of a stone base course. A facade that changes material at the
// bottom storey or two is most of what separates a building from an extruded rectangle, and it
// is the part of the wall the player stands next to. 0 turns it off (Building sets it to 0
// wherever a shopfront already has the ground floor).
uniform float base_height = 0.0;
uniform vec3 base_color : source_color = vec3(0.60, 0.58, 0.54);
// World Y where the crown floors start, and how much lighter or darker they are. Building puts
// its crown band at the same height, so the painted change and the moulding read as one cap.
uniform float crown_start = 100000.0;
uniform float crown_shade = 1.0;

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
// Roof covering: 0 gravel ballast, 1 white membrane (a cool roof, everywhere in California),
// 2 dark bitumen. Flat grey roofs are most of what you see from the air.
uniform int roof_style = 0;
// How many window bays make one shop at street level, per face (x: +X, y: -X, z: +Z, w: -Z).
// Building picks these and places the shop signs in the world from the same numbers, so the
// names line up with the sign bands drawn here.
uniform vec4 shop_span = vec4(3.0, 3.0, 3.0, 3.0);
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
// World Y of the building's base (grime is measured up from here).
uniform float base_y = 0.0;

// What the glass reflects. Not the real environment map: see the note in the glass branch.
uniform vec3 sky_zenith : source_color = vec3(0.26, 0.44, 0.80);
// "Horizon" here is not the sky at the horizon: a pane on a wall reflects whatever is level
// with it, which from the street is the buildings opposite, not bright sky. Setting this to a
// pale sky blue turned every shop window into milk glass.
uniform vec3 sky_horizon : source_color = vec3(0.42, 0.47, 0.55);
uniform vec3 street_reflect : source_color = vec3(0.09, 0.09, 0.10);
// 0 no reflection at all, 1 full. Turned down on spandrel panels.
uniform float reflect_strength = 1.0;
// How bright the room behind the glass is against full daylight outside. Rooms read almost
// black from the street in real life; a room lit to the same level as the wall around it is
// what made every pane look like a beige card taped over the opening.
uniform float interior_exposure = 0.40;

// Fake rooms behind the glass. How deep the virtual room is (meters).
uniform float room_depth = 3.2;
uniform bool interior_enabled = true;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 world_tangent;
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
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_y = wp.y;
	world_pos = wp.xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// The wall's horizontal axis: local Z on the +-X faces, local X on the +-Z faces.
	vec3 t_local = abs(NORMAL.x) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	world_tangent = normalize((MODEL_MATRIX * vec4(t_local, 0.0)).xyz);
}


// Interior mapping: trace the view ray into a box behind the window and return the colour of
// whichever inner surface it reaches. A window shaded this way has real parallax - lean left and
// you see the right-hand wall of the room - which is what stops a tower reading as a painted
// box. `w` is the position across the window in 0..1, `dir` is the view ray in wall space
// (x along the wall, y up, z into the building).
vec3 room_interior(vec2 w, vec3 dir, float wide, float high, float deep, float room_seed, float blind_chance, out float depth_t) {
	vec3 ro = vec3(w.x * wide, w.y * high, 0.0);
	float best = 1e9;
	int surface = 0; // 0 back wall, 1 side wall, 2 floor, 3 ceiling
	if (dir.z > 1e-4) {
		float t = deep / dir.z;
		if (t > 0.0 && t < best) { best = t; surface = 0; }
	}
	if (abs(dir.x) > 1e-4) {
		float t = ((dir.x > 0.0 ? wide : 0.0) - ro.x) / dir.x;
		if (t > 0.0 && t < best) { best = t; surface = 1; }
	}
	if (abs(dir.y) > 1e-4) {
		float t = ((dir.y > 0.0 ? high : 0.0) - ro.y) / dir.y;
		if (t > 0.0 && t < best) { best = t; surface = dir.y > 0.0 ? 3 : 2; }
	}
	best = min(best, 1e8);
	depth_t = clamp(best / max(deep, 0.01), 0.0, 2.0);

	// Each room gets its own paint, and the surfaces differ the way a real room does: the
	// ceiling catches the most daylight, the floor the least.
	float tone = 0.62 + 0.45 * hash21(vec2(room_seed, 3.1));
	// Offices are mostly neutral, but a few rooms are painted; the variety reads at a glance.
	float tinted = step(0.72, hash21(vec2(room_seed, 17.9)));
	vec3 paint = mix(vec3(0.76, 0.74, 0.70), vec3(0.44, 0.47, 0.52), hash21(vec2(room_seed, 7.7)) * 0.7);
	paint = mix(paint, paint * vec3(1.15, 0.92, 0.80), tinted);
	vec3 col = paint * tone;
	if (surface == 0) {
		col *= 0.78;
	} else if (surface == 1) {
		col *= 0.62;
	} else if (surface == 2) {
		col = mix(vec3(0.24, 0.20, 0.17), vec3(0.34, 0.32, 0.30), hash21(vec2(room_seed, 11.3))) * 0.9;
	} else {
		col *= 1.15;
	}
	// Light falls off with how far into the room the ray reached.
	col *= mix(1.0, 0.35, clamp(depth_t, 0.0, 1.0));

	// Blinds, hanging just inside the glass at a height that differs room to room. Nothing says
	// "occupied building" like a facade where every blind is pulled to a different level.
	float drop = hash21(vec2(room_seed, 23.7));
	if (drop > 1.0 - blind_chance) {
		float level = 1.0 - (drop - (1.0 - blind_chance)) * 1.25;
		if (w.y > level) {
			vec3 blind = mix(vec3(0.80, 0.78, 0.72), vec3(0.55, 0.53, 0.50), hash21(vec2(room_seed, 31.1)));
			// Slats.
			blind *= 0.88 + 0.12 * step(0.5, fract((w.y - level) * 26.0));
			col = blind;
			depth_t = 0.0;
		}
	}
	return col;
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
		// Roof, with a lighter parapet ring around the edge.
		vec2 edge = part_size.xz * 0.5 - abs(local_pos.xz);
		float parapet = 1.0 - step(0.7, min(edge.x, edge.y));
		vec3 surface;
		if (roof_style == 1) {
			// White single-ply membrane, rolled in strips and welded at the seams, weathered
			// grey where water sits.
			surface = vec3(0.78, 0.78, 0.76);
			float strip = fract(local_pos.x * 0.5 + hash21(vec2(seed, 2.0)));
			surface *= 1.0 - 0.10 * smoothstep(0.06, 0.0, min(strip, 1.0 - strip));
			float pond = hash21(floor(local_pos.xz * 0.35) + seed);
			surface *= 0.86 + 0.18 * pond;
			rough = 0.82;
		} else if (roof_style == 2) {
			// Bitumen: dark, patched, and shinier where it has been resealed.
			surface = vec3(0.14, 0.135, 0.13);
			float patch = hash21(floor(local_pos.xz * 0.6) + seed);
			surface *= 0.8 + 0.5 * patch;
			rough = mix(0.55, 0.95, patch);
		} else {
			vec3 gravel = mix(vec3(0.38, 0.37, 0.36), facade_color, 0.25);
			gravel *= 0.92 + 0.16 * hash21(floor(local_pos.xz * 1.5) + seed);
			surface = gravel;
			rough = 0.95;
		}
		albedo = mix(surface, facade_color * 0.9, parapet);
	} else {
		// Which wall are we on, and how far along it (u) and up it (v)?
		float u;
		float pitch;
		float face_id;
		// A cut corner. Its normal points diagonally, so neither axis branch below can measure
		// along it, and a window grid carried across it would leave half a window either side.
		// It is built as a solid corner pier instead, which is what a chamfered corner usually
		// is, so all it needs is somewhere sane to sample the wall texture from.
		bool chamfer = abs(n.x) > 0.35 && abs(n.z) > 0.35;
		if (chamfer) {
			vec2 along = normalize(vec2(-n.z, n.x));
			u = dot(local_pos.xz, along) + 0.5 * (part_size.x + part_size.z);
			pitch = window_pitch_x;
			face_id = 5.0;
		} else if (abs(n.x) > 0.5) {
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
		// Street level is a row of separate businesses, not one continuous glass ribbon. A run
		// of two to four bays is one shop, and it gets its own sign band, its own bulkhead
		// colour and one bay turned into a door.
		bool fascia = false;
		bool bulkhead = false;
		bool door_bay = false;
		float shop_seed = 0.0;
		// Window opening in cell units (centre and half size), kept so the fake interior knows
		// where the hole in the wall is.
		vec2 win_c = vec2(0.5, 0.52);
		vec2 win_h = vec2(0.27, 0.25);
		if (chamfer) {
			// Solid pier: no glass, no shopfront. Falls through to the wall finish below.
		} else if (storefront) {
			float span = max(shop_span[int(face_id) - 1], 1.0);
			float shop_id = floor(col / span);
			shop_seed = hash21(vec2(shop_id * 1.7, face_id * 13.0) + seed);
			door_bay = abs(col - (shop_id * span + floor(shop_seed * span))) < 0.5;
			// The door runs to the pavement; a display window sits on a bulkhead.
			float low = door_bay ? 0.05 : 0.15;
			glass = fv > low && fv < 0.74 && abs(fu - 0.5) < 0.44;
			fascia = fv >= 0.76 && fv < 0.93;
			bulkhead = fv < low && abs(fu - 0.5) < 0.46;
			win_c = vec2(0.5, (low + 0.74) * 0.5);
			win_h = vec2(0.44, (0.74 - low) * 0.5);
		} else if (window_style == 0) {
			glass = abs(fu - 0.5) < 0.27 && abs(fv - 0.52) < 0.25;
		} else if (window_style == 1) {
			glass = abs(fv - 0.55) < 0.27;
			frame = glass && abs(fu - 0.5) > 0.47;
			glass = glass && !frame;
			win_c = vec2(0.5, 0.55);
			win_h = vec2(0.47, 0.27);
		} else if (window_style == 2) {
			frame = fu < 0.05 || fv < 0.06;
			glass = !frame;
			win_c = vec2(0.525, 0.53);
			win_h = vec2(0.475, 0.47);
		} else {
			glass = abs(fu - 0.5) < 0.16 && abs(fv - 0.5) < 0.40;
			win_c = vec2(0.5, 0.5);
			win_h = vec2(0.16, 0.40);
		}

		// Reveal: the wall band right around a punched or slot window (sill, jambs, lintel).
		bool reveal = false;
		if (!chamfer && !storefront && (window_style == 0 || window_style == 3)) {
			float hw = window_style == 0 ? 0.27 : 0.16;
			float hh = window_style == 0 ? 0.25 : 0.40;
			float cy = window_style == 0 ? 0.52 : 0.5;
			reveal = !glass && abs(fu - 0.5) < hw + 0.05 && abs(fv - cy) < hh + 0.05;
		}
		if (glass) {
			float k = hash31(vec3(col, row, face_id * 17.0 + seed));
			bool lit = k < lit_ratio;
			float room_seed = hash31(vec3(col, row, face_id * 17.0 + seed)) * 97.0;
			albedo = window_tint * (0.30 + 0.15 * hash31(vec3(row, col, face_id + seed)));
			vec3 to_frag = normalize(world_pos - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);

			if (interior_enabled) {
				// Where we are inside the opening, and the view ray in wall space.
				vec2 w = clamp((vec2(fu, fv) - (win_c - win_h)) / (2.0 * win_h), vec2(0.0), vec2(1.0));
				vec3 up = vec3(0.0, 1.0, 0.0);
				vec3 tan_dir = normalize(world_tangent - world_normal * dot(world_tangent, world_normal));
				vec3 ray = vec3(dot(to_frag, tan_dir), dot(to_frag, up), -dot(to_frag, world_normal));
				float wide = max(2.0 * win_h.x * pitch, 0.2);
				float high = max(2.0 * win_h.y * (storefront ? ground_floor_height : floor_height), 0.2);
				float depth_t = 0.0;
				// Offices are full of blinds; a shop window with a blind in it is not a shop.
				vec3 room = room_interior(w, ray, wide, high, room_depth, room_seed, storefront ? 0.10 : 0.72, depth_t);
				// Daylight outside is many stops brighter than anything indoors, so the room
				// arrives dark; at night an unlit room is darker still.
				// A shop is lit inside even in daylight; an office floor is not.
				float expose = storefront ? interior_exposure * 3.2 : interior_exposure;
				// At night an unlit room is dark, full stop. At 0.45 the pale blinds picked up
				// the blue night ambient and every window on the block read as a lit panel.
				room *= expose * (1.0 - 0.88 * night_factor);
				if (storefront) {
					room *= vec3(1.10, 1.03, 0.92);
				}
				// The glass still carries its own tint; the room shows through it.
				albedo = mix(room, albedo * 0.5, 0.28);
			} else {
				// Fallback: a soft vertical gradient behind the glass.
				albedo *= 0.85 + 0.3 * fv;
			}
			// Darker toward the frame so the pane reads as set into the wall. Measured against
			// the opening THIS style declared, not against the punched window's constants:
			// 0.2 / 0.18 is exactly win_h - 0.07 for style 0 and for nothing else, so on a
			// curtain wall (win_h 0.475 / 0.47) it darkened 86 % of the pane by 45 % and every
			// bay read as a dark rectangle with a lighter card floating inside it.
			float du = abs(fu - win_c.x);
			float dv = abs(fv - win_c.y);
			float inset = smoothstep(0.0, 0.06, max(du - (win_h.x - 0.07), dv - (win_h.y - 0.07)));
			albedo *= mix(1.0, 0.45, inset * (storefront ? 0.5 : 1.0));

			// Glass reflects, and that is most of what a window looks like from outside. In any
			// photograph the panes are not beige rectangles: above the horizon they mirror the
			// sky, below it the dark street, and which one you get swings with the angle you
			// are standing at, so a facade is never two windows the same. Computed here from
			// the reflected ray rather than by raising METALLIC, because a metallic pane picks
			// up the real environment map and whole curtain-wall towers turn into
			// see-through cages.
			vec3 refl = reflect(to_frag, world_normal);
			vec3 sky_ref = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.55, refl.y));
			sky_ref = mix(street_reflect, sky_ref, smoothstep(-0.22, 0.10, refl.y));
			// Schlick: nearly transparent head on, a mirror at a glancing angle.
			float fres = pow(1.0 - clamp(-dot(to_frag, world_normal), 0.0, 1.0), 4.0);
			float mirror = mix(0.26, 0.90, fres) * reflect_strength * (1.0 - 0.85 * night_factor);
			// A lit shop interior competes with the reflection; an empty office does not.
			if (storefront) {
				mirror *= 0.66;
			}
			albedo = mix(albedo, sky_ref, mirror);

			// Tinted glass, not a mirror: with more metal the panes reflect pure sky and whole
			// curtain-wall towers read as see-through cages from a distance.
			rough = 0.32;
			metal = 0.2;
			if (storefront) {
				// Anodised shopfront framing: jambs, a centre mullion, the transom above the
				// display, and a kick plate at the bottom of the door. A shop window with no
				// framing in it is the tell that a street was drawn rather than built.
				float mx = abs(fu - 0.5);
				float bars = step(mx, 0.028) + step(0.405, mx);
				bars += step(0.655, fv) * step(fv, 0.705);
				if (door_bay) {
					bars += step(fv, 0.13);
					bars += step(0.40, fv) * step(fv, 0.425);   // push bar
				}
				bars = clamp(bars, 0.0, 1.0);
				vec3 mullion = mix(vec3(0.11, 0.11, 0.12), vec3(0.55, 0.56, 0.58), step(0.6, shop_seed));
				albedo = mix(albedo, mullion, bars);
				rough = mix(rough, 0.42, bars);
				metal = mix(metal, 0.65, bars);
			}
			if (lit) {
				float glow = 0.55 + 0.45 * hash31(vec3(col + 3.0, row + 7.0, face_id + seed));
				// No daytime floor. It used to be 0.12 + 0.88 * night_factor, so at ten in the
				// morning every window the lit roll picked still carried a warm emission and an
				// 8 % pull toward lit_color - and lit_ratio runs to half the bays, so a whole
				// downtown facade read as a random checkerboard of gold and black rectangles
				// with none of the interior mapping or the sky reflection visible through it.
				// A real office window shows nothing from the street in daylight.
				float on = night_factor;
				albedo = mix(albedo, lit_color, 0.7 * on);
				emission = lit_color * glow * lit_strength * on;
				metal = mix(metal, 0.0, on);
				rough = mix(rough, 0.5, on);
			}
		} else if (fascia) {
			// Sign band. Each shop paints it its own colour, which is what makes a block read
			// as a row of businesses rather than one long building with a stripe on it.
			vec3 sign_hue = mix(vec3(0.16, 0.18, 0.22), vec3(0.42, 0.20, 0.16), hash21(vec2(shop_seed, 5.3)));
			sign_hue = mix(sign_hue, vec3(0.18, 0.30, 0.26), step(0.66, hash21(vec2(shop_seed, 9.1))));
			sign_hue = mix(sign_hue, vec3(0.22, 0.20, 0.26), step(0.86, hash21(vec2(shop_seed, 2.4))));
			albedo = sign_hue;
			// A darker lip top and bottom so the band reads as a board fixed to the wall.
			float lip = step(fv, 0.785) + step(0.918, fv);
			albedo *= mix(1.0, 0.55, clamp(lip, 0.0, 1.0));
			rough = 0.55;
			metal = 0.05;
		} else if (bulkhead) {
			// The panelled base under a display window: stall risers are always a different
			// material from the wall, usually tile or painted board.
			vec3 base_col = mix(vec3(0.20, 0.19, 0.18), vec3(0.42, 0.34, 0.28), hash21(vec2(shop_seed, 13.7)));
			base_col = mix(base_col, vec3(0.30, 0.33, 0.36), step(0.7, hash21(vec2(shop_seed, 19.3))));
			// Two recessed panels per bay.
			float panel = step(0.06, abs(fract(fu * 2.0) - 0.5) * 2.0);
			albedo = base_col * mix(0.72, 1.0, panel);
			rough = 0.6;
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
			// --- Base, shaft, crown ----------------------------------------------------
			// The bottom storeys in a heavier material with deep horizontal joints, and a
			// shade change over the top ones. Both go in before the grime, so dirt still runs
			// down over the stone the way it does over the wall above it.
			float base_up = v - base_y;
			if (base_height > 0.01 && base_up < base_height) {
				float course = fract(base_up / 0.92);
				float block = fract((u + floor(base_up / 0.92) * 0.46) / 1.84);
				float joint = clamp(step(course, 0.05) + step(block, 0.018), 0.0, 1.0);
				vec3 stone = base_color * (0.90 + 0.18 * hash21(vec2(floor(base_up / 0.92), floor(u / 1.84)) + seed));
				albedo = mix(stone, stone * 0.55, joint);
				rough = 0.9;
				metal = 0.0;
				wall_nm_weight *= 0.4;
			}
			albedo *= mix(1.0, crown_shade, step(crown_start, v));

			// --- Weathering ------------------------------------------------------------
			// Grime is most of what separates a rendered box from a photographed building.
			// Rain washes dirt off every sill and draws it down the wall in fine vertical
			// streaks that run past the floor below, and soot collects at street level.
			// The old version banded the streaks into hard 33 cm blocks that reset at every
			// floor line, which read as a pattern rather than as dirt.
			float ground_dirt = 1.0 - smoothstep(0.0, 6.5, v - base_y);
			ground_dirt *= 0.65 + 0.35 * hash21(vec2(floor(u * 1.7), face_id) + seed);

			// Metres below the nearest sill above this point. Measured on absolute height, so a
			// streak keeps running across the floor line instead of restarting at it.
			float sill_y = ground_floor_height + floor((v - ground_floor_height) / floor_height) * floor_height + 0.22 * floor_height;
			float below = v < sill_y ? sill_y - v : sill_y + floor_height - v;
			float run = 1.0 - smoothstep(0.0, 2.6, below);
			run *= smoothstep(0.0, 0.12, below);   // the sill itself stays clean

			// Two octaves of narrow vertical strips: ~8 cm and ~2.5 cm, so the streaking has
			// fine structure instead of one solid smear.
			float fine = hash21(vec2(floor(u * 12.0), face_id * 5.0) + seed);
			fine *= 0.45 + 0.55 * hash21(vec2(floor(u * 40.0), face_id * 11.0) + seed * 3.0);
			// Dirt leaves a sill under the window, not across the whole bay.
			float across = 1.0 - smoothstep(0.22, 0.44, abs(fu - 0.5));
			// Not every window drips: an empty one breaks the rhythm.
			float drips = step(0.35, hash21(vec2(col, row + face_id * 3.0) + seed));
			float streak = run * across * drips * fine;

			float dirt = weathering * clamp(0.55 * ground_dirt + 0.75 * streak, 0.0, 1.0);
			// Grime is a warm grey-brown, so it cools and desaturates the wall rather than
			// just dimming it.
			albedo = mix(albedo, albedo * vec3(0.46, 0.44, 0.42), dirt);
			rough = min(1.0, rough + 0.18 * dirt);
		}
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	// Tamed dielectric reflection so tall facades do not mirror the sky at grazing angles.
	SPECULAR = 0.25;
	EMISSION = emission;
	NORMAL_MAP = wall_nm;
	NORMAL_MAP_DEPTH = wall_normal_depth * wall_nm_weight;
}
