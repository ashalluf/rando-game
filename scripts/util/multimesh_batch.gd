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


## Builds the MultiMeshInstance3D nodes and returns them keyed by batch key.
func build(parent: Node3D) -> Dictionary:
	var nodes := {}
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var xforms: Array = batch.xforms
		if xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = batch.mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, batch.colors[i])
			mm.set_instance_custom_data(i, batch.custom[i])
		var node := MultiMeshInstance3D.new()
		node.name = "Batch_" + key
		node.multimesh = mm
		# Foliage casts its shadow from a lighter twin (PropFactory.shadow_proxy()): same
		# instances, same materials, a quarter of the triangles, drawn into the shadow maps only.
		var proxy: Mesh = null if batch.no_shadow else PropFactory.shadow_proxy(batch.mesh)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if batch.no_shadow or proxy else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var draw_distance: float = batch.get("draw_distance", 0.0)
		_set_draw_distance(node, draw_distance)
		parent.add_child(node)
		nodes[key] = node
		if proxy:
			var twin_mm := MultiMesh.new()
			twin_mm.transform_format = MultiMesh.TRANSFORM_3D
			twin_mm.use_colors = true
			twin_mm.use_custom_data = true
			twin_mm.mesh = proxy
			twin_mm.instance_count = mm.instance_count
			twin_mm.buffer = mm.buffer
			var twin := MultiMeshInstance3D.new()
			twin.name = "BatchShadow_" + key
			twin.multimesh = twin_mm
			twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			# The tree itself already feeds the global illumination; this is only its shadow.
			twin.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			_set_draw_distance(twin, draw_distance)
			parent.add_child(twin)
			node.set_meta("shadow_twin", twin)
	_batches.clear()
	return nodes


static func _set_draw_distance(node: GeometryInstance3D, draw_distance: float) -> void:
	if draw_distance > 0.0:
		node.visibility_range_end = draw_distance
		node.visibility_range_end_margin = draw_distance * 0.12
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Hides one instance of a built batch (collapses it to nothing far below the world), and its
## shadow twin's copy with it, or a felled tree would leave its shadow standing.
static func hide_instance(node: MultiMeshInstance3D, index: int) -> void:
	if node and index >= 0 and index < node.multimesh.instance_count:
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
