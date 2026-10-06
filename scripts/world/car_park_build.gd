class_name CarParkBuild
extends RefCounted
## Builds a multi-storey car park (CarPark: where and the plan) in a chunk.
##
## FULL: one node in the structure's own frame (x along the street from the structure's first
## corner = u, z in from the street = v, y up from the ground deck), holding
##   - ONE mesh, a surface per material: the decks' tops on shaders/car_park_deck.gdshader (the
##     stall lines, wheel tracks and oil are the shader's), precast concrete for slabs, beams,
##     columns, spandrels, the ramp strip's walls and the core, the painted bands on the columns
##     (a colour a level, as real car parks do it), the light fittings (lit day and night), glass,
##     steel;
##   - ONE trimesh collision body (StaticBody3D, world layer, mask 0, backface collision) of every
##     slab, ramp, wall, column, kerb, the apron across the pavement and every parked car;
##   - the parked cars as MultiMeshes of ArenaGrounds' static cars (no shadow inside; the roof's
##     cast);
##   - two CarParkGate barrier arms at the entry and the exit, the lettering (TextMesh, not on
##     the web), the night pools on the decks (additive, lamp_factor).
## LOD and the far city: a box a storey band (a dark open band over a concrete spandrel) and the
## core, the old far-box path.

const CONCRETE := Color(0.80, 0.79, 0.75)
const CONCRETE_DARK := Color(0.56, 0.56, 0.55)
## One colour a level, on the columns (ground, 1, 2, ...).
const LEVEL_COLORS := [Color(0.16, 0.42, 0.72), Color(0.12, 0.55, 0.32), Color(0.85, 0.62, 0.08),
	Color(0.72, 0.16, 0.12), Color(0.45, 0.22, 0.62), Color(0.05, 0.55, 0.62), Color(0.88, 0.40, 0.08)]
const LEVEL_NAMES := ["G", "2", "3", "4", "5", "6", "7"]
## Light fittings along an aisle (m apart) and how bright (emission, lit day and night).
const LIGHT_SPACING := 5.4
const LIGHT_GLOW := 3.2
## Roof light poles (m apart along an aisle) and their height.
const ROOF_POLE_SPACING := 18.0
const ROOF_POLE_H := 6.2
## The ramp's slab and its sampling (m).
const RAMP_SLAB := 0.26
const RAMP_STEP := 1.0
## Parked cars' collision box (length, height, width; m).
const CAR_BOX := Vector3(4.5, 1.35, 1.84)
## Cars and the lettering stop drawing past these (m).
const CAR_DRAW := 260.0
const TEXT_DRAW := 110.0

static var _mats: Dictionary = {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## The structure's frame in the chunk (true world): origin at the structure's street corner (u0,
## v0) on the ground deck, x along u, z along v.
static func frame_xform(plan: CityPlan, s: Dictionary) -> Transform3D:
	var f: Dictionary = s.frame
	var lay: Dictionary = s.layout
	var o := Industrial.fp(f, float(lay.u0), float(lay.v0))
	var a: Vector2 = f.a
	var n: Vector2 = f.n
	return Transform3D(Basis(Vector3(a.x, 0.0, a.y), Vector3.UP, Vector3(n.x, 0.0, n.y)), Vector3(o.x, CarPark.ground_y(plan, s), o.y))


static func build(ch: CityChunk, s: Dictionary) -> void:
	var lay: Dictionary = s.layout
	var site: Rect2 = s.site
	ch._lot_rects.append(site)
	var xf := frame_xform(ch.plan, s)
	if ch.level != CityChunk.Level.FULL:
		_build_far(ch, s, xf)
		return
	var t0 := Time.get_ticks_usec()
	var node := Node3D.new()
	node.name = "CarPark_%d" % (int(s.seed) % 100000)
	node.transform = xf
	node.add_to_group("car_park")
	node.set_meta("car_park", s)
	ch.add_child(node)
	var g := Geo.new()
	_structure(g, ch, s, xf)
	var mi := MeshInstance3D.new()
	mi.name = "Structure"
	mi.mesh = g.commit()
	node.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var tri := ConcavePolygonShape3D.new()
	tri.backface_collision = true
	tri.set_faces(g.col)
	shape.shape = tri
	body.add_child(shape)
	node.add_child(body)
	_cars(node, g, s)
	if not g.car_faces.is_empty():
		var cshape := CollisionShape3D.new()
		var ctri := ConcavePolygonShape3D.new()
		ctri.backface_collision = true
		ctri.set_faces(g.car_faces)
		cshape.shape = ctri
		cshape.name = "Cars"
		body.add_child(cshape)
	_gates(node, s)
	_pools(node, s)
	if not OS.has_feature("web"):
		_lettering(node, s)
	# The core is solid: it occludes.
	var top := float(lay.height) + 3.2
	ch._occluder_boxes.append([xf, Vector3(CarPark.CORE * 0.5, top * 0.5, float(lay.ds) * 0.5), Vector3(CarPark.CORE - 0.6, top - 0.6, float(lay.ds) - 0.6)])
	ch.building_count += 1
	node.set_meta("build_us", Time.get_ticks_usec() - t0)


# --- The structure -------------------------------------------------------------------------------

static func _structure(g: Geo, ch: CityChunk, s: Dictionary, xf: Transform3D) -> void:
	var lay: Dictionary = s.layout
	var ls: float = lay.ls
	var ds: float = lay.ds
	var e0: float = lay.e0
	var m0: float = lay.m0
	var m1: float = lay.m1
	var r0: float = lay.r0
	var r1: float = lay.r1
	var s0: float = lay.s0
	var s1: float = lay.s1
	var decks := int(lay.decks)
	var two := int(lay.modules) == 2
	var F := CarPark.FLOOR
	var W := CarPark.WALL
	var SL := CarPark.SLAB
	var PAR := CarPark.PARAPET
	var cols: Array = lay.cols
	var col_v: Array = lay.col_v
	# --- Slabs and deck tops, every level (0 the ground, `decks` the roof). Their soffits and the
	# beams' are painted white, as real car parks paint them to make the most of the light.
	for k in decks + 1:
		var y := F * float(k)
		var roof := k == decks
		if k == 0:
			g.box("concrete", Vector3(e0, -0.9, 0.0), Vector3(ls, 0.0, ds), true, true)
		else:
			g.bottom_key = "ceiling"
			# The slab, with the ramp strip open from r0 to r1.
			g.box("concrete", Vector3(e0, y - SL, 0.0), Vector3(ls, y, s0), true, true)
			g.box("concrete", Vector3(e0, y - SL, s0), Vector3(r0, y, s1), true, true)
			g.box("concrete", Vector3(r1, y - SL, s0), Vector3(ls, y, s1), true, true)
			if two:
				g.box("concrete", Vector3(e0, y - SL, s1), Vector3(ls, y, ds), true, true)
			else:
				g.box("concrete", Vector3(e0, y - SL, s1), Vector3(ls, y, ds), true, true)
		_deck_tops(g, lay, y, roof)
		g.bottom_key = "ceiling"
		# Downstand beams under every deck over the ground, across v at each column line.
		if k >= 1:
			for cu: float in cols:
				if cu <= e0 + 0.01:
					continue
				var bu0 := clampf(cu - 0.2, e0, ls - 0.4)
				if absf(cu - r0) < 0.01:
					bu0 = cu - 0.4
				var inside := cu > r0 + 0.3 and cu < r1 - 0.3
				if inside:
					g.box("concrete", Vector3(bu0, y - SL - CarPark.BEAM, 0.0), Vector3(bu0 + 0.4, y - SL, s0), false)
					g.box("concrete", Vector3(bu0, y - SL - CarPark.BEAM, s1), Vector3(bu0 + 0.4, y - SL, ds), false)
				else:
					g.box("concrete", Vector3(bu0, y - SL - CarPark.BEAM, 0.0), Vector3(bu0 + 0.4, y - SL, ds), false)
		g.bottom_key = ""
		# Columns up to the next deck, with the level's band and a hazard foot.
		if k < decks:
			var top := F * float(k + 1) - SL - CarPark.BEAM
			for cu: float in cols:
				if cu <= e0 + 0.01:
					continue
				var cx := clampf(cu, e0 + 0.3, ls - 0.3)
				for cv: float in col_v:
					var c0 := Vector3(cx - 0.27, y, cv - 0.27)
					var c1 := Vector3(cx + 0.27, top, cv + 0.27)
					g.box("concrete", c0, c1, true, false, true)
					g.box("band_%d" % mini(k, LEVEL_COLORS.size() - 1), Vector3(cx - 0.285, y + 1.35, cv - 0.285), Vector3(cx + 0.285, y + 1.9, cv + 0.285), false, false, true)
					g.box("hazard", Vector3(cx - 0.285, y, cv - 0.285), Vector3(cx + 0.285, y + 0.45, cv + 0.285), false, false, true)
		# Spandrels: the precast panels round the edge of every deck over the ground (the roof's
		# are its parapet), a low wall round the ground deck except across the entry.
		_spandrels(g, lay, k)
		# Light fittings under the next deck: down the aisles, across the end zones, along the
		# strip's lane past the ramp.
		if k < decks:
			_lights(g, lay, k)
	# --- The ramps, one a level, in the strip; level k's rises from r0 to r1.
	for k in decks:
		_ramp(g, lay, k)
		_strip_walls(g, lay, k)
	# The roof has no ramp onward: a parapet round the opening the last ramp comes up through,
	# both sides and across its foot.
	var yr := F * float(decks)
	g.box("precast", Vector3(r0, yr - SL - 0.01, s0 - W), Vector3(r1, yr + PAR, s0 + 0.01))
	g.box("precast", Vector3(r0, yr - SL - 0.01, s1 - 0.01), Vector3(r1, yr + PAR, s1 + W))
	g.box("precast", Vector3(r0 - W, yr - SL - 0.01, s0 + 0.01), Vector3(r0 + 0.01, yr + PAR, s1 - 0.01))
	# --- The core: stairs and lift at the low-u end, the full depth, a storey over the roof.
	_core(g, lay, s)
	# --- The roof: light poles down the aisles.
	_roof(g, lay)
	# --- The ground: the entry and exit lanes, their island, the clearance bar, kerbs, the apron
	# over the pavement to the street, and hedges in the setback.
	_ground(g, ch, s, xf)


## A deck's top surfaces, band by band (CarParkDeck shader kinds; see its header).
static func _deck_tops(g: Geo, lay: Dictionary, y: float, roof: bool) -> void:
	var ls: float = lay.ls
	var ds: float = lay.ds
	var e0: float = lay.e0
	var m0: float = lay.m0
	var m1: float = lay.m1
	var r1: float = lay.r1
	var s0: float = lay.s0
	var s1: float = lay.s1
	var st0: float = lay.st0
	var rf := 1.0 if roof else 0.0
	var aisle_c := CarPark.WALL + CarPark.STALL_D + CarPark.AISLE * 0.5
	# The end zones: drives, their lane centre the zone's middle (y across u).
	g.deck(Vector3(e0, y, 0.0), Vector3(m0, y, ds), 0, rf, Vector2(0.0, (e0 + m0) * 0.5), true)
	g.deck(Vector3(m1, y, 0.0), Vector3(ls, y, ds), 0, rf, Vector2(0.0, (m1 + ls) * 0.5), true)
	# The middle, band by band.
	for b: Array in lay.bands:
		var v0: float = b[0]
		var v1: float = b[1]
		if int(b[2]) == 1:
			g.deck(Vector3(m0, y, v0), Vector3(m1, y, v1), 1, rf, Vector2(st0, float(b[3])), false)
		else:
			g.deck(Vector3(m0, y, v0), Vector3(m1, y, v1), 0, rf, Vector2(0.0, (v0 + v1) * 0.5), false)
	# Wall bands (under the spandrels and the strip's walls): plain drive.
	g.deck(Vector3(m0, y, 0.0), Vector3(m1, y, CarPark.WALL), 0, rf, Vector2(0.0, -9.0), false)
	g.deck(Vector3(m0, y, s0 - CarPark.WALL), Vector3(m1, y, s0), 0, rf, Vector2(0.0, -9.0), false)
	g.deck(Vector3(m0, y, s1), Vector3(m1, y, s1 + CarPark.WALL), 0, rf, Vector2(0.0, -9.0), false)
	if int(lay.modules) == 2:
		g.deck(Vector3(m0, y, ds - CarPark.WALL), Vector3(m1, y, ds), 0, rf, Vector2(0.0, -9.0), false)
	# The strip's lane past the ramp (the ground's under the ramp is the ramp's wedge).
	g.deck(Vector3(r1, y, s0), Vector3(m1, y, s1), 0, rf, Vector2(0.0, (s0 + s1) * 0.5), false)


## Spandrels of level k (k >= 1: a precast panel per bay from under the slab's edge to the
## parapet; the ground: a low kerb wall round the edge, open across the entry and exit lanes).
static func _spandrels(g: Geo, lay: Dictionary, k: int) -> void:
	var ls: float = lay.ls
	var ds: float = lay.ds
	var e0: float = lay.e0
	var m0: float = lay.m0
	var r0: float = lay.r0
	var r1: float = lay.r1
	var y := CarPark.FLOOR * float(k)
	var cols: Array = lay.cols
	var lo := y - CarPark.SLAB - 0.06 if k > 0 else -0.05
	var hi := y + (CarPark.PARAPET if k > 0 else 0.95)
	var t := 0.18
	# Front (v = 0) and back (v = ds; on a one-module plan the strip's outer wall is the back, so
	# no panels along the ramp there).
	for i in cols.size() - 1:
		var ua: float = cols[i]
		var ub: float = cols[i + 1]
		if ub - ua < 0.3:
			continue
		var a := ua + 0.02
		var b := ub - 0.02
		if not (k == 0 and ub <= m0 + 0.01):
			g.box("precast", Vector3(a, lo, -t), Vector3(b, hi, 0.0))
		if int(lay.modules) == 2 or not (ua >= r0 - 0.01 and ub <= r1 + 0.01):
			if int(lay.modules) == 1 and ua < r1 and ub > r0:
				# Split round the ramp's span.
				if ua < r0:
					g.box("precast", Vector3(a, lo, ds), Vector3(r0, hi, ds + t))
				if ub > r1:
					g.box("precast", Vector3(r1, lo, ds), Vector3(b, hi, ds + t))
			else:
				g.box("precast", Vector3(a, lo, ds), Vector3(b, hi, ds + t))
	# The far end (u = ls), in two or three panels across v.
	var n := int(ds / 8.5) + 1
	for j in n:
		var a := ds * float(j) / float(n) + 0.02
		var b := ds * float(j + 1) / float(n) - 0.02
		g.box("precast", Vector3(ls, lo, a), Vector3(ls + t, hi, b))
	# The roof's light-grey cap on the panels.
	if k > 0:
		g.box("coping", Vector3(e0, hi, -t - 0.02), Vector3(ls + t, hi + 0.06, 0.02), false)
		g.box("coping", Vector3(ls - 0.02, hi, -t), Vector3(ls + t + 0.02, hi + 0.06, ds + t), false)


## The ramp from level k to k + 1: the eased slope from r0 to r1 across the strip; at the ground
## a solid wedge (its end at r1 a wall), above a slab RAMP_SLAB thick.
static func _ramp(g: Geo, lay: Dictionary, k: int) -> void:
	var r0: float = lay.r0
	var s0: float = lay.s0
	var s1: float = lay.s1
	var y0 := CarPark.FLOOR * float(k)
	var n := int(ceil(CarPark.RAMP_LEN / RAMP_STEP))
	var mid := (s0 + s1) * 0.5
	for i in n:
		var xa := CarPark.RAMP_LEN * float(i) / float(n)
		var xb := CarPark.RAMP_LEN * float(i + 1) / float(n)
		var ya := y0 + CarPark.ramp_rise(xa)
		var yb := y0 + CarPark.ramp_rise(xb)
		var ua := r0 + xa
		var ub := r0 + xb
		var p0 := Vector3(ua, ya, s0)
		var p1 := Vector3(ub, yb, s0)
		var p2 := Vector3(ub, yb, s1)
		var p3 := Vector3(ua, ya, s1)
		var along := (p1 - p0).normalized()
		var up := along.cross(Vector3(0.0, 0.0, 1.0)).normalized()
		if up.y < 0.0:
			up = -up
		# Top: UV x along the slope's length, y across from the middle.
		var la := CarPark.RAMP_LEN * float(i) / float(n)
		var lb := CarPark.RAMP_LEN * float(i + 1) / float(n)
		g.quad("deck", [p0, p1, p2, p3], up, [Vector2(la, s0 - mid), Vector2(lb, s0 - mid), Vector2(lb, s1 - mid), Vector2(la, s1 - mid)],
				Vector2(2.0, 0.0), true, along)
		var ba := 0.0 if k == 0 else ya - RAMP_SLAB
		var bb := 0.0 if k == 0 else yb - RAMP_SLAB
		if k > 0:
			g.quad("ceiling", [Vector3(ua, ba, s0), Vector3(ub, bb, s0), Vector3(ub, bb, s1), Vector3(ua, ba, s1)], -up, [], Vector2.ZERO, true)
	if k == 0:
		# The wedge's end, facing on along the strip.
		var r1: float = lay.r1
		g.quad("concrete", [Vector3(r1, 0.0, s0), Vector3(r1, CarPark.FLOOR, s0), Vector3(r1, CarPark.FLOOR, s1), Vector3(r1, 0.0, s1)],
				Vector3.RIGHT, [], Vector2.ZERO, true)


## The strip's walls at level k, both sides, from r0 to r1: the deck's upstand (the parapet on
## level k's side, from under its slab) and above it whatever of the ramp's own parapet the
## upstand does not already cover - so the wall is solid where the ramp is near the deck and
## leaves an open band under the next deck where it has climbed past.
static func _strip_walls(g: Geo, lay: Dictionary, k: int) -> void:
	var r0: float = lay.r0
	var r1: float = lay.r1
	var s0: float = lay.s0
	var s1: float = lay.s1
	var y0 := CarPark.FLOOR * float(k)
	var PAR := CarPark.PARAPET
	var W := CarPark.WALL
	var ceil_y := y0 + CarPark.FLOOR - CarPark.SLAB
	var a_lo := y0 - CarPark.SLAB if k > 0 else 0.0
	var a_hi := y0 + PAR
	for side in 2:
		var v0 := s0 - W if side == 0 else s1 - 0.01
		var v1 := s0 + 0.01 if side == 0 else s1 + W
		g.box("precast", Vector3(r0, a_lo - 0.01, v0), Vector3(r1, a_hi, v1))
		var n := int(ceil(CarPark.RAMP_LEN / RAMP_STEP))
		for i in n:
			var xa := CarPark.RAMP_LEN * float(i) / float(n)
			var xb := CarPark.RAMP_LEN * float(i + 1) / float(n)
			var ba := maxf(y0 + CarPark.ramp_rise(xa) - 0.3, a_hi)
			var bb := maxf(y0 + CarPark.ramp_rise(xb) - 0.3, a_hi)
			var ta := minf(y0 + CarPark.ramp_rise(xa) + PAR, ceil_y)
			var tb := minf(y0 + CarPark.ramp_rise(xb) + PAR, ceil_y)
			if ta - ba < 0.01 and tb - bb < 0.01:
				continue
			ta = maxf(ta, ba)
			tb = maxf(tb, bb)
			g.slant_wall("precast", r0 + xa, r0 + xb, ba, ta, bb, tb, v0, v1)


## Ceiling lights of level k (under deck k + 1): fittings down every aisle, across the end zones,
## along the strip's lane past the ramp.
static func _lights(g: Geo, lay: Dictionary, k: int) -> void:
	var y := CarPark.FLOOR * float(k + 1) - CarPark.SLAB
	var m0: float = lay.m0
	var m1: float = lay.m1
	var e0: float = lay.e0
	var ls: float = lay.ls
	var ds: float = lay.ds
	for b: Array in lay.bands:
		if int(b[2]) != 0:
			continue
		var vc := (float(b[0]) + float(b[1])) * 0.5
		var n := int((m1 - m0) / LIGHT_SPACING)
		for i in n:
			var u := m0 + (float(i) + 0.5) * (m1 - m0) / float(n)
			g.box("light", Vector3(u - 0.6, y - 0.07, vc - 0.09), Vector3(u + 0.6, y, vc + 0.09), false)
	var nv := int(ds / LIGHT_SPACING)
	for j in nv:
		var v := (float(j) + 0.5) * ds / float(nv)
		for uc: float in [(e0 + m0) * 0.5, (m1 + ls) * 0.5]:
			g.box("light", Vector3(uc - 0.09, y - 0.07, v - 0.6), Vector3(uc + 0.09, y, v + 0.6), false)
	var vs := (float(lay.s0) + float(lay.s1)) * 0.5
	var r1: float = lay.r1
	if m1 - r1 > 3.0:
		var nr := maxi(1, int((m1 - r1) / LIGHT_SPACING))
		for i in nr:
			var u := r1 + (float(i) + 0.5) * (m1 - r1) / float(nr)
			g.box("light", Vector3(u - 0.6, y - 0.07, vs - 0.09), Vector3(u + 0.6, y, vs + 0.09), false)
	# Wall lights along the ramp, on the strip's inner wall at the ramp's height.
	var r0: float = lay.r0
	for i in 4:
		var x := CarPark.RAMP_LEN * (float(i) + 0.5) / 4.0
		var yy := CarPark.FLOOR * float(k) + CarPark.ramp_rise(x) + 2.0
		yy = minf(yy, CarPark.FLOOR * float(k + 1) - CarPark.SLAB - 0.2)
		g.box("light", Vector3(r0 + x - 0.5, yy - 0.06, float(lay.s0) + 0.0), Vector3(r0 + x + 0.5, yy + 0.06, float(lay.s0) + 0.08), false)


## The stair and lift core: walls the full depth at the low-u end, a glazed stair slot on the
## street face, a door onto every deck from the end zone, a lift overrun and the P sign's panel.
static func _core(g: Geo, lay: Dictionary, s: Dictionary) -> void:
	var ds: float = lay.ds
	var e0: float = lay.e0
	var top := float(lay.height) + 3.0
	var C := CarPark.CORE
	var t := 0.25
	# Walls: the street face round the slot, the back, the outer side, the side onto the decks.
	var slot0 := 1.0
	var slot1 := 2.6
	g.box("precast", Vector3(0.0, -0.9, -0.05), Vector3(slot0, top, t))
	g.box("precast", Vector3(slot1, -0.9, -0.05), Vector3(C, top, t))
	g.box("precast", Vector3(slot0, 2.7, -0.05), Vector3(slot1, 3.3, t))
	g.box("glass", Vector3(slot0, 3.3, 0.0), Vector3(slot1, top - 0.6, 0.12), false)
	g.box("precast", Vector3(slot0, top - 0.6, -0.05), Vector3(slot1, top, t))
	# The street door into the lobby (glass, lit), its canopy.
	g.box("glass_lit", Vector3(slot0, 0.0, 0.0), Vector3(slot1, 2.7, 0.12), false)
	g.box("steel", Vector3(slot0 - 0.4, 2.75, -1.3), Vector3(slot1 + 0.4, 2.9, 0.0))
	g.box("precast", Vector3(0.0, -0.9, ds - t), Vector3(C, top, ds))
	g.box("precast", Vector3(0.0, -0.9, 0.0), Vector3(t, top, ds))
	g.box("precast", Vector3(C - t, -0.9, 0.0), Vector3(C, top, ds))
	g.box("roofing", Vector3(0.0, top, 0.0), Vector3(C, top + 0.12, ds))
	# The lift overrun.
	g.box("precast", Vector3(0.6, top, ds * 0.5 - 1.6), Vector3(C - 0.6, top + 2.2, ds * 0.5 + 1.6))
	# A steel door from the stairs onto every deck, a lit EXIT sign over it.
	var decks := int(lay.decks)
	for k in decks + 1:
		var y := CarPark.FLOOR * float(k)
		var dv := 2.6
		g.box("door", Vector3(C, y, dv - 0.5), Vector3(C + 0.06, y + 2.1, dv + 0.5), false)
		g.box("exit_sign", Vector3(C, y + 2.2, dv - 0.25), Vector3(C + 0.08, y + 2.42, dv + 0.25), false)
	# Vertical joints in the panels (darker strips), and a horizontal band at every deck.
	for k in decks + 1:
		var y := CarPark.FLOOR * float(k)
		g.box("coping", Vector3(-0.02, y - 0.02, -0.07), Vector3(C + 0.02, y + 0.02, -0.04), false)
	# The P panel at the top of the street face (the letter is a TextMesh).
	g.box("sign_blue", Vector3(slot1 + 0.15, top - 2.6, -0.14), Vector3(C - 0.25, top - 0.4, -0.05), false)


## The roof: light poles on the aisles' centre lines.
static func _roof(g: Geo, lay: Dictionary) -> void:
	var y := CarPark.FLOOR * float(lay.decks)
	var m0: float = lay.m0
	var m1: float = lay.m1
	for b: Array in lay.bands:
		if int(b[2]) != 0:
			continue
		var vc := (float(b[0]) + float(b[1])) * 0.5
		var n := maxi(1, int((m1 - m0) / ROOF_POLE_SPACING))
		for i in n:
			var u := m0 + (float(i) + 0.5) * (m1 - m0) / float(n)
			g.box("hazard", Vector3(u - 0.35, y, vc - 0.35), Vector3(u + 0.35, y + 0.5, vc + 0.35))
			g.box("steel", Vector3(u - 0.09, y + 0.5, vc - 0.09), Vector3(u + 0.09, y + ROOF_POLE_H, vc + 0.09))
			for sv: float in [-1.0, 1.0]:
				g.box("steel", Vector3(u - 0.06, y + ROOF_POLE_H - 0.12, vc + sv * 0.05), Vector3(u + 0.06, y + ROOF_POLE_H - 0.02, vc + sv * 1.4))
				g.box("steel", Vector3(u - 0.22, y + ROOF_POLE_H - 0.22, vc + sv * 1.4 - 0.3), Vector3(u + 0.22, y + ROOF_POLE_H - 0.02, vc + sv * 1.4 + 0.3), false)
				g.box("lamp_head", Vector3(u - 0.18, y + ROOF_POLE_H - 0.25, vc + sv * 1.4 - 0.26), Vector3(u + 0.18, y + ROOF_POLE_H - 0.21, vc + sv * 1.4 + 0.26), false)


## The ground: the island between the lanes, the clearance bar, the apron down over the pavement
## to the street, kerbs, hedges in the setback.
static func _ground(g: Geo, ch: CityChunk, s: Dictionary, xf: Transform3D) -> void:
	var lay: Dictionary = s.layout
	var e0: float = lay.e0
	var m0: float = lay.m0
	var ls: float = lay.ls
	var iu := e0 + CarPark.ISLAND_U
	# The island: a kerbed nose of yellow, the ticket and pay machines on it.
	g.box("kerb_yellow", Vector3(iu, 0.0, 0.3), Vector3(iu + CarPark.ISLAND_W, 0.16, 6.2))
	g.box("machine", Vector3(iu + 0.05, 0.16, CarPark.ARM_V - 1.1), Vector3(iu + 0.55, 1.45, CarPark.ARM_V - 0.7))
	g.box("screen", Vector3(iu + CarPark.ISLAND_W - 0.04, 0.95, CarPark.ARM_V - 1.05), Vector3(iu + CarPark.ISLAND_W + 0.005, 1.25, CarPark.ARM_V - 0.75), false)
	g.box("machine", Vector3(iu + 0.05, 0.16, CarPark.ARM_V + 0.9), Vector3(iu + 0.55, 1.45, CarPark.ARM_V + 1.3))
	g.box("screen", Vector3(iu - 0.005, 0.95, CarPark.ARM_V + 0.95), Vector3(iu + 0.04, 1.25, CarPark.ARM_V + 1.25), false)
	# The barrier posts (the arms are CarParkGate nodes).
	g.box("hazard", Vector3(iu + 0.08, 0.16, CarPark.ARM_V - 0.2), Vector3(iu + 0.52, 1.05, CarPark.ARM_V + 0.2))
	# Bollards guarding the core's corner and the island's nose.
	for p: Vector2 in [Vector2(e0 + 0.35, 0.45), Vector2(iu + CarPark.ISLAND_W * 0.5, 0.0)]:
		g.box("hazard", Vector3(p.x - 0.11, 0.0, p.y - 0.11), Vector3(p.x + 0.11, 1.0, p.y + 0.11))
	# The clearance bar across the opening, hung from the level 1 spandrel's soffit.
	var cb := CarPark.CLEARANCE
	g.box("hazard", Vector3(e0 + 0.15, cb, -0.4), Vector3(m0 - 0.15, cb + 0.14, -0.26), false)
	for cu: float in [e0 + 0.3, m0 - 0.3]:
		g.box("steel", Vector3(cu - 0.015, cb + 0.14, -0.35), Vector3(cu + 0.015, CarPark.FLOOR - CarPark.SLAB, -0.31), false)
	# The apron: a kerb ramp up off the road, flat over the pavement a hair above it, then up the
	# setback to the ground deck. Heights from the chunk's own ground, brought into the frame.
	var w := ch.plan.sidewalk_width + CarPark.SETBACK
	var inv := xf.affine_inverse()
	var a := e0 - 0.6
	var b := m0 + 0.6
	var prof := []
	for u: float in [a, b]:
		var wp := xf * Vector3(u, 0.0, -w)
		var road := (inv * Vector3(wp.x, ch._gy(wp.x, wp.z) + CityChunk.ROAD_TOP, wp.z)).y + 0.01
		var pp := xf * Vector3(u, 0.0, -CarPark.SETBACK)
		var pave := (inv * Vector3(pp.x, ch._gy(pp.x, pp.z) + CityChunk.SIDEWALK_TOP, pp.z)).y + 0.015
		prof.append([road, minf(pave, 0.0)])
	var vs := [-w, -w + 0.9, -CarPark.SETBACK, -0.15, 0.0]
	for j in 4:
		var ya := []
		for e in 2:
			var pr: Array = prof[e]
			ya.append([pr[0], pr[1], pr[1], 0.0, 0.0][j])
			ya.append([pr[1], pr[1], 0.0, 0.0, 0.0][j])
		# Flared at the kerb, so a car swinging in off the kerb lane stays on it.
		var fl := [2.6, 2.6, 1.2, 0.0, 0.0]
		var a0 := a - float(fl[j])
		var a1 := a - float(fl[j + 1])
		var b0 := b + float(fl[j])
		var b1 := b + float(fl[j + 1])
		var q := [Vector3(a0, ya[0], vs[j]), Vector3(b0, ya[2], vs[j]), Vector3(b1, ya[3], vs[j + 1]), Vector3(a1, ya[1], vs[j + 1])]
		g.quad("apron", q, Vector3.UP, [], Vector2.ZERO, true)
		# Its flanks down to the pavement.
		for side in 2:
			var u0 := a0 if side == 0 else b0
			var u1 := a1 if side == 0 else b1
			var y0: float = ya[0] if side == 0 else ya[2]
			var y1: float = ya[1] if side == 0 else ya[3]
			var nrm := Vector3.LEFT if side == 0 else Vector3.RIGHT
			g.quad("apron", [Vector3(u0, y0 - 0.25, vs[j]), Vector3(u0, y0, vs[j]), Vector3(u1, y1, vs[j + 1]), Vector3(u1, y1 - 0.25, vs[j + 1])], nrm, [], Vector2.ZERO, false)
	# The ENTER / EXIT board over the lanes, under the level-1 spandrel.
	g.box("door", Vector3(e0 + 0.2, CarPark.CLEARANCE + 0.22, -0.32), Vector3(m0 - 0.2, CarPark.FLOOR - CarPark.SLAB - 0.06, -0.2), false)
	# The blade sign at the far corner: a lit panel standing out from the facade.
	var by := CarPark.FLOOR * 2.0
	g.box("sign_blue", Vector3(ls - 0.72, by - 3.6, -1.5), Vector3(ls - 0.58, by + 1.2, -0.2), false)
	g.box("steel", Vector3(ls - 0.7, by - 3.7, -1.55), Vector3(ls - 0.6, by + 1.3, -1.45), false)
	# Hedges in the setback along the rest of the front, in raised concrete planters.
	g.box("precast", Vector3(m0 + 0.6, -0.3, -CarPark.SETBACK + 0.1), Vector3(ls, 0.45, -0.1))
	g.box("hedge", Vector3(m0 + 0.7, 0.45, -CarPark.SETBACK + 0.18), Vector3(ls - 0.1, 1.15, -0.18), false)


# --- Cars, gates, pools, letters ------------------------------------------------------------------

## The parked cars: stalls taken by a hash of the car park, the level and the stall.
static func _cars(node: Node3D, g: Geo, s: Dictionary) -> void:
	var lay: Dictionary = s.layout
	var decks := int(lay.decks)
	var st0: float = lay.st0
	var n := int(lay.stalls)
	var seed_v := int(s.seed)
	var inside: Array = [[], [], [], []]
	var roof: Array = [[], [], [], []]
	var cols: Array = [[], [], [], []]
	var rcols: Array = [[], [], [], []]
	for k in decks + 1:
		var y := CarPark.FLOOR * float(k)
		var top := k == decks
		var fill := CarPark.ROOF_FILL if top else CarPark.FILL
		for bi in (lay.bands as Array).size():
			var b: Array = lay.bands[bi]
			if int(b[2]) != 1:
				continue
			var back: float = b[3]
			var dir := 1.0 if back < float(b[0]) + 0.01 else -1.0
			for i in n:
				if _h01([seed_v, k, bi, i, "cp_car"]) >= fill:
					continue
				var u := st0 + (float(i) + 0.5) * CarPark.STALL_W + (_h01([seed_v, k, bi, i, "cp_dx"]) - 0.5) * 0.25
				var v := back + dir * (2.55 + _h01([seed_v, k, bi, i, "cp_dv"]) * 0.3)
				var kind := 0
				var r := _h01([seed_v, k, bi, i, "cp_kind"])
				if r > 0.55:
					kind = 2 if r < 0.8 else (1 if r < 0.9 else 3)
				# Nose toward the back wall: the car's nose is -Z; dir +1 means the wall is at -v.
				var yaw := 0.0 if dir > 0.0 else PI
				yaw += (_h01([seed_v, k, bi, i, "cp_yaw"]) - 0.5) * 0.06
				var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(u, y + 0.005, v))
				var paint: Color = ArenaGrounds.CAR_PAINTS[absi(hash([seed_v, k, bi, i, "cp_paint"])) % ArenaGrounds.CAR_PAINTS.size()]
				(roof[kind] if top else inside[kind]).append(xf)
				(rcols[kind] if top else cols[kind]).append(paint)
				g.car_box(xf, CAR_BOX)
	for kind in 4:
		for pass_i in 2:
			var xfs: Array = roof[kind] if pass_i == 1 else inside[kind]
			if xfs.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = ArenaGrounds.car_mesh(kind)
			mm.instance_count = xfs.size()
			var pc: Array = rcols[kind] if pass_i == 1 else cols[kind]
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i])
				mm.set_instance_color(i, pc[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Cars%s%d" % ["Roof" if pass_i == 1 else "", kind]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if pass_i == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = CAR_DRAW
			node.add_child(mmi)


## The barrier arms at the entry and the exit: on the island, lying across each lane.
static func _gates(node: Node3D, s: Dictionary) -> void:
	var lay: Dictionary = s.layout
	var iu: float = float(lay.e0) + CarPark.ISLAND_U
	for side in 2:
		var gate := CarParkGate.new()
		gate.name = "GateIn" if side == 0 else "GateOut"
		# The entry lane is +u of the island, the exit -u.
		var px := iu + CarPark.ISLAND_W * 0.5 + (0.15 if side == 0 else -0.15)
		gate.position = Vector3(px, 0.98, CarPark.ARM_V + (0.0 if side == 0 else 0.0))
		gate.side = 1.0 if side == 0 else -1.0
		var arm := MeshInstance3D.new()
		arm.name = "Arm"
		arm.mesh = arm_mesh()
		arm.scale = Vector3(gate.side, 1.0, 1.0)
		var pivot := Node3D.new()
		pivot.name = "Pivot"
		pivot.add_child(arm)
		gate.add_child(pivot)
		gate.arm = pivot
		gate.add_to_group("car_park_gate")
		node.add_child(gate)


## A barrier arm along +x from its pivot: a red and white striped tube with a counterweight.
static func arm_mesh() -> Mesh:
	if _mats.has("arm_mesh"):
		return _mats.arm_mesh
	var g := Geo.new()
	var L := CarPark.ARM_LEN
	var n := 8
	for i in n:
		var a := 0.1 + L * float(i) / float(n)
		var b := 0.1 + L * float(i + 1) / float(n)
		g.box("arm_red" if i % 2 == 0 else "arm_white", Vector3(a, -0.045, -0.035), Vector3(b, 0.045, 0.035), false)
	g.box("steel", Vector3(-0.32, -0.08, -0.07), Vector3(0.1, 0.08, 0.07), false)
	var mesh := g.commit()
	_mats.arm_mesh = mesh
	return mesh


## Additive light pools on each deck under its fittings (night, lamp_factor), as one MultiMesh.
static func _pools(node: Node3D, s: Dictionary) -> void:
	var lay: Dictionary = s.layout
	var m0: float = lay.m0
	var m1: float = lay.m1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = PropFactory.light_pool(Color(0.9, 0.96, 1.0), 0.55)
	var xfs: Array[Transform3D] = []
	for k in int(lay.decks):
		var y := CarPark.FLOOR * float(k) + 0.03
		for b: Array in lay.bands:
			if int(b[2]) != 0:
				continue
			var vc := (float(b[0]) + float(b[1])) * 0.5
			var n := int((m1 - m0) / (LIGHT_SPACING * 2.0))
			for i in n:
				var u := m0 + (float(i) + 0.5) * (m1 - m0) / float(n)
				xfs.append(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(8.0, 1.0, 8.0)), Vector3(u, y, vc)))
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Pools"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 200.0
	node.add_child(mmi)


## The operator's name over the entry, ENTER / EXIT, the levels on the core's wall, the P.
static func _lettering(node: Node3D, s: Dictionary) -> void:
	var lay: Dictionary = s.layout
	var e0: float = lay.e0
	var m0: float = lay.m0
	var iu := e0 + CarPark.ISLAND_U
	var face := Basis(Vector3.UP, PI)
	var add := func(text: String, size: float, color: Color, at: Vector3, basis: Basis, draw: float) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = BigVehicles.text_mesh(text, size, color)
		mi.transform = Transform3D(basis, at)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = draw
		node.add_child(mi)
	# The name along the level-1 spandrel over the entry, facing the street (-v).
	add.call(String(s.name), 0.55, Color(0.95, 0.95, 0.92), Vector3((e0 + float(lay.m1)) * 0.5, CarPark.FLOOR + 0.55, -0.2), face, TEXT_DRAW * 1.6)
	add.call("ENTER", 0.26, Color(0.35, 1.0, 0.45), Vector3((iu + m0) * 0.5, CarPark.CLEARANCE + 0.45, -0.33), face, TEXT_DRAW)
	add.call("EXIT", 0.26, Color(1.0, 0.3, 0.25), Vector3((e0 + iu) * 0.5, CarPark.CLEARANCE + 0.45, -0.33), face, TEXT_DRAW)
	add.call("CLEARANCE 7'0\"", 0.13, Color(0.08, 0.08, 0.08), Vector3((e0 + m0) * 0.5, CarPark.CLEARANCE + 0.07, -0.41), face, 60.0)
	# The P, big, on the core's street face.
	var top := float(lay.height) + 3.0
	add.call("P", 1.7, Color(1, 1, 1), Vector3((2.6 + CarPark.CORE - 0.1) * 0.5, top - 1.5, -0.16), face, 600.0)
	# The levels on the core's wall facing the end zone, and on the far end wall facing the aisles.
	var side := Basis(Vector3.UP, PI * 0.5)
	for k in int(lay.decks) + 1:
		var y := CarPark.FLOOR * float(k)
		var label := "ROOF" if k == int(lay.decks) else ("LEVEL " + String(LEVEL_NAMES[mini(k, LEVEL_NAMES.size() - 1)]))
		var col: Color = LEVEL_COLORS[mini(k, LEVEL_COLORS.size() - 1)]
		add.call(label, 0.42, col, Vector3(CarPark.CORE + 0.02, y + 1.6, 6.5), side, 45.0)
		if k < int(lay.decks):
			add.call("UP", 0.5, Color(0.92, 0.92, 0.88), Vector3(float(lay.r0) + 1.6, y + 0.03, (float(lay.s0) + float(lay.s1)) * 0.5),
					Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5), 40.0)
	# The blade sign at the corner by the entry: P A R K down a lit panel.
	var letters := "PARK"
	for i in letters.length():
		var ly := CarPark.FLOOR * 2.0 - float(i) * 1.12 + 0.55
		add.call(letters[i], 0.85, Color(1, 1, 1), Vector3(float(lay.ls) - 0.735, ly, -0.85), Basis(Vector3.UP, -PI * 0.5), 400.0)
		add.call(letters[i], 0.85, Color(1, 1, 1), Vector3(float(lay.ls) - 0.565, ly, -0.85), Basis(Vector3.UP, PI * 0.5), 400.0)


# --- Far ------------------------------------------------------------------------------------------

## LOD chunks and the far city: per storey a dark band (the open deck) over a concrete spandrel,
## and the core, as far boxes (the old path, no code). The batch adds the relief: taken back off.
static func _build_far(ch: CityChunk, s: Dictionary, xf: Transform3D) -> void:
	var lay: Dictionary = s.layout
	var ls: float = lay.ls
	var ds: float = lay.ds
	var decks := int(lay.decks)
	var seedf := float(int(s.seed) % 997) / 997.0
	var put := func(lo: Vector3, hi: Vector3, color: Color) -> void:
		var c := xf * ((lo + hi) * 0.5)
		c.y -= ch._gy(c.x, c.z)
		var rot := xf.basis * Basis.from_scale(hi - lo)
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(rot, c), color, Color(0.0, 0.0, seedf, 1.0))
	put.call(Vector3(CarPark.CORE, -0.5, 0.0), Vector3(ls, CarPark.FLOOR - CarPark.SLAB - 0.06, ds), Color(0.18, 0.18, 0.19))
	for k in range(1, decks + 1):
		var y := CarPark.FLOOR * float(k)
		put.call(Vector3(CarPark.CORE, y - CarPark.SLAB - 0.06, -0.18), Vector3(ls + 0.18, y + CarPark.PARAPET, ds + 0.18), CONCRETE * 0.92)
		if k < decks:
			put.call(Vector3(CarPark.CORE + 0.3, y + CarPark.PARAPET, 0.3), Vector3(ls - 0.3, y + CarPark.FLOOR - CarPark.SLAB - 0.06, ds - 0.3), Color(0.16, 0.16, 0.17))
	put.call(Vector3(0.0, -0.5, 0.0), Vector3(CarPark.CORE, float(lay.height) + 3.0, ds), CONCRETE * 0.85)
	var centre := xf * Vector3(ls * 0.5, float(lay.height) * 0.5, ds * 0.5)
	var size := Vector3(ls, float(lay.height), ds)
	var a3 := xf.basis.x
	ch._add_lod_shape(size if absf(a3.x) > 0.5 else Vector3(ds, float(lay.height), ls), centre)


# --- Materials --------------------------------------------------------------------------------------

static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	if key.begins_with("band_"):
		var c: Color = LEVEL_COLORS[int(key.trim_prefix("band_")) % LEVEL_COLORS.size()]
		m = PropFactory.material(c, 0.55)
	else:
		match key:
			"deck":
				var sm := ShaderMaterial.new()
				sm.shader = load("res://shaders/car_park_deck.gdshader")
				sm.set_shader_parameter("albedo_tex", PropFactory.texture("concrete", "Color"))
				sm.set_shader_parameter("normal_tex", PropFactory.texture("concrete", "NormalGL"))
				sm.set_shader_parameter("rough_tex", PropFactory.texture("concrete", "Roughness"))
				sm.set_shader_parameter("stall_w", CarPark.STALL_W)
				sm.set_shader_parameter("stall_d", CarPark.STALL_D)
				m = sm
			"concrete":
				m = PropFactory.pbr("concrete", 3.0, CONCRETE_DARK.lerp(CONCRETE, 0.6))
			"precast":
				m = PropFactory.pbr("concrete", 2.5, CONCRETE)
			"ceiling":
				# Painted white, and lit from below by the fittings and the bright deck (a soffit
				# under a slab sees no sky: without this it drew as a brown-black lid).
				var cm := PropFactory.pbr("plaster_white", 3.0, Color(0.93, 0.93, 0.9)).duplicate() as StandardMaterial3D
				cm.emission_enabled = true
				cm.emission = Color(0.93, 0.93, 0.9)
				cm.emission_energy_multiplier = 0.16
				m = cm
			"coping":
				m = PropFactory.material(Color(0.62, 0.62, 0.6), 0.8)
			"roofing":
				m = PropFactory.material(Color(0.5, 0.5, 0.5), 0.9)
			"apron":
				m = PropFactory.pbr("concrete", 4.0, Color(0.86, 0.85, 0.82))
			"hazard", "kerb_yellow":
				m = _hazard_material()
			"steel":
				var sm := StandardMaterial3D.new()
				sm.albedo_color = Color(0.55, 0.56, 0.58)
				sm.metallic = 0.8
				sm.roughness = 0.38
				m = sm
			"machine":
				m = PropFactory.material(Color(0.1, 0.22, 0.42), 0.4)
			"door":
				m = PropFactory.material(Color(0.34, 0.36, 0.38), 0.5)
			"glass":
				var gm := StandardMaterial3D.new()
				gm.albedo_color = Color(0.06, 0.08, 0.09)
				gm.roughness = 0.06
				gm.metallic = 0.5
				m = gm
			"hedge":
				m = PropFactory.material(Color(0.13, 0.24, 0.09), 0.95)
			"arm_red":
				m = PropFactory.material(Color(0.72, 0.06, 0.05), 0.45)
			"arm_white":
				m = PropFactory.material(Color(0.9, 0.9, 0.88), 0.45)
			"light":
				m = _glow_material(Vector3(1.0, 0.98, 0.92), LIGHT_GLOW, 0.0)
			"lamp_head":
				m = _glow_material(Vector3(1.0, 0.92, 0.78), 4.0, 1.0)
			"glass_lit":
				m = _glow_material(Vector3(0.95, 0.82, 0.6), 0.9, 0.0)
			"screen":
				m = _glow_material(Vector3(0.35, 0.75, 1.0), 1.4, 0.0)
			"exit_sign":
				m = _glow_material(Vector3(0.2, 1.0, 0.3), 2.0, 0.0)
			"sign_blue":
				m = _glow_material(Vector3(0.05, 0.22, 0.85), 1.2, 0.0)
			_:
				m = PropFactory.material(Color(0.5, 0.5, 0.5))
	_mats[key] = m
	return m


## Yellow and black chevrons (the bollards, the column feet, the clearance bar, the island's kerb),
## in world space.
static func _hazard_material() -> Material:
	if _mats.has("hazard_mat"):
		return _mats.hazard_mat
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
#include "res://shaders/color_space.gdshaderinc"
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float s = fract((wp.x + wp.z + wp.y) * 2.6);
	float px = fwidth((wp.x + wp.z + wp.y) * 2.6);
	float b = smoothstep(0.5 - px, 0.5 + px, s);
	vec3 c = mix(vec3(0.75, 0.52, 0.02), vec3(0.025, 0.025, 0.025), b);
	ALBEDO = cs_out(c);
	ROUGHNESS = 0.55;
}
"""
	sm.shader = sh
	_mats.hazard_mat = sm
	return sm


## A fitting or a sign that glows: `night_only` 0 lights it day and night (a car park's ceiling
## lights never go off), 1 only after dark (lamp_factor).
static func _glow_material(color: Vector3, strength: float, night_only: float) -> Material:
	var sm := ShaderMaterial.new()
	var key := "glow_shader"
	if not _mats.has(key):
		var sh := Shader.new()
		sh.code = """shader_type spatial;
#include "res://shaders/color_space.gdshaderinc"
global uniform float lamp_factor;
uniform vec3 glow = vec3(1.0);
uniform float strength = 3.0;
uniform float night_only = 0.0;
void fragment() {
	float on = mix(1.0, 0.08 + 0.92 * lamp_factor, night_only);
	ALBEDO = cs_out(glow * 0.6);
	ROUGHNESS = 0.4;
	EMISSION = cs_out(glow * strength * on);
}
"""
		_mats[key] = sh
	sm.shader = _mats[key]
	sm.set_shader_parameter("glow", color)
	sm.set_shader_parameter("strength", strength)
	sm.set_shader_parameter("night_only", night_only)
	return sm


# --- Geometry ----------------------------------------------------------------------------------------

## Triangles into packed arrays, a surface per material key, and the collision faces beside them.
## Every vertex carries a normal, a tangent, UV and UV2 (one format for every surface).
class Geo:
	var _s: Dictionary = {}
	var col := PackedVector3Array()
	var car_faces := PackedVector3Array()
	## The material boxes' bottom faces take when set (the decks' painted soffits).
	var bottom_key := ""

	func _surf(key: String) -> CpSurf:
		if not _s.has(key):
			_s[key] = CpSurf.new()
		return _s[key]

	## A triangle facing `n` (wound to face it: Godot's fronts are clockwise seen from the front).
	func tri(key: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, uv2: Vector2,
			collide: bool, tangent: Vector3 = Vector3.ZERO) -> void:
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
		var s := _surf(key)
		var tg := tangent
		if tg == Vector3.ZERO:
			tg = Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.BACK
		s.v.append(a)
		s.v.append(b)
		s.v.append(c)
		s.uv.append(ua)
		s.uv.append(ub)
		s.uv.append(uc)
		for i in 3:
			s.n.append(n)
			s.t.append(tg.x)
			s.t.append(tg.y)
			s.t.append(tg.z)
			s.t.append(1.0)
			s.uv2.append(uv2)
		if collide:
			col.append(a)
			col.append(b)
			col.append(c)

	## A quad (corners in order round it) facing `n`. `uvs` empty: metres by the normal.
	func quad(key: String, q: Array, n: Vector3, uvs: Array, uv2: Vector2, collide: bool, tangent: Vector3 = Vector3.ZERO) -> void:
		var u := uvs
		if u.is_empty():
			u = []
			for p: Vector3 in q:
				u.append(Vector2(p.x + p.z, p.y) if absf(n.y) < 0.5 else Vector2(p.x, p.z))
		tri(key, q[0], q[1], q[2], n, u[0], u[1], u[2], uv2, collide, tangent)
		tri(key, q[0], q[2], q[3], n, u[0], u[2], u[3], uv2, collide, tangent)

	## An axis-aligned box from `lo` to `hi`. `no_top` / `no_bottom` leave those faces out (a
	## deck's top is drawn by deck()); collision takes every face drawn, and the top too.
	func box(key: String, lo: Vector3, hi: Vector3, collide: bool = true, no_top: bool = false, no_bottom: bool = false) -> void:
		var x0 := lo.x
		var y0 := lo.y
		var z0 := lo.z
		var x1 := hi.x
		var y1 := hi.y
		var z1 := hi.z
		var faces := [
			[Vector3.RIGHT, Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1)],
			[Vector3.LEFT, Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x0, y0, z0)],
			[Vector3.UP, Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0)],
			[Vector3.DOWN, Vector3(x0, y0, z1), Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1)],
			[Vector3.BACK, Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(x0, y0, z1)],
			[Vector3.FORWARD, Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y0, z0)],
		]
		for f: Array in faces:
			var n: Vector3 = f[0]
			if no_top and n == Vector3.UP:
				if collide:
					col.append_array(PackedVector3Array([f[1], f[2], f[3], f[1], f[3], f[4]]))
				continue
			if no_bottom and n == Vector3.DOWN:
				continue
			quad(bottom_key if n == Vector3.DOWN and bottom_key != "" else key, [f[1], f[2], f[3], f[4]], n, [], Vector2.ZERO, collide)

	## A deck's top over [lo.x, hi.x] x [lo.z, hi.z] at lo.y: `kind` and `roof` into UV2, UV in
	## metres - x along u from `origin.x`, y across: from `origin.y` (a drive's centre, or a stall
	## row's back wall; the row's y counts away from its wall). `across_u`: a drive running along
	## v (an end zone), whose UV x is v and y is u from its centre.
	func deck(lo: Vector3, hi: Vector3, kind: int, roof: float, origin: Vector2, across_u: bool) -> void:
		var y := lo.y
		var q := [Vector3(lo.x, y, lo.z), Vector3(hi.x, y, lo.z), Vector3(hi.x, y, hi.z), Vector3(lo.x, y, hi.z)]
		var uvs := []
		for p: Vector3 in q:
			if across_u:
				uvs.append(Vector2(p.z, p.x - origin.y))
			elif kind == 1:
				uvs.append(Vector2(p.x - origin.x, absf(p.z - origin.y)))
			else:
				uvs.append(Vector2(p.x - origin.x, p.z - origin.y))
		quad("deck", q, Vector3.UP, uvs, Vector2(float(kind), roof), false, Vector3.BACK if across_u else Vector3.RIGHT)

	## A wall along u from ua to ub between v0 and v1, its bottom and top sloping (ba..bb, ta..tb).
	func slant_wall(key: String, ua: float, ub: float, ba: float, ta: float, bb: float, tb: float, v0: float, v1: float) -> void:
		for side in 2:
			var v := v0 if side == 0 else v1
			var n := Vector3.FORWARD if side == 0 else Vector3.BACK
			quad(key, [Vector3(ua, ba, v), Vector3(ub, bb, v), Vector3(ub, tb, v), Vector3(ua, ta, v)], n, [], Vector2.ZERO, true)
		var up := Vector3(-(tb - ta), ub - ua, 0.0).normalized()
		quad(key, [Vector3(ua, ta, v0), Vector3(ub, tb, v0), Vector3(ub, tb, v1), Vector3(ua, ta, v1)], up, [], Vector2.ZERO, true)
		var dn := Vector3(bb - ba, -(ub - ua), 0.0).normalized()
		quad(key, [Vector3(ua, ba, v0), Vector3(ub, bb, v0), Vector3(ub, bb, v1), Vector3(ua, ba, v1)], dn, [], Vector2.ZERO, true)

	## A parked car's collision: a box of `size` (length along its z) under transform `xf`.
	func car_box(xf: Transform3D, size: Vector3) -> void:
		var h := Vector3(size.z * 0.5, size.y, size.x * 0.5)
		var c := [Vector3(-h.x, 0.15, -h.z), Vector3(h.x, 0.15, -h.z), Vector3(h.x, 0.15, h.z), Vector3(-h.x, 0.15, h.z),
			Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
		for i in c.size():
			c[i] = xf * (c[i] as Vector3)
		for f: Array in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
			car_faces.append_array(PackedVector3Array([c[f[0]], c[f[1]], c[f[2]], c[f[0]], c[f[2]], c[f[3]]]))

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for key: String in _s:
			var s: CpSurf = _s[key]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = s.v
			arrays[Mesh.ARRAY_NORMAL] = s.n
			arrays[Mesh.ARRAY_TANGENT] = s.t
			arrays[Mesh.ARRAY_TEX_UV] = s.uv
			arrays[Mesh.ARRAY_TEX_UV2] = s.uv2
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, CarParkBuild.material(key))
		return mesh


## One surface's vertex arrays (members, so appending changes them in place: a packed array held
## in an Array or a Dictionary is a value, and appending to it appends to a copy).
class CpSurf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
