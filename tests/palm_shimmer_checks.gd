extends RefCounted
## Palm crowns without the flecks (PalmShimmer, shaders/foliage.gdshader) for tests/smoke_test.gd.
## Loaded at run time (not named there), so it compiles after the autoloads.
## Checks: the palm shader compiles and keeps the mesh's normal on back faces behind the switch;
## its leaflet widening reads CUSTOM0 and stays out of the shadow pass; every palm level's leaflet
## vertices carry their offset across the blade (zero at the tip, inside the blade's half width)
## and nothing else carries one; the mesh's surface has the CUSTOM0 format; the widening rule
## widens only what is under the pixel floor, never past its cap, and keeps width x coverage; the
## boots' undersides face outward; the material carries the switch.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var t0 := Time.get_ticks_msec()
	_shader()
	_levels()
	_mesh()
	_rule()
	_material()
	print("PALM_SHIMMER_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


static func _text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""


func _shader() -> void:
	var sh: Shader = load("res://shaders/foliage.gdshader")
	_check(sh != null and not sh.get_shader_uniform_list().is_empty(), "palm shimmer: the palm shader compiles")
	var src := _text("res://shaders/foliage.gdshader")
	var frag := src.find("void fragment()")
	var flip := src.find("if (palm_shimmer > 0.5) {", frag)
	_check(frag > 0 and flip > frag and src.find("NORMAL = -NORMAL;", flip) > flip and src.find("!FRONT_FACING", flip) > flip,
		"palm shimmer: a back face keeps the mesh's normal, behind the switch")
	var vtx := src.find("void vertex()")
	var widen := src.find("CUSTOM0.w > 0.5", vtx)
	_check(vtx > 0 and widen > vtx and widen < src.find("vec3 origin", vtx) and src.find("PROJECTION_MATRIX[3][3] < 0.5", vtx) > vtx,
		"palm shimmer: leaflets are widened at rest, before the wind, never in the shadow pass")
	_check(src.contains("#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS") and src.contains("n > leaf_cover"),
		"palm shimmer: coverage is dithered on Forward+ only")


## Every level of a palm: leaflet vertices carry CUSTOM0 (w 1) inside the blade, the rest zero.
func _levels() -> void:
	if not PalmShimmer.enabled:
		return
	var bad := []
	for v in [0, 3]:
		var leaf_counts := []
		for l in PropFactory.PALM_LEVELS.size():
			var arrays: Array = PropFactory._palm_level(v, PropFactory.PALM_LEVELS[l])
			var custom = arrays[Mesh.ARRAY_CUSTOM0]
			if custom == null:
				bad.append("v%d l%d: no CUSTOM0" % [v, l])
				continue
			var cf: PackedFloat32Array = custom
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n := verts.size()
			if cf.size() != n * 4:
				bad.append("v%d l%d: CUSTOM0 size %d for %d vertices" % [v, l, cf.size(), n])
				continue
			var leaf := 0
			var tips := 0
			var worst := 0.0
			for i in n:
				var w := cf[i * 4 + 3]
				var off := Vector3(cf[i * 4], cf[i * 4 + 1], cf[i * 4 + 2])
				if w > 0.5:
					leaf += 1
					worst = maxf(worst, off.length())
					if off.length() < 1e-6:
						tips += 1
				elif off.length() > 1e-6:
					bad.append("v%d l%d: a non-leaflet vertex has an offset" % [v, l])
					break
			if leaf == 0 or tips == 0:
				bad.append("v%d l%d: %d leaflet vertices, %d tips" % [v, l, leaf, tips])
			# A blade spans `stride` leaflets of the rachis (15 at the coarsest level: up to ~3 m
			# along a long frond), so its half width is under a metre a 4-leaflet stride and 2 m at most.
			if worst > (2.0 if int(PropFactory.PALM_LEVELS[l].stride) > 4 else 0.8):
				bad.append("v%d l%d: a leaflet offset of %.2f m" % [v, l, worst])
			leaf_counts.append(leaf)
		# Coarser levels draw fewer leaflet vertices.
		for k in range(1, leaf_counts.size()):
			if leaf_counts[k] > leaf_counts[k - 1]:
				bad.append("v%d: level %d has more leaflet vertices than level %d" % [v, k, k - 1])
	_check(bad.is_empty(), "palm shimmer: every level's leaflets carry their offset across the blade, nothing else does (%s)" % str(bad.slice(0, 4)))


func _mesh() -> void:
	var m := PropFactory.palm(1) as ArrayMesh
	_check(m != null and m.get_surface_count() == 1, "palm shimmer: a palm is one surface")
	if m == null:
		return
	var has := (m.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0) != 0
	_check(has == PalmShimmer.enabled, "palm shimmer: the palm surface carries CUSTOM0 (%s) when the pass is on" % str(has))
	# The boots' undersides: no trunk-side vertex near the boots' rings looks straight down.
	var arrays: Array = PropFactory._palm_level(1, PropFactory.PALM_LEVELS[0])
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var down := 0
	var cf = arrays[Mesh.ARRAY_CUSTOM0]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var top := 0.0
	for p in verts:
		top = maxf(top, p.y)
	for i in nrm.size():
		var leaf := cf != null and (cf as PackedFloat32Array)[i * 4 + 3] > 0.5
		# The boots stand between 0.58 and 0.96 of the trunk; leaflets and coconuts are higher / rounder.
		if not leaf and nrm[i].y < -0.6 and Vector2(nrm[i].x, nrm[i].z).length() < 0.62 and verts[i].y < top * 0.7:
			down += 1
	_check(not PalmShimmer.enabled or down == 0, "palm shimmer: the boots' undersides face outward, not into the trunk (%d facing down)" % down)


func _rule() -> void:
	var ok := true
	for px: float in [0.01, 0.2, 0.5, 1.0, PalmShimmer.MIN_PX, 2.0, 8.0]:
		var r := PalmShimmer.widen(px)
		if r.x < 1.0 or r.x > PalmShimmer.MAX_WIDEN + 1e-4 or absf(r.x * r.y - 1.0) > 1e-4:
			ok = false
		if px >= PalmShimmer.MIN_PX and r.x != 1.0:
			ok = false
		if px < PalmShimmer.MIN_PX and r.x < PalmShimmer.MAX_WIDEN - 1e-4 and absf(px * r.x - PalmShimmer.MIN_PX) > 1e-4:
			ok = false
	_check(ok, "palm shimmer: only what is under the pixel floor is widened, to the floor or the cap, width x coverage kept")
	var src := _text("res://shaders/foliage.gdshader")
	_check(src.contains("clamp(leaf_min_px / max(width_px, 1e-5), 1.0, leaf_max_widen)") and src.contains("leaf_cover = 1.0 / k;"),
		"palm shimmer: the shader's rule is PalmShimmer.widen()")


func _material() -> void:
	var mat := PropFactory.foliage_material()
	_check(mat != null and float(mat.get_shader_parameter("palm_shimmer")) == (1.0 if PalmShimmer.enabled else 0.0)
		and is_equal_approx(float(mat.get_shader_parameter("leaf_min_px")), PalmShimmer.MIN_PX)
		and is_equal_approx(float(mat.get_shader_parameter("leaf_specular")), PalmShimmer.LEAF_SPECULAR if PalmShimmer.enabled else 0.34),
		"palm shimmer: the palm material carries the switch and the pixel floor")
