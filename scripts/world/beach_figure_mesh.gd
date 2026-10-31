class_name BeachFigureMesh
extends CampFigureMesh
## A beach chunk's static figures (BeachFigure) merged the camps' way (CampFigureMesh), but in
## CELL-metre cells along the shore, each with a near mesh (the middle bodies, ~2,100 triangles a
## person) inside `near_range` and a far one (the far bodies, ~600) past it, and the far bodies'
## shadow: a crowded beach chunk holds ninety people, and as one merged mesh it was drawn at its
## middle bodies whenever the camera was near any of them. Each cell is a draw per material either
## way (the chunk's few crowd rigs, one suit each), switched by Godot's visibility ranges, which
## measure to the cell's middle.

## Metres of shore per cell, and where the near bodies hand over to the far ones.
const CELL := 32.0
var near_range: float = 42.0
var _cells: Dictionary = {}
var _cell_of: Array = []


## Figure `xform` with its near and far bodies (the far one also casts its shadow). Index for
## hide_figure().
func add_figure(near: Mesh, far: Mesh, xform: Transform3D) -> int:
	entries.append([near, far, xform])
	_cell_of.append(floori(xform.origin.z / CELL))
	return entries.size() - 1


func _ready() -> void:
	for i in entries.size():
		var c: int = _cell_of[i]
		if _cells.has(c):
			continue
		var near := MeshInstance3D.new()
		near.name = "Near_%d" % c
		near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		near.visibility_range_end = near_range
		near.visibility_range_end_margin = 2.0
		add_child(near)
		var far := MeshInstance3D.new()
		far.name = "Far_%d" % c
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far.visibility_range_begin = near_range
		far.visibility_range_begin_margin = 2.0
		far.visibility_range_end = draw_distance
		add_child(far)
		var shadow := MeshInstance3D.new()
		shadow.name = "Shadow_%d" % c
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		shadow.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		shadow.visibility_range_end = minf(draw_distance, shadow_distance)
		add_child(shadow)
		_cells[c] = [near, far, shadow]
	for c: int in _cells:
		_rebuild_cell(c)


func hide_figure(index: int) -> void:
	if _hidden.has(index):
		return
	_hidden[index] = true
	if is_inside_tree() and index < _cell_of.size():
		_rebuild_cell(_cell_of[index])


func _rebuild() -> void:
	for c: int in _cells:
		_rebuild_cell(c)


func _rebuild_cell(c: int) -> void:
	var nodes: Array = _cells[c]
	(nodes[0] as MeshInstance3D).mesh = _merge_cell(c, 0, true)
	(nodes[1] as MeshInstance3D).mesh = _merge_cell(c, 1, true)
	(nodes[2] as MeshInstance3D).mesh = _merge_cell(c, 1, false)


## The cell's figures' near (slot 0) or far (slot 1) bodies merged by material; `materials` false
## merges them into one surface with none (a shadow has no material).
func _merge_cell(c: int, slot: int, materials: bool) -> ArrayMesh:
	var tools := {}
	var order: Array = []
	for i in entries.size():
		if _hidden.has(i) or _cell_of[i] != c:
			continue
		var mesh: Mesh = entries[i][slot]
		if mesh == null:
			continue
		var xf: Transform3D = entries[i][2]
		for s in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(s) if materials else null
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
				order.append(mat)
			(tools[mat] as SurfaceTool).append_from(mesh, s, xf)
	if order.is_empty():
		return null
	var out := ArrayMesh.new()
	for mat in order:
		(tools[mat] as SurfaceTool).commit(out)
		if mat:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out
