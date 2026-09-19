class_name MultiMeshBatch
extends RefCounted
## Collects transforms per mesh and emits one MultiMeshInstance3D per mesh.
## Used for the thousands of small repeated things in a city: lamps, trees, dashes, stripes.

var _batches: Dictionary = {}


func add(key: String, mesh: Mesh, xform: Transform3D, color: Color = Color.WHITE) -> void:
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "xforms": [], "colors": []}
	var batch: Dictionary = _batches[key]
	batch.xforms.append(xform)
	batch.colors.append(color)


func build(parent: Node3D) -> void:
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
	_batches.clear()
