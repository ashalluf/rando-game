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
