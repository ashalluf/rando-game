class_name MultiMeshBatch
extends RefCounted
## Collects transforms per mesh and emits one MultiMeshInstance3D per mesh.
## Used for the thousands of small repeated things in a city: lamps, trees, dashes, stripes.

var _batches: Dictionary = {}
## Optional ground function (x, z) -> y added to every instance origin (the city relief).
var ground: Callable
## Batch keys whose instances lie flat on the ground (road markings): they are tilted to the
## ground slope as well, so a long dash on a hill does not poke out of the asphalt.
var tilt_keys: Dictionary = {}


## Returns the instance index within `key`, so callers can hide that instance later.
func add(key: String, mesh: Mesh, xform: Transform3D, color: Color = Color.WHITE, custom: Color = Color.BLACK) -> int:
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "xforms": [], "colors": [], "custom": [], "no_shadow": false}
	var batch: Dictionary = _batches[key]
	if ground.is_valid():
		var x := xform.origin.x
		var z := xform.origin.z
		xform.origin.y += ground.call(x, z)
		if tilt_keys.has(key):
			var gx: float = (ground.call(x + 0.5, z) - ground.call(x - 0.5, z))
			var gz: float = (ground.call(x, z + 0.5) - ground.call(x, z - 0.5))
			var normal := Vector3(-gx, 1.0, -gz).normalized()
			var axis := Vector3.UP.cross(normal)
			if axis.length_squared() > 1e-8:
				xform.basis = Basis(axis.normalized(), Vector3.UP.angle_to(normal)) * xform.basis
	batch.xforms.append(xform)
	batch.colors.append(color)
	batch.custom.append(custom)
	return batch.xforms.size() - 1


func keys() -> Array:
	return _batches.keys()


## The collected instances, key -> {"mesh", "xforms", "colors", "custom"}, without building any
## nodes: the far city reads a capture chunk's batches this way (CityChunk.capturing).
func data() -> Dictionary:
	return _batches


func set_no_shadow(key: String) -> void:
	if _batches.has(key):
		_batches[key].no_shadow = true


## Stops drawing this batch past `meters`. Use it for dense detail geometry (grass) that costs
## real triangles but is invisible at a distance anyway.
func set_draw_distance(key: String, meters: float) -> void:
	if _batches.has(key):
		_batches[key].draw_distance = meters


## Off: every batch is one node again, as before foliage was split into cells (the "before"
## side of that A/B, still_shot.gd TREE_CELLS=0).
static var cell_split: bool = true
## Foliage batches (PropFactory.lod_cells()) that would draw at least this many triangles at
## full detail are split into cells. A batch picks ONE mesh LOD for all its instances, from the
## nearest point of its bounds (none at all while the camera is inside them), and it is culled
## as one box: every tree of the block the camera stands in drew at full detail, the ones
## behind the camera and behind the buildings included, and into every shadow cascade the
## block touched. A cell is a few trees, so it is culled, shadow-cascaded and LOD-picked as
## that - the renderer's own one-pixel rule, per group of trees rather than per block.
static var cell_min_tris: int = 60000
## Largest side of a cell, metres (instance origins; the canopies add their own radius).
static var cell_size: float = 36.0
## A cell keeps at least this many instances, so a lone tree does not become its own draw.
static var cell_min_instances: int = 3
## Most cells a batch is split into (a draw a surface each, and a shadow twin's).
static var cell_max: int = 12
## The cells are drawn only while the camera is within this distance of the batch's centre
## (hierarchical LOD: they are the whole batch's visibility children). Past it the batch draws
## whole, one draw a surface as before - a cell split buys nothing a block away but draws.
static var cell_range: float = 190.0
## Cells pick their mesh LOD for the biggest instance in them (lod_bias = its scale): the
## renderer measures a multimesh's LOD error at the node's scale, not the instances'.
static var cell_lod_scale: bool = true
static var debug_record: bool = false
static var debug_batches: Array = []
## Hysteresis of that switch, metres, so the camera standing on the line does not flip it.
const CELL_RANGE_MARGIN := 12.0


## Builds the MultiMeshInstance3D nodes and returns them keyed by batch key. A split batch is
## returned as its whole node, which carries its cells in metadata (hide_instance() uses them).
func build(parent: Node3D) -> Dictionary:
	var nodes := {}
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var xforms: Array = batch.xforms
		if xforms.is_empty():
			continue
		var draw_distance: float = batch.get("draw_distance", 0.0)
		var proxy: Mesh = null if batch.no_shadow else PropFactory.shadow_proxy(batch.mesh)
		var node := _make_node("Batch_" + key, batch, PackedInt32Array(), proxy, draw_distance)
		parent.add_child(node)
		nodes[key] = node
		var twin := _make_twin("BatchShadow_" + key, node, proxy, draw_distance)
		if twin:
			parent.add_child(twin)
		var cells := _cells(batch)
		if debug_record and PropFactory.lod_cells(batch.mesh):
			debug_batches.append({"node": node, "xforms": xforms.duplicate(), "mesh": batch.mesh, "cells": cells})
		if cells.size() < 2:
			continue
		# Hierarchical LOD: the whole batch hides once the camera is within cell_range of it,
		# and the cells show only while it is hidden that way (visibility_parent), so exactly
		# one of the two sets is ever drawn and they switch on the same test.
		for gi: GeometryInstance3D in ([node, twin] if twin else [node]):
			gi.visibility_range_begin = cell_range
			gi.visibility_range_begin_margin = CELL_RANGE_MARGIN
		var cell_nodes: Array[MultiMeshInstance3D] = []
		var cell_of := PackedInt32Array()
		var local_of := PackedInt32Array()
		cell_of.resize(xforms.size())
		local_of.resize(xforms.size())
		for c in cells.size():
			var idx: PackedInt32Array = cells[c]
			for k in idx.size():
				cell_of[idx[k]] = c
				local_of[idx[k]] = k
			var cell := _make_node("BatchCell_%s_%d" % [key, c], batch, idx, proxy, draw_distance)
			parent.add_child(cell)
			if cell_lod_scale:
				cell.lod_bias = _max_scale(xforms, idx)
			cell.visibility_parent = NodePath("../" + String(node.name))
			var cell_twin := _make_twin("BatchCellShadow_%s_%d" % [key, c], cell, proxy, draw_distance)
			if cell_twin:
				parent.add_child(cell_twin)
				cell_twin.visibility_parent = NodePath("../" + String(node.name))
			cell_nodes.append(cell)
		node.set_meta("cells", cell_nodes)
		node.set_meta("cell_of", cell_of)
		node.set_meta("local_of", local_of)
	_batches.clear()
	return nodes


## One node drawing `batch`'s instances `idx` (all of them when empty).
static func _make_node(node_name: String, batch: Dictionary, idx: PackedInt32Array, proxy: Mesh, draw_distance: float) -> MultiMeshInstance3D:
	var xforms: Array = batch.xforms
	var count := idx.size() if not idx.is_empty() else xforms.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = batch.mesh
	mm.instance_count = count
	for i in count:
		var j: int = idx[i] if not idx.is_empty() else i
		mm.set_instance_transform(i, xforms[j])
		mm.set_instance_color(i, batch.colors[j])
		mm.set_instance_custom_data(i, batch.custom[j])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	# Foliage casts its shadow from a lighter twin (PropFactory.shadow_proxy()): same
	# instances, same materials, a quarter of the triangles, drawn into the shadow maps only.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if batch.no_shadow or proxy else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_set_draw_distance(node, draw_distance)
	return node


## `node`'s shadow twin (the same instance buffer, the proxy mesh, shadows only), or null.
static func _make_twin(node_name: String, node: MultiMeshInstance3D, proxy: Mesh, draw_distance: float) -> MultiMeshInstance3D:
	if proxy == null:
		return null
	var mm := node.multimesh
	var twin_mm := MultiMesh.new()
	twin_mm.transform_format = MultiMesh.TRANSFORM_3D
	twin_mm.use_colors = true
	twin_mm.use_custom_data = true
	twin_mm.mesh = proxy
	twin_mm.instance_count = mm.instance_count
	twin_mm.buffer = mm.buffer
	var twin := MultiMeshInstance3D.new()
	twin.name = node_name
	twin.multimesh = twin_mm
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# The tree itself already feeds the global illumination; this is only its shadow.
	twin.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	twin.lod_bias = node.lod_bias
	_set_draw_distance(twin, draw_distance)
	node.set_meta("shadow_twin", twin)
	return twin


## The cells `batch` is split into (index lists), or [] to keep it whole: a k-d split of the
## instance origins, halving the longer side at the median until a cell is under cell_size, too
## few to split, or there are cell_max cells. Deterministic (the instances' own order breaks ties).
static func _cells(batch: Dictionary) -> Array:
	var xforms: Array = batch.xforms
	if not cell_split or xforms.size() < cell_min_instances * 2 or not PropFactory.lod_cells(batch.mesh):
		return []
	if xforms.size() * PropFactory.mesh_triangles(batch.mesh) < cell_min_tris:
		return []
	var all := PackedInt32Array()
	for i in xforms.size():
		all.append(i)
	var todo: Array = [all]
	var out: Array = []
	while not todo.is_empty():
		# Breadth first, so the cap below leaves cells of even size.
		var g: PackedInt32Array = todo.pop_front()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for i in g:
			var o: Vector3 = (xforms[i] as Transform3D).origin
			lo = lo.min(Vector2(o.x, o.z))
			hi = hi.max(Vector2(o.x, o.z))
		var ext := hi - lo
		if maxf(ext.x, ext.y) <= cell_size or g.size() < cell_min_instances * 2 \
				or out.size() + todo.size() + 2 > cell_max:
			out.append(g)
			continue
		var axis := 0 if ext.x >= ext.y else 2
		var order := Array(g)
		order.sort_custom(func(a: int, b: int) -> bool:
			var pa: float = (xforms[a] as Transform3D).origin[axis]
			var pb: float = (xforms[b] as Transform3D).origin[axis]
			return pa < pb or (pa == pb and a < b))
		var half := order.size() / 2
		todo.append(PackedInt32Array(order.slice(0, half)))
		todo.append(PackedInt32Array(order.slice(half)))
	return out


static func _max_scale(xforms: Array, idx: PackedInt32Array) -> float:
	var s := 1.0
	for i in idx:
		var b: Basis = (xforms[i] as Transform3D).basis
		s = maxf(s, maxf(b.x.length(), maxf(b.y.length(), b.z.length())))
	return s


static func _set_draw_distance(node: GeometryInstance3D, draw_distance: float) -> void:
	if draw_distance > 0.0:
		node.visibility_range_end = draw_distance
		node.visibility_range_end_margin = draw_distance * 0.12
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Hides one instance of a built batch (collapses it to nothing far below the world), and its
## shadow twin's copy with it, or a felled tree would leave its shadow standing. A split batch
## hides it in the cell that draws it near the camera as well.
static func hide_instance(node: MultiMeshInstance3D, index: int) -> void:
	if node and index >= 0 and index < node.multimesh.instance_count:
		_hide_one(node, index)
		if node.has_meta("cells"):
			var cells: Array = node.get_meta("cells")
			var cell := cells[(node.get_meta("cell_of") as PackedInt32Array)[index]] as MultiMeshInstance3D
			if is_instance_valid(cell):
				_hide_one(cell, (node.get_meta("local_of") as PackedInt32Array)[index])


static func _hide_one(node: MultiMeshInstance3D, index: int) -> void:
	var gone := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -10000.0, 0.0))
	node.multimesh.set_instance_transform(index, gone)
	# has_meta first: get_meta(key, null) is an error when the key is missing (CLAUDE.md), and
	# batches that cast no shadow (lamps' light pools, lettering) have no twin.
	var twin := node.get_meta("shadow_twin") as MultiMeshInstance3D if node.has_meta("shadow_twin") else null
	if twin and is_instance_valid(twin) and index < twin.multimesh.instance_count:
		twin.multimesh.set_instance_transform(index, gone)


## Off: merge_meshes() leaves every node as it was (the "before" side of a frame-cost A/B,
## still_shot.gd MERGE_STATIC=0).
static var merge_enabled: bool = true


## Merges the plain, static primitive meshes under `root` - boxes, cylinders, spheres placed one
## node each - into ONE mesh per material and render setting, so what was a draw call per box
## (and one more per box in the depth pre-pass and in each shadow cascade it falls in) is one per
## material. The far landmarks are built this way: across the basin they were 802 nodes (337 after
## this), and on the hills bookmark 569 of the frame's 1,202 draw calls for 9k triangles. Exact by
## construction, and conservative about what it touches: only auto-named MeshInstance3Ds (a
## named one may be looked up later) with no script, children, groups or metadata, visible, under
## plain Node3D parents, a PrimitiveMesh (no LODs to lose), no visibility range, custom bounds,
## overlay or mirroring transform, and an opaque BaseMaterial3D that does not map anything in
## the object's own space (object-space triplanar, billboards, distance fade). Shader materials
## are left alone: they can read MODEL_MATRIX. Returns how many nodes it replaced.
static func merge_meshes(root: Node3D) -> int:
	if not merge_enabled:
		return 0
	var groups := {}
	var done: Array[MeshInstance3D] = []
	for n in root.find_children("@*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf: Variant = _merge_xform(mi, root)
		if xf == null:
			continue
		var parts := []
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if not _merge_material_ok(mat):
				parts.clear()
				break
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_INDEX] == null:
				parts.clear()
				break
			parts.append([mat, arrays])
		if parts.is_empty():
			continue
		for p: Array in parts:
			var arrays: Array = p[1]
			var sig := ""
			for a in Mesh.ARRAY_MAX:
				sig += "1" if arrays[a] != null else "0"
			var key := "%d|%s|%d|%d|%d|%.3f|%.3f|%s" % [p[0].get_instance_id(), sig, mi.cast_shadow, mi.gi_mode,
				mi.layers, mi.extra_cull_margin, mi.lod_bias, mi.ignore_occlusion_culling]
			if not groups.has(key):
				groups[key] = {"mat": p[0], "proto": mi, "arrays": []}
			(groups[key].arrays as Array).append([xf, arrays])
		done.append(mi)
	var i := 0
	for key: String in groups:
		var g: Dictionary = groups[key]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _merge_arrays(g.arrays))
		mesh.surface_set_material(0, g.mat)
		var proto: MeshInstance3D = g.proto
		var out := MeshInstance3D.new()
		out.name = "Merged%d" % i
		out.mesh = mesh
		out.cast_shadow = proto.cast_shadow
		out.gi_mode = proto.gi_mode
		out.layers = proto.layers
		out.extra_cull_margin = proto.extra_cull_margin
		out.lod_bias = proto.lod_bias
		out.ignore_occlusion_culling = proto.ignore_occlusion_culling
		root.add_child(out)
		i += 1
	for mi in done:
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	return done.size()


## `mi`'s transform relative to `root`, or null when it must not be merged.
static func _merge_xform(mi: MeshInstance3D, root: Node3D) -> Variant:
	if not (mi.mesh is PrimitiveMesh) or mi.get_script() != null or mi.get_child_count() > 0 \
			or not mi.visible or not mi.get_groups().is_empty() or not mi.get_meta_list().is_empty() \
			or mi.skin != null or mi.material_overlay != null or mi.custom_aabb.has_volume() \
			or mi.visibility_range_begin > 0.0 or mi.visibility_range_end > 0.0 or mi.transparency > 0.0:
		return null
	var xf := mi.transform
	var p := mi.get_parent()
	while p != root:
		if not (p is Node3D) or p.get_script() != null or not (p as Node3D).visible or p is CollisionObject3D:
			return null
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	if xf.basis.determinant() <= 0.0:
		return null
	return xf


static func _merge_material_ok(mat: BaseMaterial3D) -> bool:
	return mat != null and mat.next_pass == null \
		and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
		and mat.blend_mode == BaseMaterial3D.BLEND_MODE_MIX \
		and mat.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED \
		and mat.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED \
		and not mat.fixed_size and not mat.use_point_size \
		and (not mat.uv1_triplanar or mat.uv1_world_triplanar) \
		and (not mat.uv2_triplanar or mat.uv2_world_triplanar)


## One surface from [transform, arrays] pairs of the same format: vertices, normals and tangents
## moved into the root's space (normals by the inverse transpose, so a stretched box shades as
## before), everything else copied, indices offset.
static func _merge_arrays(parts: Array) -> Array:
	var first: Array = parts[0][1]
	# Each output array is its own local while it grows (copy-on-write: one still referenced
	# from a list would be copied whole on every append), built as an empty copy of the
	# input's type.
	var acc := {}
	for a in Mesh.ARRAY_MAX:
		if first[a] != null:
			var empty = first[a].duplicate()
			empty.clear()
			acc[a] = empty
	for part: Array in parts:
		var xf: Transform3D = part[0]
		var arrays: Array = part[1]
		var nb := xf.basis.inverse().transposed()
		var base: int = (acc[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for a: int in acc.keys():
			var dst = acc[a]
			acc[a] = null
			match a:
				Mesh.ARRAY_VERTEX:
					for v: Vector3 in arrays[a]:
						dst.append(xf * v)
				Mesh.ARRAY_NORMAL:
					for nv: Vector3 in arrays[a]:
						dst.append((nb * nv).normalized())
				Mesh.ARRAY_TANGENT:
					var t: PackedFloat32Array = arrays[a]
					for k in range(0, t.size(), 4):
						var tv := (xf.basis * Vector3(t[k], t[k + 1], t[k + 2])).normalized()
						dst.append(tv.x)
						dst.append(tv.y)
						dst.append(tv.z)
						dst.append(t[k + 3])
				Mesh.ARRAY_INDEX:
					for k: int in arrays[a]:
						dst.append(base + k)
				_:
					dst.append_array(arrays[a])
			acc[a] = dst
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a: int in acc:
		out[a] = acc[a]
	return out
