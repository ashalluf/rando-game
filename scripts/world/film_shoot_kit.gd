class_name FilmShootKit
extends RefCounted
## The film shoot's hardware (FilmShoot), built here in code at real size on one shader
## (shaders/film_shoot.gdshader), with FarmersMarketKit's mesh builder (Geo: the near triangles
## the surface, a coarse level its one LOD and the shadow twin):
## - production trailers: the honeywagon (a row of doors, vents and steps) and cast trailers
##   (doors, windows, an awning rolled up, steps) - white aluminium skin on a chassis with tandem
##   axles, landing legs, roof air conditioners, marker lights;
## - a tow-behind generator; the grip / electric trucks' lift gates and carts (the trucks
##   themselves are the box truck's far body, FilmShootBuild);
## - the catering tent (a 20 x 10 ft frame tent over buffet tables, chafing dishes, urns);
## - the camera dolly on its track (a camera with lens, matte box and monitor on the arm), the
##   camera crane (wheeled base, column, truss arm, counterweights, the remote head and camera);
## - an 18K HMI on a roller stand, the balloon light on a wind-up stand, C-stands with a black
##   flag or a bounce board, video village's monitor cart and director's chairs, the sound cart,
##   apple boxes and road cases, sandbags;
## - the closure: type III barricades, cones, the orange notices on posts and the yellow arrow sign.
##
## What a face is rides in the vertex colour's alpha (code / 20, C_* below), its colour in the rgb
## (sRGB), roughness and metal in UV2. Every piece faces +z (a trailer runs along +x, its doors on
## +z) with its origin on the ground.

const C_FIXED := 0.0
const C_METAL := 2.0
const C_PAINT := 3.0
const C_DUVE := 4.0
const C_CANVAS := 5.0
const C_RUBBER := 6.0
const C_GLASS := 7.0
const C_WOOD := 8.0
const C_HMI := 9.0
const C_BALLOON := 10.0
const C_SCREEN := 11.0
const C_LAMP := 12.0
const C_NOTICE := 13.0
const C_BOUNCE := 14.0
const C_SANDBAG := 15.0
const C_CHROME := 16.0
const C_STRIPE := 17.0
const C_SKIN := 18.0

## The balloon's centre over the ground, and its radii.
const BALLOON_Y := 6.6
const BALLOON_R := Vector3(1.05, 0.8, 1.05)
## The HMI head's height.
const HMI_Y := 3.4
## Trailer body: floor and roof heights.
const TRAILER_FLOOR := 1.0
const TRAILER_ROOF := 3.95

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/film_shoot.gdshader")
	return _material


static func col(rgb: Color, code: float) -> Color:
	return Color(rgb.r, rgb.g, rgb.b, code / 20.0)


static func _finish(g: FarmersMarketKit.Geo, edge: float = 0.06) -> ArrayMesh:
	var mesh := g.commit(edge)
	mesh.surface_set_material(0, material())
	var sh: Variant = PropFactory._shadow_proxies.get(mesh)
	if sh is ArrayMesh:
		(sh as ArrayMesh).surface_set_material(0, material())
	return mesh


# Shared colours.
const ALU := Color(0.78, 0.79, 0.8)
const STEEL := Color(0.42, 0.43, 0.45)
const BLACK := Color(0.035, 0.035, 0.038)
const TYRE := Color(0.05, 0.05, 0.052)
const RM_ALU := Vector2(0.35, 0.9)
const RM_STEEL := Vector2(0.5, 0.85)
const RM_BLACK := Vector2(0.6, 0.15)


## A wheel whose axle runs along `axis` (unit) through `c`: the tyre, its sidewalls, the hub.
static func _wheel(g: FarmersMarketKit.Geo, c: Vector3, axis: Vector3, r: float, w: float, hub: Color = ALU, sides: int = 14) -> void:
	var a := c - axis * w * 0.5
	var b := c + axis * w * 0.5
	g.tube(a, b, r, sides, col(TYRE, C_RUBBER), Vector2(0.9, 0.0))
	var x := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := axis.cross(x).normalized()
	for end: int in [-1, 1]:
		var cc := c + axis * w * 0.5 * float(end)
		var face := axis * float(end)
		for k in sides:
			var t0 := TAU * float(k) / sides
			var t1 := TAU * float(k + 1) / sides
			var p0 := cc + (x * cos(t0) + z * sin(t0)) * r
			var p1 := cc + (x * cos(t1) + z * sin(t1)) * r
			var q0 := cc + (x * cos(t0) + z * sin(t0)) * r * 0.62
			var q1 := cc + (x * cos(t1) + z * sin(t1)) * r * 0.62
			g.quad(q0, p0, p1, q1, face, col(TYRE, C_RUBBER), Vector2(0.9, 0.0))
			g.tri(cc + face * 0.01, q0 + face * 0.01, q1 + face * 0.01, face, col(hub, C_METAL), RM_ALU)


static func _caster(g: FarmersMarketKit.Geo, at: Vector3, r: float) -> void:
	g.mode = 1
	g.bar(at + Vector3(0, r, 0), at + Vector3(0, r * 2.6, 0), 0.03, col(STEEL, C_METAL), RM_STEEL)
	_wheel(g, at + Vector3(0, r, 0), Vector3(0, 0, 1), r, r * 0.6, STEEL, 10)
	g.mode = 0


# --- Basecamp ------------------------------------------------------------------------------------

## A production trailer `length` m long (along +x, the front at +x), its doors on +z: the
## honeywagon (`honey` true: a row of six doors, each with its step and number) or a cast trailer.
static func trailer(length: float, honey: bool) -> ArrayMesh:
	var key := "trailer_%.1f_%s" % [length, honey]
	if _meshes.has(key):
		return _meshes[key]
	var g := FarmersMarketKit.Geo.new()
	var w := 2.55
	var hw := w * 0.5
	var hl := length * 0.5
	var y0 := TRAILER_FLOOR
	var y1 := TRAILER_ROOF
	var skin := col(Color(0.92, 0.92, 0.9), C_SKIN)
	var rm_skin := Vector2(0.38, 0.35)
	var ch := 0.22
	# The body: an octagon in plan (chamfered corners), sides, roof and floor.
	var plan_pts: Array[Vector2] = [Vector2(hl - ch, -hw), Vector2(hl, -hw + ch), Vector2(hl, hw - ch), Vector2(hl - ch, hw),
		Vector2(-hl + ch, hw), Vector2(-hl, hw - ch), Vector2(-hl, -hw + ch), Vector2(-hl + ch, -hw)]
	for i in plan_pts.size():
		var a := plan_pts[i]
		var b := plan_pts[(i + 1) % plan_pts.size()]
		var out := Vector3((a + b).x, 0.0, (a + b).y).normalized()
		var d := b - a
		out = Vector3(d.y, 0.0, -d.x).normalized()
		g.quad(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), out, skin, rm_skin)
	# Roof (slightly crowned) and floor.
	var roof := col(Color(0.86, 0.86, 0.84), C_FIXED)
	for i in range(1, plan_pts.size() - 1):
		var a := plan_pts[0]
		var b := plan_pts[i]
		var c := plan_pts[i + 1]
		g.tri(Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(c.x, y1, c.y), Vector3.UP, roof, Vector2(0.6, 0.1))
		g.tri(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(c.x, y0, c.y), Vector3.DOWN, col(STEEL, C_FIXED), RM_STEEL)
	# A livery band and the rub rail low on both sides.
	var band := col(Color(0.12, 0.22, 0.38) if not honey else Color(0.3, 0.32, 0.34), C_PAINT)
	for s: float in [-1.0, 1.0]:
		g.box(Transform3D(Basis(), Vector3(0.0, y0 + 0.42, s * (hw + 0.006))), Vector3(length - ch * 2.0, 0.16, 0.012), band, Vector2(0.3, 0.2))
		g.box(Transform3D(Basis(), Vector3(0.0, y0 + 0.05, s * (hw + 0.02))), Vector3(length - 0.1, 0.08, 0.04), col(ALU, C_METAL), RM_ALU)
		g.box(Transform3D(Basis(), Vector3(0.0, y1 - 0.06, s * (hw + 0.012))), Vector3(length - ch * 2.0, 0.06, 0.024), col(ALU, C_METAL), RM_ALU)
	# Doors, steps and windows on the +z side.
	var doors: Array[float] = []
	if honey:
		var n := 6
		for i in n:
			doors.append(lerpf(-hl + 1.1, hl - 1.1, float(i) / float(n - 1)))
	else:
		doors.append(-hl + 1.4)
		doors.append(hl * 0.25)
	var door_c := col(Color(0.85, 0.85, 0.83), C_SKIN)
	var frame := col(ALU, C_METAL)
	var glass := col(Color(0.06, 0.07, 0.08), C_GLASS)
	var zf := hw + 0.012
	for i in doors.size():
		var dx := doors[i]
		# The door leaf a hair proud with its frame, a small window, the handle.
		g.box(Transform3D(Basis(), Vector3(dx, y0 + 1.0, zf)), Vector3(0.78, 1.98, 0.02), door_c, rm_skin)
		g.box(Transform3D(Basis(), Vector3(dx, y0 + 2.02, zf + 0.004)), Vector3(0.86, 0.05, 0.03), frame, RM_ALU)
		g.box(Transform3D(Basis(), Vector3(dx - 0.42, y0 + 1.0, zf + 0.004)), Vector3(0.04, 2.0, 0.03), frame, RM_ALU)
		g.box(Transform3D(Basis(), Vector3(dx + 0.42, y0 + 1.0, zf + 0.004)), Vector3(0.04, 2.0, 0.03), frame, RM_ALU)
		g.box(Transform3D(Basis(), Vector3(dx, y0 + 1.55, zf + 0.006)), Vector3(0.4, 0.5, 0.012), glass, Vector2(0.08, 0.0))
		g.mode = 1
		g.box(Transform3D(Basis(), Vector3(dx + 0.3, y0 + 1.0, zf + 0.03)), Vector3(0.04, 0.16, 0.04), col(Color(0.15, 0.15, 0.16), C_METAL), RM_STEEL)
		g.mode = 0
		# A lamp over the door (lit after dark).
		g.box(Transform3D(Basis(), Vector3(dx, y0 + 2.18, zf + 0.04)), Vector3(0.16, 0.08, 0.08), col(Color(1.0, 0.86, 0.62), C_LAMP), Vector2(0.2, 0.0))
		# Diamond-plate steps: three treads on stringers, a handrail.
		var step := col(Color(0.6, 0.61, 0.62), C_CHROME)
		for k in 3:
			var sy := y0 - 0.25 - 0.25 * k
			g.box(Transform3D(Basis(), Vector3(dx, sy, hw + 0.2 + 0.24 * k)), Vector3(0.82, 0.04, 0.28), step, Vector2(0.4, 0.9))
		g.mode = 1
		for sx: float in [-0.42, 0.42]:
			g.bar(Vector3(dx + sx, y0, hw + 0.06), Vector3(dx + sx, 0.02, hw + 0.84), 0.04, step, Vector2(0.4, 0.9))
		g.tube(Vector3(dx + 0.45, 0.25, hw + 0.84), Vector3(dx + 0.45, y0 + 0.9, hw + 0.2), 0.018, 6, col(ALU, C_METAL), RM_ALU)
		g.mode = 0
		if honey:
			# A vent over each door and the room's number plate.
			g.box(Transform3D(Basis(), Vector3(dx, y1 - 0.35, zf + 0.01)), Vector3(0.34, 0.18, 0.02), col(Color(0.7, 0.7, 0.68), C_METAL), RM_ALU)
	if not honey:
		# Windows between and past the doors, and the rolled awning over them.
		for wx: float in [-hl * 0.45, hl * 0.62, hl * 0.85]:
			if absf(wx - doors[1]) < 1.1 or absf(wx - doors[0]) < 1.1:
				continue
			g.box(Transform3D(Basis(), Vector3(wx, y0 + 1.55, zf + 0.004)), Vector3(1.1, 0.7, 0.02), frame, RM_ALU)
			g.box(Transform3D(Basis(), Vector3(wx, y0 + 1.55, zf + 0.012)), Vector3(1.02, 0.62, 0.012), glass, Vector2(0.08, 0.0))
		g.tube(Vector3(-hl + 0.4, y1 - 0.25, hw + 0.12), Vector3(hl - 1.0, y1 - 0.25, hw + 0.12), 0.09, 10, col(Color(0.2, 0.32, 0.5), C_CANVAS), Vector2(0.8, 0.0))
		# The back: windows on the far side too.
		for wx: float in [-hl * 0.3, hl * 0.4]:
			g.box(Transform3D(Basis(), Vector3(wx, y0 + 1.55, -zf - 0.004)), Vector3(1.1, 0.7, 0.02), frame, RM_ALU)
			g.box(Transform3D(Basis(), Vector3(wx, y0 + 1.55, -zf - 0.012)), Vector3(1.02, 0.62, 0.012), glass, Vector2(0.08, 0.0))
	# Roof air conditioners and a vent per section.
	var nac := 3 if honey else 2
	for i in nac:
		var ax := lerpf(-hl + 1.6, hl - 1.6, (float(i) + 0.5) / float(nac))
		g.box(Transform3D(Basis(), Vector3(ax, y1 + 0.17, 0.0)), Vector3(1.0, 0.34, 0.75), col(Color(0.88, 0.88, 0.86), C_PAINT), Vector2(0.5, 0.0))
		g.mode = 1
		g.box(Transform3D(Basis(), Vector3(ax, y1 + 0.345, 0.0)), Vector3(0.82, 0.012, 0.58), col(Color(0.4, 0.4, 0.4), C_METAL), RM_STEEL)
		g.mode = 0
	# Marker lights at the top corners, tail lights at the back.
	g.mode = 1
	for s: float in [-1.0, 1.0]:
		g.box(Transform3D(Basis(), Vector3(hl - 0.3, y1 - 0.12, s * (hw + 0.02))), Vector3(0.1, 0.05, 0.03), col(Color(1.0, 0.55, 0.08), C_LAMP), Vector2(0.2, 0.0))
		g.box(Transform3D(Basis(), Vector3(-hl - 0.015, y0 + 0.35, s * (hw - 0.3))), Vector3(0.03, 0.12, 0.22), col(Color(0.9, 0.06, 0.04), C_LAMP), Vector2(0.2, 0.0))
	g.mode = 0
	# The chassis: frame rails, tandem axles under the back third, fenders, the landing legs at
	# the front and the gooseneck / tongue.
	var steel := col(STEEL, C_METAL)
	for s: float in [-1.0, 1.0]:
		g.box(Transform3D(Basis(), Vector3(0.0, y0 - 0.12, s * 0.5)), Vector3(length - 0.4, 0.22, 0.1), col(BLACK, C_PAINT), RM_BLACK)
	var axle_x := -hl + length * 0.27
	for k: float in [-0.55, 0.55]:
		for s: float in [-1.0, 1.0]:
			_wheel(g, Vector3(axle_x + k, 0.4, s * (hw - 0.32)), Vector3(0, 0, 1), 0.4, 0.24)
	g.mode = 1
	for k: float in [-0.55, 0.55]:
		g.tube(Vector3(axle_x + k, 0.4, -hw + 0.2), Vector3(axle_x + k, 0.4, hw - 0.2), 0.05, 6, steel, RM_STEEL)
	g.mode = 0
	for s: float in [-1.0, 1.0]:
		g.box(Transform3D(Basis(), Vector3(axle_x, 0.92, s * (hw - 0.05))), Vector3(2.1, 0.06, 0.12), col(ALU, C_CHROME), RM_ALU)
	for s: float in [-1.0, 1.0]:
		g.bar(Vector3(hl - 1.6, y0 - 0.2, s * 0.6), Vector3(hl - 1.6, 0.02, s * 0.6), 0.09, steel, RM_STEEL)
		g.box(Transform3D(Basis(), Vector3(hl - 1.6, 0.02, s * 0.6)), Vector3(0.25, 0.04, 0.25), steel, RM_STEEL)
	g.bar(Vector3(hl - 0.1, y0 - 0.15, 0.0), Vector3(hl + 1.2, 0.55, 0.0), 0.14, col(BLACK, C_PAINT), RM_BLACK)
	g.cyl(Vector3(hl + 1.2, 0.0, 0.0), 0.05, 0.05, 0.55, 8, steel, RM_STEEL)
	# Far level: one box body.
	g.mode = 2
	g.box(Transform3D(Basis(), Vector3(0.0, (y0 + y1) * 0.5, 0.0)), Vector3(length, y1 - y0, w), skin, rm_skin)
	g.box(Transform3D(Basis(), Vector3(axle_x, 0.4, 0.0)), Vector3(1.9, 0.8, w - 0.2), col(TYRE, C_RUBBER), Vector2(0.9, 0.0))
	g.mode = 0
	var mesh := _finish(g, 0.1)
	_meshes[key] = mesh
	return mesh


## The tow-behind generator: a sound-proofed box on two wheels, its louvres, the exhaust stack,
## the tongue (+x) and a jack.
static func genny() -> ArrayMesh:
	if _meshes.has("genny"):
		return _meshes.genny
	var g := FarmersMarketKit.Geo.new()
	var body := col(Color(0.9, 0.9, 0.88), C_PAINT)
	g.box(Transform3D(Basis(), Vector3(0.0, 1.35, 0.0)), Vector3(3.4, 1.55, 1.75), body, Vector2(0.45, 0.1))
	g.box(Transform3D(Basis(), Vector3(0.0, 2.15, 0.0)), Vector3(3.3, 0.06, 1.65), col(Color(0.82, 0.82, 0.8), C_PAINT), Vector2(0.5, 0.1))
	for s: float in [-1.0, 1.0]:
		for i in 6:
			g.box(Transform3D(Basis(), Vector3(-1.2 + i * 0.12, 1.3, s * 0.885)), Vector3(0.06, 0.8, 0.02), col(Color(0.25, 0.25, 0.26), C_METAL), RM_STEEL)
		g.box(Transform3D(Basis(), Vector3(0.7, 1.3, s * 0.885)), Vector3(1.1, 0.9, 0.02), col(Color(0.82, 0.82, 0.8), C_PAINT), Vector2(0.45, 0.1))
		_wheel(g, Vector3(-0.2, 0.36, s * 0.98), Vector3(0, 0, 1), 0.36, 0.22)
		g.box(Transform3D(Basis(), Vector3(-0.2, 0.78, s * 0.98)), Vector3(0.95, 0.05, 0.28), col(BLACK, C_PAINT), RM_BLACK)
	g.box(Transform3D(Basis(), Vector3(0.0, 0.52, 0.0)), Vector3(3.2, 0.12, 1.4), col(BLACK, C_PAINT), RM_BLACK)
	g.cyl(Vector3(-1.1, 2.18, 0.4), 0.07, 0.07, 0.55, 10, col(Color(0.2, 0.2, 0.2), C_METAL), RM_STEEL)
	g.bar(Vector3(1.6, 0.6, 0.0), Vector3(2.7, 0.45, 0.0), 0.1, col(BLACK, C_PAINT), RM_BLACK)
	g.cyl(Vector3(2.4, 0.0, 0.0), 0.04, 0.04, 0.52, 8, col(STEEL, C_METAL), RM_STEEL)
	# Its distribution box (the cables' end) and a warning label.
	g.box(Transform3D(Basis(), Vector3(-1.75, 1.0, 0.0)), Vector3(0.1, 0.6, 1.0), col(Color(0.18, 0.18, 0.2), C_PAINT), RM_BLACK)
	g.box(Transform3D(Basis(), Vector3(0.7, 1.6, 0.9)), Vector3(0.3, 0.2, 0.01), col(Color(0.95, 0.72, 0.1), C_FIXED), Vector2(0.4, 0.0))
	var mesh := _finish(g, 0.06)
	_meshes.genny = mesh
	return mesh


## The back of a grip or electric truck: its lift gate down, carts on the street behind it (a
## C-stand cart, a lighting cart and stacked sandbags). Origin on the ground at the truck's rear
## bumper's centre, +x away from the truck.
static func truck_tail(electric: bool) -> ArrayMesh:
	var key := "tail_%s" % electric
	if _meshes.has(key):
		return _meshes[key]
	var g := FarmersMarketKit.Geo.new()
	var plate := col(Color(0.62, 0.63, 0.64), C_CHROME)
	# The lift gate: a platform at the road, its posts up the doorway.
	g.box(Transform3D(Basis(), Vector3(0.9, 0.04, 0.0)), Vector3(1.8, 0.06, 2.3), plate, Vector2(0.45, 0.9))
	for s: float in [-1.0, 1.0]:
		g.box(Transform3D(Basis(), Vector3(0.1, 0.65, s * 1.08)), Vector3(0.12, 1.2, 0.1), col(STEEL, C_METAL), RM_STEEL)
	# A cart on the gate and one on the street.
	_cart(g, Transform3D(Basis(), Vector3(0.95, 0.07, -0.45)), electric)
	_cart(g, Transform3D(Basis(Vector3.UP, 0.25), Vector3(2.6, 0.0, 0.55)), not electric)
	# Sandbags stacked by the gate.
	for i in 5:
		_sandbag(g, Transform3D(Basis(Vector3.UP, 0.2 * i), Vector3(2.2 + (i % 2) * 0.1, 0.09 + 0.14 * (i / 2), -0.9 + 0.05 * i)))
	var mesh := _finish(g, 0.05)
	_meshes[key] = mesh
	return mesh


## A rolling cart: C-stands racked upright (grip) or cable coils and distro boxes (electric).
static func _cart(g: FarmersMarketKit.Geo, xf: Transform3D, electric: bool) -> void:
	var frame := col(Color(0.2, 0.2, 0.22), C_PAINT)
	g.box(xf * Transform3D(Basis(), Vector3(0, 0.28, 0)), Vector3(1.5, 0.05, 0.75), frame, RM_BLACK)
	for sx: float in [-0.7, 0.7]:
		for sz: float in [-0.33, 0.33]:
			g.bar(xf * Vector3(sx, 0.12, sz), xf * Vector3(sx, 1.2, sz), 0.035, frame, RM_BLACK)
			_caster(g, xf * Vector3(sx, 0.0, sz), 0.06)
	g.bar(xf * Vector3(-0.7, 1.2, 0), xf * Vector3(0.7, 1.2, 0), 0.03, frame, RM_BLACK)
	if electric:
		for i in 3:
			g.cyl(xf * Vector3(-0.42 + i * 0.42, 0.3, 0.0), 0.28, 0.28, 0.22, 14, col(Color(0.05, 0.05, 0.05), C_RUBBER), Vector2(0.75, 0.0))
			g.cyl(xf * Vector3(-0.42 + i * 0.42, 0.52, 0.0), 0.24, 0.24, 0.16, 14, col(Color(0.05, 0.05, 0.05), C_RUBBER), Vector2(0.75, 0.0))
		g.box(xf * Transform3D(Basis(), Vector3(0.2, 0.86, 0.0)), Vector3(0.5, 0.3, 0.4), col(Color(0.12, 0.12, 0.14), C_PAINT), RM_BLACK)
		g.box(xf * Transform3D(Basis(), Vector3(0.2, 0.86, 0.205)), Vector3(0.3, 0.06, 0.01), col(Color(0.9, 0.7, 0.1), C_FIXED), Vector2(0.4, 0.0))
	else:
		for i in 7:
			var x := -0.6 + i * 0.2
			g.bar(xf * Vector3(x, 0.3, -0.15), xf * Vector3(x, 1.75, -0.15), 0.022, col(Color(0.72, 0.73, 0.74), C_CHROME), Vector2(0.3, 0.9))
			g.bar(xf * Vector3(x, 1.75, -0.15), xf * Vector3(x + 0.05, 1.82, 0.25), 0.02, col(Color(0.72, 0.73, 0.74), C_CHROME), Vector2(0.3, 0.9))
		for i in 3:
			_sandbag(g, xf * Transform3D(Basis(), Vector3(-0.4 + i * 0.4, 0.37, 0.2)))


static func _sandbag(g: FarmersMarketKit.Geo, xf: Transform3D) -> void:
	var bag := col(Color(0.22, 0.2, 0.15), C_SANDBAG)
	g.ellipsoid(xf, Vector3(0.24, 0.08, 0.13), 8, 4, bag, Vector2(0.95, 0.0))
	g.mode = 1
	g.tube(xf * Vector3(-0.16, 0.08, 0.0), xf * Vector3(0.16, 0.08, 0.0), 0.012, 4, col(BLACK, C_FIXED), RM_BLACK)
	g.mode = 0


## The catering tent: a 20 x 10 ft frame tent (+z the open long side) over two buffet tables of
## chafing dishes, a coffee station with urns, stacked cups and a cooler.
static func catering() -> ArrayMesh:
	if _meshes.has("catering"):
		return _meshes.catering
	var g := FarmersMarketKit.Geo.new()
	var hx := 3.05
	var hz := 1.525
	var eave := 2.3
	var peak := 3.25
	var canvas := col(Color(0.96, 0.96, 0.94), C_CANVAS)
	var rm_c := Vector2(0.82, 0.0)
	var alu := col(ALU, C_METAL)
	# Legs and the eave frame.
	for sx: float in [-1.0, 0.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.bar(Vector3(sx * hx, 0.0, sz * hz), Vector3(sx * hx, eave, sz * hz), 0.05, alu, RM_ALU)
			g.box(Transform3D(Basis(), Vector3(sx * hx, 0.01, sz * hz)), Vector3(0.18, 0.02, 0.18), col(STEEL, C_METAL), RM_STEEL)
			g.mode = 1
			_sandbag(g, Transform3D(Basis(Vector3.UP, 0.4 * sx), Vector3(sx * hx + 0.12, 0.08, sz * hz)))
			g.mode = 0
	# The roof: a ridge along x, two pitched faces and the hipped ends, a valance.
	var r0 := Vector3(-hx + hz, peak, 0.0)
	var r1 := Vector3(hx - hz, peak, 0.0)
	g.quad(Vector3(-hx, eave, hz), Vector3(hx, eave, hz), r1, r0, Vector3(0, 1, 1), canvas, rm_c)
	g.quad(Vector3(hx, eave, -hz), Vector3(-hx, eave, -hz), r0, r1, Vector3(0, 1, -1), canvas, rm_c)
	g.tri(Vector3(hx, eave, hz), Vector3(hx, eave, -hz), r1, Vector3(1, 1, 0), canvas, rm_c)
	g.tri(Vector3(-hx, eave, -hz), Vector3(-hx, eave, hz), r0, Vector3(-1, 1, 0), canvas, rm_c)
	for sz: float in [-1.0, 1.0]:
		g.quad(Vector3(-hx, eave - 0.25, sz * hz), Vector3(hx, eave - 0.25, sz * hz), Vector3(hx, eave, sz * hz), Vector3(-hx, eave, sz * hz), Vector3(0, 0, sz), canvas, rm_c)
	for sx: float in [-1.0, 1.0]:
		g.quad(Vector3(sx * hx, eave - 0.25, -hz), Vector3(sx * hx, eave - 0.25, hz), Vector3(sx * hx, eave, hz), Vector3(sx * hx, eave, -hz), Vector3(sx, 0, 0), canvas, rm_c)
	# The back wall (a side curtain).
	g.quad(Vector3(-hx, 0.05, -hz), Vector3(hx, 0.05, -hz), Vector3(hx, eave, -hz), Vector3(-hx, eave, -hz), Vector3(0, 0, -1), canvas, rm_c)
	# Buffet tables under black skirting, chafing dishes with their lids, sternos.
	var cloth := col(Color(0.06, 0.06, 0.07), C_DUVE)
	var chrome := col(Color(0.8, 0.81, 0.82), C_CHROME)
	for tx: float in [-1.5, 1.5]:
		g.box(Transform3D(Basis(), Vector3(tx, 0.38, -0.55)), Vector3(2.4, 0.76, 0.76), cloth, Vector2(0.95, 0.0))
		for k in 3:
			var cx := tx - 0.75 + k * 0.75
			g.box(Transform3D(Basis(), Vector3(cx, 0.82, -0.55)), Vector3(0.62, 0.1, 0.38), chrome, Vector2(0.18, 0.95))
			g.ellipsoid(Transform3D(Basis(), Vector3(cx, 0.87, -0.55)), Vector3(0.3, 0.09, 0.18), 10, 4, chrome, Vector2(0.15, 0.95), 0, 0.0, 0.0, PI * 0.5)
			g.mode = 1
			g.box(Transform3D(Basis(), Vector3(cx, 0.97, -0.55)), Vector3(0.1, 0.03, 0.03), col(BLACK, C_FIXED), RM_BLACK)
			g.mode = 0
	# Coffee station at one end: urns, cups, a cooler on the road.
	for k in 2:
		g.cyl(Vector3(2.45, 0.76, -0.9 + k * 0.42), 0.15, 0.15, 0.52, 12, chrome, Vector2(0.2, 0.95))
		g.cyl(Vector3(2.45, 1.28, -0.9 + k * 0.42), 0.15, 0.06, 0.06, 12, col(BLACK, C_PAINT), RM_BLACK)
	g.box(Transform3D(Basis(), Vector3(2.45, 0.38, -0.7)), Vector3(0.75, 0.76, 0.8), cloth, Vector2(0.95, 0.0))
	for k in 3:
		g.cyl(Vector3(2.6, 0.76, -0.25 + k * 0.08), 0.045, 0.045, 0.22, 8, col(Color(0.95, 0.95, 0.93), C_FIXED), Vector2(0.6, 0.0))
	g.box(Transform3D(Basis(), Vector3(-2.4, 0.22, 0.55)), Vector3(0.75, 0.44, 0.45), col(Color(0.12, 0.3, 0.6), C_PAINT), Vector2(0.4, 0.0))
	g.box(Transform3D(Basis(), Vector3(-2.4, 0.46, 0.55)), Vector3(0.78, 0.05, 0.48), col(Color(0.95, 0.95, 0.93), C_PAINT), Vector2(0.4, 0.0))
	# A string of bulbs along the front eave.
	var n := 14
	for k in n:
		var x := lerpf(-hx + 0.2, hx - 0.2, float(k) / float(n - 1))
		g.mode = 1
		g.ellipsoid(Transform3D(Basis(), Vector3(x, eave - 0.32, hz + 0.02)), Vector3(0.03, 0.04, 0.03), 6, 3, col(Color(1.0, 0.82, 0.55), C_LAMP), Vector2(0.15, 0.0))
		g.mode = 0
	var mesh := _finish(g, 0.06)
	_meshes.catering = mesh
	return mesh


# --- The set -------------------------------------------------------------------------------------

## The cinema camera (body along -z behind the lens, the lens along +z): origin at its base plate.
static func _camera(g: FarmersMarketKit.Geo, xf: Transform3D) -> void:
	var body := col(Color(0.08, 0.08, 0.085), C_PAINT)
	var rm := Vector2(0.45, 0.3)
	g.box(xf * Transform3D(Basis(), Vector3(0, 0.03, 0.0)), Vector3(0.22, 0.06, 0.5), col(STEEL, C_METAL), RM_STEEL)
	g.box(xf * Transform3D(Basis(), Vector3(0, 0.2, -0.05)), Vector3(0.16, 0.24, 0.32), body, rm)
	g.box(xf * Transform3D(Basis(), Vector3(0, 0.36, -0.05)), Vector3(0.05, 0.06, 0.24), body, rm)
	# The lens: barrel, focus ring, the front element and the matte box with its flags.
	g.tube(xf * Vector3(0, 0.2, 0.11), xf * Vector3(0, 0.2, 0.36), 0.055, 14, col(Color(0.06, 0.06, 0.06), C_PAINT), rm)
	g.tube(xf * Vector3(0, 0.2, 0.18), xf * Vector3(0, 0.2, 0.24), 0.062, 14, col(Color(0.12, 0.12, 0.12), C_METAL), RM_STEEL)
	g.cyl(xf * Vector3(0, 0.2, 0.36), 0.05, 0.05, 0.0, 12, col(Color(0.05, 0.06, 0.1), C_GLASS), Vector2(0.05, 0.0))
	var mb := xf * Transform3D(Basis(), Vector3(0, 0.2, 0.44))
	for s: float in [-1.0, 1.0]:
		g.box(mb * Transform3D(Basis(), Vector3(s * 0.13, 0.0, 0.0)), Vector3(0.01, 0.2, 0.16), body, rm)
		g.box(mb * Transform3D(Basis(), Vector3(0.0, s * 0.1, 0.0)), Vector3(0.26, 0.01, 0.16), body, rm)
	# The monitor on its arm and the operator's handles.
	g.box(xf * Transform3D(Basis(Vector3.UP, 0.4), Vector3(-0.22, 0.38, -0.05)), Vector3(0.2, 0.13, 0.03), body, rm)
	g.box(xf * Transform3D(Basis(Vector3.UP, 0.4), Vector3(-0.226, 0.38, -0.065)), Vector3(0.18, 0.11, 0.005), col(Color(0.5, 0.55, 0.6), C_SCREEN), Vector2(0.1, 0.0))
	g.mode = 1
	g.bar(xf * Vector3(-0.08, 0.3, -0.05), xf * Vector3(-0.2, 0.35, -0.05), 0.012, col(STEEL, C_METAL), RM_STEEL)
	g.box(xf * Transform3D(Basis(), Vector3(0.0, 0.28, -0.24)), Vector3(0.1, 0.06, 0.08), col(Color(0.06, 0.06, 0.06), C_PAINT), rm)
	g.mode = 0


## The dolly track: two pipe rails on wooden wedges every metre, `length` m along x.
static func track(length: float) -> ArrayMesh:
	var key := "track_%.1f" % length
	if _meshes.has(key):
		return _meshes[key]
	var g := FarmersMarketKit.Geo.new()
	var hl := length * 0.5
	var wood := col(Color(0.66, 0.52, 0.34), C_WOOD)
	var n := int(length) + 1
	for i in n:
		var x := lerpf(-hl + 0.1, hl - 0.1, float(i) / float(n - 1))
		g.box(Transform3D(Basis(), Vector3(x, 0.04, 0.0)), Vector3(0.12, 0.08, 0.9), wood, Vector2(0.85, 0.0))
		g.mode = 1
		g.box(Transform3D(Basis(Vector3.FORWARD, 0.1), Vector3(x + 0.1, 0.03, 0.32)), Vector3(0.1, 0.04, 0.12), wood, Vector2(0.85, 0.0))
		g.mode = 0
	for s: float in [-1.0, 1.0]:
		g.tube(Vector3(-hl, 0.12, s * 0.31), Vector3(hl, 0.12, s * 0.31), 0.024, 8, col(Color(0.78, 0.79, 0.8), C_CHROME), Vector2(0.25, 0.95))
	var mesh := _finish(g, 0.04)
	_meshes[key] = mesh
	return mesh


## The camera dolly on the track: a chassis on track wheels, push bar, the seat, the hydraulic
## arm and the camera on its head, the camera looking along +z.
static func dolly() -> ArrayMesh:
	if _meshes.has("dolly"):
		return _meshes.dolly
	var g := FarmersMarketKit.Geo.new()
	var paint := col(Color(0.08, 0.1, 0.12), C_PAINT)
	var rm := Vector2(0.4, 0.4)
	g.box(Transform3D(Basis(), Vector3(0.0, 0.3, 0.0)), Vector3(1.1, 0.2, 0.68), paint, rm)
	for sx: float in [-0.45, 0.45]:
		for sz: float in [-0.31, 0.31]:
			_wheel(g, Vector3(sx, 0.17, sz), Vector3(0, 0, 1), 0.07, 0.05, STEEL, 10)
	# The arm (a column on a slant) and the head.
	g.bar(Vector3(0.15, 0.4, 0.0), Vector3(0.05, 1.15, 0.0), 0.11, paint, rm)
	g.cyl(Vector3(0.05, 1.15, 0.0), 0.09, 0.07, 0.12, 12, col(STEEL, C_METAL), RM_STEEL)
	g.box(Transform3D(Basis(), Vector3(0.05, 1.33, 0.0)), Vector3(0.2, 0.08, 0.2), col(Color(0.15, 0.15, 0.16), C_METAL), RM_STEEL)
	_camera(g, Transform3D(Basis(), Vector3(0.05, 1.37, 0.0)))
	# Push bar at the back, the seat on its post.
	g.bar(Vector3(-0.55, 0.42, -0.3), Vector3(-0.7, 1.05, -0.3), 0.03, col(STEEL, C_METAL), RM_STEEL)
	g.bar(Vector3(-0.55, 0.42, 0.3), Vector3(-0.7, 1.05, 0.3), 0.03, col(STEEL, C_METAL), RM_STEEL)
	g.tube(Vector3(-0.7, 1.05, -0.3), Vector3(-0.7, 1.05, 0.3), 0.022, 8, col(BLACK, C_RUBBER), Vector2(0.8, 0.0))
	g.bar(Vector3(0.35, 0.4, 0.3), Vector3(0.35, 0.95, 0.3), 0.04, col(STEEL, C_METAL), RM_STEEL)
	g.cyl(Vector3(0.35, 0.95, 0.3), 0.15, 0.15, 0.06, 12, col(BLACK, C_RUBBER), Vector2(0.8, 0.0))
	var mesh := _finish(g, 0.05)
	_meshes.dolly = mesh
	return mesh


## The camera crane: a wheeled base, the column, a truss arm out along +z rising to the remote
## head and camera, the bucket of counterweights at the back.
static func crane() -> ArrayMesh:
	if _meshes.has("crane"):
		return _meshes.crane
	var g := FarmersMarketKit.Geo.new()
	var paint := col(Color(0.12, 0.13, 0.14), C_PAINT)
	var silver := col(Color(0.72, 0.73, 0.74), C_METAL)
	var rm := Vector2(0.45, 0.35)
	# Base: a cross of outriggers on wheels.
	for a in 4:
		var d := Vector3(cos(a * PI * 0.5 + PI * 0.25), 0.0, sin(a * PI * 0.5 + PI * 0.25))
		g.bar(Vector3(0, 0.3, 0), Vector3(0, 0.3, 0) + d * 1.0, 0.1, paint, rm)
		_wheel(g, d * 1.0 + Vector3(0, 0.14, 0), d.cross(Vector3.UP).normalized(), 0.14, 0.08, STEEL, 10)
		g.cyl(d * 0.9, 0.06, 0.06, 0.3, 8, silver, RM_STEEL)
	g.cyl(Vector3(0, 0.25, 0), 0.22, 0.2, 1.25, 14, paint, rm)
	g.cyl(Vector3(0, 1.5, 0), 0.24, 0.24, 0.12, 14, silver, RM_STEEL)
	# The arm: a pivot at (0, 1.75, 0), out 5.4 m along +z, rising 18 degrees; 1.6 m back.
	var pivot := Vector3(0, 1.78, 0)
	var dir := Vector3(0, sin(deg_to_rad(18.0)), cos(deg_to_rad(18.0)))
	var tip := pivot + dir * 5.4
	var tail := pivot - dir * 1.7
	g.box(Transform3D(Basis(), pivot), Vector3(0.36, 0.3, 0.3), silver, RM_STEEL)
	# Truss: four chords and zig-zag lacing, tapering toward the tip.
	var side := Vector3.RIGHT
	var up := dir.cross(side).normalized() * -1.0
	var chords: Array[Vector3] = [Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)]
	var segs := 9
	for c in chords.size():
		var cc := chords[c]
		var a := tail + side * cc.x * 0.14 + up * cc.y * 0.14
		var b := tip + side * cc.x * 0.07 + up * cc.y * 0.07
		g.tube(a, b, 0.02, 6, silver, RM_STEEL)
	g.mode = 1
	for i in segs:
		var f0 := float(i) / segs
		var f1 := float(i + 1) / segs
		for c in chords.size():
			var c0 := chords[c]
			var c1 := chords[(c + 1) % chords.size()]
			var w0 := lerpf(0.14, 0.07, f0)
			var w1 := lerpf(0.14, 0.07, f1)
			var p0 := tail.lerp(tip, f0) + side * c0.x * w0 + up * c0.y * w0
			var p1 := tail.lerp(tip, f1) + side * c1.x * w1 + up * c1.y * w1
			g.tube(p0, p1, 0.011, 4, silver, RM_STEEL)
	g.mode = 2
	g.bar(tail, tip, 0.2, silver, RM_STEEL)
	g.mode = 0
	# The weight bucket and its weights.
	g.box(Transform3D(Basis(), tail + Vector3(0, -0.35, 0)), Vector3(0.45, 0.5, 0.4), paint, rm)
	for k in 4:
		g.box(Transform3D(Basis(), tail + Vector3(0, -0.12 + k * 0.08, 0)), Vector3(0.5, 0.06, 0.45), col(Color(0.35, 0.36, 0.37), C_METAL), RM_STEEL)
	# The remote head (a U yoke) and the camera on it, looking along +z and down a little.
	var head := Transform3D(Basis(), tip + Vector3(0, -0.12, 0.05))
	g.box(head * Transform3D(Basis(), Vector3(0, 0.0, 0)), Vector3(0.36, 0.06, 0.24), paint, rm)
	for s: float in [-1.0, 1.0]:
		g.box(head * Transform3D(Basis(), Vector3(s * 0.17, -0.2, 0)), Vector3(0.04, 0.4, 0.2), paint, rm)
	_camera(g, head * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, -0.45, 0.0)))
	var mesh := _finish(g, 0.06)
	_meshes.crane = mesh
	return mesh


## A three-legged roller stand: legs, wheels, the column to `top` and its riser collars.
static func _stand(g: FarmersMarketKit.Geo, top: float, spread: float, wheels: bool) -> void:
	var steel := col(Color(0.55, 0.56, 0.57), C_METAL)
	var black := col(BLACK, C_PAINT)
	for a in 3:
		var d := Vector3(cos(a * TAU / 3.0), 0.0, sin(a * TAU / 3.0))
		var foot := d * spread + Vector3(0, 0.12 if wheels else 0.02, 0)
		g.bar(Vector3(0, 0.75, 0), foot, 0.035, black, RM_BLACK)
		if wheels:
			_caster(g, d * spread, 0.06)
		else:
			g.box(Transform3D(Basis(), d * spread + Vector3(0, 0.02, 0)), Vector3(0.06, 0.04, 0.06), col(BLACK, C_RUBBER), Vector2(0.8, 0.0))
	g.cyl(Vector3(0, 0.6, 0), 0.04, 0.04, top - 0.6, 10, steel, RM_STEEL)
	g.cyl(Vector3(0, 0.55, 0), 0.05, 0.05, 1.0, 10, black, RM_BLACK)
	g.mode = 1
	for y: float in [1.55, lerpf(1.55, top, 0.5)]:
		g.cyl(Vector3(0, y, 0), 0.055, 0.055, 0.07, 10, col(Color(0.15, 0.15, 0.16), C_METAL), RM_STEEL)
	g.mode = 0


## An 18K HMI fresnel on its roller stand, aimed along +z (tilted down a little): the yoke, the
## lamp housing with its vents, the lens and the barn doors; the ballast on the ground.
static func hmi() -> ArrayMesh:
	if _meshes.has("hmi"):
		return _meshes.hmi
	var g := FarmersMarketKit.Geo.new()
	_stand(g, HMI_Y - 0.35, 0.85, true)
	var black := col(Color(0.06, 0.06, 0.065), C_PAINT)
	var rm := Vector2(0.55, 0.3)
	var c := Vector3(0, HMI_Y, 0)
	# The yoke.
	g.box(Transform3D(Basis(), c + Vector3(0, -0.38, 0)), Vector3(0.95, 0.06, 0.1), black, rm)
	for s: float in [-1.0, 1.0]:
		g.box(Transform3D(Basis(), c + Vector3(s * 0.46, -0.18, 0)), Vector3(0.05, 0.42, 0.1), black, rm)
	# The housing (tilted 8 degrees down), lens and barn doors.
	var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(8.0)), c)
	g.tube(tilt * Vector3(0, 0, -0.45), tilt * Vector3(0, 0, 0.3), 0.4, 18, black, rm)
	g.cyl(tilt * Vector3(0, 0, -0.45), 0.38, 0.2, 0.0, 18, black, rm)
	g.tri(tilt * Vector3(-0.38, 0, -0.45), tilt * Vector3(0.38, 0, -0.45), tilt * Vector3(0, 0.38, -0.45), tilt.basis * Vector3.BACK * -1.0, black, rm)
	var lens_n := tilt.basis * Vector3.BACK
	var lens_c := tilt * Vector3(0, 0, 0.3)
	var n := 18
	for k in n:
		var t0 := TAU * float(k) / n
		var t1 := TAU * float(k + 1) / n
		g.tri(lens_c + lens_n * 0.01, tilt * Vector3(cos(t0) * 0.36, sin(t0) * 0.36, 0.3), tilt * Vector3(cos(t1) * 0.36, sin(t1) * 0.36, 0.3), lens_n, col(Color(0.95, 0.97, 1.0), C_HMI), Vector2(0.1, 0.0))
	g.mode = 1
	for i in 6:
		g.box(tilt * Transform3D(Basis(), Vector3(0, 0.41, -0.35 + i * 0.1)), Vector3(0.5, 0.03, 0.04), col(Color(0.2, 0.2, 0.21), C_METAL), RM_STEEL)
	g.mode = 0
	var door := col(Color(0.05, 0.05, 0.055), C_PAINT)
	for s: float in [-1.0, 1.0]:
		g.quad(tilt * Vector3(s * 0.4, -0.4, 0.33), tilt * Vector3(s * 0.4, 0.4, 0.33), tilt * Vector3(s * 0.62, 0.4, 0.72), tilt * Vector3(s * 0.62, -0.4, 0.72), tilt.basis * Vector3(s, 0, -0.6), door, rm)
		g.quad(tilt * Vector3(-0.4, s * 0.4, 0.33), tilt * Vector3(0.4, s * 0.4, 0.33), tilt * Vector3(0.36, s * 0.55, 0.62), tilt * Vector3(-0.36, s * 0.55, 0.62), tilt.basis * Vector3(0, s, -0.5), door, rm)
	# The ballast on the ground beside the stand and a sandbag on each leg.
	g.box(Transform3D(Basis(Vector3.UP, 0.3), Vector3(-0.9, 0.17, -0.6)), Vector3(0.55, 0.34, 0.4), col(Color(0.14, 0.15, 0.16), C_PAINT), RM_BLACK)
	g.mode = 1
	g.box(Transform3D(Basis(Vector3.UP, 0.3), Vector3(-0.9, 0.3, -0.403)), Vector3(0.3, 0.06, 0.01), col(Color(0.2, 0.8, 0.3), C_LAMP), Vector2(0.2, 0.0))
	for a in 3:
		var d := Vector3(cos(a * TAU / 3.0), 0.0, sin(a * TAU / 3.0))
		_sandbag(g, Transform3D(Basis(Vector3.UP, -a * TAU / 3.0), d * 0.55 + Vector3(0, 0.36, 0)))
	g.mode = 0
	var mesh := _finish(g, 0.06)
	_meshes.hmi = mesh
	return mesh


## The balloon light: a glowing white envelope on a wind-up stand with outriggers, tethers and
## sandbags.
static func balloon() -> ArrayMesh:
	if _meshes.has("balloon"):
		return _meshes.balloon
	var g := FarmersMarketKit.Geo.new()
	_stand(g, BALLOON_Y - BALLOON_R.y, 1.25, false)
	var c := Vector3(0, BALLOON_Y, 0)
	g.ellipsoid(Transform3D(Basis(), c), BALLOON_R, 22, 12, col(Color(1.0, 0.99, 0.96), C_BALLOON), Vector2(0.9, 0.0))
	# The skirt ring and the tethers to the outrigger feet.
	g.cyl(c + Vector3(0, -BALLOON_R.y - 0.05, 0), 0.3, 0.3, 0.1, 14, col(Color(0.1, 0.1, 0.1), C_PAINT), RM_BLACK)
	g.mode = 1
	for a in 3:
		var d := Vector3(cos(a * TAU / 3.0 + 0.5), 0.0, sin(a * TAU / 3.0 + 0.5))
		g.tube(c + d * BALLOON_R.x * 0.95, d * 3.2 + Vector3(0, 0.05, 0), 0.006, 3, col(BLACK, C_FIXED), RM_BLACK)
		_sandbag(g, Transform3D(Basis(Vector3.UP, a), d * 3.2 + Vector3(0, 0.08, 0)))
		_sandbag(g, Transform3D(Basis(Vector3.UP, a + 1.0), d * 1.0 + Vector3(0, 0.08, 0)))
	g.mode = 0
	var mesh := _finish(g, 0.08)
	_meshes.balloon = mesh
	return mesh


## A C-stand with an arm and a 4 x 4 ft frame facing +z: a black flag (duvetyne) or a bounce
## (silver one side).
static func c_stand(bounce: bool) -> ArrayMesh:
	var key := "cstand_%s" % bounce
	if _meshes.has(key):
		return _meshes[key]
	var g := FarmersMarketKit.Geo.new()
	var chrome := col(Color(0.7, 0.71, 0.72), C_CHROME)
	# Turtle base: three legs of different heights.
	for a in 3:
		var d := Vector3(cos(a * TAU / 3.0), 0.0, sin(a * TAU / 3.0))
		g.bar(Vector3(0, 0.2 + a * 0.1, 0), d * 0.55 + Vector3(0, 0.02, 0), 0.02, chrome, Vector2(0.3, 0.9))
	g.cyl(Vector3(0, 0.0, 0), 0.02, 0.016, 2.05, 8, chrome, Vector2(0.3, 0.9))
	var head := Vector3(0, 2.05, 0)
	g.mode = 1
	g.cyl(head - Vector3(0, 0.06, 0), 0.04, 0.04, 0.12, 8, col(Color(0.15, 0.15, 0.15), C_METAL), RM_STEEL)
	_sandbag(g, Transform3D(Basis(Vector3.UP, 0.2), Vector3(0.3, 0.2, 0.05)))
	g.mode = 0
	g.bar(head, head + Vector3(0, 0.15, 0.55), 0.018, chrome, Vector2(0.3, 0.9))
	var fc := head + Vector3(0, 0.45, 0.6)
	var s := 0.6
	var face := col(Color(0.04, 0.04, 0.045), C_DUVE) if not bounce else col(Color(0.82, 0.83, 0.85), C_BOUNCE)
	g.quad(fc + Vector3(-s, -s, 0), fc + Vector3(s, -s, 0), fc + Vector3(s, s, 0), fc + Vector3(-s, s, 0), Vector3.BACK, face, Vector2(0.9, 0.0) if not bounce else Vector2(0.3, 0.7))
	g.quad(fc + Vector3(s, -s, -0.003), fc + Vector3(-s, -s, -0.003), fc + Vector3(-s, s, -0.003), fc + Vector3(s, s, -0.003), Vector3.FORWARD,
		col(Color(0.04, 0.04, 0.045), C_DUVE) if not bounce else col(Color(0.92, 0.92, 0.9), C_CANVAS), Vector2(0.9, 0.0))
	g.mode = 1
	for k in 4:
		var a := fc + Vector3(-s if k < 2 else s, -s if k % 3 == 0 else s, 0)
		var b := fc + Vector3(-s if (k + 1) % 4 < 2 else s, -s if (k + 1) % 4 % 3 == 0 else s, 0)
		g.tube(a, b, 0.012, 4, chrome, Vector2(0.3, 0.9))
	g.mode = 0
	var mesh := _finish(g, 0.05)
	_meshes[key] = mesh
	return mesh


## Video village: the monitor cart (two monitors and a hood), three director's chairs and the
## sound cart beside them. Origin on the ground, the monitors facing -z (the chairs on -z).
static func village() -> ArrayMesh:
	if _meshes.has("village"):
		return _meshes.village
	var g := FarmersMarketKit.Geo.new()
	var frame := col(Color(0.15, 0.15, 0.16), C_PAINT)
	g.box(Transform3D(Basis(), Vector3(0, 0.5, 0.3)), Vector3(1.1, 0.06, 0.6), frame, RM_BLACK)
	g.box(Transform3D(Basis(), Vector3(0, 0.18, 0.3)), Vector3(1.1, 0.04, 0.6), frame, RM_BLACK)
	for sx: float in [-0.52, 0.52]:
		for sz: float in [0.03, 0.57]:
			g.bar(Vector3(sx, 0.1, sz), Vector3(sx, 1.0, sz), 0.03, frame, RM_BLACK)
			_caster(g, Vector3(sx, 0.0, sz), 0.05)
	for sx: float in [-0.27, 0.27]:
		g.box(Transform3D(Basis(Vector3.UP, sx * -0.4), Vector3(sx, 1.2, 0.32)), Vector3(0.5, 0.32, 0.05), col(Color(0.05, 0.05, 0.05), C_PAINT), RM_BLACK)
		g.box(Transform3D(Basis(Vector3.UP, sx * -0.4), Vector3(sx, 1.2, 0.29)), Vector3(0.46, 0.28, 0.005), col(Color(0.55, 0.6, 0.65), C_SCREEN), Vector2(0.1, 0.0))
		g.box(Transform3D(Basis(Vector3.UP, sx * -0.4), Vector3(sx, 1.38, 0.24)), Vector3(0.52, 0.02, 0.18), col(Color(0.04, 0.04, 0.04), C_DUVE), Vector2(0.9, 0.0))
	g.box(Transform3D(Basis(), Vector3(0, 0.75, 0.3)), Vector3(0.4, 0.4, 0.4), col(Color(0.08, 0.08, 0.08), C_PAINT), RM_BLACK)
	# Director's chairs: wooden X frames, black canvas seat and back, facing the monitors (+z).
	for i in 3:
		_chair(g, Transform3D(Basis(), Vector3(-0.85 + i * 0.85, 0.0, -0.75)))
	# The sound cart off to one side: shelves, the mixer, antennas.
	var sc := Transform3D(Basis(Vector3.UP, 0.5), Vector3(1.6, 0.0, 0.1))
	g.box(sc * Transform3D(Basis(), Vector3(0, 0.45, 0)), Vector3(0.8, 0.9, 0.5), frame, RM_BLACK)
	g.box(sc * Transform3D(Basis(), Vector3(0, 0.93, 0.0)), Vector3(0.7, 0.06, 0.45), col(Color(0.18, 0.18, 0.2), C_METAL), RM_STEEL)
	g.mode = 1
	for k in 8:
		g.box(sc * Transform3D(Basis(), Vector3(-0.3 + k * 0.085, 0.975, 0.05)), Vector3(0.03, 0.03, 0.12), col(Color(0.9, 0.4, 0.1) if k % 3 == 0 else Color(0.6, 0.6, 0.6), C_LAMP if k % 3 == 0 else C_METAL), Vector2(0.4, 0.5))
	for k in 2:
		g.bar(sc * Vector3(-0.3 + k * 0.6, 0.95, -0.2), sc * Vector3(-0.3 + k * 0.6, 1.9, -0.2), 0.012, col(BLACK, C_METAL), RM_BLACK)
	g.mode = 0
	var mesh := _finish(g, 0.05)
	_meshes.village = mesh
	return mesh


static func _chair(g: FarmersMarketKit.Geo, xf: Transform3D) -> void:
	var wood := col(Color(0.62, 0.45, 0.28), C_WOOD)
	var canvas := col(Color(0.05, 0.05, 0.055), C_DUVE)
	for s: float in [-1.0, 1.0]:
		g.bar(xf * Vector3(s * 0.25, 0.0, -0.22), xf * Vector3(s * 0.25, 1.15, -0.25), 0.035, wood, Vector2(0.7, 0.0))
		g.bar(xf * Vector3(s * 0.25, 0.0, 0.2), xf * Vector3(s * 0.25, 0.85, 0.2), 0.035, wood, Vector2(0.7, 0.0))
		g.bar(xf * Vector3(s * 0.25, 0.1, -0.22), xf * Vector3(s * 0.25, 0.75, 0.2), 0.03, wood, Vector2(0.7, 0.0))
		g.bar(xf * Vector3(s * 0.25, 0.85, -0.22), xf * Vector3(s * 0.25, 0.85, 0.2), 0.035, wood, Vector2(0.7, 0.0))
	g.box(xf * Transform3D(Basis(), Vector3(0, 0.76, 0.0)), Vector3(0.5, 0.02, 0.42), canvas, Vector2(0.9, 0.0))
	g.box(xf * Transform3D(Basis(), Vector3(0, 1.0, -0.24)), Vector3(0.52, 0.22, 0.015), canvas, Vector2(0.9, 0.0))
	g.mode = 1
	g.box(xf * Transform3D(Basis(), Vector3(0, 1.0, -0.25)), Vector3(0.3, 0.05, 0.005), col(Color(0.9, 0.9, 0.86), C_FIXED), Vector2(0.9, 0.0))
	g.mode = 0


## Set dressing by the camera: apple boxes stacked, road cases, a coil of cable, a sandbag pile.
static func kit_pile() -> ArrayMesh:
	if _meshes.has("pile"):
		return _meshes.pile
	var g := FarmersMarketKit.Geo.new()
	var wood := col(Color(0.7, 0.56, 0.36), C_WOOD)
	var sizes := [Vector3(0.5, 0.2, 0.3), Vector3(0.5, 0.1, 0.3), Vector3(0.5, 0.05, 0.3), Vector3(0.5, 0.2, 0.3)]
	var y := 0.0
	for i in sizes.size():
		var s: Vector3 = sizes[i]
		g.box(Transform3D(Basis(Vector3.UP, 0.08 * i), Vector3(0.0, y + s.y * 0.5, 0.0)), s, wood, Vector2(0.85, 0.0))
		y += s.y
	g.mode = 1
	g.box(Transform3D(Basis(), Vector3(0.0, 0.1, 0.152)), Vector3(0.2, 0.06, 0.01), col(Color(0.15, 0.1, 0.06), C_FIXED), Vector2(0.9, 0.0))
	g.mode = 0
	var case := col(Color(0.05, 0.05, 0.055), C_PAINT)
	var corner := col(Color(0.7, 0.71, 0.72), C_CHROME)
	for i in 2:
		var cxf := Transform3D(Basis(Vector3.UP, 0.3 * i), Vector3(0.9, 0.3 + i * 0.6, -0.1))
		g.box(cxf, Vector3(0.8, 0.6, 0.55), case, Vector2(0.45, 0.1))
		g.mode = 1
		for sx: float in [-0.4, 0.4]:
			for sy: float in [-0.3, 0.3]:
				g.box(cxf * Transform3D(Basis(), Vector3(sx, sy, 0.275)), Vector3(0.06, 0.06, 0.01), corner, Vector2(0.3, 0.9))
		g.box(cxf * Transform3D(Basis(), Vector3(0, 0.1, 0.28)), Vector3(0.12, 0.04, 0.02), corner, Vector2(0.3, 0.9))
		g.mode = 0
	g.cyl(Vector3(-0.7, 0.0, 0.1), 0.3, 0.3, 0.16, 14, col(Color(0.05, 0.05, 0.05), C_RUBBER), Vector2(0.75, 0.0))
	for i in 3:
		_sandbag(g, Transform3D(Basis(Vector3.UP, 0.4 * i), Vector3(-0.2 + i * 0.12, 0.08 + 0.13 * (i / 2), -0.45)))
	var mesh := _finish(g, 0.04)
	_meshes.pile = mesh
	return mesh


# --- The closure ---------------------------------------------------------------------------------

## A type III barricade 2.4 m wide: two A-frame legs, three striped boards (the shader's stripes),
## facing +z.
static func barricade() -> ArrayMesh:
	if _meshes.has("barricade"):
		return _meshes.barricade
	var g := FarmersMarketKit.Geo.new()
	var white := col(Color(0.92, 0.92, 0.9), C_PAINT)
	for s: float in [-1.1, 1.1]:
		g.bar(Vector3(s, 0.0, 0.25), Vector3(s, 1.55, 0.0), 0.06, white, Vector2(0.5, 0.0))
		g.bar(Vector3(s, 0.0, -0.25), Vector3(s, 1.55, 0.0), 0.06, white, Vector2(0.5, 0.0))
		g.box(Transform3D(Basis(), Vector3(s, 0.03, 0.0)), Vector3(0.12, 0.06, 0.7), col(Color(0.08, 0.08, 0.08), C_RUBBER), Vector2(0.85, 0.0))
	for i in 3:
		var y := 0.55 + i * 0.4
		g.box(Transform3D(Basis(), Vector3(0.0, y, 0.06 - i * 0.03)), Vector3(2.45, 0.2, 0.025), col(Color.WHITE, C_STRIPE), Vector2(0.45, 0.0))
	# A flashing lamp on the top board.
	g.cyl(Vector3(1.0, 1.4, 0.0), 0.08, 0.08, 0.04, 10, col(Color(0.15, 0.15, 0.16), C_PAINT), RM_BLACK)
	g.cyl(Vector3(1.0, 1.44, 0.0), 0.08, 0.075, 0.12, 10, col(Color(1.0, 0.6, 0.1), C_LAMP), Vector2(0.2, 0.0))
	var mesh := _finish(g, 0.05)
	_meshes.barricade = mesh
	return mesh


## A 28 in traffic cone with its reflective collar.
static func cone() -> ArrayMesh:
	if _meshes.has("cone"):
		return _meshes.cone
	var g := FarmersMarketKit.Geo.new()
	var orange := col(Color(1.0, 0.36, 0.04), C_PAINT)
	g.box(Transform3D(Basis(), Vector3(0, 0.02, 0)), Vector3(0.36, 0.04, 0.36), orange, Vector2(0.6, 0.0))
	g.cyl(Vector3(0, 0.04, 0), 0.15, 0.1, 0.25, 14, orange, Vector2(0.6, 0.0), false)
	g.cyl(Vector3(0, 0.29, 0), 0.1, 0.075, 0.13, 14, col(Color(0.95, 0.95, 0.93), C_LAMP), Vector2(0.4, 0.0), false)
	g.cyl(Vector3(0, 0.42, 0), 0.075, 0.025, 0.3, 14, orange, Vector2(0.6, 0.0))
	var mesh := _finish(g, 0.03)
	_meshes.cone = mesh
	return mesh


## A notice post: a square steel post with the orange "filming" notice cable-tied on (the
## lettering is FilmShootBuild's detail mesh) at 1.7 m, facing +z.
static func notice() -> ArrayMesh:
	if _meshes.has("notice"):
		return _meshes.notice
	var g := FarmersMarketKit.Geo.new()
	var steel := col(Color(0.55, 0.56, 0.57), C_METAL)
	g.box(Transform3D(Basis(), Vector3(0, 1.2, -0.03)), Vector3(0.05, 2.4, 0.05), steel, RM_STEEL)
	g.box(Transform3D(Basis(), Vector3(0, 1.7, 0.0)), Vector3(0.43, 0.56, 0.006), col(Color(1.0, 0.52, 0.06), C_NOTICE), Vector2(0.8, 0.0))
	g.mode = 1
	for y: float in [1.48, 1.92]:
		g.box(Transform3D(Basis(), Vector3(0, y, 0.0)), Vector3(0.07, 0.012, 0.02), col(Color(0.05, 0.05, 0.05), C_FIXED), RM_BLACK)
	g.mode = 0
	var mesh := _finish(g, 0.03)
	_meshes.notice = mesh
	return mesh


## The yellow location arrow sign on its post (the production's code and an arrow are lettering
## in the detail mesh), facing +z.
static func arrow_sign() -> ArrayMesh:
	if _meshes.has("arrow"):
		return _meshes.arrow
	var g := FarmersMarketKit.Geo.new()
	g.box(Transform3D(Basis(), Vector3(0, 1.3, -0.03)), Vector3(0.05, 2.6, 0.05), col(Color(0.55, 0.56, 0.57), C_METAL), RM_STEEL)
	g.box(Transform3D(Basis(), Vector3(0, 2.25, 0.0)), Vector3(0.75, 0.48, 0.006), col(Color(0.98, 0.85, 0.08), C_NOTICE), Vector2(0.7, 0.0))
	g.box(Transform3D(Basis(), Vector3(0, 1.65, 0.0)), Vector3(0.6, 0.42, 0.006), col(Color(0.95, 0.95, 0.92), C_FIXED), Vector2(0.7, 0.0))
	var mesh := _finish(g, 0.03)
	_meshes.arrow = mesh
	return mesh


## Builds every mesh once (the loading screen), so the first shoot does not stall.
static func warm() -> Array:
	if not FilmShoot.enabled:
		return []
	for c: Array in FilmShoot.CAMP:
		if String(c[0]) == "honeywagon" or String(c[0]) == "cast":
			trailer(float(c[1]), String(c[0]) == "honeywagon")
	genny()
	truck_tail(false)
	truck_tail(true)
	catering()
	track(FilmShoot.TRACK_LEN)
	dolly()
	crane()
	hmi()
	balloon()
	c_stand(false)
	c_stand(true)
	village()
	kit_pile()
	barricade()
	cone()
	notice()
	arrow_sign()
	return [material()]
