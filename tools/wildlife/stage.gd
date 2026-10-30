extends RefCounted
## Stages the wildlife for tools/glshot/still_shot.gd (WILD=...): the animals named, in a row across
## the view WILD_DIST metres ahead of the camera (default 12), WILD_SPACING apart (default 2.2),
## side-on to it (WILD_TURN degrees more, default 90), posed by WILD_POSE stand | graze | sit |
## walk | trot | flee (a bolt away from the camera: a deer's stot, a rabbit's bound), run
## WILD_FRAMES frames (default 20). The live survey is turned off so only these are in the frame
## (WILD_LIVE=1 keeps it). A species may carry a seed: "deer:3".

static func stage(tree: SceneTree, scene: Node, spec: String, cam: Camera3D) -> Array:
	var wl: Node = scene.get_node_or_null("Wildlife")
	if wl == null or cam == null:
		print("WILD: no Wildlife node or camera")
		return []
	if OS.get_environment("WILD_LIVE") != "1":
		wl.set("enabled", false)
	var ws: Node = tree.root.get_node("/root/WorldState")
	var dist := _f("WILD_DIST", 12.0)
	var spacing := _f("WILD_SPACING", 2.2)
	var turn := deg_to_rad(_f("WILD_TURN", 90.0))
	var pose := OS.get_environment("WILD_POSE") if OS.get_environment("WILD_POSE") != "" else "stand"
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var names := spec.split(",")
	var out: Array = []
	var cam_w: Vector3 = ws.call("to_world", cam.global_position)
	for i in names.size():
		var bits := names[i].split(":")
		var sp := bits[0]
		var sd := bits[1].to_int() if bits.size() > 1 else 7 + i
		var off := (float(i) - float(names.size() - 1) * 0.5) * spacing
		var p := cam_w + fwd * dist + right * off
		var yaw := atan2(-fwd.x, -fwd.z) + turn
		var an: Node3D = wl.call("stage", sp, Vector2(p.x, p.z), yaw, sd, true)
		out.append(an)
	await tree.process_frame
	for an: Node3D in out:
		var rig = an.get("rig")
		match pose:
			"graze":
				an.set("_idle_pose", 0)
			"sit":
				an.set("_idle_pose", 1)
			"walk", "trot":
				var f := Vector3(-sin(float(an.get("_yaw"))), 0.0, -cos(float(an.get("_yaw"))))
				an.set("route", [an.position + f * 60.0])
				an.set("mode", 2)
			"flee":
				an.call("_flee_from", cam.global_position)
	for k in int(_f("WILD_FRAMES", 20.0)):
		await tree.process_frame
	for an: Node3D in out:
		if is_instance_valid(an):
			print("WILD %s at %s yaw %.2f level %d" % [an.name, ws.call("to_world", an.global_position), an.rotation.y, an.get("rig").call("level")])
	return out


static func _f(key: String, dflt: float) -> float:
	var v := OS.get_environment(key)
	return v.to_float() if v != "" else dflt
