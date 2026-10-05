class_name LotFill
extends RefCounted
## The ground between downtown's and midtown's buildings (2026-09-27). Every tower stood alone on
## its lot and the rest of the lot, the gaps between lots and whatever a landmark's square had
## pushed out were the block's bare pale paving: 41 % of downtown's buildable ground (54 % in the
## financial core) and 55 % of midtown's, a sea of tan concrete from the street and the air
## (tools/lot_coverage.gd measures it). Real downtown Los Angeles has almost none of that. So:
##   - a slender tower on a big lot stands on a PODIUM filling most of it, a parking deck or
##     retail and lobby storeys (Building._add_podium(); CityChunk sets `podium_lot`), with its
##     drive-in and roof deck of parked cars laid here;
##   - what the building leaves of its lot, out to the lot's grid cell, is a FORECOURT: its own
##     paving (granite setts, dark pavers, limestone - not the public pavement), raised planters
##     with shrubs and a tree, benches facing them, bollards along the street, a reflecting pool
##     or a bronze on a plinth in the bigger ones (forecourt());
##   - some lots are SURFACE CAR PARKS (CityPlan.lots() "parking"): asphalt, stall rows and
##     aisles, the static parked cars, a pay booth, masts, a low wall, a hedge or chain-link on the
##     street sides (surface_lot());
##   - the cells a landmark's square dropped are forecourt round the landmark, or a car park
##     (leftovers()).
## Every roll is a private rng seeded from the plan seed and the lot (never the block rng or the
## building's own), so nothing else in the city moves. The ground goes through the chunk: on a
## FULL chunk each kind of paving is ONE merged mesh a chunk (commit()), on a LOD chunk it joins
## the merged far ground, and in the far city's capture it is recorded like any slab - so the
## far plates darken where there is asphalt. The furniture is FULL only, through the chunk's
## batches and merged boxes (planter kerbs share the plinths' concrete), a draw or two a kind.

## Districts whose lots get podiums, forecourts and car parks.
const DISTRICTS := [CityPlan.District.DOWNTOWN, CityPlan.District.MIDTOWN]
## Top of the forecourt paving, and of the asphalt (driveways lie on the paving), over the
## pavement slab (metres).
const PAVING_LIFT := 0.04
const ASPHALT_LIFT := 0.05
## Forecourt paving looks: [texture set, metres a tile, tint].
## (A block uses one of them.)
## None of them is the public pavement's pale tan, or a forecourt reads as more bare pavement.
const PAVINGS := [
	["paving", 2.2, Color(0.72, 0.72, 0.72)],
	["pavers", 1.25, Color(0.62, 0.61, 0.60)],
	["paving", 1.6, Color(0.64, 0.68, 0.73)],
	["pavers", 1.5, Color(0.80, 0.55, 0.45)],
]
## What each vertex of the fill mesh is, in shaders/lot_ground.gdshader's COLOR.r (16ths): the
## four pavings are 0-3.
const KIND_ASPHALT := 4
const KIND_LAWN := 5
const KIND_SOIL := 6
const KIND_DARK := 7
const KIND_SWIM := 8
## The colour each paving and the asphalt is recorded in for the far ground (a slab's tint).
const PAVING_FAR := [Color(0.56, 0.56, 0.56), Color(0.47, 0.47, 0.46), Color(0.50, 0.53, 0.57), Color(0.60, 0.43, 0.36)]
const ASPHALT_FAR := Color(0.36, 0.36, 0.38)
const LAWN_FAR := Color(0.36, 0.52, 0.26)
## Most trees one chunk's forecourts plant, and the most parked cars its car parks hold: trees are
## the frame's biggest single cost, a static car ~260 triangles.
const MAX_TREES := 10
const MAX_CARS := 170
## How far the parked cars cast shadows (metres): a static car has no LODs, and its shadow a
## few pixels long is not worth it in the far cascades.
const CAR_SHADOW_DISTANCE := 70.0
## Share of a car park's stalls that are taken (a range, hashed per lot).
const CAR_FILL := Vector2(0.55, 0.92)
## Share of a parking podium's roof stalls that are taken.
const ROOF_FILL := 0.45
## Odds a strip or a planted piece of forecourt gets bollards along its street side (a plaza
## always does), and the most in one run: a frontage of them on every lot was two thousand
## bollards in a street view, each in every shadow cascade.
const BOLLARD_ODDS := 0.3
const BOLLARD_RUN := 9
## A planter's kerb height, and the depth of the strip a narrow leftover gets.
const PLANTER_HEIGHT := 0.55
## Forecourt pieces at least this deep (metres) are a plaza: a feature in the middle on a cross
## of walks this wide, and a lawn in each quarter (at these odds; else a raised planter).
const PLAZA_DEPTH := 11.0
const PLAZA_WALK := 3.2
const LAWN_ODDS := 0.7
## Odds a plaza's feature is a reflecting pool (else a bronze on a plinth), and that it has one.
const POOL_ODDS := 0.5
const FEATURE_ODDS := 0.7
## A dropped cell (leftovers()) this big or bigger may be a car park instead of forecourt.
const LEFTOVER_PARK_ODDS := 0.35
## Stall and row module: CityChunk's approach parking and ArenaGrounds use the same.
const STALL := Vector2(2.7, 5.4)
const AISLE := 7.0
## How a car park is edged on its street sides: odds of a low wall, a hedge, chain-link (the rest).
const EDGE_WALL := 0.45
const EDGE_HEDGE := 0.3
const WALL_HEIGHT := 0.7
const FENCE_HEIGHT := 1.9


## True where the lot fill runs: a city block of these districts.
static func wanted(ch: CityChunk, district: int) -> bool:
	return ch.zone == MacroMap.Zone.CITY and district in DISTRICTS


## The face of a lot that looks at the nearest street, as Building counts faces (1 +X, 2 -X,
## 3 +Z, 4 -Z): the side of the block's inner rect the lot's centre is nearest.
static func street_face(ch: CityChunk, lot: Dictionary) -> int:
	var inner: Rect2 = (ch.plan.block(ch.ix, ch.iz).rect as Rect2).grow(-ch.plan.sidewalk_width)
	var c: Vector2 = lot.center
	var d := [inner.end.x - c.x, c.x - inner.position.x, inner.end.y - c.y, c.y - inner.position.y]
	var best := 0
	for i in 4:
		if float(d[i]) < float(d[best]):
			best = i
	return best + 1


static func _rng(ch: CityChunk, tag: String, a: Variant) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ch.plan.seed, ch.ix, ch.iz, "lot_fill", tag, a])
	return rng


static func _cell(lot: Dictionary) -> Rect2:
	if lot.has("cell"):
		return lot.cell
	var size: Vector2 = lot.size
	return Rect2((lot.center as Vector2) - size * 0.5, size)


## Which of PAVINGS a block's forecourts wear (one a block: each look is a draw call a chunk).
static func _paving_for(ch: CityChunk) -> int:
	return absi(hash([ch.plan.seed, ch.ix, ch.iz, "fill_paving"])) % PAVINGS.size()


static func _material(ch: CityChunk, kind: String) -> Material:
	if kind == "lawn":
		return _lawn_material(ch)
	if kind == "asphalt":
		return PropFactory.road("asphalt", 7.0, Color(0.6, 0.6, 0.62), hash([ch.plan.seed, "lot_asphalt"]), 0.0, 0.7)
	var p: Array = PAVINGS[int(kind.substr(6))]
	return PropFactory.road(p[0], p[1], p[2], hash([ch.plan.seed, "lot_paving", kind]), 0.0, 0.2)


## One rect of fill ground: a FULL chunk collects it into the kind's merged mesh (commit()); a LOD
## chunk or the far city's capture lays it as a slab (the merged far ground, or captured.ground).
## `kind` is "paving<N>" or "asphalt".
static func _ground(ch: CityChunk, r: Rect2, kind: String) -> void:
	if r.size.x < 0.5 or r.size.y < 0.5:
		return
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		if not ch._fill_ground.has(kind):
			ch._fill_ground[kind] = []
		(ch._fill_ground[kind] as Array).append(r)
		return
	# From afar the forecourt paving is the pavement's colour give or take, and every slab is
	# more of the merged far ground's triangles (a LOD chunk grids it at 8 m, whatever it is):
	# only the car parks' asphalt, which changes how a block reads from the air, goes in. And a
	# slab under 6 m would not join the merged far ground at all (CityChunk._add_slab() makes it a
	# box of its own material: a draw).
	if (kind != "asphalt" and kind != "lawn") or maxf(r.size.x, r.size.y) < 6.0:
		return
	var lift := ASPHALT_LIFT if kind == "asphalt" or kind == "lawn" else PAVING_LIFT
	var far: Color = ASPHALT_FAR if kind == "asphalt" else (LAWN_FAR if kind == "lawn" else PAVING_FAR[int(kind.substr(6))])
	var c := r.get_center()
	ch._add_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP + lift - 0.02, c.y), Vector3(r.size.x, 0.04, r.size.y), far, false, _material(ch, kind))


## A solid box in the chunk's merged boxes, with collision, always as a box: CityChunk._add_slab()
## takes anything 0.5 m tall or less and 6 m long for ground and lays a relief grid of its own
## (a node and a draw each - a pool's kerbs were four).
static func _solid(ch: CityChunk, pos: Vector3, size: Vector3, mat: Material, collide: bool = true) -> void:
	var lifted := pos + Vector3(0.0, ch._gy(pos.x, pos.z), 0.0)
	ch._merge_box(mat, size, lifted)
	if collide:
		ch._add_shape(size, lifted)


## A box in the fill mesh (planted soil, water, polished stone, glass): FULL chunks only, placed
## at `at` (relief included), `kind` one of the KIND_* ids.
static func _box(ch: CityChunk, size: Vector3, at: Vector3, kind: int) -> void:
	ch._fill_boxes.append([size, at, kind])


## The shader id a ground kind is drawn as.
static func _kind_id(kind: String) -> int:
	if kind == "asphalt":
		return KIND_ASPHALT
	if kind == "lawn":
		return KIND_LAWN
	return int(kind.substr(6))


static var _fill_material: ShaderMaterial = null


## The fill mesh's one material (shaders/lot_ground.gdshader), shared by every chunk.
static func fill_material() -> ShaderMaterial:
	if _fill_material != null:
		return _fill_material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/lot_ground.gdshader")
	mat.set_shader_parameter("setts_tex", PropFactory.texture("paving", "Color"))
	mat.set_shader_parameter("setts_nrm", PropFactory.texture("paving", "NormalGL"))
	mat.set_shader_parameter("pavers_tex", PropFactory.texture("pavers", "Color"))
	mat.set_shader_parameter("pavers_nrm", PropFactory.texture("pavers", "NormalGL"))
	mat.set_shader_parameter("asphalt_tex", PropFactory.texture("asphalt", "Color"))
	mat.set_shader_parameter("asphalt_nrm", PropFactory.texture("asphalt", "NormalGL"))
	mat.set_shader_parameter("grass_tex", PropFactory.texture("grass", "Color"))
	mat.set_shader_parameter("paving_scale", Vector4(PAVINGS[0][1], PAVINGS[1][1], PAVINGS[2][1], PAVINGS[3][1]))
	for i in 4:
		mat.set_shader_parameter("paving_tint_%d" % i, PAVINGS[i][2])
	_fill_material = mat
	return mat


## The FULL chunk's fill - every paving, the asphalt, the lawns, the planted tops, the water and
## the polished stone - as ONE relief-following mesh on ONE material (shaders/lot_ground.gdshader,
## what each vertex is in its colour): a draw call a chunk, not one per kind (it was up to six).
static func commit(ch: CityChunk) -> void:
	if ch._fill_ground.is_empty() and ch._fill_boxes.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kinds: Array = ch._fill_ground.keys()
	kinds.sort()
	for kind: String in kinds:
		var lift := ASPHALT_LIFT if kind == "asphalt" or kind == "lawn" else PAVING_LIFT
		var id_color := Color(float(_kind_id(kind)) / 16.0, 0.0, 0.0, 1.0)
		for r: Rect2 in ch._fill_ground[kind]:
			var nx := 1
			var nz := 1
			# Downtown's relief is off and elsewhere it rolls over hundreds of metres, so most
			# rects are flat or a plane: one quad then, the relief grid only where it bends.
			if not _planar(ch, r):
				var step := ch.ground_grid_step if CityChunk._detail() >= 1.0 else ch.ground_grid_step * 2.0
				nx = clampi(ceili(r.size.x / step), 1, 60)
				nz = clampi(ceili(r.size.y / step), 1, 60)
			st.append_from(ch._grid_mesh(r, CityChunk.SIDEWALK_TOP + lift, lift + 0.02, nx, nz, true, id_color), 0, Transform3D.IDENTITY)
	# The boxes go in unindexed like the grids: a SurfaceTool that is handed an indexed mesh after
	# unindexed ones keeps only the indexed triangles, and every grid vanished (the car parks
	# drew as the bare pavement under them).
	var unit := CityChunk.unit_box_arrays()
	var uv: PackedVector3Array = unit[0]
	var un: PackedVector3Array = unit[1]
	var ut: PackedVector2Array = unit[3]
	var ui: PackedInt32Array = unit[4]
	for b: Array in ch._fill_boxes:
		var size: Vector3 = b[0]
		var at: Vector3 = b[1]
		st.set_color(Color(float(b[2]) / 16.0, 0.0, 0.0, 1.0))
		for i: int in ui:
			st.set_normal(un[i])
			st.set_uv(ut[i])
			st.set_color(Color(float(b[2]) / 16.0, 0.0, 0.0, 1.0))
			st.add_vertex(uv[i] * size + at)
	var mi := MeshInstance3D.new()
	mi.name = "LotFill"
	mi.mesh = st.commit()
	mi.material_override = fill_material()
	# Four centimetres proud of the pavement: its shadow is nothing, and in every cascade. (The
	# planters' kerbs, which do cast, are in the plinths' mesh.)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ch.add_child(mi)
	ch._fill_ground.clear()
	ch._fill_boxes.clear()


## True when the relief under `r` is a plane to within a centimetre (its centre and edge middles
## where the corners' bilinear puts them).
static func _planar(ch: CityChunk, r: Rect2) -> bool:
	var h00 := ch._gy(r.position.x, r.position.y)
	var h10 := ch._gy(r.end.x, r.position.y)
	var h01 := ch._gy(r.position.x, r.end.y)
	var h11 := ch._gy(r.end.x, r.end.y)
	for f: Vector2 in [Vector2(0.5, 0.5), Vector2(0.5, 0.0), Vector2(0.5, 1.0), Vector2(0.0, 0.5), Vector2(1.0, 0.5)]:
		var want := lerpf(lerpf(h00, h10, f.x), lerpf(h01, h11, f.x), f.y)
		if absf(ch._gy(r.position.x + r.size.x * f.x, r.position.y + r.size.y * f.y) - want) > 0.01:
			return false
	return true


# --- A building's lot -------------------------------------------------------------------------

## After a lot's building is planned (LOD, capture) or built (FULL): its forecourt out to the
## lot's cell, and for a parking podium the drive-in and the roof deck's cars.
static func after_building(ch: CityChunk, lot: Dictionary, bld: Building) -> void:
	var cell := _cell(lot)
	var centre: Vector2 = lot.center
	var holes: Array[Rect2] = []
	for part: Dictionary in bld.parts:
		var size: Vector3 = part.size
		var c: Vector3 = part.center
		if c.y - size.y * 0.5 > 0.05:
			continue
		holes.append(Rect2(centre.x + c.x - size.x * 0.5, centre.y + c.z - size.z * 0.5, size.x, size.z))
	var paving := "paving%d" % _paving_for(ch)
	# The block's service alley (Alleys) takes a band down the seam of the lot grid: the paving and
	# the forecourt keep off it, and the alley is told what stands beside it.
	Alleys.record(ch, lot, holes)
	var back := Alleys.back_strip(ch.plan, ch.ix, ch.iz, lot, holes)
	var keep: Array[Rect2] = holes.duplicate()
	keep.append_array(Alleys.keep_out(ch.plan, ch.ix, ch.iz))
	if back.size.x > 0.0:
		keep.append(back)
		var backs: Array[Rect2] = [back]
		for piece: Rect2 in _minus(Alleys.trim(ch.plan, ch.ix, ch.iz, cell), backs, 0.0):
			_ground(ch, piece, paving)
	else:
		_ground(ch, Alleys.trim(ch.plan, ch.ix, ch.iz, cell), paving)
	var entry := bld.garage_entry()
	if not entry.is_empty():
		keep.append(_driveway(ch, cell, centre, entry))
	if ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	var rng := _rng(ch, "forecourt", lot.seed)
	if bld.podium_kind == 2:
		_roof_deck(ch, bld, centre, rng)
	elif bld.podium_kind == 1:
		_roof_garden(ch, bld, centre, rng)
	for r: Rect2 in _minus(cell.grow(-0.4), keep, 0.3):
		forecourt(ch, r, rng)


## The drive-in of a parking podium: asphalt from the opening out to the cell's edge, and on
## across the pavement to the kerb when the cell ends at the block's edge. Returns the
## driveway's rect (the forecourt keeps off it).
static func _driveway(ch: CityChunk, cell: Rect2, centre: Vector2, entry: Dictionary) -> Rect2:
	var at: Vector3 = entry.at
	var n: Vector3 = entry.normal
	var w: float = clampf(float(entry.width), 5.0, 7.5)
	var p := centre + Vector2(at.x, at.z)
	var r: Rect2
	if absf(n.x) > 0.5:
		var x1 := cell.end.x if n.x > 0.0 else cell.position.x
		r = Rect2(minf(p.x, x1), p.y - w * 0.5, absf(x1 - p.x), w)
	else:
		var z1 := cell.end.y if n.z > 0.0 else cell.position.y
		r = Rect2(p.x - w * 0.5, minf(p.y, z1), w, absf(z1 - p.y))
	_ground(ch, r, "asphalt")
	# Across the pavement to the kerb, where the cell meets the block's edge.
	var block: Rect2 = ch.plan.block(ch.ix, ch.iz).rect
	var inner := block.grow(-ch.plan.sidewalk_width)
	var sw: float = ch.plan.sidewalk_width
	if absf(n.x) > 0.5:
		var edge := inner.end.x if n.x > 0.0 else inner.position.x
		if absf((cell.end.x if n.x > 0.0 else cell.position.x) - edge) < 0.5:
			_ground(ch, Rect2(edge if n.x > 0.0 else edge - sw, r.position.y, sw, w), "asphalt")
	else:
		var edge := inner.end.y if n.z > 0.0 else inner.position.y
		if absf((cell.end.y if n.z > 0.0 else cell.position.y) - edge) < 0.5:
			_ground(ch, Rect2(r.position.x, edge if n.z > 0.0 else edge - sw, w, sw), "asphalt")
	return r


## A parking podium's roof is its top deck: cars in the stalls the shader paints (building.gdshader,
## the roof branch: double rows along x on a 17.8 m module from 1 m in), off the tower's footprint.
static func _roof_deck(ch: CityChunk, bld: Building, centre: Vector2, rng: RandomNumberGenerator) -> void:
	var pod: Dictionary = bld.parts[0]
	var size: Vector3 = pod.size
	var top := CityChunk.SIDEWALK_TOP + size.y
	var towers: Array[Rect2] = []
	for i in range(1, bld.parts.size()):
		var s: Vector3 = bld.parts[i].size
		var c: Vector3 = bld.parts[i].center
		towers.append(Rect2(c.x - s.x * 0.5 - 1.2, c.z - s.z * 0.5 - 1.2, s.x + 2.4, s.z + 2.4))
	var cols := int(size.x / STALL.x)
	var k := 0
	while true:
		var band := 1.0 + float(k) * (STALL.y * 2.0 + AISLE)
		if band + STALL.y > size.z - 0.8:
			break
		for half in 2:
			var qz := band + STALL.y * 0.5 + (STALL.y + AISLE if half == 1 else 0.0)
			if qz + STALL.y * 0.5 > size.z - 0.8:
				continue
			for i in cols:
				var qx := (float(i) + 0.5) * STALL.x
				if qx < 1.4 or qx > size.x - 1.4:
					continue
				var local := Vector2(qx - size.x * 0.5, qz - size.z * 0.5)
				var stall := Rect2(local - Vector2(1.2, 2.5), Vector2(2.4, 5.0))
				var clear := true
				for t: Rect2 in towers:
					if t.intersects(stall):
						clear = false
						break
				if not clear or rng.randf() >= ROOF_FILL or ch._fill_cars >= MAX_CARS:
					continue
				var yaw := (PI if half == 0 else 0.0) + rng.randf_range(-0.04, 0.04)
				_car(ch, rng, Vector3(centre.x + local.x, top, centre.y + local.y), yaw)
		# Light poles down the aisle (the deck is dark at night without them), off the tower.
		var aisle_z := band + STALL.y + AISLE * 0.5
		if aisle_z < size.z - 2.0:
			var poles := maxi(1, int(size.x / 28.0))
			for j in poles:
				var local := Vector2(size.x * (float(j) + 0.5) / float(poles) - size.x * 0.5, aisle_z - size.z * 0.5)
				var clear := true
				for t: Rect2 in towers:
					if t.grow(1.0).has_point(local):
						clear = false
				if clear:
					_lamp(ch, Vector3(centre.x + local.x, top, centre.y + local.y))
		k += 1


## A static parked car (ArenaGrounds.car_mesh()): a saloon or the taller van-like body - two kinds,
## two draws a chunk; the paint is what varies.
## A retail podium's roof is the tower's amenity deck (Building leaves it bare of plant): the
## forecourt's planters, benches and a pool, round the tower.
static func _roof_garden(ch: CityChunk, bld: Building, centre: Vector2, rng: RandomNumberGenerator) -> void:
	var pod: Dictionary = bld.parts[0]
	var size: Vector3 = pod.size
	var top := CityChunk.SIDEWALK_TOP + size.y
	var deck := Rect2(centre.x - size.x * 0.5, centre.y - size.z * 0.5, size.x, size.z).grow(-1.4)
	var towers: Array[Rect2] = []
	for i in range(1, bld.parts.size()):
		var s: Vector3 = bld.parts[i].size
		var c: Vector3 = bld.parts[i].center
		if c.y - s.y * 0.5 <= size.y + 0.05:
			towers.append(Rect2(centre.x + c.x - s.x * 0.5, centre.y + c.z - s.z * 0.5, s.x, s.z))
	for r: Rect2 in _minus(deck, towers, 1.5):
		forecourt(ch, r, rng, top)


static func _car(ch: CityChunk, rng: RandomNumberGenerator, at: Vector3, yaw: float) -> void:
	var v := 0 if rng.randf() < 0.62 else 2
	var paint: Color = ArenaGrounds.CAR_PAINTS[rng.randi() % ArenaGrounds.CAR_PAINTS.size()]
	var key := "apark_car_%d" % v
	ch._batch.add(key, ArenaGrounds.car_mesh(v), Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0.0, 0.005, 0.0)), paint)
	ch._batch.set_shadow_distance(key, CAR_SHADOW_DISTANCE)
	ch._fill_cars += 1


# --- Forecourts -------------------------------------------------------------------------------

## One piece of forecourt (a rect of the lot the building leaves, on the lot's paving): a narrow
## strip gets bollards and a hedge planter along it, a deeper one raised planters with benches
## facing them, a plaza a feature in the middle - a reflecting pool or a bronze on a plinth - and
## planters round it with a tree or two.
## `roof_y` >= 0 lays it on a roof at that height (a podium's garden: no street side, no bollards).
static func forecourt(ch: CityChunk, r: Rect2, rng: RandomNumberGenerator, roof_y: float = -1.0) -> void:
	var short := minf(r.size.x, r.size.y)
	var long := maxf(r.size.x, r.size.y)
	if short < 1.6 or long < 4.0:
		return
	var long_x := r.size.x >= r.size.y
	var roof := roof_y >= 0.0
	var y0 := roof_y if roof else CityChunk.SIDEWALK_TOP + PAVING_LIFT
	var street := -1 if roof else _street_side(ch, r)
	if short < 4.5:
		# A strip: now and then bollards along the street side, a hedge planter behind them if
		# it fits.
		if street >= 0 and rng.randf() < BOLLARD_ODDS:
			_bollards(ch, r, street, rng)
		if short >= 2.6 and rng.randf() < 0.7:
			var pr := _inset_along(r, long_x, 1.0, 1.2)
			pr = _thin_to(pr, long_x, minf(1.3, short - 1.2))
			_planter(ch, pr, rng, false, y0)
		return
	if short < PLAZA_DEPTH:
		# Planters down the middle of the piece, a bench facing each from the open side.
		var n := maxi(1, int((long - 2.0) / 9.0))
		var seg := (long - 2.0) / float(n)
		var depth := clampf(short * 0.4, 1.4, 3.2)
		for i in n:
			if rng.randf() < 0.2:
				continue
			var a := 1.0 + float(i) * seg + 0.8
			var b := a + seg - 1.6
			var pr: Rect2
			if long_x:
				pr = Rect2(r.position.x + a, r.get_center().y - depth * 0.5, b - a, depth)
			else:
				pr = Rect2(r.get_center().x - depth * 0.5, r.position.y + a, depth, b - a)
			_planter(ch, pr, rng, rng.randf() < 0.55, y0)
			if rng.randf() < 0.6:
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var pc := pr.get_center()
				var off := depth * 0.5 + 0.9
				var at := Vector3(pc.x, y0, pc.y + side * off) if long_x else Vector3(pc.x + side * off, y0, pc.y)
				var face := Vector2(0.0, side) if long_x else Vector2(side, 0.0)
				if r.has_point(Vector2(at.x, at.z)):
					ch._add_bench(at, atan2(-face.x, -face.y))
		if street >= 0 and rng.randf() < BOLLARD_ODDS:
			_bollards(ch, r, street, rng)
		return
	# A plaza: a feature in the middle on a cross of walks, a lawn in each quarter (with a tree
	# and a few benches along its walk side) or, now and then, a raised planter instead; a big
	# plaza of bare paving was what this is here to get rid of.
	var c := r.get_center()
	var feature := Vector2(minf(r.size.x * 0.3, 12.0), minf(r.size.y * 0.3, 12.0))
	if rng.randf() < FEATURE_ODDS:
		if rng.randf() < POOL_ODDS or roof:
			_pool(ch, Rect2(c - feature * 0.5, feature), y0, roof)
		else:
			_bronze(ch, c, rng, y0)
	var walk := PLAZA_WALK * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			# The quarter between the walks and the plaza's edge, 1.5 m in from the edge.
			var inner_x := maxf(walk, feature.x * 0.5 + 1.2)
			var inner_z := maxf(walk, feature.y * 0.5 + 1.2)
			var x0 := c.x + sx * inner_x
			var x1 := c.x + sx * (r.size.x * 0.5 - 1.5)
			var z0 := c.y + sz * inner_z
			var z1 := c.y + sz * (r.size.y * 0.5 - 1.5)
			var q := Rect2(minf(x0, x1), minf(z0, z1), absf(x1 - x0), absf(z1 - z0))
			if q.size.x < 3.0 or q.size.y < 3.0:
				continue
			if rng.randf() < LAWN_ODDS:
				_lawn(ch, q, rng, y0, roof)
			else:
				_planter(ch, q.grow(-0.6), rng, rng.randf() < 0.6, y0)
			# A bench on the lawn's walk side, facing across the walk.
			if rng.randf() < 0.7:
				var bz := c.y + sz * (inner_z - 0.8)
				var bx := lerpf(q.position.x, q.end.x, 0.5)
				ch._add_bench(Vector3(bx, y0, bz), atan2(0.0, sz))
	if street >= 0:
		_bollards(ch, r, street, rng)


## Which side of `r` faces a street (0 -Z, 1 +Z, 2 -X, 3 +X), -1 when none is within reach: a
## side on or near the block's inner edge.
static func _street_side(ch: CityChunk, r: Rect2) -> int:
	var inner: Rect2 = (ch.plan.block(ch.ix, ch.iz).rect as Rect2).grow(-ch.plan.sidewalk_width)
	var d := [r.position.y - inner.position.y, inner.end.y - r.end.y, r.position.x - inner.position.x, inner.end.x - r.end.x]
	var best := -1
	for i in 4:
		if float(d[i]) < 3.0 and (best < 0 or float(d[i]) < float(d[best])):
			best = i
	return best


## A run of bollards along side `side` of `r`, 0.5 m in: at most BOLLARD_RUN of them, 2 m apart,
## in front of the middle of the frontage (the doors), one left out for the way through.
static func _bollards(ch: CityChunk, r: Rect2, side: int, rng: RandomNumberGenerator) -> void:
	var top := CityChunk.SIDEWALK_TOP + PAVING_LIFT
	var along_x := side <= 1
	var length := r.size.x if along_x else r.size.y
	var n := mini(int((length - 1.0) / 2.0), BOLLARD_RUN)
	if n < 2:
		return
	var start := (length - float(n) * 2.0) * 0.5
	var skip := rng.randi() % n
	for i in n:
		if i == skip and n > 4:
			continue
		var t := start + (float(i) + 0.5) * 2.0
		var q: Vector2
		match side:
			0:
				q = Vector2(r.position.x + t, r.position.y + 0.5)
			1:
				q = Vector2(r.position.x + t, r.end.y - 0.5)
			2:
				q = Vector2(r.position.x + 0.5, r.position.y + t)
			_:
				q = Vector2(r.end.x - 0.5, r.position.y + t)
		ch._add_prop("bollard", Vector3(q.x, top, q.y), Color(0.25, 0.25, 0.27), [
			["bollard", PropFactory.bollard(), Transform3D(Basis(), Vector3(q.x, top + 0.45, q.y))],
		], [[Vector3(0.3, 0.9, 0.3), Vector3(q.x, top + 0.45, q.y), 0.0]])


static func _inset_along(r: Rect2, long_x: bool, ends: float, _side: float) -> Rect2:
	return r.grow_individual(-ends, 0.0, -ends, 0.0) if long_x else r.grow_individual(0.0, -ends, 0.0, -ends)


static func _thin_to(r: Rect2, long_x: bool, depth: float) -> Rect2:
	var c := r.get_center()
	return Rect2(r.position.x, c.y - depth * 0.5, r.size.x, depth) if long_x else Rect2(c.x - depth * 0.5, r.position.y, depth, r.size.y)


## A raised planter over `r`: a precast kerb (the plinths' concrete, so it merges into their
## mesh), planted soil (the fill mesh), shrubs, and a tree in the middle if `tree` and the
## chunk's budget allows.
static func _planter(ch: CityChunk, r: Rect2, rng: RandomNumberGenerator, tree: bool, base: float = CityChunk.SIDEWALK_TOP + PAVING_LIFT) -> void:
	if r.size.x < 0.9 or r.size.y < 0.9:
		return
	var c := r.get_center()
	var h := PLANTER_HEIGHT
	_solid(ch, Vector3(c.x, base + h * 0.5, c.y), Vector3(r.size.x, h, r.size.y), Building.plinth_material())
	# The planted top stands a hair proud of the kerb box (which is solid), inside its rim.
	var soil_top := base + h + 0.012
	_box(ch, Vector3(r.size.x - 0.4, 0.04, r.size.y - 0.4), Vector3(c.x, soil_top - 0.02 + ch._gy(c.x, c.y), c.y), KIND_SOIL)
	var inner := r.grow(-0.35)
	var area := inner.size.x * inner.size.y
	var has_tree := tree and ch._fill_trees < MAX_TREES and minf(r.size.x, r.size.y) >= 1.4
	for k in clampi(int(area / 1.3), 1, 16):
		var p := Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
		if has_tree and p.distance_to(c) < 0.9:
			continue
		_shrub(ch, Vector3(p.x, soil_top, p.y), rng)
	if has_tree:
		ch._fill_trees += 1
		_tree(ch, Vector3(c.x, soil_top, c.y), rng)


## A shrub in a planter: ONE species a chunk (a batch key is a draw call, and its shadow twin
## another - planted with CityChunk._add_bush()'s eight-way roll, the planters alone put up to
## sixteen new draws on a chunk).
static func _shrub(ch: CityChunk, at: Vector3, rng: RandomNumberGenerator) -> void:
	var pick := absi(hash([ch.plan.seed, ch.ix, ch.iz, "fill_shrub"])) % PropFactory.BUSHES.size()
	var sc := rng.randf_range(0.9, 1.4)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sc, sc, sc))
	var tint := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.0))
	if LaTrees.accent_shrub(ch, at, LaTrees.PLANTER_ACCENT):
		return
	ch._batch.add("bush_%d" % pick, PropFactory.model_bush(pick), Transform3D(basis, at), tint)


## A planter's tree: the block's own street tree (CityChunk._tree_bias, the species its street
## already plants, so usually no new batch), at a planter's size.
static func _tree(ch: CityChunk, at: Vector3, rng: RandomNumberGenerator) -> void:
	var variant := clampi(ch._tree_bias, 0, PropFactory.CITY_TREES.size() - 1)
	var s := PropFactory.city_tree_scale(variant, PropFactory.city_tree_height(variant, rng) * 0.8)
	var tint := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.05))
	var variety := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.25, 1.0))
	var yaw := rng.randf() * TAU
	if LaTrees.lot_tree(ch, at, yaw, tint):
		return
	ch._batch.add("tree_%d" % variant, PropFactory.model_tree(variant), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint, variety)


## A shallow reflecting pool over `r`: a stone kerb and a dark still surface (merged boxes).
## A lawn panel over `r` (the fill mesh; on a roof a thin slab), a tree in the middle if the
## budget allows. No blade grass: a sparse sprinkle read as weeds and a lawn's worth was another
## draw and tens of thousands of triangles a chunk; the lawn texture carries it.
static func _lawn(ch: CityChunk, r: Rect2, rng: RandomNumberGenerator, base: float, roof: bool) -> void:
	var c := r.get_center()
	if roof:
		_box(ch, Vector3(r.size.x, 0.06, r.size.y), Vector3(c.x, base + 0.03 + ch._gy(c.x, c.y), c.y), KIND_LAWN)
	else:
		_ground(ch, r, "lawn")
	if ch._fill_trees < MAX_TREES and minf(r.size.x, r.size.y) >= 4.0:
		ch._fill_trees += 1
		_tree(ch, Vector3(c.x, base + 0.02, c.y), rng)


static func _lawn_material(ch: CityChunk) -> Material:
	return PropFactory.lawn(Color(0.34, 0.50, 0.22), hash([ch.plan.seed, "lot_lawn"]), 0.4, 2.2)


static func _pool(ch: CityChunk, r: Rect2, base: float = CityChunk.SIDEWALK_TOP + PAVING_LIFT, swim: bool = false) -> void:
	if r.size.x < 3.0 or r.size.y < 3.0:
		return
	var c := r.get_center()
	var kerb := 0.45
	var t := 0.4
	for side in 4:
		var horiz := side < 2
		var pos := c + (Vector2(0.0, (r.size.y - t) * 0.5 * (1.0 if side == 0 else -1.0)) if horiz else Vector2((r.size.x - t) * 0.5 * (1.0 if side == 2 else -1.0), 0.0))
		var size := Vector3(r.size.x, kerb, t) if horiz else Vector3(t, kerb, r.size.y - t * 2.0)
		_solid(ch, Vector3(pos.x, base + kerb * 0.5, pos.y), size, Building.plinth_material())
	_box(ch, Vector3(r.size.x - t * 2.0, 0.06, r.size.y - t * 2.0), Vector3(c.x, base + kerb - 0.12 + ch._gy(c.x, c.y), c.y), KIND_SWIM if swim else KIND_DARK)




## An abstract bronze on a granite plinth: a leaning column of turned blocks (the shapes are
## invented), in the chunk's batch.
static func _bronze(ch: CityChunk, at: Vector2, rng: RandomNumberGenerator, base: float = CityChunk.SIDEWALK_TOP + PAVING_LIFT) -> void:
	var ph := 1.3
	var plinth_at := Vector3(at.x, base + ph * 0.5 + ch._gy(at.x, at.y), at.y)
	_box(ch, Vector3(2.0, ph, 2.0), plinth_at, KIND_DARK)
	ch._add_shape(Vector3(2.0, ph, 2.0), plinth_at)
	var bronze := PropFactory.box("fill_bronze", Vector3.ONE, Color(0.36, 0.24, 0.14))
	var yaw := rng.randf() * TAU
	var p := Vector3(at.x, base + ph, at.y)
	var lean := rng.randf_range(0.2, 0.45)
	var parts := [[0.5, 1.2], [0.42, 1.0], [0.6, 0.8], [0.36, 1.1], [0.22, 0.9]]
	for i in parts.size():
		var w: float = parts[i][0]
		var l: float = parts[i][1]
		var b := Basis(Vector3.UP, yaw + float(i) * 0.7) * Basis(Vector3.RIGHT, lean * float(i) * 0.45)
		var dir := b.y
		ch._batch.add("fill_bronze", bronze, Transform3D(b.scaled_local(Vector3(w, l, w * 0.7)), p + dir * l * 0.5), Color(0.36, 0.24, 0.14))
		p += dir * l * 0.9



# --- Surface car parks --------------------------------------------------------------------------

## A lot that is a surface car park (CityPlan.lots() "parking"): asphalt over its cell; on a FULL
## chunk the stall rows either side of the aisles, the parked cars, a pay booth by the way in, light
## masts, and a low wall, a hedge or chain-link along its street sides.
static func surface_lot(ch: CityChunk, lot: Dictionary) -> void:
	_car_park(ch, Alleys.trim(ch.plan, ch.ix, ch.iz, _cell(lot)), int(lot.seed))


static func _car_park(ch: CityChunk, cell: Rect2, key: int) -> void:
	_ground(ch, cell, "asphalt")
	if ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	var rng := _rng(ch, "car_park", key)
	var r := cell.grow(-1.2)
	if r.size.x < 12.0 or r.size.y < 10.0:
		return
	RoadWear.car_park(ch, r, CityChunk.SIDEWALK_TOP + ASPHALT_LIFT, key)
	# Rows run along the long side; u along the rows, v across them.
	var along_x := r.size.x >= r.size.y
	var U := r.size.x if along_x else r.size.y
	var V := r.size.y if along_x else r.size.x
	var to_world := func(u: float, v: float) -> Vector2:
		return r.position + (Vector2(u, v) if along_x else Vector2(v, u))
	var fill := rng.randf_range(CAR_FILL.x, CAR_FILL.y)
	var top := CityChunk.SIDEWALK_TOP + ASPHALT_LIFT
	var stripe := PropFactory.box("pstripe", Vector3(4.4, 0.01, 0.12), Color(0.95, 0.95, 0.92))
	var stripe_basis := Basis(Vector3.UP, PI * 0.5) if along_x else Basis()
	var v := 0.0
	var rows: Array[Vector2] = [] # [v of the row's aisle-side edge, +1 / -1: which way the noses point]
	var aisles: Array[float] = []
	while v + STALL.y + AISLE <= V + 0.01:
		rows.append(Vector2(v, 1.0))
		aisles.append(v + STALL.y + AISLE * 0.5)
		if v + STALL.y * 2.0 + AISLE <= V + 0.01:
			rows.append(Vector2(v + STALL.y + AISLE, -1.0))
			v += STALL.y * 2.0 + AISLE
		else:
			v += STALL.y + AISLE
	if rows.is_empty():
		return
	var n := int((U - 2.0) / STALL.x)
	var u0 := (U - float(n) * STALL.x) * 0.5
	for row: Vector2 in rows:
		var vc := row.x + STALL.y * 0.5
		for i in n + 1:
			var su := u0 + float(i) * STALL.x
			var sp: Vector2 = to_world.call(su, vc)
			ch._batch.add("pstripe", stripe, Transform3D(stripe_basis, Vector3(sp.x, top + 0.005, sp.y)))
			if i < n and rng.randf() < fill and ch._fill_cars < MAX_CARS:
				var cp: Vector2 = to_world.call(su + STALL.x * 0.5, vc)
				# Noses toward the aisle: +v on a row before its aisle, -v after it.
				var nose := Vector2(0.0, row.y) if along_x else Vector2(row.y, 0.0)
				var yaw := atan2(-nose.x, -nose.y) + rng.randf_range(-0.05, 0.05)
				_car(ch, rng, Vector3(cp.x, top, cp.y), yaw)
	# Light poles down the aisles.
	for a: float in aisles:
		var m := maxi(1, int(U / 30.0))
		for j in m:
			var q: Vector2 = to_world.call(U * (float(j) + 0.5) / float(m), a)
			_lamp(ch, Vector3(q.x, top, q.y))
	# The street sides: a way in at the first aisle's end, a pay booth beside it, and the edging.
	var street := _street_side(ch, cell)
	var gate := Vector2.INF
	if street >= 0:
		# The way in: at the end of the first aisle where the aisles run at the street, else
		# halfway along the side that faces it.
		var gate_u: float = aisles[0] if not aisles.is_empty() else V * 0.5
		var gc := cell.get_center()
		var across := gate_u + (r.position.y if along_x else r.position.x)
		match street:
			0:
				gate = Vector2(across, cell.position.y) if not along_x else Vector2(gc.x, cell.position.y)
			1:
				gate = Vector2(across, cell.end.y) if not along_x else Vector2(gc.x, cell.end.y)
			2:
				gate = Vector2(cell.position.x, across) if along_x else Vector2(cell.position.x, gc.y)
			_:
				gate = Vector2(cell.end.x, across) if along_x else Vector2(cell.end.x, gc.y)
		_booth(ch, gate, street, rng)
	var roll := rng.randf()
	for side in 4:
		if side != street and _street_side_of(ch, cell, side) > 3.0:
			continue
		if roll < EDGE_WALL:
			_edge_run(ch, cell, side, gate, "wall", rng)
		elif roll < EDGE_WALL + EDGE_HEDGE:
			_edge_run(ch, cell, side, gate, "hedge", rng)
		else:
			_edge_run(ch, cell, side, gate, "fence", rng)


## A light pole: the street lamp and its pool of light, in the street lamps' own batches (no draw
## call of its own) - but without the street lamp's OmniLight3D, which a car park's worth of
## poles would multiply; the additive pool carries the night.
static func _lamp(ch: CityChunk, at: Vector3) -> void:
	var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(CityChunk.LAMP_POOL_SIZE * 1.3, 1.0, CityChunk.LAMP_POOL_SIZE * 1.3)), at + Vector3(0.0, 0.05, 0.0))
	ch._add_prop("lamp", at, Color(0.28, 0.29, 0.32), [
		["lamp", PropFactory.model_lamp(), Transform3D(Basis(Vector3.UP, fmod(absf(at.x * 7.3 + at.z * 3.1), TAU)), at), ch._lamp_tint],
		["lamp_pool", PropFactory.light_pool(), pool],
	], [[Vector3(0.3, 3.9, 0.3), at + Vector3(0.0, 1.95, 0.0), 0.0]])


## How far side `side` of `r` is from the block's inner edge on that side.
static func _street_side_of(ch: CityChunk, r: Rect2, side: int) -> float:
	var inner: Rect2 = (ch.plan.block(ch.ix, ch.iz).rect as Rect2).grow(-ch.plan.sidewalk_width)
	var d := [r.position.y - inner.position.y, inner.end.y - r.end.y, r.position.x - inner.position.x, inner.end.x - r.end.x]
	return float(d[side])


## A run of edging along side `side` of `r` with a 7 m gap for the way in at `gate`.
static func _edge_run(ch: CityChunk, r: Rect2, side: int, gate: Vector2, kind: String, rng: RandomNumberGenerator) -> void:
	var along_x := side <= 1
	var a := r.position.x if along_x else r.position.y
	var b := r.end.x if along_x else r.end.y
	var line: float
	match side:
		0:
			line = r.position.y + 0.3
		1:
			line = r.end.y - 0.3
		2:
			line = r.position.x + 0.3
		_:
			line = r.end.x - 0.3
	var spans: Array[Vector2] = [Vector2(a + 0.3, b - 0.3)]
	if gate != Vector2.INF:
		var g := gate.x if along_x else gate.y
		var on_side := absf((gate.y if along_x else gate.x) - (r.position.y if side == 0 else r.end.y if side == 1 else r.position.x if side == 2 else r.end.x)) < 0.6
		if on_side and g > a and g < b:
			spans = [Vector2(a + 0.3, g - 3.5), Vector2(g + 3.5, b - 0.3)]
	var base := CityChunk.SIDEWALK_TOP + ASPHALT_LIFT
	for s: Vector2 in spans:
		var len := s.y - s.x
		if len < 1.0:
			continue
		var mid := (s.x + s.y) * 0.5
		var c := Vector2(mid, line) if along_x else Vector2(line, mid)
		ClimbingPlants.note_run(ch, c, len, along_x, base, WALL_HEIGHT if kind == "wall" else FENCE_HEIGHT, kind)
		match kind:
			"wall":
				var size := Vector3(len, WALL_HEIGHT, 0.3) if along_x else Vector3(0.3, WALL_HEIGHT, len)
				_solid(ch, Vector3(c.x, base + WALL_HEIGHT * 0.5, c.y), size, Building.plinth_material())
			"hedge":
				var pr := Rect2(c - Vector2(len, 1.0) * 0.5, Vector2(len, 1.0)) if along_x else Rect2(c - Vector2(1.0, len) * 0.5, Vector2(1.0, len))
				_planter(ch, pr, rng, false)
			_:
				_fence(ch, c, len, along_x, base)


## Chain-link along a run: galvanised posts every 3 m with a top rail, and the mesh between them
## (shaders/chain_link.gdshader, one quad a panel) - two batches a chunk (the rails are posts).
static func _fence(ch: CityChunk, c: Vector2, length: float, along_x: bool, base: float) -> void:
	var n := maxi(1, ceili(length / 3.0))
	var panel := length / float(n)
	var yaw := 0.0 if along_x else PI * 0.5
	var dir := Vector2(1.0, 0.0) if along_x else Vector2(0.0, 1.0)
	var post := PropFactory.cylinder("fence_post", 0.03, 1.0, Color(0.55, 0.56, 0.57), 0.03, 8)
	for i in n + 1:
		var q := c + dir * (-length * 0.5 + float(i) * panel)
		ch._batch.add("fence_post", post, Transform3D(Basis().scaled(Vector3(1.0, FENCE_HEIGHT, 1.0)), Vector3(q.x, base + FENCE_HEIGHT * 0.5, q.y)))
	for i in n:
		var q := c + dir * (-length * 0.5 + (float(i) + 0.5) * panel)
		ch._batch.add("fence_mesh", chain_link_panel(), Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(panel, 1.0, 1.0)), Vector3(q.x, base, q.y)))
		ch._batch.add("fence_post", post, Transform3D((Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI * 0.5)).scaled_local(Vector3(1.0, panel, 1.0)), Vector3(q.x, base + FENCE_HEIGHT, q.y)))
	ch._batch.set_no_shadow("fence_mesh")
	ch._batch.set_shadow_distance("fence_post", 40.0)


static var _chain_link: ArrayMesh = null


## One metre of chain-link, FENCE_HEIGHT tall, centred on x, standing on y 0, both faces; UV in
## metres (x along, y up) for the shader's diamond mesh. Instances stretch it along x.
static func chain_link_panel() -> ArrayMesh:
	if _chain_link != null:
		return _chain_link
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := FENCE_HEIGHT - 0.05
	var pts := [Vector3(-0.5, 0.05, 0.0), Vector3(0.5, 0.05, 0.0), Vector3(0.5, h, 0.0), Vector3(-0.5, h, 0.0)]
	var uvs := [Vector2(0.0, 0.05), Vector2(1.0, 0.05), Vector2(1.0, h), Vector2(0.0, h)]
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3(0.0, 0.0, 1.0))
		st.set_uv(uvs[k])
		st.add_vertex(pts[k])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/chain_link.gdshader")
	st.set_material(mat)
	_chain_link = st.commit()
	return _chain_link


## A pay booth by the way in: a small cabin in precast with a dark window band all round, its roof
## overhanging, and a boom post.
static func _booth(ch: CityChunk, gate: Vector2, street: int, rng: RandomNumberGenerator) -> void:
	var inward := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)][street] as Vector2
	var side := Vector2(inward.y, -inward.x) * (1.0 if rng.randf() < 0.5 else -1.0)
	var c := gate + inward * 3.0 + side * 4.6
	var base := CityChunk.SIDEWALK_TOP + ASPHALT_LIFT
	var mat := Building.plinth_material()
	_solid(ch, Vector3(c.x, base + 0.5, c.y), Vector3(1.9, 1.0, 1.9), mat)
	_box(ch, Vector3(1.8, 1.1, 1.8), Vector3(c.x, base + 1.55 + ch._gy(c.x, c.y), c.y), KIND_DARK)
	_solid(ch, Vector3(c.x, base + 2.25, c.y), Vector3(2.5, 0.3, 2.5), mat, false)



# --- What a landmark's square left -------------------------------------------------------------

## The cells CityPlan.lots() dropped for a landmark's square, less what the landmark stands on:
## forecourt round it (its plaza), or now and then a car park. A downtown tower's own footprint
## is known (LandmarkDowntown.footprint(), kept 4 m clear); any other landmark keeps its whole
## square, whose shape nothing here knows.
static func leftovers(ch: CityChunk, block: Dictionary) -> void:
	if ch.plan.macro == null:
		return
	var cells := ch.plan.dropped_cells(ch.ix, ch.iz)
	if cells.is_empty():
		return
	var rect: Rect2 = block.rect
	var holes: Array[Rect2] = []
	for lm in Landmarks.all():
		if lm.get("area") is Dictionary:
			continue
		var r: float = lm.radius
		var sq := Rect2((lm.anchor as Vector2) - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
		if not sq.intersects(rect):
			continue
		if LandmarkDowntown.is_tower(str(lm.id)):
			holes.append(LandmarkDowntown.footprint(lm).grow(4.0))
		else:
			holes.append(sq)
	var k := 0
	for cell: Rect2 in cells:
		for piece: Rect2 in _minus(cell, holes, 0.0):
			k += 1
			if minf(piece.size.x, piece.size.y) < 2.0:
				continue
			var rng := _rng(ch, "leftover", k)
			if piece.size.x >= 24.0 and piece.size.y >= 18.0 and rng.randf() < LEFTOVER_PARK_ODDS:
				_car_park(ch, piece, hash([k, "leftover_park"]))
				continue
			var paving := "paving%d" % _paving_for(ch)
			_ground(ch, piece, paving)
			if ch.level == CityChunk.Level.FULL and not ch.capturing:
				forecourt(ch, piece.grow(-0.4), rng)


# --- Rects --------------------------------------------------------------------------------------

## `area` less every rect in `holes` (each grown by `margin`), as a few rects: the area is cut on
## every hole edge, the free cells are merged into runs along x, and runs of the same extent are
## stacked along z (ArenaGrounds.leftovers()'s way). Slivers under 0.5 m are dropped.
static func _minus(area: Rect2, holes: Array[Rect2], margin: float) -> Array[Rect2]:
	var cuts: Array[Rect2] = []
	for h: Rect2 in holes:
		var g := h.grow(margin)
		if g.intersects(area):
			cuts.append(g.intersection(area))
	if cuts.is_empty():
		return [area]
	var xs: Array[float] = [area.position.x, area.end.x]
	var zs: Array[float] = [area.position.y, area.end.y]
	for c: Rect2 in cuts:
		for x: float in [c.position.x, c.end.x]:
			if x > area.position.x + 0.01 and x < area.end.x - 0.01 and not xs.has(x):
				xs.append(x)
		for z: float in [c.position.y, c.end.y]:
			if z > area.position.y + 0.01 and z < area.end.y - 0.01 and not zs.has(z):
				zs.append(z)
	xs.sort()
	zs.sort()
	var runs: Array[Rect2] = []
	for j in zs.size() - 1:
		var run := Rect2()
		var open := false
		for i in xs.size() - 1:
			var cell := Rect2(Vector2(xs[i], zs[j]), Vector2(xs[i + 1] - xs[i], zs[j + 1] - zs[j]))
			var covered := false
			for c: Rect2 in cuts:
				if c.has_point(cell.get_center()):
					covered = true
					break
			if covered:
				if open:
					runs.append(run)
				open = false
			elif open:
				run = run.merge(cell)
			else:
				run = cell
				open = true
		if open:
			runs.append(run)
	var out: Array[Rect2] = []
	for r in runs:
		var merged := false
		for k in out.size():
			var o := out[k]
			if is_equal_approx(o.position.x, r.position.x) and is_equal_approx(o.size.x, r.size.x) and is_equal_approx(o.end.y, r.position.y):
				out[k] = o.merge(r)
				merged = true
				break
		if not merged:
			out.append(r)
	var kept: Array[Rect2] = []
	for r in out:
		if minf(r.size.x, r.size.y) >= 0.5:
			kept.append(r)
	return kept


# --- Probe (tools/lot_coverage.gd) ----------------------------------------------------------------

## What the fill makes of a lot, for the coverage probe: {"kind": "podium_parking" |
## "podium_retail" | "forecourt" | "parking", "holes": the ground parts, lot-local}.
static func plan_lot(_plan: CityPlan, lot: Dictionary, bld: Building, _district: int, _boost: float) -> Dictionary:
	if lot.get("parking", false):
		return {"kind": "parking", "holes": []}
	var kind := "forecourt"
	if bld.podium_kind == 2:
		kind = "podium_parking"
	elif bld.podium_kind == 1:
		kind = "podium_retail"
	return {"kind": kind}


## True where the fill covers lot-local point `p` (anything the building does not stand on is
## forecourt or car park out to the cell, so everything left in the lot is covered).
static func covers(_fill: Dictionary, _p: Vector2) -> bool:
	return true
