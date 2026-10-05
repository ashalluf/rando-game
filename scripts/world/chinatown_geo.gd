class_name ChinatownGeo
extends LandmarkGeo
## LandmarkGeo for Chinatown (ChinatownKit): the same packed-array surfaces and the same
## winding rule, plus two things the district needs:
## - `xf`: every triangle is placed through it (positions, normals and the facing hint), so a
##   builder works in its own building's frame and a whole block of buildings goes into ONE mesh;
## - UV2 per vertex (`uv2`, set before adding): the lanterns' sway in chinatown.gdshader (x metres
##   below the point the lantern hangs from, y its phase). Everything else leaves it at zero.

var xf := Transform3D.IDENTITY
var uv2 := Vector2.ZERO


func use(key: String, mat: Material) -> void:
	if _surfaces.has(key):
		return
	super.use(key, mat)
	_surfaces[key]["uv2"] = PackedVector2Array()


func tri(key: String, a: Vector3, b: Vector3, c: Vector3, want: Vector3, ua: Vector2, ub: Vector2, uc: Vector2,
		col: Color = Color.WHITE, collide: bool = false, na: Vector3 = Vector3.ZERO, nb: Vector3 = Vector3.ZERO, nc: Vector3 = Vector3.ZERO) -> void:
	var s: Dictionary = _surfaces[key]
	var bs := xf.basis
	a = xf * a
	b = xf * b
	c = xf * c
	want = bs * want
	if na != Vector3.ZERO:
		na = (bs * na).normalized()
		nb = (bs * nb).normalized()
		nc = (bs * nc).normalized()
	var flat := (c - a).cross(b - a)
	if flat.length_squared() < 1e-12:
		return
	if flat.dot(want) < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
		var tn := nb
		nb = nc
		nc = tn
		flat = -flat
	var fn := flat.normalized()
	if na == Vector3.ZERO:
		na = fn
		nb = fn
		nc = fn
	# Through typed locals, as LandmarkGeo does: they share the dictionary's arrays.
	var vs: PackedVector3Array = s.v
	vs.append(a)
	vs.append(b)
	vs.append(c)
	var ns: PackedVector3Array = s.nrm
	ns.append(na)
	ns.append(nb)
	ns.append(nc)
	var us: PackedVector2Array = s.uv
	us.append(ua)
	us.append(ub)
	us.append(uc)
	var cs: PackedColorArray = s.col
	cs.append(col)
	cs.append(col)
	cs.append(col)
	var u2: PackedVector2Array = s.uv2
	u2.append(uv2)
	u2.append(uv2)
	u2.append(uv2)
	s.n += 1
	triangles += 1
	if collide:
		collision.append_array(PackedVector3Array([a, b, c]))


## Commits every surface into one MeshInstance3D under `parent`, UV2 carried; tangents from the
## UVs for the shader's NORMAL_MAP (tiles, rafters, fruit).
func commit(parent: Node3D, node_name: String, shadow: bool = true, draw_distance: float = 0.0) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for key in _order:
		var s: Dictionary = _surfaces[key]
		if int(s.n) == 0:
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.v
		arrays[Mesh.ARRAY_NORMAL] = s.nrm
		arrays[Mesh.ARRAY_TEX_UV] = s.uv
		arrays[Mesh.ARRAY_TEX_UV2] = s.uv2
		arrays[Mesh.ARRAY_COLOR] = s.col
		var st := SurfaceTool.new()
		st.create_from_arrays(arrays)
		st.index()
		st.generate_tangents()
		var before := mesh.get_surface_count()
		st.commit(mesh)
		if mesh.get_surface_count() > before:
			mesh.surface_set_material(before, s.mat)
	_surfaces.clear()
	_order.clear()
	committed_triangles += triangles
	committed_surfaces += mesh.get_surface_count()
	triangles = 0
	if mesh.get_surface_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if draw_distance > 0.0:
		mi.visibility_range_end = draw_distance
		mi.visibility_range_end_margin = draw_distance * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	return mi
