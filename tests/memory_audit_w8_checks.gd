extends RefCounted
## The memory audit after wave 8 (docs/HANDOFF.md, "Memory after wave 8") for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads; never names CityStreamer as a type.
##   - a teleport (update_streaming(true)) lets the chunks it leaves go before it builds the next
##     area: none waits for the dissolve, each is hidden with its meshes dropped at once, and freed
##     (queue_free) by the frame's end;
##   - the chunks of the new window are all there and built in the same call, as before.

var _t: Node
var _tree: SceneTree


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var script: Script = city.get_script()
	if not bool(script.get("TELEPORT_FREE")):
		_check(true, "memory-audit-w8: TELEPORT_FREE=0, the A/B (nothing to check)")
		return
	var player := _tree.get_first_node_in_group("player") as Node3D
	var ws: Node = _tree.root.get_node("/root/WorldState")
	if player == null:
		return
	var home: Vector3 = ws.call("to_world", player.global_position)
	var before: Array = (city.get("chunks") as Dictionary).values()
	var freed0 := int(script.get("teleport_freed"))
	# 3 km east: none of the window here survives the jump (its LOD ring reaches 840 m).
	var away := home + Vector3(3000.0, 0.0, 0.0)
	var local: Vector3 = ws.call("to_local", away)
	local.y = float(city.call("ground_height_at", local)) + 3.0
	player.global_position = local
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	city.call("update_streaming", true)
	# Same frame: nothing waits on the dissolve, and the old chunks are gone already.
	var retiring: Dictionary = city.get("_retiring")
	var freed := int(script.get("teleport_freed")) - freed0
	_check(retiring.is_empty() and freed > 0,
		"memory-audit-w8: a teleport lets the chunks it leaves go at once (%d, %d still retiring)" % [freed, retiring.size()])
	# Out of the window, each old chunk is hidden and holds no mesh this frame, and is gone by the next.
	var heavy := 0
	var old: Array = []
	for c in before:
		if is_instance_valid(c) and not (city.get("chunks") as Dictionary).values().has(c):
			old.append(c)
			if (c as Node3D).visible:
				heavy += 1
			for n in (c as Node).find_children("*", "MeshInstance3D", true, false):
				if (n as MeshInstance3D).mesh != null:
					heavy += 1
					break
	_check(not old.is_empty() and heavy == 0,
		"memory-audit-w8: the chunks left behind drop their meshes at once (%d left, %d still holding meshes)" % [old.size(), heavy])
	await _tree.process_frame
	await _tree.process_frame
	var alive := 0
	for c in old:
		if is_instance_valid(c):
			alive += 1
	_check(alive == 0, "memory-audit-w8: and are freed by the frame's end (%d alive)" % alive)
	var full := 0
	for c in (city.get("chunks") as Dictionary).values():
		if int(c.get("level")) == 0:
			full += 1
	_check(full >= 9, "memory-audit-w8: the new window is built in the same call (%d FULL chunks)" % full)
