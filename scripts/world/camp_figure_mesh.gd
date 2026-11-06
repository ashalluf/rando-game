class_name CampFigureMesh
extends Node3D
## All of a chunk's static camp figures (CampFigure) merged into one mesh - a surface per
## material, so a chunk's figures are a draw per model it uses (Encampment.FIGURE_MODELS) - plus
## a shadows-only twin merged from their far bodies. As MultiMesh batches, one per model and
## pose, a skid-row chunk's eighteen figures were fifteen batches of one or two, and with their
## shadow twins the figures alone were 230 draw calls round skid row. A figure that wakes is
## taken out by rebuilding the mesh without it (hide()): rare, and a few tens of thousands of
## vertices.

## Per figure: [baked mesh, its shadow mesh (or null), transform in this node's space].
var entries: Array = []
var draw_distance: float = 110.0
## Their shadows stop here (m).
var shadow_distance: float = 60.0
var _hidden := {}
var _body: MeshInstance3D
var _shadow: MeshInstance3D


func add(mesh: Mesh, shadow: Mesh, xform: Transform3D) -> int:
	entries.append([mesh, shadow, xform])
	return entries.size() - 1


func _ready() -> void:
	_body = MeshInstance3D.new()
	_body.name = "Figures"
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.visibility_range_end = draw_distance
	add_child(_body)
	_shadow = MeshInstance3D.new()
	_shadow.name = "FigureShadows"
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_shadow.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_shadow.visibility_range_end = minf(draw_distance, shadow_distance)
	add_child(_shadow)
	_rebuild()


## Takes figure `index` out (it woke into a live person).
func hide_figure(index: int) -> void:
	if _hidden.has(index):
		return
	_hidden[index] = true
	if is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	_body.mesh = _merge(0)
	_shadow.mesh = _merge(1)


## The entries' meshes (slot 0 the figures, 1 their shadows) merged by material, through
## SurfaceTool.append_from() (native: it takes positions, normals and tangents through the
## transform itself; a GDScript loop over forty thousand vertices was tens of milliseconds).
func _merge(slot: int) -> ArrayMesh:
	var tools := {}
	var order: Array = []
	for i in entries.size():
		if _hidden.has(i):
			continue
		var mesh: Mesh = entries[i][slot]
		if mesh == null:
			continue
		var xf: Transform3D = entries[i][2]
		for s in mesh.get_surface_count():
			# The shadow twin is one surface whatever it is made of: a shadow has no material.
			var mat: Material = mesh.surface_get_material(s) if slot == 0 else null
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
