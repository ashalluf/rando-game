extends RefCounted
## Stages the crowd's flow in front of the camera for a still (tools/glshot/still_shot.gd
## FLOW=kerb|groups) and returns the EYE that frames it ("" if nothing could be staged). Loaded at
## run time by the still script, so it may name the game's classes:
##   kerb    a bunch waiting at the crosswalk at the corner of the camera's block nearest it, the
##           steady hand up (FLOW_PEOPLE, default 9); EYE across the road looking back at them
##   groups  pairs and threes walking along the camera's nearest pavement with singles coming the
##           other way (FLOW_PEOPLE, default 12), run FLOW_SECONDS (default 3) of game time; EYE on
##           the pavement ahead, looking back along it
## CROWD_FLOW=0 is the before: the same people placed the same way, walking without the flow.

var _scene: Node
var _plan: CityPlan
var _tree: SceneTree
var _ws: Node


func stage(scene: Node, kind: String, cam: Camera3D) -> String:
	_scene = scene
	_tree = scene.get_tree()
	_plan = scene.get("plan")
	_ws = _tree.root.get_node("/root/WorldState")
	if _plan == null or cam == null:
		print("FLOW: nothing to stage with")
		return ""
	var traffic := scene.get_node_or_null("Traffic")
	if traffic:
		traffic.set("staged", true)
	var cp: Vector3 = _ws.to_world(cam.global_position)
	var here := Vector2(cp.x, cp.z)
	match kind:
		"kerb":
			return await _kerb(here)
		"groups":
			return await _groups(here)
	print("FLOW: unknown kind ", kind)
	return ""


func _envi(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback


func _envf(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return float(v) if v != "" else fallback


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _walker(ring: Rect2, at: Vector2, seed_value: int) -> Pedestrian:
	var chunk: Node = _scene.chunks.get(_plan.chunk_index_at(ring.get_center()))
	if chunk == null:
		return null
	var p := Pedestrian.new()
	p.setup(ring, _plan.sidewalk_width, seed_value)
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	p.set_meta("no_trim", true)
	p.position = Vector3(at.x, chunk.call("ground_y", at.x, at.y) + 0.1, at.y)
	chunk.add_child(p)
	return p


## Clears the crowd's own walkers off a stretch so the staged ones are the scene.
func _clear(at: Vector2, reach: float) -> void:
	for n in _tree.get_nodes_in_group("pedestrian"):
		var p := n as Pedestrian
		if p and not p.has_meta("no_trim") and Vector2(p.position.x, p.position.z).distance_to(at) < reach:
			p.queue_free()


func _eye(at: Vector2, height_agl: float, look_at: Vector3) -> String:
	var h := _plan.height_at(at) + CityChunk.SIDEWALK_TOP + height_agl
	var d := look_at - Vector3(at.x, h, at.y)
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [at.x, h, at.y, yaw, pitch]


func _kerb(here: Vector2) -> String:
	var b := _plan.block_index_at(here)
	var rect: Rect2 = _plan.block(b.x, b.y).rect
	var centre := rect.get_center()
	var sx := 1.0 if here.x > centre.x else -1.0
	var sz := 1.0 if here.y > centre.y else -1.0
	var corner := Vector2(rect.end.x - 2.5 if sx > 0.0 else rect.position.x + 2.5, rect.end.y - 5.0 if sz > 0.0 else rect.position.y + 5.0)
	_clear(corner, 30.0)
	await _ticks(2)
	var node := Vector2i(b.x + (1 if sx > 0.0 else 0), b.y + (1 if sz > 0.0 else 0))
	# The steady hand for walkers crossing the road along x: its traffic has green.
	TrafficSignals.force(_plan, node.x, node.y, CityPlan.AXIS_Z, TrafficSignals.Light.GREEN, 0.5)
	var n := _envi("FLOW_PEOPLE", 9)
	var people: Array = []
	for k in n:
		var at := corner + Vector2(-sx * float(k % 3) * 0.9, -sz * float(k / 3) * 1.4)
		var p := _walker(rect, at, 77100 + k)
		if p:
			people.append(p)
	await _ticks(3)
	var crossing: Pedestrian = null
	for p: Pedestrian in people:
		if p.plan_crossing(CityPlan.AXIS_Z):
			crossing = p
			p._place_at(p._cross_from, 0.0)
			p._arrive_at_kerb()
			var across := (p._cross_to - p._cross_from).normalized()
			p._visual.rotation.y = atan2(-across.x, -across.y)
	if crossing == null:
		print("FLOW kerb: no crosswalk at the corner nearest the camera")
		return ""
	await _ticks(_envi("FLOW_FRAMES", 40))
	var from := crossing._cross_from
	var to := crossing._cross_to
	var dir := (to - from).normalized()
	# Out on the crosswalk, a little to the side, about seven metres off them.
	var eye := from + dir * _envf("FLOW_EYE_OUT", 7.5) + Vector2(-dir.y, dir.x) * _envf("FLOW_EYE_SIDE", 3.5)
	var mid := Vector3(from.x, _plan.height_at(from) + 0.9, from.y)
	print("FLOW kerb: %d waiting at %s, slots %s" % [people.size(), from, people.map(func(q): return int(q.flow.get("kerb_slot", -1)))])
	return _eye(eye, 1.65, mid)


func _groups(here: Vector2) -> String:
	var b := _plan.block_index_at(here)
	var rect: Rect2 = _plan.block(b.x, b.y).rect
	# The north or south pavement, whichever the camera is nearer.
	var north := absf(here.y - rect.position.y) < absf(here.y - rect.end.y)
	var y := rect.position.y + 2.2 if north else rect.end.y - 2.2
	var x0 := clampf(here.x, rect.position.x + 30.0, rect.end.x - 30.0)
	_clear(Vector2(x0, y), 45.0)
	await _ticks(2)
	var n := _envi("FLOW_PEOPLE", 12)
	var made := 0
	var k := 0
	var walkers: Array = []
	# Pairs and threes from x0 heading -x (toward the camera), singles coming the other way.
	while made < n and k < 20:
		var x := x0 + 3.2 * float(k)
		if k % 3 != 2:
			var l := _walker(rect, Vector2(x, y), 77200 + k)
			if l == null:
				break
			made += 1
			walkers.append(l)
			l.set_meta("flow_goal", Vector2(x0 - 40.0, y + (0.4 if k % 2 == 0 else -0.4)))
			var m := 1 if k % 4 != 1 else 2
			for j in m:
				if made >= n:
					break
				var f := _walker(rect, Vector2(x + 0.5, y + 0.6), 77300 + k * 3 + j)
				if f:
					await _ticks(1)
					CrowdFlow.join(f, l, true)
					walkers.append(f)
					made += 1
		else:
			var s := _walker(rect, Vector2(x0 - 12.0 - 3.0 * float(k), y + 0.3), 77400 + k)
			if s == null:
				break
			made += 1
			s.set_meta("flow_goal", Vector2(x0 + 40.0, y))
			walkers.append(s)
		k += 1
	await _ticks(2)
	for w: Pedestrian in walkers:
		if w.has_meta("flow_goal"):
			w._go_to(w.get_meta("flow_goal"))
	await _ticks(int(60.0 * _envf("FLOW_SECONDS", 3.0)))
	for w: Pedestrian in walkers:
		print("FLOW groups walker at %s leader %s" % [Vector2(w.position.x, w.position.z), w.flow.get("leader") != null])
	var eye := Vector2(x0 - 16.0, y + (1.4 if north else -1.4))
	return _eye(eye, 1.65, Vector3(x0 + 2.0, _plan.height_at(Vector2(x0 + 2.0, y)) + 1.0, y))
