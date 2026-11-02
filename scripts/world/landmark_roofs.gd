class_name LandmarkRoofs
extends RefCounted
## What stands on the downtown towers' flat roofs (LandmarkDowntown). Their builders left each
## roof a bare cap with one blank concrete box on it - the "mechanical" block - and from another
## tower's roof (refcam3 `rooftop_golden`, the 333 S Hope helipad at 17:45) that box was the
## largest thing in the frame: a flat grey slab with nothing on it. Real towers carry a louvred
## mechanical penthouse and a field of plant round it, and at golden hour that plant is what
## throws the long shadows that make a roof read as a roof.
##
## Per tower, from its own data (`LandmarkDowntown.tower(id)`: the prism tiers and every box the
## builders made, `TowerMesh.boxes`):
##   * every roof box (concrete, over MECH_MIN_Y, at least MECH_MIN_SIZE across) is CLAD as a
##     penthouse: louvred screen walls on a frame of posts a little outside it, taller than the
##     box, a capped roof with an overhang, a door, an exhaust fan and a flue on top;
##   * the roof tier that box stands on is dressed: packaged rooftop units on curbs with their fan
##     tops and a duct dropping into the roof, cooling towers with louvred casings and a fan stack,
##     mushroom exhaust fans, and a duct run on legs from the nearest units to the penthouse -
##     inside the tier's outline less EDGE_INSET (the window-washing davits and machines,
##     TowerGondolas, stand at the edge), clear of the penthouse and the helipad's deck, net and
##     stair (`LandmarkDowntown.TOWERS[id].helipad`).
## A tower whose roof has no such box (a crown, a spire, a lit lantern) is left alone.
##
## The plan is pure (hashes of the tower's id: the downtown towers are the same on every seed);
## one mesh per tower on Rooftops' shader (`Rooftops.material()`, kinds in the vertex alpha),
## built once and shared by the far copy and the detailed one; collision boxes on the detailed
## one. LANDMARK_ROOFS=0 is the A/B (nothing built).

static var enabled := OS.get_environment("LANDMARK_ROOFS") != "0" and RcRooftop.enabled

## A roof box is one the builders put higher than this (local metres over the tower's base)...
const MECH_MIN_Y := 60.0
## ...at least this wide both ways and this tall (the lit bands and fins are thinner).
const MECH_MIN_SIZE := 5.0
const MECH_MIN_HEIGHT := 1.2
## How far inside the roof's outline the plant keeps (the parapet, the gondolas' davits).
const EDGE_INSET := 3.6
## The candidate grid the plant is laid on (metres) and the share of cells that get a piece.
const CELL := 4.4
const FILL := 0.72
## Room kept round the penthouse (its doors, the duct runs) and round each piece.
const PENT_ROOM := 1.8
const PIECE_ROOM := 0.7
## The helipad's deck is grown by its safety net, the stair and a walkway to it.
const PAD_ROOM := 3.4
## How much taller than the builders' box the penthouse stands, and how far outside it.
const PENT_RISE := 1.3
const PENT_OUT := 0.25
## The near and far copies stop drawing the plant past this (it is under a pixel there).
const DRAW_DISTANCE := 950.0

## Paint (sRGB as written; Rooftops' shader decodes it).
const UNIT_GREY := Color(0.74, 0.74, 0.71)
const UNIT_BEIGE := Color(0.78, 0.75, 0.68)
const DUCT := Color(0.66, 0.67, 0.68)
const CURB := Color(0.58, 0.57, 0.54)
const FAN_DARK := Color(0.16, 0.17, 0.18)
const PENT_METAL := [Color(0.60, 0.61, 0.61), Color(0.48, 0.50, 0.51), Color(0.70, 0.68, 0.64)]

## Kinds of rooftop.gdshader (Rooftops' K_*).
const K_PAINT := 0
const K_STEEL := 1
const K_CONCRETE := 2
const K_LOUVRE := 12
const K_GRATING := 16

enum Piece { RTU, FAN, TOWER }

## Towers whose roof boxes are not plant (the unfinished tower's are its bare core and forms).
const SKIP := ["dt_unfinished"]

static var _cache: Dictionary = {}


static func _h(id: String, tag: String, i: int = 0) -> float:
	return float(absi(hash([id, "landmark_roofs", tag, i])) % 100000) / 100000.0


## The plan of one tower's roof: {"pent": [[centre, size, paint], ...] (local, the penthouse's
## box), "pieces": [[Piece, Vector3 base centre, Vector2 footprint, variant], ...], "ducts":
## [[from, to], ...] (local, at the duct's height)}. Empty when the tower has no flat roof with a
## mechanical box.
static func plan(id: String) -> Dictionary:
	var out := {"pent": [], "pieces": [], "ducts": []}
	if not LandmarkDowntown.TOWERS.has(id) or SKIP.has(id):
		return out
	var t: Dictionary = LandmarkDowntown.tower(id)
	var tiers: Array = t.get("tiers", [])
	var mech: Array = []
	for b: Array in t.get("boxes", []):
		var c: Vector3 = b[0]
		var s: Vector3 = b[1]
		var col: Color = b[2]
		if c.y < MECH_MIN_Y or s.x < MECH_MIN_SIZE or s.z < MECH_MIN_SIZE or s.y < MECH_MIN_HEIGHT:
			continue
		if not col.is_equal_approx(LandmarkDowntown.CONCRETE):
			continue
		if b.size() > 3 and absf(float(b[3])) > 0.001:
			continue
		var tier := _tier_under(tiers, c, s)
		if tier.is_empty():
			continue
		mech.append([c, s, tier])
	if mech.is_empty():
		return out
	# Keep-outs on the roof (local XZ): every penthouse and the helipad.
	var keep: Array[Rect2] = []
	var paint: Color = PENT_METAL[int(_h(id, "paint") * float(PENT_METAL.size())) % PENT_METAL.size()]
	for m: Array in mech:
		var c: Vector3 = m[0]
		var s: Vector3 = m[1]
		var size := Vector3(s.x + PENT_OUT * 2.0, s.y + PENT_RISE, s.z + PENT_OUT * 2.0)
		var base_y := c.y - s.y * 0.5
		out.pent.append([Vector3(c.x, base_y + size.y * 0.5, c.z), size, paint])
		keep.append(Rect2(Vector2(c.x, c.z) - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)).grow(PENT_ROOM))
	var row: Dictionary = LandmarkDowntown.TOWERS[id]
	if row.has("helipad"):
		var pad: Array = row.helipad
		var pc: Vector3 = pad[0]
		var half := float(pad[1]) * 0.5 + PAD_ROOM
		keep.append(Rect2(Vector2(pc.x - half, pc.z - half), Vector2(half * 2.0, half * 2.0)))
	# One roof per tier that carries a penthouse (a pair of towers has two).
	var done: Array = []
	for m: Array in mech:
		var tier: Array = m[2]
		if done.has(tier):
			continue
		done.append(tier)
		_lay_roof(id, out, tier, keep, m)
	return out


## The prism tier the box stands on: the one whose roof (y1, or the top of its parapet) is under
## the box's foot and whose outline holds the box's centre.
static func _tier_under(tiers: Array, c: Vector3, s: Vector3) -> Array:
	var foot := c.y - s.y * 0.5
	var best: Array = []
	for tier: Array in tiers:
		var y1: float = tier[2]
		if foot < y1 - 0.2 or foot > y1 + TowerMesh.PARAPET_HEIGHT + 1.5:
			continue
		if not Geometry2D.is_point_in_polygon(Vector2(c.x, c.z), tier[0]):
			continue
		if best.is_empty() or float(tier[2]) > float(best[2]):
			best = tier
	return best


static func _lay_roof(id: String, out: Dictionary, tier: Array, keep: Array[Rect2], m: Array) -> void:
	var outline: PackedVector2Array = tier[0]
	var roof_y: float = tier[2]
	var inner_list := Geometry2D.offset_polygon(outline, -EDGE_INSET)
	if inner_list.is_empty():
		return
	var inner: PackedVector2Array = inner_list[0]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in inner:
		lo = lo.min(p)
		hi = hi.max(p)
	var taken: Array[Rect2] = keep.duplicate()
	var placed: Array = []
	var nx := int(floorf((hi.x - lo.x) / CELL))
	var nz := int(floorf((hi.y - lo.y) / CELL))
	var cell_i := 0
	for iz in nz + 1:
		for ix in nx + 1:
			cell_i += 1
			if _h(id, "fill", cell_i) > FILL:
				continue
			var roll := _h(id, "kind", cell_i)
			var kind := Piece.RTU
			var fp := Vector2(3.4, 2.0)
			if roll > 0.82:
				kind = Piece.TOWER
				fp = Vector2(4.2, 4.2)
			elif roll > 0.6:
				kind = Piece.FAN
				fp = Vector2(1.1, 1.1)
			# Units lie along the longer side of the roof, a few turned across.
			if kind == Piece.RTU and ((hi.x - lo.x < hi.y - lo.y) != (_h(id, "turn", cell_i) < 0.2)):
				fp = Vector2(fp.y, fp.x)
			var jit := Vector2(_h(id, "jx", cell_i) - 0.5, _h(id, "jz", cell_i) - 0.5) * (CELL - fp.x) * 0.5
			var at := lo + Vector2(float(ix) + 0.5, float(iz) + 0.5) * CELL + jit
			var r := Rect2(at - fp * 0.5, fp)
			if not _inside(r, inner):
				continue
			var clash := false
			for k: Rect2 in taken:
				if k.intersects(r.grow(PIECE_ROOM)):
					clash = true
					break
			if clash:
				continue
			taken.append(r)
			var variant := int(_h(id, "variant", cell_i) * 4.0)
			out.pieces.append([kind, Vector3(at.x, roof_y, at.y), fp, variant])
			placed.append([kind, at])
	# Duct runs on legs from the two units nearest the penthouse to its wall: along x, then z.
	var pc: Vector3 = m[0]
	var ps: Vector3 = m[1]
	var near: Array = []
	for p: Array in placed:
		if p[0] == Piece.RTU:
			near.append(p[1])
	near.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(Vector2(pc.x, pc.z)) < b.distance_squared_to(Vector2(pc.x, pc.z)))
	var y := roof_y + 0.95
	for k in mini(2, near.size()):
		var a: Vector2 = near[k]
		var wall_z := pc.z + signf(a.y - pc.z) * (ps.z * 0.5 + PENT_OUT)
		if absf(a.y - pc.z) < ps.z * 0.5:
			wall_z = a.y
		var corner := Vector3(clampf(a.x, pc.x - ps.x * 0.5 + 1.0, pc.x + ps.x * 0.5 - 1.0), y, a.y)
		out.ducts.append([Vector3(a.x, y, a.y), corner])
		out.ducts.append([corner, Vector3(corner.x, y, wall_z)])


static func _inside(r: Rect2, poly: PackedVector2Array) -> bool:
	for p: Vector2 in [r.position, r.position + Vector2(r.size.x, 0.0), r.end, r.position + Vector2(0.0, r.size.y)]:
		if not Geometry2D.is_point_in_polygon(p, poly):
			return false
	return true


## The roof's mesh for a tower (cached), or null when it has no roof to dress.
static func mesh(id: String) -> ArrayMesh:
	if _cache.has(id):
		return _cache[id]
	var p := plan(id)
	var m: ArrayMesh = null
	if not p.pent.is_empty():
		var g := RooftopGeo.new()
		for pe: Array in p.pent:
			_penthouse(g, id, pe[0], pe[1], pe[2])
		var i := 0
		for pc: Array in p.pieces:
			i += 1
			match int(pc[0]):
				Piece.RTU:
					_rtu(g, pc[1], pc[2], int(pc[3]))
				Piece.FAN:
					_fan(g, pc[1])
				Piece.TOWER:
					_cooling_tower(g, pc[1], pc[2])
		for d: Array in p.ducts:
			_duct(g, d[0], d[1])
		m = ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g.arrays())
		m.surface_set_material(0, Rooftops.material())
	_cache[id] = m
	return m


## Puts the dressed roof on a tower under `parent` at `at` (the tower's base, local = tower
## metres). `statics` non-null (the detailed copy): collision boxes for the penthouse and plant.
static func dress(parent: Node3D, at: Vector3, id: String, statics: StaticBody3D) -> void:
	if not enabled:
		return
	var m := mesh(id)
	if m == null:
		return
	var node := MeshInstance3D.new()
	node.name = "Roof_" + id
	node.mesh = m
	node.position = at
	node.visibility_range_end = DRAW_DISTANCE
	node.visibility_range_end_margin = 80.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(node)
	if statics == null:
		return
	var p := plan(id)
	for pe: Array in p.pent:
		_shape(statics, at + (pe[0] as Vector3), pe[1])
	for pc: Array in p.pieces:
		var fp: Vector2 = pc[2]
		var h := 1.6 if int(pc[0]) == Piece.RTU else (3.9 if int(pc[0]) == Piece.TOWER else 0.9)
		_shape(statics, at + (pc[1] as Vector3) + Vector3(0.0, h * 0.5, 0.0), Vector3(fp.x, h, fp.y))


static func _shape(statics: StaticBody3D, centre: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = centre
	statics.add_child(cs)


# --- Pieces --------------------------------------------------------------------------------

## The mechanical penthouse round a builders' box: posts, louvred screens, a capped roof with an
## overhang, a door in each long side, an exhaust fan and a flue on top.
static func _penthouse(g: RooftopGeo, id: String, c: Vector3, size: Vector3, metal: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := c.y - size.y * 0.5
	var h := size.y
	g.box(Vector3(c.x, y0 + 0.1, c.z), Vector3(size.x + 0.3, 0.2, size.z + 0.3), CURB, K_CONCRETE)
	g.box(Vector3(c.x, y0 + 0.2 + (h - 0.45) * 0.5, c.z), Vector3(size.x, h - 0.45, size.z), metal, K_LOUVRE)
	# The cap: a fascia band and a roof with an overhang.
	g.box(Vector3(c.x, y0 + h - 0.13, c.z), Vector3(size.x + 0.4, 0.26, size.z + 0.4), metal.darkened(0.18), K_PAINT)
	var post := metal.darkened(0.3)
	for x: float in [-hx, hx]:
		for z: float in [-hz, hz]:
			g.box(Vector3(c.x + x, y0 + h * 0.5, c.z + z), Vector3(0.18, h - 0.2, 0.18), post, K_STEEL)
	# Mullion posts every ~2.4 m along each side, a hair proud of the screens.
	var nx := maxi(1, int(size.x / 2.4))
	for k in range(1, nx):
		var x := -hx + float(k) * size.x / float(nx)
		for z: float in [-hz - 0.03, hz + 0.03]:
			g.box(Vector3(c.x + x, y0 + h * 0.5, c.z + z), Vector3(0.12, h - 0.45, 0.07), post, K_STEEL)
	var nz := maxi(1, int(size.z / 2.4))
	for k in range(1, nz):
		var z := -hz + float(k) * size.z / float(nz)
		for x: float in [-hx - 0.03, hx + 0.03]:
			g.box(Vector3(c.x + x, y0 + h * 0.5, c.z + z), Vector3(0.07, h - 0.45, 0.12), post, K_STEEL)
	# Doors, solid steel panels in the screens, with a step.
	for side: float in [-1.0, 1.0]:
		var dx := (hx * 0.45) * side
		g.box(Vector3(c.x + dx, y0 + 1.15, c.z + (hz + 0.05) * side), Vector3(1.0, 2.2, 0.06), Color(0.30, 0.31, 0.32), K_PAINT)
		g.box(Vector3(c.x + dx, y0 + 0.08, c.z + (hz + 0.5) * side), Vector3(1.4, 0.16, 0.8), CURB, K_CONCRETE)
	# On top: an exhaust fan, a flue, a small packaged unit.
	var top := y0 + h
	var fx := c.x + (_h(id, "pfan") - 0.5) * size.x * 0.5
	g.box(Vector3(fx, top + 0.15, c.z - hz * 0.35), Vector3(1.5, 0.3, 1.5), CURB, K_CONCRETE)
	g.cyl(Vector3(fx, top + 0.3, c.z - hz * 0.35), 0.6, 0.6, 0.55, 14, UNIT_GREY, K_PAINT)
	g.cyl(Vector3(fx, top + 0.85, c.z - hz * 0.35), 0.62, 0.62, 0.05, 14, FAN_DARK, K_GRATING)
	g.cyl(Vector3(c.x - hx * 0.55, top, c.z + hz * 0.4), 0.2, 0.2, 2.4, 10, DUCT, K_STEEL)
	g.cyl(Vector3(c.x - hx * 0.55, top + 2.4, c.z + hz * 0.4), 0.32, 0.06, 0.3, 10, DUCT, K_STEEL)
	g.box(Vector3(c.x + hx * 0.45, top + 0.55, c.z + hz * 0.3), Vector3(2.2, 1.1, 1.4), UNIT_GREY, K_PAINT)
	g.cyl(Vector3(c.x + hx * 0.45, top + 1.1, c.z + hz * 0.3), 0.42, 0.42, 0.06, 12, FAN_DARK, K_GRATING)


## A packaged rooftop unit on its curb: the cabinet, a louvred coil face, two condenser fans on
## top, a duct dropping into the roof at one end.
static func _rtu(g: RooftopGeo, base: Vector3, fp: Vector2, variant: int) -> void:
	var paint := UNIT_GREY if variant % 2 == 0 else UNIT_BEIGE
	var along_x := fp.x >= fp.y
	var L := maxf(fp.x, fp.y) - 0.2
	var W := minf(fp.x, fp.y) - 0.2
	var size := Vector3(L, 1.3, W) if along_x else Vector3(W, 1.3, L)
	g.box(base + Vector3(0.0, 0.14, 0.0), Vector3(size.x + 0.2, 0.28, size.z + 0.2), CURB, K_CONCRETE)
	g.box(base + Vector3(0.0, 0.28 + size.y * 0.5, 0.0), size, paint, K_PAINT)
	# The coil face on one long side.
	var side := 1.0 if variant < 2 else -1.0
	if along_x:
		g.box(base + Vector3(L * 0.12, 0.28 + size.y * 0.5, side * (W * 0.5 + 0.02)), Vector3(L * 0.6, size.y * 0.7, 0.05), paint.darkened(0.1), K_LOUVRE)
	else:
		g.box(base + Vector3(side * (W * 0.5 + 0.02), 0.28 + size.y * 0.5, L * 0.12), Vector3(0.05, size.y * 0.7, L * 0.6), paint.darkened(0.1), K_LOUVRE)
	var top := base.y + 0.28 + size.y
	var ax := Vector3(1.0, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, 1.0)
	for f: float in [0.18, -0.12]:
		var p := Vector3(base.x, top, base.z) + ax * (f * L)
		g.cyl(p, 0.5, 0.5, 0.12, 14, FAN_DARK, K_STEEL)
		g.cyl(p + Vector3(0.0, 0.12, 0.0), 0.48, 0.48, 0.02, 14, Color(0.40, 0.41, 0.42), K_GRATING)
	# Supply and return dropping into the roof at the far end.
	var end := Vector3(base.x, base.y, base.z) - ax * (L * 0.5 + 0.35)
	g.box(end + Vector3(0.0, 0.5, 0.0), Vector3(0.7, 1.0, 0.7) if along_x else Vector3(0.7, 1.0, 0.7), DUCT, K_STEEL)


## A mushroom exhaust fan on a curb.
static func _fan(g: RooftopGeo, base: Vector3) -> void:
	g.box(base + Vector3(0.0, 0.15, 0.0), Vector3(1.0, 0.3, 1.0), CURB, K_CONCRETE)
	g.cyl(base + Vector3(0.0, 0.3, 0.0), 0.36, 0.36, 0.42, 12, UNIT_GREY, K_PAINT)
	g.cyl(base + Vector3(0.0, 0.72, 0.0), 0.56, 0.24, 0.26, 12, UNIT_GREY, K_PAINT)


## A cooling tower on steel dunnage: louvred intake round the bottom, a casing, the fan stack.
static func _cooling_tower(g: RooftopGeo, base: Vector3, fp: Vector2) -> void:
	var s := Vector3(fp.x - 0.4, 0.0, fp.y - 0.4)
	for x: float in [-s.x * 0.5 + 0.2, s.x * 0.5 - 0.2]:
		g.beam(base + Vector3(x, 0.25, -s.z * 0.5), base + Vector3(x, 0.25, s.z * 0.5), 0.25, 0.5, Color(0.30, 0.31, 0.32), K_STEEL)
	g.box(base + Vector3(0.0, 0.5 + 0.7, 0.0), Vector3(s.x, 1.4, s.z), Color(0.62, 0.64, 0.64), K_LOUVRE)
	g.box(base + Vector3(0.0, 1.9 + 0.75, 0.0), Vector3(s.x, 1.5, s.z), Color(0.70, 0.71, 0.70), K_PAINT)
	var top := base + Vector3(0.0, 3.4, 0.0)
	g.cyl(top, 1.5, 1.4, 0.75, 20, Color(0.66, 0.67, 0.67), K_PAINT, false, false)
	g.cyl(top + Vector3(0.0, 0.62, 0.0), 1.38, 1.38, 0.04, 20, FAN_DARK, K_GRATING)


## A rectangular duct on legs from a to b (both at the duct's centre height).
static func _duct(g: RooftopGeo, a: Vector3, b: Vector3) -> void:
	if a.distance_to(b) < 0.5:
		return
	g.beam(a, b, 0.75, 0.55, DUCT, K_STEEL)
	var n := int(a.distance_to(b) / 2.6)
	for k in n + 1:
		var p := a.lerp(b, float(k) / float(maxi(n, 1)))
		g.box(Vector3(p.x, (p.y - 0.28) * 0.5 + (a.y - 0.95) * 0.5, p.z), Vector3(0.08, p.y - 0.28 - (a.y - 0.95), 0.08), Color(0.30, 0.31, 0.32), K_STEEL)
