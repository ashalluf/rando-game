class_name CivicKit
extends RefCounted
## The civic buildings' geometry (CivicBuildings places them): five kinds built in code at real
## size in the site's frame (CivicGeo: u along the street, v in from it), one mesh a building with
## a surface per material, its collision, lettering, flags, lamps and night light, and what the
## chunk adds round it (trees, bench seats, people rings, parked cars). layout() and masses() are
## PURE (the far tiers and the checks ask them); build() is FULL detail only.

const WALL_H_SPANISH := 6.4
const PO_FLOOR := 0.48
## The mail truck (CivicKit.mail_truck()): its footprint for layouts (width, height, length; m),
## and the invented livery: warm white over a deep teal belt band.
const TRUCK := Vector3(2.0, 2.6, 5.4)
const TRUCK_WHITE := Color(0.93, 0.92, 0.88)
const TRUCK_TEAL := Color(0.02, 0.36, 0.40)
const TRUCK_RANGE := 220.0
const FLAG_SIZE := Vector2(1.83, 0.96)

const STUCCO_WHITE := Color(0.93, 0.90, 0.84)
const STUCCO_TINTS := [Color(1.0, 0.98, 0.93), Color(1.0, 0.95, 0.85), Color(0.98, 0.94, 0.88), Color(0.97, 0.92, 0.82)]
const COMMUNITY_TINTS := [Color(0.88, 0.56, 0.40), Color(0.98, 0.86, 0.62), Color(0.96, 0.93, 0.86), Color(0.86, 0.66, 0.52)]
const CONCRETE := Color(0.82, 0.81, 0.77)

static var _mats: Dictionary = {}
static var _mesh_cache: Dictionary = {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# --- Layout (pure) -------------------------------------------------------------------------------

## The plan of site `s` in its frame. Pure: the far tiers, keeps_clear() and the checks ask it.
static func layout(s: Dictionary) -> Dictionary:
	var L: float = s.L
	var D: float = s.D
	var var_v := int(s.get("variant", 0))
	var k := int(s.kind)
	var out := {"L": L, "D": D}
	match k:
		CivicBuildings.Kind.LIBRARY_SPANISH:
			var bw := clampf(L - 8.0, 16.0, 30.0)
			var bd := clampf(D * 0.42, 11.0, 15.0)
			var sb := clampf(D * 0.28, 6.5, 10.0)
			var bu0 := (L - bw) * 0.5
			out.merge({"sb": sb, "bu0": bu0, "bu1": bu0 + bw, "bv0": sb, "bv1": sb + bd, "h": WALL_H_SPANISH,
				"tower": var_v % 5 < 2 and bw >= 18.0, "tower_left": var_v % 2 == 0,
				"loggia": var_v % 5 >= 3 and L - bw >= 9.0, "wing": D - (sb + bd) >= 9.0 and var_v % 3 != 0,
				"tint": STUCCO_TINTS[var_v % STUCCO_TINTS.size()]})
		CivicBuildings.Kind.LIBRARY_MODERN:
			var bw2 := clampf(L - 10.0, 16.0, 30.0)
			var bd2 := clampf(D * 0.42, 11.0, 15.0)
			var sb2 := clampf(D * 0.26, 6.5, 9.5)
			var bu02 := (L - bw2) * 0.5
			out.merge({"sb": sb2, "bu0": bu02, "bu1": bu02 + bw2, "bv0": sb2, "bv1": sb2 + bd2, "h": 4.8,
				"folded": var_v % 2 == 0, "over": 1.8, "park": D - (sb2 + bd2) >= 13.0})
		CivicBuildings.Kind.POST_OFFICE:
			var drive := 6.5
			var bw3 := clampf(L - drive - 4.5, 18.0, 30.0)
			var bd3 := clampf(D * 0.36, 12.0, 16.0)
			var sb3 := clampf(D * 0.2, 7.0, 9.5)
			var brick := var_v % 3 != 0
			out.merge({"sb": sb3, "bu0": 1.8, "bu1": 1.8 + bw3, "bv0": sb3, "bv1": sb3 + bd3, "h": 7.6,
				"drive_u": L - 0.6 - drive * 0.5, "drive_w": drive, "dock": D - (sb3 + bd3) >= 10.0, "brick": brick})
		CivicBuildings.Kind.CITY_SERVICES:
			var bw4 := clampf(L - 8.0, 22.0, 44.0)
			var bd4 := clampf(D * 0.44, 13.0, 18.0)
			var sb4 := clampf(D * 0.22, 6.0, 9.0)
			var bu04 := (L - bw4) * 0.5
			var storeys := 2 + int(var_v % 2 == 0)
			out.merge({"sb": sb4, "bu0": bu04, "bu1": bu04 + bw4, "bv0": sb4, "bv1": sb4 + bd4, "storeys": storeys,
				"h": 4.6 + 3.8 * float(storeys - 1), "colonnade": 3.0, "park": D - (sb4 + bd4) >= 13.0})
		CivicBuildings.Kind.COMMUNITY:
			var hw := clampf(L * 0.42, 15.0, 21.0)
			var hd := clampf(D * 0.5, 15.0, 22.0)
			var sb5 := clampf(D * 0.22, 6.0, 9.0)
			var hall_left := var_v % 2 == 0
			var hu0 := 2.0 if hall_left else L - 2.0 - hw
			var wu0 := hu0 + hw + 3.0 if hall_left else 2.0
			var wu1 := L - 2.0 if hall_left else hu0 - 3.0
			out.merge({"sb": sb5, "bu0": minf(hu0, wu0), "bu1": maxf(hu0 + hw, wu1), "bv0": sb5, "bv1": sb5 + hd,
				"hall": [hu0, hu0 + hw], "wing": [wu0, wu1], "wing_d": clampf(hd * 0.7, 11.0, 15.0), "h": 8.0,
				"tint": COMMUNITY_TINTS[var_v % COMMUNITY_TINTS.size()], "bowstring": var_v % 3 != 0})
	return out


## The building's masses (frame-local boxes, the node's space) for the far tiers and collision:
## [{c, size, color, finish, window, rows, pitch, lit, wall_set, roof?, roof_pitch?}].
static func masses(s: Dictionary, lay: Dictionary) -> Array:
	var L: float = lay.L
	var sx := 1.0
	var out: Array = []
	var B := func(u0: float, u1: float, y0: float, y1: float, v0: float, v1: float) -> Array:
		return [Vector3(((u0 + u1) * 0.5 - L * 0.5) * sx, (y0 + y1) * 0.5, -(v0 + v1) * 0.5), Vector3(absf(u1 - u0), y1 - y0, absf(v1 - v0))]
	var lit := 0.55
	match int(s.kind):
		CivicBuildings.Kind.LIBRARY_SPANISH:
			var b: Array = B.call(lay.bu0, lay.bu1, 0.0, lay.h, lay.bv0, lay.bv1)
			out.append({"c": b[0], "size": b[1], "color": lay.tint, "finish": Building.Finish.FLAT, "window": Building.WindowStyle.NARROW,
				"rows": 1, "pitch": 3.4, "lit": lit, "wall_set": "plaster_white", "roof": HouseKit.CLAY_FAR, "roof_pitch": 0.42})
			var cu := (float(lay.bu0) + float(lay.bu1)) * 0.5
			var p: Array = B.call(cu - 3.4, cu + 3.4, 0.0, lay.h + 1.6, float(lay.bv0) - 2.6, float(lay.bv0) + 1.0)
			out.append({"c": p[0], "size": p[1], "color": lay.tint, "plain": true, "solid": true})
			if lay.tower:
				var tu: float = float(lay.bu0) + 0.6 if lay.tower_left else float(lay.bu1) - 4.8
				var t: Array = B.call(tu, tu + 4.2, 0.0, 11.0, float(lay.bv0) - 0.8, float(lay.bv0) + 3.4)
				out.append({"c": t[0], "size": t[1], "color": lay.tint, "plain": true, "roof": HouseKit.CLAY_FAR, "roof_pitch": 0.9})
		CivicBuildings.Kind.LIBRARY_MODERN:
			var b2: Array = B.call(lay.bu0, lay.bu1, 0.0, lay.h, lay.bv0, lay.bv1)
			out.append({"c": b2[0], "size": b2[1], "color": Color(0.70, 0.66, 0.58), "finish": Building.Finish.GLASS, "window": Building.WindowStyle.CURTAIN,
				"rows": 1, "pitch": 1.5, "lit": 0.7})
			var r2: Array = B.call(float(lay.bu0) - lay.over, float(lay.bu1) + lay.over, lay.h, lay.h + 0.5, float(lay.bv0) - lay.over, float(lay.bv1) + lay.over)
			out.append({"c": r2[0], "size": r2[1], "color": Color(0.9, 0.89, 0.86), "plain": true, "solid": false})
		CivicBuildings.Kind.POST_OFFICE:
			var b3: Array = B.call(lay.bu0, lay.bu1, 0.0, float(lay.h) + 1.0, lay.bv0, lay.bv1)
			out.append({"c": b3[0], "size": b3[1], "color": Color(0.62, 0.36, 0.28) if lay.brick else Color(0.90, 0.86, 0.76),
				"finish": Building.Finish.BRICK if lay.brick else Building.Finish.FLAT, "window": Building.WindowStyle.NARROW,
				"rows": 1, "pitch": 3.6, "lit": lit, "wall_set": "brick_red" if lay.brick else "plaster_beige"})
		CivicBuildings.Kind.CITY_SERVICES:
			var b4: Array = B.call(lay.bu0, lay.bu1, 0.0, float(lay.h) + 0.9, lay.bv0, lay.bv1)
			out.append({"c": b4[0], "size": b4[1], "color": CONCRETE, "finish": Building.Finish.PANELS, "window": Building.WindowStyle.RIBBON,
				"rows": int(lay.storeys), "pitch": 1.2, "lit": 0.6, "wall_set": "concrete"})
		CivicBuildings.Kind.COMMUNITY:
			var hall: Array = lay.hall
			var wing: Array = lay.wing
			var hb: Array = B.call(hall[0], hall[1], 0.0, lay.h, lay.bv0, lay.bv1)
			out.append({"c": hb[0], "size": hb[1], "color": lay.tint, "finish": Building.Finish.FLAT, "window": Building.WindowStyle.RIBBON,
				"rows": 1, "pitch": 3.0, "lit": 0.5, "wall_set": "plaster_painted"})
			var hr: Array = B.call(hall[0], hall[1], lay.h, float(lay.h) + 1.4, lay.bv0, lay.bv1)
			out.append({"c": hr[0], "size": hr[1], "color": Color(0.62, 0.64, 0.66), "plain": true})
			if float(wing[1]) - float(wing[0]) > 6.0:
				var wb: Array = B.call(wing[0], wing[1], 0.0, 4.6, lay.bv0, float(lay.bv0) + float(lay.wing_d))
				out.append({"c": wb[0], "size": wb[1], "color": lay.tint, "finish": Building.Finish.FLAT, "window": Building.WindowStyle.PUNCHED,
					"rows": 1, "pitch": 3.2, "lit": 0.45, "wall_set": "plaster_painted"})
	return out


# --- FULL build ----------------------------------------------------------------------------------

## Builds the FULL-detail building under `node` (the site's local frame). Returns what the chunk
## adds round it: {"occluders": [[centre, size]], "trees": [[local pos, palm]], "seats": [[local
## pos, yaw]], "people": [[local Rect2 (x, z), salt, worker]], "cars": [[local Transform3D, paint]]}.
static func build(node: Node3D, s: Dictionary, lay: Dictionary, sx: float, sidewalk: float) -> Dictionary:
	var L: float = lay.L
	var g := CivicGeo.new(L, sx, int(s.builder))
	g.colors["clay"] = Color.WHITE
	g.colors["clay_ridge"] = Color.WHITE
	g.colors["seam"] = Color.WHITE
	lay["sidewalk"] = sidewalk
	var res := {"occluders": [], "trees": [], "seats": [], "people": [], "cars": [], "trucks": [], "flags": [], "texts": [], "lamps": [], "pools": []}
	match int(s.kind):
		CivicBuildings.Kind.LIBRARY_SPANISH:
			_library_spanish(g, s, lay, res)
		CivicBuildings.Kind.LIBRARY_MODERN:
			_library_modern(g, s, lay, res)
		CivicBuildings.Kind.POST_OFFICE:
			_post_office(g, s, lay, res)
		CivicBuildings.Kind.CITY_SERVICES:
			_city_services(g, s, lay, res)
		CivicBuildings.Kind.COMMUNITY:
			_community(g, s, lay, res)
	var mi := MeshInstance3D.new()
	mi.name = "Building"
	mi.mesh = g.commit(material)
	node.add_child(mi)
	node.set_meta("triangles", g.tris)
	_collision(node, s, lay, sx, res)
	_texts(node, g, res)
	_flags(node, g, res)
	_trucks(node, g, res)
	_night(node, g, res)
	for m: Dictionary in masses(s, lay):
		var c: Vector3 = m.c
		res.occluders.append([Vector3(c.x * sx, c.y, c.z), m.size])
	return res


## The four faces of the frame box (u0..u1, v0..v1) as [o, t, n, length] in wall() terms: front
## (street, v0), right (u1), back (v1), left (u0).
static func _faces(u0: float, u1: float, v0: float, v1: float) -> Array:
	return [[Vector3(u0, 0, v0), Vector3(1, 0, 0), Vector3(0, 0, -1), u1 - u0],
		[Vector3(u1, 0, v0), Vector3(0, 0, 1), Vector3(1, 0, 0), v1 - v0],
		[Vector3(u1, 0, v1), Vector3(-1, 0, 0), Vector3(0, 0, 1), u1 - u0],
		[Vector3(u0, 0, v1), Vector3(0, 0, -1), Vector3(-1, 0, 0), v1 - v0]]


## Openings evenly along a face of `length`: `n` of width `w`, from y0 to y1, keeping `margin`
## at each end and out of `keep` ranges [[a0, a1], ...].
static func _row(length: float, n: int, w: float, y0: float, y1: float, margin: float, arch: bool, glass: String, depth: float, keep: Array = [], room_h: float = 3.4, floor_y: float = 0.0) -> Array:
	var out: Array = []
	if n <= 0 or length - margin * 2.0 < w:
		return out
	var step := (length - margin * 2.0) / float(n)
	for i in n:
		var c := margin + step * (float(i) + 0.5)
		var a0 := c - w * 0.5
		var a1 := c + w * 0.5
		var bad := false
		for r: Array in keep:
			if a1 > float(r[0]) - 0.3 and a0 < float(r[1]) + 0.3:
				bad = true
		if not bad:
			out.append({"a0": a0, "a1": a1, "y0": y0, "y1": y1, "arch": arch, "glass": glass, "depth": depth, "room_h": room_h, "floor": floor_y})
	return out


## Walls of a box with openings per face (ops[0..3] in _faces() order); muntins on every opening
## with glass when `mullions` > 0 (cols, rows per metre).
static func _box_walls(g: CivicGeo, key: String, reveal: String, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, ops: Array, frame_key: String = "", grid := Vector2(0.0, 0.0)) -> void:
	var faces := _faces(u0, u1, v0, v1)
	for f in 4:
		var fc: Array = faces[f]
		var o: Vector3 = fc[0]
		var face_ops: Array = ops[f] if f < ops.size() else []
		g.wall(key, o, fc[1], fc[2], 0.0, fc[3], y0, y1, face_ops, reveal)
		if frame_key != "" and grid.x > 0.0:
			for op: Dictionary in face_ops:
				if String(op.get("glass", "")) == "":
					continue
				var cols := maxi(1, roundi((float(op.a1) - float(op.a0)) / grid.x))
				var rows := maxi(1, roundi((g._spring(op) - float(op.y0)) / grid.y))
				g.muntins(frame_key, o, fc[1], fc[2], op, cols, rows)


## A flat roof with a parapet over the frame box.
static func _flat_roof(g: CivicGeo, wall_key: String, cap_key: String, u0: float, u1: float, v0: float, v1: float, y: float, parapet: float, roof_key := "roof") -> void:
	g.box(roof_key, u0 + 0.2, u1 - 0.2, y - 0.1, y + 0.05, v0 + 0.2, v1 - 0.2)
	if parapet <= 0.0:
		return
	g.box(wall_key, u0, u1, y, y + parapet, v0, v0 + 0.25)
	g.box(wall_key, u0, u1, y, y + parapet, v1 - 0.25, v1)
	g.box(wall_key, u0, u0 + 0.25, y, y + parapet, v0, v1)
	g.box(wall_key, u1 - 0.25, u1, y, y + parapet, v0, v1)
	g.box(cap_key, u0 - 0.06, u1 + 0.06, y + parapet, y + parapet + 0.08, v0 - 0.06, v0 + 0.31)
	g.box(cap_key, u0 - 0.06, u1 + 0.06, y + parapet, y + parapet + 0.08, v1 - 0.31, v1 + 0.06)
	g.box(cap_key, u0 - 0.06, u0 + 0.31, y + parapet, y + parapet + 0.08, v0, v1)
	g.box(cap_key, u1 - 0.31, u1 + 0.06, y + parapet, y + parapet + 0.08, v0, v1)


## The site's ground: paving under the forecourt, lawn either side of a walk, asphalt for drives.
static func _ground(g: CivicGeo, key: String, u0: float, u1: float, v0: float, v1: float) -> void:
	# Deep enough to meet the pavement round a site on a slope (MAX_RELIEF).
	g.box(key, u0, u1, -1.0, 0.025, v0, v1)


## A bench (seat, back, two cast legs) facing -v (the street) at frame (u, v); its seat for the
## crowd in `res`.
static func _bench(g: CivicGeo, res: Dictionary, u: float, v: float, facing_street: bool = true) -> void:
	var f := -1.0 if facing_street else 1.0
	g.box("wood", u - 0.9, u + 0.9, 0.42, 0.47, v - 0.22, v + 0.22)
	g.box("wood", u - 0.9, u + 0.9, 0.55, 0.85, v - f * 0.24, v - f * 0.2)
	for e: float in [-0.75, 0.75]:
		g.box("iron", u + e - 0.04, u + e + 0.04, 0.0, 0.85, v - 0.24, v + 0.24)
	var p := g.P(u, 0.0, v)
	res.seats.append([p, PI if facing_street else 0.0])


## A lamp post with a lantern head (cast iron, a lit glass box), its pool and a real light.
static func _lamp_post(g: CivicGeo, res: Dictionary, u: float, v: float, h: float = 3.6) -> void:
	g.cyl("iron", Vector3(u, 0.0, v), 0.11, 0.5, 8)
	g.cyl("iron", Vector3(u, 0.5, v), 0.05, h - 0.5, 8)
	g.box("iron", u - 0.2, u + 0.2, h, h + 0.06, v - 0.2, v + 0.2)
	g.box("lamp_warm", u - 0.15, u + 0.15, h + 0.06, h + 0.5, v - 0.15, v + 0.15)
	g.box("iron", u - 0.22, u + 0.22, h + 0.5, h + 0.58, v - 0.22, v + 0.22)
	g.cyl("iron", Vector3(u, h + 0.58, v), 0.06, 0.18, 6, 0.01)
	res.pools.append([g.P(u, 0.06, v), 7.5, Color(1.0, 0.82, 0.58), 0.9])
	res.lamps.append([g.P(u, h + 0.3, v), 11.0, Color(1.0, 0.8, 0.56)])


## A wall-mounted lantern beside a door at frame (u, y, v) on a face with outward normal `n`.
static func _wall_lantern(g: CivicGeo, res: Dictionary, u: float, y: float, v: float, n: Vector3) -> void:
	var o := Vector3(u, y, v) + n * 0.28
	g.box("iron", o.x - 0.13, o.x + 0.13, y + 0.42, y + 0.48, o.z - 0.13, o.z + 0.13)
	g.box("lamp_warm", o.x - 0.1, o.x + 0.1, y, y + 0.42, o.z - 0.1, o.z + 0.1)
	g.box("iron", o.x - 0.12, o.x + 0.12, y - 0.06, y, o.z - 0.12, o.z + 0.12)
	g.beam("iron", Vector3(u, y + 0.45, v), Vector3(o.x, y + 0.45, o.z), 0.04)
	res.pools.append([g.P(u + n.x * 1.2, 0.06, v + n.z * 1.2), 4.0, Color(1.0, 0.8, 0.55), 0.7])


## A flagpole at frame (u, v), `h` tall, flying `flag_kind` (0 the national stripes, 1 the city's).
static func _flagpole(g: CivicGeo, res: Dictionary, u: float, v: float, h: float, flag_kind: int) -> void:
	g.cyl("concrete", Vector3(u, 0.0, v), 0.45, 0.25, 10)
	g.cyl("pole", Vector3(u, 0.25, v), 0.075, h - 0.25, 10, 0.045)
	g.cyl("gold", Vector3(u, h, v), 0.1, 0.2, 8, 0.02)
	res.flags.append([g.P(u, h - 0.15, v), flag_kind])


## A blue kerbside collection box at frame (u, v), its door facing the street.
static func _mailbox(g: CivicGeo, u: float, v: float) -> void:
	for e: Array in [[-0.22, -0.18], [0.22, -0.18], [-0.22, 0.18], [0.22, 0.18]]:
		g.box("box_blue", u + float(e[0]) - 0.03, u + float(e[0]) + 0.03, 0.0, 0.25, v + float(e[1]) - 0.03, v + float(e[1]) + 0.03)
	g.box("box_blue", u - 0.3, u + 0.3, 0.25, 1.05, v - 0.25, v + 0.25)
	g.hcyl("box_blue", u - 0.3, u + 0.3, 1.05, v, 0.25, 8, true)
	# The pull-down slot door, a white panel with the service's mark.
	g.box("iron", u - 0.2, u + 0.2, 0.92, 1.18, v - 0.27, v - 0.24)
	g.box("paint_white", u - 0.16, u + 0.16, 0.5, 0.78, v - 0.26, v - 0.25)
	g.box("box_red", u - 0.16, u + 0.16, 0.59, 0.62, v - 0.265, v - 0.255)


## Trees and palms for the forecourt: at frame (u, v).
static func _tree(g: CivicGeo, res: Dictionary, u: float, v: float, palm: bool) -> void:
	g.cyl("concrete", Vector3(u, 0.0, v), 0.75, 0.06, 10)
	res.trees.append([g.P(u, 0.0, v), palm])


## A car park strip of stalls along frame u at v0..v0+5.4 (noses toward +v when `toward_back`),
## static cars (ArenaGrounds' mesh, the chunk's batch) in `fill` of them.
static func _car_park(g: CivicGeo, res: Dictionary, u0: float, u1: float, v0: float, toward_back: bool, fill: float, salt: Array) -> void:
	var stall := 2.7
	g.box("asphalt", u0, u1, -0.04, 0.03, v0 - 6.0, v0 + 5.6)
	var u := u0 + 0.6
	var i := 0
	while u + stall <= u1 - 0.4:
		g.box("paint_white", u - 0.05, u + 0.05, 0.03, 0.04, v0 + 0.3, v0 + 5.2)
		var cu := u + stall * 0.5
		g.box("concrete", cu - 0.85, cu + 0.85, 0.03, 0.15, v0 + (4.85 if toward_back else 0.45), v0 + (5.05 if toward_back else 0.65))
		if _h01(salt + [i, "car"]) < fill:
			var yaw := (0.0 if toward_back else PI) + (_h01(salt + [i, "yaw"]) - 0.5) * 0.05
			var paint: Color = ArenaGrounds.CAR_PAINTS[absi(hash(salt + [i, "paint"])) % ArenaGrounds.CAR_PAINTS.size()]
			var v := 0 if _h01(salt + [i, "v"]) < 0.62 else 2
			# Local: the car's nose is -Z; frame +v is local -Z.
			var p := g.P(cu, 0.03, v0 + 2.7)
			res.cars.append([Transform3D(Basis(Vector3.UP, yaw), p), paint, v])
		u += stall
		i += 1
	g.box("paint_white", u - 0.05, u + 0.05, 0.03, 0.04, v0 + 0.3, v0 + 5.2)


# --- The Spanish revival branch library ----------------------------------------------------------

static func _library_spanish(g: CivicGeo, s: Dictionary, lay: Dictionary, res: Dictionary) -> void:
	var L: float = lay.L
	var D: float = lay.D
	var u0: float = lay.bu0
	var u1: float = lay.bu1
	var v0: float = lay.bv0
	var v1: float = lay.bv1
	var h: float = lay.h
	var cu := (u0 + u1) * 0.5
	var tint: Color = lay.tint
	g.colors["stucco"] = tint
	# Ground: the lawn either side of a paver walk from the kerb to the door, a terrazzo landing.
	_ground(g, "lawn", 0.0, L, 0.0, D)
	g.box("pavers", cu - 1.4, cu + 1.4, 0.0, 0.05, 0.0, v0 - 2.6)
	g.box("pavers", u0 - 1.0, u1 + 1.0, 0.0, 0.05, v1, minf(v1 + 1.4, D))
	# A low stucco garden wall along the street with a gap for the walk and terracotta caps.
	for seg: Array in [[0.4, cu - 2.2], [cu + 2.2, L - 0.4]]:
		g.box("stucco", seg[0], seg[1], 0.0, 0.6, 0.4, 0.7)
		g.box("terracotta", float(seg[0]) - 0.03, float(seg[1]) + 0.03, 0.6, 0.66, 0.35, 0.75)
	for e: float in [cu - 2.2, cu + 2.2]:
		g.box("stucco", e - 0.3, e + 0.3, 0.0, 1.1, 0.3, 0.8)
		g.box("terracotta", e - 0.34, e + 0.34, 1.1, 1.18, 0.26, 0.84)
	# The main block: thick stucco walls, tall arched reading-room windows, a hip roof of clay.
	var pav0 := cu - 3.2
	var pav1 := cu + 3.2
	var front := _row(u1 - u0, maxi(2, int((u1 - u0) / 3.6)), 1.7, 1.15, 4.9, 1.6, true, "glass_lib", 0.32, [[pav0 - u0, pav1 - u0]], 6.0)
	var sidec := maxi(1, int((v1 - v0 - 2.0) / 3.6))
	var right := _row(v1 - v0, sidec, 1.7, 1.15, 4.9, 1.6, true, "glass_lib", 0.32, [], 6.0)
	var left := _row(v1 - v0, sidec, 1.7, 1.15, 4.9, 1.6, true, "glass_lib", 0.32, [], 6.0)
	var back := _row(u1 - u0, maxi(2, int((u1 - u0) / 4.0)), 1.4, 3.1, 5.0, 1.6, false, "glass_lib", 0.3, [], 6.0)
	if lay.tower:
		# The tower stands on a front corner: no windows behind it.
		if lay.tower_left:
			left = left.filter(func(op: Dictionary) -> bool: return float(op.a1) < (v1 - v0) - 4.0)
			front = front.filter(func(op: Dictionary) -> bool: return float(op.a0) > 5.2)
		else:
			right = right.filter(func(op: Dictionary) -> bool: return float(op.a0) > 4.0)
			front = front.filter(func(op: Dictionary) -> bool: return float(op.a1) < (u1 - u0) - 5.2)
	_box_walls(g, "stucco", "stucco", u0, u1, v0, v1, 0.0, h, [front, right, back, left], "steel_dark", Vector2(0.42, 0.55))
	# A cast-stone water table at the foot and iron grilles over the lower lights.
	g.box("cast_stone", u0 - 0.06, u1 + 0.06, 0.0, 0.45, v0 - 0.06, v0 + 0.1)
	g.box("cast_stone", u0 - 0.06, u1 + 0.06, 0.0, 0.45, v1 - 0.1, v1 + 0.06)
	g.box("cast_stone", u0 - 0.06, u0 + 0.1, 0.0, 0.45, v0, v1)
	g.box("cast_stone", u1 - 0.1, u1 + 0.06, 0.0, 0.45, v0, v1)
	for op: Dictionary in front:
		var a0 := u0 + float(op.a0)
		var a1 := u0 + float(op.a1)
		g.box("cast_stone", a0 - 0.12, a1 + 0.12, 1.02, 1.15, v0 - 0.12, v0 + 0.02)
		var nb := 5
		for k in nb + 1:
			var bu := lerpf(a0 + 0.08, a1 - 0.08, float(k) / float(nb))
			g.box("iron", bu - 0.018, bu + 0.018, 1.15, 2.75, v0 - 0.1, v0 - 0.064)
		for yb: float in [1.3, 2.7]:
			g.box("iron", a0, a1, yb - 0.02, yb + 0.02, v0 - 0.1, v0 - 0.064)
	# Roof: a hip of clay tile with exposed rafter tails, a cast-stone frieze under the eave.
	g.box("cast_stone", u0 - 0.04, u1 + 0.04, h - 0.45, h - 0.3, v0 - 0.08, v1 + 0.08)
	g.hip("clay", "soffit_wood", u0, u1, v0, v1, h, 0.42, 0.75)
	g.rafters("wood_dark", u0 - 0.4, u1 + 0.4, h - 0.05, v0, 0.65, -1.0)
	g.rafters("wood_dark", u0 - 0.4, u1 + 0.4, h - 0.05, v1, 0.65, 1.0)
	# The entrance pavilion: taller, projecting, its gable to the street, an arched door in a
	# cast-stone surround, a small arched window above, lanterns either side.
	var pv0 := v0 - 2.6
	var ph := h + 1.6
	var door := {"a0": 3.2 - 1.2, "a1": 3.2 + 1.2, "y0": 0.0, "y1": 4.3, "arch": true, "glass": "glass_door", "depth": 0.55}
	var above := {"a0": 3.2 - 0.55, "a1": 3.2 + 0.55, "y0": 5.2, "y1": 6.9, "arch": true, "glass": "glass_lib", "depth": 0.35}
	var pfaces := _faces(pav0, pav1, pv0, v0 + 0.01)
	g.wall("stucco", pfaces[0][0], pfaces[0][1], pfaces[0][2], 0.0, 6.4, 0.0, ph, [door, above], "stucco")
	g.wall("stucco", pfaces[1][0], pfaces[1][1], pfaces[1][2], 0.0, 2.61, 0.0, ph, [], "stucco")
	g.wall("stucco", pfaces[3][0], pfaces[3][1], pfaces[3][2], 0.0, 2.61, 0.0, ph, [], "stucco")
	g.muntins("steel_dark", pfaces[0][0], pfaces[0][1], pfaces[0][2], above, 2, 3)
	# Door leaves: two panelled oak leaves set in the opening, the arch over them glazed.
	g.box("door_oak", pav0 + 2.05, pav1 - 2.05, 0.0, 3.2, pv0 + 0.5, pv0 + 0.56)
	g.box("iron", cu - 0.03, cu + 0.03, 0.05, 3.15, pv0 + 0.48, pv0 + 0.5)
	for side: float in [-1.0, 1.0]:
		for py: float in [0.4, 1.6]:
			g.box("door_panel", cu + side * 0.6 - 0.4, cu + side * 0.6 + 0.4, py, py + 1.0, pv0 + 0.47, pv0 + 0.5)
	# The surround: pilasters and an archivolt of cast stone proud of the wall, a shield over it.
	g.box("cast_stone", pav0 + 1.35, pav0 + 1.85, 0.0, 3.3, pv0 - 0.14, pv0)
	g.box("cast_stone", pav1 - 1.85, pav1 - 1.35, 0.0, 3.3, pv0 - 0.14, pv0)
	for k in 12:
		var a0 := PI - PI * float(k) / 12.0
		var a1 := PI - PI * float(k + 1) / 12.0
		var r := 1.45
		var c0 := Vector3(cu + cos(a0) * r, 3.1 + sin(a0) * r, pv0 - 0.07)
		var c1 := Vector3(cu + cos(a1) * r, 3.1 + sin(a1) * r, pv0 - 0.07)
		g.beam("cast_stone", c0, c1, 0.34)
	g.box("cast_stone", cu - 0.35, cu + 0.35, 4.55, 5.0, pv0 - 0.16, pv0)
	g.box("tile_blue", cu - 2.5, cu + 2.5, 6.98, 7.08, pv0 - 0.03, pv0)
	g.gable("clay", "stucco", "soffit_wood", pav0, pav1, pv0, v0 + 1.0, ph, 0.42, 0.55, false)
	# Steps: three terrazzo risers out to the walk.
	for k in 3:
		g.box("terrazzo", cu - 2.2 + float(k) * 0.3, cu + 2.2 - float(k) * 0.3, 0.0, 0.17 * float(3 - k) * 0.33 + 0.02, pv0 - 1.4 + float(k) * 0.4, pv0)
	_wall_lantern(g, res, cu - 2.2, 2.4, pv0, Vector3(0, 0, -1))
	_wall_lantern(g, res, cu + 2.2, 2.4, pv0, Vector3(0, 0, -1))
	g.box("lamp_warm", cu - 0.25, cu + 0.25, 4.35, 4.42, pv0 + 0.1, pv0 + 0.5)
	res.texts.append(["PUBLIC LIBRARY", 0.5, Color(0.20, 0.16, 0.12), g.P(cu, 7.6, pv0 - 0.02), 140.0])
	# The corner tower: square, plain stucco, an arched belfry opening on each street side, a
	# steep clay hip and a finial.
	if lay.tower:
		var tu0: float = u0 + 0.6 if lay.tower_left else u1 - 4.8
		var tu1 := tu0 + 4.2
		var tv0 := v0 - 0.8
		var tv1 := v0 + 3.4
		var th := 11.0
		var bel := {"a0": 2.1 - 0.75, "a1": 2.1 + 0.75, "y0": 8.0, "y1": 10.1, "arch": true, "glass": "", "depth": 0.5, "through": true}
		var tw := {"a0": 2.1 - 0.4, "a1": 2.1 + 0.4, "y0": 4.0, "y1": 5.6, "arch": true, "glass": "glass_lib", "depth": 0.3}
		_box_walls(g, "stucco", "stucco", tu0, tu1, tv0, tv1, 0.0, th, [[bel, tw], [bel], [bel], [bel]])
		g.box("dark", tu0 + 0.5, tu1 - 0.5, 7.9, 10.2, tv0 + 0.5, tv1 - 0.5)
		g.box("cast_stone", tu0 - 0.1, tu1 + 0.1, 7.75, 7.95, tv0 - 0.1, tv1 + 0.1)
		g.hip("clay", "soffit_wood", tu0, tu1, tv0, tv1, th, 0.9, 0.4)
		g.cyl("copper", Vector3((tu0 + tu1) * 0.5, th + 2.35, (tv0 + tv1) * 0.5), 0.08, 0.9, 6, 0.01)
	# A side loggia: an arcade of three arches on piers along the side wall, a shed roof of clay.
	if lay.loggia:
		var la_u1 := u1 + 3.4
		var lv0 := v0 + 1.0
		var lv1 := v1 - 1.0
		var arc_ops := _row(lv1 - lv0, 3, 2.2, 0.0, 3.4, 0.35, true, "", 0.4)
		for op: Dictionary in arc_ops:
			op.through = true
		var o := Vector3(la_u1, 0.0, lv0)
		g.wall("stucco", o, Vector3(0, 0, 1), Vector3(1, 0, 0), 0.0, lv1 - lv0, 0.0, 4.0, arc_ops, "stucco")
		g.wall("stucco", Vector3(la_u1 - 0.4, 0.0, lv1), Vector3(0, 0, -1), Vector3(-1, 0, 0), 0.0, lv1 - lv0, 0.0, 4.0, _mirror_ops(arc_ops, lv1 - lv0), "stucco")
		g.box("stucco", u1, la_u1, 0.0, 4.0, lv0 - 0.4, lv0)
		g.box("stucco", u1, la_u1, 0.0, 4.0, lv1, lv1 + 0.4)
		g.box("terrazzo", u1, la_u1 - 0.4, 0.0, 0.06, lv0, lv1)
		g.box("soffit_wood", u1, la_u1, 3.95, 4.0, lv0, lv1)
		g.gable("clay", "stucco", "", u1 - 0.2, la_u1 + 0.3, lv0 - 0.4, lv1 + 0.4, 4.0, 0.3, 0.0, false)
		_bench(g, res, u1 + 1.7, (lv0 + lv1) * 0.5, false)
	# A low rear wing (the children's room) with a gable to the back.
	if lay.wing:
		var wu0 := cu - minf(5.5, (u1 - u0) * 0.3)
		var wu1 := cu + minf(5.5, (u1 - u0) * 0.3)
		var wv1 := minf(v1 + 7.5, D - 1.4)
		var wops := _row(wu1 - wu0, 2, 1.5, 1.0, 3.2, 1.2, false, "glass_lib", 0.28)
		var sops := _row(wv1 - v1, 1, 1.5, 1.0, 3.2, 1.0, false, "glass_lib", 0.28)
		_box_walls(g, "stucco", "stucco", wu0, wu1, v1 - 0.2, wv1, 0.0, 4.0, [[], sops, wops, sops], "steel_dark", Vector2(0.5, 0.55))
		g.gable("clay", "stucco", "soffit_wood", wu0, wu1, v1 - 0.2, wv1, 4.0, 0.42, 0.5, false)
	# Forecourt: two palms flanking the walk, a jacaranda or two on the lawn, benches, a book drop.
	_tree(g, res, cu - 3.4, (v0 - 2.6) * 0.45 + 0.4, true)
	_tree(g, res, cu + 3.4, (v0 - 2.6) * 0.45 + 0.4, true)
	if L > 30.0:
		_tree(g, res, 3.5, v0 * 0.5, false)
		_tree(g, res, L - 3.5, v0 * 0.5, false)
	_bench(g, res, cu - 4.8, v0 - 1.6)
	_bench(g, res, cu + 4.8, v0 - 1.6)
	_book_drop(g, cu + 2.6, 1.3)
	_bike_rack(g, cu - 3.0, 1.4)
	_lamp_post(g, res, cu - 2.0, 1.2)
	_lamp_post(g, res, cu + 2.0, 1.2)
	res.texts.append(["%s BRANCH LIBRARY" % String(s.name), 0.2, Color(0.30, 0.24, 0.18), g.P(cu - 2.2 - minf(3.0, cu - 3.0), 0.33, 0.38), 60.0])
	res.people.append([_ring(g, 1.0, L - 1.0, 0.9, v0 - 2.8), 1, false])
	res.people.append([_ring(g, 1.0, L - 1.0, 0.9, v0 - 2.8), 2, false])


## The same openings measured from the other end of a face of `length`.
static func _mirror_ops(ops: Array, length: float) -> Array:
	var out: Array = []
	for op: Dictionary in ops:
		var o2 := op.duplicate()
		o2.a0 = length - float(op.a1)
		o2.a1 = length - float(op.a0)
		out.append(o2)
	return out


## A frame rect for a people ring, as the local Rect2 (x, z) CivicBuildings expects.
static func _ring(g: CivicGeo, u0: float, u1: float, v0: float, v1: float) -> Rect2:
	var a := g.P(u0, 0.0, v0)
	var b := g.P(u1, 0.0, v1)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(b.x - a.x), absf(b.z - a.z)))


static func _book_drop(g: CivicGeo, u: float, v: float) -> void:
	g.box("box_green", u - 0.4, u + 0.4, 0.0, 1.05, v - 0.35, v + 0.35)
	g.hcyl("box_green", u - 0.4, u + 0.4, 1.05, v, 0.35, 8, true)
	g.box("steel", u - 0.25, u + 0.25, 0.95, 1.12, v - 0.37, v - 0.34)
	g.box("paint_white", u - 0.22, u + 0.22, 0.5, 0.7, v - 0.36, v - 0.35)


static func _bike_rack(g: CivicGeo, u: float, v: float) -> void:
	for k in 3:
		var bu := u - 0.8 + float(k) * 0.8
		g.beam("steel", Vector3(bu, 0.0, v - 0.35), Vector3(bu, 0.8, v - 0.35), 0.05)
		g.beam("steel", Vector3(bu, 0.0, v + 0.35), Vector3(bu, 0.8, v + 0.35), 0.05)
		g.beam("steel", Vector3(bu, 0.8, v - 0.35), Vector3(bu, 0.8, v + 0.35), 0.05)


# --- The mid-century branch library -------------------------------------------------------------

static func _library_modern(g: CivicGeo, s: Dictionary, lay: Dictionary, res: Dictionary) -> void:
	var L: float = lay.L
	var D: float = lay.D
	var u0: float = lay.bu0
	var u1: float = lay.bu1
	var v0: float = lay.bv0
	var v1: float = lay.bv1
	var h: float = lay.h
	var ov: float = lay.over
	var cu := (u0 + u1) * 0.5
	_ground(g, "lawn", 0.0, L, 0.0, D)
	g.box("concrete_pale", u0 - ov, u1 + ov, 0.0, 0.06, v0 - ov - 0.5, v0)
	g.box("concrete_pale", cu - 1.8, cu + 1.8, 0.0, 0.05, 0.0, v0 - ov)
	# Stone veneer plinth and side walls, a glass front of floor-to-ceiling panes between slim
	# aluminium mullions, the doors in the middle.
	var bay := 1.5
	var nb := maxi(4, roundi((u1 - u0) / bay))
	var bw := (u1 - u0) / float(nb)
	var front_ops: Array = []
	for i in nb:
		var a0 := float(i) * bw + 0.04
		var a1 := float(i + 1) * bw - 0.04
		front_ops.append({"a0": a0, "a1": a1, "y0": 0.45, "y1": h - 0.35, "glass": "glass_lib" if absf((a0 + a1) * 0.5 - (cu - u0)) > 1.6 else "glass_door", "depth": 0.06})
	var side_ops := _row(v1 - v0, maxi(1, int((v1 - v0) / 3.2)), 0.7, 0.9, h - 0.6, 1.4, false, "glass_lib", 0.15)
	var back_ops := _row(u1 - u0, maxi(2, int((u1 - u0) / 3.0)), 2.2, 2.6, h - 0.5, 1.2, false, "glass_lib", 0.12)
	var faces := _faces(u0, u1, v0, v1)
	g.wall("anodized", faces[0][0], faces[0][1], faces[0][2], 0.0, u1 - u0, 0.0, h, front_ops, "anodized")
	g.wall("stone", faces[1][0], faces[1][1], faces[1][2], 0.0, v1 - v0, 0.0, h, side_ops, "anodized")
	g.wall("stucco_white", faces[2][0], faces[2][1], faces[2][2], 0.0, u1 - u0, 0.0, h, back_ops, "anodized")
	g.wall("stone", faces[3][0], faces[3][1], faces[3][2], 0.0, v1 - v0, 0.0, h, side_ops, "anodized")
	for i in nb + 1:
		var mu := u0 + float(i) * bw
		g.box("anodized", mu - 0.05, mu + 0.05, 0.4, h - 0.3, v0 - 0.12, v0 + 0.02)
	g.box("anodized", u0, u1, 2.65, 2.72, v0 - 0.1, v0 + 0.02)
	g.box("stone", u0 - 0.1, u1 + 0.1, 0.0, 0.45, v0 - 0.12, v0 + 0.05)
	# The roof: a thin slab with a deep cantilever all round, a white fascia; or a folded plate of
	# ridges and valleys across the front, each fold a pair of panels.
	var ru0 := u0 - ov
	var ru1 := u1 + ov
	var rv0 := v0 - ov
	var rv1 := v1 + ov
	if lay.folded:
		var folds := maxi(3, roundi((ru1 - ru0) / 3.2))
		var fw := (ru1 - ru0) / float(folds)
		for i in folds:
			var a := ru0 + float(i) * fw
			var m := a + fw * 0.5
			var b := a + fw
			var lo := h + 0.05
			var hi := h + 1.15
			for half: Array in [[a, m, lo, hi], [m, b, hi, lo]]:
				var ua: float = half[0]
				var ub: float = half[1]
				var ya: float = half[2]
				var yb: float = half[3]
				var nn := Vector3(-(yb - ya), ub - ua, 0.0).normalized()
				g.quad("fascia_white", nn, Vector3(ua, ya, rv0), Vector3(ub, yb, rv0), Vector3(ub, yb, rv1), Vector3(ua, ya, rv1))
				g.quad("soffit_white", -nn, Vector3(ua, ya - 0.18, rv0), Vector3(ub, yb - 0.18, rv0), Vector3(ub, yb - 0.18, rv1), Vector3(ua, ya - 0.18, rv1))
				for ev: Array in [[rv0, -1.0], [rv1, 1.0]]:
					var vv: float = ev[0]
					g.quad("fascia_white", Vector3(0, 0, ev[1]), Vector3(ua, ya - 0.18, vv), Vector3(ub, yb - 0.18, vv), Vector3(ub, yb, vv), Vector3(ua, ya, vv))
			# The fold's triangle down to the wall top, closing the glass front's head.
			g.quad_tri("fascia_white", Vector3(0, 0, -1), Vector3(a, lo - 0.18, v0 - 0.01), Vector3(b, lo - 0.18, v0 - 0.01), Vector3(m, hi - 0.18, v0 - 0.01))
			g.quad_tri("fascia_white", Vector3(0, 0, 1), Vector3(a, lo - 0.18, v1 + 0.01), Vector3(b, lo - 0.18, v1 + 0.01), Vector3(m, hi - 0.18, v1 + 0.01))
		for eu: Array in [[ru0, -1.0], [ru1, 1.0]]:
			g.quad("fascia_white", Vector3(eu[1], 0, 0), Vector3(eu[0], h - 0.13, rv0), Vector3(eu[0], h - 0.13, rv1), Vector3(eu[0], h + 0.05, rv1), Vector3(eu[0], h + 0.05, rv0))
	else:
		g.box("fascia_white", ru0, ru1, h, h + 0.5, rv0, rv1)
		g.box("soffit_white", ru0, ru1, h - 0.02, h, rv0, rv1)
		g.box("anodized_gold", ru0 - 0.02, ru1 + 0.02, h + 0.38, h + 0.44, rv0 - 0.02, rv0 + 0.01)
	# Recessed downlights in the soffit (lit at night) and slim columns at the front edge.
	var dl := ru0 + 1.2
	while dl < ru1 - 0.8:
		g.box("lamp_cool", dl - 0.12, dl + 0.12, h - 0.04, h - 0.02, rv0 + 0.75, rv0 + 0.99)
		dl += 2.4
	for cu2: float in [u0 + 0.2, u1 - 0.2]:
		g.cyl("fascia_white", Vector3(cu2, 0.0, rv0 + 0.25), 0.09, h, 10)
	# The stone feature wall standing out under the eave, the name on its face, and a breeze-block
	# screen across the other side of the front.
	var fu := u0 + 2.2
	g.box("stone", fu - 4.2, fu + 0.3, 0.0, 3.4, v0 - ov - 0.1, v0 - ov + 0.35)
	res.texts.append(["PUBLIC LIBRARY", 0.42, Color(0.92, 0.80, 0.45), g.P(fu - 1.95, 2.45, v0 - ov - 0.12), 140.0])
	res.texts.append(["%s BRANCH" % String(s.name), 0.22, Color(0.92, 0.80, 0.45), g.P(fu - 1.95, 1.9, v0 - ov - 0.12), 90.0])
	g.colors["breeze"] = Color(0.92, 0.9, 0.84)
	var bu0 := u1 - 7.0
	var bu1 := u1 - 1.4
	var bv := v0 - 1.2
	for side: float in [-1.0, 1.0]:
		g.quad("breeze", Vector3(0, 0, side), Vector3(bu0, 0.3, bv), Vector3(bu1, 0.3, bv), Vector3(bu1, 3.1, bv), Vector3(bu0, 3.1, bv))
	g.box("concrete_pale", bu0 - 0.1, bu1 + 0.1, 0.0, 0.3, bv - 0.15, bv + 0.15)
	g.box("concrete_pale", bu0 - 0.1, bu1 + 0.1, 3.1, 3.2, bv - 0.15, bv + 0.15)
	res.texts.append([CivicBuildings.LIBRARY, 0.2, Color(0.3, 0.28, 0.24), g.P(cu, h + 0.25, rv0 - 0.03), 90.0])
	# Planters with low shrubs, benches, a book drop, a flag; a car park behind.
	for pu: float in [cu - 5.0, cu + 5.0]:
		g.box("concrete_pale", pu - 1.6, pu + 1.6, 0.0, 0.55, v0 - ov - 3.2, v0 - ov - 1.8)
		g.box("shrub", pu - 1.45, pu + 1.45, 0.55, 1.05, v0 - ov - 3.05, v0 - ov - 1.95)
	_bench(g, res, cu - 5.0, v0 - ov - 4.2)
	_bench(g, res, cu + 5.0, v0 - ov - 4.2)
	_book_drop(g, cu + 2.6, 1.2)
	if u0 - ov > 4.0:
		_tree(g, res, (u0 - ov) * 0.5, v0 + 2.0, false)
	if L - u1 - ov > 4.0:
		_tree(g, res, (L + u1 + ov) * 0.5, v0 + 2.0, false)
	_lamp_post(g, res, cu - 2.3, 1.1)
	if lay.park:
		_car_park(g, res, 1.0, L - 1.0, D - 6.6, true, 0.55, [s.builder, "lib_park"])
	res.people.append([_ring(g, 1.0, L - 1.0, 0.9, v0 - ov - 0.3), 1, false])
	res.people.append([_ring(g, 1.0, L - 1.0, 0.9, v0 - ov - 0.3), 2, false])


# --- The post office -----------------------------------------------------------------------------

static func _post_office(g: CivicGeo, s: Dictionary, lay: Dictionary, res: Dictionary) -> void:
	var L: float = lay.L
	var D: float = lay.D
	var u0: float = lay.bu0
	var u1: float = lay.bu1
	var v0: float = lay.bv0
	var v1: float = lay.bv1
	var h: float = lay.h
	var cu := (u0 + u1) * 0.5
	var wall := "brick" if lay.brick else "stucco_cream"
	var fl := PO_FLOOR
	_ground(g, "lawn", 0.0, u1 + 0.6, 0.0, v0)
	g.box("concrete_pale", cu - 2.4, cu + 2.4, 0.0, 0.05, 0.0, v0 - 3.0)
	g.box("concrete_pale", u0 - 0.6, u1 + 0.6, 0.0, 0.04, v0 - 1.0, v0)
	# The drive along the high-u side to the yard, its apron across the pavement.
	var du: float = lay.drive_u
	var dw: float = lay.drive_w
	g.box("asphalt", du - dw * 0.5, du + dw * 0.5, -0.04, 0.035, 0.0, D)
	g.box("asphalt", u1 + 0.6, L, -0.04, 0.035, v0, D)
	g.box("asphalt", 0.0, u1 + 0.6, -0.04, 0.035, v1, D)
	# The building: a granite base, brick or stucco walls in bays between flat pilasters, tall
	# multi-light windows over stone sills under stone lintels, the entrance in the middle bay up
	# a granite stair; a stone cornice and a parapet.
	var nbays := po_bays(lay)
	var bayw := (u1 - u0) / float(nbays)
	var mid := nbays / 2
	var front_ops: Array = []
	for i in nbays:
		var c := (float(i) + 0.5) * bayw
		if i == mid:
			front_ops.append({"a0": c - 1.3, "a1": c + 1.3, "y0": fl, "y1": fl + 3.6, "glass": "glass_door", "depth": 0.4, "floor": fl, "room_h": 6.6})
			front_ops.append({"a0": c - 1.3, "a1": c + 1.3, "y0": fl + 3.9, "y1": fl + 5.6, "glass": "glass_post", "depth": 0.4, "floor": fl, "room_h": 6.6})
		else:
			front_ops.append({"a0": c - 0.95, "a1": c + 0.95, "y0": fl + 1.0, "y1": fl + 5.4, "glass": "glass_post", "depth": 0.3, "floor": fl, "room_h": 6.6})
	var side_ops := _row(v1 - v0, maxi(1, int((v1 - v0) / 4.0)), 1.6, fl + 1.0, fl + 5.0, 1.6, false, "glass_post", 0.3, [], 6.6, fl)
	var faces := _faces(u0, u1, v0, v1)
	var back_ops: Array = []
	if lay.dock:
		back_ops = _row(u1 - u0, 3, 3.2, 1.25, 4.4, 2.0, false, "", 0.3)
		for op: Dictionary in back_ops:
			op.through = true
	g.wall(wall, faces[0][0], faces[0][1], faces[0][2], 0.0, u1 - u0, 0.0, h, front_ops, "cast_stone")
	g.wall(wall, faces[1][0], faces[1][1], faces[1][2], 0.0, v1 - v0, 0.0, h, side_ops, "cast_stone")
	g.wall(wall, faces[2][0], faces[2][1], faces[2][2], 0.0, u1 - u0, 0.0, h, back_ops, "concrete")
	g.wall(wall, faces[3][0], faces[3][1], faces[3][2], 0.0, v1 - v0, 0.0, h, side_ops, "cast_stone")
	for op: Dictionary in front_ops:
		if String(op.glass) == "glass_door":
			continue
		g.muntins("steel_dark", faces[0][0], faces[0][1], faces[0][2], op, 3, 6)
		var a0 := u0 + float(op.a0)
		var a1 := u0 + float(op.a1)
		g.box("cast_stone", a0 - 0.15, a1 + 0.15, float(op.y0) - 0.14, float(op.y0), v0 - 0.12, v0 + 0.02)
		g.box("cast_stone", a0 - 0.2, a1 + 0.2, float(op.y1), float(op.y1) + 0.32, v0 - 0.08, v0 + 0.02)
	for op: Dictionary in side_ops:
		g.muntins("steel_dark", faces[1][0], faces[1][1], faces[1][2], op, 3, 6)
		g.muntins("steel_dark", faces[3][0], faces[3][1], faces[3][2], op, 3, 6)
	for i in nbays + 1:
		var pu := u0 + float(i) * bayw
		g.box(wall, pu - 0.36, pu + 0.36, 0.9, h - 0.9, v0 - 0.16, v0 + 0.02)
		g.box("cast_stone", pu - 0.42, pu + 0.42, h - 0.9, h - 0.6, v0 - 0.2, v0 + 0.02)
	g.box("granite", u0 - 0.12, u1 + 0.12, 0.0, 0.9, v0 - 0.2, v1 + 0.12)
	g.box("cast_stone", u0 - 0.25, u1 + 0.25, h - 0.6, h, v0 - 0.32, v1 + 0.25)
	g.box("cast_stone", u0 - 0.38, u1 + 0.38, h - 0.08, h + 0.08, v0 - 0.42, v1 + 0.35)
	_flat_roof(g, wall, "cast_stone", u0, u1, v0, v1, h + 0.08, 0.95)
	# The entrance: a granite stair of three risers to a landing, brass rails, the doors in bronze
	# frames, an eagle-less transom (a clock), lantern standards either side.
	var ec := entry_u(lay)
	var rise := fl / 3.0
	for k in 3:
		g.box("granite", ec - 2.4 + float(k) * 0.1, ec + 2.4 - float(k) * 0.1, 0.0, rise * float(k + 1), v0 - 1.9 + float(k) * 0.45, v0)
	g.box("granite", ec - 2.4, ec + 2.4, 0.0, fl, v0 - 0.55, v0)
	for su: float in [ec - 1.7, ec + 1.7]:
		g.beam("brass", Vector3(su, 1.0, v0 - 2.1), Vector3(su, fl + 0.95, v0 - 0.4), 0.05)
		g.cyl("brass", Vector3(su, 0.0, v0 - 2.1), 0.03, 1.0, 6)
		g.cyl("brass", Vector3(su, fl, v0 - 0.4), 0.03, 0.95, 6)
	g.box("bronze", ec - 1.3, ec + 1.3, fl + 3.6, fl + 3.9, v0 - 0.4, v0 - 0.3)
	g.box("bronze", ec - 0.05, ec + 0.05, fl, fl + 3.6, v0 - 0.4, v0 - 0.34)
	g.cyl("bronze", Vector3(ec, fl + 4.75, v0 - 0.45), 0.42, 0.06, 16)
	g.cyl("paint_white", Vector3(ec, fl + 4.75, v0 - 0.47), 0.37, 0.02, 16)
	for lu: float in [ec - 2.7, ec + 2.7]:
		_lamp_post(g, res, lu, v0 - 1.2, 3.0)
	# Lettering on the frieze and over the door.
	res.texts.append(["%s OFFICE" % CivicBuildings.POST, 0.5, Color(0.86, 0.82, 0.70) if lay.brick else Color(0.25, 0.22, 0.18), g.P(cu, h - 0.3, v0 - 0.33), 150.0])
	res.texts.append(["%s STATION" % String(s.name), 0.24, Color(0.78, 0.64, 0.36), g.P(ec, fl + 3.75, v0 - 0.42), 70.0])
	# The flag on its pole on the lawn, collection boxes at the kerb.
	_flagpole(g, res, ec - 6.5 if ec - 6.5 > 2.0 else ec + 6.5, 2.4, 11.5, 0)
	g.cyl("concrete", Vector3(ec - 6.5 if ec - 6.5 > 2.0 else ec + 6.5, 0.0, 2.4), 1.4, 0.15, 14)
	_mailbox(g, ec + 3.0, 0.6)
	_mailbox(g, ec + 3.75, 0.6)
	_tree(g, res, maxf(u0 + 1.5, 2.0), v0 * 0.45, false)
	_bench(g, res, ec - 4.0, v0 - 1.6)
	# The loading dock behind: a raised platform under a canopy, roll-up doors, bumpers, the yard
	# with the mail trucks backed up to the dock and in a row along the back fence.
	if lay.dock:
		var dv0 := v1
		var dv1 := v1 + 3.0
		g.box("concrete", u0 + 0.6, u1 - 0.6, 0.0, 1.2, dv0, dv1)
		g.box("paint_yellow", u0 + 0.6, u1 - 0.6, 1.18, 1.21, dv1 - 0.18, dv1)
		for op: Dictionary in back_ops:
			var a0 := u1 - float(op.a1)
			var a1 := u1 - float(op.a0)
			g.box("rollup", a0, a1, 1.25, 4.4, v1 - 0.28, v1 - 0.24)
			for bu: float in [a0 + 0.3, a1 - 0.3]:
				g.box("rubber", bu - 0.15, bu + 0.15, 0.6, 1.1, dv1, dv1 + 0.12)
			var tru := (a0 + a1) * 0.5
			res.trucks.append(Transform3D(Basis(), g.P(tru, 0.035, dv1 + 0.4 + TRUCK.z * 0.5)))
		g.box("steel", u0 + 0.4, u1 - 0.4, 4.9, 5.1, dv0, dv1 + 2.0)
		for cu2: float in [u0 + 1.0, u1 - 1.0]:
			g.box("steel", cu2 - 0.1, cu2 + 0.1, 1.2, 4.9, dv1 + 1.8, dv1 + 2.0)
		g.box("lamp_cool", u0 + 1.0, u1 - 1.0, 4.88, 4.9, dv0 + 0.5, dv0 + 1.4)
		g.box("concrete", u1 - 2.4, u1 - 0.6, 0.0, 1.2, dv1, dv1 + 2.8)
		for k in 6:
			g.box("concrete", u1 - 2.4, u1 - 0.6, 0.0, 0.2 * float(6 - k), dv1 + 2.8 + float(k) * 0.3, dv1 + 3.1 + float(k) * 0.3)
		# The back row: noses to the building, tails to the fence.
		var tv := D - 0.9 - TRUCK.z * 0.5
		var tu := 2.0
		var n := 0
		while tu < du - dw * 0.5 - 1.2 and n < 5:
			if _h01([s.builder, n, "truck"]) < 0.85:
				res.trucks.append(Transform3D(Basis(Vector3.UP, PI), g.P(tu, 0.035, tv)))
			g.box("paint_white", tu + 1.3, tu + 1.4, 0.035, 0.045, tv - 2.4, tv + 2.4)
			tu += 3.0
			n += 1
		# Chain-link round the yard, an open gate leaf folded back by the drive.
		g.box("steel", 0.3, 0.36, 0.0, 2.4, v1, D - 0.3)
		g.box("steel", 0.3, L - 0.3, 2.34, 2.4, D - 0.36, D - 0.3)
		g.box("chain", 0.3, L - 0.3, 0.05, 2.34, D - 0.34, D - 0.32)
		g.box("chain", 0.32, 0.34, 0.05, 2.34, v1, D - 0.3)
		g.box("chain", L - 0.34, L - 0.32, 0.05, 2.34, v0 + 2.0, D - 0.3)
		g.box("steel", L - 0.36, L - 0.3, 2.34, 2.4, v0 + 2.0, D - 0.3)
		var fp := 0.3
		while fp < L:
			g.cyl("steel", Vector3(fp, 0.0, D - 0.33), 0.04, 2.4, 6)
			fp += 3.0
		# Floodlights on the building's back corners.
		for fu: float in [u0 + 0.6, u1 - 0.6]:
			g.box("steel_dark", fu - 0.25, fu + 0.25, 6.0, 6.25, v1 + 0.1, v1 + 0.5)
			g.box("lamp_cool", fu - 0.22, fu + 0.22, 5.98, 6.0, v1 + 0.15, v1 + 0.45)
			res.pools.append([g.P(fu, 0.06, v1 + 8.0), 14.0, Color(0.86, 0.92, 1.0), 0.7])
		res.lamps.append([g.P(cu, 4.4, v1 + 2.0), 18.0, Color(0.85, 0.92, 1.0)])
		res.people.append([_ring(g, u0 + 1.0, u1 - 1.0, v1 + 3.6, minf(v1 + 9.0, D - 2.0)), 3, true])
	# One more truck at the kerb in front, loading the collection boxes (CivicBuildings.keeps_clear
	# keeps the parked cars off that stretch).
	res.trucks.append(Transform3D(Basis(Vector3.UP, PI * 0.5), g.P(kerb_truck_u(lay), CityChunk.ROAD_TOP - CityChunk.SIDEWALK_TOP + 0.01, -float(lay.get("sidewalk", 4.0)) - 1.2)))
	res.people.append([_ring(g, 1.0, u1, 0.9, v0 - 2.4), 1, false])
	res.people.append([_ring(g, 1.0, u1, 0.9, v0 - 2.4), 2, false])


## The post office's bays across its front (odd, the door in the middle one).
static func po_bays(lay: Dictionary) -> int:
	return maxi(5, int((float(lay.bu1) - float(lay.bu0)) / 3.6) | 1)


## The post office's entrance (frame u).
static func entry_u(lay: Dictionary) -> float:
	var n := po_bays(lay)
	return float(lay.bu0) + (float(n / 2) + 0.5) * (float(lay.bu1) - float(lay.bu0)) / float(n)


## Where the mail truck stands at the kerb in front (frame u).
static func kerb_truck_u(lay: Dictionary) -> float:
	return entry_u(lay) + 3.4


# --- City services -------------------------------------------------------------------------------

static func _city_services(g: CivicGeo, s: Dictionary, lay: Dictionary, res: Dictionary) -> void:
	var L: float = lay.L
	var D: float = lay.D
	var u0: float = lay.bu0
	var u1: float = lay.bu1
	var v0: float = lay.bv0
	var v1: float = lay.bv1
	var h: float = lay.h
	var storeys := int(lay.storeys)
	var col: float = lay.colonnade
	var cu := (u0 + u1) * 0.5
	g.box("concrete_pale", 0.0, L, -0.05, 0.03, 0.0, v1 + 0.5)
	if not lay.park:
		g.box("lawn", 0.0, L, -0.05, 0.025, v1 + 0.5, D)
	# Ground floor: glass behind a colonnade of square piers carrying the floors above.
	var gv0 := v0 + col
	var gnd_ops: Array = []
	var bays := maxi(4, roundi((u1 - u0) / 4.8))
	var bw := (u1 - u0) / float(bays)
	for i in bays:
		var c := (float(i) + 0.5) * bw
		var door := absf(u0 + c - cu) < bw * 0.6
		gnd_ops.append({"a0": c - bw * 0.5 + 0.2, "a1": c + bw * 0.5 - 0.2, "y0": 0.0 if door else 0.5, "y1": 3.6, "glass": "glass_door" if door else "glass_office", "depth": 0.08, "room_h": 4.2})
	var gf := _faces(u0, u1, gv0, v1)
	g.wall("concrete", gf[0][0], gf[0][1], gf[0][2], 0.0, u1 - u0, 0.0, 4.6, gnd_ops, "anodized")
	for f in [1, 3]:
		var sops := _row(v1 - gv0, maxi(1, int((v1 - gv0) / 3.0)), 1.8, 0.9, 3.6, 1.2, false, "glass_office", 0.15)
		g.wall("concrete", gf[f][0], gf[f][1], gf[f][2], 0.0, v1 - gv0, 0.0, 4.6, sops, "concrete")
	g.wall("concrete", gf[2][0], gf[2][1], gf[2][2], 0.0, u1 - u0, 0.0, 4.6, _row(u1 - u0, bays, 2.0, 0.9, 3.6, 1.2, false, "glass_office", 0.15), "concrete")
	g.box("soffit_white", u0, u1, 4.5, 4.6, v0, gv0)
	for i in bays + 1:
		var pu := u0 + float(i) * bw
		g.box("concrete", pu - 0.4, pu + 0.4, 0.0, 4.6, v0 + 0.1, v0 + 0.9)
		if i < bays:
			g.box("lamp_cool", pu + bw * 0.5 - 0.3, pu + bw * 0.5 + 0.3, 4.48, 4.5, v0 + 1.2, v0 + 1.8)
	g.box("concrete_pale", u0, u1, 0.0, 0.04, v0, gv0)
	# Upper floors: ribbon windows between proud spandrels, vertical fins of the sun screen.
	var up := _faces(u0, u1, v0, v1)
	for k in range(1, storeys):
		var y := 4.6 + 3.8 * float(k - 1)
		var rib := [{"a0": 0.6, "a1": u1 - u0 - 0.6, "y0": y + 0.95, "y1": y + 3.2, "glass": "glass_office", "depth": 0.25, "floor": y, "room_h": 3.5}]
		var ribs := [{"a0": 0.6, "a1": v1 - v0 - 0.6, "y0": y + 0.95, "y1": y + 3.2, "glass": "glass_office", "depth": 0.25, "floor": y, "room_h": 3.5}]
		g.wall("concrete", up[0][0], up[0][1], up[0][2], 0.0, u1 - u0, y, y + 3.8, rib, "concrete")
		g.wall("concrete", up[1][0], up[1][1], up[1][2], 0.0, v1 - v0, y, y + 3.8, ribs, "concrete")
		g.wall("concrete", up[2][0], up[2][1], up[2][2], 0.0, u1 - u0, y, y + 3.8, rib, "concrete")
		g.wall("concrete", up[3][0], up[3][1], up[3][2], 0.0, v1 - v0, y, y + 3.8, ribs, "concrete")
		# Mullions in the ribbon.
		var mu := u0 + 0.6
		while mu < u1 - 0.6:
			g.box("anodized", mu - 0.03, mu + 0.03, y + 0.95, y + 3.2, v0 + 0.2, v0 + 0.25)
			mu += 1.5
	var fin := u0 + 0.6
	while fin <= u1 - 0.55:
		g.box("concrete_pale", fin - 0.08, fin + 0.08, 4.6, h - 0.1, v0 - 0.85, v0)
		fin += 1.2
	_flat_roof(g, "concrete", "concrete_pale", u0, u1, v0, v1, h, 0.9)
	g.box("plant", cu - 3.0, cu + 3.0, h, h + 1.8, v0 + 3.0, v0 + 6.0)
	g.box("plant", u0 + 3.0, u0 + 5.0, h, h + 1.3, v1 - 4.0, v1 - 2.0)
	g.box("steel_dark", cu - 2.0, cu + 2.0, h + 1.8, h + 1.95, v0 + 3.6, v0 + 5.4)
	# The name on the band over the colonnade, the services under it.
	res.texts.append(["%s CENTER" % CivicBuildings.SERVICES, 0.55, Color(0.18, 0.2, 0.22), g.P(cu, 5.2, v0 - 0.88), 160.0])
	res.texts.append(["PERMITS - WATER & POWER - PARKING - SANITATION", 0.2, Color(0.2, 0.22, 0.24), g.P(cu, 4.85, v0 - 0.88), 70.0])
	res.texts.append([String(s.name), 0.28, Color(0.94, 0.94, 0.9), g.P(4.0, 1.25, 1.18), 70.0])
	# The forecourt: three flags, a monument sign, planters, benches, a bus-shelter-like canopy
	# over the queue at the door.
	for i in 3:
		_flagpole(g, res, 2.5 + float(i) * 1.8, 2.6, 10.5 - 0.5 * float(i % 2), 0 if i == 1 else 1)
	g.box("concrete", 1.6, 6.4, 0.0, 1.6, 1.0, 1.4)
	g.box("anodized", 1.7, 6.3, 0.95, 1.5, 0.98, 1.0)
	for pu: float in [cu - 6.0, cu + 6.0]:
		g.box("concrete_pale", pu - 2.0, pu + 2.0, 0.0, 0.6, v0 - 3.4, v0 - 1.8)
		g.box("shrub", pu - 1.85, pu + 1.85, 0.6, 1.0, v0 - 3.25, v0 - 1.95)
		_bench(g, res, pu, v0 - 4.3)
	_tree(g, res, 2.4, v0 * 0.5 + 1.2, false)
	_tree(g, res, L - 2.4, v0 * 0.5, false)
	_lamp_post(g, res, cu - 3.0, 1.0)
	_lamp_post(g, res, cu + 3.0, 1.0)
	if lay.park:
		_car_park(g, res, 1.0, L - 1.0, D - 6.6, true, 0.75, [s.builder, "svc_park"])
	res.lamps.append([g.P(cu, 3.9, v0 + 1.4), 14.0, Color(0.9, 0.95, 1.0)])
	for i in 3:
		res.people.append([_ring(g, 1.0, L - 1.0, 0.9, v0 + col - 0.4), i + 1, false])


# --- The community center ------------------------------------------------------------------------

static func _community(g: CivicGeo, s: Dictionary, lay: Dictionary, res: Dictionary) -> void:
	var L: float = lay.L
	var D: float = lay.D
	var v0: float = lay.bv0
	var v1: float = lay.bv1
	var h: float = lay.h
	var hall: Array = lay.hall
	var wing: Array = lay.wing
	var hu0: float = hall[0]
	var hu1: float = hall[1]
	var wu0: float = wing[0]
	var wu1: float = wing[1]
	var wd: float = lay.wing_d
	var tint: Color = lay.tint
	g.colors["stucco_paint"] = tint
	_ground(g, "lawn", 0.0, L, 0.0, D)
	g.box("concrete_pale", 0.5, L - 0.5, 0.0, 0.05, v0 - 4.5, v0)
	g.box("concrete_pale", minf(hu1, wu1), maxf(hu0, wu0), 0.0, 0.05, v0, v0 + wd)
	# The hall: tall walls with a clerestory band, a bowstring roof (or a low gable) of standing
	# seam metal on its long span.
	var hops := [{"a0": 1.2, "a1": hu1 - hu0 - 1.2, "y0": 5.4, "y1": 7.3, "glass": "glass_hall", "depth": 0.2, "room_h": 7.8},
		{"a0": (hu1 - hu0) * 0.5 - 1.4, "a1": (hu1 - hu0) * 0.5 + 1.4, "y0": 0.0, "y1": 2.8, "glass": "glass_door", "depth": 0.2}]
	var sops := [{"a0": 1.2, "a1": v1 - v0 - 1.2, "y0": 5.4, "y1": 7.3, "glass": "glass_hall", "depth": 0.2, "room_h": 7.8}]
	_box_walls(g, "stucco_paint", "stucco_paint", hu0, hu1, v0, v1, 0.0, h, [hops, sops, [], sops])
	g.box("concrete", hu0 - 0.05, hu1 + 0.05, 0.0, 0.6, v0 - 0.05, v1 + 0.05)
	# Reveal lines in the stucco (control joints) and a contrasting band under the clerestory.
	var accent := Color(0.12, 0.30, 0.38) if int(s.get("variant", 0)) % 2 == 0 else Color(0.55, 0.18, 0.12)
	g.colors["accent"] = accent
	g.box("accent", hu0 - 0.06, hu1 + 0.06, 4.7, 5.2, v0 - 0.06, v1 + 0.06)
	var ju := hu0 + 3.0
	while ju < hu1 - 1.0:
		g.box("dark", ju - 0.02, ju + 0.02, 0.6, 4.7, v0 - 0.015, v0)
		ju += 3.0
	res.texts.append(["GYM", 0.9, Color(0.96, 0.95, 0.9), g.P((hu0 + hu1) * 0.5, 3.6, v0 - 0.02), 120.0])
	if lay.bowstring:
		var segs := 12
		var rise := 2.4
		for k in segs:
			var t0 := float(k) / float(segs)
			var t1 := float(k + 1) / float(segs)
			var ua := lerpf(hu0 - 0.5, hu1 + 0.5, t0)
			var ub := lerpf(hu0 - 0.5, hu1 + 0.5, t1)
			var ya := h + rise * 4.0 * t0 * (1.0 - t0)
			var yb := h + rise * 4.0 * t1 * (1.0 - t1)
			var nn := Vector3(-(yb - ya), ub - ua, 0.0).normalized()
			var span := ub - ua
			g.tri_uv("seam", nn, Vector3(ua, ya, v0 - 0.6), Vector3(ub, yb, v0 - 0.6), Vector3(ub, yb, v1 + 0.6), Vector2(0, t0 * 20.0), Vector2(0, t1 * 20.0), Vector2(v1 - v0 + 1.2, t1 * 20.0))
			g.tri_uv("seam", nn, Vector3(ua, ya, v0 - 0.6), Vector3(ub, yb, v1 + 0.6), Vector3(ua, ya, v1 + 0.6), Vector2(0, t0 * 20.0), Vector2(v1 - v0 + 1.2, t1 * 20.0), Vector2(v1 - v0 + 1.2, t0 * 20.0))
			g.quad("soffit_white", -nn, Vector3(ua, ya - 0.1, v0 - 0.6), Vector3(ub, yb - 0.1, v0 - 0.6), Vector3(ub, yb - 0.1, v1 + 0.6), Vector3(ua, ya - 0.1, v1 + 0.6))
			var ca := clampf(ua, hu0, hu1)
			var cb := clampf(ub, hu0, hu1)
			if cb > ca:
				var yca := h + rise * 4.0 * inverse_lerp(hu0 - 0.5, hu1 + 0.5, ca) * (1.0 - inverse_lerp(hu0 - 0.5, hu1 + 0.5, ca))
				var ycb := h + rise * 4.0 * inverse_lerp(hu0 - 0.5, hu1 + 0.5, cb) * (1.0 - inverse_lerp(hu0 - 0.5, hu1 + 0.5, cb))
				for ev: Array in [[v0, -1.0], [v1, 1.0]]:
					g.quad("stucco_paint", Vector3(0, 0, ev[1]), Vector3(ca, h, ev[0]), Vector3(cb, h, ev[0]), Vector3(cb, ycb - 0.1, ev[0]), Vector3(ca, yca - 0.1, ev[0]))
			g.box("fascia_white", minf(ua, ub), maxf(ua, ub), minf(ya, yb) - 0.2, maxf(ya, yb), v0 - 0.66, v0 - 0.6)
	else:
		g.gable("seam", "stucco_paint", "soffit_white", hu0, hu1, v0, v1, h, 0.18, 0.6, false)
	# The wing: classrooms and offices, punched windows, a flat roof with a parapet.
	if wu1 - wu0 > 6.0:
		var wv1 := v0 + wd
		var wops := _row(wu1 - wu0, maxi(2, int((wu1 - wu0) / 3.2)), 1.8, 0.9, 3.0, 1.2, false, "glass_office", 0.2)
		var wsops := _row(wd, maxi(1, int(wd / 3.4)), 1.8, 0.9, 3.0, 1.2, false, "glass_office", 0.2)
		_box_walls(g, "stucco_paint", "stucco_paint", wu0, wu1, v0, wv1, 0.0, 4.2, [wops, wsops, wops, wsops], "steel_dark", Vector2(0.9, 1.05))
		_flat_roof(g, "stucco_paint", "concrete_pale", wu0, wu1, v0, wv1, 4.2, 0.6)
		g.box("plant", (wu0 + wu1) * 0.5 - 1.2, (wu0 + wu1) * 0.5 + 1.2, 4.2, 5.4, v0 + 3.0, v0 + 5.0)
		res.texts.append(["%s COMMUNITY CENTER" % String(s.name), 0.34 if wu1 - wu0 > 14.0 else 0.24, Color(0.96, 0.95, 0.9), g.P((wu0 + wu1) * 0.5, 4.45, v0 - 0.02), 120.0])
	# The entry canopy across the gap between hall and wing, on steel columns.
	var gu0 := minf(hu1, wu1)
	var gu1 := maxf(hu0, wu0)
	if gu1 > gu0:
		g.box("fascia_white", gu0 - 0.4, gu1 + 0.4, 3.6, 3.9, v0 - 4.0, v0 + wd * 0.5)
		for cu2: float in [gu0 + 0.3, gu1 - 0.3]:
			g.cyl("steel", Vector3(cu2, 0.0, v0 - 3.6), 0.1, 3.6, 8)
		g.box("lamp_warm", gu0, gu1, 3.58, 3.6, v0 - 3.6, v0 - 0.4)
		res.lamps.append([g.P((gu0 + gu1) * 0.5, 3.2, v0 - 2.0), 12.0, Color(1.0, 0.82, 0.6)])
		res.pools.append([g.P((gu0 + gu1) * 0.5, 0.06, v0 - 2.5), 6.0, Color(1.0, 0.82, 0.6), 1.0])
	# Outdoors: picnic tables under trees, benches, a notice board, a drinking fountain.
	var pv := clampf(v0 - 2.6, 2.0, v0 - 1.0)
	for i in 2:
		var tu := (hu0 + hu1) * 0.5 + (float(i) - 0.5) * 6.0
		if tu < 1.5 or tu > L - 1.5:
			continue
		g.box("wood", tu - 1.0, tu + 1.0, 0.72, 0.78, pv - 0.4, pv + 0.4)
		for sv: float in [-0.75, 0.75]:
			g.box("wood", tu - 1.0, tu + 1.0, 0.42, 0.46, pv + sv - 0.15, pv + sv + 0.15)
		for e: float in [-0.75, 0.75]:
			g.box("steel", tu + e - 0.04, tu + e + 0.04, 0.0, 0.74, pv - 0.8, pv + 0.8)
	g.box("wood_dark", 2.0, 4.0, 0.9, 2.1, 1.2, 1.3)
	g.box("cork", 2.1, 3.9, 1.0, 2.0, 1.17, 1.2)
	g.beam("wood_dark", Vector3(2.0, 0.0, 1.25), Vector3(2.0, 2.2, 1.25), 0.1)
	g.beam("wood_dark", Vector3(4.0, 0.0, 1.25), Vector3(4.0, 2.2, 1.25), 0.1)
	g.cyl("steel", Vector3(L - 3.0, 0.0, 1.4), 0.18, 0.9, 8)
	_bench(g, res, (wu0 + wu1) * 0.5, v0 - 2.0)
	_tree(g, res, 2.4, v0 * 0.55, false)
	_tree(g, res, L - 2.4, v0 * 0.55, false)
	_lamp_post(g, res, L * 0.5, 1.0)
	res.people.append([_ring(g, 1.0, L - 1.0, 0.9, v0 - 0.6), 1, false])
	res.people.append([_ring(g, 1.0, L - 1.0, 0.9, v0 - 0.6), 2, false])
	res.people.append([_ring(g, 1.0, L - 1.0, 0.9, v0 - 0.6), 3, false])


# --- Collision, lettering, flags, trucks, night --------------------------------------------------

static func _collision(node: Node3D, s: Dictionary, lay: Dictionary, sx: float, res: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	for m: Dictionary in masses(s, lay):
		if not bool(m.get("solid", true)):
			continue
		var c: Vector3 = m.c
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = m.size
		cs.shape = bs
		cs.position = Vector3(c.x * sx, c.y, c.z)
		body.add_child(cs)
	for t: Transform3D in res.trucks:
		var cs2 := CollisionShape3D.new()
		var b2 := BoxShape3D.new()
		b2.size = Vector3(TRUCK.x, TRUCK.y, TRUCK.z)
		cs2.shape = b2
		cs2.transform = Transform3D(t.basis, t.origin + Vector3(0.0, TRUCK.y * 0.5, 0.0))
		body.add_child(cs2)


static func _texts(node: Node3D, _g: CivicGeo, res: Dictionary) -> void:
	if OS.has_feature("web"):
		return
	for it: Array in res.texts:
		var mi := MeshInstance3D.new()
		mi.mesh = BigVehicles.text_mesh(it[0], it[1], it[2])
		mi.position = it[3]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = it[4]
		node.add_child(mi)


static func _flags(node: Node3D, _g: CivicGeo, res: Dictionary) -> void:
	for f: Array in res.flags:
		var mi := MeshInstance3D.new()
		mi.name = "Flag"
		mi.mesh = flag_mesh()
		mi.material_override = flag_material(int(f[1]))
		var p: Vector3 = f[0]
		mi.position = p + Vector3(0.05, -FLAG_SIZE.y, 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 260.0
		node.add_child(mi)


static func _trucks(node: Node3D, _g: CivicGeo, res: Dictionary) -> void:
	var list: Array = res.trucks
	var van := mail_truck()
	if list.is_empty() or van.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = van.mesh
	mm.instance_count = list.size()
	var size: Vector3 = van.size
	for i in list.size():
		var t: Transform3D = list[i]
		mm.set_instance_transform(i, t * Transform3D(Basis(), van.offset))
		if OS.has_feature("web"):
			continue
		# The service's name on both flanks, on the band.
		for side: float in [-1.0, 1.0]:
			var tm := MeshInstance3D.new()
			tm.mesh = BigVehicles.text_mesh(CivicBuildings.POST, 0.2, Color(0.97, 0.96, 0.92))
			tm.transform = t * Transform3D(Basis(Vector3.UP, side * PI * 0.5), Vector3(side * (size.x * 0.5 + 0.03), size.y * 0.58, 0.2))
			tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tm.visibility_range_end = 45.0
			node.add_child(tm)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MailTrucks"
	mmi.multimesh = mm
	mmi.visibility_range_end = TRUCK_RANGE
	node.add_child(mmi)


static func _night(node: Node3D, _g: CivicGeo, res: Dictionary) -> void:
	for p: Array in res.pools:
		var mi := MeshInstance3D.new()
		mi.mesh = PropFactory.light_pool(p[2], p[3])
		var r: float = p[1]
		mi.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(r, 1.0, r)), p[0])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 220.0
		node.add_child(mi)
	if OS.has_feature("web"):
		return
	for l: Array in res.lamps:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.omni_range = l[1]
		o.light_color = l[2]
		o.light_energy = 0.0
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 110.0
		o.distance_fade_length = 40.0
		# Hidden as DayNight hides a dark lamp, so its lamp tick shows it after dark.
		o.visible = false
		o.set_meta("dark_hidden", true)
		o.add_to_group("lamp_light")
		node.add_child(o)


# --- The flag and the mail truck -----------------------------------------------------------------

## A flag: a 16 x 8 grid FLAG_SIZE across, hoist at x 0, flying toward +x; UV 0..1 (the shader
## waves it and paints it).
static func flag_mesh() -> Mesh:
	if _mesh_cache.has("flag"):
		return _mesh_cache.flag
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 16
	var ny := 8
	for j in ny:
		for i in nx:
			var q := [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]
			for c: Vector2 in q:
				var uv := Vector2(c.x / float(nx), c.y / float(ny))
				st.set_normal(Vector3.BACK)
				st.set_uv(uv)
				st.add_vertex(Vector3(uv.x * FLAG_SIZE.x, uv.y * FLAG_SIZE.y, 0.0))
	var mesh := st.commit()
	_mesh_cache.flag = mesh
	return mesh


static func flag_material(kind: int) -> ShaderMaterial:
	var key := "flag_%d" % kind
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/civic_flag.gdshader")
	m.set_shader_parameter("kind", kind)
	_mats[key] = m
	return m


## The mail truck: the Blender-built high-roof panel van (Vehicle's VAN body, its ~8k-triangle far
## twin, as the police stations park their cruisers) in the invented CONTINENTAL POST livery: a
## warm white body with a deep teal belt band (car_paint's fleet band, stripe_mode 3) - not any
## real postal service's colours - and the name on both flanks (_trucks()). {"mesh", "offset"
## (the model's origin from a van standing on y 0, nose -Z), "size"} or {} without the model.
static func mail_truck() -> Dictionary:
	if _mesh_cache.has("truck"):
		return _mesh_cache.truck
	var out := {}
	_mesh_cache.truck = out
	var path: String = Vehicle.BODY_MODELS.get(Vehicle.BodyType.VAN, "")
	if path == "" or not ResourceLoader.exists(path):
		return out
	var inst := (load(path) as PackedScene).instantiate()
	var far: ArrayMesh = null
	var near_box := AABB()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.name).ends_with("_far"):
			far = m.mesh as ArrayMesh
		elif m.mesh:
			near_box = m.mesh.get_aabb()
	inst.free()
	if far == null or far.get_surface_count() == 0:
		return out
	var mesh := far.duplicate() as ArrayMesh
	for si in mesh.get_surface_count():
		var src := mesh.surface_get_material(si) as StandardMaterial3D
		if src == null:
			continue
		if String(src.resource_name).begins_with("paint"):
			mesh.surface_set_material(si, _truck_paint(src, near_box if near_box.size != Vector3.ZERO else far.get_aabb()))
		else:
			var pm := Vehicle._part_material(src)
			if pm != null:
				mesh.surface_set_material(si, pm)
	var box := far.get_aabb()
	out.mesh = mesh
	out.offset = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	out.size = box.size
	return out


## The livery's paint: car_paint with a fleet belt band.
static func _truck_paint(src: StandardMaterial3D, box: AABB) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Vehicle.PAINT_SHADER
	mat.set_shader_parameter("albedo_tex", src.albedo_texture)
	mat.set_shader_parameter("paint", TRUCK_WHITE)
	if src.normal_texture:
		mat.set_shader_parameter("normal_tex", src.normal_texture)
		mat.set_shader_parameter("has_normal", true)
	var f: Dictionary = Vehicle.FINISHES[Vehicle.Finish.GLOSS]
	mat.set_shader_parameter("paint_metallic", f.metallic)
	mat.set_shader_parameter("paint_roughness", f.roughness)
	mat.set_shader_parameter("clearcoat_amount", f.clearcoat)
	mat.set_shader_parameter("clearcoat_roughness_value", f.cc_rough)
	mat.set_shader_parameter("flake_strength", 0.0)
	mat.set_shader_parameter("stripe_color", TRUCK_TEAL)
	mat.set_shader_parameter("stripe_mode", 3)
	mat.set_shader_parameter("stripe_height", 0.36)
	mat.set_shader_parameter("stripe_width", 0.05)
	mat.set_shader_parameter("body_min", box.position)
	mat.set_shader_parameter("body_size", box.size)
	mat.set_shader_parameter("length_is_x", box.size.x >= box.size.z)
	return mat


# --- Materials -----------------------------------------------------------------------------------

static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"stucco", "stucco_paint":
			var sm := (PropFactory.pbr("plaster_white", 2.2, Color.WHITE, 1.0, true) as StandardMaterial3D).duplicate() as StandardMaterial3D
			sm.vertex_color_is_srgb = true
			m = sm
		"stucco_white":
			m = PropFactory.pbr("plaster_white", 2.2, Color(0.95, 0.94, 0.9))
		"stucco_cream":
			m = PropFactory.pbr("plaster_beige", 2.4, Color(0.98, 0.94, 0.84))
		"brick":
			m = PropFactory.pbr("brick_red", 2.0, Color(0.92, 0.88, 0.86))
		"cast_stone", "terrazzo":
			m = PropFactory.pbr("concrete", 2.0, Color(0.88, 0.84, 0.74) if key == "cast_stone" else Color(0.86, 0.82, 0.76))
		"granite":
			m = PropFactory.pbr("concrete_layers", 2.0, Color(0.62, 0.6, 0.58))
		"stone":
			m = PropFactory.pbr("brick", 1.6, Color(0.82, 0.74, 0.62))
		"concrete":
			m = PropFactory.pbr("concrete", 3.0, CONCRETE)
		"concrete_pale":
			m = PropFactory.pbr("concrete", 3.0, Color(0.9, 0.89, 0.86))
		"pavers":
			m = PropFactory.pbr("pavers", 2.0, Color(0.86, 0.72, 0.62))
		"asphalt":
			m = PropFactory.pbr("asphalt", 4.0, Color(0.78, 0.78, 0.78))
		"lawn":
			m = PropFactory.lawn(Color(0.42, 0.55, 0.26), 41, 0.3)
		"clay":
			m = HouseKit.material("h_roof")
		"seam":
			var sm2 := StandardMaterial3D.new()
			sm2.albedo_color = Color(0.62, 0.64, 0.66)
			sm2.metallic = 0.55
			sm2.roughness = 0.4
			sm2.vertex_color_use_as_albedo = true
			m = sm2
		"terracotta":
			m = PropFactory.material(Color(0.66, 0.34, 0.22), 0.8)
		"accent":
			var am := StandardMaterial3D.new()
			am.vertex_color_use_as_albedo = true
			am.vertex_color_is_srgb = true
			am.roughness = 0.6
			m = am
		"tile_blue":
			m = PropFactory.material(Color(0.12, 0.30, 0.52), 0.35)
		"soffit_wood", "door_oak", "wood_dark":
			m = PropFactory.pbr("planks", 1.2, {"soffit_wood": Color(0.52, 0.36, 0.24), "door_oak": Color(0.46, 0.30, 0.18), "wood_dark": Color(0.30, 0.20, 0.13)}[key])
		"wood":
			m = PropFactory.pbr("planks", 1.2, Color(0.62, 0.48, 0.34))
		"door_panel":
			m = PropFactory.material(Color(0.34, 0.22, 0.13), 0.5)
		"soffit_white", "fascia_white", "paint_white":
			m = PropFactory.material(Color(0.93, 0.93, 0.9), 0.6)
		"plant":
			m = PropFactory.material(Color(0.72, 0.73, 0.72), 0.6)
		"roof":
			m = PropFactory.material(Color(0.62, 0.62, 0.6), 0.9)
		"shrub":
			m = PropFactory.material(Color(0.16, 0.28, 0.12), 0.95)
		"cork":
			m = PropFactory.material(Color(0.62, 0.46, 0.3), 0.95)
		"dark":
			m = PropFactory.material(Color(0.05, 0.05, 0.05), 0.95)
		"rubber", "tyre", "trim_black":
			m = PropFactory.material(Color(0.04, 0.04, 0.045), 0.8 if key != "trim_black" else 0.55)
		"paint_yellow":
			m = PropFactory.material(Color(0.9, 0.72, 0.08), 0.6)
		"box_blue":
			m = PropFactory.material(Color(0.07, 0.17, 0.42), 0.45)
		"box_red":
			m = PropFactory.material(Color(0.62, 0.06, 0.06), 0.5)
		"box_green":
			m = PropFactory.material(Color(0.12, 0.26, 0.18), 0.5)
		"rollup":
			m = PropFactory.pbr("metal_corrugated", 1.0, Color(0.74, 0.75, 0.76))
		"chain":
			m = LotFill.chain_link_panel().surface_get_material(0)
		"breeze":
			var br := ShaderMaterial.new()
			br.shader = load("res://shaders/house_breeze.gdshader")
			m = br
		"steel", "steel_dark", "iron", "brass", "bronze", "gold", "anodized", "anodized_gold", "chrome", "copper", "pole":
			var mm := StandardMaterial3D.new()
			mm.albedo_color = {"steel": Color(0.62, 0.63, 0.64), "steel_dark": Color(0.16, 0.17, 0.17), "iron": Color(0.07, 0.07, 0.07),
				"brass": Color(0.80, 0.62, 0.30), "bronze": Color(0.36, 0.25, 0.16), "gold": Color(0.85, 0.66, 0.25),
				"anodized": Color(0.66, 0.67, 0.68), "anodized_gold": Color(0.78, 0.62, 0.32), "chrome": Color(0.8, 0.8, 0.82),
				"copper": Color(0.30, 0.52, 0.44), "pole": Color(0.88, 0.88, 0.86)}[key]
			mm.metallic = 0.25 if key == "iron" or key == "pole" else 0.75
			mm.roughness = 0.5 if key == "iron" else (0.25 if key == "chrome" or key == "gold" or key == "brass" else 0.4)
			m = mm
		"glass_lib", "glass_post", "glass_office", "glass_hall", "glass_door":
			var cg := ShaderMaterial.new()
			cg.shader = load("res://shaders/civic_glass.gdshader")
			cg.set_shader_parameter("room", {"glass_lib": 0, "glass_post": 1, "glass_office": 2, "glass_hall": 3, "glass_door": 4}[key])
			m = cg
		"lamp_warm", "lamp_cool", "lamp_head", "lamp_tail", "lamp_amber":
			var lm := ShaderMaterial.new()
			lm.shader = PoliceStation._lamp_shader()
			lm.set_shader_parameter("tint", {"lamp_warm": Vector3(1.0, 0.8, 0.55), "lamp_cool": Vector3(0.88, 0.94, 1.0),
				"lamp_head": Vector3(1.0, 0.97, 0.9), "lamp_tail": Vector3(0.9, 0.05, 0.03), "lamp_amber": Vector3(1.0, 0.55, 0.08)}[key])
			lm.set_shader_parameter("strength", 5.0 if key == "lamp_warm" or key == "lamp_cool" else 0.6)
			lm.set_shader_parameter("day", 0.1)
			m = lm
		_:
			m = PropFactory.material(Color(0.5, 0.5, 0.5))
	_mats[key] = m
	return m
