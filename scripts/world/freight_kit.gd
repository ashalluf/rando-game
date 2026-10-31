class_name FreightKit
extends FreewayKit
## The freight line's fixed works in one chunk (FreightRail is the line; this builds what a chunk
## owns of it - every SEG-metre stretch of the line whose middle is in the chunk's owned rect, and
## every junction, signal and stop whose position is - and, through FreightYard, the chunk's part
## of the yard):
##
##   yard      the two main tracks up the old roadway to a buffer stop each (the yard's own tracks
##             are FreightYard's);
##   trench    the floor and its drains, the walls up to a parapet over the street with a fence
##             on it, lights on the walls, every deck a cross street crosses on (girders, soffit,
##             fascias, a barrier at each edge, a light under it), the crossover;
##   grade     the median between kerbs, ballasted, and at each level crossing concrete panels
##             flush with the rails, the gate assemblies (masts, crossbucks, flashers, bells; the
##             arms and lamps are RailGate nodes FreightRailSystem drives), stop bars and the
##             crossing's X on the cross street;
##   severed   a row of K-rail and a ROAD CLOSED board across each cut-off cross street;
##   signals   three-lamp block signals on masts or wall brackets;
##   portal    the headwall at the mouth of the covered way, the dark bore behind it.
##
## Track everywhere is real geometry: crushed-stone ballast beds with shoulders, concrete ties
## (MultiMesh, with their pads and clips) or timber ones in the yard, and rails swept from the
## light rail's 115 lb profile (FULL). The concrete is FreewayKit's structure material (its
## streaks, grime, formwork), the track freight_track.gdshader, the lettering FreewayKit's paint.
## LOD chunks keep the trench's shell, the decks, the ballast beds and the portal.

const T_BALLAST := 1
const T_TIE := 2
const T_HEAD := 3
const T_RAIL := 4
const T_CLIP := 5
const T_PANEL := 6
const T_LENS := 7
const T_STEEL := 8
const T_PAINT := 9
const T_DIRT := 10
const T_TIMBER := 11

const SEG := 4.0
const TIE_SPACING := 0.61
const TIMBER_SPACING := 0.5
## Ballast: its top this far under the rail top, this far out from a track's centre, its shoulder.
const BALLAST_DROP := 0.25
const BALLAST_HALF := 1.95
const SHOULDER := 0.55
## The median at grade: kerbs' inner faces this far out (the trench's own width), their size.
const KERB_HALF := 5.15
const KERB_W := 0.3
const KERB_H := 0.18
const PARAPET := 1.07
const FENCE := 1.8
## Decks: depth under the street, girder spacing; lights on the trench walls this far apart.
const DECK_DEPTH := 1.05
const GIRDER_STEP := 2.6
const WALL_LIGHT_EVERY := 32.0
## Block signals this far apart along each track.
const SIGNAL_EVERY := 520.0

const BALLAST_COL := Color(0.36, 0.345, 0.325)
const TIE_COL := Color(0.47, 0.46, 0.44)
const TIMBER_COL := Color(0.24, 0.19, 0.15)
const RAIL_COL := Color(0.4, 0.3, 0.24)
const CONC := Color(0.70, 0.69, 0.66)
const WALL_COL := Color(0.74, 0.73, 0.70)
const DARK := Color(0.06, 0.06, 0.065)
const BORE := Color(0.01, 0.01, 0.012)
const FR_GALV := Color(0.62, 0.64, 0.65)
const BLACK := Color(0.05, 0.05, 0.05)

var fr: FreightRail
var area := Rect2()
var track := SurfaceTool.new()
var _track_any := false
var _ties := PackedFloat32Array()
var _timbers := PackedFloat32Array()
var _shapes: Array = []
var _gates: Array = []
var _yard: FreightYard
static var _tie_mesh: ArrayMesh
static var _timber_mesh: ArrayMesh
static var _track_mat: ShaderMaterial


## Road decals (patches, oil, paint, crosswalk bars) the street furniture laid over the open
## trench, where there is no road, are collapsed before the chunk's batches build. Only flat things
## at road height: a prop's index stays valid (it is scaled to nothing, never removed).
static func clear_road_decals(c: CityChunk) -> void:
	if c.capturing:
		return
	var fr := FreightRail.of(c.plan)
	if fr == null:
		return
	var holes := fr.cuts_in(c.owned_rect().grow(8.0))
	if holes.is_empty():
		return
	var batches: Dictionary = c._batch.data()
	for key: String in batches:
		if key.begins_with("fr_"):
			continue
		var xforms: Array = batches[key].xforms
		for i in xforms.size():
			var xf: Transform3D = xforms[i]
			var p := Vector2(xf.origin.x, xf.origin.z)
			if xf.origin.y - c._gy(p.x, p.y) > CityChunk.ROAD_TOP + 0.12:
				continue
			for h: Rect2 in holes:
				if h.grow(0.3).has_point(p):
					xforms[i] = Transform3D(Basis().scaled(Vector3.ZERO), xf.origin)
					break


## The steps a chunk runs for the line (and the yard) in its owned rect; none where it has nothing.
static func attach(c: CityChunk) -> Array[Callable]:
	var out: Array[Callable] = []
	if c.capturing:
		return out
	var fr := FreightRail.of(c.plan)
	if fr == null:
		return out
	var area := c.owned_rect()
	var reach := Rect2(fr.avenue_x - 16.0, fr.z0 - 30.0, 32.0, fr.s_mouth + 70.0).merge(fr.yard_rect)
	if not reach.intersects(area):
		return out
	var k := FreightKit.new(c)
	k.fr = fr
	k.area = area
	c.set_meta("freight_kit", k)
	out.append(k._line_step)
	out.append(k._features_step)
	if fr.yard_rect.intersects(area):
		k._yard = FreightYard.new()
		k._yard.setup(k)
		out.append_array(k._yard.steps())
	out.append(k._commit_step)
	return out


func _init(c: CityChunk) -> void:
	super(c)
	track.begin(Mesh.PRIMITIVE_TRIANGLES)
	Industrial._state(c)


static func track_material() -> ShaderMaterial:
	if _track_mat == null:
		_track_mat = ShaderMaterial.new()
		_track_mat.shader = load("res://shaders/freight_track.gdshader")
	return _track_mat


static func tcol(c: Color, kind: int) -> Color:
	return Color(c.r, c.g, c.b, float(kind) / 32.0)


func _owns(p: Vector2) -> bool:
	return area.has_point(p)


func _street(p: Vector2) -> float:
	return chunk._gy(p.x, p.y) + CityChunk.ROAD_TOP


# --- Track ------------------------------------------------------------------------------------

## The two rails of one track whose centre runs from (xa, za) to (xb, zb), rail tops ya, yb.
func rails(xa: float, za: float, xb: float, zb: float, ya: float, yb: float) -> void:
	if not full:
		return
	var prof: Array = LightRailKit.RAIL_PROFILE
	var n := prof.size()
	var d := Vector3(xb - xa, yb - ya, zb - za)
	var across := Vector3(d.z, 0.0, -d.x).normalized()
	if across.x < 0.0:
		across = -across
	var mid := Vector2(0.0, 0.09)
	for side: float in [-1.0, 1.0]:
		var off := side * (FreightRail.GAUGE * 0.5 + 0.036)
		var a0 := Vector3(xa, ya - 0.168, za) + across * off
		var b0 := Vector3(xb, yb - 0.168, zb) + across * off
		for k in n:
			var p: Vector2 = prof[k]
			var q: Vector2 = prof[(k + 1) % n]
			if p.y < 0.001 and q.y < 0.001:
				continue
			var e := q - p
			var on := Vector2(e.y, -e.x).normalized()
			if on.dot((p + q) * 0.5 - mid) < 0.0:
				on = -on
			var want := across * on.x + Vector3.UP * on.y
			var top := p.y > 0.16 and q.y > 0.16
			var col := tcol(RAIL_COL, T_HEAD if top else T_RAIL)
			quad(track, a0 + across * p.x + Vector3.UP * p.y, a0 + across * q.x + Vector3.UP * q.y,
				b0 + across * q.x + Vector3.UP * q.y, b0 + across * p.x + Vector3.UP * p.y, want, col,
				Vector2(za, 0.0), Vector2(za, 0.0), Vector2(zb, 0.0), Vector2(zb, 0.0), Vector2(p.x if top else 0.0, 0.0))
			if top:
				# UV2.x carries the lateral position across the head: redo with per-vertex values.
				pass
		_track_any = true


## Ties under a track from za to zb (centre x as a function of z by linear interpolation from xa
## to xb), the rail top ya..yb: on the global TIE_SPACING grid so neighbouring chunks line up.
func ties(xa: float, za: float, xb: float, zb: float, ya: float, yb: float, timber: bool = false) -> void:
	if not full:
		return
	var sp := TIMBER_SPACING if timber else TIE_SPACING
	var lo := minf(za, zb)
	var hi := maxf(za, zb)
	var k0 := ceili(lo / sp)
	var k1 := floori((hi - 0.0001) / sp)
	var yaw := atan2(xb - xa, zb - za)
	var c := cos(yaw)
	var s := sin(yaw)
	var buf := _timbers if timber else _ties
	for k in range(k0, k1 + 1):
		var z := float(k) * sp
		var t := (z - za) / maxf(zb - za, 0.0001) if absf(zb - za) > 0.0001 else 0.0
		var x := lerpf(xa, xb, t)
		var y := lerpf(ya, yb, t) - 0.172
		# Rows of the 3x4 transform: a yaw about y.
		buf.append_array([c, 0.0, s, x, 0.0, 1.0, 0.0, y, -s, 0.0, c, z])
	if timber:
		_timbers = buf
	else:
		_ties = buf


## A ballast bed under tracks at centre xs (ascending), from za to zb, its top under the rail tops
## ya..yb, its shoulders down to base heights ga..gb. UV.y is metres across from the nearest track
## (the shader's dust and oil follow the rails); UV2.y how dirty (1 on the main).
func ballast(xs: Array, za: float, zb: float, ya: float, yb: float, ga: float, gb: float, dirt := 1.0, shoulders := true) -> void:
	var ta := ya - BALLAST_DROP
	var tb := yb - BALLAST_DROP
	var col := tcol(BALLAST_COL, T_BALLAST)
	var x_lo: float = float(xs[0]) - BALLAST_HALF
	var x_hi: float = float(xs[xs.size() - 1]) + BALLAST_HALF
	# The top, in strips per track (and between).
	var edges: Array = [x_lo]
	for i in xs.size():
		var x: float = xs[i]
		if i > 0:
			var prev: float = xs[i - 1]
			var m := (prev + x) * 0.5
			edges.append(m)
	edges.append(x_hi)
	for i in xs.size():
		var x0: float = edges[i]
		var x1: float = edges[i + 1]
		var cx: float = xs[i]
		quad(track, Vector3(x0, ta, za), Vector3(x1, ta, za), Vector3(x1, tb, zb), Vector3(x0, tb, zb), Vector3.UP, col,
			Vector2(za, x0 - cx), Vector2(za, x1 - cx), Vector2(zb, x1 - cx), Vector2(zb, x0 - cx), Vector2(0.0, dirt))
	if shoulders:
		for side: float in [-1.0, 1.0]:
			var xe := x_lo if side < 0.0 else x_hi
			var dropa := maxf(ta - ga, 0.0)
			var dropb := maxf(tb - gb, 0.0)
			var oa := xe + side * maxf(dropa, 0.05) * 1.6
			var ob := xe + side * maxf(dropb, 0.05) * 1.6
			quad(track, Vector3(xe, ta, za), Vector3(oa, minf(ga, ta) - 0.02, za), Vector3(ob, minf(gb, tb) - 0.02, zb), Vector3(xe, tb, zb),
				Vector3(side, 1.2, 0.0).normalized(), col, Vector2(za, side * 2.0), Vector2(za, side * 3.0), Vector2(zb, side * 3.0), Vector2(zb, side * 2.0), Vector2(0.0, dirt * 0.4))
	_track_any = true


## The concrete tie (2.59 m, a trapezoid section) with its rail-seat pads and clips; origin at the
## middle of its top face, long axis x.
static func tie_mesh() -> ArrayMesh:
	if _tie_mesh != null:
		return _tie_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hl := 1.295
	var tw := 0.115
	var bw := 0.145
	var h := 0.21
	var col := tcol(TIE_COL, T_TIE)
	# Top, the two sloped sides, the ends.
	_q(st, Vector3(-hl, 0.0, -tw), Vector3(hl, 0.0, -tw), Vector3(hl, 0.0, tw), Vector3(-hl, 0.0, tw), Vector3.UP, col)
	for s: float in [-1.0, 1.0]:
		_q(st, Vector3(-hl, 0.0, s * tw), Vector3(hl, 0.0, s * tw), Vector3(hl, -h, s * bw), Vector3(-hl, -h, s * bw), Vector3(0.0, 0.15, s).normalized(), col)
		_q(st, Vector3(s * hl, 0.0, -tw), Vector3(s * hl, 0.0, tw), Vector3(s * hl, -h, bw), Vector3(s * hl, -h, -bw), Vector3(s, 0.0, 0.0), col)
	# Pads and the four clips (a low box each side of each rail foot).
	var pad := tcol(Color(0.06, 0.06, 0.06), T_CLIP)
	var clip := tcol(Color(0.08, 0.075, 0.07), T_CLIP)
	for rx: float in [-0.7535, 0.7535]:
		_box(st, Vector3(rx, 0.006, 0.0), Vector3(0.09, 0.006, 0.1), pad)
		for e: float in [-1.0, 1.0]:
			_box(st, Vector3(rx + e * 0.105, 0.03, 0.0), Vector3(0.035, 0.03, 0.04), clip)
	_tie_mesh = st.commit()
	return _tie_mesh


## A creosoted timber tie (2.6 m) with two steel tie plates.
static func timber_mesh() -> ArrayMesh:
	if _timber_mesh != null:
		return _timber_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := tcol(TIMBER_COL, T_TIMBER)
	_box(st, Vector3(0.0, -0.09, 0.0), Vector3(1.3, 0.09, 0.115), col)
	var plate := tcol(Color(0.2, 0.12, 0.08), T_CLIP)
	for rx: float in [-0.7535, 0.7535]:
		_box(st, Vector3(rx, 0.008, 0.0), Vector3(0.18, 0.008, 0.1), plate)
	_timber_mesh = st.commit()
	return _timber_mesh


static func _q(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, col: Color) -> void:
	for tri_pts: Array in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = tri_pts[0]
		var p1: Vector3 = tri_pts[1]
		var p2: Vector3 = tri_pts[2]
		var n := (p2 - p0).cross(p1 - p0)
		if n.dot(want) < 0.0:
			var t := p1
			p1 = p2
			p2 = t
			n = -n
		n = n.normalized()
		for p: Vector3 in [p0, p1, p2]:
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(Vector2(0.0, p.x))
			st.add_vertex(p)


## An axis-aligned box (no bottom) into `st`.
static func _box(st: SurfaceTool, c: Vector3, h: Vector3, col: Color) -> void:
	var x := Vector3(h.x, 0.0, 0.0)
	var y := Vector3(0.0, h.y, 0.0)
	var z := Vector3(0.0, 0.0, h.z)
	_q(st, c + y - x - z, c + y + x - z, c + y + x + z, c + y - x + z, Vector3.UP, col)
	for s: float in [-1.0, 1.0]:
		_q(st, c + x * s - y - z, c + x * s - y + z, c + x * s + y + z, c + x * s + y - z, Vector3(s, 0.0, 0.0), col)
		_q(st, c + z * s - y - x, c + z * s - y + x, c + z * s + y + x, c + z * s + y - x, Vector3(0.0, 0.0, s), col)


# --- The line ---------------------------------------------------------------------------------

## Every SEG stretch of the line this chunk owns: by mode, the track and its bed, the trench, the
## median.
func _line_step() -> void:
	var n := ceili((fr.s_mouth + 30.0) / SEG)
	var x := fr.avenue_x
	if not (area.position.x <= x + 0.01 and area.end.x > x):
		return
	var k0 := maxi(0, floori((area.position.y - fr.z0) / SEG) - 1)
	var k1 := mini(n - 1, ceili((area.end.y - fr.z0) / SEG) + 1)
	for k in range(k0, k1 + 1):
		var sa := float(k) * SEG
		var sb := sa + SEG
		if not _owns(fr.point((sa + sb) * 0.5, 0.0)):
			continue
		_segment(sa, sb)


func _segment(sa: float, sb: float) -> void:
	var sm := (sa + sb) * 0.5
	var m := fr.mode_at(sm)
	var za := fr.z0 + sa
	var zb := fr.z0 + sb
	var ya := fr.rail_at(sa)
	var yb := fr.rail_at(sb)
	var x := fr.avenue_x
	var H := FreightRail.TRACK_HALF
	if sm > fr.s_mouth + 26.0:
		return
	var mains: Array = [x - H, x + H]
	match m:
		FreightRail.Mode.YARD:
			var ga := ya - FreightRail.TRACK_DEPTH
			var gb := yb - FreightRail.TRACK_DEPTH
			ballast(mains, za, zb, ya, yb, ga, gb, 0.8)
			for tx: float in mains:
				rails(tx, za, tx, zb, ya, yb)
				ties(tx, za, tx, zb, ya, yb)
		FreightRail.Mode.GRADE:
			_median(sa, sb)
		_:
			# Split at the decks' edges: a stretch is under a deck or open all along, or a
			# parapet runs up to 2 m onto the deck and the next stretch leaves the trench open.
			var cuts: Array[float] = [sa]
			for j in fr.junctions:
				if int(j.kind) != FreightRail.Junction.BRIDGE:
					continue
				for e: float in [float(j.s) - float(j.w) * 0.5, float(j.s) + float(j.w) * 0.5]:
					if e > sa + 0.05 and e < sb - 0.05:
						cuts.append(e)
			cuts.sort()
			cuts.append(sb)
			for c in cuts.size() - 1:
				_trench(cuts[c], cuts[c + 1])
	# The crossover: a third track from the east main to the west one.
	if sb > fr.s_xo and sa < fr.s_xo + FreightRail.XO_LEN:
		var s0 := maxf(sa, fr.s_xo)
		var s1 := minf(sb, fr.s_xo + FreightRail.XO_LEN)
		var xa := x - fr.crossover_offset(s0)
		var xb := x - fr.crossover_offset(s1)
		rails(xa, fr.z0 + s0, xb, fr.z0 + s1, fr.rail_at(s0), fr.rail_at(s1))
		ties(xa, fr.z0 + s0, xb, fr.z0 + s1, fr.rail_at(s0), fr.rail_at(s1))


## The trench over one stretch (and the open ramps, where it is shallow), with its track.
func _trench(sa: float, sb: float) -> void:
	var za := fr.z0 + sa
	var zb := fr.z0 + sb
	var ya := fr.rail_at(sa)
	var yb := fr.rail_at(sb)
	var x := fr.avenue_x
	var H := FreightRail.TRACK_HALF
	var TH := FreightRail.TRENCH_HALF
	var W := FreightRail.TRENCH_WALL
	var fa := ya - FreightRail.TRACK_DEPTH - 0.02
	var fb := yb - FreightRail.TRACK_DEPTH - 0.02
	var sta := _street(Vector2(x, za))
	var stb := _street(Vector2(x, zb))
	var under := _deck_over((sa + sb) * 0.5)
	var cc := kind_color(CONC, S_CONCRETE)
	# Floor, drains along both wall feet.
	quad(body, Vector3(x - TH, fa, za), Vector3(x + TH, fa, za), Vector3(x + TH, fb, zb), Vector3(x - TH, fb, zb), Vector3.UP, cc,
		Vector2(za, -TH), Vector2(za, TH), Vector2(zb, TH), Vector2(zb, -TH))
	for side: float in [-1.0, 1.0]:
		var xi := x + side * TH
		var xo := x + side * (TH + W)
		var xd := x + side * (TH - 0.45)
		quad(body, Vector3(xd, fa + 0.012, za), Vector3(xi, fa + 0.012, za), Vector3(xi, fb + 0.012, zb), Vector3(xd, fb + 0.012, zb), Vector3.UP,
			kind_color(Color(0.16, 0.16, 0.15), S_RUBBER))
		var top_a := sta + PARAPET
		var top_b := stb + PARAPET
		if not under.is_empty():
			top_a = float(under.soffit)
			top_b = float(under.soffit)
		# The wall's inside face, floor to the parapet (or the deck's soffit).
		quad(body, Vector3(xi, fa, za), Vector3(xi, fb, zb), Vector3(xi, top_b, zb), Vector3(xi, top_a, za), Vector3(-side, 0.0, 0.0),
			kind_color(WALL_COL, S_PILLAR), Vector2(za, 0.0), Vector2(zb, 0.0), Vector2(zb, top_b - fb), Vector2(za, top_a - fa), Vector2(0.0, top_a - fa))
		if under.is_empty():
			# Parapet top and its street face.
			quad(body, Vector3(xi, top_a, za), Vector3(xo, top_a, za), Vector3(xo, top_b, zb), Vector3(xi, top_b, zb), Vector3.UP, cc)
			quad(body, Vector3(xo, top_a, za), Vector3(xo, top_b, zb), Vector3(xo, stb - 0.08, zb), Vector3(xo, sta - 0.08, za), Vector3(side, 0.0, 0.0),
				kind_color(WALL_COL, S_BARRIER), Vector2(za, PARAPET), Vector2(zb, PARAPET), Vector2(zb, 0.0), Vector2(za, 0.0), Vector2(1.0, 0.0))
			if full:
				_fence_panel(Vector3(x + side * (TH + W * 0.5), top_a, za), Vector3(x + side * (TH + W * 0.5), top_b, zb), sa)
		if full and is_zero_approx(fmod(sa, SEG)) and fmod(sa + (8.0 if side > 0.0 else 24.0), WALL_LIGHT_EVERY) < SEG and fa < sta - 4.0:
			_wall_light(Vector3(xi, fa + 5.6, (za + zb) * 0.5), side)
	# Collision: each wall and the floor, one box a stretch.
	var zm := (za + zb) * 0.5
	var hgt := maxf(sta, stb) + PARAPET + FENCE - minf(fa, fb)
	if not under.is_empty():
		# Under a deck the wall stops at the soffit: a full-height box stood on the cross street.
		hgt = float(under.soffit) - minf(fa, fb)
	for side: float in [-1.0, 1.0]:
		_shapes.append([Vector3(W, hgt, zb - za + 0.05), Transform3D(Basis(), Vector3(x + side * (TH + W * 0.5), minf(fa, fb) + hgt * 0.5, zm))])
	_shapes.append([Vector3(TH * 2.0, 0.4, zb - za + 0.05), Transform3D(Basis(), Vector3(x, (fa + fb) * 0.5 - 0.2, zm))])
	# Track on its bed.
	var mains: Array = [x - H, x + H]
	ballast(mains, za, zb, ya, yb, fa, fb, 1.0)
	for tx: float in mains:
		rails(tx, za, tx, zb, ya, yb)
		ties(tx, za, tx, zb, ya, yb)


## The deck over a trench stretch at s, if a bridged junction is there: {"soffit", "z0", "z1"}.
func _deck_over(s: float) -> Dictionary:
	for j in fr.junctions:
		if int(j.kind) != FreightRail.Junction.BRIDGE:
			continue
		if absf(s - float(j.s)) < float(j.w) * 0.5:
			return {"soffit": _street(Vector2(fr.avenue_x, float(j.z))) - DECK_DEPTH, "z0": float(j.z) - float(j.w) * 0.5, "z1": float(j.z) + float(j.w) * 0.5}
	return {}


## A chain-link panel on the parapet from a to b (on the Industrial walls mesh, its chain-link
## kind), with a post at a.
func _fence_panel(a: Vector3, b: Vector3, s: float) -> void:
	var m := (a + b) * 0.5
	var len := a.distance_to(b)
	Industrial._wbox(chunk, Transform3D(Basis(), m + Vector3(0.0, FENCE * 0.5, 0.0)), Vector3(0.03, FENCE, len), IndustrialKit.K_CHAIN, Color(0.72, 0.73, 0.74), 0.0, 32 | 16)
	if fmod(s, 3.0 * SEG) < SEG:
		Industrial._wbox(chunk, Transform3D(Basis(), a + Vector3(0.0, FENCE * 0.5 + 0.05, 0.0)), Vector3(0.06, FENCE + 0.1, 0.06), IndustrialKit.K_GALV, Color(0.66, 0.67, 0.68))


## A light on a trench wall (side +1 east): the fixture, its lens (lit at night), its pool.
func _wall_light(at: Vector3, side: float) -> void:
	var out := Vector3(-side, 0.0, 0.0)
	box(body, at + out * 0.18, out * 0.18, Vector3.UP * 0.09, Vector3(0, 0, 0.32), kind_color(Color(0.3, 0.31, 0.32), S_PAINTED))
	box(body, at + out * 0.3 + Vector3.DOWN * 0.1, out * 0.1, Vector3.UP * 0.012, Vector3(0, 0, 0.26), kind_color(Color(1.0, 0.9, 0.75), S_LENS), 1.0)
	pool(Vector3(at.x + out.x * 3.0, at.y - 5.5, at.z), Vector3(0, 0, 1), Vector2(14.0, 9.0), Color(1.0, 0.88, 0.7))


## The median at grade over one stretch: kerbs, the ballast between them, the track (and at a
## level crossing, the panels instead).
func _median(sa: float, sb: float) -> void:
	var za := fr.z0 + sa
	var zb := fr.z0 + sb
	var ya := fr.rail_at(sa)
	var yb := fr.rail_at(sb)
	var x := fr.avenue_x
	var H := FreightRail.TRACK_HALF
	var sta := ya - FreightRail.RAIL_ABOVE
	var stb := yb - FreightRail.RAIL_ABOVE
	var mains: Array = [x - H, x + H]
	var j := _junction_at((sa + sb) * 0.5, 0.0)
	if not j.is_empty() and int(j.kind) == FreightRail.Junction.CROSSING:
		# Crossing panels flush with the rail heads, a flangeway inside each rail.
		var pc := tcol(Color(0.62, 0.61, 0.58), T_PANEL)
		var top_a := ya - 0.004
		var top_b := yb - 0.004
		var g := FreightRail.GAUGE * 0.5
		for tx: float in mains:
			for span: Vector2 in [Vector2(-H - 1.4, -g - 0.075), Vector2(-g + 0.075, g - 0.075), Vector2(g + 0.075, H + 1.4 - (H * 2.0 if tx < x else 0.0))]:
				var lo := tx + span.x
				var hi := tx + span.y
				if hi <= lo:
					continue
				quad(track, Vector3(lo, top_a, za), Vector3(hi, top_a, za), Vector3(hi, top_b, zb), Vector3(lo, top_b, zb), Vector3.UP, pc)
			for e: float in [-1.0, 1.0]:
				var f0 := tx + e * g - 0.075 * (1.0 if e > 0.0 else 0.0)
				quad(track, Vector3(f0, top_a - 0.05, za), Vector3(f0 + 0.075, top_a - 0.05, za), Vector3(f0 + 0.075, top_b - 0.05, zb), Vector3(f0, top_b - 0.05, zb), Vector3.UP,
					pc, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(1.0, 0.0))
			rails(tx, za, tx, zb, ya, yb)
		# The panels' street-facing edges where the road meets them (a sliver of asphalt ramp).
		_track_any = true
		return
	# Kerbs.
	for side: float in [-1.0, 1.0]:
		var xk := x + side * (KERB_HALF + KERB_W * 0.5)
		box(body, Vector3(xk, (sta + stb) * 0.5 + KERB_H * 0.5, (za + zb) * 0.5), Vector3(KERB_W * 0.5, 0, 0), Vector3.UP * KERB_H * 0.5,
			Vector3(0, 0, SEG * 0.5), kind_color(CONC, S_BARRIER))
	# Ballast filling the median up to the ties.
	var xs: Array = [x - H, x + H]
	var ta := ya - BALLAST_DROP
	var tb := yb - BALLAST_DROP
	var col := tcol(BALLAST_COL, T_BALLAST)
	quad(track, Vector3(x - KERB_HALF, ta, za), Vector3(x - H - BALLAST_HALF, ta, za), Vector3(x - H - BALLAST_HALF, tb, zb), Vector3(x - KERB_HALF, tb, zb), Vector3.UP, col,
		Vector2(za, -3.0), Vector2(za, -2.0), Vector2(zb, -2.0), Vector2(zb, -3.0), Vector2(0.0, 0.5))
	quad(track, Vector3(x + H + BALLAST_HALF, ta, za), Vector3(x + KERB_HALF, ta, za), Vector3(x + KERB_HALF, tb, zb), Vector3(x + H + BALLAST_HALF, tb, zb), Vector3.UP, col,
		Vector2(za, 2.0), Vector2(za, 3.0), Vector2(zb, 3.0), Vector2(zb, 2.0), Vector2(0.0, 0.5))
	ballast(xs, za, zb, ya, yb, sta, stb, 1.0, false)
	for tx: float in mains:
		rails(tx, za, tx, zb, ya, yb)
		ties(tx, za, tx, zb, ya, yb)


## The junction whose carriageway holds the line's point at s (grown by pad), or {}.
func _junction_at(s: float, pad: float) -> Dictionary:
	for j in fr.junctions:
		if absf(s - float(j.s)) < float(j.w) * 0.5 + pad:
			return j
	return {}


# --- Junctions, signals, the portal ------------------------------------------------------------

func _features_step() -> void:
	for j in fr.junctions:
		var p := Vector2(fr.avenue_x, float(j.z))
		if not _owns(p):
			continue
		match int(j.kind):
			FreightRail.Junction.BRIDGE:
				_deck(j)
			FreightRail.Junction.CROSSING:
				_crossing(j)
			FreightRail.Junction.CLOSED:
				_severed(j)
	if full:
		for sig: Dictionary in signals(fr):
			if _owns(fr.point(float(sig.s), float(sig.off))):
				_signal(sig)
		# The buffer stops at the end of the mains.
		if _owns(fr.point(1.0, 0.0)):
			for off: float in [-FreightRail.TRACK_HALF, FreightRail.TRACK_HALF]:
				_buffer_stop(fr.track_point(0.0, off))
	if _owns(fr.point(fr.s_mouth, 0.0)) or _owns(fr.point(fr.s_mouth + 12.0, 0.0)):
		_portal()


## A deck carrying cross street j over the trench: girders under the road slab, the soffit, a
## fascia and a barrier on each edge facing along the trench, a light under it.
func _deck(j: Dictionary) -> void:
	var x := fr.avenue_x
	var z := float(j.z)
	var hw := float(j.w) * 0.5
	var TH := FreightRail.TRENCH_HALF
	var W := FreightRail.TRENCH_WALL
	var st := _street(Vector2(x, z))
	var soffit := st - DECK_DEPTH
	var cs := kind_color(CONC, S_SOFFIT)
	quad(body, Vector3(x - TH, soffit, z - hw), Vector3(x + TH, soffit, z - hw), Vector3(x + TH, soffit, z + hw), Vector3(x - TH, soffit, z + hw), Vector3.DOWN, cs,
		Vector2(z - hw, -TH), Vector2(z - hw, TH), Vector2(z + hw, TH), Vector2(z + hw, -TH))
	# Girders spanning the trench (along x).
	var g := -hw + GIRDER_STEP * 0.5
	while g < hw:
		box(body, Vector3(x, soffit - 0.32, z + g), Vector3(TH, 0, 0), Vector3.UP * 0.32, Vector3(0, 0, 0.28), kind_color(CONC, S_PILLAR), 0.0, false)
		g += GIRDER_STEP
	for e: float in [-1.0, 1.0]:
		var ze := z + e * hw
		# Fascia: the slab's edge from the street down past the girders.
		quad(body, Vector3(x - TH - W, st + 0.02, ze), Vector3(x + TH + W, st + 0.02, ze), Vector3(x + TH + W, soffit - 0.64, ze), Vector3(x - TH - W, soffit - 0.64, ze),
			Vector3(0, 0, e), kind_color(CONC, S_FASCIA), Vector2(x - TH - W, 0.0), Vector2(x + TH + W, 0.0), Vector2(x + TH + W, -1.6), Vector2(x - TH - W, -1.6))
		# A barrier along the deck edge, so nobody walks off it into the trench.
		box(body, Vector3(x, st + PARAPET * 0.5, ze - e * 0.22), Vector3(TH + W, 0, 0), Vector3.UP * PARAPET * 0.5, Vector3(0, 0, 0.22), kind_color(WALL_COL, S_BARRIER), 1.0)
		if full:
			for k in range(-2, 3):
				Industrial._wbox(chunk, Transform3D(Basis(), Vector3(x + float(k) * (TH + W) * 0.5, st + PARAPET + FENCE * 0.5, ze - e * 0.22)), Vector3((TH + W) * 0.5, FENCE, 0.03), IndustrialKit.K_CHAIN, Color(0.72, 0.73, 0.74), 0.0, 32 | 16)
		_shapes.append([Vector3((TH + W) * 2.0, PARAPET + FENCE, 0.44), Transform3D(Basis(), Vector3(x, st + (PARAPET + FENCE) * 0.5, ze - e * 0.22))])
	if full:
		box(body, Vector3(x, soffit - 0.7, z), Vector3(0.3, 0, 0), Vector3.UP * 0.06, Vector3(0, 0, 0.6), kind_color(Color(0.3, 0.31, 0.32), S_PAINTED))
		box(body, Vector3(x, soffit - 0.77, z), Vector3(0.22, 0, 0), Vector3.UP * 0.01, Vector3(0, 0, 0.5), kind_color(Color(1.0, 0.92, 0.8), S_LENS), 1.0, false)
		pool(Vector3(x, fr.rail_at(float(j.s)) - 0.3, z), Vector3(0, 0, 1), Vector2(18.0, 10.0), Color(1.0, 0.9, 0.76))


## The gates of a level crossing: one assembly on each approach of the cross street (on its right,
## on the corner outside the avenue's kerb), stop bars and the crossing's X on the road.
func _crossing(j: Dictionary) -> void:
	var x := fr.avenue_x
	var z := float(j.z)
	var w := float(j.w)
	var reach := fr.avenue_width * 0.5 + 1.8
	var run_dir := Vector2(1.0, 0.0)
	for approach: float in [-1.0, 1.0]:
		var heading := -run_dir * approach
		var right := Vector2(-heading.y, heading.x)
		var mast := Vector2(x, z) + run_dir * approach * reach + right * (w * 0.5 + 0.7)
		var gy := chunk._gy(mast.x, mast.y) + CityChunk.SIDEWALK_TOP
		var base := Vector3(mast.x, gy, mast.y)
		var h3 := Vector3(heading.x, 0.0, heading.y)
		var r3 := Vector3(right.x, 0.0, right.y)
		if full:
			var col := kind_color(Color(0.80, 0.80, 0.79), S_STEEL)
			prism(body, base, base + Vector3.UP * 4.3, 0.09, 0.08, 8, col)
			box(body, base + Vector3.UP * 0.12, Vector3(0.35, 0, 0), Vector3.UP * 0.12, Vector3(0, 0, 0.35), kind_color(CONC, S_CONCRETE))
			box(body, base + r3 * 0.35 + Vector3.UP * 0.75, r3 * 0.2, Vector3.UP * 0.55, h3 * 0.22, kind_color(Color(0.62, 0.63, 0.62), S_STEEL))
			prism(body, base + Vector3.UP * 4.3, base + Vector3.UP * 4.5, 0.13, 0.04, 8, kind_color(BLACK, S_PAINTED))
			var face := base - h3 * 0.08 + Vector3.UP * 3.75
			for sgn: float in [-1.0, 1.0]:
				var axis_v := (r3 * cos(PI * 0.25) + Vector3.UP * sin(PI * 0.25) * sgn).normalized()
				var up_v := (Vector3.UP * cos(PI * 0.25) - r3 * sin(PI * 0.25) * sgn).normalized()
				box(body, face, axis_v * 0.61, up_v * 0.11, h3 * 0.01, kind_color(Color(0.94, 0.94, 0.92), S_PAINTED))
			# "2 TRACKS" plate under the crossbuck.
			box(body, base - h3 * 0.08 + Vector3.UP * 3.2, r3 * 0.34, Vector3.UP * 0.14, h3 * 0.01, kind_color(Color(0.94, 0.94, 0.92), S_PAINTED))
			_plate_text("2 TRACKS", base - h3 * 0.1 + Vector3.UP * 3.2, -h3, 0.16)
			box(body, base - h3 * 0.05 + Vector3.UP * 2.85, r3 * 0.62, Vector3.UP * 0.04, h3 * 0.04, kind_color(DARK, S_PAINTED))
			for e: float in [-0.48, 0.48]:
				var lc := base - h3 * 0.12 + r3 * e + Vector3.UP * 2.85
				box(body, lc + h3 * 0.06, r3 * 0.24, Vector3.UP * 0.24, h3 * 0.03, kind_color(DARK, S_PAINTED))
				box(body, lc - h3 * 0.06 + Vector3.UP * 0.13, r3 * 0.16, Vector3.UP * 0.015, h3 * 0.13, kind_color(DARK, S_PAINTED))
			# Stop bar and the crossing's X on the approach lanes (right half of the road).
			var paint_y := chunk._gy(mast.x, mast.y) + CityChunk.ROAD_TOP + 0.012
			var bar := Vector2(x, z) + run_dir * approach * (reach + 4.0)
			var lane_c := Vector2(x, z) + right * (w * 0.25)
			_paint_quad(Vector3(bar.x, paint_y, lane_c.y), Vector2(0.3, w * 0.25 - 0.3))
			var xc := Vector2(x, z) + run_dir * approach * (reach + 14.0) + right * (w * 0.25)
			for sgn2: float in [-1.0, 1.0]:
				_paint_bar(Vector3(xc.x, paint_y, xc.y), Vector2(cos(0.6 * sgn2), sin(0.6 * sgn2)), 6.0, 0.4)
		_gates.append({"base": base, "heading": heading, "right": right, "length": w * 0.5 + 0.4, "node": j.node, "axis": CityPlan.AXIS_Z})


func _paint_quad(c: Vector3, half: Vector2) -> void:
	var col := tcol(Color(0.92, 0.92, 0.88), T_PAINT)
	quad(track, c + Vector3(-half.x, 0, -half.y), c + Vector3(half.x, 0, -half.y), c + Vector3(half.x, 0, half.y), c + Vector3(-half.x, 0, half.y), Vector3.UP, col)
	_track_any = true


func _paint_bar(c: Vector3, dir: Vector2, length_m: float, width_m: float) -> void:
	var col := tcol(Color(0.92, 0.92, 0.88), T_PAINT)
	var d := Vector3(dir.x, 0.0, dir.y) * length_m * 0.5
	var n := Vector3(-dir.y, 0.0, dir.x) * width_m * 0.5
	quad(track, c - d - n, c + d - n, c + d + n, c - d + n, Vector3.UP, col)
	_track_any = true


## Black lettering on a white plate facing `out`.
func _plate_text(text: String, at: Vector3, out: Vector3, height: float) -> void:
	var right := Vector3.UP.cross(out).normalized()
	var xf := Transform3D(Basis(right, Vector3.UP, out), at + out * 0.005)
	letters(text, height, Vector2.ZERO, xf, kind_color(BLACK, P_SIGN), Rect2(-1, -1, 2, 2), Vector2.ZERO)


## A severed cross street: a row of K-rail across it just outside the avenue's kerb, on both
## sides, with a ROAD CLOSED board on each.
func _severed(j: Dictionary) -> void:
	var x := fr.avenue_x
	var z := float(j.z)
	var w := float(j.w)
	for side: float in [-1.0, 1.0]:
		var bx := x + side * (fr.avenue_width * 0.5 + 1.4)
		if not _owns(Vector2(bx, z)) and not _owns(Vector2(x, z)):
			continue
		var gy := chunk._gy(bx, z) + CityChunk.ROAD_TOP
		var n := maxi(1, int(w / 3.8))
		for k in n:
			var zc := z - w * 0.5 + (float(k) + 0.5) * w / float(n)
			_k_rail(Vector3(bx, gy, zc), Vector3(0, 0, 1), w / float(n) - 0.1)
		_shapes.append([Vector3(0.6, 0.85, w), Transform3D(Basis(), Vector3(bx, gy + 0.42, z))])
		if full:
			var bc := Vector3(bx, gy + 0.81, z)
			var out := Vector3(side, 0.0, 0.0)
			for pz: float in [-1.0, 1.0]:
				box(body, bc + Vector3(0, 0.55, pz * 1.0), Vector3(0.04, 0, 0), Vector3.UP * 0.55, Vector3(0, 0, 0.04), kind_color(FR_GALV, S_STEEL))
			box(body, bc + Vector3(0, 0.95, 0), Vector3(0.02, 0, 0), Vector3.UP * 0.3, Vector3(0, 0, 1.25), kind_color(Color(0.94, 0.94, 0.92), S_PAINTED))
			# The striped rail under the board (Type III barricade, orange and white).
			for k in 6:
				var c := Color(0.95, 0.42, 0.06) if k % 2 == 0 else Color(0.94, 0.94, 0.92)
				box(body, bc + Vector3(0, 0.45, -1.25 + 0.21 + float(k) * 0.42), Vector3(0.02, 0, 0), Vector3.UP * 0.1, Vector3(0, 0, 0.21), kind_color(c, S_PAINTED))
			_plate_text("ROAD CLOSED", bc + Vector3(0.0, 0.95, 0.0) + out * 0.025, out, 0.3)


## A New Jersey barrier (K-rail) centred at `c` (its foot), along `along`, `len` long.
func _k_rail(c: Vector3, along: Vector3, len: float) -> void:
	var n := along.cross(Vector3.UP).normalized()
	var pts := PackedVector2Array([Vector2(-0.3, 0.0), Vector2(-0.28, 0.08), Vector2(-0.1, 0.33), Vector2(-0.08, 0.81),
		Vector2(0.08, 0.81), Vector2(0.1, 0.33), Vector2(0.28, 0.08), Vector2(0.3, 0.0)])
	var a := c - along * len * 0.5
	var b := c + along * len * 0.5
	var col := kind_color(Color(0.72, 0.71, 0.68), S_BARRIER)
	for i in pts.size() - 1:
		var p := pts[i]
		var q := pts[i + 1]
		var e := q - p
		var on := Vector2(e.y, -e.x).normalized()
		if on.dot((p + q) * 0.5 - Vector2(0.0, 0.3)) < 0.0:
			on = -on
		quad(body, a + n * p.x + Vector3.UP * p.y, a + n * q.x + Vector3.UP * q.y, b + n * q.x + Vector3.UP * q.y, b + n * p.x + Vector3.UP * p.y,
			n * on.x + Vector3.UP * on.y, col, Vector2(0.0, p.y), Vector2(0.0, q.y), Vector2(len, q.y), Vector2(len, p.y), Vector2(1.0, 0.0))
	for e2: float in [-1.0, 1.0]:
		var ec := c + along * len * 0.5 * e2
		var poly: Array[Vector3] = []
		for p in pts:
			poly.append(ec + n * p.x + Vector3.UP * p.y)
		for i in range(1, poly.size() - 1):
			tri(body, poly[0], poly[i], poly[i + 1], along * e2, col)


## Where the line's block signals stand: {"s", "off" (the track, west +), "dir" (-1 facing trains
## going north, +1 south), "kind" ("mast" or "wall")}. Pure.
static func signals(f: FreightRail) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var H := FreightRail.TRACK_HALF
	var s := f.s_yard_end + 40.0
	var k := 0
	while s < f.s_mouth - 20.0:
		for d: int in [-1, 1]:
			# A signal stands on the right of the track it governs for trains coming at it: a
			# northbound (-s) train on the east track (off -H) sees it to its right (east).
			var off := -H if d < 0 else H
			var side := -1.0 if d < 0 else 1.0
			var sm := f.mode_at(s)
			# Never in a junction (a mast in the median would stand in the crossing).
			var ok := true
			for j in f.junctions:
				if absf(s - float(j.s)) < float(j.w) * 0.5 + 4.0:
					ok = false
			if ok:
				out.append({"s": s, "off": off + side * 2.55, "track": off, "dir": d, "kind": "wall" if sm != FreightRail.Mode.GRADE else "mast", "k": k})
		s += SIGNAL_EVERY
		k += 1
	return out


## A block signal: a mast (or a bracket off the trench wall) with a three-lamp head on a black
## target, facing the trains it governs; the top lamp lit green (the line's signals are cleared by
## the timetable: no train is ever let into an occupied block).
func _signal(sig: Dictionary) -> void:
	var s: float = sig.s
	var d: int = sig.dir
	var p := fr.point(s, float(sig.off))
	var face := Vector3(0, 0, -float(d))
	var y0 := fr.rail_at(s) - (FreightRail.TRACK_DEPTH if fr.mode_at(s) != FreightRail.Mode.GRADE else FreightRail.RAIL_ABOVE)
	var base := Vector3(p.x, y0, p.y)
	var head_y := 4.6
	var steel := tcol(FR_GALV, T_STEEL)
	var blk := tcol(BLACK, T_PAINT)
	if str(sig.kind) == "mast":
		_tprism(base, base + Vector3.UP * head_y, 0.08, steel)
		_tbox(base + Vector3.UP * 0.15, Vector3(0.25, 0.15, 0.25), tcol(CONC, T_PAINT))
	else:
		# Bracket off the wall behind the signal.
		var wall_x := fr.avenue_x + (FreightRail.TRENCH_HALF if p.x > fr.avenue_x else -FreightRail.TRENCH_HALF)
		var hy := y0 + head_y
		_tbox(Vector3((wall_x + p.x) * 0.5, hy - 0.4, p.y), Vector3(absf(wall_x - p.x) * 0.5, 0.05, 0.05), steel)
		_tprism(Vector3(p.x, hy - 0.45, p.y), Vector3(p.x, hy + 0.1, p.y), 0.05, steel)
	var hc := base + Vector3.UP * (head_y + 0.55)
	# Target and head.
	_tbox(hc - face * 0.05, Vector3(0.38, 0.62, 0.02), blk)
	_tbox(hc + face * 0.08, Vector3(0.16, 0.5, 0.12), blk)
	var lit := [Color(0.1, 1.0, 0.35), Color(1.0, 0.75, 0.05), Color(1.0, 0.08, 0.04)]
	for i in 3:
		var lc := hc + face * 0.205 + Vector3.UP * (0.32 - 0.32 * float(i))
		var on := 1.0 if i == 0 else 0.0
		_tdisc(lc, face, 0.085, tcol(lit[i], T_LENS), on)
		# Hood over each lamp.
		_tbox(lc + face * 0.08 + Vector3.UP * 0.1, Vector3(0.1, 0.008, 0.08), blk)
	_track_any = true


func _tbox(c: Vector3, h: Vector3, col: Color) -> void:
	box(track, c, Vector3(h.x, 0, 0), Vector3(0, h.y, 0), Vector3(0, 0, h.z), col)


func _tprism(a: Vector3, b: Vector3, r: float, col: Color) -> void:
	prism(track, a, b, r, r, 8, col)


func _tdisc(c: Vector3, n: Vector3, r: float, col: Color, energy: float) -> void:
	var u := n.cross(Vector3.UP).normalized()
	var v := Vector3.UP
	for i in 10:
		var a0 := TAU * float(i) / 10.0
		var a1 := TAU * float(i + 1) / 10.0
		tri(track, c, c + (u * cos(a0) + v * sin(a0)) * r, c + (u * cos(a1) + v * sin(a1)) * r, n, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(energy, 0.0))


## A buffer stop at the end of a main: two rails bent up into a frame, a red and white beam.
func _buffer_stop(p: Vector3) -> void:
	var steel := tcol(Color(0.25, 0.24, 0.23), T_STEEL)
	for e: float in [-0.72, 0.72]:
		_tbox(p + Vector3(e, 0.45, -0.6), Vector3(0.08, 0.45, 0.6), steel)
	_tbox(p + Vector3(0.0, 0.85, -0.05), Vector3(1.1, 0.18, 0.12), tcol(Color(0.85, 0.1, 0.06), T_PAINT))
	for k in 4:
		_tbox(p + Vector3(-0.83 + float(k) * 0.55, 0.85, -0.18), Vector3(0.12, 0.17, 0.005), tcol(Color(0.95, 0.95, 0.92), T_PAINT))
	_shapes.append([Vector3(2.4, 1.2, 1.4), Transform3D(Basis(), p + Vector3(0, 0.6, -0.6))])


## The covered way's portal: a headwall across the trench with the parapet over it, the dark
## bore behind (its walls, a ceiling, the track running into the dark).
func _portal() -> void:
	var x := fr.avenue_x
	var s := fr.s_mouth
	var z := fr.z0 + s
	var y := fr.rail_at(s)
	var TH := FreightRail.TRENCH_HALF
	var W := FreightRail.TRENCH_WALL
	var st := _street(Vector2(x, z))
	var crown := y + 6.6
	var floor_y := y - FreightRail.TRACK_DEPTH
	var cc := kind_color(WALL_COL, S_PILLAR)
	# The headwall face, from the bore's crown to the parapet.
	quad(body, Vector3(x - TH - W, crown, z), Vector3(x + TH + W, crown, z), Vector3(x + TH + W, st + PARAPET, z), Vector3(x - TH - W, st + PARAPET, z), Vector3(0, 0, -1), cc,
		Vector2(x - TH, 0.0), Vector2(x + TH, 0.0), Vector2(x + TH, st + PARAPET - crown), Vector2(x - TH, st + PARAPET - crown), Vector2(0.0, st + PARAPET - crown))
	box(body, Vector3(x, crown + 0.35, z - 0.25), Vector3(TH + W, 0, 0), Vector3.UP * 0.35, Vector3(0, 0, 0.25), kind_color(CONC, S_CONCRETE), 0.0, false)
	box(body, Vector3(x, st + PARAPET * 0.5, z + 0.25), Vector3(TH + W, 0, 0), Vector3.UP * PARAPET * 0.5, Vector3(0, 0, 0.25), kind_color(WALL_COL, S_BARRIER), 1.0)
	if full:
		_plate_text(FreightRail.RAILROAD, Vector3(x, crown + 1.3, z - 0.02), Vector3(0, 0, -1), 0.55)
	# The bore: dark walls, ceiling and floor running in 30 m.
	var dk := kind_color(BORE, S_PAINTED)
	var z1 := z + 30.0
	var y1 := fr.rail_at(s + 30.0)
	quad(body, Vector3(x - TH, crown, z), Vector3(x + TH, crown, z), Vector3(x + TH, crown + (y1 - y), z1), Vector3(x - TH, crown + (y1 - y), z1), Vector3.DOWN, dk)
	for side: float in [-1.0, 1.0]:
		quad(body, Vector3(x + side * TH, floor_y, z), Vector3(x + side * TH, crown, z), Vector3(x + side * TH, crown + (y1 - y), z1), Vector3(x + side * TH, floor_y + (y1 - y), z1), Vector3(-side, 0, 0), dk)
	quad(body, Vector3(x - TH, crown, z1), Vector3(x + TH, crown, z1), Vector3(x + TH, floor_y + (y1 - y), z1), Vector3(x - TH, floor_y + (y1 - y), z1), Vector3(0, 0, -1), dk)
	_shapes.append([Vector3((TH + W) * 2.0, st + PARAPET - crown, 0.5), Transform3D(Basis(), Vector3(x, (crown + st + PARAPET) * 0.5, z))])


# --- Commit ------------------------------------------------------------------------------------

func _commit_step() -> void:
	var tag := "freight_static"
	var mi := _add("FreightStructure", body.commit(), structure_material())
	mi.add_to_group(tag)
	if _track_any:
		var tm := _add("FreightTrack", track.commit(), track_material())
		tm.add_to_group(tag)
	if _paint_any:
		var pm := _add("FreightSigns", paint.commit(), paint_material())
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _glow_any:
		var gi := _add("FreightGlow", glow.commit(), pool_material())
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for pair: Array in [[_ties, tie_mesh(), "FreightTies"], [_timbers, timber_mesh(), "FreightTimbers"]]:
		var buf: PackedFloat32Array = pair[0]
		if buf.is_empty():
			continue
		# With white instance colours: a MultiMesh without use_colors hands the Compatibility
		# renderer's shader a COLOR that is not the vertex colour (the ties' kind rides in it).
		var n := buf.size() / 12
		var cbuf := PackedFloat32Array()
		cbuf.resize(n * 16)
		for i in n:
			for f in 12:
				cbuf[i * 16 + f] = buf[i * 12 + f]
			for f in 4:
				cbuf[i * 16 + 12 + f] = 1.0
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = pair[1]
		mm.instance_count = n
		mm.buffer = cbuf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = pair[2]
		mmi.multimesh = mm
		mmi.material_override = track_material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 260.0
		chunk.add_child(mmi)
	if _yard != null:
		_yard.commit()
	if not _shapes.is_empty():
		var sb := StaticBody3D.new()
		sb.name = "FreightBody"
		sb.collision_layer = 1
		sb.collision_mask = 0
		for sh: Array in _shapes:
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = sh[0]
			cs.shape = bx
			cs.transform = sh[1]
			sb.add_child(cs)
		chunk.add_child(sb)
	for g in _gates:
		var gate := RailGate.make(g, full)
		gate.remove_from_group("rail_gate")
		gate.add_to_group("freight_gate")
		chunk.add_child(gate)
	chunk.remove_meta("freight_kit")
