class_name HeliSpot
extends Node3D
## Where a flyable helicopter waits (FlyableHeli): a rooftop pad's parked helicopter, the hospital's
## air ambulance, the police HQ's, the airport heliport's. Its transform is the helicopter's (the
## skids' bottom at the origin, the nose down -Z).
##
## A rooftop pad already draws its parked helicopter as one merged mesh (Rooftops), the
## `stand_in`: a real body is only made when the player comes within `wake_distance`, the stand-in
## hidden while it exists, and put back (the body freed) once the player is `sleep_distance` away
## and nobody has flown it. `eager` spots (the few landmark pads, which have no stand-in) make
## theirs as soon as they enter the tree. The body lives under the city root, like a parked car,
## so one flown away survives its pad's chunk; a spot whose helicopter is gone (flown off and
## left, or a wreck cleared) makes a new one.

## Metres from the player where a parked helicopter becomes a real one, and where it goes back.
const WAKE_DISTANCE := 75.0
const SLEEP_DISTANCE := 160.0
const CHECK_SECONDS := 0.4

## FlyableHeli.Livery (as an int: the classes refer to each other).
var livery: int = 0
var colors: Array = []
var stand_in: Node3D = null
var eager: bool = false
var heli: FlyableHeli = null

var _left: float = 0.0

## Every spot's live helicopter by its TRUE world key: a pad rebuilt with its chunk finds the one
## it already made instead of making a second.
static var _live: Dictionary = {}


func _ready() -> void:
	add_to_group("heli_spot")
	_left = 0.0 if eager else randf() * CHECK_SECONDS
	if eager:
		_tick.call_deferred()


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = CHECK_SECONDS
	_tick()


func key() -> Vector3i:
	var w := WorldState.to_world(global_position)
	return Vector3i(roundi(w.x), roundi(w.y), roundi(w.z))


func _tick() -> void:
	if not is_inside_tree():
		return
	var k := key()
	if heli == null or not is_instance_valid(heli):
		heli = _live.get(k) as FlyableHeli if is_instance_valid(_live.get(k)) else null
	if heli != null and (heli.is_wreck() or not heli.is_inside_tree()):
		heli = null
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var d := INF if player == null else player.global_position.distance_to(global_position)
	if heli == null:
		_live.erase(k)
		if eager or d < WAKE_DISTANCE:
			heli = make()
	elif not eager and _at_home() and d > SLEEP_DISTANCE:
		_free_heli()
	if stand_in and is_instance_valid(stand_in):
		stand_in.visible = heli == null


## True while the helicopter has never been flown and sits where it was put.
func _at_home() -> bool:
	return heli != null and heli.driver == null and not heli.has_meta("driven") \
			and heli.global_position.distance_to(global_position) < 1.5


func _free_heli() -> void:
	_live.erase(key())
	if heli and is_instance_valid(heli):
		heli.queue_free()
	heli = null


## Makes the real helicopter now (tests call it directly).
func make() -> FlyableHeli:
	if not HeliPads.enabled or not is_inside_tree():
		return null
	var root := get_tree().get_first_node_in_group("city") as Node3D
	if root == null:
		root = get_tree().current_scene as Node3D
	if root == null:
		return null
	var h := FlyableHeli.new()
	h.name = "FlyableHeli"
	h.setup_heli(livery, colors)
	h.home_world = WorldState.to_world(global_position)
	# Placed before it enters the tree, in its parent's frame, frozen on the pad until somebody
	# gets in (Player.enter_vehicle unfreezes it): nothing to simulate while it waits.
	h.transform = root.global_transform.affine_inverse() * Transform3D(global_basis.orthonormalized(), global_position + Vector3.UP * 0.02)
	h.freeze = true
	root.add_child(h)
	h.hold_crash_watch(6)
	_live[key()] = h
	if stand_in and is_instance_valid(stand_in):
		stand_in.visible = false
	return h


func _exit_tree() -> void:
	# The pad's chunk went: a helicopter nobody has touched goes with it.
	if heli != null and is_instance_valid(heli) and _at_home():
		_free_heli()
