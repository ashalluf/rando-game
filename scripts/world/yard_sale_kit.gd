class_name YardSaleKit
extends RefCounted
## What a Los Angeles yard sale puts out, built in code at real size (YardSales places it): the
## six-foot moulded folding table and a card table, each with its goods (household, books and
## records, kitchen; a bare table with closed boxes while the sale is setting up), a rolling rack
## of clothes on hangers, a three-seat sofa, a floor lamp, stacks of moving boxes, the FREE box
## left at the kerb, the hand-lettered poster board on lath stakes with its balloons, and the
## cardboard signs taped to the corner poles (or on a stake in the parkway) with an arrow.
##
## Everything is ONE shader (shaders/yard_sale.gdshader); BackyardKit's builder and primitives
## (G, box, cyl, tube, ellipsoid, sheet) write the vertices, with the codes below in the vertex
## alpha (`code / 16`). Signs are lettered by hand: SignFont's strokes laid out with a wobble per
## glyph (slant, size, baseline) and drawn as marker ribbons. Meshes are cached (static); `warm()`
## builds the fixed ones on the loading screen. Frame of a piece: origin on the ground under its
## middle, its front (the customers' side, a sign's face) toward -Z, except the corner signs,
## whose face is +Z (YardSales turns them to face the cross street).

const K_FIXED := 0
const K_PAINT := 1
const K_FABRIC := 2
const K_METAL := 3
const K_GLOSS := 4
const K_CARD := 5
const K_PAPER := 6
const K_INK := 7
const K_CLOTH := 8
const K_HDPE := 9
const K_WOOD := 10
const K_CHROME := 11
const K_LATEX := 12
const K_RUBBER := 13
const K_SHADE := 14
const K_TAG := 15

## The table tops' heights (m).
const TABLE6_TOP := 0.74
const CARD_TOP := 0.71
## Sign boards: [colour, code] - kraft cardboard, fluorescent pink, fluorescent lime, white.
const BOARDS := [[Color(0.66, 0.5, 0.33), K_CARD], [Color(0.98, 0.38, 0.62), K_PAPER], [Color(0.78, 0.95, 0.3), K_PAPER], [Color(0.95, 0.95, 0.93), K_PAPER]]
## Marker inks: black, red, blue, green.
const INKS := [Color(0.04, 0.04, 0.05), Color(0.72, 0.06, 0.06), Color(0.06, 0.16, 0.55), Color(0.05, 0.32, 0.12)]
const KRAFT := Color(0.64, 0.49, 0.33)
const TAPE := Color(0.72, 0.6, 0.42)
const TAG_COLORS := [Color(1.0, 0.45, 0.1), Color(0.55, 1.0, 0.2), Color(1.0, 0.95, 0.2), Color(1.0, 0.3, 0.6)]

static var _meshes := {}
static var _material: ShaderMaterial = null


static func col(srgb: Color, code: int) -> Color:
	return BackyardKit.col(srgb, code)


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/yard_sale.gdshader")
	return _material


static func _cached(key: String, maker: Callable) -> Mesh:
	if not _meshes.has(key):
		var m: Mesh = maker.call()
		m.resource_name = key
		_meshes[key] = m
	return _meshes[key]


## The fixed kinds (the signs are made per text when a sale needs them).
const KINDS := ["table6_0", "table6_1", "table6_2", "table6_bare", "card_0", "card_1", "card_2", "card_bare",
	"rack", "sofa", "boxes_0", "boxes_1", "floor_lamp", "balloons", "free_box"]


static func warm() -> Array:
	for k: String in KINDS:
		get_mesh(k)
	return [material()]


static func get_mesh(kind: String) -> Mesh:
	match kind:
		"table6_0", "table6_1", "table6_2", "table6_bare":
			return _cached(kind, _table6.bind(kind.trim_prefix("table6_")))
		"card_0", "card_1", "card_2", "card_bare":
			return _cached(kind, _card.bind(kind.trim_prefix("card_")))
		"rack":
			return _cached(kind, _rack)
		"sofa":
			return _cached(kind, _sofa)
		"boxes_0", "boxes_1":
			return _cached(kind, _boxes.bind(int(kind.trim_prefix("boxes_"))))
		"floor_lamp":
			return _cached(kind, _floor_lamp)
		"balloons":
			return _cached(kind, _balloons)
		"free_box":
			return _cached(kind, _free_box)
	push_error("YardSaleKit: no mesh %s" % kind)
	return null


## A parked cruiser's instance custom (MicroMesh's shader: paint rgb, wear a).
static func bike_paint(i: int) -> Color:
	var p: Array = MicroMesh.PAINTS[MicroMesh.Kind.CRUISER]
	var c: Color = p[i % p.size()]
	return Color(c.r, c.g, c.b, 0.55)


# --- Tables ---------------------------------------------------------------------------------------

## The six-foot moulded table: a white HDPE top with its rolled edge, two folding leg frames of
## grey steel tube with their braces; and the goods on it.
static func _table6(goods: String) -> Mesh:
	var g := BackyardKit.G.new()
	var top := col(Color(0.9, 0.9, 0.87), K_HDPE)
	var steel := col(Color(0.5, 0.51, 0.52), K_METAL)
	var t := TABLE6_TOP
	BackyardKit.box(g, Transform3D(Basis(), Vector3(0, t - 0.022, 0)), Vector3(1.83, 0.044, 0.76), top)
	# The rolled skirt under the edge.
	for s: float in [-1.0, 1.0]:
		BackyardKit.box(g, Transform3D(Basis(), Vector3(0, t - 0.06, s * 0.36)), Vector3(1.8, 0.035, 0.03), top)
		BackyardKit.box(g, Transform3D(Basis(), Vector3(s * 0.895, t - 0.06, 0)), Vector3(0.03, 0.035, 0.7), top)
	# Two leg frames, each a U of tube, raked a little; a brace back to a centre rail.
	for s: float in [-1.0, 1.0]:
		var x := s * 0.7
		for z: float in [-0.3, 0.3]:
			BackyardKit.cyl(g, Vector3(x + s * 0.06, 0.012, z), Vector3(x, t - 0.08, z), 0.0125, 0.0125, 6, steel, false)
			BackyardKit.cyl(g, Vector3(x + s * 0.06, 0.0, z), Vector3(x + s * 0.06, 0.025, z), 0.016, 0.016, 6, col(Color(0.12, 0.12, 0.12), K_RUBBER))
		BackyardKit.cyl(g, Vector3(x + s * 0.05, 0.12, -0.3), Vector3(x + s * 0.05, 0.12, 0.3), 0.011, 0.011, 5, steel, false)
		BackyardKit.cyl(g, Vector3(x, t - 0.08, -0.3), Vector3(x, t - 0.08, 0.3), 0.011, 0.011, 5, steel, false)
		BackyardKit.cyl(g, Vector3(x + s * 0.03, 0.4, 0.0), Vector3(s * 0.25, t - 0.085, 0.0), 0.009, 0.009, 5, steel, false)
	BackyardKit.cyl(g, Vector3(-0.25, t - 0.085, 0), Vector3(0.25, t - 0.085, 0), 0.01, 0.01, 5, steel, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["ys_table6", goods])
	_goods(g, goods, Vector2(1.7, 0.66), t, rng)
	return g.mesh(material())


## A card table: a square vinyl-padded top on four folding legs.
static func _card(goods: String) -> Mesh:
	var g := BackyardKit.G.new()
	var t := CARD_TOP
	var vinyl: Color = [Color(0.16, 0.12, 0.09), Color(0.1, 0.2, 0.14), Color(0.18, 0.18, 0.2)][absi(hash(goods)) % 3]
	BackyardKit.box(g, Transform3D(Basis(), Vector3(0, t - 0.02, 0)), Vector3(0.86, 0.04, 0.86), col(vinyl, K_GLOSS))
	BackyardKit.box(g, Transform3D(Basis(), Vector3(0, t - 0.05, 0)), Vector3(0.84, 0.035, 0.84), col(Color(0.08, 0.08, 0.08), K_PAINT))
	var steel := col(Color(0.1, 0.1, 0.1), K_PAINT)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			BackyardKit.cyl(g, Vector3(sx * 0.37, 0.0, sz * 0.37), Vector3(sx * 0.38, t - 0.06, sz * 0.38), 0.011, 0.011, 5, steel, false)
			BackyardKit.cyl(g, Vector3(sx * 0.37, 0.0, sz * 0.37), Vector3(sx * 0.37, 0.02, sz * 0.37), 0.014, 0.014, 5, col(Color(0.1, 0.1, 0.1), K_RUBBER))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["ys_card", goods])
	_goods(g, goods, Vector2(0.76, 0.74), t, rng)
	return g.mesh(material())


## The goods on a table top `size` (x along, z across) at height `t`: laid out along x in slots.
static func _goods(g: BackyardKit.G, goods: String, size: Vector2, t: float, rng: RandomNumberGenerator) -> void:
	var list: Array = []
	match goods:
		"0":
			list = ["open_box", "lamp", "plates", "mugs", "vase", "toaster", "books", "frames"]
		"1":
			list = ["records", "book_box", "games", "radio", "books", "frames", "vase"]
		"2":
			list = ["pots", "blender", "jars", "basket", "plates", "fan", "mugs"]
		_:
			list = ["closed_box", "closed_box", "open_box"]
	# Shuffle by the stream, then fit as many as the table takes.
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = list[i]
		list[i] = list[j]
		list[j] = tmp
	var x := -size.x * 0.5
	for k: String in list:
		var w := _good_width(k)
		if x + w > size.x * 0.5:
			continue
		var z := rng.randf_range(-0.12, 0.08) * size.y
		_good(g, k, Vector3(x + w * 0.5, t, z), rng)
		x += w + rng.randf_range(0.02, 0.08)


static func _good_width(k: String) -> float:
	match k:
		"open_box", "closed_box", "book_box", "records":
			return 0.44
		"lamp", "fan":
			return 0.32
		"plates", "vase", "jars", "blender":
			return 0.24
		"mugs", "toaster", "pots", "basket", "radio":
			return 0.3
		"books":
			return 0.34
		"games":
			return 0.36
		"frames":
			return 0.3
	return 0.3


## A small fluorescent price sticker at `p` on a face looking along `n`.
static func _sticker(g: BackyardKit.G, p: Vector3, n: Vector3, rng: RandomNumberGenerator) -> void:
	var c := col(TAG_COLORS[rng.randi() % TAG_COLORS.size()], K_TAG)
	var a := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized() * 0.011
	var b := n.cross(a).normalized() * 0.011
	var o := p + n * 0.0015
	var i0 := g.vert(o - a - b, n, c)
	var i1 := g.vert(o + a - b, n, c)
	var i2 := g.vert(o + a + b, n, c)
	var i3 := g.vert(o - a + b, n, c)
	g.quad(i0, i1, i2, i3, n)


static func _hue(rng: RandomNumberGenerator, sat: float = 0.5, val: float = 0.6) -> Color:
	return Color.from_hsv(rng.randf(), sat * rng.randf_range(0.5, 1.0), val * rng.randf_range(0.6, 1.1))


## One thing on a table at `p` (its foot).
static func _good(g: BackyardKit.G, k: String, p: Vector3, rng: RandomNumberGenerator) -> void:
	var front := Vector3(0, 0, -1)
	match k:
		"open_box", "book_box", "records":
			var sz := Vector3(0.42, 0.26 if k != "records" else 0.2, 0.32 if k != "records" else 0.34)
			_open_box(g, p, sz, rng, k)
			_sticker(g, p + Vector3(0.1, sz.y * 0.6, -sz.z * 0.5), front, rng)
		"closed_box":
			_closed_box(g, p, Vector3(0.42, 0.3, 0.32), rng.randf_range(-0.15, 0.15))
		"lamp":
			var c := col(_hue(rng, 0.4, 0.7), K_GLOSS)
			BackyardKit.ellipsoid(g, p + Vector3(0, 0.12, 0), Vector3(0.09, 0.12, 0.09), 6, 12, c)
			BackyardKit.cyl(g, p + Vector3(0, 0.22, 0), p + Vector3(0, 0.4, 0), 0.009, 0.009, 6, col(Color(0.7, 0.6, 0.35), K_CHROME))
			BackyardKit.cyl(g, p + Vector3(0, 0.33, 0), p + Vector3(0, 0.55, 0), 0.16, 0.1, 16, col(Color(0.9, 0.86, 0.76), K_SHADE))
			BackyardKit.cyl(g, p + Vector3(0, 0.55, 0), p + Vector3(0, 0.33, 0), 0.098, 0.155, 16, col(Color(0.75, 0.72, 0.64), K_SHADE), false)
			_sticker(g, p + Vector3(0, 0.12, -0.09), front, rng)
		"plates":
			var c := col(Color(0.92, 0.91, 0.87) if rng.randf() < 0.6 else _hue(rng, 0.3, 0.8), K_GLOSS)
			var n := rng.randi_range(4, 8)
			for i in n:
				BackyardKit.cyl(g, p + Vector3(0, 0.012 * i, 0), p + Vector3(0, 0.012 * i + 0.011, 0), 0.115, 0.13, 16, c)
		"mugs":
			for i in 4:
				var q := p + Vector3((float(i % 2) - 0.5) * 0.12, 0.0, (float(i >> 1) - 0.5) * 0.12)
				var c := col(_hue(rng, 0.5, 0.8), K_GLOSS)
				BackyardKit.cyl(g, q, q + Vector3(0, 0.095, 0), 0.042, 0.045, 12, c)
				BackyardKit.tube(g, [q + Vector3(0.045, 0.075, 0), q + Vector3(0.072, 0.06, 0), q + Vector3(0.072, 0.035, 0), q + Vector3(0.045, 0.022, 0)], 0.007, 4, c)
		"vase":
			var c := col(_hue(rng, 0.6, 0.6), K_GLOSS)
			BackyardKit.cyl(g, p, p + Vector3(0, 0.08, 0), 0.05, 0.085, 12, c, false)
			BackyardKit.cyl(g, p + Vector3(0, 0.08, 0), p + Vector3(0, 0.22, 0), 0.085, 0.04, 12, c, false)
			BackyardKit.cyl(g, p + Vector3(0, 0.22, 0), p + Vector3(0, 0.28, 0), 0.04, 0.05, 12, c, false)
			BackyardKit.cyl(g, p, p + Vector3(0, 0.002, 0), 0.0, 0.05, 12, c)
		"toaster":
			var c := col(Color(0.78, 0.79, 0.8) if rng.randf() < 0.5 else Color(0.62, 0.1, 0.08), K_GLOSS)
			BackyardKit.box(g, Transform3D(Basis(), p + Vector3(0, 0.095, 0)), Vector3(0.27, 0.19, 0.16), c)
			for x: float in [-0.045, 0.045]:
				BackyardKit.box(g, Transform3D(Basis(), p + Vector3(x, 0.19, 0)), Vector3(0.03, 0.004, 0.12), col(Color(0.05, 0.05, 0.05), K_FIXED))
			BackyardKit.box(g, Transform3D(Basis(), p + Vector3(0.11, 0.1, -0.085)), Vector3(0.02, 0.03, 0.012), col(Color(0.06, 0.06, 0.06), K_RUBBER))
			_sticker(g, p + Vector3(-0.06, 0.12, -0.081), front, rng)
		"books":
			var x := -0.16
			while x < 0.15:
				var w := rng.randf_range(0.022, 0.05)
				var h := rng.randf_range(0.18, 0.25)
				var d := rng.randf_range(0.13, 0.17)
				BackyardKit.box(g, Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.03, 0.03)), p + Vector3(x + w * 0.5, h * 0.5, 0)), Vector3(w, h, d), col(_hue(rng, 0.55, 0.55), K_PAPER))
				x += w + 0.002
			_sticker(g, p + Vector3(-0.12, 0.15, -0.08), front, rng)
		"frames":
			for i in 2:
				var q := p + Vector3((float(i) - 0.5) * 0.14, 0, 0.04 * float(i))
				var tilt := Basis(Vector3.RIGHT, 0.28)
				var h := rng.randf_range(0.2, 0.3)
				var w := rng.randf_range(0.16, 0.24)
				var xf := Transform3D(tilt, q + Vector3(0, h * 0.5 * cos(0.28), 0.04))
				BackyardKit.box(g, xf, Vector3(w, h, 0.018), col(Color(0.55, 0.4, 0.2) if rng.randf() < 0.5 else Color(0.1, 0.1, 0.1), K_WOOD))
				BackyardKit.box(g, xf * Transform3D(Basis(), Vector3(0, 0, -0.008)), Vector3(w - 0.04, h - 0.04, 0.004), col(_hue(rng, 0.35, 0.7), K_GLOSS))
		"games":
			var y := 0.0
			for i in rng.randi_range(2, 4):
				var hh := rng.randf_range(0.05, 0.08)
				var sz := Vector3(rng.randf_range(0.26, 0.34), hh, rng.randf_range(0.2, 0.27))
				BackyardKit.box(g, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.15, 0.15)), p + Vector3(0, y + hh * 0.5, 0)), sz, col(_hue(rng, 0.7, 0.75), K_PAPER))
				y += hh
			_sticker(g, p + Vector3(0, y + 0.0, 0), Vector3.UP, rng)
		"radio":
			var c := col(Color(0.08, 0.08, 0.09), K_GLOSS)
			BackyardKit.box(g, Transform3D(Basis(), p + Vector3(0, 0.08, 0)), Vector3(0.3, 0.16, 0.12), c)
			for x: float in [-0.09, 0.09]:
				BackyardKit.cyl(g, p + Vector3(x, 0.08, -0.06), p + Vector3(x, 0.08, -0.062), 0.05, 0.05, 14, col(Color(0.2, 0.2, 0.21), K_METAL))
			BackyardKit.tube(g, [p + Vector3(-0.12, 0.16, 0.03), p + Vector3(-0.12, 0.2, 0.03), p + Vector3(0.12, 0.2, 0.03), p + Vector3(0.12, 0.16, 0.03)], 0.007, 4, col(Color(0.6, 0.6, 0.6), K_CHROME))
		"pots":
			for i in 2:
				var q := p + Vector3((float(i) - 0.5) * 0.15, 0, 0)
				var r := 0.07 + 0.02 * float(i)
				BackyardKit.cyl(g, q, q + Vector3(0, r * 1.1, 0), r, r, 14, col(Color(0.7, 0.71, 0.72), K_METAL))
				BackyardKit.cyl(g, q + Vector3(0, r * 1.1, 0), q + Vector3(0, r * 1.1 + 0.015, 0), r + 0.004, r * 0.3, 14, col(Color(0.6, 0.61, 0.62), K_METAL))
				BackyardKit.cyl(g, q + Vector3(r, r * 0.9, 0), q + Vector3(r + 0.08, r * 0.9, 0), 0.008, 0.008, 4, col(Color(0.06, 0.06, 0.06), K_RUBBER))
		"blender":
			BackyardKit.box(g, Transform3D(Basis(), p + Vector3(0, 0.05, 0)), Vector3(0.16, 0.1, 0.16), col(Color(0.9, 0.9, 0.88), K_GLOSS))
			BackyardKit.cyl(g, p + Vector3(0, 0.1, 0), p + Vector3(0, 0.33, 0), 0.055, 0.075, 12, col(Color(0.62, 0.68, 0.7), K_GLOSS))
			BackyardKit.cyl(g, p + Vector3(0, 0.33, 0), p + Vector3(0, 0.35, 0), 0.078, 0.078, 12, col(Color(0.08, 0.08, 0.08), K_RUBBER))
			_sticker(g, p + Vector3(0, 0.05, -0.081), front, rng)
		"jars":
			for i in 3:
				var q := p + Vector3((float(i) - 1.0) * 0.075, 0, rng.randf_range(-0.03, 0.03))
				var h := rng.randf_range(0.1, 0.18)
				BackyardKit.cyl(g, q, q + Vector3(0, h, 0), 0.032, 0.032, 10, col(Color(0.55, 0.62, 0.58), K_GLOSS))
				BackyardKit.cyl(g, q + Vector3(0, h, 0), q + Vector3(0, h + 0.015, 0), 0.03, 0.03, 10, col(_hue(rng, 0.6, 0.6), K_METAL))
		"basket":
			BackyardKit.cyl(g, p, p + Vector3(0, 0.16, 0), 0.11, 0.14, 14, col(Color(0.62, 0.47, 0.28), K_WOOD), false)
			BackyardKit.cyl(g, p, p + Vector3(0, 0.003, 0), 0.0, 0.11, 14, col(Color(0.5, 0.38, 0.22), K_WOOD))
			BackyardKit.tube(g, [p + Vector3(-0.12, 0.16, 0), p + Vector3(-0.08, 0.28, 0), p + Vector3(0.08, 0.28, 0), p + Vector3(0.12, 0.16, 0)], 0.008, 4, col(Color(0.55, 0.42, 0.25), K_WOOD))
		"fan":
			var c := col(Color(0.9, 0.9, 0.88), K_GLOSS)
			BackyardKit.cyl(g, p, p + Vector3(0, 0.03, 0), 0.11, 0.11, 14, c)
			BackyardKit.cyl(g, p + Vector3(0, 0.03, 0), p + Vector3(0, 0.25, 0), 0.015, 0.015, 6, c, false)
			BackyardKit.torus(g, p + Vector3(0, 0.38, 0), 0.15, 0.008, 20, 4, col(Color(0.85, 0.85, 0.85), K_CHROME), 1)
			var hub := p + Vector3(0, 0.38, 0)
			for i in 3:
				var a := TAU * float(i) / 3.0
				var tip := hub + Vector3(cos(a), sin(a), 0) * 0.13
				var i0 := g.vert(hub, front, col(Color(0.5, 0.65, 0.75), K_GLOSS))
				var i1 := g.vert(tip + Vector3(-sin(a), cos(a), 0) * 0.04, front, col(Color(0.5, 0.65, 0.75), K_GLOSS))
				var i2 := g.vert(tip - Vector3(-sin(a), cos(a), 0) * 0.04, front, col(Color(0.5, 0.65, 0.75), K_GLOSS))
				g.tri(i0, i1, i2, front)
				g.tri(i0, i2, i1, -front)


## A kraft box, its four flaps open and splayed, full: the tops of what is in it showing.
static func _open_box(g: BackyardKit.G, p: Vector3, sz: Vector3, rng: RandomNumberGenerator, k: String) -> void:
	var kr := col(KRAFT * rng.randf_range(0.9, 1.08), K_CARD)
	var inside := col(KRAFT * 0.62, K_CARD)
	var h := sz * 0.5
	# Four walls (two faces each: out and in), the floor.
	for side in 4:
		var nrm: Vector3 = [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)][side]
		var len: float = sz.x if side < 2 else sz.z
		var c := p + nrm * (h.z if side < 2 else h.x) + Vector3(0, h.y, 0)
		var tang := nrm.cross(Vector3.UP).normalized()
		var a := c - tang * len * 0.5 - Vector3(0, h.y, 0)
		var b := c + tang * len * 0.5 - Vector3(0, h.y, 0)
		var a2 := a + Vector3(0, sz.y, 0)
		var b2 := b + Vector3(0, sz.y, 0)
		for face in 2:
			var nn := nrm if face == 0 else -nrm
			var cl := kr if face == 0 else inside
			var off := nn * 0.002
			g.quad(g.vert(a + off, nn, cl, Vector2(0, 0)), g.vert(b + off, nn, cl, Vector2(len, 0)), g.vert(b2 + off, nn, cl, Vector2(len, sz.y)), g.vert(a2 + off, nn, cl, Vector2(0, sz.y)), nn)
		# Its flap, hinged at the top edge, splayed out and down.
		var fl := (sz.z if side < 2 else sz.x) * 0.5 * rng.randf_range(0.85, 1.0)
		var ang := rng.randf_range(0.35, 0.9)
		var d := (nrm * cos(ang) + Vector3.UP * sin(ang)).normalized() * fl
		var fn := tang.cross(d).normalized()
		if fn.dot(Vector3.UP) < 0.0:
			fn = -fn
		for face in 2:
			var nn := fn if face == 0 else -fn
			var cl := inside if face == 0 else kr
			var off := nn * 0.0015
			g.quad(g.vert(a2 + off, nn, cl, Vector2(0, 0)), g.vert(b2 + off, nn, cl, Vector2(len, 0)), g.vert(b2 + d + off, nn, cl, Vector2(len, fl)), g.vert(a2 + d + off, nn, cl, Vector2(0, fl)), nn)
	# What is inside, up to near the rim.
	var fill := p + Vector3(0, sz.y - 0.05, 0)
	match k:
		"records":
			for i in 14:
				var z := -h.z + 0.03 + float(i) * (sz.z - 0.06) / 13.0
				BackyardKit.box(g, Transform3D(Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12)), p + Vector3(0, 0.16, z)), Vector3(sz.x - 0.08, 0.3, 0.006), col(_hue(rng, 0.6, 0.7), K_PAPER))
		"book_box":
			var x := -h.x + 0.03
			while x < h.x - 0.05:
				var w := rng.randf_range(0.025, 0.05)
				BackyardKit.box(g, Transform3D(Basis(), Vector3(p.x + x + w * 0.5, fill.y, p.z)), Vector3(w, 0.1, sz.z - 0.05), col(_hue(rng, 0.55, 0.55), K_PAPER))
				x += w + 0.003
		_:
			for i in 7:
				var q := fill + Vector3(rng.randf_range(-h.x + 0.07, h.x - 0.07), 0, rng.randf_range(-h.z + 0.07, h.z - 0.07))
				if rng.randf() < 0.5:
					BackyardKit.box(g, Transform3D(Basis(Vector3.UP, rng.randf() * PI), q), Vector3(rng.randf_range(0.06, 0.14), rng.randf_range(0.04, 0.09), rng.randf_range(0.06, 0.12)), col(_hue(rng, 0.5, 0.7), K_GLOSS))
				else:
					BackyardKit.cyl(g, q - Vector3(0, 0.03, 0), q + Vector3(0, rng.randf_range(0.0, 0.06), 0), 0.035, 0.035, 8, col(_hue(rng, 0.4, 0.7), K_GLOSS))


## A closed, taped moving box (the tape along the top seam and down both ends).
static func _closed_box(g: BackyardKit.G, p: Vector3, sz: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, sz.y * 0.5, 0))
	BackyardKit.box(g, xf, sz, col(KRAFT, K_CARD))
	var tape := col(TAPE, K_CARD)
	BackyardKit.box(g, xf * Transform3D(Basis(), Vector3(0, sz.y * 0.5 + 0.0008, 0)), Vector3(sz.x + 0.003, 0.0015, 0.05), tape, Vector2(1, 0))
	for s: float in [-1.0, 1.0]:
		BackyardKit.box(g, xf * Transform3D(Basis(), Vector3(s * (sz.x * 0.5 + 0.0008), sz.y * 0.3, 0)), Vector3(0.0015, sz.y * 0.4, 0.05), tape, Vector2(1, 0))
	# The seam between the top flaps, and a scrawled word on the side.
	BackyardKit.box(g, xf * Transform3D(Basis(), Vector3(0, sz.y * 0.5 + 0.0012, 0)), Vector3(sz.x * 0.98, 0.0012, 0.004), col(KRAFT * 0.5, K_FIXED))


# --- The rack, the sofa, the lamp, boxes --------------------------------------------------------

## A rolling garment rack of chrome tube, a dozen things on wire hangers.
static func _rack() -> Mesh:
	var g := BackyardKit.G.new()
	var ch := col(Color(0.8, 0.8, 0.8), K_CHROME)
	var H := 1.55
	for s: float in [-1.0, 1.0]:
		var x := s * 0.72
		BackyardKit.cyl(g, Vector3(x, 0.08, 0), Vector3(x, H, 0), 0.0125, 0.0125, 8, ch, false)
		BackyardKit.cyl(g, Vector3(x, 0.08, -0.26), Vector3(x, 0.08, 0.26), 0.014, 0.014, 8, ch, true)
		for z: float in [-0.25, 0.25]:
			BackyardKit.cyl(g, Vector3(x, 0.08, z), Vector3(x, 0.03, z), 0.006, 0.006, 4, ch, false)
			BackyardKit.cyl(g, Vector3(x - 0.012, 0.03, z), Vector3(x + 0.012, 0.03, z), 0.03, 0.03, 10, col(Color(0.08, 0.08, 0.08), K_RUBBER))
	BackyardKit.cyl(g, Vector3(-0.74, H, 0), Vector3(0.74, H, 0), 0.0125, 0.0125, 8, ch, true)
	BackyardKit.cyl(g, Vector3(-0.72, 0.1, 0), Vector3(0.72, 0.1, 0), 0.011, 0.011, 6, ch, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7181
	var cloth := col(Color.WHITE, K_CLOTH)
	var wire := col(Color(0.7, 0.7, 0.72), K_METAL)
	var x := -0.62
	var part := 0
	while x < 0.62:
		var kind := rng.randi() % 4
		var w := 0.44 if kind != 3 else 0.36
		var top := H - 0.07
		var tilt := rng.randf_range(-0.18, 0.18)
		var b := Basis(Vector3.UP, tilt)
		var o := Vector3(x, 0, 0)
		# The hanger: the hook over the rail, the shoulders.
		BackyardKit.tube(g, [o + Vector3(0, H - 0.02, 0.02), o + Vector3(0, H + 0.025, 0.0), o + Vector3(0, H - 0.01, -0.02), o + Vector3(0, top + 0.02, 0)], 0.002, 3, wire)
		BackyardKit.tube(g, [o + b * Vector3(0, top, -w * 0.5), o + Vector3(0, top + 0.05, 0), o + b * Vector3(0, top, w * 0.5)], 0.0025, 3, wire)
		var tl := o + b * Vector3(0, top, -w * 0.5)
		var tr := o + b * Vector3(0, top, w * 0.5)
		match kind:
			0:
				# A shirt or a tee: the body, the sleeves hanging down its sides.
				var drop := rng.randf_range(0.62, 0.78)
				BackyardKit.sheet(g, tl, tr, Vector3(0, -drop, 0), 3, 4, cloth, float(part), 0.015, 0.5)
				for s: float in [-1.0, 1.0]:
					var e := o + b * Vector3(0.012, top - 0.02, s * (w * 0.5 + 0.005))
					BackyardKit.sheet(g, e, e + b * Vector3(0, -0.02, s * 0.09), Vector3(0, -drop * 0.7, 0), 1, 3, cloth, float(part), 0.0, 0.6)
			1:
				# A dress, flared.
				var drop := rng.randf_range(0.95, 1.15)
				BackyardKit.sheet(g, tl + b * Vector3(0, 0, 0.06), tr - b * Vector3(0, 0, 0.06), Vector3(0, -drop, 0), 3, 5, cloth, float(part), 0.03, 0.8)
				BackyardKit.sheet(g, tl + b * Vector3(0, -drop * 0.55, -0.05), tr + b * Vector3(0, -drop * 0.55, 0.05), Vector3(0, -drop * 0.45, 0), 3, 2, cloth, float(part), 0.02, 1.0)
			2:
				# A jacket: wider, a little stiffer, its sleeves as long as the body.
				var drop := rng.randf_range(0.66, 0.8)
				BackyardKit.sheet(g, tl + b * Vector3(0, 0, -0.03), tr + b * Vector3(0, 0, 0.03), Vector3(0, -drop, 0), 3, 4, cloth, float(part), 0.01, 0.3)
				for s: float in [-1.0, 1.0]:
					var e := o + b * Vector3(0.02, top - 0.03, s * (w * 0.5 + 0.04))
					BackyardKit.sheet(g, e, e + b * Vector3(0, 0, s * 0.11), Vector3(0, -drop * 0.95, 0), 1, 3, cloth, float(part), 0.0, 0.3)
			_:
				# Trousers folded over the hanger's bar.
				var drop := rng.randf_range(0.48, 0.58)
				BackyardKit.tube(g, [tl + Vector3(0, -0.06, 0), tr + Vector3(0, -0.06, 0)], 0.003, 3, wire)
				BackyardKit.sheet(g, tl + Vector3(0.008, -0.06, 0.03), tr + Vector3(0.008, -0.06, -0.03), Vector3(0, -drop, 0), 2, 3, cloth, float(part), 0.01, 0.4)
				BackyardKit.sheet(g, tl + Vector3(-0.008, -0.06, 0.03), tr + Vector3(-0.008, -0.06, -0.03), Vector3(0, -drop * 0.85, 0), 2, 3, cloth, float(part), 0.01, 0.4)
		x += rng.randf_range(0.075, 0.12)
		part += 1
	return g.mesh(material())


## A three-seat sofa (the household's fabric), cushions loose on a frame, wood legs.
static func _sofa() -> Mesh:
	var g := BackyardKit.G.new()
	var fab := col(Color.WHITE, K_FABRIC)
	var dark := col(Color(0.82, 0.82, 0.82), K_FABRIC)
	var W := 2.05
	var D := 0.9
	BackyardKit.box(g, Transform3D(Basis(), Vector3(0, 0.24, 0.02)), Vector3(W - 0.36, 0.2, D - 0.1), dark)
	for i in 3:
		var x := (float(i) - 1.0) * 0.56
		var bx := Transform3D(Basis(Vector3.RIGHT, 0.04), Vector3(x, 0.4, -0.05))
		BackyardKit.box(g, bx, Vector3(0.55, 0.13, 0.68), fab)
		# Back cushions, leaning back.
		var bk := Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(x, 0.66, 0.29))
		BackyardKit.box(g, bk, Vector3(0.55, 0.42, 0.18), fab)
	# The back frame and the arms (rolled tops).
	BackyardKit.box(g, Transform3D(Basis(), Vector3(0, 0.5, 0.4)), Vector3(W - 0.02, 0.62, 0.1), dark)
	for s: float in [-1.0, 1.0]:
		var x := s * (W * 0.5 - 0.1)
		BackyardKit.box(g, Transform3D(Basis(), Vector3(x, 0.36, 0.0)), Vector3(0.2, 0.44, D), dark)
		BackyardKit.cyl(g, Vector3(x, 0.6, -D * 0.5), Vector3(x, 0.6, D * 0.5 - 0.02), 0.11, 0.11, 12, fab)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			BackyardKit.cyl(g, Vector3(sx * (W * 0.5 - 0.08), 0.0, sz * (D * 0.5 - 0.08)), Vector3(sx * (W * 0.5 - 0.08), 0.14, sz * (D * 0.5 - 0.08)), 0.022, 0.03, 8, col(Color(0.36, 0.24, 0.14), K_WOOD))
	return g.mesh(material())


static func _floor_lamp() -> Mesh:
	var g := BackyardKit.G.new()
	var brass := col(Color(0.62, 0.5, 0.3), K_CHROME)
	BackyardKit.cyl(g, Vector3.ZERO, Vector3(0, 0.03, 0), 0.15, 0.14, 18, col(Color(0.12, 0.12, 0.12), K_PAINT))
	BackyardKit.cyl(g, Vector3(0, 0.03, 0), Vector3(0, 1.38, 0), 0.012, 0.012, 8, brass, false)
	BackyardKit.cyl(g, Vector3(0, 1.3, 0), Vector3(0, 1.58, 0), 0.22, 0.17, 20, col(Color(0.92, 0.88, 0.78), K_SHADE))
	BackyardKit.cyl(g, Vector3(0, 1.58, 0), Vector3(0, 1.3, 0), 0.168, 0.218, 20, col(Color(0.78, 0.74, 0.65), K_SHADE), false)
	BackyardKit.tube(g, [Vector3(0, 1.0, 0), Vector3(0.02, 0.6, 0.0), Vector3(0.05, 0.1, 0.03), Vector3(0.3, 0.005, 0.1)], 0.003, 3, col(Color(0.9, 0.9, 0.88), K_RUBBER))
	return g.mesh(material())


## Moving boxes on the ground: two closed ones stacked and an open one beside them; or one open
## one full of things on a plastic storage tote.
static func _boxes(v: int) -> Mesh:
	var g := BackyardKit.G.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["ys_boxes", v])
	if v == 0:
		_closed_box(g, Vector3(-0.22, 0, 0.02), Vector3(0.48, 0.34, 0.4), 0.05)
		_closed_box(g, Vector3(-0.2, 0.34, 0.03), Vector3(0.42, 0.3, 0.34), -0.12)
		_open_box(g, Vector3(0.26, 0, -0.02), Vector3(0.42, 0.32, 0.36), rng, "open_box")
	else:
		var tote := col(Color(0.12, 0.3, 0.55) if rng.randf() < 0.5 else Color(0.85, 0.85, 0.83), K_GLOSS)
		BackyardKit.box(g, Transform3D(Basis(), Vector3(-0.2, 0.15, 0)), Vector3(0.5, 0.3, 0.38), tote)
		BackyardKit.box(g, Transform3D(Basis(), Vector3(-0.2, 0.31, 0)), Vector3(0.54, 0.025, 0.42), col(Color(0.9, 0.9, 0.9), K_GLOSS))
		_open_box(g, Vector3(-0.2, 0.32, 0), Vector3(0.4, 0.28, 0.32), rng, "book_box")
		_closed_box(g, Vector3(0.28, 0, 0.0), Vector3(0.4, 0.4, 0.4), 0.2)
	return g.mesh(material())


## The FREE box at the kerb after the sale: an open box of leftovers with FREE across its front.
static func _free_box() -> Mesh:
	var g := BackyardKit.G.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var sz := Vector3(0.5, 0.36, 0.4)
	_open_box(g, Vector3.ZERO, sz, rng, "open_box")
	var right := Vector3(-1, 0, 0)
	_hand_text(g, "FREE", Vector3(0, sz.y * 0.32, -sz.z * 0.5 - 0.004), right, Vector3.UP, Vector3(0, 0, -1), 0.11, 0.42, 0.016, INKS[0], rng)
	return g.mesh(material())


static func _balloons() -> Mesh:
	var g := BackyardKit.G.new()
	var colors := [Color(0.85, 0.08, 0.1), Color(0.98, 0.82, 0.12), Color(0.12, 0.4, 0.85)]
	var tops := [Vector3(-0.12, 1.78, 0.04), Vector3(0.1, 1.88, -0.03), Vector3(0.02, 1.65, 0.1)]
	var root := Vector3(0, 1.0, 0)
	for i in 3:
		var t: Vector3 = tops[i]
		var w: float = (t.y - root.y) / 1.0
		var c := col(colors[i], K_LATEX)
		# The string: a slack line up to the knot, freer the higher it goes.
		var n := 8
		for k in n:
			var a := root.lerp(t - Vector3(0, 0.18, 0), float(k) / float(n))
			var b := root.lerp(t - Vector3(0, 0.18, 0), float(k + 1) / float(n))
			a.x += sin(float(k) * 0.8) * 0.01
			BackyardKit.cyl(g, a, b, 0.0012, 0.0012, 3, col(Color(0.9, 0.9, 0.9), K_FIXED), false, Vector2(float(i), float(k) / float(n) * w))
		BackyardKit.ellipsoid(g, t, Vector3(0.14, 0.17, 0.14), 8, 14, c, Vector2(float(i), w))
		BackyardKit.cyl(g, t - Vector3(0, 0.185, 0), t - Vector3(0, 0.16, 0), 0.006, 0.014, 6, c, false, Vector2(float(i), w))
	return g.mesh(material())


# --- Signs ------------------------------------------------------------------------------------------

## A tape band round a pole of radius `r` (two: above and below the sign).
static func tape_ring(r: float) -> Mesh:
	return _cached("tape_%d" % int(r * 1000.0), _make_tape.bind(r))


static func _make_tape(r: float) -> Mesh:
	var g := BackyardKit.G.new()
	var c := col(Color(0.62, 0.63, 0.64), K_GLOSS)
	for y: float in [0.16, -0.16]:
		BackyardKit.cyl(g, Vector3(0, y - 0.025, 0), Vector3(0, y + 0.025, 0), r + 0.003, r + 0.003, 14, c, false)
	return g.mesh(material())


## The poster board on its two lath stakes, lettered: headline, days and hours, an arrow to the
## door. Faces -Z.
static func stake_sign(head: String, days: String, board: int, ink: int) -> Mesh:
	var key := "stake_%s_%s_%d_%d" % [head.replace(" ", "_"), days.replace(" ", "_"), board, ink]
	return _cached(key, _make_stake.bind(head, days, board, ink, key))


static func _make_stake(head: String, days: String, board: int, ink: int, key: String) -> Mesh:
	var g := BackyardKit.G.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var lath := col(Color(0.74, 0.6, 0.42), K_WOOD)
	for x: float in [-0.24, 0.24]:
		BackyardKit.box(g, Transform3D(Basis(), Vector3(x, 0.52, 0.012)), Vector3(0.038, 1.04, 0.012), lath)
	var size := Vector2(0.71, 0.56)
	_board(g, Vector3(0, 0.74, 0), size, Vector3(0, 0, -1), board, rng)
	var right := Vector3(-1, 0, 0)
	var face := Vector3(0, 0, -1)
	var o := Vector3(0, 0.74, -0.004)
	var ic: Color = INKS[ink]
	var ic2: Color = INKS[0] if ink != 0 else INKS[1]
	_hand_text(g, head, o + Vector3(0, 0.11, 0), right, Vector3.UP, face, 0.1, size.x - 0.08, 0.017, ic, rng)
	_hand_text(g, days, o + Vector3(0, -0.04, 0), right, Vector3.UP, face, 0.07, size.x - 0.12, 0.012, ic2, rng)
	_arrow(g, o + Vector3(0, -0.17, 0), right, Vector3.UP, face, 0.36, 0.012, ic2, rng)
	return g.mesh(material())


## A cardboard sign for a pole (faces +Z, its back against the pole): the headline over an arrow
## pointing `arrow` (+1 to the reader's right).
static func pole_sign(head: String, arrow: int, board: int, ink: int) -> Mesh:
	var key := "pole_%s_%d_%d_%d" % [head.replace(" ", "_"), arrow, board, ink]
	return _cached(key, _make_pole.bind(head, arrow, board, ink, key))


static func _make_pole(head: String, arrow: int, board: int, ink: int, key: String) -> Mesh:
	var g := BackyardKit.G.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	_pole_face(g, Vector3(0, 0, 0.004), head, arrow, board, ink, rng)
	return g.mesh(material())


## The same sign on a lath stake in the parkway (its foot at the origin).
static func lath_sign(head: String, arrow: int, board: int, ink: int) -> Mesh:
	var key := "lath_%s_%d_%d_%d" % [head.replace(" ", "_"), arrow, board, ink]
	return _cached(key, _make_lath.bind(head, arrow, board, ink, key))


static func _make_lath(head: String, arrow: int, board: int, ink: int, key: String) -> Mesh:
	var g := BackyardKit.G.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	BackyardKit.box(g, Transform3D(Basis(), Vector3(0, 0.55, -0.012)), Vector3(0.038, 1.1, 0.012), col(Color(0.74, 0.6, 0.42), K_WOOD))
	_pole_face(g, Vector3(0, 0.92, 0.0), head, arrow, board, ink, rng)
	return g.mesh(material())


static func _pole_face(g: BackyardKit.G, c: Vector3, head: String, arrow: int, board: int, ink: int, rng: RandomNumberGenerator) -> void:
	var size := Vector2(0.56, 0.36)
	_board(g, c, size, Vector3(0, 0, 1), board, rng)
	var right := Vector3(1, 0, 0)
	var face := Vector3(0, 0, 1)
	var o := c + Vector3(0, 0, 0.004)
	var ic: Color = INKS[ink]
	_hand_text(g, head, o + Vector3(0, 0.05, 0), right, Vector3.UP, face, 0.085, size.x - 0.06, 0.014, ic, rng)
	_arrow(g, o + Vector3(0, -0.09, 0), right * float(arrow), Vector3.UP, face, 0.34, 0.016, ic, rng)


## A price card ("$40", "FREE") taped to a thing (faces -Z).
static func tag_mesh(text: String) -> Mesh:
	var key := "tag_" + text.replace("$", "D")
	return _cached(key, _make_tag.bind(text, key))


static func _make_tag(text: String, key: String) -> Mesh:
	var g := BackyardKit.G.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var c := col(Color(0.96, 0.96, 0.92), K_PAPER)
	BackyardKit.box(g, Transform3D(), Vector3(0.2, 0.13, 0.002), c)
	var dollar := text.begins_with("$")
	var t := text.trim_prefix("$")
	var o := Vector3(0.02 if dollar else 0.0, -0.005, -0.0015)
	_hand_text(g, t, o, Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.065, 0.16, 0.009, INKS[1], rng)
	if dollar:
		# A dollar sign, which SignFont has no glyph for: its S with a bar through it.
		var s0 := o + Vector3(0.065, 0, 0)
		_hand_text(g, "S", s0, Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.06, 0.05, 0.008, INKS[1], rng)
		_ribbons(g, [PackedVector2Array([Vector2(0.0, -0.04), Vector2(0.0, 0.04)])], s0, Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.006, INKS[1])
	return g.mesh(material())


## The sign's board: a thin slab facing `face`, its colour BOARDS[board].
static func _board(g: BackyardKit.G, c: Vector3, size: Vector2, face: Vector3, board: int, rng: RandomNumberGenerator) -> void:
	var b: Array = BOARDS[board]
	var cl := col(b[0], int(b[1]))
	var xf := Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.025, 0.025)), c)
	BackyardKit.box(g, xf, Vector3(size.x, size.y, 0.004), cl)
	# The kraft's corrugated edge shows darker on a cardboard sign.
	if board == 0:
		BackyardKit.box(g, xf * Transform3D(Basis(), Vector3(0, -size.y * 0.5 + 0.004, face.z * 0.0022)), Vector3(size.x, 0.008, 0.001), col(Color(0.5, 0.37, 0.24), K_CARD))


## Hand lettering: `text` centred at `o` in the plane (right, up), facing `face`, cap height `cap`
## (shrunk to fit `width`), a marker `pen` wide. Each glyph slants, sizes and sits a little off the
## line on its own; the line drifts.
static func _hand_text(g: BackyardKit.G, text: String, o: Vector3, right: Vector3, up: Vector3, face: Vector3, cap: float, width: float, pen: float, ink: Color, rng: RandomNumberGenerator) -> void:
	var glyphs: Array = []
	var x := 0.0
	for i in text.length():
		var gl := SignFont.glyph(text[i])
		var strokes: Array = gl[0]
		var w: float = gl[1]
		if strokes.is_empty():
			x += SignFont.SPACE
			continue
		glyphs.append([strokes, x, w])
		x += w + SignFont.TRACKING + 0.08
	var total := maxf(x - SignFont.TRACKING - 0.08, 0.01)
	var s := minf(cap, width / total)
	var drift := rng.randf_range(-0.04, 0.04)
	for gd: Array in glyphs:
		var gx: float = gd[1]
		var gw: float = gd[2]
		var rot := rng.randf_range(-0.09, 0.09)
		var sc := rng.randf_range(0.9, 1.1)
		var dy := rng.randf_range(-0.05, 0.05) + drift * (gx / total - 0.5)
		var pivot := Vector2(gw * 0.5, 0.5)
		var strokes: Array = []
		for st: PackedVector2Array in gd[0]:
			var pts := PackedVector2Array()
			for p: Vector2 in st:
				var q := (p - pivot).rotated(rot) * sc + pivot
				pts.append(Vector2((gx + q.x - total * 0.5) * s, (q.y - 0.5 + dy) * s))
			strokes.append(pts)
		_ribbons(g, strokes, o, right, up, face, pen, ink)


## An arrow `length` long along `dir` (in the sign's plane) from `o`'s left to right, hand drawn.
static func _arrow(g: BackyardKit.G, o: Vector3, dir: Vector3, up: Vector3, face: Vector3, length: float, pen: float, ink: Color, rng: RandomNumberGenerator) -> void:
	var h := length * 0.5
	var wob := rng.randf_range(-0.015, 0.015)
	var shaft := PackedVector2Array([Vector2(-h, wob), Vector2(0.0, -wob * 0.5), Vector2(h, wob * 0.3)])
	var head := PackedVector2Array([Vector2(h - 0.07, 0.06 + wob), Vector2(h + 0.005, wob * 0.3), Vector2(h - 0.07, -0.055 + wob)])
	_ribbons(g, [shaft, head], o, dir.normalized(), up, face, pen, ink)


## Polylines (in the plane's metres) drawn as marker ribbons `pen` wide a hair in front of `o`.
static func _ribbons(g: BackyardKit.G, strokes: Array, o: Vector3, right: Vector3, up: Vector3, face: Vector3, pen: float, ink: Color) -> void:
	var c := col(ink, K_INK)
	var hp := pen * 0.5
	for st: PackedVector2Array in strokes:
		for i in st.size() - 1:
			var a := st[i]
			var b := st[i + 1]
			var d := b - a
			var L := d.length()
			if L < 1e-5:
				continue
			d /= L
			# Each segment overlaps its neighbours by half a pen: same ink, no seam.
			a -= d * hp
			b += d * hp
			var nrm := Vector2(-d.y, d.x) * hp
			var p := [a + nrm, b + nrm, b - nrm, a - nrm]
			var ids: Array[int] = []
			for k in 4:
				var q: Vector2 = p[k]
				ids.append(g.vert(o + right * q.x + up * q.y + face * 0.0004 * float(i % 3), face, c, q * 2.0))
			g.quad(ids[0], ids[1], ids[2], ids[3], face)
