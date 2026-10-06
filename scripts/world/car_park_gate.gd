class_name CarParkGate
extends Node3D
## A car park's barrier arm (CarParkBuild): it lifts when the player, on foot or at the wheel,
## comes within `reach` of it, and comes down again `hold` seconds after they have gone. The arm
## has no collision: a barrier you have to stop for is no fun when you are overpowered, and one
## that a car can hook would launch it. Checked a few times a second, off the physics clock.

## How near (m) the player must come for the arm to lift.
@export var reach: float = 7.5
## Seconds it stays up after the player has gone.
@export var hold: float = 2.5
## Seconds to lift or drop.
@export var swing_time: float = 1.4
## How far it lifts (degrees).
@export var open_degrees: float = 84.0

var arm: Node3D
## +1: the arm lies along +x from its pivot; -1 along -x (it lifts the same way either way).
var side: float = 1.0
var _angle: float = 0.0
var _clear_for: float = 99.0
var _tick: int = 0
var _want_open: bool = false
## Forced open (tests and stills).
var force_open: bool = false


func _ready() -> void:
	_tick = absi(hash(get_instance_id())) % 6


func _physics_process(delta: float) -> void:
	_tick += 1
	if _tick % 6 == 0:
		_want_open = force_open or _player_near()
	if _want_open:
		_clear_for = 0.0
	else:
		_clear_for += delta
	var target := deg_to_rad(open_degrees) if _clear_for < hold else 0.0
	var step := deg_to_rad(open_degrees) / maxf(swing_time, 0.05) * delta
	_angle = move_toward(_angle, target, step)
	if arm:
		arm.rotation = Vector3(0.0, 0.0, _angle * side)


func _player_near() -> bool:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return false
	var at := p.global_position
	var v = p.get("vehicle")
	if v is Node3D and is_instance_valid(v):
		at = (v as Node3D).global_position
	return at.distance_to(global_position) < reach


## 0 shut .. 1 open.
func openness() -> float:
	return _angle / deg_to_rad(open_degrees)
