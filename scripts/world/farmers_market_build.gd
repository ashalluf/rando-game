class_name FarmersMarketBuild
extends RefCounted
## Lays a farmers' market (FarmersMarket) out in the chunk that owns its street: the steps a block
## adds (CityChunk._block_steps(), one hook line). FULL: the bollards and signs at both ends and
## the painted stall marks (always), then by the hour and the day the canopies, goods tables,
## packed-up stacks and vans, the banners and string lights (ONE mesh a chunk), the stallholders
## (StreetVendor) and the shoppers (MarketShopper) under the crowd cap, and a browse spot in front
## of every stall (the chunk's "vendor_queue": the crowd's life layer stops people there). LOD:
## the canopies alone (their mesh's far level). The far city's capture: nothing (a canopy is a
## pixel from there). Static: call with the chunk.

## How far the pieces draw (m) and cast shadows.
const CANOPY_DRAW := 320.0
const GOODS_DRAW := 140.0
const STOCK_DRAW := 110.0
const DETAIL_DRAW := 120.0
const SHADOW_REACH := 60.0
## Most stallholders and shoppers a chunk spawns (each in the crowd cap).
const MAX_VENDORS := 14
## The string lights: height at the canopies' corners, sag, bulb spacing.
const LIGHT_Y := 2.42
const LIGHT_SAG := 0.32
const BULB_STEP := 0.45
## Bollards: spacing across the street and how far in from the closure's start.
const BOLLARD_STEP := 1.55
const BOLLARD_IN := 1.4
## Banner colours (sRGB) behind the growers' names.
const BANNERS := [Color(0.1, 0.28, 0.16), Color(0.55, 0.08, 0.06), Color(0.92, 0.88, 0.76), Color(0.08, 0.16, 0.34),
	Color(0.42, 0.24, 0.12), Color(0.95, 0.78, 0.2)]

## The road van far twin's mesh per paint, and its offset ({} without the model).
static var _vans: Dictionary = {}
const VAN_PAINTS := [Color(0.92, 0.92, 0.9), Color(0.92, 0.92, 0.9), Color(0.75, 0.76, 0.77), Color(0.16, 0.3, 0.2), Color(0.85, 0.82, 0.72)]


## The steps of chunk `ch`'s market, or none.
static func steps(ch: CityChunk, _block: Dictionary) -> Array[Callable]:
	var out: Array[Callable] = []
	if ch.capturing or not FarmersMarket.enabled:
		return out
	var m := FarmersMarket.market_of_chunk(ch.plan, ch.ix, ch.iz)
	if m.is_empty():
		return out
	ch.market_road = m.rect
	if ch.level != CityChunk.Level.FULL:
		out.append(func() -> void: build_lod(ch, m))
		return out
	var people := {"vendors": [], "shoppers": 0}
	out.append(func() -> void: build(ch, m, people))
	for i in MAX_VENDORS:
		out.append(func() -> void: spawn_vendor(ch, m, people, i))
	for i in FarmersMarket.MAX_SHOPPERS:
		out.append(func() -> void: spawn_shopper(ch, m, people, i))
	return out


## The frame of a stall: origin on the road under its canopy's centre, +z toward the aisle.
static func stall_xf(m: Dictionary, s: Dictionary) -> Transform3D:
	var p := FarmersMarket.point(m, float(s.t), float(s.o))
	var across: Vector2 = FarmersMarket.dirs(m)[1]
	var front := -across * float(s.side)
	var z3 := Vector3(front.x, 0.0, front.y)
	var x3 := Vector3.UP.cross(z3)
	return Transform3D(Basis(x3, Vector3.UP, z3), Vector3(p.x, CityChunk.ROAD_TOP, p.y))


static func build_lod(ch: CityChunk, m: Dictionary) -> void:
	var hour := FarmersMarket.hour_now(ch)
	var st := FarmersMarket.status(m, hour, FarmersMarket.weekday(ch))
	var lay := FarmersMarket.layout(m)
	for i in (lay.stalls as Array).size():
		if int(st.states[i]) != FarmersMarket.State.UP:
			continue
		var s: Dictionary = lay.stalls[i]
		var c: Color = FarmersMarketKit.CANVAS[int(s.canvas)]
		ch._batch.add("fm_canopy", FarmersMarketKit.canopy(), stall_xf(m, s), Color.WHITE, c)
	ch._batch.set_no_shadow("fm_canopy")


## Everything a FULL chunk draws of its market at this hour and day.
static func build(ch: CityChunk, m: Dictionary, people: Dictionary) -> void:
	var hour := FarmersMarket.hour_now(ch)
	var day := FarmersMarket.weekday(ch)
	var st := FarmersMarket.status(m, hour, day)
	var lay := FarmersMarket.layout(m)
	var d := Detail.new(ch)
	_ends(ch, m, d)
	_marks(ch, m, lay, d)
	var queue: Array = ch.get_meta("vendor_queue", [])
	var stalls: Array = lay.stalls
	var states: Array = st.states
	var rect: Rect2 = ch.plan.block(ch.ix, ch.iz).rect
	for i in stalls.size():
		var s: Dictionary = stalls[i]
		var xf := stall_xf(m, s)
		match int(states[i]):
			FarmersMarket.State.UP:
				_stall_up(ch, m, s, xf, d, queue, people, rect)
			FarmersMarket.State.FOLDED:
				_stall_packed(ch, s, xf)
	ch.set_meta("vendor_queue", queue)
	_lights(ch, m, lay, states, d)
	for j in (lay.vans as Array).size():
		if bool(st.vans[j]):
			_van(ch, m, lay.vans[j])
	d.commit("MarketDetail")
	people.shoppers = int(st.shoppers)
	people.aisle = _aisle(m, lay)
	for k: String in ch._batch.keys():
		if not k.begins_with("fm_"):
			continue
		if k == "fm_canopy":
			ch._batch.set_draw_distance(k, CANOPY_DRAW)
		elif k.begins_with("fm_goods"):
			ch._batch.set_draw_distance(k, GOODS_DRAW)
		elif k.begins_with("fm_van"):
			ch._batch.set_draw_distance(k, CANOPY_DRAW)
		else:
			ch._batch.set_draw_distance(k, STOCK_DRAW)
		if not k.begins_with("fm_van"):
			ch._batch.set_shadow_reach(k, SHADOW_REACH)


## The aisle down the middle (between the two rows' fronts): {"t0", "t1", "o0", "o1"}.
static func _aisle(m: Dictionary, lay: Dictionary) -> Dictionary:
	var lo_front := -INF
	var hi_front := INF
	for s: Dictionary in lay.stalls:
		var front := float(s.o) - float(s.side) * FarmersMarketKit.HALF
		if int(s.side) < 0:
			lo_front = maxf(lo_front, front)
		else:
			hi_front = minf(hi_front, front)
	if lo_front == -INF:
		lo_front = -float(m.width) * 0.5 + 1.0
	if hi_front == INF:
		hi_front = float(m.width) * 0.5 - 1.0
	return {"t0": float(lay.len0), "t1": float(lay.len1), "o0": lo_front + 0.55, "o1": hi_front - 0.55}


static func _stall_up(ch: CityChunk, m: Dictionary, s: Dictionary, xf: Transform3D, d: Detail, queue: Array, people: Dictionary, rect: Rect2) -> void:
	var plan: CityPlan = ch.plan
	var id := "fm_%d" % int(s.i)
	var canvas: Color = FarmersMarketKit.CANVAS[int(s.canvas)]
	var gy := ch._gy(xf.origin.x, xf.origin.z)
	# The canopy: knocked by a blast or a car it flies off as one body.
	if not WorldState.is_destroyed(ch.key, id + "_c"):
		var mesh := FarmersMarketKit.canopy()
		var idx := ch._batch.add("fm_canopy", mesh, xf, Color.WHITE, canvas)
		var item := EncampmentItem.new()
		item.name = "MarketCanopy_%d" % int(s.i)
		item.chunk = ch
		item.item_id = id + "_c"
		item.instances = [["fm_canopy", idx]]
		item.mesh = mesh
		item.mass_kg = 22.0
		item.custom = canvas
		item.health = 120.0
		item.setup(Vector3(FarmersMarketKit.HALF * 2.0, 0.5, FarmersMarketKit.HALF * 2.0), FarmersMarketKit.EAVE + 0.3)
		item.transform = Transform3D(xf.basis, xf.origin + Vector3(0.0, gy, 0.0))
		ch.add_child(item)
	# The goods and their table.
	var goods_alive := not WorldState.is_destroyed(ch.key, id + "_g")
	var record: Variant = null
	if goods_alive:
		var gmesh := FarmersMarketKit.goods(int(s.kind), int(s.variant))
		var gkey := FarmersMarketKit.goods_key(int(s.kind), int(s.variant))
		var gidx := ch._batch.add(gkey, gmesh, xf)
		var item := EncampmentItem.new()
		item.name = "MarketTable_%d" % int(s.i)
		item.chunk = ch
		item.item_id = id + "_g"
		item.instances = [[gkey, gidx]]
		item.mesh = gmesh
		item.mass_kg = 45.0
		item.health = 60.0
		item.setup(Vector3(FarmersMarketKit.TABLE.x + 0.1, 0.95, FarmersMarketKit.TABLE.z + 0.1), 0.48)
		# The box stands over the front table, not the canopy's centre.
		(item.get_child(0) as Node3D).position.z = FarmersMarketKit.TABLE_Z
		item.transform = Transform3D(xf.basis, xf.origin + Vector3(0.0, gy, 0.0))
		ch.add_child(item)
		record = item
	# The grower's banner on the front valance.
	var name: String = s.name
	var bc: Color = BANNERS[absi(hash(name)) % BANNERS.size()]
	var light_bg := bc.get_luminance() > 0.5
	d.banner(xf, name, bc, Color(0.08, 0.08, 0.08) if light_bg else Color(0.96, 0.94, 0.88))
	# The stallholder behind the table, facing the aisle, and the browse spots in front of it.
	if goods_alive:
		var front := Vector2(xf.basis.z.x, xf.basis.z.z)
		var vat := xf * Vector3(0.0, 0.0, 0.2)
		(people.vendors as Array).append({"at": Vector2(vat.x, vat.z), "yaw": atan2(-front.x, -front.y),
			"seed": hash([plan.seed, m.seed, s.i, "vendor"]), "rect": rect})
		for k in 2:
			var p := xf * Vector3(-0.45 + 0.9 * k, 0.0, 1.78)
			queue.append({"p": Vector2(p.x, p.z), "yaw": atan2(front.x, front.y), "taken": null, "record": record})


## A stall setting up or packing: its tables folded and crates stacked, and the canopy either
## still standing over them (half struck, HALF_STRUCK of them), folded onto a cart beside the
## stack (every other stall in a row: the cart carries its neighbour's too), or already loaded.
const HALF_STRUCK := 0.3


static func _stall_packed(ch: CityChunk, s: Dictionary, xf: Transform3D) -> void:
	var v := int(s.variant) % 2
	ch._batch.add("fm_packed_%d" % v, FarmersMarketKit.packed(v), xf * Transform3D(Basis(), Vector3(0.0, 0.0, -0.6)))
	var canvas: Color = FarmersMarketKit.CANVAS[int(s.canvas)]
	if FarmersMarket._h01([int(s.i), int(s.variant), "half_struck"]) < HALF_STRUCK:
		ch._batch.add("fm_canopy", FarmersMarketKit.canopy(), xf, Color.WHITE, canvas)
	elif int(s.row) % 2 == 0:
		ch._batch.add("fm_folded", FarmersMarketKit.canopy_folded(), xf * Transform3D(Basis(Vector3.UP, 0.12), Vector3(0.1, 0.0, 0.75)), Color.WHITE, canvas)


## A van parked behind the stalls (the road van's far twin in a plain paint).
static func _van(ch: CityChunk, m: Dictionary, v: Dictionary) -> void:
	var paint := int(v.paint) % VAN_PAINTS.size()
	var body := van_mesh(paint)
	if body.is_empty():
		return
	var p := FarmersMarket.point(m, float(v.t), float(v.o))
	var along: Vector2 = FarmersMarket.dirs(m)[0] * float(v.dir)
	var fwd := Vector3(along.x, 0.0, along.y)
	var basis := Basis.looking_at(-fwd if bool(body.flip) else fwd, Vector3.UP)
	var xf := Transform3D(basis, Vector3(p.x, CityChunk.ROAD_TOP, p.y)) * Transform3D(Basis(), body.offset)
	ch._batch.add("fm_van_%d" % paint, body.mesh, xf)
	# Its collision: one box.
	var size: Vector3 = body.size
	var yaw := atan2(fwd.x, fwd.z)
	ch._add_shape(Vector3(size.x, size.y, size.z) if not bool(body.length_x) else Vector3(size.z, size.y, size.x), Vector3(p.x, CityChunk.ROAD_TOP + size.y * 0.5 + ch._gy(p.x, p.y), p.y), yaw)


## The road van's far twin, painted (Vehicle's paint shader, plain), and how to stand it on the
## road: {"mesh", "offset", "size", "length_x", "flip"}; {} without the model.
static func van_mesh(paint: int) -> Dictionary:
	if _vans.has(paint):
		return _vans[paint]
	var out := {}
	_vans[paint] = out
	var path: String = Vehicle.BODY_MODELS.get(Vehicle.BodyType.VAN, "")
	if path == "" or not ResourceLoader.exists(path):
		return out
	var inst := (load(path) as PackedScene).instantiate()
	var far: ArrayMesh = null
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if String((mi as MeshInstance3D).name).ends_with("_far"):
			far = (mi as MeshInstance3D).mesh as ArrayMesh
	inst.free()
	if far == null or far.get_surface_count() == 0:
		return out
	var mesh := far.duplicate() as ArrayMesh
	var box := far.get_aabb()
	for si in mesh.get_surface_count():
		var src := mesh.surface_get_material(si) as StandardMaterial3D
		if src == null:
			continue
		if String(src.resource_name).begins_with("paint"):
			mesh.surface_set_material(si, _paint(src, box, VAN_PAINTS[paint]))
		else:
			var pm := Vehicle._part_material(src)
			if pm != null:
				mesh.surface_set_material(si, pm)
	out.mesh = mesh
	# Its shadow from a box of its size (the body is ~8k triangles in four cascades).
	var shadow := BoxMesh.new()
	shadow.size = box.size * Vector3(0.92, 0.94, 0.97)
	var sm := ArrayMesh.new()
	var sarr := shadow.get_mesh_arrays()
	var verts: PackedVector3Array = sarr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] += box.get_center() - Vector3(0.0, box.size.y * 0.03, 0.0)
	sarr[Mesh.ARRAY_VERTEX] = verts
	sm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sarr)
	PropFactory._shadow_proxies[mesh] = sm
	out.offset = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	out.length_x = box.size.x > box.size.z
	out.size = box.size
	# The road bodies face +z (Vehicle's models); looking_at points -z down the road.
	out.flip = true
	return out


static func _paint(src: StandardMaterial3D, box: AABB, paint: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Vehicle.PAINT_SHADER
	mat.set_shader_parameter("albedo_tex", src.albedo_texture)
	mat.set_shader_parameter("paint", paint)
	if src.normal_texture:
		mat.set_shader_parameter("normal_tex", src.normal_texture)
		mat.set_shader_parameter("has_normal", true)
	var f: Dictionary = Vehicle.FINISHES[Vehicle.Finish.GLOSS]
	mat.set_shader_parameter("paint_metallic", f.metallic)
	mat.set_shader_parameter("paint_roughness", f.roughness)
	mat.set_shader_parameter("clearcoat_amount", f.clearcoat)
	mat.set_shader_parameter("clearcoat_roughness_value", f.cc_rough)
	mat.set_shader_parameter("flake_strength", f.flake)
	mat.set_shader_parameter("body_min", box.position)
	mat.set_shader_parameter("body_size", box.size)
	mat.set_shader_parameter("length_is_x", box.size.x >= box.size.z)
	return mat


## The bollards across both ends and the market's sign beside each.
static func _ends(ch: CityChunk, m: Dictionary, d: Detail) -> void:
	var half := float(m.width) * 0.5
	var along: Vector2 = FarmersMarket.dirs(m)[0]
	for end in 2:
		var t := float(m.lo) + FarmersMarket.CLOSE_INSET + BOLLARD_IN if end == 0 else float(m.hi) - FarmersMarket.CLOSE_INSET - BOLLARD_IN
		var n := maxi(2, int((half * 2.0 - 1.2) / BOLLARD_STEP))
		for k in n + 1:
			var o := lerpf(-half + 0.6, half - 0.6, float(k) / n)
			var p := FarmersMarket.point(m, t, o)
			ch._batch.add("fm_bollard", FarmersMarketKit.bollard(), Transform3D(Basis(), Vector3(p.x, CityChunk.ROAD_TOP, p.y)))
			ch._add_shape(Vector3(0.16, 0.9, 0.16), Vector3(p.x, CityChunk.ROAD_TOP + 0.45 + ch._gy(p.x, p.y), p.y))
		# The sign by the right-hand kerb, facing out of the market toward the crossing.
		var out_dir := -along if end == 0 else along
		var side := 1.0 if end == 0 else -1.0
		var sp := FarmersMarket.point(m, t + (out_dir.x + out_dir.y) * 0.6, side * (half - 0.55))
		var z3 := Vector3(out_dir.x, 0.0, out_dir.y)
		var xf := Transform3D(Basis(Vector3.UP.cross(z3), Vector3.UP, z3), Vector3(sp.x, CityChunk.ROAD_TOP, sp.y))
		ch._batch.add("fm_sign", FarmersMarketKit.sign_post(), xf)
		d.sign_text(xf, m)


## The stall marks painted on the asphalt: a white corner at each front corner of every space and
## its number.
static func _marks(ch: CityChunk, m: Dictionary, lay: Dictionary, d: Detail) -> void:
	var n := 0
	for s: Dictionary in lay.stalls:
		n += 1
		var xf := stall_xf(m, s)
		d.mark(xf, int(s.i) + 1)


## String lights across the aisle: between the front corners of two canopies facing each other,
## zig-zagging down the market; only where both are up.
static func _lights(ch: CityChunk, m: Dictionary, lay: Dictionary, states: Array, d: Detail) -> void:
	var rows := {-1: {}, 1: {}}
	var stalls: Array = lay.stalls
	for i in stalls.size():
		var s: Dictionary = stalls[i]
		if int(states[i]) == FarmersMarket.State.UP:
			(rows[int(s.side)] as Dictionary)[int(s.row)] = s
	var left: Dictionary = rows[-1]
	var right: Dictionary = rows[1]
	for r: int in left:
		if not right.has(r):
			continue
		var a: Dictionary = left[r]
		var b: Dictionary = right[r]
		var xa := stall_xf(m, a)
		var xb := stall_xf(m, b)
		var h := FarmersMarketKit.HALF - 0.02
		# A's front-left corner to B's front-right (a diagonal), and on odd rows the other way.
		var flip := r % 2 == 1
		var pa := xa * Vector3(-h if not flip else h, LIGHT_Y, h)
		var pb := xb * Vector3(h if not flip else -h, LIGHT_Y, h)
		d.string_lights(pa, pb)


## The banners, sign lettering, stall marks and string lights of one chunk: ONE mesh on the kit's
## material (sign faces and bulbs are codes on it).
class Detail:
	var ch: CityChunk
	var g := FarmersMarketKit.Geo.new()
	var st := SurfaceTool.new()
	var has_text := false

	func _init(chunk: CityChunk) -> void:
		ch = chunk
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func _lift(xf: Transform3D) -> Transform3D:
		return Transform3D(xf.basis, xf.origin + Vector3(0.0, ch._gy(xf.origin.x, xf.origin.z), 0.0))

	## A vinyl banner on the canopy's front valance with the grower's name.
	func banner(xf0: Transform3D, text: String, bg: Color, fg: Color) -> void:
		var xf := _lift(xf0)
		var z := FarmersMarketKit.HALF + 0.035
		var y := FarmersMarketKit.EAVE - FarmersMarketKit.VALANCE * 0.5
		var hw := 1.32
		var hh := FarmersMarketKit.VALANCE * 0.42
		var c := FarmersMarketKit.col(bg, FarmersMarketKit.C_FIXED)
		g.quad(xf * Vector3(-hw, y - hh, z), xf * Vector3(hw, y - hh, z), xf * Vector3(hw, y + hh, z), xf * Vector3(-hw, y + hh, z), xf.basis.z, c, Vector2(0.55, 0.0))
		# Grommets at the corners.
		for sx: float in [-1.0, 1.0]:
			g.abox(xf * Vector3(sx * (hw - 0.04), y + hh - 0.03, z + 0.004), Vector3(0.018, 0.018, 0.004), FarmersMarketKit.col(Color(0.75, 0.75, 0.72), FarmersMarketKit.C_METAL), Vector2(0.3, 0.9))
		_text(xf * Transform3D(Basis(), Vector3(0.0, y, z + 0.006)), text, hh * 1.25, fg, hw * 1.8)

	## The sign at an end: the market's name, its day and hours, and "no vehicles".
	func sign_text(xf0: Transform3D, m: Dictionary) -> void:
		var xf := _lift(xf0)
		var z := 0.024
		var street := String(m.name).replace(" FARMERS MARKET", "")
		_text(xf * Transform3D(Basis(), Vector3(0.0, 2.73, z)), "FARMERS", 0.12, Color(0.96, 0.94, 0.86), 0.8)
		_text(xf * Transform3D(Basis(), Vector3(0.0, 2.6, z)), "MARKET", 0.1, Color(0.96, 0.94, 0.86), 0.8)
		_text(xf * Transform3D(Basis(), Vector3(0.0, 2.38, z)), street, 0.075, Color(0.12, 0.2, 0.12), 0.82)
		_text(xf * Transform3D(Basis(), Vector3(0.0, 2.23, z)), String(FarmersMarket.DAY_NAMES[int(m.day)]), 0.09, Color(0.55, 0.1, 0.06), 0.82)
		_text(xf * Transform3D(Basis(), Vector3(0.0, 2.1, z)), "8 AM - 1 PM", 0.08, Color(0.1, 0.1, 0.1), 0.82)
		_text(xf * Transform3D(Basis(), Vector3(0.0, 1.92, z)), "NO VEHICLES", 0.06, Color(0.55, 0.1, 0.06), 0.82)

	## A painted stall space: white corners at its two front corners and its number at the front.
	func mark(xf0: Transform3D, number: int) -> void:
		var xf := _lift(xf0)
		var paint := FarmersMarketKit.col(Color(0.9, 0.9, 0.86), FarmersMarketKit.C_FIXED)
		var rm := Vector2(0.75, 0.0)
		var h := FarmersMarketKit.HALF
		var y := 0.006
		var w := 0.06
		var l := 0.45
		for sx: float in [-1.0, 1.0]:
			var c := Vector3(sx * h, y, h)
			_flat(xf, c + Vector3(-sx * l * 0.5, 0, -w * 0.5), Vector2(l, w), paint, rm)
			_flat(xf, c + Vector3(-sx * w * 0.5, 0, -l * 0.5), Vector2(w, l), paint, rm)
		var tx := xf * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, y + 0.001, h - 0.3))
		_text(tx, str(number), 0.24, Color(0.88, 0.88, 0.84), 0.6)

	func _flat(xf: Transform3D, c: Vector3, size: Vector2, cl: Color, rm: Vector2) -> void:
		var a := xf * (c + Vector3(-size.x * 0.5, 0, -size.y * 0.5))
		var b := xf * (c + Vector3(size.x * 0.5, 0, -size.y * 0.5))
		var d := xf * (c + Vector3(size.x * 0.5, 0, size.y * 0.5))
		var e := xf * (c + Vector3(-size.x * 0.5, 0, size.y * 0.5))
		g.quad(a, b, d, e, Vector3.UP, cl, rm)

	## A string of bulbs from `a` to `b` (both on the road's frame, lifted here), sagging.
	func string_lights(a0: Vector3, b0: Vector3) -> void:
		var a := a0 + Vector3(0.0, ch._gy(a0.x, a0.z), 0.0)
		var b := b0 + Vector3(0.0, ch._gy(b0.x, b0.z), 0.0)
		var length := a.distance_to(b)
		var n := maxi(2, int(length / BULB_STEP))
		var wire := FarmersMarketKit.col(Color(0.04, 0.04, 0.04), FarmersMarketKit.C_FIXED)
		var bulb := FarmersMarketKit.col(Color(1.0, 0.82, 0.55), FarmersMarketKit.C_BULB)
		var prev := a
		for k in range(1, n + 1):
			var f := float(k) / n
			var p := a.lerp(b, f) - Vector3(0.0, LIGHT_SAG * 4.0 * f * (1.0 - f), 0.0)
			g.tube(prev, p, 0.004, 3, wire, Vector2(0.6, 0.0))
			if k < n:
				g.tube(p, p - Vector3(0, 0.05, 0), 0.009, 5, wire, Vector2(0.5, 0.0))
				g.ellipsoid(Transform3D(Basis(), p - Vector3(0, 0.085, 0)), Vector3(0.024, 0.032, 0.024), 6, 4, bulb, Vector2(0.15, 0.0))
			prev = p

	## Lettering (TextMesh outlines) into the text tool, centred at `xf`, facing its +z.
	func _text(xf: Transform3D, text: String, height: float, cl: Color, max_w: float) -> void:
		StreetVendors._text(st, text, height, xf, cl, max_w)
		has_text = true

	func commit(node_name: String) -> void:
		if g.v.is_empty() and not has_text:
			return
		var mesh := g.commit(0.0) if not g.v.is_empty() else ArrayMesh.new()
		if has_text:
			# The lettering (StreetClutter's vertex format) as a second surface on the same material.
			var arrays := st.commit_to_arrays()
			if arrays.size() > 0 and arrays[Mesh.ARRAY_VERTEX] != null and not (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				mesh.surface_set_material(mesh.get_surface_count() - 1, FarmersMarketKit.material())
		if mesh.get_surface_count() == 0:
			return
		var mi := MeshInstance3D.new()
		mi.name = node_name
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = DETAIL_DRAW
		mi.visibility_range_end_margin = 12.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		ch.add_child(mi)


# --- People ------------------------------------------------------------------------------------

## The stallholder of the `index`-th stall that is up (a build step each), under the crowd cap.
static func spawn_vendor(ch: CityChunk, _m: Dictionary, people: Dictionary, index: int) -> void:
	var list: Array = people.vendors
	if index >= list.size():
		return
	# Spread over the market: every n-th stall when there are more stalls than vendors.
	var stride := maxi(1, ceili(float(list.size()) / MAX_VENDORS))
	var i := index * stride
	if i >= list.size():
		return
	var s: Dictionary = list[i]
	if not ch._take_crowd_room():
		return
	var ped := StreetVendor.new()
	ped.setup_vendor(s.rect, int(s.seed), s.at, float(s.yaw), false, 0.0)
	var at: Vector2 = s.at
	ped.position = Vector3(at.x, ch.ground_y(at.x, at.y) + 0.05, at.y)
	ch.add_child(ped)


## The `index`-th shopper, if the hour has that many (FarmersMarket.status()).
static func spawn_shopper(ch: CityChunk, m: Dictionary, people: Dictionary, index: int) -> void:
	if index >= int(people.get("shoppers", 0)) or not people.has("aisle"):
		return
	if not ch._take_crowd_room():
		return
	var ped := MarketShopper.new()
	var seed_value := hash([ch.plan.seed, m.seed, index, "shopper"])
	ped.setup_market(m, people.aisle, ch.plan.block(ch.ix, ch.iz).rect, seed_value)
	var start := ped._random_ring_point(4.0)
	ped.position = Vector3(start.x, ch.ground_y(start.x, start.y) + 0.1, start.y)
	ch.add_child(ped)
