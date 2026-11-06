class_name TerminalCurb
extends RefCounted
## The departures kerb in front of the terminal's head house (refcam `terminal_curb`,
## tools/refcams/cameras_w7.json; docs/HANDOFF.md "The terminal's departures kerb"). Before it the
## kerb was an empty grey slab with a white line along it: the crowd bunched at the strip's two
## ends, the loop cars sat bumper to bumper and never stopped, and across the lanes the city's
## houses stood in plain view. What a real departures kerb has, built here in code:
##   - the kerb itself: a granite kerb stone with its face painted white (a loading zone), a row of
##     steel anti-ram bollards along it, large-format concrete paving on the strip (joints, wear);
##   - door pylons by every vestibule (a lit DOOR n box over the invented airlines checking in
##     there), PASSENGER LOADING ONLY plates on the kerb, benches and bin pairs against the glass,
##     a curbside check-in podium, a corral of nested luggage carts;
##   - glass vestibules in place of the old grey boxes (AirportTerminal asks vestibule());
##   - a planted median along the far side of the lanes (birds of paradise, agaves, palms), which is
##     what a terminal's road has where this one showed the street of houses behind it;
##   - travellers standing in groups with their luggage (CurbTraveller: on the phone, talking,
##     arms folded; the bags a MultiMesh at their feet, CODE-built roller cases, carry-ons and
##     duffels in muted colours) - the spots are pure (spots()), so the bags and the people agree;
##   - the loop's kerb lane stops: a share of cars pull in to the kerb, stand on their hazards for
##     a drop-off and go (loop_speed(), one hook in TrafficManager._drive_loops()), so the lane is
##     stop-and-go with gaps; a share of the loop's cars are taxis and shuttle vans (loop_car()).
## Every roll is a hash of the seed and the place; nothing else in the city moves. TERMINAL_CURB=0
## is the A/B (the kerb exactly as before).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("TERMINAL_CURB") != "0"

## The kerb line (world z) and where the strip's top is over the tarmac (Landmarks._build_dropoff()).
const KERB_Z := 624.0
const STRIP_TOP := 0.24
const X0 := -449.0
const X1 := -251.0
## The tree columns (AirportTerminal: every 30 m from the hall's west end, on z 629) and the
## vestibules (every 30 m from 15 m in, against the glass at z 636).
const COLUMN_Z := 629.0
const FRONT_Z := 636.0
const BOLLARD_STEP := 1.7
## The kerb lane's stops: a car decides at the start of each lap (hash) whether it stops, where
## along the kerb, for how long, and pulls this far toward the kerb while it stands.
const STOP_SHARE := 0.55
const STOP_T := Vector2(26.0, 238.0)
const DWELL := Vector2(9.0, 26.0)
const PULL_IN := 1.55
## The share of loop cars that are taxis and shuttle vans (loop_car()).
const TAXI_SHARE := 0.22
const SHUTTLE_SHARE := 0.12
## The shuttles' fleet bands (teal, navy, red, green, orange).
const SHUTTLE_BANDS := [Color(0.0, 0.42, 0.45), Color(0.08, 0.14, 0.38), Color(0.62, 0.08, 0.08), Color(0.10, 0.38, 0.18), Color(0.85, 0.42, 0.05)]
## Invented airlines checking in behind each door (west to east), the pylons' second line.
const AIRLINES := ["SUNCREST AIR", "GULLWING", "PALMAIRE", "CORAL SKIES", "NORTHWIND", "TERRALUZ", "HALCYON"]
## Muted luggage colours (sRGB): black and charcoal most, then navy, grey, silver, the odd colour.
const BAG_COLORS := [Color(0.07, 0.07, 0.08), Color(0.08, 0.08, 0.09), Color(0.16, 0.16, 0.18), Color(0.12, 0.15, 0.24),
	Color(0.42, 0.43, 0.45), Color(0.66, 0.66, 0.67), Color(0.45, 0.10, 0.10), Color(0.12, 0.30, 0.28), Color(0.55, 0.40, 0.26),
	Color(0.07, 0.07, 0.08), Color(0.10, 0.10, 0.11), Color(0.20, 0.32, 0.52), Color(0.70, 0.55, 0.20), Color(0.30, 0.18, 0.35)]

static var _meshes: Dictionary = {}


static func _h(parts: Array) -> int:
	return absi(hash(parts))


static func _r(parts: Array) -> float:
	return float(_h(parts) % 100000) / 100000.0


static func column_xs() -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	var x := Airport.HEAD_HOUSE.position.x
	while x <= Airport.HEAD_HOUSE.end.x + 0.5:
		xs.append(x)
		x += 30.0
	return xs


static func door_xs() -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	var hh := Airport.HEAD_HOUSE
	var x := hh.position.x + 15.0
	while x < hh.end.x - 10.0:
		xs.append(x)
		x += 30.0
	return xs


# --- Where people stand -------------------------------------------------------------------------

## The travellers' spots (pure): [{p: Vector2 world xz, yaw, seed, group (a Vector2 centre), bags:
## [[kind, offset Vector2 world, yaw, colour index]]}]. Groups of one to four along the kerb (waiting
## for a ride or just dropped off, facing the lanes), in front of the doors (going in) and along the
## walk, clear of the columns, the vestibules, the pylons and the furniture.
static func spots(seed_value: int) -> Array:
	var out: Array = []
	var taken: Array[Vector2] = []
	var cols := column_xs()
	var doors := door_xs()
	for bay in range(-1, cols.size()):
		var bx0 := cols[0] - 8.0 if bay < 0 else cols[bay]
		var bx1 := cols[0] if bay < 0 else (cols[bay] + 30.0)
		bx1 = minf(bx1, X1)
		if bx1 - bx0 < 4.0:
			continue
		var n := 3 + _h([seed_value, "tc_groups", bay]) % 3
		for gi in n:
			var key := [seed_value, "tc_group", bay, gi]
			var where := _r(key + ["where"])
			var c := Vector2(lerpf(bx0 + 1.5, bx1 - 1.5, _r(key + ["x"])), 0.0)
			var face := 0.0
			if where < 0.5:
				# At the kerb, behind the bollards, facing the lanes.
				c.y = 625.7 + 0.6 * _r(key + ["z"])
				face = (_r(key + ["f"]) - 0.5) * 1.2
			elif where < 0.75:
				# By a door, about to go in (their backs to the lanes).
				var d := doors[_h(key + ["door"]) % doors.size()]
				c = Vector2(d + (_r(key + ["x"]) - 0.5) * 9.0, 631.6 + 0.8 * _r(key + ["z"]))
				face = PI + (_r(key + ["f"]) - 0.5) * 1.4
			else:
				# Along the walk, stopped to sort something out.
				c.y = 627.6 + 2.8 * _r(key + ["z"])
				face = PI * 0.5 * (1.0 if _r(key + ["f"]) < 0.5 else -1.0) + (_r(key + ["g"]) - 0.5) * 1.0
			if not _clear(c, 1.6, taken):
				continue
			var size := 1 + _h(key + ["n"]) % 3
			if _r(key + ["big"]) < 0.15:
				size = 4
			var side := Vector2(cos(face), -sin(face))
			var fwd := Vector2(-sin(face), -cos(face))
			for k in size:
				var off := side * ((float(k) - float(size - 1) * 0.5) * 0.85) + fwd * ((_r(key + ["ff", k]) - 0.5) * 0.5)
				var p := c + off
				if not _clear(p, 0.55, taken):
					continue
				taken.append(p)
				var yaw := face + (_r(key + ["fy", k]) - 0.5) * 0.9
				# Facing a mate a little in a group (they are talking).
				if size > 1:
					yaw = lerp_angle(yaw, atan2(-(c - p).x, -(c - p).y), 0.35)
				var bags: Array = []
				var nb := 1 + _h(key + ["nb", k]) % 2
				var sv := Vector2(cos(yaw), -sin(yaw))
				var fv := Vector2(-sin(yaw), -cos(yaw))
				for b in nb:
					var kind := _h(key + ["bk", k, b]) % 4
					var bo := sv * (0.42 + 0.12 * float(b)) * (1.0 if b == 0 else -1.0) + fv * (0.05 + 0.15 * _r(key + ["bo", k, b]))
					bags.append([kind, p + bo, yaw + (_r(key + ["by", k, b]) - 0.5) * 0.8, _h(key + ["bc", k, b]) % BAG_COLORS.size()])
				out.append({"p": p, "yaw": yaw, "seed": _h(key + ["seed", k]), "group": c, "bags": bags})
	return out


## True when `p` keeps `r` metres off everything standing on the strip (and the other people).
static func _clear(p: Vector2, r: float, taken: Array[Vector2]) -> bool:
	if p.x < X0 or p.x > X1 or p.y < 625.2 or p.y > 633.0:
		return false
	for cx in column_xs():
		if Vector2(cx, COLUMN_Z).distance_to(p) < 0.9 + r * 0.5:
			return false
	for dx in door_xs():
		# The pylon, the podium and the vestibule's front.
		if Vector2(dx + 2.6, 627.4).distance_to(p) < 0.6 + r * 0.5:
			return false
		if absf(p.x - dx) < 4.2 and p.y > 632.4:
			return false
	for f: Rect2 in furniture_rects():
		if f.grow(r * 0.4).has_point(p):
			return false
	for t in taken:
		if t.distance_to(p) < r * 0.7:
			return false
	return true


## The fixed furniture's footprints (world xz), so people and bags keep off them.
static func furniture_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for cx in column_xs():
		if cx < X0 or cx > X1:
			continue
		out.append(Rect2(cx - 1.3, 633.9, 2.6, 1.3))
	out.append(Rect2(-366.0, 626.0, 7.2, 1.3))
	out.append(Rect2(-393.0, 626.4, 2.0, 1.0))
	return out


# --- The build ------------------------------------------------------------------------------------

## The kerb's material for the strip Landmarks lays: large concrete paving with joints.
static func paving() -> Material:
	return LandmarkMats.paving("concrete", 4.0, Color(0.84, 0.83, 0.80), 6271, 1.5, 0.3)


## Called at the end of Landmarks._build_dropoff(): the kerb, the furniture, the planted median,
## the luggage. Near copy only (none of it reads from the far city).
static func build(parent: Node3D, statics: StaticBody3D, macro: MacroMap, detailed: bool) -> void:
	if not enabled or not detailed or macro == null:
		return
	var y0: float = macro.tarmac_top
	var top := y0 + STRIP_TOP
	var road: Rect2 = macro.terminal_road
	var g := LandmarkGeo.new()
	g.use("steel", LandmarkMats.plain("tc_steel", Color(0.42, 0.43, 0.45), 0.38, 0.85))
	g.use("cap", LandmarkMats.plain("tc_cap", Color(0.80, 0.81, 0.82), 0.22, 0.95))
	g.use("stone", LandmarkMats.plain("tc_stone", Color(0.70, 0.69, 0.66), 0.75, 0.0))
	g.use("paint", LandmarkMats.plain("tc_paint", Color(0.92, 0.92, 0.90), 0.6, 0.0))
	g.use("dark", LandmarkMats.plain("tc_dark", Color(0.10, 0.11, 0.12), 0.45, 0.4))
	g.use("wood", LandmarkMats.plain("tc_wood", Color(0.55, 0.38, 0.24), 0.6, 0.0))
	g.use("lit", LandmarkMats.glow("tc_lit", Color(0.94, 0.96, 1.0)))
	g.use("mulch", LandmarkMats.plain("tc_mulch", Color(0.16, 0.12, 0.09), 0.95, 0.0))
	var collide := statics != null
	# The kerb stone along the strip's edge, its face painted white, and the gutter's darker band.
	g.box("stone", Vector3((X0 + X1) * 0.5 - 0.5, (y0 + 0.06 + top + 0.012) * 0.5, KERB_Z + 0.155), Vector3(X1 - X0 + 22.0, top + 0.012 - y0 - 0.06, 0.32), Color.WHITE, Basis(), 0.02)
	g.box("paint", Vector3((X0 + X1) * 0.5 - 0.5, (y0 + 0.06 + top) * 0.5, KERB_Z - 0.012), Vector3(X1 - X0 + 22.0, top - y0 - 0.06 - 0.01, 0.012), Color.WHITE)
	# The bollards: steel, a polished cap, a gap at each door's crossing to the cars.
	var bx := X0 + 0.5
	while bx < X1:
		var near_door := false
		for dx in door_xs():
			if absf(bx - dx) < 0.8:
				near_door = true
		if not near_door:
			g.cylinder("steel", Vector3(bx, top, KERB_Z + 0.55), 0.115, 0.92, 12, Color.WHITE, -1.0, collide, false)
			g.cylinder("cap", Vector3(bx, top + 0.92, KERB_Z + 0.55), 0.118, 0.06, 12, Color.WHITE, 0.07)
			g.cylinder("dark", Vector3(bx, top + 0.70, KERB_Z + 0.55), 0.119, 0.05, 12, Color.WHITE, -1.0, false, false)
		bx += BOLLARD_STEP
	var texts: Array = []
	var plates: Array = []
	var doors := door_xs()
	for di in doors.size():
		var dx := doors[di]
		# A door pylon on the walk by each vestibule: a slim post, a lit box with the door number
		# and the airlines behind it, both faces along the kerb.
		var px := dx + 2.6
		var pz := 627.4
		g.box("dark", Vector3(px, top + 1.55, pz), Vector3(0.14, 3.1, 0.14), Color.WHITE, Basis(), 0.01, collide)
		g.box("dark", Vector3(px, top + 3.55, pz), Vector3(0.22, 1.25, 1.9), Color.WHITE, Basis(), 0.03, collide)
		for s: float in [-1.0, 1.0]:
			g.box("lit", Vector3(px + 0.112 * s, top + 3.75, pz), Vector3(0.004, 0.62, 1.66), Color(0.10, 0.20, 0.42))
			var yaw := PI * 0.5 * s
			var bas := Basis(Vector3.UP, yaw)
			texts.append(["DOOR %d" % (di + 1), 0.42, Transform3D(bas, Vector3(px + 0.118 * s, top + 3.80, pz))])
			var air := "%s  " % AIRLINES[di % AIRLINES.size()]
			plates.append([air, 0.15, Transform3D(bas, Vector3(px + 0.118 * s, top + 3.17, pz))])
		# A loading-zone plate on a post at the kerb, between bollards.
		var lx := dx + 9.0
		g.box("steel", Vector3(lx, top + 1.2, KERB_Z + 0.55), Vector3(0.06, 2.4, 0.06), Color.WHITE, Basis(), 0.0, collide)
		g.box("paint", Vector3(lx, top + 2.05, KERB_Z + 0.55), Vector3(0.03, 0.62, 0.46), Color.WHITE)
		for s: float in [-1.0, 1.0]:
			var bas := Basis(Vector3.UP, PI * 0.5 * s)
			plates.append(["PASSENGER", 0.07, Transform3D(bas, Vector3(lx + 0.02 * s, top + 2.25, KERB_Z + 0.55))])
			plates.append(["LOADING", 0.07, Transform3D(bas, Vector3(lx + 0.02 * s, top + 2.15, KERB_Z + 0.55))])
			plates.append(["ONLY", 0.07, Transform3D(bas, Vector3(lx + 0.02 * s, top + 2.05, KERB_Z + 0.55))])
			plates.append(["NO PARKING", 0.06, Transform3D(bas, Vector3(lx + 0.02 * s, top + 1.88, KERB_Z + 0.55))])
	# Benches and bin pairs against the glass, between the vestibules (under each column line).
	for cx in column_xs():
		if cx < X0 or cx > X1:
			continue
		var bz := 634.55
		for leg: float in [-0.95, 0.95]:
			g.box("steel", Vector3(cx + leg, top + 0.22, bz), Vector3(0.06, 0.44, 0.5), Color.WHITE, Basis(), 0.01)
		g.box("wood", Vector3(cx, top + 0.46, bz), Vector3(2.2, 0.06, 0.5), Color.WHITE, Basis(), 0.012, collide)
		g.box("wood", Vector3(cx, top + 0.78, bz + 0.25), Vector3(2.2, 0.36, 0.05), Color.WHITE, Basis(), 0.012)
		for side: float in [-1.0, 1.0]:
			var tx: float = cx + side * 1.75
			g.cylinder("steel", Vector3(tx, top, bz + 0.05), 0.26, 0.95, 14, Color.WHITE, -1.0, collide, true)
			g.cylinder("dark", Vector3(tx, top + 0.95, bz + 0.05), 0.27, 0.04, 14, Color.WHITE)
	# Curbside check-in: a podium with its lit sign.
	g.box("dark", Vector3(-392.0, top + 0.55, 626.9), Vector3(1.4, 1.1, 0.6), Color.WHITE, Basis(), 0.03, collide)
	g.box("steel", Vector3(-392.0, top + 1.12, 626.9), Vector3(1.46, 0.04, 0.66), Color.WHITE)
	g.box("dark", Vector3(-392.0, top + 1.6, 627.18), Vector3(0.05, 0.9, 0.05), Color.WHITE)
	g.box("lit", Vector3(-392.0, top + 2.15, 627.18), Vector3(1.5, 0.32, 0.04), Color(0.92, 0.55, 0.12))
	texts.append(["CURBSIDE CHECK-IN", 0.15, Transform3D(Basis(Vector3.UP, PI), Vector3(-392.0, top + 2.15, 627.155))])
	# The far side of the lanes: a planted median, its kerb, mulch, low planting and palms.
	var mz0 := road.position.y + 0.4
	var mz1 := mz0 + 2.6
	var mx0 := road.position.x + 10.0
	var mx1 := road.end.x - 10.0
	g.box("stone", Vector3((mx0 + mx1) * 0.5, y0 + 0.2, (mz0 + mz1) * 0.5), Vector3(mx1 - mx0, 0.4, mz1 - mz0), Color.WHITE, Basis(), 0.04, collide)
	g.box("mulch", Vector3((mx0 + mx1) * 0.5, y0 + 0.41, (mz0 + mz1) * 0.5), Vector3(mx1 - mx0 - 0.3, 0.02, mz1 - mz0 - 0.3), Color.WHITE)
	g.commit(parent, "TerminalCurb")
	g.commit_collision(statics)
	var letters := MeshInstance3D.new()
	letters.name = "TerminalCurbSigns"
	letters.mesh = Airport.merged_text(texts, LandmarkMats.glow("tc_letters", Color(1.0, 1.0, 1.0)))
	letters.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(letters)
	var plate_mi := MeshInstance3D.new()
	plate_mi.name = "TerminalCurbPlates"
	plate_mi.mesh = Airport.merged_text(plates, LandmarkMats.plain("tc_plate_ink", Color(0.75, 0.08, 0.06), 0.6, 0.0))
	plate_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(plate_mi)
	# The airline line on the pylons is white on the blue (the plates above put it red: redo it).
	var airline: Array = []
	for p: Array in plates:
		if String(p[0]).contains("  "):
			airline.append(p)
	var air_mi := MeshInstance3D.new()
	air_mi.name = "TerminalCurbAirlines"
	air_mi.mesh = Airport.merged_text(airline, LandmarkMats.glow("tc_airline", Color(0.85, 0.90, 1.0)))
	air_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(air_mi)
	# Planting and luggage as batches.
	var batch := MultiMeshBatch.new()
	var mx := mx0 + 1.5
	var k := 0
	while mx < mx1 - 1.0:
		var at := Vector3(mx, y0 + 0.42, (mz0 + mz1) * 0.5 + (_r([k, "tc_mz"]) - 0.5) * 0.8)
		if k % 6 == 0:
			var v := _h([k, "tc_palm"]) % 3
			batch.add("palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, _r([k, "tc_py"]) * TAU).scaled(Vector3.ONE * (0.9 + 0.25 * _r([k, "tc_ps"]))), at))
		elif LaTrees.enabled:
			var sp: int = LaTrees.Species.BIRD_OF_PARADISE if k % 3 != 0 else LaTrees.Species.AGAVE
			var var_i := _h([k, "tc_v"]) % 2
			batch.add("la_%d_%d" % [sp, var_i], LaTrees.mesh(sp, var_i), Transform3D(Basis(Vector3.UP, _r([k, "tc_ly"]) * TAU).scaled(Vector3.ONE * (0.85 + 0.3 * _r([k, "tc_ls"]))), at))
		mx += 2.3
		k += 1
	# The luggage cart corral: a row of nested carts.
	for i in 6:
		batch.add("tc_cart", cart_mesh(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-365.4 + 1.05 * float(i), top, 626.65)))
	var nodes: Dictionary = batch.build(parent)
	for key: String in nodes:
		if key.begins_with("tc_bag") or key == "tc_cart":
			(nodes[key] as GeometryInstance3D).material_override = bag_material()
			(nodes[key] as GeometryInstance3D).visibility_range_end = 120.0


## The bags of the travellers who are there (people_steps() records them as they spawn), one
## batch under the chunk; bags with nobody beside them read as a lost-luggage alert.
static func _commit_bags(chunk: CityChunk, here: Array, top: float) -> void:
	if not is_instance_valid(chunk) or here.is_empty():
		return
	var batch := MultiMeshBatch.new()
	for s: Dictionary in here:
		for b: Array in s.bags:
			var at2: Vector2 = b[1]
			var kind: int = int(b[0])
			batch.add("tc_bag_%d" % kind, bag_mesh(kind), Transform3D(Basis(Vector3.UP, float(b[2])), Vector3(at2.x, top, at2.y)), BAG_COLORS[int(b[3])])
	var holder := Node3D.new()
	holder.name = "TerminalLuggage"
	chunk.add_child(holder)
	var nodes: Dictionary = batch.build(holder)
	for key: String in nodes:
		(nodes[key] as GeometryInstance3D).material_override = bag_material()
		(nodes[key] as GeometryInstance3D).visibility_range_end = 120.0


## The glass vestibules on the head house's front (AirportTerminal.build_head_house() calls this
## in place of its old grey boxes): a glazed box on a steel frame, a sliding door's opening in the
## middle with its leaves part open, a flat canopy over it and a lit door number.
static func vestibule(g: LandmarkGeo, x: float, front: float, y0: float, _index: int) -> void:
	var d := 3.0
	var w := 7.2
	var h := 3.4
	var z0 := front - d
	# The glazing: front either side of the doors and both ends.
	for s: float in [-1.0, 1.0]:
		var xa: float = x + s * 1.2
		var xb: float = x + s * w * 0.5
		var a := Vector3(minf(xa, xb), y0 + 0.08, z0)
		var b := Vector3(maxf(xa, xb), y0 + 0.08, z0)
		g.quad("glass", Vector3(a.x, a.y, z0), Vector3(b.x, a.y, z0), Vector3(b.x, y0 + h, z0), Vector3(a.x, y0 + h, z0), Vector3(0, 0, -1),
			Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, y0 + h), Vector2(a.x, y0 + h), Color.WHITE)
		var ex: float = x + s * w * 0.5
		g.quad("glass", Vector3(ex, y0 + 0.08, z0), Vector3(ex, y0 + 0.08, front), Vector3(ex, y0 + h, front), Vector3(ex, y0 + h, z0), Vector3(s, 0, 0),
			Vector2(z0, y0), Vector2(front, y0), Vector2(front, y0 + h), Vector2(z0, y0 + h), Color.WHITE)
	# The doorway: the lobby's dark inside, two glass leaves slid part open, a transom over them.
	g.box("dark", Vector3(x, y0 + 1.25, z0 + 0.25), Vector3(2.4, 2.5, 0.04), Color(0.45, 0.42, 0.40))
	for s: float in [-1.0, 1.0]:
		g.quad("glass", Vector3(x + s * 0.55, y0 + 0.08, z0 - 0.04), Vector3(x + s * 1.5, y0 + 0.08, z0 - 0.04), Vector3(x + s * 1.5, y0 + 2.5, z0 - 0.04), Vector3(x + s * 0.55, y0 + 2.5, z0 - 0.04), Vector3(0, 0, -1),
			Vector2(x, y0), Vector2(x + 1.0, y0), Vector2(x + 1.0, y0 + 2.5), Vector2(x, y0 + 2.5), Color.WHITE)
	g.quad("glass", Vector3(x - 1.2, y0 + 2.62, z0), Vector3(x + 1.2, y0 + 2.62, z0), Vector3(x + 1.2, y0 + h, z0), Vector3(x - 1.2, y0 + h, z0), Vector3(0, 0, -1),
		Vector2(x - 1.2, y0 + 2.6), Vector2(x + 1.2, y0 + 2.6), Vector2(x + 1.2, y0 + h), Vector2(x - 1.2, y0 + h), Color.WHITE)
	# The steel frame: posts at the corners and either side of the doors, the transom bar, sills.
	var steel := Color(0.70, 0.71, 0.73)
	for px: float in [x - w * 0.5, x - 1.2, x + 1.2, x + w * 0.5]:
		g.box("metal", Vector3(px, y0 + h * 0.5, z0), Vector3(0.12, h, 0.12), steel, Basis(), 0.01)
	g.box("metal", Vector3(x, y0 + 2.56, z0), Vector3(2.4, 0.12, 0.14), steel)
	for s: float in [-1.0, 1.0]:
		g.box("metal", Vector3(x + s * w * 0.5, y0 + h * 0.5, front - 0.06), Vector3(0.12, h, 0.12), steel)
		g.box("metal", Vector3(x + s * w * 0.5, y0 + 0.04, z0 + d * 0.5), Vector3(0.1, 0.08, d), steel)
	g.box("metal", Vector3(x, y0 + 0.04, z0), Vector3(w, 0.08, 0.1), steel)
	# The canopy: a thin slab over the vestibule and a metre past it, a dark fascia band with the
	# door number lit in it.
	g.box("metal", Vector3(x, y0 + h + 0.14, z0 + d * 0.5 - 0.5), Vector3(w + 0.8, 0.28, d + 1.0), Color(0.86, 0.87, 0.89), Basis(), 0.03)
	g.box("dark", Vector3(x, y0 + h + 0.14, z0 - 1.02), Vector3(2.0, 0.22, 0.03), Color.WHITE)


## The luggage material: the vertex colour (white shell, dark hardware) times the instance's
## colour; a satin plastic.
static func bag_material() -> StandardMaterial3D:
	if _meshes.has("mat"):
		return _meshes["mat"]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.42
	mat.metallic = 0.0
	_meshes["mat"] = mat
	return mat


## Code-built luggage at real size, standing on its wheels or base at the origin, its front -z:
## 0 a large hard-shell spinner (ribbed shell, zip seam, four wheels, the handle housing),
## 1 a carry-on with its handle pulled up, 2 a soft duffel, 3 a carry-on with a backpack leaning
## on it. White where the instance colour should show, near black for wheels and handles.
static func bag_mesh(kind: int) -> Mesh:
	var key := "bag_%d" % kind
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shell := Color(1.0, 1.0, 1.0)
	var hw := Color(0.06, 0.06, 0.065)
	match kind:
		0, 1, 3:
			var big := kind == 0
			var sz := Vector3(0.48, 0.70, 0.28) if big else Vector3(0.38, 0.54, 0.23)
			var base := 0.07
			_rbox(st, Vector3(0.0, base + sz.y * 0.5, 0.0), sz, 0.045, shell)
			# Vertical ribs on both faces and the zip seam round the middle of the depth.
			for s: float in [-1.0, 1.0]:
				for i in 4:
					var rx := (float(i) - 1.5) * sz.x * 0.2
					_box(st, Vector3(rx, base + sz.y * 0.5, s * (sz.z * 0.5 + 0.004)), Vector3(0.022, sz.y * 0.78, 0.01), shell * 0.92)
			_box(st, Vector3(0.0, base + sz.y * 0.5, 0.0), Vector3(sz.x + 0.008, sz.y - 0.06, 0.018), hw)
			# Spinner wheels at the four corners.
			for wx: float in [-1.0, 1.0]:
				for wz: float in [-1.0, 1.0]:
					_box(st, Vector3(wx * (sz.x * 0.5 - 0.04), base - 0.035, wz * (sz.z * 0.5 - 0.04)), Vector3(0.05, 0.07, 0.035), hw)
			# The handle: its housing on top, pulled up on a carry-on.
			var up := 0.0 if kind == 0 else 0.42
			for hx: float in [-1.0, 1.0]:
				_box(st, Vector3(hx * sz.x * 0.3, base + sz.y + up * 0.5, sz.z * 0.38), Vector3(0.022, up + 0.03, 0.018), hw)
			_box(st, Vector3(0.0, base + sz.y + up + 0.02, sz.z * 0.38), Vector3(sz.x * 0.66, 0.03, 0.03), hw)
			# A side carry handle.
			_box(st, Vector3(sz.x * 0.5 + 0.012, base + sz.y * 0.55, 0.0), Vector3(0.02, 0.03, 0.14), hw)
			if kind == 3:
				# A backpack leaning on its front.
				var bp := Basis(Vector3.RIGHT, -0.22)
				_rbox(st, Vector3(0.0, 0.26, -sz.z * 0.5 - 0.11), Vector3(0.30, 0.44, 0.16), 0.05, Color(0.30, 0.30, 0.32), bp)
				_rbox(st, Vector3(0.0, 0.17, -sz.z * 0.5 - 0.2), Vector3(0.24, 0.18, 0.06), 0.025, Color(0.26, 0.26, 0.28), bp)
		2:
			# A duffel lying on its side: a rounded body, two webbing handles over it, end pockets.
			_rbox(st, Vector3(0.0, 0.16, 0.0), Vector3(0.62, 0.32, 0.30), 0.12, shell)
			for hx: float in [-1.0, 1.0]:
				_box(st, Vector3(hx * 0.12, 0.33, 0.0), Vector3(0.035, 0.03, 0.3), hw)
			_box(st, Vector3(0.0, 0.36, 0.0), Vector3(0.28, 0.025, 0.04), hw)
			_box(st, Vector3(0.0, 0.17, -0.155), Vector3(0.5, 0.012, 0.012), hw)
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## An airport luggage cart, nose +x: a chassis with two wheels and casters, the deck, the
## folding back frame and the push bar (all dark steel; the vertex colour is the paint).
static func cart_mesh() -> Mesh:
	if _meshes.has("cart"):
		return _meshes["cart"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steel := Color(0.55, 0.56, 0.58)
	var dark := Color(0.08, 0.08, 0.09)
	_box(st, Vector3(0.0, 0.16, 0.0), Vector3(0.9, 0.035, 0.55), steel)
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(-0.1, 0.12, s * 0.3), Vector3(1.05, 0.04, 0.04), steel)
		_box(st, Vector3(-0.45, 0.12, s * 0.3), Vector3(0.18, 0.24, 0.05), dark)
		_box(st, Vector3(0.38, 0.07, s * 0.24), Vector3(0.1, 0.14, 0.04), dark)
		var lean := Basis(Vector3.BACK, -0.22)
		_box(st, Vector3(-0.42, 0.62, s * 0.27), Vector3(0.035, 0.95, 0.035), steel, lean)
	_box(st, Vector3(-0.53, 1.08, 0.0), Vector3(0.04, 0.04, 0.6), dark)
	_box(st, Vector3(-0.3, 0.7, 0.0), Vector3(0.03, 0.4, 0.5), steel, Basis(Vector3.BACK, -0.22))
	st.generate_normals()
	var mesh := st.commit()
	_meshes["cart"] = mesh
	return mesh


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, b: Basis = Basis()) -> void:
	var h := s * 0.5
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(c + b * Vector3(h.x * (1.0 if i & 1 else -1.0), h.y * (1.0 if i & 2 else -1.0), h.z * (1.0 if i & 4 else -1.0)))
	var faces := [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
	for f: Array in faces:
		_quad(st, corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], col, c)


## A box with every edge chamfered by `r` (six faces, twelve bevel strips, eight corners): a
## moulded shell that catches the light along its edges.
static func _rbox(st: SurfaceTool, c: Vector3, s: Vector3, r: float, col: Color, b: Basis = Basis()) -> void:
	var h := s * 0.5
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.9)
	var v := func(sx: float, sy: float, sz: float, axis: int) -> Vector3:
		var p := Vector3(sx * (h.x - r), sy * (h.y - r), sz * (h.z - r))
		p[axis] = [sx, sy, sz][axis] * h[axis]
		return c + b * p
	var sg := [-1.0, 1.0]
	# The faces.
	for axis in 3:
		for sa: float in sg:
			var q: Array[Vector3] = []
			for u: float in sg:
				for w: float in sg:
					var sv := [0.0, 0.0, 0.0]
					sv[axis] = sa
					sv[(axis + 1) % 3] = u
					sv[(axis + 2) % 3] = w * u
					q.append(v.call(sv[0], sv[1], sv[2], axis))
			_quad(st, q[0], q[1], q[2], q[3], col, c)
	# The bevel strips: between face `a1` and face `a2` along the third axis.
	for a1 in 3:
		var a2 := (a1 + 1) % 3
		var a3 := (a1 + 2) % 3
		for s1: float in sg:
			for s2: float in sg:
				var p := [0.0, 0.0, 0.0]
				p[a1] = s1
				p[a2] = s2
				p[a3] = -1.0
				var e0: Vector3 = v.call(p[0], p[1], p[2], a1)
				var f0: Vector3 = v.call(p[0], p[1], p[2], a2)
				p[a3] = 1.0
				var e1: Vector3 = v.call(p[0], p[1], p[2], a1)
				var f1: Vector3 = v.call(p[0], p[1], p[2], a2)
				_quad(st, e0, e1, f1, f0, col, c)
	# The corners.
	for sx: float in sg:
		for sy: float in sg:
			for sz: float in sg:
				var t0: Vector3 = v.call(sx, sy, sz, 0)
				var t1: Vector3 = v.call(sx, sy, sz, 1)
				var t2: Vector3 = v.call(sx, sy, sz, 2)
				_quad(st, t0, t1, t2, t2, col, c)


## A quad wound so it faces away from `inside` (Godot's front faces are clockwise).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	var out := (a + b + c + d) * 0.25 - inside
	var tris: Array = [[a, b, c], [a, c, d]] if n.dot(out) < 0.0 else [[a, c, b], [a, d, c]]
	for t: Array in tris:
		if (t[1] - t[0]).cross(t[2] - t[0]).length_squared() < 1e-14:
			continue
		for v: Vector3 in t:
			st.set_color(col)
			st.add_vertex(v)


# --- The loop's kerb lane -------------------------------------------------------------------------

## TrafficManager._drive_loops() asks this for every loop car each tick, after its follow speed:
## returns [speed, shift] - the speed it may go, and how far toward the kerb it stands (metres,
## along the loop's right). Loop 0's first leg runs along the kerb: there a car stops at its spot
## for a drop-off on its hazards, pulled in, and goes again; the cars behind close up on it.
static func loop_speed(car: Vehicle, loop_index: int, speed: float, delta: float) -> Array:
	if not enabled or loop_index != 0:
		return [speed, 0.0]
	var tr: Dictionary = car.traffic
	var t: float = tr.t
	var leg := t < STOP_T.y + 12.0
	var shift: float = tr.get("tc_shift", 0.0)
	if not tr.has("tc_lap"):
		# Its first tick: maybe it is already standing at the kerb, part way through a stop.
		tr.tc_lap = 0
		var h0 := _r([car.get_instance_id(), "tc_first"])
		if leg and t > STOP_T.x and h0 < 0.45:
			tr.tc_stop = t
			tr.tc_left = lerpf(DWELL.x, DWELL.y, _r([car.get_instance_id(), "tc_d0"])) * _r([car.get_instance_id(), "tc_part"])
			shift = PULL_IN
		else:
			_decide(car, tr)
	if not leg:
		if tr.get("tc_done", false):
			tr.tc_done = false
			tr.tc_lap = int(tr.tc_lap) + 1
		tr.tc_stop = -1.0
		tr.hazard = false
		shift = move_toward(shift, 0.0, delta * 0.8)
		tr.tc_shift = shift
		return [speed, shift]
	if t < STOP_T.x - 14.0 and not tr.get("tc_done", false) and float(tr.get("tc_stop", -1.0)) < 0.0:
		_decide(car, tr)
	var stop: float = tr.get("tc_stop", -1.0)
	var want := 0.0
	if stop >= 0.0:
		var to := stop - t
		if to < 14.0:
			want = PULL_IN
		if to <= 0.15:
			speed = 0.0
			tr.hazard = true
			tr.tc_left = float(tr.get("tc_left", 0.0)) - delta
			if float(tr.tc_left) <= 0.0:
				tr.tc_stop = -1.0
				tr.tc_done = true
				tr.hazard = false
		else:
			speed = minf(speed, maxf(0.4, to * 0.6))
	shift = move_toward(shift, want, delta * (0.9 if want > shift else 0.6))
	tr.tc_shift = shift
	return [speed, shift]


static func _decide(car: Vehicle, tr: Dictionary) -> void:
	var key := [car.get_instance_id(), int(tr.tc_lap)]
	tr.tc_done = false
	if _r(key + ["stop"]) < STOP_SHARE:
		tr.tc_stop = lerpf(STOP_T.x, STOP_T.y, _r(key + ["at"]))
		tr.tc_left = lerpf(DWELL.x, DWELL.y, _r(key + ["dwell"]))
	else:
		tr.tc_stop = -1.0
		tr.tc_done = true


## A taxi or a shuttle van for the loop (null: the caller's ordinary car). `pick` is a hash of
## the slot; the car is built from its own generator, so the caller's stream is untouched.
static func loop_car(pick: int) -> Vehicle:
	if not enabled:
		return null
	var r := float(absi(pick) % 1000) / 1000.0
	var want := -1
	if r < TAXI_SHARE:
		want = Vehicle.BodyType.TAXI
	elif r < TAXI_SHARE + SHUTTLE_SHARE:
		want = Vehicle.BodyType.VAN
	if want < 0:
		return null
	var rng := RandomNumberGenerator.new()
	for i in 400:
		rng.seed = absi(hash([pick, "tc_car", i]))
		var probe := RandomNumberGenerator.new()
		probe.seed = rng.seed
		var look := hash([probe.state, 7717])
		var type := Vehicle._body_for_roll(probe.randi_range(0, 999))
		var job := Vehicle._roll(look, 11)
		if want == Vehicle.BodyType.TAXI and type == Vehicle.BodyType.SEDAN and job < Vehicle.TAXI_SHARE:
			return Vehicle.random_car(rng)
		if want == Vehicle.BodyType.VAN and type == Vehicle.BodyType.VAN and job < Vehicle.DELIVERY_SHARE:
			# A hotel or car-park shuttle: white, its fleet's band down the side (the courier
			# livery's band, repainted before the car is in the tree).
			var van := Vehicle.random_car(rng)
			van.paint = Color(0.93, 0.93, 0.92)
			van.trim_color = SHUTTLE_BANDS[absi(pick) % SHUTTLE_BANDS.size()]
			return van
	return null


# --- The travellers ---------------------------------------------------------------------------------

## How many plain walkers the airport chunk puts on the kerb (CityChunk._build_airport()): fewer
## with the travellers standing there (they share the crowd cap; the walkers bunched at the strip's
## ends, the travellers are dealt along it).
const WALKERS := 12


static func walkers(count: int) -> int:
	return mini(count, WALKERS) if enabled else count


## Landmarks.people_steps() for the terminal: one CurbTraveller a step at each spot, in the crowd cap.
static func people_steps(chunk: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	if not enabled or chunk == null or chunk.plan == null or chunk.plan.macro == null:
		return steps
	var macro: MacroMap = chunk.plan.macro
	var rect: Rect2 = macro.terminal_curb.grow(2.0)
	var y: float = macro.tarmac_top + STRIP_TOP
	# Dealt in a hashed order, so a crowd cap that runs out thins the whole kerb evenly.
	var all := spots(chunk.plan.seed)
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.seed) < int(b.seed))
	var here: Array = []
	for s: Dictionary in all:
		# All of them under the chunk that builds the terminal (the kerb runs over three chunks; the
		# people go with the building they stand in front of).
		steps.append(func() -> void: _spawn(chunk, rect, s, y, here))
	steps.append(func() -> void: _commit_bags(chunk, here, y))
	return steps


static func _spawn(chunk: CityChunk, rect: Rect2, s: Dictionary, y: float, here: Array) -> void:
	if not is_instance_valid(chunk) or not chunk._take_crowd_room():
		return
	here.append(s)
	var ped := CurbTraveller.new()
	ped.setup_traveller(rect, int(s.seed), s.p, float(s.yaw), s.group)
	ped.position = Vector3((s.p as Vector2).x, y + 0.05, (s.p as Vector2).y)
	chunk.add_child(ped)
