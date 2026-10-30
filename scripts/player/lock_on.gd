class_name LockOn
extends Node
## GTA-style aim (owner, 2026-09-24: "GTA style aiming that auto locks onto targets"). Hold aim
## (`alt_fire`: right mouse / left trigger) with a gun that allows it and the camera pulls in
## over the shoulder and locks onto the person, or failing that the car in traffic, nearest the
## crosshair. The camera swings onto the target and holds it there, shots go straight at it
## (`Player.get_aim()` aims at the lock, not at the screen centre), and a flick of the mouse or
## the right stick jumps the lock to the next target that way. When the target goes down the
## lock picks up the next one after `reacquire_delay`. Let go of aim to free the camera.

@export_group("Lock on")
## Widest angle off the crosshair a target can be picked up at (degrees).
@export var acquire_cone_deg: float = 24.0
## Furthest a target can be locked (metres).
@export var acquire_range: float = 110.0
## A locked target is dropped past this multiple of the range, or after this long out of sight.
@export var keep_range_scale: float = 1.35
@export var lost_sight_grace: float = 0.6
## How fast the camera swings onto the target (per second, exponential).
@export var track_speed: float = 14.0
## Mouse travel (pixels) or stick deflection that jumps the lock to the next target that way.
@export var switch_flick_px: float = 80.0
@export var switch_stick: float = 0.75
## How far off the crosshair the next target may be when flicking to it (degrees).
@export var switch_cone_deg: float = 55.0
## Where on a person / a car the lock sits (metres above its origin).
@export var person_aim_height: float = 1.2
@export var car_aim_height: float = 0.8
## Degrees of penalty a car pays against a person when both are near the crosshair.
@export var car_penalty_deg: float = 8.0
## Seconds after a target goes down before the lock looks for the next one.
@export var reacquire_delay: float = 0.25

@export_group("Aim camera")
## Camera distance and how much the field of view narrows while aiming.
@export var aim_distance: float = 3.8
@export var aim_fov_drop: float = 14.0

## The locked node (a Pedestrian or a Vehicle), or null.
var target: Node3D = null
## True while the aim button is held with a gun that can lock.
var aiming: bool = false

var _player: Player
var _lost: float = 0.0
var _reacquire: float = 0.0
var _sight_timer: float = 0.0
var _stick_armed: bool = true


func _ready() -> void:
	_player = get_parent() as Player


func _process(delta: float) -> void:
	if _player == null:
		return
	var rig := _player.camera_rig
	var weapon: Node = _player.weapon_manager.current if _player.weapon_manager else null
	var can_lock := weapon != null and bool(weapon.get("lock_on")) and _player.vehicle == null
	aiming = can_lock and Input.is_action_pressed("alt_fire")
	rig.set_aiming(aiming, aim_distance, aim_fov_drop)
	if not aiming:
		target = null
		rig.lock_active = false
		return
	# The body turns to face where the gun points, as it does for a shot.
	_player.notify_aiming()
	if target != null and not _alive(target):
		target = null
		_reacquire = reacquire_delay
	if target == null:
		rig.lock_active = false
		_reacquire -= delta
		if _reacquire <= 0.0:
			target = _pick(null, 0.0)
			_lost = 0.0
			_sight_timer = 0.0
		return
	# Still worth holding? Out of range, or out of sight for longer than the grace, lets go.
	var from: Vector3 = rig.aim_origin()
	var point := aim_point()
	if from.distance_to(point) > acquire_range * keep_range_scale:
		target = null
		rig.lock_active = false
		return
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = 0.1
		_lost = 0.0 if _visible(target, point) else _lost + 0.1
		if _lost > lost_sight_grace:
			target = null
			rig.lock_active = false
			return
	# A flick of the mouse or the stick jumps to the next target that way.
	var nudge: Vector2 = rig.take_lock_nudge()
	var stick := Input.get_axis("look_left", "look_right")
	var side := 0.0
	if absf(nudge.x) > switch_flick_px:
		side = signf(nudge.x)
	elif absf(stick) > switch_stick and _stick_armed:
		side = signf(stick)
		_stick_armed = false
	if absf(stick) < switch_stick * 0.5:
		_stick_armed = true
	if side != 0.0:
		var next := _pick(target, side)
		rig.clear_lock_nudge()
		if next != null:
			target = next
			point = aim_point()
	rig.lock_active = true
	rig.track(point, track_speed, delta)


## Where shots should go: the target's chest, led by its velocity for a projectile of
## `lead_speed` m/s (0 = hitscan, no lead).
func aim_point(lead_speed: float = 0.0) -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	var p := _chest(target)
	if lead_speed > 0.0:
		var vel := Vector3.ZERO
		if target is CharacterBody3D:
			vel = (target as CharacterBody3D).velocity
		elif target is RigidBody3D:
			vel = (target as RigidBody3D).linear_velocity
		var t: float = _player.camera_rig.aim_origin().distance_to(p) / lead_speed
		p += vel * t
	return p


func _chest(node: Node3D) -> Vector3:
	return node.global_position + Vector3.UP * (car_aim_height if node is Vehicle else person_aim_height)


func _alive(node: Node3D) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion() or not node.is_inside_tree():
		return false
	if node is Pedestrian:
		return not bool(node.get("_down"))
	if node is Vehicle:
		return not (node as Vehicle).traffic.is_empty() or (node as Vehicle).driver != null
	return true


## The best target near the crosshair; with `side` set (-1 left, +1 right), the nearest one on
## that side of `current` on screen instead.
func _pick(current: Node3D, side: float) -> Node3D:
	var rig := _player.camera_rig
	var cam := _player.camera
	var from: Vector3 = rig.aim_origin()
	var forward := -cam.global_basis.z
	var right := cam.global_basis.x
	var cone := deg_to_rad(switch_cone_deg if side != 0.0 else acquire_cone_deg)
	var current_x := 0.0
	if current != null:
		current_x = (_chest(current) - from).normalized().dot(right)
	var scored: Array = []
	for group in ["pedestrian", "police", "vehicle"]:
		for n in get_tree().get_nodes_in_group(group):
			var node := n as Node3D
			if node == null or node == current or node == _player.vehicle or not _alive(node):
				continue
			var p := _chest(node)
			var to: Vector3 = p - from
			var dist: float = to.length()
			if dist < 1.0 or dist > acquire_range:
				continue
			var dir: Vector3 = to / dist
			var angle := acos(clampf(dir.dot(forward), -1.0, 1.0))
			if angle > cone:
				continue
			var score: float = rad_to_deg(angle) + dist * 0.04 + (car_penalty_deg if node is Vehicle else 0.0)
			if side != 0.0:
				var dx: float = dir.dot(right) - current_x
				if dx * side <= 0.01:
					continue
				score = absf(dx) * 60.0 + dist * 0.02
			scored.append([score, node, p])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	# Sight is a ray each, so only the best few are asked.
	for i in mini(scored.size(), 5):
		if _visible(scored[i][1], scored[i][2]):
			return scored[i][1]
	return null


func _visible(node: Node3D, point: Vector3) -> bool:
	var from: Vector3 = _player.camera_rig.aim_origin()
	var query := PhysicsRayQueryParameters3D.create(from, point, Player.AIM_MASK, [_player.get_rid()])
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var c: Node = hit.collider
	while c != null:
		if c == node:
			return true
		c = c.get_parent()
	return false
