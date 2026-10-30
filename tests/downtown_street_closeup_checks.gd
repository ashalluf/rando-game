extends RefCounted
## Downtown streets at arm's length (scripts/world/street_closeup.gd), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## A downtown block on Broadway built FULL: the kerb face is its own mesh on the close-up material
## (the ring keeps the pavement's), the gutter is the concrete pan and no piece of it lies over a
## kerb inlet's apron, the road paint is pressed, a surface lot's cars are real bodies up close (one
## per static car, which is hidden), a tree under a shed's deck is taken out, Broadway's goods keep
## off a car park's frontage; then the same block with STREET_CLOSEUP off: the same props and the
## same batch counts (nothing rolled), no KerbFace, the old strip.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_t._check(StreetCloseup.enabled, "street closeup: on by default (STREET_CLOSEUP=0 is the A/B)")
	var paint := PropFactory.road_paint_material()
	_t._check(is_equal_approx(float(paint.get_shader_parameter("thickness")), StreetCloseup.PAINT_THICK) \
		and paint.shader.code.contains("thickness"), "street closeup: the road paint is pressed to %.0f mm" % (StreetCloseup.PAINT_THICK * 1000.0))
	# The pan's 8 mm box tops out at PAN_LIFT + 4 mm; the lowest pressed bar (a dash, its box from
	# 5 mm) at 5 mm + PAINT_THICK: 2 mm or more between them.
	_t._check(StreetCloseup.PAN_LIFT + 0.004 <= 0.005 + StreetCloseup.PAINT_THICK - 0.002,
		"street closeup: the pan tops out under the pressed paint (crosswalk bars cross it)")
	var k := _pick(plan)
	_t._check(k != Vector2i(-99999, -99999), "street closeup: found a downtown block on Broadway")
	if k == Vector2i(-99999, -99999):
		return
	_goods(plan)
	var on: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	on.build()
	_block(on)
	_sheds(on)
	StreetCloseup.enabled = false
	var off: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	off.build()
	StreetCloseup.enabled = true
	_ab(on, off)
	_drop(on)
	_drop(off)
	_lot_cars(city, plan)


## A downtown block of buildings fronting Broadway (x 2991): the block west of it near 5th St.
func _pick(plan: CityPlan) -> Vector2i:
	var home := plan.block_index_at(Vector2(2960.0, -60.0))
	for r in 3:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var k := home + Vector2i(dx, dz)
				var b := plan.block(k.x, k.y)
				if int(b.kind) == CityPlan.BlockKind.BUILDINGS and not b.has("site") and int(b.district) == CityPlan.District.DOWNTOWN:
					return k
	return Vector2i(-99999, -99999)


func _block(ch: CityChunk) -> void:
	var face := ch.get_node_or_null("KerbFace") as MeshInstance3D
	var ring := ch.get_node_or_null("KerbRing") as MeshInstance3D
	_t._check(face != null and face.material_override is ShaderMaterial \
		and (face.material_override as ShaderMaterial).shader.resource_path.ends_with("kerb_closeup.gdshader"),
		"street closeup: the kerb face is its own mesh on the close-up material")
	_t._check(ring != null and not (ring.material_override as ShaderMaterial).shader.resource_path.ends_with("kerb_closeup.gdshader"),
		"street closeup: the ring's top keeps the pavement's material")
	var data := ch._batch.data()
	_t._check(data.has("gutter") and data.gutter.mesh == StreetCloseup.pan_mesh() and (data.gutter.xforms as Array).size() > 8,
		"street closeup: the gutter is the concrete pan (%d pieces)" % ((data.gutter.xforms as Array).size() if data.has("gutter") else 0))
	# No pan piece over a kerb inlet's apron: worked out per edge as RoadHardware lays them.
	var rect: Rect2 = ch.plan.block(ch.ix, ch.iz).rect
	var over := 0
	var inlets := 0
	if data.has("gutter"):
		for e: Array in CityChunk._sidewalk_edges(rect):
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var dir := (b - a).normalized()
			for at: float in StreetCloseup.inlet_alongs(ch, e):
				inlets += 1
				var ip := a + dir * at
				for x: Transform3D in data.gutter.xforms:
					var half := 2.0 * x.basis.get_scale().z
					var c := Vector2(x.origin.x, x.origin.z)
					var off := c - ip
					if absf(off.dot(dir)) < half + RoadHardware.INLET_APRON - 0.01 and absf(off.dot(Vector2(-dir.y, dir.x))) < 1.0:
						over += 1
	_t._check(over == 0, "street closeup: no gutter pan over a kerb inlet's apron (%d inlets, %d over)" % [inlets, over])
	# The pan's kerb side flag is consistent: every piece's custom.r is 0 or 1.
	var flags := true
	if data.has("gutter"):
		for c: Color in data.gutter.custom:
			flags = flags and (is_equal_approx(c.r, 0.0) or is_equal_approx(c.r, 1.0))
	_t._check(flags, "street closeup: every pan piece says which side its kerb is")


## A tree under a shed's deck is taken out of its batch (one test shed round the first tree).
func _sheds(ch: CityChunk) -> void:
	var data := ch._batch.data()
	var key := ""
	for kk: String in data:
		if (kk.begins_with("tree_") and kk != "tree_grate") or kk.begins_with("palm_") or kk.begins_with("la_"):
			key = kk
			break
	if key == "":
		_t._check(true, "street closeup: (no street tree on the block to shed)")
		return
	var o: Vector3 = (data[key].xforms[0] as Transform3D).origin
	var p := Vector2(o.x, o.z)
	ch.set_meta("sc_sheds", [PackedVector2Array([p + Vector2(-0.5, -0.5), p + Vector2(0.5, -0.5), p + Vector2(0.5, 0.5), p + Vector2(-0.5, 0.5)])])
	var gone := StreetCloseup.clear_sheds(ch, ch._mm_nodes)
	_t._check(gone >= 1 and not ch.has_meta("sc_sheds"), "street closeup: a street tree under a shed's deck is taken out (%d)" % gone)


## Broadway's goods: never in front of a surface car park or a vacant lot (pure).
func _goods(plan: CityPlan) -> void:
	var found := false
	var ok := true
	var shop_ok := true
	for bz in range(-12, 12):
		for bx in range(-3, 3):
			var home := plan.block_index_at(Vector2(2960.0, 0.0)) + Vector2i(bx, bz)
			for lot: Dictionary in plan.lots(home.x, home.y):
				if not lot.has("cell"):
					continue
				var c: Vector2 = (lot.cell as Rect2).get_center()
				if lot.get("parking", false):
					found = true
					ok = ok and StreetCloseup.goods_blocked(plan, home.x, home.y, c)
				elif VacantLots.kind_of(plan, home.x, home.y, lot) == VacantLots.NONE:
					shop_ok = shop_ok and not StreetCloseup.goods_blocked(plan, home.x, home.y, c) or _near_other(plan, home, lot)
	_t._check(ok, "street closeup: Broadway's goods keep off a car park's frontage%s" % ("" if found else " (no car park found nearby)"))
	_t._check(shop_ok, "street closeup: a lot with a building still gets its goods")


## A lot cell within 0.8 m of a car park's or a vacant lot's (goods_blocked's margin) may say either.
func _near_other(plan: CityPlan, k: Vector2i, lot: Dictionary) -> bool:
	for o: Dictionary in plan.lots(k.x, k.y):
		if o == lot or not o.has("cell"):
			continue
		if (o.get("parking", false) or VacantLots.kind_of(plan, k.x, k.y, o) != VacantLots.NONE) and (o.cell as Rect2).grow(0.8).has_point((lot.cell as Rect2).get_center()):
			return true
	return false


## The same block with the close-up pass off: the same props and batch counts, the old pieces.
func _ab(on: CityChunk, off: CityChunk) -> void:
	# The stop benches (their own id sequence, laid at the finish) keep further off cafe sets.
	var ra := on.prop_records.filter(func(r: Dictionary) -> bool: return not String(r.id).begins_with("ad_bench"))
	var rb := off.prop_records.filter(func(r: Dictionary) -> bool: return not String(r.id).begins_with("ad_bench"))
	var same := ra.size() == rb.size()
	if same:
		for i in ra.size():
			var a: Dictionary = ra[i]
			var b: Dictionary = rb[i]
			same = same and a.id == b.id and (a.position as Vector3).is_equal_approx(b.position)
	_t._check(same, "street closeup: the same props in the same places with it off (%d / %d)" % [ra.size(), rb.size()])
	var counts := true
	var bad := ""
	var don := on._batch.data()
	var doff := off._batch.data()
	for key: String in doff:
		# The pan is split round the inlets; Broadway's goods keep off car parks.
		if key == "gutter" or key.begins_with("bw_"):
			continue
		var n_on := (don[key].xforms as Array).size() if don.has(key) else -1
		if n_on != (doff[key].xforms as Array).size():
			counts = false
			bad = key
	_t._check(counts, "street closeup: every other batch has the same instances with it off%s" % ("" if bad == "" else " (%s differs)" % bad))
	_t._check(off.get_node_or_null("KerbFace") == null and doff.has("gutter") and doff.gutter.mesh == PropFactory.gutter(),
		"street closeup: off, the kerb face is in the ring and the gutter is the old strip")


## A surface car park's static cars are real bodies within REAL_CAR_NEAR: a downtown or midtown
## block with a parking lot, built FULL.
func _lot_cars(city: Node3D, plan: CityPlan) -> void:
	var k := Vector2i(-99999, -99999)
	for a: Vector2 in [Vector2(2960.0, 0.0), Vector2(2400.0, 900.0), Vector2(1200.0, 600.0)]:
		var home := plan.block_index_at(a)
		for r in 4:
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if k.x != -99999:
						continue
					var kk := home + Vector2i(dx, dz)
					var b := plan.block(kk.x, kk.y)
					if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site"):
						continue
					for lot: Dictionary in plan.lots(kk.x, kk.y):
						if lot.get("parking", false):
							k = kk
	if k.x == -99999:
		_t._check(true, "street closeup: (no surface car park found to check)")
		return
	var ch: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	ch.build()
	var statics := 0
	for key: String in ch._batch.data():
		if key.begins_with("apark_car_"):
			statics += (ch._batch.data()[key].xforms as Array).size()
	var near := 0
	var far := 0
	var ranged := true
	for c in ch.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("LotRealCars"):
			near += (c as MultiMeshInstance3D).multimesh.instance_count
			ranged = ranged and is_equal_approx((c as MultiMeshInstance3D).visibility_range_end, StreetCloseup.REAL_CAR_NEAR)
		elif c is MultiMeshInstance3D and String(c.name).begins_with("LotCars"):
			far += (c as MultiMeshInstance3D).multimesh.instance_count
			ranged = ranged and is_equal_approx((c as MultiMeshInstance3D).visibility_range_begin, StreetCloseup.REAL_CAR_NEAR)
	_t._check(statics > 0 and near == far and near > 0 and near <= statics and ranged,
		"street closeup: a car park's cars are real bodies up close (%d of %d static cars, %d stand-ins past %.0f m)" % [near, statics, far, StreetCloseup.REAL_CAR_NEAR])
	_drop(ch)


func _drop(chunk: CityChunk) -> void:
	chunk.get_parent().remove_child(chunk)
	chunk.free()
