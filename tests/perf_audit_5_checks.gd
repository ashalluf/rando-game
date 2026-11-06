extends RefCounted
## The fifth perf audit's cuts (docs/HANDOFF.md, the perf-audit-5 section) for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads; reads the city as it stands.
##   - a near car wheel casts from a plain 40-segment twin, under a quarter of its triangles;
##   - every car wheel rig that has a twin shows it exactly while the wheel is near, and the
##     wheel itself then casts nothing;
##   - the knee-high plants' shadow twins pick their LOD at the trees' shadow scale;
##   - nobody inside the crowd's shadow range is left without a shadow (rig or middle body).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_wheel_meshes()
	_wheel_rigs(city)
	_knee_twins(city)
	_crowd_shadows(city)


func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		n += ((a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


func _wheel_meshes() -> void:
	var near := PropFactory.car_wheel(1, 0.34, 0.22, true)
	var shadow := PropFactory.car_wheel_shadow(1, 0.34, 0.22)
	var a := _tris(near)
	var b := _tris(shadow)
	# The dummy renderer keeps no mesh data: then there is nothing to compare.
	_t._check(a == 0 or (b > 0 and b * 4 < a),
		"perf-audit-5: a near car wheel's shadow twin is under a quarter of its triangles (%d of %d)" % [b, a])


func _wheel_rigs(city: Node3D) -> void:
	var cars := 0
	var bad := 0
	for n in city.get_tree().get_nodes_in_group("vehicle"):
		var car := n as Vehicle
		if car == null or not is_instance_valid(car):
			continue
		for rig: Array in car._wheel_rigs:
			var mi := rig[1] as MeshInstance3D
			if mi == null:
				continue
			var twin := mi.get_node_or_null(^"WheelShadow") as GeometryInstance3D
			if twin == null:
				continue
			cars += 1
			if twin.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY \
					or mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
					or twin.visible != car._wheel_near:
				bad += 1
	var on := Vehicle.wheel_shadow_lite
	_t._check((cars > 0) == on and bad == 0,
		"perf-audit-5: car wheels cast from their twin exactly while near, never twice (%d wheels, %d wrong)" % [cars, bad])


func _knee_twins(city: Node3D) -> void:
	var seen := 0
	var bad := 0
	for n in city.find_children("Batch_*", "MultiMeshInstance3D", true, false):
		var node := n as MultiMeshInstance3D
		if not node.has_meta("shadow_twin") or node.multimesh == null or node.multimesh.mesh == null:
			continue
		var mesh := node.multimesh.mesh
		if not mesh.has_meta("knee_shadow_lod"):
			continue
		var twin := node.get_meta("shadow_twin") as MultiMeshInstance3D
		seen += 1
		if not is_equal_approx(twin.lod_bias, node.lod_bias * FoliageLod.SHADOW_LOD_SCALE):
			bad += 1
	var tagged := PropFactory.model_bush(0).has_meta("knee_shadow_lod") and PropFactory.model_shrub(0).has_meta("knee_shadow_lod")
	_t._check(bad == 0 and tagged == PropFactory.knee_shadow_lod,
		"perf-audit-5: knee-high plants' shadow twins pick their LOD at the trees' shadow scale (%d batches, %d wrong)" % [seen, bad])


func _crowd_shadows(city: Node3D) -> void:
	var player := city.get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var seen := 0
	var bad := 0
	var lite := 0
	for n in city.get_tree().get_nodes_in_group("pedestrian"):
		var p := n as Pedestrian
		if p == null or not p.is_inside_tree() or not p.is_visible_in_tree() or p._draw_tier != 0:
			continue
		var d := p.global_position.distance_to(player.global_position)
		if d > Pedestrian.shadow_range - 2.0:
			continue
		for mi in p._meshes:
			if not is_instance_valid(mi) or Pedestrian.is_hair(mi) or mi.skin == null or not mi.visible:
				continue
			seen += 1
			var twin: MeshInstance3D = mi.get_meta("shadow_twin") if mi.has_meta("shadow_twin") else null
			var twin_on := twin != null and twin.visible
			var rig_on := mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if twin_on:
				lite += 1
			if twin_on == rig_on:
				bad += 1
	_t._check(bad == 0,
		"perf-audit-5: everyone inside the crowd's shadow range casts exactly one shadow, rig or middle body (%d bodies, %d from the middle body, %d wrong)" % [seen, lite, bad])
