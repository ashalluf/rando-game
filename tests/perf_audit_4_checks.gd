extends RefCounted
## The fourth perf audit's cuts (docs/HANDOFF.md, the perf-audit-4 section) for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads. Every check reads what it stages or the
## city as it stands, never where an earlier file left the player.
##   - HorizonTiles cuts a mesh into tiles holding exactly its triangles, each inside its box;
##   - the horizon plane and the far ring are drawn by those tiles, every triangle once;
##   - a far-city tile node is hidden only when every block in it is dissolved, and shown when any is not.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tiles_exact()
	_horizon(city)
	_far_cover(city)


## Every triangle of a plane comes back in exactly one tile, by its vertices' positions; every
## tile's vertices lie inside its box; no tile keeps a vertex it does not draw.
func _tiles_exact() -> void:
	var p := PlaneMesh.new()
	p.size = Vector2(1000.0, 1000.0)
	p.subdivide_width = 41
	p.subdivide_depth = 41
	var src: Array = p.get_mesh_arrays()
	var want := _tri_keys(src[Mesh.ARRAY_VERTEX], src[Mesh.ARRAY_INDEX])
	var got: Dictionary = {}
	var inside := true
	var compact := true
	var parts := HorizonTiles.tile_meshes(p, 4)
	for e: Array in parts:
		var a := (e[0] as ArrayMesh).surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var used := {}
		for i in idx:
			used[i] = true
		compact = compact and used.size() == v.size()
		var box: AABB = e[1]
		for q in v:
			inside = inside and box.grow(0.001).has_point(q)
		for k in _tri_keys(v, idx):
			got[k] = int(got.get(k, 0)) + 1
	var exact := got.size() == want.size()
	for k in want:
		exact = exact and int(got.get(k, 0)) == 1
	_t._check(parts.size() == 16 and exact and inside and compact,
		"perf-audit-4: a tiled plane draws each of its %d triangles exactly once (%d tiles, %d triangles back), each tile inside its box and holding only the vertices it draws"
			% [want.size(), parts.size(), got.size()])


static func _tri_keys(v: PackedVector3Array, idx: PackedInt32Array) -> Dictionary:
	var out := {}
	for i in range(0, idx.size(), 3):
		out["%s|%s|%s" % [v[idx[i]].snapped(Vector3.ONE * 0.01), v[idx[i + 1]].snapped(Vector3.ONE * 0.01), v[idx[i + 2]].snapped(Vector3.ONE * 0.01)]] = true
	return out


## The streamer's horizon plane and far ring are tiled (or one mesh with the switch off), the plane
## keeping all of its PlaneMesh's triangles.
func _horizon(city: Node3D) -> void:
	var ground: Node3D = city.get("_ground")
	if ground == null or ground.get_child_count() == 0:
		_t._check(false, "perf-audit-4: the city has its horizon plane")
		return
	var mi := ground.get_child(0) as MeshInstance3D
	var tris := 0
	var boxed := true
	for m: Mesh in HorizonTiles.meshes_of(mi):
		tris += (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	for c in mi.get_children():
		if c is MeshInstance3D:
			boxed = boxed and (c as MeshInstance3D).custom_aabb.size.x > 0.0 and (c as MeshInstance3D).material_override == mi.material_override
	var n: int = city.get_script().get_script_constant_map().get("GROUND_SUBDIVISIONS", 320) + 1
	var tiles := HorizonTiles.meshes_of(mi).size()
	_t._check(tris == n * n * 2 and boxed and (tiles == HorizonTiles.TILES * HorizonTiles.TILES if HorizonTiles.enabled else tiles == 1),
		"perf-audit-4: the horizon plane is %d tiles on its own material with tight boxes, %d triangles (a %d x %d grid)" % [tiles, tris, n, n])
	var ring: MeshInstance3D = city.get("_far_ring")
	if ring:
		var rt := HorizonTiles.meshes_of(ring).size()
		_t._check(rt > 3 if HorizonTiles.enabled else rt == 1,
			"perf-audit-4: the far ranges' ring is cut into %d tiles" % rt)


## For every built far-city tile: a node is hidden exactly when every block it draws for is
## dissolved (alpha 0; the planting only under a FULL chunk).
func _far_cover(city: Node3D) -> void:
	var sky = city.get("_skyline")
	if sky == null:
		return
	var bad := 0
	var hidden := 0
	var nodes := 0
	for t: Vector2i in sky._tiles:
		var tile = sky._tiles[t]
		if tile == null:
			continue
		var want := [false, false, false, false]
		for block: Vector2i in sky._tile_blocks.get(t, []):
			var b: Dictionary = sky._blocks[block]
			var a: float = sky._alpha.get(block, 1.0)
			if a > 0.0 or not Skyline.hide_covered:
				want[0] = want[0] or int(b.bn) > 0
				want[2] = want[2] or int(b.hn) > 0
				want[3] = want[3] or int(b.get("en", 0)) > 0
			if a > 0.0 or int(sky._cover.get(block, 1)) != CityChunk.Level.FULL or not Skyline.hide_covered:
				want[1] = want[1] or int(b.vn) > 0
		var list: Array = [tile.node, tile.veg, tile.house, tile.get("est")]
		for k in 4:
			if list[k] == null:
				continue
			nodes += 1
			if not (list[k] as Node3D).visible:
				hidden += 1
			if (list[k] as Node3D).visible != want[k]:
				bad += 1
	_t._check(bad == 0 and nodes > 0, "perf-audit-4: far-city tile nodes are hidden exactly when everything they draw is dissolved (%d of %d hidden, %d wrong)" % [hidden, nodes, bad])
