extends RefCounted
## The perf audit's cuts (docs/HANDOFF.md, the perf-audit section) for tests/smoke_test.gd. Loaded
## at run time, so it compiles after the autoloads. Checks: a batch with a shadow distance and no
## lighter twin casts from a SHADOWS_ONLY twin of its own mesh with a finite range (it used to do
## nothing); the street furniture's reaches are set on a FULL chunk's benches; the bench and the
## trash can are one surface per material with the triangles they had; the bus plate's lettering
## is under its budget; the lawn grass is batched in cells, each with the draw distance; the
## light rail's wires are their own non-casting mesh; physics props stop drawing.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_shadow_distance_twin()
	_merged_models()
	_chunk(city)


func _shadow_distance_twin() -> void:
	var holder := Node3D.new()
	var batch := MultiMeshBatch.new()
	var box := BoxMesh.new()
	for i in 4:
		batch.add("code_built", box, Transform3D(Basis(), Vector3(float(i) * 3.0, 0.0, 0.0)))
	batch.set_shadow_distance("code_built", 40.0)
	var nodes := batch.build(holder)
	var node: MultiMeshInstance3D = nodes.get("code_built")
	var twin: MultiMeshInstance3D = node.get_meta("shadow_twin", null) if node else null
	_t._check(node != null and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and twin != null \
			and twin.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY \
			and twin.multimesh.mesh == box and twin.visibility_range_end > 40.0 and twin.visibility_range_end < 60.0,
		"perf: a shadow distance on a code-built batch casts from a twin of its own mesh, out to the distance")
	holder.free()


func _merged_models() -> void:
	var bench := PropFactory.model_bench()
	var can := PropFactory.model_trash_can(false)
	_t._check(bench.get_surface_count() <= 5 and bench.get_surface_count() >= 1 and _tris(bench) > 4000,
		"perf: the bench is one surface per material (%d surfaces, %d triangles)" % [bench.get_surface_count(), _tris(bench)])
	_t._check(can.get_surface_count() == 1 and _tris(can) > 2000,
		"perf: the trash can is one surface (%d, %d triangles)" % [can.get_surface_count(), _tris(can)])
	var sign := PropFactory.bus_sign()
	_t._check(_tris(sign) < 1200, "perf: the bus plate's lettering is light (%d triangles)" % _tris(sign))


static func _tris(m: Mesh) -> int:
	var t := 0
	for i in m.get_surface_count():
		t += (m as ArrayMesh).surface_get_array_index_len(i) / 3
	return t


func _chunk(city: Node3D) -> void:
	var grass_cells := 0
	var grass_unranged := 0
	var bench_twin := false
	var bench_seen := false
	var rail_detail_ok := true
	var rail_seen := false
	for c in city.get_children():
		if not (c is CityChunk) or (c as CityChunk).level != CityChunk.Level.FULL:
			continue
		for n in c.get_children():
			var nm := String(n.name)
			if nm.begins_with("Batch_grass_"):
				grass_cells += 1
				if (n as GeometryInstance3D).visibility_range_end <= 0.0:
					grass_unranged += 1
			elif nm == "Batch_grass":
				grass_unranged += 1
			elif nm == "Batch_bench":
				bench_seen = true
				var tw: Node = n.get_meta("shadow_twin", null)
				if tw and (tw as GeometryInstance3D).visibility_range_end > 0.0:
					bench_twin = true
			elif nm == "RailDetail":
				rail_seen = true
				if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					rail_detail_ok = false
	_t._check(grass_unranged == 0, "perf: the lawn grass is in cells, every cell with its draw distance (%d cells)" % grass_cells)
	_t._check(not bench_seen or bench_twin, "perf: a FULL chunk's benches cast from a twin with a reach")
	_t._check(rail_detail_ok, "perf: the light rail's wires cast no shadow (%s)" % ("seen" if rail_seen else "no rail chunk here"))
	var props := 0
	var ranged := 0
	for p in _t.get_tree().get_nodes_in_group("physics_prop"):
		if p is TrashCan or p is PhysicsProp:
			for ch in p.get_children():
				if ch is MeshInstance3D:
					props += 1
					if (ch as MeshInstance3D).visibility_range_end > 0.0:
						ranged += 1
	_t._check(props == ranged, "perf: trash cans, barrels and tyres stop drawing past their distance (%d of %d)" % [ranged, props])
