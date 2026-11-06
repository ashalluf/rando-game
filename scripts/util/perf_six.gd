class_name PerfSix
## Perf audit 6 (docs/HANDOFF.md "Perf audit 6"): the cuts found by measuring every refcam after
## wave 7, each behind its own switch. Every cut here changes what the GPU is fed, never what a
## camera sees (each was proved with a DIFF=1 / --strict pair against an A/A run).

## The rooftop air-conditioning units (Building's RoofUnits MultiMeshes: the 4.7k-triangle
## condenser model, 1.7x) cast from a lighter twin: the model's shadow proxy at the shadow LOD
## scale the car bodies use. They used to cast the full model into every cascade - downtown has
## hundreds on the roofs round any camera, and none had a lighter caster. ROOF_UNIT_SHADOW=0 the A/B.
static var roof_units_lite := OS.get_environment("ROOF_UNIT_SHADOW") != "0"
const ROOF_UNIT_SHADOW_BIAS := 0.3


## Called by Building._commit_roof() for each RoofUnits node, already in the tree.
static func roof_units(units: MultiMeshInstance3D, mesh: Mesh, xforms: Array) -> void:
	if not roof_units_lite or xforms.is_empty():
		return
	var proxy: Mesh = PropFactory.shadow_proxy(mesh)
	if proxy == null:
		proxy = mesh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = proxy
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var twin := MultiMeshInstance3D.new()
	twin.name = String(units.name) + "Shadow"
	twin.multimesh = mm
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	twin.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	twin.lod_bias = ROOF_UNIT_SHADOW_BIAS
	units.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	units.add_sibling(twin)


## Every other batch's shadow twin (street props' shadow proxies, and a batch's own mesh cast within
## a shadow reach) picks its LOD at the trees' shadow LOD scale too: a bench, a hydrant or a lamp's
## shadow at a cascade's texels does not need the camera pass's triangles. PROP_SHADOW_LOD=0 the A/B.
static var prop_shadow_lod := OS.get_environment("PROP_SHADOW_LOD") != "0"


static func prop_twin_bias() -> float:
	return FoliageLod.SHADOW_LOD_SCALE if prop_shadow_lod else 1.0


## The far city's canopies (PropFactory.canopy_blob(): 24 triangles, unit ellipsoid, a tree or a
## clump 3-20 m across; FarCity/Planting was 1.3 M of street_noon's 7.1 M triangles) get a second
## level of 12 triangles - a triangular antiprism on the blob's own vertices (alternate vertices of
## the upper and the lower ring, the poles) - which the renderer takes only where the change is
## under a pixel: its departure from the blob is at most CANOPY_LOD_ERROR of the unit, and a tile's
## LOD bias is its biggest canopy's scale (planting_bias), so the edge is in metres for the
## biggest tree in it. CANOPY_LOD=0 the A/B.
static var canopy_lod := OS.get_environment("CANOPY_LOD") != "0"
const CANOPY_LOD_ERROR := 0.22


## `blob` (the 28-vertex, 24-triangle blob without_degenerate() makes) with the coarse level.
static func canopy_with_lod(blob: ArrayMesh) -> ArrayMesh:
	if not canopy_lod or blob.get_surface_count() != 1:
		return blob
	var arrays := blob.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if v.size() != 28:
		return blob
	# Vertices: 1..6 the top pole's copies, 7..12 the upper ring (13 repeats 7), 14..19 the lower
	# ring (20 repeats 14), 21..26 the bottom pole's copies. Upper ring at 0, 120, 240 degrees
	# (7, 9, 11), lower at 60, 180, 300 (15, 17, 19); wound like the blob's own triangles.
	var coarse := PackedInt32Array([
		1, 9, 7, 2, 11, 9, 3, 7, 11,
		7, 9, 15, 9, 17, 15, 9, 11, 17, 11, 19, 17, 11, 7, 19, 7, 15, 19,
		15, 17, 21, 17, 19, 22, 19, 15, 23])
	var mat := blob.surface_get_material(0)
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {CANOPY_LOD_ERROR: coarse})
	if mat:
		out.surface_set_material(0, mat)
	out.set_meta("canopy_lod", true)
	return out


## Skyline's planting node: a batch picks its LOD from the node's scale, never its instances', so
## the canopy's edge (in units of the blob) is made metres for the biggest canopy in the tile.
static func planting_bias(node: GeometryInstance3D, mesh: Mesh, xforms: Array) -> void:
	if not mesh.has_meta("canopy_lod"):
		return
	var biggest := 0.0
	for x: Transform3D in xforms:
		var sc := x.basis.get_scale()
		biggest = maxf(biggest, maxf(sc.x, maxf(sc.y, sc.z)))
	node.lod_bias = maxf(biggest, 0.01)


## The facade kit's casting pieces (awnings, balconies, fire escapes, window ACs, roof vents and
## tanks, blade signs: Building._finish_kit()) cast from a twin of their own mesh, like the
## roofline already did, so their shadow takes the shadow LOD scale (prop_twin_bias) instead of
## the camera's. Same reach as the piece's draw distance: the same casters, lighter.
## KIT_SHADOW_TWIN=0 the A/B.
static var kit_shadow_twin := OS.get_environment("KIT_SHADOW_TWIN") != "0"


## Called by Building._finish_kit() for each kind, before its draw distance is set.
static func kit_shadow(kit: MultiMeshBatch, key: String, draw_distance: float) -> void:
	if not kit_shadow_twin or not prop_shadow_lod:
		return
	var batch: Dictionary = kit._batches.get(key, {})
	if batch.is_empty() or batch.get("no_shadow", false) or float(batch.get("shadow_reach", 0.0)) > 0.0:
		return
	kit.set_shadow_reach(key, draw_distance)


## Experimental (FOLIAGE_CELLS=1, off by default): a foliage batch (a scanned plant's FoliageLod
## ladder, a palm's ladder) is drawn as cells of FOLIAGE_CELL metres, so each picks its own LOD.
## A batch picks ONE level for every instance from its whole box, which for a chunk-wide batch the
## camera stands in is level 0 for every tree in the chunk. The batch's own node keeps every
## instance (everything that reads or hides one by index still does) but draws none
## (visible_instance_count 0); the cells are its children, so they follow its visibility.
static var foliage_cells := OS.get_environment("FOLIAGE_CELLS") == "1"
static var FOLIAGE_CELL: float = float(OS.get_environment("FOLIAGE_CELL")) if OS.get_environment("FOLIAGE_CELL") != "" else 48.0


static func cell_batch(node: MultiMeshInstance3D, twin: MultiMeshInstance3D, mesh: Mesh, xforms: Array, colors: Array, custom: Array) -> void:
	if not foliage_cells or not (mesh.has_meta("foliage_ladder") or mesh.has_meta("palm_ladder")):
		return
	var cells := {}
	var cell_of := PackedInt32Array()
	var local := PackedInt32Array()
	cell_of.resize(xforms.size())
	local.resize(xforms.size())
	for i in xforms.size():
		var o: Vector3 = (xforms[i] as Transform3D).origin
		var k := Vector2i(floori(o.x / FOLIAGE_CELL), floori(o.z / FOLIAGE_CELL))
		if not cells.has(k):
			cells[k] = []
		local[i] = (cells[k] as Array).size()
		(cells[k] as Array).append(i)
	if cells.size() < 2:
		return
	var nodes: Array = []
	var twins: Array = []
	var ci := 0
	for k: Vector2i in cells:
		var idx: Array = cells[k]
		var xs: Array = []
		var cs: Array = []
		var us: Array = []
		for i: int in idx:
			cell_of[i] = ci
			xs.append(xforms[i])
			cs.append(colors[i])
			us.append(custom[i])
		var buf := MultiMeshBatch._instance_buffer(xs, cs, us)
		nodes.append(_cell_node(node, node.multimesh.mesh, buf, xs.size(), "Cell_%d" % ci))
		twins.append(_cell_node(twin, twin.multimesh.mesh, buf, xs.size(), "Cell_%d" % ci) if twin else null)
		ci += 1
	node.multimesh.visible_instance_count = 0
	if twin:
		twin.multimesh.visible_instance_count = 0
	node.set_meta("cells", nodes)
	node.set_meta("cell_twins", twins)
	node.set_meta("cell_of", cell_of)
	node.set_meta("cell_local", local)


static func _cell_node(parent: MultiMeshInstance3D, mesh: Mesh, buf: PackedFloat32Array, count: int, nm: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.buffer = buf
	var c := MultiMeshInstance3D.new()
	c.name = nm
	c.multimesh = mm
	c.cast_shadow = parent.cast_shadow
	c.gi_mode = parent.gi_mode
	c.lod_bias = parent.lod_bias
	c.material_override = parent.material_override
	c.layers = parent.layers
	c.visibility_range_begin = parent.visibility_range_begin
	c.visibility_range_end = parent.visibility_range_end
	c.visibility_range_end_margin = parent.visibility_range_end_margin
	c.visibility_range_fade_mode = parent.visibility_range_fade_mode
	parent.add_child(c)
	return c


## hide_instance()'s copy into the cell that draws the instance.
static func hide_in_cell(node: MultiMeshInstance3D, index: int, gone: Transform3D) -> void:
	if not node.has_meta("cells"):
		return
	var cell_of: PackedInt32Array = node.get_meta("cell_of")
	if index >= cell_of.size():
		return
	var c := cell_of[index]
	var li: int = (node.get_meta("cell_local") as PackedInt32Array)[index]
	for list_key in ["cells", "cell_twins"]:
		var mi = (node.get_meta(list_key) as Array)[c]
		if mi != null and is_instance_valid(mi) and li < (mi as MultiMeshInstance3D).multimesh.instance_count:
			(mi as MultiMeshInstance3D).multimesh.set_instance_transform(li, gone)
