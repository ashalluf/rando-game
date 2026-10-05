class_name PierCarousel
extends RefCounted
## The pier park's carousel (PierPark): a round platform under a striped canopy with a scalloped,
## bulb-lit rounding board, a mirrored centre column, brass poles and twenty-eight carved horses
## in two rings - painted coats, saddles, blankets and gold trim - riding up and down their poles.
##
## It turns in the vertex shader (pier_park.gdshader, ride 2: about +Y round the node's origin at
## OMEGA, anticlockwise from above as American carousels do; horse k bobs on its own phase), so
## nothing runs on the CPU. The base it stands on is a separate static mesh with collision.

const OMEGA := TAU / 22.0
const R_PLATFORM := 8.2
const R_CANOPY := 8.8
const CANOPY_Y := 4.7
const RINGS: Array[Vector2] = [Vector2(6.8, 16.0), Vector2(5.1, 12.0)]
const COATS: Array[Color] = [Color(0.95, 0.93, 0.88), Color(0.12, 0.10, 0.09), Color(0.55, 0.32, 0.18),
	Color(0.72, 0.70, 0.68), Color(0.90, 0.80, 0.60), Color(0.36, 0.22, 0.14)]
const SADDLES: Array[Color] = [Color(0.70, 0.08, 0.10), Color(0.08, 0.25, 0.60), Color(0.10, 0.45, 0.30), Color(0.55, 0.15, 0.50)]
const STRIPE_A := Color(0.80, 0.10, 0.14)

static var _meshes: Dictionary = {}


static func build(parent: Node3D, at: Vector3, detailed: bool) -> Node3D:
	var node := Node3D.new()
	node.name = "Carousel"
	node.position = at
	parent.add_child(node)
	var key := "near" if detailed else "far"
	if not _meshes.has(key):
		_meshes[key] = _meshes_for(detailed)
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.name = ["Base", "Ride", "RideLights"][i]
		mi.mesh = _meshes[key][i]
		if i == 2 or not detailed:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	return node


## [base, the turning ride, its bulbs].
static func _meshes_for(detailed: bool) -> Array:
	var turning := _turning(detailed)
	return [_base(detailed), turning[0], turning[1]]


static func material() -> ShaderMaterial:
	return PierMesh.material("carousel", 2, {"hub": Vector3.ZERO, "omega": OMEGA})


static func _base(detailed: bool) -> ArrayMesh:
	var g := PierMesh.new()
	g.use("b", PierMesh.material("park"))
	g.slot("b")
	g.kind = PierMesh.K_PAINT
	var segs := 32 if detailed else 12
	g.cone(Vector3.ZERO, R_PLATFORM + 0.6, 0.0, R_PLATFORM + 0.6, 0.45, segs, Color(0.85, 0.80, 0.68))
	g.ring_flat(Vector3(0, 0.45, 0), R_PLATFORM + 0.05, R_PLATFORM + 0.6, segs, Color(0.62, 0.48, 0.32))
	if detailed:
		# A low brass fence round it, open at the gate.
		g.kind = PierMesh.K_GOLD
		var fr := R_PLATFORM + 2.6
		var pts := PackedVector3Array()
		for i in 41:
			var a := lerpf(0.25, TAU - 0.25, float(i) / 40.0)
			pts.append(Vector3(cos(a) * fr, 1.0, sin(a) * fr))
			if i % 2 == 0:
				g.tube(Vector3(cos(a) * fr, 0.0, sin(a) * fr), Vector3(cos(a) * fr, 1.0, sin(a) * fr), 0.03, 0.03, Color.WHITE, 5)
		g.sweep(pts, 0.035, Color.WHITE, 5)
	return g.build_mesh()


static func _turning(detailed: bool) -> Array:
	var g := PierMesh.new()
	g.use("r", material())
	g.use("rl", material())
	g.light_slot = "rl"
	g.slot("r")
	var segs := 48 if detailed else 16
	var deck_y := 0.55
	g.anim = 0.0
	# Platform: boards on top, a painted skirt.
	g.kind = PierMesh.K_BOARDS
	g.ring_flat(Vector3(0, deck_y, 0), 0.0, R_PLATFORM, segs, Color(0.58, 0.44, 0.30))
	g.kind = PierMesh.K_PAINT
	g.cone(Vector3.ZERO, R_PLATFORM, 0.45, R_PLATFORM, deck_y, segs, Color(0.85, 0.75, 0.30))
	# Centre column: a drum of mirrors and painted panels.
	g.kind = PierMesh.K_GOLD
	g.cone(Vector3.ZERO, 1.25, deck_y, 1.25, deck_y + 0.25, 16, Color.WHITE)
	g.kind = PierMesh.K_SIGN
	g.cone(Vector3.ZERO, 1.15, deck_y + 0.25, 1.15, CANOPY_Y - 0.2, 16, Color(0.25, 0.55, 0.65))
	g.kind = PierMesh.K_GOLD
	g.cone(Vector3.ZERO, 1.25, CANOPY_Y - 0.2, 1.25, CANOPY_Y, 16, Color.WHITE)
	# Canopy: a striped cone, the rounding board round its edge with scallops, bulbs and mirrors.
	g.kind = PierMesh.K_CANVAS
	g.cone(Vector3.ZERO, R_CANOPY, CANOPY_Y + 0.5, 1.2, CANOPY_Y + 2.5, segs, STRIPE_A)
	# The ceiling under it: cream boards radiating from the column, rings of bulbs.
	g.kind = PierMesh.K_BOARDS
	g.cone(Vector3.ZERO, R_CANOPY, CANOPY_Y + 0.5, 1.2, CANOPY_Y + 2.5, segs, Color(0.93, 0.88, 0.74), true)
	if detailed:
		g.kind = PierMesh.K_BULB
		for ring in 3:
			var f := 0.3 + 0.22 * float(ring)
			var rr := lerpf(1.2, R_CANOPY, f)
			var yy := lerpf(CANOPY_Y + 2.5, CANOPY_Y + 0.5, f) - 0.08
			var nb := int(rr * 4.0)
			for i in nb:
				var a := TAU * (float(i) + 0.5 * float(ring)) / float(nb)
				g.anim = float(i + ring * 7)
				g.ellipsoid(Transform3D(Basis(), Vector3(cos(a) * rr, yy, sin(a) * rr)), Vector3(0.05, 0.05, 0.05), Color(1.0, 0.85, 0.55), 4, 2)
		g.anim = 0.0
	g.kind = PierMesh.K_PAINT
	g.cone(Vector3.ZERO, 1.2, CANOPY_Y + 2.5, 0.3, CANOPY_Y + 3.3, 12, Color(0.85, 0.75, 0.30))
	g.kind = PierMesh.K_GOLD
	g.ellipsoid(Transform3D(Basis(), Vector3(0, CANOPY_Y + 3.45, 0)), Vector3(0.25, 0.3, 0.25), Color.WHITE, 8, 5)
	g.kind = PierMesh.K_PAINT
	g.cone(Vector3.ZERO, R_CANOPY, CANOPY_Y - 0.3, R_CANOPY, CANOPY_Y + 0.5, segs, Color(0.92, 0.88, 0.75))
	g.cone(Vector3.ZERO, R_CANOPY - 0.05, CANOPY_Y - 0.3, R_CANOPY - 0.05, CANOPY_Y + 0.5, segs, Color(0.92, 0.88, 0.75), true)
	g.ring_flat(Vector3(0, CANOPY_Y - 0.3, 0), R_CANOPY - 0.6, R_CANOPY, segs, Color(0.90, 0.84, 0.66), Vector3.DOWN)
	if detailed:
		# Mirrors and painted panels round the rounding board, bulbs between them.
		var panels := 24
		for i in panels:
			var a := TAU * (float(i) + 0.5) / float(panels)
			var d := Vector3(cos(a), 0, sin(a))
			g.kind = PierMesh.K_SIGN
			var p := d * (R_CANOPY + 0.02) + Vector3(0, CANOPY_Y + 0.1, 0)
			g.box(Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p), Vector3(0.9, 0.42, 0.03), Color(0.9, 0.75, 0.4) if i % 2 == 0 else Color(0.35, 0.6, 0.75))
		g.kind = PierMesh.K_BULB
		var bulbs := 96
		for i in bulbs:
			var a := TAU * float(i) / float(bulbs)
			var d := Vector3(cos(a), 0, sin(a))
			g.anim = float(i) * 0.6
			for y: float in [CANOPY_Y + 0.42, CANOPY_Y - 0.22]:
				g.ellipsoid(Transform3D(Basis(), d * (R_CANOPY + 0.06) + Vector3(0, y, 0)), Vector3(0.05, 0.05, 0.05), Color(1.0, 0.82, 0.5), 4, 2)
		g.anim = 0.0
		# Scallops hanging under the board.
		g.kind = PierMesh.K_CANVAS
		for i in 36:
			var a0 := TAU * float(i) / 36.0
			var a1 := TAU * float(i + 1) / 36.0
			var am := (a0 + a1) * 0.5
			var p0 := Vector3(cos(a0), 0, sin(a0)) * R_CANOPY + Vector3(0, CANOPY_Y - 0.3, 0)
			var p1 := Vector3(cos(a1), 0, sin(a1)) * R_CANOPY + Vector3(0, CANOPY_Y - 0.3, 0)
			var pm := Vector3(cos(am), 0, sin(am)) * R_CANOPY + Vector3(0, CANOPY_Y - 0.62, 0)
			var n := Vector3(cos(am), 0, sin(am))
			g.tri(p0, p1, pm, n, Vector2(0, 0), Vector2(1.5, 0), Vector2(0.75, 0.3), STRIPE_A if i % 2 == 0 else Color(0.95, 0.9, 0.8))
			g.tri(p0, p1, pm, -n, Vector2(0, 0), Vector2(1.5, 0), Vector2(0.75, 0.3), STRIPE_A if i % 2 == 0 else Color(0.95, 0.9, 0.8))
		# The sweeps under the canopy, column to rim.
		g.kind = PierMesh.K_PAINT
		for i in 16:
			var a := TAU * float(i) / 16.0
			var d := Vector3(cos(a), 0, sin(a))
			g.tube(d * 1.2 + Vector3(0, CANOPY_Y + 0.4, 0), d * (R_CANOPY - 0.1) + Vector3(0, CANOPY_Y - 0.25, 0), 0.06, 0.06, Color(0.85, 0.75, 0.30), 5)
	# Horses on brass poles.
	var k := 0
	for ring: Vector2 in RINGS:
		var r := ring.x
		var n := int(ring.y)
		for i in n:
			var phi := TAU * (float(i) + (0.5 if r < 6.0 else 0.0)) / float(n)
			var pos := Vector3(cos(phi) * r, 0.0, -sin(phi) * r)
			g.anim = 0.0
			g.kind = PierMesh.K_GOLD
			g.tube(pos + Vector3(0, deck_y, 0), pos + Vector3(0, CANOPY_Y - 0.3, 0), 0.035 if detailed else 0.08, 0.035 if detailed else 0.08, Color.WHITE, 6 if detailed else 3)
			g.anim = float(k + 1)
			var xf := Transform3D(Basis(Vector3.UP, phi), pos + Vector3(0, deck_y + 1.45, 0))
			# The horses stand in the canopy's shade: they cast nothing (the no-shadow slot).
			g.slot("rl")
			_horse(g, xf, k, detailed)
			g.slot("r")
			k += 1
	g.anim = 0.0
	return [g.build_mesh(["r"]), g.build_mesh(["rl"])]


## A carved, prancing carousel horse in its own frame (forward -Z, origin at the saddle on the
## pole), coat, mane, saddle and trim picked from `k`.
static func _horse(g: PierMesh, xf: Transform3D, k: int, detailed: bool) -> void:
	var coat: Color = COATS[k % COATS.size()]
	var mane: Color = COATS[(k + 3) % COATS.size()].darkened(0.25)
	var saddle: Color = SADDLES[(k * 7) % SADDLES.size()]
	var sg := 8 if detailed else 5
	var rg := 5 if detailed else 3
	var e := func(c: Vector3, r: Vector3, b: Basis, col: Color) -> void:
		g.ellipsoid(xf * Transform3D(b, c), r, col, sg, rg)
	g.kind = PierMesh.K_PAINT
	e.call(Vector3(0, 0, 0), Vector3(0.23, 0.26, 0.6), Basis(), coat)
	if not detailed:
		e.call(Vector3(0, 0.42, -0.62), Vector3(0.12, 0.34, 0.16), Basis(Vector3.RIGHT, -0.5), coat)
		return
	e.call(Vector3(0, 0.05, -0.42), Vector3(0.22, 0.25, 0.3), Basis(), coat)
	e.call(Vector3(0, 0.02, 0.42), Vector3(0.24, 0.27, 0.3), Basis(), coat)
	e.call(Vector3(0, 0.4, -0.62), Vector3(0.12, 0.34, 0.16), Basis(Vector3.RIGHT, -0.5), coat)
	e.call(Vector3(0, 0.72, -0.9), Vector3(0.095, 0.12, 0.26), Basis(Vector3.RIGHT, -0.75), coat)
	# Mane and forelock, ears, eyes.
	e.call(Vector3(0, 0.52, -0.52), Vector3(0.045, 0.36, 0.09), Basis(Vector3.RIGHT, -0.5), mane)
	for xs: float in [-1.0, 1.0]:
		g.tube(xf * Vector3(xs * 0.05, 0.84, -0.8), xf * Vector3(xs * 0.06, 0.98, -0.78), 0.03, 0.005, coat, 4)
		g.kind = PierMesh.K_RUBBER
		g.ellipsoid(xf * Transform3D(Basis(), Vector3(xs * 0.085, 0.76, -0.93)), Vector3(0.018, 0.022, 0.022), Color.BLACK, 4, 2)
		g.kind = PierMesh.K_PAINT
	# Legs: the front pair raised and folded (prancing), the hind pair reaching back to the ground.
	for xs: float in [-1.0, 1.0]:
		var sh := Vector3(xs * 0.12, -0.12, -0.5)
		var knee := Vector3(xs * 0.12, -0.32, -0.86)
		var hoof := Vector3(xs * 0.12, -0.6, -0.74)
		g.tube(xf * sh, xf * knee, 0.08, 0.055, coat, 6)
		g.tube(xf * knee, xf * hoof, 0.05, 0.04, coat, 6)
		var hip := Vector3(xs * 0.13, -0.08, 0.5)
		var hock := Vector3(xs * 0.13, -0.58, 0.78)
		var hoof2 := Vector3(xs * 0.13, -0.98, 0.62)
		g.tube(xf * hip, xf * hock, 0.09, 0.05, coat, 6)
		g.tube(xf * hock, xf * hoof2, 0.045, 0.04, coat, 6)
		g.kind = PierMesh.K_GOLD
		g.tube(xf * hoof, xf * (hoof + Vector3(0, -0.06, 0.02)), 0.045, 0.05, Color.WHITE, 6, true)
		g.tube(xf * hoof2, xf * (hoof2 + Vector3(0, -0.06, 0)), 0.045, 0.05, Color.WHITE, 6, true)
		g.kind = PierMesh.K_PAINT
	# Tail.
	g.tube(xf * Vector3(0, 0.08, 0.86), xf * Vector3(0, -0.2, 1.08), 0.08, 0.05, mane, 6)
	g.tube(xf * Vector3(0, -0.2, 1.08), xf * Vector3(0, -0.55, 1.05), 0.05, 0.015, mane, 6)
	# Saddle, blanket, breast collar, stirrups.
	g.kind = PierMesh.K_PAINT
	g.box(xf * Transform3D(Basis(), Vector3(0, 0.26, 0.0)), Vector3(0.5, 0.03, 0.62), saddle)
	g.box(xf * Transform3D(Basis(), Vector3(0, 0.3, 0.02)), Vector3(0.36, 0.08, 0.42), saddle.darkened(0.3), 0.06)
	g.kind = PierMesh.K_GOLD
	g.box(xf * Transform3D(Basis(), Vector3(0, 0.275, 0.0)), Vector3(0.52, 0.015, 0.64), Color.WHITE)
	g.box(xf * Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3(0, 0.12, -0.66)), Vector3(0.47, 0.06, 0.06), Color.WHITE)
	for xs: float in [-1.0, 1.0]:
		g.tube(xf * Vector3(xs * 0.24, 0.24, 0.0), xf * Vector3(xs * 0.27, -0.18, 0.0), 0.012, 0.012, Color.WHITE, 4)
		g.box(xf * Transform3D(Basis(), Vector3(xs * 0.27, -0.2, 0.0)), Vector3(0.05, 0.03, 0.1), Color.WHITE)
