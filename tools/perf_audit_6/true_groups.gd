extends RefCounted
## TRUE=1 on tools/refcams/refcams_shot.gd: per refcam, the triangles every MultiMesh group really
## submits (each instance at the LOD the renderer picks, frustum and cascades; still_shot's
## _true_tris), because the renderer's own counter counts a surface with LODs once per draw call
## whatever its instance count (CLAUDE.md, measurement trap 3). Prints "TRUE_<camera> <group> ..."
## lines; tools/perf_audit_6/true_table.py tabulates two runs.

static func report(shot: Node, cam_name: String) -> void:
	var groups := {}
	var scene: Node = shot.current_scene
	for n in scene.find_children("*", "MultiMeshInstance3D", true, false):
		var node := n as MultiMeshInstance3D
		if node.multimesh == null or node.multimesh.mesh == null:
			continue
		var nm := String(node.name)
		var mesh: Mesh = node.multimesh.mesh
		var g := ""
		var extra: Variant = null
		if nm.begins_with("Planting_"):
			g = "far_planting"
		elif nm.begins_with("Sky_"):
			g = "far_boxes"
		elif nm == "RoofUnits" or nm == "RoofUnitsRusted":
			g = "roof_units"
			extra = node.get_parent().get_node_or_null(NodePath(nm + "Shadow"))
		elif nm.begins_with("Batch_kit_"):
			g = "facade_kit"
		elif nm.begins_with("Batch_"):
			if mesh.has_meta("foliage_ladder") or mesh.has_meta("palm_ladder") or mesh.has_meta("knee_shadow_lod"):
				g = "plants"
			else:
				g = "props"
		else:
			continue
		var twin: Variant = node.get_meta("shadow_twin") if node.has_meta("shadow_twin") else null
		if not groups.has(g):
			groups[g] = []
		(groups[g] as Array).append({"node": node, "twin": twin, "extra": extra})
	var keys := groups.keys()
	keys.sort()
	for g: String in keys:
		shot.call("_true_tris", "TRUE_%s %s" % [cam_name, g], groups[g])
