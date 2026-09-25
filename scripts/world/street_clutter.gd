class_name StreetClutter
extends RefCounted
## The everyday clutter of a Los Angeles pavement, the stuff nobody designed: coin-op newspaper
## boxes and free-magazine racks huddled in a row near the corner, chalkboard A-frames put out
## by the shops, and the litter and dead leaves the street sweeper missed, lying in the gutter
## against the kerb.
##
## Every mesh is built here in code at real dimensions - bevelled steel boxes, bent tube
## handles, a printed front page behind the window glass, magazine covers, chalk writing -
## on one shader (shaders/street_clutter.gdshader) that takes its paint from the MultiMesh
## instance custom data and its printed faces from the vertex colour's alpha, so a whole
## chunk's news boxes are one draw call, its A-frames another, and each litter variant another.
##
## Seeding: nothing here touches the block's RandomNumberGenerator. StreetDetail still makes
## every roll it always made for the news boxes (so the parked cars and the crowd that roll
## after it are unmoved) and hands the results over; everything else comes from generators
## seeded by a hash of the city seed and the block (`_rng_for`). Same seed, same street.
##
## Static: call with the chunk.

# --- Tunables --------------------------------------------------------------------------------
# Never instanced (every entry point is static), so the knobs are consts here at the top.

## Metres between the boxes of a news cluster (a box is 0.5 m wide, a rack 0.46 m).
const NEWS_GAP := 0.6
## Chance a news corner grows one or two boxes past the ones StreetDetail rolled.
const NEWS_EXTRA_ODDS := 0.65
## Share of a cluster that is open-front free-magazine racks rather than coin-op paper boxes.
const MAG_RACK_SHARE := 0.4
## How far news boxes and racks draw. A chunk's batch is measured from its centre, so anything
## under ~120 m can vanish in the far corner of the block the player is standing in.
const NEWS_DRAW_DISTANCE := 150.0
## Chance per block face (by CityPlan.District) that its shops put out an A-frame board.
const BOARD_ODDS := [0.7, 0.5, 0.06, 0.1, 0.3, 0.55]
## Most A-frames on one block.
const BOARD_MAX := 4
## A board only stands where a building front is within this many metres of the kerb (downtown
## sets its towers well back behind plazas, so this is generous), and it stands against the
## front itself only when that is under BOARD_AT_WALL.
const BOARD_FRONTAGE := 16.0
const BOARD_AT_WALL := 6.0
const BOARD_DRAW_DISTANCE := 130.0
## Litter drifts per metre of kerb, by CityPlan.District. A drift is ~1.8 m of gutter.
const LITTER_PER_M := [0.14, 0.08, 0.035, 0.11, 0.04, 0.07]
const LITTER_DRAW_DISTANCE := 120.0
## Clearance kept from anything already on the pavement (lamps, meters, trees, cans...).
const CLEAR := 0.55

## Coin-op box paint: mostly the reds, blues, yellows and greens the real ones come in, plus
## the black and white ones, and a faded orange.
const NEWS_PAINTS := [
	Color(0.62, 0.1, 0.09), Color(0.12, 0.24, 0.52), Color(0.86, 0.66, 0.1), Color(0.12, 0.3, 0.18),
	Color(0.08, 0.08, 0.09), Color(0.82, 0.82, 0.8), Color(0.78, 0.36, 0.1), Color(0.2, 0.42, 0.62),
]
## A-frame frames: black steel, dark stained wood, natural wood, white paint.
const BOARD_FRAMES := [Color(0.07, 0.07, 0.075), Color(0.24, 0.15, 0.09), Color(0.52, 0.37, 0.22), Color(0.86, 0.85, 0.82)]

## Batch keys (one draw call each per chunk).
const K_NEWS := "sc_newsbox"
const K_RACK := "sc_magrack"
const K_BOARD := "sc_board"
const K_LITTER := "sc_litter_"
const LITTER_VARIANTS := 3

# Vertex colour alpha codes, read by shaders/street_clutter.gdshader.
const A_FIXED := 0.0       # the vertex colour is the colour
const A_NEWS := 0.25       # a newspaper front page behind glass (UV 0..1 over the page)
const A_COVER := 0.5       # a magazine cover (UV.x's whole part picks the cover)
const A_CHALK := 0.75      # chalk on a slate board (likewise)
const A_PAINT := 1.0       # the instance's paint (INSTANCE_CUSTOM.rgb)

static var _meshes: Dictionary = {}


# --- Placement ---------------------------------------------------------------------------------

## The clutter of one block, after StreetDetail's furniture (so it can keep clear of it).
## `news` is StreetDetail's rolled news corners: [point, dir, inward, [paint Color, ...]].
static func build_block(chunk: CityChunk, rect: Rect2, edges: Array, district: int, news: Array) -> void:
	var occupied := _occupied(chunk)
	for n: Array in news:
		_news_cluster(chunk, n[0], n[1], n[2], n[3], occupied)
	_boards(chunk, rect, edges, district, occupied)
	_litter(chunk, edges, district)


## A row of news boxes and magazine racks along the kerb, fronts to the pavement.
static func _news_cluster(chunk: CityChunk, p: Vector2, dir: Vector2, inward: Vector2, paints: Array, occupied: Array) -> void:
	var top: float = CityChunk.SIDEWALK_TOP
	var rng := _rng_for([chunk.plan.seed, "news_cluster", int(p.x * 10.0), int(p.y * 10.0)])
	var count := paints.size()
	if rng.randf() < NEWS_EXTRA_ODDS:
		count += 1 + int(rng.randf() < 0.4)
	var yaw := atan2(-inward.x, -inward.y)
	var t := 0.0
	for i in count:
		var rack := rng.randf() < MAG_RACK_SHARE
		var paint: Color = paints[i] if i < paints.size() else NEWS_PAINTS[rng.randi() % NEWS_PAINTS.size()]
		if rack and paint.get_luminance() > 0.7:
			paint = paint.darkened(0.2)
		var q := p + dir * t + inward * rng.randf_range(-0.05, 0.05)
		t += NEWS_GAP + rng.randf_range(-0.03, 0.06)
		var seed01 := rng.randf()
		var y := yaw + rng.randf_range(-0.07, 0.07)
		if not _clear(occupied, q, 0.3):
			continue
		occupied.append([q, 0.3])
		var at := Vector3(q.x, top, q.y)
		var custom := Color(paint.r, paint.g, paint.b, seed01)
		var mesh := magazine_rack() if rack else news_box()
		chunk._add_prop("newsbox", at, paint, [
			[K_RACK if rack else K_NEWS, mesh, Transform3D(Basis(Vector3.UP, y), at), Color.WHITE, custom],
		], [[Vector3(0.5, 1.12, 0.44), at + Vector3(0.0, 0.56, 0.0), y]])
	chunk._batch.set_draw_distance(K_NEWS, NEWS_DRAW_DISTANCE)
	chunk._batch.set_draw_distance(K_RACK, NEWS_DRAW_DISTANCE)


## Chalkboard A-frames the shops put out: on the kerb side of the pavement or against the
## shopfront, panels facing along the pavement, only where there is a building front to belong
## to. Breakable (one shape each).
static func _boards(chunk: CityChunk, _rect: Rect2, edges: Array, district: int, occupied: Array) -> void:
	var plan: CityPlan = chunk.plan
	var odds: float = BOARD_ODDS[district]
	if odds <= 0.0:
		return
	# Shops, so blocks of buildings. Downtown's core towers are landmarks rather than Building
	# nodes, so a block with no footprints to test takes the kerb side on trust.
	if int(plan.block(chunk.ix, chunk.iz).kind) != CityPlan.BlockKind.BUILDINGS:
		return
	var walls := StreetDetail._footprints(chunk)
	var top: float = CityChunk.SIDEWALK_TOP
	var placed := 0
	for e in edges.size():
		if placed >= BOARD_MAX:
			break
		var rng := _rng_for([plan.seed, "aboard", chunk.ix, chunk.iz, e])
		if rng.randf() > odds:
			continue
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		if length < 24.0:
			continue
		var dir := (b - a) / length
		for k in 1 + int(rng.randf() < 0.45):
			var t := rng.randf_range(9.0, length - 9.0)
			var kerb := a + dir * t
			var wall := _wall_depth(walls, kerb, inward) if not walls.is_empty() else BOARD_FRONTAGE
			var by_door := rng.randf() < 0.45
			var frame: Color = BOARD_FRAMES[rng.randi() % BOARD_FRAMES.size()]
			var seed01 := rng.randf()
			var spin := rng.randf_range(-0.25, 0.25) + (PI if rng.randf() < 0.5 else 0.0)
			if wall > BOARD_FRONTAGE or placed >= BOARD_MAX:
				continue
			var depth := wall - 0.5 if by_door and wall > 2.6 and wall < BOARD_AT_WALL else rng.randf_range(1.2, 1.5)
			var q := kerb + inward * depth
			if not _clear(occupied, q, 0.45):
				continue
			occupied.append([q, 0.45])
			placed += 1
			var at := Vector3(q.x, top, q.y)
			var y := atan2(-dir.x, -dir.y) + spin
			chunk._add_prop("aboard", at, frame, [
				[K_BOARD, a_frame(), Transform3D(Basis(Vector3.UP, y), at), Color.WHITE, Color(frame.r, frame.g, frame.b, seed01)],
			], [[Vector3(0.62, 0.95, 0.5), at + Vector3(0.0, 0.47, 0.0), y]])
	chunk._batch.set_draw_distance(K_BOARD, BOARD_DRAW_DISTANCE)


## Litter and dead leaves in the gutter, against the kerb face, along all four of the block's
## kerbs. Drawn only (you walk through it), flat, and no shadow.
static func _litter(chunk: CityChunk, edges: Array, district: int) -> void:
	var batch: MultiMeshBatch = chunk._batch
	var y0: float = CityChunk.ROAD_TOP + 0.008
	for v in LITTER_VARIANTS:
		batch.tilt_keys[K_LITTER + str(v)] = true
	for e in edges.size():
		var rng := _rng_for([chunk.plan.seed, "litter", chunk.ix, chunk.iz, e])
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		if length < 8.0:
			continue
		var dir := (b - a) / length
		var yaw := atan2(-inward.x, -inward.y)
		var count := int(length * float(LITTER_PER_M[district]) * rng.randf_range(0.6, 1.4))
		for i in count:
			var t := rng.randf_range(1.5, length - 1.5)
			var v := rng.randi() % LITTER_VARIANTS
			var out := rng.randf_range(0.0, 0.05)
			# Clear of the storm grates StreetDetail puts 4 m in from each end.
			if absf(t - 4.0) < 1.4 or absf(t - (length - 4.0)) < 1.4:
				continue
			# Local +Z runs out from the kerb into the road. Never mirrored: a mirror turns the
			# faces inside out and the drift would draw its undersides.
			var p := a + dir * t - inward * out
			var basis := Basis(Vector3.UP, yaw)
			batch.add(K_LITTER + str(v), litter(v), Transform3D(basis, Vector3(p.x, y0, p.y)))
	for v in LITTER_VARIANTS:
		batch.set_no_shadow(K_LITTER + str(v))
		batch.set_draw_distance(K_LITTER + str(v), LITTER_DRAW_DISTANCE)


## Everything already on this chunk's pavements: breakable props, street trees, trash cans.
static func _occupied(chunk: CityChunk) -> Array:
	var out: Array = []
	for r: Dictionary in chunk.prop_records:
		var p: Vector3 = r.position
		var reach := 2.4 if String(r.kind) == "bus_stop" else (1.0 if String(r.kind) == "cafe" else CLEAR)
		out.append([Vector2(p.x, p.z), reach])
	var data: Dictionary = chunk._batch.data()
	if data.has("tree_grate"):
		for x: Transform3D in data["tree_grate"].xforms:
			out.append([Vector2(x.origin.x, x.origin.z), 0.95])
	for c in chunk.get_children():
		if c is TrashCan or c is PhysicsProp:
			out.append([Vector2((c as Node3D).position.x, (c as Node3D).position.z), CLEAR])
	return out


static func _clear(occupied: Array, p: Vector2, half: float) -> bool:
	for o: Array in occupied:
		if (o[0] as Vector2).distance_to(p) < float(o[1]) + half:
			return false
	return true


## Metres from the kerb to the nearest ground-floor wall walking inward (BOARD_FRONTAGE + 1
## when there is none that close).
static func _wall_depth(walls: Array[Rect2], kerb: Vector2, inward: Vector2) -> float:
	var steps := int((BOARD_FRONTAGE - 1.5) / 0.25) + 1
	for k in steps:
		var d := 1.5 + k * 0.25
		var probe := kerb + inward * d
		for r: Rect2 in walls:
			if r.has_point(probe):
				return d
	return BOARD_FRONTAGE + 1.0


static func _rng_for(parts: Array) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(parts)
	return rng


# --- Material ----------------------------------------------------------------------------------

## The one material everything here wears. `litter` turns the painted-steel detail, the grime
## and the stickers off (leaves and paper are not painted steel).
static func material(litter_look: bool = false) -> ShaderMaterial:
	var key := "sc_mat_litter" if litter_look else "sc_mat"
	if _meshes.has(key):
		return _meshes[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/street_clutter.gdshader")
	var albedo := PropFactory.texture("metal_painted", "Color")
	mat.set_shader_parameter("use_detail", albedo != null and not litter_look)
	if albedo:
		mat.set_shader_parameter("detail_albedo", albedo)
		mat.set_shader_parameter("detail_normal", PropFactory.texture("metal_painted", "NormalGL"))
		mat.set_shader_parameter("detail_rough", PropFactory.texture("metal_painted", "Roughness"))
	if litter_look:
		mat.set_shader_parameter("grime", 0.0)
		mat.set_shader_parameter("stickers", 0.0)
	_meshes[key] = mat
	return mat


# --- Meshes ------------------------------------------------------------------------------------
# Origin at the base, Y up, the front (the side you use) toward local -Z.

## A coin-op newspaper vending box on its pedestal: 0.5 x 0.42 m, 1.18 m to the top of the coin
## mechanism, the window in the door showing today's front page.
static func news_box() -> Mesh:
	if _meshes.has(K_NEWS):
		return _meshes[K_NEWS]
	var st := _begin()
	var steel := Color(0.11, 0.11, 0.12)
	var galv := Color(0.6, 0.61, 0.62)
	var chrome := Color(0.78, 0.79, 0.8)
	var paint := Color(1, 1, 1, A_PAINT)
	var rm_paint := Vector2(0.42, 0.0)
	# Pedestal: base plate, square column, mounting plate.
	_bbox(st, _at(0.0, 0.008, 0.02), Vector3(0.36, 0.016, 0.3), 0.004, steel, Vector2(0.6, 0.4))
	_bbox(st, _at(0.0, 0.2, 0.02), Vector3(0.075, 0.37, 0.075), 0.006, steel, Vector2(0.55, 0.4))
	_bbox(st, _at(0.0, 0.392, 0.0), Vector3(0.3, 0.014, 0.26), 0.004, steel, Vector2(0.6, 0.4))
	# Cabinet and its overhanging lid.
	_bbox(st, _at(0.0, 0.7, 0.0), Vector3(0.5, 0.6, 0.42), 0.014, paint, rm_paint)
	_bbox(st, _at(0.0, 1.018, 0.0), Vector3(0.52, 0.036, 0.44), 0.012, paint, rm_paint)
	# Coin mechanism housing on the lid, its slot plate, slot, price label and return button.
	_bbox(st, _at(0.13, 1.106, 0.06), Vector3(0.17, 0.14, 0.22), 0.012, galv, Vector2(0.4, 0.85))
	_bbox(st, _at(0.13, 1.11, -0.0535), Vector3(0.11, 0.08, 0.006), 0.002, chrome, Vector2(0.22, 1.0))
	_bbox(st, _at(0.13, 1.128, -0.0572), Vector3(0.036, 0.006, 0.004), 0.001, Color(0.02, 0.02, 0.02), Vector2(0.6, 0.0))
	_bbox(st, _at(0.13, 1.092, -0.0572), Vector3(0.07, 0.024, 0.003), 0.001, Color(0.9, 0.88, 0.8), Vector2(0.7, 0.0))
	_cyl(st, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.195, 1.14, -0.05)), 0.009, 0.012, 0.008, chrome, Vector2(0.25, 1.0))
	# The door: a panel proud of the cabinet, framing the window.
	var zf := -0.2175
	_bbox(st, _at(0.0, 0.555, zf), Vector3(0.47, 0.25, 0.015), 0.005, paint, rm_paint)
	_bbox(st, _at(0.0, 0.968, zf), Vector3(0.47, 0.035, 0.015), 0.005, paint, rm_paint)
	_bbox(st, _at(-0.2125, 0.815, zf), Vector3(0.045, 0.27, 0.015), 0.005, paint, rm_paint)
	_bbox(st, _at(0.2125, 0.815, zf), Vector3(0.045, 0.27, 0.015), 0.005, paint, rm_paint)
	# The page behind the glass (the glass is the page's own gloss).
	_page(st, Vector3(0.19, 0.95, -0.2115), Vector3(-0.19, 0.95, -0.2115), Vector3(-0.19, 0.68, -0.2115), Vector3(0.19, 0.68, -0.2115),
		Vector3(0, 0, -1), A_NEWS, Vector2(0.0, 0.0), Vector2(0.06, 0.0))
	# Pull handle on two stand-offs, and the lock.
	_tube(st, [Vector3(-0.12, 0.625, -0.226), Vector3(-0.12, 0.625, -0.248), Vector3(0.12, 0.625, -0.248), Vector3(0.12, 0.625, -0.226)], 0.0095, 8, chrome, Vector2(0.2, 1.0))
	_cyl(st, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.17, 0.5, -0.225)), 0.016, 0.016, 0.008, chrome, Vector2(0.25, 1.0))
	# Hinge knuckles along the door's top edge.
	for x in [-0.15, 0.15]:
		_cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x - 0.03, 0.99, -0.228)), 0.008, 0.008, 0.06, steel, Vector2(0.5, 0.6))
	return _finish(st, K_NEWS)


## An open-front rack of free papers and magazines: 0.47 x 0.38 m, 1.05 m tall plus the header
## card, three sloped shelves with a stack on each.
static func magazine_rack() -> Mesh:
	if _meshes.has(K_RACK):
		return _meshes[K_RACK]
	var st := _begin()
	var paint := Color(1, 1, 1, A_PAINT)
	var rm := Vector2(0.5, 0.0)
	var paper := Color(0.82, 0.8, 0.75)
	for s in [-1.0, 1.0]:
		_bbox(st, _at(s * 0.222, 0.51, 0.0), Vector3(0.018, 1.02, 0.36), 0.005, paint, rm)
		# Feet: a steel shoe under each side.
		_bbox(st, _at(s * 0.222, 0.006, 0.0), Vector3(0.05, 0.012, 0.4), 0.003, Color(0.1, 0.1, 0.11), Vector2(0.6, 0.4))
	_bbox(st, _at(0.0, 0.52, 0.172), Vector3(0.426, 1.0, 0.016), 0.004, paint, rm)
	_bbox(st, _at(0.0, 1.033, 0.0), Vector3(0.47, 0.026, 0.38), 0.008, paint, rm)
	# The header card, leaning back on the top.
	var hb := Basis(Vector3.RIGHT, -0.28)
	var hx := Transform3D(hb, Vector3(0.0, 1.11, -0.1))
	_bbox(st, hx, Vector3(0.44, 0.13, 0.012), 0.003, paint, rm)
	var hn := hb * Vector3(0, 0, -1)
	_page(st, hx * Vector3(0.2, 0.055, -0.0068), hx * Vector3(-0.2, 0.055, -0.0068), hx * Vector3(-0.2, -0.055, -0.0068), hx * Vector3(0.2, -0.055, -0.0068),
		hn, A_COVER, Vector2(7.0, 0.0), Vector2(0.35, 0.0), Vector2(0.95, 0.3))
	# Shelves, each sloped back, with a lip and a stack of papers on it.
	var shelves := [0.07, 0.4, 0.73]
	for i in shelves.size():
		var y: float = shelves[i]
		# Rising toward the back (the lip in front holds the stack), steep enough that the
		# covers face you from standing height. Tilted the other way they face the back panel.
		var sb := Basis(Vector3.RIGHT, -0.5)
		var sx := Transform3D(sb, Vector3(0.0, y + 0.07, 0.0))
		_bbox(st, sx, Vector3(0.426, 0.012, 0.31), 0.003, paint, rm)
		_bbox(st, sx * _at(0.0, 0.022, -0.149), Vector3(0.426, 0.045, 0.012), 0.003, paint, rm)
		var thick := 0.025 + 0.012 * float((i * 5 + 2) % 3)
		var stack := sx * Transform3D(Basis(), Vector3(0.0, 0.006 + thick * 0.5, 0.01))
		_bbox(st, stack, Vector3(0.33, thick, 0.27), 0.002, paper, Vector2(0.85, 0.0))
		var h := thick * 0.5 + 0.0012
		_page(st, stack * Vector3(0.165, h, 0.135), stack * Vector3(-0.165, h, 0.135), stack * Vector3(-0.165, h, -0.135), stack * Vector3(0.165, h, -0.135),
			sb * Vector3.UP, A_COVER, Vector2(float(i), 0.0), Vector2(0.3, 0.0))
	return _finish(st, K_RACK)


## A chalkboard A-frame ("sandwich board"): two 0.6 x 0.95 m framed boards hinged at the top,
## feet 0.46 m apart, a spreader bar each side. Faces along local Z.
static func a_frame() -> Mesh:
	if _meshes.has(K_BOARD):
		return _meshes[K_BOARD]
	var st := _begin()
	var frame := Color(1, 1, 1, A_PAINT)
	var rm := Vector2(0.62, 0.0)
	var slate := Color(0.06, 0.065, 0.065)
	var length := 0.955
	var tilt := atan2(0.225, 0.93)
	var sides := [
		Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(0.0, 0.0, -0.225)),
		Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, tilt), Vector3(0.0, 0.0, 0.225)),
	]
	for s in sides.size():
		var px: Transform3D = sides[s]
		# Stiles run to the ground, rails top and bottom, the slate between them.
		for x in [-0.28, 0.28]:
			_bbox(st, px * _at(x, length * 0.5, 0.0), Vector3(0.04, length, 0.028), 0.006, frame, rm)
		_bbox(st, px * _at(0.0, length - 0.03, 0.0), Vector3(0.52, 0.06, 0.028), 0.006, frame, rm)
		_bbox(st, px * _at(0.0, 0.12, 0.0), Vector3(0.52, 0.07, 0.028), 0.006, frame, rm)
		_bbox(st, px * _at(0.0, 0.525, 0.0), Vector3(0.52, 0.74, 0.012), 0.002, slate, Vector2(0.85, 0.0))
		var n: Vector3 = px.basis * Vector3(0, 0, -1)
		_page(st, px * Vector3(0.26, 0.895, -0.0072), px * Vector3(-0.26, 0.895, -0.0072), px * Vector3(-0.26, 0.155, -0.0072), px * Vector3(0.26, 0.155, -0.0072),
			n, A_CHALK, Vector2(float(s), 0.0), Vector2(0.88, 0.0))
	# Spreader bars and the hinge pin.
	var steel := Color(0.3, 0.3, 0.31)
	for x in [-0.25, 0.25]:
		_tube(st, [sides[0] * Vector3(x, 0.42, 0.016), sides[1] * Vector3(-x, 0.42, 0.016)], 0.005, 6, steel, Vector2(0.4, 0.9))
	_tube(st, [Vector3(-0.3, length * cos(tilt) - 0.005, 0.0), Vector3(0.3, length * cos(tilt) - 0.005, 0.0)], 0.009, 8, steel, Vector2(0.4, 0.9))
	return _finish(st, K_BOARD)


## One gutter drift, `variant` 0..2: ~1.8 m of it along local X, lying on the asphalt from the
## kerb face (z 0) out into the road (+z). Dead leaves banked against the kerb, a grit line in
## the corner, a crushed cup or can, a balled-up paper, a flattened wrapper.
static func litter(variant: int) -> Mesh:
	var key := K_LITTER + str(variant)
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["street_litter", variant])
	var st := _begin()
	# Grit and dust in the corner between gutter and kerb face.
	var grit := Color(0.2, 0.18, 0.15)
	var segs := 14
	var prev_w := rng.randf_range(0.04, 0.1)
	for i in segs:
		var x0 := -0.9 + 1.8 * float(i) / segs
		var x1 := -0.9 + 1.8 * float(i + 1) / segs
		var w := rng.randf_range(0.03, 0.12)
		_tri(st, Vector3(x0, 0.001, 0.0), Vector3(x1, 0.001, 0.0), Vector3(x1, 0.001, w), Vector3.UP, grit, Vector2(0.95, 0.0))
		_tri(st, Vector3(x0, 0.001, 0.0), Vector3(x1, 0.001, w), Vector3(x0, 0.001, prev_w), Vector3.UP, grit, Vector2(0.95, 0.0))
		prev_w = w
	# Dead leaves, banked toward the kerb.
	var leaf_colors := [Color(0.38, 0.29, 0.18), Color(0.47, 0.38, 0.23), Color(0.3, 0.23, 0.15), Color(0.5, 0.41, 0.24),
		Color(0.34, 0.34, 0.2), Color(0.42, 0.27, 0.17), Color(0.56, 0.5, 0.36)]
	for i in rng.randi_range(12, 20):
		var c := Vector3(rng.randf_range(-0.85, 0.85), 0.0, 0.025 + 0.4 * pow(rng.randf(), 2.2))
		var col: Color = leaf_colors[rng.randi() % leaf_colors.size()]
		col = col.darkened(rng.randf_range(0.0, 0.2))
		_leaf(st, c, rng.randf_range(0.05, 0.11), rng.randf_range(0.45, 0.7), rng.randf_range(0.0, TAU), rng.randf_range(0.004, 0.014), col)
	# A crushed paper cup or a can.
	var along := rng.randf_range(0.0, TAU)
	var c0 := Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(0.1, 0.35))
	if variant != 1:
		var band: Color = [Color(0.55, 0.12, 0.1), Color(0.12, 0.35, 0.22), Color(0.35, 0.22, 0.14)][variant % 3]
		_cup(st, c0, along, band)
	if variant != 0:
		var can: Color = [Color(0.6, 0.1, 0.1), Color(0.72, 0.72, 0.74), Color(0.12, 0.3, 0.55)][(variant + 1) % 3]
		_can(st, c0 + Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.05, 0.1)), along + 1.3, can)
	# Balled-up paper and a flattened wrapper.
	_paper_ball(st, Vector3(rng.randf_range(-0.8, 0.8), 0.0, rng.randf_range(0.05, 0.3)), 0.03 + 0.01 * variant, rng,
		Color(0.84, 0.83, 0.8) if variant != 2 else Color(0.56, 0.43, 0.3))
	var wrap: Color = [Color(0.88, 0.86, 0.8), Color(0.85, 0.7, 0.2), Color(0.75, 0.2, 0.15)][variant % 3]
	_wrapper(st, Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(0.08, 0.3)), rng.randf_range(0.0, TAU), wrap, rng)
	var mesh := st.commit()
	mesh.surface_set_material(0, material(true))
	_meshes[key] = mesh
	return mesh


# --- Geometry helpers --------------------------------------------------------------------------

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _finish(st: SurfaceTool, key: String) -> Mesh:
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_meshes[key] = mesh
	return mesh


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


## One vertex. Every vertex carries the same attributes (a SurfaceTool's format is fixed by its
## first vertex): colour (alpha = the shader's code), normal, UV (metres, or 0..1 on a printed
## face), UV2 = (roughness, metallic).
static func _vtx(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, col: Color, rm: Vector2) -> void:
	# A plain Color is opaque, and alpha 1 is the paint code: only pure white means "the
	# instance's paint", any other colour is its own (A_FIXED). Printed faces pass their codes.
	if col.a > 0.99 and not col.is_equal_approx(Color.WHITE):
		col.a = A_FIXED
	st.set_color(col)
	st.set_normal(n)
	st.set_uv(uv)
	st.set_uv2(rm)
	st.add_vertex(p)


## A flat triangle turned to face `want`, UVs projected from the dominant axis in metres.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3, col: Color, rm: Vector2) -> void:
	var cr := (c - a).cross(b - a)
	if cr.length_squared() < 1e-14:
		return
	if cr.dot(want) < 0.0:
		var t := b
		b = c
		c = t
		cr = -cr
	var n := cr.normalized()
	for p: Vector3 in [a, b, c]:
		_vtx(st, p, n, _proj(p, n), col, rm)


static func _proj(p: Vector3, n: Vector3) -> Vector2:
	var an := n.abs()
	if an.y >= an.x and an.y >= an.z:
		return Vector2(p.x, p.z)
	if an.x >= an.z:
		return Vector2(p.z, -p.y)
	return Vector2(p.x, -p.y)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, col: Color, rm: Vector2) -> void:
	_tri(st, a, b, c, want, col, rm)
	_tri(st, a, c, d, want, col, rm)


## A printed face: corners top-left, top-right, bottom-right, bottom-left as seen from the front,
## UV 0..1 over it plus `uv_offset` (whose whole part tells covers apart).
static func _page(st: SurfaceTool, tl: Vector3, tr: Vector3, br: Vector3, bl: Vector3, n: Vector3, code: float, uv_offset: Vector2, rm: Vector2, span: Vector2 = Vector2.ONE) -> void:
	var col := Color(1, 1, 1, code)
	var pts := [[tl, Vector2(0, 0)], [tr, Vector2(span.x, 0)], [br, Vector2(span.x, span.y)], [bl, Vector2(0, span.y)]]
	var n1 := n.normalized()
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		var p0: Array = pts[tri[0]]
		var p1: Array = pts[tri[1]]
		var p2: Array = pts[tri[2]]
		var a: Vector3 = p0[0]
		var b: Vector3 = p1[0]
		var c: Vector3 = p2[0]
		if (c - a).cross(b - a).dot(n1) < 0.0:
			_vtx(st, a, n1, p0[1] + uv_offset, col, rm)
			_vtx(st, c, n1, p2[1] + uv_offset, col, rm)
			_vtx(st, b, n1, p1[1] + uv_offset, col, rm)
		else:
			_vtx(st, a, n1, p0[1] + uv_offset, col, rm)
			_vtx(st, b, n1, p1[1] + uv_offset, col, rm)
			_vtx(st, c, n1, p2[1] + uv_offset, col, rm)


## A box with chamfered edges and corners (flat facets, so every edge catches the light, which is
## most of what makes a steel box read as made rather than as a primitive). 44 triangles.
static func _bbox(st: SurfaceTool, xf: Transform3D, size: Vector3, bevel: float, col: Color, rm: Vector2) -> void:
	var h := size * 0.5
	var bv := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var corner := func(s: Vector3, k: int) -> Vector3:
		var v := Vector3(s.x * (h.x - bv), s.y * (h.y - bv), s.z * (h.z - bv))
		v[k] = s[k] * h[k]
		return xf * v
	var axes := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
	# Faces.
	for k in 3:
		var j := (k + 1) % 3
		var l := (k + 2) % 3
		for sg in [-1.0, 1.0]:
			var quad: Array = []
			for pair in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
				var s := Vector3.ZERO
				s[k] = sg
				s[j] = pair[0]
				s[l] = pair[1]
				quad.append(corner.call(s, k))
			_quad(st, quad[0], quad[1], quad[2], quad[3], xf.basis * (axes[k] * sg), col, rm)
	if bv <= 0.0:
		return
	# Edge chamfers.
	for k in 3:
		for m in range(k + 1, 3):
			var l := 3 - k - m
			for sk in [-1.0, 1.0]:
				for sm in [-1.0, 1.0]:
					var s0 := Vector3.ZERO
					s0[k] = sk
					s0[m] = sm
					s0[l] = -1.0
					var s1 := s0
					s1[l] = 1.0
					_quad(st, corner.call(s0, k), corner.call(s1, k), corner.call(s1, m), corner.call(s0, m), xf.basis * (axes[k] * sk + axes[m] * sm), col, rm)
	# Corner facets.
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				_tri(st, corner.call(s, 0), corner.call(s, 1), corner.call(s, 2), xf.basis * s, col, rm)


## A capped cylinder along local Y from 0 to `height`, radius r0 at the bottom, r1 at the top.
static func _cyl(st: SurfaceTool, xf: Transform3D, r0: float, r1: float, height: float, col: Color, rm: Vector2, sides: int = 10) -> void:
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var p00 := xf * (d0 * r0)
		var p10 := xf * (d1 * r0)
		var p01 := xf * (d0 * r1 + Vector3(0.0, height, 0.0))
		var p11 := xf * (d1 * r1 + Vector3(0.0, height, 0.0))
		var n0 := (xf.basis * d0).normalized()
		var n1 := (xf.basis * d1).normalized()
		_smooth_quad(st, p00, p10, p11, p01, n0, n1, n1, n0, col, rm)
		var top := xf * Vector3(0.0, height, 0.0)
		var bottom := xf * Vector3.ZERO
		_tri(st, top, p01, p11, xf.basis * Vector3.UP, col, rm)
		_tri(st, bottom, p00, p10, xf.basis * Vector3.DOWN, col, rm)


## A quad with its own normal at each corner, turned so the normals face out.
static func _smooth_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, col: Color, rm: Vector2) -> void:
	var want := na + nb + nc + nd
	var verts := [[a, na], [b, nb], [c, nc], [a, na], [c, nc], [d, nd]]
	if (c - a).cross(b - a).dot(want) < 0.0:
		verts = [[a, na], [c, nc], [b, nb], [a, na], [d, nd], [c, nc]]
	for v: Array in verts:
		var p: Vector3 = v[0]
		var n: Vector3 = v[1]
		_vtx(st, p, n, _proj(p, n), col, rm)


## A round tube swept along a polyline (bent handles, bars).
static func _tube(st: SurfaceTool, path: Array, r: float, sides: int, col: Color, rm: Vector2) -> void:
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var along := b - a
		if along.length_squared() < 1e-10:
			continue
		along = along.normalized()
		var ref := Vector3.UP if absf(along.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var u := along.cross(ref).normalized()
		var v := along.cross(u).normalized()
		for k in sides:
			var t0 := TAU * float(k) / sides
			var t1 := TAU * float(k + 1) / sides
			var d0 := u * cos(t0) + v * sin(t0)
			var d1 := u * cos(t1) + v * sin(t1)
			_smooth_quad(st, a + d0 * r, a + d1 * r, b + d1 * r, b + d0 * r, d0, d1, d1, d0, col, rm)


## A dead leaf: an elongated hexagon cupped up at its edges, lying on the ground.
static func _leaf(st: SurfaceTool, c: Vector3, length: float, width_ratio: float, yaw: float, curl: float, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var w := length * width_ratio * 0.5
	var outline := [
		Vector3(0.0, 0.002, -length * 0.5), Vector3(w * 0.8, curl, -length * 0.2), Vector3(w, curl * 0.9, length * 0.12),
		Vector3(0.0, 0.003, length * 0.5), Vector3(-w, curl * 0.8, length * 0.12), Vector3(-w * 0.85, curl, -length * 0.2),
	]
	var mid := c + b * Vector3(0.0, 0.0015, 0.0)
	var rm := Vector2(0.78, 0.0)
	for i in outline.size():
		var p0: Vector3 = c + b * (outline[i] as Vector3)
		var p1: Vector3 = c + b * (outline[(i + 1) % outline.size()] as Vector3)
		_tri(st, mid, p0, p1, Vector3.UP, col, rm)


## A crushed paper cup on its side: a tapered tube squashed flat, white with a printed band,
## open at the mouth (both sides drawn, so you see into it).
static func _cup(st: SurfaceTool, c: Vector3, yaw: float, band: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var white := Color(0.88, 0.87, 0.84)
	var rings := [[0.0, 0.026, white], [0.03, 0.03, band], [0.065, 0.034, band], [0.095, 0.038, white]]
	var sides := 10
	var rm := Vector2(0.6, 0.0)
	var pts: Array = []
	for ring: Array in rings:
		var row: Array = []
		for k in sides:
			var t := TAU * float(k) / sides
			var r: float = ring[1]
			var y := sin(t) * r * 0.55 + r * 0.55
			row.append(c + b * Vector3(cos(t) * r, y, float(ring[0]) - 0.047))
		pts.append(row)
	for i in rings.size() - 1:
		var col: Color = rings[i][2] if i != 1 else band
		for k in sides:
			var p00: Vector3 = pts[i][k]
			var p01: Vector3 = pts[i][(k + 1) % sides]
			var p10: Vector3 = pts[i + 1][k]
			var p11: Vector3 = pts[i + 1][(k + 1) % sides]
			var axis_c := c + b * Vector3(0.0, 0.017, float(rings[i][0]) - 0.047)
			var out := ((p00 + p11) * 0.5 - axis_c)
			_quad(st, p00, p01, p11, p10, out, col, rm)
			_quad(st, p00, p01, p11, p10, -out, Color(0.8, 0.78, 0.74), rm)
	# The base.
	var base_c := c + b * Vector3(0.0, 0.026 * 0.55, -0.047)
	for k in sides:
		_tri(st, base_c, pts[0][k], pts[0][(k + 1) % sides], b * Vector3(0, 0, -1), white, rm)


## A crushed drink can on its side, pinched in the middle.
static func _can(st: SurfaceTool, c: Vector3, yaw: float, paint: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var sides := 8
	var alu := Color(0.72, 0.72, 0.74)
	var rings := [[-0.06, 0.03, 1.0], [-0.054, 0.033, 1.0], [0.0, 0.03, 0.45], [0.054, 0.033, 1.0], [0.06, 0.03, 1.0]]
	var pts: Array = []
	for ring: Array in rings:
		var row: Array = []
		var r: float = ring[1]
		var squash: float = ring[2]
		for k in sides:
			var t := TAU * float(k) / sides + 0.3
			row.append(c + b * Vector3(float(ring[0]), 0.033 * squash + sin(t) * r * squash, cos(t) * r * (2.0 - squash)))
		pts.append(row)
	for i in rings.size() - 1:
		var col := alu if i == 0 or i == rings.size() - 2 else paint
		var rm := Vector2(0.3, 0.9) if col == alu else Vector2(0.35, 0.6)
		for k in sides:
			var p00: Vector3 = pts[i][k]
			var p01: Vector3 = pts[i][(k + 1) % sides]
			var p10: Vector3 = pts[i + 1][k]
			var p11: Vector3 = pts[i + 1][(k + 1) % sides]
			var mid := c + b * Vector3((float(rings[i][0]) + float(rings[i + 1][0])) * 0.5, 0.025, 0.0)
			_quad(st, p00, p01, p11, p10, (p00 + p11) * 0.5 - mid, col, rm)
	for e in [0, rings.size() - 1]:
		var cc := c + b * Vector3(float(rings[e][0]), 0.033, 0.0)
		for k in sides:
			_tri(st, cc, pts[e][k], pts[e][(k + 1) % sides], b * Vector3(signf(float(rings[e][0])), 0, 0), alu, Vector2(0.3, 0.9))


## A balled-up sheet of paper: a lumpy faceted sphere.
static func _paper_ball(st: SurfaceTool, c: Vector3, r: float, rng: RandomNumberGenerator, col: Color) -> void:
	var rings := 5
	var sectors := 7
	var grid: Array = []
	for i in rings + 1:
		var row: Array = []
		var v := PI * float(i) / rings
		for j in sectors:
			var u := TAU * float(j) / sectors
			var d := Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
			var rr := r * (rng.randf_range(0.72, 1.18) if i > 0 and i < rings else 1.0)
			row.append(c + Vector3(0.0, r * 0.85, 0.0) + d * rr)
		grid.append(row)
	var center := c + Vector3(0.0, r * 0.85, 0.0)
	for i in rings:
		for j in sectors:
			var p00: Vector3 = grid[i][j]
			var p01: Vector3 = grid[i][(j + 1) % sectors]
			var p10: Vector3 = grid[i + 1][j]
			var p11: Vector3 = grid[i + 1][(j + 1) % sectors]
			var out := (p00 + p11) * 0.5 - center
			_tri(st, p00, p01, p11, out, col, Vector2(0.9, 0.0))
			_tri(st, p00, p11, p10, out, col, Vector2(0.9, 0.0))


## A flattened wrapper or flyer, crumpled a little: a 3 x 3 grid with jittered heights.
static func _wrapper(st: SurfaceTool, c: Vector3, yaw: float, col: Color, rng: RandomNumberGenerator) -> void:
	var b := Basis(Vector3.UP, yaw)
	var grid: Array = []
	for i in 4:
		var row: Array = []
		for j in 4:
			var h := 0.002 + (rng.randf() * 0.012 if i > 0 and i < 3 and j > 0 and j < 3 else rng.randf() * 0.004)
			row.append(c + b * Vector3(-0.07 + 0.14 * j / 3.0 + rng.randf_range(-0.006, 0.006), h, -0.05 + 0.1 * i / 3.0 + rng.randf_range(-0.006, 0.006)))
		grid.append(row)
	for i in 3:
		for j in 3:
			_quad(st, grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j], Vector3.UP, col, Vector2(0.7, 0.0))
