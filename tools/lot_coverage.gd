extends SceneTree
## How much of the city's ground the buildings cover, block by block, and what the rest is.
## Walks every BUILDINGS block inside a rect, lays each lot's building out exactly as
## CityChunk._build_lot() does (Building.plan_only(), no nodes, podium_lot set where LotFill
## runs) and rasterises each block's inner rect (inside the pavement ring) on a GRID m grid:
##   built     under a building part standing on the ground (podiums included) or a downtown tower
##   yard      a pocket garden (lawn), or a freeway corridor lot (ivy)
##   forecourt a lot's ground the building leaves, out to its grid cell, and the cells a
##             landmark's square dropped (LotFill: paving, planters, benches)
##   parking   a surface car park (CityPlan.lots() "parking", LotFill)
##   bare      the block's plain paving: nothing on it
## With FILL=0 the lot fill is left out (what the city was before it: forecourt and parking are
## bare, no podiums). Also the shapes' own coverage of their lot and the podiums built.
## Headless is fine: nothing is drawn.
##
##   godot --headless --path . --script tools/lot_coverage.gd
##
## Env: RECT=x,z,w,d (default downtown's game extent), SEED (default 1337), FILL (default 1),
## GRID (default 1.0).
## Everything is loaded dynamically: this script compiles before the autoloads exist.
func _initialize() -> void:
	await process_frame
	var plan_script: GDScript = load("res://scripts/world/city_plan.gd")
	var macro_script: GDScript = load("res://scripts/world/macro_map.gd")
	var building_scene: PackedScene = load("res://scenes/props/building.tscn")
	var fill_script: GDScript = load("res://scripts/world/lot_fill.gd")
	var lm_script: GDScript = load("res://scripts/world/landmarks.gd")
	var dt_script: GDScript = load("res://scripts/world/landmark_downtown.gd")
	var fill_on := OS.get_environment("FILL") != "0"
	var grid := float(OS.get_environment("GRID")) if OS.get_environment("GRID") != "" else 1.0
	var plan = plan_script.new()
	plan.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	plan.macro = macro_script.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	var area := Rect2(1650.0, -1750.0, 2300.0, 3770.0)
	var env := OS.get_environment("RECT")
	if env != "":
		var v := env.split_floats(",")
		area = Rect2(v[0], v[1], v[2], v[3])
	var lo: Vector2i = plan.block_index_at(area.position)
	var hi: Vector2i = plan.block_index_at(area.end)
	var names := ["DOWNTOWN", "MIDTOWN", "SUBURBS", "INDUSTRIAL", "CAMPUS", "BEACHTOWN"]
	var shape_names := ["SLAB", "TOWER", "STEPPED", "PODIUM_TOWER", "L_SHAPE", "SETBACK", "CROWN", "WAREHOUSE"]
	var kinds := ["bare", "built", "yard", "forecourt", "parking"]
	var tot := {}
	var shape_cov := {}
	var podiums := {}
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b: Dictionary = plan.block(bx, bz)
			if int(b.kind) != 0 or b.has("site"):
				continue
			var brect: Rect2 = b.rect
			if not area.has_point(brect.get_center()) or int(plan.zone_at(brect.get_center())) != 0:
				continue
			# A block a landmark claims whole (the civic set) is the landmark's own ground.
			if lm_script.claims(brect):
				continue
			var boost: float = plan.macro.skyline_boost(brect.get_center())
			var d: String = names[int(b.district)]
			if int(b.district) == 0:
				d += "_core" if boost > 0.55 else "_rest"
			var filled: bool = fill_on and int(b.district) in fill_script.DISTRICTS
			if not tot.has(d):
				tot[d] = {"blocks": 0, "inner": 0.0, "lots": 0.0, "lots_n": 0, "lot_built": 0.0, "k": [0, 0, 0, 0, 0]}
			var t: Dictionary = tot[d]
			var inner: Rect2 = brect.grow(-plan.sidewalk_width)
			t.blocks += 1
			var gx := maxi(1, int(inner.size.x / grid))
			var gz := maxi(1, int(inner.size.y / grid))
			var cells := PackedByteArray()
			cells.resize(gx * gz)
			var box := [cells, inner, grid, gx, gz]
			# The box is the grid's only holder: a packed array written with two holders is copied.
			cells = PackedByteArray()
			# The downtown towers standing in the block.
			for lm in lm_script.all():
				if dt_script.is_tower(str(lm.id)):
					var fp: Rect2 = dt_script.footprint(lm)
					if fp.intersects(inner):
						_paint(box, fp, 1)
			for lot: Dictionary in plan.lots(bx, bz):
				var size: Vector2 = lot.size
				var lot_rect := Rect2((lot.center as Vector2) - size * 0.5, size)
				var cell: Rect2 = lot.get("cell", lot_rect)
				t.lots += size.x * size.y
				t.lots_n += 1
				if lot.yard:
					_paint(box, lot_rect, 2)
					continue
				if plan.macro.freeway and (plan.macro.freeway.blocks(lot.center, 14.0) or plan.macro.freeway.blocks_rect(lot_rect, 3.0)):
					_paint(box, lot_rect, 2)
					continue
				if filled and lot.get("parking", false):
					_paint(box, cell, 4)
					continue
				var bld = building_scene.instantiate()
				bld.seed = lot.seed
				bld.lot_size = size
				var target: float = plan.lot_height(lot.seed, int(b.district), boost)
				bld.min_height = target * 0.88
				bld.max_height = target
				var sh: Array[int] = []
				sh.assign(plan_script.lot_shapes(int(b.district), boost))
				bld.shape_options = sh
				var fi: Array[int] = []
				fi.assign(plan_script.lot_finishes(int(b.district), boost))
				bld.finish_options = fi
				bld.podium_lot = filled
				bld.plan_only()
				var ground := 0.0
				for part: Dictionary in bld.parts:
					var c: Vector3 = part.center
					var s: Vector3 = part.size
					if c.y - s.y * 0.5 > 0.01:
						continue
					_paint(box, Rect2((lot.center as Vector2) + Vector2(c.x - s.x * 0.5, c.z - s.z * 0.5), Vector2(s.x, s.z)), 1)
					ground += s.x * s.z
				t.lot_built += minf(ground, size.x * size.y)
				if filled:
					_paint(box, cell, 3)
				if int(bld.podium_kind) > 0:
					var pk := d + (" parking" if int(bld.podium_kind) == 2 else " retail")
					podiums[pk] = int(podiums.get(pk, 0)) + 1
				var sk: String = d + " " + shape_names[int(bld.shape)]
				if not shape_cov.has(sk):
					shape_cov[sk] = [0, 0.0]
				shape_cov[sk][0] += 1
				shape_cov[sk][1] += minf(ground / (size.x * size.y), 1.0)
				bld.free()
			if filled:
				# What a landmark's square dropped, less the landmark (LotFill.leftovers()).
				var holes: Array[Rect2] = []
				for lm in lm_script.all():
					if lm.get("area") is Dictionary:
						continue
					var r: float = lm.radius
					var sq := Rect2((lm.anchor as Vector2) - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
					if sq.intersects(brect):
						holes.append(dt_script.footprint(lm).grow(4.0) if dt_script.is_tower(str(lm.id)) else sq)
				for cell: Rect2 in plan.dropped_cells(bx, bz):
					for piece: Rect2 in fill_script._minus(cell, holes, 0.0):
						_paint(box, piece, 3)
			var counts: Array = t.k
			var painted: PackedByteArray = box[0]
			for k in painted.size():
				counts[painted[k]] += 1
			t.inner += float(gx * gz)
	for d: String in tot:
		var t: Dictionary = tot[d]
		var line := "COVER %s blocks %d lots %d | buildings cover %.1f %% of their lots |" % [d, t.blocks, t.lots_n, 100.0 * t.lot_built / maxf(t.lots, 1.0)]
		for k in kinds.size():
			line += " %s %.1f %%" % [kinds[k], 100.0 * float(t.k[k]) / t.inner]
		print(line)
	var keys := shape_cov.keys()
	keys.sort()
	for k: String in keys:
		print("SHAPE %s n %d mean lot cover %.1f %%" % [k, shape_cov[k][0], 100.0 * shape_cov[k][1] / shape_cov[k][0]])
	var pk := podiums.keys()
	pk.sort()
	for k: String in pk:
		print("PODIUM %s %d" % [k, podiums[k]])
	quit()


## Paints a world rect into a block's grid (`box` = [cells, inner, grid, gx, gz]) with a kind (1
## built, 2 yard, 3 forecourt, 4 parking), only over bare ground - built paints over anything.
func _paint(box: Array, r: Rect2, kind: int) -> void:
	var cells: PackedByteArray = box[0]
	box[0] = null
	var inner: Rect2 = box[1]
	var grid: float = box[2]
	var gx: int = box[3]
	var gz: int = box[4]
	var i0 := clampi(int((r.position.x - inner.position.x) / grid), 0, gx)
	var i1 := clampi(int(ceil((r.end.x - inner.position.x) / grid)), 0, gx)
	var j0 := clampi(int((r.position.y - inner.position.y) / grid), 0, gz)
	var j1 := clampi(int(ceil((r.end.y - inner.position.y) / grid)), 0, gz)
	for j in range(j0, j1):
		var cz := inner.position.y + (j + 0.5) * grid
		if cz < r.position.y or cz > r.end.y:
			continue
		for i in range(i0, i1):
			var cx := inner.position.x + (i + 0.5) * grid
			if cx < r.position.x or cx > r.end.x:
				continue
			var k := j * gx + i
			if cells[k] == 1:
				continue
			if kind == 1 or cells[k] == 0:
				cells[k] = kind
	box[0] = cells
