extends Node
## Autoload: global physics guardrails.
## - Caps the number of active physics props (spawners ask can_spawn()).
## - Frees debris after a timeout.
## - Freezes props far from the player so only nearby physics is simulated.
## Props opt in by joining the "physics_prop" group; debris also joins "debris".

const PROP_GROUP := "physics_prop"
const DEBRIS_GROUP := "debris"
const PLAYER_GROUP := "player"

@export_group("Budget")
## Hard cap on props in the "physics_prop" group.
@export var max_active_bodies: int = 500
## Debris older than this (seconds) is freed.
@export var debris_lifetime: float = 12.0

@export_group("Distance Sleeping")
## Props farther than this from the player are frozen (meters).
@export var simulate_radius: float = 90.0
## Frozen props wake up again inside simulate_radius * this factor (hysteresis).
@export var wake_radius_factor: float = 0.85
## How often the guardrails run (seconds).
@export var check_interval: float = 0.25
## Past this distance from the player (metres) a car nobody is driving stops running its own
## per-step script (Vehicle.set_script_active). Its physics body is untouched - VehicleBody3D's
## suspension runs in the physics server, not in the script - so a parked car still sits, rolls
## and gets blown up exactly as before. What stops is wheel spin and LOD bookkeeping that nobody
## can see at this range. Measured headless on a downtown block, the 451 cars' scripts were 12 of
## 67 ms of every physics step.
@export var vehicle_script_radius: float = 100.0

var frozen_count: int = 0
var _timer: float = 0.0


## A physics tick, not a frame: Vehicle.settle() only sticks when it runs between the physics
## callbacks and the next step (see there).
func _physics_process(delta: float) -> void:
	_timer += delta
	if _timer < check_interval:
		return
	_timer = 0.0
	_run_checks()


func active_body_count() -> int:
	return get_tree().get_nodes_in_group(PROP_GROUP).size()


func can_spawn() -> bool:
	return active_body_count() < max_active_bodies


## Mark a body (or a ragdoll root) as short-lived debris and start its lifetime clock.
func register_debris(body: Node3D) -> void:
	body.add_to_group(PROP_GROUP)
	body.add_to_group(DEBRIS_GROUP)
	body.set_meta("spawn_time", _now())


## Frees the oldest debris until there is room for `count` more bodies.
## Returns true if there is room afterwards.
func make_room(count: int = 1) -> bool:
	var over := active_body_count() + count - max_active_bodies
	if over <= 0:
		return true
	var debris := get_tree().get_nodes_in_group(DEBRIS_GROUP)
	debris.sort_custom(func(a, b): return a.get_meta("spawn_time", 0.0) < b.get_meta("spawn_time", 0.0))
	for i in mini(over, debris.size()):
		debris[i].queue_free()
		debris[i].remove_from_group(PROP_GROUP)
		debris[i].remove_from_group(DEBRIS_GROUP)
	return active_body_count() + count <= max_active_bodies


func _run_checks() -> void:
	var now := _now()
	var player := get_tree().get_first_node_in_group(PLAYER_GROUP) as Node3D
	var wake_radius := simulate_radius * wake_radius_factor
	frozen_count = 0
	for node in get_tree().get_nodes_in_group(PROP_GROUP):
		if node.is_queued_for_deletion():
			continue
		if node.is_in_group(DEBRIS_GROUP):
			var born: float = node.get_meta("spawn_time", now)
			if now - born > debris_lifetime:
				node.queue_free()
				continue
		var body := node as RigidBody3D
		if body == null or player == null:
			continue
		if body is VehicleBody3D:
			# Never freeze vehicles: frozen wheels divide by zero and poison the body with NaN.
			if player and body.has_method("set_script_active"):
				var near := body.global_position.distance_to(player.global_position) < vehicle_script_radius
				body.set_script_active(near or body.get("driver") != null)
			if body.has_method("settle"):
				body.settle()
			continue
		var dist := body.global_position.distance_to(player.global_position)
		if body.freeze:
			if dist < wake_radius:
				body.freeze = false
			else:
				frozen_count += 1
		elif dist > simulate_radius:
			body.freeze = true
			frozen_count += 1


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
