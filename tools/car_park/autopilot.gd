extends RefCounted
## Drives a car up a car park with the player's own controls (Input actions, so the car is
## driven exactly as the owner drives it): pure pursuit along CarPark.drive_path(), slowing for
## the turns. Used by tests/garage_drive_in_checks.gd and tools/car_park/drive_shot.gd.
##   var ap = load("res://tools/car_park/autopilot.gd").new()
##   ap.setup(local_points)            # chunk-local (scene) positions
##   each physics tick: ap.step(car)   # true once it has arrived
##   ap.release()                      # lets go of the controls

var path: PackedVector3Array
var i: int = 1
## Cruise speed (m/s) and how hard it slows for a turn.
var speed: float = 5.5
var arrive: float = 2.6
var done: bool = false
## Furthest point reached (an index into path).
var reached: int = 0


func setup(points: PackedVector3Array) -> void:
	path = points
	i = 1
	done = false
	reached = 0


func step(car: Node3D) -> bool:
	if done or path.size() < 2:
		release()
		return true
	var pos := car.global_position
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	while i < path.size() - 1:
		var d := Vector3(path[i].x - pos.x, 0.0, path[i].z - pos.z)
		# Reached, or passed close by (behind the car now).
		if d.length() < arrive or (d.length() < 6.0 and d.dot(fwd) < 0.0):
			i += 1
			reached = maxi(reached, i - 1)
		else:
			break
	var tgt := path[i]
	var to := Vector3(tgt.x - pos.x, 0.0, tgt.z - pos.z)
	if i == path.size() - 1 and to.length() < arrive:
		done = true
		reached = path.size() - 1
		release()
		return true
	# Aim between this point and the next one when close, so a corner is cut like a driver would.
	if i < path.size() - 1 and to.length() < 5.0:
		var nx := path[i + 1]
		var blend := 1.0 - to.length() / 5.0
		to = to.lerp(Vector3(nx.x - pos.x, 0.0, nx.z - pos.z), blend * 0.5)
	var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
	var steer := clampf(-ang * 2.4, -1.0, 1.0)
	var vel: float = (car as RigidBody3D).linear_velocity.dot(-car.global_basis.z) if car is RigidBody3D else 0.0
	var want := speed * (1.0 - 0.6 * clampf(absf(ang) / 1.0, 0.0, 1.0))
	# Reversing out of a corner it cannot make: back up straight.
	var thr := clampf((want - vel) * 0.7, -1.0, 1.0)
	if absf(ang) > 2.0:
		thr = 0.5
	_press("move_forward", maxf(thr, 0.0))
	_press("move_back", maxf(-thr, 0.0))
	_press("move_right", maxf(steer, 0.0))
	_press("move_left", maxf(-steer, 0.0))
	return false


func _press(action: String, amount: float) -> void:
	if amount > 0.02:
		Input.action_press(action, amount)
	else:
		Input.action_release(action)


func release() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)


## CarPark.drive_path() (true world, heights over the ground deck) as chunk-local points.
static func local_path(plan: CityPlan, s: Dictionary, ws: Node, to_deck: int = -1) -> PackedVector3Array:
	var gy := CarPark.ground_y(plan, s)
	var out := PackedVector3Array()
	for p: Vector3 in CarPark.drive_path(plan, s, to_deck):
		out.append(ws.call("to_local", Vector3(p.x, gy + p.y, p.z)))
	return out


## What is in front of the car (for a stuck report): rays ahead at three heights.
static func blocker(car: Node3D) -> String:
	var space := car.get_world_3d().direct_space_state
	var fwd := -car.global_basis.z
	var out := []
	for h: float in [0.25, 0.6, 1.2]:
		var from := car.global_position + Vector3.UP * h
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 4.0, 1 | 4 | 8)
		q.exclude = [(car as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			out.append("h%.2f: clear" % h)
		else:
			var c: Node = hit.collider
			out.append("h%.2f: %s at %.2f m (%s)" % [h, c.get_path() if c.is_inside_tree() else c.name, from.distance_to(hit.position), hit.normal])
	var down := PhysicsRayQueryParameters3D.create(car.global_position + Vector3.UP * 1.0, car.global_position - Vector3.UP * 2.0, 1)
	down.exclude = [(car as CollisionObject3D).get_rid()]
	var d := space.intersect_ray(down)
	out.append("under: %s" % (str((d.collider as Node).name) + " y %.2f" % (d.position as Vector3).y if not d.is_empty() else "nothing"))
	return "; ".join(out)
