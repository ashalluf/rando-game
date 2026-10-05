// Building damage (scripts/world/building_damage.gd): broken windows, blast holes and soot on
// shaders/building.gdshader's walls, from a short list of points the building was hit at.
//
// `damage[i]` is one record: xyz a point in the wall mesh's own space (the building's local
// space, or a tower's), w = kind * 100 + radius. Kinds (BuildingDamage.K_*):
//   1 CRACK   a round in a pane: the pane holding the point is crazed, cracks out of the point
//   2 SHATTER the pane holding the point is gone (teeth of glass left in the frame)
//   3 BLAST   every pane whose centre is within the radius is gone, within 1.8x crazed; soot
//   4 HOLE    a hole punched through the wall round the point, of the radius: the burnt room
//             behind it is traced like the windows' rooms, soot round it and up over it
//   5 POCK    a round's scar in stone, render or brick: a dark pit in a ring of chipped,
//             paler material (the decal on Forward+ fades; this stays, and the web draws it)
// `damage_count` 0 (every building nobody has shot) costs one branch. Nothing here is
// per-instance: a building's facade material is its own (Building._part_material()), and a
// tower's damaged copy gets its own overrides (BuildingDamage), so the shared ones stay clean.

uniform vec4 damage[32];
uniform int damage_count = 0;

// The jagged outline of a hole: radius at angle `a` round its centre. BuildingDamage.hole_radius()
// is this line for line (the rim mesh is laid round it).
float dmg_hole_radius(float r, float a, float s) {
	return r * (0.80 + 0.12 * sin(3.0 * a + s) + 0.07 * sin(7.0 * a + 2.3 * s) + 0.045 * sin(13.0 * a + 4.1 * s));
}

// Smooth value noise, 0..1 (soot edges).
float dmg_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A record's own seed, from where it is (BuildingDamage.record_seed()).
float dmg_seed(vec3 p) {
	return mod(p.x * 1.37 + p.y * 2.11 + p.z * 0.73, 6.2832);
}

// The worst any record does to the pane centred on `pc` (model space), half size `hs` (metres
// along `mu` and up), on the wall facing `mn`: 0 whole, 1 crazed, 2 gone. `impact` comes back as
// where the cracks start, in metres from the pane's centre; `seed_out` the record's seed.
float dmg_pane_state(vec3 pc, vec3 mu, vec3 mn, vec2 hs, out vec2 impact, out float seed_out) {
	float state = 0.0;
	impact = vec2(0.0);
	seed_out = 0.0;
	for (int i = 0; i < damage_count; i++) {
		vec4 e = damage[i];
		float kind = floor(e.w / 100.0 + 0.001);
		float r = e.w - kind * 100.0;
		vec3 d = e.xyz - pc;
		vec2 q = vec2(dot(d, mu), d.y);
		float s = 0.0;
		if (kind < 2.5) {
			if (abs(dot(d, mn)) < 0.6 && abs(q.x) < hs.x + 0.12 && abs(q.y) < hs.y + 0.12) {
				s = kind;
			}
		} else if (kind < 3.5) {
			float dist = length(d);
			// Only the panes on the blast's side of their wall.
			s = dot(d, mn) < -0.3 ? 0.0 : (dist < r ? 2.0 : (dist < r * 1.8 ? 1.0 : 0.0));
		}
		if (s > state) {
			state = s;
			impact = clamp(q, -hs, hs);
			seed_out = dmg_seed(e.xyz);
		}
	}
	return state;
}

// Whether the wall point `mp` is inside a hole, and the soot on it. `hole` comes back as (x along
// mu, y up) from the hole's centre in .xy, its radius in .z and its seed in .w.
bool dmg_wall(vec3 mp, vec3 mu, vec3 mn, out vec4 hole, out float soot, out vec2 pock) {
	soot = 0.0;
	pock = vec2(0.0);
	hole = vec4(0.0);
	bool inside = false;
	for (int i = 0; i < damage_count; i++) {
		vec4 e = damage[i];
		float kind = floor(e.w / 100.0 + 0.001);
		float r = e.w - kind * 100.0;
		vec3 d = mp - e.xyz;
		if (kind > 4.5) {
			if (abs(dot(d, mn)) > 0.3 || dot(d, d) > r * r * 4.0) {
				continue;
			}
			vec2 q = vec2(dot(d, mu), d.y);
			float s = dmg_seed(e.xyz);
			float jr = r * (0.75 + 0.25 * sin(5.0 * atan(q.y, q.x) + s));
			float rho = length(q);
			// The pit, and the spalled ring round it where the face came off.
			pock.x = max(pock.x, 1.0 - smoothstep(jr * 0.30, jr * 0.45, rho));
			pock.y = max(pock.y, (1.0 - smoothstep(jr * 0.8, jr, rho)) * step(jr * 0.3, rho));
		} else if (kind > 3.5) {
			if (abs(dot(d, mn)) > 0.8) {
				continue;
			}
			vec2 q = vec2(dot(d, mu), d.y);
			float s = dmg_seed(e.xyz);
			float a = atan(q.y, q.x);
			float jr = dmg_hole_radius(r, a, s);
			float rho = length(q);
			if (rho < jr) {
				inside = true;
				hole = vec4(q, r, s);
			}
			// Soot: a burnt ring, carried up the wall over the hole by the smoke.
			vec2 qs = vec2(q.x / (1.0 + 0.18 * max(q.y, 0.0)), q.y > 0.0 ? q.y * 0.42 : q.y * 1.1);
			float br = length(qs) / max(jr, 0.05);
			float n = dmg_noise(q * 2.1 + s) * 0.6 + dmg_noise(q * 6.3 + s * 2.0) * 0.4;
			soot = max(soot, (1.0 - smoothstep(1.0, 2.7 + 0.8 * n, br)) * (0.75 + 0.25 * n));
		} else if (kind > 2.5) {
			float dist = length(d);
			float n = dmg_noise(vec2(dot(d, mu), d.y) * 1.7 + 4.0);
			soot = max(soot, pow(clamp(1.0 - dist / (r * 0.75), 0.0, 1.0), 1.4) * (0.55 + 0.35 * n));
		}
	}
	return inside;
}

// The cracks in a crazed pane at `p` (metres from its centre): radial cracks out of the impact,
// rings of a spider web round it, and on tempered glass a dice net over the whole pane. 0..1.
float dmg_cracks(vec2 p, vec2 c, vec2 hs, float s, float px, bool tempered) {
	vec2 d = p - c;
	float r = length(d) + 1e-4;
	float ang = atan(d.y, d.x);
	float w = 0.0018 + px * 0.6;
	// Radial cracks: thirteen sectors, each wandering a little and of its own length.
	float a = ang / 6.2832 * 13.0 + s;
	float k = floor(a);
	float wav = 0.12 * sin(r * 8.0 + k * 3.1) + 0.06 * sin(r * 23.0 + k);
	float da = abs(fract(a + wav) - 0.5) * (6.2832 / 13.0) * r;
	float len = 0.25 + 1.4 * hash21(vec2(k, s * 3.0));
	float radial = (1.0 - smoothstep(w * 0.5, w, da)) * (1.0 - smoothstep(len * 0.8, len, r));
	// Rings: a polygon per ring, its radius stepped sector by sector.
	float ring = 0.0;
	for (int j = 0; j < 4; j++) {
		float rj = 0.05 * pow(float(j) + 1.0, 1.55) * (0.8 + 0.4 * hash21(vec2(k, float(j) + s)));
		float on = step(0.3, hash21(vec2(k + 7.0, float(j) * 3.0 + s)));
		ring = max(ring, on * (1.0 - smoothstep(w * 0.5, w, abs(r - rj))));
	}
	// The crushed spot where the round went through.
	float crush = 1.0 - smoothstep(0.012, 0.035, r);
	float net = 0.0;
	if (tempered) {
		// Tempered glass crazes all over into little cubes: a jittered cell net.
		vec2 g = p / 0.032;
		vec2 gi = floor(g);
		float best = 9.0;
		float second = 9.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 o = vec2(float(x), float(y));
				vec2 cp = o + vec2(hash21(gi + o + s), hash21(gi + o + s + 17.0));
				float dd = length(g - gi - cp);
				if (dd < best) {
					second = best;
					best = dd;
				} else if (dd < second) {
					second = dd;
				}
			}
		}
		float edge = (second - best) * 0.032;
		net = 1.0 - smoothstep(w * 0.35, w * 0.7, edge);
		// Finer than a pixel the net is a frosting.
		net = mix(net, 0.32, smoothstep(0.004, 0.012, px));
		net *= 0.55 + 0.45 * (1.0 - smoothstep(0.0, 1.6, r));
	}
	float fine = 1.0 - smoothstep(0.006, 0.03, px);
	return clamp(max(max(radial, ring) * mix(0.5, 1.0, fine), max(crush, net)), 0.0, 1.0);
}

// Whether a gone pane's point `p` is still a tooth of glass left in the frame.
bool dmg_teeth(vec2 p, vec2 hs, float s) {
	float ed = min(hs.x - abs(p.x), hs.y - abs(p.y));
	float along = abs(p.x) > hs.x - 0.15 ? p.y * 2.3 + sign(p.x) * 5.0 : p.x * 2.3 + sign(p.y) * 11.0;
	float n = hash21(vec2(floor(along * 3.0), s)) * 0.65 + hash21(vec2(floor(along * 9.0), s + 3.0)) * 0.35;
	float tooth = 0.015 + 0.17 * pow(n, 2.2);
	return ed < tooth;
}

// The room behind a hole, traced from the hole's face along `ray` (x along the wall, y up, z into
// the building): first the broken edge through the wall's thickness, then a burnt-out room. The
// colour comes back as `alb` (lit by the renderer, kept small) and `emit` (the day falling in
// through the hole, and embers at night).
void dmg_hole_room(vec4 hole, vec3 ray, int finish, vec3 wall_col, float px, float day, float sky_now,
		out vec3 alb, out vec3 emit, out float rough) {
	vec2 q = hole.xy;
	float r = hole.z;
	float s = hole.w;
	vec3 o = vec3(q, 0.0);
	vec3 rd = vec3(ray.xy, max(ray.z, 0.02));
	// The broken edge through the wall: a ray that leaves the hole's outline within the wall's
	// thickness meets the break.
	float thick = 0.32;
	float tt = -1.0;
	for (int i = 1; i <= 4; i++) {
		float z = thick * float(i) / 4.0;
		vec3 pz = o + rd * (z / rd.z);
		float a = atan(pz.y, pz.x);
		// Taper: the break opens a little as it goes in (spalling on the outside face).
		if (length(pz.xy) > dmg_hole_radius(r, a, s) * (1.0 - 0.10 * float(i) / 4.0)) {
			tt = z;
			break;
		}
	}
	if (tt > 0.0) {
		vec3 pz = o + rd * (tt / rd.z);
		vec3 core;
		if (finish == 1) {
			// Brick: courses of broken brick and mortar through the wall.
			float row = floor(pz.y / 0.075);
			float bu = fract((pz.x + mod(row, 2.0) * 0.11 + tt) / 0.22);
			float mortar = step(fract(pz.y / 0.075), 0.16) + step(bu, 0.07);
			core = mix(vec3(0.36, 0.15, 0.10) * (0.8 + 0.4 * hash21(vec2(row, floor(pz.x / 0.22)) + s)), vec3(0.50, 0.48, 0.44), clamp(mortar, 0.0, 1.0));
		} else if (finish == 0) {
			// Render over block: a pale skin, then grey block.
			core = mix(wall_col * 0.95, vec3(0.42, 0.41, 0.39), step(0.025, tt));
		} else {
			core = vec3(0.50, 0.49, 0.47);
		}
		float grit = hash21(floor(pz.xy * 40.0) + floor(tt * 40.0) + s);
		core *= 0.75 + 0.35 * grit;
		// Soot on the break's outer lip.
		core *= mix(0.35, 1.0, smoothstep(0.0, thick, tt));
		alb = core * 0.6;
		emit = core * (0.10 + 0.45 * day) * sky_now * mix(1.0, 0.55, tt / thick);
		rough = 0.95;
		return;
	}
	// The room: floor a little under the hole's foot, ceiling over its head, 5 m deep.
	float floor_y = -0.85 * r;
	float ceil_y = max(0.95 * r, floor_y + 2.9);
	float half_w = max(2.3 * r, 3.0);
	float deep = 5.0;
	vec3 p0 = o + rd * (thick / rd.z);
	float t = (deep - p0.z) / rd.z;
	int face = 0;
	if (rd.y < 0.0) {
		float tf = (floor_y - p0.y) / rd.y;
		if (tf < t) { t = tf; face = 1; }
	} else if (rd.y > 0.0) {
		float tc = (ceil_y - p0.y) / rd.y;
		if (tc < t) { t = tc; face = 2; }
	}
	if (rd.x < 0.0) {
		float tl = (-half_w - p0.x) / rd.x;
		if (tl < t) { t = tl; face = 3; }
	} else if (rd.x > 0.0) {
		float tr = (half_w - p0.x) / rd.x;
		if (tr < t) { t = tr; face = 3; }
	}
	vec3 h = p0 + rd * t;
	vec3 col;
	if (face == 1) {
		// Rubble over a burnt floor: broken blocks, ash, a scorched patch under the hole.
		float chunk = smoothstep(0.35, 0.75, dmg_noise(h.xz * 5.0 + s)) * (0.6 + 0.4 * dmg_noise(h.xz * 17.0 + s));
		col = mix(vec3(0.07, 0.065, 0.06), vec3(0.44, 0.41, 0.37), chunk);
		float pile = 1.0 - smoothstep(0.0, 2.2 * r, length(vec2(h.x, h.z - 0.8)));
		col = mix(col * 0.6, col * vec3(1.15, 1.05, 0.95), pile);
	} else if (face == 2) {
		// The slab over it, black with soot near the hole, a broken light hanging.
		col = vec3(0.30, 0.29, 0.28) * mix(0.15, 1.0, smoothstep(0.5, 4.0, h.z));
	} else {
		// Plaster walls, scorched toward the hole and up, a doorway dark at the back.
		// The room's own paint (a few office and flat colours), stained.
		float pick = hash21(vec2(s, 7.0));
		vec3 paint = pick < 0.4 ? vec3(0.62, 0.58, 0.50) : (pick < 0.7 ? vec3(0.50, 0.56, 0.52) : (pick < 0.85 ? vec3(0.48, 0.52, 0.60) : vec3(0.64, 0.50, 0.42)));
		col = paint * (0.85 + 0.2 * dmg_noise(h.xy * 1.3 + s));
		float scorch = (1.0 - smoothstep(0.0, 3.5, h.z)) * 0.7 + smoothstep(floor_y, ceil_y, h.y) * 0.35;
		col *= 1.0 - 0.75 * clamp(scorch, 0.0, 1.0);
		if (face == 0 && abs(h.x - (hash21(vec2(s, 2.0)) - 0.5) * half_w) < 0.5 && h.y < floor_y + 2.1) {
			col *= 0.12;
		}
	}
	// Daylight comes in through the hole and falls off into the room.
	float depth01 = clamp(h.z / deep, 0.0, 1.0);
	float light = mix(0.55, 0.10, depth01) * (face == 1 ? 1.25 : 1.0);
	alb = col * 0.22;
	emit = col * light * day * sky_now * 1.5;
	// Embers glow in the rubble after dark (and faintly by day), breathing.
	if (face == 1) {
		vec2 g = floor(h.xz / 0.18);
		float ember = step(0.93, hash21(g + s * 1.7)) * (0.6 + 0.4 * sin(TIME * (1.3 + hash21(g)) + hash21(g + 2.0) * 6.0));
		emit += vec3(1.0, 0.32, 0.06) * ember * mix(0.4, 1.4, 1.0 - day) * (1.0 - smoothstep(1.0, 4.0, h.z));
	}
	rough = 0.95;
}
