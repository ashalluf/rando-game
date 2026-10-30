extends RefCounted
## Stages people standing on uneven ground in front of a free camera for a foot-placement still
## (tools/glshot/still_shot.gd FEET=kerb|stairs|slope; FOOT_IK=0 is the before). Returns the EYE
## that frames them ("" if nothing could be staged). Loaded at run time by the still script.
##   kerb    FEET_AT=x,z (true world, on a pavement): the nearest kerb edge is found by rays and
##           three people stand at it (one side-on with a foot over it, two facing the road just
##           back from it); EYE low in the road looking at the kerb.
##   stairs  the replica's beach stairs (FEET_STAIR=0..4, its index in the Esplanade's table):
##           people on the treads facing down, up and side-on; EYE beside the flight.
##   slope   FEET_AT=x,z on sloping ground: people across, up and down the slope; EYE side-on.
## FEET_EYE_DIST (m) moves the camera in or out; FEET_SEEDS=a,b,c picks the people.

var _scene: Node
var _ws: Node
var _space: PhysicsDirectSpaceState3D
var _peds: Array = []


func stage(scene: Node, kind: String, tree: SceneTree, player: Node3D) -> String:
	_scene = scene
	_ws = tree.root.get_node("/root/WorldState")
	var plan = scene.get("plan")
	var at := Vector2.INF
	var stair: Array = []
	if kind == "stairs":
		var rep = plan.macro.replica if plan and plan.macro else null
		if rep == null:
			print("FEET: no replica")
			return ""
		var list: Array = rep.data.get("stairs", [])
		var s := float(list[clampi(int(_env("FEET_STAIR", "0")), 0, list.size() - 1)])
		stair = rep.at_s(s)
		var sd: Dictionary = stair[3]
		at = (stair[0] as Vector2) + ReplicaAreas.left_of(stair[1]) * ((float(sd.edge) + float(sd.toe)) * 0.5)
	else:
		var a := _env("FEET_AT", "").split_floats(",")
		if a.size() < 2:
			print("FEET: FEET_AT=x,z needed")
			return ""
		at = Vector2(a[0], a[1])
	# Bring the streaming there and let the chunks round it build.
	player.global_position = _ws.to_local(Vector3(at.x, plan.height_at(at) + 2.0, at.y))
	if scene.has_method("update_streaming"):
		scene.call("update_streaming", true)
	for i in 30:
		await tree.physics_frame
	_space = (scene as Node3D).get_world_3d().direct_space_state
	var eye := ""
	match kind:
		"kerb":
			eye = _kerb(at)
		"stairs":
			eye = _stairs(stair)
		"slope":
			eye = _slope(at)
	# Keep the player out of the picture, near enough that the people are physics bodies.
	player.visible = false
	for i in 50:
		await tree.physics_frame
	return eye


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return fallback if v == "" else v


## Ground height under (x, z) in true world (the highest surface under `from_y`), or NAN.
func _ground(x: float, z: float, from_y: float) -> float:
	var a: Vector3 = _ws.to_local(Vector3(x, from_y, z))
	var q := PhysicsRayQueryParameters3D.create(a, a - Vector3(0, 40.0, 0), 1 | CrowdFeet.FEET_LAYER)
	var hit := _space.intersect_ray(q)
	if not hit.is_empty() and CrowdFeet._passes(hit):
		q.from = hit.position - Vector3(0, 0.002, 0)
		hit = _space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return (_ws.to_world(hit.position) as Vector3).y


func _seed(i: int) -> int:
	var seeds := _env("FEET_SEEDS", "11,29,47,61").split(",")
	return int(seeds[i % seeds.size()])


## One person standing at true world (x, z) on the ground there, facing yaw (radians, 0 = -z).
func _stand(p: Vector2, yaw: float, i: int, from_y: float) -> void:
	var y := _ground(p.x, p.y, from_y)
	if is_nan(y):
		return
	var ped := Pedestrian.new()
	ped.setup(Rect2(p.x - 40.0, p.y - 40.0, 80.0, 80.0), 4.0, _seed(i))
	ped.pause_chance = 0.0
	ped.cross_chance = 0.0
	ped.life_spawn_chance = 0.0
	ped.life_chance = 0.0
	ped.position = _ws.to_local(Vector3(p.x, y + 0.02, p.y))
	_scene.add_child(ped)
	ped._pause_left = 1.0e6
	ped._visual.rotation.y = yaw
	ped._play_idle()
	ped._speed = 0.0
	_peds.append(ped)
	print("FEET person %d at %.2f,%.2f,%.2f yaw %.0f" % [i, p.x, y, p.y, rad_to_deg(yaw)])


static func _yaw_of(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


## EYE string looking from `from` at `to` (true world).
static func _eye_at(from: Vector3, to: Vector3) -> String:
	var d := (to - from).normalized()
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
	return "%.2f,%.2f,%.2f,%.1f,%.1f" % [from.x, from.y, from.z, yaw, pitch]


func _kerb(at: Vector2) -> String:
	var top := _ground(at.x, at.y, 400.0) + 1.5
	var h0 := _ground(at.x, at.y, top)
	# The nearest direction (of 16) in which the ground drops more than 8 cm within 8 m.
	var best_t := INF
	var best_d := Vector2.ZERO
	for k in 16:
		var d := Vector2.from_angle(TAU * float(k) / 16.0)
		var t := 0.1
		while t < 8.0:
			var p := at + d * t
			var h := _ground(p.x, p.y, top)
			if not is_nan(h) and h < h0 - 0.08:
				if t < best_t:
					best_t = t
					best_d = d
				break
			t += 0.1
	if best_t == INF:
		print("FEET: no kerb near %s" % at)
		return ""
	# Refine the edge to 1 cm.
	var lo := best_t - 0.1
	var hi := best_t
	for i in 8:
		var mid := (lo + hi) * 0.5
		var p := at + best_d * mid
		if _ground(p.x, p.y, top) < h0 - 0.08:
			hi = mid
		else:
			lo = mid
	var edge := at + best_d * lo
	var along := Vector2(-best_d.y, best_d.x)
	print("FEET kerb edge %.2f,%.2f road toward %s" % [edge.x, edge.y, best_d])
	# Side-on with the outer foot over the edge; facing the road at the edge; side-on the other way.
	_stand(edge + along * -1.3 - best_d * 0.06, _yaw_of(along), 0, top)
	_stand(edge - best_d * 0.16, _yaw_of(best_d), 1, top)
	_stand(edge + along * 1.3 - best_d * 0.08, _yaw_of(-along), 2, top)
	var dist := float(_env("FEET_EYE_DIST", "3.6"))
	var road := edge + best_d * dist + along * 0.4
	var gy := _ground(road.x, road.y, top)
	return _eye_at(Vector3(road.x, gy + 0.55, road.y), Vector3(edge.x, h0 + 0.35, edge.y))


func _stairs(at: Array) -> String:
	var p: Vector2 = at[0]
	var d: Vector2 = at[1]
	var sd: Dictionary = at[3]
	var l := ReplicaAreas.left_of(d)
	var edge := float(sd.edge)
	var toe := float(sd.toe)
	var top := float(at[2]) + 3.0
	var down := (l * -signf(edge - toe)).normalized() # down the flight
	var span := absf(edge - toe)
	var spot := func(share: float, side: float) -> Vector2:
		return p + l * lerpf(edge, toe, share) + d * side
	# Near the foot of the flight, seen from the sand looking up it (the side walls hide feet
	# from beside it).
	_stand(spot.call(0.70, 0.45), _yaw_of(down), 0, top)
	_stand(spot.call(0.79, -0.42), _yaw_of(-down), 1, top)
	_stand(spot.call(0.88, 0.2), _yaw_of(d), 2, top)
	var mid: Vector2 = spot.call(0.8, 0.0)
	var dist := float(_env("FEET_EYE_DIST", "5.2"))
	var cam := mid + down * dist
	var my := _ground(mid.x, mid.y, top)
	var cy := _ground(cam.x, cam.y, top)
	print("FEET stairs %.1f m long, middle %.2f,%.2f" % [span, mid.x, mid.y])
	return _eye_at(Vector3(cam.x, (cy if not is_nan(cy) else my - 1.0) + 1.2, cam.y), Vector3(mid.x, my + 0.5, mid.y))


func _slope(at: Vector2) -> String:
	var top := _ground(at.x, at.y, 2000.0) + 3.0
	var e := 1.0
	var gx := (_ground(at.x + e, at.y, top) - _ground(at.x - e, at.y, top)) / (2.0 * e)
	var gz := (_ground(at.x, at.y + e, top) - _ground(at.x, at.y - e, top)) / (2.0 * e)
	var up := Vector2(gx, gz)
	if up.length() < 0.02:
		up = Vector2(0, -1)
	print("FEET slope grade %.0f %% up toward %s" % [up.length() * 100.0, up.normalized()])
	up = up.normalized()
	var across := Vector2(-up.y, up.x)
	_stand(at - across * 1.3, _yaw_of(across), 0, top)
	_stand(at, _yaw_of(up), 1, top)
	_stand(at + across * 1.3 + up * 0.4, _yaw_of(-up), 2, top)
	# The camera stands off to the side, across the contour from the middle person.
	var dist := float(_env("FEET_EYE_DIST", "5.0"))
	var eye_xz := at + up.orthogonal() * dist
	var gy := _ground(eye_xz.x, eye_xz.y, top + 20.0)
	var my := _ground(at.x, at.y, top)
	return _eye_at(Vector3(eye_xz.x, maxf(gy, my) + 1.3, eye_xz.y), Vector3(at.x, my + 0.7, at.y))
