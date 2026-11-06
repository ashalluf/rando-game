extends RefCounted
## A camera row's optional `wildlife` key (cameras_w8.json's coyote_night): urban wildlife staged
## where the row says, so the frame holds a coyote under the lamp and raccoons at the carts
## whatever the survey rolled. Loaded at run time by refcams_shot.gd (after the autoloads).
##
##   {"animals": [[species, x, z, yaw_deg, pose, seed], ...], "live": false}
## x, z a TRUE world point; yaw the game's yaw in degrees (0 faces -z); pose stand | sniff | sit |
## bins (a raccoon rooting at the kerb carts) | walk | trot (the gait plays, the animal is put back
## on its spot every frame so it is where the row says at the shot). The live survey is switched
## off and what it had put down freed (`live`: true keeps it). The log prints REFCAM wild lines.

static var hero_at := Vector3.INF
static var hero_yaw := 0.0
static var _made: Array = []
static var _survey_was := true


static func stage(tree: SceneTree, scene: Node, _cam: Camera3D, place: Callable, row: Dictionary) -> void:
	var spec: Dictionary = row.get("wildlife", {}) if row.get("wildlife", null) is Dictionary else {}
	var wl: Node = scene.get_node_or_null("Wildlife")
	if wl == null:
		print("REFCAM wild: no Wildlife node")
		return
	if not bool(spec.get("live", false)):
		_survey_was = bool(wl.get("enabled"))
		wl.set("enabled", false)
		for a in wl.call("animals"):
			(a as Node).queue_free()
	var moving: Array = []
	for e: Array in spec.get("animals", []):
		var sp := String(e[0])
		var yaw := deg_to_rad(float(e[3]))
		var pose := String(e[4]) if e.size() > 4 else "stand"
		var sd := int(e[5]) if e.size() > 5 else 7
		var an: Node3D = wl.call("stage", sp, Vector2(float(e[1]), float(e[2])), yaw, sd, true)
		_made.append(an)
		an.set("at_bins", pose == "bins")
		if pose in ["walk", "trot"]:
			moving.append([an, an.position, yaw, pose])
	await tree.process_frame
	for an: Node3D in _made:
		var rig: Variant = an.get("rig")
		if rig == null:
			continue
		var e: Array = spec.animals[_made.find(an)]
		var pose := String(e[4]) if e.size() > 4 else "stand"
		match pose:
			"sniff":
				an.set("_idle_pose", 0)
			"sit":
				an.set("_idle_pose", 1)
			"stand":
				an.set("_idle_pose", 2)
	for i in 20:
		for m: Array in moving:
			var an: Node3D = m[0]
			if not is_instance_valid(an):
				continue
			var f := Vector3(-sin(float(m[2])), 0.0, -cos(float(m[2])))
			an.position = m[1]
			an.set("_yaw", float(m[2]))
			an.rotation.y = float(m[2])
			an.set("route", [an.position + f * 60.0])
			an.set("mode", 2)
		await tree.process_frame
		place.call()
	# A trot: the rig's speed past its trot threshold (the travel speed is a walk).
	for m: Array in moving:
		if m[3] == "trot" and is_instance_valid(m[0]):
			var rig: Variant = (m[0] as Node3D).get("rig")
			if rig:
				rig.set("speed", float(rig.get("trot_at")) * 1.15)
	for an: Node3D in _made:
		if is_instance_valid(an):
			print("REFCAM wild %s at %s yaw %.1f level %d" % [an.name, str(WorldState.to_world(an.global_position)),
				rad_to_deg(an.rotation.y), int(an.get("rig").call("level"))])


static func unstage() -> void:
	for a in _made:
		if is_instance_valid(a):
			a.queue_free()
	_made.clear()
