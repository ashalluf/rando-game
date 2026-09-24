class_name Skyline
extends Node3D
## The far city: the super-LOD tier (owner, 2026-09-24: "it's glaringly obvious that certain
## areas of the map aren't loading properly at a distance ... do whatever GTA does").
##
## The world is drawn by four tiers, the way GTA V and RDR2 draw theirs: FULL chunks near the
## player, LOD chunks (merged, cheap) out to seven blocks, THIS tier for every city block of the
## map, and the horizon plane (macro_ground.gdshader) with the mountains under all of it. The
## rule that makes it seamless is that a coarser tier always stands in until the finer one is
## built: every block of the map is drawn here from the moment its tile is built, and each block
## is hidden - dissolved over `fade_time`, never cut - only once a chunk has been installed on
## it, and shown again (dissolved back in) before that chunk is freed. So there is no distance at
## which the city hands over from one tier to the next and no ring where neither draws; the
## handoff is per block, and it happens wherever the streamer has actually got to.
##
## Before this there was a coarse tier drawn only beyond a fixed distance, as one visibility
## range per 36-block tile measured to the tile's centre, only seven tiles out, behind a camera
## that clipped everything past 2 km. Measured over the basin's city blocks: two thirds of the
## map past the far plane, a hundred-odd blocks drawn twice (a LOD chunk and this tier on top of
## each other), holes where a tile's centre was too close for it to draw but its far half was
## past the LOD ring, and from the air (above ~800 m) the coarse boxes drawn over the detailed
## city. See docs/HANDOFF.md, section on the distance.
##
## WHAT IS DRAWN is the LOD chunk's own city, not an imitation of it. A city block's massing comes
## from running CityChunk's LOD block build in capture mode (CityChunk.capturing): the same steps
## with the same random rolls, so the same lots, pads, malls, big boxes, yards and freeway
## corridor, and exactly the boxes the LOD chunk will draw, with the same colours and facade
## data. Anything added to the block build later - a downtown data table, a new district - shows
## here too, because this IS the block build. Around it: one plate per block over the area the
## chunk owns, in the average colour its LOD ground is drawn in, with its two roads painted on by
## the shader (building_lod.gdshader, plate mode); the freeway decks and pillars the chunk would
## build, from Freeway's own segments; container stacks and aprons from the port and airport
## builds; and on the hills the planting and the estates HillRoads places (far_canopy.gdshader
## seats them on the drawn far ground, or on the real terrain where a LOD chunk has it).
##
## Tiles of TILE_BLOCKS x TILE_BLOCKS blocks, one MultiMesh (one draw) each plus one for the hill
## planting. Built nearest-and-most-in-view first, a block at a time inside a per-frame budget,
## out to `radius` metres - the whole basin - and not dropped again unless the player goes far
## enough for them to leave that radius.

## Blocks per tile edge. Bigger means fewer draw calls and coarser culling granularity.
const TILE_BLOCKS := 6
## Vegetation clumps on a hill block at full cover, falling to zero at the rock line.
const HILL_CLUMPS := 10
## Street trees: metres between them along a kerb (the chunks plant every
## CityStreamer.tree_spacing x CityChunk.street_tree_spacing, about 10 m) - the far city plants
## the same rows at the district's own odds, and a park at one canopy per PARK_TREE_AREA m2.
const STREET_TREE_STEP := 10.0
const PARK_TREE_AREA := 260.0
## The block plate's top above the relief: under the LOD chunks' road (CityChunk.ROAD_TOP 0.1)
## so a block dissolving between the two tiers never has its plate over the streamed road.
const PLATE_TOP := 0.04
## How deep the plate reaches under that, so a block on a slope does not show daylight under its
## downhill edge (its top is a plane fitted to the relief, which rolls a metre or two across one).
const PLATE_DEPTH := 3.0
## Flags in INSTANCE_CUSTOM.a that building_lod.gdshader reads (0 is a facade, 1 plain): a
## block plate, which it paints the roads on, and a freeway deck, an asphalt carriageway.
const PLATE_FLAG := 2.0
const DECK_FLAG := 3.0

## Seconds a block takes to dissolve out when a chunk covers it, and back in when it leaves.
var fade_time: float = 0.45
## Metres around the player the tier reaches. The ground follower is 14 km across, so its edge
## is 7 km out; nothing past it can be seen.
var radius: float = 7000.0
## The rest of the old interface: both 0 now, because nothing here is drawn by distance. Kept so
## the tier handoff checks can read them (tests/smoke_test.gd).
var draw_from: float = 0.0
var fade_margin: float = 0.0

var _plan: CityPlan
## CityStreamer's chunk style (colours and spacings), which the capture build needs.
var _style: Dictionary = {}
## shaders/far_canopy.gdshader, sharing the ground follower's height uniforms (CityStreamer sets
## both). The hill planting draws with it, in its own MultiMesh per tile, because it has to stand
## on the ground the far plane actually draws rather than on MacroMap.height_at() - see the shader.
var _canopy: ShaderMaterial
## Tile -> {"node", "veg", "house", "colors", "veg_colors", "veg_custom", "house_colors"}, or null
## for a tile with nothing in it (most of the map: ocean, open hillside), remembered so it is
## never scanned again.
var _tiles: Dictionary = {}
## Block -> {"tile", "b0", "bn", "v0", "vn", "h0", "hn", "hill"}: where its instances sit in its
## tile's box MultiMesh (b), planting (v: hill scrub, street and park trees) and estates (h).
var _blocks: Dictionary = {}
## Block -> CityChunk.Level of the chunk standing on it. Kept for blocks whose tile is not built
## yet too, so a tile built later starts with the right blocks hidden.
var _cover: Dictionary = {}
## Block -> current visibility, 0..1, for blocks whose tile is built.
var _alpha: Dictionary = {}
## Blocks whose visibility is still moving.
var _fading: Dictionary = {}
## The tile under construction: {"t", "blocks" (Array[Vector2i]), "next", accumulators}.
var _work: Dictionary = {}
## Where the last scan for a missing tile was centred, and whether it found none: nothing is
## rescanned until the player reaches another tile.
var _scan_tile: Vector2i = Vector2i(1 << 30, 0)
var _scan_empty: bool = false
## The player's tile at the last trim (trimming only has anything to do once they cross one).
var _trim_tile: Vector2i = Vector2i(1 << 30, 0)
## World XZ -> priority (lower is sooner). CityStreamer supplies it so that tiles and chunks are
## ordered by the same view- and travel-weighted distance.
var _priority: Callable
var blocks_built: int = 0


func setup(plan: CityPlan, style: Dictionary, canopy: ShaderMaterial = null, priority: Callable = Callable()) -> void:
	_plan = plan
	_style = style
	_canopy = canopy
	_priority = priority
	# Tile instances are placed at TRUE world coordinates, exactly like a CityChunk's children,
	# so this node carries the origin shift for all of them. CityStreamer.recenter() moves every
	# direct Node3D child of the scene root, which keeps this at -world_offset from here on.
	position = -WorldState.world_offset


func has_tile(t: Vector2i) -> bool:
	return _tiles.has(t)


## Tiles with something in them.
func tile_count() -> int:
	var n := 0
	for t in _tiles:
		if _tiles[t] != null:
			n += 1
	return n


static func tile_of(block: Vector2i) -> Vector2i:
	return Vector2i(floori(float(block.x) / TILE_BLOCKS), floori(float(block.y) / TILE_BLOCKS))


# --- The handoff -------------------------------------------------------------------------------

## A chunk now stands on `block` (CityStreamer._install_chunk): dissolve this tier out there.
## `level` is the chunk's CityChunk.Level: the hill planting stays under a LOD chunk (which has
## none of its own) and moves onto its terrain; under a FULL chunk it goes, like everything else.
func cover(block: Vector2i, level: int) -> void:
	_cover[block] = level
	if _blocks.has(block):
		_set_seat(block, true)
		_fading[block] = true


## The chunk on `block` is going (CityStreamer): dissolve this tier back in. The streamer keeps
## the chunk up for `fade_time` while this happens, so the block is never empty.
func uncover(block: Vector2i) -> void:
	_cover.erase(block)
	if _blocks.has(block):
		_fading[block] = true


func is_covered(block: Vector2i) -> bool:
	return _cover.has(block)


## How visible this tier is on `block` right now (0 hidden .. 1 drawn), or -1 when its tile is
## not built. For the tier checks.
func block_alpha(block: Vector2i) -> float:
	if not _blocks.has(block):
		return -1.0
	return _alpha.get(block, 1.0)


## Instances this tier draws for a block (boxes, plate, planting); 0 = the block is empty here.
func block_instances(block: Vector2i) -> int:
	var b: Dictionary = _blocks.get(block, {})
	if b.is_empty():
		return 0
	return int(b.bn) + int(b.vn) + int(b.hn)


## Visibility the block is heading for: 0 where a chunk stands, 1 elsewhere.
func _target(block: Vector2i) -> float:
	return 0.0 if _cover.has(block) else 1.0


func _process(delta: float) -> void:
	if _fading.is_empty():
		return
	var step := delta / maxf(fade_time, 0.001)
	for block in _fading.keys():
		var target := _target(block)
		var a: float = move_toward(_alpha.get(block, 1.0), target, step)
		_alpha[block] = a
		_apply_alpha(block, a)
		if is_equal_approx(a, target):
			_fading.erase(block)
			if a >= 1.0:
				# Fully back: the planting goes back onto the far ground the plane draws.
				_set_seat(block, false)


## Writes a block's visibility into its instances' colour alpha, which building_lod.gdshader and
## far_canopy.gdshader dissolve by (and collapse at zero, so a hidden box costs no fragments).
func _apply_alpha(block: Vector2i, a: float) -> void:
	var b: Dictionary = _blocks.get(block, {})
	var tile = _tiles.get(b.get("tile", Vector2i.ZERO))
	if b.is_empty() or tile == null:
		return
	if int(b.bn) > 0 and tile.node:
		var mm: MultiMesh = (tile.node as MultiMeshInstance3D).multimesh
		var cols: Array = tile.colors
		for i in range(int(b.b0), int(b.b0) + int(b.bn)):
			var c: Color = cols[i]
			mm.set_instance_color(i, Color(c.r, c.g, c.b, a))
	# Planting stays under a LOD chunk (it plants nothing of its own: no scrub on the hills, no
	# street or park trees in the city) and goes under a FULL one, which has the real trees;
	# estates go under either, because both build their own.
	if tile.veg and int(b.vn) > 0:
		var vm: MultiMesh = (tile.veg as MultiMeshInstance3D).multimesh
		var vcols: Array = tile.veg_colors
		var planting := a if int(_cover.get(block, 1)) == CityChunk.Level.FULL else 1.0
		for i in range(int(b.v0), int(b.v0) + int(b.vn)):
			var c: Color = vcols[i]
			vm.set_instance_color(i, Color(c.r, c.g, c.b, planting))
	if tile.house and int(b.hn) > 0:
		var hm: MultiMesh = (tile.house as MultiMeshInstance3D).multimesh
		var hcols: Array = tile.house_colors
		for i in range(int(b.h0), int(b.h0) + int(b.hn)):
			var c: Color = hcols[i]
			hm.set_instance_color(i, Color(c.r, c.g, c.b, a))


## Where a block's planting stands: on the real terrain (a LOD chunk has drawn it there) or on
## the far ground the horizon plane draws (far_canopy.gdshader, INSTANCE_CUSTOM.r).
func _set_seat(block: Vector2i, real: bool) -> void:
	var b: Dictionary = _blocks.get(block, {})
	var tile = _tiles.get(b.get("tile", Vector2i.ZERO))
	# Only hill planting ever stands on the far plane: a city block's trees are over its plate,
	# on the real relief, always (the plane is sunk under the city).
	if b.is_empty() or tile == null or tile.veg == null or int(b.vn) == 0 or not b.get("hill", false):
		return
	var vm: MultiMesh = (tile.veg as MultiMeshInstance3D).multimesh
	var custom := Color(1.0 if real else 0.0, 0.0, 0.0, 0.0)
	var store: Array = tile.veg_custom
	for i in range(int(b.v0), int(b.v0) + int(b.vn)):
		store[i] = custom
		vm.set_instance_custom_data(i, custom)


# --- Building ----------------------------------------------------------------------------------

## Builds every missing tile within `metres` of `eye` (true world XZ) right now. The loading
## screen, teleports and the headless check use it; play uses advance().
func build_near(eye: Vector2, metres: float) -> void:
	if _plan == null:
		return
	var centre := tile_of(_plan.block_index_at(eye))
	var reach := int(ceil(metres / (TILE_BLOCKS * _plan.block_size_range.x))) + 1
	var todo: Array[Vector2i] = []
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var t := Vector2i(centre.x + dx, centre.y + dz)
			if not _tiles.has(t) and _tile_centre(t).distance_to(eye) <= metres + TILE_BLOCKS * _plan.block_size_range.y:
				todo.append(t)
	todo.sort_custom(func(a, b): return _tile_priority(a, eye) < _tile_priority(b, eye))
	for t in todo:
		if _work.get("t", Vector2i(1 << 30, 0)) == t:
			while not _work_step():
				pass
			continue
		_begin_tile(t)
		while not _work_step():
			pass


## Spends up to `budget_usec` building the far city, a block at a time, starting the tile that
## matters most (nearest, most in view, most ahead of travel) whenever one is finished.
func advance(eye: Vector2, budget_usec: int) -> void:
	if _plan == null:
		return
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < budget_usec:
		if _work.is_empty():
			var t := _next_tile(eye)
			if t.x == 1 << 30:
				return
			_begin_tile(t)
		_work_step()


## Frees tiles that have left `radius` (plus a tile of slack) - only a player who flies far out
## of the basin ever gets here.
func trim(eye: Vector2) -> void:
	var here := tile_of(_plan.block_index_at(eye))
	if here == _trim_tile:
		return
	_trim_tile = here
	for t in _tiles.keys():
		if _tile_centre(t).distance_to(eye) > radius + 2.0 * TILE_BLOCKS * _plan.block_size_range.y:
			var tile = _tiles[t]
			if tile != null:
				if tile.node:
					(tile.node as Node).queue_free()
				if tile.veg:
					(tile.veg as Node).queue_free()
				if tile.house:
					(tile.house as Node).queue_free()
			_tiles.erase(t)
			for bx in TILE_BLOCKS:
				for bz in TILE_BLOCKS:
					var k := Vector2i(t.x * TILE_BLOCKS + bx, t.y * TILE_BLOCKS + bz)
					_blocks.erase(k)
					_alpha.erase(k)
					_fading.erase(k)
			_scan_empty = false


## True when every tile within `radius` of `eye` is built.
func complete(eye: Vector2) -> bool:
	return _work.is_empty() and _next_tile(eye).x == 1 << 30


func _next_tile(eye: Vector2) -> Vector2i:
	var none := Vector2i(1 << 30, 0)
	var centre := tile_of(_plan.block_index_at(eye))
	if centre == _scan_tile and _scan_empty:
		return none
	var reach := int(ceil(radius / (TILE_BLOCKS * _plan.block_size_range.x))) + 1
	var best := none
	var best_p := INF
	# Ring by ring outward, and only as far as twice the first ring anything is missing on: the
	# view weighting can at most double a tile's distance, so nothing further out could win.
	# Scanning every tile in reach instead was ~14 ms a pick at the start of a session.
	var stop := reach
	for ring in range(0, reach + 1):
		if ring > stop:
			break
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var t := Vector2i(centre.x + dx, centre.y + dz)
				if _tiles.has(t) or _tile_centre(t).distance_to(eye) > radius:
					continue
				var p := _tile_priority(t, eye)
				if p < best_p:
					best_p = p
					best = t
				stop = mini(stop, ring * 2 + 1)
	_scan_tile = centre
	_scan_empty = best == none
	return best


func _tile_centre(t: Vector2i) -> Vector2:
	var a: Rect2 = _plan.owned_rect(t.x * TILE_BLOCKS, t.y * TILE_BLOCKS)
	var b: Rect2 = _plan.owned_rect(t.x * TILE_BLOCKS + TILE_BLOCKS - 1, t.y * TILE_BLOCKS + TILE_BLOCKS - 1)
	return (a.position + b.end) * 0.5


## Distance to the nearest point of the tile, weighted by the streamer's view priority at it.
func _tile_priority(t: Vector2i, eye: Vector2) -> float:
	var a: Rect2 = _plan.owned_rect(t.x * TILE_BLOCKS, t.y * TILE_BLOCKS)
	var b: Rect2 = _plan.owned_rect(t.x * TILE_BLOCKS + TILE_BLOCKS - 1, t.y * TILE_BLOCKS + TILE_BLOCKS - 1)
	var rect := Rect2(a.position, b.end - a.position)
	var nearest := Vector2(clampf(eye.x, rect.position.x, rect.end.x), clampf(eye.y, rect.position.y, rect.end.y))
	if _priority.is_valid():
		return float(_priority.call(nearest))
	return nearest.distance_to(eye)


func _begin_tile(t: Vector2i) -> void:
	var blocks: Array[Vector2i] = []
	for bx in TILE_BLOCKS:
		for bz in TILE_BLOCKS:
			blocks.append(Vector2i(t.x * TILE_BLOCKS + bx, t.y * TILE_BLOCKS + bz))
	# Plain Arrays throughout: they are shared by reference, so the block builders can append to
	# what they read out of here.
	_work = {
		"t": t, "blocks": blocks, "next": 0, "ranges": {},
		"xforms": [], "colors": [], "customs": [],
		"veg": [], "veg_colors": [], "veg_custom": [],
		"houses": [], "house_colors": [], "hills": {},
	}


## One block of the tile under construction; true once the tile is finished and in the tree.
func _work_step() -> bool:
	if _work.is_empty():
		return true
	var blocks: Array = _work.blocks
	if _work.next < blocks.size():
		var k: Vector2i = blocks[_work.next]
		_work.next += 1
		var b0: int = (_work.xforms as Array).size()
		var v0: int = (_work.veg as Array).size()
		var h0: int = (_work.houses as Array).size()
		_add_block(k)
		_work.ranges[k] = [b0, (_work.xforms as Array).size() - b0, v0, (_work.veg as Array).size() - v0,
			h0, (_work.houses as Array).size() - h0]
		blocks_built += 1
		return false
	_commit_tile()
	_work = {}
	return true


func _commit_tile() -> void:
	var t: Vector2i = _work.t
	var xforms: Array = _work.xforms
	var veg: Array = _work.veg
	var houses: Array = _work.houses
	if xforms.is_empty() and veg.is_empty() and houses.is_empty():
		# Remembered as empty, so an ocean tile is never rescanned. A plain marker rather than a
		# node: most of the map is water and open hillside.
		_tiles[t] = null
		return
	var colors: Array = _work.colors
	var customs: Array = _work.customs
	var veg_colors: Array = _work.veg_colors
	var veg_custom: Array = _work.veg_custom
	var house_colors: Array = _work.house_colors
	var tile := {"node": null, "veg": null, "house": null, "colors": colors, "veg_colors": veg_colors,
		"veg_custom": veg_custom, "house_colors": house_colors}
	if not xforms.is_empty():
		tile.node = _box_node(t, xforms, colors, customs)
		add_child(tile.node)
	if _canopy != null:
		# Canopies on a rounded blob, estates on boxes: two MultiMeshes on the one canopy shader,
		# which seats both on the ground actually drawn under them.
		if not veg.is_empty():
			tile.veg = _planting_node("Planting_%d_%d" % [t.x, t.y], PropFactory.canopy_blob(), veg, veg_colors, veg_custom)
			add_child(tile.veg)
		if not houses.is_empty():
			var house_custom: Array = []
			house_custom.resize(houses.size())
			house_custom.fill(Color(0.0, 0.0, 0.0, 0.0))
			tile.house = _planting_node("Estates_%d_%d" % [t.x, t.y], PropFactory.unit_box(), houses, house_colors, house_custom)
			add_child(tile.house)
	_tiles[t] = tile
	var hills: Dictionary = _work.hills
	for k in _work.ranges:
		var r: Array = _work.ranges[k]
		if int(r[1]) + int(r[3]) + int(r[5]) == 0:
			continue
		_blocks[k] = {"tile": t, "b0": r[0], "bn": r[1], "v0": r[2], "vn": r[3], "h0": r[4], "hn": r[5], "hill": hills.has(k)}
		# A tile built under chunks that are already standing starts with those blocks hidden,
		# at once: nothing is fading, they were never shown.
		if _cover.has(k):
			_alpha[k] = 0.0
			_apply_alpha(k, 0.0)
			_set_seat(k, true)
		else:
			_alpha[k] = 1.0


## The tile's boxes and plates: one MultiMesh on the LOD box shader.
func _box_node(t: Vector2i, xforms: Array, colors: Array, customs: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = PropFactory.unit_box()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, customs[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Sky_%d_%d" % [t.x, t.y]
	node.multimesh = mm
	# The same shader the LOD boxes use, so a far tower is drawn exactly as it will be when its
	# LOD chunk arrives - same facade, same glazing, same lit windows at night.
	node.material_override = PropFactory.building_lod_material()
	# Never casts: everything within shadow reach is covered by chunks, which cast their own.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return node


## The tile's hill planting and hill estates, on the canopy shader, which seats every one of them
## on the far ground (or, flagged, on the real terrain). One more draw per hill tile.
func _planting_node(node_name: String, mesh: Mesh, veg: Array, veg_colors: Array, veg_custom: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = veg.size()
	for i in veg.size():
		mm.set_instance_transform(i, veg[i])
		mm.set_instance_color(i, veg_colors[i])
		mm.set_instance_custom_data(i, veg_custom[i])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = _canopy
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The shader moves every clump by up to tens of metres, so the MultiMesh's own bounds (built
	# from the CPU positions) can be off by that much; pad them rather than have a clump culled
	# while it is still on screen.
	node.extra_cull_margin = 120.0
	return node


# --- One block ---------------------------------------------------------------------------------

func _add_block(k: Vector2i) -> void:
	var b := _plan.block(k.x, k.y)
	var rect: Rect2 = b.rect
	var macro: MacroMap = _plan.macro
	var zone: int = macro.zone_at(rect.get_center()) if macro else MacroMap.Zone.CITY
	match zone:
		MacroMap.Zone.CITY, MacroMap.Zone.PORT, MacroMap.Zone.AIRPORT:
			_add_captured(k, b, zone)
		MacroMap.Zone.HILLS:
			_work.hills[k] = true
			_add_hills(rect, macro)
	_add_freeway(k)


## A block as its LOD chunk builds it: the chunk's own block build run in capture mode.
func _add_captured(k: Vector2i, b: Dictionary, zone: int) -> void:
	var ch := CityChunk.new()
	ch.plan = _plan
	ch.ix = k.x
	ch.iz = k.y
	ch.level = CityChunk.Level.LOD
	ch.style = _style
	ch.capturing = true
	ch.begin_build()
	while not ch.build_step():
		pass
	var cap: Dictionary = ch.captured
	var batch: Dictionary = cap.get("batch", {})
	var xforms: Array = _work.xforms
	var colors: Array = _work.colors
	var customs: Array = _work.customs
	# The ground first, so a block's plate is the first of its instances.
	_add_plate(k, zone, cap.get("ground", []), ch)
	# The LOD boxes: every building part and plinth, exactly as the chunk batches them.
	if batch.has("lod_box"):
		var lb: Dictionary = batch["lod_box"]
		for i in (lb.xforms as Array).size():
			xforms.append(lb.xforms[i])
			colors.append(lb.colors[i])
			customs.append(lb.custom[i])
	# Solid slabs the block build made directly - shopping plazas, big-box stores, pads - in
	# their slab colour, plain.
	for box: Array in cap.get("boxes", []):
		xforms.append(box[0])
		var c: Color = box[1]
		colors.append(Color(c.r, c.g, c.b, 1.0))
		customs.append(Color(0.0, 0.0, float(absi(hash([k, xforms.size()])) % 997) / 997.0, 1.0))
	if zone == MacroMap.Zone.CITY:
		_add_city_trees(k, b, ch)
	# Container stacks in the port yard.
	if batch.has("container"):
		var cb: Dictionary = batch["container"]
		var size: Vector3 = (PropFactory.container().get_aabb() as AABB).size
		for i in (cb.xforms as Array).size():
			var xf: Transform3D = cb.xforms[i]
			xforms.append(Transform3D(xf.basis.scaled_local(size), xf.origin))
			var c: Color = cb.colors[i]
			colors.append(Color(c.r, c.g, c.b, 1.0))
			customs.append(Color(0.0, 0.0, 0.0, 1.0))
	ch.free()


## One plate over the area the chunk owns, top on a plane fitted to the relief, in the average
## colour its LOD ground is drawn in (the far colour the capture recorded for each slab), with the
## chunk's two roads - on its +X and +Z sides - left for the shader to paint (their widths ride in
## INSTANCE_CUSTOM.r / .g).
##
## Outside the city, ground that crosses the whole block one way (the airport's runways) cuts the
## plate into strips instead of being averaged into it: a runway is what an airport looks like
## from the air, and laid as a second plate on top it would fight the first for depth - on the
## web's depth buffer two surfaces 10 cm apart are one surface a kilometre away.
func _add_plate(k: Vector2i, zone: int, ground: Array, ch: CityChunk) -> void:
	var area: Rect2 = _plan.owned_rect(k.x, k.y)
	var roads := zone == MacroMap.Zone.CITY
	var wx: float = _plan.road_width(CityPlan.AXIS_X, k.x + 1) if roads else 0.0
	var wz: float = _plan.road_width(CityPlan.AXIS_Z, k.y + 1) if roads else 0.0
	var bands: Array = []
	if not roads:
		for i in range(1, ground.size()):
			var r: Rect2 = (ground[i][0] as Rect2).intersection(area)
			if r.size.y > 0.0 and r.size.x >= area.size.x - 1.0:
				bands.append([r.position.y, r.end.y, ground[i][3]])
		bands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var col := _ground_colour(Rect2(area.position, area.size - Vector2(wx, wz)), zone, ground, bands)
	if bands.is_empty():
		_plate(k, area, col, wx, wz, ch)
		return
	var z := area.position.y
	for band: Array in bands:
		var z0 := maxf(float(band[0]), z)
		if z0 > z + 0.5:
			_plate(k, Rect2(area.position.x, z, area.size.x, z0 - z), col, 0.0, 0.0, ch)
		if float(band[1]) > z0 + 0.01:
			_plate(k, Rect2(area.position.x, z0, area.size.x, float(band[1]) - z0), band[2], 0.0, 0.0, ch)
		z = maxf(z, float(band[1]))
	if area.end.y > z + 0.5:
		_plate(k, Rect2(area.position.x, z, area.size.x, area.end.y - z), col, 0.0, 0.0, ch)


## What the ground inside `inner` looks like from above: sampled on a grid, later slabs over
## earlier ones (the build lays them bottom up), the far colour of whatever is on top averaged.
## Samples inside `bands` ([z0, z1, colour]) are left out - those get their own plates.
func _ground_colour(inner: Rect2, zone: int, ground: Array, bands: Array) -> Color:
	var asphalt: Color = _style.get("asphalt", Color(0.2, 0.2, 0.22))
	var sum := Color(0.0, 0.0, 0.0, 0.0)
	var n := 0
	const GRID := 8
	for gx in GRID:
		for gz in GRID:
			var p := inner.position + inner.size * Vector2((gx + 0.5) / GRID, (gz + 0.5) / GRID)
			var in_band := false
			for band: Array in bands:
				if p.y >= float(band[0]) and p.y < float(band[1]):
					in_band = true
			if in_band:
				continue
			var top: Color = Color(-1.0, 0.0, 0.0)
			for g: Array in ground:
				if (g[0] as Rect2).has_point(p):
					top = g[3]
			if top.r < 0.0:
				continue
			sum += Color(top.r, top.g, top.b, 0.0)
			n += 1
	if n > 0:
		return Color(sum.r / n, sum.g / n, sum.b / n)
	if zone == MacroMap.Zone.CITY:
		# A block the build laid no ground on (landmark footprints): pavement.
		return CityChunk.far_tint(_style.get("sidewalk", Color(0.68, 0.66, 0.62)), asphalt)
	return Color(0.12, 0.12, 0.12)


## One plate instance over `rect`: its top on a plane fitted to the relief under its corners.
func _plate(k: Vector2i, rect: Rect2, col: Color, wx: float, wz: float, ch: CityChunk) -> void:
	var h00 := ch._gy(rect.position.x, rect.position.y)
	var h10 := ch._gy(rect.end.x, rect.position.y)
	var h01 := ch._gy(rect.position.x, rect.end.y)
	var h11 := ch._gy(rect.end.x, rect.end.y)
	var slope_x := ((h10 - h00) + (h11 - h01)) * 0.5
	var slope_z := ((h01 - h00) + (h11 - h10)) * 0.5
	var centre_h := (h00 + h10 + h01 + h11) * 0.25
	var c := rect.get_center()
	var basis := Basis(Vector3(rect.size.x, slope_x, 0.0), Vector3(0.0, PLATE_DEPTH, 0.0), Vector3(0.0, slope_z, rect.size.y))
	var top_y := centre_h + PLATE_TOP
	(_work.xforms as Array).append(Transform3D(basis, Vector3(c.x, top_y - PLATE_DEPTH * 0.5, c.y)))
	(_work.colors as Array).append(Color(col.r, col.g, col.b, 1.0))
	(_work.customs as Array).append(Color(wx, wz, float(absi(hash([k, "plate", rect.position])) % 997) / 997.0, PLATE_FLAG))


## The freeway deck and pillars the chunk that owns each segment's midpoint would build.
func _add_freeway(k: Vector2i) -> void:
	var macro: MacroMap = _plan.macro
	if macro == null or macro.freeway == null:
		return
	var area: Rect2 = _plan.owned_rect(k.x, k.y)
	var xforms: Array = _work.xforms
	var colors: Array = _work.colors
	var customs: Array = _work.customs
	var t := Freeway.DECK_THICKNESS
	var concrete := Color(0.62, 0.61, 0.59)
	var pillar_every := int(round(Freeway.PILLAR_SPACING / Freeway.STEP))
	for seg in macro.freeway.segments_in(area):
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var seg_len := a.distance_to(b)
		if seg_len < 0.5:
			continue
		var mid := a.lerp(b, 0.5)
		if not area.has_point(mid):
			continue
		var ha: float = seg.ha
		var hb: float = seg.hb
		var dir := (b - a) / seg_len
		var nrm := Vector2(-dir.y, dir.x)
		var fwd := Vector3(b.x - a.x, hb - ha, b.y - a.y).normalized()
		var right := Vector3(nrm.x, 0.0, nrm.y)
		var up := right.cross(fwd).normalized()
		# The deck, as the chunk's collision box has it: tilted to the grade, a little long so the
		# segments overlap at the joints. The barriers ride on top as a lip.
		var basis := Basis(right * float(seg.width), up * (t + 1.05), -fwd * (seg_len + 0.4))
		xforms.append(Transform3D(basis, Vector3(mid.x, (ha + hb) * 0.5 - t + (t + 1.05) * 0.5, mid.y)))
		colors.append(concrete)
		# Deck flag: building_lod.gdshader draws an asphalt carriageway on top, not a roof.
		customs.append(Color(float(seg.width), 0.0, 0.0, DECK_FLAG))
		if int(seg.index) % pillar_every == 0:
			var ground := _plan.height_at(a)
			var cap := ha - t - 0.1
			if cap - ground > 1.5:
				var h := cap - ground + 1.0
				var pb := Basis(right * float(seg.width) * 0.62, Vector3(0.0, h, 0.0), Vector3(dir.x, 0.0, dir.y) * 1.6)
				xforms.append(Transform3D(pb, Vector3(a.x, ground - 1.0 + h * 0.5, a.y)))
				colors.append(concrete * 0.94)
				customs.append(Color(0.0, 0.0, 0.0, 1.0))


## The trees a FULL chunk plants on a city block, as canopies: rows along the kerbs at the
## district's own odds (CityPlan.DISTRICTS "trees"), a park full of them, palms on a palm street
## and lavender crowns on a jacaranda one - those two rolls come out of the capture, so they are
## the block's own. The FULL chunk places each tree with its own rolls, which a capture of the LOD
## build does not make, so these are the right rows at the right density rather than the very
## same trees; they dissolve out as the FULL chunk arrives, 200 m away. The LOD chunks plant
## nothing, which is what made the city between two and seven blocks out bald.
func _add_city_trees(k: Vector2i, b: Dictionary, ch: CityChunk) -> void:
	var rect: Rect2 = b.rect
	var params: Dictionary = CityPlan.DISTRICTS[b.district]
	var veg: Array = _work.veg
	var veg_colors: Array = _work.veg_colors
	var veg_custom: Array = _work.veg_custom
	# Always on the real relief: far_canopy.gdshader leaves an instance flagged 1 where it is.
	var real := Color(1.0, 0.0, 0.0, 0.0)
	var palms := ch._palm_street
	var jacaranda := ch._jacaranda_street
	var spots: Array[Vector2] = []
	if b.kind == CityPlan.BlockKind.PARK:
		var inner := rect.grow(-4.0)
		var n := int(inner.get_area() / PARK_TREE_AREA)
		for i in n:
			spots.append(_spot(inner, hash([_plan.seed, "park", k, i])))
	# Kerb rows on every block, parks and plazas included (the FULL build lines them all).
	var odds: float = params.get("trees", 0.5)
	var ring := rect.grow(-1.6)
	var corners := [ring.position, Vector2(ring.end.x, ring.position.y), ring.end, Vector2(ring.position.x, ring.end.y)]
	for e in 4:
		var a: Vector2 = corners[e]
		var c: Vector2 = corners[(e + 1) % 4]
		var n := int(a.distance_to(c) / STREET_TREE_STEP)
		for i in n:
			if float(absi(hash([_plan.seed, "st", k, e, i])) % 1000) / 1000.0 >= odds:
				continue
			spots.append(a.lerp(c, (float(i) + 0.5) / float(maxi(n, 1))))
	for i in spots.size():
		var p: Vector2 = spots[i]
		var hs := hash([_plan.seed, "tree", k, i])
		var v: float = float(absi(hs) % 1000) / 1000.0
		var gy := ch._gy(p.x, p.y) + CityChunk.SIDEWALK_TOP
		var r: float
		var th: float
		var lift: float
		var col: Color
		if palms and b.kind != CityPlan.BlockKind.PARK:
			# A palm from a kilometre off is its crown and nothing else.
			r = 3.6 + v * 1.4
			th = 2.2
			lift = 9.0 + v * 5.0
			col = Color(0.13, 0.17, 0.08).lerp(Color(0.19, 0.22, 0.11), v)
		else:
			r = 5.0 + v * 3.5
			th = 4.6 + v * 2.6
			lift = 2.6
			col = Color(0.075, 0.115, 0.050).lerp(Color(0.135, 0.170, 0.075), v)
			if jacaranda and float(absi(hash([hs, "j"])) % 100) < 85.0:
				col = Color(0.30, 0.25, 0.48).lerp(Color(0.38, 0.33, 0.56), v)
		veg.append(Transform3D(Basis(Vector3.UP, float(absi(hs) % 628) * 0.01).scaled(Vector3(r, th, r * 0.9)),
			Vector3(p.x, gy + lift + th * 0.5, p.y)))
		veg_colors.append(col)
		veg_custom.append(real)


## A hill block: vegetation and the estates HillRoads places. The planting is the bulk of it.
## Density falls with elevation the way the planting actually does - scrub on the lower slopes,
## thinning through the tree line, bare rock on the tops - which is both what it should look like
## and cheaper than blanketing every peak. The estates are the ones the LOD chunk draws
## (CityChunk._build_mansions: an 18 x 7.5 x 13 m house 4 m back on its pad), seated with the
## planting because out here the ground they stand on is the far plane's, not the real one.
func _add_hills(rect: Rect2, macro: MacroMap) -> void:
	if macro == null:
		return
	var center := rect.get_center()
	var elev: float = macro.height_at(center)
	var cover_amount: float = clampf(1.0 - (elev - 60.0) / 520.0, 0.0, 1.0)
	var clumps: int = int(round(cover_amount * float(HILL_CLUMPS)))
	var veg: Array = _work.veg
	var veg_colors: Array = _work.veg_colors
	var veg_custom: Array = _work.veg_custom
	for i in clumps:
		var hs := hash([_plan.seed, "veg", int(center.x), int(center.y), i])
		var p := _spot(rect, hs)
		# Only a first guess at the height where the far plane is the ground: far_canopy.gdshader
		# moves the clump onto the ground the plane really draws there, which on a ridge is tens
		# of metres lower than height_at(). Under a LOD chunk this IS the ground (its terrain is
		# height_at()), and the shader leaves it here.
		var gy: float = macro.height_at(p)
		# Wide and low: a canopy clump, not a post. At this distance the silhouette is all that
		# survives, and a tall thin box reads as a pole.
		var r: float = 7.0 + float(absi(hash([hs, "r"])) % 9)
		var th: float = 4.0 + float(absi(hash([hs, "t"])) % 6)
		veg.append(Transform3D(
			Basis(Vector3.UP, float(absi(hs) % 628) * 0.01).scaled(Vector3(r, th, r * 0.85)),
			Vector3(p.x, gy + th * 0.45, p.y)))
		veg_colors.append(_scrub(hs, cover_amount))
		veg_custom.append(Color(0.0, 0.0, 0.0, 0.0))
	if macro.hill_roads == null:
		return
	var houses: Array = _work.houses
	var house_colors: Array = _work.house_colors
	for m in macro.hill_roads.mansions_in(rect):
		var pos: Vector2 = m.pos
		var yaw: float = m.yaw
		var basis := Basis(Vector3.UP, yaw)
		# `height` is the pad's deck elevation (CityChunk._build_mansions builds on it), the house
		# 4 m back on the pad, on its 0.4 m pad, 7.5 m tall.
		var at := Vector3(pos.x, float(m.height), pos.y)
		houses.append(Transform3D(basis.scaled(Vector3(18.0, 7.5, 13.0)), at + basis * Vector3(0.0, 4.15, -4.0)))
		house_colors.append(Color(0.92, 0.88, 0.8))


func _spot(rect: Rect2, hs: int) -> Vector2:
	return rect.position + Vector2(
		rect.size.x * float(absi(hash([hs, "x"])) % 1000) / 1000.0,
		rect.size.y * float(absi(hash([hs, "z"])) % 1000) / 1000.0)


## Hill planting, matching the bands the terrain and macro-ground shaders already use: olive
## chaparral low down, greyer sage as it dries out with height, so the far hills do not read as
## one flat green.
func _scrub(hs: int, cover_amount: float) -> Color:
	var v: float = float(absi(hash([hs, "v"])) % 1000) / 1000.0
	var lush := Color(0.155, 0.205, 0.105).lerp(Color(0.225, 0.255, 0.130), v)
	var dry := Color(0.235, 0.230, 0.145).lerp(Color(0.285, 0.275, 0.185), v)
	return dry.lerp(lush, clampf(cover_amount, 0.0, 1.0))
