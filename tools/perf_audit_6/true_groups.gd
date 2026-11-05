extends RefCounted
## TRUE=1 on tools/refcams/refcams_shot.gd: per refcam, the triangles every MultiMesh group really
## submits (each instance at the LOD the renderer picks, frustum and cascades; still_shot's
## _true_tris), because the renderer's own counter counts a surface with LODs once per draw call
## whatever its instance count (CLAUDE.md, measurement trap 3). Prints "TRUE_<camera> <group> ..."
## lines; tools/perf_audit_6/true_table.py tabulates two runs.

static func report(shot: Object, cam_name: String) -> void:
	var groups := {}
	var scene: Node = shot.get("current_scene")
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
	houses(shot, cam_name)


## The houses' meshes (HouseKit.commit(): one per material a chunk, no LODs), by material: camera
## (in the frustum) and shadow (cascades the swept box reaches), like _true_tris.
static func houses(shot: Object, cam_name: String) -> void:
	var cam: Camera3D = (shot as SceneTree).root.get_camera_3d()
	var planes := cam.get_frustum()
	var sun: DirectionalLight3D = null
	for n in (shot.get("current_scene") as Node).find_children("*", "DirectionalLight3D", true, false):
		if (n as DirectionalLight3D).shadow_enabled:
			sun = n
			break
	var by := {}
	for n in (shot.get("current_scene") as Node).find_children("House_*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var tris := 0
		for s in mi.mesh.get_surface_count():
			var surf := RenderingServer.mesh_get_surface(mi.mesh.get_rid(), s)
			var ic := int(surf.get("index_count", 0))
			tris += (ic if ic > 0 else int(surf.get("vertex_count", 0))) / 3
		var box: AABB = mi.global_transform * mi.get_aabb()
		var row: Array = by.get(String(mi.name), [0, 0])
		if shot.call("_box_in_frustum", box, planes):
			row[0] += tris
		if sun and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			var d := Vector3.ZERO.max(box.position - cam.global_position).max(cam.global_position - box.end).length()
			if d < sun.directional_shadow_max_distance:
				row[1] += tris
		by[String(mi.name)] = row
	for k: String in by:
		print("TRUE_%s houses %s camera tris=%d shadow_reach tris=%d (one cascade each)" % [cam_name, k, by[k][0], by[k][1]])
