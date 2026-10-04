extends RefCounted
## The far city's buildings (docs/HANDOFF.md 9bd): checks for tests/smoke_test.gd that a far box
## carries its near building, field for field. Loaded at run time, so it compiles after the
## autoloads and can name Building, FarBuilding, CityChunk and Skyline. Bookkeeping and source
## reads only - under --headless no shader runs, so these guard the contract (the code, the
## shared grid, the shared rolls, the palette copies), and tools/glshot/far_building_shot.gd
## with far_pair.py measures the pixels.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_codes_exact()
	_parts_carry_the_building()
	_roof_plan_is_the_roof()
	_tiers_take_their_share(city)
	_shaders_agree()


## Every 20-bit code survives a float32 basis and comes back as itself, and the shear it adds is
## under the 4 mm the bounds and the AABB checks can ignore.
func _codes_exact() -> void:
	var ok := true
	var worst := 0.0
	for base: int in [0, 1, 777, 524287, 1048575 - 6]:
		var codes := [base, base + 1, base + 2, base + 3, base + 4, base + 5]
		var b := FarBuilding.encode(Vector3(31.7, 143.25, 18.9), codes)
		var back := FarBuilding.codes(b)
		for k in 6:
			ok = ok and back[k] == codes[k]
		worst = maxf(worst, maxf(absf(b.x.y), absf(b.z.y)))
		var box := Transform3D(b, Vector3.ZERO) * AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
		worst = maxf(worst, absf(box.size.x - 31.7) * 0.5)
	_t._check(ok and worst < 0.004, "the far boxes' codes survive a float basis exactly and shear them under 4 mm (%.4f m)" % worst)


## A planned building's far boxes decode to its own facade: the grid Building.part_grid() gives
## the near walls, its palette entries, its rolls, its plinth and parapet.
func _parts_carry_the_building() -> void:
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var checked := 0
	var wrong: Array[String] = []
	var plant := 0
	var podiums := 0
	for i in 40:
		var b: Building = scene.instantiate()
		b.seed = 9000 + i * 131
		b.lot_size = Vector2(26.0 + float(i % 5) * 6.0, 24.0 + float(i % 3) * 8.0)
		b.min_height = 8.0 + float(i % 7) * 12.0
		b.max_height = b.min_height * 1.6
		b.podium_lot = i % 2 == 0
		b.plinth_depth = 0.4 + 0.1 * float(i % 4)
		var style := b.plan_only()
		var boxes := FarBuilding.boxes(b, style, b.plinth_depth)
		for pi in b.parts.size():
			var part: Dictionary = b.parts[pi]
			var xf: Transform3D = boxes[pi][0]
			var custom: Color = boxes[pi][2]
			var d := FarBuilding.decode(xf.basis)
			var grid := b.part_grid(part, style)
			var size: Vector3 = part.size
			var ext := b.plinth_depth if bool(grid.on_ground) else 0.0
			var rise := b.parapet_rise(part)
			var why := ""
			if not is_equal_approx(custom.a, FarBuilding.PART_FLAG):
				why += " flag"
			if d.seed != b.seed % 1000 or d.finish != int(b.finish) or d.window_style != int(b.window_style) or d.roof_style != b.roof_style:
				why += " identity"
			if Building.LIT_COLORS[d.lit] != style.lit or Building.WINDOW_TINTS[d.tint] != style.tint:
				why += " palette"
			if d.cols_x != int(grid.cols_x) or d.cols_z != int(grid.cols_z) or d.rows != int(grid.rows):
				why += " grid"
			if bool(d.storefront) != (float(grid.storefront) > 0.0) or bool(d.parking) != bool(grid.parking) or bool(d.chamfer) != (float(grid.cut_x) > 0.0) or bool(d.crown) != (float(grid.crown) >= 0.0):
				why += " flags"
			if absf(d.lit_ratio - float(style.lit_ratio)) > 1.0 / 65535.0 or absf(d.base_h - float(grid.base_h)) > 0.051:
				why += " numbers"
			if absf(d.ext - ext) > 0.006 or absf(d.rise - rise) > 0.006:
				why += " plinth/parapet"
			if not d.size.is_equal_approx(Vector3(size.x, size.y + ext + rise, size.z)):
				why += " size"
			var paints: Array = Building.FRAME_PAINTS.get(b.finish, Building.FRAME_PAINTS[Building.Finish.FLAT])
			if paints[d.frame] != b.frame_paint():
				why += " frame"
			if FarBuilding.WALL_SETS[d.wall_set] != (style.wall_set as Array)[0]:
				why += " wall set"
			for f in 4:
				if int(d.spans[f]) != int(b._shop_spans()[f]):
					why += " spans"
					break
			if why != "" and wrong.size() < 4:
				wrong.append("seed %d part %d:%s" % [b.seed, pi, why])
			checked += 1
			if int(part.get("podium", 0)) > 0:
				podiums += 1
		plant += boxes.size() - b.parts.size()
		b.free()
	_t._check(checked > 60 and wrong.is_empty() and podiums > 0 and plant > 0,
		"a far box decodes to its near building's own facade, grid, plinth and parapet (%d parts, %d podiums, %d plant boxes%s)" % [checked, podiums, plant, (": " + ", ".join(wrong)) if wrong else ""])


## The far roof plant is the near roof plant: Building.roof_plan() on a planned building lists
## exactly what generate() builds on the same seed, unit for unit, roll for roll.
func _roof_plan_is_the_roof() -> void:
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var same := true
	var props := 0
	var kinds := {}
	for i in 12:
		var built: Building = scene.instantiate()
		var planned: Building = scene.instantiate()
		for b: Building in [built, planned]:
			b.seed = 4400 + i * 53
			b.lot_size = Vector2(32.0, 30.0)
			b.min_height = 12.0 + float(i) * 9.0
			b.max_height = b.min_height * 1.4
			b.position = Vector3(6000.0 + float(i) * 60.0, 0.0, 6000.0)
		_t.add_child(built)
		planned.plan_only()
		var plan: Array = planned.roof_plan()
		var real: Array = built.roof_props
		same = same and plan.size() == real.size() and not real.is_empty()
		for k in mini(plan.size(), real.size()):
			var a: Array = plan[k]
			var r: Array = real[k]
			same = same and a[0] == r[0] and (a[1] as Vector3).is_equal_approx(r[1]) and str(a[2]) == str(r[2]) and a[3] == r[3]
			kinds[r[0]] = true
		props += real.size()
		built.free()
		planned.free()
	_t._check(same and props > 20 and kinds.size() >= 4, "the far roof plant is the one the near building builds (%d units of %d kinds, same spots, same rolls)" % [props, kinds.size()])


## The LOD chunk draws every unit of roof plant; the far city keeps only what makes a silhouette
## out there, and every coded part.
func _tiers_take_their_share(city: Node3D) -> void:
	var streamer := city as CityStreamer
	if streamer == null or not FarBuilding.enabled:
		_t._check(FarBuilding.enabled, "the far boxes are coded (FarBuilding.enabled)")
		return
	var plan: CityPlan = streamer.plan
	var parts := 0
	var small := 0
	var big := 0
	var kept_small := 0
	for k: Vector2i in [Vector2i(7, 2), Vector2i(3, -3), Vector2i(10, 5), Vector2i(5, -2), Vector2i(-3, 6)]:
		var b := plan.block(k.x, k.y)
		if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
			continue
		var cap := CityChunk.new()
		cap.plan = plan
		cap.ix = k.x
		cap.iz = k.y
		cap.level = CityChunk.Level.LOD
		cap.style = streamer.chunk_style()
		cap.capturing = true
		cap.build()
		var lb: Dictionary = cap.captured.batch.get("lod_box", {"custom": []})
		for c: Color in lb.custom:
			if is_equal_approx(c.a, FarBuilding.PART_FLAG):
				parts += 1
			elif is_equal_approx(c.a, FarBuilding.PLANT_FLAG):
				if c.g > 0.5:
					big += 1
				else:
					small += 1
					if FarBuilding.far_keeps(c):
						kept_small += 1
		cap.free()
	_t._check(parts > 20 and big > 0 and small > big and kept_small == 0,
		"the LOD ring builds every roof unit, the far city only the silhouettes (%d parts, %d silhouette units, %d small ones left to the LOD ring)" % [parts, big, small])


## The two building shaders roll the lit offices and the spandrels from the same include, and the
## far one's copies of Building's palettes are Building's.
func _shaders_agree() -> void:
	var near := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	var far := FileAccess.get_file_as_string("res://shaders/building_lod.gdshader")
	var inc := "#include \"res://shaders/window_lights.gdshaderinc\""
	var shared := near.contains(inc) and far.contains(inc) and near.contains("window_lit(seed, face_id, row, col, lit_ratio)") \
		and far.contains("window_lit(sd, face_id, row, col, lit_ratio_p)") and near.contains("spandrel_pale(seed)") and far.contains("spandrel_pale(sd)")
	_t._check(shared and not near.contains("hash31(vec3(floor(col / 3.0), row"), "the near walls and the far boxes light the same offices (window_lights.gdshaderinc, integer rolls)")
	var scale_ok := far.contains("268435456.0") and is_equal_approx(FarBuilding.CODE_SCALE * 268435456.0, 1.0)
	var why := ""
	for pair: Array in [["window_tint_srgb(int i)", Building.WINDOW_TINTS], ["lit_srgb(int i)", Building.LIT_COLORS],
			["shop_frame_far(uint shop)", Building.SHOP_FRAME_COLORS]]:
		var got := _colours(far, pair[0])
		if got != pair[1]:
			why += " %s" % pair[0]
	var paints := _colours(far, "frame_paint_srgb(int finish, int i)")
	# The function lists brick, panels, glass, then flat (the fall-through).
	var want: Array = Building.FRAME_PAINTS[Building.Finish.BRICK] + Building.FRAME_PAINTS[Building.Finish.PANELS] \
		+ Building.FRAME_PAINTS[Building.Finish.GLASS] + Building.FRAME_PAINTS[Building.Finish.FLAT]
	if paints != want:
		why += " frame_paint_srgb"
	# The wall texture means, linear then raw per set, in FarBuilding.WALL_SETS order.
	var means := _colours(far, "vec3 wall_tex_mean(int i)")
	var want_means: Array = []
	for key: String in FarBuilding.WALL_SETS:
		want_means.append_array(Building.WALL_TEXTURE_MEAN[key])
	if means != want_means or FarBuilding.WALL_SETS.size() != Building.WALL_TEXTURE_MEAN.size():
		why += " wall_tex_mean"
	_t._check(scale_ok and why == "", "the far shader decodes FarBuilding's scale and copies Building's palettes exactly (%s)" % ("all match" if why == "" else "differ:" + why))


## The vec3(r, g, b) constants in a shader function's body, as Colors, in order.
func _colours(code: String, signature: String) -> Array:
	var at := code.find(signature)
	if at < 0:
		return []
	var body := code.substr(at, code.find("\n}", at) - at)
	var re := RegEx.create_from_string("vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\)")
	var out: Array = []
	for m in re.search_all(body):
		out.append(Color(m.get_string(1).to_float(), m.get_string(2).to_float(), m.get_string(3).to_float()))
	return out
