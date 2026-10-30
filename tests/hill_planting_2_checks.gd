extends RefCounted
## The hills' planted volume (hill-planting-2, docs/HANDOFF.md "The hills' planted volume"):
## checks for tests/smoke_test.gd. Builds its own chunks round a fixed front-range point (never
## leaning on where the player was left) and frees them:
##   * the scatter clump is a few triangles on three LOD levels, every face wound outward;
##   * a FULL hill chunk plants hundreds of clumps, all on the painted stand (none on rock, cuts or
##     roads), as one shadowless batch with a draw distance, on the fading material;
##   * a LOD hill chunk (which planted nothing before) plants its own, bigger, coarser clumps;
##   * the hills' own planting (_plant_hills) is exactly where it was with HILL_PLANTING_2=0, and
##     the oak clumps only ADD oaks;
##   * the instance budget: clumps x triangles stays inside what the frame was given.

var _t: Node
const AT := Vector2(0.0, -1400.0)


func run(t: Node, city: Node3D) -> void:
	_t = t
	if not HillScatter.enabled:
		_t._check(true, "hill-planting-2: off (HILL_PLANTING_2=0)")
		return
	var plan: CityPlan = city.get("plan") if city else null
	if plan == null or plan.macro == null or not city.has_method("_new_chunk"):
		_t._check(false, "hill-planting-2: no city plan to build hill chunks from")
		return
	_mesh()
	var k: Vector2i = plan.block_index_at(AT)
	_full(city, plan, k)
	_lod(city, k)


func _build(city: Node3D, k: Vector2i, level: int) -> CityChunk:
	var chunk: CityChunk = city._new_chunk(k, level)
	chunk.build()
	return chunk


func _free(chunk: CityChunk) -> void:
	if chunk.get_parent():
		chunk.get_parent().remove_child(chunk)
	chunk.free()


func _mesh() -> void:
	var m := HillScatter.mesh()
	var arrays := m.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tris := idx.size() / 3
	var inward := 0
	for i in tris:
		var a := v[idx[i * 3]]
		var b := v[idx[i * 3 + 1]]
		var c := v[idx[i * 3 + 2]]
		# Faces point away from a point under the clump's middle (front faces are clockwise).
		var mid := (a + b + c) / 3.0
		if (c - a).cross(b - a).dot(mid - Vector3(0.0, -1.0, 0.0)) <= 0.0:
			inward += 1
	var box := m.get_aabb()
	_t._check(tris <= 80 and inward == 0 and m.has_meta("foliage_ladder") and HillScatter.EDGES.size() == 2 \
			and box.size.x > box.size.y * 1.3 and box.position.y < 0.0,
		"hill-planting-2: the scatter clump is %d triangles on 3 levels, a low wide mound (%.1f x %.1f m), every face outward (%d inward)" % [tris, box.size.x, box.size.y, inward])
	var full := HillScatter.mesh_for("full")
	var lod := HillScatter.mesh_for("lod")
	var src := FileAccess.get_file_as_string("res://shaders/hill_scatter.gdshader")
	_t._check(full.surface_get_material(0) != lod.surface_get_material(0) and (full.surface_get_material(0) as ShaderMaterial).get_shader_parameter("near_fade") == HillScatter.FULL_FADE \
			and src.contains("color_space.gdshaderinc") and src.contains("cs_out("),
		"hill-planting-2: FULL clumps fade in past %s m, LOD clumps do not; the shader works in linear on both renderers" % HillScatter.FULL_FADE)


func _full(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	var chunk := _build(city, k, CityChunk.Level.FULL)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var done: Dictionary = chunk.get_meta("hill_scatter_done", {})
	var node: MultiMeshInstance3D = chunk.get_node_or_null("Batch_hill_scatter_full")
	var count := int(done.get("count", 0))
	var shaded := node != null and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and not chunk.has_node("BatchShadow_hill_scatter_full") \
			and absf(node.visibility_range_end - HillScatter.FULL_DRAW) < 0.5
	_t._check(chunk.zone == MacroMap.Zone.HILLS and count >= 150 and node != null and node.multimesh.instance_count == count and shaded,
		"hill-planting-2: a FULL hill chunk plants %d scatter clumps of %d points, one shadowless batch drawn to %.0f m (chunk build %.0f ms, the scatter %.0f ms in %d steps)" % [count, int(done.get("tried", 0)), HillScatter.FULL_DRAW, ms, int(done.get("usec", 0)) / 1000.0, int(done.get("steps", 0))])
	# On the stand the terrain paints, off the tile's own grid (as _check_hill_planting does).
	var off := 0
	var rock := 0
	var road := 0
	var segs: Array[Dictionary] = chunk._hill_segments()
	for p: Vector2 in done.get("points", []):
		var th := func(q: Vector2) -> float: return chunk._terrain_height(q)
		var grad := Vector2(th.call(p + Vector2(2.0, 0.0)) - th.call(p - Vector2(2.0, 0.0)),
			th.call(p + Vector2(0.0, 2.0)) - th.call(p - Vector2(0.0, 2.0))) * 0.25
		var g := HillPlanting.ground(p, grad, true, chunk._terrain_height(p, "drains"), chunk._terrain_rill(p))
		if float(g.brush) < HillScatter.BRUSH_MIN - 0.05:
			off += 1
		if float(g.rocky) > 0.3 or float(g.bare) > 0.4:
			rock += 1
		if chunk._near_hill_road(p, segs, 3.0):
			road += 1
	_t._check(off == 0 and rock == 0 and road == 0, "hill-planting-2: every clump stands on the painted brush (%d off the stand, %d on rock or cuts, %d on a road)" % [off, rock, road])
	var planted: Dictionary = chunk.hill_planting
	var on := {}
	for e: Array in planted.get("points", []):
		on[str(e)] = true
	var oaks := int(planted.get("oak", 0))
	var clumped := int(planted.get("oak_clump", 0))
	_free(chunk)
	# HILL_PLANTING_2=0: the old planting exactly, no scatter, no extra oaks.
	HillScatter.enabled = false
	var old := _build(city, k, CityChunk.Level.FULL)
	HillScatter.enabled = true
	var moved := 0
	var pts: Array = old.hill_planting.get("points", [])
	for e: Array in pts:
		if not on.has(str(e)):
			moved += 1
	_t._check(moved == 0 and pts.size() == on.size() and old.get_node_or_null("Batch_hill_scatter_full") == null and int(old.hill_planting.get("oak_clump", 0)) == 0,
		"hill-planting-2: the hills' own planting is unmoved (%d of %d points moved; %d oaks, +%d in clumps)" % [moved, pts.size(), oaks, clumped])
	_free(old)
	# The budget at level 0 for the chunk the camera stands in: a few HillShrubs' worth.
	_t._check(count * 63 < 120000, "hill-planting-2: a FULL chunk's clumps are %d triangles at their finest" % (count * 63))


func _lod(city: Node3D, k: Vector2i) -> void:
	var chunk := _build(city, k + Vector2i(1, 0), CityChunk.Level.LOD)
	var done: Dictionary = chunk.get_meta("hill_scatter_done", {})
	var node: MultiMeshInstance3D = chunk.get_node_or_null("Batch_hill_scatter_lod")
	var count := int(done.get("count", 0))
	var ok := node != null and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and absf(node.visibility_range_end - HillScatter.LOD_DRAW) < 0.5
	_t._check(chunk.zone != MacroMap.Zone.HILLS or (ok and count >= 40 and count * 15 < 40000),
		"hill-planting-2: a LOD hill chunk plants %d bigger clumps (%d triangles at its middle level), drawn to %.0f m, no shadow" % [count, count * 15, HillScatter.LOD_DRAW])
	_free(chunk)
