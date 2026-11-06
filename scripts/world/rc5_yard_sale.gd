class_name Rc5YardSale
extends RefCounted
## The yard sale refcam (wave 8, `yard_sale` in tools/refcams/cameras_w8.json; docs/HANDOFF.md
## "The yard sale from across the street"). Seen from the far pavement at 09:30 the sales read as
## two bare white tables in a yard: a real one is crammed. So:
##   - the tables are full: goods in two rows (tall things at the back), a box and a tote stashed
##     under every six-foot table (YardSaleKit._goods / _table6 ask `enabled`);
##   - a pop-up shade canopy (2.44 m square, scissor-truss frame, peaked top with its valance) over
##     a table on a share of sales - the silhouette that says "yard sale" from down the street;
##   - a blanket on the lawn spread with what does not go on a table: shoes, a toolbox, a cooler, a
##     crate of records, a rolled rug, a golf bag, a stack of frames.
## Both are new row kinds in YardSales.ITEMS ("canopy", "blanket"), offered by `extra_kinds()`
## after the old ones, so a sale's other rolls are unchanged. Meshes on YardSaleKit's one shader.
## `RC5_YARD_SALE=0` is the A/B (the old tables, no canopy, no blanket).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_YARD_SALE") != "0"

## The canopy's square (m), eave and peak heights; the fabric colours (sRGB): blue, white, red,
## green, tan.
const CANOPY := 2.44
const EAVE := 2.05
const PEAK := 2.62
const CANOPY_COLORS := [Color(0.12, 0.3, 0.62), Color(0.92, 0.92, 0.9), Color(0.68, 0.1, 0.1), Color(0.14, 0.4, 0.22), Color(0.72, 0.62, 0.45)]
## The blanket (m): its patches' colours.
const BLANKET := Vector2(1.85, 1.3)


## The kinds the refcam pass adds to a sale's row (after the old ones).
static func extra_kinds() -> Array:
	return ["canopy", "blanket"] if enabled else []


static func canopy_variants() -> int:
	return CANOPY_COLORS.size()


# --- The canopy -----------------------------------------------------------------------------------

## A 8 x 8 ft pop-up canopy over a six-foot table of goods `goods` ("0".."2"), fabric colour `v`.
static func canopy(g: BackyardKit.G, v: int, goods: String) -> void:
	var fab_c: Color = CANOPY_COLORS[v % CANOPY_COLORS.size()]
	var fab := YardSaleKit.col(fab_c, YardSaleKit.K_PAINT)
	var under := YardSaleKit.col(fab_c * 0.8, YardSaleKit.K_PAINT)
	var steel := YardSaleKit.col(Color(0.78, 0.79, 0.8), YardSaleKit.K_METAL)
	var black := YardSaleKit.col(Color(0.08, 0.08, 0.08), YardSaleKit.K_RUBBER)
	var h := CANOPY * 0.5 - 0.03
	# Four square legs (the inner tube telescoping out of the outer), feet plates.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * h, 0, sz * h)
			BackyardKit.box(g, Transform3D(Basis(), p + Vector3(0, 0.75, 0)), Vector3(0.032, 1.5, 0.032), steel)
			BackyardKit.box(g, Transform3D(Basis(), p + Vector3(0, 1.75, 0)), Vector3(0.025, 0.6, 0.025), steel)
			BackyardKit.box(g, Transform3D(Basis(), p + Vector3(0, 0.004, 0)), Vector3(0.12, 0.008, 0.12), black)
			BackyardKit.box(g, Transform3D(Basis(), p + Vector3(0, 1.5, 0)), Vector3(0.05, 0.05, 0.05), black)
	# The scissor truss along each side under the eave: X's of flat bar.
	for side in 4:
		var a := Vector3(-h, 0, -h)
		var b := Vector3(h, 0, -h)
		match side:
			1:
				a = Vector3(h, 0, -h)
				b = Vector3(h, 0, h)
			2:
				a = Vector3(h, 0, h)
				b = Vector3(-h, 0, h)
			3:
				a = Vector3(-h, 0, h)
				b = Vector3(-h, 0, -h)
		var n := 3
		for k in n:
			var p0 := a.lerp(b, float(k) / float(n))
			var p1 := a.lerp(b, float(k + 1) / float(n))
			BackyardKit.cyl(g, p0 + Vector3(0, EAVE - 0.02, 0), p1 + Vector3(0, EAVE - 0.3, 0), 0.008, 0.008, 4, steel, false)
			BackyardKit.cyl(g, p0 + Vector3(0, EAVE - 0.3, 0), p1 + Vector3(0, EAVE - 0.02, 0), 0.008, 0.008, 4, steel, false)
	# The roof struts to the peak.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			BackyardKit.cyl(g, Vector3(sx * h, EAVE, sz * h), Vector3(0, PEAK - 0.05, 0), 0.009, 0.009, 4, steel, false)
	# The top: four sloped panels with a slight sag, both faces, overhanging the frame.
	var o := CANOPY * 0.5 + 0.02
	var corners := [Vector3(-o, EAVE + 0.01, -o), Vector3(o, EAVE + 0.01, -o), Vector3(o, EAVE + 0.01, o), Vector3(-o, EAVE + 0.01, o)]
	var peak := Vector3(0, PEAK, 0)
	for i in 4:
		var c0: Vector3 = corners[i]
		var c1: Vector3 = corners[(i + 1) % 4]
		var mid := (c0 + c1) * 0.5
		var sag := mid.lerp(peak, 0.45) - Vector3(0, 0.035, 0)
		var nrm := (c1 - c0).cross(peak - c0).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		for tri: Array in [[c0, c1, sag], [c1, peak, sag], [peak, c0, sag]]:
			var q0: Vector3 = tri[0]
			var q1: Vector3 = tri[1]
			var q2: Vector3 = tri[2]
			var i0 := g.vert(q0, nrm, fab, Vector2(q0.x, q0.z))
			var i1 := g.vert(q1, nrm, fab, Vector2(q1.x, q1.z))
			var i2 := g.vert(q2, nrm, fab, Vector2(q2.x, q2.z))
			g.tri(i0, i1, i2, nrm)
			var j0 := g.vert(q0 - Vector3(0, 0.004, 0), -nrm, under, Vector2(q0.x, q0.z))
			var j1 := g.vert(q1 - Vector3(0, 0.004, 0), -nrm, under, Vector2(q1.x, q1.z))
			var j2 := g.vert(q2 - Vector3(0, 0.004, 0), -nrm, under, Vector2(q2.x, q2.z))
			g.tri(j0, j2, j1, -nrm)
		# The valance hanging from the edge, scalloped by a slight wave.
		var dir := (c1 - c0).normalized()
		var out := Vector3(-dir.z, 0, dir.x)
		if out.dot(mid) < 0.0:
			out = -out
		var segs := 8
		for k in segs:
			var e0 := c0.lerp(c1, float(k) / float(segs)) + out * 0.004
			var e1 := c0.lerp(c1, float(k + 1) / float(segs)) + out * 0.004
			var d0 := 0.2 - 0.025 * absf(sin(float(k) * PI * 0.5))
			var d1 := 0.2 - 0.025 * absf(sin(float(k + 1) * PI * 0.5))
			var v0 := g.vert(e0, out, fab, Vector2(float(k) * 0.3, 0))
			var v1 := g.vert(e1, out, fab, Vector2(float(k + 1) * 0.3, 0))
			var v2 := g.vert(e1 - Vector3(0, d1, 0), out, fab, Vector2(float(k + 1) * 0.3, d1))
			var v3 := g.vert(e0 - Vector3(0, d0, 0), out, fab, Vector2(float(k) * 0.3, d0))
			g.quad(v0, v1, v2, v3, out)
			var w0 := g.vert(e0 - out * 0.008, -out, under)
			var w1 := g.vert(e1 - out * 0.008, -out, under)
			var w2 := g.vert(e1 - out * 0.008 - Vector3(0, d1, 0), -out, under)
			var w3 := g.vert(e0 - out * 0.008 - Vector3(0, d0, 0), -out, under)
			g.quad(w0, w3, w2, w1, -out)
	# A six-foot table of goods under it, toward the back.
	YardSaleKit.table6_into(g, goods, Vector3(0, 0, 0.35))
	# A weight bag on each front leg.
	for sx: float in [-1.0, 1.0]:
		BackyardKit.box(g, Transform3D(Basis(), Vector3(sx * h, 0.09, -h - 0.06)), Vector3(0.14, 0.16, 0.09), black)


# --- The blanket of things on the lawn -------------------------------------------------------------

## A blanket spread on the lawn with what does not go on a table.
static func blanket(g: BackyardKit.G, v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["ys_blanket", v])
	# A patchwork quilt or a striped beach blanket, a hair over the grass, its edges turned.
	var nx := 6
	var nz := 4
	var pal := [Color(0.62, 0.16, 0.14), Color(0.86, 0.8, 0.62), Color(0.18, 0.28, 0.5), Color(0.32, 0.46, 0.3),
		Color(0.8, 0.55, 0.2), Color(0.5, 0.3, 0.42)]
	for i in nx:
		for k in nz:
			var c: Color = pal[(i + k * 2 + v) % pal.size()] if v == 0 else pal[(i + v) % pal.size()]
			var x0 := -BLANKET.x * 0.5 + BLANKET.x * float(i) / float(nx)
			var z0 := -BLANKET.y * 0.5 + BLANKET.y * float(k) / float(nz)
			var sx := BLANKET.x / float(nx)
			var sz := BLANKET.y / float(nz)
			var y := 0.012 + 0.004 * rng.randf()
			BackyardKit.box(g, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.01, 0.01)), Vector3(x0 + sx * 0.5, y, z0 + sz * 0.5)), Vector3(sx, 0.006, sz), YardSaleKit.col(c, YardSaleKit.K_PAINT))
	# What is on it, in loose rows.
	var things := ["shoes", "toolbox", "cooler", "records", "rug", "golf", "frames", "shoes", "lamp", "games"]
	for i in range(things.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = things[i]
		things[i] = things[j]
		things[j] = t
	var spots := [Vector3(-0.62, 0, -0.35), Vector3(0.0, 0, -0.38), Vector3(0.62, 0, -0.32), Vector3(-0.6, 0, 0.25),
		Vector3(0.02, 0, 0.3), Vector3(0.6, 0, 0.28)]
	for s in spots.size():
		var p: Vector3 = spots[s] + Vector3(rng.randf_range(-0.06, 0.06), 0.018, rng.randf_range(-0.05, 0.05))
		_thing(g, String(things[s]), p, rng)


static func _thing(g: BackyardKit.G, k: String, p: Vector3, rng: RandomNumberGenerator) -> void:
	var yaw := rng.randf_range(-0.4, 0.4)
	match k:
		"shoes":
			for i in 2:
				var c := YardSaleKit.col(YardSaleKit._hue(rng, 0.4, 0.5) if rng.randf() < 0.6 else Color(0.08, 0.08, 0.08), YardSaleKit.K_GLOSS)
				var q := p + Vector3((float(i) - 0.5) * 0.2, 0, rng.randf_range(-0.05, 0.05))
				for f in 2:
					var b := Basis(Vector3.UP, yaw + rng.randf_range(-0.1, 0.1))
					var fq := q + b * Vector3((float(f) - 0.5) * 0.1, 0, 0)
					BackyardKit.box(g, Transform3D(b, fq + Vector3(0, 0.045, 0)), Vector3(0.09, 0.08, 0.27), c)
					BackyardKit.box(g, Transform3D(b, fq + Vector3(0, 0.012, 0)), Vector3(0.095, 0.024, 0.28), YardSaleKit.col(Color(0.88, 0.86, 0.82), YardSaleKit.K_RUBBER))
		"toolbox":
			var c := YardSaleKit.col(Color(0.7, 0.08, 0.06) if rng.randf() < 0.6 else Color(0.1, 0.22, 0.5), YardSaleKit.K_PAINT)
			var b := Basis(Vector3.UP, yaw)
			BackyardKit.box(g, Transform3D(b, p + Vector3(0, 0.11, 0)), Vector3(0.48, 0.22, 0.24), c)
			BackyardKit.box(g, Transform3D(b, p + Vector3(0, 0.225, 0)), Vector3(0.49, 0.012, 0.25), YardSaleKit.col(Color(0.5, 0.06, 0.05), YardSaleKit.K_PAINT))
			BackyardKit.cyl(g, p + b * Vector3(-0.12, 0.235, 0), p + b * Vector3(0.12, 0.235, 0), 0.012, 0.012, 6, YardSaleKit.col(Color(0.1, 0.1, 0.1), YardSaleKit.K_RUBBER))
		"cooler":
			var b := Basis(Vector3.UP, yaw)
			var body := YardSaleKit.col(Color(0.9, 0.9, 0.88) if rng.randf() < 0.5 else Color(0.16, 0.36, 0.62), YardSaleKit.K_GLOSS)
			BackyardKit.box(g, Transform3D(b, p + Vector3(0, 0.17, 0)), Vector3(0.58, 0.34, 0.36), body)
			BackyardKit.box(g, Transform3D(b, p + Vector3(0, 0.36, 0)), Vector3(0.6, 0.05, 0.38), YardSaleKit.col(Color(0.92, 0.92, 0.9), YardSaleKit.K_GLOSS))
		"records":
			YardSaleKit._open_box(g, p, Vector3(0.36, 0.2, 0.34), rng, "records")
		"rug":
			var b := Basis(Vector3.UP, yaw + PI * 0.5)
			var c := YardSaleKit.col(YardSaleKit._hue(rng, 0.55, 0.5), YardSaleKit.K_PAINT)
			BackyardKit.cyl(g, p + b * Vector3(-0.45, 0.075, 0), p + b * Vector3(0.45, 0.075, 0), 0.075, 0.075, 10, c)
		"golf":
			var b := Basis(Vector3.UP, yaw)
			# The bag lying on its side, three club heads out of the top.
			var bag := YardSaleKit.col(Color(0.12, 0.12, 0.14) if rng.randf() < 0.5 else Color(0.55, 0.12, 0.1), YardSaleKit.K_PAINT)
			BackyardKit.cyl(g, p + b * Vector3(-0.42, 0.11, 0), p + b * Vector3(0.35, 0.11, 0), 0.11, 0.12, 10, bag)
			for i in 3:
				var o := Vector3(0.35, 0.11, (float(i) - 1.0) * 0.05)
				BackyardKit.cyl(g, p + b * o, p + b * (o + Vector3(0.28, 0.02 * float(i), 0)), 0.006, 0.006, 4, YardSaleKit.col(Color(0.7, 0.7, 0.72), YardSaleKit.K_CHROME), false)
				BackyardKit.box(g, Transform3D(b, p + b * (o + Vector3(0.3, 0.02 * float(i), 0))), Vector3(0.06, 0.04, 0.035), YardSaleKit.col(Color(0.3, 0.3, 0.32), YardSaleKit.K_METAL))
		"frames":
			YardSaleKit._good(g, "frames", p, rng)
		"lamp":
			YardSaleKit._good(g, "lamp", p, rng)
		_:
			YardSaleKit._good(g, "games", p, rng)
