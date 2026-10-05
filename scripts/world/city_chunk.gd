class_name CityChunk
extends Node3D
## One city block plus the road on its +X side, the road on its +Z side, and the intersection at
## that corner. FULL level has everything: buildings, props, collision, physics trash cans.
## LOD level is just slabs and colored boxes for the far skyline, with plain box collision on
## buildings and full terrain collision so nothing drives into a far building or through a hill.
## Children are placed at true world coordinates; the chunk node sits at -WorldState.world_offset.

enum Level { FULL, LOD }

const BUILDING_SCENE := preload("res://scenes/props/building.tscn")
## Extra physics layer bit carried only by hill terrain, so "is terrain above me?" rays
## are not blocked by a pad, wall or roof on the way up.
const TERRAIN_LAYER := 16
const ROAD_TOP := 0.1
const SIDEWALK_TOP := 0.25
## How many scatter attempts a full hill chunk makes (rocks, shrubs, scrub, grass clusters).
## A bare slope is the loudest thing in a wide shot and the hills were the emptiest part of the
## map (2.9 M triangles against downtown's 8 M), so they carry half as much again.
@export var hill_scatter_min: int = 150
@export var hill_scatter_max: int = 230
## Hill planting (_plant_hills, on the ground HillPlanting reads out of the terrain shader):
## metres between the points of the jittered grid a FULL hill chunk tries a plant at. A
## chaparral stand gets a shrub at most of its points, so this is the stand's density.
@export var hill_brush_spacing: float = 6.2
## Share of a stand's grid points that carry a shrub, and the shrubs' height range in metres
## (chaparral is head-high to twice that; the wide low shape is most of what reads as brush).
@export var hill_brush_fill: float = 0.8
@export var hill_brush_height: Vector2 = Vector2(1.9, 3.4)
## Metres out to which a chunk's shrubs are drawn (to the nearest point of the chunk). Past a
## hundred metres a shrub's alpha-cut leaves mip away to a few dark texels and every stand drew
## as a scatter of black dashes over the hill; out there the terrain shader's painted stands,
## with their own canopy relief, are the brush.
@export var hill_brush_distance: float = 110.0
## How much of a hollow (HillPlanting.hollow(), metres per metre) a point needs before an oak or
## sycamore stands there, the odds it does in the deepest hollows, and their heights.
@export var hill_oak_hollow: float = 0.09
@export var hill_oak_chance: float = 0.3
@export var hill_oak_height: Vector2 = Vector2(6.0, 9.0)
## Odds of a lone shrub (sage, buckwheat) at a point of open dry grass.
@export var hill_sage_chance: float = 0.05
## Hill shells (_build_hill_shells, shaders/hill_shells.gdshader): a FULL hill tile drawn again
## as thin lifted layers that grow the knee-high dry grass and the brush understory out of the
## painted ground near the camera. Metres the shells keep clear of a hill road's edge and of a
## mansion pad's rim (the asphalt and the paving lie on the carved ground, so a shell would grow
## straight through them).
@export var shell_road_margin: float = 1.2
@export var shell_pad_margin: float = 1.5

@export_group("Geometry budget")
## Quads across a hill chunk's terrain tile: one for a chunk a hill road crosses (the carved
## road bed and the mansion pads are the sharpest features in the height field), one for plain
## slopes, one for the far LOD tiles. Terrain is a single mesh per chunk, so subdividing it is
## nearly free in draw calls; what it costs is height samples (about 6 us each) at build time.
@export var terrain_subdiv_road: int = 48
@export var terrain_subdiv: int = 32
## The far tiles were 6 quads across against the near tiles' 28, and the swap popped. Collision
## now reuses this same grid instead of re-sampling its own, so the extra detail is nearly free.
@export var terrain_subdiv_lod: int = 20
## Metres per quad in the city's ground grids (roads, pavements, lawns, plazas). The relief
## under the blocks rolls over tens of metres, so at 5 m a street was a visibly faceted plane.
@export var ground_grid_step: float = 2.2
## Metres per quad of the *collision* grid under those same surfaces, kept coarse on purpose:
## the trimesh is what physics walks on and it gains nothing from the visual resolution.
@export var ground_collision_step: float = 5.0
## The same for a far (LOD) chunk's merged ground. It used the near step, so a block 300 m out
## was ~12,000 triangles of flat ground and 32 of its 40 ms build (measured headless: the
## pavement slab alone 17.6 ms, the roads 14.7) - which is why a fast flight outran the LOD ring
## and flew over holes. The relief rolls over tens of metres; an 8 m chord is under 15 cm off it,
## a fraction of a pixel from where these chunks are seen.
@export var lod_ground_grid_step: float = 8.0
## FULL chunks' raised ground slabs cast their shadow from their skirt and edge cells alone
## (_add_ground_grid). False casts the whole grid again, the A/B (`GROUND_SHADOW=0` on
## still_shot.gd).
static var ground_skirt_shadows: bool = true
## Ground slabs whose top is at most this far over the pavement are "on the ground" for that rule.
const GROUND_RIM_TOP := 0.5
## Grass tufts per square metre of lawn, and the cap for one patch. A tuft is 160 triangles
## (ten creased blades) and covers about a third of a metre, so a lawn costs roughly 300
## triangles a square metre - a tenth of what the same ground costs in tree canopy overhead,
## for the surface the player is actually standing on. A lawn without it is a green plane
## wearing a texture, and the texture stops convincing at about three metres.
@export var grass_per_sqm: float = 1.9
@export var grass_max_per_patch: int = 22000
## How far blade grass, flowering ground cover and grass clumps keep drawing (metres). Grass
## used to stop at 70 m, which left a bald ring around the player wherever there was lawn.
@export var grass_distance: float = 115.0
@export var flower_distance: float = 150.0
@export var clump_distance: float = 135.0
## Ground-cover plants per square metre of planting, and the triangles one square metre of it
## may spend. The downloaded plants run from 941 triangles (bermuda grass) to 54 764 (a
## dandelion), a factor of fifty, so a flat instance count plants either a handful of dandelions
## or a thin sprinkle of everything else; the budget turns it into as many as the species costs.
@export var cover_per_sqm: float = 0.35
@export var cover_tris_per_sqm: float = 150.0
## Street trees stand closer together than they did. A real boulevard plants them about every
## ten metres; the streamer's `tree_spacing` is multiplied by this.
@export var street_tree_spacing: float = 0.85
## Quads across one chunk of sea, near and far. The waves are vertex displacement, so this is
## what decides whether a swell is a curve or a crease.
@export var ocean_subdiv: int = 72
@export var ocean_subdiv_lod: int = 32

const PROP_HEALTH := {"billboard": 300.0, "lamp": 30.0, "hydrant": 20.0, "bench": 20.0, "stop_sign": 10.0, "signal": 60.0, "signal_cabinet": 50.0, "barrier": 80.0, "cafe": 15.0, "planter": 25.0, "rack": 15.0, "newsbox": 10.0, "mailbox": 20.0, "bollard": 40.0, "street_sign": 12.0, "bus_stop": 40.0}

var plan: CityPlan
var ix: int = 0
var iz: int = 0
var level: Level = Level.FULL
var key: String = ""
var zone: MacroMap.Zone = MacroMap.Zone.CITY
## Colors and spacing from the streamer's exports.
var style: Dictionary = {}

var building_count: int = 0
var prop_records: Array[Dictionary] = []
## Landmark ids this chunk built in detail (the streamer hides their far versions meanwhile).
var built_landmarks: Array[String] = []

## Parked cars this chunk spawned. They live under the city root (a driven car must outlive its
## chunk), so the chunk frees the ones nobody drove when it unloads.
var _cars: Array[Node] = []
## The replica area's builder for this chunk, when a replica area runs through it (ReplicaBuilder).
var _replica: ReplicaBuilder = null
## The river's builder for this chunk, when the river's corridor reaches its block (RiverBuild):
## held here, its steps are bound to it.
var _river_build: RefCounted = null
var _batch := MultiMeshBatch.new()
## Per-block surface look (set by _block_surface from the district table and the block seed).
var _tree_bias: int = -1
## True when this block's street trees are palms (set per block from the district's "palms" odds).
var _palm_street: bool = false
var _jacaranda_street: bool = false
var _lamp_tint: Color = Color.WHITE
var _mm_nodes: Dictionary = {}
var _statics: StreetProps
## Footprints of the lots this chunk built on, so lawn grass can keep out of the houses.
var _lot_rects: Array[Rect2] = []
## The billboards a FULL build has planned (Billboards.on_building() / block_step()), placed as
## props by Billboards.commit() in a step just before the finish.
var billboard_jobs: Array = []
## LotFill's state while building: the fill ground by kind (merged at the finish, FULL only), and
## the trees and parked cars its forecourts and car parks have spent of their caps.
var _fill_ground: Dictionary = {}
var _fill_boxes: Array = []
var _fill_trees: int = 0
var _fill_cars: int = 0
## YardFill's (the yards outside downtown and midtown): the lots of a yard district and the
## freeway's right of way as the lot steps leave them, for the block step; then the yard ground's
## rects, walks, boxes and ivy cells and the upright boxes (merged at the finish, FULL only), and
## what the planting and parked cars have spent of the chunk's budgets.
var _yard_lots: Array = []
var _yard_corridor: Array = []
var _yard_ground: Array = []
var _yard_strips: Array = []
var _yard_boxes: Array = []
var _yard_ivy: Array[Rect2] = []
var _yard_walls: Array = []
var _yard_shrubs: int = 0
var _yard_trees: int = 0
var _yard_palms: int = 0
var _yard_flowers: int = 0
var _yard_cars: int = 0
## Industrial's (the INDUSTRIAL district's warehouses and yards): its lot entries, footprints and
## the meshes and counts it is building (Industrial._state()).
var _ind: Dictionary = {}
## The rec park's or school's meshes in the making (Parks._state()).
var _park: Dictionary = {}

## Dissolve state, driven by CityStreamer when this chunk is being replaced by a detailed one.
## Block index the streaming window was centred on when this chunk was built. Only used to
## decide whether far LOD buildings are worth giving collision to.
var center_block: Vector2i = Vector2i.ZERO
var _fade_left: float = 0.0
var _fade_total: float = 0.0
var _fade_mat: ShaderMaterial
var _prop_counter: int = 0


## Lattice spacing of the relief cache below, in metres.
const RELIEF_STEP := 3.0
## The lattice a far (LOD) chunk samples on, and the far city (Skyline) with it. A third as
## many samples per metre is a ninth as many relief evaluations, and the relief's shortest
## wavelength is ~100 m, so 9 m interpolates it to a few centimetres.
const LOD_RELIEF_STEP := 9.0
## Cached MacroMap.relief_at samples on a fixed world lattice, keyed Vector2i(x, z) / _relief_step.
var _relief_lattice: Dictionary = {}
var _relief_step: float = RELIEF_STEP

## Capture mode, for the far city (Skyline): the chunk runs its LOD block build - the same
## steps with the same random rolls, so the same lots, pads, malls and massing - but builds
## nothing. Ground slabs and solid boxes are recorded in `captured` instead of being made, and
## the batched boxes are read back from the batch. That is what makes the far tier the very city
## the LOD chunk will draw, including anything anyone adds to the block build later: it IS the
## block build. Set before begin_build(); the chunk never enters the tree.
var capturing: bool = false
## {"ground": [[Rect2, Color (tint), float top, Color (LINEAR: what the LOD chunk draws there,
##  seen from afar)], ...], "boxes": [[Transform3D, Color], ...],
##  "batch": {key: {"xforms", "colors", "custom"}}} once a capture has run.
var captured: Dictionary = {}

## The city's rolling ground under a world XZ (MacroMap.relief_at): every slab, prop and node a
## chunk builds adds this to its flat height. Zero on hills, beaches and flat zones.
##
## Sampled on a 3 m world lattice and bilinearly interpolated in between, because one true
## sample costs about 6 microseconds (two four-octave noise fields, a landmark loop and three
## rect fades) and a chunk asks for thousands of them: every ground-grid vertex, every batched
## instance, every prop. The field itself is smooth - its shortest wavelength is around 50 m,
## so the interpolation is within a couple of centimetres - and the lattice is shared by every
## slab and batch in the chunk, which is what pays for the finer ground grids and the much
## denser scatter below: they build FASTER than the coarse ones used to.
## The pavement height at (x, z) in this chunk's space: what a pedestrian walks on.
## A farmers' market's street (FarmersMarketBuild): people standing on it stand on the asphalt.
var market_road := Rect2()


func ground_y(x: float, z: float) -> float:
	if market_road.has_area() and market_road.has_point(Vector2(x, z)):
		return ROAD_TOP + _gy(x, z)
	return SIDEWALK_TOP + _gy(x, z)


func _gy(x: float, z: float) -> float:
	if plan == null or plan.macro == null:
		return 0.0
	var fx := x / _relief_step
	var fz := z / _relief_step
	var i := floori(fx)
	var j := floori(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	return lerpf(
		lerpf(_relief_sample(i, j), _relief_sample(i + 1, j), tx),
		lerpf(_relief_sample(i, j + 1), _relief_sample(i + 1, j + 1), tx), tz)


func _relief_sample(i: int, j: int) -> float:
	var key := Vector2i(i, j)
	var cached: Variant = _relief_lattice.get(key)
	if cached != null:
		return cached
	var h := plan.macro.relief_at(Vector2(i * _relief_step, j * _relief_step))
	_relief_lattice[key] = h
	return h


static var _detail_cache: float = -1.0

## 1 on desktop, a fraction of it in the browser build (WebGL, one thread). Everything dense in
## this file is scaled by it, so the web build stays playable while the desktop build spends.
static func _detail() -> float:
	if _detail_cache < 0.0:
		_detail_cache = 0.35 if OS.has_feature("web") else 1.0
	return _detail_cache


static var _tri_cache: Dictionary = {}

## Triangles in a mesh, measured once and cached per mesh (PropFactory hands out the same
## instance every time). This is what lets a scatter spend a triangle budget instead of an
## instance count - see `_scatter_ground_cover`.
static func _mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 1
	var id := mesh.get_instance_id()
	if _tri_cache.has(id):
		return _tri_cache[id]
	var n := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices != null:
			n += (indices as PackedInt32Array).size() / 3
		else:
			n += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	_tri_cache[id] = maxi(n, 1)
	return _tri_cache[id]


## The whole build at once: the loading screen, teleports and the smoke test use this.
func build() -> void:
	begin_build()
	while not build_step():
		pass


## Runs the next step of the build; true once the chunk is finished. CityStreamer calls this a
## few times a frame, inside a time budget, so a detailed block arriving while the player flies
## is spread over a few frames instead of all landing in one - and it is the same city either
## way, because the steps run in the same order with the same random rolls as build().
func build_step() -> bool:
	# At the finish, the steps that must follow every deferred one (_run_last) go in, one at a time.
	if _step == _steps.size() - 1 and not _last_steps.is_empty():
		_steps.insert(_step, _last_steps.pop_front())
	if _step < _steps.size():
		# A step that returns false has more to do and runs again next time (see _run_or_defer).
		if _steps[_step].call() != false:
			_step += 1
	return _step >= _steps.size()


## Runs `work` (a step that returns true once it is finished) as build steps of its own, just
## before the finish, when a build is under way; right here, to completion, otherwise. For big
## self-contained jobs with their own random stream - grass - so moving them later changes
## nothing about what they make.
func _run_or_defer(work: Callable) -> void:
	if _step < _steps.size() - 1:
		_steps.insert(_steps.size() - 1, work)
		return
	while work.call() != true:
		pass


## Runs `step` after every step the build has deferred (_run_or_defer, crowds, YardFill's walls),
## just before the finish, in the order these calls were made. For the passes that read what the
## deferred steps laid (ClimbingPlants, Murals). Each of them used to move itself behind whatever
## step still stood before the finish, and two of them did that to each other forever: the build
## never ended and grew its step list until the box ran out of memory.
func _run_last(step: Callable) -> void:
	_last_steps.append(step)


## `step` with the batch's relief lift switched off while it runs. The hill steps place their
## rocks, planting, pads and palms at MacroMap.height_at(), which already includes the relief
## (_gy: the inland valley's plateau, the rolling ground up the lower slopes), so the batch adding
## _gy again floated all of it by exactly that much - 15 m at the foot of the front range's
## valley flank, 75 m further up. Only these steps: anything else in a hill chunk (the replica's
## hill route, which places through ReplicaBuilder.rel()) is still lifted. Returns what the step
## returns, so a step that runs again (_plant_hills) keeps doing so.
func _on_map_ground(step: Callable) -> Callable:
	return func() -> Variant:
		_batch.ground = Callable()
		var done: Variant = step.call()
		_batch.ground = _gy
		return done


## The steps a build is made of: roads, the block's pavement, then each building, the street
## furniture, the parked cars, each pedestrian, the crossing, the freeway, and the finish. Each
## is small next to the old all-in-one build, which was a hundred milliseconds on a slow machine.
var _steps: Array[Callable] = []
var _step: int = 0
## Steps queued by _run_last(), put in front of the finish one by one when it is reached.
var _last_steps: Array[Callable] = []


func begin_build() -> void:
	_batch.ground = _gy
	_batch.tilt_keys = {"dash": true, "stripe": true, "manhole": true, "gutter": true, "grate": true, "stop_line": true, "patch": true, "arrow_straight": true, "arrow_left": true, "pstripe": true, "tree_grate": true}
	key = "%d,%d" % [ix, iz]
	name = "Chunk_" + key
	position = -WorldState.world_offset
	_relief_step = RELIEF_STEP if level == Level.FULL else LOD_RELIEF_STEP
	if level == Level.FULL and not capturing:
		_statics = StreetProps.new()
		_statics.chunk = self
		add_child(_statics)
	var block := plan.block(ix, iz)
	zone = plan.zone_at((block.rect as Rect2).get_center())
	_steps.clear()
	_step = 0
	_last_steps.clear()
	# A block the replica area's corridor runs through builds the replica's own content in place
	# of the seeded block (ReplicaAreas.block_role(), ReplicaBuilder).
	var replica: ReplicaAreas = plan.macro.replica if plan.macro else null
	var replica_role := 0
	if replica != null and (zone == MacroMap.Zone.CITY or zone == MacroMap.Zone.BEACH):
		replica_role = replica.block_role(plan, ix, iz)
	if capturing:
		_begin_capture(block, replica_role)
		return
	# The marina's blocks (Marina) build the marina, whatever their zone (MarinaBuild).
	if plan.marina_block(ix, iz):
		_steps.append_array(MarinaBuild.attach(self, block))
		_steps.append(_finish_build)
		return
	match zone:
		MacroMap.Zone.OCEAN:
			_steps.append(_build_water)
			# The same for the headland: its shore is an ellipse, so a chunk whose centre is at sea
			# can hold a slice of its sea cliffs, which nobody built - the hill chunk next door
			# ended in a straight wall of terrain along the chunk line.
			if _headland_shore(true):
				_steps.append_array([_sample_terrain, _build_terrain])
			# The waterline does not respect the zone grid: a chunk whose centre is out to sea
			# can still have the shore running through its landward edge, and before this those
			# bands showed as dark gaps between one beach and the next.
			if _owns_shoreline():
				_steps.append(_build_beach.bind(block))
				_steps.append(_build_hill_roads)
		MacroMap.Zone.HILLS:
			# ...and a hill chunk on the headland's shore holds a slice of sea, which only the
			# sea chunks built: its terrain ran down to sea level with no water over it.
			if _headland_shore(false):
				_steps.append(_build_water)
			_steps.append_array([_sample_terrain, _mark_shell_ground, _build_terrain, _build_hill_shells, _build_hill_roads, _on_map_ground(_build_mansions), _on_map_ground(_scatter_hills), _on_map_ground(_plant_hills)])
		MacroMap.Zone.BEACH:
			if replica_role == 0:
				_steps.append(_build_roads.bind(block))
			if _owns_shoreline():
				_steps.append(_build_beach.bind(block))
			# The coast highway runs the length of the sand on the land side of it, so a beach
			# chunk has to lay road as well; without this PCH simply stops at every beach town
			# and picks up again where the cliffs start.
			_steps.append(_build_hill_roads)
		MacroMap.Zone.AIRPORT:
			_steps.append(_build_airport)
		MacroMap.Zone.PORT:
			_steps.append_array(_port_steps(block))
		_:
			if _owns_shoreline():
				_steps.append(_build_beach.bind(block))
				_steps.append(_build_hill_roads)
			if block.has("site"):
				# A landmark owns this ground (CityPlan.sites()): the roads it keeps open, and its
				# own part of the landmark instead of a block.
				_steps.append(_build_roads.bind(block))
				_steps.append_array(Landmarks.site_steps(block.site, self))
				if level == Level.FULL:
					_steps.append(_build_intersection.bind(plan.intersection(ix + 1, iz + 1)))
				_steps.append(_build_freeway)
				_steps.append(_build_light_rail)
				_steps.append_array(FreightKit.attach(self))
				if level == Level.FULL and plan.macro:
					_steps.append(_build_landmarks)
				_steps.append(_finish_build)
				return
			if replica_role == 0 and plan.river_block(ix, iz):
				# The Los Angeles River's corridor reaches this block (LaRiver): its streets (the
				# ones the river closes end at the bank, the bridged ones run over it) and the
				# river's own ground, channel and bridges instead of the seeded block. No relief
				# floor at LOD: it would lie over the channel; RiverBuild brings its own collision.
				_steps.append(_build_roads.bind(block))
				_steps.append_array(RiverBuild.attach(self, block))
				if level == Level.FULL:
					_steps.append(_build_intersection.bind(plan.intersection(ix + 1, iz + 1)))
			elif replica_role == 0 and FreightYard.claims(plan, ix, iz):
				# The freight yard's blocks (FreightRail.yard_block()): its own ground and works.
				_steps.append(_build_roads.bind(block))
				_steps.append_array(FreightYard.attach(self))
			elif replica_role == 0:
				_steps.append(_build_roads.bind(block))
				_steps.append_array(_block_steps(block))
				if level == Level.FULL:
					_steps.append(_build_intersection.bind(plan.intersection(ix + 1, iz + 1)))
				else:
					_steps.append(_add_relief_floor)
			elif level != Level.FULL:
				_steps.append(_add_relief_floor)
	if replica != null and ReplicaBuilder.wanted(self):
		_steps.append_array(ReplicaBuilder.attach(self, replica_role))
	# The marina's channel, jetties, breakwater and highway bridge where they reach this chunk.
	_steps.append_array(MarinaBuild.extras(self))
	# The freeway runs over every zone: city blocks, the beach, the hills, the lot. It is built
	# last so its deck lands on top of whatever the chunk laid down.
	_steps.append(_build_freeway)
	# The light rail (LightRail, LightRailKit): track, structure, overhead, stations, gates.
	_steps.append(_build_light_rail)
	# What stands on the hills (RidgeBuild): towers, masts, tanks, fire roads, the right of way.
	_steps.append_array(RidgeBuild.attach(self))
	# The freight line (FreightRail, FreightKit): track, trench, decks, crossings, the yard's tracks.
	_steps.append_array(FreightKit.attach(self))
	if level == Level.FULL and plan.macro:
		_steps.append(_build_landmarks)
	if level == Level.FULL:
		# Tags, buffs, posters and stickers (StreetWear) on the walls, poles and freeway columns
		# everything above built. Hash-seeded: the block's rng is untouched.
		_steps.append(StreetWear.build.bind(self))
		# Bougainvillea, ivy, fig, jasmine, vines and accent plants on what the build laid
		# (ClimbingPlants: hash-seeded, moves itself behind the deferred steps).
		_steps.append(ClimbingPlants.build.bind(self))
		# Murals, ghost signs, painted crosswalks and cabinets (Murals): hash-seeded, last.
		_steps.append(Murals.build.bind(self))
		# Pole signs, window vinyl, banners and street plates (BoulevardSigns; hash-seeded, last).
		_steps.append(BoulevardSigns.build.bind(self))
	_steps.append(_finish_build)


## The capture build (see `capturing`): only what the far city draws from a block - its massing
## and its ground - run exactly as the LOD build runs it. Roads are left out (Skyline paints them
## from the plan), and so are the freeway (drawn from Freeway's own data), the landmarks (they
## have far versions of their own) and everything the finish step makes (nodes).
func _begin_capture(block: Dictionary, replica_role: int = 0) -> void:
	captured = {"ground": [], "boxes": [], "batch": {}}
	if plan.marina_block(ix, iz):
		_steps.append(MarinaBuild.capture.bind(self))
		_steps.append(func() -> void: captured.batch = _batch.data())
		return
	_steps.append_array(MarinaBuild.extras(self))
	match zone:
		MacroMap.Zone.CITY:
			# A replica block or a landmark's site does not build the seeded block, so the far
			# city must not record one there either.
			if String(block.get("site", "")) == GolfCourse.ID:
				# The golf course's capture: its ground's colour and its buildings (GolfBuild).
				_steps.append_array(GolfBuild.capture_steps(self))
			elif replica_role == 0 and not block.has("site"):
				if plan.river_block(ix, iz):
					_steps.append(RiverBuild.capture.bind(self))
				elif FreightYard.claims(plan, ix, iz):
					_steps.append(FreightYard.capture.bind(self))
				else:
					_steps.append_array(_block_steps(block))
			elif block.get("site", "") == OilField.ID:
				# The oil field's hill, pumpjacks, tanks and masts (OilFieldBuild).
				_steps.append_array(OilFieldBuild.capture_steps(self))
			elif block.has("site"):
				_steps.append_array(Landmarks.capture_steps(block.site, self))
		MacroMap.Zone.PORT:
			_steps.append_array(_port_steps(block))
		MacroMap.Zone.AIRPORT:
			_steps.append(_build_airport)
	_steps.append(func() -> void: captured.batch = _batch.data())


func _build_landmarks() -> void:
	for lm in Landmarks.in_rect(owned_rect()):
		Landmarks.build(lm, self, _statics, plan, true)
		built_landmarks.append(lm.id)
		# The crowds a landmark wants (a plaza full of people, a park's walkers) are ordinary
		# pedestrians on their own seeded stream, one per build step like the block's own, queued
		# just before the finish so nothing else in the build moves.
		for crowd: Array in Landmarks.crowds(lm, plan):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([plan.seed, lm.id, crowd[0]])
			for step in _crowd_steps(crowd[0], crowd[1], crowd[2], rng):
				_steps.insert(_steps.size() - 1, step)
		for step in Landmarks.people_steps(lm, self):
			_steps.insert(_steps.size() - 1, step)


## Batches that are paint on the road (shaders/road_paint.gdshader wears them).
const PAINT_KEYS := ["dash", "stripe", "stop_line", "arrow_straight", "arrow_left", "pstripe"]


func _finish_build() -> void:
	# Paint and wear never cast. `tilt_keys` is exactly the set of batches that lie flat on the
	# ground, and the tallest of them - a 2 cm crosswalk stripe at ROAD_TOP + 0.015, so 0.025 m
	# proud of the asphalt - throws an 0.022 m shadow with the sun at its default 48 degrees,
	# against the 0.059 m one near-cascade texel covers (2048 texels over the 120 m bounding
	# sphere of the first split at the 700 m reach Quality sets at HIGH). StreetDetail already
	# opts "gutter" and "patch" out by hand; this covers the other nine, up to nine shadow draw
	# calls a chunk across the 25 full chunks load_radius_blocks keeps, drawing nothing.
	# `flat_key`, not `key`: `key` is this chunk's own "ix,iz" member.
	for flat_key: String in _batch.tilt_keys:
		_batch.set_no_shadow(flat_key)
	# Lettering on street-name plates and shop boards: a few centimetres proud of the plate, so
	# its shadow falls on the plate it is printed on. A single street's signs were 70k triangles
	# of it in every cascade.
	for text_key: String in _batch.keys():
		if text_key.begins_with("text_"):
			_batch.set_no_shadow(text_key)
	_add_shop_spill()
	LotFill.commit(self)
	YardFill.commit(self)
	HouseKit.commit(self)
	HillHomeKit.commit(self)
	Industrial.commit(self)
	VacantLots.commit(self)
	Parks.commit(self)
	Alleys.commit(self)
	DecoBoulevard.commit(self)
	Construction.commit(self)
	StreetShadowReach.apply(self)
	_commit_far_ground()
	_commit_boxes()
	FreightKit.clear_road_decals(self)
	var fire_trees := TreeFire.collect(self, _batch)
	_mm_nodes = _batch.build(self)
	TreeFire.attach(self, fire_trees, _mm_nodes)
	for paint_key: String in PAINT_KEYS:
		if _mm_nodes.has(paint_key):
			(_mm_nodes[paint_key] as MultiMeshInstance3D).material_override = PropFactory.road_paint_material()
	if _mm_nodes.has("lod_box"):
		(_mm_nodes["lod_box"] as MultiMeshInstance3D).material_override = PropFactory.building_lod_material()
	_build_occluder()
	# The build's own samples go; pedestrians walking the pavement (Pedestrian._ground_y) fill
	# back only the few cells along their ring.
	_relief_lattice.clear()


## How far the shop spill draws (metres). Past it the lit shopfronts carry the street.
const SHOP_SPILL_DISTANCE := 170.0


## The light open shops throw on the pavement (Building.shop_pools), as ONE additive batch for
## the chunk: a draw call, and nothing at all by day (light_pool.gdshader reads lamp_factor). The
## batch adds the relief, so each pool goes in at the pavement top.
func _add_shop_spill() -> void:
	var mesh := PropFactory.shop_spill()
	for child in get_children():
		if child is Building:
			var b := child as Building
			for pool: Array in b.shop_pools:
				var xf: Transform3D = b.transform * (pool[0] as Transform3D)
				xf.origin.y = SIDEWALK_TOP + 0.06
				_batch.add("shop_spill", mesh, xf, pool[1])
	_batch.set_no_shadow("shop_spill")
	_batch.set_draw_distance("shop_spill", SHOP_SPILL_DISTANCE)


## Building boxes (building transform, part centre, part size) for this chunk's occluder: the
## LOD branch collects its own as it lays the boxes; FULL buildings are read back off the
## Building nodes in _build_occluder().
var _occluder_boxes: Array = []
## Metres each occluder box is pulled in from its building on every side, and down from its
## roof. An occluder must never stick out past what it stands for, or whatever is behind the
## sliver gets culled while it is in plain sight. 1.75 m clears the cut corners Building gives a
## wide part (one window bay off each end, and a box inset by half a cut on both axes is
## exactly inside the chamfer); the roof comes down a metre for parapets and plant.
const OCCLUDER_INSET := 1.75
const OCCLUDER_ROOF_DROP := 1.0


## One OccluderInstance3D per chunk, made of its building boxes, for Godot's occlusion culling.
## At street level the buildings either side hide most of the city, and until this every
## building, tree, car and person behind them was still sent to the GPU every frame. It removes
## nothing that is visible: only what is behind a wall. Needs
## rendering/occlusion_culling/use_occlusion_culling (project.godot); a no-op on the web, where
## the rasteriser it uses is not built.
func _build_occluder() -> void:
	for child in get_children():
		if child is Building:
			var b := child as Building
			# The building's whole transform: hill mansions are turned to face their road.
			for part in b.parts:
				_occluder_boxes.append([b.transform, part.center, part.size])
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for box: Array in _occluder_boxes:
		var xf: Transform3D = box[0]
		var c: Vector3 = box[1]
		var sz: Vector3 = box[2]
		var hx := sz.x * 0.5 - minf(OCCLUDER_INSET, sz.x * 0.2)
		var hz := sz.z * 0.5 - minf(OCCLUDER_INSET, sz.z * 0.2)
		var bottom := c.y - sz.y * 0.5
		var top := c.y + sz.y * 0.5 - OCCLUDER_ROOF_DROP
		# Small boxes cost the rasteriser more than they hide.
		if hx < 1.5 or hz < 1.5 or top - bottom < 4.0:
			continue
		var o := verts.size()
		for y: float in [bottom, top]:
			verts.append(xf * Vector3(c.x - hx, y, c.z - hz))
			verts.append(xf * Vector3(c.x + hx, y, c.z - hz))
			verts.append(xf * Vector3(c.x + hx, y, c.z + hz))
			verts.append(xf * Vector3(c.x - hx, y, c.z + hz))
		# Four walls and the roof; nothing sees a building's underside.
		for f: Array in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]:
			idx.append_array(PackedInt32Array([o + f[0], o + f[1], o + f[2], o + f[0], o + f[2], o + f[3]]))
	_occluder_boxes.clear()
	if idx.is_empty():
		return
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, idx)
	var node := OccluderInstance3D.new()
	node.name = "Occluder"
	node.occluder = occ
	add_child(node)


## The whole area this chunk owns: its block plus the roads on its +X and +Z sides.
func owned_rect() -> Rect2:
	return plan.owned_rect(ix, iz)


# --- Airport and port ------------------------------------------------------------------

func _build_airport() -> void:
	var area := owned_rect()
	var macro: MacroMap = plan.macro
	# The field over this chunk: concrete apron, taxiways, grass, runways (also in the far city's
	# capture), and at LOD / FULL the masts, fences and navaids, at FULL the paint, the light
	# fixtures and the ground crews at the gates (Airport; the buildings are landmarks).
	Airport.build_chunk(self)
	if capturing:
		return
	if level == Level.FULL and area.has_point(macro.terminal_curb.get_center()):
		# The drop-off curb in front of the terminal is packed (owner: "jampacked").
		var curb_rng := RandomNumberGenerator.new()
		curb_rng.seed = plan.seed ^ 0x7e5
		_spawn_crowd(macro.terminal_curb, 4.0, style.airport_crowd, curb_rng)
	if level == Level.FULL:
		# Flyable jets on the taxiway and the remote stands, owned like parked cars (city root,
		# freed with the chunk unless someone flew them away).
		for spot in macro.apron_spots:
			var sp: Vector2 = spot[0]
			if not area.has_point(sp):
				continue
			var jet := Aircraft.new()
			jet.setup_aircraft(spot[1] as Aircraft.Kind)
			var holder: Node = get_parent() if get_parent() else self
			jet.position = WorldState.to_local(Vector3(sp.x, 1.0, sp.y)) if holder != self else Vector3(sp.x, 1.0, sp.y)
			jet.rotation.y = float(spot[2]) if (spot as Array).size() > 2 else -PI * 0.5
			holder.add_child(jet)
			_cars.append(jet)


## Ground crew at a gate (Airport._crew()): an ApronCrew on a small ring, under the crowd cap.
func _spawn_apron_crew(ring: Rect2, rng: RandomNumberGenerator) -> void:
	if not _take_crowd_room():
		return
	var ped := ApronCrew.new()
	ped.setup(ring, 2.0, rng.randi())
	var start := ped._random_ring_point(2.0)
	ped.position = Vector3(start.x, plan.macro.tarmac_top + 0.1, start.y)
	add_child(ped)


## The container terminal (PortKit builds the pieces). The yard's rows, columns, skipped truck
## lanes and stack heights are still the old port's rolls on the block's own rng, made in the
## old order, so every stack stands where it stood; everything new - liveries, 20 ft pairs,
## high-cubes, the second box of a row, the gantries - draws from a private stream (`kit`).
## The far city replays this in capture mode and gets the same boxes.
const PORT_YARD_TOP := 0.2
## Yard concrete tint. At 0.78 the terminal read as a white sheet from the air, far brighter
## than the streets round it; real terminal paving is mid-grey concrete and asphalt.
const PORT_YARD_TINT := Color(0.44, 0.44, 0.43)
## Two boxes abreast in each row, centred this far either side of the row line (a 0.2 m gap).
const PORT_ROW_OFFSET := 1.32
## Metres of the quay chunks kept clear of stacks, back from the quay edge: the crane rails
## (the waterside one STS_QUAY_SETBACK in, the landside one a gauge behind it) and the lanes
## the trucks load in under the cranes.
const PORT_APRON := 42.0
const PORT_COLOR_ROLLS := 6
const PORT_PAINT_WHITE := Color(0.92, 0.92, 0.88)
const PORT_PAINT_YELLOW := Color(0.95, 0.72, 0.12)


## The port block as three build steps sharing `st`: the yard and its stacks, the paint, then
## the gantries or the quay with its cranes. One step used to hold all of it, and at full detail
## that was 16-26 ms against a street chunk's 3; split, lifted once (_port_lift) and warmed
## (PortKit.warm()), no step costs more than the old port's worst.
func _port_steps(block: Dictionary) -> Array[Callable]:
	var st := {"block": block}
	return [_port_yard.bind(st), _port_paint.bind(st), _port_kit.bind(st)]


## The height the port's pieces stand at above the plan: the relief at the chunk's centre, the
## same single lift the yard slab gets (_add_slab lifts a box by its centre), so the stacks, the
## paint and the cranes stand on the slab wherever it is. MacroMap flattens the relief to nothing
## over the port rect and the bay, so this is ~0 - but the paint alone sampled it ~2,000 times
## (five a line, for the tilt), 5-15 ms a chunk.
var _port_lift := 0.0
## FULL port chunks: every stack pile's top (PortLife.pile()), for the moving gantries.
var _port_piles: Array = []


func _pgy(_x: float, _z: float) -> float:
	return _port_lift


## Runs `work` with the batch lifting everything by `_port_lift` (and tilting nothing).
func _port_run(work: Callable) -> void:
	var lift := _batch.ground
	_batch.ground = _pgy
	work.call()
	_batch.ground = lift


func _port_yard(st: Dictionary) -> void:
	var block: Dictionary = st.block
	var area := owned_rect()
	var c := area.get_center()
	_port_lift = _gy(c.x, c.y)
	_add_slab(Vector3(c.x, 0.1, c.y), Vector3(area.size.x, 0.2, area.size.y), style.concrete, level == Level.FULL, PropFactory.road("concrete", 5.0, PORT_YARD_TINT, hash([plan.seed, ix, iz, "yard"]), 6.0, 0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = block.seed
	var kit := RandomNumberGenerator.new()
	kit.seed = hash([plan.seed, ix, iz, "port_kit"])
	var macro: MacroMap = plan.macro
	st.area = area
	st.kit = kit
	st.quay = macro.zone_at(Vector2(c.x, area.end.y + 30.0)) == MacroMap.Zone.OCEAN
	st.apron_z = area.end.y - PORT_APRON if st.quay else INF
	st.rows = int(area.size.y / 9.0)
	st.cols = int(area.size.x / 14.0)
	st.origin = Vector2(area.position.x + 8.0, area.position.y + 6.0)
	st.gate = PortLife.is_gate(plan, ix, iz)
	_port_piles.clear()
	var lanes: Array[int] = []
	st.lanes = lanes
	_port_run(func() -> void:
		var rows: int = st.rows
		var cols: int = st.cols
		var origin: Vector2 = st.origin
		for r in rows:
			if rng.randf() < 0.3:
				lanes.append(r) # an empty lane for trucks
				continue
			for col in cols:
				if rng.randf() < 0.35:
					continue
				var height := rng.randi_range(1, 3)
				var p := origin + Vector2(col * 14.0, r * 9.0)
				if p.x + 6.0 > area.end.x - 4.0 or p.y + 1.2 > area.end.y - 4.0:
					continue
				var picks: Array[int] = []
				for h in height:
					picks.append(rng.randi() % PORT_COLOR_ROLLS)
				if p.y + PORT_ROW_OFFSET + PortKit.W * 0.5 > float(st.apron_z):
					continue
				# The gate's chunk holds no stacks (PortLife / PortGate; after the rolls).
				if st.gate:
					continue
				_port_stack(p, height, picks, kit))


func _port_paint(st: Dictionary) -> void:
	if level != Level.FULL or capturing or st.gate:
		return
	_port_run(func() -> void: _paint_port_yard(st.area, st.origin, st.rows, st.cols, st.lanes, st.apron_z))


func _port_kit(st: Dictionary) -> void:
	var area: Rect2 = st.area
	var kit: RandomNumberGenerator = st.kit
	if level == Level.FULL and not capturing:
		PortLife.ensure(self)
	_port_run(func() -> void:
		if st.gate:
			PortGate.build(self, area)
		elif st.quay:
			_build_quay(area, kit)
		else:
			_place_rtg(area, st.origin, st.rows, st.cols, kit)
		if level == Level.FULL:
			for i in 2:
				_add_lamp(Vector3(area.position.x + 4.0 + i * (area.size.x - 8.0), 0.2, area.position.y + 4.0))
		var mp := Vector3(area.position.x + 3.0, PORT_YARD_TOP, area.position.y + 2.2)
		if level == Level.FULL and not capturing:
			# A high mast by the chunk's north-west corner, in the gap between the stacks (a pole
			# 40 cm thick is a pixel from the LOD ring, so the LOD chunks leave it out).
			_batch.add("port_mast", PortKit.mast_mesh(), Transform3D(Basis(), mp))
			_add_shape(Vector3(0.9, PortKit.MAST_H, 0.9), mp + Vector3(0.0, PortKit.MAST_H * 0.5 + _pgy(mp.x, mp.z), 0.0))
		if not capturing:
			# The mast's light on the yard after dark (the additive night quad the street lamps
			# use; nothing by day). A terminal at night is floodlit, and from the air the lit
			# yard is what reads, so the LOD chunks keep the pool without the pole.
			_add_port_pool(mp, PORT_MAST_POOL))
	if level != Level.FULL:
		# A gantry's shadow past the full ring is a smudge; skip its twin's draws.
		_batch.set_no_shadow("rtg")
	_batch.set_no_shadow("port_pool")


## Diameters (m) of the night light pools under a high mast and under a crane's portal.
const PORT_MAST_POOL := 92.0
const PORT_CRANE_POOL := 60.0


## An additive pool of floodlight on the yard at `at`, `size` across (PropFactory.light_pool(),
## laid flat the way _add_lamp() lays a street lamp's).
func _add_port_pool(at: Vector3, size: float) -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(size, 1.0, size)), Vector3(at.x, PORT_YARD_TOP + 0.07, at.z))
	# A soft falloff: floodlights 34 m up light the yard evenly, not in a hot spot like a street
	# lamp's.
	_batch.add("port_pool", PropFactory.light_pool(Color(1.0, 0.9, 0.74), 0.5, 1.5), xf)


## One stack slot: the rolled `height` of boxes in the row line, a second pile abreast (most
## slots) a box higher or lower, each pile 40 ft boxes or pairs of 20s, some of them high-cubes.
## `picks` are the old per-box colour rolls, which choose the first pile's liveries.
func _port_stack(p: Vector2, height: int, picks: Array[int], kit: RandomNumberGenerator) -> void:
	var single := kit.randf() < 0.15
	var offsets: Array[float] = [0.0]
	if not single:
		offsets = [-PORT_ROW_OFFSET, PORT_ROW_OFFSET]
	# Boxes in a row mostly face one way.
	var row_flip := kit.randf() < 0.5
	for li in offsets.size():
		var z := p.y + offsets[li]
		var n := height if li == 0 else clampi(height + kit.randi_range(-1, 1), 1, 4)
		var twenty := kit.randf() < 0.22
		var y := PORT_YARD_TOP
		var top_index := -1
		for h in n:
			var hc := kit.randf() < (0.1 if twenty else 0.45)
			var hgt := PortKit.H_HC if hc else PortKit.H_STD
			var pick: int = picks[h] if li == 0 and h < picks.size() else kit.randi() % PORT_COLOR_ROLLS
			if twenty:
				for e: float in [-1.0, 1.0]:
					var cx := p.x + e * (PortKit.L20 + PortKit.PAIR_GAP) * 0.5
					var liv := _port_livery(pick if e < 0.0 else kit.randi() % PORT_COLOR_ROLLS, kit)
					_add_container(Vector3(cx, y + hgt * 0.5, z), false, hc, row_flip != (kit.randf() < 0.2), liv, kit)
			else:
				top_index = _add_container(Vector3(p.x, y + hgt * 0.5, z), true, hc, row_flip != (kit.randf() < 0.15), _port_livery(pick, kit), kit)
			y += hgt
		if level == Level.FULL and not capturing:
			# Each pile's top for PortLife's gantries (a 40 ft box on top can be lifted off).
			_port_piles.append(PortLife.pile(_batch, top_index if not twenty else -1, p.x, z, y + _port_lift))
		if level == Level.FULL:
			_add_shape(Vector3(PortKit.L40, y - PORT_YARD_TOP, PortKit.W), Vector3(p.x, (PORT_YARD_TOP + y) * 0.5 + _pgy(p.x, z), z))


## The livery for an old colour roll: the shipping line of that hue, now and then a leasing
## pool's plain box or an old brown one instead.
func _port_livery(pick: int, kit: RandomNumberGenerator) -> int:
	var r := kit.randf()
	if r < 0.14:
		return 6
	if r < 0.24:
		return 7
	if r < 0.29:
		return 8
	return PortKit.COLOR_TO_LIVERY[pick]


func _add_container(centre: Vector3, forty: bool, high_cube: bool, flip: bool, livery: int, kit: RandomNumberGenerator) -> int:
	var look := PortKit.container_look(livery, kit)
	return _batch.add("container", PropFactory.container(), PortKit.container_xform(centre, forty, high_cube, flip), look[0], look[1])


## A painted line on the yard from `a` to `b` (plan XZ), through the road-paint batch.
func _port_line(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	# The stripe mesh is 0.6 m across and 3 m long in its own Z: scale it in its own frame
	# first, then turn its length onto the line.
	var basis := Basis(Vector3.UP, atan2(d.x, d.y)) * Basis().scaled(Vector3(width / 0.6, 1.0, length / 3.0))
	var mid := (a + b) * 0.5
	_batch.add("stripe", PropFactory.stripe(), Transform3D(basis, Vector3(mid.x, PORT_YARD_TOP + 0.011, mid.y)), color)


## Slot outlines round every stack slot, dashed centre lines down the truck lanes.
func _paint_port_yard(area: Rect2, origin: Vector2, rows: int, cols: int, lanes: Array[int], apron_z: float) -> void:
	var half_w := PORT_ROW_OFFSET + PortKit.W * 0.5 + 0.15
	var half_l := PortKit.L40 * 0.5 + 0.2
	for r in rows:
		var z := origin.y + r * 9.0
		if z + half_w > area.end.y - 1.0 or z + half_w > apron_z:
			continue
		if lanes.has(r):
			var x := area.position.x + 2.0
			while x < area.end.x - 5.0:
				_port_line(Vector2(x, z), Vector2(x + 3.0, z), 0.15, PORT_PAINT_YELLOW)
				x += 7.0
			continue
		for col in cols:
			var px := origin.x + col * 14.0
			if px + half_l > area.end.x - 1.0:
				continue
			for s: float in [-1.0, 1.0]:
				_port_line(Vector2(px - half_l, z + s * half_w), Vector2(px + half_l, z + s * half_w), 0.12, PORT_PAINT_WHITE)
				_port_line(Vector2(px + s * half_l, z - half_w), Vector2(px + s * half_l, z + half_w), 0.12, PORT_PAINT_WHITE)


## A yard gantry (most chunks away from the quay) straddling three rows over one column, its
## legs in the aisles between the rows.
func _place_rtg(area: Rect2, origin: Vector2, rows: int, cols: int, kit: RandomNumberGenerator) -> void:
	if rows < 3 or cols < 1 or kit.randf() > 0.8:
		return
	var reach := PortKit.RTG_SPAN * 0.5 + 0.6
	for attempt in 6:
		var r0 := kit.randi_range(0, rows - 3)
		var col := kit.randi_range(0, cols - 1)
		var flip := kit.randf() < 0.5
		var p := origin + Vector2(col * 14.0, (r0 + 1) * 9.0)
		if p.x - 4.8 < area.position.x + 0.5 or p.x + 4.8 > area.end.x - 0.5:
			continue
		if p.y - reach - 2.0 < area.position.y + 0.5 or p.y + reach > area.end.y - 0.5:
			continue
		var xf := Transform3D(Basis(Vector3.UP, PI) if flip else Basis(), Vector3(p.x, PORT_YARD_TOP, p.y))
		if level == Level.FULL and not capturing and PortLife.enabled:
			# A working gantry (PortLife moves it and its box; its collision moves with it).
			var dx := 14.0 if col + 1 < cols and p.x + 14.0 + 4.8 < area.end.x - 0.5 else -14.0
			PortLife.mark_rtg(self, Vector3(p.x, PORT_YARD_TOP + _pgy(p.x, p.y), p.y), flip, dx, _port_piles)
			return
		_batch.add("rtg", PropFactory.rtg(), xf)
		if level == Level.FULL:
			var lift := Transform3D(Basis(), Vector3(0.0, _pgy(p.x, p.y), 0.0))
			for s: Array in PortKit.rtg_shapes():
				_add_shape_xf(s[0], lift * xf * (s[1] as Transform3D))
		return


## The south quay: two ship-to-shore cranes per chunk on their rails, and at full detail the
## rails, the coping with its bollards and fenders, and the apron's paint.
func _build_quay(area: Rect2, kit: RandomNumberGenerator) -> void:
	var qz := area.end.y
	var macro: MacroMap = plan.macro
	var ship := _moored_ship()
	var crane_z := qz - PortKit.STS_QUAY_SETBACK - PortKit.STS_GAUGE * 0.5
	for k in 2:
		var x := area.position.x + area.size.x * (0.25 + 0.5 * k)
		if macro.zone_at(Vector2(x, qz + 30.0)) != MacroMap.Zone.OCEAN:
			continue
		var working := ship.x < INF and absf(x - ship.x) < 95.0
		if working and PortLife.enabled:
			# A working crane gantries along its rails to the bay it works.
			x = PortLife.bay_x(x)
		_build_sts_crane(Vector3(x, PORT_YARD_TOP, crane_z), working, ship.y - crane_z, kit, k)
	if level != Level.FULL or capturing:
		return
	var cx := area.get_center().x
	var w := area.size.x
	# Crane rails on their concrete beams, the waterside one near the edge.
	for zr: float in [qz - PortKit.STS_QUAY_SETBACK, qz - PortKit.STS_QUAY_SETBACK - PortKit.STS_GAUGE]:
		_add_slab(Vector3(cx, PORT_YARD_TOP + 0.004, zr), Vector3(w, 0.012, 1.1), Color(0.6, 0.6, 0.58), false)
		_add_slab(Vector3(cx, PORT_YARD_TOP + 0.03, zr), Vector3(w, 0.06, 0.14), Color(0.23, 0.22, 0.21), false)
	# The coping along the edge, a yellow line on it, bollards on it and fenders on its face.
	var cope_h := 0.3
	_add_slab(Vector3(cx, PORT_YARD_TOP + cope_h * 0.5, qz - 0.6), Vector3(w, cope_h, 1.2), Color(0.64, 0.63, 0.6))
	_port_line(Vector2(area.position.x, qz - 0.15), Vector2(area.end.x, qz - 0.15), 0.25, PORT_PAINT_YELLOW)
	var x := area.position.x + 8.0
	while x < area.end.x - 2.0:
		var at := Vector3(x, PORT_YARD_TOP + cope_h, qz - 0.75)
		_batch.add("port_bollard", PortKit.bollard_mesh(), Transform3D(Basis(), at))
		_add_shape(Vector3(0.6, 0.8, 0.6), at + Vector3(0.0, 0.4 + _pgy(x, at.z), 0.0))
		_batch.add("port_fender", PortKit.fender_mesh(), Transform3D(Basis(), Vector3(x + 8.0, PORT_YARD_TOP + 0.1, qz)))
		x += 16.0
	# The apron: the yellow keep-clear line inside the waterside rail and the truck lanes'
	# dashed lines between the rails.
	var lane_x0 := area.position.x + 1.0
	_port_line(Vector2(area.position.x, qz - 1.6), Vector2(area.end.x, qz - 1.6), 0.15, PORT_PAINT_YELLOW)
	for k in range(1, 6):
		var z := qz - PortKit.STS_QUAY_SETBACK - k * PortKit.STS_GAUGE / 6.0
		var dx := lane_x0
		while dx < area.end.x - 4.0:
			_port_line(Vector2(dx, z), Vector2(dx + 4.0, z), 0.13, PORT_PAINT_WHITE)
			dx += 9.0


## The moored container ship's anchor (plan XZ), or INF when there is none.
func _moored_ship() -> Vector2:
	for lm in Landmarks.all():
		if lm.id == "cargo_ship":
			return lm.anchor
	return Vector2(INF, INF)


## One ship-to-shore crane on the quay at `at` (its frame's origin). A crane over the moored
## ship (`working`) has its boom down and its trolley out over the ship, the spreader part way
## down, most with a box on it; the rest have their booms raised and their trolleys parked. The
## far city gets it as a dozen boxes. (`ship_z`, the ship's centre line in the crane frame, is
## what the working poses were chosen for: about 40 m out.)
func _build_sts_crane(at: Vector3, working: bool, ship_z: float, kit: RandomNumberGenerator, index: int) -> void:
	var raised := not working
	var trolley_z := PortKit.STS_PARKED.x
	var spreader_y := PortKit.STS_PARKED.y
	var carrying := false
	if working:
		# One of a few poses over the ship (PortKit.STS_WORK_POSES, warmed on the loading screen
		# so no crane builds its mesh mid-flight); the trolley nearest the ship's centre line.
		var pose: Vector2 = PortKit.STS_WORK_POSES[kit.randi() % PortKit.STS_WORK_POSES.size()]
		trolley_z = pose.x
		spreader_y = pose.y
		carrying = kit.randf() < 0.65
	var livery := _port_livery(kit.randi() % PORT_COLOR_ROLLS, kit)
	var base := at + Vector3(0.0, _pgy(at.x, at.z), 0.0)
	if capturing:
		for fb: Array in PortKit.sts_far_boxes(raised):
			var xf := Transform3D(Basis(), base) * (fb[1] as Transform3D)
			captured.boxes.append([Transform3D(xf.basis * Basis().scaled(fb[0]), xf.origin), fb[2]])
		return
	var crane := MeshInstance3D.new()
	# Named, so it is never mistaken for an auto-named box to merge, and a check can count it.
	crane.name = "StsCrane%d" % index
	var moving := working and level == Level.FULL and PortLife.enabled
	crane.mesh = PortKit.sts_frame_mesh() if moving else PortKit.sts_mesh(raised, trolley_z, spreader_y)
	crane.position = base
	add_child(crane)
	if moving:
		# PortLife runs its trolley, spreader and boxes (the rolls above are still made).
		PortLife.mark_crane(self, base, ix * 2 + index)
		if carrying:
			PortKit.container_look(livery, kit)
			kit.randf()
	elif carrying:
		_add_container(at + Vector3(0.0, spreader_y - PortKit.H_STD * 0.5 - 0.03, trolley_z), true, false, kit.randf() < 0.5, livery, kit)
	# Its floodlights on the apron after dark.
	_add_port_pool(at + Vector3(0.0, 0.0, 6.0), PORT_CRANE_POOL)
	if level == Level.FULL:
		for s: Array in PortKit.sts_shapes(raised):
			_add_shape_xf(s[0], Transform3D(Basis(), base) * (s[1] as Transform3D))


# --- Ocean, beach, hills ---------------------------------------------------------------

func _build_water() -> void:
	var area := owned_rect()
	var c := area.get_center()
	# Waving surface (shaders/ocean.gdshader, Gerstner waves sized by the Weather node) over a
	# solid box so the sea still holds you up. Surface at +0.15 so it sits above the ground
	# follower plane (y = 0), which otherwise shows through as grass over the whole sea.
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(area.size.x, area.size.y)
	# The swell is Gerstner displacement in the vertex shader, so this subdivision IS the wave
	# shape: at 12 quads a far chunk had 8 m quads and the sea read as folded paper next to
	# the near chunks. One mesh per chunk either way - it costs triangles, not draw calls.
	var n := ocean_subdiv if level == Level.FULL else ocean_subdiv_lod
	plane.subdivide_width = n
	plane.subdivide_depth = n
	mesh.mesh = plane
	mesh.material_override = PropFactory.ocean_material()
	mesh.position = Vector3(c.x, 0.15, c.y)
	mesh.custom_aabb = AABB(Vector3(-area.size.x * 0.5, -40.0, -area.size.y * 0.5), Vector3(area.size.x, 80.0, area.size.y))
	mesh.name = "Ocean"
	# It never casts. The sea at y 0.15 is the lowest drawn surface in the world and it is fully
	# opaque (depth_draw_opaque, no ALPHA path), so nothing under it is visible and the only
	# thing it could shadow is itself. At subdivide 72 this plane is 73 x 73 quads = 10,658
	# triangles, 2,178 at the LOD's 32, and a coastal view has 25 FULL chunks plus the LOD ring
	# inside directional_shadow_max_distance 400, so a six-figure triangle count - every vertex
	# of it running five Gerstner swells plus the tsunami - went into the cascades every frame.
	# What that bought was self-shadowing between crests, and the swell is gentle enough for the
	# sun's default 2.0 normal bias and 0.75 shadow blur to eat most of it. It still RECEIVES,
	# which is what piers, boats and the freeway deck need.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	# The sea floor. The visual box has to sit well below the deepest wave trough: at wave_scale
	# 1 the swell is already +-1.2 m and a storm is six times that, so with its top just under
	# the surface the trough dipped below it and the floor's flat top drew *over* the water in
	# hard-edged grey patches, which is what made the sea look like a broken plane. The
	# collision stays where it was, so the sea still holds you up at the surface.
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(area.size.x, 1.0, area.size.y)
	floor_mesh.mesh = box
	floor_mesh.material_override = PropFactory.material(style.ocean.darkened(0.5), 0.6)
	floor_mesh.position = Vector3(c.x, -14.0, c.y)
	# Fourteen metres under opaque water, and the only thing below it is the ground follower,
	# which its own vertex shader sinks another ten wherever the bake says water. Nothing its
	# shadow could darken is ever drawn, and it was one more shadow draw call per water chunk
	# per cascade - 225 chunks are streamed at once and the 700 m shadow distance reaches all
	# of them, so out at sea that is every one of them casting into nothing.
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mesh)
	if level == Level.FULL:
		_add_shape(box.size, Vector3(c.x, -0.6, c.y))


## Sand steps along the shore, in metres. Short enough that the coastline's curve reads as a
## curve: the shore bends by up to 180 m over its length, and at chunk size that came out as a
## row of rectangles with the corners cut off each other.
const SAND_STEP := 9.0
## How far the sand runs out UNDER the water, and how far inland past the beach zone it reaches.
## Both are overlaps on purpose - the wet strip has to start below the waterline or the waves
## break onto an edge, and the inland lip has to pass under the first row of buildings or a
## hairline of ground shows through between the sand and the town.
const SAND_WET := 26.0
const SAND_LIP := 22.0
## The sand's profile, in metres of height. A beach is two slopes, not one: a steep wet face
## that runs down under the water and a long gentle dry rise behind it. Getting this wrong is
## very visible - a single ramp from below the waves to the town crosses the sea surface (which
## sits at 0.15) most of the way up the beach, and drowns it.
## SAND_EDGE is where the sand meets the water, and must stay ABOVE 0.15.
## UV units per metre of sand. The material is world-triplanar, so this only has to be
## consistent and roughly the right scale for the tangent basis the normal map needs.
const SAND_UV_SCALE := 0.2
## The berm and the swash. A beach is not one ramp: the swash piles a crest up about half way
## across the dry sand and the backshore falls away again behind it. That crest is the whole
## reason a beach has a shape from standing height - the plane this used to be ran at a constant
## 0.3 per cent over 92 m, so it had ONE normal across its whole width and shaded as one flat
## colour whatever texture was on it (measured: luminance sigma 1.2 of 255 across the sand in a
## ground-level frame, against 25 for the water beside it).
## SAND_BERM_AT is where the crest sits as a fraction of beach_width, SAND_CREST how high it
## stands above the waterline, SAND_SWASH how far up the beach the sea still washes, SAND_CUSP
## how much the crest rises and falls along the shore. Keep SAND_CUSP small: the collider
## follows this profile in bands and the player stands on the collider, not on the mesh.
const SAND_SWASH := 13.0
const SAND_BERM_AT := 0.46
const SAND_CREST := 0.95
const SAND_CUSP := 0.12
## The tonal bands across the shore, seaward to landward, one per point in a _build_sand() row:
## under water, the waterline, the swash, the berm, the backshore. Sand the sea has just been
## over is a third darker and much less warm than dry sand, and the line where it dries out is
## the strongest single cue that a beach is a beach. No texture can carry it - a 5 m tile mips
## to one flat colour by forty metres, the same thing PropFactory.lawn() was written to fix for
## grass - so it rides the vertex colour. These multiply into the albedo: 1.0 is exactly the
## sand that was there before and every other value only darkens it.
const SAND_TONES: Array[Color] = [
	Color(0.44, 0.48, 0.52), Color(0.50, 0.53, 0.56), Color(0.54, 0.56, 0.59), Color(0.84, 0.81, 0.75),
	Color(1.0, 1.0, 1.0), Color(0.90, 0.90, 0.88),
]
## The sand falls away fast under the water (SAND_STEEP_AT metres seaward of the waterline it is
## at SAND_STEEP_Y, and SAND_LOW at SAND_WET): the surf's troughs and its held-down mean level
## (surf.gdshaderinc) reach well below the old 0.75 m at 26 m out, so the sand poked up through
## the inner surf zone and z-fought it in nested zigzags, and where the flat sea plane crossed a
## 3.7 % ramp the two lay centimetres apart over metres.
const SAND_STEEP_AT := 3.5
const SAND_STEEP_Y := -0.6
## Bands across the profile the dry sand's collider is cut into.
const SAND_COLLIDER_BANDS := 5
const SAND_LOW := -3.0
const SAND_EDGE := 0.22
const SAND_HIGH := 0.5


## The beach: a strip that follows the shoreline itself rather than a chunk-sized slab. The
## coast is a curve, so slabs left visible rectangular seams and, where the curve ran out of a
## chunk, gaps of bare ground between one beach and the next. This walks the chunk's Z range,
## asks MacroMap where the water is at each step, and lays a continuous ramp from under the
## waves up to the town.
## True when this chunk is the one the waterline runs through at its own Z. Exactly one chunk per
## Z band answers yes, so the sand is laid once and never double-drawn by a neighbour.
## True if this chunk's rect holds part of the Palos Verdes headland (`land`) or of the sea off
## its shore (not `land`), sampled on a 5 x 5 grid. San Pedro Bay wraps the headland's south and
## east sides, so its whole shore runs through chunks zoned by their centres alone.
func _headland_shore(land: bool) -> bool:
	var macro: MacroMap = plan.macro
	if macro == null:
		return false
	var r := owned_rect()
	if macro.headland_dist(r.get_center()) > r.size.length() + 50.0:
		return false
	# Not along the replica's coast (Malaga Cove and north): its sand, bluff and beach are its own.
	if macro.replica:
		var cr: Vector2 = macro.replica.coast_range()
		if r.end.y > cr.x - 200.0 and r.position.y < cr.y + 200.0:
			return false
	for j in 5:
		for i in 5:
			var p := r.position + r.size * Vector2(float(i) / 4.0, float(j) / 4.0)
			if land:
				if macro.headland_dist(p) < -2.0 and macro.zone_at(p) != MacroMap.Zone.OCEAN:
					return true
			elif macro.zone_at(p) == MacroMap.Zone.OCEAN and macro.headland_dist(p) < 400.0:
				return true
	return false


func _owns_shoreline() -> bool:
	if plan.macro == null:
		return false
	var rect := owned_rect()
	var cx := plan.macro.coast_x(rect.get_center().y)
	return cx >= rect.position.x and cx < rect.end.x


func _build_beach(block: Dictionary) -> void:
	# Under a replica area the grid roads that would cross the sand are not built (the corridor
	# runs to the sea), so the sand covers the chunk's road strips too.
	# The street ending at the beach on the block's +Z side is this chunk's too, and the sand has
	# to run across its strip: built over the block alone, every street end along the coast was a
	# gap in the beach with the sea plane showing through it (the sea chunk's water lies over its
	# whole rect, flat at 0.15, sand or not). Over the strip the sand's landward edge dips under
	# the road instead of standing on it (_build_sand's `strip_from`).
	var life_z := Vector2(owned_rect().position.y, owned_rect().end.y)
	# The marina's channel cuts the sand (MarinaBuild.sand_rects(): the rect less its band).
	if _replica != null:
		for sr: Rect2 in MarinaBuild.sand_rects(self, owned_rect()):
			_build_sand(sr)
	else:
		var r: Rect2 = block.rect
		var own := owned_rect()
		for sr: Rect2 in MarinaBuild.sand_rects(self, Rect2(r.position.x, r.position.y, r.size.x, maxf(own.end.y - r.position.y, r.size.y))):
			_build_sand(sr, r.end.y if sr.position.y < r.end.y - 0.5 else INF)
		life_z = Vector2(r.position.y, maxf(own.end.y, r.end.y))
	if level != Level.FULL:
		# The beach's towels and umbrellas as dots of colour, the path and the courts (BeachLife).
		if not capturing:
			BeachLife.build_lod(self, life_z.x, life_z.y)
		return
	for sr: Rect2 in MarinaBuild.sand_rects(self, owned_rect() if _replica != null else Rect2(block.rect.position, Vector2(block.rect.size.x, owned_rect().end.y - block.rect.position.y))):
		_build_surf_spray(sr)
	var rng := RandomNumberGenerator.new()
	rng.seed = block.seed
	# The replica's beach under the Esplanade bluff has no palms on the sand (they are up on the
	# bluff, in the front yards).
	var bare := false
	if plan.macro and plan.macro.replica:
		var cr: Vector2 = plan.macro.replica.coast_range()
		bare = block.rect.end.y > cr.x and block.rect.position.y < cr.y
	# Scattered across the DRY sand, which is a band that moves with the shoreline rather than
	# the chunk's rectangle: dropping them in the rectangle put palms in the surf.
	# BeachLife's bike path runs along the back of the sand: a palm rolled onto it is moved just off
	# it (after its roll, so the stream does not move), and the palms and the tower are what the
	# beach's people keep clear of.
	var path := BeachLife.enabled and not bare and not BeachLife.kept_off(plan, (life_z.x + life_z.y) * 0.5)
	var obstacles: Array = []
	for i in rng.randi_range(6, 14):
		var z := rng.randf_range(block.rect.position.y + 4.0, block.rect.end.y - 4.0)
		var across := rng.randf_range(0.18, 0.95)
		if path and absf(across - BeachLife.PATH_AT) < 0.05:
			across = BeachLife.PATH_AT + (0.06 if across >= BeachLife.PATH_AT else -0.06)
		var at := Vector3(_dry_sand_x(z, across), _sand_y(z, across), z)
		# Not in the marina's channel: the same six draws _add_palm() makes, so nothing moves.
		if not bare and MarinaBuild.on_channel(self, at, 4.0):
			for d in 6:
				if d == 1:
					rng.randi()
				else:
					rng.randf()
		elif not bare:
			_add_palm(at, rng)
			obstacles.append([Vector2(at.x, at.z), 0.8])
	var tower := {}
	if rng.randf() < 0.6:
		var z := rng.randf_range(block.rect.position.y + 8.0, block.rect.end.y - 8.0)
		var across := rng.randf_range(0.1, 0.5)
		var spin := rng.randf_range(0.0, TAU)
		var at := Vector3(_dry_sand_x(z, across), _sand_y(z, across), z)
		if MarinaBuild.on_channel(self, at, 8.0):
			pass # Not in the marina's channel (its rolls are made).
		elif BeachLife.enabled:
			# Turned to the sea (a tower watches the water), its rolled spin only a little jitter.
			var slope := (plan.macro.coast_x(z + 2.0) - plan.macro.coast_x(z - 2.0)) / 4.0 if plan.macro else 0.0
			var yaw := atan2(1.0, -slope) + (spin / TAU - 0.5) * 0.3
			tower = {"at": Vector2(at.x, at.z), "yaw": yaw, "y": at.y}
			obstacles.append([Vector2(at.x, at.z) - Vector2(-sin(yaw), -cos(yaw)) * 1.8, 4.6])
			_batch.add("beach_tower", BeachLife.tower_mesh(), Transform3D(Basis(Vector3.UP, yaw), at))
			_add_shape(Vector3(3.1, 4.8, 3.4), at + Basis(Vector3.UP, yaw) * Vector3(0.0, 2.4, 0.4), yaw)
		else:
			_add_lifeguard_tower(at, spin)
	# The beach's people keep out of the marina's channel and off its jetties.
	obstacles.append_array(MarinaBuild.beach_obstacles(self))
	BeachLife.build(self, life_z.x, life_z.y, obstacles, tower)


## Metres of shoreline between two spray instances (shaders/surf_spray.gdshader).
const SPRAY_STEP := 7.0


## Spray and mist off the breakers along this chunk's stretch of the waterline: one MultiMesh of
## quads, two per SPRAY_STEP (the tall spray off the lip and the low mist behind it), each at the
## waterline with the way to the land in its custom data. The shader moves each out to the break
## point and puffs it as the waves break there, so this costs one draw and never changes.
func _build_surf_spray(rect: Rect2) -> void:
	var macro: MacroMap = plan.macro
	if macro == null:
		return
	var count := maxi(1, int(rect.size.y / SPRAY_STEP))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = count * 2
	mm.mesh = PropFactory.surf_spray_mesh()
	var lo := Vector3(INF, 0.0, INF)
	var hi := Vector3(-INF, 0.0, -INF)
	for i in count:
		var z := rect.position.y + (float(i) + 0.5) * rect.size.y / count
		var x := macro.coast_x(z)
		var slope := (macro.coast_x(z + 1.0) - macro.coast_x(z - 1.0)) * 0.5
		var land := Vector2(1.0, -slope).normalized()
		var h := fposmod(sin(z * 12.9898 + x * 78.233) * 43758.5453, 1.0)
		for kind in 2:
			mm.set_instance_transform(i * 2 + kind, Transform3D(Basis(), Vector3(x, 0.15, z)))
			mm.set_instance_custom_data(i * 2 + kind, Color(land.x, land.y, fposmod(h + 0.37 * kind, 1.0), float(kind)))
		lo = Vector3(minf(lo.x, x), 0.0, minf(lo.z, z))
		hi = Vector3(maxf(hi.x, x), 0.0, maxf(hi.z, z))
	var inst := MultiMeshInstance3D.new()
	inst.name = "SurfSpray"
	inst.multimesh = mm
	inst.material_override = PropFactory.surf_spray_material()
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader carries every quad out to the break point (up to ~110 m in a storm) and up.
	var reach := 160.0
	inst.custom_aabb = AABB(Vector3(lo.x - reach, -2.0, lo.z - 20.0), Vector3(hi.x - lo.x + reach + 40.0, 30.0, hi.z - lo.z + 40.0))
	add_child(inst)


## Height of the sand at `across` (0 at the waterline, 1 at the town) for a given Z. The berm
## wanders along the shore, which is what cusps are; it is a smooth function of z so it carries
## across a chunk boundary without a step.
func _sand_y(z: float, across: float) -> float:
	var crest := SAND_CREST + SAND_CUSP * sin(z * 0.11) * cos(z * 0.047)
	if across <= SAND_BERM_AT:
		return lerpf(SAND_EDGE, SAND_EDGE + crest, across / maxf(SAND_BERM_AT, 0.001))
	var t := (across - SAND_BERM_AT) / maxf(1.0 - SAND_BERM_AT, 0.001)
	return lerpf(SAND_EDGE + crest, SAND_HIGH, t * t * (3.0 - 2.0 * t))


## `strip_from`: rows past this z are the street strip on the block's +Z side, where the sand's
## landward edge dips under the road (ROAD_TOP) rather than standing 0.4 m over it.
## Each vertex carries UV2 = (metres landward of the waterline, beach width) for the swash
## (shaders/beach_sand.gdshader).
func _build_sand(rect: Rect2, strip_from: float = INF) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var macro: MacroMap = plan.macro
	var zs := PackedFloat32Array()
	var z_end := minf(rect.end.y, strip_from)
	var steps := maxi(2, ceili((z_end - rect.position.y) / SAND_STEP))
	for i in steps + 1:
		zs.append(rect.position.y + (z_end - rect.position.y) * float(i) / steps)
	if strip_from < rect.end.y - 0.5:
		var w := rect.end.y - strip_from
		var edge := minf(2.0, w * 0.3)
		zs.append(strip_from + edge)
		zs.append(rect.end.y - edge)
		zs.append(rect.end.y)
	var quads := 0
	var prev: Array[Vector3] = []
	var prev_w := 0.0
	var prev_x := 0.0
	for i in zs.size():
		var z: float = zs[i]
		var water_x := rect.position.x
		var inland_x := rect.end.x
		var width := inland_x - water_x
		if macro:
			water_x = macro.coast_x(z)
			width = macro.beach_width_at(z)
			inland_x = water_x + width + SAND_LIP
		var in_strip := z > strip_from + 0.01 and z < rect.end.y - 0.01
		# Seaward to landward: the bar under the water, the waterline, the swash the sea still
		# reaches, the berm crest, and the backshore falling away behind it.
		var row: Array[Vector3] = [
			Vector3(water_x - SAND_WET, SAND_LOW, z),
			Vector3(water_x - SAND_STEEP_AT, SAND_STEEP_Y, z),
			Vector3(water_x, SAND_EDGE, z),
			Vector3(water_x + SAND_SWASH, _sand_y(z, SAND_SWASH / maxf(width, 1.0)), z),
			Vector3(water_x + width * SAND_BERM_AT, _sand_y(z, SAND_BERM_AT), z),
			Vector3(inland_x, ROAD_TOP - 0.04 if in_strip else SAND_HIGH, z),
		]
		if i > 0:
			# One strip per band. UVs come from world XZ so the grain runs continuously from one
			# chunk into the next; without them generate_tangents() fails outright and the sand
			# gets no tangent basis, which silently kills its normal map.
			for k in row.size() - 1:
				var a: Vector3 = prev[k]
				var b: Vector3 = prev[k + 1]
				var c: Vector3 = row[k + 1]
				var d: Vector3 = row[k]
				for pair in [[a, SAND_TONES[k], 0], [b, SAND_TONES[k + 1], 0], [c, SAND_TONES[k + 1], 1],
						[a, SAND_TONES[k], 0], [c, SAND_TONES[k + 1], 1], [d, SAND_TONES[k], 1]]:
					var v: Vector3 = pair[0]
					var this_row: bool = pair[2] == 1
					st.set_color(pair[1] as Color)
					st.set_uv(Vector2(v.x, v.z) * SAND_UV_SCALE)
					st.set_uv2(Vector2(v.x - (water_x if this_row else prev_x), width if this_row else prev_w))
					st.add_vertex(v)
				quads += 1
		prev = row
		prev_w = width
		prev_x = water_x
	if quads > 0:
		st.generate_normals()
		st.generate_tangents()
		var mesh := MeshInstance3D.new()
		mesh.name = "Sand"
		mesh.mesh = st.commit()
		# The sand set at 2 m a tile (the set is trodden sand, footprints and all, photographed over
		# about that; at 5 m every footprint was half a metre across, and under a low sun the beach
		# read as rippling water), the wet/dry banding above from the vertex colour, and the surf's
		# swash running up it (PropFactory.beach_sand_material(), shaders/beach_sand.gdshader).
		mesh.material_override = PropFactory.beach_sand_material()
		add_child(mesh)
	if level != Level.FULL:
		return
	# The collider follows the berm in bands rather than being one flat box under the whole
	# beach: with a metre of crest in the middle, a flat box leaves the player walking through
	# the sand on the way up and a foot above it on the way down. Five boxes, not a mesh shape -
	# the player only ever walks the dry sand and a box stack is cheaper and steadier.
	var block_rect := Rect2(rect.position, Vector2(rect.size.x, minf(rect.end.y, strip_from) - rect.position.y))
	var c := block_rect.get_center()
	if macro == null:
		_add_shape(Vector3(block_rect.size.x, 0.4, block_rect.size.y), Vector3(c.x, SAND_EDGE - 0.1, c.y))
		return
	var width: float = macro.beach_width_at(c.y) + SAND_LIP
	var band := width / float(SAND_COLLIDER_BANDS)
	for k in SAND_COLLIDER_BANDS:
		var across := (float(k) + 0.5) / float(SAND_COLLIDER_BANDS)
		var x := macro.coast_x(c.y) + width * across
		var y := _sand_y(c.y, across)
		_add_shape(Vector3(band + 0.2, 0.4, block_rect.size.y), Vector3(x, y - 0.2, c.y))
	# The street strip: the seaward bands only, where the sand keeps its profile.
	if strip_from < rect.end.y - 0.5:
		var sz := (strip_from + rect.end.y) * 0.5
		for k in 3:
			var across := (float(k) + 0.5) / float(SAND_COLLIDER_BANDS)
			_add_shape(Vector3(band + 0.2, 0.4, rect.end.y - strip_from), Vector3(macro.coast_x(sz) + width * across, _sand_y(sz, across) - 0.2, sz))


## X of a point on the dry sand at Z, `across` running 0 at the waterline to 1 at the town.
func _dry_sand_x(z: float, across: float) -> float:
	if plan.macro == null:
		return owned_rect().get_center().x
	return plan.macro.coast_x(z) + plan.macro.beach_width_at(z) * across


## One whole palm from PropFactory.palm(): trunk, crown, dead-frond skirt and coconuts in a
## single batched mesh, so a palm-lined boulevard costs one draw call.
## `collide` is false for palms standing in for street trees: ordinary street trees have never
## had collision, and giving a whole boulevard of them solid trunks walls the road in and traps
## cars against the kerb.
## Radius of a palm crown at scale 1, in metres: a Washingtonia frond is about three metres and
## the fronds sit round a point. Used to keep a crown out of the building next to it.
const PALM_CROWN_R := 3.2


## Distance from `p` to the nearest building footprint this chunk has recorded, 0 inside one.
## The lot steps fill `_lot_rects` before `_build_sidewalk_props` runs, so a street tree can ask
## how much room it actually has before it decides how big to be.
func _room_for_canopy(p: Vector2) -> float:
	var best := 99.0
	for lot in _lot_rects:
		var dx := maxf(maxf(lot.position.x - p.x, p.x - lot.end.x), 0.0)
		var dy := maxf(maxf(lot.position.y - p.y, p.y - lot.end.y), 0.0)
		best = minf(best, Vector2(dx, dy).length())
		if best <= 0.0:
			return 0.0
	return best


## `lean_to`, if given, is the direction the trunk should lean in - the road, for a street palm.
## Without it a palm planted 2.4 m from a lot line puts a three-metre frond through the building.
func _add_palm(at: Vector3, rng: RandomNumberGenerator, collide: bool = true, lean_to: Vector2 = Vector2.ZERO) -> void:
	var s := rng.randf_range(0.78, 1.25)
	var variant := rng.randi() % PropFactory.PALM_VARIANTS
	var yaw := rng.randf_range(0.0, TAU)
	if lean_to != Vector2.ZERO:
		# Cancel the mesh's own lean yaw, then aim it, with enough jitter that a row of palms
		# does not lean in lockstep. The jitter is folded out of the yaw we already drew rather
		# than taken from a fresh randf: a new call on a block's rng shifts every prop placed
		# after it, and the city for a given seed would quietly become a different city.
		yaw = atan2(lean_to.x, lean_to.y) - PropFactory.palm_lean(variant) + (yaw / TAU - 0.5) * 1.2
		# And it can only be as big as the gap it stands in. Downtown lots run to the pavement
		# line, so a full-size crown two metres off the glass models a frond through the
		# building - the most obvious kind of wrong there is in a city. Never below 0.55, or
		# the boulevard turns into a row of shrubs.
		s = minf(s, maxf(0.55, _room_for_canopy(Vector2(at.x, at.z)) / PALM_CROWN_R))
	var tint := Color(rng.randf_range(0.88, 1.12), rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.08))
	# Not through a freeway deck (see _add_tree). After the rolls, so the rng stream is the same.
	if _under_freeway(Vector2(at.x, at.z), PALM_FREEWAY_MARGIN):
		return
	_batch.add("palm_%d" % variant, PropFactory.palm(variant), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint)
	if collide:
		_add_shape(Vector3(0.5, 9.0 * s, 0.5), at + Vector3(0.0, 4.5 * s, 0.0))


func _add_lifeguard_tower(at: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	for dx: float in [-1.2, 1.2]:
		for dz: float in [-1.2, 1.2]:
			_batch.add("lifeguard_leg", PropFactory.lifeguard_leg(), Transform3D(basis, at + basis * Vector3(dx, 1.3, dz)))
	_batch.add("lifeguard_cabin", PropFactory.lifeguard_cabin(), Transform3D(basis, at + Vector3(0.0, 3.8, 0.0)))
	_batch.add("lifeguard_ramp", PropFactory.lifeguard_ramp(), Transform3D(basis * Basis(Vector3.RIGHT, -0.55), at + basis * Vector3(0.0, 1.3, 3.2)))
	_add_shape(Vector3(3.0, 5.0, 3.0), at + Vector3(0.0, 2.5, 0.0), yaw)


## Terrain tile over the whole owned area, colored by height, with heightmap collision.
## The terrain tile's heights and drainage, sampled a few rows a call (a build step that runs
## again until it is done): a height in the eroded mountains costs 20-40 us here, and a FULL
## tile's 1,089-2,401 of them in one step was a 30-90 ms frame whenever a hill chunk streamed in.
var _tile_n: int = 0
var _tile_row: int = 0
var _tile_heights := PackedFloat32Array()
var _tile_drains := PackedFloat32Array()
## Microseconds of sampling a call takes before it hands the frame back.
const TERRAIN_SAMPLE_BUDGET_US := 2500


func _sample_terrain() -> bool:
	var area := owned_rect()
	if _tile_heights.is_empty():
		# Finer tile where a hill road passes, so the carved road bed reads cleanly. The whole
		# grid is several times what it was: a ridge is read as a silhouette against the sky and
		# an eight-metre quad gives a mountain a faceted, folded-paper edge no shading can hide.
		var has_road := _hill_segments().size() > 0
		_tile_n = (terrain_subdiv_road if has_road else terrain_subdiv) if level == Level.FULL else terrain_subdiv_lod
		_tile_heights.resize((_tile_n + 1) * (_tile_n + 1))
		_tile_drains.resize((_tile_n + 1) * (_tile_n + 1))
		_tile_row = 0
	var n := _tile_n
	var t0 := Time.get_ticks_usec()
	while _tile_row <= n:
		var j := _tile_row
		for i in n + 1:
			var x := area.position.x + area.size.x * i / n
			var z := area.position.y + area.size.y * j / n
			_tile_heights[j * (n + 1) + i] = plan.height_at(Vector2(x, z))
			# The drainage the height_at() just above left (MacroMap.last_drain).
			_tile_drains[j * (n + 1) + i] = plan.macro.last_drain if plan.macro else 0.0
		_tile_row += 1
		if Time.get_ticks_usec() - t0 > TERRAIN_SAMPLE_BUDGET_US:
			break
	return _tile_row > n


func _build_terrain() -> void:
	# Its heights come from _sample_terrain, a step of its own before it; run it here if a
	# caller only listed this one.
	if _tile_heights.is_empty() or _tile_row <= _tile_n:
		while not _sample_terrain():
			pass
	var area := owned_rect()
	var n := _tile_n
	var heights := _tile_heights
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n + 1:
		for i in n + 1:
			var x := area.position.x + area.size.x * i / n
			var z := area.position.y + area.size.y * j / n
			var h := heights[j * (n + 1) + i]
			# COLOR.r is the height (0..1 over 40..940 m), COLOR.g the drainage the height field
			# was cut with (0 a spur's crest, 0.5 open slope, 1 a gully's line), which
			# terrain.gdshader paints brush, scree and rock from - the same field HillPlanting
			# plants by.
			var t := clampf((h - 40.0) / 900.0, 0.0, 1.0)
			# COLOR.b is where the hill shells may grow (hill_shells.gdshader): 0.5 at the edge
			# of a road, pad or landmark (_mark_shell_ground), over it outside. A distance, so
			# the edge interpolates straight across a quad.
			var keep := 0.0
			if not _shell_clear.is_empty():
				keep = clampf(0.5 + _shell_clear[j * (n + 1) + i] / (2.0 * SHELL_CLEAR_SPAN), 0.0, 1.0)
				_shell_any = _shell_any or (keep > 0.5 and h > 1.5)
			st.set_color(Color(t, _tile_drains[j * (n + 1) + i] * 0.5 + 0.5, keep, 1.0))
			st.add_vertex(Vector3(x, h, z))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + (n + 1)
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	# Kept for the planting, which reads slopes and hollows off the very surface drawn.
	_terrain_grid = {"heights": heights, "drains": _tile_drains, "n": n, "area": area}
	var mesh := MeshInstance3D.new()
	mesh.name = "Terrain"
	mesh.mesh = st.commit()
	# The shells (_build_hill_shells) draw this very mesh again.
	_terrain_mesh = mesh.mesh
	mesh.material_override = PropFactory.terrain_material()
	add_child(mesh)
	# Collision on the same grid as the mesh, so a fast car never outruns the detailed chunks
	# and drops through a far hill, and so the ground it hits is the ground it sees. Sharing
	# the grid is also what makes the finer terrain affordable: the heights are already
	# sampled, and a HeightMapShape3D is a flat array, not a BVH. The body is tagged so the
	# player can tell "under the terrain" from "under a bridge".
	var cn := n
	var cheights := heights
	if n != cn:
		cheights = PackedFloat32Array()
		cheights.resize((cn + 1) * (cn + 1))
		for j in cn + 1:
			for i in cn + 1:
				cheights[j * (cn + 1) + i] = plan.height_at(Vector2(area.position.x + area.size.x * i / cn, area.position.y + area.size.y * j / cn))
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1 | TERRAIN_LAYER
	body.collision_mask = 0
	body.set_meta("terrain", true)
	var shape := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = cn + 1
	hm.map_depth = cn + 1
	hm.map_data = cheights
	shape.shape = hm
	var c := area.get_center()
	shape.transform = Transform3D(Basis().scaled(Vector3(area.size.x / cn, 1.0, area.size.y / cn)), Vector3(c.x, 0.0, c.y))
	body.add_child(shape)
	add_child(body)


func _hill_segments() -> Array[Dictionary]:
	if plan.macro == null or plan.macro.hill_roads == null:
		return []
	var segs: Array[Dictionary] = plan.macro.hill_roads.segments_in(owned_rect())
	# The coast highway's bridge over the marina's channel replaces its strip there (MarinaBuild).
	return MarinaBuild.filter_segments(self, segs)


## Asphalt strips following the carved road beds, clipped to this chunk.
## Boulders, shrubs, dry scrub and grass tufts over a hill chunk, kept off the roads and the
## mansion pads. Rocks prefer steep ground and get collision. Heights come off the tile's own
## grid (_terrain_height), the surface drawn and collided with: MacroMap.height_at() is 20-40 us
## in the eroded hills and this step asked it about a thousand times - a 60 ms frame every time
## a hill chunk streamed in - and it is not the surface drawn anyway (a rock on the exact
## height could stand a metre proud of the 3 m grid's face, or sink into it).
## A build step that runs again until done, SCATTER_PER_STEP tries a call, the same one random
## stream throughout (kept in _scatter_rng), so it scatters exactly what it did in one go.
func _scatter_hills() -> bool:
	if level != Level.FULL:
		return true
	var area := owned_rect()
	if _scatter_rng == null:
		_scatter_rng = RandomNumberGenerator.new()
		_scatter_rng.seed = hash([plan.seed, ix, iz, "hills"])
		_scatter_left = _scatter_rng.randi_range(hill_scatter_min, hill_scatter_max)
	var rng := _scatter_rng
	var segs := _hill_segments()
	var pads := plan.macro.hill_roads.mansions_in(area.grow(HillRoads.PAD_RADIUS + 6.0))
	var tries := mini(_scatter_left, SCATTER_PER_STEP)
	_scatter_left -= tries
	for i in tries:
		var p := Vector2(rng.randf_range(area.position.x + 1.0, area.end.x - 1.0), rng.randf_range(area.position.y + 1.0, area.end.y - 1.0))
		if _near_hill_road(p, segs, 2.5) or _near_pad(p, pads, 4.0):
			continue
		var h := _terrain_height(p)
		if h < 1.5:
			continue
		# Not under the reservoir, on its bathtub ring or trail (Reservoir.keep_clear()).
		if plan.macro.reservoir and plan.macro.reservoir.keep_clear(p, h):
			continue
		var hx := _terrain_height(p + Vector2(1.0, 0.0)) - _terrain_height(p - Vector2(1.0, 0.0))
		var hz := _terrain_height(p + Vector2(0.0, 1.0)) - _terrain_height(p - Vector2(0.0, 1.0))
		var slope := Vector2(hx, hz).length() * 0.5
		var at := Vector3(p.x, h, p.y)
		var yaw := rng.randf_range(0.0, TAU)
		var roll := rng.randf()
		if (slope > 0.35 and roll < 0.45) or roll < 0.08:
			var v := rng.randi() % 2
			var sc := rng.randf_range(0.6, 1.7)
			var tilt := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
			_batch.add("rock_%d" % v, PropFactory.model_rock(v), Transform3D(tilt.scaled(Vector3(sc, sc, sc)), at - Vector3(0.0, 0.15 * sc, 0.0)))
			var size := (Vector3(2.4, 0.8, 1.2) if v == 0 else Vector3(2.4, 1.8, 2.4)) * sc
			_add_shape(size, at + Vector3(0.0, size.y * 0.5 - 0.15 * sc, 0.0), yaw)
		elif roll < 0.38:
			var v := rng.randi() % 4
			var sc := rng.randf_range(0.6, 1.2)
			var tint := Color(rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.0), rng.randf_range(0.7, 0.9))
			_batch.add("shrub_%d" % v, PropFactory.model_shrub(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), at - Vector3(0.0, 0.05, 0.0)), tint)
		elif roll < 0.62:
			var v := rng.randi() % 5
			var sc := rng.randf_range(1.3, 2.4)
			_batch.add("scrub_%d" % v, PropFactory.model_scrub(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), at - Vector3(0.0, 0.03, 0.0)), Color(rng.randf_range(0.9, 1.1), rng.randf_range(0.9, 1.05), rng.randf_range(0.85, 1.0)))
		else:
			for k in rng.randi_range(3, 7):
				var q := p + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
				if _near_hill_road(q, segs, 1.5) or _near_pad(q, pads, 3.0):
					continue
				var v := rng.randi() % 5
				var sc := rng.randf_range(1.4, 2.6)
				var tint := Color(rng.randf_range(0.95, 1.1), rng.randf_range(0.9, 1.05), rng.randf_range(0.7, 0.9))
				_batch.add("tuft_%d" % v, PropFactory.model_grass_tuft(v), Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sc, sc, sc)), Vector3(q.x, _terrain_height(q) - 0.02, q.y)), tint)
	if _scatter_left > 0:
		return false
	for v in 5:
		_batch.set_no_shadow("tuft_%d" % v)
		_batch.set_no_shadow("scrub_%d" % v)
	return true


## _scatter_hills' random stream and the tries it has left; tries per build step (~4 ms of
## rocks with their collision shapes, shrubs and tuft clusters on a slow machine).
var _scatter_rng: RandomNumberGenerator = null
var _scatter_left: int = 0
const SCATTER_PER_STEP := 60


## Metres of clearance the shells' per-vertex keep-out distance (the terrain's COLOR.b) spans
## each side of the edge of a road, pad or landmark.
const SHELL_CLEAR_SPAN := 4.0
## False on the web, and below MEDIUM (Quality): no shells are built, and the built ones hide.
static var shells_enabled: bool = not OS.has_feature("web")
## Where _mark_shell_ground has got to: the obstacles still to mark, the clearance so far (signed
## metres per tile vertex, positive where shells may grow), and whether any vertex is clear.
var _shell_todo: Array = []
var _shell_clear := PackedFloat32Array()
var _shell_marked: bool = false
var _shell_any: bool = false
## The terrain tile's mesh (_build_terrain), which the shells draw again.
var _terrain_mesh: Mesh = null
## The shells' node, when built.
var hill_shell_node: HillShells = null
## Microseconds of obstacle marking a call does before it hands the frame back.
const SHELL_MARK_BUDGET_US := 2000
## Landmarks the shells grow round as usual: the ridge letters stand on legs two metres and more
## over the slope, and that landmark's 400 m radius is the lots it reserves, not built ground.
const SHELL_FREE_LANDMARKS := ["sign"]


## Where the shells must not grow round this tile: a hill road and its shoulder, a mansion pad,
## a landmark's ground ([a, b, reach]: a segment, or a point when a == b, and how far round it).
func _shell_marks(area: Rect2) -> Array:
	var marks: Array = []
	for seg in _hill_segments():
		marks.append([seg.a, seg.b, float(seg.width) * 0.5 + shell_road_margin])
	if plan.macro and plan.macro.hill_roads:
		for m in plan.macro.hill_roads.mansions_in(area.grow(HillRoads.PAD_RADIUS + SHELL_CLEAR_SPAN + shell_pad_margin)):
			marks.append([m.pos, m.pos, HillRoads.PAD_RADIUS + shell_pad_margin])
	for lm in Landmarks.all():
		var r: float = float(lm.get("radius", 0.0))
		var at: Vector2 = lm.anchor
		if r > 0.0 and not SHELL_FREE_LANDMARKS.has(lm.id) and area.grow(r + SHELL_CLEAR_SPAN).has_point(at):
			marks.append([at, at, r])
	marks.append_array(Ballpark.shell_marks(area))
	# The reservoir's shore, bathtub ring, trail, dam and spillway (Reservoir.shell_marks()).
	if plan.macro and plan.macro.reservoir:
		marks.append_array(plan.macro.reservoir.shell_marks(area.grow(SHELL_CLEAR_SPAN + 12.0)))
	return marks


## Lowers `clear` (per tile vertex) round one obstacle: only the vertices within its reach and
## SHELL_CLEAR_SPAN are visited. The same vertex positions _build_terrain lays.
func _shell_clear_mark(clear: PackedFloat32Array, mark: Array, n: int, area: Rect2) -> void:
	var cell := area.size / float(n)
	var a: Vector2 = mark[0]
	var b: Vector2 = mark[1]
	var reach: float = mark[2]
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (reach + SHELL_CLEAR_SPAN)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (reach + SHELL_CLEAR_SPAN)
	var i0 := clampi(floori((lo.x - area.position.x) / cell.x), 0, n)
	var i1 := clampi(ceili((hi.x - area.position.x) / cell.x), 0, n)
	var j0 := clampi(floori((lo.y - area.position.y) / cell.y), 0, n)
	var j1 := clampi(ceili((hi.y - area.position.y) / cell.y), 0, n)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector2(area.position.x + area.size.x * i / n, area.position.y + area.size.y * j / n)
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) - reach
			var k := j * (n + 1) + i
			if d < clear[k]:
				clear[k] = d


## The shells' keep-out, a build step between the tile's heights and its mesh (which carries it
## in COLOR.b), a few obstacles a call. Nothing random.
func _mark_shell_ground() -> bool:
	if level != Level.FULL or capturing or not shells_enabled:
		return true
	var area := owned_rect()
	var n := _tile_n
	if not _shell_marked:
		_shell_marked = true
		# A replica area's hill route lays its own road, walks and walls over the tile
		# (ReplicaBuilder); the painted ground is left as it is there.
		if ReplicaBuilder.wanted(self):
			return true
		_shell_clear.resize((n + 1) * (n + 1))
		_shell_clear.fill(SHELL_CLEAR_SPAN)
		_shell_todo = _shell_marks(area)
	var t0 := Time.get_ticks_usec()
	while not _shell_todo.is_empty() and Time.get_ticks_usec() - t0 < SHELL_MARK_BUDGET_US:
		_shell_clear_mark(_shell_clear, _shell_todo.pop_back(), n, area)
	return _shell_todo.is_empty()


## The tile drawn again HillShells.LAYERS times as thin lifted layers (hill_shells.gdshader):
## the dry grass and the brush understory grow out of the ground the terrain shader paints.
## It is the terrain's own mesh in a MultiMesh of one identity instance per layer (the layer's
## height in the instance's custom data), so it costs no vertex or index memory and a few
## microseconds to build; HillShells draws fewer layers as the camera moves away. No rng.
func _build_hill_shells() -> void:
	if level != Level.FULL or capturing or not shells_enabled or _terrain_mesh == null or not _shell_any:
		return
	var lo := INF
	var hi := -INF
	for h in _tile_heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	hill_shell_node = HillShells.make(_terrain_mesh, owned_rect(), lo, hi)
	add_child(hill_shell_node)


## The terrain tile's heights ({"heights", "n", "area"}, _build_terrain) for the planting.
var _terrain_grid: Dictionary = {}
## Where _plant_hills has got to (grid rows done) and what it has planted: kind -> count, and
## "points" [Vector2 world XZ, kind] for the checks.
var _plant_row: int = 0
var hill_planting: Dictionary = {}
## Grid rows _plant_hills does per build step (a row is ~20 points, about 1 ms on a slow machine).
const PLANT_ROWS_PER_STEP := 3


## The drawn terrain's height at `p` (true world XZ): the tile's own grid, bilinear, or the map
## off the tile.
func _terrain_height(p: Vector2, field: String = "heights") -> float:
	if _terrain_grid.is_empty():
		return plan.height_at(p) if field == "heights" else plan.macro.drainage_at(p)
	var area: Rect2 = _terrain_grid.area
	var n: int = _terrain_grid.n
	var u := (p.x - area.position.x) / area.size.x * n
	var v := (p.y - area.position.y) / area.size.y * n
	if u < 0.0 or v < 0.0 or u > n or v > n:
		return plan.height_at(p) if field == "heights" else plan.macro.drainage_at(p)
	var i := mini(int(u), n - 1)
	var j := mini(int(v), n - 1)
	var fu := u - i
	var fv := v - j
	var h: PackedFloat32Array = _terrain_grid[field]
	var a := h[j * (n + 1) + i]
	var b := h[j * (n + 1) + i + 1]
	var c := h[(j + 1) * (n + 1) + i]
	var d := h[(j + 1) * (n + 1) + i + 1]
	return lerpf(lerpf(a, b, fu), lerpf(c, d, fu), fv)


## Chaparral stands, oaks in the hollows, lone shrubs on the grass: a jittered grid over a FULL
## hill chunk, each point planted by what the terrain shader paints there (HillPlanting), so the
## shrubs stand on the painted brush, thickest on the north faces, and nothing grows on the rock
## or the bare cuts. A private random stream (never the chunk's), a few grid rows a build step.
func _plant_hills() -> bool:
	if level != Level.FULL or capturing:
		return true
	var area := owned_rect()
	var step := hill_brush_spacing
	var nx := maxi(1, int(area.size.x / step))
	var nz := maxi(1, int(area.size.y / step))
	if _plant_row == 0:
		hill_planting = {"chaparral": 0, "oak": 0, "sage": 0, "points": []}
	var segs := _hill_segments()
	var pads := plan.macro.hill_roads.mansions_in(area.grow(HillRoads.PAD_RADIUS + 6.0))
	var height := Callable(self, "_terrain_height")
	var chap := PropFactory.model_chaparral()
	var chap_h := PropFactory.chaparral_height()
	var points: Array = hill_planting.points
	var stop := mini(nz, _plant_row + PLANT_ROWS_PER_STEP)
	for j in range(_plant_row, stop):
		# One stream per row, so a row plants the same whatever step it lands in.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([plan.seed, ix, iz, "hill_planting", j])
		for i in nx:
			var p := area.position + Vector2((i + rng.randf_range(0.1, 0.9)) * area.size.x / nx, (j + rng.randf_range(0.1, 0.9)) * area.size.y / nz)
			var roll := rng.randf()
			var yaw := rng.randf_range(0.0, TAU)
			var size := rng.randf()
			var tone := rng.randf()
			if _near_hill_road(p, segs, 3.0) or _near_pad(p, pads, 5.0):
				continue
			var h := _terrain_height(p)
			if h < 1.5:
				continue
			if plan.macro.reservoir and plan.macro.reservoir.keep_clear(p, h):
				continue
			var grad := Vector2(_terrain_height(p + Vector2(2.0, 0.0)) - _terrain_height(p - Vector2(2.0, 0.0)),
				_terrain_height(p + Vector2(0.0, 2.0)) - _terrain_height(p - Vector2(0.0, 2.0))) * 0.25
			# The drainage off the tile's own grid, as the shader gets it through the vertex colour.
			var g := HillPlanting.ground(p, grad, true, _terrain_height(p, "drains"))
			# Nothing on the rock or the bare cuts and trails.
			if float(g.rocky) > 0.3 or float(g.bare) > 0.4:
				continue
			var hollow := HillPlanting.hollow(p, h, 14.0, height)
			var wet := clampf((hollow - hill_oak_hollow) / (hill_oak_hollow * 2.0), 0.0, 1.0)
			var at := Vector3(p.x, h, p.y)
			if wet > 0.0 and float(g.slope) < 0.4 and roll < hill_oak_chance * wet:
				var v := int(tone * 10.0) % PropFactory.HILL_OAKS.size()
				var s := lerpf(hill_oak_height.x, hill_oak_height.y, size) / PropFactory.hill_oak_height(v)
				# Dark, glossy evergreen oak green. Over 1: the leaf atlas is three quarters black
				# background, which the mip chain averages into the leaves, so at a few tens of
				# metres a canopy tinted below 1 drew as a black hole in the hillside.
				var tint := Color(1.35, 1.4, 0.85).lerp(Color(1.6, 1.62, 1.0), tone)
				var variety := Color(rng.randf(), rng.randf(), rng.randf_range(0.0, 0.5), 0.0)
				# A California sycamore in the wettest hollows (LaTrees, hashes only).
				if not LaTrees.gully_tree(self, at - Vector3(0.0, 0.1, 0.0), yaw, wet):
					_batch.add("hill_oak_%d" % v, PropFactory.model_hill_oak(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at - Vector3(0.0, 0.1, 0.0)), tint, variety)
				hill_planting.oak += 1
				points.append([p, "oak"])
				continue
			# Hollows carry the brush thicker, on any face.
			var brush := clampf(float(g.brush) + wet * 0.3, 0.0, 1.0)
			if brush > 0.5 and roll < hill_brush_fill:
				# Wide and low, leaning into the slope a little, buried at the downhill edge.
				var s := lerpf(hill_brush_height.x, hill_brush_height.y, size * size) / chap_h
				var up := Vector3(-grad.x, 1.0, -grad.y).normalized().lerp(Vector3.UP, 0.6).normalized()
				var tilt := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw)
				# Dark olive, warmer than the scan's sage-green leaves (which read blue-grey on a hill),
				# and over 1 for the same reason as the oaks: the searsia's leaves are small sprites
				# on a black atlas, and at 0.8 a stand was black from twenty metres.
				var tint := Color(1.75, 1.7, 1.05).lerp(Color(2.15, 2.05, 1.3), tone)
				# Few leaves thinned out: a stand is dense. Half as wide again as tall, so the shrubs of
				# a stand close up into one mass at no extra triangles (at 1.15 they stood apart as dots).
				var variety := Color(rng.randf() * 0.3, rng.randf(), rng.randf(), 0.0)
				_batch.add("hill_chaparral", chap, Transform3D(tilt.scaled(Vector3(s * 1.45, s, s * 1.45)), at - Vector3(0.0, 0.2 + float(g.slope) * 1.5, 0.0)), tint, variety)
				hill_planting.chaparral += 1
				points.append([p, "chaparral"])
			elif brush < 0.35 and roll > 1.0 - hill_sage_chance:
				# A lone grey-green shrub out on the straw.
				var s := lerpf(1.0, 1.7, size) / chap_h
				var tint := Color(1.9, 1.95, 1.6)
				_batch.add("hill_chaparral", chap, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s * 1.1, s, s * 1.1)), at - Vector3(0.0, 0.15, 0.0)), tint, Color(rng.randf(), rng.randf(), 0.8, 0.0))
				hill_planting.sage += 1
				points.append([p, "sage"])
	_plant_row = stop
	if _plant_row < nz:
		return false
	# The stands cast no shadow: a hundred-odd shrubs a block went into every cascade, and the
	# painted brush under them is already the shade between the bushes. The oaks, a few a
	# block, keep theirs.
	_batch.set_no_shadow("hill_chaparral")
	_batch.set_draw_distance("hill_chaparral", hill_brush_distance)
	return true


## A lawn tint, from watered green to burnt tan. The old range was all lush, so from the air
## every block was the same bright rectangle of astroturf; on a Californian street about a third
## of the front yards have given up by August.
func _lawn_color(rng: RandomNumberGenerator) -> Color:
	var dry := rng.randf()
	if dry < 0.34:
		# Burnt off: straw over dust.
		return Color(rng.randf_range(0.95, 1.12), rng.randf_range(0.82, 0.94), rng.randf_range(0.48, 0.62))
	if dry < 0.62:
		# Patchy.
		return Color(rng.randf_range(0.86, 0.99), rng.randf_range(0.88, 0.98), rng.randf_range(0.58, 0.72))
	return Color(rng.randf_range(0.74, 0.90), rng.randf_range(0.90, 1.0), rng.randf_range(0.66, 0.80))


func _near_hill_road(p: Vector2, segs: Array[Dictionary], margin: float) -> bool:
	for seg in segs:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
		if p.distance_to(closest) < (seg.width as float) * 0.5 + margin:
			return true
	return false


func _near_pad(p: Vector2, pads: Array[Dictionary], margin: float) -> bool:
	if Ballpark.covers(p, margin):
		return true
	for m in pads:
		if p.distance_to(m.pos) < HillRoads.PAD_RADIUS + margin:
			return true
	return false


func _build_hill_roads() -> void:
	var segs := _hill_segments()
	if segs.is_empty():
		return
	var area := owned_rect()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	for seg in segs:
		# The replica's hill route is carved here but drawn by ReplicaBuilder, markings and all;
		# an estate's driveway is carved as a road and drawn with its estate (_build_mansions).
		if not seg.get("draw", true) or seg.get("drive", false):
			continue
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var seg_len := a.distance_to(b)
		if seg_len < 0.5:
			continue
		var pieces := maxi(1, ceili(seg_len / 6.0))
		var dir := (b - a) / seg_len
		var half: float = seg.width * 0.5
		# The edges are mitred at the segment's ends (HillRoads._mitre()), so the strip turns a
		# bend - a hairpin's 30 degrees a piece - without wedges missing from its outside.
		var na: Vector2 = seg.get("na", Vector2(-dir.y, dir.x)) * half
		var nb: Vector2 = seg.get("nb", Vector2(-dir.y, dir.x)) * half
		# Each edge vertex sits on the carved ground under it, not level with the centre line: where
		# a drive leaves its parent the two strips overlap, and level across each they stood at two
		# heights with a step between. Consecutive pieces share their edge heights.
		var prev_end := Vector2(NAN, NAN)
		for k in pieces:
			var t0 := float(k) / pieces
			var t1 := float(k + 1) / pieces
			var c0 := a.lerp(b, t0)
			var c1 := a.lerp(b, t1)
			if not area.has_point(c0.lerp(c1, 0.5)):
				prev_end = Vector2(NAN, NAN)
				continue
			var n0 := na.lerp(nb, t0)
			var n1 := na.lerp(nb, t1)
			# 0.26 rather than a hair over the ground: the beach lays a 0.4 m sand slab centred
			# on zero, so its surface is at 0.2, and the coast highway crossing a beach town
			# would otherwise be buried in it for the length of the sand.
			var e0 := prev_end
			if is_nan(e0.x):
				e0 = Vector2(plan.height_at(c0 - n0), plan.height_at(c0 + n0)) + Vector2.ONE * 0.26
			var e1 := Vector2(plan.height_at(c1 - n1), plan.height_at(c1 + n1)) + Vector2.ONE * 0.26
			prev_end = e1
			var v0 := Vector3(c0.x - n0.x, e0.x, c0.y - n0.y)
			var v1 := Vector3(c0.x + n0.x, e0.y, c0.y + n0.y)
			var v2 := Vector3(c1.x + n1.x, e1.y, c1.y + n1.y)
			var v3 := Vector3(c1.x - n1.x, e1.x, c1.y - n1.y)
			for v in [v0, v2, v1, v0, v3, v2]:
				st.add_vertex(v)
			quads += 1
	if quads == 0:
		return
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "HillRoad"
	mesh.mesh = st.commit()
	mesh.material_override = PropFactory.pbr("asphalt", 7.0, Color(0.79, 0.79, 0.81))
	add_child(mesh)


## Hillside estates (the Hollywood Hills / Palisades look): a graded pad with a stucco villa on
## its back half, a pool beside it, a paved motor court at the front, a driveway from the road
## with a gate between two piers, and round the pad a wall that is whatever the ground makes it -
## a low garden wall where the pad is level with the hillside, a retaining wall holding the cut
## bank back where the hillside stands above it, and a tall one dropping down the fill where the
## pad stands out over the slope. The pad, walls, piers, gate, rim and water go into the chunk's
## merged boxes (one mesh per material), the driveway into one strip a chunk, so an estate costs
## its house and its palms in draw calls.
func _build_mansions() -> void:
	if plan.macro == null or plan.macro.hill_roads == null:
		return
	var drive_st := SurfaceTool.new()
	drive_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drives := 0
	for m in plan.macro.hill_roads.mansions_in(owned_rect()):
		if HillHomeKit.enabled:
			# The house, its pad, walls and site (HillHomeKit); the driveway is drawn here.
			var gate_at := HillHomeKit.build(self, m)
			if level != Level.FULL and not capturing and EstateFar.enabled:
				# Its garden, court, pool glow and lamps on the same plan (EstateFar), one batch.
				for part: Array in EstateFar.parts(plan, m, true):
					_batch.add("estate_far", EstateFar.mesh(), part[0], part[1], part[2])
				# Its lamps grow with distance in the vertex shader: no shadow pass.
				_batch.set_no_shadow("estate_far")
			var drive_from: Vector2 = m.get("drive_from", m.pos)
			if level == Level.FULL and drive_from.distance_to(gate_at) > 1.0:
				_drive_strip(drive_st, drive_from, gate_at, ESTATE_DRIVE_WIDTH)
				drives += 1
			continue
		var pos: Vector2 = m.pos
		var h: float = m.height
		var yaw: float = m.yaw
		var rng := RandomNumberGenerator.new()
		rng.seed = m.seed
		var basis := Basis(Vector3.UP, yaw)
		var at := Vector3(pos.x, h, pos.y)
		if level != Level.FULL and EstateFar.enabled:
			# Far: the estate's parts and lamps (EstateFar) on the real terrain, one batch.
			for part: Array in EstateFar.parts(plan, m, true):
				_batch.add("estate_far", EstateFar.mesh(), part[0], part[1], part[2])
			# Its lamps grow with distance in the vertex shader: no shadow pass.
			_batch.set_no_shadow("estate_far")
			continue
		var pad_mat := PropFactory.pbr("pavers", 3.0, Color(0.93, 0.9, 0.85))
		_merge_box_xf(pad_mat, Transform3D(basis.scaled_local(ESTATE_PAD), at + Vector3(0.0, ESTATE_PAD.y * 0.5, 0.0)))
		if level != Level.FULL:
			# Far: the pad, the house as a box in a warm tone, the pool.
			_batch.add("lod_box", PropFactory.unit_box(), Transform3D(basis.scaled_local(Vector3(18.0, 7.5, 13.0)), at + basis * Vector3(0.0, 4.15, -4.0)), Color(0.92, 0.88, 0.8))
			continue
		_add_shape(ESTATE_PAD, at + Vector3(0.0, ESTATE_PAD.y * 0.5, 0.0), yaw)
		var top := h + ESTATE_PAD.y
		if EstateFar.enabled:
			# The garden: lawn down both sides of the motor court and behind the house, as the far
			# estates (EstateFar) draw it, so the paving is the court and not the whole pad.
			for piece: Array in EstateFar.LAWN_PIECES:
				_merge_box_xf(PropFactory.lawn(Color(0.36, 0.48, 0.24), 6173, 0.4, 0.0), Transform3D(basis.scaled_local(piece[1]), at + basis * (piece[0] as Vector3) + Vector3(0.0, ESTATE_PAD.y, 0.0)))
		# House: a wide low villa on the back half of the pad.
		var house := BUILDING_SCENE.instantiate() as Building
		house.seed = m.seed
		house.lot_size = Vector2(18.0, 13.0)
		house.min_height = 6.5
		house.max_height = 9.5
		house.force_shape = Building.Shape.SLAB
		# Rendered stucco mostly, now and then brick, as up in the canyons.
		house.finish_options.assign([Building.Finish.FLAT, Building.Finish.FLAT, Building.Finish.FLAT, Building.Finish.BRICK])
		house.allow_storefront = false
		house.lit_ratio_range = Vector2(0.3, 0.6)
		house.position = at + basis * Vector3(0.0, ESTATE_PAD.y, -4.0)
		house.rotation.y = yaw
		add_child(house)
		building_count += 1
		# Pool on the front half, to one side of the motor court, with a pale coping.
		var pool_x := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(5.0, 6.5)
		var pool_c := at + basis * Vector3(pool_x, ESTATE_PAD.y, 6.0)
		_merge_box_xf(PropFactory.material(Color(0.93, 0.92, 0.88), 0.8), Transform3D(basis.scaled_local(Vector3(6.4, 0.12, 8.4)), pool_c + Vector3(0.0, 0.06, 0.0)))
		_merge_box_xf(_pool_water(), Transform3D(basis.scaled_local(Vector3(5.4, 0.1, 7.4)), pool_c + Vector3(0.0, 0.13, 0.0)))
		# Walls round the pad, by what the ground does beyond each side.
		var wall_kind := rng.randi() % 3
		var stucco := PropFactory.material(ESTATE_STUCCO[rng.randi() % ESTATE_STUCCO.size()], 0.9)
		var retain: Material = PropFactory.pbr("rock", 2.5, Color(0.85, 0.8, 0.74)) if wall_kind == 0 else PropFactory.pbr("concrete", 3.0, Color(0.9, 0.88, 0.84))
		var hx := ESTATE_PAD.x * 0.5
		var hz := ESTATE_PAD.z * 0.5
		var gate_gap := 5.2
		# [centre (local), length, along x?, outward normal (local)]
		var sides := [[Vector3(0.0, 0.0, -hz), ESTATE_PAD.x, true, Vector3(0, 0, -1)], [Vector3(hx, 0.0, 0.0), ESTATE_PAD.z, false, Vector3(1, 0, 0)],
			[Vector3(-hx, 0.0, 0.0), ESTATE_PAD.z, false, Vector3(-1, 0, 0)]]
		# The front wall stands either side of the gate.
		var half_front := (ESTATE_PAD.x - gate_gap) * 0.5
		sides.append([Vector3(-(gate_gap * 0.5 + half_front * 0.5), 0.0, hz), half_front, true, Vector3(0, 0, 1)])
		sides.append([Vector3(gate_gap * 0.5 + half_front * 0.5, 0.0, hz), half_front, true, Vector3(0, 0, 1)])
		for sd: Array in sides:
			var c: Vector3 = sd[0]
			var length: float = sd[1]
			var along_x: bool = sd[2]
			var outward: Vector3 = sd[3]
			# The ground just beyond the side: its middle and both ends, the highest and lowest.
			var tang := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
			var hi := -INF
			var lo := INF
			for f: float in [-0.45, 0.0, 0.45]:
				var q := at + basis * (c + outward * 2.5 + tang * length * f)
				var gq := plan.height_at(Vector2(q.x, q.z))
				hi = maxf(hi, gq)
				lo = minf(lo, gq)
			var thick := 0.5
			var mat: Material = stucco
			var y0 := top
			var y1 := top + 1.1
			if hi - top > 1.2:
				# Cut: a retaining wall holding the bank back, up to the ground behind it.
				mat = retain
				y1 = top + clampf(hi - top + 0.4, 1.4, 4.5)
				thick = 0.7
			elif top - lo > 1.2:
				# Fill: the wall runs down the bank below the pad, its top a parapet.
				mat = retain
				y0 = top - clampf(top - lo + 1.5, 2.0, 8.0)
				y1 = top + 1.0
				thick = 0.7
			var size := Vector3(length, y1 - y0, thick) if along_x else Vector3(thick, y1 - y0, length)
			var wpos := at + basis * (c - outward * thick * 0.5)
			wpos.y = (y0 + y1) * 0.5
			_merge_box_xf(mat, Transform3D(basis.scaled_local(size), wpos))
			_add_shape(size, wpos, yaw)
			# A coping on the stucco and retaining walls alike.
			var cap := Vector3(size.x + 0.1, 0.08, size.z + 0.1)
			_merge_box_xf(PropFactory.material(Color(0.88, 0.86, 0.82), 0.8), Transform3D(basis.scaled_local(cap), Vector3(wpos.x, y1 + 0.04, wpos.z)))
		# Gate piers and the gate, across the drive.
		for sx: float in [-1.0, 1.0]:
			var pier := at + basis * Vector3(sx * (gate_gap * 0.5 + 0.35), 0.0, hz - 0.35)
			pier.y = top + 1.2
			_merge_box_xf(stucco, Transform3D(basis.scaled_local(Vector3(0.75, 2.4, 0.75)), pier))
			_merge_box_xf(PropFactory.material(Color(0.88, 0.86, 0.82), 0.8), Transform3D(basis.scaled_local(Vector3(0.9, 0.1, 0.9)), pier + Vector3(0.0, 1.25, 0.0)))
			_add_shape(Vector3(0.75, 2.4, 0.75), pier, yaw)
		var gate := at + basis * Vector3(0.0, 0.0, hz - 0.35)
		gate.y = top + 0.95
		_merge_box_xf(ESTATE_GATE_MATERIAL(), Transform3D(basis.scaled_local(Vector3(gate_gap - 0.1, 1.7, 0.08)), gate))
		_add_shape(Vector3(gate_gap - 0.1, 1.7, 0.08), gate, yaw)
		# The driveway: from the road's edge to the gate, laid on the graded ground.
		var from: Vector2 = m.get("drive_from", pos)
		var gate2 := Vector2(gate.x, gate.z) + Vector2(basis.z.x, basis.z.z) * 0.4
		if from.distance_to(gate2) > 1.0:
			_drive_strip(drive_st, from, gate2, ESTATE_DRIVE_WIDTH)
			drives += 1
		for i in rng.randi_range(2, 4):
			var local := Vector3(rng.randf_range(-11.0, 11.0), ESTATE_PAD.y, rng.randf_range(-10.0, -9.0) if rng.randf() < 0.5 else rng.randf_range(2.0, 3.0))
			_add_palm(at + basis * local, rng)
	if drives > 0:
		drive_st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "Driveways"
		mi.mesh = drive_st.commit()
		mi.material_override = PropFactory.pbr("concrete", 4.0, Color(0.86, 0.85, 0.82))
		add_child(mi)


## An estate's pad (x across, z toward the road), its driveway's width, the walls' paints.
const ESTATE_PAD := Vector3(26.0, 0.4, 22.0)
const ESTATE_DRIVE_WIDTH := 4.4
const ESTATE_STUCCO: Array[Color] = [Color(0.94, 0.92, 0.87), Color(0.9, 0.86, 0.78), Color(0.95, 0.94, 0.92), Color(0.84, 0.78, 0.68)]
static var _pool_water_mat: StandardMaterial3D
static var _gate_mat: StandardMaterial3D


static func _pool_water() -> StandardMaterial3D:
	if _pool_water_mat == null:
		_pool_water_mat = StandardMaterial3D.new()
		_pool_water_mat.albedo_color = Color(0.25, 0.65, 0.85)
		_pool_water_mat.roughness = 0.05
		_pool_water_mat.metallic = 0.2
	return _pool_water_mat


static func ESTATE_GATE_MATERIAL() -> StandardMaterial3D:
	if _gate_mat == null:
		_gate_mat = StandardMaterial3D.new()
		_gate_mat.albedo_color = Color(0.09, 0.09, 0.085)
		_gate_mat.roughness = 0.45
		_gate_mat.metallic = 0.8
	return _gate_mat


## A strip of driveway from `a` to `b`, `width` wide, lying 0.12 m over the carved ground.
func _drive_strip(st: SurfaceTool, a: Vector2, b: Vector2, width: float) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var n := Vector2(-dir.y, dir.x) * width * 0.5
	var pieces := maxi(1, ceili(length / 3.0))
	for k in pieces:
		var c0 := a.lerp(b, float(k) / pieces)
		var c1 := a.lerp(b, float(k + 1) / pieces)
		var h0 := plan.height_at(c0) + 0.12
		var h1 := plan.height_at(c1) + 0.12
		var v0 := Vector3(c0.x - n.x, h0, c0.y - n.y)
		var v1 := Vector3(c0.x + n.x, h0, c0.y + n.y)
		var v2 := Vector3(c1.x + n.x, h1, c1.y + n.y)
		var v3 := Vector3(c1.x - n.x, h1, c1.y - n.y)
		for v in [v0, v2, v1, v0, v3, v2]:
			st.add_vertex(v)


func has_prop(id: String) -> bool:
	for record in prop_records:
		if record.id == id:
			return true
	return false


# --- Roads -----------------------------------------------------------------------------

func _build_roads(block: Dictionary) -> void:
	var rect: Rect2 = block.rect
	var asphalt: Color = style.asphalt
	var params: Dictionary = CityPlan.DISTRICTS[block.district]
	# Vertical road on the +X side, spanning this block's Z range. Each road keeps one look
	# along its whole length (seeded by axis and index).
	var look_x := _road_look(CityPlan.AXIS_X, ix + 1, params)
	var rx := plan.road_pos(CityPlan.AXIS_X, ix + 1)
	var wx := plan.road_width(CityPlan.AXIS_X, ix + 1)
	# A road through a landmark's site is closed there (CityPlan.road_open): the landmark's own
	# ground covers it. A closed segment is closed along the whole block.
	var open_x := plan.road_open(CityPlan.AXIS_X, ix + 1, rect.get_center().y)
	if open_x:
		_road_slab(Rect2(rx - wx * 0.5, rect.position.y, wx, rect.size.y), asphalt, look_x.material)
	elif FarmersMarket.paves(plan, ix, iz, CityPlan.AXIS_X):
		# A farmers' market's street is closed to cars but still a street (FarmersMarket).
		_road_slab(Rect2(rx - wx * 0.5, rect.position.y, wx, rect.size.y), asphalt, look_x.material)
	# Horizontal road on the +Z side, spanning this block's X range.
	var look_z := _road_look(CityPlan.AXIS_Z, iz + 1, params)
	var rz := plan.road_pos(CityPlan.AXIS_Z, iz + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, iz + 1)
	var open_z := plan.road_open(CityPlan.AXIS_Z, iz + 1, rect.get_center().x)
	if open_z:
		_road_slab(Rect2(rect.position.x, rz - wz * 0.5, rect.size.x, wz), asphalt, look_z.material)
	elif FarmersMarket.paves(plan, ix, iz, CityPlan.AXIS_Z):
		_road_slab(Rect2(rect.position.x, rz - wz * 0.5, rect.size.x, wz), asphalt, look_z.material)
	# The intersection square at the +X +Z corner.
	if plan.road_open(CityPlan.AXIS_X, ix + 1, rz) or plan.road_open(CityPlan.AXIS_Z, iz + 1, rx):
		_road_slab(Rect2(rx - wx * 0.5, rz - wz * 0.5, wx, wz), asphalt, look_x.material)
	if level == Level.FULL:
		if open_x:
			_mark_road(true, rx, wx, rect.position.y, rect.end.y, look_x)
		if open_z:
			_mark_road(false, rz, wz, rect.position.x, rect.end.x, look_z)


## A road's slab over `r`, less the light rail's portal trench where it runs down the middle
## (LightRail.cuts_in(): the slab is laid round the hole in up to four pieces).
func _road_slab(r: Rect2, asphalt: Color, material: Material) -> void:
	var rail := LightRail.of(plan)
	var cuts: Array[Rect2] = []
	if rail != null and not capturing and level == Level.FULL:
		cuts = rail.cuts_in(r)
	# The freight trench too (FreightRail.cuts_in()), at FULL and LOD: it is seen from the air.
	var freight := FreightRail.of(plan)
	if freight != null and not capturing:
		cuts.append_array(freight.cuts_in(r))
	if cuts.is_empty():
		_add_slab(Vector3(r.get_center().x, ROAD_TOP * 0.5, r.get_center().y), Vector3(r.size.x, ROAD_TOP, r.size.y), asphalt, true, material)
		return
	var pieces: Array[Rect2] = [r]
	for cut in cuts:
		var hole := cut.intersection(r)
		if hole.size.x <= 0.0 or hole.size.y <= 0.0:
			continue
		var next: Array[Rect2] = []
		for q in pieces:
			var h := hole.intersection(q)
			if h.size.x <= 0.0 or h.size.y <= 0.0:
				next.append(q)
				continue
			next.append_array([
				Rect2(q.position.x, q.position.y, h.position.x - q.position.x, q.size.y),
				Rect2(h.end.x, q.position.y, q.end.x - h.end.x, q.size.y),
				Rect2(h.position.x, q.position.y, h.size.x, h.position.y - q.position.y),
				Rect2(h.position.x, h.end.y, h.size.x, q.end.y - h.end.y),
			])
		pieces = next
	for p in pieces:
		if p.size.x > 0.05 and p.size.y > 0.05:
			_add_slab(Vector3(p.get_center().x, ROAD_TOP * 0.5, p.get_center().y), Vector3(p.size.x, ROAD_TOP, p.size.y), asphalt, true, material)


## The light rail's works in this chunk (LightRailKit), after the freeway: FULL chunks only. An
## LOD chunk, the far city's capture and everything past them see the line as LightRailSystem's
## one far mesh (a little inside the FULL works, so where both draw only the detail shows).
func _build_light_rail() -> void:
	if capturing or level != Level.FULL or LightRail.of(plan) == null:
		return
	if zone != MacroMap.Zone.CITY and zone != MacroMap.Zone.BEACH:
		return
	LightRailKit.new(self).build_all()


## Asphalt sets and tints a road can wear; a road keeps one along its length.
## Asphalt is dark. These used to sit at 0.6-0.85, which put the carriageway at exactly the
## same value as the concrete pavement beside it, so a street photograph of the city read as one
## flat grey field with paint on it. Sun-bleached LA asphalt is still only about a quarter as
## bright as a kerb.
## Road paints. These are TINTS ON A PHOTOGRAPHED TEXTURE, and `uniform vec3 tint : source_color`
## means Godot sRGB-decodes them: Color(0.40) multiplies by 0.133, not by 0.40. Asphalt033's own
## mean is already 0.0849 linear - the real reflectance of asphalt - so the old 0.31..0.49 range
## laid the carriageway at 0.0065..0.0169, five to fifteen times darker than any road on earth,
## and every street in the city read as a black ribbon. These land at 0.040..0.068 on the
## Asphalt033 set and 0.061..0.104 on the coarser AerialAsphalt01 one, which is weathered asphalt
## through to a recently resurfaced street. The smoke test checks the arithmetic.
const ROAD_TINTS := [Color(0.842, 0.842, 0.884), Color(0.724, 0.724, 0.771), Color(0.920, 0.885, 0.848), Color(0.786, 0.808, 0.873), Color(0.755, 0.733, 0.711)]


## {"material", "line" (color), "solid" (bool)} for one road, seeded by axis and index.
func _road_look(axis: int, index: int, params: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, "road_look", axis, index])
	var set_key := "asphalt" if rng.randf() < 0.55 else "asphalt_aerial"
	var tint: Color = ROAD_TINTS[rng.randi() % ROAD_TINTS.size()]
	var white := rng.randf() < float(params.get("line_white", 0.4))
	var material := PropFactory.road(set_key, 7.0 if set_key == "asphalt" else 9.0, tint, hash([plan.seed, axis, index]))
	# Which way its street lamps run, for the glow the road wears seen from afar at night
	# (road.gdshader): an AXIS_X road stands at an x and runs along Z.
	material.set_shader_parameter("lamp_axis", 1 if axis == CityPlan.AXIS_X else 2)
	return {
		"material": material,
		"line": Color(0.95, 0.95, 0.9) if white else Color(0.95, 0.8, 0.2),
		"solid": rng.randf() < 0.35,
	}


## Center-line markings along one block: dashed yellow on streets, double solid on avenues.
func _mark_road(along_z: bool, center: float, width: float, a: float, b: float, look: Dictionary = {}) -> void:
	var line: Color = look.get("line", Color(0.95, 0.8, 0.2))
	var solid: bool = look.get("solid", false)
	a += 3.0
	b -= 3.0
	if b - a < 4.0:
		return
	var avenue := width >= plan.avenue_width - 0.1
	var yaw := 0.0 if along_z else PI * 0.5
	# Nothing painted over the light rail's portal trench (LightRail.cuts_in()).
	var rail := LightRail.of(plan)
	var cuts: Array[Rect2] = []
	if rail != null:
		cuts = rail.cuts_in(Rect2(center - width, a, width * 2.0, b - a) if along_z else Rect2(a, center - width, b - a, width * 2.0))
	var freight := FreightRail.of(plan)
	if freight != null:
		cuts.append_array(freight.cuts_in(Rect2(center - width, a, width * 2.0, b - a) if along_z else Rect2(a, center - width, b - a, width * 2.0)))
	# One or two manhole covers in a lane, seeded by the road position.
	var mh := RandomNumberGenerator.new()
	mh.seed = hash([center, a, along_z])
	for i in mh.randi_range(1, 2):
		var t := mh.randf_range(a + 4.0, b - 4.0)
		var lane := (width * 0.25) * (1.0 if mh.randf() < 0.5 else -1.0)
		var pos := Vector3(center + lane, ROAD_TOP - 0.025, t) if along_z else Vector3(t, ROAD_TOP - 0.025, center + lane)
		if _in_cuts(cuts, pos) or RoadHardware.enabled:
			continue
		_batch.add("manhole", PropFactory.model_manhole(), Transform3D(Basis(Vector3.UP, mh.randf_range(0.0, TAU)), pos))
	if avenue:
		for side: float in [-0.3, 0.3]:
			# In pieces so the line follows the relief.
			var t0 := a
			while t0 < b - 0.5:
				var piece := minf(4.0, b - t0)
				var mid := t0 + piece * 0.5
				var pos := Vector3(center + side, ROAD_TOP + 0.01, mid) if along_z else Vector3(mid, ROAD_TOP + 0.01, center + side)
				if not _in_cuts(cuts, pos):
					_batch.add("dash", PropFactory.dash(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, 1.0, piece / 3.0)), pos), line)
				t0 += piece
	elif solid:
		var t0 := a
		while t0 < b - 0.5:
			var piece := minf(4.0, b - t0)
			var mid := t0 + piece * 0.5
			var pos := Vector3(center, ROAD_TOP + 0.01, mid) if along_z else Vector3(mid, ROAD_TOP + 0.01, center)
			if not _in_cuts(cuts, pos):
				_batch.add("dash", PropFactory.dash(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, 1.0, piece / 3.0)), pos), line)
			t0 += piece
	else:
		var t := a + 1.5
		while t < b - 1.5:
			var pos := Vector3(center, ROAD_TOP + 0.01, t) if along_z else Vector3(t, ROAD_TOP + 0.01, center)
			if not _in_cuts(cuts, pos):
				_batch.add("dash", PropFactory.dash(), Transform3D(Basis(Vector3.UP, yaw), pos), line)
			t += 6.0


## Whether a point (world XYZ) falls in one of `cuts` (the rail trench's holes in the road).
static func _in_cuts(cuts: Array[Rect2], pos: Vector3) -> bool:
	for r in cuts:
		if r.grow(0.6).has_point(Vector2(pos.x, pos.z)):
			return true
	return false


# --- Block -----------------------------------------------------------------------------

## A city block as build steps: the pavement, then what stands on it one building at a time, then
## (FULL) the furniture, the parked cars and each pedestrian. One random stream runs through all
## of it in that order, exactly as it did when this was a single function - the far skyline
## replays the same rolls (see Skyline), so the order is load-bearing.
func _block_steps(block: Dictionary) -> Array[Callable]:
	var rect: Rect2 = block.rect
	var district: CityPlan.District = block.district
	var params: Dictionary = CityPlan.DISTRICTS[district]
	var rng := RandomNumberGenerator.new()
	rng.seed = block.seed
	var steps: Array[Callable] = [_block_surface.bind(block, params, rng)]
	# A memorial park (Cemetery): its own hash-seeded plan replaces everything else of the block.
	if CemeteryBuild.wanted(self, block):
		steps.append_array(CemeteryBuild.steps(self, block))
		return steps
	# A hospital campus (Hospital; its own hash-seeded layout) in place of the block's own build.
	match -1 if Hospital.is_hospital(block) else int(block.kind):
		-1:
			steps.append_array(HospitalBuild.steps(self, block))
		CityPlan.BlockKind.PARK:
			if Parks.wanted(self, block):
				# A rec park (Parks: its own hash-seeded layout). The lawn roll is still made, so the
				# block's stream starts where the old park's did.
				steps.append(func() -> void:
					_lawn_color(rng)
					Parks.build(self, block))
			else:
				steps.append(_build_park.bind(rect, rng))
		CityPlan.BlockKind.SCHOOL:
			steps.append(func() -> void: Parks.build(self, block))
			# A public school (Schools; its own hash-seeded plan, any level).
			steps.append_array(Schools.steps(self, block))
		CityPlan.BlockKind.PLAZA:
			steps.append(_build_plaza.bind(rect, rng))
		CityPlan.BlockKind.MALL:
			steps.append(func() -> void: Commercial.build_mall(self, rect, rng))
		CityPlan.BlockKind.BIGBOX:
			steps.append(func() -> void: Commercial.build_bigbox(self, rect, rng))
		_:
			_lawn_rect = Rect2()
			if params.get("lawn", false):
				steps.append(_block_lawn.bind(rect, rng))
			steps.append_array(_lot_steps(rect, params, rng))
			steps.append(_build_approach_parking.bind(rect))
			# What a landmark's square pushed out of the lot grid, less the landmark: forecourt
			# round it or a car park (LotFill; its own rolls).
			if LotFill.wanted(self, district):
				steps.append(func() -> void: LotFill.leftovers(self, block))
			# Beach-town yards and walk streets, the campus's walks, quads and service yards, and the
			# freeway's right of way in any district, once every lot is down (YardFill; hash-seeded,
			# the block's rng untouched).
			steps.append(func() -> void: YardFill.block_step(self, block))
			# The industrial district's yards, rail spurs and fences (Industrial; hash-seeded).
			steps.append(func() -> void: Industrial.block_step(self, block))
			# Billboards: the freeway's monopoles, then every board the lots planned (Billboards;
			# hash-seeded, placed in a step before the finish so the block's props keep their ids).
			steps.append(func() -> void: Billboards.block_step(self, block))
			# The service alley down the seam of the lot grid (Alleys; hash-seeded, after the lots).
			steps.append(func() -> void: Alleys.block_step(self, block))
			# Front and side lawns, in the gaps the houses leave. The lawn slab runs under the
			# whole block, so the footprints the lots just recorded are what the grass has to
			# stay out of; a suburb whose lawns are flat green paint is the tell.
			steps.append(func() -> void:
				if _lawn_rect.size.x > 1.0:
					_add_grass(_lawn_rect, 0.85, 0.0, _lot_rects))
	# The tall pole signs' far boxes (BoulevardSigns; LOD and the far city's capture only).
	steps.append(func() -> void: BoulevardSigns.block_step(self, block))
	# The farmers' market on this chunk's street (FarmersMarketBuild; hash-seeded, by the hour and
	# the day; the block's rng untouched). Before the walkers, so its people get the crowd's room.
	steps.append_array(FarmersMarketBuild.steps(self, block))
	if level == Level.FULL:
		steps.append(_build_sidewalk_props.bind(rect, params, rng, district))
		# Midtown's deco boulevard: mature palms on its kerbs, the night pools (DecoBoulevard), after
		# the furniture they keep clear of.
		steps.append(func() -> void: DecoBoulevard.block_step(self, block))
		# The kerb: the pavement's cut ring, its paint and house numbers (Kerbs; hash-seeded).
		steps.append_array(Kerbs.steps(self, block))
		# Broadway's goods on the pavement and its street clock (Broadway; hash-seeded).
		if Broadway.block_side(plan, ix, iz) != 0:
			steps.append(func() -> void: Broadway.block_step(self, rect))
		# Downtown encampments (Encampment), after the furniture they keep clear of. Its own
		# hash-seeded rolls: the block's rng is untouched, so the cars and the crowd are unmoved.
		var camps: int = Encampment.block_flags(plan, ix, iz) if block.kind == CityPlan.BlockKind.BUILDINGS else 0
		if camps != 0:
			var sleepers: Array = []
			steps.append(func() -> void: Encampment.build_block(self, rect, _sidewalk_edges(rect), sleepers))
			# The people at the camps, one a step, before the block's walkers take the crowd cap.
			for i in Encampment.PEOPLE_STEPS:
				steps.append(func() -> void: Encampment.spawn_sleeper(self, rect, sleepers, i))
		# Street vendors (StreetVendors): carts, trucks and their people. Hash-seeded by block and
		# face and by the hour; the block's rng is untouched. Before the parked cars, which keep
		# out of a truck's stretch of kerb.
		if StreetVendors.wanted(self, block):
			steps.append(func() -> void: StreetVendors.build_block(self, block))
			for i in StreetVendors.MAX_PER_BLOCK:
				steps.append(func() -> void: StreetVendors.spawn_vendor(self, i))
		# Road works in the kerb lane and the building sites' crews (Construction; hash-seeded),
		# before the parked cars, which keep out of a closure.
		if Construction.wanted(self, block):
			steps.append_array(Construction.steps(self, block))
		steps.append_array(_park_car_steps(rect, rng, params))
		steps.append_array(_pedestrian_steps(rect, rng, params, Encampment.PATH_KEEP + 1.0 if camps & Encampment.FACES else -1.0))
		# The rec park's or school's people (Parks; their own stream, after the block's walkers).
		steps.append_array(Parks.people_steps(self, block))
	return steps


## The four pavement edges of a block as [a, b, inward] (the order _build_sidewalk_props uses).
static func _sidewalk_edges(rect: Rect2) -> Array:
	return [
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(0.0, 1.0)],
		[Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Vector2(0.0, -1.0)],
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Vector2(1.0, 0.0)],
		[Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), Vector2(-1.0, 0.0)],
	]


## Where the block's lawn is (set by _block_lawn, read once the lots are down).
var _lawn_rect := Rect2()


## Suburbs and campus: lawns between the buildings instead of bare paving.
func _block_lawn(rect: Rect2, rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-plan.sidewalk_width)
	var ic := inner.get_center()
	var lawn := _lawn_color(rng)
	_add_slab(Vector3(ic.x, SIDEWALK_TOP + 0.02, ic.y), Vector3(inner.size.x, 0.04, inner.size.y), style.grass, false, PropFactory.lawn(lawn, hash([plan.seed, ix, iz, "lawn"])))
	_lawn_rect = inner


## The block's look (paving, dominant tree, palm or jacaranda street, lamp paint) and its pavement.
func _block_surface(block: Dictionary, params: Dictionary, rng: RandomNumberGenerator) -> void:
	var rect: Rect2 = block.rect
	var center := rect.get_center()
	# This block's look: paving set, dominant tree, lamp paint (all from the district table).
	var pavings: Array = params.get("paving", [["paving", 3.0, Color(0.95, 0.94, 0.92)]])
	var paving: Array = pavings[rng.randi() % pavings.size()]
	var paving_tint: Color = (paving[2] as Color).lightened(rng.randf_range(-0.06, 0.06))
	# Any number of species: the old form indexed weights[0..2] by hand, which silently ignored
	# every tree added after the third.
	var weights: Array = params.get("tree_weights", [0.34, 0.33, 0.33])
	var total := 0.0
	for w in weights:
		total += float(w)
	var pick := rng.randf() * maxf(total, 0.0001)
	_tree_bias = weights.size() - 1
	var run := 0.0
	for i in weights.size():
		run += float(weights[i])
		if pick < run:
			_tree_bias = i
			break
	# Some blocks are palm-lined, the way whole boulevards are in Los Angeles. It is a per-block
	# roll so palms run in runs rather than being sprinkled one here and one there.
	_palm_street = rng.randf() < float(params.get("palms", 0.25))
	# And some are jacaranda-lined, the same idea: a whole street of one flowering species is
	# how Los Angeles actually looks in spring, and it is the strongest colour the city has.
	_jacaranda_street = not _palm_street and rng.randf() < float(params.get("jacarandas", 0.14))
	_lamp_tint = params.get("lamp_tint", Color.WHITE)
	# Pavement: the same wear shader as the road, but with expansion joints and far less
	# patching and staining, so a sidewalk reads as poured slabs rather than a grey plane.
	var paving_mat := PropFactory.road(paving[0], paving[1], paving_tint, hash([plan.seed, ix, iz, "paving"]), rng.randf_range(1.2, 1.9), 0.45)
	# A FULL block's outer ring of pavement is Kerbs' (cut for ramps, aprons and tree wells).
	var pave := rect
	if Kerbs.takes(self, rect):
		Kerbs.begin(self, rect, paving_mat)
		pave = Kerbs.inner(rect)
	_add_slab(Vector3(pave.get_center().x, SIDEWALK_TOP * 0.5, pave.get_center().y), Vector3(pave.size.x, SIDEWALK_TOP, pave.size.y), style.sidewalk, true, paving_mat)


## `sidewalk` narrows the strip the walkers keep to (a block with encampments along its walls);
## below zero it is the plan's pavement width.
func _pedestrian_steps(rect: Rect2, rng: RandomNumberGenerator, params: Dictionary = {}, sidewalk: float = -1.0) -> Array[Callable]:
	var count: int = params.get("people", style.pedestrians_per_block)
	if plan.macro and not params.is_empty():
		# The downtown core is the busiest: up to twice the district's count in the middle.
		count = roundi(count * (1.0 + plan.macro.skyline_boost(rect.get_center())))
	return _crowd_steps(rect, plan.sidewalk_width if sidewalk < 0.0 else sidewalk, count, rng)


## `count` pedestrians wandering the sidewalk ring of `rect` (inset `sidewalk` meters).
func _spawn_crowd(rect: Rect2, sidewalk: float, count: int, rng: RandomNumberGenerator) -> void:
	for step in _crowd_steps(rect, sidewalk, count, rng):
		step.call()


## The same crowd as build steps: count the room under the cap once, then one person a step.
func _crowd_steps(rect: Rect2, sidewalk: float, count: int, rng: RandomNumberGenerator) -> Array[Callable]:
	var steps: Array[Callable] = []
	if count <= 0:
		return steps
	steps.append(_count_crowd_room)
	for i in count:
		steps.append(_spawn_walker.bind(rect, sidewalk, rng))
	return steps


## How many more pedestrians the city's cap allows (set by _count_crowd_room).
var _crowd_room: int = 0


func _count_crowd_room() -> void:
	var streamer := get_parent()
	if streamer and streamer.has_method("take_crowd_room"):
		return
	_crowd_room = count_crowd_room(get_tree(), int(style.max_pedestrians))


## The cap minus the pedestrians that will still be here next frame.
static func count_crowd_room(tree: SceneTree, cap: int) -> int:
	var existing := 0
	for n in tree.get_nodes_in_group("pedestrian"):
		# A pedestrian inside a chunk that is being freed is not flagged itself; check its chunk.
		var parent := n.get_parent()
		if n.is_queued_for_deletion() or (parent and parent.is_queued_for_deletion()):
			continue
		existing += 1
	return cap - existing


## One walker's worth of room: from the streamer's city-wide count when there is a streamer
## (see CityStreamer.take_crowd_room()), else from this chunk's own count. `reserve` is the share
## of the cap to leave unspent (a walker near downtown leaves room for the people at the camps).
func _take_crowd_room(reserve: float = 0.0) -> bool:
	var streamer := get_parent()
	if streamer and streamer.has_method("take_crowd_room"):
		return streamer.take_crowd_room(reserve)
	if _crowd_room <= roundi(int(style.max_pedestrians) * reserve):
		return false
	_crowd_room -= 1
	return true


func _spawn_walker(rect: Rect2, sidewalk: float, rng: RandomNumberGenerator) -> void:
	if not _take_crowd_room(Encampment.walker_reserve(plan, ix, iz)):
		return
	var ped := Pedestrian.new()
	ped.setup(rect, sidewalk, rng.randi())
	var start := ped._random_ring_point(sidewalk)
	ped.position = Vector3(start.x, SIDEWALK_TOP + 0.1 + _gy(start.x, start.y), start.y)
	add_child(ped)


## The stall line mesh is shared with the car parks' 4.4 m bays (Commercial); a kerb bay is
## CityPlan.PARKING_LANE across, so the street's lines are the same mesh scaled down.
const STALL_SCALE := CityPlan.PARKING_LANE / 4.4


## Parked cars in the lanes of this chunk's two roads, nose along the road.
## One build step per parking spot. A car is the most expensive single thing a chunk makes
## (about 35 ms on a slow machine: the body model, paint, wheels, lights), and a block's worth
## built in one step was the worst hitch left while flying - up to 590 ms. The stall lines are
## laid now; the rolls happen in the steps, in the same order as when this was one loop.
func _park_car_steps(rect: Rect2, rng: RandomNumberGenerator, params: Dictionary = {}) -> Array[Callable]:
	var steps: Array[Callable] = []
	var max_cars: int = params.get("parked", style.cars_per_block)
	if max_cars <= 0:
		return steps
	var rx := plan.road_pos(CityPlan.AXIS_X, ix + 1)
	var wx := plan.road_width(CityPlan.AXIS_X, ix + 1)
	var rz := plan.road_pos(CityPlan.AXIS_Z, iz + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, iz + 1)
	var spots: Array = []
	for side: float in [-1.0, 1.0]:
		var x := rx + side * CityPlan.parking_offset(wx)
		var t := rect.position.y + 8.0
		while t < rect.end.y - 8.0:
			spots.append([Vector3(x, 0.4, t), 0.0, side])
			# Painted stall line between spots (none on a road the freight yard closes).
			if not FreightRail.keeps_clear(plan, Vector2(x, t)):
				_batch.add("pstripe", PropFactory.box("pstripe", Vector3(4.4, 0.01, 0.12), Color(0.95, 0.95, 0.92)), Transform3D(Basis().scaled(Vector3(STALL_SCALE, 1.0, 1.0)), Vector3(x, ROAD_TOP + 0.014, t + 4.0)))
			t += 8.0
		var z := rz + side * CityPlan.parking_offset(wz)
		t = rect.position.x + 8.0
		while t < rect.end.x - 8.0:
			spots.append([Vector3(t, 0.4, z), PI * 0.5, side])
			if not FreightRail.keeps_clear(plan, Vector2(t, z)):
				_batch.add("pstripe", PropFactory.box("pstripe", Vector3(4.4, 0.01, 0.12), Color(0.95, 0.95, 0.92)), Transform3D(Basis(Vector3.UP, PI * 0.5).scaled_local(Vector3(STALL_SCALE, 1.0, 1.0)), Vector3(t + 4.0, ROAD_TOP + 0.014, z)))
			t += 8.0
	# Seeded from the block, not the global generator: `Array.shuffle()` put different cars in
	# different spots every run, which broke "same seed, same city" (and made every A/B render
	# compare two different streets). Its own generator, so the block's rng stream is untouched.
	var order := RandomNumberGenerator.new()
	order.seed = hash([plan.seed, ix, iz, 7331])
	for i in range(spots.size() - 1, 0, -1):
		var j := order.randi_range(0, i)
		var tmp = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	var count := [0]
	for spot in spots:
		steps.append(_park_car.bind(spot, rng, max_cars, count))
	return steps


func _park_car(spot: Array, rng: RandomNumberGenerator, max_cars: int, count: Array) -> void:
	# 0.55, not 0.35: at a third the kerbs read as a city on a quiet Sunday. Parked cars are
	# live rigid bodies - CLAUDE.md is explicit that a Vehicle must never be frozen, because
	# frozen wheels divide by zero and poison the body with NaN - but an undisturbed one
	# sleeps (Vehicle.settle()), so a parked car nobody touches costs close to nothing.
	# PhysicsBudget still caps the total, and Quality halves that cap below its top level.
	if count[0] >= max_cars or rng.randf() > 0.55 or not PhysicsBudget.can_spawn():
		return
	var car := Vehicle.random_car(rng)
	if (plan.macro and Landmarks.covers(plan, Vector2(spot[0].x, spot[0].z), 3.0)) or BigVehicles.in_stop_zone(plan, Vector2(spot[0].x, spot[0].z)) \
			or FireStation.keeps_clear(plan, Vector2(spot[0].x, spot[0].z)) or PoliceStation.keeps_clear(plan, Vector2(spot[0].x, spot[0].z)) \
			or Schools.keeps_clear(plan, Vector2(spot[0].x, spot[0].z)) or Alleys.keeps_clear(plan, Vector2(spot[0].x, spot[0].z)) \
			or Kerbs.blocks_parking(self, spot[0]) or Hospital.keeps_clear(plan, Vector2(spot[0].x, spot[0].z)) \
			or FreightRail.keeps_clear(plan, Vector2(spot[0].x, spot[0].z)):
		# After the rolls, so the chunk rng runs the same whether or not the spot is used. A bus
		# stop's kerb is kept clear for the bus (BigVehicles), a fire station's for its engines.
		car.free()
		return
	var holder: Node = get_parent() if get_parent() else self
	var spot_pos: Vector3 = spot[0] + Vector3(0.0, 0.3 + _gy(spot[0].x, spot[0].z), 0.0)
	car.position = WorldState.to_local(spot_pos) if holder != self else spot_pos
	car.rotation.y = spot[1] + (PI if rng.randf() < 0.5 else 0.0)
	# A street vendor's truck at this stretch of kerb (StreetVendors): after every roll, so the
	# block's stream (and the walkers after it) runs the same with or without the truck.
	# It counts as parked, so the cap (and with it the rolls) is the same too.
	if StreetVendors.blocks_parking(self, spot[0]) or Construction.blocks_parking(self, spot[0]) \
			or KerbBins.blocks_parking(plan, spot[0], float(car._dims().length)) \
			or FarmersMarket.blocks_parking(plan, spot[0]):
		car.free()
		count[0] += 1
		return
	holder.add_child(car)
	# A chunk still being built is hidden until it is finished (CityStreamer), and its cars
	# live under the city root rather than under it, so they are hidden with it by hand.
	car.visible = visible
	_cars.append(car)
	count[0] += 1


## Shows a chunk that was built hidden over several frames, and the parked cars it placed.
func reveal() -> void:
	visible = true
	for car in _cars:
		if is_instance_valid(car):
			(car as Node3D).visible = true


## This chunk has left the streaming window but stays drawn a moment longer, while the far city
## dissolves back in over it (CityStreamer._retire_chunk). Everything that is not just its look
## goes now, exactly when it went before there was a dissolve: its parked cars and its people, its
## trash cans, and its collision - nothing should walk, drive or be hit in a block that is fading.
func retire() -> void:
	for car in _cars:
		if is_instance_valid(car) and not car.has_meta("driven"):
			car.queue_free()
	_cars.clear()
	for child in get_children():
		if child.is_in_group("pedestrian") or child.is_in_group("physics_prop"):
			child.queue_free()
		elif child is CollisionObject3D:
			(child as CollisionObject3D).collision_layer = 0
			(child as CollisionObject3D).collision_mask = 0
	set_process(false)


func _exit_tree() -> void:
	for car in _cars:
		if is_instance_valid(car) and not car.has_meta("driven"):
			car.queue_free()
	_cars.clear()


## Lot layout is shared by FULL and LOD so both see the same buildings.
## Lots come from the PLAN, seeded per block, so the far skyline can ask for exactly the same
## buildings (see CityPlan.lots()). One build step per lot.
func _lot_steps(_rect: Rect2, params: Dictionary, rng: RandomNumberGenerator) -> Array[Callable]:
	var steps: Array[Callable] = [func() -> void:
		_lot_rects.clear()
		_yard_lots.clear()
		_yard_corridor.clear()
		_ind = {}]
	for lot in plan.lots(ix, iz):
		steps.append(_build_lot.bind(lot, params, rng))
	# The cells the lot grid's gap roll left too small for a lot: a house of their own in the
	# suburbs and the beach town (HouseKit.extra_lots(); hash-seeded, after every rolled lot).
	var district: int = plan.block(ix, iz).district
	if HouseKit.wanted(self, district):
		for lot: Dictionary in HouseKit.extra_lots(plan, ix, iz):
			if not CarDealers.covers(plan, ix, iz, lot.center):
				steps.append(_build_house.bind(lot, district))
	return steps


func _build_lot(lot: Dictionary, params: Dictionary, rng: RandomNumberGenerator) -> void:
	var pads: float = params.get("pads", 0.0)
	# The district this block sits in, for the shared massing curve. block() is cached.
	var district: int = plan.block(ix, iz).district
	var center: Vector2 = lot.center
	if lot.yard:
		_build_yard(lot, rng)
		return
	# What stands on this lot (a house, a pad, or the freeway corridor above it): the
	# suburban lawn grass keeps out of these.
	_lot_rects.append(Rect2(center - (lot.size as Vector2) * 0.5 - Vector2(0.4, 0.4), (lot.size as Vector2) + Vector2(0.8, 0.8)))
	var pad: bool = lot.edge and pads > 0.0 and rng.randf() < pads and (lot.size as Vector2).x >= 18.0 and (lot.size as Vector2).y >= 18.0
	# Nothing gets built in the corridor the freeway flies over - no part of the lot, pads
	# included. Checked here, after the pad roll, so skipping a lot does not shift the chunk rng
	# for the lots after it. It tested the lot's centre alone (14 m either side of the deck),
	# which let the corner of a big lot stand well into the deck and its pillars.
	if _under_freeway(center, 14.0) or _lot_under_freeway(lot):
		_build_corridor_lot(lot)
		return
	# A fire station's lot (FireStation: one lot in a cell, hash-seeded; the pad roll above is made).
	if FireStation.claims(plan, ix, iz, lot):
		FireStation.build_lot(self, lot)
		return
	# A police station's lots (PoliceStation: a run of lots on one street, hash-seeded; the pad roll is made).
	if PoliceStation.claims(plan, ix, iz, lot):
		PoliceStation.build_lot(self, lot)
		return
	# A Broadway movie palace (Broadway: a table of real addresses; the rolls above are made).
	if Broadway.claims(plan, ix, iz, lot):
		Broadway.build_lot(self, lot)
		return
	# A car dealership's site (CarDealers: a run of edge lots on an auto row, hash-seeded; the pad
	# roll above is made, so no other lot moves).
	if CarDealers.claims(plan, ix, iz, lot):
		CarDealers.build_lot(self, lot)
		return
	# A single pumpjack behind a fence (OilField.lot_well(): a hash of the lot; the rolls above are made).
	var well := OilField.lot_well(plan, lot, district)
	if not well.is_empty():
		OilFieldBuild.claim_lot(self, lot, well, district)
		return
	var fill := LotFill.wanted(self, district)
	# A surface car park (CityPlan.lots() "parking"; the pad roll above is still made).
	if fill and lot.get("parking", false):
		LotFill.surface_lot(self, lot)
		return
	if pad:
		Commercial.build_pad(self, lot, rng)
		return
	# A vacant lot or a gravel car park (VacantLots: a hash of seed + lot, after every roll above).
	if VacantLots.build_lot(self, lot):
		return
	# The suburbs' and the beach town's houses (HouseKit: real houses, planned purely from the lot).
	if HouseKit.wanted(self, district):
		# The lawn's blades and the street trees keep off the house, not the whole lot.
		_lot_rects.pop_back()
		_build_house(lot, district)
		return
	# A deco building on a midtown boulevard (DecoBoulevard: hash-seeded, the pad roll is made).
	if DecoBoulevard.build_lot(self, lot):
		return
	var building := BUILDING_SCENE.instantiate() as Building
	building.seed = lot.seed
	building.lot_size = lot.size
	# Downtown and midtown: a slender tower may stand on a podium filling its lot, its drive-in on
	# the street side (Building._add_podium()).
	building.podium_lot = fill
	if fill:
		building.street_face = LotFill.street_face(self, lot)
	# Its back on the block's service alley, if it has one (Alleys: pure, no roll).
	building.back_face = Alleys.back_face(plan, ix, iz, lot)
	# Downtown core: the skyline climbs toward the center (supertalls in the middle).
	var boost := plan.macro.skyline_boost(center) if plan.macro else 0.0
	# Handing the whole district band to each building made every lot an independent uniform
	# draw between the two heights, and a uniform draw has no tail: downtown's 50..140 lerped
	# to 100..308 in the core came out with a median of 134 m and the twelve tallest towers
	# inside 65 m of each other, so the top of the city read as one flat line rather than as
	# a skyline. So the band is rolled ONCE per lot into a target height and the building gets
	# a narrow band around that, with the roll bent by pow(u, curve): most lots land near the
	# bottom of the band and a handful reach the top (CityPlan.lot_height(), shared with the far
	# tier). How hard to bend it is set by how much room the district actually has - log base 4
	# of the band's ratio - so the suburbs' 5..14 m (2.8x) only reaches 1.74 and still reads as
	# a street of houses (median 7.7 m); the downtown core has its own band and a flatter curve
	# (DISTRICTS DOWNTOWN core_height / core_curve), a field of 80-200 m towers under the
	# landmark ones.
	var target := plan.lot_height(lot.seed, district, boost)
	building.min_height = target * 0.88
	building.max_height = target
	building.lit_ratio_range = params.lit
	building.weathering_range = params.get("weathering", Vector2(0.2, 0.9))
	building.shape_options.assign(CityPlan.lot_shapes(district, boost))
	building.finish_options.assign(CityPlan.lot_finishes(district, boost))
	# Broadway's 1920s commercial blocks (masonry, the height limit, its own shop names).
	Broadway.dress(self, lot, building)
	var g := _gy(center.x, center.y)
	var gmin := g
	var half: Vector2 = lot.size * 0.5
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		gmin = minf(gmin, _gy(center.x + c.x * half.x, center.y + c.y * half.y))
	# A concrete plinth reaches from the base down past the lowest sidewalk corner.
	building.plinth_depth = g - gmin + SIDEWALK_TOP + 0.6
	var base := Vector3(center.x, SIDEWALK_TOP, center.y)
	building.position = base + Vector3(0.0, g, 0.0)
	# A tower going up (Construction: a hash of seed + block, after every roll; the Building's own
	# rolls never run).
	if Construction.build_lot(self, lot):
		building.free()
		building_count += 1
		return
	# An INDUSTRIAL warehouse is Industrial's own tilt-up building (hash-seeded; no roll moves).
	if Industrial.wanted(self, district) and Industrial.build_lot(self, lot, building):
		building.free()
		building_count += 1
		return
	if level == Level.FULL:
		# Its plinth joins the chunk's merged boxes (Building.plinth_in_chunk).
		building.plinth_in_chunk = merge_boxes and not _boxes_committed
		add_child(building)
		if building.plinth_in_chunk:
			var plinth := building.plinth_box()
			if not plinth.is_empty():
				_merge_box(Building.plinth_material(), plinth[0], building.position + (plinth[1] as Vector3))
		building_count += 1
		if fill:
			LotFill.after_building(self, lot, building)
		elif YardFill.wanted(self, district):
			YardFill.record_lot(self, lot, building)
		Billboards.on_building(self, lot, building, district)
	else:
		# Far away: just the boxes, in the facade color, no props. They do get plain box
		# collision so a fast car cannot drive into a footprint and get shot through the
		# floor when the detailed building appears around it.
		var lod_style := building.plan_only()
		for part in building.parts:
			var size: Vector3 = part.size
			var part_center: Vector3 = part.center
			# The shape needs the relief explicitly (the batch adds it to what it draws).
			_add_lod_shape(size, building.position + part_center)
			_occluder_boxes.append([Transform3D(Basis(), building.position), part_center, size])
		# What is drawn: the parts coded with the near building's own facade, roof and lights,
		# the plinth folded into them, and its roof plant (FarBuilding; the far city captures
		# exactly these). The batch adds the relief at each instance's own origin, but the near
		# building stands on the relief at the lot's centre, and so must every part and unit of
		# its far copy - an offset tier used to sit a few centimetres off the one under it.
		if FarBuilding.enabled:
			for fb: Array in FarBuilding.boxes(building, lod_style, building.plinth_depth):
				var xf: Transform3D = fb[0]
				var at: Vector3 = base + xf.origin
				at.y += g - _gy(at.x, at.z)
				_batch.add("lod_box", PropFactory.unit_box(), Transform3D(xf.basis, at), fb[1], fb[2])
		else:
			# The old far boxes: the facade colour and a window style (building_lod.gdshader's old path).
			var custom := Color(float(building.window_style) / 4.0, lod_style.lit_ratio, float(building.seed % 997) / 997.0, 0.0)
			for part in building.parts:
				var part_custom := Color(1.0 / 4.0, 0.06, custom.b, 0.0) if Building.is_parking(part) else custom
				_batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(part.size), base + (part.center as Vector3)), building.part_lod_color(part), part_custom)
			var fp: Vector2 = building.footprint
			if fp.x > 0.0 and building.plinth_depth > 0.05:
				_batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(fp.x + 0.3, building.plinth_depth, fp.y + 0.3)), base + Vector3(0.0, -building.plinth_depth * 0.5, 0.0)), Color(0.66, 0.66, 0.66), Color(0.0, 0.0, 0.0, 1.0))
		if fill:
			LotFill.after_building(self, lot, building)
		elif YardFill.wanted(self, district):
			YardFill.record_lot(self, lot, building)
		Billboards.on_building(self, lot, building, district)
		building.free()
		building_count += 1


## One house (HouseKit) on a lot of the plan's, or on a cell the lot grid left empty.
func _build_house(lot: Dictionary, district: int) -> void:
	var house := HouseKit.plan_house(plan, ix, iz, lot, district)
	for r: Rect2 in HouseKit.ground_parts(house):
		_lot_rects.append(r.grow(0.3))
	# A timber frame going up on the house's own plan (Construction; a hash of seed + lot).
	if not Construction.build_house(self, lot, house):
		HouseKit.build(self, house)
	building_count += 1
	if YardFill.wanted(self, district):
		_yard_lots.append(HouseKit.yard_entry(lot, house))


## A skipped inner lot becomes a pocket garden: lawn, a few trees and shrubs, a bench.
func _build_yard(lot: Dictionary, rng: RandomNumberGenerator) -> void:
	var center: Vector2 = lot.center
	var size: Vector2 = lot.size
	var lawn := _lawn_color(rng)
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.02, center.y), Vector3(size.x, 0.04, size.y), style.grass, false, PropFactory.lawn(lawn, hash([plan.seed, ix, iz, "lawn"])))
	if level != Level.FULL:
		return
	for i in rng.randi_range(3, 7):
		var p := center + Vector2(rng.randf_range(-size.x * 0.4, size.x * 0.4), rng.randf_range(-size.y * 0.4, size.y * 0.4))
		_add_tree(Vector3(p.x, SIDEWALK_TOP, p.y), rng)
	for i in rng.randi_range(6, 14):
		var p := center + Vector2(rng.randf_range(-size.x * 0.45, size.x * 0.45), rng.randf_range(-size.y * 0.45, size.y * 0.45))
		_add_bush(Vector3(p.x, SIDEWALK_TOP, p.y), rng)
	# A pocket garden is a garden: planted beds, not mown grass with three bushes on it.
	_scatter_ground_cover(Rect2(center - size * 0.45, size * 0.9), rng, 1.35)
	_add_grass(Rect2(center - size * 0.46, size * 0.92), 1.0)
	if rng.randf() < 0.6:
		_add_bench(Vector3(center.x, SIDEWALK_TOP + 0.04, center.y + size.y * 0.3), PI)


## Far chunks merge all their ground into ONE vertex-coloured mesh. See _add_ground_grid().
var _far_ground: SurfaceTool
var _far_ground_any: bool = false
var _lod_body: StaticBody3D


## Rings of LOD chunks beyond this get NO building collision. A LOD chunk starts seven blocks
## out; the player cannot touch a building until the chunk is FULL (two blocks) and has real
## collision, and the streaming window now leads their velocity, so the upgrade lands before
## they arrive even in a jet. The outer rings were paying the broadphase for 984 box shapes
## nobody can reach. Nothing is drawn differently - this is collision only.
const LOD_COLLISION_RINGS := 4


func _lod_collision_wanted() -> bool:
	if level == Level.FULL:
		return true
	# The chunk's RING is its distance from the player, so this is safe by construction: a chunk
	# at ring 5 is four hundred metres away, and it is rebuilt as FULL - with real collision -
	# long before they can reach it.
	return maxi(absi(ix - center_block.x), absi(iz - center_block.y)) <= LOD_COLLISION_RINGS


func _add_lod_shape(size: Vector3, pos: Vector3) -> void:
	if capturing or not _lod_collision_wanted():
		return
	if _lod_body == null:
		_lod_body = StaticBody3D.new()
		_lod_body.name = "LodBuildings"
		_lod_body.collision_layer = 1
		_lod_body.collision_mask = 0
		add_child(_lod_body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	_lod_body.add_child(shape)


func _build_park(rect: Rect2, rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-2.0)
	var center := inner.get_center()
	# Lawns range from lush to summer-dry.
	var lawn := _lawn_color(rng)
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.02, center.y), Vector3(inner.size.x, 0.04, inner.size.y), style.grass, false, PropFactory.lawn(lawn, hash([plan.seed, ix, iz, "lawn"])))
	if level != Level.FULL:
		return
	var path_w := 3.0
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.04, center.y), Vector3(inner.size.x, 0.02, path_w), style.path, false)
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.04, center.y), Vector3(path_w, 0.02, inner.size.y), style.path, false)
	for i in rng.randi_range(16, 34):
		var p := Vector2(rng.randf_range(inner.position.x + 3.0, inner.end.x - 3.0), rng.randf_range(inner.position.y + 3.0, inner.end.y - 3.0))
		if absf(p.x - center.x) < path_w or absf(p.y - center.y) < path_w:
			continue
		_add_tree(Vector3(p.x, SIDEWALK_TOP, p.y), rng)
	for i in rng.randi_range(4, 8):
		var along_x := rng.randf() < 0.5
		var t := rng.randf_range(-0.4, 0.4)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := center + (Vector2(inner.size.x * t, side * (path_w * 0.5 + 0.6)) if along_x else Vector2(side * (path_w * 0.5 + 0.6), inner.size.y * t))
		_add_bench(Vector3(p.x, SIDEWALK_TOP + 0.04, p.y), (0.0 if side > 0.0 else PI) if along_x else side * PI * 0.5)
	for dx: float in [-1.0, 1.0]:
		for dz: float in [-1.0, 1.0]:
			_add_lamp(Vector3(center.x + dx * (path_w * 0.5 + 1.0), SIDEWALK_TOP + 0.04, center.y + dz * (path_w * 0.5 + 1.0)))
	# Bushes and grass.
	for i in rng.randi_range(12, 26):
		var p := Vector2(rng.randf_range(inner.position.x + 2.0, inner.end.x - 2.0), rng.randf_range(inner.position.y + 2.0, inner.end.y - 2.0))
		if absf(p.x - center.x) < path_w + 1.0 or absf(p.y - center.y) < path_w + 1.0:
			continue
		_add_bush(Vector3(p.x, SIDEWALK_TOP + 0.04, p.y), rng)
	# Flowering ground cover over the whole park: this is where a park stops being bare grass.
	_scatter_ground_cover(inner.grow(-2.0), rng, 1.0)
	_add_grass(inner.grow(-1.0), 1.0, path_w * 0.5 + 0.3)


## Freeway right-of-way: a lot the deck flies over or passes within LOT_FREEWAY_MARGIN of is never
## built on, and it used to be left as the block's bare paving - every block a freeway crossed was
## an empty tan plaza either side of the deck. Real ones are banks of ivy and iceplant with
## oleander and other shrubs along them: so an ivy ground cover over the lot and, on FULL chunks,
## shrubs everywhere except under the deck itself (shade and pillars). A private rng from the
## lot's own seed, so neither the chunk rng nor anything built after this moves.
func _build_corridor_lot(lot: Dictionary) -> void:
	# The right of way is YardFill's now (ivy over the whole cell, the deck's shade bare, hedge and
	# tree rows along the deck, sound walls, a maintenance yard): laid by its block step, once every
	# lot of the block is down. What follows is the old ground, kept for YardFill.enabled = false.
	if YardFill.enabled and zone == MacroMap.Zone.CITY:
		_yard_corridor.append(lot)
		return
	var size: Vector2 = lot.size
	var center: Vector2 = lot.center
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.02, center.y), Vector3(maxf(size.x - 1.0, 0.5), 0.04, maxf(size.y - 1.0, 0.5)),
		style.grass, false, PropFactory.lawn(CORRIDOR_IVY, hash([plan.seed, "corridor_ivy"]), 0.0, 0.0))
	if level != Level.FULL or capturing:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, ix, iz, lot.seed, "corridor"])
	var rect := Rect2(center - size * 0.5, size).grow(-1.2)
	var n := clampi(int(rect.size.x * rect.size.y / CORRIDOR_SHRUB_AREA), 0, 60)
	for i in n:
		var p := Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
		if _under_freeway(p, 1.5):
			continue
		_add_bush(Vector3(p.x, SIDEWALK_TOP + 0.04, p.y), rng)


## Under the final approach (MacroMap.runway_clear_zone()) CityPlan.lots() builds nothing, and
## the lots it drops were left as the block's bare paving - by the airport, a row of empty tan
## blocks either side of the 105. It is the airport's long-term parking instead, as the land
## under the real one's approach is: asphalt, double rows of stalls on 7 m aisles, cars packed in
## (ArenaGrounds' static ~260-triangle cars in the chunk batch - nothing taller than a car under
## the glide path) and lamps on the aisles. Stalls keep off the lots left standing. Its own rng.
func _build_approach_parking(rect: Rect2) -> void:
	if plan.macro == null:
		return
	var area := rect.grow(-plan.sidewalk_width - 1.0).intersection(plan.macro.runway_clear_zone().grow(APPROACH_PARK_REACH))
	if area.size.x < 20.0 or area.size.y < 14.0:
		return
	var c := area.get_center()
	_add_slab(Vector3(c.x, SIDEWALK_TOP + 0.02, c.y), Vector3(area.size.x, 0.04, area.size.y), Color(0.4, 0.4, 0.42), false,
		PropFactory.road("asphalt", 7.0, Color(0.62, 0.62, 0.64), hash([plan.seed, ix, iz, "approach_park"]), 0.0, 0.6))
	# The far (LOD) chunks park cars too, fewer and without the stall paint: from the air an empty
	# asphalt block reads as a hole in the city. Never in the far city's capture.
	if capturing:
		return
	var full := level == Level.FULL
	var max_cars := APPROACH_PARK_MAX_CARS if full else APPROACH_PARK_MAX_CARS / 2
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, ix, iz, "approach_park"])
	var stall := ArenaGrounds.STALL
	var pitch := stall.y * 2.0 + 7.0
	var cars := 0
	var z := area.position.y + 3.5
	while z + stall.y * 2.0 < area.end.y - 1.0:
		for half in 2:
			var zc := z + stall.y * (0.5 + float(half))
			var x := area.position.x + 2.0
			while x + stall.x < area.end.x - 2.0:
				var bay := Rect2(Vector2(x, zc - stall.y * 0.5), stall)
				var free := true
				for r: Rect2 in _lot_rects:
					if r.intersects(bay):
						free = false
						break
				if free:
					if full:
						_batch.add("pstripe", PropFactory.box("pstripe", Vector3(4.4, 0.01, 0.12), Color(0.95, 0.95, 0.92)),
							Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, SIDEWALK_TOP + 0.05, zc)))
					if cars < max_cars and rng.randf() < (0.72 if full else 0.5):
						var v := rng.randi() % ArenaGrounds.CAR_KINDS
						var paint: Color = ArenaGrounds.CAR_PAINTS[rng.randi() % ArenaGrounds.CAR_PAINTS.size()]
						var yaw := (0.0 if half == 0 else PI) + rng.randf_range(-0.04, 0.04)
						_batch.add("apark_car_%d" % v, ArenaGrounds.car_mesh(v), Transform3D(Basis(Vector3.UP, yaw),
							Vector3(x + stall.x * 0.5, SIDEWALK_TOP + 0.045, zc)), paint)
						cars += 1
				x += stall.x
		# A lamp on every other aisle.
		if full and int((z - area.position.y) / pitch) % 2 == 0:
			_add_lamp(Vector3(c.x, SIDEWALK_TOP + 0.04, z + stall.y * 2.0 + 3.5))
		z += pitch


func _add_bush(at: Vector3, rng: RandomNumberGenerator) -> void:
	var sc := rng.randf_range(0.7, 1.3)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sc, sc, sc))
	var tint := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.0))
	# Eight species now: the four original shrub_02 variants plus four downloaded bushes. One
	# roll decides which family, so the seeded sequence stays the same length either way.
	if rng.randf() < 0.5:
		var v := rng.randi() % 4
		_batch.add("shrub_%d" % v, PropFactory.model_shrub(v), Transform3D(basis, at), tint)
	else:
		var b := rng.randi() % PropFactory.BUSHES.size()
		_batch.add("bush_%d" % b, PropFactory.model_bush(b), Transform3D(basis, at), tint)


## Blade grass over a lawn: PropFactory.grass_blade() tufts in the "grass_<cx>_<cz>" batches, one
## per GRASS_CELL of true world, each one draw call however many tufts it holds - a hundred tufts
## or twenty thousand, which is what makes real grass affordable at all.
##
## `blockers` are rects the grass has to keep out of (the house footprints on a suburban block,
## which the lawn slab runs underneath). They are rasterised into an occupancy grid first,
## because testing twenty rects for each of twenty thousand blades costs more than the grass.
## Its own seeded rng, so adding grass never shifts the block's sequence and moves a building.
func _add_grass(rect: Rect2, density: float = 1.0, keep_out: float = 0.0, blockers: Array[Rect2] = []) -> void:
	if level != Level.FULL or rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, ix, iz, "grass", int(rect.position.x), int(rect.position.y)])
	var area := rect.size.x * rect.size.y
	var count := int(clampf(area * grass_per_sqm * density * _detail(), 0.0, float(grass_max_per_patch)))
	if count <= 0:
		return
	var cell := 2.0
	var gx := maxi(1, ceili(rect.size.x / cell))
	var gz := maxi(1, ceili(rect.size.y / cell))
	var blocked := PackedByteArray()
	if not blockers.is_empty():
		blocked.resize(gx * gz)
		for b in blockers:
			var i0 := clampi(floori((b.position.x - rect.position.x) / cell), 0, gx - 1)
			var i1 := clampi(ceili((b.end.x - rect.position.x) / cell), 0, gx - 1)
			var j0 := clampi(floori((b.position.y - rect.position.y) / cell), 0, gz - 1)
			var j1 := clampi(ceili((b.end.y - rect.position.y) / cell), 0, gz - 1)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					blocked[j * gx + i] = 1
	var center := rect.get_center()
	var blade := PropFactory.grass_blade()
	# A big lawn is twenty thousand tufts, so it is planted GRASS_SLICE at a time as build steps
	# of its own. Its random stream is its own too, so the lawn comes out identical either way.
	var done := [0]
	var keys := {}
	_run_or_defer(func() -> bool:
		var stop := mini(count, done[0] + GRASS_SLICE)
		for k in range(done[0], stop):
			var p := Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
			if keep_out > 0.0 and (absf(p.x - center.x) < keep_out or absf(p.y - center.y) < keep_out):
				continue
			if not blocked.is_empty():
				var ci := clampi(int((p.x - rect.position.x) / cell), 0, gx - 1)
				var cj := clampi(int((p.y - rect.position.y) / cell), 0, gz - 1)
				if blocked[cj * gx + ci] == 1:
					continue
			# Squash and stretch each tuft independently, so a lawn is not one shape repeated.
			var sc := rng.randf_range(0.55, 1.6)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sc * rng.randf_range(0.85, 1.2), sc * rng.randf_range(0.7, 1.35), sc * rng.randf_range(0.85, 1.2)))
			var tint := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.05))
			var key := "grass_%d_%d" % [floori(p.x / GRASS_CELL), floori(p.y / GRASS_CELL)]
			keys[key] = true
			_batch.add(key, blade, Transform3D(basis, Vector3(p.x, SIDEWALK_TOP + 0.05, p.y)), tint, Color(rng.randf(), 0.0, 0.0))
		done[0] = stop
		if stop < count:
			return false
		for key: String in keys:
			_batch.set_no_shadow(key)
			_batch.set_draw_distance(key, grass_distance)
		return true)


## Grass tufts planted per build step (see _add_grass).
const GRASS_SLICE := 800
## The grass is batched in cells this many metres across (true world, so a cell is the same for
## every lawn of the chunk): a batch's draw distance is measured to the centre of its bounds, so as
## ONE batch a chunk drew every tuft it had while its centre was inside grass_distance - in the beach
## town 3.4 million triangles of blades in six draws, 43 % of the frame.
const GRASS_CELL := 32.0


## Flowering ground cover and grass clumps scattered over a patch of lawn. This is where the
## city's colour at ground level comes from: before it, a park was bare grass between a tree and
## a bench. Kept to the FULL level and given a short draw distance - they are small enough that
## they are a few pixels at any range, and there are a lot of them.
func _scatter_ground_cover(rect: Rect2, rng: RandomNumberGenerator, density: float = 1.0) -> void:
	if level != Level.FULL:
		return
	var area := rect.size.x * rect.size.y
	# One flowering species dominates a patch, the way a planted bed or a wildflower verge does;
	# a mixed sprinkle of seven colours reads as confetti.
	# TWO flowering species per patch, not seven. Every distinct species is a separate batch key
	# and a batch key is a draw call, so letting the 28% "other" roll reach all seven put nine new
	# draws on every FULL chunk - about 225 across the streamed city, for plants that are a few
	# pixels across. Two species also looks more like planting than seven does.
	var lead := rng.randi() % PropFactory.FLOWERS.size()
	var second := (lead + 1 + rng.randi() % maxi(PropFactory.FLOWERS.size() - 1, 1)) % PropFactory.FLOWERS.size()
	var clump := rng.randi() % PropFactory.GRASS_CLUMPS.size()
	# How many plants a patch gets is a TRIANGLE budget, not a flat count. These are scanned
	# models and they differ by a factor of fifty - 941 triangles for a clump of bermuda
	# grass, 54 764 for one dandelion - so the old flat 90 either planted a thin sprinkle
	# that left the lawn bare or spent 2.8 million triangles on fifty dandelions nobody can
	# see the seed heads of. Costing the mix means a cheap species carpets the bed and an
	# expensive one is planted as the specimen it is, for the same money either way.
	var avg := 0.42 * float(_mesh_tris(PropFactory.model_grass_clump(clump)))
	avg += 0.58 * 0.72 * float(_mesh_tris(PropFactory.model_flower(lead)))
	avg += 0.58 * 0.28 * float(_mesh_tris(PropFactory.model_flower(second)))
	var wanted := area * cover_per_sqm * density
	var afforded := area * cover_tris_per_sqm / maxf(avg, 1.0)
	var count := clampi(int(minf(wanted, afforded) * _detail()), 0, 3000)
	for i in count:
		var p := Vector2(
			rng.randf_range(rect.position.x, rect.end.x),
			rng.randf_range(rect.position.y, rect.end.y))
		var sc := rng.randf_range(0.7, 1.45)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sc, sc, sc))
		var tint := Color(rng.randf_range(0.88, 1.12), rng.randf_range(0.9, 1.1), rng.randf_range(0.88, 1.1))
		var at := Vector3(p.x, SIDEWALK_TOP + 0.02, p.y)
		if rng.randf() < 0.42:
			_batch.add("gclump_%d" % clump, PropFactory.model_grass_clump(clump), Transform3D(basis, at), tint)
		else:
			var f: int = lead if rng.randf() < 0.72 else second
			_batch.add("flower_%d" % f, PropFactory.model_flower(f), Transform3D(basis, at), tint)
	for f: int in [lead, second]:
		_batch.set_draw_distance("flower_%d" % f, flower_distance)
		_batch.set_no_shadow("flower_%d" % f)
	_batch.set_draw_distance("gclump_%d" % clump, clump_distance)
	_batch.set_no_shadow("gclump_%d" % clump)


func _build_plaza(rect: Rect2, rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-2.0)
	var center := inner.get_center()
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.02, center.y), Vector3(inner.size.x, 0.04, inner.size.y), style.plaza, false, PropFactory.road("paving", 2.5, Color(0.92, 0.89, 0.84), hash([plan.seed, ix, iz, "plaza"]), 3.0, 0.35))
	if level != Level.FULL:
		return
	var basin_r := minf(inner.size.x, inner.size.y) * 0.12
	var stone := Color(0.6, 0.58, 0.55)
	_add_cylinder(Vector3(center.x, SIDEWALK_TOP + 0.45, center.y), basin_r, 0.9, stone)
	_add_cylinder(Vector3(center.x, SIDEWALK_TOP + 0.8, center.y), basin_r - 0.5, 0.3, style.water, false, true)
	_add_cylinder(Vector3(center.x, SIDEWALK_TOP + 1.9, center.y), 0.6, 2.6, stone)
	_add_cylinder(Vector3(center.x, SIDEWALK_TOP + 3.3, center.y), 1.3, 0.25, stone, false)
	var ring := basin_r + 6.0
	for i in 4:
		var angle := i * PI * 0.5 + PI * 0.25
		var p := center + Vector2(cos(angle), sin(angle)) * ring
		_add_slab(Vector3(p.x, SIDEWALK_TOP + 0.35, p.y), Vector3(2.4, 0.7, 2.4), Color(0.55, 0.5, 0.45))
		_add_tree(Vector3(p.x, SIDEWALK_TOP + 0.7, p.y), rng)
	for i in 8:
		var angle := i * PI * 0.25
		var p := center + Vector2(cos(angle), sin(angle)) * (basin_r + 3.0)
		_add_bench(Vector3(p.x, SIDEWALK_TOP + 0.04, p.y), -angle + PI * 0.5)
	for dx: float in [-1.0, 1.0]:
		for dz: float in [-1.0, 1.0]:
			_add_lamp(Vector3(center.x + dx * inner.size.x * 0.3, SIDEWALK_TOP + 0.04, center.y + dz * inner.size.y * 0.3))
	_furnish_plaza(inner, basin_r)


## A whole block of paving round one fountain read as an empty tan square from the street and
## the air. So the plaza gets what real ones have: a raised planting bed in each quadrant (ground
## cover, shrubs, a tree or two), a row of trees in grates down the promenade along each long
## side, and benches facing the beds. Everything from a private rng (after the block rng's own
## rolls above), so no roll the chunk made before moves, and nothing inside `keep` of the
## fountain's ring or of the four lamps.
func _furnish_plaza(inner: Rect2, basin_r: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, ix, iz, "plaza_furniture"])
	var center := inner.get_center()
	var keep := basin_r + 9.0
	var curb := Color(0.62, 0.6, 0.56)
	var lawn := PropFactory.lawn(Color(0.40, 0.52, 0.24), hash([plan.seed, ix, iz, "plaza_bed"]), 0.2, 0.0)
	# The beds: one per quadrant, between the fountain's ring and the promenade.
	var bw := clampf(inner.size.x * 0.24, 8.0, 26.0)
	var bd := clampf(inner.size.y * 0.24, 8.0, 26.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var off := Vector2(sx * maxf(keep + bw * 0.5, inner.size.x * 0.26), sz * maxf(keep * 0.7 + bd * 0.5, inner.size.y * 0.26))
			var c := center + off
			var bed := Rect2(c - Vector2(bw, bd) * 0.5, Vector2(bw, bd))
			if not inner.grow(-7.0).encloses(bed):
				continue
			# A low stone curb round a lawn, 45 cm up, which you can sit on.
			for e in 4:
				var horiz := e < 2
				var side_len := bw if horiz else bd
				var pos := c + (Vector2(0.0, (bd * 0.5) * (1.0 if e == 0 else -1.0)) if horiz else Vector2((bw * 0.5) * (1.0 if e == 2 else -1.0), 0.0))
				_add_slab(Vector3(pos.x, SIDEWALK_TOP + 0.22, pos.y), Vector3(side_len + 0.5 if horiz else 0.5, 0.45, 0.5 if horiz else side_len + 0.5), curb)
			_add_slab(Vector3(c.x, SIDEWALK_TOP + 0.4, c.y), Vector3(bw - 0.5, 0.04, bd - 0.5), style.grass, false, lawn)
			var inside := bed.grow(-1.2)
			_scatter_ground_cover(inside, rng, 0.8)
			for i in clampi(int(bw * bd / 40.0), 2, 10):
				var p := Vector2(rng.randf_range(inside.position.x, inside.end.x), rng.randf_range(inside.position.y, inside.end.y))
				_add_bush(Vector3(p.x, SIDEWALK_TOP + 0.42, p.y), rng)
			var trees := 1 if bw * bd < 200.0 else 2
			for i in trees:
				var p := inside.get_center() + Vector2(rng.randf_range(-0.25, 0.25) * inside.size.x, rng.randf_range(-0.25, 0.25) * inside.size.y)
				_add_tree(Vector3(p.x, SIDEWALK_TOP + 0.42, p.y), rng)
			# Benches along the bed's side that faces the fountain.
			var face := Vector2(0.0, -sz)
			var edge_p := c + Vector2(0.0, -sz * (bd * 0.5 + 1.4))
			for k in 2:
				var bp := edge_p + Vector2((float(k) - 0.5) * bw * 0.5, 0.0)
				_add_bench(Vector3(bp.x, SIDEWALK_TOP + 0.04, bp.y), atan2(-face.x, -face.y))
	# Trees in grates down the promenade along the two long sides.
	var long_x := inner.size.x >= inner.size.y
	var run := inner.size.x if long_x else inner.size.y
	var n := int((run - 16.0) / PLAZA_TREE_STEP)
	for side: float in [-1.0, 1.0]:
		for i in n:
			var t := -run * 0.5 + 8.0 + (float(i) + 0.5) * (run - 16.0) / float(maxi(n, 1))
			var across := ((inner.size.y if long_x else inner.size.x) * 0.5 - 4.5) * side
			var p := center + (Vector2(t, across) if long_x else Vector2(across, t))
			_batch.add("tree_grate", PropFactory.box("tree_grate", Vector3(1.6, 0.03, 1.6), Color(0.12, 0.12, 0.13)), Transform3D(Basis(), Vector3(p.x, SIDEWALK_TOP + 0.045, p.y)))
			_add_tree(Vector3(p.x, SIDEWALK_TOP + 0.04, p.y), rng)


func _build_sidewalk_props(rect: Rect2, params: Dictionary, rng: RandomNumberGenerator, block_district: int = 0) -> void:
	var tree_chance: float = params.trees
	var lamp_spacing: float = style.lamp_spacing
	# A real boulevard plants its street trees about every ten metres, not every twelve.
	var tree_spacing: float = style.tree_spacing * street_tree_spacing
	var edges := [
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(0.0, 1.0)],
		[Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Vector2(0.0, -1.0)],
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Vector2(1.0, 0.0)],
		[Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), Vector2(-1.0, 0.0)],
	]
	var hydrant_edge := rng.randi() % 4
	var cans_left: int = style.trash_cans_per_block
	for e in edges.size():
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var t := lamp_spacing * (0.5 if e % 2 == 0 else 0.25)
		while t < length - 4.0:
			var p := a + dir * t + inward
			if not Alleys.in_mouth(plan, ix, iz, p) and not Broadway.lamp(self, p, inward):
				_add_lamp(Vector3(p.x, SIDEWALK_TOP, p.y))
			t += lamp_spacing
		t = tree_spacing * 0.75
		while t < length - 4.0:
			if rng.randf() < tree_chance and fmod(t, lamp_spacing) > 3.0:
				# 1.3 rather than 1.6: every 30 cm back toward the kerb is 30 cm of crown that
				# is over the street instead of inside the building on the lot line.
				var p := a + dir * t + inward * 1.3
				if Alleys.in_mouth(plan, ix, iz, p):
					# Not across an alley's mouth (Alleys): the tree's rolls are still made, into a
					# batch nobody builds, so the block's stream is the same.
					var real := _batch
					_batch = MultiMeshBatch.new()
					_add_tree(Vector3(p.x, SIDEWALK_TOP, p.y), rng, -inward)
					_batch = real
					t += tree_spacing
					continue
				_batch.add("tree_grate", PropFactory.box("tree_grate", Vector3(1.6, 0.03, 1.6), Color(0.12, 0.12, 0.13)), Transform3D(Basis(), Vector3(p.x, SIDEWALK_TOP + 0.005, p.y)))
				_add_tree(Vector3(p.x, SIDEWALK_TOP, p.y), rng, -inward)
			elif rng.randf() < tree_chance * 0.5:
				var p := a + dir * (t + tree_spacing * 0.4) + inward * 2.2
				var real := _batch
				if Alleys.in_mouth(plan, ix, iz, p):
					_batch = MultiMeshBatch.new()
				_add_bush(Vector3(p.x, SIDEWALK_TOP, p.y), rng)
				_batch = real
			t += tree_spacing
		if e == hydrant_edge:
			var p := a + dir * rng.randf_range(6.0, length - 6.0) + inward
			var aged := rng.randf() < 0.4
			_add_prop("hydrant", Vector3(p.x, SIDEWALK_TOP, p.y), Color(0.85, 0.15, 0.12), [
				["hydrant_aged" if aged else "hydrant", PropFactory.model_hydrant(aged), Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), Vector3(p.x, SIDEWALK_TOP, p.y))],
			], [[Vector3(0.3, 0.8, 0.3), Vector3(p.x, SIDEWALK_TOP + 0.4, p.y), 0.0]])
		if cans_left > 0 and rng.randf() < 0.6 and PhysicsBudget.can_spawn():
			cans_left -= 1
			var p := a + dir * rng.randf_range(4.0, length - 4.0) + inward * 1.3
			var can := TrashCan.new()
			can.rusty = rng.randf() < 0.35
			can.position = Vector3(p.x, SIDEWALK_TOP + 0.02 + _gy(p.x, p.y), p.y)
			can.rotation.y = rng.randf_range(0.0, TAU)
			add_child(can)
	_build_clutter(rect, edges, params, rng)
	StreetDetail.build_block(self, rect, edges, params, block_district, rng)
	# The shelters of the bus lines' stops on this block (hash-seeded, no rng).
	BigVehicles.build_bus_stops(self, rect, edges)


# --- Intersections ---------------------------------------------------------------------

func _build_intersection(inter: Dictionary) -> void:
	# A T where a road closed by a landmark's site meets its edge: no crossings, signals or signs
	# for an arm that is not there.
	if plan.junction_closed(ix + 1, iz + 1):
		return
	var pos: Vector2 = inter.pos
	var size: Vector2 = inter.size
	var kind: CityPlan.Intersection = inter.kind
	var rng := RandomNumberGenerator.new()
	rng.seed = inter.seed
	if kind == CityPlan.Intersection.ROUNDABOUT:
		var r := minf(size.x, size.y) * 0.3
		_add_cylinder(Vector3(pos.x, ROAD_TOP + 0.15, pos.y), r, 0.3, style.sidewalk)
		_add_cylinder(Vector3(pos.x, ROAD_TOP + 0.31, pos.y), r - 0.8, 0.04, style.grass, false)
		_add_tree(Vector3(pos.x, ROAD_TOP + 0.3, pos.y), rng)
		return
	StreetDetail.build_intersection(self, pos, size, kind, rng)
	if kind == CityPlan.Intersection.PLAIN:
		return
	_add_crosswalks(pos, size, inter.seed)
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for c: Vector2 in corners:
		var corner := pos + Vector2(c.x * (size.x * 0.5 + 1.2), c.y * (size.y * 0.5 + 1.2))
		var at := Vector3(corner.x, SIDEWALK_TOP, corner.y)
		if kind == CityPlan.Intersection.STOP_SIGNS:
			var face := Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, atan2(-c.x, -c.y))
			_add_prop("stop_sign", at, Color(0.8, 0.12, 0.1), [
				["sign_pole", PropFactory.sign_pole(), Transform3D(Basis(), at + Vector3(0.0, 1.3, 0.0))],
				["stop_sign", PropFactory.stop_sign(), Transform3D(face, at + Vector3(0.0, 2.4, 0.0))],
			], [[Vector3(0.3, 2.8, 0.3), at + Vector3(0.0, 1.4, 0.0), 0.0]])
		elif not _add_signal_corner(at, c, size):
			_add_signal(at, c, size)
	if kind == CityPlan.Intersection.SIGNALS:
		_add_signal_cabinet(pos, size)


## Crosswalk styles by intersection seed: 0 zebra, 1 wide continental bars, 2 ladder edges.
func _add_crosswalks(pos: Vector2, size: Vector2, kind_seed: int = 0) -> void:
	var style_id := absi(kind_seed) % 3
	var step := 1.4 if style_id == 0 else 1.9
	# No stripe over the freight trench (FreightRail.cuts_in()): the road is not there.
	var holes: Array = []
	var freight := FreightRail.of(plan)
	if freight != null:
		holes = freight.cuts_in(Rect2(pos - size * 0.5, size).grow(4.0))
	var bar := Basis().scaled(Vector3(1.0 if style_id == 0 else 1.6, 1.0, 1.0))
	for side: float in [-1.0, 1.0]:
		var z := pos.y + side * (size.y * 0.5 + 1.8)
		if style_id == 2:
			# A ladder's two rails run ACROSS the crossing, so on the z sides they run along x,
			# size.x long and 0.24 m wide. The yaw puts the stripe's length on world x and
			# Basis.scaled() scales world axes, so the length factor goes in x and the width
			# factor in z. The two branches of this function had each other's basis: these
			# rails ran along z instead, and the ones below came out a hundred metres wide.
			for edge: float in [-1.4, 1.4]:
				if not _in_holes(holes, Vector2(pos.x, z + edge), size.x * 0.5):
					_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(size.x / 3.0, 1.0, 0.4)), Vector3(pos.x, ROAD_TOP + 0.015, z + edge)))
		else:
			var x := pos.x - size.x * 0.5 + 1.2
			while x < pos.x + size.x * 0.5 - 0.6:
				if not _in_holes(holes, Vector2(x, z)):
					_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(Vector3.UP, PI * 0.5) * bar, Vector3(x, ROAD_TOP + 0.015, z)))
				x += step
		var xx := pos.x + side * (size.x * 0.5 + 1.8)
		if style_id == 2:
			# On the x sides the rails run along z, which is the stripe's own length axis, so
			# no yaw and the factors are already in the right places.
			for edge: float in [-1.4, 1.4]:
				if not _in_holes(holes, Vector2(xx + edge, pos.y)):
					_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis().scaled(Vector3(0.4, 1.0, size.y / 3.0)), Vector3(xx + edge, ROAD_TOP + 0.015, pos.y)))
		else:
			var zz := pos.y - size.y * 0.5 + 1.2
			while zz < pos.y + size.y * 0.5 - 0.6:
				if not _in_holes(holes, Vector2(xx, zz)):
					_batch.add("stripe", PropFactory.stripe(), Transform3D(bar, Vector3(xx, ROAD_TOP + 0.015, zz)))
				zz += step


static func _in_holes(holes: Array, p: Vector2, half_x: float = 0.0) -> bool:
	for h: Rect2 in holes:
		if h.grow(0.6).intersects(Rect2(p.x - half_x, p.y, half_x * 2.0 + 0.001, 0.001)):
			return true
	return false


## Heights on a signal pole (metres above the pavement): the side-mount head's bracket, the
## pedestrian heads, the push buttons.
const SIGNAL_SIDE_Y := 4.6
const SIGNAL_PED_Y := 2.7
const SIGNAL_BUTTON_Y := 1.05
## How far past the innermost lane centre a mast arm runs (metres).
const SIGNAL_ARM_OVERRUN := 0.6
## Draw distances (metres). A lit lens is what reads a junction from a block away, and at night
## from much further, so the heads go out furthest; the pedestrian heads and buttons are for the
## pavement.
const SIGNAL_HEAD_DRAW := 420.0
const SIGNAL_PED_DRAW := 160.0
const SIGNAL_SMALL_DRAW := 70.0


## One corner of a signalised intersection (owner, 2026-09-24: "GTA-level street life"), laid out
## the way US junctions are: each corner's pole carries the mast arm for the approach it stands
## on the far right of, with a head over every lane of that approach and a second head low on
## the pole, plus the two pedestrian heads facing back across the two crosswalks that end here
## and their push buttons. Every head is an instance in the chunk's MultiMesh batch whose custom
## data is the intersection's offset into TrafficSignals' cycle and the axis it serves, so the
## lens shader lights it with no node of its own. False when the model is missing (the caller
## then builds the old primitive signal).
func _add_signal_corner(at: Vector3, c: Vector2, size: Vector2) -> bool:
	var pole_mesh := PropFactory.signal_part("sig_pole")
	if pole_mesh.get_surface_count() == 0:
		return false
	var head_mesh := PropFactory.signal_part("sig_head")
	var ped_mesh := PropFactory.signal_part("sig_ped")
	var off := TrafficSignals.offset01(plan, ix + 1, iz + 1)
	# The approach this corner is the far right of: (-1, +1) and (+1, -1) face traffic on the
	# north-south (AXIS_X) road, the other two traffic on the east-west one. `dir` is that
	# traffic's direction of travel (TrafficManager._lane_offset puts it on the right).
	var on_x := c.x * c.y < 0.0
	var axis := CityPlan.AXIS_X if on_x else CityPlan.AXIS_Z
	var dir := c.y if on_x else c.x
	var arm_dir := Vector3(-c.x, 0.0, 0.0) if on_x else Vector3(0.0, 0.0, -c.y)
	var facing := Vector3(0.0, 0.0, -dir) if on_x else Vector3(-dir, 0.0, 0.0)
	var width: float = size.x if on_x else size.y
	var lanes := 2 if width > plan.street_width + 1.0 else 1
	# From the pole to each lane centre of the approach: the pole stands 1.2 m in from the kerb.
	var reach := width * 0.5 + 1.2
	var heads: Array[float] = []
	var arm_len := 0.0
	for n in lanes:
		var d := reach - CityPlan.lane_center(width, lanes, n)
		heads.append(d)
		arm_len = maxf(arm_len, d + SIGNAL_ARM_OVERRUN)
	var arm_y := PropFactory.SIGNAL_ARM_Y
	var arm_yaw := atan2(-arm_dir.z, arm_dir.x)
	var head_yaw := atan2(facing.x, facing.z)
	var custom := Color(off, float(axis), 0.0, 0.0)
	var instances := [
		# The handhole away from the corner.
		["sig_pole", pole_mesh, Transform3D(Basis(Vector3.UP, atan2(-c.x, -c.y)), at)],
		["sig_arm", PropFactory.signal_part("sig_arm"), Transform3D(Basis(Vector3.UP, arm_yaw).scaled_local(Vector3(arm_len / PropFactory.SIGNAL_ARM_LENGTH, 1.0, 1.0)), at + Vector3(0.0, arm_y, 0.0))],
		["sig_bracket", PropFactory.signal_part("sig_bracket"), Transform3D(Basis(Vector3.UP, arm_yaw), at + Vector3(0.0, SIGNAL_SIDE_Y, 0.0))],
		["sig_head", head_mesh, Transform3D(Basis(Vector3.UP, head_yaw), at + arm_dir * PropFactory.SIGNAL_BRACKET_REACH + Vector3(0.0, SIGNAL_SIDE_Y, 0.0)), Color.WHITE, custom],
	]
	for d in heads:
		instances.append(["sig_head", head_mesh, Transform3D(Basis(Vector3.UP, head_yaw), at + arm_dir * d + Vector3(0.0, arm_y, 0.0)), Color.WHITE, custom])
	# The crosswalk across the north-south road ends here too, and the one across the east-west
	# road: a pedestrian head for each, facing the people waiting at its other end, and a button
	# for the people waiting at this end.
	for across_x: bool in [true, false]:
		var face := Vector3(-c.x, 0.0, 0.0) if across_x else Vector3(0.0, 0.0, -c.y)
		var crossing := CityPlan.AXIS_X if across_x else CityPlan.AXIS_Z
		instances.append(["sig_ped", ped_mesh, Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), at + Vector3(0.0, SIGNAL_PED_Y, 0.0)), Color.WHITE, Color(off, float(crossing), 0.0, 0.0)])
		var press := Vector3(0.0, 0.0, c.y) if across_x else Vector3(c.x, 0.0, 0.0)
		instances.append(["sig_button", PropFactory.signal_part("sig_button"), Transform3D(Basis(Vector3.UP, atan2(press.x, press.z)), at + Vector3(0.0, SIGNAL_BUTTON_Y, 0.0))])
	var pole_h := PropFactory.SIGNAL_POLE_HEIGHT
	_add_prop("signal", at, Color(0.5, 0.51, 0.52), instances, [
		[Vector3(0.34, pole_h, 0.34), at + Vector3(0.0, pole_h * 0.5, 0.0), 0.0],
		[Vector3(arm_len - 0.2, 0.26, 0.26), at + arm_dir * (arm_len * 0.5 + 0.1) + Vector3(0.0, arm_y, 0.0), arm_yaw],
	])
	_batch.set_draw_distance("sig_head", SIGNAL_HEAD_DRAW)
	_batch.set_draw_distance("sig_ped", SIGNAL_PED_DRAW)
	_batch.set_draw_distance("sig_button", SIGNAL_SMALL_DRAW)
	_batch.set_no_shadow("sig_button")
	return true


## The signal controller: one cabinet per signalised junction, on the pavement of a seeded
## corner, back against the lot line of the north-south road's pavement and past the crosswalk,
## door to the street. The box that makes the heads change, as far as anyone on the pavement can
## tell. Out of the band people walk (1-3 m from the kerb): at 3 m it stood square across the
## route round the block and a walker walked into its door and stayed there.
const SIGNAL_CABINET_INSET := 3.6
func _add_signal_cabinet(pos: Vector2, size: Vector2) -> void:
	var mesh := PropFactory.signal_part("sig_cabinet")
	if mesh.get_surface_count() == 0:
		return
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	var c: Vector2 = corners[absi(hash([plan.seed, "signal_cabinet", ix, iz])) % corners.size()]
	var inset := minf(SIGNAL_CABINET_INSET, plan.sidewalk_width - 0.3)
	var p := pos + Vector2(c.x * (size.x * 0.5 + inset), c.y * (size.y * 0.5 + 6.0))
	var at := Vector3(p.x, SIDEWALK_TOP, p.y)
	var yaw := atan2(-c.x, 0.0)
	_add_prop("signal_cabinet", at, Color(0.66, 0.68, 0.63), [
		["sig_cabinet", mesh, Transform3D(Basis(Vector3.UP, yaw), at)],
	], [[Vector3(0.8, 1.6, 0.56), at + Vector3(0.0, 0.8, 0.0), yaw]])
	_batch.set_draw_distance("sig_cabinet", SIGNAL_PED_DRAW)


## The old primitive signal: a pole, an arm and three always-lit spheres. Only built when
## traffic_signal.glb is missing.
func _add_signal(at: Vector3, corner: Vector2, size: Vector2) -> void:
	var along_x := size.x >= size.y
	var dir := Vector3(-corner.x, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, -corner.y)
	var yaw := 0.0 if along_x else PI * 0.5
	var arm_center := at + Vector3(0.0, 6.2, 0.0) + dir * 2.5
	var box_pos := at + Vector3(0.0, 5.5, 0.0) + dir * 4.6
	var instances := [
		["signal_pole", PropFactory.signal_pole(), Transform3D(Basis(), at + Vector3(0.0, 3.25, 0.0))],
		["signal_arm", PropFactory.signal_arm(), Transform3D(Basis(Vector3.UP, yaw), arm_center)],
		["signal_box", PropFactory.signal_box(), Transform3D(Basis(), box_pos)],
	]
	var colors := [Color(1.0, 0.2, 0.15), Color(1.0, 0.8, 0.2), Color(0.2, 1.0, 0.3)]
	var facing := (Vector3(0.0, 0.0, 0.2) if along_x else Vector3(0.2, 0.0, 0.0)) * (corner.y if along_x else corner.x)
	for i in 3:
		instances.append(["signal_light_%d" % i, PropFactory.signal_light(colors[i]), Transform3D(Basis(), box_pos + Vector3(0.0, 0.32 - i * 0.32, 0.0) + facing)])
	_add_prop("signal", at, Color(0.2, 0.2, 0.22), instances, [[Vector3(0.3, 6.5, 0.3), at + Vector3(0.0, 3.25, 0.0), 0.0]])


# --- Props (destructible) --------------------------------------------------------------

## Registers a breakable prop: MultiMesh instances plus collision shapes tagged with its record.
## Skipped entirely if WorldState says this prop was already destroyed.
func _add_prop(kind: String, at: Vector3, color: Color, instances: Array, shapes: Array) -> void:
	var id := "%s_%d" % [kind, _prop_counter]
	_prop_counter += 1
	if WorldState.is_destroyed(key, id):
		return
	var g := _gy(at.x, at.z)
	var record := {"id": id, "kind": kind, "position": at + Vector3(0.0, g, 0.0), "color": color, "health": PROP_HEALTH.get(kind, 20.0), "instances": [], "shapes": [], "dead": false}
	for inst in instances:
		# A fifth entry is the instance's custom data (a signal head's timing, see _add_signal_corner).
		var index := _batch.add(inst[0], inst[1], inst[2], inst[3] if inst.size() > 3 else Color.WHITE, inst[4] if inst.size() > 4 else Color.BLACK)
		record.instances.append([inst[0], index])
	for s in shapes:
		var shape := _add_shape(s[0], s[1] + Vector3(0.0, g, 0.0), s[2])
		if shape:
			shape.set_meta("prop", record)
			record.shapes.append(shape)
	prop_records.append(record)


func damage_prop(record: Dictionary, damage: float, hit_dir: Vector3) -> void:
	if record.dead:
		return
	record.health -= damage
	if record.health <= 0.0:
		break_prop(record, hit_dir)


func break_prop(record: Dictionary, hit_dir: Vector3 = Vector3.UP) -> void:
	if record.dead:
		return
	record.dead = true
	for inst in record.instances:
		MultiMeshBatch.hide_instance(_mm_nodes.get(inst[0]), inst[1])
	for shape in record.shapes:
		if is_instance_valid(shape):
			shape.queue_free()
	WorldState.mark_destroyed(key, record.id)
	Sfx.play("break", record.position)
	_spawn_debris(record.position, record.color, hit_dir)


func _spawn_debris(at: Vector3, color: Color, hit_dir: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([at.x, at.z, Time.get_ticks_msec()])
	var pieces := 4
	if not PhysicsBudget.make_room(pieces):
		return
	for i in pieces:
		var body := RigidBody3D.new()
		body.collision_layer = 4
		body.collision_mask = 7
		body.mass = 1.5
		var size := Vector3(rng.randf_range(0.2, 0.5), rng.randf_range(0.3, 1.2), rng.randf_range(0.2, 0.5))
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = PropFactory.material(color)
		body.add_child(mesh)
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		body.add_child(shape)
		body.position = at + Vector3(rng.randf_range(-0.4, 0.4), 0.6 + i * 0.7, rng.randf_range(-0.4, 0.4))
		add_child(body)
		PhysicsBudget.register_debris(body)
		body.linear_velocity = (hit_dir.normalized() * 6.0 + Vector3(rng.randf_range(-3, 3), rng.randf_range(4, 9), rng.randf_range(-3, 3)))
		body.angular_velocity = Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6))


## Diameter of the pool of light a street lamp throws, and how far up the light itself sits.
const LAMP_POOL_SIZE := 13.0
const LAMP_LIGHT_HEIGHT := 3.5


func _add_lamp(at: Vector3) -> void:
	# The pool of light on the pavement rides in the same batch as the lamp, so shooting the
	# lamp out takes its light with it. It is additive and unshaded, and the only thing lighting
	# the street on the web build.
	# Basis.scaled() is a LEFT multiply - Godot scales the basis ROWS - so the factors land on
	# the WORLD axes, after the rotation, not on the quad's own. Laid flat the quad spans world
	# X and Z, so the size goes in x and z and the 1.0 goes in y (the normal). Written the
	# obvious way round, (SIZE, SIZE, 1.0), the second SIZE was spent on the normal of an
	# unshaded shader and every lamp in the city threw a 13 x 1 m bar instead of a 13 m disc.
	# 9 cm up: at 5 cm it lay exactly on the yard ground beside the pavement (YardFill's and
	# Industrial's, both 5 cm over it) and z-fought it in stripes at night. Additive and drawing
	# no depth, it looks the same wherever it lies.
	var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(LAMP_POOL_SIZE, 1.0, LAMP_POOL_SIZE)), at + Vector3(0.0, 0.09, 0.0))
	_add_prop("lamp", at, Color(0.28, 0.29, 0.32), [
		["lamp", PropFactory.model_lamp(), Transform3D(Basis(Vector3.UP, fmod(absf(at.x * 7.3 + at.z * 3.1), TAU)), at), _lamp_tint],
		["lamp_pool", PropFactory.light_pool(), pool, NightCity.pool_color(Vector2(at.x, at.z))],
	], [[Vector3(0.3, 3.9, 0.3), at + Vector3(0.0, 1.95, 0.0), 0.0]])
	_batch.set_no_shadow("lamp_pool")
	if level != Level.FULL:
		return
	# A real light as well, so the lamp actually lifts the people and cars under it. DayNight
	# drives the whole group's energy; Quality turns them off at the low levels.
	var light := OmniLight3D.new()
	light.position = at + Vector3(0.0, LAMP_LIGHT_HEIGHT + _gy(at.x, at.z), 0.0)
	light.omni_range = 11.0
	light.omni_attenuation = 1.4
	# Sodium or LED by where it stands, as the far streets' glow says (NightCity.lamp_led()).
	light.light_color = NightCity.lamp_light(Vector2(at.x, at.z))
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 15.0
	light.add_to_group("lamp_light")
	add_child(light)


## `yaw` is the direction the bench faces (forward is -Z).
func _add_bench(at: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_add_prop("bench", at, Color(0.5, 0.36, 0.22), [
		["bench", PropFactory.model_bench(), Transform3D(basis, at)],
	], [[Vector3(1.9, 0.9, 0.7), at + Vector3(0.0, 0.45, 0.0), yaw]])
	# Its two seats, for the walkers on this chunk to sit on (Pedestrian's life, CrowdLife).
	if not prop_records.is_empty() and prop_records.back().kind == "bench" and level == Level.FULL:
		CrowdLife.add_seat(self, at + Vector3(0.0, _gy(at.x, at.z), 0.0), yaw, prop_records.back())


## District clutter on the sidewalk ring: cafe tables downtown, planters on leafy blocks, barrels,
## tyres and concrete barriers on industrial blocks. `edges` are [a, b, inward] like the props.
func _build_clutter(_rect: Rect2, edges: Array, params: Dictionary, rng: RandomNumberGenerator) -> void:
	var cafes: int = params.get("cafes", 0)
	var planters: int = params.get("planters", 0)
	var clutter: int = params.get("clutter", 0)
	for i in cafes:
		var e: Array = edges[rng.randi() % 4]
		var yaw := atan2(-e[2].x, -e[2].y)
		var p: Vector2 = _edge_point(e, rng, 6.0) + e[2] * 2.6
		_add_prop("cafe", Vector3(p.x, SIDEWALK_TOP, p.y), Color(0.25, 0.25, 0.27), [
			["cafe_set", PropFactory.model_cafe_set(), Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(p.x, SIDEWALK_TOP, p.y))],
		], [[Vector3(0.9, 0.9, 1.7), Vector3(p.x, SIDEWALK_TOP + 0.45, p.y), yaw + PI * 0.5]])
	for i in planters:
		var e: Array = edges[rng.randi() % 4]
		var yaw := atan2(-e[2].x, -e[2].y)
		var p: Vector2 = _edge_point(e, rng, 5.0) + e[2] * 2.4
		_add_prop("planter", Vector3(p.x, SIDEWALK_TOP, p.y), Color(0.45, 0.32, 0.2), [
			["planter", PropFactory.model_planter(), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, SIDEWALK_TOP, p.y))],
		], [[Vector3(0.95, 0.45, 0.45), Vector3(p.x, SIDEWALK_TOP + 0.22, p.y), yaw]])
	for i in clutter:
		var e: Array = edges[rng.randi() % 4]
		var yaw := atan2(-e[2].x, -e[2].y) + rng.randf_range(-0.3, 0.3)
		var p: Vector2 = _edge_point(e, rng, 5.0) + e[2] * rng.randf_range(1.8, 3.0)
		var at := Vector3(p.x, SIDEWALK_TOP, p.y)
		var lifted := at + Vector3(0.0, _gy(p.x, p.y), 0.0)
		var roll := rng.randf()
		if roll < 0.3:
			if rng.randf() < 0.5:
				_add_prop("barrier", at, Color(0.6, 0.6, 0.58), [
					["barrier", PropFactory.model_barrier(), Transform3D(Basis(Vector3.UP, yaw), at)],
				], [[Vector3(1.55, 0.83, 0.64), at + Vector3(0.0, 0.42, 0.0), yaw]])
			else:
				_add_prop("barrier", at, Color(0.6, 0.6, 0.58), [
					["barrier_tall", PropFactory.model_barrier_tall(), Transform3D(Basis(Vector3.UP, yaw), at)],
				], [[Vector3(1.57, 1.11, 0.44), at + Vector3(0.0, 0.56, 0.0), yaw]])
		elif roll < 0.7:
			if not PhysicsBudget.can_spawn():
				continue
			var barrel := PhysicsProp.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.28
			cyl.height = 0.88
			barrel.setup(PropFactory.model_barrel(), cyl, Vector3(0.0, 0.44, 0.0), 25.0)
			barrel.position = lifted + Vector3(0.0, 0.05, 0.0)
			barrel.rotation.y = rng.randf_range(0.0, TAU)
			add_child(barrel)
		else:
			var stack := rng.randi_range(1, 3)
			for k in stack:
				if not PhysicsBudget.can_spawn():
					break
				var tyre := PhysicsProp.new()
				var disc := CylinderShape3D.new()
				disc.radius = 0.3
				disc.height = 0.16
				tyre.setup(PropFactory.model_tyre(), disc, Vector3(0.0, 0.08, 0.0), 10.0)
				tyre.position = lifted + Vector3(rng.randf_range(-0.05, 0.05), 0.05 + k * 0.17, rng.randf_range(-0.05, 0.05))
				tyre.rotation.y = rng.randf_range(0.0, TAU)
				add_child(tyre)


## A random point along a sidewalk edge, `margin` meters clear of both corners.
func _edge_point(edge: Array, rng: RandomNumberGenerator, margin: float) -> Vector2:
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	return a.lerp(b, rng.randf_range(margin, maxf(margin, a.distance_to(b) - margin)) / a.distance_to(b))


func _add_tree(at: Vector3, rng: RandomNumberGenerator, lean_to: Vector2 = Vector2.ZERO) -> void:
	if _palm_street and rng.randf() < 0.8:
		_add_palm(at, rng, false, lean_to)
		return
	var yaw := rng.randf_range(0.0, TAU)
	# Most trees on a block are its dominant species; the rest are whatever.
	var variant := _tree_bias if (_tree_bias >= 0 and rng.randf() < 0.7) else rng.randi() % PropFactory.CITY_TREES.size()
	if _jacaranda_street and rng.randf() < 0.85:
		variant = PropFactory.CITY_TREES.size() - 1
	# A target HEIGHT in metres, from that species' own range. One shared range does not work:
	# the models run from 2.6 m to 19.5 m native, and stretching one much past 1.5x leaves a
	# sparse, skeletal canopy because its leaf cards were never built to fill that volume.
	var s := PropFactory.city_tree_scale(variant, PropFactory.city_tree_height(variant, rng))
	var tint := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.05))
	# Per-instance variety, read by shaders/foliage_tex.gdshader: leaf count, canopy proportion,
	# leaf tone, and how far into bloom this one is. Five models become effectively unlimited
	# trees while staying five meshes and five draw calls - a batch IS a draw call, so making
	# fifty variant meshes would have cost fifty of them per chunk.
	var variety := Color(
		rng.randf_range(0.0, 1.0),
		rng.randf_range(0.0, 1.0),
		rng.randf_range(0.0, 1.0),
		rng.randf_range(0.25, 1.0))
	# Never under a freeway deck: nine metres up, a park or plaza tree's canopy came up through
	# the carriageway and stood in the lanes. Skipped after every roll it makes, so the rng
	# stream, and so everything planted after it, is the same as before.
	if _under_freeway(Vector2(at.x, at.z), TREE_FREEWAY_MARGIN):
		return
	# Los Angeles' own species for a share of blocks, parks and planters (LaTrees, hashes only).
	if LaTrees.street_or_park(self, at, yaw, tint, lean_to):
		return
	_batch.add("tree_%d" % variant, PropFactory.model_tree(variant), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint, variety)


# --- Helpers ---------------------------------------------------------------------------

func _add_slab(pos: Vector3, size: Vector3, color: Color, collide: bool = true, material: Material = null) -> void:
	if capturing:
		# Recorded, not built (see `capturing`). A thin slab is ground; anything thicker is a
		# solid box, lifted by one relief sample at its centre exactly as below.
		if size.y <= 0.5:
			# Its far colour is worked out the way the build below would draw it: a city ground
			# slab goes into the merged ground at far_tint(), anything else is a box wearing its
			# material (an airport apron, a port yard - road() at a tint well above 1).
			var far_col := far_tint(color, style.asphalt)
			if not (zone == MacroMap.Zone.CITY and maxf(size.x, size.z) >= 6.0):
				far_col = PropFactory.far_albedo(material if material else PropFactory.material(color, 0.95), far_col)
			captured.ground.append([Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z), color, pos.y + size.y * 0.5, far_col])
		else:
			captured.boxes.append([Transform3D(Basis().scaled(size), pos + Vector3(0.0, _gy(pos.x, pos.z), 0.0)), color])
		return
	var mat: Material = material if material else PropFactory.material(color, 0.95)
	if zone == MacroMap.Zone.CITY and size.y <= 0.5 and maxf(size.x, size.z) >= 6.0:
		# Thin ground slab in the city (road, sidewalk, lawn, plaza): follow the relief.
		_add_ground_grid(Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z), pos.y + size.y * 0.5, size.y + 0.5, mat, collide, color)
		return
	var lifted := pos + Vector3(0.0, _gy(pos.x, pos.z), 0.0)
	if merge_boxes and not _boxes_committed:
		_merge_box(mat, size, lifted)
	else:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = mat
		mesh.position = lifted
		add_child(mesh)
	if collide:
		_add_shape(size, lifted)


## Solid boxes (_add_slab's non-ground path: big-box walls, their pilasters, base bands and
## parapets, planters, port and airport pads, the crane) are merged per material into ONE mesh a
## chunk, committed at the finish (_commit_boxes). Each used to be its own MeshInstance3D, so its
## own draw call - and again in the depth pre-pass and in every shadow cascade it falls in: a
## big box is twenty-odd of them, and 300-530 were standing in every bookmark's streamed ring,
## most of them in the LOD chunks, casting into the far cascades. Merging is exact: the vertices
## are BoxMesh's own (unit_box_arrays(), scaled and moved), every material that comes through
## here maps its textures in world space (PropFactory.pbr() is world-triplanar, material() is a
## flat colour, road() works in world space) or reads BoxMesh's UV atlas, which does not depend
## on the size, and the whole set still casts and receives like before.
## `merge_boxes` false builds them one node each, as before (the A/B for a frame-cost
## measurement: still_shot.gd MERGE_STATIC=0).
static var merge_boxes: bool = true
## Material -> [verts, normals, tangents, uvs, indices].
var _boxes: Dictionary = {}
## Set once the boxes are committed; anything added after that is built as its own node again.
var _boxes_committed: bool = false
static var _unit_box: Array = []


## BoxMesh's arrays for a 1 m cube, read once. Normals and tangents are snapped back onto the
## axes (they come back through the vertex compression a few 1e-5 off).
static func unit_box_arrays() -> Array:
	if _unit_box.is_empty():
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		var a := box.get_mesh_arrays()
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		for i in n.size():
			n[i] = n[i].round()
		var t: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
		for i in t.size():
			t[i] = roundf(t[i])
		_unit_box = [a[Mesh.ARRAY_VERTEX], n, t, a[Mesh.ARRAY_TEX_UV], a[Mesh.ARRAY_INDEX]]
	return _unit_box


func _merge_box(mat: Material, size: Vector3, at: Vector3) -> void:
	var unit := unit_box_arrays()
	var acc: Array = _boxes.get(mat, [])
	if acc.is_empty():
		acc = [PackedVector3Array(), PackedVector3Array(), PackedFloat32Array(), PackedVector2Array(), PackedInt32Array()]
		_boxes[mat] = acc
	# Take the arrays out of the list while they grow: a packed array is copy-on-write, and one
	# still referenced from `acc` would be copied whole on every append.
	var verts: PackedVector3Array = acc[0]
	var normals: PackedVector3Array = acc[1]
	var tangents: PackedFloat32Array = acc[2]
	var uvs: PackedVector2Array = acc[3]
	var idx: PackedInt32Array = acc[4]
	acc.fill(null)
	var base := verts.size()
	for v: Vector3 in unit[0]:
		verts.append(v * size + at)
	normals.append_array(unit[1])
	tangents.append_array(unit[2])
	uvs.append_array(unit[3])
	for i: int in unit[4]:
		idx.append(base + i)
	acc[0] = verts
	acc[1] = normals
	acc[2] = tangents
	acc[3] = uvs
	acc[4] = idx


## `_merge_box()` for a box with any transform (its basis scaled to the box's size): the hill
## estates' pads and walls, turned to face their road.
func _merge_box_xf(mat: Material, xf: Transform3D) -> void:
	if not merge_boxes or _boxes_committed:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		mesh.mesh = box
		mesh.material_override = mat
		mesh.transform = xf
		add_child(mesh)
		return
	var unit := unit_box_arrays()
	var acc: Array = _boxes.get(mat, [])
	if acc.is_empty():
		acc = [PackedVector3Array(), PackedVector3Array(), PackedFloat32Array(), PackedVector2Array(), PackedInt32Array()]
		_boxes[mat] = acc
	var verts: PackedVector3Array = acc[0]
	var normals: PackedVector3Array = acc[1]
	var tangents: PackedFloat32Array = acc[2]
	var uvs: PackedVector2Array = acc[3]
	var idx: PackedInt32Array = acc[4]
	acc.fill(null)
	var base := verts.size()
	var rot := xf.basis.orthonormalized()
	for v: Vector3 in unit[0]:
		verts.append(xf * v)
	for nrm: Vector3 in unit[1]:
		normals.append(rot * nrm)
	var t: PackedFloat32Array = unit[2]
	for i in range(0, t.size(), 4):
		var tv := rot * Vector3(t[i], t[i + 1], t[i + 2])
		tangents.append_array([tv.x, tv.y, tv.z, t[i + 3]])
	uvs.append_array(unit[3])
	for i: int in unit[4]:
		idx.append(base + i)
	acc[0] = verts
	acc[1] = normals
	acc[2] = tangents
	acc[3] = uvs
	acc[4] = idx


func _commit_boxes() -> void:
	_boxes_committed = true
	var n := 0
	for mat: Material in _boxes:
		var acc: Array = _boxes[mat]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = acc[0]
		arrays[Mesh.ARRAY_NORMAL] = acc[1]
		arrays[Mesh.ARRAY_TANGENT] = acc[2]
		arrays[Mesh.ARRAY_TEX_UV] = acc[3]
		arrays[Mesh.ARRAY_INDEX] = acc[4]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "Boxes%d" % n
		mi.mesh = mesh
		mi.material_override = mat
		add_child(mi)
		n += 1
	_boxes.clear()


## A ground surface over `rect` at `top` above the relief, with a skirt hanging `skirt` meters
## down its edges (the curb face between sidewalk and road).
##
## The drawn grid is fine (`ground_grid_step`) and the collision trimesh is built separately on
## a coarse one (`ground_collision_step`): the streets are what the player looks along for a
## hundred metres, and five-metre quads gave the relief a folded look, but physics walks on the
## shape and would only pay for the detail. Both come from the cached relief, so the fine grid
## costs about what the old coarse one did.
func _add_ground_grid(rect: Rect2, top: float, skirt: float, mat: Material, collide: bool, tint: Color = Color.WHITE) -> void:
	var far := level != Level.FULL
	var step := ground_grid_step if _detail() >= 1.0 else ground_grid_step * 2.0
	if far:
		step = maxf(step, lod_ground_grid_step)
	var nx := clampi(ceili(rect.size.x / step), 1, 120)
	var nz := clampi(ceili(rect.size.y / step), 1, 120)
	# Far chunks carry the surface's colour in the mesh itself (see below). Linear, because a
	# vertex colour reaches the shader verbatim where a material's albedo_color is decoded from
	# sRGB. Alpha marks the carriageway and which way it runs, for the street lamp glow far chunks
	# get instead of lamps (far_ground.gdshader): 1.0 along Z, 0.75 along X, 0.5 a junction, 0.25
	# a pavement, 0 anything else. A road slab is long and thin, a junction square.
	var vcolor := Color(0.0, 0.0, 0.0, 0.0)
	if far:
		var lamp := 0.0
		if tint == style.asphalt:
			lamp = 1.0 if rect.size.y > rect.size.x * 1.5 else (0.75 if rect.size.x > rect.size.y * 1.5 else 0.5)
		elif tint == style.sidewalk:
			lamp = 0.25
		# Everything but the asphalt is a textured surface up close, and a texture averages well
		# under its tint (paving, lawn and concrete sets sit about 0.6 of it): at the bare tint
		# the far pavements were twice as bright as the near ones and lit up like snow at night.
		var lin := far_tint(tint, style.asphalt)
		vcolor = Color(lin.r, lin.g, lin.b, lamp)
	var mesh := _grid_mesh(rect, top, skirt, nx, nz, far, vcolor)
	if far:
		# FAR CHUNKS: one mesh for all of it. Each ground surface used to be its own
		# MeshInstance with its own material, and at about seven a chunk across two hundred LOD
		# chunks that was ~1377 draw calls - 45% of everything the streamed city submits - for
		# flat ground a quarter of a kilometre away. Merged into a single vertex-coloured mesh
		# it is ONE. The per-surface shaders (road wear, lawn stripes, paving joints) are all
		# sub-pixel at this range; their base colour is the whole of what survives, and that is
		# exactly what the vertex colour carries. Full-detail chunks are untouched.
		if _far_ground == null:
			_far_ground = SurfaceTool.new()
			_far_ground.begin(Mesh.PRIMITIVE_TRIANGLES)
		# The colour has to be IN the appended mesh: append_from() copies the source's own
		# vertices and ignores set_color(), so the merged ground used to come out with no colour
		# at all - black - and every street, pavement and lawn in the far city was a black void
		# by day as well as by night.
		_far_ground.append_from(mesh, 0, Transform3D.IDENTITY)
		_far_ground_any = true
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		add_child(mi)
		if ground_skirt_shadows and top > ROAD_TOP + 0.001 and top <= SIDEWALK_TOP + GROUND_RIM_TOP:
			# A raised slab on the ground (the block's pavement, a lawn, a plaza, a bed; not a
			# thin slab up in the air, such as a gas station's canopy, which is ground-grid shaped
			# too and must cast all of itself) shadows nothing anyone can see with the middle of
			# its top - everything near it stands on it - so it casts from its
			# skirt (the kerb face, which draws the kerb's shadow on the road) and the ring of
			# cells along its edge (which keeps the kerb top's shadow edge, filter and all, as it
			# was). Cast whole, the block's pavement grid was ~10k triangles in every cascade
			# (HANDOFF 9bf). The road keeps its shadow: the paint and patches on it are
			# millimetres proud, and without it their edges came out lighter.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var rim := MeshInstance3D.new()
			rim.name = "GroundRim"
			rim.mesh = _grid_mesh(rect, top, skirt, nx, nz, false, Color.WHITE, true)
			rim.material_override = mat
			rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			rim.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			add_child(rim)
	if not (collide and _statics):
		return
	var cx := clampi(ceili(rect.size.x / ground_collision_step), 1, 48)
	var cz := clampi(ceili(rect.size.y / ground_collision_step), 1, 48)
	var shape := CollisionShape3D.new()
	shape.shape = (mesh if (cx == nx and cz == nz) else _grid_mesh(rect, top, skirt, cx, cz)).create_trimesh_shape()
	_statics.add_child(shape)


## The colour a ground surface is drawn in from afar (the LOD chunks' merged ground and the far
## city's block plates, which must agree): linear, and at 0.6 of its tint unless it is asphalt.
static func far_tint(tint: Color, asphalt: Color) -> Color:
	var lin := tint.srgb_to_linear() * (1.0 if tint == asphalt else 0.6)
	return Color(lin.r, lin.g, lin.b, 1.0)


## One grid of `nx` by `nz` quads over `rect`, following the relief, with the skirt around it.
## `colored` gives every vertex `color` (the far chunks' merged ground).
## `rim_only` keeps only the top's ring of edge cells and the skirt: the shadow caster of a FULL
## chunk's raised ground (_add_ground_grid).
func _grid_mesh(rect: Rect2, top: float, skirt: float, nx: int, nz: int, colored: bool = false, color: Color = Color.WHITE, rim_only: bool = false) -> ArrayMesh:
	var pts := PackedVector3Array()
	pts.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			var x := rect.position.x + rect.size.x * i / nx
			var z := rect.position.y + rect.size.y * j / nz
			pts[j * (nx + 1) + i] = Vector3(x, top + _gy(x, z), z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if colored:
		st.set_color(color)
	# UV runs 0..1 across the rect, so a road knows where its kerbs are (street_glow.gdshaderinc
	# puts the lamp pools along them). Nothing else on the city ground reads UV: those shaders
	# all work in world space.
	var inv := Vector2(1.0 / maxf(rect.size.x, 0.01), 1.0 / maxf(rect.size.y, 0.01))
	for j in nz:
		for i in nx:
			if rim_only and j > 0 and j < nz - 1 and i > 0 and i < nx - 1:
				continue
			var a := pts[j * (nx + 1) + i]
			var b := pts[j * (nx + 1) + i + 1]
			var c := pts[(j + 1) * (nx + 1) + i]
			var d := pts[(j + 1) * (nx + 1) + i + 1]
			_uv_vert(st, a, rect.position, inv)
			_uv_vert(st, b, rect.position, inv)
			_uv_vert(st, c, rect.position, inv)
			_uv_vert(st, b, rect.position, inv)
			_uv_vert(st, d, rect.position, inv)
			_uv_vert(st, c, rect.position, inv)
	# Skirt: both windings so it shows from either side.
	var down := Vector3(0.0, skirt, 0.0)
	var ring: Array[Vector3] = []
	for i in nx + 1:
		ring.append(pts[i])
	for j in range(1, nz + 1):
		ring.append(pts[j * (nx + 1) + nx])
	for i in range(nx - 1, -1, -1):
		ring.append(pts[nz * (nx + 1) + i])
	for j in range(nz - 1, 0, -1):
		ring.append(pts[j * (nx + 1)])
	for k in ring.size():
		var p0 := ring[k]
		var p1 := ring[(k + 1) % ring.size()]
		_tri(st, p0, p1, p0 - down)
		_tri(st, p1, p1 - down, p0 - down)
		_tri(st, p0, p0 - down, p1)
		_tri(st, p1, p0 - down, p1 - down)
	st.generate_normals()
	return st.commit()


static func _uv_vert(st: SurfaceTool, v: Vector3, origin: Vector2, inv: Vector2) -> void:
	st.set_uv(Vector2(v.x - origin.x, v.z - origin.y) * inv)
	st.add_vertex(v)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Far city chunks: an invisible floor at road height following the relief, so a fast car does
## not drop to the flat base plane before the detailed chunk arrives.
func _add_relief_floor() -> void:
	var area := owned_rect()
	var n := 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := PackedVector3Array()
	pts.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var x := area.position.x + area.size.x * i / n
			var z := area.position.y + area.size.y * j / n
			pts[j * (n + 1) + i] = Vector3(x, ROAD_TOP + _gy(x, z), z)
	for j in n:
		for i in n:
			_tri(st, pts[j * (n + 1) + i], pts[j * (n + 1) + i + 1], pts[(j + 1) * (n + 1) + i])
			_tri(st, pts[j * (n + 1) + i + 1], pts[(j + 1) * (n + 1) + i + 1], pts[(j + 1) * (n + 1) + i])
	var body := StaticBody3D.new()
	body.name = "ReliefFloor"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = st.commit().create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


func _add_cylinder(pos: Vector3, radius: float, height: float, color: Color, collide: bool = true, unshaded: bool = false) -> void:
	if capturing:
		return
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 16
	mesh.mesh = cyl
	mesh.material_override = PropFactory.material(color, 0.9, unshaded)
	var lifted := pos + Vector3(0.0, _gy(pos.x, pos.z), 0.0)
	mesh.position = lifted
	add_child(mesh)
	if collide and _statics:
		var shape := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		shape.shape = s
		shape.position = lifted
		_statics.add_child(shape)


func _add_shape(size: Vector3, pos: Vector3, yaw: float = 0.0) -> CollisionShape3D:
	if _statics == null:
		return null
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	shape.rotation.y = yaw
	_statics.add_child(shape)
	return shape


## A collision box with any transform (chunk frame): tilted struts, a raised crane boom.
func _add_shape_xf(size: Vector3, xf: Transform3D) -> void:
	if _statics == null:
		return
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = xf
	_statics.add_child(shape)


# --- Freeway ---------------------------------------------------------------------------------

## Metres kept between a lot and the deck's edge (the pillars stand inside the deck's width).
const LOT_FREEWAY_MARGIN := 3.0
## ... between a tree's trunk and the deck's edge, about a canopy's radius, and a palm's (its
## crown stands clear above the deck, so it may lean over the barrier as real ones do).
const TREE_FREEWAY_MARGIN := 5.0
## The ground cover on a freeway corridor lot (_build_corridor_lot), a deep ivy green, and one
## shrub per this many square metres of it.
const CORRIDOR_IVY := Color(0.21, 0.33, 0.14)
const CORRIDOR_SHRUB_AREA := 55.0
## How far past the approach clear zone the long-term parking reaches (the lots CityPlan drops are
## every lot the zone touches, so they run on past it), and the most parked cars in one chunk.
const APPROACH_PARK_REACH := 22.0
const APPROACH_PARK_MAX_CARS := 260
## Metres between the trees down a plaza's promenades (_furnish_plaza).
const PLAZA_TREE_STEP := 9.0
const PALM_FREEWAY_MARGIN := 2.0

## True where the freeway deck flies over, plus `margin` metres either side.
func _under_freeway(pos: Vector2, margin: float) -> bool:
	if plan.macro == null or plan.macro.freeway == null:
		return false
	return plan.macro.freeway.blocks(pos, margin)



## True when any part of a lot (CityPlan.lots()) is under the freeway deck or within
## LOT_FREEWAY_MARGIN of its edge.
func _lot_under_freeway(lot: Dictionary) -> bool:
	if plan.macro == null or plan.macro.freeway == null:
		return false
	var size: Vector2 = lot.size
	var rect := Rect2((lot.center as Vector2) - size * 0.5, size)
	# The light rail's structure keeps its lots clear the same way (LightRail.blocks_rect()).
	var rail := LightRail.of(plan)
	if rail != null and rail.blocks_rect(rect, 2.0):
		return true
	return plan.macro.freeway.blocks_rect(rect, LOT_FREEWAY_MARGIN)


## Deck segments of the freeway crossing this chunk.
func _freeway_segments() -> Array[Dictionary]:
	if plan.macro == null or plan.macro.freeway == null:
		return []
	return plan.macro.freeway.segments_in(owned_rect())


## The elevated freeway: deck, girder, barriers, bents, lane markings, light standards, sign
## gantries and roadside furniture (FreewayKit), then the off-ramps. Built straight into four
## meshes per chunk (asphalt top, structure, paint and sign faces, the night light pools) rather
## than through the batch, because the batch adds the ground relief to every instance and the
## deck is nine metres above it. Collision is one tilted box per segment.
func _build_freeway() -> void:
	var segs := _freeway_segments()
	if segs.is_empty():
		return
	var area := owned_rect()
	var deck_body := StaticBody3D.new()
	deck_body.name = "FreewayBody"
	deck_body.collision_layer = 1
	deck_body.collision_mask = 0
	var kit := FreewayKit.new(self)
	# The four-level stack's connectors go into the same meshes (StackBuild).
	var quads := kit.build_segments(segs, area) + StackBuild.build(self, kit, deck_body)
	if quads == 0:
		return
	var t := Freeway.DECK_THICKNESS
	for seg in segs:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var seg_len := a.distance_to(b)
		var mid := a.lerp(b, 0.5)
		# Segments are claimed by the chunk their midpoint falls in, so the deck is built once.
		# (The stack's connectors are banked: StackBuild gives them their own boxes.)
		if seg_len < 0.5 or not area.has_point(mid) or seg.has("link"):
			continue
		var ha: float = seg.ha
		var hb: float = seg.hb
		var dir := (b - a) / seg_len
		var nrm := Vector2(-dir.y, dir.x)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(seg.width, t, seg_len + 0.4)
		cs.shape = bx
		var fwd := Vector3(b.x - a.x, hb - ha, b.y - a.y).normalized()
		var right := Vector3(nrm.x, 0.0, nrm.y)
		var up := right.cross(fwd).normalized()
		cs.transform = Transform3D(Basis(right, up, -fwd), Vector3(mid.x, (ha + hb) * 0.5 - t * 0.5, mid.y))
		deck_body.add_child(cs)
	add_child(deck_body)
	kit.commit(PropFactory.road("asphalt_aerial", 9.0, Color(0.69, 0.69, 0.71), hash([plan.seed, "freeway"]), 0.0, 0.7))
	_build_freeway_ramps()


## Off-ramps: a sloped ribbon peeling off the deck edge and running down to the street, with a
## barrier on each side (FreewayKit.ramp_piece()). The landing is on the surface grid, so you can drive on and off.
func _build_freeway_ramps() -> void:
	if plan.macro == null or plan.macro.freeway == null:
		return
	var area := owned_rect()
	var list := plan.macro.freeway.ramps_in(area)
	if list.is_empty():
		return
	var kit := FreewayKit.new(self)
	var ramp_body := StaticBody3D.new()
	ramp_body.name = "RampBody"
	ramp_body.collision_layer = 1
	ramp_body.collision_mask = 0
	var built := 0
	for r in list:
		var start: Vector2 = r.pos
		var yaw: float = r.yaw
		var out := Vector2(-sin(yaw), -cos(yaw))
		var top_y: float = r.top
		var run := Freeway.RAMP_RUN
		var steps := Freeway.RAMP_STEPS
		var width := Freeway.RAMP_WIDTH
		var path := Freeway.ramp_path(r)
		var prev := start
		var prev_y := top_y - Freeway.DECK_THICKNESS * 0.5
		var ground_end := plan.height_at(start + out * run) + 0.12
		for k in range(1, steps + 1):
			var t := float(k) / steps
			# Ease out at both ends so the ramp meets the deck and the street smoothly.
			var ease := t * t * (3.0 - 2.0 * t)
			var p: Vector2 = path[k]
			var y := lerpf(top_y - Freeway.DECK_THICKNESS * 0.5, ground_end, ease)
			var d: Vector2 = p - prev
			if d.length() < 0.2:
				continue
			var n := Vector2(-d.y, d.x).normalized() * (width * 0.5)
			kit.ramp_piece(Vector3(prev.x, prev_y, prev.y), Vector3(p.x, y, p.y), n.normalized(), width, float(k - 1) * run / steps, float(k) * run / steps)
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			var seg_len: float = d.length()
			bx.size = Vector3(width, 0.8, seg_len + 0.3)
			cs.shape = bx
			var fwd := Vector3(p.x - prev.x, y - prev_y, p.y - prev.y).normalized()
			var right := Vector3(n.x, 0.0, n.y).normalized()
			var up := right.cross(fwd).normalized()
			var mid := Vector3((prev.x + p.x) * 0.5, (prev_y + y) * 0.5 - 0.4, (prev.y + p.y) * 0.5)
			cs.transform = Transform3D(Basis(right, up, -fwd), mid)
			ramp_body.add_child(cs)
			prev = p
			prev_y = y
		built += 1
	if built == 0:
		return
	add_child(ramp_body)
	kit.commit(PropFactory.road("asphalt_aerial", 9.0, Color(0.69, 0.69, 0.71), hash([plan.seed, "ramp"]), 0.0, 0.7), "Ramp")


## Starts this chunk dissolving instead of vanishing, and frees it when it has gone. Called on
## the OLD chunk once its replacement is already standing in the same place, so what the player
## sees is a coarse block thinning out over a detailed one rather than a block changing identity
## between two frames.
##
## Three things have to happen at once or the dissolve is worse than the pop it replaces:
##  - the LOD boxes get their OWN material. PropFactory caches one for every LOD chunk in the
##    city, so setting `fade` on the shared one would dissolve the whole skyline at once.
##  - everything else this chunk drew is hidden NOW. Its road and pavement slabs sit at exactly
##    the same height as the new chunk's, and two coincident surfaces z-fight, which is far more
##    visible than the swap.
##  - its collision stops. The boxes are on their way out; walking into a building that is
##    visibly dissolving, or having a car hit one, is the giveaway.
func begin_fade_out(seconds: float) -> void:
	var node := _mm_nodes.get("lod_box") as MultiMeshInstance3D
	if node == null or seconds <= 0.0:
		queue_free()
		return
	_fade_total = seconds
	_fade_left = seconds
	_fade_mat = PropFactory.building_lod_material().duplicate() as ShaderMaterial
	node.material_override = _fade_mat
	for child in get_children():
		if child != node and child is Node3D:
			(child as Node3D).visible = false
		if child is CollisionObject3D:
			(child as CollisionObject3D).collision_layer = 0
			(child as CollisionObject3D).collision_mask = 0
	set_process(true)


func _process(delta: float) -> void:
	if _fade_left <= 0.0:
		return
	_fade_left -= delta
	if _fade_left <= 0.0:
		queue_free()
		return
	if _fade_mat:
		_fade_mat.set_shader_parameter("chunk_fade", clampf(_fade_left / _fade_total, 0.0, 1.0))


## Commits the far chunk's merged ground as one MeshInstance. `append_from` carried each surface
## in with the colour set before it, so a single vertex-coloured material paints road, pavement,
## lawn and plaza in one draw instead of one draw apiece.
func _commit_far_ground() -> void:
	if not _far_ground_any or _far_ground == null:
		return
	var mesh := _far_ground.commit()
	_far_ground = null
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "FarGround"
	mi.mesh = mesh
	mi.material_override = PropFactory.far_ground_material()
	# It is ground: it receives, and shadowing anything from a quarter kilometre out is cascade
	# fill for nothing.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
