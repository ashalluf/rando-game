class_name CarCloseup
extends RefCounted
## A parked everyday car from two metres (wave 6, refcam3 `car_closeup`, docs/HANDOFF.md "The
## parked car at arm's length"). What gave the car away as a game at that range, fixed on the cars
## themselves:
## * the bumper bands: raycast grids a few centimetres proud of the loft (make_road_cars.py
##   wrap_band), and between the grid's rays the curved skin bulged out through them in ragged
##   teeth of body colour along every bumper. `apply()` finds the trim pieces that lie wholly in a
##   bumper zone (the low part of each end of the body: the bands, fog-lamp pockets, the lower
##   grille surrounds - never a lamp bezel, which stands above) and draws a copy of just those,
##   pushed out PUSH along their normals, in front of the original within NEAR metres;
## * the grime (car_paint.gdshaderinc `grime_look`) and the tyres (PropFactory's wheel shader,
##   `squash`): set from here, behind the same switch.
##
## CAR_CLOSEUP=0 is the A/B (the cars exactly as they were).

static var enabled: bool = OS.get_environment("CAR_CLOSEUP") != "0"

## A trim piece is a bumper piece when its top is under this share of the body's height ...
const ZONE_TOP := 0.45
## ... and it lies within this share of the length from one end.
const ZONE_END := 0.25
## How far the copy stands out, metres (the bulges measured on the crossover's nose band were
## under a centimetre; the bands themselves stand 3-5 cm proud).
const PUSH := 0.012
## The copy is drawn this near (the teeth were a few pixels from further off).
const NEAR := 18.0

## Meta on a near body mesh resource: its pushed band copy (an ArrayMesh, or null when the body
## has none). On the mesh, so it lives and dies with the model: never a cache keyed on an id.
const META := "car_closeup_bands"


## Called at the end of Vehicle._add_body_model() with its near meshes, the mesh-space box of the
## body and which mesh axis is its length.
static func apply(near: Array[MeshInstance3D], box: AABB, along_x: bool) -> void:
	if not enabled or box.size.y <= 0.0:
		return
	for m in near:
		if not is_instance_valid(m) or m.mesh == null or m.mesh.get_surface_count() < 2:
			continue
		var bands: Variant = m.mesh.get_meta(META) if m.mesh.has_meta(META) else _build(m.mesh, box, along_x)
		if bands == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "BumperBands"
		mi.mesh = bands
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.visibility_range_end = NEAR
		m.add_child(mi)


## The pushed copy of a body mesh's bumper trim pieces (null when it has none, or when the
## renderer keeps no mesh data: the headless check).
static func _build(mesh: Mesh, box: AABB, along_x: bool) -> Variant:
	var out: Variant = null
	var st: SurfaceTool = null
	var mat: Material = null
	for si in mesh.get_surface_count():
		var src := mesh.surface_get_material(si)
		if src == null or String(src.resource_name) != "trim":
			continue
		var arr: Array = mesh.surface_get_arrays(si)
		if arr.is_empty():
			continue
		var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ii: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if vv.is_empty() or nn.size() != vv.size():
			continue
		if ii.is_empty():
			ii.resize(vv.size())
			for k in vv.size():
				ii[k] = k
		var keep := pieces(vv, ii, box, along_x)
		if keep.is_empty():
			continue
		if st == null:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			mat = src
		for t in keep:
			for c in 3:
				var k: int = ii[t * 3 + c]
				st.set_normal(nn[k])
				st.add_vertex(vv[k] + nn[k] * PUSH)
	if st != null:
		var am := st.commit()
		am.surface_set_material(0, mat)
		out = am
	mesh.set_meta(META, out)
	return out


## The triangles of the trim pieces (connected by shared positions) that lie wholly in a bumper
## zone. Pure: tests and probes call it with plain arrays.
static func pieces(vv: PackedVector3Array, ii: PackedInt32Array, box: AABB, along_x: bool) -> PackedInt32Array:
	# Union-find over welded positions (the glTF splits vertices at hard edges and seams).
	var id_of := {}
	var weld := PackedInt32Array()
	weld.resize(vv.size())
	for k in vv.size():
		var key := Vector3i((vv[k] * 2000.0).round())
		if not id_of.has(key):
			id_of[key] = id_of.size()
		weld[k] = id_of[key]
	var parent := PackedInt32Array()
	parent.resize(id_of.size())
	for k in parent.size():
		parent[k] = k
	var tris := ii.size() / 3
	for t in tris:
		var a := _root(parent, weld[ii[t * 3]])
		for c in [1, 2]:
			var b := _root(parent, weld[ii[t * 3 + c]])
			if a != b:
				parent[b] = a
	# Each piece's extent in the body's own share-of-the-box terms.
	var top := {}
	var lo := {}
	var hi := {}
	for k in vv.size():
		var r := _root(parent, weld[k])
		var q := (vv[k] - box.position) / box.size
		var al := q.x if along_x else q.z
		top[r] = maxf(float(top.get(r, -1.0)), q.y)
		lo[r] = minf(float(lo.get(r, 2.0)), al)
		hi[r] = maxf(float(hi.get(r, -1.0)), al)
	var out := PackedInt32Array()
	for t in tris:
		var r := _root(parent, weld[ii[t * 3]])
		if float(top[r]) > ZONE_TOP:
			continue
		if float(hi[r]) > ZONE_END and float(lo[r]) < 1.0 - ZONE_END:
			continue
		out.append(t)
	return out


static func _root(parent: PackedInt32Array, k: int) -> int:
	while parent[k] != k:
		parent[k] = parent[parent[k]]
		k = parent[k]
	return k
