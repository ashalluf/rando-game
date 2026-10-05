class_name MountainOccluder
extends Node3D
## The mountains past the streamed chunks as an occluder, so a range hides the far city behind it
## (Skyline's tiles of the valley from the basin, the basin's from the valley, far landmarks).
## Past the chunks the ground IS the horizon plane (CityStreamer's Ground on
## macro_ground.gdshader), so the sheet is laid under THAT surface, never over it:
##   * the plane's height at a point is a cubic B-spline of the bake (MacroMap.bake_height), which
##     is never under the lowest of the 4 x 4 texels it weighs, plus zero-mean crags of at most
##     half of `flats_amplitude + relief_amplitude` (23 m), less a sink of 5 m once it is
##     SINK_CLEAR from the camera (macro_relief.gdshaderinc), and it is linear between its own
##     vertices, 44 m apart;
##   * so each cell of this sheet takes the lowest texel within WINDOW texels of it (its own
##     texels, a plane vertex either way, the spline's reach), each vertex the lowest of its cells,
##     less DROP (crags, sink and a margin).
## Only cells between INNER and REACH metres of the camera, rebuilt every REBUILD_STEP metres it
## travels: inside INNER the streamed chunks draw the ground and the plane sinks under them (the
## chunks' own terrain occluders, Occluders._terrain(), cover that). Flat cells are left out:
## they hide only what is buried. Disabled while the camera is below the plane where it stands (a
## deep canyon the bake averages over), where a sheet under the plane is not under the picture.
## OCCLUDERS=0 builds none of it.

## Bake texels a cell spans, and how many texels round it its height is the lowest of.
const CELL_TEXELS := 4
const WINDOW := 5
## Metres under the lowest texel: the crags' half amplitude (23), the far sink (5), a margin.
const DROP := 40.0
## A cell whose window spans fewer metres than this is flat ground (the valley floor, the basin).
const MIN_RELIEF := 60.0
## Metres from the camera the sheet starts and ends (the plane is 14 km across), and how far the
## camera may go before it is rebuilt round it again.
const INNER := 1500.0
const REACH := 6500.0
const REBUILD_STEP := 250.0
## How far from the camera the plane has stopped sinking (macro_relief's far_ground_sink).
const SINK_CLEAR := 1150.0

var _span: float = 16000.0
var _res: int = 0
var _cells: int = 0
## Per cell: the lowest texel of its window (metres) and whether it has relief. Vertex heights.
var _vh := PackedFloat32Array()
## The bake's heights (metres), row by row.
var _hgt := PackedFloat32Array()
var _keep := PackedByteArray()
var _built_at := Vector2(INF, INF)
var _below := false
var _check := 0.0
var _node: OccluderInstance3D
## Triangles in the current sheet (the checks read it).
var triangles: int = 0


## Built under the streamer, which shifts it with every origin re-centre like any other child.
static func attach(streamer: Node3D, macro: MacroMap, span: float) -> MountainOccluder:
	if not Occluders.enabled or OS.has_feature("web") or macro == null or macro.bake_height == null:
		return null
	var m := MountainOccluder.new()
	m.name = "MountainOccluder"
	m._setup(macro.bake_height, span)
	m.position = WorldState.to_local(Vector3.ZERO)
	streamer.add_child(m)
	return m


func _setup(img: Image, span: float) -> void:
	_span = span
	_res = img.get_width()
	_cells = _res / CELL_TEXELS
	_hgt.resize(_res * _res)

	for y in _res:
		for x in _res:
			_hgt[y * _res + x] = img.get_pixel(x, y).r * MacroMap.BAKE_HEIGHT_SCALE
	# Separable min and max over each cell's window: rows, then columns.
	var lo_r := PackedFloat32Array()
	var hi_r := PackedFloat32Array()
	lo_r.resize(_res * _cells)
	hi_r.resize(_res * _cells)
	for y in _res:
		for c in _cells:
			var x0 := maxi(0, c * CELL_TEXELS - WINDOW)
			var x1 := mini(_res - 1, (c + 1) * CELL_TEXELS - 1 + WINDOW)
			var a := INF
			var b := -INF
			for x in range(x0, x1 + 1):
				var h := _hgt[y * _res + x]
				a = minf(a, h)
				b = maxf(b, h)
			lo_r[y * _cells + c] = a
			hi_r[y * _cells + c] = b
	var lo := PackedFloat32Array()
	lo.resize(_cells * _cells)
	_keep.resize(_cells * _cells)
	for cy in _cells:
		var y0 := maxi(0, cy * CELL_TEXELS - WINDOW)
		var y1 := mini(_res - 1, (cy + 1) * CELL_TEXELS - 1 + WINDOW)
		for cx in _cells:
			var a := INF
			var b := -INF
			for y in range(y0, y1 + 1):
				a = minf(a, lo_r[y * _cells + cx])
				b = maxf(b, hi_r[y * _cells + cx])
			lo[cy * _cells + cx] = a
			# Water in the window (0) or flat ground: no sheet here.
			_keep[cy * _cells + cx] = 1 if a > 0.0 and b - a >= MIN_RELIEF else 0
	_vh.resize((_cells + 1) * (_cells + 1))
	for vy in _cells + 1:
		for vx in _cells + 1:
			var h := INF
			for cy in [vy - 1, vy]:
				for cx in [vx - 1, vx]:
					if cy >= 0 and cy < _cells and cx >= 0 and cx < _cells:
						h = minf(h, lo[cy * _cells + cx])
			_vh[vy * (_cells + 1) + vx] = h - DROP


## The sheet's height at a vertex (world XZ of vertex vx, vy) - for the checks.
func vertex_world(vx: int, vy: int) -> Vector3:
	var step := _span / float(_cells)
	return Vector3(-_span * 0.5 + vx * step, _vh[vy * (_cells + 1) + vx], -_span * 0.5 + vy * step)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var w := WorldState.to_world(cam.global_position)
	var at := Vector2(w.x, w.z)
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		var below := w.y < _plane_ceiling(at)
		if below != _below:
			_below = below
			if _node:
				_node.visible = not _below
	if at.distance_to(_built_at) > REBUILD_STEP:
		rebuild(at)


## The highest the plane can stand where the camera is: the most of the texels the spline there
## weighs, plus the crags' half amplitude (ignoring the sink, which only lowers it).
func _plane_ceiling(at: Vector2) -> float:
	var step := _span / float(_res)
	var tx := int(floor((at.x + _span * 0.5) / step))
	var ty := int(floor((at.y + _span * 0.5) / step))
	var h := 0.0
	for y in range(ty - 3, ty + 4):
		for x in range(tx - 3, tx + 4):
			h = maxf(h, _hgt[clampi(y, 0, _res - 1) * _res + clampi(x, 0, _res - 1)])
	return h + 23.0


## The sheet's cells between INNER and REACH of `at` (true world XZ).
func rebuild(at: Vector2) -> void:
	_built_at = at
	var step := _span / float(_cells)
	var origin := -_span * 0.5
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var c0 := Vector2i(clampi(int((at.x - REACH - origin) / step), 0, _cells - 1), clampi(int((at.y - REACH - origin) / step), 0, _cells - 1))
	var c1 := Vector2i(clampi(int((at.x + REACH - origin) / step), 0, _cells - 1), clampi(int((at.y + REACH - origin) / step), 0, _cells - 1))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			if _keep[cy * _cells + cx] == 0:
				continue
			var r := Rect2(origin + cx * step, origin + cy * step, step, step)
			var near := Vector2(clampf(at.x, r.position.x, r.end.x), clampf(at.y, r.position.y, r.end.y))
			var far := maxf(absf(at.x - r.get_center().x), absf(at.y - r.get_center().y)) + step * 0.5
			if near.distance_to(at) < INNER or far > REACH:
				continue
			var o := verts.size()
			for v: Vector2i in [Vector2i(cx, cy), Vector2i(cx + 1, cy), Vector2i(cx + 1, cy + 1), Vector2i(cx, cy + 1)]:
				verts.append(Vector3(origin + v.x * step, _vh[v.y * (_cells + 1) + v.x], origin + v.y * step))
			idx.append_array(PackedInt32Array([o, o + 1, o + 2, o, o + 2, o + 3]))
	triangles = idx.size() / 3
	if idx.is_empty():
		if _node:
			_node.queue_free()
			_node = null
		return
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, idx)
	if _node == null:
		_node = OccluderInstance3D.new()
		_node.name = "Sheet"
		add_child(_node)
		_node.visible = not _below
	_node.occluder = occ
