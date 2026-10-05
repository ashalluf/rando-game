class_name ParkKit
extends RefCounted
## The rec parks' and schools' upright geometry (Parks lays it out), at real size, written straight
## into a chunk's ONE walls mesh through IndustrialKit's box and cylinder writers (so every face
## carries UV in metres in its own frame and its kind in the vertex colour) and drawn by
## shaders/park_walls.gdshader. Pure geometry: no rolls, no nodes.
##
## Vertex layout (IndustrialKit's): COLOR.rgb the paint (display numbers), COLOR.a the kind (K_*)
## in 32nds, UV face metres (x along the face from its left corner seen from outside, y up from the
## box's foot), UV2 = (the box's height, a per-box parameter).

# --- Kinds (COLOR.a in 32nds; mirrored in park_walls.gdshader) -----------------------------------
const K_STEEL := 0
const K_GALV := 1
const K_CHAIN := 2
const K_WINDSCREEN := 3
const K_NET := 4
const K_HOOPNET := 5
const K_BACKBOARD := 6
const K_PLASTIC := 7
const K_RUBBER := 8
const K_ALUM := 9
const K_CMU := 10
const K_STUCCO := 11
const K_ROOF := 12
const K_GLASS := 13
const K_LAMP := 14
const K_WOOD := 15
const K_CONCRETE := 16
const K_CHALK := 17
const K_CANOPY := 18
const K_DOOR := 19
const KIND_COUNT := 20

## K_STUCCO's parameter (UV2.y): what its faces carry.
const W_BLANK := 0.0
const W_CLASSROOM := 1.0
const W_CLASS_DOORS := 2.0
const W_CLERESTORY := 3.0
const W_BUNGALOW := 4.0
const W_ENTRY := 5.0

const WHITE := Color(0.93, 0.93, 0.91)
const GALV := Color(0.62, 0.64, 0.64)
const BLACK := Color(0.08, 0.08, 0.09)
const GREEN_STEEL := Color(0.13, 0.26, 0.18)
const ORANGE := Color(0.88, 0.36, 0.08)
const WOOD := Color(0.55, 0.40, 0.26)
const CONCRETE := Color(0.72, 0.71, 0.68)
const CMU := Color(0.70, 0.66, 0.60)
const ROOF := Color(0.55, 0.55, 0.53)
const WINDSCREEN := Color(0.07, 0.20, 0.14)
## Playground plastic: [posts, decks / roofs, slides, panels], four sets (display numbers).
const PLAY_SETS := [
	[Color(0.12, 0.30, 0.55), Color(0.90, 0.62, 0.10), Color(0.88, 0.20, 0.16), Color(0.20, 0.55, 0.30)],
	[Color(0.18, 0.42, 0.25), Color(0.85, 0.80, 0.70), Color(0.15, 0.45, 0.70), Color(0.62, 0.42, 0.22)],
	[Color(0.45, 0.16, 0.45), Color(0.95, 0.75, 0.12), Color(0.12, 0.52, 0.60), Color(0.90, 0.40, 0.12)],
	[Color(0.55, 0.12, 0.10), Color(0.90, 0.85, 0.75), Color(0.95, 0.70, 0.08), Color(0.15, 0.30, 0.55)],
]

## Triangles written (the smoke test and the bench read it).
static var tris: int = 0


static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, kind: int, paint: Color, param: float = 0.0, skip: int = 32) -> void:
	IndustrialKit.box(st, xf, size, kind, paint, param, skip)
	tris += 12


## A box of section `w` x `h` from `a` to `b` (a rail, a strut, a chain).
static func beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float, h: float, kind: int, paint: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.001:
		return
	var z := d / len
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	box(st, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, h, len), kind, paint, 0.0, 0)


static func post(st: SurfaceTool, at: Vector3, r: float, h: float, kind: int, paint: Color, segs: int = 8) -> void:
	IndustrialKit.cyl(st, Transform3D(Basis(), at), r, h, kind, paint, segs, true)
	tris += segs * 3


## A frame in the world: origin `at`, x along `u` (a unit XZ vector), z along v = (-u.y, u.x).
static func frame(at: Vector3, u: Vector2) -> Transform3D:
	var x := Vector3(u.x, 0.0, u.y)
	var z := Vector3(-u.y, 0.0, u.x)
	return Transform3D(Basis(x, Vector3.UP, z), at)


# --- Fences -------------------------------------------------------------------------------------

## A chain-link run from `a` to `b` (feet on the ground): galvanised line posts every 3 m, a top
## rail, the fabric, and a dark green windscreen on its lower part when `screen` (a tennis
## enclosure), on one face (+normal side seen from `inside`).
static func fence(st: SurfaceTool, a: Vector3, b: Vector3, h: float, screen: bool = false, rail: bool = true) -> void:
	var d := b - a
	var len := Vector2(d.x, d.z).length()
	if len < 0.3:
		return
	var n := maxi(1, ceili(len / 3.0))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		post(st, p, 0.03 if i > 0 and i < n else 0.045, h + 0.05, K_GALV, GALV, 6)
	if rail:
		beam(st, a + Vector3(0.0, h, 0.0), b + Vector3(0.0, h, 0.0), 0.042, 0.042, K_GALV, GALV)
	var mid := (a + b) * 0.5
	var dir := Vector3(d.x, 0.0, d.z) / len
	var side := Vector3(-dir.z, 0.0, dir.x)
	var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).orthonormalized()
	var yfoot := minf(a.y, b.y)
	box(st, Transform3D(basis, Vector3(mid.x, yfoot + 0.05 + (h - 0.05) * 0.5 + (maxf(a.y, b.y) - yfoot) * 0.5, mid.z)), Vector3(len, h - 0.05, 0.012), K_CHAIN, GALV, 0.0, 48)
	if screen:
		var sh := minf(h - 0.25, 2.6)
		box(st, Transform3D(basis, Vector3(mid.x, yfoot + 0.1 + sh * 0.5, mid.z) + side * 0.025), Vector3(len, sh, 0.008), K_WINDSCREEN, WINDSCREEN, 0.0, 48)


## A fence round a rect (corners `r` at ground `y`), leaving `gaps` (centres on the edges) 1.5 m open.
static func fence_rect(st: SurfaceTool, ch: CityChunk, r: Rect2, y: float, h: float, screen: bool, gaps: Array = []) -> void:
	var cs := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for e in 4:
		var p0: Vector2 = cs[e]
		var p1: Vector2 = cs[(e + 1) % 4]
		var runs: Array = [[p0, p1]]
		for g: Vector2 in gaps:
			var seg := Geometry2D.get_closest_point_to_segment(g, p0, p1)
			if seg.distance_to(g) > 0.5:
				continue
			var next: Array = []
			for run: Array in runs:
				var s0: Vector2 = run[0]
				var s1: Vector2 = run[1]
				var t := (g - s0).dot((s1 - s0).normalized())
				var l := s0.distance_to(s1)
				if t < 0.0 or t > l:
					next.append(run)
					continue
				var dir := (s1 - s0) / l
				if t - 0.8 > 0.3:
					next.append([s0, s0 + dir * (t - 0.8)])
				if l - t - 0.8 > 0.3:
					next.append([s0 + dir * (t + 0.8), s1])
			runs = next
		for run: Array in runs:
			var q0: Vector2 = run[0]
			var q1: Vector2 = run[1]
			fence(st, Vector3(q0.x, y + ch._gy(q0.x, q0.y), q0.y), Vector3(q1.x, y + ch._gy(q1.x, q1.y), q1.y), h, screen)


# --- Diamond ------------------------------------------------------------------------------------

## The backstop: a tall curved chain-link screen behind home plate (`xf` at home, x down the
## first-base line, z down the third), with its hood.
static func backstop(st: SurfaceTool, xf: Transform3D) -> void:
	var r := 7.0
	var h := 6.0
	var segs := 7
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var ang := deg_to_rad(-30.0 + 210.0 * float(i) / float(segs)) + PI * 0.5
		# Round the back of home: the arc from down the first-base line's foul side to the third's.
		var dir := Vector3(cos(ang + PI * 0.25), 0.0, sin(ang + PI * 0.25))
		pts.append(xf * (-(Vector3(dir.x, 0.0, dir.z)) * r))
	for i in segs:
		fence(st, pts[i], pts[i + 1], h, false)
		post(st, pts[i], 0.08, h + 0.3, K_GALV, GALV, 8)
	post(st, pts[segs], 0.08, h + 0.3, K_GALV, GALV, 8)
	# Padding along the foot (green) and the hood over it.
	for i in segs:
		var a := pts[i]
		var b := pts[i + 1]
		beam(st, a + Vector3(0.0, 0.6, 0.0), b + Vector3(0.0, 0.6, 0.0), 0.08, 1.2, K_RUBBER, Color(0.10, 0.22, 0.14))


## A dugout: concrete-block shelter, roof, a bench, chain-link across its open front. `xf` at the
## middle of its front, x along it, its back toward +z.
static func dugout(st: SurfaceTool, xf: Transform3D, len: float = 7.0) -> void:
	var d := 2.2
	var h := 2.3
	box(st, xf * Transform3D(Basis(), Vector3(0.0, h * 0.5, d - 0.1)), Vector3(len, h, 0.2), K_CMU, CMU)
	for s: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(s * (len * 0.5 - 0.1), h * 0.5, d * 0.5)), Vector3(0.2, h, d), K_CMU, CMU)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, h + 0.08, d * 0.5)), Vector3(len + 0.3, 0.16, d + 0.5), K_CANOPY, Color(0.14, 0.28, 0.20), 1.0)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.45, d - 0.55)), Vector3(len - 0.6, 0.06, 0.4), K_WOOD, WOOD)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.22, d - 0.55)), Vector3(len - 0.6, 0.44, 0.08), K_CMU, CMU)
	fence(st, xf * Vector3(-len * 0.5 + 0.2, 0.0, 0.0), xf * Vector3(len * 0.5 - 0.2, 0.0, 0.0), 1.2, false)


## Aluminium bleachers: `rows` rows of seat and foot planks rising behind `xf` (its front, x along
## the run, z back), on galvanised frames every 3.6 m, rails at the ends and back.
static func bleachers(st: SurfaceTool, xf: Transform3D, len: float, rows: int, seat: Color = Color(0.78, 0.79, 0.80)) -> void:
	var step := Vector2(0.72, 0.36)
	for i in rows:
		var z := 0.3 + step.x * float(i)
		var y := 0.42 + step.y * float(i)
		box(st, xf * Transform3D(Basis(), Vector3(0.0, y, z + 0.18)), Vector3(len, 0.05, 0.28), K_ALUM, seat)
		box(st, xf * Transform3D(Basis(), Vector3(0.0, y - 0.38, z - 0.12)), Vector3(len, 0.04, 0.26), K_ALUM, Color(0.70, 0.71, 0.72))
	var depth := 0.3 + step.x * float(rows)
	var top := 0.42 + step.y * float(rows - 1)
	var nf := maxi(2, ceili(len / 3.6) + 1)
	for k in nf:
		var x := -len * 0.5 + 0.3 + (len - 0.6) * float(k) / float(nf - 1)
		beam(st, xf * Vector3(x, 0.0, 0.1), xf * Vector3(x, top, depth), 0.08, 0.08, K_GALV, GALV)
		beam(st, xf * Vector3(x, 0.0, depth), xf * Vector3(x, top, depth), 0.07, 0.07, K_GALV, GALV)
	beam(st, xf * Vector3(-len * 0.5, top + 1.0, depth), xf * Vector3(len * 0.5, top + 1.0, depth), 0.05, 0.05, K_GALV, GALV)
	for s: float in [-1.0, 1.0]:
		beam(st, xf * Vector3(s * len * 0.5, 1.0, 0.1), xf * Vector3(s * len * 0.5, top + 1.0, depth), 0.05, 0.05, K_GALV, GALV)


## A press box on posts behind the top row of a grandstand.
static func press_box(st: SurfaceTool, xf: Transform3D, len: float, base_y: float, colour: Color) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, base_y + 1.4, 1.3)), Vector3(len, 2.8, 2.6), K_STUCCO, colour.lightened(0.55), W_BLANK)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, base_y + 1.7, -0.01)), Vector3(len - 0.4, 1.1, 0.06), K_GLASS, Color(0.3, 0.36, 0.4))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, base_y + 2.9, 1.3)), Vector3(len + 0.3, 0.2, 2.9), K_ROOF, ROOF)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, base_y + 2.65, -0.02)), Vector3(len, 0.3, 0.05), K_STEEL, colour)


## A ball diamond's bases, pitching rubber and home plate (white), `xf` at home.
static func bases(st: SurfaceTool, xf: Transform3D, base: float, pitch: float) -> void:
	for p: Vector3 in [Vector3(base, 0.0, 0.0), Vector3(base, 0.0, base), Vector3(0.0, 0.0, base)]:
		box(st, xf * Transform3D(Basis(Vector3.UP, PI * 0.25), p + Vector3(0.0, 0.05, 0.0)), Vector3(0.38, 0.1, 0.38), K_CHALK, WHITE)
	var m := pitch / sqrt(2.0)
	box(st, xf * Transform3D(Basis(Vector3.UP, -PI * 0.25), Vector3(m, 0.02, m)), Vector3(0.61, 0.04, 0.15), K_CHALK, WHITE)
	box(st, xf * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, 0.015, 0.0)), Vector3(0.36, 0.03, 0.36), K_CHALK, WHITE)


# --- Courts -------------------------------------------------------------------------------------

## A basketball goal at one end of a court: `xf` at the middle of the baseline, x INTO the court.
## A steel gooseneck pole behind the baseline, a fan steel backboard (white, with its painted
## square), an orange rim at 3.05 m and a net hanging from it (chain on park courts by `chain`).
static func hoop(st: SurfaceTool, xf: Transform3D, chain: bool) -> void:
	var pole := Color(0.10, 0.12, 0.14)
	post(st, xf * Vector3(-1.25, 0.0, 0.0), 0.085, 3.1, K_STEEL, pole, 10)
	beam(st, xf * Vector3(-1.25, 3.05, 0.0), xf * Vector3(0.95, 3.55, 0.0), 0.12, 0.12, K_STEEL, pole)
	beam(st, xf * Vector3(-1.25, 2.6, 0.0), xf * Vector3(0.95, 3.2, 0.0), 0.07, 0.07, K_STEEL, pole)
	# Backboard: 1.8 x 1.05 m, its foot 2.9 m up, its face 1.2 m in from the baseline.
	box(st, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(1.2, 3.42, 0.0)), Vector3(1.8, 1.05, 0.04), K_BACKBOARD, WHITE)
	post(st, xf * Vector3(-1.25, 0.0, 0.0), 0.16, 1.8, K_RUBBER, Color(0.10, 0.16, 0.32), 10)
	# Rim: 0.45 m across, its centre 0.15 + 0.23 m off the board.
	var c := Vector3(1.2 + 0.15 + 0.23, 3.05, 0.0)
	var segs := 10
	var ring: Array[Vector3] = []
	for i in segs:
		var a := TAU * float(i) / float(segs)
		ring.append(c + Vector3(cos(a), 0.0, sin(a)) * 0.229)
	for i in segs:
		beam(st, xf * ring[i], xf * ring[(i + 1) % segs], 0.02, 0.02, K_STEEL, ORANGE)
	beam(st, xf * Vector3(1.22, 3.05, 0.0), xf * (c - Vector3(0.229, 0.0, 0.0)), 0.05, 0.03, K_STEEL, ORANGE)
	# The net: a cut-out frustum hanging 0.45 m (chain 0.38 m), narrowing to 0.15 m.
	var drop := 0.38 if chain else 0.45
	var low := 0.15
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p00 := c + Vector3(cos(a0), 0.0, sin(a0)) * 0.229
		var p10 := c + Vector3(cos(a1), 0.0, sin(a1)) * 0.229
		var p01 := c + Vector3(cos(a0) * low, -drop, sin(a0) * low)
		var p11 := c + Vector3(cos(a1) * low, -drop, sin(a1) * low)
		_quad(st, xf * p00, xf * p10, xf * p11, xf * p01, K_HOOPNET, WHITE if not chain else GALV, 1.0 if chain else 0.0, 0.72 * float(i), 0.72 * float(i + 1), drop)


## Two-sided quad (a cut-out net face): corners a b c d round it, u from u0 to u1, v 0..h.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, kind: int, paint: Color, param: float, u0: float, u1: float, h: float) -> void:
	var col := IndustrialKit.kind_color(kind, paint)
	var n := (b - a).cross(d - a).normalized()
	var pts := [a, b, c, d]
	var uvs := [Vector2(u0, h), Vector2(u1, h), Vector2(u1, 0.0), Vector2(u0, 0.0)]
	for side in 2:
		var order := [0, 1, 2, 0, 2, 3] if side == 0 else [0, 2, 1, 0, 3, 2]
		var nn := n if side == 0 else -n
		for k: int in order:
			st.set_normal(nn)
			st.set_color(col)
			st.set_uv(uvs[k])
			st.set_uv2(Vector2(h, param))
			st.add_vertex(pts[k])
	tris += 4


## A tennis net across a court: `xf` at the middle of the net line, x across the court.
static func tennis_net(st: SurfaceTool, xf: Transform3D) -> void:
	var half := 10.97 * 0.5 + 0.914
	for s: float in [-1.0, 1.0]:
		post(st, xf * Vector3(s * half, 0.0, 0.0), 0.04, 1.07, K_STEEL, GREEN_STEEL, 8)
	# The net sags from 1.07 m at the posts to 0.914 m in the middle: two panels.
	for s: float in [-1.0, 1.0]:
		var outer := xf * Vector3(s * half, 1.07, 0.0)
		var inner := xf * Vector3(0.0, 0.914, 0.0)
		var o0 := xf * Vector3(s * half, 0.02, 0.0)
		var i0 := xf * Vector3(0.0, 0.02, 0.0)
		if s > 0.0:
			_quad(st, inner, outer, o0, i0, K_NET, Color(0.06, 0.06, 0.06), 0.045, 0.0, half, 1.0)
		else:
			_quad(st, outer, inner, i0, o0, K_NET, Color(0.06, 0.06, 0.06), 0.045, 0.0, half, 1.0)
		beam(st, inner + Vector3(0.0, 0.03, 0.0), outer + Vector3(0.0, 0.03, 0.0), 0.012, 0.06, K_CHALK, WHITE)
	beam(st, xf * Vector3(0.0, 0.0, 0.0), xf * Vector3(0.0, 0.914, 0.0), 0.012, 0.05, K_CHALK, WHITE)


## A soccer goal: `xf` at the middle of the goal line, x into the field. `w` x `h` the mouth.
static func soccer_goal(st: SurfaceTool, xf: Transform3D, w: float, h: float) -> void:
	var depth := 1.8 if w > 6.0 else 1.2
	for s: float in [-1.0, 1.0]:
		beam(st, xf * Vector3(0.0, 0.0, s * w * 0.5), xf * Vector3(0.0, h, s * w * 0.5), 0.1, 0.1, K_STEEL, WHITE)
		beam(st, xf * Vector3(0.0, h, s * w * 0.5), xf * Vector3(-depth * 0.6, h, s * w * 0.5), 0.05, 0.05, K_STEEL, WHITE)
		beam(st, xf * Vector3(-depth * 0.6, h, s * w * 0.5), xf * Vector3(-depth, 0.0, s * w * 0.5), 0.05, 0.05, K_STEEL, WHITE)
		_quad(st, xf * Vector3(0.0, h, s * w * 0.5), xf * Vector3(-depth * 0.6, h, s * w * 0.5), xf * Vector3(-depth, 0.0, s * w * 0.5), xf * Vector3(0.0, 0.0, s * w * 0.5), K_NET, WHITE, 0.12, 0.0, depth, h)
	beam(st, xf * Vector3(0.0, h, -w * 0.5), xf * Vector3(0.0, h, w * 0.5), 0.1, 0.1, K_STEEL, WHITE)
	beam(st, xf * Vector3(-depth, 0.03, -w * 0.5), xf * Vector3(-depth, 0.03, w * 0.5), 0.05, 0.05, K_STEEL, WHITE)
	_quad(st, xf * Vector3(-depth * 0.6, h, -w * 0.5), xf * Vector3(-depth * 0.6, h, w * 0.5), xf * Vector3(-depth, 0.0, w * 0.5), xf * Vector3(-depth, 0.0, -w * 0.5), K_NET, WHITE, 0.12, 0.0, w, h)
	_quad(st, xf * Vector3(0.0, h, -w * 0.5), xf * Vector3(0.0, h, w * 0.5), xf * Vector3(-depth * 0.6, h, w * 0.5), xf * Vector3(-depth * 0.6, h, -w * 0.5), K_NET, WHITE, 0.12, 0.0, w, depth * 0.6)


## American football goal posts (the single gooseneck kind): `xf` at the middle of the end line,
## x INTO the field; the crossbar 3.05 m up, 7.07 m wide (high school), uprights 6 m over it.
static func goal_posts(st: SurfaceTool, xf: Transform3D, scale: float = 1.0) -> void:
	var yellow := Color(0.95, 0.78, 0.10)
	var w := 7.07 * clampf(scale, 0.7, 1.0)
	post(st, xf * Vector3(-1.8, 0.0, 0.0), 0.12, 2.6, K_STEEL, yellow, 10)
	beam(st, xf * Vector3(-1.8, 2.6, 0.0), xf * Vector3(-1.8, 3.05, 0.0), 0.2, 0.2, K_STEEL, yellow)
	beam(st, xf * Vector3(-1.8, 3.05, 0.0), xf * Vector3(0.0, 3.05, 0.0), 0.16, 0.16, K_STEEL, yellow)
	beam(st, xf * Vector3(0.0, 3.05, -w * 0.5), xf * Vector3(0.0, 3.05, w * 0.5), 0.12, 0.12, K_STEEL, yellow)
	for s: float in [-1.0, 1.0]:
		beam(st, xf * Vector3(0.0, 3.05, s * w * 0.5), xf * Vector3(0.0, 9.1, s * w * 0.5), 0.1, 0.1, K_STEEL, yellow)
	post(st, xf * Vector3(-1.8, 0.0, 0.0), 0.2, 1.8, K_RUBBER, Color(0.12, 0.14, 0.30), 10)


# --- Playground ---------------------------------------------------------------------------------

## A play structure: decks on coloured posts at two heights, roofs, a tube and a wave slide, a
## climbing wall, a ladder; `xf` at its centre, x along it. About 9 x 6 m.
static func play_structure(st: SurfaceTool, xf: Transform3D, set_i: int) -> void:
	var col: Array = PLAY_SETS[set_i % PLAY_SETS.size()]
	var posts: Color = col[0]
	var decks: Color = col[1]
	var slide: Color = col[2]
	var panel: Color = col[3]
	var decks_at := [[Vector3(-2.0, 1.2, 0.0), 1.6], [Vector3(0.0, 1.6, 0.0), 1.6], [Vector3(2.0, 0.9, 0.0), 1.6]]
	for d: Array in decks_at:
		var p: Vector3 = d[0]
		var s: float = d[1]
		box(st, xf * Transform3D(Basis(), p), Vector3(s, 0.08, s), K_PLASTIC, decks)
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				post(st, xf * Vector3(p.x + cx * s * 0.47, 0.0, cz * s * 0.47), 0.06, p.y + 1.9, K_STEEL, posts, 8)
		# Guard panels on two sides.
		box(st, xf * Transform3D(Basis(), p + Vector3(0.0, 0.5, s * 0.47)), Vector3(s * 0.9, 0.9, 0.05), K_PLASTIC, panel)
	# Roofs over the two higher decks: a pyramid of two pitched slabs each.
	for i in 2:
		var p: Vector3 = (decks_at[i] as Array)[0]
		var ry := p.y + 1.9
		for s: float in [-1.0, 1.0]:
			box(st, xf * Transform3D(Basis(Vector3(0, 0, 1), s * 0.45), p + Vector3(s * 0.42, ry - p.y + 0.2, 0.0) + Vector3(0.0, 0.0, 0.0)), Vector3(1.0, 0.06, 1.9), K_PLASTIC, slide.lerp(decks, 0.2))
	# A wave slide off the highest deck, down toward +z.
	var top := xf * Vector3(0.0, 1.6, 0.8)
	var mid := xf * Vector3(0.0, 0.9, 2.4)
	var foot := xf * Vector3(0.0, 0.3, 3.8)
	for seg: Array in [[top, mid], [mid, foot]]:
		beam(st, seg[0], seg[1], 0.62, 0.05, K_PLASTIC, slide)
		for s: float in [-1.0, 1.0]:
			var off := (xf.basis * Vector3(s * 0.31, 0.15, 0.0))
			beam(st, (seg[0] as Vector3) + off, (seg[1] as Vector3) + off, 0.05, 0.3, K_PLASTIC, slide)
	# A tube slide off the left deck toward -z: a run of short boxes stepping down.
	for k in 6:
		var t0 := float(k) / 6.0
		var t1 := float(k + 1) / 6.0
		var a := xf * Vector3(-2.0 - 0.3 * sin(t0 * PI), 1.2 - 0.95 * t0, -0.8 - 2.6 * t0)
		var b := xf * Vector3(-2.0 - 0.3 * sin(t1 * PI), 1.2 - 0.95 * t1, -0.8 - 2.6 * t1)
		beam(st, a + Vector3(0.0, 0.3, 0.0), b + Vector3(0.0, 0.3, 0.0), 0.7, 0.7, K_PLASTIC, panel)
	# A climbing wall up to the right deck, and a ladder up the middle.
	box(st, xf * Transform3D(Basis(Vector3(0, 0, 1), 0.25), Vector3(3.05, 0.45, 0.0)), Vector3(0.06, 1.2, 1.4), K_PLASTIC, decks.darkened(0.2))
	for k in 5:
		beam(st, xf * Vector3(0.6, 0.3 + 0.3 * float(k), -0.75), xf * Vector3(0.6, 0.3 + 0.3 * float(k), -0.35), 0.04, 0.04, K_STEEL, posts)
	# Bridge between the left and middle decks.
	beam(st, xf * Vector3(-1.2, 1.25, 0.0), xf * Vector3(-0.8, 1.55, 0.0), 1.0, 0.06, K_PLASTIC, decks)


## Swings: an A-frame at each end, the top beam, two or four belt seats on chains. `xf` at the
## middle of the beam's foot line, x along the beam.
static func swings(st: SurfaceTool, xf: Transform3D, seats: int, paint: Color) -> void:
	var half := 1.1 * float(seats) * 0.5 + 0.6
	var h := 2.6
	for s: float in [-1.0, 1.0]:
		for f: float in [-1.0, 1.0]:
			beam(st, xf * Vector3(s * half, 0.0, f * 1.1), xf * Vector3(s * half, h, 0.0), 0.075, 0.075, K_STEEL, paint)
	beam(st, xf * Vector3(-half, h, 0.0), xf * Vector3(half, h, 0.0), 0.1, 0.1, K_STEEL, paint)
	for i in seats:
		var x := -half + 0.6 + 0.55 + 1.1 * float(i)
		var swing := 0.12 * sin(float(i) * 2.1)
		for e: float in [-0.22, 0.22]:
			beam(st, xf * Vector3(x + e, h, 0.0), xf * Vector3(x + e, 0.5, swing), 0.012, 0.012, K_GALV, GALV)
		box(st, xf * Transform3D(Basis(), Vector3(x, 0.48, swing)), Vector3(0.55, 0.03, 0.17), K_RUBBER, BLACK)


# --- Lights ------------------------------------------------------------------------------------

## A field floodlight: a galvanised pole `h` high at `at`, a crossarm and a bank of luminaires
## aimed toward `aim` (XZ), tilted down. The lamps' faces glow after dark (K_LAMP).
static func floodlight(st: SurfaceTool, at: Vector3, aim: Vector2, h: float, heads: int) -> void:
	post(st, at, 0.2, h * 0.5, K_GALV, GALV, 10)
	post(st, at + Vector3(0.0, h * 0.5, 0.0), 0.14, h * 0.5, K_GALV, GALV, 10)
	var dir := (aim - Vector2(at.x, at.z))
	if dir.length() < 0.1:
		dir = Vector2(1.0, 0.0)
	dir = dir.normalized()
	var x := Vector3(-dir.y, 0.0, dir.x)
	var fwd := Vector3(dir.x, 0.0, dir.y)
	var cols := mini(heads, 4)
	var rows := ceili(float(heads) / float(cols))
	var w := float(cols) * 0.75
	beam(st, at + Vector3(0.0, h - 0.3, 0.0) - x * w * 0.5, at + Vector3(0.0, h - 0.3, 0.0) + x * w * 0.5, 0.1, 0.1, K_GALV, GALV)
	if rows > 1:
		beam(st, at + Vector3(0.0, h + 0.5, 0.0) - x * w * 0.5, at + Vector3(0.0, h + 0.5, 0.0) + x * w * 0.5, 0.1, 0.1, K_GALV, GALV)
	var tilt := Basis(x, deg_to_rad(-28.0))
	var basis := tilt * Basis(x, Vector3.UP, -fwd).orthonormalized()
	var k := 0
	for r in rows:
		for c in cols:
			if k >= heads:
				break
			var p := at + Vector3(0.0, h - 0.3 + 0.8 * float(r), 0.0) + x * (-w * 0.5 + 0.375 + 0.75 * float(c)) + fwd * 0.25
			# The housing, then its lens on the field side.
			box(st, Transform3D(basis, p), Vector3(0.6, 0.6, 0.22), K_STEEL, Color(0.30, 0.31, 0.32))
			box(st, Transform3D(basis, p + basis.z * -0.115), Vector3(0.52, 0.52, 0.01), K_LAMP, Color(1.0, 0.97, 0.9), 0.0, 0)
			k += 1


# --- Buildings ----------------------------------------------------------------------------------

## A flat-roofed stucco building on its rect: walls (windows by `windows`), a coped parapet, the
## membrane roof, rooftop units. `xf` at the middle of its foot, x along `len`, z across `depth`.
static func flat_building(st: SurfaceTool, xf: Transform3D, len: float, depth: float, h: float, paint: Color, windows: float, trim: Color) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, h * 0.5, 0.0)), Vector3(len, h, depth), K_STUCCO, paint, windows, 32)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, h - 0.02, 0.0)), Vector3(len - 0.5, 0.06, depth - 0.5), K_ROOF, ROOF, 0.0, 47)
	for s: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, h + 0.4, s * (depth * 0.5 - 0.12))), Vector3(len, 0.8, 0.24), K_STUCCO, paint, W_BLANK, 32)
		box(st, xf * Transform3D(Basis(), Vector3(s * (len * 0.5 - 0.12), h + 0.4, 0.0)), Vector3(0.24, 0.8, depth - 0.48), K_STUCCO, paint, W_BLANK, 32)
		box(st, xf * Transform3D(Basis(), Vector3(0.0, h + 0.84, s * (depth * 0.5 - 0.12))), Vector3(len + 0.06, 0.08, 0.32), K_STEEL, trim)
		box(st, xf * Transform3D(Basis(), Vector3(s * (len * 0.5 - 0.12), h + 0.84, 0.0)), Vector3(0.32, 0.08, depth), K_STEEL, trim)
	var units := maxi(1, int(len / 14.0))
	for i in units:
		var x := -len * 0.5 + len * (float(i) + 0.5) / float(units)
		box(st, xf * Transform3D(Basis(), Vector3(x, h + 0.6, depth * 0.12)), Vector3(2.2, 1.2, 1.6), K_GALV, Color(0.78, 0.78, 0.76))


## A covered walkway along a building's face: square steel posts every 4 m, a flat metal canopy
## with a fascia. `a` to `b` along the face at ground level, the canopy `w` deep toward `out`.
static func walkway(st: SurfaceTool, a: Vector3, b: Vector3, out: Vector3, w: float, h: float, trim: Color) -> void:
	var len := a.distance_to(b)
	var n := maxi(1, int(len / 4.0))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n)) + out * (w - 0.2)
		box(st, Transform3D(Basis(), p + Vector3(0.0, h * 0.5, 0.0)), Vector3(0.15, h, 0.15), K_STEEL, Color(0.86, 0.86, 0.84))
	var mid := (a + b) * 0.5 + out * (w * 0.5) + Vector3(0.0, h + 0.1, 0.0)
	var x := (b - a).normalized()
	var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP)).orthonormalized()
	box(st, Transform3D(basis, mid), Vector3(len + 0.4, 0.18, w), K_CANOPY, Color(0.82, 0.82, 0.80), 1.0)
	box(st, Transform3D(basis, mid + out * (w * 0.5) + Vector3(0.0, -0.05, 0.0)), Vector3(len + 0.4, 0.4, 0.06), K_STEEL, trim)


## A picnic table (top, two benches, legs), `xf` at its centre, x along it.
static func picnic_table(st: SurfaceTool, xf: Transform3D) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.74, 0.0)), Vector3(1.8, 0.05, 0.76), K_WOOD, WOOD)
	for s: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.44, s * 0.62)), Vector3(1.8, 0.04, 0.26), K_WOOD, WOOD)
		beam(st, xf * Vector3(s * 0.62, 0.0, -0.75), xf * Vector3(s * 0.62, 0.74, 0.0), 0.06, 0.06, K_STEEL, Color(0.2, 0.2, 0.22))
		beam(st, xf * Vector3(s * 0.62, 0.0, 0.75), xf * Vector3(s * 0.62, 0.74, 0.0), 0.06, 0.06, K_STEEL, Color(0.2, 0.2, 0.22))


## A picnic shelter: four posts, a low hipped metal roof, tables under it. `xf` at its centre.
static func shelter(st: SurfaceTool, xf: Transform3D, len: float, depth: float, tables: int, paint: Color) -> void:
	var h := 2.8
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(st, xf * Transform3D(Basis(), Vector3(sx * (len * 0.5 - 0.6), h * 0.5, sz * (depth * 0.5 - 0.6))), Vector3(0.18, h, 0.18), K_STEEL, paint)
	for s: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(Vector3.RIGHT, -s * 0.28), Vector3(0.0, h + 0.4, s * depth * 0.25)), Vector3(len + 0.6, 0.08, depth * 0.55), K_CANOPY, paint.darkened(0.15), 1.0)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, h + 0.05, 0.0)), Vector3(len, 0.18, 0.15), K_STEEL, paint)
	for i in tables:
		var x := -len * 0.5 + len * (float(i) + 0.5) / float(tables)
		picnic_table(st, xf * Transform3D(Basis(), Vector3(x, 0.0, 0.0)))


## A ladder out of the pool (two rails over the coping, three treads). `xf` on the coping, x into
## the pool.
static func pool_ladder(st: SurfaceTool, xf: Transform3D) -> void:
	for s: float in [-0.25, 0.25]:
		beam(st, xf * Vector3(-0.35, 0.0, s), xf * Vector3(-0.35, 0.9, s), 0.04, 0.04, K_GALV, Color(0.85, 0.86, 0.86))
		beam(st, xf * Vector3(-0.35, 0.9, s), xf * Vector3(0.15, 0.9, s), 0.04, 0.04, K_GALV, Color(0.85, 0.86, 0.86))
		beam(st, xf * Vector3(0.15, 0.9, s), xf * Vector3(0.2, -1.2, s), 0.04, 0.04, K_GALV, Color(0.85, 0.86, 0.86))
	for k in 3:
		box(st, xf * Transform3D(Basis(), Vector3(0.18, -0.3 - 0.3 * float(k), 0.0)), Vector3(0.08, 0.03, 0.5), K_GALV, Color(0.85, 0.86, 0.86))


## A lifeguard chair: a white steel frame, a seat 1.8 m up, an umbrella pole.
static func guard_chair(st: SurfaceTool, xf: Transform3D) -> void:
	for sx: float in [-0.35, 0.35]:
		beam(st, xf * Vector3(sx, 0.0, -0.4), xf * Vector3(sx, 1.8, 0.0), 0.06, 0.06, K_STEEL, WHITE)
		beam(st, xf * Vector3(sx, 0.0, 0.4), xf * Vector3(sx, 1.8, 0.0), 0.06, 0.06, K_STEEL, WHITE)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.8, 0.0)), Vector3(0.8, 0.06, 0.5), K_PLASTIC, WHITE)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 2.15, 0.22)), Vector3(0.8, 0.7, 0.05), K_PLASTIC, WHITE)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 2.3, -0.2)), Vector3(0.05, 1.0, 0.05), K_STEEL, WHITE)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 2.85, -0.2)), Vector3(1.5, 0.05, 1.5), K_PLASTIC, Color(0.85, 0.2, 0.15))
