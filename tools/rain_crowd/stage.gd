extends RefCounted
## Stages the crowd in the rain for tools/glshot/still_shot.gd (RAIN_STAGE=<level>, with
## --weather=rain|storm for the sky and the wet streets): forces RainCrowd's level and settles
## everyone near the player as the rain would have left them (umbrellas up, hoods up, in the
## doorways and shelters, a share gone in). RAIN_FOCUS=umbrella|hood|shelter|street moves the free
## camera to the nearest person doing that (RAIN_FOCUS_DIST metres off, default 6); street looks
## along the pavement from where the camera is. Returns the EYE it set ("" for none).
## RAIN_REPORT=1 prints what everyone near the camera is doing.


static func stage(tree: SceneTree, level: float, cam: Camera3D) -> String:
	RainCrowd.forced = level
	var counts := {"umbrella": 0, "hood": 0, "shelter": 0, "inside": 0, "none": 0}
	var best: Pedestrian = null
	var best_d := 120.0
	var focus := OS.get_environment("RAIN_FOCUS")
	for n in tree.get_nodes_in_group("pedestrian"):
		var p := n as Pedestrian
		if p == null or p.rain == null:
			continue
		p.rain.settle_now()
		var r: RainCrowd = p.rain
		var key := "inside" if r.inside else ("shelter" if r.sheltering else ("umbrella" if r.open > 0.5 else ("hood" if r.hood > 0.5 else "none")))
		if p._life_near:
			counts[key] = int(counts[key]) + 1
		if OS.get_environment("RAIN_REPORT") == "1" and p._life_near:
			print("RAIN %s at %s act %d gear %d" % [key, (tree.root.get_node("/root/WorldState").to_world(p.global_position) as Vector3).snapped(Vector3.ONE * 0.1), p._act, r.gear])
		if focus != "" and focus != "street" and key == focus and cam:
			var d := p.global_position.distance_to(cam.global_position)
			if d < best_d:
				best_d = d
				best = p
	print("RAIN_STAGE level %.2f near: %s" % [level, counts])
	if best == null:
		return ""
	var yaw := best._visual.global_rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var dist := float(OS.get_environment("RAIN_FOCUS_DIST")) if OS.get_environment("RAIN_FOCUS_DIST") != "" else 6.0
	var target := best.global_position + Vector3.UP * 1.3
	var at := best.global_position + (fwd * 0.85 + right * 0.5).normalized() * dist + Vector3.UP * 1.7
	var dd := target - at
	var world: Vector3 = tree.root.get_node("/root/WorldState").to_world(at)
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [world.x, world.y, world.z, rad_to_deg(atan2(-dd.x, -dd.z)), rad_to_deg(atan2(dd.y, Vector2(dd.x, dd.z).length()))]
