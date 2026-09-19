class_name MultiMeshBatch
extends RefCounted
## Collects transforms per mesh and emits one MultiMeshInstance3D per mesh.
## Used for the thousands of small repeated things in a city: lamps, trees, dashes, stripes.

var _batches: Dictionary = {}


## Returns the instance index within `key`, so callers can hide that instance later.
func add(key: String, mesh: Mesh, xform: Transform3D, color: Color = Color.WHITE) -> int:
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "xforms": [], "colors": []}
	var batch: Dictionary = _batches[key]
	batch.xforms.append(xform)
	batch.colors.append(color)
	return batch.xforms.size() - 1


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
		mm.mesh = batch.mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, batch.colors[i])
		var node := MultiMeshInstance3D.new()
		node.name = "Batch_" + key
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(node)
		nodes[key] = node
	_batches.clear()
	return nodes


## Hides one instance of a built batch (collapses it to nothing far below the world).
static func hide_instance(node: MultiMeshInstance3D, index: int) -> void:
	if node and index >= 0 and index < node.multimesh.instance_count:
		node.multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -10000.0, 0.0)))
