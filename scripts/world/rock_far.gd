class_name RockFar
extends Node3D
## Draws every tor RockOutcrops plans (scripts/world/rock_outcrops.gd), at every distance, so a
## crag never pops between tiers: near cells (NEAR_CELL square, the scans, one level, a shadow from
## the welded mesh) within NEAR_RANGE of the camera, far cells (FAR_CELL square, RockKit's welded
## meshes with their LODs, no shadow) for the rest of the basin. One MultiMesh per kind per cell. A tor in a
## shown near cell is collapsed in its far cell (INSTANCE_CUSTOM.a 0), so it is drawn once.
## Where a FULL or LOD chunk drew the real terrain under a tor (`claim()`), the tor stands where
## the CPU put it (INSTANCE_CUSTOM.r 1); elsewhere rock_outcrop.gdshader seats it on the horizon
## plane's drawn ground. Its node's origin is the true-world origin (MountainOccluder's rule), a
## child of the streamer so the origin shifts carry it.

const NEAR_CELL := 320.0
const FAR_CELL := 1920.0
## Metres from the camera to a near cell's nearest point inside which the cell is shown: inside
## the LOD ring (CityStreamer.lod_reach_metres(), 840 m), so a near tor stands on a chunk's real
## terrain; past it the welded mesh is a good match for a rock that size.
const NEAR_RANGE := 420.0
## Metres to a near cell inside which its tors cast (their welded mesh, SHADOWS_ONLY).
const SHADOW_RANGE := 240.0
## Seconds between looks at which near cells to show.
const SURVEY := 0.4

## The RockFar nodes alive (a check can build a second city while the first stands); `current`
## is the newest in the tree.
static var _live: Array[RockFar] = []
static var current: RockFar:
	get:
		for i in range(_live.size() - 1, -1, -1):
			if is_instance_valid(_live[i]) and _live[i].is_inside_tree():
				return _live[i]
		return null
## ROCK_DEBUG=1: every survey prints what is shown and claimed.
static var DEBUG: bool = OS.get_environment("ROCK_DEBUG") == "1"

var _plan: CityPlan
var _tors: Array = []
## Per tor: [near key, index there, far key, index there].
var _slots: Array = []
## Vector3i(cell x, cell z, kind) -> MultiMeshInstance3D: the near cells built (on first show,
## freed when hidden), the tors of every near cell, and the far cells (all built at once).
var _near: Dictionary = {}
var _near_lists: Dictionary = {}
var _far: Dictionary = {}
## Vector3i -> the near cell's shadow (the welded mesh, SHADOWS_ONLY), shown with it.
var _near_shadow: Dictionary = {}
## Near cell (Vector2i) -> the tor ids in it.
var _near_tors: Dictionary = {}
var _shown: Dictionary = {}
## Seed -> {tor id -> how many chunks claim it}. Static: the chunks the loading screen builds can
## claim before this node exists, and it reads them when it does.
static var _claims: Dictionary = {}
var _clock := 0.0
var _materials: Array[ShaderMaterial] = []


## Builds the node under `streamer` (CityStreamer) once the basin bake exists. Copies the far
## planting material's plane uniforms and has the streamer keep them current.
static func attach(streamer: Node3D, plan: CityPlan, canopy: ShaderMaterial) -> RockFar:
	if not RockOutcrops.enabled or plan == null or plan.macro == null or plan.macro.bake_height == null:
		return null
	var tors := RockOutcrops.tors(plan)
	if tors.is_empty():
		return null
	var f := RockFar.new()
	f.name = "RockFar"
	f._plan = plan
	f._tors = tors
	f.position = WorldState.to_local(Vector3.ZERO)
	for kind in RockKit.TOR_KINDS:
		for far in [false, true]:
			var mat := RockKit.material(kind, true, far)
			_copy_plane(canopy, mat)
			AerialReview.apply_rock(mat)
			f._materials.append(mat)
	# The near rock (a chunk's batch) hashes its tone off the true origin: it needs world_offset.
	for kind in RockKit.KINDS.size():
		f._materials.append(RockKit.material(kind, false, false))
	var list: Variant = streamer.get("_far_ground_materials")
	if list is Array:
		for m in f._materials:
			(list as Array).append(m)
	f._build()
	streamer.add_child(f)
	_live.append(f)
	return f


static func _copy_plane(src: ShaderMaterial, dst: ShaderMaterial) -> void:
	if src == null:
		return
	for p in ["macro_tex", "macro_height_tex", "macro_centre", "macro_span", "macro_height", "calm_centre",
			"calm_axes", "calm_dir", "calm2_centre", "calm2_axes", "plane_half", "plane_step", "edge_start",
			"edge_end", "world_offset", "plane_origin"]:
		var v: Variant = src.get_shader_parameter(p)
		if v != null:
			dst.set_shader_parameter(p, v)


func _build() -> void:
	var near_lists := {}
	var far_lists := {}
	_slots.resize(_tors.size())
	for t: Dictionary in _tors:
		var p: Vector2 = t.pos
		var nk := Vector3i(floori(p.x / NEAR_CELL), floori(p.y / NEAR_CELL), int(t.kind))
		var fk := Vector3i(floori(p.x / FAR_CELL), floori(p.y / FAR_CELL), int(t.kind))
		if not near_lists.has(nk):
			near_lists[nk] = []
		if not far_lists.has(fk):
			far_lists[fk] = []
		_slots[int(t.id)] = [nk, (near_lists[nk] as Array).size(), fk, (far_lists[fk] as Array).size()]
		(near_lists[nk] as Array).append(t)
		(far_lists[fk] as Array).append(t)
		var c2 := Vector2i(nk.x, nk.y)
		if not _near_tors.has(c2):
			_near_tors[c2] = []
		(_near_tors[c2] as Array).append(int(t.id))
	_near_lists = near_lists
	for k: Vector3i in far_lists:
		_far[k] = _cell(far_lists[k], k.z, true, "RockFar_%d_%d_%d" % [k.x, k.y, k.z])


func _cell(list: Array, kind: int, far: bool, label: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = RockKit.mid_mesh(kind) if far else RockKit.mesh(kind)
	mm.instance_count = list.size()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var b: AABB = RockKit.bounds(kind)
	for i in list.size():
		var t: Dictionary = list[i]
		var xf := Transform3D(t.basis, Vector3(t.pos.x, t.y, t.pos.y))
		mm.set_instance_transform(i, xf)
		mm.set_instance_custom_data(i, Color(1.0 if is_claimed(_plan.seed, int(t.id)) else 0.0, float(t.tone), float(t.sink) / 100.0, 1.0))
		var wb := xf * b
		lo = lo.min(wb.position)
		hi = hi.max(wb.end)
	var mi := MultiMeshInstance3D.new()
	mi.name = label
	mi.multimesh = mm
	mi.material_override = RockKit.material(kind, true, far)
	# The seat on the far plane moves a rock tens of metres; the box allows for it.
	mi.custom_aabb = AABB(lo - Vector3(0.0, 120.0, 0.0), hi - lo + Vector3(0.0, 240.0, 0.0))
	# Shadows come from the welded mesh (_near_shadow): the scan's own would cost 9k triangles a
	# rock in every cascade.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = SURVEY
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	survey(WorldState.to_world(cam.global_position))


## Shows the near cells within NEAR_RANGE of the TRUE world point `eye`, collapsing their tors
## in the far cells, and hands the rest back.
func survey(eye: Vector3) -> void:
	var e := Vector2(eye.x, eye.z)
	var want := {}
	var shade := {}
	var r := int(ceil(NEAR_RANGE / NEAR_CELL)) + 1
	var c := Vector2i(floori(e.x / NEAR_CELL), floori(e.y / NEAR_CELL))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := c + Vector2i(dx, dz)
			if not _near_tors.has(k):
				continue
			var rect := Rect2(Vector2(k) * NEAR_CELL, Vector2(NEAR_CELL, NEAR_CELL))
			var q := Vector2(clampf(e.x, rect.position.x, rect.end.x), clampf(e.y, rect.position.y, rect.end.y))
			if q.distance_to(e) < NEAR_RANGE:
				want[k] = true
				if q.distance_to(e) < SHADOW_RANGE:
					shade[k] = true
	for k: Vector2i in _shown.keys():
		if not want.has(k):
			_show_near(k, false)
	for k: Vector2i in want:
		if not _shown.has(k):
			_show_near(k, true)
	for k: Vector2i in _shown:
		for kind in RockKit.TOR_KINDS:
			var key := Vector3i(k.x, k.y, kind)
			if _near_shadow.has(key):
				(_near_shadow[key] as Node3D).visible = shade.has(k)
	if DEBUG:
		var near_tors := 0
		for k: Vector2i in _shown:
			near_tors += (_near_tors[k] as Array).size()
		print("ROCKFAR eye %s near cells %d (%d tors), claimed %d" % [e, _shown.size(), near_tors, (_claims.get(_plan.seed, {}) as Dictionary).size()])


func _show_near(cell: Vector2i, on: bool) -> void:
	if on:
		_shown[cell] = true
	else:
		_shown.erase(cell)
	for kind in RockKit.TOR_KINDS:
		var k := Vector3i(cell.x, cell.y, kind)
		if not _near_lists.has(k):
			continue
		if on and not _near.has(k):
			_near[k] = _cell(_near_lists[k], k.z, false, "RockNear_%d_%d_%d" % [k.x, k.y, k.z])
			var sh := _cell(_near_lists[k], k.z, true, "RockNearShadow_%d_%d_%d" % [k.x, k.y, k.z])
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			sh.visible = false
			_near_shadow[k] = sh
		elif not on and _near.has(k):
			(_near[k] as Node).queue_free()
			(_near_shadow[k] as Node).queue_free()
			_near.erase(k)
			_near_shadow.erase(k)
	for id: int in _near_tors[cell]:
		_write(id)


## Rewrites tor `id`'s custom data in both its cells from its claims and its near cell's state.
func _write(id: int) -> void:
	var t: Dictionary = _tors[id]
	var s: Array = _slots[id]
	var real := 1.0 if is_claimed(_plan.seed, id) else 0.0
	var nk: Vector3i = s[0]
	var shown := _shown.has(Vector2i(nk.x, nk.y))
	var data := Color(real, float(t.tone), float(t.sink) / 100.0, 1.0)
	if _near.has(nk):
		((_near[nk] as MultiMeshInstance3D).multimesh).set_instance_custom_data(int(s[1]), data)
		((_near_shadow[nk] as MultiMeshInstance3D).multimesh).set_instance_custom_data(int(s[1]), data)
	data.a = 0.0 if shown else 1.0
	((_far[s[2]] as MultiMeshInstance3D).multimesh).set_instance_custom_data(int(s[3]), data)


## A chunk drew the real terrain under these tors of seed `seed` (CityChunk FULL or LOD): they
## stand on it.
static func claim(seed: int, ids: Array) -> void:
	if not _claims.has(seed):
		_claims[seed] = {}
	var c: Dictionary = _claims[seed]
	for id: int in ids:
		c[id] = int(c.get(id, 0)) + 1
		if int(c[id]) == 1:
			_rewrite(seed, id)


static func release(seed: int, ids: Array) -> void:
	var c: Dictionary = _claims.get(seed, {})
	for id: int in ids:
		var n := int(c.get(id, 0)) - 1
		if n <= 0:
			c.erase(id)
			_rewrite(seed, id)
		else:
			c[id] = n


static func is_claimed(seed: int, id: int) -> bool:
	return int((_claims.get(seed, {}) as Dictionary).get(id, 0)) > 0


static func _rewrite(seed: int, id: int) -> void:
	for f in _live:
		if is_instance_valid(f) and f._plan and f._plan.seed == seed and id < f._tors.size():
			f._write(id)


## The built near cell `k` (Vector3i cell x, z, kind), or null.
func near_node(k: Vector3i) -> MultiMeshInstance3D:
	return _near.get(k) as MultiMeshInstance3D


func near_shown(cell: Vector2i) -> bool:
	return _shown.has(cell)


func _exit_tree() -> void:
	_live.erase(self)
