class_name HorizonTiles
extends RefCounted
## The horizon plane (206 k triangles) and the far ranges' ring (~120 k) are each ONE mesh with a
## cull margin the size of the map, so the renderer drew all of both at every camera, however
## little of them was in view (perf-audit-4: a third of the beach camera's triangles, a sixth of
## the hills'). split() cuts such a mesh into a grid of tiles holding EXACTLY its triangles and
## vertices (each tile's index list is a subset of the original's, compacted with MeshCompact),
## each with a tight box in x and z and the full lift range in y, so the frustum drops the tiles
## behind and beside the camera. The vertex shader only moves vertices vertically, so a tile never
## draws outside its box. Same triangles, same rasterisation, same pixels.
##
## HORIZON_TILES=0 in the environment keeps the single meshes (the A/B).

static var enabled := OS.get_environment("HORIZON_TILES") != "0"

## Tiles per side of the grid.
const TILES := 4
## The box's height range (mesh space): the bake lifts the plane up to MacroMap.BAKE_HEIGHT_SCALE
## (1,600 m) plus crags, and sinks it with distance and under water.
const Y_MIN := -1500.0
const Y_MAX := 4500.0
## Slack round each tile's x / z extent.
const MARGIN := 2.0


## Replaces `mi`'s mesh by the first tile and adds the others as children named
## "<mi name>_tile<k>" with meta horizon_tile (sharing material_override, shadow and layer
## settings). Does nothing when disabled or when `mi` has no indexed mesh.
static func split(mi: MeshInstance3D, tiles: int = TILES) -> void:
	if not enabled or mi == null or mi.mesh == null:
		return
	var parts := tile_meshes(mi.mesh, tiles)
	if parts.size() < 2:
		return
	mi.extra_cull_margin = 0.0
	for k in parts.size():
		var target := mi
		if k > 0:
			target = MeshInstance3D.new()
			target.name = "%s_tile%d" % [mi.name if mi.name != "" else "Horizon", k]
			target.set_meta("horizon_tile", true)
			target.material_override = mi.material_override
			target.cast_shadow = mi.cast_shadow
			target.layers = mi.layers
			target.gi_mode = mi.gi_mode
			mi.add_child(target)
		target.mesh = parts[k][0]
		target.custom_aabb = parts[k][1]


## Every mesh drawing `mi`'s geometry: its own and its tiles' (what a check reads back).
static func meshes_of(mi: MeshInstance3D) -> Array[Mesh]:
	var out: Array[Mesh] = []
	if mi == null:
		return out
	if mi.mesh:
		out.append(mi.mesh)
	for c in mi.get_children():
		if c is MeshInstance3D and c.has_meta("horizon_tile") and (c as MeshInstance3D).mesh:
			out.append((c as MeshInstance3D).mesh)
	return out


## `mesh`'s first surface cut into a tiles x tiles grid by triangle centroid: [[ArrayMesh, AABB], ...]
## for the tiles that hold any triangle, in grid order.
static func tile_meshes(mesh: Mesh, tiles: int) -> Array:
	var arrays: Array = mesh.surface_get_arrays(0) if mesh is ArrayMesh else (mesh as PrimitiveMesh).get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if verts.is_empty() or idx.is_empty():
		return []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in verts:
		lo = lo.min(Vector2(v.x, v.z))
		hi = hi.max(Vector2(v.x, v.z))
	var span := (hi - lo) / float(tiles)
	var lists: Array[PackedInt32Array] = []
	lists.resize(tiles * tiles)
	for i in range(0, idx.size(), 3):
		var c := (verts[idx[i]] + verts[idx[i + 1]] + verts[idx[i + 2]]) / 3.0
		var tx := clampi(int((c.x - lo.x) / span.x), 0, tiles - 1)
		var tz := clampi(int((c.z - lo.y) / span.y), 0, tiles - 1)
		var t := tz * tiles + tx
		lists[t].append(idx[i])
		lists[t].append(idx[i + 1])
		lists[t].append(idx[i + 2])
	var mat := mesh.surface_get_material(0)
	var out: Array = []
	for t in lists.size():
		if lists[t].is_empty():
			continue
		var a := arrays.duplicate()
		a[Mesh.ARRAY_INDEX] = lists[t]
		a = MeshCompact.compact(a)
		var tv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var blo := Vector2(INF, INF)
		var bhi := Vector2(-INF, -INF)
		for v in tv:
			blo = blo.min(Vector2(v.x, v.z))
			bhi = bhi.max(Vector2(v.x, v.z))
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		if mat:
			am.surface_set_material(0, mat)
		var box := AABB(Vector3(blo.x - MARGIN, Y_MIN, blo.y - MARGIN),
			Vector3(bhi.x - blo.x + 2.0 * MARGIN, Y_MAX - Y_MIN, bhi.y - blo.y + 2.0 * MARGIN))
		out.append([am, box])
	return out
