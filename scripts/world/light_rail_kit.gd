class_name LightRailKit
extends FreewayKit
## The Coral Line's fixed works in one chunk (LightRail is the line itself; this builds what a
## chunk owns of it): every 2 m sample segment whose midpoint is in the chunk's owned rect, and
## every pole, column, station, crossing and substation whose position is.
##
##   at grade  a concrete trackway down the street's median, a hair over the asphalt, with the
##             rails embedded flush (polished head, dark flangeway);
##   trench    the portal: U-walls from the trench floor to a parapet over the street, a headwall
##             at the tunnel mouth with the dark bore behind it, sleepers and real rail profiles;
##   aerial    a box girder with parapets, a ballast bed with concrete sleepers and real rails,
##             round columns with hammerhead caps in the median every COLUMN_SPACING (never in a
##             junction or over a freeway, where the span grows instead);
##   overhead  centre poles every LightRail.POLE_SPACING with a cantilever and a registration arm
##             over each track, the messenger sagging between poles, droppers, and the contact
##             wire staggered from side to side at each pole (FULL only; LOD keeps the poles);
##   stations  island platforms (tactile edges, a ramp to the crosswalk at grade, a lift tower on
##             the structure), a canopy on a row of columns with lit soffit strips and a band of
##             the line's colour, benches, ticket machines, a lit map case, a lit name pylon and
##             hanging name signs, light pools; the underground terminus is two stair kiosks in
##             the median;
##   crossings gate assemblies (mast, flashers, crossbuck, bell, counterweight) at each approach,
##             the arms and flashing lamps as nodes the LightRailSystem drives;
##   power     traction substations under the structure.
##
## Into FreewayKit's meshes (its structure shader, its sign paint, its pools): a chunk with the
## line draws three more meshes, the gates a few nodes each. Hashes only, no rng.

const TRACKWAY_EXTRA := 1.45
const GAUGE := 1.435
const RAIL_HEAD := 0.072
const COLUMN_SPACING := 30.0
const DECK_EXTRA := 1.75
const DECK_DEPTH := 2.0
const PARAPET := 1.05
const SLEEPER_SPACING := 0.65
const TRENCH_WALL := 0.45

const CONC_TRACK := Color(0.47, 0.465, 0.45)
const CONC_STRUCT := Color(0.72, 0.71, 0.68)
const RAIL_STEEL := Color(0.50, 0.48, 0.46)
const RAIL_TOP := Color(0.80, 0.80, 0.79)
const GROOVE := Color(0.05, 0.05, 0.05)
const BALLAST := Color(0.44, 0.42, 0.39)
const POLE := Color(0.33, 0.35, 0.36)
const WIRE := Color(0.30, 0.22, 0.16)
const TACTILE := Color(0.95, 0.78, 0.10)
const CANOPY := Color(0.86, 0.86, 0.84)
const DARK := Color(0.10, 0.10, 0.11)
const BORE := Color(0.012, 0.012, 0.013)
const MACHINE := Color(0.20, 0.21, 0.23)

## The real rail section (a 115 lb rail, metres: x across, y up from the foot).
const RAIL_PROFILE := [Vector2(-0.07, 0.0), Vector2(0.07, 0.0), Vector2(0.07, 0.012), Vector2(0.013, 0.034),
	Vector2(0.009, 0.108), Vector2(0.036, 0.124), Vector2(0.036, 0.168), Vector2(-0.036, 0.168),
	Vector2(-0.036, 0.124), Vector2(-0.009, 0.108), Vector2(-0.013, 0.034), Vector2(-0.07, 0.012)]

var line: LightRail
var _signs: Array[Dictionary] = []
var _gates: Array[Dictionary] = []
var _shapes: Array = []


func _init(c: CityChunk) -> void:
	super(c)
	line = LightRail.of(plan)


## Everything this chunk owns of the line, then commits it. Returns false when there was nothing.
func build_all() -> bool:
	if line == null:
		return false
	var area := chunk.owned_rect()
	var idx := line.indices_in(area)
	var any := not idx.is_empty()
	for i in idx:
		_segment(i)
	any = _features(area) or any
	if not any:
		return false
	_commit()
	return true


# --- Helpers ---------------------------------------------------------------------------------

func _col(c: Color, kind: int) -> Color:
	return kind_color(c, kind)


## The street (the chunk's own drawn relief) at a world XZ.
func _street(p: Vector2) -> float:
	return chunk._gy(p.x, p.y) + CityChunk.ROAD_TOP


## Frame at sample i: position, direction, right vector (all world XZ).
func _frame(i: int) -> Array:
	var d: Vector2 = line.dirs[i]
	return [line.pts[i], d, Vector2(-d.y, d.x)]


func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


# --- Per segment -----------------------------------------------------------------------------

func _segment(i: int) -> void:
	var j := i + 1
	var m: int = line.mode[i]
	var m2: int = line.mode[j]
	if m == LightRail.Mode.TUNNEL and m2 == LightRail.Mode.TUNNEL:
		return
	var fa := _frame(i)
	var fb := _frame(j)
	var pa: Vector2 = fa[0]
	var pb: Vector2 = fb[0]
	var ra: Vector2 = fa[2]
	var rb: Vector2 = fb[2]
	var ha: float = line.half[i]
	var hb: float = line.half[j]
	var ya: float = line.rail[i]
	var yb: float = line.rail[j]
	var sa: float = line.run[i]
	var sb: float = line.run[j]
	if m == LightRail.Mode.GRADE and m2 == LightRail.Mode.GRADE:
		_trackway(pa, pb, ra, rb, ha, hb, sa, sb)
	elif m == LightRail.Mode.AERIAL or m2 == LightRail.Mode.AERIAL:
		_deck(pa, pb, ra, rb, ha, hb, ya, yb, sa, sb)
	else:
		_trench(pa, pb, ra, rb, ha, hb, ya, yb, sa, sb)
	if full:
		_wires(i)


## At grade: the trackway slab flush in the median, the rails' heads and flangeways in it.
func _trackway(pa: Vector2, pb: Vector2, ra: Vector2, rb: Vector2, ha: float, hb: float, sa: float, sb: float) -> void:
	var lift := 0.03
	var wa := ha + TRACKWAY_EXTRA
	var wb := hb + TRACKWAY_EXTRA
	var la := pa - ra * wa
	var lb := pb - rb * wb
	var r_a := pa + ra * wa
	var r_b := pb + rb * wb
	var c := _col(CONC_TRACK, S_CONCRETE)
	var y_la := _street(la) + lift
	var y_ra := _street(r_a) + lift
	var y_lb := _street(lb) + lift
	var y_rb := _street(r_b) + lift
	quad(body, _v3(la, y_la), _v3(r_a, y_ra), _v3(r_b, y_rb), _v3(lb, y_lb), Vector3.UP, c,
		Vector2(sa, -wa), Vector2(sa, wa), Vector2(sb, wb), Vector2(sb, -wb))
	# The slab's edges stand a hair proud of the asphalt.
	for side: float in [-1.0, 1.0]:
		var ea := pa + ra * side * wa
		var eb := pb + rb * side * wb
		var ya := _street(ea) + lift
		var yb := _street(eb) + lift
		var out3 := Vector3(ra.x, 0.0, ra.y) * side
		quad(body, _v3(ea, ya), _v3(eb, yb), _v3(eb, yb - 0.08), _v3(ea, ya - 0.08), out3, c,
			Vector2(sa, 0.08), Vector2(sb, 0.08), Vector2(sb, 0.0), Vector2(sa, 0.0))
	if not full:
		return
	for track: float in [-1.0, 1.0]:
		for rail_side: float in [-1.0, 1.0]:
			var off_a := track * ha + rail_side * (GAUGE * 0.5 + RAIL_HEAD * 0.5)
			var off_b := track * hb + rail_side * (GAUGE * 0.5 + RAIL_HEAD * 0.5)
			_flat_strip(pa + ra * off_a, pb + rb * off_b, ra, rb, RAIL_HEAD, lift + 0.004, _col(RAIL_TOP, S_STEEL), sa, sb)
			# The flangeway on the inside of each rail.
			var g_a := off_a - rail_side * (RAIL_HEAD * 0.5 + 0.026)
			var g_b := off_b - rail_side * (RAIL_HEAD * 0.5 + 0.026)
			_flat_strip(pa + ra * g_a, pb + rb * g_b, ra, rb, 0.045, lift + 0.003, _col(GROOVE, S_RUBBER), sa, sb)


func _flat_strip(ca: Vector2, cb: Vector2, ra: Vector2, rb: Vector2, w: float, lift: float, col: Color, sa: float, sb: float) -> void:
	var a0 := ca - ra * w * 0.5
	var a1 := ca + ra * w * 0.5
	var b0 := cb - rb * w * 0.5
	var b1 := cb + rb * w * 0.5
	quad(body, _v3(a0, _street(a0) + lift), _v3(a1, _street(a1) + lift), _v3(b1, _street(b1) + lift), _v3(b0, _street(b0) + lift),
		Vector3.UP, col, Vector2(sa, 0.0), Vector2(sa, w), Vector2(sb, w), Vector2(sb, 0.0))


## A rail of the real section from a to b (rail foot points), `ra`/`rb` across.
func _rail(a: Vector3, b: Vector3, ra: Vector2, rb: Vector2, sa: float, sb: float) -> void:
	var n := RAIL_PROFILE.size()
	var ca := Vector3(ra.x, 0.0, ra.y)
	var cb := Vector3(rb.x, 0.0, rb.y)
	var mid := Vector2(0.0, 0.09)
	for k in n:
		var p: Vector2 = RAIL_PROFILE[k]
		var q: Vector2 = RAIL_PROFILE[(k + 1) % n]
		if p.y < 0.001 and q.y < 0.001:
			continue
		var e := q - p
		var on := Vector2(e.y, -e.x).normalized()
		if on.dot((p + q) * 0.5 - mid) < 0.0:
			on = -on
		var want := (ca + cb).normalized() * on.x + Vector3.UP * on.y
		var top := p.y > 0.16 and q.y > 0.16
		var col := _col(RAIL_TOP if top else RAIL_STEEL, S_STEEL)
		quad(body, a + ca * p.x + Vector3.UP * p.y, a + ca * q.x + Vector3.UP * q.y,
			b + cb * q.x + Vector3.UP * q.y, b + cb * p.x + Vector3.UP * p.y, want, col,
			Vector2(sa, p.y), Vector2(sa, q.y), Vector2(sb, q.y), Vector2(sb, p.y))


## Rails and sleepers on a bed at the rail-foot heights ya/yb (structure and trench).
func _track_on_bed(pa: Vector2, pb: Vector2, ra: Vector2, rb: Vector2, ha: float, hb: float, ya: float, yb: float, sa: float, sb: float) -> void:
	var foot_a := ya - 0.168
	var foot_b := yb - 0.168
	for track: float in [-1.0, 1.0]:
		if full:
			for rail_side: float in [-1.0, 1.0]:
				var oa := track * ha + rail_side * (GAUGE * 0.5 + 0.036)
				var ob := track * hb + rail_side * (GAUGE * 0.5 + 0.036)
				var a3 := _v3(pa + ra * oa, foot_a)
				var b3 := _v3(pb + rb * ob, foot_b)
				_rail(a3, b3, ra, rb, sa, sb)
			# Concrete sleepers on SLEEPER_SPACING of the route.
			var k0 := ceili(sa / SLEEPER_SPACING)
			var k1 := floori(sb / SLEEPER_SPACING)
			for k in range(k0, k1 + 1):
				var t := clampf((float(k) * SLEEPER_SPACING - sa) / maxf(sb - sa, 0.001), 0.0, 1.0)
				var p := pa.lerp(pb, t)
				var r := ra.lerp(rb, t).normalized()
				var h := lerpf(ha, hb, t)
				var y := lerpf(foot_a, foot_b, t) - 0.11
				var c := _v3(p + r * track * h, y)
				var d3 := Vector3(-r.y, 0.0, r.x)
				box(body, c, Vector3(r.x, 0.0, r.y) * 1.3, Vector3.UP * 0.11, d3 * 0.12, _col(CONC_STRUCT, S_CONCRETE))
		else:
			for rail_side: float in [-1.0, 1.0]:
				var oa := track * ha + rail_side * (GAUGE * 0.5 + 0.036)
				var ob := track * hb + rail_side * (GAUGE * 0.5 + 0.036)
				var a0 := pa + ra * (oa - 0.04)
				var a1 := pa + ra * (oa + 0.04)
				var b0 := pb + rb * (ob - 0.04)
				var b1 := pb + rb * (ob + 0.04)
				quad(body, _v3(a0, ya), _v3(a1, ya), _v3(b1, yb), _v3(b0, yb), Vector3.UP, _col(RAIL_TOP, S_STEEL))


## The aerial structure over one segment: deck, parapets, girder, ballast bed and track.
func _deck(pa: Vector2, pb: Vector2, ra: Vector2, rb: Vector2, ha: float, hb: float, ya: float, yb: float, sa: float, sb: float) -> void:
	var wa := ha + DECK_EXTRA
	var wb := hb + DECK_EXTRA
	var bed_a := ya - 0.168 - 0.33
	var bed_b := yb - 0.168 - 0.33
	var top_a := bed_a - 0.05
	var top_b := bed_b - 0.05
	var cs := _col(CONC_STRUCT, S_CONCRETE)
	var r3a := Vector3(ra.x, 0.0, ra.y)
	var r3b := Vector3(rb.x, 0.0, rb.y)
	var A := _v3(pa, 0.0)
	var B := _v3(pb, 0.0)
	# The ballast bed between the parapets' inner faces.
	var bw_a := wa - 0.35
	var bw_b := wb - 0.35
	quad(body, A - r3a * bw_a + Vector3.UP * bed_a, A + r3a * bw_a + Vector3.UP * bed_a,
		B + r3b * bw_b + Vector3.UP * bed_b, B - r3b * bw_b + Vector3.UP * bed_b, Vector3.UP, _col(BALLAST, S_RUBBER),
		Vector2(sa, 0.0), Vector2(sa, 1.0), Vector2(sb, 1.0), Vector2(sb, 0.0))
	# Parapets (inner face, top, outer face) and the girder's side down to its soffit.
	for side: float in [-1.0, 1.0]:
		var ia := A + r3a * side * bw_a
		var ib := B + r3b * side * bw_b
		var oa := A + r3a * side * wa
		var ob := B + r3b * side * wb
		var pt_a := top_a + PARAPET
		var pt_b := top_b + PARAPET
		quad(body, ia + Vector3.UP * bed_a, ib + Vector3.UP * bed_b, ib + Vector3.UP * pt_b, ia + Vector3.UP * pt_a,
			-r3a * side, _col(CONC_STRUCT, S_BARRIER), Vector2(sa, 0.0), Vector2(sb, 0.0), Vector2(sb, PARAPET), Vector2(sa, PARAPET))
		quad(body, ia + Vector3.UP * pt_a, ib + Vector3.UP * pt_b, ob + Vector3.UP * pt_b, oa + Vector3.UP * pt_a,
			Vector3.UP, cs, Vector2(sa, 0.0), Vector2(sb, 0.0), Vector2(sb, 0.35), Vector2(sa, 0.35))
		# Outer face: the fascia from the parapet top down to the girder's lip.
		var lip_a := top_a - 0.55
		var lip_b := top_b - 0.55
		quad(body, oa + Vector3.UP * pt_a, ob + Vector3.UP * pt_b, ob + Vector3.UP * lip_b, oa + Vector3.UP * lip_a,
			r3a * side, _col(CONC_STRUCT, S_FASCIA), Vector2(sa, 0.0), Vector2(sb, 0.0), Vector2(sb, -1.6), Vector2(sa, -1.6))
		# The cantilever's underside to the web, the web's inclined face to the soffit.
		var web_a := A + r3a * side * (wa - 1.6)
		var web_b := B + r3b * side * (wb - 1.6)
		var foot_a := A + r3a * side * (wa - 2.3)
		var foot_b := B + r3b * side * (wb - 2.3)
		quad(body, oa + Vector3.UP * lip_a, ob + Vector3.UP * lip_b, web_b + Vector3.UP * (lip_b - 0.25), web_a + Vector3.UP * (lip_a - 0.25),
			Vector3.DOWN + r3a * side * 0.2, _col(CONC_STRUCT, S_SOFFIT), Vector2(sa, side * wa), Vector2(sb, side * wb), Vector2(sb, side * (wb - 1.6)), Vector2(sa, side * (wa - 1.6)))
		quad(body, web_a + Vector3.UP * (lip_a - 0.25), web_b + Vector3.UP * (lip_b - 0.25), foot_b + Vector3.UP * (top_b - DECK_DEPTH), foot_a + Vector3.UP * (top_a - DECK_DEPTH),
			r3a * side + Vector3.DOWN * 0.3, cs, Vector2(sa, -0.8), Vector2(sb, -0.8), Vector2(sb, -DECK_DEPTH), Vector2(sa, -DECK_DEPTH))
	# The bottom slab.
	var fa := wa - 2.3
	var fb := wb - 2.3
	quad(body, A - r3a * fa + Vector3.UP * (top_a - DECK_DEPTH), A + r3a * fa + Vector3.UP * (top_a - DECK_DEPTH),
		B + r3b * fb + Vector3.UP * (top_b - DECK_DEPTH), B - r3b * fb + Vector3.UP * (top_b - DECK_DEPTH), Vector3.DOWN,
		_col(CONC_STRUCT, S_SOFFIT), Vector2(sa, -fa), Vector2(sa, fa), Vector2(sb, fb), Vector2(sb, -fb))
	_track_on_bed(pa, pb, ra, rb, ha, hb, ya, yb, sa, sb)
	# Collision: the deck as one tilted box a segment (the trains need none; the player does).
	var mid := (A + B) * 0.5
	var fwd := Vector3(pb.x - pa.x, yb - ya, pb.y - pa.y)
	var len := fwd.length()
	if len > 0.01:
		_shapes.append([Vector3(wa * 2.0, 0.6, len + 0.05), Transform3D(_basis(fwd, r3a), mid + Vector3.UP * ((bed_a + bed_b) * 0.5 - 0.3))])


func _basis(fwd: Vector3, right: Vector3) -> Basis:
	var f := fwd.normalized()
	var up := right.normalized().cross(f).normalized()
	if up.y < 0.0:
		up = -up
	var r := f.cross(up).normalized()
	return Basis(r, up, -f)


## The portal trench (and its headwall at the mouth).
func _trench(pa: Vector2, pb: Vector2, ra: Vector2, rb: Vector2, ha: float, hb: float, ya: float, yb: float, sa: float, sb: float) -> void:
	var wa := ha + LightRail.TRENCH_HALF_EXTRA
	var wb := hb + LightRail.TRENCH_HALF_EXTRA
	var floor_a := ya - 0.168 - 0.25
	var floor_b := yb - 0.168 - 0.25
	var r3a := Vector3(ra.x, 0.0, ra.y)
	var r3b := Vector3(rb.x, 0.0, rb.y)
	var A := _v3(pa, 0.0)
	var B := _v3(pb, 0.0)
	quad(body, A - r3a * wa + Vector3.UP * floor_a, A + r3a * wa + Vector3.UP * floor_a,
		B + r3b * wb + Vector3.UP * floor_b, B - r3b * wb + Vector3.UP * floor_b, Vector3.UP, _col(CONC_STRUCT, S_CONCRETE),
		Vector2(sa, 0.0), Vector2(sa, 1.0), Vector2(sb, 1.0), Vector2(sb, 0.0))
	for side: float in [-1.0, 1.0]:
		var ia := A + r3a * side * wa
		var ib := B + r3b * side * wb
		var oa := A + r3a * side * (wa + TRENCH_WALL)
		var ob := B + r3b * side * (wb + TRENCH_WALL)
		var sta := _street(Vector2(ia.x, ia.z)) + PARAPET
		var stb := _street(Vector2(ib.x, ib.z)) + PARAPET
		quad(body, ia + Vector3.UP * floor_a, ib + Vector3.UP * floor_b, ib + Vector3.UP * stb, ia + Vector3.UP * sta,
			-r3a * side, _col(CONC_STRUCT, S_PILLAR), Vector2(sa, 0.0), Vector2(sb, 0.0), Vector2(sb, stb - floor_b), Vector2(sa, sta - floor_a), Vector2(0.0, sta - floor_a))
		quad(body, ia + Vector3.UP * sta, ib + Vector3.UP * stb, ob + Vector3.UP * stb, oa + Vector3.UP * sta,
			Vector3.UP, _col(CONC_STRUCT, S_CONCRETE))
		quad(body, oa + Vector3.UP * sta, ob + Vector3.UP * stb, ob + Vector3.UP * (stb - PARAPET - 0.1), oa + Vector3.UP * (sta - PARAPET - 0.1),
			r3a * side, _col(CONC_STRUCT, S_BARRIER), Vector2(sa, PARAPET), Vector2(sb, PARAPET), Vector2(sb, 0.0), Vector2(sa, 0.0))
		# The wall as collision, so nothing walks or drives into the trench from the street.
		var mid := (ia + ib + oa + ob) * 0.25
		var fwd := ib - ia
		var hgt := maxf(sta, stb) - minf(floor_a, floor_b)
		_shapes.append([Vector3(TRENCH_WALL, hgt, fwd.length() + 0.05), Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), mid + Vector3.UP * (minf(floor_a, floor_b) + hgt * 0.5))])
	_track_on_bed(pa, pb, ra, rb, ha, hb, ya, yb, sa, sb)
	# The headwall at the mouth: the face over the bore and the dark bore behind it.
	if sa <= line.mouth_s and sb > line.mouth_s:
		_headwall()


func _headwall() -> void:
	var smp := line.sample(line.mouth_s)
	var p: Vector2 = smp.pos
	var d: Vector2 = smp.dir
	var r := Vector2(-d.y, d.x)
	var w: float = float(smp.half) + LightRail.TRENCH_HALF_EXTRA + TRENCH_WALL
	var rail_y: float = smp.y
	var roof := rail_y + 6.0
	var st := _street(p) + PARAPET + 0.3
	var r3 := Vector3(r.x, 0.0, r.y)
	var d3 := Vector3(d.x, 0.0, d.y)
	var c := _v3(p, 0.0)
	# Face above the opening, facing out of the tunnel (toward +s).
	quad(body, c - r3 * w + Vector3.UP * roof, c + r3 * w + Vector3.UP * roof, c + r3 * w + Vector3.UP * st, c - r3 * w + Vector3.UP * st,
		d3, _col(CONC_STRUCT, S_PILLAR), Vector2(0.0, 0.0), Vector2(w * 2.0, 0.0), Vector2(w * 2.0, st - roof), Vector2(0.0, st - roof), Vector2(0.0, st - roof))
	quad(body, c - r3 * w + Vector3.UP * st, c + r3 * w + Vector3.UP * st, c + r3 * w + Vector3.UP * st - d3 * 0.6, c - r3 * w + Vector3.UP * st - d3 * 0.6,
		Vector3.UP, _col(CONC_STRUCT, S_CONCRETE))
	# The bore: a dark box going back into the hill (the train vanishes into it).
	var depth := 40.0
	var wi := w - TRENCH_WALL
	var fl := rail_y - 0.45
	var back := c - d3 * depth
	var bore := _col(BORE, S_RUBBER)
	quad(body, c - r3 * wi + Vector3.UP * roof, back - r3 * wi + Vector3.UP * (roof - depth * 0.045), back + r3 * wi + Vector3.UP * (roof - depth * 0.045), c + r3 * wi + Vector3.UP * roof, Vector3.DOWN, bore)
	for side: float in [-1.0, 1.0]:
		quad(body, c + r3 * side * wi + Vector3.UP * fl, back + r3 * side * wi + Vector3.UP * (fl - depth * 0.045),
			back + r3 * side * wi + Vector3.UP * (roof - depth * 0.045), c + r3 * side * wi + Vector3.UP * roof, -r3 * side, bore)
	quad(body, back - r3 * wi + Vector3.UP * (fl - depth * 0.045), back + r3 * wi + Vector3.UP * (fl - depth * 0.045),
		back + r3 * wi + Vector3.UP * (roof - depth * 0.045), back - r3 * wi + Vector3.UP * (roof - depth * 0.045), d3, bore)
	quad(body, c - r3 * wi + Vector3.UP * fl, c + r3 * wi + Vector3.UP * fl, back + r3 * wi + Vector3.UP * (fl - depth * 0.045), back - r3 * wi + Vector3.UP * (fl - depth * 0.045), Vector3.UP, bore)


# --- Overhead line ---------------------------------------------------------------------------

## Whether a world XZ is inside a road junction, grown by `pad` (LightRail.in_junction()).
func _in_junction(p: Vector2, pad: float) -> bool:
	return line.in_junction(p, pad)


## Contact wire and messenger over both tracks for segment i (FULL).
func _wires(i: int) -> void:
	var j := i + 1
	var sa: float = line.run[i]
	var sb: float = line.run[j]
	if sb < line.mouth_s:
		return
	for track: float in [-1.0, 1.0]:
		var a := _wire_points(sa, track)
		var b := _wire_points(sb, track)
		_wire(a[0], b[0], 0.0065)
		_wire(a[1], b[1], 0.0055)
		# A dropper wherever one falls in this segment (every ~9 m of the span).
		var span := _span(sa)
		var n_drop := maxi(int((float(span[1]) - float(span[0])) / 9.0), 2)
		var step: float = (float(span[1]) - float(span[0])) / float(n_drop)
		for k in range(1, n_drop):
			var sd: float = span[0] + step * float(k)
			if sd >= sa and sd < sb:
				var w := _wire_points(sd, track)
				_wire(w[0], w[1], 0.004)


func _span(s: float) -> Array:
	return line.span_at(s)


## [contact point, messenger point] over track `track` at s.
func _wire_points(s: float, track: float) -> Array:
	var span := _span(s)
	var s0: float = span[0]
	var s1: float = span[1]
	var t := clampf((s - s0) / maxf(s1 - s0, 0.1), 0.0, 1.0)
	var k: int = span[2]
	# Stagger: the contact wire zig-zags +-0.2 m about the track from pole to pole.
	var st0 := 0.2 * (1.0 if posmod(k, 2) == 0 else -1.0)
	var stagger := lerpf(st0, -st0, t)
	var smp := line.sample(s)
	var d: Vector2 = smp.dir
	var r := Vector2(-d.y, d.x)
	var p: Vector2 = (smp.pos as Vector2) + r * (track * float(smp.half) + stagger)
	var pm: Vector2 = (smp.pos as Vector2) + r * (track * float(smp.half))
	var cy: float = float(smp.y) + LightRail.CONTACT_HEIGHT - 0.04 * sin(t * PI)
	var sag := 0.42 * 4.0 * t * (1.0 - t)
	var my: float = float(smp.y) + LightRail.CONTACT_HEIGHT + LightRail.SYSTEM_HEIGHT - sag
	return [Vector3(p.x, cy, p.y), Vector3(pm.x, my, pm.y)]


func _wire(a: Vector3, b: Vector3, r: float) -> void:
	prism(body, a, b, r, r, 3, _col(WIRE, S_STEEL), false)


## A centre pole at s with a cantilever and a registration arm over each track.
func _pole(s: float) -> void:
	var smp := line.sample(s)
	var p: Vector2 = smp.pos
	var d: Vector2 = smp.dir
	var r := Vector2(-d.y, d.x)
	var y: float = smp.y
	var m: int = smp.mode
	var foot := y - 0.5
	if m == LightRail.Mode.GRADE:
		foot = _street(p)
	var top := y + LightRail.CONTACT_HEIGHT + LightRail.SYSTEM_HEIGHT + 0.7
	var base := _v3(p, foot)
	var col := _col(POLE, S_PAINTED)
	if not full:
		box(body, base + Vector3.UP * (top - foot) * 0.5, Vector3(0.14, 0, 0), Vector3.UP * (top - foot) * 0.5, Vector3(0, 0, 0.14), col)
		return
	prism(body, base, _v3(p, top), 0.16, 0.12, 8, col)
	box(body, base + Vector3.UP * 0.2, Vector3(0.32, 0, 0), Vector3.UP * 0.2, Vector3(0, 0, 0.32), _col(CONC_STRUCT, S_CONCRETE))
	var half: float = smp.half
	var r3 := Vector3(r.x, 0.0, r.y)
	var my := y + LightRail.CONTACT_HEIGHT + LightRail.SYSTEM_HEIGHT
	var cy := y + LightRail.CONTACT_HEIGHT
	var k: int = line.span_at(s + 0.01)[2]
	var stagger := 0.2 * (1.0 if posmod(k, 2) == 0 else -1.0)
	for track: float in [-1.0, 1.0]:
		var c := _v3(p, 0.0)
		var tip := c + r3 * track * (half + 0.45)
		# The cantilever (a tube out to over the track), its stay, the registration arm down to
		# the contact wire, insulators at the pole end.
		prism(body, c + r3 * track * 0.1 + Vector3.UP * my, tip + Vector3.UP * my, 0.035, 0.035, 5, _col(RAIL_STEEL, S_STEEL))
		prism(body, c + r3 * track * 0.1 + Vector3.UP * (my + 0.55), tip + Vector3.UP * my - r3 * track * 0.4, 0.02, 0.02, 4, _col(RAIL_STEEL, S_STEEL))
		var contact := c + r3 * (track * half + stagger) + Vector3.UP * cy
		prism(body, tip + Vector3.UP * my - r3 * track * 0.25, contact + Vector3.UP * 0.02, 0.018, 0.018, 4, _col(RAIL_STEEL, S_STEEL))
		prism(body, c + r3 * track * 0.12 + Vector3.UP * my, c + r3 * track * 0.42 + Vector3.UP * my, 0.06, 0.06, 6, _col(Color(0.45, 0.30, 0.18), S_PAINTED))


# --- Features: poles, columns, stations, crossings, substations ------------------------------

func _owns(p: Vector2) -> bool:
	return chunk.owned_rect().has_point(p)


func _features(area: Rect2) -> bool:
	var any := false
	# Poles.
	for s: float in line.poles:
		if _owns(line.sample(s).pos):
			_pole(s)
			any = true
	# Columns under the structure.
	var c0 := 0
	var c1 := ceili(line.length / COLUMN_SPACING)
	for k in range(c0, c1 + 1):
		var s := float(k) * COLUMN_SPACING + 5.0
		var smp := line.sample(s)
		if int(smp.mode) != LightRail.Mode.AERIAL or not _owns(smp.pos):
			continue
		var p: Vector2 = smp.pos
		var ground := _street(p) - 0.1
		var deck_bottom: float = float(smp.y) - 0.168 - 0.38 - DECK_DEPTH
		if deck_bottom - ground < 2.6:
			continue
		if _in_junction(p, 2.0):
			continue
		if plan.macro.freeway != null and plan.macro.freeway.blocks(p, 2.5):
			continue
		_column(smp, ground, deck_bottom)
		any = true
	# Stations.
	for st in line.stations:
		if _owns(st.pos):
			_station(st)
			any = true
	# Crossings.
	for c in line.crossings:
		if bool(c.gates) and _owns(c.pos):
			_crossing(c)
			any = true
	# Substations, under the structure.
	for s: float in _substations():
		var smp := line.sample(s)
		if _owns(smp.pos):
			_substation(smp)
			any = true
	return any


## Where the traction substations stand: under the structure, one every ~1.2 km of it, never in
## a junction or under a freeway.
func _substations() -> Array[float]:
	var out: Array[float] = []
	var last := -INF
	for i in line.pts.size():
		if line.mode[i] != LightRail.Mode.AERIAL:
			continue
		var s: float = line.run[i]
		if s - last < 1200.0:
			continue
		var p := line.pts[i]
		if line.rail[i] - line.street[i] < 7.0 or _in_junction(p, 8.0):
			continue
		if plan.macro.freeway != null and plan.macro.freeway.blocks(p, 10.0):
			continue
		var ok := true
		for st in line.stations:
			if absf(float(st.s) - s) < LightRail.PLATFORM_LENGTH:
				ok = false
		if not ok:
			continue
		out.append(s)
		last = s
	return out


func _column(smp: Dictionary, ground: float, deck_bottom: float) -> void:
	var p: Vector2 = smp.pos
	var d: Vector2 = smp.dir
	var r := Vector2(-d.y, d.x)
	var r3 := Vector3(r.x, 0.0, r.y)
	var d3 := Vector3(d.x, 0.0, d.y)
	var cap_h := 1.4
	var col_top := deck_bottom - cap_h
	var base := _v3(p, ground)
	var col := _col(CONC_STRUCT, S_PILLAR)
	if full:
		prism(body, base, _v3(p, col_top), 0.95, 0.95, 14, col, false)
	else:
		box(body, base + Vector3.UP * (col_top - ground) * 0.5, r3 * 0.9, Vector3.UP * (col_top - ground) * 0.5, d3 * 0.9, col)
	# The hammerhead cap under the girder.
	var w: float = float(smp.half) + DECK_EXTRA - 2.0
	box(body, _v3(p, col_top + cap_h * 0.5), r3 * w, Vector3.UP * cap_h * 0.5, d3 * 1.1, _col(CONC_STRUCT, S_PILLAR))
	_shapes.append([Vector3(1.8, col_top - ground, 1.8), Transform3D(Basis(), base + Vector3.UP * (col_top - ground) * 0.5)])


## A station: the island platform with everything on it.
func _station(st: Dictionary) -> void:
	var s: float = st.s
	var m: int = st.mode
	if m == LightRail.Mode.TUNNEL:
		_entrances(st)
		return
	var smp := line.sample(s)
	var p: Vector2 = smp.pos
	var d: Vector2 = smp.dir
	var r := Vector2(-d.y, d.x)
	var r3 := Vector3(r.x, 0.0, r.y)
	var d3 := Vector3(d.x, 0.0, d.y)
	var half_w: float = float(st.width) * 0.5
	var L := LightRail.PLATFORM_LENGTH
	var rail_y: float = smp.y
	var deck := rail_y + LightRail.PLATFORM_HEIGHT
	var ground := _street(p)
	var foot := ground if m == LightRail.Mode.GRADE else rail_y - 0.6
	var c := _v3(p, 0.0)
	var cs := _col(CONC_STRUCT, S_CONCRETE)
	# The platform slab (follows the line's height along its length) and its edge faces.
	var n_seg := 8
	for k in n_seg:
		var t0 := -L * 0.5 + L * float(k) / n_seg
		var t1 := -L * 0.5 + L * float(k + 1) / n_seg
		var y0 := float(line.sample(s + t0).y) + LightRail.PLATFORM_HEIGHT
		var y1 := float(line.sample(s + t1).y) + LightRail.PLATFORM_HEIGHT
		var a := c + d3 * t0
		var b := c + d3 * t1
		var inner := half_w - 0.6
		quad(body, a - r3 * inner + Vector3.UP * y0, a + r3 * inner + Vector3.UP * y0, b + r3 * inner + Vector3.UP * y1, b - r3 * inner + Vector3.UP * y1,
			Vector3.UP, _col(Color(0.66, 0.65, 0.62), S_CONCRETE), Vector2(t0, -inner), Vector2(t0, inner), Vector2(t1, inner), Vector2(t1, -inner))
		for side: float in [-1.0, 1.0]:
			# Tactile warning strip along each edge, then the edge face down to the track bed.
			var e0 := a + r3 * side * inner
			var e1 := b + r3 * side * inner
			var o0 := a + r3 * side * half_w
			var o1 := b + r3 * side * half_w
			quad(body, e0 + Vector3.UP * (y0 + 0.004), o0 + Vector3.UP * (y0 + 0.004), o1 + Vector3.UP * (y1 + 0.004), e1 + Vector3.UP * (y1 + 0.004),
				Vector3.UP, _col(TACTILE, S_PAINTED))
			var fy0 := foot if m == LightRail.Mode.GRADE else y0 - 1.2
			var fy1 := foot if m == LightRail.Mode.GRADE else y1 - 1.2
			quad(body, o0 + Vector3.UP * y0, o1 + Vector3.UP * y1, o1 + Vector3.UP * fy1, o0 + Vector3.UP * fy0,
				r3 * side, _col(CONC_STRUCT, S_BARRIER), Vector2(t0, 1.0), Vector2(t1, 1.0), Vector2(t1, 0.0), Vector2(t0, 0.0))
	# The platform as collision.
	_shapes.append([Vector3(half_w * 2.0, deck - foot + 0.1, L), Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.y)), _v3(p, (deck + foot) * 0.5))])
	# Ramps down to the crosswalks at both ends (at grade) or a lift and stair tower (aerial).
	if m == LightRail.Mode.GRADE:
		for end: float in [-1.0, 1.0]:
			var a := c + d3 * end * L * 0.5
			var b := c + d3 * end * (L * 0.5 + LightRail.RAMP_RUN)
			var ya := deck
			var yb := _street(Vector2(b.x, b.z)) + 0.02
			var rw := half_w - 0.15
			quad(body, a - r3 * rw + Vector3.UP * ya, a + r3 * rw + Vector3.UP * ya, b + r3 * rw + Vector3.UP * yb, b - r3 * rw + Vector3.UP * yb,
				Vector3.UP, _col(Color(0.62, 0.61, 0.58), S_CONCRETE))
			for side: float in [-1.0, 1.0]:
				quad(body, a + r3 * side * rw + Vector3.UP * ya, b + r3 * side * rw + Vector3.UP * yb, b + r3 * side * rw + Vector3.UP * (yb - 0.05), a + r3 * side * rw + Vector3.UP * (foot - 0.05),
					r3 * side, cs)
				# Handrails.
				prism(body, a + r3 * side * (rw - 0.05) + Vector3.UP * (ya + 0.95), b + r3 * side * (rw - 0.05) + Vector3.UP * (yb + 0.95), 0.025, 0.025, 5, _col(RAIL_TOP, S_STEEL), false)
				for q in 3:
					var t := float(q) / 2.0
					var pp := a.lerp(b, t) + r3 * side * (rw - 0.05)
					var py := lerpf(ya, yb, t)
					prism(body, pp + Vector3.UP * py, pp + Vector3.UP * (py + 0.95), 0.02, 0.02, 4, _col(RAIL_TOP, S_STEEL), false)
			var mid := (a + b) * 0.5
			var fwd := b + Vector3.UP * yb - (a + Vector3.UP * ya)
			_shapes.append([Vector3(rw * 2.0, 0.3, fwd.length()), Transform3D(_basis(fwd, r3), mid + Vector3.UP * ((ya + yb) * 0.5 - 0.15))])
	else:
		_lift_tower(c + d3 * (L * 0.5 - 4.0), r3, d3, half_w, ground, deck)
	# The canopy: columns down the middle, a shallow butterfly roof, a band of the line's colour,
	# lit strips under it.
	var canopy_l := L * 0.78
	var roof_y := deck + 3.5
	var n_col := 6
	for k in n_col:
		var t := -canopy_l * 0.5 + canopy_l * (float(k) + 0.5) / n_col
		var y := float(line.sample(s + t).y) + LightRail.PLATFORM_HEIGHT
		var base := c + d3 * t + Vector3.UP * y
		if full:
			prism(body, base, base + Vector3.UP * (roof_y - y - 0.1), 0.11, 0.09, 8, _col(Color(0.26, 0.27, 0.29), S_PAINTED))
		else:
			box(body, base + Vector3.UP * (roof_y - y) * 0.5, r3 * 0.1, Vector3.UP * (roof_y - y) * 0.5, d3 * 0.1, _col(Color(0.26, 0.27, 0.29), S_PAINTED))
	var cw := half_w + 0.65
	for k in 6:
		var t0 := -canopy_l * 0.5 + canopy_l * float(k) / 6.0
		var t1 := -canopy_l * 0.5 + canopy_l * float(k + 1) / 6.0
		var a := c + d3 * t0
		var b := c + d3 * t1
		var ya0 := float(line.sample(s + t0).y) - rail_y
		var yb0 := float(line.sample(s + t1).y) - rail_y
		for side: float in [-1.0, 1.0]:
			var in_a := a + Vector3.UP * (roof_y + ya0 - 0.12)
			var in_b := b + Vector3.UP * (roof_y + yb0 - 0.12)
			var out_a := a + r3 * side * cw + Vector3.UP * (roof_y + ya0 + 0.25)
			var out_b := b + r3 * side * cw + Vector3.UP * (roof_y + yb0 + 0.25)
			quad(body, in_a + Vector3.UP * 0.14, in_b + Vector3.UP * 0.14, out_b + Vector3.UP * 0.14, out_a + Vector3.UP * 0.14, Vector3.UP, _col(CANOPY, S_PAINTED))
			quad(body, in_a, in_b, out_b, out_a, Vector3.DOWN, _col(CANOPY, S_SOFFIT))
			# The edge band in the line's colour.
			quad(body, out_a, out_b, out_b + Vector3.UP * 0.14, out_a + Vector3.UP * 0.14, r3 * side, _col(LightRail.LINE_COLOR, S_PAINTED))
			# A lit strip under each half of the roof.
			var la := a + r3 * side * cw * 0.45 + Vector3.UP * (roof_y + ya0 + 0.04)
			var lb := b + r3 * side * cw * 0.45 + Vector3.UP * (roof_y + yb0 + 0.04)
			quad(body, la - r3 * 0.07, lb - r3 * 0.07, lb + r3 * 0.07, la + r3 * 0.07, Vector3.DOWN, _col(Color(1.0, 0.95, 0.85), S_LENS), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(0.35, 0.0))
	# Light pools on the platform at night.
	pool(c + Vector3.UP * (deck + 0.03), d3, Vector2(canopy_l + 6.0, half_w * 2.0 + 2.5), Color(1.0, 0.93, 0.8, 0.5))
	if not full:
		return
	# Furniture: benches, ticket machines and a map case at the near end, bins.
	for k in 3:
		var t := -canopy_l * 0.33 + canopy_l * 0.33 * float(k)
		var y := float(line.sample(s + t).y) + LightRail.PLATFORM_HEIGHT
		var bc := c + d3 * (t + 2.5) + Vector3.UP * y
		_bench(bc, d3, r3)
	var end_t := L * 0.5 - 4.5
	var ye := float(line.sample(s + end_t).y) + LightRail.PLATFORM_HEIGHT
	for q in 2:
		var mc := c + d3 * (end_t - float(q) * 1.1) + r3 * (half_w - 1.25) + Vector3.UP * ye
		_ticket_machine(mc, d3, r3)
	_map_case(c + d3 * (end_t - 3.2) - r3 * (half_w - 1.2) + Vector3.UP * ye, d3, r3)
	_pylon(c + d3 * (end_t + 2.6) + Vector3.UP * ye, d3, r3, str(st.name))
	_riders(st)
	# Hanging name signs under the canopy, one facing each track.
	for side: float in [-1.0, 1.0]:
		for t: float in [-canopy_l * 0.25, canopy_l * 0.25]:
			var y := float(line.sample(s + t).y) - rail_y
			var sc := c + d3 * t + r3 * side * (half_w - 0.55) + Vector3.UP * (roof_y + y - 0.75)
			_hanging_sign(sc, d3 * side, r3 * side, str(st.name))


## People waiting on the platform (RailRider), inside the crowd cap; hash-seeded.
func _riders(st: Dictionary) -> void:
	if chunk.capturing or chunk.level != CityChunk.Level.FULL:
		return
	var idx := line.stations.find(st)
	var n := 3 + int(hash01([plan.seed, "riders", idx]) * 4.0)
	for k in n:
		if not chunk._take_crowd_room():
			return
		var ped := RailRider.new()
		ped.line = line
		ped.station = idx
		ped.setup(Rect2(), 3.0, hash([plan.seed, "rider", idx, k]))
		var p := ped._random_ring_point(3.0)
		ped.position = Vector3(p.x, ped._ground_y(p.x, p.y, 0.0), p.y)
		chunk.add_child(ped)


func _bench(c: Vector3, d3: Vector3, r3: Vector3) -> void:
	var seat := _col(Color(0.55, 0.57, 0.58), S_STEEL)
	box(body, c + Vector3.UP * 0.45, d3 * 0.9, Vector3.UP * 0.03, r3 * 0.22, seat)
	box(body, c + Vector3.UP * 0.75 + r3 * 0.0, d3 * 0.9, Vector3.UP * 0.25, r3 * 0.02, seat)
	for e: float in [-0.75, 0.75]:
		box(body, c + d3 * e + Vector3.UP * 0.22, d3 * 0.03, Vector3.UP * 0.22, r3 * 0.2, _col(DARK, S_PAINTED))


func _ticket_machine(c: Vector3, d3: Vector3, r3: Vector3) -> void:
	box(body, c + Vector3.UP * 0.95, d3 * 0.42, Vector3.UP * 0.95, r3 * 0.3, _col(MACHINE, S_PAINTED))
	box(body, c + Vector3.UP * 1.75, d3 * 0.43, Vector3.UP * 0.12, r3 * 0.31, _col(LightRail.LINE_COLOR, S_PAINTED))
	# The screen and the card slot face out across the platform (toward -r3).
	var face := c - r3 * 0.305
	quad(body, face + d3 * 0.22 + Vector3.UP * 1.25, face - d3 * 0.22 + Vector3.UP * 1.25, face - d3 * 0.22 + Vector3.UP * 1.55, face + d3 * 0.22 + Vector3.UP * 1.55,
		-r3, _col(Color(0.35, 0.55, 0.75), S_LENS), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(0.25, 0.0))
	quad(body, face + d3 * 0.1 + Vector3.UP * 1.0, face - d3 * 0.1 + Vector3.UP * 1.0, face - d3 * 0.1 + Vector3.UP * 1.08, face + d3 * 0.1 + Vector3.UP * 1.08,
		-r3, _col(Color(0.2, 0.9, 0.4), S_LENS), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(0.15, 0.0))


func _map_case(c: Vector3, d3: Vector3, r3: Vector3) -> void:
	for e: float in [-0.65, 0.65]:
		prism(body, c + d3 * e, c + d3 * e + Vector3.UP * 2.1, 0.04, 0.04, 6, _col(Color(0.26, 0.27, 0.29), S_PAINTED), false)
	box(body, c + Vector3.UP * 1.35, d3 * 0.62, Vector3.UP * 0.7, r3 * 0.05, _col(DARK, S_PAINTED))
	for side: float in [-1.0, 1.0]:
		var f := c + r3 * side * 0.055
		quad(body, f - d3 * 0.55 + Vector3.UP * 0.75, f + d3 * 0.55 + Vector3.UP * 0.75, f + d3 * 0.55 + Vector3.UP * 1.95, f - d3 * 0.55 + Vector3.UP * 1.95,
			r3 * side, _col(Color(0.92, 0.9, 0.84), S_LENS), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(0.12, 0.0))
		# The line's diagram: a band in its colour with station dots.
		var by := 1.55
		quad(body, f + r3 * side * 0.004 - d3 * 0.45 + Vector3.UP * by, f + r3 * side * 0.004 + d3 * 0.45 + Vector3.UP * by, f + r3 * side * 0.004 + d3 * 0.45 + Vector3.UP * (by + 0.04), f + r3 * side * 0.004 - d3 * 0.45 + Vector3.UP * (by + 0.04),
			r3 * side, _col(LightRail.LINE_COLOR, S_LENS), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(0.1, 0.0))


## The station's name pylon: a slim lit tower with the line's bullet on top.
func _pylon(c: Vector3, d3: Vector3, r3: Vector3, station_name: String) -> void:
	box(body, c + Vector3.UP * 1.6, d3 * 0.18, Vector3.UP * 1.6, r3 * 0.45, _col(DARK, S_PAINTED))
	box(body, c + Vector3.UP * 3.45, d3 * 0.2, Vector3.UP * 0.28, r3 * 0.47, _col(LightRail.LINE_COLOR, S_LENS), 0.22)
	for side: float in [-1.0, 1.0]:
		var face := c + d3 * side * 0.185
		var xf := Transform3D(Basis(_reading(d3 * side), Vector3.UP, d3 * side), face + Vector3.UP * 3.45)
		letters(LightRail.LINE_LETTER, 0.36, Vector2.ZERO, xf, kind_color(Color(1, 1, 1), P_SIGN), Rect2(-0.5, -0.3, 1.0, 0.6), Vector2(d3.x, d3.z) * side)
		var nxf := Transform3D(Basis(_reading(d3 * side), Vector3.UP, d3 * side), face + Vector3.UP * 2.2)
		letters(_wrap(station_name), 0.17, Vector2.ZERO, nxf, kind_color(Color(0.95, 0.95, 0.93), P_SIGN), Rect2(-0.45, -0.6, 0.9, 1.2), Vector2(d3.x, d3.z) * side, 0.82)


func _hanging_sign(c: Vector3, along: Vector3, out: Vector3, station_name: String) -> void:
	var w := 2.6
	box(body, c, along * w * 0.5, Vector3.UP * 0.22, out * 0.04, _col(DARK, S_PAINTED))
	for e: float in [-0.9, 0.9]:
		prism(body, c + along * e + Vector3.UP * 0.22, c + along * e + Vector3.UP * 0.75, 0.012, 0.012, 4, _col(RAIL_STEEL, S_STEEL), false)
	var face := c + out * 0.045
	quad(body, face - along * w * 0.5 + Vector3.UP * 0.18, face + along * w * 0.5 + Vector3.UP * 0.18, face + along * w * 0.5 + Vector3.UP * 0.22, face - along * w * 0.5 + Vector3.UP * 0.22,
		out, _col(LightRail.LINE_COLOR, S_PAINTED))
	var xf := Transform3D(Basis(_reading(out), Vector3.UP, out), face)
	letters(station_name, 0.2, Vector2(0.0, -0.03), xf, kind_color(Color(0.96, 0.96, 0.94), P_SIGN), Rect2(-w * 0.5, -0.22, w, 0.44), Vector2(out.x, out.z), w - 0.2)


## The reading direction on a face looking out along `out`: the right hand of someone facing it.
static func _reading(out: Vector3) -> Vector3:
	return Vector3.UP.cross(out).normalized()


static func _wrap(text: String) -> String:
	return text.replace(" / ", "\n")


## The aerial station's lift and stair tower, from the street up to the platform's end.
func _lift_tower(c: Vector3, r3: Vector3, d3: Vector3, half_w: float, ground: float, deck: float) -> void:
	var h := deck - ground
	var w := minf(half_w - 0.4, 1.6)
	box(body, Vector3(c.x, ground + h * 0.5, c.z), r3 * w, Vector3.UP * h * 0.5, d3 * 2.0, _col(Color(0.80, 0.80, 0.78), S_PILLAR), 0.0)
	# Glazed lift shaft face and a lit band.
	for side: float in [-1.0, 1.0]:
		var f := c + r3 * side * (w + 0.01)
		quad(body, f - d3 * 1.4 + Vector3.UP * (ground + 0.3), f + d3 * 1.4 + Vector3.UP * (ground + 0.3), f + d3 * 1.4 + Vector3.UP * (deck - 0.4), f - d3 * 1.4 + Vector3.UP * (deck - 0.4),
			r3 * side, _col(Color(0.20, 0.27, 0.30), S_LENS), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(0.04, 0.0))
	box(body, Vector3(c.x, deck + 0.4, c.z), r3 * (w + 0.05), Vector3.UP * 0.4, d3 * 2.05, _col(LightRail.LINE_COLOR, S_PAINTED))
	_shapes.append([Vector3(w * 2.0, h, 4.0), Transform3D(Basis(Vector3.UP, atan2(-d3.x, -d3.z)), Vector3(c.x, ground + h * 0.5, c.z))])


## The underground terminus: two stair kiosks in the avenue's median either side of the street it
## is named for, each a glass canopy over a stair down, a parapet round it and a lit pylon.
func _entrances(st: Dictionary) -> void:
	var s: float = st.s
	for end: float in [-1.0, 1.0]:
		var smp := line.sample(s + end * 26.0)
		var p: Vector2 = smp.pos
		if _in_junction(p, 4.0):
			continue
		var d: Vector2 = smp.dir
		var d3 := Vector3(d.x, 0.0, d.y) * end
		var r3 := Vector3(-d.y, 0.0, d.x)
		var g := _street(p)
		var c := _v3(p, g)
		var hw := 1.6
		var hl := 5.0
		# Kerb island and parapet round three sides, the stair mouth open toward the crossing.
		box(body, c + Vector3.UP * 0.08, r3 * (hw + 0.6), Vector3.UP * 0.08, d3 * (hl + 1.0), _col(Color(0.66, 0.65, 0.62), S_CONCRETE))
		for side: float in [-1.0, 1.0]:
			box(body, c + r3 * side * hw + Vector3.UP * 0.65, r3 * 0.12, Vector3.UP * 0.5, d3 * hl, _col(CONC_STRUCT, S_BARRIER))
		box(body, c + d3 * hl + Vector3.UP * 0.65, r3 * hw, Vector3.UP * 0.5, d3 * 0.12, _col(CONC_STRUCT, S_BARRIER))
		# The stair: dark treads stepping down into the dark (drawn in the island, a few steps).
		for q in 8:
			var t := -hl + 1.0 + float(q) * 1.1
			var y := 0.17 - float(q) * 0.012
			var shade := lerpf(0.35, 0.02, float(q) / 7.0)
			quad(body, c + d3 * t - r3 * (hw - 0.12) + Vector3.UP * y, c + d3 * t + r3 * (hw - 0.12) + Vector3.UP * y,
				c + d3 * (t + 1.1) + r3 * (hw - 0.12) + Vector3.UP * y, c + d3 * (t + 1.1) - r3 * (hw - 0.12) + Vector3.UP * y,
				Vector3.UP, _col(Color(shade, shade, shade), S_RUBBER))
		# The canopy: four posts, a glass roof (dark tinted), the line's band.
		for a: float in [-1.0, 1.0]:
			for b: float in [-hl + 0.3, hl - 0.3]:
				prism(body, c + r3 * a * (hw + 0.05) + d3 * b, c + r3 * a * (hw + 0.05) + d3 * b + Vector3.UP * 2.9, 0.06, 0.06, 6, _col(Color(0.26, 0.27, 0.29), S_PAINTED), false)
		box(body, c + Vector3.UP * 3.0, r3 * (hw + 0.35), Vector3.UP * 0.08, d3 * (hl + 0.2), _col(Color(0.32, 0.40, 0.44), S_STEEL))
		box(body, c + Vector3.UP * 2.86, r3 * (hw + 0.36), Vector3.UP * 0.07, d3 * (hl + 0.21), _col(LightRail.LINE_COLOR, S_PAINTED))
		quad(body, c + Vector3.UP * 2.9 - r3 * 0.1 - d3 * (hl - 0.5), c + Vector3.UP * 2.9 + r3 * 0.1 - d3 * (hl - 0.5),
			c + Vector3.UP * 2.9 + r3 * 0.1 + d3 * (hl - 0.5), c + Vector3.UP * 2.9 - r3 * 0.1 + d3 * (hl - 0.5), Vector3.DOWN,
			_col(Color(1.0, 0.95, 0.85), S_LENS), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(0.3, 0.0))
		pool(c + Vector3.UP * 0.2, d3, Vector2(hl * 2.0 + 3.0, hw * 2.0 + 3.0), Color(1.0, 0.93, 0.8, 0.45))
		if full:
			_pylon(c - d3 * (hl + 0.6) + r3 * 0.0, r3, d3, str(st.name))
		_shapes.append([Vector3(hw * 2.0 + 0.3, 1.2, hl * 2.0), Transform3D(Basis(Vector3.UP, atan2(-d3.x, -d3.z)), c + Vector3.UP * 0.6)])


## A level crossing: a gate assembly on the kerb at each approach of the road crossed.
func _crossing(c: Dictionary) -> void:
	var pos: Vector2 = c.pos
	var axis: int = c.axis
	var w: float = c.width
	var s: float = c.s
	var reach: float = float(line.sample(s).half) + TRACKWAY_EXTRA + 3.2
	# The road crossed runs along `run_dir`; the line along `line_dir`.
	var run_dir := Vector2(0.0, 1.0) if axis == CityPlan.AXIS_X else Vector2(1.0, 0.0)
	for approach: float in [-1.0, 1.0]:
		# Traffic coming from the `approach` side, heading -approach * run_dir.
		var heading := -run_dir * approach
		var right := Vector2(-heading.y, heading.x)
		var mast := pos + run_dir * approach * reach + right * (w * 0.5 + 0.7)
		var g := _street(mast) + 0.15
		var base := _v3(mast, g)
		var col := _col(Color(0.80, 0.80, 0.79), S_STEEL)
		if full:
			prism(body, base, base + Vector3.UP * 4.3, 0.09, 0.08, 8, col)
			box(body, base + Vector3.UP * 0.12, Vector3(0.35, 0, 0), Vector3.UP * 0.12, Vector3(0, 0, 0.35), _col(CONC_STRUCT, S_CONCRETE))
			# The gate mechanism box beside the mast, the bell on top.
			var h3 := Vector3(heading.x, 0.0, heading.y)
			var r3 := Vector3(right.x, 0.0, right.y)
			box(body, base + r3 * 0.35 + Vector3.UP * 0.75, r3 * 0.2, Vector3.UP * 0.55, h3 * 0.22, _col(Color(0.62, 0.63, 0.62), S_STEEL))
			prism(body, base + Vector3.UP * 4.3, base + Vector3.UP * 4.5, 0.13, 0.04, 8, _col(Color(0.12, 0.12, 0.12), S_PAINTED))
			# Crossbuck: two white boards in an X facing the traffic.
			var face := base - h3 * 0.08 + Vector3.UP * 3.75
			for sgn: float in [-1.0, 1.0]:
				var axis_v := (r3 * cos(PI * 0.25) + Vector3.UP * sin(PI * 0.25) * sgn).normalized()
				var up_v := (Vector3.UP * cos(PI * 0.25) - r3 * sin(PI * 0.25) * sgn).normalized()
				box(body, face, axis_v * 0.61, up_v * 0.11, h3 * 0.01, _col(Color(0.94, 0.94, 0.92), S_PAINTED))
			# Flasher heads: a crossarm with two hooded lamps facing the traffic (the lamps are the
			# gate node's).
			box(body, base - h3 * 0.05 + Vector3.UP * 2.85, r3 * 0.62, Vector3.UP * 0.04, h3 * 0.04, _col(DARK, S_PAINTED))
			for e: float in [-0.48, 0.48]:
				var lc := base - h3 * 0.12 + r3 * e + Vector3.UP * 2.85
				box(body, lc + h3 * 0.06, r3 * 0.24, Vector3.UP * 0.24, h3 * 0.03, _col(DARK, S_PAINTED))
				box(body, lc - Vector3.UP * 0.0 - h3 * 0.06 + Vector3.UP * 0.13, r3 * 0.16, Vector3.UP * 0.015, h3 * 0.13, _col(DARK, S_PAINTED))
		else:
			box(body, base + Vector3.UP * 2.0, Vector3(0.08, 0, 0), Vector3.UP * 2.0, Vector3(0, 0, 0.08), col)
		_gates.append({"base": base, "heading": heading, "right": right, "length": w * 0.5 + 0.4, "node": c.node, "axis": axis})


func _substation(smp: Dictionary) -> void:
	var p: Vector2 = smp.pos
	var d: Vector2 = smp.dir
	var d3 := Vector3(d.x, 0.0, d.y)
	var r3 := Vector3(-d.y, 0.0, d.x)
	var g := _street(p)
	var c := _v3(p, g)
	box(body, c + Vector3.UP * 1.65, d3 * 5.5, Vector3.UP * 1.65, r3 * 1.5, _col(Color(0.78, 0.74, 0.66), S_PAINTED))
	box(body, c + Vector3.UP * 3.35, d3 * 5.6, Vector3.UP * 0.06, r3 * 1.6, _col(Color(0.45, 0.45, 0.44), S_STEEL))
	# Louvre bands and doors on each long side.
	for side: float in [-1.0, 1.0]:
		var f := c + r3 * side * 1.505
		for k in 4:
			var t := -4.2 + float(k) * 2.8
			quad(body, f + d3 * (t - 0.6) + Vector3.UP * 1.9, f + d3 * (t + 0.6) + Vector3.UP * 1.9, f + d3 * (t + 0.6) + Vector3.UP * 2.7, f + d3 * (t - 0.6) + Vector3.UP * 2.7,
				r3 * side, _col(Color(0.30, 0.30, 0.29), S_SOFFIT))
		quad(body, f + d3 * 3.5 + Vector3.UP * 0.05, f + d3 * 4.6 + Vector3.UP * 0.05, f + d3 * 4.6 + Vector3.UP * 2.2, f + d3 * 3.5 + Vector3.UP * 2.2,
			r3 * side, _col(Color(0.40, 0.42, 0.40), S_STEEL))
	_shapes.append([Vector3(3.0, 3.4, 11.0), Transform3D(Basis(Vector3.UP, atan2(-d3.x, -d3.z)), c + Vector3.UP * 1.7)])


# --- Commit ----------------------------------------------------------------------------------

func _commit() -> void:
	var mi := _add("RailStructure", body.commit(), structure_material())
	mi.add_to_group("light_rail_static")
	if _paint_any:
		var pm := _add("RailSigns", paint.commit(), paint_material())
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _glow_any:
		var gi := _add("RailGlow", glow.commit(), pool_material())
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _shapes.is_empty():
		var sb := StaticBody3D.new()
		sb.name = "RailBody"
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
		chunk.add_child(RailGate.make(g, full))
