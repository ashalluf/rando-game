class_name ReplicaHouses
extends RefCounted
## The houses of a replica area (ReplicaAreas lots): stucco beach houses, duplexes, small
## apartment blocks with tuck-under parking, flat-roofed modern boxes and the long condominium
## with its green glass balconies. Real geometry, not a textured box: the wall is cut round every
## opening, each opening has its reveals, a frame and glass (shaders/house_glass.gdshader) set
## back in it, garage doors carry their panel grooves, roofs are hipped or gabled clay tile with
## eaves, soffits and fascias, or flat behind a coped parapet, and balconies are slabs with glass
## or steel rails. What sells a street of houses from a car window is exactly that depth: the
## shadow line under an eave, the dark slot of a garage, glass sitting back from the wall face.
##
## Everything a lot looks like was rolled with the lot (ReplicaAreas._lot()), and the footprint
## here comes from `frame()`, a pure function of the lot, so the parked cars can keep out of the
## driveways the houses build and the far tiers draw the same box.
##
## FULL chunks build it into the chunk's ReplicaBuilder surfaces (one mesh per material for every
## house in the chunk); LOD chunks draw each house as the city's LOD boxes plus a roof prism.

# --- Tunables --------------------------------------------------------------------------------

## Storey height, metres (the condo sets its own).
const STOREY := 3.0
## Eave overhang past the wall, and the roof pitch as rise over run (5:12, about 23 degrees).
const EAVE := 0.55
const PITCH := 0.42
## How far glass sits back from the wall face, and the width of its frame.
const REVEAL := 0.13
const FRAME := 0.055
## Metres per tile of the clay roof texture (22 barrels across it, about 0.2 m each).
const TILE_M := 4.4
## Parapet height above a flat roof, and a balcony's rail.
const PARAPET := 0.85
const RAIL_H := 1.05
## The garage opening, and the entry door (its width is ReplicaAreas.HOUSE_DOOR_W, like the gaps
## to the neighbours: the footprint is worked out there).
const GARAGE_H := 2.35
const DOOR_W := ReplicaAreas.HOUSE_DOOR_W
## How far below the floor the walls run, to meet ground that falls away along the lot.
const PLINTH := 0.6

const BLINDS := [Color(0.92, 0.9, 0.84), Color(0.85, 0.82, 0.75), Color(0.6, 0.58, 0.55), Color(0.93, 0.93, 0.93), Color(0.74, 0.66, 0.56)]
const DOORS := [Color(0.92, 0.91, 0.88), Color(0.86, 0.84, 0.80), Color(0.42, 0.30, 0.21), Color(0.28, 0.28, 0.29), Color(0.62, 0.52, 0.40)]
const ENTRY := [Color(0.30, 0.20, 0.14), Color(0.16, 0.15, 0.15), Color(0.52, 0.36, 0.22), Color(0.20, 0.30, 0.34)]
const WHITE_TRIM := Color(0.93, 0.92, 0.89)
const DARK_TRIM := Color(0.19, 0.18, 0.17)
const RAIL_GLASS := Color(0.55, 0.72, 0.68, 0.34)
const CONDO_GLASS := Color(0.28, 0.58, 0.48, 0.55)
const METAL := Color(0.24, 0.24, 0.25)

var b: ReplicaBuilder
var lot: Dictionary
var rng := RandomNumberGenerator.new()
var c2: Vector2
var fr: Vector2
var al: Vector2
var g: float = 0.0
var wall_col: Color
var trim_col: Color
var frame_col: Color
var tile_col: Color


## Builds one lot's house into a chunk (a build step).
static func build(builder: ReplicaBuilder, the_lot: Dictionary) -> void:
	var h := ReplicaHouses.new()
	h.b = builder
	h.lot = the_lot
	h._setup()
	if builder.full:
		if the_lot.kind == "condo":
			h._condo()
		else:
			h._house()
	else:
		h._lod()


# --- The lot's footprint -----------------------------------------------------------------------

## A lot's footprint in its own frame (ReplicaAreas.house_frame(): the house rect, driveway and
## entry, cached on the lot).
static func frame(the_lot: Dictionary) -> Dictionary:
	return ReplicaAreas.house_frame(the_lot)


## True when a car parked at path distance `s` on `side` (+1 east, -1 west) would block one of
## the frontage houses' driveways.
static func driveway_near(builder: ReplicaBuilder, s: float, side: float) -> bool:
	for l in builder.rep.frontage_lots(builder.plan):
		if float(l.get("side", 0.0)) != side or absf(float(l.get("s", -1e9)) - s) > float(l.w) * 0.5 + 6.0:
			continue
		var f := frame(l)
		if float(f.drive_w) <= 0.0:
			continue
		# East lots run their u axis against the route (see ReplicaAreas._lot()), west lots with it.
		var ds := float(l.s) - side * float(f.drive_u)
		if absf(s - ds) < float(f.drive_w) * 0.5 + 2.7:
			return true
	return false


func _setup() -> void:
	rng.seed = int(lot.seed)
	c2 = lot.center
	fr = (lot.front as Vector2).normalized()
	al = Vector2(-fr.y, fr.x)
	var f := frame(lot)
	var gmax := -INF
	for cu: float in [float(f.u0), float(f.u1)]:
		for cv: float in [float(f.v0), float(f.v1)]:
			var p := c2 + al * cu + fr * cv
			gmax = maxf(gmax, b.chunk._gy(p.x, p.y))
	g = gmax + CityChunk.SIDEWALK_TOP
	wall_col = lot.color
	trim_col = WHITE_TRIM if float(lot.trim) < 0.62 else wall_col.lightened(0.35)
	frame_col = WHITE_TRIM if float(lot.trim) < 0.45 else DARK_TRIM
	tile_col = lot.tile


# --- Emitting ------------------------------------------------------------------------------------

## A point in the lot's frame: `u` along the street, `y` above the floor, `v` toward the street.
func W(u: float, y: float, v: float) -> Vector3:
	var p := c2 + al * u + fr * v
	return Vector3(p.x, g + y, p.y)


func L(p: Vector2, y: float) -> Vector3:
	return W(p.x, y, p.y)


## A direction in the lot's frame, in world space.
func N(n: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(al.x * n.x + fr.x * n.y, y, al.y * n.x + fr.y * n.y)


func _tri(name: String, a: Vector3, bb: Vector3, c: Vector3, n: Vector3, col: Color, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	var s := b.st(name)
	if (bb - a).cross(c - a).dot(n) > 0.0:
		var t := bb
		bb = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
	s.set_smooth_group(-1)
	s.set_color(col)
	s.set_uv(ua)
	s.add_vertex(a)
	s.set_uv(ub)
	s.add_vertex(bb)
	s.set_uv(uc)
	s.add_vertex(c)


func _quad(name: String, a: Vector3, bb: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color, uv: Array = []) -> void:
	if uv.is_empty():
		_tri(name, a, bb, c, n, col)
		_tri(name, a, c, d, n, col)
	else:
		_tri(name, a, bb, c, n, col, uv[0], uv[1], uv[2])
		_tri(name, a, c, d, n, col, uv[0], uv[2], uv[3])


## A box in the lot's frame: centre `p` (u, v), from y0 to y1, half sizes `h` along `t` and along
## `n` (the two horizontal axes, unit, in lot space). Every face outward; `bottom` adds the
## underside (a slab seen from below).
func _box(name: String, p: Vector2, y0: float, y1: float, t: Vector2, n: Vector2, h: Vector2, col: Color, bottom: bool = false) -> void:
	var ht := t * h.x
	var hn := n * h.y
	var c := [p - ht - hn, p + ht - hn, p + ht + hn, p - ht + hn]
	for k in 4:
		var a2: Vector2 = c[k]
		var b2: Vector2 = c[(k + 1) % 4]
		var out := ((a2 + b2) * 0.5 - p).normalized()
		_quad(name, L(a2, y0), L(b2, y0), L(b2, y1), L(a2, y1), N(out), col)
	_quad(name, L(c[0], y1), L(c[1], y1), L(c[2], y1), L(c[3], y1), Vector3.UP, col)
	if bottom:
		_quad(name, L(c[0], y0), L(c[1], y0), L(c[2], y0), L(c[3], y0), Vector3.DOWN, col.darkened(0.2))


# --- Walls and openings --------------------------------------------------------------------------

## A wall from lot point `o` along unit `t` for `length`, facing `n`, from y0 to y1, with the
## openings `holes` ([a0, a1, y0, y1, kind], a along t from o) cut out of it: the face is split on
## every opening's edges and only the cells outside an opening are laid.
func _wall(o: Vector2, t: Vector2, n: Vector2, length: float, y0: float, y1: float, holes: Array) -> void:
	var xs: Array[float] = [0.0, length]
	var ys: Array[float] = [y0, y1]
	for h: Array in holes:
		xs.append(clampf(h[0], 0.0, length))
		xs.append(clampf(h[1], 0.0, length))
		ys.append(clampf(h[2], y0, y1))
		ys.append(clampf(h[3], y0, y1))
	xs.sort()
	ys.sort()
	var nw := N(n)
	for xi in xs.size() - 1:
		var xa := xs[xi]
		var xb := xs[xi + 1]
		if xb - xa < 0.004:
			continue
		for yi in ys.size() - 1:
			var ya := ys[yi]
			var yb := ys[yi + 1]
			if yb - ya < 0.004:
				continue
			var mx := (xa + xb) * 0.5
			var my := (ya + yb) * 0.5
			var inside := false
			for h: Array in holes:
				if mx > float(h[0]) and mx < float(h[1]) and my > float(h[2]) and my < float(h[3]):
					inside = true
					break
			if inside:
				continue
			_quad("h_wall", L(o + t * xa, ya), L(o + t * xb, ya), L(o + t * xb, yb), L(o + t * xa, yb), nw, wall_col)
	for h: Array in holes:
		_opening(o, t, n, h)


## One opening: its reveals, then what fills it - glass in a frame (windows, sliders), a panelled
## garage door, an entry door, or the dark mouth of a carport.
func _opening(o: Vector2, t: Vector2, n: Vector2, h: Array) -> void:
	var a0: float = h[0]
	var a1: float = h[1]
	var y0: float = h[2]
	var y1: float = h[3]
	var kind: String = h[4]
	var dep := REVEAL
	match kind:
		"garage":
			dep = 0.24
		"dark":
			dep = 2.6
		"slider":
			dep = 0.2
		"door":
			dep = 0.22
	var back := -n * dep
	var p0 := o + t * a0
	var p1 := o + t * a1
	var reveal := wall_col.darkened(0.08)
	_quad("h_wall", L(p0, y0), L(p0 + back, y0), L(p0 + back, y1), L(p0, y1), N(t), reveal)
	_quad("h_wall", L(p1, y0), L(p1 + back, y0), L(p1 + back, y1), L(p1, y1), N(-t), reveal)
	_quad("h_wall", L(p0, y1), L(p1, y1), L(p1 + back, y1), L(p0 + back, y1), Vector3.DOWN, wall_col.darkened(0.18))
	if y0 > 0.05:
		_quad("h_wall", L(p0, y0), L(p1, y0), L(p1 + back, y0), L(p0 + back, y0), Vector3.UP, wall_col.lightened(0.04))
	var q0 := p0 + back
	var q1 := p1 + back
	var nw := N(n)
	match kind:
		"garage":
			var door: Color = DOORS[absi(hash([int(lot.seed), "door"])) % DOORS.size()]
			_quad("h_door", L(q0, y0), L(q1, y0), L(q1, y1), L(q0, y1), nw, door)
			# Panel grooves: four seams across the door and the stile lines down it.
			for k in range(1, 5):
				var y := y0 + (y1 - y0) * k / 5.0
				_quad("h_door", L(q0 + n * 0.005, y - 0.018), L(q1 + n * 0.005, y - 0.018), L(q1 + n * 0.005, y + 0.018), L(q0 + n * 0.005, y + 0.018), nw, door.darkened(0.35))
			var bays := maxi(2, int(round((a1 - a0) / 0.8)))
			for k in range(1, bays):
				var pa := q0.lerp(q1, float(k) / bays) + n * 0.006
				_quad("h_door", L(pa - t * 0.012, y0), L(pa + t * 0.012, y0), L(pa + t * 0.012, y1), L(pa - t * 0.012, y1), nw, door.darkened(0.2))
			# The floor of the opening, the driveway running in under the door.
			_quad("h_drive", L(p0, 0.018), L(p1, 0.018), L(q1, 0.018), L(q0, 0.018), Vector3.UP, Color.WHITE)
		"door":
			var door: Color = ENTRY[absi(hash([int(lot.seed), "entry"])) % ENTRY.size()]
			_quad("h_door", L(q0, y0), L(q1, y0), L(q1, y1), L(q0, y1), nw, door)
			# A narrow light up the side of it, and the frame.
			_glass(q0.lerp(q1, 0.72) + n * 0.01, q0.lerp(q1, 0.9) + n * 0.01, y0 + 0.9, y1 - 0.2, n, 0.5)
			_frame_ring(q0, q1, y0, y1, t, n, frame_col)
			_box("h_trim", (p0 + p1) * 0.5 + n * 0.04, -0.12, 0.0, t, n, Vector2((a1 - a0) * 0.5 + 0.35, 0.55), trim_col.darkened(0.1))
		"dark":
			_quad("h_dark", L(q0, y0), L(q1, y0), L(q1, y1), L(q0, y1), nw, Color(0.05, 0.05, 0.05))
			_quad("h_dark", L(p0, 0.01), L(p1, 0.01), L(q1, 0.01), L(q0, 0.01), Vector3.UP, Color(0.18, 0.18, 0.18))
		_:
			_glass(q0, q1, y0, y1, n, rng.randf())
			_frame_ring(q0, q1, y0, y1, t, n, frame_col)
			var width := a1 - a0
			var bars := int(width / (1.25 if kind == "slider" else 0.95))
			for k in range(1, bars + 1):
				var pa := q0.lerp(q1, float(k) / (bars + 1)) + n * 0.02
				_quad("h_trim", L(pa - t * 0.03, y0), L(pa + t * 0.03, y0), L(pa + t * 0.03, y1), L(pa - t * 0.03, y1), nw, frame_col)
			if kind == "window":
				# A sill proud of the wall.
				_box("h_trim", (p0 + p1) * 0.5 + n * 0.03, y0 - 0.06, y0, t, n, Vector2(width * 0.5 + 0.06, 0.07), trim_col)


## A glass pane from lot point a to b (along the wall), y0..y1, facing n. UV runs 0..1 across it
## (top-left 0,0) and COLOR carries the blind colour and a per-window random.
func _glass(a: Vector2, bb: Vector2, y0: float, y1: float, n: Vector2, rnd: float) -> void:
	var blind: Color = BLINDS[absi(hash([int(lot.seed), a.x, a.y])) % BLINDS.size()]
	blind.a = rnd
	_quad("glass", L(a, y1), L(bb, y1), L(bb, y0), L(a, y0), N(n), blind, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])


## The frame round an opening's glass, just in front of it.
func _frame_ring(q0: Vector2, q1: Vector2, y0: float, y1: float, t: Vector2, n: Vector2, col: Color) -> void:
	var f := FRAME
	var o := n * 0.015
	var nw := N(n)
	_quad("h_trim", L(q0 + o, y1 - f), L(q1 + o, y1 - f), L(q1 + o, y1), L(q0 + o, y1), nw, col)
	_quad("h_trim", L(q0 + o, y0), L(q1 + o, y0), L(q1 + o, y0 + f), L(q0 + o, y0 + f), nw, col)
	_quad("h_trim", L(q0 + o, y0), L(q0 + t * f + o, y0), L(q0 + t * f + o, y1), L(q0 + o, y1), nw, col)
	_quad("h_trim", L(q1 - t * f + o, y0), L(q1 + o, y0), L(q1 + o, y1), L(q1 - t * f + o, y1), nw, col)


## A balcony on a wall: the slab from a0 to a1 along it, `depth` out, its floor at `y`; a glass
## or steel rail round the outside.
func _balcony(o: Vector2, t: Vector2, n: Vector2, a0: float, a1: float, y: float, depth: float, glass: bool, tint: Color = RAIL_GLASS) -> void:
	var mid := o + t * ((a0 + a1) * 0.5) + n * (depth * 0.5)
	var half := Vector2((a1 - a0) * 0.5, depth * 0.5)
	_box("h_trim", mid, y - 0.2, y, t, n, half, trim_col, true)
	var e0 := o + t * a0 + n * depth
	var e1 := o + t * a1 + n * depth
	var w0 := o + t * a0
	var w1 := o + t * a1
	var inset := 0.05
	if glass:
		for seg: Array in [[e0 - t * -inset - n * inset, e1 - t * inset - n * inset], [w0 + t * inset, e0 + t * inset - n * inset], [e1 - t * inset - n * inset, w1 - t * inset]]:
			var sa: Vector2 = seg[0]
			var sb: Vector2 = seg[1]
			var sn := Vector2(-(sb - sa).y, (sb - sa).x).normalized()
			_quad("h_rail", L(sa, y + 0.05), L(sb, y + 0.05), L(sb, y + RAIL_H - 0.06), L(sa, y + RAIL_H - 0.06), N(sn), tint)
		_rail_bar(e0 - n * inset, e1 - n * inset, y + RAIL_H - 0.03, 0.035)
		_rail_bar(w0 + t * inset, e0 + t * inset - n * inset, y + RAIL_H - 0.03, 0.035)
		_rail_bar(e1 - t * inset - n * inset, w1 - t * inset, y + RAIL_H - 0.03, 0.035)
	else:
		_rail_bar(e0 - n * inset, e1 - n * inset, y + RAIL_H - 0.03, 0.03)
		_rail_bar(e0 - n * inset, e1 - n * inset, y + 0.1, 0.02)
		var count := int((a1 - a0) / 0.12)
		for k in count + 1:
			var p := (e0 - n * inset).lerp(e1 - n * inset, float(k) / maxf(count, 1))
			_box("h_metal", p, y + 0.1, y + RAIL_H - 0.03, t, n, Vector2(0.008, 0.008), METAL)
		for pair: Array in [[w0 + t * inset, e0 + t * inset - n * inset], [w1 - t * inset, e1 - t * inset - n * inset]]:
			_rail_bar(pair[0], pair[1], y + RAIL_H - 0.03, 0.03)
			var sa: Vector2 = pair[0]
			var sb: Vector2 = pair[1]
			var cnt := int(sa.distance_to(sb) / 0.12)
			for k in cnt + 1:
				_box("h_metal", sa.lerp(sb, float(k) / maxf(cnt, 1)), y + 0.1, y + RAIL_H - 0.03, t, n, Vector2(0.008, 0.008), METAL)


func _rail_bar(a: Vector2, bb: Vector2, y: float, r: float) -> void:
	var d := bb - a
	if d.length() < 0.01:
		return
	var t := d.normalized()
	var n := Vector2(-t.y, t.x)
	_box("h_metal", (a + bb) * 0.5, y - r, y + r, t, n, Vector2(d.length() * 0.5, r), METAL)


# --- Roofs ---------------------------------------------------------------------------------------

## A hipped roof over the rect u0..u1, v0..v1 whose eaves sit at y: the four tiled planes rising
## to the ridge along the longer side, the soffit under the overhang and the fascia round it.
func _hip(u0: float, u1: float, v0: float, v1: float, y: float) -> void:
	var U0 := u0 - EAVE
	var U1 := u1 + EAVE
	var V0 := v0 - EAVE
	var V1 := v1 + EAVE
	_eaves(u0, u1, v0, v1, U0, U1, V0, V1, y)
	var ew := U1 - U0
	var ed := V1 - V0
	var tint := tile_col
	if ew >= ed:
		var rise := ed * 0.5 * PITCH
		var r0 := Vector2(U0 + ed * 0.5, (V0 + V1) * 0.5)
		var r1 := Vector2(U1 - ed * 0.5, (V0 + V1) * 0.5)
		var ry := y + rise
		_roof_plane(Vector2(U0, V1), Vector2(U1, V1), r1, r0, y, ry, Vector2(0, 1))
		_roof_plane(Vector2(U1, V0), Vector2(U0, V0), r0, r1, y, ry, Vector2(0, -1))
		_roof_tri(Vector2(U0, V0), Vector2(U0, V1), r0, y, ry, Vector2(-1, 0))
		_roof_tri(Vector2(U1, V1), Vector2(U1, V0), r1, y, ry, Vector2(1, 0))
		_ridge(r0, r1, ry, tint)
	else:
		var rise := ew * 0.5 * PITCH
		var r0 := Vector2((U0 + U1) * 0.5, V0 + ew * 0.5)
		var r1 := Vector2((U0 + U1) * 0.5, V1 - ew * 0.5)
		var ry := y + rise
		_roof_plane(Vector2(U1, V1), Vector2(U1, V0), r0, r1, y, ry, Vector2(1, 0))
		_roof_plane(Vector2(U0, V0), Vector2(U0, V1), r1, r0, y, ry, Vector2(-1, 0))
		_roof_tri(Vector2(U0, V1), Vector2(U1, V1), r1, y, ry, Vector2(0, 1))
		_roof_tri(Vector2(U1, V0), Vector2(U0, V0), r0, y, ry, Vector2(0, -1))
		_ridge(r0, r1, ry, tint)


## A gabled roof: two planes meeting on a ridge along the longer side, the gable ends walled in
## stucco, the rakes overhanging them.
func _gable(u0: float, u1: float, v0: float, v1: float, y: float) -> void:
	var along_u := (u1 - u0) >= (v1 - v0)
	var U0 := u0 - EAVE
	var U1 := u1 + EAVE
	var V0 := v0 - EAVE
	var V1 := v1 + EAVE
	_eaves(u0, u1, v0, v1, U0, U1, V0, V1, y, along_u, not along_u)
	if along_u:
		var ry := y + (V1 - V0) * 0.5 * PITCH
		var vm := (V0 + V1) * 0.5
		_roof_plane(Vector2(U0, V1), Vector2(U1, V1), Vector2(U1, vm), Vector2(U0, vm), y, ry, Vector2(0, 1))
		_roof_plane(Vector2(U1, V0), Vector2(U0, V0), Vector2(U0, vm), Vector2(U1, vm), y, ry, Vector2(0, -1))
		# The gable end runs up from the soffit line to just under the roof: the planes are
		# EAVE * PITCH higher over the wall than at the eave.
		var ey := y + EAVE * PITCH
		var wy := ey + ((v1 - v0) * 0.5) * PITCH
		for e: Array in [[u0, -1.0], [u1, 1.0]]:
			var u: float = e[0]
			_quad("h_wall", W(u, y - 0.2, v0), W(u, y - 0.2, v1), W(u, ey, v1), W(u, ey, v0), N(Vector2(e[1], 0)), wall_col)
			_tri("h_wall", W(u, ey, v0), W(u, ey, v1), W(u, wy, vm), N(Vector2(e[1], 0)), wall_col)
			# The underside of the rake.
			_quad("h_trim", W(u, y, V1), W(u, ry, vm), W(U0 if e[1] < 0.0 else U1, ry, vm), W(U0 if e[1] < 0.0 else U1, y, V1), Vector3.DOWN, trim_col.darkened(0.1))
			_quad("h_trim", W(u, y, V0), W(u, ry, vm), W(U0 if e[1] < 0.0 else U1, ry, vm), W(U0 if e[1] < 0.0 else U1, y, V0), Vector3.DOWN, trim_col.darkened(0.1))
		_ridge(Vector2(U0, vm), Vector2(U1, vm), ry, tile_col)
	else:
		var ry := y + (U1 - U0) * 0.5 * PITCH
		var um := (U0 + U1) * 0.5
		_roof_plane(Vector2(U1, V1), Vector2(U1, V0), Vector2(um, V0), Vector2(um, V1), y, ry, Vector2(1, 0))
		_roof_plane(Vector2(U0, V0), Vector2(U0, V1), Vector2(um, V1), Vector2(um, V0), y, ry, Vector2(-1, 0))
		var ey := y + EAVE * PITCH
		var wy := ey + ((u1 - u0) * 0.5) * PITCH
		for e: Array in [[v0, -1.0], [v1, 1.0]]:
			var v: float = e[0]
			_quad("h_wall", W(u0, y - 0.2, v), W(u1, y - 0.2, v), W(u1, ey, v), W(u0, ey, v), N(Vector2(0, e[1])), wall_col)
			_tri("h_wall", W(u0, ey, v), W(u1, ey, v), W(um, wy, v), N(Vector2(0, e[1])), wall_col)
			var vv := V0 if e[1] < 0.0 else V1
			_quad("h_trim", W(U1, y, v), W(um, ry, v), W(um, ry, vv), W(U1, y, vv), Vector3.DOWN, trim_col.darkened(0.1))
			_quad("h_trim", W(U0, y, v), W(um, ry, v), W(um, ry, vv), W(U0, y, vv), Vector3.DOWN, trim_col.darkened(0.1))
		_ridge(Vector2(um, V0), Vector2(um, V1), ry, tile_col)


## The soffit under an overhang and the fascia board round its edge. `skip_u` / `skip_v` leave the
## ends where a gable rakes instead.
func _eaves(u0: float, u1: float, v0: float, v1: float, U0: float, U1: float, V0: float, V1: float, y: float, skip_u: bool = false, skip_v: bool = false) -> void:
	var fy := y - 0.2
	var sof := trim_col.darkened(0.12)
	# Soffit ring, facing down.
	# (Not under a gable's rake, which is sloped: _gable() lays that.)
	if not skip_v:
		_quad("h_trim", W(U0, fy, V1), W(U1, fy, V1), W(u1, fy, v1), W(u0, fy, v1), Vector3.DOWN, sof)
		_quad("h_trim", W(U1, fy, V0), W(U0, fy, V0), W(u0, fy, v0), W(u1, fy, v0), Vector3.DOWN, sof)
	if not skip_u:
		_quad("h_trim", W(U0, fy, V0), W(U0, fy, V1), W(u0, fy, v1), W(u0, fy, v0), Vector3.DOWN, sof)
		_quad("h_trim", W(U1, fy, V1), W(U1, fy, V0), W(u1, fy, v0), W(u1, fy, v1), Vector3.DOWN, sof)
	# Fascia, facing out.
	if not skip_v:
		_quad("h_trim", W(U0, fy, V1), W(U1, fy, V1), W(U1, y, V1), W(U0, y, V1), N(Vector2(0, 1)), trim_col)
		_quad("h_trim", W(U1, fy, V0), W(U0, fy, V0), W(U0, y, V0), W(U1, y, V0), N(Vector2(0, -1)), trim_col)
	if not skip_u:
		_quad("h_trim", W(U0, fy, V0), W(U0, fy, V1), W(U0, y, V1), W(U0, y, V0), N(Vector2(-1, 0)), trim_col)
		_quad("h_trim", W(U1, fy, V1), W(U1, fy, V0), W(U1, y, V0), W(U1, y, V1), N(Vector2(1, 0)), trim_col)


## One tiled roof plane from eave edge a-b (at y) up to ridge points c-d (at ry). UV runs along the
## eave and up the slope in metres, so the barrels run down every plane whichever way it faces.
func _roof_plane(a: Vector2, bb: Vector2, c: Vector2, d: Vector2, y: float, ry: float, out: Vector2) -> void:
	var e := (bb - a).normalized()
	var slope := ry - y
	var run := absf((c - a).dot(out))
	var up_len := sqrt(run * run + slope * slope)
	var uv := func(p: Vector2, py: float) -> Vector2:
		var along := (p - a).dot(e)
		var s := (py - y) / maxf(slope, 0.001) * up_len
		return Vector2(along, -s) / TILE_M
	var n := N(out * slope).normalized() + Vector3(0, run, 0).normalized()
	_quad("h_roof", L(a, y), L(bb, y), L(c, ry), L(d, ry), n, tile_col, [uv.call(a, y), uv.call(bb, y), uv.call(c, ry), uv.call(d, ry)])


func _roof_tri(a: Vector2, bb: Vector2, c: Vector2, y: float, ry: float, out: Vector2) -> void:
	var e := (bb - a).normalized()
	var run := absf((c - a).dot(out))
	var slope := ry - y
	var up_len := sqrt(run * run + slope * slope)
	var uv := func(p: Vector2, py: float) -> Vector2:
		return Vector2((p - a).dot(e), -(py - y) / maxf(slope, 0.001) * up_len) / TILE_M
	var n := N(out).normalized() * slope + Vector3(0, run, 0)
	_tri("h_roof", L(a, y), L(bb, y), L(c, ry), n, tile_col, uv.call(a, y), uv.call(bb, y), uv.call(c, ry))


## Ridge (and hip) capping: a round-topped run of tiles along the top.
func _ridge(r0: Vector2, r1: Vector2, ry: float, tint: Color) -> void:
	var d := r1 - r0
	if d.length() < 0.05:
		return
	var t := d.normalized()
	var n := Vector2(-t.y, t.x)
	_box("h_roof", (r0 + r1) * 0.5, ry - 0.04, ry + 0.11, t, n, Vector2(d.length() * 0.5 + 0.1, 0.13), tint.darkened(0.08))


## A flat roof: the membrane, and the parapet's inner faces and coping (its outer faces are the
## walls, which run up past the roof line).
func _flat(u0: float, u1: float, v0: float, v1: float, y: float, parapet: float) -> void:
	var t := 0.22
	_quad("h_flat", W(u0 + t, y, v0 + t), W(u1 - t, y, v0 + t), W(u1 - t, y, v1 - t), W(u0 + t, y, v1 - t), Vector3.UP, Color.WHITE)
	var top := y + parapet
	_quad("h_wall", W(u0 + t, y, v1 - t), W(u1 - t, y, v1 - t), W(u1 - t, top, v1 - t), W(u0 + t, top, v1 - t), N(Vector2(0, -1)), wall_col.darkened(0.1))
	_quad("h_wall", W(u0 + t, y, v0 + t), W(u1 - t, y, v0 + t), W(u1 - t, top, v0 + t), W(u0 + t, top, v0 + t), N(Vector2(0, 1)), wall_col.darkened(0.1))
	_quad("h_wall", W(u0 + t, y, v0 + t), W(u0 + t, y, v1 - t), W(u0 + t, top, v1 - t), W(u0 + t, top, v0 + t), N(Vector2(1, 0)), wall_col.darkened(0.1))
	_quad("h_wall", W(u1 - t, y, v0 + t), W(u1 - t, y, v1 - t), W(u1 - t, top, v1 - t), W(u1 - t, top, v0 + t), N(Vector2(-1, 0)), wall_col.darkened(0.1))
	# Coping: a cap proud of the wall on both sides.
	var cy := top + 0.07
	for e: Array in [[Vector2((u0 + u1) * 0.5, v1 - t * 0.5), Vector2(1, 0), (u1 - u0) * 0.5 + 0.04], [Vector2((u0 + u1) * 0.5, v0 + t * 0.5), Vector2(1, 0), (u1 - u0) * 0.5 + 0.04],
			[Vector2(u0 + t * 0.5, (v0 + v1) * 0.5), Vector2(0, 1), (v1 - v0) * 0.5 - t], [Vector2(u1 - t * 0.5, (v0 + v1) * 0.5), Vector2(0, 1), (v1 - v0) * 0.5 - t]]:
		var tt: Vector2 = e[1]
		_box("h_trim", e[0], top, cy, tt, Vector2(-tt.y, tt.x), Vector2(e[2], t * 0.5 + 0.05), trim_col, true)


# --- A house ---------------------------------------------------------------------------------------

## A house, duplex, modern box or small apartment block on its lot.
func _house() -> void:
	var f := frame(lot)
	var u0: float = f.u0
	var u1: float = f.u1
	var v0: float = f.v0
	var v1: float = f.v1
	var kind: String = lot.kind
	var storeys: int = lot.storeys
	var roof: String = lot.roof
	var width := u1 - u0
	var ocean_back: bool = lot.where == "frontage" and float(lot.get("side", 1.0)) < 0.0
	# The top floor steps back from the street on a third of them, over a roof deck.
	var step_back := 0.0
	if storeys >= 2 and kind != "apartment" and rng.randf() < 0.38:
		step_back = rng.randf_range(2.0, 3.4)
	var lower_top := float(storeys - (1 if step_back > 0.0 else 0)) * STOREY
	var modern := kind == "modern"
	var flat_roof := roof == "flat"
	var parapet := PARAPET if flat_roof else 0.0
	var balcony_floor := 1 if storeys >= 2 else -1
	var has_balcony: bool = lot.balcony and balcony_floor > 0 and step_back <= 0.0
	# The lower block.
	var lower_parapet := (RAIL_H if step_back > 0.0 else parapet)
	_block(u0, u1, v0, v1, 0, storeys - (1 if step_back > 0.0 else 0), lower_parapet, ocean_back, has_balcony, f)
	if step_back > 0.0:
		_flat(u0, u1, v0, v1, lower_top, RAIL_H)
		var vb := v1 - step_back
		_block(u0 + (0.0 if width < 10.0 else rng.randf_range(0.0, 1.2)), u1, v0, vb, storeys - 1, storeys, parapet, ocean_back, false, f)
		if flat_roof:
			_flat(u0, u1, v0, vb, float(storeys) * STOREY, parapet)
		elif roof == "gable":
			_gable(u0, u1, v0, vb, float(storeys) * STOREY)
		else:
			_hip(u0, u1, v0, vb, float(storeys) * STOREY)
	else:
		if flat_roof:
			_flat(u0, u1, v0, v1, lower_top, parapet)
		elif roof == "gable":
			_gable(u0, u1, v0, v1, lower_top)
		else:
			_hip(u0, u1, v0, v1, lower_top)
	if flat_roof and rng.randf() < 0.5:
		# A condenser or two on the roof.
		for k in rng.randi_range(1, 2):
			var p := Vector2(rng.randf_range(u0 + 1.5, u1 - 1.5), rng.randf_range(v0 + 1.5, v0 + (v1 - v0) * 0.5))
			_box("h_metal", p, float(storeys) * STOREY, float(storeys) * STOREY + 0.9, Vector2(1, 0), Vector2(0, 1), Vector2(0.45, 0.45), Color(0.72, 0.72, 0.70))
	_front_yard(f)
	_solids(f, storeys, roof, step_back)


## One block of floors from floor f0 up to f1 over the rect, every face cut for its openings, the
## walls running PLINTH below the floor and `parapet` above the top.
func _block(u0: float, u1: float, v0: float, v1: float, f0: int, f1: int, parapet: float, ocean_back: bool, balcony: bool, f: Dictionary) -> void:
	var y0 := -PLINTH if f0 == 0 else float(f0) * STOREY
	var y1 := float(f1) * STOREY + parapet
	var roofed := parapet <= 0.0
	if roofed:
		# Pitched: the walls stop under the soffit (the eave closes the rest).
		y1 = float(f1) * STOREY - 0.2
	var faces := [
		[Vector2(u0, v1), Vector2(1, 0), Vector2(0, 1), u1 - u0, "front"],
		[Vector2(u1, v0), Vector2(-1, 0), Vector2(0, -1), u1 - u0, "back"],
		[Vector2(u0, v0), Vector2(0, 1), Vector2(-1, 0), v1 - v0, "side"],
		[Vector2(u1, v1), Vector2(0, -1), Vector2(1, 0), v1 - v0, "side"],
	]
	for face: Array in faces:
		var o: Vector2 = face[0]
		var t: Vector2 = face[1]
		var n: Vector2 = face[2]
		var length: float = face[3]
		var which: String = face[4]
		var holes: Array = []
		for fl in range(f0, f1):
			holes.append_array(_openings(which, o, t, length, fl, f, ocean_back, balcony, u0))
		_wall(o, t, n, length, y0, y1, holes)
		if which == "front" and balcony and f0 <= 1 and f1 > 1:
			var a0 := length * rng.randf_range(0.08, 0.2)
			var a1 := length * rng.randf_range(0.62, 0.95)
			_balcony(o, t, n, a0, a1, STOREY, rng.randf_range(1.1, 1.7), lot.kind == "modern" or rng.randf() < 0.45)
		if which == "back" and ocean_back and f1 > 1 and f0 <= 1:
			_balcony(o, t, n, length * 0.1, length * 0.9, STOREY, 1.8, true)


## Openings on one face for one floor, in the face's own coordinates ([a0, a1, y0, y1, kind]).
func _openings(which: String, o: Vector2, t: Vector2, length: float, fl: int, f: Dictionary, ocean_back: bool, balcony: bool, bu0: float) -> Array:
	var out: Array = []
	var fy := float(fl) * STOREY
	var face_rng := RandomNumberGenerator.new()
	face_rng.seed = hash([int(lot.seed), which, fl, int(o.x * 10.0), int(o.y * 10.0)])
	match which:
		"front":
			if fl == 0:
				# The face runs from u0 along +u, so a = u - u0.
				var taken: Array[Vector2] = []
				if float(f.drive_w) > 0.0 and lot.kind != "apartment":
					var a := float(f.drive_u) - float(o.x)
					var half := float(f.drive_w) * 0.5 - (0.15 if float(f.drive_w) < 4.0 else 0.25)
					out.append([a - half, a + half, 0.0, GARAGE_H, "garage"])
					taken.append(Vector2(a - half - 0.4, a + half + 0.4))
				if lot.kind == "apartment":
					# Tuck-under parking: the whole ground floor open in bays, bar a lobby door.
					var bays := maxi(2, int(length / 3.4))
					var bw := length / bays
					for k in bays:
						if k == bays - 1:
							out.append([k * bw + bw * 0.3, k * bw + bw * 0.3 + DOOR_W, 0.0, 2.2, "door"])
							continue
						out.append([k * bw + 0.3, (k + 1) * bw - 0.3, 0.0, 2.45, "dark"])
					return out
				var ea := float(f.entry_u) - float(o.x)
				out.append([ea - DOOR_W * 0.5, ea + DOOR_W * 0.5, 0.0, 2.25, "door"])
				taken.append(Vector2(ea - DOOR_W * 0.5 - 0.5, ea + DOOR_W * 0.5 + 0.5))
				_fill_windows(out, taken, length, fy + 0.95, fy + 2.3, face_rng, 1.2, 2.2)
			else:
				if balcony and fl == 1:
					var sw := minf(length * 0.45, face_rng.randf_range(2.4, 3.8))
					var sa := length * 0.5 - sw * 0.5 + face_rng.randf_range(-0.8, 0.8)
					out.append([sa, sa + sw, fy + 0.05, fy + 2.4, "slider"])
					_fill_windows(out, [Vector2(sa - 0.6, sa + sw + 0.6)], length, fy + 0.9, fy + 2.35, face_rng, 1.2, 1.8)
				elif lot.kind == "modern":
					var sw := length * face_rng.randf_range(0.5, 0.75)
					var sa := face_rng.randf_range(0.5, length - sw - 0.5)
					out.append([sa, sa + sw, fy + 0.35, fy + 2.5, "window"])
				else:
					_fill_windows(out, [], length, fy + 0.9, fy + 2.35, face_rng, 1.3, 1.9)
		"back":
			if ocean_back and fl >= 1:
				var sw := length * 0.6
				out.append([length * 0.2, length * 0.2 + sw, fy + 0.05, fy + 2.45, "slider"])
			else:
				_fill_windows(out, [], length, fy + 0.95, fy + 2.3, face_rng, 1.0, 1.6)
		"side":
			var n := int(length / 5.5)
			for k in n:
				if face_rng.randf() < 0.45:
					continue
				var a := (float(k) + 0.5) * length / n
				out.append([a - 0.45, a + 0.45, fy + 1.15, fy + 2.2, "window"])
	return out


## Windows spread along a face, `lo`..`hi` wide, keeping out of the `taken` spans.
func _fill_windows(out: Array, taken: Array, length: float, y0: float, y1: float, r: RandomNumberGenerator, lo: float, hi: float) -> void:
	var count := maxi(1, int(length / 3.4))
	for k in count:
		var w := r.randf_range(lo, hi)
		var c := (float(k) + 0.5) * length / count
		var a0 := c - w * 0.5
		var a1 := c + w * 0.5
		if a0 < 0.6 or a1 > length - 0.6:
			continue
		var clash := false
		for sp: Vector2 in taken:
			if a1 > sp.x and a0 < sp.y:
				clash = true
		if not clash:
			out.append([a0, a1, y0, y1, "window"])


## The front yard: driveway, a path to the door, a low garden wall or a hedge, planting.
func _front_yard(f: Dictionary) -> void:
	var edge: float = float(lot.d) * 0.5
	var v1: float = f.v1
	var u0 := -float(lot.w) * 0.5
	var u1 := float(lot.w) * 0.5
	if float(f.drive_w) > 0.0:
		var du: float = f.drive_u
		var hw: float = float(f.drive_w) * 0.5
		_quad("h_drive", W(du - hw, 0.02, edge), W(du + hw, 0.02, edge), W(du + hw, 0.02, v1), W(du - hw, 0.02, v1), Vector3.UP, Color.WHITE)
	var eu: float = f.entry_u
	_quad("h_drive", W(eu - 0.6, 0.025, edge), W(eu + 0.6, 0.025, edge), W(eu + 0.6, 0.025, v1), W(eu - 0.6, 0.025, v1), Vector3.UP, Color.WHITE)
	var roll := rng.randf()
	var gaps: Array[Vector2] = [Vector2(eu - 0.7, eu + 0.7)]
	if float(f.drive_w) > 0.0:
		gaps.append(Vector2(float(f.drive_u) - float(f.drive_w) * 0.5 - 0.1, float(f.drive_u) + float(f.drive_w) * 0.5 + 0.1))
	gaps.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var runs: Array[Vector2] = []
	var start := u0 + 0.1
	for gp in gaps:
		if gp.x > start + 0.3:
			runs.append(Vector2(start, gp.x))
		start = maxf(start, gp.y)
	if u1 - 0.1 > start + 0.3:
		runs.append(Vector2(start, u1 - 0.1))
	var wall_h := rng.randf_range(0.55, 1.15)
	for run in runs:
		var mid := Vector2((run.x + run.y) * 0.5, edge - 0.25)
		if roll < 0.5:
			_box("h_wall", mid, -0.1, wall_h, Vector2(1, 0), Vector2(0, 1), Vector2((run.y - run.x) * 0.5, 0.12), wall_col.lightened(0.05))
			_box("h_trim", mid, wall_h, wall_h + 0.06, Vector2(1, 0), Vector2(0, 1), Vector2((run.y - run.x) * 0.5 + 0.02, 0.16), trim_col)
		elif roll < 0.8:
			# A clipped hedge along the front.
			var n := int((run.y - run.x) / 1.1)
			for k in n:
				var q := W(lerpf(run.x + 0.5, run.y - 0.5, (float(k) + 0.5) / maxf(n, 1)), 0.0, edge - 0.5)
				var sc := rng.randf_range(0.7, 0.95)
				b.batch_add("shrub_%d" % (k % 4), PropFactory.model_shrub(k % 4), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * 0.8, sc)), q), Color(0.9, 1.0, 0.85))
	# Planting against the house.
	for k in rng.randi_range(2, 5):
		var u := rng.randf_range(u0 + 0.8, u1 - 0.8)
		var clash := false
		for gp in gaps:
			if u > gp.x - 0.6 and u < gp.y + 0.6:
				clash = true
		if clash:
			continue
		var v := rng.randf_range(v1 + 0.6, edge - 1.0)
		if v <= v1 + 0.5:
			continue
		var roll2 := rng.randf()
		var q := W(u, 0.0, v)
		if roll2 < 0.45:
			b.batch_add("bush_%d" % (k % 4), PropFactory.model_bush(k % 4), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), q))
		elif roll2 < 0.75:
			var fv: int = [0, 3, 1, 2][k % 4]
			b.batch_add("flower_%d" % fv, PropFactory.model_flower(fv), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.3, 1.3, 1.3)), q))
		else:
			b.batch_add("gclump_%d" % (k % 2), PropFactory.model_grass_clump(k % 2), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), q))


## Collision and the occluder for a house: its block (and top floor), and a hull for a pitched roof.
func _solids(f: Dictionary, storeys: int, roof: String, step_back: float) -> void:
	var u0: float = f.u0
	var u1: float = f.u1
	var v0: float = f.v0
	var v1: float = f.v1
	var lower := float(storeys - (1 if step_back > 0.0 else 0)) * STOREY
	_solid_box(u0, u1, v0, v1, -PLINTH, lower + (PARAPET if roof == "flat" or step_back > 0.0 else 0.0))
	var top_v1 := v1 - step_back
	if step_back > 0.0:
		_solid_box(u0, u1, v0, top_v1, lower, float(storeys) * STOREY + (PARAPET if roof == "flat" else 0.0))
	if roof != "flat":
		var y := float(storeys) * STOREY
		var hull := PackedVector3Array()
		var ew := u1 - u0 + EAVE * 2.0
		var ed := top_v1 - v0 + EAVE * 2.0
		var rise := minf(ew, ed) * 0.5 * PITCH
		for p: Vector2 in [Vector2(u0 - EAVE, v0 - EAVE), Vector2(u1 + EAVE, v0 - EAVE), Vector2(u1 + EAVE, top_v1 + EAVE), Vector2(u0 - EAVE, top_v1 + EAVE)]:
			hull.append(W(p.x, y, p.y))
		var cu := (u0 + u1) * 0.5
		var cv := (v0 + top_v1) * 0.5
		if ew >= ed:
			hull.append(W(u0 - EAVE + ed * 0.5, y + rise, cv))
			hull.append(W(u1 + EAVE - ed * 0.5, y + rise, cv))
		else:
			hull.append(W(cu, y + rise, v0 - EAVE + ew * 0.5))
			hull.append(W(cu, y + rise, top_v1 + EAVE - ew * 0.5))
		var shape := CollisionShape3D.new()
		var cs := ConvexPolygonShape3D.new()
		cs.points = hull
		shape.shape = cs
		b._body_node().add_child(shape)


func _basis() -> Basis:
	return Basis(Vector3(al.x, 0, al.y), Vector3.UP, Vector3(-fr.x, 0, -fr.y))


## A solid box over the rect from y0 to y1: collision, and an occluder part.
func _solid_box(u0: float, u1: float, v0: float, v1: float, y0: float, y1: float) -> void:
	var centre := W((u0 + u1) * 0.5, (y0 + y1) * 0.5, (v0 + v1) * 0.5)
	var size := Vector3(u1 - u0, y1 - y0, v1 - v0)
	if b.full or b.chunk._lod_collision_wanted():
		var shape := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = size
		shape.shape = bx
		shape.transform = Transform3D(_basis(), centre)
		b._body_node().add_child(shape)
	b.chunk._occluder_boxes.append([Transform3D(_basis(), centre), Vector3.ZERO, size])


# --- The condominium -------------------------------------------------------------------------------

## The long condominium block: four floors of units behind continuous balconies in bays, green
## glass rails, stucco fins between the bays, a flat roof behind a parapet.
func _condo() -> void:
	var f := frame(lot)
	var u0: float = f.u0
	var u1: float = f.u1
	var v0: float = f.v0
	var v1: float = f.v1
	var storeys: int = lot.storeys
	var sh := (float(lot.height) - 1.2) / float(storeys)
	var H := float(storeys) * sh
	var length := u1 - u0
	var bays := maxi(4, int(round(length / 8.0)))
	var bw := length / bays
	var depth := 1.8
	# Street face: the units' glass set back behind the balcony line.
	var o := Vector2(u0, v1)
	var t := Vector2(1, 0)
	var n := Vector2(0, 1)
	var holes: Array = []
	for fl in storeys:
		var fy := float(fl) * sh
		for k in bays:
			var a0 := k * bw + 0.45
			var a1 := (k + 1) * bw - 0.45
			if fl == 0 and k % 5 == 2:
				holes.append([a0 + 1.6, a1 - 1.6, 0.0, 2.6, "door"])
				continue
			holes.append([a0 + 0.25, a1 - 0.25, fy + 0.08, fy + 2.55, "slider"])
	_wall(o, t, n, length, -PLINTH, H + 1.2, holes)
	for fl in range(1, storeys):
		var fy := float(fl) * sh
		for k in bays:
			_balcony(o, t, n, k * bw + 0.2, (k + 1) * bw - 0.2, fy, depth, true, CONDO_GLASS)
	# The fins between the bays, full height, and a planter strip along the ground floor.
	for k in bays + 1:
		var a := k * bw
		_box("h_wall", o + t * a + n * (depth * 0.5 + 0.1), -0.1, H + 0.6, t, n, Vector2(0.17, depth * 0.5 + 0.1), wall_col.darkened(0.03))
	for k in bays:
		var p := o + t * ((k + 0.5) * bw) + n * 1.1
		_box("h_wall", p, -0.05, 0.55, t, n, Vector2(bw * 0.5 - 0.6, 0.45), wall_col.darkened(0.06))
		for j in 3:
			var q := L(p + t * lerpf(-bw * 0.35, bw * 0.35, float(j) / 2.0), 0.55)
			b.batch_add("shrub_%d" % ((k + j) % 4), PropFactory.model_shrub((k + j) % 4), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.6, 0.6, 0.6)), q), Color(0.9, 1.0, 0.85))
	# The other faces: windows per bay.
	var back_holes: Array = []
	for fl in storeys:
		for k in bays:
			back_holes.append([k * bw + 1.6, (k + 1) * bw - 1.6, float(fl) * sh + 0.95, float(fl) * sh + 2.35, "window"])
	_wall(Vector2(u1, v0), Vector2(-1, 0), Vector2(0, -1), length, -PLINTH, H + 1.2, back_holes)
	for face: Array in [[Vector2(u0, v0), Vector2(0, 1), Vector2(-1, 0)], [Vector2(u1, v1), Vector2(0, -1), Vector2(1, 0)]]:
		var side_holes: Array = []
		for fl in storeys:
			side_holes.append([(v1 - v0) * 0.3, (v1 - v0) * 0.3 + 1.2, float(fl) * sh + 1.0, float(fl) * sh + 2.3, "window"])
			side_holes.append([(v1 - v0) * 0.62, (v1 - v0) * 0.62 + 1.2, float(fl) * sh + 1.0, float(fl) * sh + 2.3, "window"])
		_wall(face[0], face[1], face[2], v1 - v0, -PLINTH, H + 1.2, side_holes)
	_flat(u0, u1, v0, v1, H, 1.2)
	for k in int(length / 14.0):
		var p := Vector2(u0 + 7.0 + k * 14.0, v0 + (v1 - v0) * 0.4)
		_box("h_metal", p, H, H + 1.3, Vector2(1, 0), Vector2(0, 1), Vector2(0.9, 0.7), Color(0.7, 0.7, 0.68))
	# The front yard: a path in to each lobby and lawn.
	_solid_box(u0, u1, v0, v1, -PLINTH, H + 1.2)


# --- Far (LOD) chunks ------------------------------------------------------------------------------

## A far house: the city's LOD box in the lot's colour (shaders/building_lod.gdshader draws its
## windows), a roof prism in the tile colour when it is pitched, and its collision.
func _lod() -> void:
	var f := frame(lot)
	var u0: float = f.u0
	var u1: float = f.u1
	var v0: float = f.v0
	var v1: float = f.v1
	var storeys: int = lot.storeys
	var H := float(lot.height) - (1.2 if lot.kind == "condo" else (0.0 if lot.roof == "flat" else 2.2))
	if lot.roof == "flat" and lot.kind != "condo":
		H = float(storeys) * STOREY + PARAPET
	var centre := W((u0 + u1) * 0.5, H * 0.5 - PLINTH * 0.5, (v0 + v1) * 0.5)
	var size := Vector3(u1 - u0, H + PLINTH, v1 - v0)
	var bas := _basis()
	var custom := Color(0.25, 0.32, float(absi(int(lot.seed)) % 997) / 997.0, 0.0)
	b.batch_add("lod_box", PropFactory.unit_box(), Transform3D(Basis(bas.x * size.x, bas.y * size.y, bas.z * size.z), centre), wall_col, custom)
	if lot.roof != "flat" and lot.kind != "condo":
		var ew := size.x + EAVE * 2.0
		var ed := size.z + EAVE * 2.0
		var rise := minf(ew, ed) * 0.5 * PITCH
		var rb := bas if ew >= ed else Basis(bas.z, bas.y, -bas.x)
		var sx := maxf(ew, ed)
		var sz := minf(ew, ed)
		b.batch_add("replica_roof_lod", roof_prism(), Transform3D(Basis(rb.x * sx, rb.y * rise, rb.z * sz), W((u0 + u1) * 0.5, H, (v0 + v1) * 0.5)), tile_col)
	_solid_box(u0, u1, v0, v1, -PLINTH, H)


static var _prism: Mesh

## A unit hipped roof: 1 x 1 base on y 0, ridge at y 1 along X from -0.25 to 0.25.
static func roof_prism() -> Mesh:
	if _prism != null:
		return _prism
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var a := Vector3(-0.5, 0, -0.5)
	var bq := Vector3(0.5, 0, -0.5)
	var c := Vector3(0.5, 0, 0.5)
	var d := Vector3(-0.5, 0, 0.5)
	var r0 := Vector3(-0.25, 1, 0)
	var r1 := Vector3(0.25, 1, 0)
	for f: Array in [[d, c, r1, r0], [bq, a, r0, r1]]:
		for tri: Array in [[f[0], f[2], f[1]], [f[0], f[3], f[2]]]:
			for v: Vector3 in tri:
				st.add_vertex(v)
	for tri: Array in [[a, r0, d], [c, r1, bq]]:
		for v: Vector3 in tri:
			st.add_vertex(v)
	st.generate_normals()
	_prism = st.commit()
	_prism.surface_set_material(0, PropFactory.material(Color.WHITE, 0.8))
	return _prism


# --- Materials ------------------------------------------------------------------------------------

static func material(name: String) -> Material:
	match name:
		"h_wall":
			var m := (PropFactory.pbr("plaster_white", 2.2, Color.WHITE, 1.0, true) as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.vertex_color_is_srgb = true
			return m
		"h_trim", "h_door":
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.roughness = 0.55 if name == "h_trim" else 0.45
			return m
		"h_metal":
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.metallic = 0.55
			m.roughness = 0.42
			return m
		"h_dark":
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.roughness = 0.9
			return m
		"h_roof":
			var m := StandardMaterial3D.new()
			m.albedo_texture = PropFactory.texture("roof_clay", "Color")
			var nt := PropFactory.texture("roof_clay", "NormalGL")
			if nt:
				m.normal_enabled = true
				m.normal_texture = nt
				m.normal_scale = 1.0
			var rt := PropFactory.texture("roof_clay", "Roughness")
			if rt:
				m.roughness_texture = rt
				m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			return m
		"h_flat":
			return PropFactory.pbr("concrete", 3.0, Color(0.78, 0.77, 0.74))
		"h_rail":
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.06
			m.metallic = 0.2
			return m
		"h_drive":
			return PropFactory.road("sidewalk", 3.0, Color(1.45, 1.44, 1.40), 7334, 0.0, 0.35)
		"glass":
			var m := ShaderMaterial.new()
			m.shader = load("res://shaders/house_glass.gdshader")
			return m
	return PropFactory.material(Color.MAGENTA)
