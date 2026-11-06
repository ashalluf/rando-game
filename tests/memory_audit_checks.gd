extends RefCounted
## The memory checks for tests/smoke_test.gd (docs/HANDOFF.md, "Memory audit"): the run's peak
## resident memory stays under a budget, and the leaks and copies the audit cut stay cut - derived
## meshes keyed so a reloaded model finds its old copy (PropFactory.mesh_key()), shadow twins
## holding only the vertices they draw (MeshCompact), the crowd's weld data dropped once its two
## bodies are built, TreeFire forgetting the chunks that are gone. Loaded at run time, so it
## compiles after the autoloads.
##
## The budget: MEMORY_BUDGET_MB in the environment, else BUDGET_MB. It is the peak of the whole
## process so far (VmHWM), read where this runs in the smoke test (after the city's checks), so a
## feature that adds a cache the size of a city shows up here before it shows up as an OOM kill.
## Linux only (/proc); elsewhere the budget line is skipped.

## Peak resident memory of the headless smoke test up to these checks, in MB. Measured on the
## 4-core / 15 GB fleet box after the audit: see docs/HANDOFF.md for the numbers. The fleet's
## ceiling is 4 GB: the merged city of 2026-10-05 (batches 1-4) peaked at 3.3-3.7 GB before the
## audit, so ordinary growth passes and a doubling does not.
const BUDGET_MB := 4000

var _t: Node
var _tree: SceneTree


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_mesh_key()
	_compact()
	_shadow_twins()
	_welds()
	_tree_fire(city)
	_tucks()
	_budget()


## A model's derived meshes are keyed by its sub-resource path, the same on every load: keyed by
## the RID, every reload of a car body built (and kept) another wheel tuck.
func _mesh_key() -> void:
	var path := "res://assets/models/road_sedan.glb"
	if not ResourceLoader.exists(path):
		return
	var keys: Array[String] = []
	var rids: Array[int] = []
	for i in 2:
		var inst: Node = (load(path) as PackedScene).instantiate()
		var mi := inst.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		keys.append(PropFactory.mesh_key(mi.mesh))
		rids.append(mi.mesh.get_rid().get_id())
		inst.free()
	_check(keys[0] == keys[1] and keys[0].begins_with("res://"),
		"a model's mesh key survives a reload (%s; RIDs %s)" % [keys[0], "differ" if rids[0] != rids[1] else "same"])


## MeshCompact drops exactly the vertices no index uses and draws the same triangles.
func _compact() -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var tans := PackedFloat32Array()
	for i in 12:
		verts.append(Vector3(i, i * 0.5, -i))
		uvs.append(Vector2(i * 0.1, 1.0 - i * 0.1))
		cols.append(Color(i / 12.0, 0.5, 1.0 - i / 12.0, 1.0))
		tans.append_array([1.0, 0.0, 0.0, float(i % 2) * 2.0 - 1.0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TANGENT] = tans
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([2, 5, 9, 9, 5, 11])
	var lods := {0.5: PackedInt32Array([2, 5, 7])}
	var out: Array = MeshCompact.compact(arrays, lods)
	var ov: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
	var oi: PackedInt32Array = out[Mesh.ARRAY_INDEX]
	var same := oi.size() == 6
	for i in oi.size():
		var src: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array)[i]
		same = same and ov[oi[i]] == verts[src] and (out[Mesh.ARRAY_TEX_UV] as PackedVector2Array)[oi[i]] == uvs[src] \
			and (out[Mesh.ARRAY_COLOR] as PackedColorArray)[oi[i]] == cols[src] \
			and (out[Mesh.ARRAY_TANGENT] as PackedFloat32Array)[oi[i] * 4 + 3] == tans[src * 4 + 3]
	var lod: PackedInt32Array = lods[0.5]
	same = same and ov[lod[2]] == verts[7]
	_check(ov.size() == 5 and same, "MeshCompact keeps the 5 used vertices of 12, every attribute and both index lists (%d)" % ov.size())


## Every imported model's shadow stand-in holds fewer vertices than the mesh it stands in for
## (it draws a coarse LOD of it; it used to carry the whole vertex buffer).
func _shadow_twins() -> void:
	var twins := 0
	var lean := 0
	var saved := 0
	for mesh in PropFactory._shadow_proxies:
		var proxy: Mesh = PropFactory._shadow_proxies[mesh]
		if not (mesh is ArrayMesh) or not (proxy is ArrayMesh) or not is_instance_valid(mesh):
			continue
		var a := 0
		var b := 0
		for s in (mesh as ArrayMesh).get_surface_count():
			a += (mesh as ArrayMesh).surface_get_array_len(s)
		for s in (proxy as ArrayMesh).get_surface_count():
			b += (proxy as ArrayMesh).surface_get_array_len(s)
		twins += 1
		if b < a:
			lean += 1
		saved += a - b
	_check(twins == 0 or lean * 10 >= twins * 8,
		"shadow stand-ins keep only the vertices they draw (%d of %d leaner, %d vertices fewer)" % [lean, twins, saved])


## The crowd's weld data (its arrays read back, the welded copy and its LOD chain) is dropped once
## a model's middle and far bodies are both built.
func _welds() -> void:
	var held := 0
	var built := 0
	for mesh in Pedestrian._far_meshes:
		var per: Dictionary = Pedestrian._far_meshes[mesh]
		if per.has(Pedestrian.mid_triangles) and per.has(Pedestrian.far_triangles):
			built += 1
			if Pedestrian._welds.has(mesh):
				held += 1
	_check(held == 0, "no weld kept for a model whose two far bodies are built (%d of %d)" % [held, built])


## TreeFire keeps records only for chunks that still exist.
func _tree_fire(city: Node3D) -> void:
	var dead := 0
	var all := 0
	for k in TreeFire._chunks:
		all += 1
		var ch: Variant = (TreeFire._chunks[k].chunk as WeakRef).get_ref()
		if ch == null or not is_instance_valid(ch):
			dead += 1
	var full := int(city.call("chunk_counts").x)
	_check(dead <= full and all <= full * 2 + 8, "TreeFire keeps %d chunk records, %d of them gone (%d FULL chunks)" % [all, dead, full])


## The wheel tucks are keyed by path, so each body model has one.
func _tucks() -> void:
	var by_rid := 0
	var n := 0
	for k in PropFactory._cache:
		var key := str(k)
		if key.begins_with("body_tuck_"):
			n += 1
			if key.contains("rid") or key.contains("RID("):
				by_rid += 1
	_check(by_rid == 0, "body wheel tucks are keyed by the model's path (%d tucks, %d by RID)" % [n, by_rid])


func _budget() -> void:
	var hwm := _hwm_mb()
	if hwm <= 0:
		return
	var budget := BUDGET_MB
	var env := OS.get_environment("MEMORY_BUDGET_MB")
	if env.is_valid_int():
		budget = int(env)
	_check(hwm <= budget, "the smoke test's peak resident memory so far is %d MB (budget %d MB)" % [hwm, budget])


## This process's peak resident set (VmHWM) in MB, or 0 where /proc is missing.
static func _hwm_mb() -> int:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return 0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmHWM:"):
			return int(line.split(":")[1].strip_edges().split(" ")[0]) / 1024
	return 0
