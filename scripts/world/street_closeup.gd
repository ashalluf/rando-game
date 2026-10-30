class_name StreetCloseup
extends RefCounted
## Downtown's streets at a pedestrian's eye, 2-10 m (fleet wave 3, `downtown-street-closeup`;
## docs/HANDOFF.md "Downtown streets at arm's length"). A review of the historic core, the Financial
## District, South Park and Broadway at noon, 17:30 and 21:00 listed what most breaks the picture
## up close; this file is the fixes that were real geometry or shader work rather than tuning:
##   * The KERB FACE (Kerbs._kerb_face) was drawn in the pavement's material, which is projected
##     from above: a flat grey band with a razor edge. It is now its own mesh ("KerbFace") on
##     shaders/kerb_closeup.gdshader - the pavement's concrete sampled across the face, grime and
##     splash at its foot, tyre scuffs, chips, 10 ft joints - with a 2.5 cm ARRIS strip over the top
##     edge whose normal rolls the edge round (the strip discards itself past `arris_reach`).
##   * The GUTTER was a dark strip laid on the asphalt (StreetDetail). Los Angeles pours its kerb
##     and gutter as one: a 0.6 m concrete pan, dished to a flow line of silt at the kerb, sealed at
##     the asphalt, on the same joints. Same batch key, a wider box and the close-up material; no
##     piece is laid over a kerb inlet's apron (RoadHardware) any more.
##   * Paint that stood 2.5 cm proud of the road on its box sides (CityChunk's PAINT_KEYS) is
##     pressed to 4 mm in the paint shader's vertex stage (`road_paint.gdshader` `thickness`).
## Nothing here rolls anything: geometry only follows what Kerbs and StreetDetail already decided.
## `STREET_CLOSEUP=0` in the environment is the A/B (every surface exactly as before).
## Checks: tests/downtown_street_closeup_checks.gd.

static var enabled: bool = OS.get_environment("STREET_CLOSEUP") != "0"

## The concrete pan's width out from the kerb face (m; LA's standard 24 in gutter).
const PAN_WIDTH := 0.6
## The arris strip's width on the kerb top and its lift over the pavement (m).
const ARRIS := 0.025
const ARRIS_LIFT := 0.002
## The pan box's centre over the road top: its 8 mm box tops out 6 mm up, over the road wear's
## stamps (4.2 mm) and under the pressed paint (5 mm + 4 mm: crosswalk bars cross it).
const PAN_LIFT := 0.002
## A pavement cafe set's clearance for the stop benches StreetFurniture lays at the finish (m):
## the table and its chairs reach 1.3 m from the prop's centre, which was taken for a 0.6 m post.
const CAFE_CLEAR := 1.4
## The road paint's thickness once pressed (m): thermoplastic is 2-3 mm.
const PAINT_THICK := 0.004

static var _mats: Dictionary = {}


## The face / arris material for a pavement material (the same texture and tint, so the face is
## the same concrete as the slab it is the edge of). Cached by the texture and tint: the pavement
## materials are themselves cached for the session (PropFactory.road()).
static func kerb_material(paving: Material) -> ShaderMaterial:
	var tex: Texture2D = null
	var nrm: Texture2D = null
	var tint := Vector3(0.95, 0.94, 0.92)
	var scale := 3.0
	if paving is ShaderMaterial:
		var sm := paving as ShaderMaterial
		tex = sm.get_shader_parameter("albedo_tex")
		nrm = sm.get_shader_parameter("normal_tex")
		var t: Variant = sm.get_shader_parameter("tint")
		if t is Color:
			tint = Vector3((t as Color).r, (t as Color).g, (t as Color).b)
		elif t is Vector3:
			tint = t
		var s: Variant = sm.get_shader_parameter("tex_scale")
		if s != null:
			scale = float(s)
	var key := "kerb_%s_%s_%.2f" % [tex.resource_path if tex else "-", tint, scale]
	if _mats.has(key):
		return _mats[key]
	var mat := _base()
	if tex:
		mat.set_shader_parameter("albedo_tex", tex)
	if nrm:
		mat.set_shader_parameter("normal_tex", nrm)
	# As a Color, like the pavement's own: a source_color uniform is decoded the same way there.
	mat.set_shader_parameter("tint", Color(tint.x, tint.y, tint.z))
	mat.set_shader_parameter("tex_scale", maxf(scale, 0.5))
	_mats[key] = mat
	return mat


## The gutter pan's material (one for the city: the pans are poured, not the block's paving).
static func gutter_material() -> ShaderMaterial:
	if _mats.has("gutter"):
		return _mats["gutter"]
	var mat := _base()
	mat.set_shader_parameter("albedo_tex", PropFactory.texture("sidewalk", "Color"))
	mat.set_shader_parameter("normal_tex", PropFactory.texture("sidewalk", "NormalGL"))
	mat.set_shader_parameter("tint", Color(1.42, 1.40, 1.34))
	mat.set_shader_parameter("tex_scale", 2.5)
	mat.set_shader_parameter("gutter", true)
	_mats["gutter"] = mat
	return mat


static func _base() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/kerb_closeup.gdshader")
	mat.set_shader_parameter("pan_width", PAN_WIDTH)
	mat.set_shader_parameter("kerb_h", CityChunk.SIDEWALK_TOP - CityChunk.ROAD_TOP)
	return mat


## The gutter pan's mesh: a unit-length box PAN_WIDTH across (scaled along by the piece).
static func pan_mesh() -> Mesh:
	if _mats.has("pan_mesh"):
		return _mats["pan_mesh"]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(PAN_WIDTH, 0.008, 4.0)
	mesh.material = gutter_material()
	_mats["pan_mesh"] = mesh
	return mesh


## Where the kerb inlets RoadHardware will lay on edge `e` stand (metres along it), so the pan
## stops short of their aprons: RoadHardware._inlets()' own test, worked out the same way.
static func inlet_alongs(chunk: CityChunk, e: Array) -> Array[float]:
	var out: Array[float] = []
	if not RoadHardware.enabled:
		return out
	var a: Vector2 = e[0]
	var b: Vector2 = e[1]
	var inward: Vector2 = e[2]
	var length := a.distance_to(b)
	if length < RoadHardware.INLET_ALONG * 2.0 + RoadHardware.INLET_APRON * 2.0:
		return out
	var plan := chunk.plan
	var axis := CityPlan.AXIS_X if absf(inward.x) > 0.5 else CityPlan.AXIS_Z
	var index := (chunk.ix if inward.x > 0.0 else chunk.ix + 1) if axis == CityPlan.AXIS_X else (chunk.iz if inward.y > 0.0 else chunk.iz + 1)
	var mid := (a + b) * 0.5
	if not plan.road_open(axis, index, mid.y if axis == CityPlan.AXIS_X else mid.x):
		return out
	out.append(RoadHardware.INLET_ALONG)
	out.append(length - RoadHardware.INLET_ALONG)
	return out


## StreetDetail's gutter for one kerb edge: pan pieces along it, clear of the inlets' aprons.
## The pieces are the old strip's (2 m in from each end, at most 4 m), split round an apron.
static func lay_gutter(chunk: CityChunk, e: Array) -> void:
	var batch: MultiMeshBatch = chunk._batch
	var a: Vector2 = e[0]
	var b: Vector2 = e[1]
	var inward: Vector2 = e[2]
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var yaw := atan2(-dir.x, -dir.y)
	var basis0 := Basis(Vector3.UP, yaw)
	# Which side of the box's local x is the kerb: local +x is up x (-dir) = (-dir.y, 0, dir.x).
	var lx := Vector2(-dir.y, dir.x)
	var side := 1.0 if lx.dot(inward) > 0.0 else 0.0
	var gaps: Array = []
	for at: float in inlet_alongs(chunk, e):
		gaps.append([at - RoadHardware.INLET_APRON - 0.05, at + RoadHardware.INLET_APRON + 0.05])
	var spans: Array = [[2.0, length - 2.0]]
	for g: Array in gaps:
		var next: Array = []
		for s: Array in spans:
			if g[1] <= s[0] or g[0] >= s[1]:
				next.append(s)
				continue
			if g[0] > s[0]:
				next.append([s[0], g[0]])
			if g[1] < s[1]:
				next.append([g[1], s[1]])
		spans = next
	var y := CityChunk.ROAD_TOP + PAN_LIFT
	for s: Array in spans:
		var t: float = s[0]
		while t < float(s[1]) - 0.05:
			var piece := minf(4.0, float(s[1]) - t)
			var p := a + dir * (t + piece * 0.5) - inward * PAN_WIDTH * 0.5
			batch.add("gutter", pan_mesh(), Transform3D(basis0.scaled_local(Vector3(1.0, 1.0, piece / 4.0)), Vector3(p.x, y, p.y)), Color.WHITE, Color(side, 0.0, 0.0, 0.0))
			t += piece


# --- The kerb face and its arris (called by Kerbs) ------------------------------------------------

## One triangle of the kerb face into `fst` (UV: metres along the kerb, metres over the road top).
static func face_tri(fst: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, want: Vector3, mode: float) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-14:
		return
	if n.dot(want) < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
	for k in 3:
		var v: Vector3 = [a, b, c][k]
		fst.set_normal(want)
		fst.set_uv([ua, ub, uc][k])
		fst.set_uv2(Vector2(mode, 0.0))
		fst.add_vertex(v)


# --- Parked cars in surface lots -----------------------------------------------------------------

## How near a lot's cars are the real bodies (CarParkBuild.real_body(): the road cars' far twins in
## their paint) rather than ArenaGrounds' static boxes, measured to their 24 m cell's centre (m).
const REAL_CAR_NEAR := 42.0
## The cells cars are grouped in for that range (m): a batch's range is measured to its centre.
const CAR_CELL := 24.0

## LotFill._car() records each static car it laid in a FULL chunk (after its rolls, from the
## batch index it got): [batch key, index, transform, kind, paint].
static func note_car(ch: CityChunk, key: String, index: int, xf: Transform3D, kind: int, paint: Color) -> void:
	if not enabled or ch.level != CityChunk.Level.FULL or index < 0:
		return
	# The batch lifted it onto the relief as it took it: that transform, not the one passed in.
	var batch: Dictionary = ch._batch.data().get(key, {})
	if batch.is_empty() or index >= (batch.xforms as Array).size():
		return
	if not ch.has_meta("sc_cars"):
		ch.set_meta("sc_cars", [])
	(ch.get_meta("sc_cars") as Array).append([key, index, batch.xforms[index], kind, paint])


## At the chunk's finish, once the batches are built: every recorded car leaves the chunk-wide
## batch (hide_instance(), its shadow twin and contact shadow too) and is drawn again per cell -
## the real body within REAL_CAR_NEAR, the same static box past it.
static func commit_cars(ch: CityChunk, nodes: Dictionary) -> void:
	if not ch.has_meta("sc_cars"):
		return
	var cars: Array = ch.get_meta("sc_cars")
	ch.remove_meta("sc_cars")
	if not CarParkBuild.real_body(CarParkBuild.REAL_TYPES[0]).has("mesh"):
		return
	var seed_v := ch.plan.seed
	# cell -> {"far": {kind: [[xf, paint]]}, "near": {type: [[xf, paint]]}, "box": AABB}
	var cells: Dictionary = {}
	for c: Array in cars:
		var node := nodes.get(c[0]) as MultiMeshInstance3D
		if node == null:
			continue
		var xf: Transform3D = c[2]
		var p := xf.origin
		MultiMeshBatch.hide_instance(node, int(c[1]))
		var ck := Vector2i(floori(p.x / CAR_CELL), floori(p.z / CAR_CELL))
		if not cells.has(ck):
			cells[ck] = {"far": {}, "near": {}, "box": AABB(p, Vector3.ZERO)}
		var cell: Dictionary = cells[ck]
		cell.box = (cell.box as AABB).expand(p)
		var kind: int = c[3]
		if not (cell.far as Dictionary).has(kind):
			cell.far[kind] = []
		cell.far[kind].append([xf, c[4]])
		var hk := [seed_v, snappedf(p.x, 0.1), snappedf(p.z, 0.1), "sc_car"]
		var t: int = CarParkBuild.REAL_TYPES[CarParkBuild._pick_type(_h01(hk + ["body"]))]
		var rp: Color = Vehicle.PAINTS[absi(hash(hk + ["paint"])) % Vehicle.PAINTS.size()]
		if not (cell.near as Dictionary).has(t):
			cell.near[t] = []
		cell.near[t].append([xf, rp])
	for ck: Vector2i in cells:
		var cell: Dictionary = cells[ck]
		var bounds: AABB = (cell.box as AABB).grow(3.0)
		bounds.size.y += 1.5
		for kind: int in cell.far:
			var mmi := CarParkBuild._car_mmi(ArenaGrounds.car_mesh(kind), cell.far[kind], Vector3.ZERO, false)
			mmi.name = "LotCars%d_%d_%d" % [kind, ck.x, ck.y]
			_seat(ch, mmi, bounds)
			mmi.visibility_range_begin = REAL_CAR_NEAR
			# Their shadows past the real bodies' reach are a few pixels: none, as the batch's twin
			# stopped at LotFill.CAR_SHADOW_DISTANCE anyway.
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for t: int in cell.near:
			var body := CarParkBuild.real_body(t)
			var mmi := _real_mmi(body.mesh, cell.near[t], body.offset)
			mmi.name = "LotRealCars%d_%d_%d" % [t, ck.x, ck.y]
			_seat(ch, mmi, bounds)
			mmi.visibility_range_end = REAL_CAR_NEAR


## The real bodies of a cell: paint per instance in the custom data (car_park_car.gdshader).
## Instance colours are on too (white): on the Compatibility renderer a MultiMesh with custom data
## and no colours handed the shader garbage for the paint (neon pinks and cyans in the stills).
static func _real_mmi(mesh: Mesh, cars: Array, offset: Vector3) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cars.size()
	for i in cars.size():
		var c: Array = cars[i]
		mm.set_instance_transform(i, (c[0] as Transform3D) * Transform3D(Basis(), offset))
		var p: Color = c[1]
		mm.set_instance_color(i, Color.WHITE)
		mm.set_instance_custom_data(i, Color(p.r, p.g, p.b, 1.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


## A cell's MultiMesh in the chunk with the cell's bounds (all of a cell's groups measure their
## range to one centre, so a stall never draws twice or not at all).
static func _seat(ch: CityChunk, mmi: MultiMeshInstance3D, bounds: AABB) -> void:
	mmi.custom_aabb = bounds
	ch.add_child(mmi)


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# --- Street trees under a sidewalk shed ----------------------------------------------------------

## Construction's covered walkway over the pavement (its deck's footprint, chunk space).
static func note_shed(ch: CityChunk, poly: PackedVector2Array) -> void:
	if not enabled:
		return
	if not ch.has_meta("sc_sheds"):
		ch.set_meta("sc_sheds", [])
	(ch.get_meta("sc_sheds") as Array).append(poly)


## The street trees whose trunks stand under a shed's deck: their trunks went up through it. A
## shed goes up where the trees were boxed and taken down for the works; the tree's grate stays.
## Returns how many were taken out (the checks read it).
static func clear_sheds(ch: CityChunk, nodes: Dictionary) -> int:
	if not ch.has_meta("sc_sheds"):
		return 0
	var sheds: Array = ch.get_meta("sc_sheds")
	ch.remove_meta("sc_sheds")
	var data := ch._batch.data()
	var gone := 0
	for key: String in data:
		if not (key.begins_with("palm_") or key.begins_with("la_") or (key.begins_with("tree_") and key != "tree_grate")):
			continue
		var node := nodes.get(key) as MultiMeshInstance3D
		if node == null:
			continue
		var xforms: Array = data[key].xforms
		for i in xforms.size():
			var o: Vector3 = (xforms[i] as Transform3D).origin
			for poly: PackedVector2Array in sheds:
				if Geometry2D.is_point_in_polygon(Vector2(o.x, o.z), poly):
					MultiMeshBatch.hide_instance(node, i)
					gone += 1
					break
	ch.set_meta("sc_shed_trees", gone)
	return gone


# --- Broadway's goods in front of a wall ---------------------------------------------------------

## Whether the frontage behind pavement point `at` (where Broadway sets out a rack, gowns or a sale
## table, 0.6 m past the pavement) is NOT a shop: a surface car park's wall or a vacant lot's
## fence, which the goods stood half inside. Pure (the lot plan and VacantLots' own question).
static func goods_blocked(plan: CityPlan, ix: int, iz: int, at: Vector2) -> bool:
	if not enabled:
		return false
	for lot: Dictionary in plan.lots(ix, iz):
		if not lot.has("cell"):
			continue
		var cell: Rect2 = lot.cell
		if not cell.grow(0.8).has_point(at):
			continue
		if lot.get("parking", false) or VacantLots.kind_of(plan, ix, iz, lot) != VacantLots.NONE:
			return true
	return false


## Broadway's folding sale table (BroadwayStreet.table_mesh(), same footprint and height): it was
## nine saturated cubes on a board. Now a cloth over the top and down both long sides, stacks of
## folded tees in the muted colours a wholesale table carries, two open cartons with the stock
## standing in them, a shoebox pile, and the day-glo price card on its stake. Vertex colours on the
## table's own material; ~1.4k triangles.
static func sale_table_mesh(material: Material) -> Mesh:
	if _mats.has("sale_table"):
		return _mats["sale_table"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := func(c: Vector3, s: Vector3, col: Color, yaw: float = 0.0) -> void:
		BroadwayStreet._box(st, c, s, col, Basis(Vector3.UP, yaw))
	var steel := Color(0.3, 0.3, 0.32)
	for sx: float in [-0.8, 0.8]:
		for sz: float in [-0.3, 0.3]:
			box.call(Vector3(sz, 0.36, sx), Vector3(0.03, 0.72, 0.03), steel)
	box.call(Vector3(0.0, 0.74, 0.0), Vector3(0.75, 0.04, 1.8), Color(0.88, 0.87, 0.84))
	# The cloth: over the top and hanging 0.32 m down both long sides, a deep navy.
	var cloth := Color(0.10, 0.13, 0.24)
	box.call(Vector3(0.0, 0.766, 0.0), Vector3(0.80, 0.012, 1.86), cloth)
	for side: float in [-1.0, 1.0]:
		box.call(Vector3(side * 0.40, 0.61, 0.0), Vector3(0.008, 0.32, 1.86), cloth)
	# Folded tees, stacked: a stack is one colour, its layers a hair out of line.
	var tees := [Color(0.55, 0.55, 0.56), Color(0.12, 0.14, 0.22), Color(0.08, 0.08, 0.09), Color(0.86, 0.85, 0.82),
		Color(0.30, 0.33, 0.22), Color(0.38, 0.12, 0.14), Color(0.62, 0.52, 0.40), Color(0.25, 0.34, 0.46)]
	var k := 0
	for row in 2:
		for col in 3:
			var c: Color = tees[(k * 3 + 1) % tees.size()]
			var n := 4 + (k * 5) % 4
			var cx := -0.18 + 0.34 * float(row)
			var cz := -0.72 + 0.27 * float(col)
			for layer in n:
				var j := Vector3(0.008 * sin(float(layer * 7 + k)), 0.0, 0.01 * cos(float(layer * 5 + k)))
				var shade := 0.92 + 0.08 * float((layer + k) % 2)
				box.call(Vector3(cx, 0.784 + 0.024 * float(layer), cz) + j, Vector3(0.28, 0.022, 0.24), Color(c.r * shade, c.g * shade, c.b * shade), 0.03 * sin(float(layer + k)))
			k += 1
	# Two open cartons, the stock standing in them (rolled socks, boxed phone cases).
	var kraft := Color(0.55, 0.42, 0.27)
	for b in 2:
		var cz := 0.18 + 0.36 * float(b)
		var cx := 0.0
		var h := 0.2
		var w := Vector2(0.42, 0.30)
		box.call(Vector3(cx, 0.776 + 0.004, cz), Vector3(w.x, 0.008, w.y), kraft.darkened(0.2))
		for sgn: float in [-1.0, 1.0]:
			box.call(Vector3(cx + sgn * w.x * 0.5, 0.776 + h * 0.5, cz), Vector3(0.006, h, w.y), kraft)
			box.call(Vector3(cx, 0.776 + h * 0.5, cz + sgn * w.y * 0.5), Vector3(w.x, h, 0.006), kraft)
			# The flaps, folded out and down a little.
			box.call(Vector3(cx + sgn * (w.x * 0.5 + 0.06), 0.776 + h - 0.02, cz), Vector3(0.12, 0.005, w.y), kraft.lightened(0.05), 0.0)
		# A packing tape stripe down one side.
		box.call(Vector3(cx + w.x * 0.5 + 0.004, 0.776 + h * 0.5, cz), Vector3(0.002, h, 0.05), Color(0.72, 0.62, 0.42))
		for m in 8:
			var mc := Color(0.08, 0.08, 0.1) if b == 0 else ([Color(0.9, 0.9, 0.88), Color(0.15, 0.15, 0.17), Color(0.5, 0.48, 0.45)][m % 3])
			var px := cx - 0.15 + 0.1 * float(m % 4)
			var pz := cz - 0.07 + 0.14 * float(m / 4)
			var mh := 0.16 if b == 0 else 0.13
			box.call(Vector3(px, 0.78 + mh * 0.5, pz), Vector3(0.075, mh, 0.1 if b == 0 else 0.07), mc, 0.08 * float(m % 3 - 1))
	# Shoeboxes, a short pile at the end.
	var shoe := [Color(0.85, 0.32, 0.12), Color(0.12, 0.12, 0.13), Color(0.82, 0.80, 0.76)]
	for s in 3:
		box.call(Vector3(-0.15 + 0.015 * float(s % 2), 0.776 + 0.06 + 0.12 * float(s), 0.78), Vector3(0.33, 0.115, 0.2), shoe[s], 0.04 * float(s - 1))
		box.call(Vector3(-0.15 + 0.015 * float(s % 2), 0.776 + 0.118 + 0.12 * float(s), 0.78), Vector3(0.335, 0.008, 0.205), (shoe[s] as Color).darkened(0.15), 0.04 * float(s - 1))
	# The price card on its stake, day-glo board.
	box.call(Vector3(0.0, 1.1, 0.95), Vector3(0.6, 0.45, 0.012), Color(0.95, 0.85, 0.15))
	box.call(Vector3(0.0, 1.1, 0.958), Vector3(0.5, 0.09, 0.004), Color(0.75, 0.08, 0.06))
	box.call(Vector3(0.0, 0.5, 0.95), Vector3(0.03, 1.0, 0.03), steel)
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, material)
	_mats["sale_table"] = mesh
	return mesh
