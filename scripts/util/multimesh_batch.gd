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


func set_no_shadow(key: String) -> void:
	if _batches.has(key):
		_batches[key].no_shadow = true


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
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if batch.no_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(node)
		nodes[key] = node
	_batches.clear()
	return nodes


## Hides one instance of a built batch (collapses it to nothing far below the world).
static func hide_instance(node: MultiMeshInstance3D, index: int) -> void:
	if node and index >= 0 and index < node.multimesh.instance_count:
		node.multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -10000.0, 0.0)))
