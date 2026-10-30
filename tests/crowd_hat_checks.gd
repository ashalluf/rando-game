extends RefCounted
## Headwear checks for tests/smoke_test.gd (CrowdHat): every crowd rig has its head measured
## (CrowdHatTable, tools/crowd/hat_fit.gd - rerun it when a rig is rebuilt), every hat builds for
## every rig with its three levels, sits where a hat sits on that head (the band above the brows
## and over the ear tops, the crown just over the skull), and goes on a person as one unshadowed
## draw with the hair pressed or hidden under it; the crowd on the spawn block wears them, and a
## person knocked down keeps theirs on the body. What the dummy renderer cannot show - the head
## coming through the cloth - is the fit tool's REPORT=1. Loaded at run time like the other
## crowd checks, so it compiles after the autoloads.

var _t: Node
var _tree: SceneTree
const KINDS := ["cap", "beanie", "bucket", "peaked"]


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_check_table()
	_check_meshes()
	_check_dress()
	await _check_crowd(city)


func _check_table() -> void:
	var missing: Array = []
	var bad: Array = []
	var rigs: Array = Pedestrian.MODELS.duplicate()
	for r: String in PoliceOfficer.OFFICER_MODELS:
		if not r in rigs:
			rigs.append(r)
	for r: String in rigs:
		var row: Dictionary = CrowdHatTable.TABLE.get(r.get_file(), {})
		if row.is_empty():
			missing.append(r.get_file())
		elif (row.skull as Array).size() != CrowdHatTable.ROWS * CrowdHatTable.COLS \
				or (row.hair_t as Array).size() != CrowdHatTable.ROWS * CrowdHatTable.COLS:
			bad.append(r.get_file())
	_check(missing.is_empty() and bad.is_empty(), "every crowd rig's head is measured for its hats (CrowdHatTable; missing %s, bad %s)" % [missing, bad])


## Every hat on every rig: three levels, each well under the one above; the band above the brows
## at the front and over the ear tops at the sides; the crown a few millimetres over the skull.
func _check_meshes() -> void:
	var bad: Array = []
	var worst := Vector2(1.0, 0.0)
	for r: String in Pedestrian.MODELS:
		var h = CrowdHat.head_for(r)
		for kind in [CrowdHat.Kind.CAP, CrowdHat.Kind.BEANIE, CrowdHat.Kind.BUCKET, CrowdHat.Kind.PEAKED]:
			var mesh: ArrayMesh = CrowdHat.build_mesh(r, kind)
			var tris: Array = CrowdHat.lod_triangles(mesh)
			var why := ""
			if mesh.get_surface_count() != 1 or tris.size() != 3 or int(tris[0]) < 1000 or int(tris[0]) > 4000 \
					or int(tris[1]) * 2 > int(tris[0]) or int(tris[2]) * 2 > int(tris[1]):
				why += " levels %s" % str(tris)
			var front: float = CrowdHat.edge_y(h, kind, 0.0) - h.eye_y
			if front < 0.025 or front > 0.06:
				why += " front edge %.3f over the eyes" % front
			var ear_th := atan2(h.ear.x, h.ear.z - h.c.z)
			if CrowdHat.edge_y(h, kind, ear_th) < h.ear.y:
				why += " band below the ear top"
			if kind != CrowdHat.Kind.PEAKED and kind != CrowdHat.Kind.BUCKET:
				var top: Vector3 = CrowdHat._point(h, kind, 0.0, PI * 0.5, 1.0)
				var over: float = top.y - h.top
				worst = Vector2(minf(worst.x, over), maxf(worst.y, over))
				if over < 0.002 or over > 0.03:
					why += " crown %.3f over the head" % over
			if why != "":
				bad.append("%s %s:%s" % [r.get_file(), KINDS[kind], why])
	_check(bad.is_empty(), "every hat builds on every rig and sits where a hat sits (crown %.1f-%.1f mm over the skull; %s)" % [worst.x * 1000.0, worst.y * 1000.0, bad])


## One rig dressed in each kind: one Hat node, one surface, no shadow pass, a draw distance; the
## hair pressed under it (a new mesh) or, with no mesh data to press, hidden.
func _check_dress() -> void:
	var path: String = PoliceOfficer.OFFICER_MODELS[0]
	var bad: Array = []
	for kind in [CrowdHat.Kind.CAP, CrowdHat.Kind.BEANIE, CrowdHat.Kind.BUCKET, CrowdHat.Kind.PEAKED]:
		var rig: Node3D = (load(path) as PackedScene).instantiate()
		_t.add_child(rig)
		Pedestrian.prepare_rig(rig, 1)
		var hair_meshes := {}
		for hmi in rig.find_children("Hair*", "MeshInstance3D", true, false):
			hair_meshes[hmi] = (hmi as MeshInstance3D).mesh
		var mi := CrowdHat.dress(rig, path, kind, 5, 60.0)
		var hats := rig.find_children("Hat", "MeshInstance3D", true, false)
		var mat := mi.material_override as ShaderMaterial if mi else null
		if mi == null or hats.size() != 1 or mi.mesh.get_surface_count() != 1 or mat == null \
				or not str(mat.shader.resource_path).ends_with("crowd_hat.gdshader") or int(mat.get_shader_parameter("kind")) != kind \
				or mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or mi.visibility_range_end <= 0.0:
			bad.append(KINDS[kind] + " node")
		for hmi in hair_meshes:
			var m := hmi as MeshInstance3D
			if m.visible and m.mesh == hair_meshes[hmi]:
				bad.append(KINDS[kind] + " hair neither pressed nor hidden")
		rig.queue_free()
	_check(bad.is_empty(), "a hat goes on as one unshadowed draw with the hair pressed or hidden under it (%s)" % [bad])


## The spawn block's crowd wears hats, one each at most, and a person knocked down keeps theirs.
func _check_crowd(city: Node3D) -> void:
	var wearers := 0
	var doubled := 0
	var target: Node = null
	for ped in _tree.get_nodes_in_group("pedestrian"):
		if not is_instance_valid(ped) or ped is RoughSleeper:
			continue
		var hats := (ped as Node).find_children("Hat", "MeshInstance3D", true, false)
		if hats.size() > 0:
			wearers += 1
			if target == null and (ped as Node3D).is_inside_tree():
				target = ped
		if hats.size() > 1:
			doubled += 1
	_check(wearers > 0 and doubled == 0, "the crowd wears hats, one each (%d wearers, %d with more than one)" % [wearers, doubled])
	if target == null:
		return
	var parent := target.get_parent()
	var before := parent.get_child_count()
	target.call("knock", Vector3(0.0, 0.5, 0.0))
	await _tree.physics_frame
	var kept := false
	for i in range(before - 1, parent.get_child_count()):
		var doll := parent.get_child(i) as Ragdoll
		if doll and doll._rig and doll._rig.find_child("Hat", true, false) != null:
			kept = true
	_check(kept, "a person knocked down keeps their hat on the body")


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)
