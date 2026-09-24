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

const PROP_HEALTH := {"lamp": 30.0, "hydrant": 20.0, "bench": 20.0, "stop_sign": 10.0, "signal": 60.0, "barrier": 80.0, "cafe": 15.0, "planter": 25.0, "rack": 15.0, "newsbox": 10.0, "mailbox": 20.0, "bollard": 40.0, "street_sign": 12.0, "bus_stop": 40.0}

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
## Cached MacroMap.relief_at samples on a fixed world lattice, keyed Vector2i(x, z) / RELIEF_STEP.
var _relief_lattice: Dictionary = {}

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
func ground_y(x: float, z: float) -> float:
	return SIDEWALK_TOP + _gy(x, z)


func _gy(x: float, z: float) -> float:
	if plan == null or plan.macro == null:
		return 0.0
	var fx := x / RELIEF_STEP
	var fz := z / RELIEF_STEP
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
	var h := plan.macro.relief_at(Vector2(i * RELIEF_STEP, j * RELIEF_STEP))
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


## The steps a build is made of: roads, the block's pavement, then each building, the street
## furniture, the parked cars, each pedestrian, the crossing, the freeway, and the finish. Each
## is small next to the old all-in-one build, which was a hundred milliseconds on a slow machine.
var _steps: Array[Callable] = []
var _step: int = 0


func begin_build() -> void:
	_batch.ground = _gy
	_batch.tilt_keys = {"dash": true, "stripe": true, "manhole": true, "gutter": true, "grate": true, "stop_line": true, "patch": true, "arrow_straight": true, "arrow_left": true, "pstripe": true, "tree_grate": true}
	key = "%d,%d" % [ix, iz]
	name = "Chunk_" + key
	position = -WorldState.world_offset
	if level == Level.FULL:
		_statics = StreetProps.new()
		_statics.chunk = self
		add_child(_statics)
	var block := plan.block(ix, iz)
	zone = plan.zone_at((block.rect as Rect2).get_center())
	_steps.clear()
	_step = 0
	# A block the replica area's corridor runs through builds the replica's own content in place
	# of the seeded block (ReplicaAreas.block_role(), ReplicaBuilder).
	var replica: ReplicaAreas = plan.macro.replica if plan.macro else null
	var replica_role := 0
	if replica != null and (zone == MacroMap.Zone.CITY or zone == MacroMap.Zone.BEACH):
		replica_role = replica.block_role(plan, ix, iz)
	match zone:
		MacroMap.Zone.OCEAN:
			_steps.append(_build_water)
			# The waterline does not respect the zone grid: a chunk whose centre is out to sea
			# can still have the shore running through its landward edge, and before this those
			# bands showed as dark gaps between one beach and the next.
			if _owns_shoreline():
				_steps.append(_build_beach.bind(block))
				_steps.append(_build_hill_roads)
		MacroMap.Zone.HILLS:
			_steps.append_array([_build_terrain, _build_hill_roads, _build_mansions, _scatter_hills])
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
			_steps.append(_build_port.bind(block))
		_:
			if _owns_shoreline():
				_steps.append(_build_beach.bind(block))
				_steps.append(_build_hill_roads)
			if replica_role == 0:
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
	# The freeway runs over every zone: city blocks, the beach, the hills, the lot. It is built
	# last so its deck lands on top of whatever the chunk laid down.
	_steps.append(_build_freeway)
	if level == Level.FULL and plan.macro:
		_steps.append(_build_landmarks)
	_steps.append(_finish_build)


func _build_landmarks() -> void:
	for lm in Landmarks.in_rect(owned_rect()):
		Landmarks.build(lm, self, _statics, plan, true)
		built_landmarks.append(lm.id)


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
	_commit_far_ground()
	_mm_nodes = _batch.build(self)
	for paint_key: String in PAINT_KEYS:
		if _mm_nodes.has(paint_key):
			(_mm_nodes[paint_key] as MultiMeshInstance3D).material_override = PropFactory.road_paint_material()
	if _mm_nodes.has("lod_box"):
		(_mm_nodes["lod_box"] as MultiMeshInstance3D).material_override = PropFactory.building_lod_material()
	_build_occluder()
	# The build's own samples go; pedestrians walking the pavement (Pedestrian._ground_y) fill
	# back only the few cells along their ring.
	_relief_lattice.clear()


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
	var x0 := plan.road_pos(CityPlan.AXIS_X, ix) + plan.road_width(CityPlan.AXIS_X, ix) * 0.5
	var x1 := plan.road_pos(CityPlan.AXIS_X, ix + 1) + plan.road_width(CityPlan.AXIS_X, ix + 1) * 0.5
	var z0 := plan.road_pos(CityPlan.AXIS_Z, iz) + plan.road_width(CityPlan.AXIS_Z, iz) * 0.5
	var z1 := plan.road_pos(CityPlan.AXIS_Z, iz + 1) + plan.road_width(CityPlan.AXIS_Z, iz + 1) * 0.5
	return Rect2(x0, z0, x1 - x0, z1 - z0)


# --- Airport and port ------------------------------------------------------------------

func _build_airport() -> void:
	var area := owned_rect()
	var c := area.get_center()
	# Through the wear shader rather than a plain tiled material: a car park is a big flat area
	# and the tile grid is the first thing the eye finds on one.
	# An apron is concrete, not a night street. 0.44 tinting an already dark asphalt set put the
	# whole airport at an albedo of 0.014 - several chunks of continuous flat ground reading as
	# a void in every wide shot that includes it.
	_add_slab(Vector3(c.x, 0.05, c.y), Vector3(area.size.x, 0.1, area.size.y), style.tarmac, level == Level.FULL, PropFactory.road("asphalt", 8.0, Color(1.25, 1.25, 1.27), hash([plan.seed, ix, iz, "lot"]), 0.0, 0.85))
	var macro: MacroMap = plan.macro
	if level == Level.FULL and area.has_point(macro.terminal_curb.get_center()):
		# The drop-off curb in front of the terminal is packed (owner: "jampacked").
		var curb_rng := RandomNumberGenerator.new()
		curb_rng.seed = plan.seed ^ 0x7e5
		_spawn_crowd(macro.terminal_curb, 4.0, style.airport_crowd, curb_rng)
	for rz in macro.runway_zs:
		var band := Rect2(area.position.x, rz - macro.runway_width * 0.5, area.size.x, macro.runway_width)
		var strip := band.intersection(area)
		if strip.size.y <= 0.0:
			continue
		var sc := strip.get_center()
		var runway := MeshInstance3D.new()
		runway.name = "Runway"
		var box := BoxMesh.new()
		box.size = Vector3(strip.size.x, 0.04, strip.size.y)
		runway.mesh = box
		runway.material_override = PropFactory.material(style.runway, 0.95)
		runway.position = Vector3(sc.x, 0.12, sc.y)
		add_child(runway)
		if level != Level.FULL:
			continue
		# Center line dashes and edge lines.
		var x := strip.position.x + 6.0
		while x < strip.end.x - 6.0:
			# The stripe mesh is 0.6 m across by 3 m long in ITS OWN Z, and the yaw turns that
			# length onto world X. Basis.scaled() then scales the WORLD axes, so the 3x
			# lengthening goes in x. Written (1, 1, 3) it landed on world Z instead and every
			# centre-line dash came out 3 m long and 1.8 m wide - stubby blocks, not a runway.
			_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(3.0, 1.0, 1.0)), Vector3(x, 0.15, rz)))
			x += 24.0
		for side: float in [-1.0, 1.0]:
			# Same again, and much worse: the runway-length factor was landing on the stripe's
			# 0.6 m width, so each edge line was a white slab a couple of hundred metres across
			# the runway and three metres along it, instead of a thin line down its whole length.
			_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(strip.size.x / 3.0, 1.0, 1.0)), Vector3(sc.x, 0.15, rz + side * (macro.runway_width * 0.5 - 1.0))))
	if level == Level.FULL:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([ix, iz, 5])
		for i in 3:
			var p := Vector2(rng.randf_range(area.position.x + 5.0, area.end.x - 5.0), area.position.y + 4.0)
			if not _on_runway(p) and not _near_apron(p):
				_add_lamp(Vector3(p.x, 0.1, p.y))
		# Flyable jets on the apron, owned like parked cars (city root, freed with the chunk
		# unless someone flew them away).
		for spot in macro.apron_spots:
			var sp: Vector2 = spot[0]
			if not area.has_point(sp):
				continue
			var jet := Aircraft.new()
			jet.setup_aircraft(spot[1] as Aircraft.Kind)
			var holder: Node = get_parent() if get_parent() else self
			jet.position = WorldState.to_local(Vector3(sp.x, 1.0, sp.y)) if holder != self else Vector3(sp.x, 1.0, sp.y)
			jet.rotation.y = -PI * 0.5
			holder.add_child(jet)
			_cars.append(jet)


func _near_apron(p: Vector2) -> bool:
	for spot in plan.macro.apron_spots:
		if (spot[0] as Vector2).distance_to(p) < 45.0:
			return true
	return false


func _on_runway(p: Vector2) -> bool:
	for rz in plan.macro.runway_zs:
		if absf(p.y - rz) < plan.macro.runway_width * 0.5 + 6.0:
			return true
	return false


func _build_port(block: Dictionary) -> void:
	var area := owned_rect()
	var c := area.get_center()
	_add_slab(Vector3(c.x, 0.1, c.y), Vector3(area.size.x, 0.2, area.size.y), style.concrete, level == Level.FULL, PropFactory.road("concrete", 5.0, Color(0.78, 0.78, 0.76), hash([plan.seed, ix, iz, "yard"]), 6.0, 0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = block.seed
	# Container stacks in rows, colored per box.
	var colors := [Color(0.8, 0.25, 0.2), Color(0.2, 0.45, 0.75), Color(0.85, 0.6, 0.15), Color(0.3, 0.6, 0.35), Color(0.6, 0.6, 0.62), Color(0.55, 0.3, 0.55)]
	var rows := int(area.size.y / 9.0)
	var cols := int(area.size.x / 14.0)
	var origin := Vector2(area.position.x + 8.0, area.position.y + 6.0)
	for r in rows:
		if rng.randf() < 0.3:
			continue # an empty lane for trucks
		for col in cols:
			if rng.randf() < 0.35:
				continue
			var height := rng.randi_range(1, 3)
			var p := origin + Vector2(col * 14.0, r * 9.0)
			if p.x + 6.0 > area.end.x - 4.0 or p.y + 1.2 > area.end.y - 4.0:
				continue
			for h in height:
				var col_color: Color = colors[rng.randi() % colors.size()]
				_batch.add("container", PropFactory.container(), Transform3D(Basis(), Vector3(p.x, 0.2 + 1.3 + h * 2.6, p.y)), col_color)
			if level == Level.FULL:
				_add_shape(Vector3(12.0, 2.6 * height, 2.4), Vector3(p.x, 0.2 + 1.3 * height, p.y))
	# A gantry crane on chunks that touch the harbor.
	var macro: MacroMap = plan.macro
	if area.end.y >= macro.harbor_rect.position.y - 2.0 and level == Level.FULL:
		_build_crane(Vector3(c.x, 0.2, area.end.y - 18.0))
	if level == Level.FULL:
		for i in 2:
			_add_lamp(Vector3(area.position.x + 4.0 + i * (area.size.x - 8.0), 0.2, area.position.y + 4.0))


func _build_crane(at: Vector3) -> void:
	var steel := Color(0.85, 0.45, 0.15)
	var h := 40.0
	for dx: float in [-14.0, 14.0]:
		for dz: float in [-6.0, 6.0]:
			_add_slab(at + Vector3(dx, h * 0.5, dz), Vector3(1.4, h, 1.4), steel)
	_add_slab(at + Vector3(0.0, h + 0.5, -6.0), Vector3(30.0, 1.5, 1.5), steel)
	_add_slab(at + Vector3(0.0, h + 0.5, 6.0), Vector3(30.0, 1.5, 1.5), steel)
	# Boom out over the water (+Z), and a trolley with a hanging container.
	_add_slab(at + Vector3(0.0, h + 0.5, 30.0), Vector3(3.0, 2.0, 60.0), steel)
	_add_slab(at + Vector3(0.0, h - 1.5, 26.0), Vector3(4.0, 1.5, 4.0), Color(0.3, 0.3, 0.32))
	_add_slab(at + Vector3(0.0, h - 9.0, 26.0), Vector3(0.2, 14.0, 0.2), Color(0.2, 0.2, 0.2), false)
	_batch.add("container", PropFactory.container(), Transform3D(Basis(Vector3.UP, PI * 0.5), at + Vector3(0.0, h - 17.0, 26.0)), Color(0.2, 0.45, 0.75))
	_add_slab(at + Vector3(0.0, 4.0, 0.0), Vector3(6.0, 8.0, 5.0), Color(0.3, 0.3, 0.32))


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
	Color(0.44, 0.48, 0.52), Color(0.54, 0.56, 0.59), Color(0.84, 0.81, 0.75),
	Color(1.0, 1.0, 1.0), Color(0.90, 0.90, 0.88),
]
## Bands across the profile the dry sand's collider is cut into.
const SAND_COLLIDER_BANDS := 5
const SAND_LOW := -0.75
const SAND_EDGE := 0.22
const SAND_HIGH := 0.5


## The beach: a strip that follows the shoreline itself rather than a chunk-sized slab. The
## coast is a curve, so slabs left visible rectangular seams and, where the curve ran out of a
## chunk, gaps of bare ground between one beach and the next. This walks the chunk's Z range,
## asks MacroMap where the water is at each step, and lays a continuous ramp from under the
## waves up to the town.
## True when this chunk is the one the waterline runs through at its own Z. Exactly one chunk per
## Z band answers yes, so the sand is laid once and never double-drawn by a neighbour.
func _owns_shoreline() -> bool:
	if plan.macro == null:
		return false
	var rect := owned_rect()
	var cx := plan.macro.coast_x(rect.get_center().y)
	return cx >= rect.position.x and cx < rect.end.x


func _build_beach(block: Dictionary) -> void:
	# Under a replica area the grid roads that would cross the sand are not built (the corridor
	# runs to the sea), so the sand covers the chunk's road strips too.
	_build_sand(owned_rect() if _replica != null else block.rect)
	if level != Level.FULL:
		return
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
	for i in rng.randi_range(6, 14):
		var z := rng.randf_range(block.rect.position.y + 4.0, block.rect.end.y - 4.0)
		var across := rng.randf_range(0.18, 0.95)
		var at := Vector3(_dry_sand_x(z, across), _sand_y(z, across), z)
		if not bare:
			_add_palm(at, rng)
	if rng.randf() < 0.6:
		var z := rng.randf_range(block.rect.position.y + 8.0, block.rect.end.y - 8.0)
		var across := rng.randf_range(0.1, 0.5)
		_add_lifeguard_tower(Vector3(_dry_sand_x(z, across), _sand_y(z, across), z), rng.randf_range(0.0, TAU))


## Height of the sand at `across` (0 at the waterline, 1 at the town) for a given Z. The berm
## wanders along the shore, which is what cusps are; it is a smooth function of z so it carries
## across a chunk boundary without a step.
func _sand_y(z: float, across: float) -> float:
	var crest := SAND_CREST + SAND_CUSP * sin(z * 0.11) * cos(z * 0.047)
	if across <= SAND_BERM_AT:
		return lerpf(SAND_EDGE, SAND_EDGE + crest, across / maxf(SAND_BERM_AT, 0.001))
	var t := (across - SAND_BERM_AT) / maxf(1.0 - SAND_BERM_AT, 0.001)
	return lerpf(SAND_EDGE + crest, SAND_HIGH, t * t * (3.0 - 2.0 * t))


func _build_sand(rect: Rect2) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var macro: MacroMap = plan.macro
	var steps := maxi(2, ceili(rect.size.y / SAND_STEP))
	var quads := 0
	var prev: Array[Vector3] = []
	for i in steps + 1:
		var z: float = rect.position.y + rect.size.y * float(i) / steps
		var water_x := rect.position.x
		var inland_x := rect.end.x
		var width := inland_x - water_x
		if macro:
			water_x = macro.coast_x(z)
			width = macro.beach_width_at(z)
			inland_x = water_x + width + SAND_LIP
		# Seaward to landward: the bar under the water, the waterline, the swash the sea still
		# reaches, the berm crest, and the backshore falling away behind it.
		var row: Array[Vector3] = [
			Vector3(water_x - SAND_WET, SAND_LOW, z),
			Vector3(water_x, SAND_EDGE, z),
			Vector3(water_x + SAND_SWASH, _sand_y(z, SAND_SWASH / maxf(width, 1.0)), z),
			Vector3(water_x + width * SAND_BERM_AT, _sand_y(z, SAND_BERM_AT), z),
			Vector3(inland_x, SAND_HIGH, z),
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
				for pair in [[a, SAND_TONES[k]], [b, SAND_TONES[k + 1]], [c, SAND_TONES[k + 1]],
						[a, SAND_TONES[k]], [c, SAND_TONES[k + 1]], [d, SAND_TONES[k]]]:
					var v: Vector3 = pair[0]
					st.set_color(pair[1] as Color)
					st.set_uv(Vector2(v.x, v.z) * SAND_UV_SCALE)
					st.add_vertex(v)
				quads += 1
		prev = row
	if quads > 0:
		st.generate_normals()
		st.generate_tangents()
		var mesh := MeshInstance3D.new()
		mesh.name = "Sand"
		mesh.mesh = st.commit()
		# vertex_color_use_as_albedo, or the wet/dry banding above is computed and thrown away.
		# 2 m a tile: the set is trodden sand, footprints and all, photographed over about that.
		# At 5 m every footprint was half a metre across, and under a low sun the beach read as
		# rippling water.
		mesh.material_override = PropFactory.pbr("sand", 2.0, Color(1.0, 0.95, 0.85), 1.0, true)
		add_child(mesh)
	if level != Level.FULL:
		return
	# The collider follows the berm in bands rather than being one flat box under the whole
	# beach: with a metre of crest in the middle, a flat box leaves the player walking through
	# the sand on the way up and a foot above it on the way down. Five boxes, not a mesh shape -
	# the player only ever walks the dry sand and a box stack is cheaper and steadier.
	var c := rect.get_center()
	if macro == null:
		_add_shape(Vector3(rect.size.x, 0.4, rect.size.y), Vector3(c.x, SAND_EDGE - 0.1, c.y))
		return
	var width: float = macro.beach_width_at(c.y) + SAND_LIP
	var band := width / float(SAND_COLLIDER_BANDS)
	for k in SAND_COLLIDER_BANDS:
		var across := (float(k) + 0.5) / float(SAND_COLLIDER_BANDS)
		var x := macro.coast_x(c.y) + width * across
		var y := _sand_y(c.y, across)
		_add_shape(Vector3(band + 0.2, 0.4, rect.size.y), Vector3(x, y - 0.2, c.y))


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
func _build_terrain() -> void:
	var area := owned_rect()
	# Finer tile where a hill road passes, so the carved road bed reads cleanly. The whole grid
	# is several times what it was: a ridge is read as a silhouette against the sky and an
	# eight-metre quad gives a mountain a faceted, folded-paper edge no shading can hide.
	var has_road := _hill_segments().size() > 0
	var n := (terrain_subdiv_road if has_road else terrain_subdiv) if level == Level.FULL else terrain_subdiv_lod
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n + 1:
		for i in n + 1:
			var x := area.position.x + area.size.x * i / n
			var z := area.position.y + area.size.y * j / n
			var h := plan.height_at(Vector2(x, z))
			heights[j * (n + 1) + i] = h
			# COLOR.r is the height the terrain shader blends rock and snow from. Rescaled for
			# the real ranges: 160 m used to be "fully rock", and the back range is 1150.
			var t := clampf((h - 40.0) / 900.0, 0.0, 1.0)
			st.set_color(Color(t, 0.0, 0.0, 1.0))
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
	var mesh := MeshInstance3D.new()
	mesh.name = "Terrain"
	mesh.mesh = st.commit()
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
	return plan.macro.hill_roads.segments_in(owned_rect())


## Asphalt strips following the carved road beds, clipped to this chunk.
## Boulders, shrubs, dry scrub and grass tufts over a hill chunk, kept off the roads and the
## mansion pads. Rocks prefer steep ground and get collision.
func _scatter_hills() -> void:
	if level != Level.FULL:
		return
	var area := owned_rect()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, ix, iz, "hills"])
	var segs := _hill_segments()
	var pads := plan.macro.hill_roads.mansions_in(area.grow(HillRoads.PAD_RADIUS + 6.0))
	for i in rng.randi_range(hill_scatter_min, hill_scatter_max):
		var p := Vector2(rng.randf_range(area.position.x + 1.0, area.end.x - 1.0), rng.randf_range(area.position.y + 1.0, area.end.y - 1.0))
		if _near_hill_road(p, segs, 2.5) or _near_pad(p, pads, 4.0):
			continue
		var h := plan.height_at(p)
		if h < 1.5:
			continue
		var hx := plan.height_at(p + Vector2(1.0, 0.0)) - plan.height_at(p - Vector2(1.0, 0.0))
		var hz := plan.height_at(p + Vector2(0.0, 1.0)) - plan.height_at(p - Vector2(0.0, 1.0))
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
				_batch.add("tuft_%d" % v, PropFactory.model_grass_tuft(v), Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sc, sc, sc)), Vector3(q.x, plan.height_at(q) - 0.02, q.y)), tint)
	for v in 5:
		_batch.set_no_shadow("tuft_%d" % v)
		_batch.set_no_shadow("scrub_%d" % v)


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
		# The replica's hill route is carved here but drawn by ReplicaBuilder, markings and all.
		if not seg.get("draw", true):
			continue
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var seg_len := a.distance_to(b)
		if seg_len < 0.5:
			continue
		var pieces := maxi(1, ceili(seg_len / 6.0))
		var dir := (b - a) / seg_len
		var half: float = seg.width * 0.5
		var normal := Vector2(-dir.y, dir.x) * half
		for k in pieces:
			var t0 := float(k) / pieces
			var t1 := float(k + 1) / pieces
			var c0 := a.lerp(b, t0)
			var c1 := a.lerp(b, t1)
			if not area.has_point(c0.lerp(c1, 0.5)):
				continue
			# 0.26 rather than a hair over the ground: the beach lays a 0.4 m sand slab centred
			# on zero, so its surface is at 0.2, and the coast highway crossing a beach town
			# would otherwise be buried in it for the length of the sand.
			var h0 := plan.height_at(c0) + 0.26
			var h1 := plan.height_at(c1) + 0.26
			var v0 := Vector3(c0.x - normal.x, h0, c0.y - normal.y)
			var v1 := Vector3(c0.x + normal.x, h0, c0.y + normal.y)
			var v2 := Vector3(c1.x + normal.x, h1, c1.y + normal.y)
			var v3 := Vector3(c1.x - normal.x, h1, c1.y - normal.y)
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


## Hillside estates: a flat pad cut into the slope with a house, a pool, palms and a low wall.
func _build_mansions() -> void:
	if plan.macro == null or plan.macro.hill_roads == null:
		return
	for m in plan.macro.hill_roads.mansions_in(owned_rect()):
		var pos: Vector2 = m.pos
		var h: float = m.height
		var yaw: float = m.yaw
		var rng := RandomNumberGenerator.new()
		rng.seed = m.seed
		var basis := Basis(Vector3.UP, yaw)
		var at := Vector3(pos.x, h, pos.y)
		# Pad.
		var pad := MeshInstance3D.new()
		var pad_box := BoxMesh.new()
		pad_box.size = Vector3(30.0, 0.4, 26.0)
		pad.mesh = pad_box
		pad.material_override = PropFactory.pbr("paving", 4.0, Color(0.9, 0.88, 0.84))
		pad.position = at + Vector3(0.0, 0.2, 0.0)
		pad.rotation.y = yaw
		add_child(pad)
		if level != Level.FULL:
			# Far: the pad and a house box in a warm tone.
			_batch.add("lod_box", PropFactory.unit_box(), Transform3D(basis.scaled(Vector3(18.0, 7.5, 13.0)), at + basis * Vector3(0.0, 4.15, -4.0)), Color(0.92, 0.88, 0.8))
			continue
		_add_shape(Vector3(30.0, 0.4, 26.0), at + Vector3(0.0, 0.2, 0.0), yaw)
		# House: a wide low villa on the back half of the pad.
		var house := BUILDING_SCENE.instantiate() as Building
		house.seed = m.seed
		house.lot_size = Vector2(18.0, 13.0)
		house.min_height = 6.5
		house.max_height = 9.5
		house.force_shape = Building.Shape.SLAB
		house.finish_options.assign([Building.Finish.FLAT, Building.Finish.FLAT, Building.Finish.BRICK])
		house.allow_storefront = false
		house.lit_ratio_range = Vector2(0.3, 0.6)
		house.position = at + basis * Vector3(0.0, 0.4, -4.0)
		house.rotation.y = yaw
		add_child(house)
		building_count += 1
		# Pool on the front half, with a pale rim.
		var pool_c := at + basis * Vector3(rng.randf_range(-4.0, 4.0), 0.4, 6.5)
		var rim := MeshInstance3D.new()
		var rim_box := BoxMesh.new()
		rim_box.size = Vector3(9.0, 0.12, 5.6)
		rim.mesh = rim_box
		rim.material_override = PropFactory.material(Color(0.93, 0.92, 0.88), 0.8)
		rim.position = pool_c + Vector3(0.0, 0.06, 0.0)
		rim.rotation.y = yaw
		add_child(rim)
		var water := MeshInstance3D.new()
		var water_box := BoxMesh.new()
		water_box.size = Vector3(8.0, 0.1, 4.6)
		water.mesh = water_box
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.25, 0.65, 0.85)
		wmat.roughness = 0.05
		wmat.metallic = 0.2
		water.material_override = wmat
		water.position = pool_c + Vector3(0.0, 0.13, 0.0)
		water.rotation.y = yaw
		add_child(water)
		# Low wall around the pad and a few palms.
		for side: Vector3 in [Vector3(0.0, 0.0, 13.0), Vector3(0.0, 0.0, -13.0), Vector3(15.0, 0.0, 0.0), Vector3(-15.0, 0.0, 0.0)]:
			var along_x := side.z != 0.0
			var wsize := Vector3(30.0, 1.0, 0.4) if along_x else Vector3(0.4, 1.0, 26.0)
			var wpos := at + basis * (side + Vector3(0.0, 0.9, 0.0))
			var wall := MeshInstance3D.new()
			var wbox := BoxMesh.new()
			wbox.size = wsize
			wall.mesh = wbox
			wall.material_override = PropFactory.material(Color(0.85, 0.82, 0.76), 0.9)
			wall.position = wpos
			wall.rotation.y = yaw
			add_child(wall)
			_add_shape(wsize, wpos, yaw)
		for i in rng.randi_range(2, 4):
			var local := Vector3(rng.randf_range(-13.0, 13.0), 0.4, rng.randf_range(9.0, 12.0) * (1.0 if rng.randf() < 0.7 else -1.0))
			_add_palm(at + basis * local, rng)


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
	_add_slab(Vector3(rx, ROAD_TOP * 0.5, rect.get_center().y), Vector3(wx, ROAD_TOP, rect.size.y), asphalt, true, look_x.material)
	# Horizontal road on the +Z side, spanning this block's X range.
	var look_z := _road_look(CityPlan.AXIS_Z, iz + 1, params)
	var rz := plan.road_pos(CityPlan.AXIS_Z, iz + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, iz + 1)
	_add_slab(Vector3(rect.get_center().x, ROAD_TOP * 0.5, rz), Vector3(rect.size.x, ROAD_TOP, wz), asphalt, true, look_z.material)
	# The intersection square at the +X +Z corner.
	_add_slab(Vector3(rx, ROAD_TOP * 0.5, rz), Vector3(wx, ROAD_TOP, wz), asphalt, true, look_x.material)
	if level == Level.FULL:
		_mark_road(true, rx, wx, rect.position.y, rect.end.y, look_x)
		_mark_road(false, rz, wz, rect.position.x, rect.end.x, look_z)


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
	# One or two manhole covers in a lane, seeded by the road position.
	var mh := RandomNumberGenerator.new()
	mh.seed = hash([center, a, along_z])
	for i in mh.randi_range(1, 2):
		var t := mh.randf_range(a + 4.0, b - 4.0)
		var lane := (width * 0.25) * (1.0 if mh.randf() < 0.5 else -1.0)
		var pos := Vector3(center + lane, ROAD_TOP - 0.025, t) if along_z else Vector3(t, ROAD_TOP - 0.025, center + lane)
		_batch.add("manhole", PropFactory.model_manhole(), Transform3D(Basis(Vector3.UP, mh.randf_range(0.0, TAU)), pos))
	if avenue:
		for side: float in [-0.3, 0.3]:
			# In pieces so the line follows the relief.
			var t0 := a
			while t0 < b - 0.5:
				var piece := minf(4.0, b - t0)
				var mid := t0 + piece * 0.5
				var pos := Vector3(center + side, ROAD_TOP + 0.01, mid) if along_z else Vector3(mid, ROAD_TOP + 0.01, center + side)
				_batch.add("dash", PropFactory.dash(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, 1.0, piece / 3.0)), pos), line)
				t0 += piece
	elif solid:
		var t0 := a
		while t0 < b - 0.5:
			var piece := minf(4.0, b - t0)
			var mid := t0 + piece * 0.5
			var pos := Vector3(center, ROAD_TOP + 0.01, mid) if along_z else Vector3(mid, ROAD_TOP + 0.01, center)
			_batch.add("dash", PropFactory.dash(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, 1.0, piece / 3.0)), pos), line)
			t0 += piece
	else:
		var t := a + 1.5
		while t < b - 1.5:
			var pos := Vector3(center, ROAD_TOP + 0.01, t) if along_z else Vector3(t, ROAD_TOP + 0.01, center)
			_batch.add("dash", PropFactory.dash(), Transform3D(Basis(Vector3.UP, yaw), pos), line)
			t += 6.0


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
	match block.kind:
		CityPlan.BlockKind.PARK:
			steps.append(_build_park.bind(rect, rng))
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
			# Front and side lawns, in the gaps the houses leave. The lawn slab runs under the
			# whole block, so the footprints the lots just recorded are what the grass has to
			# stay out of; a suburb whose lawns are flat green paint is the tell.
			steps.append(func() -> void:
				if _lawn_rect.size.x > 1.0:
					_add_grass(_lawn_rect, 0.85, 0.0, _lot_rects))
	if level == Level.FULL:
		steps.append(_build_sidewalk_props.bind(rect, params, rng, district))
		steps.append_array(_park_car_steps(rect, rng, params))
		steps.append_array(_pedestrian_steps(rect, rng, params))
	return steps


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
	_add_slab(Vector3(center.x, SIDEWALK_TOP * 0.5, center.y), Vector3(rect.size.x, SIDEWALK_TOP, rect.size.y), style.sidewalk, true, PropFactory.road(paving[0], paving[1], paving_tint, hash([plan.seed, ix, iz, "paving"]), rng.randf_range(1.2, 1.9), 0.45))


func _pedestrian_steps(rect: Rect2, rng: RandomNumberGenerator, params: Dictionary = {}) -> Array[Callable]:
	var count: int = params.get("people", style.pedestrians_per_block)
	if plan.macro and not params.is_empty():
		# The downtown core is the busiest: up to twice the district's count in the middle.
		count = roundi(count * (1.0 + plan.macro.skyline_boost(rect.get_center())))
	return _crowd_steps(rect, plan.sidewalk_width, count, rng)


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
## (see CityStreamer.take_crowd_room()), else from this chunk's own count.
func _take_crowd_room() -> bool:
	var streamer := get_parent()
	if streamer and streamer.has_method("take_crowd_room"):
		return streamer.take_crowd_room()
	if _crowd_room <= 0:
		return false
	_crowd_room -= 1
	return true


func _spawn_walker(rect: Rect2, sidewalk: float, rng: RandomNumberGenerator) -> void:
	if not _take_crowd_room():
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
			# Painted stall line between spots.
			_batch.add("pstripe", PropFactory.box("pstripe", Vector3(4.4, 0.01, 0.12), Color(0.95, 0.95, 0.92)), Transform3D(Basis().scaled(Vector3(STALL_SCALE, 1.0, 1.0)), Vector3(x, ROAD_TOP + 0.014, t + 4.0)))
			t += 8.0
		var z := rz + side * CityPlan.parking_offset(wz)
		t = rect.position.x + 8.0
		while t < rect.end.x - 8.0:
			spots.append([Vector3(t, 0.4, z), PI * 0.5, side])
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
	if plan.macro and Landmarks.covers(plan, Vector2(spot[0].x, spot[0].z), 3.0):
		# After the rolls, so the chunk rng runs the same whether or not the spot is used.
		car.free()
		return
	var holder: Node = get_parent() if get_parent() else self
	var spot_pos: Vector3 = spot[0] + Vector3(0.0, 0.3 + _gy(spot[0].x, spot[0].z), 0.0)
	car.position = WorldState.to_local(spot_pos) if holder != self else spot_pos
	car.rotation.y = spot[1] + (PI if rng.randf() < 0.5 else 0.0)
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


func _exit_tree() -> void:
	for car in _cars:
		if is_instance_valid(car) and not car.has_meta("driven"):
			car.queue_free()
	_cars.clear()


## Lot layout is shared by FULL and LOD so both see the same buildings.
## Lots come from the PLAN, seeded per block, so the far skyline can ask for exactly the same
## buildings (see CityPlan.lots()). One build step per lot.
func _lot_steps(_rect: Rect2, params: Dictionary, rng: RandomNumberGenerator) -> Array[Callable]:
	var steps: Array[Callable] = [func() -> void: _lot_rects.clear()]
	for lot in plan.lots(ix, iz):
		steps.append(_build_lot.bind(lot, params, rng))
	return steps


func _build_lot(lot: Dictionary, params: Dictionary, rng: RandomNumberGenerator) -> void:
	var heights: Vector2 = params.height
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
	if lot.edge and pads > 0.0 and rng.randf() < pads and (lot.size as Vector2).x >= 18.0 and (lot.size as Vector2).y >= 18.0:
		Commercial.build_pad(self, lot, rng)
		return
	# Nothing gets built in the corridor the freeway flies over. Checked here, after the
	# pad roll, so skipping a lot does not shift the chunk rng for the lots after it.
	if _under_freeway(center, 14.0):
		return
	var building := BUILDING_SCENE.instantiate() as Building
	building.seed = lot.seed
	building.lot_size = lot.size
	# Downtown core: the skyline climbs toward the center (supertalls in the middle).
	var boost := plan.macro.skyline_boost(center) if plan.macro else 0.0
	# Handing the whole district band to each building made every lot an independent uniform
	# draw between the two heights, and a uniform draw has no tail: downtown's 50..140 lerped
	# to 100..308 in the core came out with a median of 134 m and the twelve tallest towers
	# inside 65 m of each other, so the top of the city read as one flat line rather than as
	# a skyline. So the band is rolled ONCE per lot into a target height and the building gets
	# a narrow band around that, with the roll bent by pow(u, curve): most lots land near the
	# bottom of the band and a handful reach the top.
	var h_low := lerpf(heights.x, heights.x * 1.45, boost)
	var h_top := lerpf(heights.y, heights.y * 2.3, boost)
	# How hard to bend it is set by how much room the district actually has - log base 4 of
	# the band's ratio - so the downtown core's 72..322 m (4.4x) bends at 2.08 and lands its
	# median at 132 m, while the suburbs' 5..14 m (2.8x) only reaches 1.74 and still reads as
	# a street of houses (median 7.7 m).
	var target := plan.lot_height(lot.seed, district, boost)
	building.min_height = target * 0.88
	building.max_height = target
	building.lit_ratio_range = params.lit
	building.weathering_range = params.get("weathering", Vector2(0.2, 0.9))
	building.shape_options.assign(params.shapes)
	building.finish_options.assign(params.finishes)
	var g := _gy(center.x, center.y)
	var gmin := g
	var half: Vector2 = lot.size * 0.5
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		gmin = minf(gmin, _gy(center.x + c.x * half.x, center.y + c.y * half.y))
	# A concrete plinth reaches from the base down past the lowest sidewalk corner.
	building.plinth_depth = g - gmin + SIDEWALK_TOP + 0.6
	var base := Vector3(center.x, SIDEWALK_TOP, center.y)
	building.position = base + Vector3(0.0, g, 0.0)
	if level == Level.FULL:
		add_child(building)
		building_count += 1
	else:
		# Far away: just the boxes, in the facade color, no props. They do get plain box
		# collision so a fast car cannot drive into a footprint and get shot through the
		# floor when the detailed building appears around it.
		var lod_style := building.plan_only()
		# Custom data for shaders/building_lod.gdshader: window style, lit ratio, seed, plain flag.
		var custom := Color(float(building.window_style) / 4.0, lod_style.lit_ratio, float(building.seed % 997) / 997.0, 0.0)
		for part in building.parts:
			var size: Vector3 = part.size
			var part_center: Vector3 = part.center
			# The batch adds the relief itself; the shape needs it explicitly.
			_batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(size), base + part_center), building.facade_color, custom)
			_add_lod_shape(size, building.position + part_center)
			_occluder_boxes.append([Transform3D(Basis(), building.position), part_center, size])
		var fp: Vector2 = building.footprint
		if fp.x > 0.0 and building.plinth_depth > 0.05:
			_batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(fp.x + 0.3, building.plinth_depth, fp.y + 0.3)), base + Vector3(0.0, -building.plinth_depth * 0.5, 0.0)), Color(0.66, 0.66, 0.66), Color(0.0, 0.0, 0.0, 1.0))
		building.free()
		building_count += 1


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
	if not _lod_collision_wanted():
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


## Blade grass over a lawn: PropFactory.grass_blade() tufts in the shared "grass" batch, which
## is one draw call however many of them there are - a lawn is one draw whether it has a hundred
## tufts on it or twenty thousand, which is what makes real grass affordable at all.
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
			_batch.add("grass", blade, Transform3D(basis, Vector3(p.x, SIDEWALK_TOP + 0.05, p.y)), tint, Color(rng.randf(), 0.0, 0.0))
		done[0] = stop
		if stop < count:
			return false
		_batch.set_no_shadow("grass")
		_batch.set_draw_distance("grass", grass_distance)
		return true)


## Grass tufts planted per build step (see _add_grass).
const GRASS_SLICE := 800


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
			_add_lamp(Vector3(p.x, SIDEWALK_TOP, p.y))
			t += lamp_spacing
		t = tree_spacing * 0.75
		while t < length - 4.0:
			if rng.randf() < tree_chance and fmod(t, lamp_spacing) > 3.0:
				# 1.3 rather than 1.6: every 30 cm back toward the kerb is 30 cm of crown that
				# is over the street instead of inside the building on the lot line.
				var p := a + dir * t + inward * 1.3
				_batch.add("tree_grate", PropFactory.box("tree_grate", Vector3(1.6, 0.03, 1.6), Color(0.12, 0.12, 0.13)), Transform3D(Basis(), Vector3(p.x, SIDEWALK_TOP + 0.005, p.y)))
				_add_tree(Vector3(p.x, SIDEWALK_TOP, p.y), rng, -inward)
			elif rng.randf() < tree_chance * 0.5:
				var p := a + dir * (t + tree_spacing * 0.4) + inward * 2.2
				_add_bush(Vector3(p.x, SIDEWALK_TOP, p.y), rng)
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


# --- Intersections ---------------------------------------------------------------------

func _build_intersection(inter: Dictionary) -> void:
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
		else:
			_add_signal(at, c, size)


## Crosswalk styles by intersection seed: 0 zebra, 1 wide continental bars, 2 ladder edges.
func _add_crosswalks(pos: Vector2, size: Vector2, kind_seed: int = 0) -> void:
	var style_id := absi(kind_seed) % 3
	var step := 1.4 if style_id == 0 else 1.9
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
				_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(size.x / 3.0, 1.0, 0.4)), Vector3(pos.x, ROAD_TOP + 0.015, z + edge)))
		else:
			var x := pos.x - size.x * 0.5 + 1.2
			while x < pos.x + size.x * 0.5 - 0.6:
				_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(Vector3.UP, PI * 0.5) * bar, Vector3(x, ROAD_TOP + 0.015, z)))
				x += step
		var xx := pos.x + side * (size.x * 0.5 + 1.8)
		if style_id == 2:
			# On the x sides the rails run along z, which is the stripe's own length axis, so
			# no yaw and the factors are already in the right places.
			for edge: float in [-1.4, 1.4]:
				_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis().scaled(Vector3(0.4, 1.0, size.y / 3.0)), Vector3(xx + edge, ROAD_TOP + 0.015, pos.y)))
		else:
			var zz := pos.y - size.y * 0.5 + 1.2
			while zz < pos.y + size.y * 0.5 - 0.6:
				_batch.add("stripe", PropFactory.stripe(), Transform3D(bar, Vector3(xx, ROAD_TOP + 0.015, zz)))
				zz += step


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
		var index := _batch.add(inst[0], inst[1], inst[2], inst[3] if inst.size() > 3 else Color.WHITE)
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
	var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(LAMP_POOL_SIZE, 1.0, LAMP_POOL_SIZE)), at + Vector3(0.0, 0.05, 0.0))
	_add_prop("lamp", at, Color(0.28, 0.29, 0.32), [
		["lamp", PropFactory.model_lamp(), Transform3D(Basis(Vector3.UP, fmod(absf(at.x * 7.3 + at.z * 3.1), TAU)), at), _lamp_tint],
		["lamp_pool", PropFactory.light_pool(), pool],
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
	light.light_color = Color(1.0, 0.86, 0.62)
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
	_batch.add("tree_%d" % variant, PropFactory.model_tree(variant), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint, variety)


# --- Helpers ---------------------------------------------------------------------------

func _add_slab(pos: Vector3, size: Vector3, color: Color, collide: bool = true, material: Material = null) -> void:
	var mat: Material = material if material else PropFactory.material(color, 0.95)
	if zone == MacroMap.Zone.CITY and size.y <= 0.5 and maxf(size.x, size.z) >= 6.0:
		# Thin ground slab in the city (road, sidewalk, lawn, plaza): follow the relief.
		_add_ground_grid(Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z), pos.y + size.y * 0.5, size.y + 0.5, mat, collide, color)
		return
	var lifted := pos + Vector3(0.0, _gy(pos.x, pos.z), 0.0)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = lifted
	add_child(mesh)
	if collide:
		_add_shape(size, lifted)


## A ground surface over `rect` at `top` above the relief, with a skirt hanging `skirt` meters
## down its edges (the curb face between sidewalk and road).
##
## The drawn grid is fine (`ground_grid_step`) and the collision trimesh is built separately on
## a coarse one (`ground_collision_step`): the streets are what the player looks along for a
## hundred metres, and five-metre quads gave the relief a folded look, but physics walks on the
## shape and would only pay for the detail. Both come from the cached relief, so the fine grid
## costs about what the old coarse one did.
func _add_ground_grid(rect: Rect2, top: float, skirt: float, mat: Material, collide: bool, tint: Color = Color.WHITE) -> void:
	var step := ground_grid_step if _detail() >= 1.0 else ground_grid_step * 2.0
	var nx := clampi(ceili(rect.size.x / step), 1, 120)
	var nz := clampi(ceili(rect.size.y / step), 1, 120)
	# Far chunks carry the surface's colour in the mesh itself (see below). Linear, because a
	# vertex colour reaches the shader verbatim where a material's albedo_color is decoded from
	# sRGB. Alpha marks the carriageway and which way it runs, for the street lamp glow far chunks
	# get instead of lamps (far_ground.gdshader): 1.0 along Z, 0.75 along X, 0.5 a junction, 0.25
	# a pavement, 0 anything else. A road slab is long and thin, a junction square.
	var far := level != Level.FULL
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
		var lin := tint.srgb_to_linear() * (1.0 if tint == style.asphalt else 0.6)
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
	if not (collide and _statics):
		return
	var cx := clampi(ceili(rect.size.x / ground_collision_step), 1, 48)
	var cz := clampi(ceili(rect.size.y / ground_collision_step), 1, 48)
	var shape := CollisionShape3D.new()
	shape.shape = (mesh if (cx == nx and cz == nz) else _grid_mesh(rect, top, skirt, cx, cz)).create_trimesh_shape()
	_statics.add_child(shape)


## One grid of `nx` by `nz` quads over `rect`, following the relief, with the skirt around it.
## `colored` gives every vertex `color` (the far chunks' merged ground).
func _grid_mesh(rect: Rect2, top: float, skirt: float, nx: int, nz: int, colored: bool = false, color: Color = Color.WHITE) -> ArrayMesh:
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


# --- Freeway ---------------------------------------------------------------------------------

## True where the freeway deck flies over, plus `margin` metres either side.
func _under_freeway(pos: Vector2, margin: float) -> bool:
	if plan.macro == null or plan.macro.freeway == null:
		return false
	return plan.macro.freeway.blocks(pos, margin)



## Deck segments of the freeway crossing this chunk.
func _freeway_segments() -> Array[Dictionary]:
	if plan.macro == null or plan.macro.freeway == null:
		return []
	return plan.macro.freeway.segments_in(owned_rect())


## The elevated freeway: deck, barriers, pillars down to the ground, lane paint, sign gantries
## and the off-ramps. Built straight into three meshes per chunk (asphalt top, vertex-coloured
## structure, unshaded paint) rather than through the batch, because the batch adds the ground
## relief to every instance and the deck is nine metres above it.
func _build_freeway() -> void:
	var segs := _freeway_segments()
	if segs.is_empty():
		return
	var area := owned_rect()
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck_body := StaticBody3D.new()
	deck_body.name = "FreewayBody"
	deck_body.collision_layer = 1
	deck_body.collision_mask = 0
	var quads := 0

	for seg in segs:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var seg_len := a.distance_to(b)
		if seg_len < 0.5:
			continue
		var mid := a.lerp(b, 0.5)
		# Segments are claimed by the chunk their midpoint falls in, so the deck is built once.
		if not area.has_point(mid):
			continue
		quads += 1
		var ha: float = seg.ha
		var hb: float = seg.hb
		var dir := (b - a) / seg_len
		var half: float = seg.width * 0.5
		var nrm := Vector2(-dir.y, dir.x)
		var edge := nrm * half
		var t := Freeway.DECK_THICKNESS

		var l0 := Vector3(a.x - edge.x, ha, a.y - edge.y)
		var r0 := Vector3(a.x + edge.x, ha, a.y + edge.y)
		var l1 := Vector3(b.x - edge.x, hb, b.y - edge.y)
		var r1 := Vector3(b.x + edge.x, hb, b.y + edge.y)
		var down := Vector3(0.0, -t, 0.0)
		# Deck top.
		for v: Vector3 in [l0, r1, r0, l0, l1, r1]:
			top.add_vertex(v)
		# Underside and the two edge fascias, so it is solid from below and from the street.
		var concrete := Color(0.62, 0.61, 0.59)
		_ribbon(body, l0 + down, r0 + down, r1 + down, l1 + down, concrete * 0.82, true)
		_ribbon(body, l0, l0 + down, l1 + down, l1, concrete)
		_ribbon(body, r0, r1, r1 + down, r0 + down, concrete)
		# Barriers along both edges.
		var bh := 1.05
		for side: float in [-1.0, 1.0]:
			var e := nrm * (half - 0.35) * side
			var p0 := Vector3(a.x + e.x, ha, a.y + e.y)
			var p1 := Vector3(b.x + e.x, hb, b.y + e.y)
			_bar(body, p0, p1, nrm * 0.35, bh, Color(0.70, 0.69, 0.67))

		# Lane paint: the median, and a dashed line between the lanes of each carriageway.
		var lift := Vector3(0.0, 0.035, 0.0)
		for off: float in [-0.04, 0.04]:
			var e := nrm * (half * off)
			_bar_flat(paint, Vector3(a.x + e.x, ha, a.y + e.y) + lift, Vector3(b.x + e.x, hb, b.y + e.y) + lift, nrm * 0.16, Color(0.95, 0.82, 0.22))
		for off: float in [-0.52, -0.17, 0.17, 0.52]:
			var e := nrm * (half * off)
			var p0 := Vector3(a.x + e.x, ha, a.y + e.y) + lift
			var p1 := Vector3(b.x + e.x, hb, b.y + e.y) + lift
			# Dashed: three metres of paint in every eight.
			_bar_flat(paint, p0.lerp(p1, 0.06), p0.lerp(p1, 0.44), nrm * 0.14, Color(0.93, 0.93, 0.90))

		# Pillars, on the segments that land on the spacing.
		var idx: int = seg.index
		if idx % int(round(Freeway.PILLAR_SPACING / Freeway.STEP)) == 0:
			var ground := plan.height_at(a)
			var cap := ha - t - 0.1
			if cap - ground > 1.5:
				_pillar(body, Vector3(a.x, ground - 1.0, a.y), cap, nrm, seg.width)

		# Overhead sign gantry every few hundred metres.
		if idx % int(round(Freeway.GANTRY_SPACING / Freeway.STEP)) == 0:
			_gantry(body, paint, Vector3(a.x, ha, a.y), nrm, half)

		# Collision: one box per segment, tilted to the segment's grade.
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(seg.width, t, seg_len + 0.4)
		cs.shape = bx
		var fwd := Vector3(b.x - a.x, hb - ha, b.y - a.y).normalized()
		var right := Vector3(nrm.x, 0.0, nrm.y)
		var up := right.cross(fwd).normalized()
		cs.transform = Transform3D(Basis(right, up, -fwd), Vector3(mid.x, (ha + hb) * 0.5 - t * 0.5, mid.y))
		deck_body.add_child(cs)

	if quads == 0:
		return
	add_child(deck_body)
	_commit_surface(top, "FreewayDeck", PropFactory.road("asphalt_aerial", 9.0, Color(0.69, 0.69, 0.71), hash([plan.seed, "freeway"]), 0.0, 0.7))
	_commit_surface(body, "FreewayStructure", PropFactory.material(Color.WHITE, 0.85))
	_commit_surface(paint, "FreewayPaint", PropFactory.material(Color.WHITE, 0.7))
	_build_freeway_ramps()


func _commit_surface(st: SurfaceTool, node_name: String, mat: Material) -> void:
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = st.commit()
	mesh.material_override = mat
	add_child(mesh)


## A flat quad a-b-c-d in one vertex colour; `flip` reverses the winding (for undersides).
func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, flip: bool = false) -> void:
	var order := [a, c, b, a, d, c] if flip else [a, b, c, a, c, d]
	for v: Vector3 in order:
		st.set_color(col)
		st.add_vertex(v)


## A box running from p0 to p1, `wide` across (a world-space half-offset) and `h` tall.
func _bar(st: SurfaceTool, p0: Vector3, p1: Vector3, wide: Vector2, h: float, col: Color) -> void:
	var w := Vector3(wide.x, 0.0, wide.y)
	var up := Vector3(0.0, h, 0.0)
	var corners := [p0 - w, p0 + w, p1 + w, p1 - w]
	for i in 4:
		var c0: Vector3 = corners[i]
		var c1: Vector3 = corners[(i + 1) % 4]
		_ribbon(st, c0, c1, c1 + up, c0 + up, col)
	# Same winding fix as _bar_flat: the cap is a horizontal quad and has to face up.
	_ribbon(st, corners[0] + up, corners[1] + up, corners[2] + up, corners[3] + up, col.lightened(0.08), true)


## A flat painted strip lying on the deck, facing up.
##
## `flip` here, not because it is an underside: `_ribbon`'s plain winding faces a horizontal quad
## DOWN, which is the opposite of the winding the deck top uses, so the lane paint was built
## back-facing and culled away entirely - a deck with no markings on it at all. The deck top's
## own order (l0, r1, r0) is the one to match.
func _bar_flat(st: SurfaceTool, p0: Vector3, p1: Vector3, wide: Vector2, col: Color) -> void:
	var w := Vector3(wide.x, 0.0, wide.y)
	_ribbon(st, p0 - w, p0 + w, p1 + w, p1 - w, col, true)


## A pair of columns and a crossbeam carrying the deck.
func _pillar(st: SurfaceTool, base: Vector3, cap_y: float, nrm: Vector2, deck_w: float) -> void:
	var col := Color(0.58, 0.57, 0.55)
	for side: float in [-1.0, 1.0]:
		var e := nrm * (deck_w * 0.26) * side
		var p := base + Vector3(e.x, 0.0, e.y)
		_bar(st, p + Vector3(-0.8, 0.0, 0.0), p + Vector3(0.8, 0.0, 0.0), nrm * 0.8, cap_y - base.y, col)
	# The headstock across the top of the columns.
	var cap := Vector3(base.x, cap_y - 1.1, base.y)
	var arm := Vector3(nrm.x, 0.0, nrm.y) * (deck_w * 0.34)
	_bar(st, cap - arm, cap + arm, nrm.orthogonal() * 1.3, 1.1, col.lightened(0.05))


## An overhead sign gantry: two posts, a truss beam and a green sign panel.
func _gantry(st: SurfaceTool, paint: SurfaceTool, at: Vector3, nrm: Vector2, half: float) -> void:
	var steel := Color(0.42, 0.43, 0.45)
	var post_h := 6.6
	for side: float in [-1.0, 1.0]:
		var e := nrm * (half - 0.2) * side
		var p := at + Vector3(e.x, 0.4, e.y)
		_bar(st, p, p + Vector3(0.0, 0.01, 0.0), nrm.orthogonal() * 0.28, post_h, steel)
	var beam := Vector3(nrm.x, 0.0, nrm.y) * (half - 0.2)
	var top := at + Vector3(0.0, 0.4 + post_h, 0.0)
	_bar(st, top - beam, top + beam, nrm.orthogonal() * 0.30, 0.55, steel)
	# The sign board itself, hung under the beam on the side traffic reads it from.
	var board := top + Vector3(0.0, -1.9, 0.0)
	var bw := Vector3(nrm.x, 0.0, nrm.y) * (half * 0.42)
	var face := Vector3(nrm.y, 0.0, -nrm.x) * 0.10
	for s: float in [-1.0, 1.0]:
		var c := board + Vector3(nrm.x, 0.0, nrm.y) * (half * 0.46) * s
		_ribbon(paint, c - bw * 0.5 + face, c + bw * 0.5 + face, c + bw * 0.5 + face + Vector3(0.0, 1.7, 0.0), c - bw * 0.5 + face + Vector3(0.0, 1.7, 0.0), Color(0.09, 0.30, 0.16))


## Off-ramps: a sloped ribbon peeling off the deck edge and running down to the street, with a
## barrier on each side. The landing is on the surface grid, so you can drive on and off.
func _build_freeway_ramps() -> void:
	if plan.macro == null or plan.macro.freeway == null:
		return
	var area := owned_rect()
	var list := plan.macro.freeway.ramps_in(area)
	if list.is_empty():
		return
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ramp_body := StaticBody3D.new()
	ramp_body.name = "RampBody"
	ramp_body.collision_layer = 1
	ramp_body.collision_mask = 0
	var built := 0
	for r in list:
		var start: Vector2 = r.pos
		var yaw: float = r.yaw
		var out := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(-out.y, out.x)
		var top_y: float = r.top
		var run := 78.0
		var steps := 13
		var width := 9.0
		var prev := start
		var prev_y := top_y - Freeway.DECK_THICKNESS * 0.5
		var ground_end := plan.height_at(start + out * run) + 0.12
		for k in range(1, steps + 1):
			var t := float(k) / steps
			# Ease out at both ends so the ramp meets the deck and the street smoothly.
			var ease := t * t * (3.0 - 2.0 * t)
			var p: Vector2 = start + out * (run * t) + side * (10.0 * sin(t * PI) * float(r.side))
			var y := lerpf(top_y - Freeway.DECK_THICKNESS * 0.5, ground_end, ease)
			var d: Vector2 = p - prev
			if d.length() < 0.2:
				continue
			var n := Vector2(-d.y, d.x).normalized() * (width * 0.5)
			var l0 := Vector3(prev.x - n.x, prev_y, prev.y - n.y)
			var r0 := Vector3(prev.x + n.x, prev_y, prev.y + n.y)
			var l1 := Vector3(p.x - n.x, y, p.y - n.y)
			var r1 := Vector3(p.x + n.x, y, p.y + n.y)
			for v: Vector3 in [l0, r1, r0, l0, l1, r1]:
				deck.add_vertex(v)
			var drop := Vector3(0.0, -0.7, 0.0)
			_ribbon(body, l0 + drop, r0 + drop, r1 + drop, l1 + drop, Color(0.5, 0.49, 0.47), true)
			_ribbon(body, l0, l0 + drop, l1 + drop, l1, Color(0.6, 0.59, 0.57))
			_ribbon(body, r0, r1, r1 + drop, r0 + drop, Color(0.6, 0.59, 0.57))
			for s: float in [-1.0, 1.0]:
				var e := n * 0.92 * s
				_bar(body, Vector3(prev.x + e.x, prev_y, prev.y + e.y), Vector3(p.x + e.x, y, p.y + e.y), n.normalized() * 0.22, 0.9, Color(0.70, 0.69, 0.67))
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
	_commit_surface(deck, "RampDeck", PropFactory.road("asphalt_aerial", 9.0, Color(0.69, 0.69, 0.71), hash([plan.seed, "ramp"]), 0.0, 0.7))
	_commit_surface(body, "RampStructure", PropFactory.material(Color.WHITE, 0.85))


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
