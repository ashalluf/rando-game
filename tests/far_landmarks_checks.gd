extends RefCounted
## Checks for the landmarks' far copies (docs/HANDOFF.md, "Far landmarks"), run from
## tests/smoke_test.gd. Each landmark below is built detailed and far, as the chunk and
## CityStreamer._build_far_landmarks() build them, into holders that are freed again: the far copy
## plants the same palms and trees as the detailed one (the same meshes, whose LOD ladders thin
## them at range) and none of its planting casts a shadow. Loaded at run time so it can name the
## landmark classes freely. The look itself is judged with tools/glshot/far_landmark_shot.gd.

## Landmarks whose far copy carries the detailed copy's planting.
const PLANTED := ["arena", "live_plaza", "civic_park", "concert_hall", "lattice_museum", "masjid_omar", "skyhook", "venice_boardwalk", "rental_lot"]

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	if plan == null or plan.macro == null:
		return
	var ws := t.get_tree().root.get_node("/root/WorldState")
	var off: Vector3 = ws.get("world_offset")
	var foliage := {}
	for v in PropFactory.PALM_VARIANTS:
		foliage[PropFactory.palm(v)] = true
	for v in PropFactory.CITY_TREES.size():
		foliage[PropFactory.model_tree(v)] = true
	var parity := ""
	var shadows := ""
	var empty := ""
	for lm in Landmarks.all():
		if not PLANTED.has(lm.id):
			continue
		var near := Node3D.new()
		near.position = -off
		city.add_child(near)
		var statics := StaticBody3D.new()
		near.add_child(statics)
		Landmarks.build(lm, near, statics, plan, true)
		var far := Node3D.new()
		far.position = -off
		city.add_child(far)
		Landmarks.build(lm, far, null, plan, false)
		MultiMeshBatch.merge_meshes(far)
		var n := _count(near, foliage, false)
		var f := _count(far, foliage, true)
		if n.count == 0:
			empty += " " + lm.id
		if n.count != f.count:
			parity += " %s (%d near, %d far)" % [lm.id, n.count, f.count]
		if f.shadowed > 0:
			shadows += " %s (%d)" % [lm.id, f.shadowed]
		near.free()
		far.free()
	_t._check(empty == "", "every planted landmark plants palms or trees near (none:%s)" % empty)
	_t._check(parity == "", "far landmark copies plant the detailed copies' palms and trees (differ:%s)" % parity)
	_t._check(shadows == "", "far landmark copies' planting casts no shadow (casting:%s)" % shadows)


## Palms and trees under `root` (MultiMesh instances and single nodes alike), and how many of the
## far ones cast a shadow (a palm or tree batch's shadow twin counts as casting).
func _count(root: Node, foliage: Dictionary, far: bool) -> Dictionary:
	var count := 0
	var shadowed := 0
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var mesh: Mesh = null
		var k := 1
		if node is MultiMeshInstance3D:
			var mm := (node as MultiMeshInstance3D).multimesh
			if mm == null:
				continue
			mesh = mm.mesh
			k = mm.instance_count
		elif node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		var gi := node as GeometryInstance3D
		var name := String(gi.name)
		var is_twin := name.begins_with("BatchShadow_palm_") or name.begins_with("BatchShadow_tree_")
		if foliage.has(mesh) and not name.begins_with("BatchShadow_"):
			count += k
		if far and (foliage.has(mesh) or is_twin) and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadowed += k
	return {"count": count, "shadowed": shadowed}
