extends RefCounted
## The memory audit after wave 8 (docs/HANDOFF.md, "Memory after wave 8") for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads; never names CityStreamer as a type.
## No teleport of its own (a jump builds a whole area: +300 MB on its shard):
##   - CityStreamer._hollow() frees what holds no physics body and runs no script, keeps the bodies
##     (and the nodes on the way to one) with their shapes and meshes dropped, and never cuts into a
##     scripted node (its meshes emptied, its children kept);
##   - an immediate update empties a chunk still standing for its dissolve (hidden, counted) and
##     leaves the chunk itself to its old timer: freed once the dissolve's time is up.

var _t: Node
var _tree: SceneTree


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var script: Script = city.get_script()
	_hollow_rule(script)
	if not bool(script.get("TELEPORT_FREE")):
		_check(true, "memory-audit-w8: TELEPORT_FREE=0, the A/B (no emptying on a teleport)")
		return
	await _retiring(city, script)


func _hollow_rule(script: Script) -> void:
	var root := Node3D.new()
	var deco := Node3D.new()
	deco.name = "Deco"
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	deco.add_child(mi)
	root.add_child(deco)
	var holder := Node3D.new()
	holder.name = "Holder"
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = BoxMesh.new()
	body.add_child(body_mesh)
	holder.add_child(body)
	holder.add_child(MeshInstance3D.new())
	root.add_child(holder)
	var walker := CharacterBody3D.new()
	walker.set_script(load("res://tests/memory_audit_w8_walker.gd"))
	var limb := MeshInstance3D.new()
	limb.mesh = BoxMesh.new()
	walker.add_child(limb)
	root.add_child(walker)
	_tree.root.add_child(root)
	walker.set_physics_process(false)
	script.call("_hollow", root, true)
	var ok := not is_instance_valid(deco) and not is_instance_valid(mi)
	ok = ok and is_instance_valid(holder) and is_instance_valid(body) and is_instance_valid(shape)
	ok = ok and shape.shape == null and not is_instance_valid(body_mesh) and holder.get_child_count() == 1
	ok = ok and is_instance_valid(limb) and limb.mesh == null and walker.get_child_count() == 1
	_check(ok, "memory-audit-w8: a teleport's emptying frees what holds no body, keeps the bodies without shapes or meshes, never cuts into a scripted node (only empties its meshes)")
	root.free()


func _retiring(city: Node3D, script: Script) -> void:
	# An unbuilt LOD chunk far from the window, standing for its dissolve.
	var key := Vector2i(9000, 9000)
	var chunk: Node3D = city.call("_new_chunk", key, 1)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	chunk.add_child(mi)
	var retiring: Dictionary = city.get("_retiring")
	retiring[key] = [chunk, 0.4]
	var n0 := int(script.get("teleport_freed"))
	city.call("_free_retiring_now")
	var emptied := int(script.get("teleport_freed")) - n0
	_check(emptied == 1 and not chunk.visible and not is_instance_valid(mi) and is_instance_valid(chunk) and retiring.has(key),
		"memory-audit-w8: an immediate update empties a retiring chunk at once and leaves the chunk to its timer (%d)" % emptied)
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(chunk) and Time.get_ticks_msec() - t0 < 10000:
		await _tree.process_frame
	_check(not is_instance_valid(chunk) and not retiring.has(key),
		"memory-audit-w8: the emptied chunk is freed when its dissolve's time is up, as before")
