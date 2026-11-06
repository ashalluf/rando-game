class_name RcSwitchback
## The switchback at night (fleet wave 8, `rc5-switchback-night`; docs/HANDOFF.md "Stadium Way's
## switchbacks at night"; refcam `switchback_night` in tools/refcams/cameras_w8.json). What a
## mountain road shows at 22:00 that the canyon road (CanyonRoad) did not:
##   * curve chevrons (the black-on-yellow W1-8 board) on posts round the outside of every sharp
##     bend of a drawn hill road - the switchbacks' hairpins first - retroreflective, so they glow
##     in the headlights (taken to be at the camera, as every retroreflector in the game);
##   * the guardrail's reflectors on the beam's face toward the road, every fourth post (they were
##     8 cm tabs on the beam's top every eighth, which nobody on the road could see);
##   * in canyon_road.gdshader (`rc5`): yellow two-way raised markers between the double yellow, and
##     the crack sealant read as glossy tar lines in rarer runs (the fine net drew a puzzle of matte
##     black seams over the whole lane).
## Pure functions of the plan's roads and ground: no roll, nothing else moves. Everything goes into
## the chunk's own guardrail mesh (one draw, FULL only). `RC5_SWITCHBACK=0` is the A/B.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var _on: int = -1


static func on() -> bool:
	if _on < 0:
		_on = 0 if OS.get_environment("RC5_SWITCHBACK") == "0" else 1
	return _on == 1


## A bend is signed where its centre line's radius is under this, metres.
const SHARP_RADIUS := 42.0
## The radius is measured over this arc either side of a station; stations every STATION metres.
const WINDOW := 18.0
const STATION := 1.5
## Chevrons every this along the bend's centre line (MUTCD: about 2 x the radius, tighter in a
## hairpin), metres.
const CHEVRON_SPACING := 11.0
## The post stands this far past the asphalt's edge (behind the guardrail and its posts).
const CHEVRON_OUT := 2.1
## The board: 18 x 24 in, its bottom this far over the ground.
const BOARD_W := 0.46
const BOARD_H := 0.61
const BOARD_LIFT := 1.25
## No chevron within this of another road's edge (a junction) or an estate's drive.
const CLEAR := 4.0
## The strip's piece length in a sharp bend (the turn between a segment's two mitred normals over
## BEND_TURN radians), metres.
const BEND_PIECE := 2.0
const BEND_TURN := 0.12
## The guardrail's reflectors: every this many posts, on the beam's road face.
const REFLECTOR_EVERY := 4

## COLOR.a of the new parts in the guardrail mesh (canyon_guardrail.gdshader's thresholds).
const K_SIGN_BLACK := 0.2
const K_SIGN_YELLOW := 0.8


## Where the chevrons stand in `area` (the chunk's owned rect): [{pos, y (ground), t (the road's
## direction there), o (outward, away from the bend's centre)}]. Pure.
static func chevrons(plan: CityPlan, area: Rect2) -> Array:
	var out: Array = []
	if plan == null or plan.macro == null or plan.macro.hill_roads == null:
		return out
	var hr: HillRoads = plan.macro.hill_roads
	var drives: Array[Vector2] = []
	for m: Dictionary in hr.mansions_in(area.grow(60.0)):
		drives.append(m.get("drive_from", m.pos))
	var reach := area.grow(CHEVRON_OUT + 12.0)
	for road: Dictionary in hr.roads:
		if road.get("drive", false) or not road.get("draw", true) or road.get("fire", false) or road.get("pad", false):
			continue
		if float(road.width) < CanyonRoad.MIN_WIDTH:
			continue
		var pts: PackedVector2Array = road.points
		if pts.size() < 3:
			continue
		var half := float(road.width) * 0.5
		var box := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			box = box.expand(q)
		if not box.grow(half + CHEVRON_OUT + WINDOW + 4.0).intersects(reach):
			continue
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
		var total := cum[cum.size() - 1]
		# Stations every STATION along the centre line; the bend's radius at one is the turn of
		# the direction WINDOW either side of it over the arc between (the roads are polylines of
		# ~11 m pieces whose turns sit at the vertices: a vertex alone says nothing of the bend).
		# Only the pieces near the chunk (the walk below is per metre and a chunk sees few roads).
		var near := reach.grow(half + WINDOW + 4.0)
		var next := 0.0
		var st := WINDOW
		while st < total - WINDOW:
			var si := _index_at(cum, st)
			if not near.has_point(pts[si]) and not near.has_point(pts[si + 1]):
				st = maxf(st + STATION, cum[si + 1] + 0.01)
				continue
			var d0 := _dir_at(pts, cum, st - WINDOW)
			var d1 := _dir_at(pts, cum, st + WINDOW)
			var ang := absf(d0.angle_to(d1))
			if ang * SHARP_RADIUS > WINDOW * 2.0 and st >= next:
				next = st + CHEVRON_SPACING
				var t := (d0 + d1).normalized()
				var o := -(d1 - d0).normalized()
				var c := _point_at(pts, cum, st)
				var p := c + o * (half + CHEVRON_OUT)
				if reach.has_point(p) and area.has_point(p) and _clear(hr, p, drives, pts, _index_at(cum, st)):
					out.append({"pos": p, "y": plan.height_at(p), "t": t, "o": o})
			st += STATION
	return out


## Clear of other roads (by their edge, not just their centre line) and of drives.
static func _clear(hr: HillRoads, p: Vector2, drives: Array[Vector2], pts: PackedVector2Array, i: int) -> bool:
	for d in drives:
		if p.distance_to(d) < CanyonRoad.DRIVE_CLEAR:
			return false
	for seg: Dictionary in hr.segments_in(Rect2(p - Vector2(20, 20), Vector2(40, 40))):
		if seg.get("drive", false) and not seg.get("draw", true):
			continue
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		# Our own road's pieces round this point are the bend itself.
		var own := false
		for k in range(maxi(0, i - 3), mini(pts.size(), i + 4)):
			if a.distance_to(pts[k]) < 0.01 or b.distance_to(pts[k]) < 0.01:
				own = true
				break
		if own:
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		if p.distance_to(q) < float(seg.width) * 0.5 + CLEAR:
			return false
	return true


## Writes the chunk's chevrons into the guardrail SurfaceTool `st`. Returns how many.
static func build_chevrons(st: SurfaceTool, plan: CityPlan, area: Rect2) -> int:
	if not on():
		return 0
	var n := 0
	for c: Dictionary in chevrons(plan, area):
		var p: Vector2 = c.pos
		var t: Vector2 = c.t
		var o: Vector2 = c.o
		var g: float = float(c.y) + CanyonRoad.LIFT - CanyonRoad.SHOULDER_DROP
		var t3 := Vector3(t.x, 0.0, t.y)
		# The board's face: normal along the road (it faces both ways), its horizontal axis `h`
		# pointing to the bend's centre (where the chevron's tip points, for both directions).
		var h3 := Vector3(-o.x, 0.0, -o.y)
		var base := Vector3(p.x, g, p.y)
		# The post: a galvanised 5 cm square, from under the ground to the board's top.
		CanyonRoad._box(st, base + Vector3(0.0, (BOARD_LIFT + BOARD_H) * 0.5 - 0.1, 0.0) - t3 * 0.03, Vector2(t.x, t.y), Vector2(o.x, o.y), Vector3(0.05, BOARD_LIFT + BOARD_H + 0.2, 0.05), CanyonRoad.K_STEEL)
		var centre := base + Vector3(0.0, BOARD_LIFT + BOARD_H * 0.5, 0.0)
		# The aluminium board, 2 cm thick, yellow both faces.
		CanyonRoad._box(st, centre, Vector2(o.x, o.y), Vector2(t.x, t.y), Vector3(BOARD_W, BOARD_H, 0.02), K_SIGN_YELLOW)
		# The black chevron on each face (2 mm proud): two arms meeting at the tip toward h.
		for face: float in [-1.0, 1.0]:
			var f := t3 * (0.012 * face)
			for arm: float in [-1.0, 1.0]:
				var a0 := centre + f + h3 * -0.13 + Vector3(0.0, 0.215 * arm, 0.0)
				var a1 := centre + f + h3 * -0.035 + Vector3(0.0, 0.215 * arm, 0.0)
				var b1 := centre + f + h3 * 0.135 + Vector3(0.0, 0.0, 0.0)
				var b0 := centre + f + h3 * 0.04 + Vector3(0.0, 0.0, 0.0)
				CanyonRoad._quad(st, a0, a1, b1, b0, K_SIGN_BLACK, 0.0, 1.0, 0.0, 1.0)
		n += 1
	return n


## The length CanyonRoad cuts segment `seg` into: `piece` (its own), or BEND_PIECE in a bend.
static func piece_length(seg: Dictionary, piece: float) -> float:
	if not on():
		return piece
	var a: Vector2 = seg.a
	var b: Vector2 = seg.b
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var na: Vector2 = seg.get("na", n)
	var nb: Vector2 = seg.get("nb", n)
	if absf(na.angle_to(nb)) > BEND_TURN:
		return BEND_PIECE
	return piece


## A reflector on the beam's face toward the road at post `s` (CanyonRoad._rail_piece's posts):
## true when this post carries one.
static func reflector_at(s: float) -> bool:
	return on() and int(roundf(s / CanyonRoad.POST_SPACING)) % REFLECTOR_EVERY == 0


## The reflector's box on the beam's road face at `p` (the beam's face line), ground `g`.
static func reflector_box(st: SurfaceTool, p: Vector2, g: float, dir: Vector2, out: Vector2) -> void:
	var o3 := Vector3(out.x, 0.0, out.y)
	# The beam's valley sits 0.155 m up its section; the tab is bolted on the splice bolt in it,
	# standing a centimetre proud of the ridges' face toward the road.
	CanyonRoad._box(st, Vector3(p.x, g + CanyonRoad.RAIL_BOTTOM + 0.155, p.y) + o3 * 0.042, dir, out, Vector3(0.09, 0.09, 0.012), CanyonRoad.K_REFLECTOR)


static func _index_at(cum: PackedFloat32Array, s: float) -> int:
	var i := cum.bsearch(s)
	return clampi(i - 1, 0, cum.size() - 2)


static func _dir_at(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	var i := _index_at(cum, clampf(s, 0.0, cum[cum.size() - 1]))
	return (pts[i + 1] - pts[i]).normalized()


static func _point_at(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	var i := _index_at(cum, s)
	var l := maxf(cum[i + 1] - cum[i], 1e-4)
	return pts[i].lerp(pts[i + 1], clampf((s - cum[i]) / l, 0.0, 1.0))
