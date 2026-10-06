class_name CornerStoreSite
extends Node3D
## A built corner store in a FULL chunk (CornerStoreKit makes it): keeps the interior hidden and
## the glass on the traced room while the player and the camera are away, shows the real interior
## behind clear glass as either comes within `reach` of the storefront (and hides it again past
## `reach + hysteresis`), and swings the door open while the player is within `door_reach` of it.
## Positions are compared in the store's own frame (to_local), so origin shifts change nothing.

## How near the storefront (m, in front of it or anywhere inside) shows the real interior.
@export var reach: float = 5.0
@export var hysteresis: float = 1.5
## How near the door (m) the player opens it, and how fast it swings (fraction a second).
@export var door_reach: float = 2.4
@export var door_speed: float = 2.2
## How far the door swings in (degrees).
@export var door_swing: float = 96.0
## Seconds between visibility checks.
@export var check_interval: float = 0.1

var store: Dictionary = {}
var lay: Dictionary = {}
var interior: Node3D
var door: Node3D
var people: Array = []
var interior_ready: bool = false
## Whether the real interior is shown (the checks read it).
var shown: bool = false
## 0 shut .. 1 open, and where it is heading.
var door_open: float = 0.0
var door_target: float = 0.0
## Force the interior shown or hidden (-1 decides by distance); stills and checks.
var force_show: int = -1
var _glass: Array = [] # [GeometryInstance3D, traced, clear]
var _wait: float = 0.0
var _player: Node3D


func add_glass(mi: GeometryInstance3D, traced: Material, clear: Material) -> void:
	_glass.append([mi, traced, clear])
	mi.material_override = traced


func _ready() -> void:
	set_process(true)
	set_physics_process(true)
	if OS.get_environment("STORE_SHOW") == "1":
		force_show = 1


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = check_interval
	var probes: Array = []
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		probes.append(cam.global_position)
	var p := _the_player()
	if p:
		probes.append(p.global_position)
	evaluate(probes, p.global_position if p else null)


## Decides from world points (the camera, the player) whether the interior is shown, and from the
## player's position (or null) whether the door opens. The checks call it with points of their own.
func evaluate(probes: Array, player_at: Variant) -> void:
	var want := false
	var open := false
	if force_show >= 0:
		want = force_show == 1
	else:
		var r := reach + (hysteresis if shown else 0.0)
		for q: Vector3 in probes:
			if near_store(to_local(q), r):
				want = true
	if player_at is Vector3:
		var lp := to_local(player_at as Vector3)
		var dx: float = lp.x - float(lay.get("door_x", 0.0))
		open = Vector2(dx, lp.z).length() < door_reach and lp.y > -1.5 and lp.y < 3.0
	if want != shown:
		set_shown(want)
	door_target = 1.0 if open and shown else 0.0


## Whether a point in the store's frame is inside the store or within `r` of its storefront.
func near_store(lp: Vector3, r: float) -> bool:
	var W: float = store.get("W", 10.0)
	var D: float = store.get("D", 10.0)
	if lp.y < -2.0 or lp.y > CornerStore.PARAPET + 1.0:
		return false
	return lp.x > -W * 0.5 - 1.0 and lp.x < W * 0.5 + 1.0 and lp.z > -D and lp.z < r


func set_shown(on: bool) -> void:
	shown = on
	if interior:
		interior.visible = on
	for g: Array in _glass:
		var mi: GeometryInstance3D = g[0]
		if is_instance_valid(mi):
			mi.material_override = g[2] if on else g[1]


func _physics_process(delta: float) -> void:
	if door == null:
		return
	if is_equal_approx(door_open, door_target):
		return
	door_open = move_toward(door_open, door_target, delta * door_speed)
	var e := door_open * door_open * (3.0 - 2.0 * door_open)
	door.rotation.y = float(lay.get("cs", 1.0)) * deg_to_rad(door_swing) * e


func _the_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
	return _player


func _exit_tree() -> void:
	for p: Variant in people:
		if is_instance_valid(p) and not (p as Node).is_queued_for_deletion():
			(p as Node).queue_free()
	people.clear()
