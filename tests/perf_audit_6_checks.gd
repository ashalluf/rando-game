extends RefCounted
## The sixth perf audit's cuts (docs/HANDOFF.md, the perf-audit-6 section) for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads; reads the city as it stands.
##   - every building's rooftop air-conditioning units cast from a twin (and only from it);
##   - street props' shadow twins pick their LOD at the trees' shadow scale.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_roof_units(city)
	_prop_twins(city)


func _roof_units(city: Node3D) -> void:
	var units := 0
	var bad := 0
	for n in city.find_children("RoofUnits*", "MultiMeshInstance3D", true, false):
		var mi := n as MultiMeshInstance3D
		if String(mi.name).ends_with("Shadow"):
			continue
		units += 1
		var twin := mi.get_parent().get_node_or_null(NodePath(String(mi.name) + "Shadow")) as MultiMeshInstance3D
		if PerfSix.roof_units_lite:
			if twin == null or twin.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY \
					or mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
					or twin.multimesh.instance_count != mi.multimesh.instance_count:
				bad += 1
		elif twin != null or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			bad += 1
	_t._check(units > 0 and bad == 0,
		"perf-audit-6: rooftop AC units cast from their twin only, every building (%d nodes, %d wrong)" % [units, bad])


func _prop_twins(city: Node3D) -> void:
	var twins := 0
	var bad := 0
	for n in city.find_children("BatchShadow_*", "MultiMeshInstance3D", true, false):
		var tw := n as MultiMeshInstance3D
		var node := tw.get_parent().get_node_or_null(NodePath(String(tw.name).replace("BatchShadow_", "Batch_"))) as MultiMeshInstance3D
		var mesh: Mesh = node.multimesh.mesh if node and node.multimesh else null
		if mesh == null or mesh.has_meta("foliage_ladder") or mesh.has_meta("palm_ladder") or mesh.has_meta("knee_shadow_lod"):
			continue
		var want: float = node.lod_bias * PerfSix.prop_twin_bias()
		twins += 1
		if not is_equal_approx(tw.lod_bias, want):
			bad += 1
	_t._check(twins > 0 and bad == 0,
		"perf-audit-6: street props' shadow twins at the shadow LOD scale (%d twins, %d wrong)" % [twins, bad])
